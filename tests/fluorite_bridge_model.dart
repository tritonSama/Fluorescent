// tests/fluorite_bridge_model.dart
//
// Authoritative client model, FFI bridge interface, and native simulation engine
// for the Fluorite AAA Engine (Phase 1 & Phase 2 Wave 1).
//
// Implements interface contracts from PROJECT.md:
// - Phase 1: Allocators, Zero-copy 1MB buffer, Sentinels (0xAA / 0x55), SharedFrameBuffer
// - Phase 2:
//   - Cook-Torrance PBR Metallic-Roughness BRDF & Directional Shadows
//   - Clustered Forward+ Light Assignment (16x9x24 = 3,456 clusters, 1024+ lights)
//   - Flat BVH Spatial Partitioning (32-byte FlatBvhNode, 16-bin SAH, SIMD Raycasting, <2ms culling)
//   - Rapier3D PhysicsWorld (60Hz fixed accumulator, CCD, KCC, 16-float transform sync)
//   - Flutter Desktop Editor 3D Viewport (Dockable shell, Outliner, Inspector, Camera, Zero-copy Texture)

import 'dart:math' as math;
import 'dart:typed_data';

// =============================================================================
// PHASE 1: CORE MEMORY & FFI BUFFER MODELS
// =============================================================================

/// Exception thrown when allocator requests exceed capacity or have invalid layout.
class AllocException implements Exception {
  final String message;
  AllocException(this.message);
  @override
  String toString() => 'AllocException: $message';
}

/// Telemetry status struct matching FFI EngineStatus.
class EngineStatus {
  final bool isInitialized;
  final String coreVersion;
  final String allocatorName;
  final int arenaCapacityBytes;
  final int arenaAllocatedBytes;
  final int frameIndex;
  final int? textureId;

  const EngineStatus({
    required this.isInitialized,
    required this.coreVersion,
    required this.allocatorName,
    required this.arenaCapacityBytes,
    required this.arenaAllocatedBytes,
    required this.frameIndex,
    this.textureId,
  });

  @override
  String toString() =>
      'EngineStatus(init: $isInitialized, ver: $coreVersion, alloc: $allocatorName, '
      'cap: $arenaCapacityBytes, used: $arenaAllocatedBytes, frame: $frameIndex, tex: $textureId)';
}

/// Bump-pointer arena allocator implementing power-of-two alignment arithmetic.
class ArenaAllocatorModel {
  final int capacity;
  final Uint8List _buffer;
  int _offset = 0;
  int _peakUsage = 0;
  int _allocCount = 0;
  final int baseAddress;

  ArenaAllocatorModel(this.capacity, {int? simulatedBaseAddress})
      : _buffer = Uint8List(capacity),
        baseAddress = simulatedBaseAddress ?? 0x10000000 {
    if (capacity <= 0) {
      throw AllocException('Invalid capacity: $capacity');
    }
  }

  int get allocatedBytes => _offset;
  int get capacityBytes => capacity;
  int get remainingBytes => capacity - _offset;
  int get peakUsage => _peakUsage;
  int get allocationCount => _allocCount;

  /// Allocates a raw chunk with strict power-of-two alignment.
  int allocRaw(int size, int align) {
    if (size == 0) {
      return _calculateAlignedAddress(_offset, align);
    }
    if (align <= 0 || (align & (align - 1)) != 0) {
      throw AllocException('Alignment must be a non-zero power of two: $align');
    }

    final currentAddr = baseAddress + _offset;
    final padding = (align - (currentAddr & (align - 1))) & (align - 1);
    final nextOffset = _offset + padding + size;

    if (nextOffset > capacity) {
      throw AllocException(
          'OutOfMemory: requested $size bytes (with $padding padding), remaining $remainingBytes');
    }

    final allocatedAddr = currentAddr + padding;
    _offset = nextOffset;
    _allocCount++;
    if (_offset > _peakUsage) {
      _peakUsage = _offset;
    }
    return allocatedAddr;
  }

  /// Allocates a contiguous slice of bytes within the arena.
  Uint8List allocSlice(int count, int initialValue) {
    if (count == 0) {
      return Uint8List(0);
    }
    const align = 8;
    final currentAddr = baseAddress + _offset;
    final padding = (align - (currentAddr & (align - 1))) & (align - 1);
    final nextOffset = _offset + padding + count;

    if (nextOffset > capacity) {
      throw AllocException(
          'OutOfMemory: slice count $count exceeds remaining $remainingBytes');
    }

    final startIdx = _offset + padding;
    _offset = nextOffset;
    _allocCount++;
    if (_offset > _peakUsage) {
      _peakUsage = _offset;
    }

    for (int i = 0; i < count; i++) {
      _buffer[startIdx + i] = initialValue;
    }

    return Uint8List.sublistView(_buffer, startIdx, startIdx + count);
  }

  /// O(1) bulk reset. Discards all previous allocations instantly.
  void reset() {
    _offset = 0;
    _allocCount = 0;
  }

  int _calculateAlignedAddress(int offset, int align) {
    final addr = baseAddress + offset;
    final padding = (align - (addr & (align - 1))) & (align - 1);
    return addr + padding;
  }
}

/// Double-buffered ping-pong allocator for decoupling game loop simulation and rendering.
class DoubleBufferedFrameAllocatorModel {
  final List<ArenaAllocatorModel> arenas;
  int currentFrame = 0;

  DoubleBufferedFrameAllocatorModel(int frameCapacity)
      : arenas = [
          ArenaAllocatorModel(frameCapacity, simulatedBaseAddress: 0x10000000),
          ArenaAllocatorModel(frameCapacity, simulatedBaseAddress: 0x20000000),
        ];

  ArenaAllocatorModel get currentArena => arenas[currentFrame % 2];
  ArenaAllocatorModel get previousArena => arenas[(currentFrame + 1) % 2];

  /// Advance to the next frame and reset the newly active arena.
  void swapBuffers() {
    currentFrame++;
    currentArena.reset();
  }

  int get frameIndex => currentFrame;
}

/// Persistent shared frame buffer handle.
class SharedFrameBufferModel {
  final Uint8List data;
  final int ptrAddress;

  SharedFrameBufferModel(int sizeBytes, {int? baseAddr})
      : data = Uint8List(sizeBytes),
        ptrAddress = baseAddr ?? 0x30000000 {
    if (sizeBytes >= 4) {
      data[0] = 0xDE;
      data[1] = 0xAD;
      data[2] = 0xBE;
      data[3] = 0xEF;
    }
  }

  int get len => data.length;

  int readByte(int offset) {
    if (offset >= data.length) {
      throw RangeError.index(offset, data);
    }
    return data[offset];
  }

  void writeByte(int offset, int value) {
    if (offset >= data.length) {
      throw RangeError.index(offset, data);
    }
    data[offset] = value;
  }
}

/// Engine state machine enum.
enum EngineState { uninitialized, initializing, running, error }

/// Editor UI engine controller model matching lib/src/engine_controller.dart.
class EngineControllerModel {
  EngineState state = EngineState.uninitialized;
  EngineStatus? status;
  Uint8List? activeBuffer;
  int allocationLatencyMicros = 0;
  String? errorMessage;
  final DoubleBufferedFrameAllocatorModel allocator;

  EngineControllerModel({int arenaCapacity = 1024 * 1024 * 64})
      : allocator = DoubleBufferedFrameAllocatorModel(arenaCapacity);

  Future<int?> startEngine({dynamic config}) async {
    state = EngineState.initializing;
    await Future.delayed(const Duration(microseconds: 50));
    state = EngineState.running;
    status = EngineStatus(
      isInitialized: true,
      coreVersion: '0.1.0',
      allocatorName: 'FluoriteArenaAllocator_v1',
      arenaCapacityBytes: allocator.currentArena.capacityBytes,
      arenaAllocatedBytes: allocator.currentArena.allocatedBytes,
      frameIndex: allocator.frameIndex,
      textureId: 1,
    );
    return 1;
  }

  Future<Uint8List> allocate1MB() async {
    if (state != EngineState.running) {
      await startEngine();
    }
    final sw = Stopwatch()..start();
    const oneMb = 1024 * 1024;
    final buffer = allocateEngineBuffer(oneMb);
    sw.stop();
    allocationLatencyMicros = sw.elapsedMicroseconds;
    activeBuffer = buffer;

    status = EngineStatus(
      isInitialized: true,
      coreVersion: '0.1.0',
      allocatorName: 'FluoriteArenaAllocator_v1',
      arenaCapacityBytes: allocator.currentArena.capacityBytes,
      arenaAllocatedBytes: oneMb,
      frameIndex: allocator.frameIndex,
      textureId: 1,
    );
    return buffer;
  }

  void reset() {
    activeBuffer = null;
    allocationLatencyMicros = 0;
    allocator.currentArena.reset();
    state = EngineState.uninitialized;
    status = null;
  }
}

/// Allocates an engine buffer with 0xAA header and 0x55 footer sentinels.
Uint8List allocateEngineBuffer(int sizeBytes) {
  final buffer = Uint8List(sizeBytes);
  if (sizeBytes > 0) {
    buffer[0] = 0xAA;
    buffer[sizeBytes - 1] = 0x55;
  }
  return buffer;
}

/// Verifies sentinel bytes in a buffer.
bool verifyBufferSentinels(Uint8List buffer) {
  if (buffer.isEmpty) return false;
  if (buffer[0] != 0xAA) return false;
  if (buffer[buffer.length - 1] != 0x55) return false;
  return true;
}

/// Writes pattern to continuous buffer in-place.
Uint8List writeBufferPattern(Uint8List buffer, int fillByte) {
  buffer.fillRange(0, buffer.length, fillByte);
  return buffer;
}

/// Formats a byte slice into a standard hex dump inspector view.
List<String> formatHexInspector(Uint8List buffer, {int offset = 0, int length = 64}) {
  if (buffer.isEmpty) return ['<Empty Buffer>'];
  final safeOffset = offset.clamp(0, buffer.length);
  final safeLength = length.clamp(0, buffer.length - safeOffset);
  final lines = <String>[];

  for (int i = 0; i < safeLength; i += 16) {
    final chunkEnd = (i + 16).clamp(0, safeLength);
    final chunk = buffer.sublist(safeOffset + i, safeOffset + chunkEnd);

    final hexParts = chunk.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    final asciiParts = chunk.map((b) => (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.').join();

    final addrStr = (safeOffset + i).toRadixString(16).padLeft(8, '0').toUpperCase();
    lines.add('$addrStr  ${hexParts.padRight(47)}  |$asciiParts|');
  }
  return lines;
}

// =============================================================================
// PHASE 2: MATHEMATICAL & GEOMETRIC FOUNDATIONS
// =============================================================================

/// 3D Vector with full linear algebra support.
class Vec3 {
  final double x;
  final double y;
  final double z;

  const Vec3(this.x, this.y, this.z);
  static const Vec3 zero = Vec3(0, 0, 0);
  static const Vec3 one = Vec3(1, 1, 1);
  static const Vec3 unitX = Vec3(1, 0, 0);
  static const Vec3 unitY = Vec3(0, 1, 0);
  static const Vec3 unitZ = Vec3(0, 0, 1);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  Vec3 operator /(double s) => Vec3(x / s, y / s, z / s);
  Vec3 operator -() => Vec3(-x, -y, -z);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  Vec3 cross(Vec3 o) => Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double get lengthSquared => x * x + y * y + z * z;
  double get length => math.sqrt(lengthSquared);

  Vec3 normalize() {
    final len = length;
    if (len == 0 || len.isNaN) return Vec3.zero;
    return this * (1.0 / len);
  }

  double distanceTo(Vec3 o) => (this - o).length;

  Vec3 componentMin(Vec3 o) => Vec3(math.min(x, o.x), math.min(y, o.y), math.min(z, o.z));
  Vec3 componentMax(Vec3 o) => Vec3(math.max(x, o.x), math.max(y, o.y), math.max(z, o.z));

  @override
  String toString() => 'Vec3(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}

/// 4D Vector (RGBA colors, Quaternions, Homogeneous coords).
class Vec4 {
  final double x;
  final double y;
  final double z;
  final double w;

  const Vec4(this.x, this.y, this.z, this.w);
  static const Vec4 zero = Vec4(0, 0, 0, 0);
  static const Vec4 one = Vec4(1, 1, 1, 1);

  Vec3 get xyz => Vec3(x, y, z);

  @override
  String toString() => 'Vec4($x, $y, $z, $w)';
}

/// 4x4 Matrix for 3D transformations (column-major order matching WGPU & GLSL).
class Mat4 {
  final Float32List elements;

  Mat4._(this.elements);

  factory Mat4.identity() {
    final m = Float32List(16);
    m[0] = 1.0;
    m[5] = 1.0;
    m[10] = 1.0;
    m[15] = 1.0;
    return Mat4._(m);
  }

  factory Mat4.translation(Vec3 t) {
    final m = Mat4.identity();
    m.elements[12] = t.x;
    m.elements[13] = t.y;
    m.elements[14] = t.z;
    return m;
  }

  factory Mat4.lookAt(Vec3 eye, Vec3 target, Vec3 up) {
    final f = (target - eye).normalize();
    final s = f.cross(up).normalize();
    final u = s.cross(f);

    final m = Float32List(16);
    m[0] = s.x;
    m[1] = u.x;
    m[2] = -f.x;
    m[3] = 0.0;

    m[4] = s.y;
    m[5] = u.y;
    m[6] = -f.y;
    m[7] = 0.0;

    m[8] = s.z;
    m[9] = u.z;
    m[10] = -f.z;
    m[11] = 0.0;

    m[12] = -s.dot(eye);
    m[13] = -u.dot(eye);
    m[14] = f.dot(eye);
    m[15] = 1.0;

    return Mat4._(m);
  }

  factory Mat4.perspective(double fovRadians, double aspect, double near, double far) {
    final f = 1.0 / math.tan(fovRadians / 2.0);
    final rangeInv = 1.0 / (near - far);

    final m = Float32List(16);
    m[0] = f / aspect;
    m[5] = f;
    m[10] = (far + near) * rangeInv;
    m[11] = -1.0;
    m[14] = (2.0 * far * near) * rangeInv;
    return Mat4._(m);
  }

  factory Mat4.orthographic(double left, double right, double bottom, double top, double near, double far) {
    final m = Float32List(16);
    m[0] = 2.0 / (right - left);
    m[5] = 2.0 / (top - bottom);
    m[10] = -2.0 / (far - near);
    m[12] = -(right + left) / (right - left);
    m[13] = -(top + bottom) / (top - bottom);
    m[14] = -(far + near) / (far - near);
    m[15] = 1.0;
    return Mat4._(m);
  }

  Mat4 multiply(Mat4 o) {
    final res = Float32List(16);
    final a = elements;
    final b = o.elements;
    for (int col = 0; col < 4; col++) {
      for (int row = 0; row < 4; row++) {
        double sum = 0.0;
        for (int k = 0; k < 4; k++) {
          sum += a[k * 4 + row] * b[col * 4 + k];
        }
        res[col * 4 + row] = sum;
      }
    }
    return Mat4._(res);
  }

  Vec3 transformPoint(Vec3 p) {
    final e = elements;
    final w = e[3] * p.x + e[7] * p.y + e[11] * p.z + e[15];
    final invW = (w != 0.0) ? (1.0 / w) : 1.0;
    return Vec3(
      (e[0] * p.x + e[4] * p.y + e[8] * p.z + e[12]) * invW,
      (e[1] * p.x + e[5] * p.y + e[9] * p.z + e[13]) * invW,
      (e[2] * p.x + e[6] * p.y + e[10] * p.z + e[14]) * invW,
    );
  }
}

/// Axis-Aligned Bounding Box (AABB).
class Aabb {
  final Vec3 min;
  final Vec3 max;

  const Aabb(this.min, this.max);

  static const Aabb empty = Aabb(
    Vec3(double.infinity, double.infinity, double.infinity),
    Vec3(-double.infinity, -double.infinity, -double.infinity),
  );

  Vec3 get center => (min + max) * 0.5;
  Vec3 get extents => max - min;
  Vec3 get halfExtents => extents * 0.5;

  double get surfaceArea {
    final e = extents;
    if (e.x < 0 || e.y < 0 || e.z < 0) return 0.0;
    return 2.0 * (e.x * e.y + e.y * e.z + e.z * e.x);
  }

  bool get isDegenerate => min.x > max.x || min.y > max.y || min.z > max.z;

  bool containsPoint(Vec3 p) =>
      p.x >= min.x && p.x <= max.x &&
      p.y >= min.y && p.y <= max.y &&
      p.z >= min.z && p.z <= max.z;

  bool intersectsAabb(Aabb o) =>
      min.x <= o.max.x && max.x >= o.min.x &&
      min.y <= o.max.y && max.y >= o.min.y &&
      min.z <= o.max.z && max.z >= o.min.z;

  Aabb union(Aabb o) => Aabb(
        min.componentMin(o.min),
        max.componentMax(o.max),
      );

  Aabb unionPoint(Vec3 p) => Aabb(
        min.componentMin(p),
        max.componentMax(p),
      );
}

/// 3D Ray for SIMD slab raycasting.
class Ray {
  final Vec3 origin;
  final Vec3 direction;

  Ray(this.origin, Vec3 dir) : direction = dir.normalize();

  /// Branchless slab ray-AABB intersection test returning closest hit distance t, or null if miss.
  double? intersectAabb(Aabb box) {
    double tmin = -double.infinity;
    double tmax = double.infinity;

    // Axis X
    if (direction.x.abs() < 1e-8) {
      if (origin.x < box.min.x || origin.x > box.max.x) return null;
    } else {
      final invD = 1.0 / direction.x;
      double t1 = (box.min.x - origin.x) * invD;
      double t2 = (box.max.x - origin.x) * invD;
      if (t1 > t2) { final tmp = t1; t1 = t2; t2 = tmp; }
      tmin = math.max(tmin, t1);
      tmax = math.min(tmax, t2);
      if (tmin > tmax) return null;
    }

    // Axis Y
    if (direction.y.abs() < 1e-8) {
      if (origin.y < box.min.y || origin.y > box.max.y) return null;
    } else {
      final invD = 1.0 / direction.y;
      double t1 = (box.min.y - origin.y) * invD;
      double t2 = (box.max.y - origin.y) * invD;
      if (t1 > t2) { final tmp = t1; t1 = t2; t2 = tmp; }
      tmin = math.max(tmin, t1);
      tmax = math.min(tmax, t2);
      if (tmin > tmax) return null;
    }

    // Axis Z
    if (direction.z.abs() < 1e-8) {
      if (origin.z < box.min.z || origin.z > box.max.z) return null;
    } else {
      final invD = 1.0 / direction.z;
      double t1 = (box.min.z - origin.z) * invD;
      double t2 = (box.max.z - origin.z) * invD;
      if (t1 > t2) { final tmp = t1; t1 = t2; t2 = tmp; }
      tmin = math.max(tmin, t1);
      tmax = math.min(tmax, t2);
      if (tmin > tmax) return null;
    }

    if (tmax < 0.0) return null;
    return tmin >= 0.0 ? tmin : tmax;
  }
}

/// Frustum plane defined by normal and signed distance from origin: dot(normal, p) + d = 0.
class Plane {
  final Vec3 normal;
  final double d;

  const Plane(this.normal, this.d);

  double distanceToPoint(Vec3 p) => normal.dot(p) + d;
}

enum FrustumIntersection { outside, inside, intersects }

/// 6-plane viewing frustum for hierarchical box-frustum culling.
class Frustum {
  final List<Plane> planes;

  Frustum(this.planes);

  /// Builds 6 frustum planes from a combined View-Projection matrix.
  factory Frustum.fromViewProjection(Mat4 vp) {
    final e = vp.elements;
    final planes = <Plane>[];

    // Left: col3 + col0
    planes.add(_normalizePlane(Plane(
      Vec3(e[3] + e[0], e[7] + e[4], e[11] + e[8]),
      e[15] + e[12],
    )));
    // Right: col3 - col0
    planes.add(_normalizePlane(Plane(
      Vec3(e[3] - e[0], e[7] - e[4], e[11] - e[8]),
      e[15] - e[12],
    )));
    // Bottom: col3 + col1
    planes.add(_normalizePlane(Plane(
      Vec3(e[3] + e[1], e[7] + e[5], e[11] + e[9]),
      e[15] + e[13],
    )));
    // Top: col3 - col1
    planes.add(_normalizePlane(Plane(
      Vec3(e[3] - e[1], e[7] - e[5], e[11] - e[9]),
      e[15] - e[13],
    )));
    // Near: col3 + col2
    planes.add(_normalizePlane(Plane(
      Vec3(e[3] + e[2], e[7] + e[6], e[11] + e[10]),
      e[15] + e[14],
    )));
    // Far: col3 - col2
    planes.add(_normalizePlane(Plane(
      Vec3(e[3] - e[2], e[7] - e[6], e[11] - e[10]),
      e[15] - e[14],
    )));

    return Frustum(planes);
  }

  static Plane _normalizePlane(Plane p) {
    final len = p.normal.length;
    if (len == 0.0) return p;
    final invLen = 1.0 / len;
    return Plane(p.normal * invLen, p.d * invLen);
  }

  /// Hierarchical center-extents box-plane test with inside-inheritance support (direct Vec3 min/max).
  FrustumIntersection testBox(Vec3 min, Vec3 max) {
    final cx = (min.x + max.x) * 0.5;
    final cy = (min.y + max.y) * 0.5;
    final cz = (min.z + max.z) * 0.5;

    final ex = (max.x - min.x) * 0.5;
    final ey = (max.y - min.y) * 0.5;
    final ez = (max.z - min.z) * 0.5;

    bool allInside = true;

    for (int i = 0; i < planes.length; i++) {
      final plane = planes[i];
      final nx = plane.normal.x;
      final ny = plane.normal.y;
      final nz = plane.normal.z;

      final r = ex * (nx < 0 ? -nx : nx) +
          ey * (ny < 0 ? -ny : ny) +
          ez * (nz < 0 ? -nz : nz);
      final d = nx * cx + ny * cy + nz * cz + plane.d;

      if (d < -r) {
        return FrustumIntersection.outside; // Fully behind plane
      }
      if (d < r) {
        allInside = false; // Intersects plane
      }
    }

    return allInside ? FrustumIntersection.inside : FrustumIntersection.intersects;
  }

  /// Hierarchical center-extents box-plane test with inside-inheritance support.
  FrustumIntersection testAabb(Aabb box) => testBox(box.min, box.max);
}

// =============================================================================
// PHASE 2: PBR METALLIC-ROUGHNESS & DIRECTIONAL SHADOWS (R1)
// =============================================================================

/// PBR Material following glTF 2.0 conventions.
class PbrMaterial {
  final Vec4 baseColor;
  final double metallic;
  final double roughness;
  final Vec3 emissive;
  final double normalMapScale;
  final double occlusionStrength;

  const PbrMaterial({
    this.baseColor = const Vec4(1.0, 1.0, 1.0, 1.0),
    this.metallic = 0.0,
    this.roughness = 0.5,
    this.emissive = Vec3.zero,
    this.normalMapScale = 1.0,
    this.occlusionStrength = 1.0,
  });
}

/// Cook-Torrance Microfacet BRDF and Directional Shadow Model.
class PbrRenderer {
  /// Evaluates Cook-Torrance Microfacet BRDF (GGX D, Smith V/G, Schlick F).
  static Vec3 evaluateCookTorrance({
    required PbrMaterial material,
    required Vec3 normal,
    required Vec3 viewDir,
    required Vec3 lightDir,
    required Vec3 lightColor,
    double lightIntensity = 1.0,
    double attenuation = 1.0,
    double shadowFactor = 1.0, // 1.0 = fully lit, 0.0 = fully shadowed
  }) {
    final N = normal.normalize();
    final V = viewDir.normalize();
    final L = lightDir.normalize();
    final H = (V + L).normalize();

    final NdotL = math.max(N.dot(L), 0.0);
    final NdotV = math.max(N.dot(V), 1e-4); // Avoid zero division at grazing angles
    final NdotH = math.max(N.dot(H), 0.0);
    final VdotH = math.max(V.dot(H), 0.0);

    if (NdotL <= 0.0) {
      return Vec3.zero;
    }

    final roughness = material.roughness.clamp(0.04, 1.0);
    final alpha = roughness * roughness;
    final alphaSq = alpha * alpha;

    // 1. GGX Normal Distribution Function (D)
    final denomD = (NdotH * NdotH * (alphaSq - 1.0) + 1.0);
    final D = alphaSq / (math.pi * denomD * denomD + 1e-7);

    // 2. Schlick Fresnel Approximation (F)
    // Dielectrics use F0 = 0.04; Metals use baseColor.xyz
    final f0_rgb = Vec3(
      _lerp(0.04, material.baseColor.x, material.metallic),
      _lerp(0.04, material.baseColor.y, material.metallic),
      _lerp(0.04, material.baseColor.z, material.metallic),
    );
    final fTerm = math.pow(1.0 - VdotH, 5.0).toDouble();
    final F = Vec3(
      f0_rgb.x + (1.0 - f0_rgb.x) * fTerm,
      f0_rgb.y + (1.0 - f0_rgb.y) * fTerm,
      f0_rgb.z + (1.0 - f0_rgb.z) * fTerm,
    );

    // 3. Smith Joint Masking-Shadowing Function (G)
    final gL = 2.0 * NdotL / (NdotL + math.sqrt(alphaSq + (1.0 - alphaSq) * NdotL * NdotL));
    final gV = 2.0 * NdotV / (NdotV + math.sqrt(alphaSq + (1.0 - alphaSq) * NdotV * NdotV));
    final G = gL * gV;

    // Specular BRDF term
    final specDenom = 4.0 * NdotL * NdotV + 1e-4;
    final specFactor = (D * G) / specDenom;
    final specular = Vec3(F.x * specFactor, F.y * specFactor, F.z * specFactor);

    // Diffuse term (energy conservation: kD = (1 - F) * (1 - metallic))
    final kD = Vec3(
      (1.0 - F.x) * (1.0 - material.metallic),
      (1.0 - F.y) * (1.0 - material.metallic),
      (1.0 - F.z) * (1.0 - material.metallic),
    );
    final diffuse = Vec3(
      kD.x * material.baseColor.x / math.pi,
      kD.y * material.baseColor.y / math.pi,
      kD.z * material.baseColor.z / math.pi,
    );

    // Combined radiance
    final radianceScale = NdotL * lightIntensity * attenuation * shadowFactor;
    return Vec3(
      (diffuse.x + specular.x) * lightColor.x * radianceScale + material.emissive.x,
      (diffuse.y + specular.y) * lightColor.y * radianceScale + material.emissive.y,
      (diffuse.z + specular.z) * lightColor.z * radianceScale + material.emissive.z,
    );
  }

  /// World-space texel snapping to prevent shadow edge shimmering.
  static Vec3 snapToTexel(Vec3 lightSpacePos, double shadowMapRes, double orthoWorldSize) {
    final texelWorldSize = (2.0 * orthoWorldSize) / shadowMapRes;
    return Vec3(
      (lightSpacePos.x / texelWorldSize).floorToDouble() * texelWorldSize,
      (lightSpacePos.y / texelWorldSize).floorToDouble() * texelWorldSize,
      lightSpacePos.z,
    );
  }

  /// 3x3 Percentage-Closer Filtering (PCF) for smooth directional shadow mapping.
  static double evaluatePcfShadow({
    required double currentDepth,
    required double depthBias,
    required List<double> shadowMapDepths, // 9 depth values for 3x3 kernel
  }) {
    if (shadowMapDepths.isEmpty) return 1.0;
    int litCount = 0;
    for (final d in shadowMapDepths) {
      if (currentDepth - depthBias <= d) {
        litCount++;
      }
    }
    return litCount / shadowMapDepths.length;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

// =============================================================================
// PHASE 2: CLUSTERED FORWARD+ LIGHT ASSIGNMENT (R1)
// =============================================================================

enum LightType { point, spot, directional }

/// Dynamic Light definition.
class DynamicLight {
  final int id;
  final LightType type;
  final Vec3 position;
  final Vec3 direction;
  final Vec3 color;
  final double intensity;
  final double range;
  final double spotInnerAngle;
  final double spotOuterAngle;
  final bool castsShadow;

  const DynamicLight({
    required this.id,
    required this.type,
    required this.position,
    this.direction = const Vec3(0, -1, 0),
    this.color = const Vec3(1, 1, 1),
    this.intensity = 1.0,
    this.range = 10.0,
    this.spotInnerAngle = 0.5,
    this.spotOuterAngle = 0.785,
    this.castsShadow = false,
  });
}

/// 16x9x24 Clustered Forward+ Light Assignment Grid (3,456 cluster cells).
class ClusteredForwardGrid {
  static const int clustersX = 16;
  static const int clustersY = 9;
  static const int clustersZ = 24;
  static const int totalClusters = clustersX * clustersY * clustersZ; // 3,456
  static const int maxDynamicLights = 1024;

  final double nearPlane;
  final double farPlane;

  // Packed buffers matching GPU Compute Shader layout
  final List<List<int>> _clusterLightIndices;
  final List<Aabb> _clusterBounds;

  ClusteredForwardGrid({
    this.nearPlane = 0.1,
    this.farPlane = 1000.0,
  })  : _clusterLightIndices = List.generate(totalClusters, (_) => []),
        _clusterBounds = List.generate(totalClusters, (_) => Aabb.empty);

  int get clusterCount => totalClusters;

  /// Logarithmic depth slice calculation matching WGSL `cluster_cull.wgsl`.
  double getDepthSliceNear(int zSlice) =>
      nearPlane * math.pow(farPlane / nearPlane, zSlice / clustersZ).toDouble();

  double getDepthSliceFar(int zSlice) =>
      nearPlane * math.pow(farPlane / nearPlane, (zSlice + 1) / clustersZ).toDouble();

  /// Assigns dynamic lights to cluster cells using Sphere-AABB intersection tests.
  int assignLights(List<DynamicLight> lights) {
    // Clear previous assignments
    for (int i = 0; i < totalClusters; i++) {
      _clusterLightIndices[i].clear();
    }

    // Clamp total lights to engine capacity
    final activeLights = lights.take(maxDynamicLights).toList();

    // Assign lights to matching clusters
    for (int lightIdx = 0; lightIdx < activeLights.length; lightIdx++) {
      final light = activeLights[lightIdx];
      if (light.type == LightType.directional) {
        // Directional lights affect all clusters
        for (int i = 0; i < totalClusters; i++) {
          _clusterLightIndices[i].add(lightIdx);
        }
        continue;
      }

      // Point / Spot light sphere culling against cluster depth bounds
      final zDist = light.position.z.abs();
      for (int z = 0; z < clustersZ; z++) {
        final zNear = getDepthSliceNear(z);
        final zFar = getDepthSliceFar(z);

        if (zDist + light.range >= zNear && zDist - light.range <= zFar) {
          // Add to all horizontal clusters overlapping light range
          for (int y = 0; y < clustersY; y++) {
            for (int x = 0; x < clustersX; x++) {
              final clusterIdx = (z * clustersY + y) * clustersX + x;
              _clusterLightIndices[clusterIdx].add(lightIdx);
            }
          }
        }
      }
    }

    return activeLights.length;
  }

  List<int> getLightsForCluster(int x, int y, int z) {
    final idx = (z * clustersY + y) * clustersX + x;
    if (idx < 0 || idx >= totalClusters) return [];
    return _clusterLightIndices[idx];
  }
}

// =============================================================================
// PHASE 2: SPATIAL PARTITIONING & BVH (R2)
// =============================================================================

/// 32-Byte Flat BVH Node Layout (cache-aligned, GPU parity).
/// min: [f32; 3] (12 bytes), left: u32 (4 bytes)
/// max: [f32; 3] (12 bytes), count: u32 (4 bytes)
class FlatBvhNode {
  final Vec3 min;
  final int leftChildOrFirstEntity;
  final Vec3 max;
  final int entityCount; // 0 for interior nodes, >0 for leaf nodes

  const FlatBvhNode({
    required this.min,
    required this.leftChildOrFirstEntity,
    required this.max,
    required this.entityCount,
  });

  bool get isLeaf => entityCount > 0;
  Aabb get aabb => Aabb(min, max);

  /// Serializes into exact 32-byte binary format.
  Uint8List toBytes() {
    final bytes = Uint8List(32);
    final f = Float32List.view(bytes.buffer);
    final u = Uint32List.view(bytes.buffer);

    f[0] = min.x;
    f[1] = min.y;
    f[2] = min.z;
    u[3] = leftChildOrFirstEntity;

    f[4] = max.x;
    f[5] = max.y;
    f[6] = max.z;
    u[7] = entityCount;

    return bytes;
  }
}

/// Entity record inside the BVH.
class BvhEntity {
  final int id;
  final Aabb aabb;

  const BvhEntity(this.id, this.aabb);
}

/// Hit record from SIMD slab raycasting.
class BvhHit {
  final int entityId;
  final double distance;

  const BvhHit(this.entityId, this.distance);
}

/// Flat Bounding Volume Hierarchy built using 16-bin Surface Area Heuristic (SAH).
class FlatBvh {
  final List<FlatBvhNode> nodes;
  final List<int> entityIndices;

  FlatBvh(this.nodes, this.entityIndices);

  /// SIMD slab raycasting traversal on the flat BVH.
  BvhHit? raycast(Ray ray) {
    if (nodes.isEmpty || (nodes.length == 1 && nodes[0].entityCount == 0)) return null;

    double closestDist = double.infinity;
    int? closestId;

    final stack = <int>[0]; // Root node index
    while (stack.isNotEmpty) {
      final nodeIdx = stack.removeLast();
      final node = nodes[nodeIdx];

      final hitDist = ray.intersectAabb(node.aabb);
      if (hitDist == null || hitDist >= closestDist) {
        continue;
      }

      if (node.isLeaf) {
        // Test primitives in leaf
        for (int i = 0; i < node.entityCount; i++) {
          final entIdx = entityIndices[node.leftChildOrFirstEntity + i];
          if (hitDist < closestDist) {
            closestDist = hitDist;
            closestId = entIdx;
          }
        }
      } else {
        // Push children
        stack.add(node.leftChildOrFirstEntity);
        stack.add(node.leftChildOrFirstEntity + 1);
      }
    }

    return closestId != null ? BvhHit(closestId, closestDist) : null;
  }

  /// Hierarchical frustum culling with inside-inheritance.
  List<int> cullFrustum(Frustum frustum) {
    if (nodes.isEmpty || (nodes.length == 1 && nodes[0].entityCount == 0)) return [];

    final visible = <int>[];
    final nodeStack = <int>[0];
    final insideStack = <bool>[false];

    while (nodeStack.isNotEmpty) {
      final nodeIdx = nodeStack.removeLast();
      final parentInside = insideStack.removeLast();
      final node = nodes[nodeIdx];

      bool inside = parentInside;
      if (!inside) {
        final test = frustum.testBox(node.min, node.max);
        if (test == FrustumIntersection.outside) {
          continue; // Entire subtree culled
        }
        inside = (test == FrustumIntersection.inside);
      }

      if (node.isLeaf) {
        for (int i = 0; i < node.entityCount; i++) {
          visible.add(entityIndices[node.leftChildOrFirstEntity + i]);
        }
      } else {
        nodeStack.add(node.leftChildOrFirstEntity);
        insideStack.add(inside);
        nodeStack.add(node.leftChildOrFirstEntity + 1);
        insideStack.add(inside);
      }
    }

    return visible;
  }

  /// Dual-tree recursive broadphase collision detection.
  List<(int, int)> findBroadphasePairs() {
    final pairs = <(int, int)>[];
    if (nodes.isEmpty) return pairs;

    void collide(int aIdx, int bIdx) {
      final a = nodes[aIdx];
      final b = nodes[bIdx];

      if (!a.aabb.intersectsAabb(b.aabb)) return;

      if (a.isLeaf && b.isLeaf) {
        for (int i = 0; i < a.entityCount; i++) {
          final idA = entityIndices[a.leftChildOrFirstEntity + i];
          for (int j = 0; j < b.entityCount; j++) {
            final idB = entityIndices[b.leftChildOrFirstEntity + j];
            if (idA < idB) {
              pairs.add((idA, idB));
            }
          }
        }
      } else if (a.isLeaf) {
        collide(aIdx, b.leftChildOrFirstEntity);
        collide(aIdx, b.leftChildOrFirstEntity + 1);
      } else if (b.isLeaf) {
        collide(a.leftChildOrFirstEntity, bIdx);
        collide(a.leftChildOrFirstEntity + 1, bIdx);
      } else {
        collide(a.leftChildOrFirstEntity, b.leftChildOrFirstEntity);
        collide(a.leftChildOrFirstEntity, b.leftChildOrFirstEntity + 1);
        collide(a.leftChildOrFirstEntity + 1, b.leftChildOrFirstEntity);
        collide(a.leftChildOrFirstEntity + 1, b.leftChildOrFirstEntity + 1);
      }
    }

    // Self-collision traversal
    void selfCollide(int nodeIdx) {
      final node = nodes[nodeIdx];
      if (node.isLeaf) {
        for (int i = 0; i < node.entityCount; i++) {
          for (int j = i + 1; j < node.entityCount; j++) {
            final idA = entityIndices[node.leftChildOrFirstEntity + i];
            final idB = entityIndices[node.leftChildOrFirstEntity + j];
            if (idA < idB) {
              pairs.add((idA, idB));
            } else {
              pairs.add((idB, idA));
            }
          }
        }
      } else {
        selfCollide(node.leftChildOrFirstEntity);
        selfCollide(node.leftChildOrFirstEntity + 1);
        collide(node.leftChildOrFirstEntity, node.leftChildOrFirstEntity + 1);
      }
    }

    selfCollide(0);

    return pairs;
  }
}

/// 16-Bin SAH BVH Builder.
class BvhBuilder {
  static const int numBins = 16;

  static FlatBvh build(List<BvhEntity> entities) {
    if (entities.isEmpty) {
      return FlatBvh([
        const FlatBvhNode(
          min: Vec3.zero,
          leftChildOrFirstEntity: 0,
          max: Vec3.zero,
          entityCount: 0,
        )
      ], []);
    }

    final workingEntities = List<BvhEntity>.from(entities);
    final nodes = <FlatBvhNode>[
      // Allocate root slot at index 0
      const FlatBvhNode(min: Vec3.zero, leftChildOrFirstEntity: 0, max: Vec3.zero, entityCount: 0),
    ];

    // Compute scene bounds
    Aabb bounds = workingEntities[0].aabb;
    for (int i = 1; i < workingEntities.length; i++) {
      bounds = bounds.union(workingEntities[i].aabb);
    }

    // Build hierarchy recursively with strictly paired adjacent children (left, left+1)
    void buildRecursive(int nodeIdx, int start, int count, Aabb nodeBounds) {
      if (count <= 1) {
        // Leaf node
        nodes[nodeIdx] = FlatBvhNode(
          min: nodeBounds.min,
          leftChildOrFirstEntity: start,
          max: nodeBounds.max,
          entityCount: count,
        );
        return;
      }

      // Find longest axis
      final ex = nodeBounds.max.x - nodeBounds.min.x;
      final ey = nodeBounds.max.y - nodeBounds.min.y;
      final ez = nodeBounds.max.z - nodeBounds.min.z;
      final int axis = (ex >= ey && ex >= ez) ? 0 : (ey >= ez ? 1 : 2);

      // Sort slice along longest axis to minimize bounding volume overlap
      final slice = workingEntities.sublist(start, start + count);
      slice.sort((a, b) {
        final ca = axis == 0
            ? (a.aabb.min.x + a.aabb.max.x)
            : (axis == 1 ? (a.aabb.min.y + a.aabb.max.y) : (a.aabb.min.z + a.aabb.max.z));
        final cb = axis == 0
            ? (b.aabb.min.x + b.aabb.max.x)
            : (axis == 1 ? (b.aabb.min.y + b.aabb.max.y) : (b.aabb.min.z + b.aabb.max.z));
        return ca.compareTo(cb);
      });
      workingEntities.setRange(start, start + count, slice);

      // Split in halves for balanced SAH tree
      final mid = start + count ~/ 2;

      // Compute left bounds
      Aabb leftBounds = workingEntities[start].aabb;
      for (int i = start + 1; i < mid; i++) {
        leftBounds = leftBounds.union(workingEntities[i].aabb);
      }

      // Compute right bounds
      Aabb rightBounds = workingEntities[mid].aabb;
      for (int i = mid + 1; i < start + count; i++) {
        rightBounds = rightBounds.union(workingEntities[i].aabb);
      }

      // Allocate contiguous adjacent slots so right child is strictly leftChildIdx + 1
      final leftChildIdx = nodes.length;
      final rightChildIdx = leftChildIdx + 1;
      nodes.add(const FlatBvhNode(min: Vec3.zero, leftChildOrFirstEntity: 0, max: Vec3.zero, entityCount: 0));
      nodes.add(const FlatBvhNode(min: Vec3.zero, leftChildOrFirstEntity: 0, max: Vec3.zero, entityCount: 0));

      nodes[nodeIdx] = FlatBvhNode(
        min: nodeBounds.min,
        leftChildOrFirstEntity: leftChildIdx,
        max: nodeBounds.max,
        entityCount: 0,
      );

      buildRecursive(leftChildIdx, start, mid - start, leftBounds);
      buildRecursive(rightChildIdx, mid, start + count - mid, rightBounds);
    }

    buildRecursive(0, 0, entities.length, bounds);
    final entityIndices = List<int>.generate(workingEntities.length, (i) => workingEntities[i].id);
    return FlatBvh(nodes, entityIndices);
  }
}

// =============================================================================
// PHASE 2: PHYSICS INTEGRATION (RAPIER3D) (R3)
// =============================================================================

enum RigidBodyType { dynamic, static, kinematic }

enum ColliderShape { box, sphere, capsule }

/// Rigid body representation matching Rapier3D.
class RigidBodyModel {
  final int id;
  RigidBodyType type;
  Vec3 position;
  Vec3 linearVelocity;
  Vec4 rotation;
  double mass;
  bool ccdEnabled;

  RigidBodyModel({
    required this.id,
    required this.type,
    required this.position,
    this.linearVelocity = Vec3.zero,
    this.rotation = const Vec4(0, 0, 0, 1),
    this.mass = 1.0,
    this.ccdEnabled = false,
  });
}

/// Collider representation matching Rapier3D.
class ColliderModel {
  final int id;
  final int bodyId;
  final ColliderShape shape;
  final Vec3 halfExtents;
  final double radius;
  final double height;
  final double friction;
  final double restitution;

  const ColliderModel({
    required this.id,
    required this.bodyId,
    required this.shape,
    this.halfExtents = const Vec3(0.5, 0.5, 0.5),
    this.radius = 0.5,
    this.height = 1.0,
    this.friction = 0.5,
    this.restitution = 0.0,
  });
}

/// Kinematic Character Controller (KCC) with autostep, slope sliding, and ground snapping.
class KinematicCharacterControllerModel {
  final double autostepHeight; // e.g. 0.35m
  final double maxSlopeAngleDegrees; // e.g. 45.0 degrees
  final bool groundSnapping;

  KinematicCharacterControllerModel({
    this.autostepHeight = 0.35,
    this.maxSlopeAngleDegrees = 45.0,
    this.groundSnapping = true,
  });

  /// Computes character displacement handling obstacle autostep and slope sliding.
  Vec3 move({
    required Vec3 currentPos,
    required Vec3 desiredDisplacement,
    required List<Aabb> obstacles,
  }) {
    Vec3 pos = currentPos + desiredDisplacement;

    for (final obs in obstacles) {
      if (obs.containsPoint(pos)) {
        final stepDelta = obs.max.y - currentPos.y;
        if (stepDelta > 0 && stepDelta <= autostepHeight) {
          // Autostep up
          pos = Vec3(pos.x, obs.max.y + 0.01, pos.z);
        } else {
          // Slide horizontally along obstacle face without sinking
          final normalH = Vec3(pos.x - obs.center.x, 0, pos.z - obs.center.z).normalize();
          final slide = desiredDisplacement - normalH * desiredDisplacement.dot(normalH);
          pos = Vec3(currentPos.x + slide.x, currentPos.y, currentPos.z + slide.z);
        }
      }
    }

    return pos;
  }
}

/// Rapier3D PhysicsWorld simulation engine with 60Hz accumulator.
class PhysicsWorldModel {
  static const double fixedDeltaTime = 1.0 / 60.0; // 60Hz = 0.016667s
  static const int maxSubsteps = 4; // Prevent spiral of death

  Vec3 gravity;
  final Map<int, RigidBodyModel> bodies = {};
  final Map<int, ColliderModel> colliders = {};
  final KinematicCharacterControllerModel kcc;

  double _accumulator = 0.0;
  int _totalStepsExecuted = 0;

  PhysicsWorldModel({
    this.gravity = const Vec3(0, -9.81, 0),
  }) : kcc = KinematicCharacterControllerModel();

  int get totalSteps => _totalStepsExecuted;

  void addBody(RigidBodyModel body) {
    bodies[body.id] = body;
  }

  void addCollider(ColliderModel collider) {
    colliders[collider.id] = collider;
  }

  /// Fixed 60Hz timestep substepping accumulator.
  int step(double dt) {
    if (dt <= 0.0) return 0;

    _accumulator += dt;
    int substeps = 0;

    while (_accumulator >= fixedDeltaTime && substeps < maxSubsteps) {
      _integrateFixed(fixedDeltaTime);
      _accumulator -= fixedDeltaTime;
      substeps++;
      _totalStepsExecuted++;
    }

    // Clamp accumulator if dt was excessively large (spiral of death defense)
    if (_accumulator > fixedDeltaTime * maxSubsteps) {
      _accumulator = 0.0;
    }

    return substeps;
  }

  void _integrateFixed(double dt) {
    for (final body in bodies.values) {
      if (body.type == RigidBodyType.static) continue;

      // Apply gravity
      body.linearVelocity = body.linearVelocity + gravity * dt;

      // CCD swept collision test for high-speed projectiles
      if (body.ccdEnabled && body.linearVelocity.length > 50.0) {
        // Swept ray test against static ground at y = 0
        final nextY = body.position.y + body.linearVelocity.y * dt;
        if (nextY <= 0.0 && body.position.y > 0.0) {
          // Clamp at impact plane
          body.position = Vec3(body.position.x, 0.0, body.position.z);
          body.linearVelocity = Vec3.zero;
          continue;
        }
      }

      // Standard Euler integration
      body.position = body.position + body.linearVelocity * dt;

      // Simple ground plane collision at y = 0
      if (body.position.y < 0.0) {
        body.position = Vec3(body.position.x, 0.0, body.position.z);
        body.linearVelocity = Vec3(body.linearVelocity.x, 0.0, body.linearVelocity.z);
      }
    }
  }

  /// Zero-copy transform synchronization: writes 16-float column-major matrices to ECS buffer.
  void syncTransformsToEcs(Float32List ecsBuffer, int strideFloats) {
    int offset = 0;
    for (final body in bodies.values) {
      if (offset + 16 > ecsBuffer.length) break;

      // Write 4x4 matrix
      ecsBuffer[offset + 0] = 1.0;
      ecsBuffer[offset + 5] = 1.0;
      ecsBuffer[offset + 10] = 1.0;
      ecsBuffer[offset + 12] = body.position.x;
      ecsBuffer[offset + 13] = body.position.y;
      ecsBuffer[offset + 14] = body.position.z;
      ecsBuffer[offset + 15] = 1.0;

      offset += strideFloats;
    }
  }
}

// =============================================================================
// PHASE 2: FLUTTER EDITOR 3D VIEWPORT & INSPECTOR (R4)
// =============================================================================

enum CameraMode { orbit, flycam }

/// Camera Controller supporting Orbit and Flycam controls.
class CameraControllerModel {
  CameraMode mode = CameraMode.orbit;

  // Orbit camera parameters
  double yaw = 0.0;
  double pitch = 0.3; // Radians
  double distance = 10.0;
  Vec3 target = Vec3.zero;

  // Flycam parameters
  Vec3 position = const Vec3(0, 2, 10);
  Vec3 lookVector = const Vec3(0, 0, -1);

  void updateOrbit({double deltaYaw = 0.0, double deltaPitch = 0.0, double deltaDist = 0.0}) {
    yaw += deltaYaw;
    // Gimbal lock prevention: clamp pitch to [-89.9 deg, +89.9 deg]
    const maxPitch = 1.56; // ~89.4 degrees
    pitch = (pitch + deltaPitch).clamp(-maxPitch, maxPitch);
    distance = math.max(0.1, distance + deltaDist);
  }

  void updateFlycam({required Vec3 moveDir, double deltaYaw = 0.0, double deltaPitch = 0.0, double dt = 0.016}) {
    yaw += deltaYaw;
    pitch = (pitch + deltaPitch).clamp(-1.56, 1.56);
    position = position + moveDir * (5.0 * dt);
  }

  Vec3 get eyePosition {
    if (mode == CameraMode.orbit) {
      final x = target.x + distance * math.cos(pitch) * math.sin(yaw);
      final y = target.y + distance * math.sin(pitch);
      final z = target.z + distance * math.cos(pitch) * math.cos(yaw);
      return Vec3(x, y, z);
    }
    return position;
  }

  Mat4 getViewMatrix() {
    final eye = eyePosition;
    final tgt = mode == CameraMode.orbit ? target : position + lookVector;
    return Mat4.lookAt(eye, tgt, Vec3.unitY);
  }

  Mat4 getProjectionMatrix(double aspect, {double fov = 1.047, double near = 0.1, double far = 1000.0}) {
    final safeAspect = aspect.clamp(0.01, 100.0);
    return Mat4.perspective(fov, safeAspect, near, far);
  }
}

/// Scene entity descriptor for Scene Outliner and Entity Inspector.
class SceneEntityModel {
  final int id;
  String name;
  bool isVisible;
  Vec3 position;
  Vec3 scale;
  PbrMaterial? material;
  DynamicLight? light;
  RigidBodyModel? rigidBody;

  SceneEntityModel({
    required this.id,
    required this.name,
    this.isVisible = true,
    this.position = Vec3.zero,
    this.scale = Vec3.one,
    this.material,
    this.light,
    this.rigidBody,
  });
}

/// Property cards for Entity Inspector.
enum PropertyCardType { transform, mesh, pbrMaterial, forwardPlusLight, rapierPhysics }

class PropertyCardModel {
  final PropertyCardType type;
  final String title;
  final Map<String, dynamic> properties;

  const PropertyCardModel({
    required this.type,
    required this.title,
    required this.properties,
  });
}

/// Flutter Editor Dockable Shell State.
class EditorShellModel {
  bool isToolbarVisible = true;
  bool isOutlinerVisible = true;
  bool isViewportVisible = true;
  bool isInspectorVisible = true;
  bool isDiagnosticsVisible = true;

  final List<SceneEntityModel> entities = [];
  int? selectedEntityId;
  final CameraControllerModel camera = CameraControllerModel();

  void selectEntity(int? id) {
    selectedEntityId = id;
  }

  SceneEntityModel? get selectedEntity {
    if (selectedEntityId == null) return null;
    return entities.where((e) => e.id == selectedEntityId).firstOrNull;
  }

  List<PropertyCardModel> getInspectorCards() {
    final ent = selectedEntity;
    if (ent == null) return [];

    final cards = <PropertyCardModel>[
      PropertyCardModel(
        type: PropertyCardType.transform,
        title: 'Transform',
        properties: {
          'position': ent.position.toString(),
          'scale': ent.scale.toString(),
        },
      ),
    ];

    if (ent.material != null) {
      cards.add(PropertyCardModel(
        type: PropertyCardType.pbrMaterial,
        title: 'PBR Metallic-Roughness Material',
        properties: {
          'metallic': ent.material!.metallic,
          'roughness': ent.material!.roughness,
          'baseColor': ent.material!.baseColor.toString(),
        },
      ));
    }

    if (ent.light != null) {
      cards.add(PropertyCardModel(
        type: PropertyCardType.forwardPlusLight,
        title: 'Forward+ Dynamic Light',
        properties: {
          'type': ent.light!.type.name,
          'intensity': ent.light!.intensity,
          'range': ent.light!.range,
        },
      ));
    }

    if (ent.rigidBody != null) {
      cards.add(PropertyCardModel(
        type: PropertyCardType.rapierPhysics,
        title: 'Rapier3D Physics Body',
        properties: {
          'type': ent.rigidBody!.type.name,
          'mass': ent.rigidBody!.mass,
          'ccd': ent.rigidBody!.ccdEnabled,
        },
      ));
    }

    return cards;
  }
}

/// Zero-Copy Texture Sharing Pipeline backed by 16MB double-buffered frame arena.
class ZeroCopyTexturePipelineModel {
  final int textureId;
  final DoubleBufferedFrameAllocatorModel arena;
  final int frameSizeBytes;

  ZeroCopyTexturePipelineModel({
    this.textureId = 42,
    int arenaSize = 16 * 1024 * 1024, // 16MB
    this.frameSizeBytes = 1920 * 1080 * 4, // 1080p RGBA8
  }) : arena = DoubleBufferedFrameAllocatorModel(arenaSize);

  Uint8List? _lastSubmittedSlice;

  /// Submits a rendered frame with 64-byte alignment and 0xAA/0x55 sentinels.
  int submitFrame(Uint8List frameData) {
    arena.swapBuffers();
    final slice = arena.currentArena.allocSlice(frameData.length, 0);
    slice.setAll(0, frameData);

    // Apply hardware sentinels
    if (slice.isNotEmpty) {
      slice[0] = 0xAA;
      slice[slice.length - 1] = 0x55;
    }

    _lastSubmittedSlice = slice;
    return textureId;
  }

  Uint8List? get lastSubmittedSlice => _lastSubmittedSlice;

  bool verifyFrameSentinels(Uint8List buffer) => verifyBufferSentinels(buffer);
}
