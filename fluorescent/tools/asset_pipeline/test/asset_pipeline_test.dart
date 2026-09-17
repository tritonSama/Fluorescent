import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';

import '../bin/asset_pipeline.dart' as cli;
import '../lib/fworld_writer.dart';
import '../lib/gltf_compiler.dart';
import '../lib/shader_toolchain/demo_transpiler.dart';
import '../lib/shader_toolchain/naga_ffi.dart';

/// Helper to generate a minimal valid glTF 2.0 JSON string with embedded base64 geometry buffer.
String createTestGltfJson({
  bool includeNormals = true,
  bool includeUvs = true,
  bool includeIndices = true,
}) {
  // Triangle with 3 vertices:
  // v0: (0.0, 1.0, 0.0), norm: (0.0, 0.0, 1.0), uv: (0.5, 1.0)
  // v1: (-1.0, -1.0, 0.0), norm: (0.0, 0.0, 1.0), uv: (0.0, 0.0)
  // v2: (1.0, -1.0, 0.0), norm: (0.0, 0.0, 1.0), uv: (1.0, 0.0)
  // indices: 0, 1, 2
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

  final bufferBuilder = BytesBuilder();
  // Buffer layout:
  // [0..35]: positions (3 * 3 * 4 = 36 bytes)
  final posOffset = bufferBuilder.length;
  bufferBuilder.add(positions.buffer.asUint8List());

  int? normOffset;
  if (includeNormals) {
    normOffset = bufferBuilder.length;
    bufferBuilder.add(normals.buffer.asUint8List());
  }

  int? uvOffset;
  if (includeUvs) {
    uvOffset = bufferBuilder.length;
    bufferBuilder.add(uvs.buffer.asUint8List());
  }

  int? idxOffset;
  if (includeIndices) {
    idxOffset = bufferBuilder.length;
    bufferBuilder.add(indices.buffer.asUint8List());
  }

  final rawBuffer = bufferBuilder.takeBytes();
  final base64Buffer = base64Encode(rawBuffer);

  final List<Map<String, dynamic>> bufferViews = [
    // bufferView 0: Positions
    {
      'buffer': 0,
      'byteOffset': posOffset,
      'byteLength': 36,
      'target': 34962, // ARRAY_BUFFER
    },
  ];

  final List<Map<String, dynamic>> accessors = [
    // accessor 0: Positions
    {
      'bufferView': 0,
      'byteOffset': 0,
      'componentType': 5126, // FLOAT
      'count': 3,
      'type': 'VEC3',
      'min': [-1.0, -1.0, 0.0],
      'max': [1.0, 1.0, 0.0],
    },
  ];

  final Map<String, dynamic> attributes = {
    'POSITION': 0,
  };

  if (includeNormals) {
    final normViewIdx = bufferViews.length;
    bufferViews.add({
      'buffer': 0,
      'byteOffset': normOffset!,
      'byteLength': 36,
      'target': 34962,
    });
    final normAccIdx = accessors.length;
    accessors.add({
      'bufferView': normViewIdx,
      'byteOffset': 0,
      'componentType': 5126,
      'count': 3,
      'type': 'VEC3',
    });
    attributes['NORMAL'] = normAccIdx;
  }

  if (includeUvs) {
    final uvViewIdx = bufferViews.length;
    bufferViews.add({
      'buffer': 0,
      'byteOffset': uvOffset!,
      'byteLength': 24,
      'target': 34962,
    });
    final uvAccIdx = accessors.length;
    accessors.add({
      'bufferView': uvViewIdx,
      'byteOffset': 0,
      'componentType': 5126,
      'count': 3,
      'type': 'VEC2',
    });
    attributes['TEXCOORD_0'] = uvAccIdx;
  }

  int? indicesAccIdx;
  if (includeIndices) {
    final idxViewIdx = bufferViews.length;
    bufferViews.add({
      'buffer': 0,
      'byteOffset': idxOffset!,
      'byteLength': 6,
      'target': 34963, // ELEMENT_ARRAY_BUFFER
    });
    indicesAccIdx = accessors.length;
    accessors.add({
      'bufferView': idxViewIdx,
      'byteOffset': 0,
      'componentType': 5123, // UNSIGNED_SHORT
      'count': 3,
      'type': 'SCALAR',
    });
  }

  final gltf = {
    'asset': {'version': '2.0', 'generator': 'fluorescent_test'},
    'buffers': [
      {
        'byteLength': rawBuffer.length,
        'uri': 'data:application/octet-stream;base64,$base64Buffer',
      }
    ],
    'bufferViews': bufferViews,
    'accessors': accessors,
    'meshes': [
      {
        'name': 'TestTriangle',
        'primitives': [
          {
            'attributes': attributes,
            if (indicesAccIdx != null) 'indices': indicesAccIdx,
            'mode': 4,
          }
        ],
      }
    ],
  };

  return jsonEncode(gltf);
}

const String testWgslSource = '''
struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vertexMain(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.clip_position = vec4<f32>(in.position, 1.0);
    out.uv = in.uv;
    return out;
}

@fragment
fn fragmentMain(in: VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(in.uv.x, in.uv.y, 0.5, 1.0);
}
''';

void main() {
  group('Pillar 2 & 4: Asset Pipeline & Shader Toolchain', () {
    test('GLTF compiler parses vertex positions, normals, UVs, and indices correctly', () {
      final gltfJson = createTestGltfJson();
      final result = GltfCompiler.compileString(gltfJson);

      expect(result.meshes, hasLength(1));
      final mesh = result.meshes.first;
      expect(mesh.name, equals('TestTriangle'));
      expect(mesh.vertexCount, equals(3));
      expect(mesh.indexCount, equals(3));

      // Positions: 3 vertices * 3 coords = 9 floats
      expect(mesh.positions, hasLength(9));
      expect(mesh.positions[0], closeTo(0.0, 0.001));
      expect(mesh.positions[1], closeTo(1.0, 0.001));
      expect(mesh.positions[2], closeTo(0.0, 0.001));

      // Normals: 3 vertices * 3 coords = 9 floats
      expect(mesh.normals, hasLength(9));
      expect(mesh.normals[2], closeTo(1.0, 0.001));

      // UVs: 3 vertices * 2 coords = 6 floats
      expect(mesh.uvs, hasLength(6));
      expect(mesh.uvs[0], closeTo(0.5, 0.001));
      expect(mesh.uvs[1], closeTo(1.0, 0.001));

      // Indices
      expect(mesh.indices, equals([0, 1, 2]));

      // Bounds
      expect(mesh.minBounds, equals([-1.0, -1.0, 0.0]));
      expect(mesh.maxBounds, equals([1.0, 1.0, 0.0]));
    });

    test('GLTF compiler synthesizes normals and sequential indices when omitted', () {
      final gltfJson = createTestGltfJson(includeNormals: false, includeIndices: false);
      final result = GltfCompiler.compileString(gltfJson);

      expect(result.meshes, hasLength(1));
      final mesh = result.meshes.first;
      expect(mesh.vertexCount, equals(3));
      expect(mesh.indexCount, equals(3));
      expect(mesh.indices, equals([0, 1, 2]));

      // Generated normals should be normalized and non-zero
      expect(mesh.normals, hasLength(9));
      final nz = mesh.normals[2];
      expect(nz.abs(), greaterThan(0.5));
    });

    test('DemoShaderTranspiler produces valid SPIR-V words with 0x07230203 magic and MSL', () {
      final transpiler = DemoShaderTranspiler();
      final bundle = transpiler.transpile(
        shaderName: 'basic_test',
        wgslSource: testWgslSource,
      );

      expect(bundle.name, equals('basic_test'));
      expect(bundle.vertexEntryPoint, equals('vertexMain'));
      expect(bundle.fragmentEntryPoint, equals('fragmentMain'));

      // Verify SPIR-V magic 0x07230203
      expect(bundle.spirvWords.isNotEmpty, isTrue);
      expect(bundle.spirvWords[0], equals(0x07230203));
      expect(bundle.spirvBytes.length, equals(bundle.spirvWords.length * 4));

      // Verify MSL generation
      expect(bundle.msl, contains('#include <metal_stdlib>'));
      expect(bundle.msl, contains('using namespace metal;'));
      expect(bundle.msl, contains('float4'));
      expect(bundle.msl, contains('vertex '));
      expect(bundle.msl, contains('fragment '));
      expect(bundle.msl, contains('[[position]]'));
    });

    test('NagaFfiTranspiler falls back to DemoShaderTranspiler when native library is absent', () {
      final transpiler = NagaFfiTranspiler();
      // On this host without native naga_ffi.dll, fallback is active
      expect(transpiler.isNativeAvailable, isFalse);
      expect(transpiler.usingFallback, isTrue);

      final bundle = transpiler.transpile(
        shaderName: 'fallback_shader',
        wgslSource: testWgslSource,
      );

      expect(bundle.name, equals('fallback_shader'));
      expect(bundle.spirvWords[0], equals(0x07230203));
      expect(bundle.msl, contains('#include <metal_stdlib>'));
    });

    test('FWorldWriter serializes and FWorldReader unpacks binary payload across compressions', () {
      final gltfJson = createTestGltfJson();
      final gltfRes = GltfCompiler.compileString(gltfJson);
      final transpiler = DemoShaderTranspiler();
      final shader = transpiler.transpile(shaderName: 'pbr', wgslSource: testWgslSource);

      for (final comp in [FWorldCompression.zlib, FWorldCompression.gzip, FWorldCompression.none]) {
        final binary = FWorldWriter.serialize(
          worldName: 'CompressTest_${comp.name}',
          meshes: gltfRes.meshes,
          shaders: [shader],
          compression: comp,
        );

        // Header check
        expect(binary[0], equals(0x46)); // 'F'
        expect(binary[1], equals(0x57)); // 'W'
        expect(binary[2], equals(0x4C)); // 'L'
        expect(binary[3], equals(0x44)); // 'D'

        // Unpack check
        final unpacked = FWorldReader.readFromBytes(binary);
        expect(unpacked.version, equals(1));
        expect(unpacked.compressionType, equals(comp.id));
        expect(unpacked.manifest['worldName'], equals('CompressTest_${comp.name}'));

        // Meshes
        expect(unpacked.meshes, hasLength(1));
        final m = unpacked.meshes.first;
        expect(m.name, equals('TestTriangle'));
        expect(m.vertexCount, equals(3));
        expect(m.indexCount, equals(3));
        expect(m.positions[1], closeTo(1.0, 0.001));
        expect(m.indices, equals([0, 1, 2]));

        // Shaders
        expect(unpacked.shaders, hasLength(1));
        final s = unpacked.shaders.first;
        expect(s.name, equals('pbr'));
        expect(s.spirvWords[0], equals(0x07230203));
        expect(s.msl, contains('vertex '));
      }
    });

    test('Asset Pipeline CLI compiles test .gltf and .wgsl into .fworld binary file', () async {
      final tempDir = await Directory.systemTemp.createTemp('fluorescent_test_');

      try {
        final gltfFile = File('${tempDir.path}${Platform.pathSeparator}test_model.gltf');
        await gltfFile.writeAsString(createTestGltfJson());

        final shaderFile = File('${tempDir.path}${Platform.pathSeparator}test_shader.wgsl');
        await shaderFile.writeAsString(testWgslSource);

        final outputFile = File('${tempDir.path}${Platform.pathSeparator}compiled_world.fworld');

        // Execute CLI entry point directly
        await cli.main([
          '--gltf',
          gltfFile.path,
          '--shader',
          shaderFile.path,
          '--output',
          outputFile.path,
          '--compress',
          'zlib',
          '--name',
          'UnitTestWorld',
        ]);

        expect(await outputFile.exists(), isTrue);
        final fileBytes = await outputFile.readAsBytes();
        expect(fileBytes.length, greaterThan(16));

        // Verify magic bytes: FWLD
        expect(fileBytes.sublist(0, 4), equals([0x46, 0x57, 0x4C, 0x44]));

        // Verify deserialization
        final unpacked = FWorldReader.readFromBytes(fileBytes);
        expect(unpacked.manifest['worldName'], equals('UnitTestWorld'));
        expect(unpacked.meshes, hasLength(1));
        expect(unpacked.meshes.first.name, equals('TestTriangle'));
        expect(unpacked.shaders, hasLength(1));
        expect(unpacked.shaders.first.name, equals('test_shader'));
        expect(unpacked.shaders.first.spirvWords[0], equals(0x07230203));
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('Asset Pipeline CLI runs successfully via sub-process execution', () async {
      final tempDir = await Directory.systemTemp.createTemp('fluorescent_cli_proc_');

      try {
        final gltfFile = File('${tempDir.path}${Platform.pathSeparator}proc_model.gltf');
        await gltfFile.writeAsString(createTestGltfJson());

        final shaderFile = File('${tempDir.path}${Platform.pathSeparator}proc_shader.wgsl');
        await shaderFile.writeAsString(testWgslSource);

        final outputFile = File('${tempDir.path}${Platform.pathSeparator}proc_world.fworld');

        final result = await Process.run(
          Platform.resolvedExecutable,
          [
            'run',
            'bin/asset_pipeline.dart',
            '--gltf',
            gltfFile.path,
            '--shader',
            shaderFile.path,
            '--output',
            outputFile.path,
          ],
          workingDirectory: Directory.current.path,
        );

        expect(result.exitCode, equals(0), reason: 'CLI failed with stderr: ${result.stderr}\nstdout: ${result.stdout}');
        expect(result.stdout, contains('Successfully generated .fworld package!'));

        expect(await outputFile.exists(), isTrue);
        final bytes = await outputFile.readAsBytes();
        expect(bytes.sublist(0, 4), equals([0x46, 0x57, 0x4C, 0x44]));
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
