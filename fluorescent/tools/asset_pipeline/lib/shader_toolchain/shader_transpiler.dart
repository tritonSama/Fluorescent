import 'dart:typed_data';

/// Multi-target shader bundle containing the original WGSL source,
/// compiled SPIR-V bytecode words, and translated Metal Shading Language (MSL) source.
class ShaderBundle {
  final String name;
  final String wgsl;
  final Uint32List spirvWords;
  final String msl;
  final String vertexEntryPoint;
  final String fragmentEntryPoint;

  ShaderBundle({
    required this.name,
    required this.wgsl,
    required this.spirvWords,
    required this.msl,
    this.vertexEntryPoint = 'vertexMain',
    this.fragmentEntryPoint = 'fragmentMain',
  });

  /// Binary view of the SPIR-V words as Uint8List.
  Uint8List get spirvBytes => spirvWords.buffer.asUint8List(
        spirvWords.offsetInBytes,
        spirvWords.lengthInBytes,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'vertexEntryPoint': vertexEntryPoint,
        'fragmentEntryPoint': fragmentEntryPoint,
        'wgslLength': wgsl.length,
        'mslLength': msl.length,
        'spirvWordsCount': spirvWords.length,
        'spirvBytesCount': spirvBytes.length,
      };
}

/// Abstract interface for transpiling WGSL shaders into multi-target bundles.
abstract class ShaderTranspiler {
  /// Transpiles WGSL source code into a [ShaderBundle].
  ShaderBundle transpileWgsl({
    required String wgslSource,
    String shaderName = 'shader',
    String vertexEntryPoint = 'vertexMain',
    String fragmentEntryPoint = 'fragmentMain',
  });

  /// Alias for [transpileWgsl] supporting positional or named options.
  ShaderBundle transpile({
    required String shaderName,
    required String wgslSource,
    String vertexEntryPoint = 'vertexMain',
    String fragmentEntryPoint = 'fragmentMain',
  });
}
