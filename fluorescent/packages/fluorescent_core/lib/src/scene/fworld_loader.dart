import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'entity.dart';
import 'world_3d.dart';

/// Represents an unpacked 3D mesh from an .fworld package.
class FWorldMesh {
  final String name;
  final int vertexCount;
  final int indexCount;
  final Float32List positions;
  final Float32List normals;
  final Float32List uvs;
  final Uint32List indices;
  final List<double> minBounds;
  final List<double> maxBounds;

  FWorldMesh({
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
}

/// Represents an unpacked multi-target shader module from an .fworld package.
class FWorldShader {
  final String name;
  final String vertexEntryPoint;
  final String fragmentEntryPoint;
  final String wgsl;
  final String msl;
  final Uint8List spirv;

  FWorldShader({
    required this.name,
    required this.vertexEntryPoint,
    required this.fragmentEntryPoint,
    required this.wgsl,
    required this.msl,
    required this.spirv,
  });

  /// Convenient view of SPIR-V bytecode as 32-bit words.
  Uint32List get spirvWords => Uint32List.view(
        spirv.buffer,
        spirv.offsetInBytes,
        spirv.lengthInBytes ~/ 4,
      );
}

/// In-memory representation of an unpacked .fworld binary package.
class FWorldData {
  final int version;
  final int compressionType;
  final int uncompressedSize;
  final Map<String, dynamic> manifest;
  final List<FWorldMesh> meshes;
  final List<FWorldShader> shaders;

  FWorldData({
    required this.version,
    required this.compressionType,
    required this.uncompressedSize,
    required this.manifest,
    required this.meshes,
    required this.shaders,
  });

  /// Converts this [FWorldData] into an active [World3D] scene graph.
  World3D toWorld3D() {
    final worldName = (manifest['worldName'] as String?) ?? 'FWorld Scene';
    final List<Entity3D> entities = [];

    // Create an entity for each mesh in the world
    for (final mesh in meshes) {
      final entity = Entity3D(mesh.name);
      entities.add(entity);
    }

    return World3D(
      name: worldName,
      metadata: manifest,
      entities: entities,
      meshes: meshes,
      shaders: shaders,
    );
  }
}

/// Deserializer and loader for the .fworld binary container format.
class FWorldLoader {
  /// Expected magic bytes 'F', 'W', 'L', 'D'
  static const List<int> magicBytes = [0x46, 0x57, 0x4C, 0x44];

  /// Loads and unpacks an .fworld binary file from the local file system.
  static Future<FWorldData> loadFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('.fworld file not found', filePath);
    }
    final bytes = await file.readAsBytes();
    return loadFromBytes(bytes);
  }

  /// Deserializes .fworld binary content from raw [Uint8List] bytes.
  static FWorldData loadFromBytes(Uint8List fileBytes) {
    if (fileBytes.length < 16) {
      throw const FormatException('Invalid .fworld data: File size is smaller than header (16 bytes).');
    }

    // 1. Verify Magic Header
    if (fileBytes[0] != magicBytes[0] ||
        fileBytes[1] != magicBytes[1] ||
        fileBytes[2] != magicBytes[2] ||
        fileBytes[3] != magicBytes[3]) {
      throw FormatException(
        'Invalid .fworld magic header: expected [0x46, 0x57, 0x4C, 0x44] (FWLD), '
        'got [${fileBytes[0]}, ${fileBytes[1]}, ${fileBytes[2]}, ${fileBytes[3]}]',
      );
    }

    final headerData = ByteData.sublistView(fileBytes, 0, 16);
    final version = headerData.getUint32(4, Endian.little);
    final compressionType = headerData.getUint32(8, Endian.little);
    final uncompressedSize = headerData.getUint32(12, Endian.little);

    final payloadData = fileBytes.sublist(16);

    // 2. Decompress Payload
    Uint8List payload;
    switch (compressionType) {
      case 1: // gzip
        payload = Uint8List.fromList(gzip.decode(payloadData));
        break;
      case 2: // zlib
        payload = Uint8List.fromList(zlib.decode(payloadData));
        break;
      case 0: // uncompressed
        payload = payloadData;
        break;
      default:
        throw FormatException('Unsupported .fworld compression type: $compressionType');
    }

    if (uncompressedSize > 0 && payload.length != uncompressedSize) {
      // Warning or strict check: payload length should match uncompressedSize
    }

    final reader = _BinaryReader(payload);

    // 3. Manifest Chunk
    final manifestLength = reader.readUint32();
    final manifestBytes = reader.readBytes(manifestLength);
    final manifestStr = utf8.decode(manifestBytes);
    final manifest = jsonDecode(manifestStr) as Map<String, dynamic>;

    // 4. Mesh Chunks
    final meshCount = reader.readUint32();
    final List<FWorldMesh> meshes = [];

    for (int i = 0; i < meshCount; i++) {
      final nameLength = reader.readUint32();
      final vertexCount = reader.readUint32();
      final indexCount = reader.readUint32();

      final nameBytes = reader.readBytes(nameLength);
      final name = utf8.decode(nameBytes);

      // Positions: vertexCount * 3 floats (12 bytes per vertex)
      final positions = reader.readFloat32List(vertexCount * 3);

      // Normals: vertexCount * 3 floats
      final normals = reader.readFloat32List(vertexCount * 3);

      // UVs: vertexCount * 2 floats (8 bytes per vertex)
      final uvs = reader.readFloat32List(vertexCount * 2);

      // Indices: indexCount uint32s (4 bytes per index)
      final indices = reader.readUint32List(indexCount);

      // Bounds: 6 floats
      final boundsList = reader.readFloat32List(6);
      final minBounds = [boundsList[0], boundsList[1], boundsList[2]];
      final maxBounds = [boundsList[3], boundsList[4], boundsList[5]];

      meshes.add(FWorldMesh(
        name: name,
        vertexCount: vertexCount,
        indexCount: indexCount,
        positions: positions,
        normals: normals,
        uvs: uvs,
        indices: indices,
        minBounds: minBounds,
        maxBounds: maxBounds,
      ));
    }

    // 5. Shader Chunks
    final shaderCount = reader.readUint32();
    final List<FWorldShader> shaders = [];

    for (int i = 0; i < shaderCount; i++) {
      final nameLength = reader.readUint32();
      final vEntryLength = reader.readUint32();
      final fEntryLength = reader.readUint32();
      final wgslLength = reader.readUint32();
      final mslLength = reader.readUint32();
      final spirvByteLength = reader.readUint32();

      final name = utf8.decode(reader.readBytes(nameLength));
      final vEntry = utf8.decode(reader.readBytes(vEntryLength));
      final fEntry = utf8.decode(reader.readBytes(fEntryLength));
      final wgsl = utf8.decode(reader.readBytes(wgslLength));
      final msl = utf8.decode(reader.readBytes(mslLength));
      final spirvBytes = reader.readBytes(spirvByteLength);

      shaders.add(FWorldShader(
        name: name,
        vertexEntryPoint: vEntry,
        fragmentEntryPoint: fEntry,
        wgsl: wgsl,
        msl: msl,
        spirv: spirvBytes,
      ));
    }

    return FWorldData(
      version: version,
      compressionType: compressionType,
      uncompressedSize: uncompressedSize,
      manifest: manifest,
      meshes: meshes,
      shaders: shaders,
    );
  }

  /// Loads an .fworld package from file and instantiates a [World3D].
  static Future<World3D> loadWorld(String filePath) async {
    final data = await loadFromFile(filePath);
    return data.toWorld3D();
  }
}

class _BinaryReader {
  final Uint8List data;
  final ByteData byteData;
  int offset = 0;

  _BinaryReader(this.data) : byteData = ByteData.sublistView(data);

  int readUint32() {
    final val = byteData.getUint32(offset, Endian.little);
    offset += 4;
    return val;
  }

  Uint8List readBytes(int count) {
    final slice = data.sublist(offset, offset + count);
    offset += count;
    return slice;
  }

  Float32List readFloat32List(int count) {
    final result = Float32List(count);
    for (int i = 0; i < count; i++) {
      result[i] = byteData.getFloat32(offset, Endian.little);
      offset += 4;
    }
    return result;
  }

  Uint32List readUint32List(int count) {
    final result = Uint32List(count);
    for (int i = 0; i < count; i++) {
      result[i] = byteData.getUint32(offset, Endian.little);
      offset += 4;
    }
    return result;
  }
}
