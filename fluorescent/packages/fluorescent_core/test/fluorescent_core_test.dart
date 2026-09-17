import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluorescent_core/fluorescent_core.dart';

Uint8List createSampleFWorldBinary({
  String worldName = 'SampleWorld',
  int compressionType = 2, // zlib
}) {
  // Manifest
  final manifest = {
    'worldName': worldName,
    'generator': 'test',
    'version': 1,
    'meshCount': 1,
    'shaderCount': 1,
    'meshes': [
      {'name': 'Triangle', 'vertexCount': 3, 'indexCount': 3}
    ],
    'shaders': [
      {'name': 'Shader1', 'vertexEntryPoint': 'vs', 'fragmentEntryPoint': 'fs'}
    ],
  };
  final manifestBytes = utf8.encode(jsonEncode(manifest));

  final payloadBuilder = BytesBuilder();
  // Manifest length + bytes
  final mLen = ByteData(4)..setUint32(0, manifestBytes.length, Endian.little);
  payloadBuilder.add(mLen.buffer.asUint8List());
  payloadBuilder.add(manifestBytes);

  // Mesh count = 1
  final mCount = ByteData(4)..setUint32(0, 1, Endian.little);
  payloadBuilder.add(mCount.buffer.asUint8List());

  // Mesh 1: name "Triangle"
  final nameBytes = utf8.encode('Triangle');
  final mHeader = ByteData(12)
    ..setUint32(0, nameBytes.length, Endian.little)
    ..setUint32(4, 3, Endian.little) // 3 vertices
    ..setUint32(8, 3, Endian.little); // 3 indices
  payloadBuilder.add(mHeader.buffer.asUint8List());
  payloadBuilder.add(nameBytes);

  // Positions: 3 * 3 * 4 = 36 bytes
  final posData = Float32List.fromList([0.0, 1.0, 0.0, -1.0, -1.0, 0.0, 1.0, -1.0, 0.0]);
  payloadBuilder.add(posData.buffer.asUint8List());

  // Normals: 36 bytes
  final normData = Float32List.fromList([0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0]);
  payloadBuilder.add(normData.buffer.asUint8List());

  // UVs: 24 bytes
  final uvData = Float32List.fromList([0.5, 1.0, 0.0, 0.0, 1.0, 0.0]);
  payloadBuilder.add(uvData.buffer.asUint8List());

  // Indices: 3 * 4 = 12 bytes
  final idxData = Uint32List.fromList([0, 1, 2]);
  payloadBuilder.add(idxData.buffer.asUint8List());

  // Bounds: 6 floats = 24 bytes
  final boundsData = Float32List.fromList([-1.0, -1.0, 0.0, 1.0, 1.0, 0.0]);
  payloadBuilder.add(boundsData.buffer.asUint8List());

  // Shader count = 1
  final sCount = ByteData(4)..setUint32(0, 1, Endian.little);
  payloadBuilder.add(sCount.buffer.asUint8List());

  // Shader 1
  final sName = utf8.encode('Shader1');
  final vsName = utf8.encode('vs');
  final fsName = utf8.encode('fs');
  final wgslBytes = utf8.encode('@vertex fn vs() {}');
  final mslBytes = utf8.encode('vertex void vs() {}');
  final spirvBytes = Uint8List.fromList([0x03, 0x02, 0x23, 0x07, 0x00, 0x00, 0x01, 0x00]);

  final sHeader = ByteData(24)
    ..setUint32(0, sName.length, Endian.little)
    ..setUint32(4, vsName.length, Endian.little)
    ..setUint32(8, fsName.length, Endian.little)
    ..setUint32(12, wgslBytes.length, Endian.little)
    ..setUint32(16, mslBytes.length, Endian.little)
    ..setUint32(20, spirvBytes.length, Endian.little);
  payloadBuilder.add(sHeader.buffer.asUint8List());
  payloadBuilder.add(sName);
  payloadBuilder.add(vsName);
  payloadBuilder.add(fsName);
  payloadBuilder.add(wgslBytes);
  payloadBuilder.add(mslBytes);
  payloadBuilder.add(spirvBytes);

  final uncompressed = payloadBuilder.takeBytes();
  final compressed = compressionType == 2
      ? zlib.encode(uncompressed)
      : (compressionType == 1 ? gzip.encode(uncompressed) : uncompressed);

  // Header (16 bytes): FWLD, version 1, compressionType, uncompressed.length
  final fileHeader = ByteData(16)
    ..setUint8(0, 0x46)
    ..setUint8(1, 0x57)
    ..setUint8(2, 0x4C)
    ..setUint8(3, 0x44)
    ..setUint32(4, 1, Endian.little)
    ..setUint32(8, compressionType, Endian.little)
    ..setUint32(12, uncompressed.length, Endian.little);

  final result = BytesBuilder();
  result.add(fileHeader.buffer.asUint8List());
  result.add(compressed);
  return result.takeBytes();
}

void main() {
  test('FWorldLoader deserializes .fworld binary correctly', () {
    final binary = createSampleFWorldBinary(worldName: 'Arena3D');
    final data = FWorldLoader.loadFromBytes(binary);

    expect(data.version, equals(1));
    expect(data.compressionType, equals(2));
    expect(data.manifest['worldName'], equals('Arena3D'));
    expect(data.meshes, hasLength(1));
    expect(data.meshes.first.name, equals('Triangle'));
    expect(data.meshes.first.vertexCount, equals(3));
    expect(data.meshes.first.positions[1], closeTo(1.0, 0.001));
    expect(data.meshes.first.indices, equals([0, 1, 2]));

    expect(data.shaders, hasLength(1));
    expect(data.shaders.first.name, equals('Shader1'));
    expect(data.shaders.first.spirvWords[0], equals(0x07230203));
  });

  test('World3D.load automatically deserializes .fworld packages', () async {
    final tempDir = await Directory.systemTemp.createTemp('fworld_loader_test_');
    try {
      final fworldFile = File('${tempDir.path}${Platform.pathSeparator}test_scene.fworld');
      await fworldFile.writeAsBytes(createSampleFWorldBinary(worldName: 'DungeonLevel1'));

      final world = await World3D.load(fworldFile.path);
      expect(world.name, equals('DungeonLevel1'));
      expect(world.meshes, hasLength(1));
      expect(world.meshes.first.name, equals('Triangle'));
      expect(world.shaders, hasLength(1));
      expect(world.entities, hasLength(1));
      expect(world.entities.first.id, equals('Triangle'));
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });
}
