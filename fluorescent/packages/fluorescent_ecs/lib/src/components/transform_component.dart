import 'dart:typed_data';

import '../entity.dart';
import '../storage/typed_component_storage.dart';

/// Offsets into the 16-float stride for each Transform component entry.
abstract final class TransformOffsets {
  /// Translation X component offset.
  static const int x = 0;

  /// Translation Y component offset.
  static const int y = 1;

  /// Translation Z component offset.
  static const int z = 2;

  /// Flags / status bits (e.g. dirty bit, static flag).
  static const int flags = 3;

  /// Quaternion rotation X component.
  static const int qx = 4;

  /// Quaternion rotation Y component.
  static const int qy = 5;

  /// Quaternion rotation Z component.
  static const int qz = 6;

  /// Quaternion rotation W component.
  static const int qw = 7;

  /// Scale X component.
  static const int sx = 8;

  /// Scale Y component.
  static const int sy = 9;

  /// Scale Z component.
  static const int sz = 10;

  /// Reserved float for alignment / future expansion.
  static const int reserved = 11;

  /// Bounding sphere radius.
  static const int boundsRadius = 12;

  /// Bounding sphere center X.
  static const int boundsCenterX = 13;

  /// Bounding sphere center Y.
  static const int boundsCenterY = 14;

  /// Bounding sphere center Z.
  static const int boundsCenterZ = 15;

  /// Total number of 32-bit floats per Transform entry (64 bytes).
  static const int stride = 16;
}

/// Bit flags for [TransformOffsets.flags].
abstract final class TransformFlags {
  /// No flags set.
  static const int none = 0;

  /// Indicates transform matrix needs recalculation.
  static const int dirty = 1 << 0;

  /// Indicates this transform is static and will not change.
  static const int staticTransform = 1 << 1;
}

/// Plain Dart object representation of a 3D Transform.
///
/// Useful for high-level operations, serialization, and initial component setup.
class TransformComponent {
  double x;
  double y;
  double z;
  int flags;
  double qx;
  double qy;
  double qz;
  double qw;
  double sx;
  double sy;
  double sz;
  double reserved;
  double boundsRadius;
  double boundsCenterX;
  double boundsCenterY;
  double boundsCenterZ;

  /// Creates a [TransformComponent] with default identity transform values.
  TransformComponent({
    this.x = 0.0,
    this.y = 0.0,
    this.z = 0.0,
    this.flags = 0,
    this.qx = 0.0,
    this.qy = 0.0,
    this.qz = 0.0,
    this.qw = 1.0,
    this.sx = 1.0,
    this.sy = 1.0,
    this.sz = 1.0,
    this.reserved = 0.0,
    this.boundsRadius = 0.0,
    this.boundsCenterX = 0.0,
    this.boundsCenterY = 0.0,
    this.boundsCenterZ = 0.0,
  });

  /// Reads transform fields directly from a contiguous [Float32List] buffer at [offset].
  factory TransformComponent.fromBuffer(Float32List buffer, int offset) {
    return TransformComponent(
      x: buffer[offset + TransformOffsets.x],
      y: buffer[offset + TransformOffsets.y],
      z: buffer[offset + TransformOffsets.z],
      flags: buffer[offset + TransformOffsets.flags].toInt(),
      qx: buffer[offset + TransformOffsets.qx],
      qy: buffer[offset + TransformOffsets.qy],
      qz: buffer[offset + TransformOffsets.qz],
      qw: buffer[offset + TransformOffsets.qw],
      sx: buffer[offset + TransformOffsets.sx],
      sy: buffer[offset + TransformOffsets.sy],
      sz: buffer[offset + TransformOffsets.sz],
      reserved: buffer[offset + TransformOffsets.reserved],
      boundsRadius: buffer[offset + TransformOffsets.boundsRadius],
      boundsCenterX: buffer[offset + TransformOffsets.boundsCenterX],
      boundsCenterY: buffer[offset + TransformOffsets.boundsCenterY],
      boundsCenterZ: buffer[offset + TransformOffsets.boundsCenterZ],
    );
  }

  /// Writes all 16 transform fields into [buffer] at [offset].
  void writeToBuffer(Float32List buffer, int offset) {
    buffer[offset + TransformOffsets.x] = x;
    buffer[offset + TransformOffsets.y] = y;
    buffer[offset + TransformOffsets.z] = z;
    buffer[offset + TransformOffsets.flags] = flags.toDouble();
    buffer[offset + TransformOffsets.qx] = qx;
    buffer[offset + TransformOffsets.qy] = qy;
    buffer[offset + TransformOffsets.qz] = qz;
    buffer[offset + TransformOffsets.qw] = qw;
    buffer[offset + TransformOffsets.sx] = sx;
    buffer[offset + TransformOffsets.sy] = sy;
    buffer[offset + TransformOffsets.sz] = sz;
    buffer[offset + TransformOffsets.reserved] = reserved;
    buffer[offset + TransformOffsets.boundsRadius] = boundsRadius;
    buffer[offset + TransformOffsets.boundsCenterX] = boundsCenterX;
    buffer[offset + TransformOffsets.boundsCenterY] = boundsCenterY;
    buffer[offset + TransformOffsets.boundsCenterZ] = boundsCenterZ;
  }
}

/// Zero-allocation in-place mutable view pointing directly to a transform slice in [Float32List].
class TransformView {
  /// The backing float buffer.
  final Float32List buffer;

  /// The float offset into [buffer].
  final int offset;

  /// Creates a [TransformView] at the given [offset].
  const TransformView(this.buffer, this.offset);

  double get x => buffer[offset + TransformOffsets.x];
  set x(double val) => buffer[offset + TransformOffsets.x] = val;

  double get y => buffer[offset + TransformOffsets.y];
  set y(double val) => buffer[offset + TransformOffsets.y] = val;

  double get z => buffer[offset + TransformOffsets.z];
  set z(double val) => buffer[offset + TransformOffsets.z] = val;

  int get flags => buffer[offset + TransformOffsets.flags].toInt();
  set flags(int val) => buffer[offset + TransformOffsets.flags] = val.toDouble();

  double get qx => buffer[offset + TransformOffsets.qx];
  set qx(double val) => buffer[offset + TransformOffsets.qx] = val;

  double get qy => buffer[offset + TransformOffsets.qy];
  set qy(double val) => buffer[offset + TransformOffsets.qy] = val;

  double get qz => buffer[offset + TransformOffsets.qz];
  set qz(double val) => buffer[offset + TransformOffsets.qz] = val;

  double get qw => buffer[offset + TransformOffsets.qw];
  set qw(double val) => buffer[offset + TransformOffsets.qw] = val;

  double get sx => buffer[offset + TransformOffsets.sx];
  set sx(double val) => buffer[offset + TransformOffsets.sx] = val;

  double get sy => buffer[offset + TransformOffsets.sy];
  set sy(double val) => buffer[offset + TransformOffsets.sy] = val;

  double get sz => buffer[offset + TransformOffsets.sz];
  set sz(double val) => buffer[offset + TransformOffsets.sz] = val;

  double get boundsRadius => buffer[offset + TransformOffsets.boundsRadius];
  set boundsRadius(double val) => buffer[offset + TransformOffsets.boundsRadius] = val;

  void setTranslation(double x, double y, double z) {
    buffer[offset + TransformOffsets.x] = x;
    buffer[offset + TransformOffsets.y] = y;
    buffer[offset + TransformOffsets.z] = z;
  }

  void setRotation(double qx, double qy, double qz, double qw) {
    buffer[offset + TransformOffsets.qx] = qx;
    buffer[offset + TransformOffsets.qy] = qy;
    buffer[offset + TransformOffsets.qz] = qz;
    buffer[offset + TransformOffsets.qw] = qw;
  }

  void setScale(double sx, double sy, double sz) {
    buffer[offset + TransformOffsets.sx] = sx;
    buffer[offset + TransformOffsets.sy] = sy;
    buffer[offset + TransformOffsets.sz] = sz;
  }
}

/// Contiguous [Float32List] component storage for 3D Transforms with 16-float stride per entity.
class TransformStorage extends TypedComponentStorage {
  /// Creates a [TransformStorage] with [TransformOffsets.stride] (16 floats per entity).
  TransformStorage({
    super.initialCapacity = 64,
    super.initialSparseCapacity = 256,
  }) : super(stride: TransformOffsets.stride);

  /// Sets or updates the transform component for [entity].
  ///
  /// Allocates space if not present. Default rotation is identity `(0,0,0,1)`
  /// and default scale is identity `(1,1,1)`.
  int set(
    Entity entity, {
    double x = 0.0,
    double y = 0.0,
    double z = 0.0,
    int flags = 0,
    double qx = 0.0,
    double qy = 0.0,
    double qz = 0.0,
    double qw = 1.0,
    double sx = 1.0,
    double sy = 1.0,
    double sz = 1.0,
    double reserved = 0.0,
    double boundsRadius = 0.0,
    double boundsCenterX = 0.0,
    double boundsCenterY = 0.0,
    double boundsCenterZ = 0.0,
  }) {
    final offset = allocate(entity);
    final buf = rawData;
    buf[offset + TransformOffsets.x] = x;
    buf[offset + TransformOffsets.y] = y;
    buf[offset + TransformOffsets.z] = z;
    buf[offset + TransformOffsets.flags] = flags.toDouble();
    buf[offset + TransformOffsets.qx] = qx;
    buf[offset + TransformOffsets.qy] = qy;
    buf[offset + TransformOffsets.qz] = qz;
    buf[offset + TransformOffsets.qw] = qw;
    buf[offset + TransformOffsets.sx] = sx;
    buf[offset + TransformOffsets.sy] = sy;
    buf[offset + TransformOffsets.sz] = sz;
    buf[offset + TransformOffsets.reserved] = reserved;
    buf[offset + TransformOffsets.boundsRadius] = boundsRadius;
    buf[offset + TransformOffsets.boundsCenterX] = boundsCenterX;
    buf[offset + TransformOffsets.boundsCenterY] = boundsCenterY;
    buf[offset + TransformOffsets.boundsCenterZ] = boundsCenterZ;
    return offset;
  }

  /// Sets transform fields from an existing [TransformComponent] object.
  int setComponent(Entity entity, TransformComponent component) {
    final offset = allocate(entity);
    component.writeToBuffer(rawData, offset);
    return offset;
  }

  /// Retrieves a [TransformComponent] representing [entity]'s transform,
  /// or `null` if the entity has no transform component.
  TransformComponent? getComponent(Entity entity) {
    final offset = getOffset(entity);
    if (offset < 0) return null;
    return TransformComponent.fromBuffer(rawData, offset);
  }

  /// Returns a zero-allocation in-place view into [entity]'s transform data,
  /// or `null` if the entity has no transform component.
  TransformView? getView(Entity entity) {
    final offset = getOffset(entity);
    if (offset < 0) return null;
    return TransformView(rawData, offset);
  }

  // --- Individual Float Getters ---

  double getX(Entity entity) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    return rawData[offset + TransformOffsets.x];
  }

  double getY(Entity entity) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    return rawData[offset + TransformOffsets.y];
  }

  double getZ(Entity entity) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    return rawData[offset + TransformOffsets.z];
  }

  int getFlags(Entity entity) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    return rawData[offset + TransformOffsets.flags].toInt();
  }

  double getQx(Entity entity) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    return rawData[offset + TransformOffsets.qx];
  }

  double getQy(Entity entity) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    return rawData[offset + TransformOffsets.qy];
  }

  double getQz(Entity entity) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    return rawData[offset + TransformOffsets.qz];
  }

  double getQw(Entity entity) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    return rawData[offset + TransformOffsets.qw];
  }

  double getSx(Entity entity) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    return rawData[offset + TransformOffsets.sx];
  }

  double getSy(Entity entity) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    return rawData[offset + TransformOffsets.sy];
  }

  double getSz(Entity entity) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    return rawData[offset + TransformOffsets.sz];
  }

  double getBoundsRadius(Entity entity) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    return rawData[offset + TransformOffsets.boundsRadius];
  }

  // --- Individual Float Setters ---

  void setX(Entity entity, double value) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    rawData[offset + TransformOffsets.x] = value;
  }

  void setY(Entity entity, double value) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    rawData[offset + TransformOffsets.y] = value;
  }

  void setZ(Entity entity, double value) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    rawData[offset + TransformOffsets.z] = value;
  }

  void setTranslation(Entity entity, double x, double y, double z) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    rawData[offset + TransformOffsets.x] = x;
    rawData[offset + TransformOffsets.y] = y;
    rawData[offset + TransformOffsets.z] = z;
  }

  void setRotation(Entity entity, double qx, double qy, double qz, double qw) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    rawData[offset + TransformOffsets.qx] = qx;
    rawData[offset + TransformOffsets.qy] = qy;
    rawData[offset + TransformOffsets.qz] = qz;
    rawData[offset + TransformOffsets.qw] = qw;
  }

  void setScale(Entity entity, double sx, double sy, double sz) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    rawData[offset + TransformOffsets.sx] = sx;
    rawData[offset + TransformOffsets.sy] = sy;
    rawData[offset + TransformOffsets.sz] = sz;
  }

  void setUniformScale(Entity entity, double scale) {
    setScale(entity, scale, scale, scale);
  }

  void setFlags(Entity entity, int flags) {
    final offset = getOffset(entity);
    if (offset < 0) throw StateError('Entity $entity has no transform component');
    rawData[offset + TransformOffsets.flags] = flags.toDouble();
  }

  bool isDirty(Entity entity) {
    return (getFlags(entity) & TransformFlags.dirty) != 0;
  }

  void setDirty(Entity entity, bool dirty) {
    final flags = getFlags(entity);
    if (dirty) {
      setFlags(entity, flags | TransformFlags.dirty);
    } else {
      setFlags(entity, flags & ~TransformFlags.dirty);
    }
  }
}
