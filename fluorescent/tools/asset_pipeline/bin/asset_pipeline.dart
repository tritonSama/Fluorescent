import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../lib/fworld_writer.dart';
import '../lib/gltf_compiler.dart';
import '../lib/shader_toolchain/naga_ffi.dart';
import '../lib/shader_toolchain/shader_transpiler.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addMultiOption('gltf', abbr: 'g', help: 'Path to input .gltf file(s)')
    ..addMultiOption('shader', abbr: 's', help: 'Path to input .wgsl shader file(s)')
    ..addOption('output', abbr: 'o', defaultsTo: 'output.fworld', help: 'Path for the output .fworld binary')
    ..addOption(
      'compress',
      abbr: 'c',
      defaultsTo: 'zlib',
      allowed: ['zlib', 'gzip', 'none'],
      help: 'Compression algorithm to apply to the .fworld payload',
    )
    ..addOption('name', abbr: 'n', help: 'Name of the compiled 3D world')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this help message');

  ArgResults results;
  try {
    results = parser.parse(arguments);
  } catch (e) {
    stderr.writeln('Error parsing arguments: $e');
    stderr.writeln(parser.usage);
    exitCode = 1;
    return;
  }

  if (results['help'] as bool) {
    stdout.writeln('Fluorescent Engine Asset Pipeline CLI');
    stdout.writeln('Usage: dart run bin/asset_pipeline.dart [options]');
    stdout.writeln(parser.usage);
    return;
  }

  final gltfPaths = results['gltf'] as List<String>;
  final shaderPaths = results['shader'] as List<String>;
  final outputPath = results['output'] as String;
  final compressOpt = results['compress'] as String;
  final worldName = (results['name'] as String?) ?? p.basenameWithoutExtension(outputPath);

  if (gltfPaths.isEmpty && shaderPaths.isEmpty) {
    stderr.writeln('Error: At least one --gltf or --shader input must be provided.');
    stderr.writeln(parser.usage);
    exitCode = 1;
    return;
  }

  stdout.writeln('=== Fluorescent Asset Pipeline ===');
  stdout.writeln('Compiling world "$worldName" -> "$outputPath"...');

  final List<CompiledMesh> compiledMeshes = [];
  final Map<String, dynamic> customMetadata = {};

  // 1. Process glTF files
  for (final gltfPath in gltfPaths) {
    stdout.writeln('Ingesting glTF: $gltfPath');
    try {
      final compileResult = await GltfCompiler.compileFile(gltfPath);
      stdout.writeln('  Extracted ${compileResult.meshes.length} mesh(es):');
      for (final m in compileResult.meshes) {
        stdout.writeln('    - ${m.name}: ${m.vertexCount} vertices, ${m.indexCount} indices');
        compiledMeshes.add(m);
      }
      customMetadata[p.basename(gltfPath)] = compileResult.metadata;
    } catch (e, st) {
      stderr.writeln('Error compiling glTF "$gltfPath": $e\n$st');
      exitCode = 2;
      return;
    }
  }

  // 2. Process Shaders
  final List<ShaderBundle> compiledShaders = [];
  final transpiler = NagaFfiTranspiler();
  stdout.writeln('Shader Toolchain Backend: ${transpiler.isNativeAvailable ? "Naga FFI (Native)" : "DemoShaderTranspiler (Fallback)"}');

  for (final shaderPath in shaderPaths) {
    stdout.writeln('Transpiling WGSL Shader: $shaderPath');
    try {
      final shaderFile = File(shaderPath);
      if (!await shaderFile.exists()) {
        throw FileSystemException('Shader file not found', shaderPath);
      }
      final wgslSource = await shaderFile.readAsString();
      final shaderName = p.basenameWithoutExtension(shaderPath);

      final bundle = transpiler.transpile(
        shaderName: shaderName,
        wgslSource: wgslSource,
      );

      stdout.writeln('  Bundle generated for "$shaderName":');
      stdout.writeln('    - SPIR-V: ${bundle.spirvWords.length} words (${bundle.spirvBytes.length} bytes)');
      stdout.writeln('    - MSL: ${bundle.msl.length} chars');
      stdout.writeln('    - Vertex Entry: ${bundle.vertexEntryPoint}');
      stdout.writeln('    - Fragment Entry: ${bundle.fragmentEntryPoint}');

      compiledShaders.add(bundle);
    } catch (e, st) {
      stderr.writeln('Error transpiling shader "$shaderPath": $e\n$st');
      exitCode = 3;
      return;
    }
  }

  // 3. Serialize and Write .fworld
  FWorldCompression compression;
  switch (compressOpt) {
    case 'gzip':
      compression = FWorldCompression.gzip;
      break;
    case 'none':
      compression = FWorldCompression.none;
      break;
    case 'zlib':
    default:
      compression = FWorldCompression.zlib;
      break;
  }

  stdout.writeln('Serializing .fworld binary with compression: ${compression.name}...');
  try {
    final outFile = await FWorldWriter.writeToFile(
      outputPath: outputPath,
      worldName: worldName,
      meshes: compiledMeshes,
      shaders: compiledShaders,
      customMetadata: customMetadata,
      compression: compression,
    );

    final fileSize = await outFile.length();
    stdout.writeln('Successfully generated .fworld package!');
    stdout.writeln('  Path: ${outFile.path}');
    stdout.writeln('  Total Size: $fileSize bytes');
    stdout.writeln('  Meshes: ${compiledMeshes.length}');
    stdout.writeln('  Shaders: ${compiledShaders.length}');
    stdout.writeln('=== Done ===');
  } catch (e, st) {
    stderr.writeln('Error writing .fworld package "$outputPath": $e\n$st');
    exitCode = 4;
    return;
  }
}
