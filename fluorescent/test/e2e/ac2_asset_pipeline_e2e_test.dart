import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../../tools/asset_pipeline/bin/asset_pipeline.dart' as cli;
import '../../tools/asset_pipeline/lib/fworld_writer.dart';
import 'e2e_test_harness.dart';

/// Constructs a valid GLTF 2.0 JSON string containing embedded base64 triangle mesh data.
String createTestGltfJson() {
  final positions = Float32List.fromList([
    0.0, 1.0, 0.0,
    -1.0, -1.0, 0.0,
    1.0, -1.0, 0.0,
  ]);

  final normals = Float32List.fromList([
    0.0, 0.0, 1.0,
    0.0, 0.0, 1.0,
    0.0, 0.0, 1.0,
  ]);

  final uvs = Float32List.fromList([
    0.5, 1.0,
    0.0, 0.0,
    1.0, 0.0,
  ]);

  final indices = Uint16List.fromList([0, 1, 2]);

  final totalByteLength = positions.lengthInBytes +
      normals.lengthInBytes +
      uvs.lengthInBytes +
      indices.lengthInBytes;

  final combinedBytes = Uint8List(totalByteLength);
  final byteData = ByteData.view(combinedBytes.buffer);

  int offset = 0;
  // Positions
  for (int i = 0; i < positions.length; i++) {
    byteData.setFloat32(offset, positions[i], Endian.little);
    offset += 4;
  }
  final posOffset = 0;
  final posLen = positions.lengthInBytes;

  // Normals
  final normOffset = offset;
  for (int i = 0; i < normals.length; i++) {
    byteData.setFloat32(offset, normals[i], Endian.little);
    offset += 4;
  }
  final normLen = normals.lengthInBytes;

  // UVs
  final uvOffset = offset;
  for (int i = 0; i < uvs.length; i++) {
    byteData.setFloat32(offset, uvs[i], Endian.little);
    offset += 4;
  }
  final uvLen = uvs.lengthInBytes;

  // Indices
  final indOffset = offset;
  for (int i = 0; i < indices.length; i++) {
    byteData.setUint16(offset, indices[i], Endian.little);
    offset += 2;
  }
  final indLen = indices.lengthInBytes;

  final b64Buffer = base64Encode(combinedBytes);

  final gltfMap = {
    'asset': {'version': '2.0', 'generator': 'FluorescentTestHarness'},
    'buffers': [
      {
        'byteLength': totalByteLength,
        'uri': 'data:application/octet-stream;base64,$b64Buffer',
      }
    ],
    'bufferViews': [
      {'buffer': 0, 'byteOffset': posOffset, 'byteLength': posLen, 'target': 34962},
      {'buffer': 0, 'byteOffset': normOffset, 'byteLength': normLen, 'target': 34962},
      {'buffer': 0, 'byteOffset': uvOffset, 'byteLength': uvLen, 'target': 34962},
      {'buffer': 0, 'byteOffset': indOffset, 'byteLength': indLen, 'target': 34963},
    ],
    'accessors': [
      {
        'bufferView': 0,
        'byteOffset': 0,
        'componentType': 5126, // FLOAT
        'count': 3,
        'type': 'VEC3',
        'max': [1.0, 1.0, 0.0],
        'min': [-1.0, -1.0, 0.0],
      },
      {
        'bufferView': 1,
        'byteOffset': 0,
        'componentType': 5126, // FLOAT
        'count': 3,
        'type': 'VEC3',
      },
      {
        'bufferView': 2,
        'byteOffset': 0,
        'componentType': 5126, // FLOAT
        'count': 3,
        'type': 'VEC2',
      },
      {
        'bufferView': 3,
        'byteOffset': 0,
        'componentType': 5123, // UNSIGNED_SHORT
        'count': 3,
        'type': 'SCALAR',
      },
    ],
    'meshes': [
      {
        'name': 'TestTriangle',
        'primitives': [
          {
            'attributes': {
              'POSITION': 0,
              'NORMAL': 1,
              'TEXCOORD_0': 2,
            },
            'indices': 3,
            'mode': 4, // TRIANGLES
          }
        ]
      }
    ],
    'nodes': [
      {'mesh': 0, 'name': 'RootNode'}
    ],
    'scenes': [
      {
        'nodes': [0]
      }
    ],
    'scene': 0,
  };

  return jsonEncode(gltfMap);
}

const String testWgslShaderSource = '''
struct Uniforms {
    modelViewProjectionMatrix : mat4x4<f32>,
};

@group(0) @binding(0) var<uniform> uniforms : Uniforms;

struct VertexInput {
    @location(0) position : vec3<f32>,
    @location(1) normal : vec3<f32>,
    @location(2) uv : vec2<f32>,
};

struct VertexOutput {
    @builtin(position) clipPosition : vec4<f32>,
    @location(0) fragUV : vec2<f32>,
};

@vertex
fn vs_main(input : VertexInput) -> VertexOutput {
    var output : VertexOutput;
    output.clipPosition = uniforms.modelViewProjectionMatrix * vec4<f32>(input.position, 1.0);
    output.fragUV = input.uv;
    return output;
}

@fragment
fn fs_main(input : VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(input.fragUV.x, input.fragUV.y, 1.0, 1.0);
}
''';

void defineTests() {
  group('AC 2 & Pillar 3: Asset Pipeline CLI Tooling & .fworld Packaging', () {
    late Directory tempDir;
    late File gltfFile;
    late File shaderFile;
    late File outputFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fluorescent_e2e_asset_');
      gltfFile = File('${tempDir.path}/test_mesh.gltf');
      await gltfFile.writeAsString(createTestGltfJson());

      shaderFile = File('${tempDir.path}/test_shader.wgsl');
      await shaderFile.writeAsString(testWgslShaderSource);

      outputFile = File('${tempDir.path}/compiled_world.fworld');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('E2E-AC2-001: CLI compiles test .gltf and .wgsl into .fworld binary with exit code 0', () async {
      exitCode = 0;

      await cli.main([
        '--gltf', gltfFile.path,
        '--shader', shaderFile.path,
        '--output', outputFile.path,
        '--compress', 'zlib',
        '--name', 'E2ETestWorld',
      ]);

      expect(exitCode, equals(0));
      expect(await outputFile.exists(), isTrue);

      final fileSize = await outputFile.length();
      expect(fileSize, greaterThan(64));
    });

    test('E2E-AC2-002: Compiled .fworld binary adheres to FWLD specification and embeds valid assets', () async {
      exitCode = 0;
      await cli.main([
        '--gltf', gltfFile.path,
        '--shader', shaderFile.path,
        '--output', outputFile.path,
        '--compress', 'zlib',
        '--name', 'SpecificationTestWorld',
      ]);

      final bytes = await outputFile.readAsBytes();

      // Magic bytes verification ('F', 'W', 'L', 'D')
      expect(bytes[0], equals(0x46));
      expect(bytes[1], equals(0x57));
      expect(bytes[2], equals(0x4C));
      expect(bytes[3], equals(0x44));

      // Read and deserialize using engine FWorldReader
      final package = FWorldReader.readFromBytes(bytes);

      expect(package.manifest['worldName'], equals('SpecificationTestWorld'));
      expect(FWorldCompression.fromId(package.compressionType), equals(FWorldCompression.zlib));
      expect(package.meshes.length, equals(1));
      expect(package.shaders.length, equals(1));

      // Validate mesh geometry
      final mesh = package.meshes.first;
      expect(mesh.name, equals('TestTriangle'));
      expect(mesh.vertexCount, equals(3));
      expect(mesh.indexCount, equals(3));
      expect(mesh.positions.length, equals(9)); // 3 vertices * 3 coordinates
      expect(mesh.normals.length, equals(9));
      expect(mesh.uvs.length, equals(6));
      expect(mesh.indices.length, equals(3));

      // Validate shader bundle
      final shader = package.shaders.first;
      expect(shader.name, equals('test_shader'));
      expect(shader.vertexEntryPoint, equals('vs_main'));
      expect(shader.fragmentEntryPoint, equals('fs_main'));
      expect(shader.wgsl.contains('@vertex'), isTrue);

      // SPIR-V header check: standard magic 0x07230203
      expect(shader.spirvWords.isNotEmpty, isTrue);
      expect(shader.spirvWords[0], equals(0x07230203));

      // Metal Shading Language check
      expect(shader.msl.contains('vertex'), isTrue);
      expect(shader.msl.contains('fragment'), isTrue);
    });

    test('E2E-AC2-003: Asset Pipeline supports gzip and uncompressed packaging modes identically', () async {
      final gzipOut = File('${tempDir.path}/world_gzip.fworld');
      final noneOut = File('${tempDir.path}/world_none.fworld');

      // 1. GZIP mode
      exitCode = 0;
      await cli.main([
        '--gltf', gltfFile.path,
        '--shader', shaderFile.path,
        '--output', gzipOut.path,
        '--compress', 'gzip',
      ]);
      expect(exitCode, equals(0));
      final gzipPkg = FWorldReader.readFromBytes(await gzipOut.readAsBytes());
      expect(FWorldCompression.fromId(gzipPkg.compressionType), equals(FWorldCompression.gzip));
      expect(gzipPkg.meshes.length, equals(1));
      expect(gzipPkg.shaders.length, equals(1));

      // 2. NONE (uncompressed) mode
      exitCode = 0;
      await cli.main([
        '--gltf', gltfFile.path,
        '--shader', shaderFile.path,
        '--output', noneOut.path,
        '--compress', 'none',
      ]);
      expect(exitCode, equals(0));
      final nonePkg = FWorldReader.readFromBytes(await noneOut.readAsBytes());
      expect(FWorldCompression.fromId(nonePkg.compressionType), equals(FWorldCompression.none));
      expect(nonePkg.meshes.length, equals(1));
      expect(nonePkg.shaders.length, equals(1));

      // Uncompressed and gzip mesh data are bit-for-bit identical
      expect(gzipPkg.meshes.first.positions, equals(nonePkg.meshes.first.positions));
      expect(gzipPkg.meshes.first.indices, equals(nonePkg.meshes.first.indices));
    });

    test('E2E-AC2-004: CLI returns non-zero exit code when required inputs are missing or invalid', () async {
      exitCode = 0;

      // No arguments provided
      await cli.main([]);
      expect(exitCode, equals(1));

      // Non-existent gltf file
      exitCode = 0;
      await cli.main([
        '--gltf', '${tempDir.path}/non_existent_file.gltf',
        '--output', '${tempDir.path}/out.fworld',
      ]);
      expect(exitCode, equals(2));
    });
  });
}

Future<void> main() async {
  await runSuite('AC 2 & Pillar 3: Asset Pipeline CLI Tooling & .fworld Packaging', defineTests);
}
