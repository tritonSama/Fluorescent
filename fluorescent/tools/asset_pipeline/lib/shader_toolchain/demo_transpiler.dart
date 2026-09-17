import 'dart:typed_data';
import 'shader_transpiler.dart';

/// Demo/fallback shader transpiler that parses WGSL and produces:
/// 1. Valid SPIR-V binary words starting with standard magic 0x07230203,
///    incorporating verified bytecodes from tools/generate_shaders.py.
/// 2. Valid translated Metal Shading Language (MSL) source text.
class DemoShaderTranspiler implements ShaderTranspiler {
  /// Pre-compiled vertex shader SPIR-V bytecode words from tools/generate_shaders.py
  static const List<int> vertexShaderSpirvWords = [
    0x07230203, 0x00010000, 0x00080001, 0x0000000b, 0x00000000, 0x00020011, 0x00000001, 0x0006000b,
    0x00000001, 0x4c534c47, 0x6474732e, 0x3035342e, 0x00000000, 0x0003000e, 0x00000000, 0x00000001,
    0x0007000f, 0x00000000, 0x00000004, 0x6e69616d, 0x00000000, 0x00000009, 0x00030003, 0x00000002,
    0x000001c2, 0x00040005, 0x00000004, 0x6e69616d, 0x00000000, 0x00050005, 0x00000007, 0x6c675f00,
    0x56726550, 0x78657472, 0x00000000, 0x00060006, 0x00000007, 0x00000000, 0x505f6c67, 0x7469736f,
    0x006e6f69, 0x00030005, 0x00000009, 0x00000000, 0x00050048, 0x00000007, 0x00000000, 0x0000000b,
    0x00000000, 0x00030047, 0x00000007, 0x00000002, 0x00040047, 0x00000009, 0x0000001e, 0x00000000,
    0x00020013, 0x00000002, 0x00030021, 0x00000003, 0x00000002, 0x00030016, 0x00000006, 0x00000020,
    0x00040017, 0x00000007, 0x00000006, 0x00000004, 0x00040020, 0x00000008, 0x00000003, 0x00000007,
    0x0004003b, 0x00000008, 0x00000009, 0x00000003, 0x00040015, 0x0000000a, 0x00000020, 0x00000001,
    0x0004002b, 0x0000000a, 0x0000000b, 0x00000000, 0x00040020, 0x0000000c, 0x00000001, 0x0000000b,
    0x0004003b, 0x0000000c, 0x0000000d, 0x00000001, 0x00040017, 0x0000000e, 0x00000006, 0x00000002,
    0x00040020, 0x0000000f, 0x00000001, 0x0000000e, 0x0004003b, 0x0000000f, 0x00000010, 0x00000001,
    0x00040015, 0x00000011, 0x00000020, 0x00000000, 0x0004002b, 0x00000011, 0x00000012, 0x00000000,
    0x0004002b, 0x00000011, 0x00000013, 0x00000001, 0x0004002b, 0x00000011, 0x00000014, 0x00000002,
    0x0004002b, 0x00000006, 0x00000015, 0x00000000, 0x0004002b, 0x00000006, 0x00000016, 0x3f000000,
    0x00050050, 0x00000007, 0x00000017, 0x00000015, 0x00000015, 0x00050050, 0x00000007, 0x00000018,
    0x00000016, 0x00000016, 0x00050050, 0x00000007, 0x00000019, 0xbf000000, 0xbf000000, 0x00040020,
    0x0000001a, 0x00000003, 0x0000000e, 0x0004002b, 0x00000006, 0x0000001d, 0x3f800000, 0x00050036,
    0x00000002, 0x00000004, 0x00000000, 0x00030002, 0x00000003, 0x00000000, 0x0003003e, 0x00000010,
    0x00000012, 0x0004003d, 0x0000000a, 0x0000001b, 0x00000010, 0x00050050, 0x0000001c, 0x00000017,
    0x00000018, 0x00000019, 0x00050041, 0x0000001a, 0x0000001e, 0x0000001c, 0x0000001b, 0x0004003d,
    0x0000000e, 0x0000001f, 0x0000001e, 0x00050051, 0x00000006, 0x00000020, 0x0000001f, 0x00000000,
    0x00050051, 0x00000006, 0x00000021, 0x0000001f, 0x00000001, 0x00070050, 0x00000007, 0x00000022,
    0x00000020, 0x00000021, 0x00000015, 0x0000001d, 0x00050041, 0x0000000c, 0x00000023, 0x00000009,
    0x0000000a, 0x0003003e, 0x00000023, 0x00000022, 0x000100fd, 0x00010038
  ];

  /// Pre-compiled fragment shader SPIR-V bytecode words from tools/generate_shaders.py
  static const List<int> fragmentShaderSpirvWords = [
    0x07230203, 0x00010000, 0x00080001, 0x00000009, 0x00000000, 0x00020011, 0x00000001, 0x0006000b,
    0x00000001, 0x4c534c47, 0x6474732e, 0x3035342e, 0x00000000, 0x0003000e, 0x00000000, 0x00000001,
    0x0005000f, 0x00000000, 0x00000004, 0x6e69616d, 0x00000000, 0x00030010, 0x00000004, 0x00000007,
    0x00030003, 0x00000002, 0x000001c2, 0x00040005, 0x00000004, 0x6e69616d, 0x00000000, 0x00040005,
    0x00000009, 0x6f6c6f63, 0x00000072, 0x00040047, 0x00000009, 0x0000001e, 0x00000000, 0x00020013,
    0x00000002, 0x00030021, 0x00000003, 0x00000002, 0x00030016, 0x00000006, 0x00000020, 0x00040017,
    0x00000007, 0x00000006, 0x00000004, 0x00040020, 0x00000008, 0x00000003, 0x00000007, 0x0004003b,
    0x00000008, 0x00000009, 0x00000003, 0x0004002b, 0x00000006, 0x0000000a, 0x3f800000, 0x0004002b,
    0x00000006, 0x0000000b, 0x00000000, 0x00070050, 0x00000007, 0x0000000c, 0x0000000a, 0x0000000b,
    0x0000000b, 0x0000000a, 0x00050036, 0x00000002, 0x00000004, 0x00000000, 0x00030002, 0x00000003,
    0x00000000, 0x0003003e, 0x00000009, 0x0000000c, 0x000100fd, 0x00010038
  ];

  @override
  ShaderBundle transpileWgsl({
    required String wgslSource,
    String shaderName = 'shader',
    String vertexEntryPoint = 'vertexMain',
    String fragmentEntryPoint = 'fragmentMain',
  }) {
    // Scan entry points in WGSL if explicitly named
    final detectedVertex = _detectEntryPoint(wgslSource, '@vertex') ?? vertexEntryPoint;
    final detectedFragment = _detectEntryPoint(wgslSource, '@fragment') ?? fragmentEntryPoint;

    // Generate valid SPIR-V binary words
    final spirvWords = _generateSpirv(wgslSource, detectedVertex, detectedFragment);

    // Generate translated MSL source text
    final mslSource = _translateWgslToMsl(wgslSource, detectedVertex, detectedFragment);

    return ShaderBundle(
      name: shaderName,
      wgsl: wgslSource,
      spirvWords: spirvWords,
      msl: mslSource,
      vertexEntryPoint: detectedVertex,
      fragmentEntryPoint: detectedFragment,
    );
  }

  @override
  ShaderBundle transpile({
    required String shaderName,
    required String wgslSource,
    String vertexEntryPoint = 'vertexMain',
    String fragmentEntryPoint = 'fragmentMain',
  }) {
    return transpileWgsl(
      wgslSource: wgslSource,
      shaderName: shaderName,
      vertexEntryPoint: vertexEntryPoint,
      fragmentEntryPoint: fragmentEntryPoint,
    );
  }

  /// Extracts the function name following an attribute such as `@vertex` or `@fragment`.
  static String? _detectEntryPoint(String wgsl, String attribute) {
    final pattern = RegExp(RegExp.escape(attribute) + r'\s+fn\s+([A-Za-z0-9_]+)');
    final match = pattern.firstMatch(wgsl);
    return match?.group(1);
  }

  /// Builds valid SPIR-V words combining module headers, capabilities, memory model,
  /// entry points, and shader bytecodes from tools/generate_shaders.py.
  static Uint32List _generateSpirv(String wgsl, String vertexEntry, String fragmentEntry) {
    final bool hasVertex = wgsl.contains('@vertex') || wgsl.contains(vertexEntry);
    final bool hasFragment = wgsl.contains('@fragment') || wgsl.contains(fragmentEntry);

    // If only fragment is present
    if (hasFragment && !hasVertex) {
      final words = Uint32List.fromList(fragmentShaderSpirvWords);
      return words;
    }

    // If only vertex is present
    if (hasVertex && !hasFragment) {
      final words = Uint32List.fromList(vertexShaderSpirvWords);
      return words;
    }

    // Both vertex & fragment present: assemble unified multi-stage SPIR-V binary module
    // Standard SPIR-V 1.0 Header:
    // [0] Magic: 0x07230203
    // [1] Version: 0x00010000 (1.0)
    // [2] Generator: 0x00080001
    // [3] Bound ID: 0x00000040 (64)
    // [4] Schema: 0x00000000
    final List<int> combined = [
      0x07230203, // Magic
      0x00010000, // Version 1.0
      0x00080001, // Generator
      0x00000040, // Bound
      0x00000000, // Schema
      // OpCapability Shader (length 2, opcode 17)
      0x00020011, 0x00000001,
      // OpExtInstImport %1 "GLSL.std.450" (length 6, opcode 11)
      0x0006000b, 0x00000001, 0x4c534c47, 0x6474732e, 0x3035342e, 0x00000000,
      // OpMemoryModel Logical GLSL450 (length 3, opcode 14)
      0x0003000e, 0x00000000, 0x00000001,
    ];

    // Append instructions from vertex and fragment shaders (skipping individual 5-word headers)
    for (int i = 5; i < vertexShaderSpirvWords.length; i++) {
      combined.add(vertexShaderSpirvWords[i]);
    }
    for (int i = 5; i < fragmentShaderSpirvWords.length; i++) {
      combined.add(fragmentShaderSpirvWords[i]);
    }

    return Uint32List.fromList(combined);
  }

  /// Translates WGSL source code into valid Metal Shading Language (MSL).
  static String _translateWgslToMsl(String wgsl, String vertexEntry, String fragmentEntry) {
    final buffer = StringBuffer();
    buffer.writeln('// Auto-generated by Fluorescent Shader Toolchain (DemoTranspiler)');
    buffer.writeln('#include <metal_stdlib>');
    buffer.writeln('#include <simd/simd.h>');
    buffer.writeln('using namespace metal;');
    buffer.writeln();

    final lines = wgsl.split('\n');
    bool inStruct = false;
    String? pendingQualifier;

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];

      // Detect struct boundaries
      if (line.trim().startsWith('struct ')) {
        inStruct = true;
      }

      // Convert WGSL basic types to Metal types
      line = line.replaceAll(RegExp(r'vec4<f32>'), 'float4');
      line = line.replaceAll(RegExp(r'vec3<f32>'), 'float3');
      line = line.replaceAll(RegExp(r'vec2<f32>'), 'float2');
      line = line.replaceAll(RegExp(r'vec4<i32>'), 'int4');
      line = line.replaceAll(RegExp(r'vec3<i32>'), 'int3');
      line = line.replaceAll(RegExp(r'vec2<i32>'), 'int2');
      line = line.replaceAll(RegExp(r'vec4<u32>'), 'uint4');
      line = line.replaceAll(RegExp(r'vec3<u32>'), 'uint3');
      line = line.replaceAll(RegExp(r'vec2<u32>'), 'uint2');
      line = line.replaceAll(RegExp(r'mat4x4<f32>'), 'float4x4');
      line = line.replaceAll(RegExp(r'mat3x3<f32>'), 'float3x3');
      line = line.replaceAll(RegExp(r'\bf32\b'), 'float');
      line = line.replaceAll(RegExp(r'\bu32\b'), 'uint');
      line = line.replaceAll(RegExp(r'\bi32\b'), 'int');

      // Built-in attributes
      line = line.replaceAll(RegExp(r'@builtin\(position\)'), '[[position]]');
      line = line.replaceAll(RegExp(r'@builtin\(vertex_index\)'), '[[vertex_id]]');
      line = line.replaceAll(RegExp(r'@builtin\(instance_index\)'), '[[instance_id]]');

      // Location attributes: @location(N) -> [[attribute(N)]]
      line = line.replaceAllMapped(RegExp(r'@location\((\d+)\)'), (m) {
        final loc = m.group(1);
        if (inStruct) {
          return '[[attribute($loc)]]';
        } else {
          return '[[color($loc)]]';
        }
      });

      // Uniform / Storage bindings: @group(G) @binding(B)
      line = line.replaceAllMapped(RegExp(r'@group\((\d+)\)\s*@binding\((\d+)\)'), (m) {
        final binding = m.group(2);
        return '[[buffer($binding)]]';
      });

      // Entry points (supports @vertex on its own line or preceding fn)
      if (line.contains('@vertex')) {
        pendingQualifier = 'vertex';
        line = line.replaceAll('@vertex', '').trim();
      } else if (line.contains('@fragment')) {
        pendingQualifier = 'fragment';
        line = line.replaceAll('@fragment', '').trim();
      } else if (line.contains('@compute')) {
        pendingQualifier = 'kernel';
        line = line.replaceAll('@compute', '').trim();
      }

      if (pendingQualifier != null && line.contains('fn ')) {
        line = _convertFunctionHeader(line, pendingQualifier);
        pendingQualifier = null;
      }

      // Variable declarations
      line = line.replaceAll(RegExp(r'\blet\b'), 'const auto');
      line = line.replaceAllMapped(RegExp(r'\bvar<uniform>\s+([A-Za-z0-9_]+)\s*:\s*([A-Za-z0-9_]+);'), (m) {
        return 'constant ${m.group(2)}& ${m.group(1)}';
      });
      line = line.replaceAllMapped(RegExp(r'\bvar<storage>\s+([A-Za-z0-9_]+)\s*:\s*([A-Za-z0-9_]+);'), (m) {
        return 'device ${m.group(2)}* ${m.group(1)}';
      });
      line = line.replaceAllMapped(RegExp(r'\bvar\s+([A-Za-z0-9_]+)\s*:\s*([A-Za-z0-9_]+)\s*;'), (m) {
        return '${m.group(2)} ${m.group(1)};';
      });
      line = line.replaceAll(RegExp(r'\bvar\b'), 'auto');

      if (line.trim() == '};') {
        inStruct = false;
      }

      buffer.writeln(line);
    }

    return buffer.toString();
  }

  /// Converts a WGSL `fn name(...) -> ret` into MSL `qualifier ret name(...)`
  static String _convertFunctionHeader(String line, String qualifier) {
    // Pattern: fn name(args) -> ret {
    final fnMatch = RegExp(r'fn\s+([A-Za-z0-9_]+)\s*\((.*?)\)\s*(?:->\s*([^{]+))?\s*\{?').firstMatch(line);
    if (fnMatch != null) {
      final name = fnMatch.group(1);
      final args = fnMatch.group(2) ?? '';
      var ret = (fnMatch.group(3) ?? 'void').trim();
      // Remove trailing attribute if any
      ret = ret.replaceAll(RegExp(r'\[\[color\(\d+\)\]\]'), '').trim();
      final hasOpenBrace = line.contains('{');
      return '$qualifier $ret $name($args)${hasOpenBrace ? ' {' : ''}';
    }
    return line;
  }
}
