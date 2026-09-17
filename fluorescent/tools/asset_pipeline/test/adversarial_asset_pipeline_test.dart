import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';

import '../bin/asset_pipeline.dart' as cli;
import '../lib/fworld_writer.dart';
import '../lib/gltf_compiler.dart';
import '../lib/shader_toolchain/demo_transpiler.dart';
import '../lib/shader_toolchain/naga_ffi.dart';

/// Helper to generate a minimal valid glTF 2.0 JSON string.
String createTestGltfJson() {
  final positions = Float32List.fromList([
    0.0, 1.0, 0.0,
    -1.0, -1.0, 0.0,
    1.0, -1.0, 0.0,
  ]);
  final indices = Uint16List.fromList([0, 1, 2]);

  final bufferBuilder = BytesBuilder();
  bufferBuilder.add(positions.buffer.asUint8List());
  final idxOffset = bufferBuilder.length;
  bufferBuilder.add(indices.buffer.asUint8List());

  final rawBuffer = bufferBuilder.takeBytes();
  final base64Buffer = base64Encode(rawBuffer);

  final gltf = {
    'asset': {'version': '2.0'},
    'buffers': [
      {
        'byteLength': rawBuffer.length,
        'uri': 'data:application/octet-stream;base64,$base64Buffer',
      }
    ],
    'bufferViews': [
      {'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
      {'buffer': 0, 'byteOffset': idxOffset, 'byteLength': 6},
    ],
    'accessors': [
      {'bufferView': 0, 'byteOffset': 0, 'componentType': 5126, 'count': 3, 'type': 'VEC3'},
      {'bufferView': 1, 'byteOffset': 0, 'componentType': 5123, 'count': 3, 'type': 'SCALAR'},
    ],
    'meshes': [
      {
        'name': 'AdversarialTriangle',
        'primitives': [
          {'attributes': {'POSITION': 0}, 'indices': 1}
        ],
      }
    ],
  };

  return jsonEncode(gltf);
}

void main() {
  group('Adversarial Testing: GLTF Parsing & Resilience', () {
    test('malformed JSON throws FormatException cleanly', () {
      expect(
        () => GltfCompiler.compileString('{"asset": { "version": "2.0", incomplete...'),
        throwsFormatException,
      );
      expect(
        () => GltfCompiler.compileString('NOT_EVEN_JSON'),
        throwsFormatException,
      );
      expect(
        () => GltfCompiler.compileString(''),
        throwsFormatException,
      );
    });

    test('missing buffer URI without direct buffer throws FormatException', () {
      final invalidGltf = {
        'asset': {'version': '2.0'},
        'buffers': [
          {'byteLength': 100} // Missing 'uri'
        ],
        'meshes': [],
      };

      expect(
        () => GltfCompiler.compileJson(invalidGltf),
        throwsFormatException,
      );
    });

    test('malformed data URI throws FormatException', () {
      final invalidGltf = {
        'asset': {'version': '2.0'},
        'buffers': [
          {
            'byteLength': 100,
            'uri': 'data:application/octet-stream;invalid_no_comma',
          }
        ],
        'meshes': [],
      };

      expect(
        () => GltfCompiler.compileJson(invalidGltf),
        throwsFormatException,
      );
    });

    test('corrupted base64 payload in data URI throws FormatException', () {
      final invalidGltf = {
        'asset': {'version': '2.0'},
        'buffers': [
          {
            'byteLength': 100,
            'uri': 'data:application/octet-stream;base64,???not_valid_base64!!!',
          }
        ],
        'meshes': [],
      };

      expect(
        () => GltfCompiler.compileJson(invalidGltf),
        throwsFormatException,
      );
    });

    test('non-existent relative buffer file throws FileSystemException', () {
      final invalidGltf = {
        'asset': {'version': '2.0'},
        'buffers': [
          {
            'byteLength': 100,
            'uri': 'does_not_exist_buffer_12345.bin',
          }
        ],
        'meshes': [],
      };

      expect(
        () => GltfCompiler.compileJson(invalidGltf, baseDir: Directory.current.path),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('relative buffer URI without baseDir throws FormatException', () {
      final invalidGltf = {
        'asset': {'version': '2.0'},
        'buffers': [
          {
            'byteLength': 100,
            'uri': 'model.bin',
          }
        ],
        'meshes': [],
      };

      expect(
        () => GltfCompiler.compileJson(invalidGltf),
        throwsFormatException,
      );
    });

    test('out-of-bounds accessor index throws RangeError', () {
      final invalidGltf = {
        'asset': {'version': '2.0'},
        'buffers': [],
        'bufferViews': [],
        'accessors': [],
        'meshes': [
          {
            'name': 'BadMesh',
            'primitives': [
              {
                'attributes': {'POSITION': 999}
              }
            ],
          }
        ],
      };

      expect(
        () => GltfCompiler.compileJson(invalidGltf),
        throwsRangeError,
      );
    });

    test('accessor with invalid float componentType throws FormatException', () {
      final rawBuffer = Uint8List(36);
      final invalidGltf = {
        'asset': {'version': '2.0'},
        'buffers': [
          {'byteLength': 36, 'uri': 'data:application/octet-stream;base64,${base64Encode(rawBuffer)}'}
        ],
        'bufferViews': [
          {'buffer': 0, 'byteOffset': 0, 'byteLength': 36}
        ],
        'accessors': [
          {'bufferView': 0, 'componentType': 5120 /* BYTE, not FLOAT (5126) */, 'count': 3, 'type': 'VEC3'}
        ],
        'meshes': [
          {
            'primitives': [
              {
                'attributes': {'POSITION': 0}
              }
            ]
          }
        ],
      };

      expect(
        () => GltfCompiler.compileJson(invalidGltf),
        throwsFormatException,
      );
    });

    test('indices accessor with unsupported componentType throws FormatException', () {
      final rawBuffer = Uint8List(36);
      final invalidGltf = {
        'asset': {'version': '2.0'},
        'buffers': [
          {'byteLength': 36, 'uri': 'data:application/octet-stream;base64,${base64Encode(rawBuffer)}'}
        ],
        'bufferViews': [
          {'buffer': 0, 'byteOffset': 0, 'byteLength': 36}
        ],
        'accessors': [
          {'bufferView': 0, 'componentType': 5126, 'count': 3, 'type': 'VEC3'},
          {'bufferView': 0, 'componentType': 5126 /* FLOAT not allowed for indices */, 'count': 3, 'type': 'SCALAR'},
        ],
        'meshes': [
          {
            'primitives': [
              {
                'attributes': {'POSITION': 0},
                'indices': 1,
              }
            ]
          }
        ],
      };

      expect(
        () => GltfCompiler.compileJson(invalidGltf),
        throwsFormatException,
      );
    });

    test('primitive without POSITION is gracefully skipped without crash', () {
      final gltf = {
        'asset': {'version': '2.0'},
        'meshes': [
          {
            'name': 'NoPosMesh',
            'primitives': [
              {
                'attributes': {'NORMAL': 0}
              }
            ]
          }
        ],
      };

      final result = GltfCompiler.compileJson(gltf);
      expect(result.meshes, isEmpty);
    });

    test('empty glTF container parses to zero meshes gracefully', () {
      final gltf = {
        'asset': {'version': '2.0'},
      };
      final result = GltfCompiler.compileJson(gltf);
      expect(result.meshes, isEmpty);
      expect(result.metadata['asset']['version'], '2.0');
    });
  });

  group('Adversarial Testing: Shader Toolchain', () {
    final demoTranspiler = DemoShaderTranspiler();
    final ffiTranspiler = NagaFfiTranspiler();

    test('empty shader source compiles to fallback bundle without throwing', () {
      final bundle = demoTranspiler.transpile(
        shaderName: 'empty_shader',
        wgslSource: '',
      );

      expect(bundle.name, 'empty_shader');
      expect(bundle.spirvWords.isNotEmpty, isTrue);
      expect(bundle.spirvWords[0], 0x07230203);
      expect(bundle.msl, contains('#include <metal_stdlib>'));
    });

    test('whitespace-only and comments-only shader compiles gracefully', () {
      const commentShader = '''
      // Single line comment
      /* Multi-line
         comment */
         
      ''';
      final bundle = demoTranspiler.transpile(
        shaderName: 'comment_only',
        wgslSource: commentShader,
      );

      expect(bundle.name, 'comment_only');
      expect(bundle.spirvWords[0], 0x07230203);
      expect(bundle.msl, contains('#include <metal_stdlib>'));
    });

    test('complex shader with uniforms, storage, and multiple entry points', () {
      const complexWgsl = '''
      struct CameraUniforms {
          view_proj: mat4x4<f32>,
          inv_view: mat4x4<f32>,
          cam_pos: vec3<f32>,
          padding: f32,
      };

      struct LightData {
          color: vec4<f32>,
          position: vec3<f32>,
          intensity: f32,
      };

      @group(0) @binding(0) var<uniform> u_camera: CameraUniforms;
      @group(0) @binding(1) var<storage> s_lights: LightData;

      struct VertexInput {
          @location(0) position: vec3<f32>,
          @location(1) normal: vec3<f32>,
          @location(2) uv: vec2<f32>,
          @builtin(vertex_index) v_idx: u32,
          @builtin(instance_index) i_idx: u32,
      };

      struct VertexOutput {
          @builtin(position) position: vec4<f32>,
          @location(0) uv: vec2<f32>,
          @location(1) normal: vec3<f32>,
      };

      @vertex
      fn customVertexEntry(in: VertexInput) -> VertexOutput {
          var out: VertexOutput;
          out.position = u_camera.view_proj * vec4<f32>(in.position, 1.0);
          out.uv = in.uv;
          out.normal = in.normal;
          return out;
      }

      @fragment
      fn customFragmentEntry(in: VertexOutput) -> @location(0) vec4<f32> {
          let lightColor = s_lights.color * s_lights.intensity;
          return lightColor;
      }
      ''';

      final bundle = demoTranspiler.transpile(
        shaderName: 'complex_pbr',
        wgslSource: complexWgsl,
      );

      expect(bundle.name, 'complex_pbr');
      expect(bundle.vertexEntryPoint, 'customVertexEntry');
      expect(bundle.fragmentEntryPoint, 'customFragmentEntry');
      expect(bundle.spirvWords[0], 0x07230203);

      // Verify MSL translation of complex features
      expect(bundle.msl, contains('float4x4'));
      expect(bundle.msl, contains('float3'));
      expect(bundle.msl, contains('float2'));
      expect(bundle.msl, contains('[[buffer(0)]]'));
      expect(bundle.msl, contains('[[buffer(1)]]'));
      expect(bundle.msl, contains('[[position]]'));
      expect(bundle.msl, contains('[[vertex_id]]'));
      expect(bundle.msl, contains('[[instance_id]]'));
      expect(bundle.msl, contains('vertex VertexOutput customVertexEntry'));
      expect(bundle.msl, contains('fragment float4 customFragmentEntry'));
    });

    test('NagaFfiTranspiler handles fallback seamlessly on invalid library path', () {
      final invalidFfi = NagaFfiTranspiler(
        customLibraryPath: 'non_existent_naga_path_12345.dll',
      );

      expect(invalidFfi.isNativeAvailable, isFalse);
      expect(invalidFfi.usingFallback, isTrue);

      final bundle = invalidFfi.transpile(
        shaderName: 'fallback_test',
        wgslSource: '@vertex fn vs() {} @fragment fn fs() {}',
      );

      expect(bundle.name, 'fallback_test');
      expect(bundle.spirvWords[0], 0x07230203);
    });
  });

  group('Adversarial Testing: .fworld Corrupted Binary Handling', () {
    test('truncated file (< 16 bytes) throws FormatException', () {
      final zeroBytes = Uint8List(0);
      expect(
        () => FWorldReader.readFromBytes(zeroBytes),
        throwsFormatException,
      );

      final fiveBytes = Uint8List.fromList([0x46, 0x57, 0x4C, 0x44, 0x01]);
      expect(
        () => FWorldReader.readFromBytes(fiveBytes),
        throwsFormatException,
      );

      final fifteenBytes = Uint8List(15);
      expect(
        () => FWorldReader.readFromBytes(fifteenBytes),
        throwsFormatException,
      );
    });

    test('corrupted magic header throws FormatException', () {
      final badMagic = Uint8List(16);
      badMagic.setRange(0, 4, [0x58, 0x58, 0x58, 0x58]); // "XXXX" instead of "FWLD"

      expect(
        () => FWorldReader.readFromBytes(badMagic),
        throwsFormatException,
      );
    });

    test('one bit flipped in magic header throws FormatException', () {
      final badMagic = Uint8List(16);
      badMagic.setRange(0, 4, [0x46, 0x57, 0x4C, 0x45]); // "FWLE" instead of "FWLD"

      expect(
        () => FWorldReader.readFromBytes(badMagic),
        throwsFormatException,
      );
    });

    test('unsupported compression type throws FormatException', () {
      final valid = FWorldWriter.serialize(worldName: 'Test');
      final corrupted = Uint8List.fromList(valid);
      final byteData = ByteData.sublistView(corrupted);
      byteData.setUint32(8, 99, Endian.little); // Unsupported compression ID 99

      expect(
        () => FWorldReader.readFromBytes(corrupted),
        throwsFormatException,
      );
    });

    test('corrupted zlib payload throws exception cleanly without native crash', () {
      final valid = FWorldWriter.serialize(
        worldName: 'TestZlib',
        compression: FWorldCompression.zlib,
      );
      final corrupted = Uint8List.fromList(valid);

      // Overwrite compressed payload with random noise
      for (int i = 16; i < corrupted.length; i++) {
        corrupted[i] = (i * 37) % 256;
      }

      expect(
        () => FWorldReader.readFromBytes(corrupted),
        throwsA(anything),
      );
    });

    test('corrupted gzip payload throws exception cleanly without native crash', () {
      final valid = FWorldWriter.serialize(
        worldName: 'TestGzip',
        compression: FWorldCompression.gzip,
      );
      final corrupted = Uint8List.fromList(valid);

      // Overwrite compressed payload with random noise
      for (int i = 16; i < corrupted.length; i++) {
        corrupted[i] = 0xAA;
      }

      expect(
        () => FWorldReader.readFromBytes(corrupted),
        throwsA(anything),
      );
    });

    test('truncated payload data throws error cleanly without hang or crash', () {
      final valid = FWorldWriter.serialize(
        worldName: 'TestTruncated',
        compression: FWorldCompression.none,
      );

      // Keep header (16 bytes) + only 2 bytes of payload
      final truncated = valid.sublist(0, 18);

      expect(
        () => FWorldReader.readFromBytes(truncated),
        throwsA(anything),
      );
    });
  });

  group('Adversarial Testing: CLI Process Execution & Exit Codes', () {
    test('CLI fails with exitCode 1 when no gltf or shader provided', () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/asset_pipeline.dart'],
        workingDirectory: Directory.current.path,
      );

      expect(result.exitCode, 1);
      expect(result.stderr, contains('Error: At least one --gltf or --shader input must be provided'));
    });

    test('CLI fails with exitCode 1 when invalid arguments are passed', () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/asset_pipeline.dart', '--unknown-option-xyz'],
        workingDirectory: Directory.current.path,
      );

      expect(result.exitCode, 1);
      expect(result.stderr, contains('Error parsing arguments'));
    });

    test('CLI fails with exitCode 2 when gltf file does not exist', () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/asset_pipeline.dart', '--gltf', 'non_existent_file_xyz.gltf'],
        workingDirectory: Directory.current.path,
      );

      expect(result.exitCode, 2);
      expect(result.stderr, contains('Error compiling glTF'));
    });

    test('CLI fails with exitCode 3 when shader file does not exist', () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/asset_pipeline.dart', '--shader', 'non_existent_shader_xyz.wgsl'],
        workingDirectory: Directory.current.path,
      );

      expect(result.exitCode, 3);
      expect(result.stderr, contains('Error transpiling shader'));
    });

    test('CLI fails with exitCode 2 when gltf file contains corrupt syntax', () async {
      final tempDir = await Directory.systemTemp.createTemp('cli_adv_');
      try {
        final badGltf = File('${tempDir.path}${Platform.pathSeparator}bad.gltf');
        await badGltf.writeAsString('{"asset": corrupt_json...');

        final result = await Process.run(
          Platform.resolvedExecutable,
          ['run', 'bin/asset_pipeline.dart', '--gltf', badGltf.path],
          workingDirectory: Directory.current.path,
        );

        expect(result.exitCode, 2);
        expect(result.stderr, contains('Error compiling glTF'));
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('CLI compiles empty shader and minimal glTF successfully without crash', () async {
      final tempDir = await Directory.systemTemp.createTemp('cli_adv_ok_');
      try {
        final gltfFile = File('${tempDir.path}${Platform.pathSeparator}min.gltf');
        await gltfFile.writeAsString(createTestGltfJson());

        final shaderFile = File('${tempDir.path}${Platform.pathSeparator}empty.wgsl');
        await shaderFile.writeAsString(''); // Empty shader

        final outFile = File('${tempDir.path}${Platform.pathSeparator}adv_out.fworld');

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
            outFile.path,
            '--compress',
            'gzip',
          ],
          workingDirectory: Directory.current.path,
        );

        expect(result.exitCode, 0, reason: 'Stderr: ${result.stderr}');
        expect(await outFile.exists(), isTrue);

        final unpacked = await FWorldReader.readFromFile(outFile.path);
        expect(unpacked.meshes, hasLength(1));
        expect(unpacked.shaders, hasLength(1));
        expect(unpacked.compressionType, 1); // gzip
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
