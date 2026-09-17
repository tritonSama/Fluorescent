import 'package:flutter_test/flutter_test.dart';
import 'package:fluorescent_core/src/rendering/render_graph.dart';
import 'package:fluorescent_core/src/rendering/render_graph_schema.dart';
import 'package:fluorescent_core/src/rendering/render_pass.dart';

void main() {
  group('AttachmentDescriptor', () {
    test('default values', () {
      const desc = AttachmentDescriptor(name: 'colorTarget');
      expect(desc.name, 'colorTarget');
      expect(desc.type, AttachmentType.color);
      expect(desc.format, TextureFormat.rgba8unorm);
      expect(desc.size, isNull);
      expect(desc.scale, isNull);
      expect(desc.loadOp, LoadOp.clear);
      expect(desc.storeOp, StoreOp.store);
      expect(desc.clearColor, [0.0, 0.0, 0.0, 1.0]);
      expect(desc.clearDepth, 1.0);
    });

    test('custom values and copyWith', () {
      final desc = AttachmentDescriptor(
        name: 'depthBuffer',
        type: AttachmentType.depth,
        format: TextureFormat.depth24plus,
        size: [1920, 1080],
        scale: [1.0, 1.0],
        loadOp: LoadOp.clear,
        storeOp: StoreOp.discard,
        clearDepth: 0.0,
      );

      expect(desc.name, 'depthBuffer');
      expect(desc.type, AttachmentType.depth);
      expect(desc.format, TextureFormat.depth24plus);
      expect(desc.size, [1920, 1080]);
      expect(desc.clearDepth, 0.0);

      final copy = desc.copyWith(name: 'depthBuffer2', clearDepth: 0.5);
      expect(copy.name, 'depthBuffer2');
      expect(copy.clearDepth, 0.5);
      expect(copy.format, TextureFormat.depth24plus);
    });

    test('JSON serialization round-trip', () {
      final original = AttachmentDescriptor(
        name: 'hdrTarget',
        type: AttachmentType.color,
        format: TextureFormat.rgba16float,
        scale: [0.5, 0.5],
        loadOp: LoadOp.dontCare,
        storeOp: StoreOp.store,
        clearColor: [0.2, 0.3, 0.4, 1.0],
      );

      final json = original.toJson();
      final restored = AttachmentDescriptor.fromJson(json);

      expect(restored.name, original.name);
      expect(restored.type, original.type);
      expect(restored.format, original.format);
      expect(restored.scale, original.scale);
      expect(restored.loadOp, original.loadOp);
      expect(restored.storeOp, original.storeOp);
      expect(restored.clearColor, original.clearColor);
      expect(restored, equals(original));
      expect(restored.hashCode, equals(original.hashCode));
    });
  });

  group('RenderPassDescriptor', () {
    test('default values', () {
      const pass = RenderPassDescriptor(name: 'main_pass');
      expect(pass.name, 'main_pass');
      expect(pass.type, PassType.raster);
      expect(pass.colorAttachments, isEmpty);
      expect(pass.depthStencilAttachment, isNull);
      expect(pass.inputs, isEmpty);
      expect(pass.dependencies, isEmpty);
      expect(pass.shader, isNull);
    });

    test('custom values and copyWith', () {
      const pass = RenderPassDescriptor(
        name: 'gbuffer',
        type: PassType.raster,
        colorAttachments: ['albedo', 'normal'],
        depthStencilAttachment: 'depth',
        inputs: ['shadowMap'],
        dependencies: ['shadow_pass'],
        shader: 'shaders/gbuffer.wgsl',
      );

      expect(pass.name, 'gbuffer');
      expect(pass.colorAttachments, ['albedo', 'normal']);
      expect(pass.depthStencilAttachment, 'depth');
      expect(pass.inputs, ['shadowMap']);
      expect(pass.dependencies, ['shadow_pass']);
      expect(pass.shader, 'shaders/gbuffer.wgsl');

      final copy = pass.copyWith(name: 'gbuffer_v2');
      expect(copy.name, 'gbuffer_v2');
      expect(copy.shader, 'shaders/gbuffer.wgsl');
    });

    test('JSON serialization round-trip', () {
      const original = RenderPassDescriptor(
        name: 'bloom_downsample',
        type: PassType.compute,
        colorAttachments: ['bloomMip1'],
        inputs: ['sceneHdr'],
        dependencies: ['tonemap'],
        shader: 'shaders/bloom.wgsl',
      );

      final json = original.toJson();
      final restored = RenderPassDescriptor.fromJson(json);

      expect(restored, equals(original));
      expect(restored.hashCode, equals(original.hashCode));
    });
  });

  group('RenderGraphSchema', () {
    test('parses standard JSON schema with Map attachments and List passes', () {
      const jsonStr = '''
      {
        "outputAttachment": "backbuffer",
        "attachments": {
          "sceneColor": {
            "type": "color",
            "format": "rgba16float",
            "scale": [1.0, 1.0]
          },
          "backbuffer": {
            "type": "color",
            "format": "rgba8unorm"
          }
        },
        "passes": [
          {
            "name": "scene_pass",
            "colorAttachments": ["sceneColor"]
          },
          {
            "name": "present_pass",
            "colorAttachments": ["backbuffer"],
            "inputs": ["sceneColor"]
          }
        ]
      }
      ''';

      final graph = RenderGraphSchema.parseJson(jsonStr);
      expect(graph.attachments.length, 2);
      expect(graph.attachments['sceneColor']!.format, TextureFormat.rgba16float);
      expect(graph.passes.length, 2);
      expect(graph.outputAttachment, 'backbuffer');
    });

    test('parses schema with List attachments and Map passes', () {
      final schemaMap = {
        'outputAttachment': 'backbuffer',
        'attachments': [
          {'name': 'albedo', 'type': 'color', 'format': 'rgba8unorm'},
          {'name': 'backbuffer', 'type': 'color', 'format': 'rgba8unorm'},
        ],
        'passes': {
          'render': {
            'colorAttachments': ['albedo'],
          },
          'composite': {
            'colorAttachments': ['backbuffer'],
            'inputs': ['albedo'],
          },
        },
      };

      final graph = RenderGraphSchema.parseMap(schemaMap);
      expect(graph.attachments.containsKey('albedo'), isTrue);
      expect(graph.attachments.containsKey('backbuffer'), isTrue);
      expect(graph.passes.containsKey('render'), isTrue);
      expect(graph.passes.containsKey('composite'), isTrue);
    });

    test('parses YAML-compatible Map with dynamic keys', () {
      final dynamicYamlMap = <dynamic, dynamic>{
        'outputAttachment': 'backbuffer',
        'attachments': <dynamic, dynamic>{
          'backbuffer': <dynamic, dynamic>{
            'type': 'color',
            'format': 'rgba8unorm',
          },
        },
        'passes': <dynamic>[
          <dynamic, dynamic>{
            'name': 'forward',
            'colorAttachments': <dynamic>['backbuffer'],
          },
        ],
      };

      final graph = RenderGraph.fromMap(dynamicYamlMap);
      expect(graph.attachments.containsKey('backbuffer'), isTrue);
      expect(graph.passes.containsKey('forward'), isTrue);
    });

    test('parses YAML formatted string', () {
      const yamlStr = '''
outputAttachment: backbuffer
attachments:
  sceneColor:
    type: color
    format: rgba16float
  backbuffer:
    type: color
    format: rgba8unorm
passes:
  - name: gbuffer
    colorAttachments: [sceneColor]
  - name: tonemap
    colorAttachments: [backbuffer]
    inputs: [sceneColor]
''';

      final graph = RenderGraph.fromYaml(yamlStr);
      expect(graph.attachments.length, 2);
      expect(graph.passes.length, 2);
      expect(graph.passes['gbuffer']!.colorAttachments, ['sceneColor']);
      expect(graph.passes['tonemap']!.inputs, ['sceneColor']);
    });

    test('serializes graph to JSON and Map', () {
      final graph = RenderGraph(
        outputAttachment: 'backbuffer',
        attachments: {
          'backbuffer': const AttachmentDescriptor(name: 'backbuffer'),
        },
        passes: {
          'main': const RenderPassDescriptor(
            name: 'main',
            colorAttachments: ['backbuffer'],
          ),
        },
      );

      final map = RenderGraphSchema.toMap(graph);
      expect(map['outputAttachment'], 'backbuffer');
      expect(map['attachments'], isNotEmpty);
      expect(map['passes'], isNotEmpty);

      final jsonStr = RenderGraphSchema.toJson(graph);
      expect(jsonStr.contains('backbuffer'), isTrue);
      expect(jsonStr.contains('main'), isTrue);
    });

    test('throws RenderGraphSchemaException on invalid schema structure', () {
      expect(
        () => RenderGraphSchema.parseJson('"not a map"'),
        throwsA(isA<RenderGraphSchemaException>()),
      );

      expect(
        () => RenderGraphSchema.parseMap({
          'passes': [
            {'invalid_no_name': 123},
          ],
        }),
        throwsA(isA<RenderGraphSchemaException>()),
      );
    });
  });

  group('RenderGraph Validation', () {
    test('throws when color attachment is not defined', () {
      final graph = RenderGraph();
      graph.addPass(const RenderPassDescriptor(
        name: 'p1',
        colorAttachments: ['non_existent'],
      ));

      expect(
        () => graph.validate(),
        throwsA(isA<RenderGraphValidationException>()),
      );
    });

    test('throws when depth attachment is not defined or wrong type', () {
      final graph = RenderGraph();
      graph.addAttachment(const AttachmentDescriptor(
        name: 'colorTarget',
        type: AttachmentType.color,
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'p1',
        depthStencilAttachment: 'colorTarget',
      ));

      expect(
        () => graph.validate(),
        throwsA(isA<RenderGraphValidationException>()),
      );
    });

    test('throws when input attachment is not defined', () {
      final graph = RenderGraph();
      graph.addPass(const RenderPassDescriptor(
        name: 'p1',
        inputs: ['missing_input'],
      ));

      expect(
        () => graph.validate(),
        throwsA(isA<RenderGraphValidationException>()),
      );
    });

    test('throws when pass dependency is not defined', () {
      final graph = RenderGraph();
      graph.addPass(const RenderPassDescriptor(
        name: 'p1',
        dependencies: ['missing_pass'],
      ));

      expect(
        () => graph.validate(),
        throwsA(isA<RenderGraphValidationException>()),
      );
    });

    test('throws on self-dependency', () {
      final graph = RenderGraph();
      graph.addPass(const RenderPassDescriptor(
        name: 'self_loop',
        dependencies: ['self_loop'],
      ));

      expect(
        () => graph.validate(),
        throwsA(isA<RenderGraphCycleException>()),
      );
    });
  });

  group('DAG Resolution & Kahn Topological Sort', () {
    test('linear dependency chain: A -> B -> C -> backbuffer', () {
      final graph = RenderGraph();
      graph.addAttachment(const AttachmentDescriptor(name: 'texA'));
      graph.addAttachment(const AttachmentDescriptor(name: 'texB'));
      graph.addAttachment(const AttachmentDescriptor(name: 'backbuffer'));

      graph.addPass(const RenderPassDescriptor(
        name: 'pass_c',
        colorAttachments: ['backbuffer'],
        inputs: ['texB'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'pass_a',
        colorAttachments: ['texA'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'pass_b',
        colorAttachments: ['texB'],
        inputs: ['texA'],
      ));

      final compiled = graph.compile();
      final names = compiled.map((p) => p.name).toList();

      expect(names, ['pass_a', 'pass_b', 'pass_c']);
    });

    test('diamond dependency graph with shadow and gbuffer passes', () {
      final graph = RenderGraph();
      graph.addAttachment(const AttachmentDescriptor(
        name: 'shadowMap',
        type: AttachmentType.depth,
      ));
      graph.addAttachment(const AttachmentDescriptor(name: 'albedo'));
      graph.addAttachment(const AttachmentDescriptor(name: 'lightingHdr'));
      graph.addAttachment(const AttachmentDescriptor(name: 'backbuffer'));

      graph.addPass(const RenderPassDescriptor(
        name: 'shadow_pass',
        depthStencilAttachment: 'shadowMap',
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'gbuffer_pass',
        colorAttachments: ['albedo'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'lighting_pass',
        colorAttachments: ['lightingHdr'],
        inputs: ['shadowMap', 'albedo'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'tonemap_pass',
        colorAttachments: ['backbuffer'],
        inputs: ['lightingHdr'],
      ));

      final compiled = graph.compile();
      final names = compiled.map((p) => p.name).toList();

      expect(names.indexOf('shadow_pass'), lessThan(names.indexOf('lighting_pass')));
      expect(names.indexOf('gbuffer_pass'), lessThan(names.indexOf('lighting_pass')));
      expect(names.indexOf('lighting_pass'), lessThan(names.indexOf('tonemap_pass')));
      expect(names.last, 'tonemap_pass');
    });

    test('explicit pass dependency without attachment input enforces order', () {
      final graph = RenderGraph();
      graph.addAttachment(const AttachmentDescriptor(name: 'backbuffer'));

      graph.addPass(const RenderPassDescriptor(
        name: 'setup_constants',
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'main_draw',
        colorAttachments: ['backbuffer'],
        dependencies: ['setup_constants'],
      ));

      final compiled = graph.compile();
      final names = compiled.map((p) => p.name).toList();

      expect(names, ['setup_constants', 'main_draw']);
    });
  });

  group('Cycle Detection with RenderGraphCycleException', () {
    test('direct 2-pass cycle: A -> B -> A', () {
      final graph = RenderGraph();
      graph.addPass(const RenderPassDescriptor(
        name: 'pass_a',
        dependencies: ['pass_b'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'pass_b',
        dependencies: ['pass_a'],
      ));

      expect(
        () => graph.compile(pruneDeadPasses: false),
        throwsA(
          isA<RenderGraphCycleException>()
              .having((e) => e.message, 'message', contains('Cycle detected'))
              .having((e) => e.cycle, 'cycle', isNotEmpty),
        ),
      );
    });

    test('multi-pass indirect cycle: A -> B -> C -> A', () {
      final graph = RenderGraph();
      graph.addPass(const RenderPassDescriptor(
        name: 'pass_a',
        dependencies: ['pass_c'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'pass_b',
        dependencies: ['pass_a'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'pass_c',
        dependencies: ['pass_b'],
      ));

      expect(
        () => graph.compile(pruneDeadPasses: false),
        throwsA(
          isA<RenderGraphCycleException>()
              .having((e) => e.message, 'message', contains('pass_'))
              .having((e) => e.cycle.length, 'cycle length', greaterThanOrEqualTo(3)),
        ),
      );
    });

    test('data dependency cycle via attachments', () {
      final graph = RenderGraph();
      graph.addAttachment(const AttachmentDescriptor(name: 'tex1'));
      graph.addAttachment(const AttachmentDescriptor(name: 'tex2'));

      // pass1 writes tex1 and reads tex2
      graph.addPass(const RenderPassDescriptor(
        name: 'pass1',
        colorAttachments: ['tex1'],
        inputs: ['tex2'],
      ));

      // pass2 writes tex2 and reads tex1
      graph.addPass(const RenderPassDescriptor(
        name: 'pass2',
        colorAttachments: ['tex2'],
        inputs: ['tex1'],
      ));

      expect(
        () => graph.compile(pruneDeadPasses: false),
        throwsA(isA<RenderGraphCycleException>()),
      );
    });
  });

  group('Dead Pass Elimination', () {
    test('prunes passes not contributing to backbuffer', () {
      final graph = RenderGraph();
      graph.addAttachment(const AttachmentDescriptor(name: 'activeColor'));
      graph.addAttachment(const AttachmentDescriptor(name: 'backbuffer'));
      graph.addAttachment(const AttachmentDescriptor(name: 'unusedColor'));
      graph.addAttachment(const AttachmentDescriptor(name: 'debugColor'));

      // Active pipeline
      graph.addPass(const RenderPassDescriptor(
        name: 'scene_pass',
        colorAttachments: ['activeColor'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'present_pass',
        colorAttachments: ['backbuffer'],
        inputs: ['activeColor'],
      ));

      // Dead passes
      graph.addPass(const RenderPassDescriptor(
        name: 'dead_pass_1',
        colorAttachments: ['unusedColor'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'dead_pass_2',
        colorAttachments: ['debugColor'],
        inputs: ['unusedColor'],
      ));

      final compiled = graph.compile(pruneDeadPasses: true);
      final names = compiled.map((p) => p.name).toList();

      expect(names, containsAll(['scene_pass', 'present_pass']));
      expect(names.contains('dead_pass_1'), isFalse);
      expect(names.contains('dead_pass_2'), isFalse);
      expect(names.length, 2);
    });

    test('preserves all passes when pruneDeadPasses is false', () {
      final graph = RenderGraph();
      graph.addAttachment(const AttachmentDescriptor(name: 'backbuffer'));
      graph.addAttachment(const AttachmentDescriptor(name: 'sideBuffer'));

      graph.addPass(const RenderPassDescriptor(
        name: 'main',
        colorAttachments: ['backbuffer'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'isolated',
        colorAttachments: ['sideBuffer'],
      ));

      final compiled = graph.compile(pruneDeadPasses: false);
      expect(compiled.length, 2);
      expect(compiled.map((p) => p.name), containsAll(['main', 'isolated']));
    });

    test('supports custom outputAttachment pruning target', () {
      final graph = RenderGraph();
      graph.addAttachment(const AttachmentDescriptor(name: 'rtA'));
      graph.addAttachment(const AttachmentDescriptor(name: 'rtB'));
      graph.addAttachment(const AttachmentDescriptor(name: 'backbuffer'));

      graph.addPass(const RenderPassDescriptor(
        name: 'pass_for_rtA',
        colorAttachments: ['rtA'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'pass_for_rtB',
        colorAttachments: ['rtB'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'pass_for_backbuffer',
        colorAttachments: ['backbuffer'],
      ));

      // Target only rtA
      final compiled = graph.compile(outputAttachment: 'rtA', pruneDeadPasses: true);
      final names = compiled.map((p) => p.name).toList();

      expect(names, ['pass_for_rtA']);
    });
  });

  group('RenderGraph Execution', () {
    test('executes registered passes in topological order', () {
      final graph = RenderGraph();
      graph.addAttachment(const AttachmentDescriptor(name: 'colorBuffer'));
      graph.addAttachment(const AttachmentDescriptor(name: 'backbuffer'));

      final executionLog = <String>[];

      graph.addPass(
        const RenderPassDescriptor(
          name: 'scene_pass',
          colorAttachments: ['colorBuffer'],
        ),
        executablePass: RenderPass(
          descriptor: const RenderPassDescriptor(
            name: 'scene_pass',
            colorAttachments: ['colorBuffer'],
          ),
          onExecute: (ctx) {
            executionLog.add('scene_pass executed');
            ctx.state['scene'] = 'rendered';
          },
        ),
      );

      graph.addPass(
        const RenderPassDescriptor(
          name: 'tonemap_pass',
          colorAttachments: ['backbuffer'],
          inputs: ['colorBuffer'],
        ),
        executablePass: RenderPass(
          descriptor: const RenderPassDescriptor(
            name: 'tonemap_pass',
            colorAttachments: ['backbuffer'],
            inputs: ['colorBuffer'],
          ),
          onExecute: (ctx) {
            executionLog.add('tonemap_pass executed');
            expect(ctx.state['scene'], 'rendered');
          },
        ),
      );

      final context = RenderContext();
      graph.execute(context);

      expect(executionLog, ['scene_pass executed', 'tonemap_pass executed']);
      expect(context.executedPasses, ['scene_pass', 'tonemap_pass']);
    });
  });
}
