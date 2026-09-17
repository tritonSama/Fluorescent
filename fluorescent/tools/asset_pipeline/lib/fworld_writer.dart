import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'gltf_compiler.dart';
import 'shader_toolchain/shader_transpiler.dart';

/// Supported compression algorithms for .fworld binary files.
enum FWorldCompression {
  none(0),
  gzip(1),
  zlib(2);

  final int id;
  const FWorldCompression(this.id);

  static FWorldCompression fromId(int id) {
    switch (id) {
      case 1:
        return FWorldCompression.gzip;
      case 2:
        return FWorldCompression.zlib;
      default:
        return FWorldCompression.none;
    }
  }
}

/// Binary serializer for the .fworld format.
class FWorldWriter {
  /// Magic bytes: 'F', 'W', 'L', 'D' (0x46, 0x57, 0x4C, 0x44)
  static const List<int> magicBytes = [0x46, 0x57, 0x4C, 0x44];
  static const int currentVersion = 1;

  /// Serializes meshes, shaders, and manifest metadata into a binary .fworld Uint8List.
  static Uint8List serialize({
    String worldName = 'DefaultWorld',
    List<CompiledMesh> meshes = const [],
    List<ShaderBundle> shaders = const [],
    Map<String, dynamic>? customMetadata,
    FWorldCompression compression = FWorldCompression.zlib,
  }) {
    // 1. Prepare Manifest TOC JSON
    final manifestMap = {
      'worldName': worldName,
      'generator': 'fluorescent_asset_pipeline',
      'version': currentVersion,
      'created': DateTime.now().toUtc().toIso8601String(),
      'meshCount': meshes.length,
      'shaderCount': shaders.length,
      'meshes': meshes.map((m) => m.toJson()).toList(),
      'shaders': shaders.map((s) => s.toJson()).toList(),
      if (customMetadata != null) 'metadata': customMetadata,
    };
    final manifestBytes = utf8.encode(jsonEncode(manifestMap));

    // 2. Build Uncompressed Payload
    final BytesBuilder payloadBuilder = BytesBuilder(copy: false);

    // [Manifest Chunk]
    final manifestHeader = ByteData(4)..setUint32(0, manifestBytes.length, Endian.little);
    payloadBuilder.add(manifestHeader.buffer.asUint8List());
    payloadBuilder.add(manifestBytes);

    // [Meshes Chunk]
    final meshCountHeader = ByteData(4)..setUint32(0, meshes.length, Endian.little);
    payloadBuilder.add(meshCountHeader.buffer.asUint8List());

    for (final mesh in meshes) {
      final nameBytes = utf8.encode(mesh.name);
      final meshHeader = ByteData(4 + 4 + 4)
        ..setUint32(0, nameBytes.length, Endian.little)
        ..setUint32(4, mesh.vertexCount, Endian.little)
        ..setUint32(8, mesh.indexCount, Endian.little);
      payloadBuilder.add(meshHeader.buffer.asUint8List());
      payloadBuilder.add(nameBytes);

      // Positions: Float32List (vertexCount * 3 * 4 bytes)
      payloadBuilder.add(mesh.positions.buffer.asUint8List(
        mesh.positions.offsetInBytes,
        mesh.positions.lengthInBytes,
      ));

      // Normals: Float32List (vertexCount * 3 * 4 bytes)
      payloadBuilder.add(mesh.normals.buffer.asUint8List(
        mesh.normals.offsetInBytes,
        mesh.normals.lengthInBytes,
      ));

      // UVs: Float32List (vertexCount * 2 * 4 bytes)
      payloadBuilder.add(mesh.uvs.buffer.asUint8List(
        mesh.uvs.offsetInBytes,
        mesh.uvs.lengthInBytes,
      ));

      // Indices: Uint32List (indexCount * 4 bytes)
      payloadBuilder.add(mesh.indices.buffer.asUint8List(
        mesh.indices.offsetInBytes,
        mesh.indices.lengthInBytes,
      ));

      // Bounds: 6 x float32 (minX, minY, minZ, maxX, maxY, maxZ)
      final boundsData = ByteData(24);
      for (int b = 0; b < 3; b++) {
        boundsData.setFloat32(b * 4, mesh.minBounds.length > b ? mesh.minBounds[b] : -1.0, Endian.little);
        boundsData.setFloat32(12 + b * 4, mesh.maxBounds.length > b ? mesh.maxBounds[b] : 1.0, Endian.little);
      }
      payloadBuilder.add(boundsData.buffer.asUint8List());
    }

    // [Shaders Chunk]
    final shaderCountHeader = ByteData(4)..setUint32(0, shaders.length, Endian.little);
    payloadBuilder.add(shaderCountHeader.buffer.asUint8List());

    for (final shader in shaders) {
      final nameBytes = utf8.encode(shader.name);
      final vEntryBytes = utf8.encode(shader.vertexEntryPoint);
      final fEntryBytes = utf8.encode(shader.fragmentEntryPoint);
      final wgslBytes = utf8.encode(shader.wgsl);
      final mslBytes = utf8.encode(shader.msl);
      final spirvBytes = shader.spirvBytes;

      final shaderHeader = ByteData(24)
        ..setUint32(0, nameBytes.length, Endian.little)
        ..setUint32(4, vEntryBytes.length, Endian.little)
        ..setUint32(8, fEntryBytes.length, Endian.little)
        ..setUint32(12, wgslBytes.length, Endian.little)
        ..setUint32(16, mslBytes.length, Endian.little)
        ..setUint32(20, spirvBytes.length, Endian.little);

      payloadBuilder.add(shaderHeader.buffer.asUint8List());
      payloadBuilder.add(nameBytes);
      payloadBuilder.add(vEntryBytes);
      payloadBuilder.add(fEntryBytes);
      payloadBuilder.add(wgslBytes);
      payloadBuilder.add(mslBytes);
      payloadBuilder.add(spirvBytes);
    }

    final uncompressedPayload = payloadBuilder.takeBytes();
    final uncompressedSize = uncompressedPayload.length;

    // 3. Apply Compression
    List<int> compressedPayload;
    switch (compression) {
      case FWorldCompression.gzip:
        compressedPayload = gzip.encode(uncompressedPayload);
        break;
      case FWorldCompression.zlib:
        compressedPayload = zlib.encode(uncompressedPayload);
        break;
      case FWorldCompression.none:
        compressedPayload = uncompressedPayload;
        break;
    }

    // 4. Build File Header (16 bytes)
    // [0..3] Magic: FWLD
    // [4..7] Version: uint32
    // [8..11] Compression Type: uint32
    // [12..15] Uncompressed Size: uint32
    final fileHeader = ByteData(16);
    fileHeader.setUint8(0, magicBytes[0]);
    fileHeader.setUint8(1, magicBytes[1]);
    fileHeader.setUint8(2, magicBytes[2]);
    fileHeader.setUint8(3, magicBytes[3]);
    fileHeader.setUint32(4, currentVersion, Endian.little);
    fileHeader.setUint32(8, compression.id, Endian.little);
    fileHeader.setUint32(12, uncompressedSize, Endian.little);

    final finalBuilder = BytesBuilder(copy: false);
    finalBuilder.add(fileHeader.buffer.asUint8List());
    finalBuilder.add(compressedPayload);

    return finalBuilder.takeBytes();
  }

  /// Writes serialized .fworld binary directly to disk.
  static Future<File> writeToFile({
    required String outputPath,
    String worldName = 'DefaultWorld',
    List<CompiledMesh> meshes = const [],
    List<ShaderBundle> shaders = const [],
    Map<String, dynamic>? customMetadata,
    FWorldCompression compression = FWorldCompression.zlib,
  }) async {
    final bytes = serialize(
      worldName: worldName,
      meshes: meshes,
      shaders: shaders,
      customMetadata: customMetadata,
      compression: compression,
    );

    final file = File(outputPath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    return file.writeAsBytes(bytes, flush: true);
  }
}

/// Unpacked mesh data read from an .fworld binary package.
class UnpackedMesh {
  final String name;
  final int vertexCount;
  final int indexCount;
  final Float32List positions;
  final Float32List normals;
  final Float32List uvs;
  final Uint32List indices;
  final List<double> minBounds;
  final List<double> maxBounds;

  UnpackedMesh({
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

/// Unpacked shader data read from an .fworld binary package.
class UnpackedShader {
  final String name;
  final String vertexEntryPoint;
  final String fragmentEntryPoint;
  final String wgsl;
  final String msl;
  final Uint8List spirv;

  UnpackedShader({
    required this.name,
    required this.vertexEntryPoint,
    required this.fragmentEntryPoint,
    required this.wgsl,
    required this.msl,
    required this.spirv,
  });

  Uint32List get spirvWords => Uint32List.view(
        spirv.buffer,
        spirv.offsetInBytes,
        spirv.lengthInBytes ~/ 4,
      );
}

/// In-memory representation of an unpacked .fworld package.
class UnpackedFWorldPackage {
  final int version;
  final int compressionType;
  final int uncompressedSize;
  final Map<String, dynamic> manifest;
  final List<UnpackedMesh> meshes;
  final List<UnpackedShader> shaders;

  UnpackedFWorldPackage({
    required this.version,
    required this.compressionType,
    required this.uncompressedSize,
    required this.manifest,
    required this.meshes,
    required this.shaders,
  });
}

/// Deserializer for .fworld binary files.
class FWorldReader {
  /// Loads and unpacks an .fworld binary file from disk.
  static Future<UnpackedFWorldPackage> readFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('.fworld file not found', filePath);
    }
    final bytes = await file.readAsBytes();
    return readFromBytes(bytes);
  }

  /// Deserializes raw bytes of an .fworld binary file.
  static UnpackedFWorldPackage readFromBytes(Uint8List fileBytes) {
    if (fileBytes.length < 16) {
      throw const FormatException('Invalid .fworld data: File size is smaller than header (16 bytes).');
    }

    // Verify magic bytes
    if (fileBytes[0] != FWorldWriter.magicBytes[0] ||
        fileBytes[1] != FWorldWriter.magicBytes[1] ||
        fileBytes[2] != FWorldWriter.magicBytes[2] ||
        fileBytes[3] != FWorldWriter.magicBytes[3]) {
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

    // Decompress payload
    Uint8List payload;
    switch (compressionType) {
      case 1: // gzip
        payload = Uint8List.fromList(gzip.decode(payloadData));
        break;
      case 2: // zlib
        payload = Uint8List.fromList(zlib.decode(payloadData));
        break;
      case 0: // none
        payload = payloadData;
        break;
      default:
        throw FormatException('Unsupported .fworld compression type: $compressionType');
    }

    final reader = _ReaderHelper(payload);

    // 1. Manifest
    final manifestLength = reader.readUint32();
    final manifestBytes = reader.readBytes(manifestLength);
    final manifestStr = utf8.decode(manifestBytes);
    final manifest = jsonDecode(manifestStr) as Map<String, dynamic>;

    // 2. Meshes
    final meshCount = reader.readUint32();
    final List<UnpackedMesh> meshes = [];

    for (int i = 0; i < meshCount; i++) {
      final nameLength = reader.readUint32();
      final vertexCount = reader.readUint32();
      final indexCount = reader.readUint32();

      final nameBytes = reader.readBytes(nameLength);
      final name = utf8.decode(nameBytes);

      final positions = reader.readFloat32List(vertexCount * 3);
      final normals = reader.readFloat32List(vertexCount * 3);
      final uvs = reader.readFloat32List(vertexCount * 2);
      final indices = reader.readUint32List(indexCount);

      final boundsList = reader.readFloat32List(6);
      final minBounds = [boundsList[0], boundsList[1], boundsList[2]];
      final maxBounds = [boundsList[3], boundsList[4], boundsList[5]];

      meshes.add(UnpackedMesh(
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

    // 3. Shaders
    final shaderCount = reader.readUint32();
    final List<UnpackedShader> shaders = [];

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

      shaders.add(UnpackedShader(
        name: name,
        vertexEntryPoint: vEntry,
        fragmentEntryPoint: fEntry,
        wgsl: wgsl,
        msl: msl,
        spirv: spirvBytes,
      ));
    }

    return UnpackedFWorldPackage(
      version: version,
      compressionType: compressionType,
      uncompressedSize: uncompressedSize,
      manifest: manifest,
      meshes: meshes,
      shaders: shaders,
    );
  }
}

class _ReaderHelper {
  final Uint8List data;
  final ByteData byteData;
  int offset = 0;

  _ReaderHelper(this.data) : byteData = ByteData.sublistView(data);

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
