import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:path/path.dart' as p;

/// Represents a compiled 3D mesh extracted from a glTF container.
class CompiledMesh {
  final String name;
  final int vertexCount;
  final int indexCount;
  final Float32List positions;
  final Float32List normals;
  final Float32List uvs;
  final Uint32List indices;
  final List<double> minBounds;
  final List<double> maxBounds;

  CompiledMesh({
    required this.name,
    required this.vertexCount,
    required this.indexCount,
    required this.positions,
    required this.normals,
    required this.uvs,
    required this.indices,
    required this.minBounds,
    required this.maxBounds,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'vertexCount': vertexCount,
        'indexCount': indexCount,
        'minBounds': minBounds,
        'maxBounds': maxBounds,
      };
}

/// Result of compiling glTF content.
class GltfCompileResult {
  final List<CompiledMesh> meshes;
  final Map<String, dynamic> metadata;

  GltfCompileResult({
    required this.meshes,
    required this.metadata,
  });
}

/// Pure-Dart glTF 2.0 parser extracting vertex positions, normals, UVs, and indices.
class GltfCompiler {
  /// Compiles a .gltf file from disk.
  static Future<GltfCompileResult> compileFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('glTF file not found', filePath);
    }

    final content = await file.readAsString();
    final baseDir = file.parent.path;
    return compileString(content, baseDir: baseDir);
  }

  /// Compiles a glTF JSON string with optional base directory for relative buffer resolution.
  static GltfCompileResult compileString(String jsonString, {String? baseDir}) {
    final Map<String, dynamic> json = jsonDecode(jsonString) as Map<String, dynamic>;
    return compileJson(json, baseDir: baseDir);
  }

  /// Compiles from parsed glTF JSON Map.
  static GltfCompileResult compileJson(
    Map<String, dynamic> json, {
    String? baseDir,
    Uint8List? directBuffer,
  }) {
    final buffersData = _loadBuffers(json, baseDir: baseDir, directBuffer: directBuffer);
    final bufferViews = (json['bufferViews'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final accessors = (json['accessors'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final meshesRaw = (json['meshes'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    final List<CompiledMesh> compiledMeshes = [];

    for (int meshIndex = 0; meshIndex < meshesRaw.length; meshIndex++) {
      final meshDef = meshesRaw[meshIndex];
      final meshName = (meshDef['name'] as String?) ?? 'mesh_$meshIndex';
      final primitives = (meshDef['primitives'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

      for (int primIndex = 0; primIndex < primitives.length; primIndex++) {
        final prim = primitives[primIndex];
        final attributes = (prim['attributes'] as Map<String, dynamic>? ?? {});
        final String primMeshName = primitives.length == 1 ? meshName : '${meshName}_prim$primIndex';

        // 1. Positions (REQUIRED)
        final posAccessorIdx = attributes['POSITION'] as int?;
        if (posAccessorIdx == null) {
          continue; // Skip primitives without position
        }

        final posAccessor = accessors[posAccessorIdx];
        final positions = _readFloat32Accessor(posAccessor, bufferViews, buffersData, expectedComponents: 3);
        final vertexCount = positions.length ~/ 3;

        // Bounding box
        List<double> minBounds;
        List<double> maxBounds;
        if (posAccessor['min'] != null && posAccessor['max'] != null) {
          minBounds = (posAccessor['min'] as List<dynamic>).map((e) => (e as num).toDouble()).toList();
          maxBounds = (posAccessor['max'] as List<dynamic>).map((e) => (e as num).toDouble()).toList();
        } else {
          minBounds = _calculateMinBounds(positions);
          maxBounds = _calculateMaxBounds(positions);
        }

        // 2. Indices
        Uint32List indices;
        final indicesAccessorIdx = prim['indices'] as int?;
        if (indicesAccessorIdx != null) {
          final indicesAccessor = accessors[indicesAccessorIdx];
          indices = _readIndicesAccessor(indicesAccessor, bufferViews, buffersData);
        } else {
          // Generate sequential triangle indices
          indices = Uint32List(vertexCount);
          for (int i = 0; i < vertexCount; i++) {
            indices[i] = i;
          }
        }

        // 3. Normals
        Float32List normals;
        final normalAccessorIdx = attributes['NORMAL'] as int?;
        if (normalAccessorIdx != null) {
          final normAccessor = accessors[normalAccessorIdx];
          normals = _readFloat32Accessor(normAccessor, bufferViews, buffersData, expectedComponents: 3);
        } else {
          // Generate flat/smooth normals from positions & indices
          normals = _generateNormals(positions, indices, vertexCount);
        }

        // 4. UVs (TEXCOORD_0)
        Float32List uvs;
        final uvAccessorIdx = attributes['TEXCOORD_0'] as int?;
        if (uvAccessorIdx != null) {
          final uvAccessor = accessors[uvAccessorIdx];
          uvs = _readFloat32Accessor(uvAccessor, bufferViews, buffersData, expectedComponents: 2);
        } else {
          // Default zero UVs
          uvs = Float32List(vertexCount * 2);
        }

        compiledMeshes.add(CompiledMesh(
          name: primMeshName,
          vertexCount: vertexCount,
          indexCount: indices.length,
          positions: positions,
          normals: normals,
          uvs: uvs,
          indices: indices,
          minBounds: minBounds,
          maxBounds: maxBounds,
        ));
      }
    }

    final metadata = {
      'asset': json['asset'] ?? {'version': '2.0'},
      'meshCount': compiledMeshes.length,
      'scenes': json['scenes'],
      'nodes': json['nodes'],
    };

    return GltfCompileResult(
      meshes: compiledMeshes,
      metadata: metadata,
    );
  }

  /// Loads buffer binary blobs from data URIs, files, or direct buffer.
  static List<Uint8List> _loadBuffers(
    Map<String, dynamic> json, {
    String? baseDir,
    Uint8List? directBuffer,
  }) {
    final buffersRaw = (json['buffers'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final List<Uint8List> buffers = [];

    for (int i = 0; i < buffersRaw.length; i++) {
      final bufferDef = buffersRaw[i];
      final uri = bufferDef['uri'] as String?;

      if (uri == null) {
        if (directBuffer != null && i == 0) {
          buffers.add(directBuffer);
        } else {
          throw FormatException('Buffer at index $i missing URI and no direct buffer provided.');
        }
        continue;
      }

      if (uri.startsWith('data:')) {
        // Data URI: data:application/octet-stream;base64,...
        final commaIndex = uri.indexOf(',');
        if (commaIndex == -1) {
          throw FormatException('Invalid data URI in glTF buffer $i');
        }
        final base64String = uri.substring(commaIndex + 1);
        final decoded = base64Decode(base64String);
        buffers.add(decoded);
      } else {
        // Relative file path
        if (baseDir == null) {
          throw FormatException('Cannot resolve relative buffer URI "$uri" without baseDir.');
        }
        final bufferPath = p.isAbsolute(uri) ? uri : p.join(baseDir, uri);
        final bufferFile = File(bufferPath);
        if (!bufferFile.existsSync()) {
          throw FileSystemException('glTF buffer file not found', bufferPath);
        }
        buffers.add(bufferFile.readAsBytesSync());
      }
    }

    return buffers;
  }

  /// Reads Float32List from an accessor.
  static Float32List _readFloat32Accessor(
    Map<String, dynamic> accessor,
    List<Map<String, dynamic>> bufferViews,
    List<Uint8List> buffers, {
    required int expectedComponents,
  }) {
    final count = accessor['count'] as int;
    final bufferViewIdx = accessor['bufferView'] as int?;
    final accessorByteOffset = (accessor['byteOffset'] as int?) ?? 0;
    final componentType = accessor['componentType'] as int;

    if (componentType != 5126) {
      throw FormatException('Expected float32 componentType (5126), got $componentType');
    }

    if (bufferViewIdx == null) {
      // In glTF, accessor without bufferView means all zeros
      return Float32List(count * expectedComponents);
    }

    final bufferView = bufferViews[bufferViewIdx];
    final bufferIdx = bufferView['buffer'] as int;
    final viewByteOffset = (bufferView['byteOffset'] as int?) ?? 0;
    final byteStride = bufferView['byteStride'] as int?;

    final buffer = buffers[bufferIdx];
    final startOffset = viewByteOffset + accessorByteOffset;
    final stride = byteStride ?? (expectedComponents * 4);

    final result = Float32List(count * expectedComponents);
    final byteData = ByteData.sublistView(buffer);

    for (int i = 0; i < count; i++) {
      final elemOffset = startOffset + (i * stride);
      for (int c = 0; c < expectedComponents; c++) {
        result[i * expectedComponents + c] = byteData.getFloat32(elemOffset + (c * 4), Endian.little);
      }
    }

    return result;
  }

  /// Reads index buffer as Uint32List (converting from uint8 or uint16 if needed).
  static Uint32List _readIndicesAccessor(
    Map<String, dynamic> accessor,
    List<Map<String, dynamic>> bufferViews,
    List<Uint8List> buffers,
  ) {
    final count = accessor['count'] as int;
    final bufferViewIdx = accessor['bufferView'] as int?;
    final accessorByteOffset = (accessor['byteOffset'] as int?) ?? 0;
    final componentType = accessor['componentType'] as int;

    if (bufferViewIdx == null) {
      final seq = Uint32List(count);
      for (int i = 0; i < count; i++) {
        seq[i] = i;
      }
      return seq;
    }

    final bufferView = bufferViews[bufferViewIdx];
    final bufferIdx = bufferView['buffer'] as int;
    final viewByteOffset = (bufferView['byteOffset'] as int?) ?? 0;
    final byteStride = bufferView['byteStride'] as int?;

    final buffer = buffers[bufferIdx];
    final startOffset = viewByteOffset + accessorByteOffset;
    final byteData = ByteData.sublistView(buffer);
    final result = Uint32List(count);

    switch (componentType) {
      case 5121: // UNSIGNED_BYTE
        final stride = byteStride ?? 1;
        for (int i = 0; i < count; i++) {
          result[i] = byteData.getUint8(startOffset + (i * stride));
        }
        break;
      case 5123: // UNSIGNED_SHORT
        final stride = byteStride ?? 2;
        for (int i = 0; i < count; i++) {
          result[i] = byteData.getUint16(startOffset + (i * stride), Endian.little);
        }
        break;
      case 5125: // UNSIGNED_INT
        final stride = byteStride ?? 4;
        for (int i = 0; i < count; i++) {
          result[i] = byteData.getUint32(startOffset + (i * stride), Endian.little);
        }
        break;
      default:
        throw FormatException('Unsupported index componentType $componentType');
    }

    return result;
  }

  /// Computes vertex normals from positions and indices.
  static Float32List _generateNormals(Float32List positions, Uint32List indices, int vertexCount) {
    final normals = Float32List(vertexCount * 3);

    for (int i = 0; i < indices.length; i += 3) {
      if (i + 2 >= indices.length) break;
      final i0 = indices[i];
      final i1 = indices[i + 1];
      final i2 = indices[i + 2];

      final p0x = positions[i0 * 3];
      final p0y = positions[i0 * 3 + 1];
      final p0z = positions[i0 * 3 + 2];

      final p1x = positions[i1 * 3];
      final p1y = positions[i1 * 3 + 1];
      final p1z = positions[i1 * 3 + 2];

      final p2x = positions[i2 * 3];
      final p2y = positions[i2 * 3 + 1];
      final p2z = positions[i2 * 3 + 2];

      // Edge vectors
      final e1x = p1x - p0x;
      final e1y = p1y - p0y;
      final e1z = p1z - p0z;

      final e2x = p2x - p0x;
      final e2y = p2y - p0y;
      final e2z = p2z - p0z;

      // Cross product e1 x e2
      final nx = e1y * e2z - e1z * e2y;
      final ny = e1z * e2x - e1x * e2z;
      final nz = e1x * e2y - e1y * e2x;

      normals[i0 * 3] += nx;
      normals[i0 * 3 + 1] += ny;
      normals[i0 * 3 + 2] += nz;

      normals[i1 * 3] += nx;
      normals[i1 * 3 + 1] += ny;
      normals[i1 * 3 + 2] += nz;

      normals[i2 * 3] += nx;
      normals[i2 * 3 + 1] += ny;
      normals[i2 * 3 + 2] += nz;
    }

    // Normalize
    for (int v = 0; v < vertexCount; v++) {
      final nx = normals[v * 3];
      final ny = normals[v * 3 + 1];
      final nz = normals[v * 3 + 2];
      final len = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (len > 0.000001) {
        normals[v * 3] = nx / len;
        normals[v * 3 + 1] = ny / len;
        normals[v * 3 + 2] = nz / len;
      } else {
        normals[v * 3] = 0.0;
        normals[v * 3 + 1] = 1.0;
        normals[v * 3 + 2] = 0.0;
      }
    }

    return normals;
  }

  static List<double> _calculateMinBounds(Float32List positions) {
    if (positions.isEmpty) return [-1.0, -1.0, -1.0];
    double minX = positions[0];
    double minY = positions[1];
    double minZ = positions[2];
    for (int i = 3; i < positions.length; i += 3) {
      if (positions[i] < minX) minX = positions[i];
      if (positions[i + 1] < minY) minY = positions[i + 1];
      if (positions[i + 2] < minZ) minZ = positions[i + 2];
    }
    return [minX, minY, minZ];
  }

  static List<double> _calculateMaxBounds(Float32List positions) {
    if (positions.isEmpty) return [1.0, 1.0, 1.0];
    double maxX = positions[0];
    double maxY = positions[1];
    double maxZ = positions[2];
    for (int i = 3; i < positions.length; i += 3) {
      if (positions[i] > maxX) maxX = positions[i];
      if (positions[i + 1] > maxY) maxY = positions[i + 1];
      if (positions[i + 2] > maxZ) maxZ = positions[i + 2];
    }
    return [maxX, maxY, maxZ];
  }
}
