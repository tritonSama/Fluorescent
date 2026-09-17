import '../../tools/asset_pipeline/lib/shader_toolchain/demo_transpiler.dart';
import '../../tools/asset_pipeline/lib/shader_toolchain/naga_ffi.dart';
import 'e2e_test_harness.dart';

const String sampleWgslShader = '''
struct CameraUniforms {
    viewProjection : mat4x4<f32>,
};

@group(0) @binding(0) var<uniform> camera : CameraUniforms;

struct VertexInput {
    @location(0) position : vec3<f32>,
    @location(1) uv : vec2<f32>,
};

struct VertexOutput {
    @builtin(position) clipPos : vec4<f32>,
    @location(0) uv : vec2<f32>,
};

@vertex
fn vertexMain(in : VertexInput) -> VertexOutput {
    var out : VertexOutput;
    out.clipPos = camera.viewProjection * vec4<f32>(in.position, 1.0);
    out.uv = in.uv;
    return out;
}

@fragment
fn fragmentMain(in : VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(in.uv.x, in.uv.y, 0.5, 1.0);
}
''';

void defineTests() {
  group('Pillar 6: Shader Toolchain (WGSL -> SPIR-V & MSL)', () {
    test('E2E-P6-001: DemoShaderTranspiler compiles WGSL into valid SPIR-V bytecode with 0x07230203 magic', () {
      final transpiler = DemoShaderTranspiler();
      final bundle = transpiler.transpile(
        shaderName: 'pbr_shader',
        wgslSource: sampleWgslShader,
      );

      expect(bundle.name, equals('pbr_shader'));
      expect(bundle.vertexEntryPoint, equals('vertexMain'));
      expect(bundle.fragmentEntryPoint, equals('fragmentMain'));

      // Validate SPIR-V binary words
      final spirvWords = bundle.spirvWords;
      expect(spirvWords.isNotEmpty, isTrue);

      // SPIR-V Specification Magic Number: 0x07230203
      expect(spirvWords[0], equals(0x07230203));

      // Check byte representation length is 4x word length
      expect(bundle.spirvBytes.length, equals(spirvWords.length * 4));
    });

    test('E2E-P6-002: DemoShaderTranspiler translates WGSL into Metal Shading Language (MSL)', () {
      final transpiler = DemoShaderTranspiler();
      final bundle = transpiler.transpile(
        shaderName: 'pbr_shader',
        wgslSource: sampleWgslShader,
      );

      final msl = bundle.msl;
      expect(msl.isNotEmpty, isTrue);

      // Verify Metal Shading Language syntax attributes
      expect(msl.contains('vertex'), isTrue);
      expect(msl.contains('fragment'), isTrue);
      expect(msl.contains('float4') || msl.contains('vec4'), isTrue);
    });

    test('E2E-P6-003: NagaFfiTranspiler provides seamless fallback when native library is absent', () {
      final nagaTranspiler = NagaFfiTranspiler();

      // Transpile must never throw DllNotFoundException, even without native .dll/.so/.dylib installed
      final bundle = nagaTranspiler.transpile(
        shaderName: 'fallback_shader',
        wgslSource: sampleWgslShader,
      );

      expect(bundle, isNotNull);
      expect(bundle.name, equals('fallback_shader'));
      expect(bundle.spirvWords.first, equals(0x07230203));
      expect(bundle.msl.isNotEmpty, isTrue);
    });

    test('E2E-P6-004: ShaderBundle serializes metadata to JSON correctly', () {
      final transpiler = DemoShaderTranspiler();
      final originalBundle = transpiler.transpile(
        shaderName: 'json_bundle',
        wgslSource: sampleWgslShader,
      );

      final jsonMap = originalBundle.toJson();

      expect(jsonMap['name'], equals(originalBundle.name));
      expect(jsonMap['vertexEntryPoint'], equals(originalBundle.vertexEntryPoint));
      expect(jsonMap['fragmentEntryPoint'], equals(originalBundle.fragmentEntryPoint));
      expect(jsonMap['wgslLength'], equals(originalBundle.wgsl.length));
      expect(jsonMap['mslLength'], equals(originalBundle.msl.length));
      expect(jsonMap['spirvWordsCount'], equals(originalBundle.spirvWords.length));
      expect(jsonMap['spirvBytesCount'], equals(originalBundle.spirvBytes.length));
    });
  });
}

Future<void> main() async {
  await runSuite('Pillar 6: Shader Toolchain (WGSL -> SPIR-V & MSL)', defineTests);
}
