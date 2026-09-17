import '../../packages/fluorescent_core/lib/src/rendering/render_graph.dart';
import '../../packages/fluorescent_core/lib/src/rendering/render_pass.dart';
import 'e2e_test_harness.dart';

void defineTests() {
  group('Pillar 2: Data-Driven RenderGraph & DAG Execution Order', () {
    test('E2E-P2-001: Parses multi-pass RenderGraph from JSON schema and compiles DAG topological order', () {
      final pipelineJson = {
        'version': '1.0',
        'outputAttachment': 'backbuffer',
        'attachments': [
          {
            'name': 'backbuffer',
            'format': 'bgra8unorm',
            'type': 'color',
            'loadOp': 'clear',
            'storeOp': 'store',
            'clearValue': {'r': 0.0, 'g': 0.0, 'b': 0.0, 'a': 1.0},
          },
          {
            'name': 'gbuffer_albedo',
            'format': 'rgba8unorm',
            'type': 'color',
            'loadOp': 'clear',
            'storeOp': 'store',
          },
          {
            'name': 'shadow_map',
            'format': 'depth32float',
            'type': 'depth',
            'loadOp': 'clear',
            'storeOp': 'store',
          },
          {
            'name': 'hdr_lighting',
            'format': 'rgba16float',
            'type': 'color',
            'loadOp': 'clear',
            'storeOp': 'store',
          },
        ],
        'passes': [
          {
            'name': 'PostProcessPass',
            'type': 'post_process',
            'inputs': ['hdr_lighting'],
            'outputs': ['backbuffer'],
            'dependencies': ['LightingPass'],
          },
          {
            'name': 'LightingPass',
            'type': 'lighting',
            'inputs': ['gbuffer_albedo', 'shadow_map'],
            'outputs': ['hdr_lighting'],
            'dependencies': ['GBufferPass', 'ShadowPass'],
          },
          {
            'name': 'GBufferPass',
            'type': 'geometry',
            'outputs': ['gbuffer_albedo'],
            'dependencies': [],
          },
          {
            'name': 'ShadowPass',
            'type': 'shadow',
            'outputs': ['shadow_map'],
            'dependencies': [],
          },
        ],
      };

      final renderGraph = RenderGraph.fromJson(pipelineJson);

      expect(renderGraph.attachments.length, equals(4));
      expect(renderGraph.passes.length, equals(4));
      expect(renderGraph.outputAttachment, equals('backbuffer'));

      // Compile DAG and verify topological order
      final executionOrder = renderGraph.compile();

      expect(executionOrder.length, equals(4));

      final passNames = executionOrder.map((p) => p.name).toList();

      // GBufferPass and ShadowPass must precede LightingPass
      final gbufferIdx = passNames.indexOf('GBufferPass');
      final shadowIdx = passNames.indexOf('ShadowPass');
      final lightingIdx = passNames.indexOf('LightingPass');
      final postProcessIdx = passNames.indexOf('PostProcessPass');

      expect(gbufferIdx, lessThan(lightingIdx));
      expect(shadowIdx, lessThan(lightingIdx));
      expect(lightingIdx, lessThan(postProcessIdx));
      expect(postProcessIdx, equals(3)); // Final pass writing to backbuffer
    });

    test('E2E-P2-002: Detects cyclic dependencies in RenderGraph DAG and throws RenderGraphCycleException', () {
      final cyclicGraph = RenderGraph();

      // Pass A depends on Pass C
      cyclicGraph.addPass(RenderPassDescriptor(
        name: 'PassA',
        dependencies: ['PassC'],
      ));

      // Pass B depends on Pass A
      cyclicGraph.addPass(RenderPassDescriptor(
        name: 'PassB',
        dependencies: ['PassA'],
      ));

      // Pass C depends on Pass B (Cycle: A -> C -> B -> A)
      cyclicGraph.addPass(RenderPassDescriptor(
        name: 'PassC',
        dependencies: ['PassB'],
      ));

      bool cycleDetected = false;
      try {
        cyclicGraph.compile();
      } catch (e) {
        if (e is RenderGraphCycleException) {
          cycleDetected = true;
          expect(e.cycle.isNotEmpty, isTrue);
        }
      }
      expect(cycleDetected, isTrue);
    });

    test('E2E-P2-003: RenderGraph validates attachment bindings and missing dependency errors', () {
      final incompleteGraph = RenderGraph();

      // Pass references non-existent dependency 'NonExistentPass'
      incompleteGraph.addPass(RenderPassDescriptor(
        name: 'MainPass',
        dependencies: ['NonExistentPass'],
      ));

      bool validationFailed = false;
      try {
        incompleteGraph.validate();
      } catch (e) {
        if (e is RenderGraphValidationException) {
          validationFailed = true;
        }
      }
      expect(validationFailed, isTrue);
    });
  });
}

Future<void> main() async {
  await runSuite('Pillar 2: Data-Driven RenderGraph & DAG Execution Order', defineTests);
}
