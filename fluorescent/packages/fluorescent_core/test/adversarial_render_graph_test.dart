import 'package:flutter_test/flutter_test.dart';
import 'package:fluorescent_core/src/rendering/render_graph.dart';
import 'package:fluorescent_core/src/rendering/render_graph_schema.dart';
import 'package:fluorescent_core/src/rendering/render_pass.dart';

void main() {
  group('Adversarial Testing: RenderGraph Diamond Topologies', () {
    test('nested multi-stage diamond graph topological ordering', () {
      // Stage 1: A -> (B1, B2) -> C
      // Stage 2: C -> (D1, D2) -> E (backbuffer)
      final graph = RenderGraph();
      graph.addAttachment(const AttachmentDescriptor(name: 'texA'));
      graph.addAttachment(const AttachmentDescriptor(name: 'texB1'));
      graph.addAttachment(const AttachmentDescriptor(name: 'texB2'));
      graph.addAttachment(const AttachmentDescriptor(name: 'texC'));
      graph.addAttachment(const AttachmentDescriptor(name: 'texD1'));
      graph.addAttachment(const AttachmentDescriptor(name: 'texD2'));
      graph.addAttachment(const AttachmentDescriptor(name: 'backbuffer'));

      graph.addPass(const RenderPassDescriptor(
        name: 'pass_A',
        colorAttachments: ['texA'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'pass_B1',
        colorAttachments: ['texB1'],
        inputs: ['texA'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'pass_B2',
        colorAttachments: ['texB2'],
        inputs: ['texA'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'pass_C',
        colorAttachments: ['texC'],
        inputs: ['texB1', 'texB2'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'pass_D1',
        colorAttachments: ['texD1'],
        inputs: ['texC'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'pass_D2',
        colorAttachments: ['texD2'],
        inputs: ['texC'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'pass_E',
        colorAttachments: ['backbuffer'],
        inputs: ['texD1', 'texD2'],
      ));

      final compiled = graph.compile();
      final names = compiled.map((p) => p.name).toList();

      expect(names.length, 7);
      expect(names.first, 'pass_A');
      expect(names.last, 'pass_E');

      // Verify intermediate constraints
      expect(names.indexOf('pass_A'), lessThan(names.indexOf('pass_B1')));
      expect(names.indexOf('pass_A'), lessThan(names.indexOf('pass_B2')));
      expect(names.indexOf('pass_B1'), lessThan(names.indexOf('pass_C')));
      expect(names.indexOf('pass_B2'), lessThan(names.indexOf('pass_C')));
      expect(names.indexOf('pass_C'), lessThan(names.indexOf('pass_D1')));
      expect(names.indexOf('pass_C'), lessThan(names.indexOf('pass_D2')));
      expect(names.indexOf('pass_D1'), lessThan(names.indexOf('pass_E')));
      expect(names.indexOf('pass_D2'), lessThan(names.indexOf('pass_E')));
    });

    test('asymmetric diamond with long chain on one branch', () {
      final graph = RenderGraph();
      graph.addAttachment(const AttachmentDescriptor(name: 'tex_root'));
      graph.addAttachment(const AttachmentDescriptor(name: 'tex_short'));
      graph.addAttachment(const AttachmentDescriptor(name: 'tex_c1'));
      graph.addAttachment(const AttachmentDescriptor(name: 'tex_c2'));
      graph.addAttachment(const AttachmentDescriptor(name: 'tex_c3'));
      graph.addAttachment(const AttachmentDescriptor(name: 'tex_c4'));
      graph.addAttachment(const AttachmentDescriptor(name: 'backbuffer'));

      graph.addPass(const RenderPassDescriptor(
        name: 'root',
        colorAttachments: ['tex_root'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'short_branch',
        colorAttachments: ['tex_short'],
        inputs: ['tex_root'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'chain_1',
        colorAttachments: ['tex_c1'],
        inputs: ['tex_root'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'chain_2',
        colorAttachments: ['tex_c2'],
        inputs: ['tex_c1'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'chain_3',
        colorAttachments: ['tex_c3'],
        inputs: ['tex_c2'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'chain_4',
        colorAttachments: ['tex_c4'],
        inputs: ['tex_c3'],
      ));
      graph.addPass(const RenderPassDescriptor(
        name: 'sink',
        colorAttachments: ['backbuffer'],
        inputs: ['tex_short', 'tex_c4'],
      ));

      final compiled = graph.compile();
      final names = compiled.map((p) => p.name).toList();

      expect(names.length, 7);
      expect(names.first, 'root');
      expect(names.last, 'sink');
      expect(names.indexOf('chain_1'), lessThan(names.indexOf('chain_2')));
      expect(names.indexOf('chain_2'), lessThan(names.indexOf('chain_3')));
      expect(names.indexOf('chain_3'), lessThan(names.indexOf('chain_4')));
      expect(names.indexOf('chain_4'), lessThan(names.indexOf('sink')));
      expect(names.indexOf('short_branch'), lessThan(names.indexOf('sink')));
    });
  });

  group('Adversarial Testing: Disjoint Subgraphs', () {
    test('disjoint components with pruneDeadPasses: false compiles all deterministically', () {
      final graph = RenderGraph();
      // Component 1: A -> B -> backbuffer
      graph.addAttachment(const AttachmentDescriptor(name: 'tex1'));
      graph.addAttachment(const AttachmentDescriptor(name: 'backbuffer'));
      graph.addPass(const RenderPassDescriptor(name: 'comp1_a', colorAttachments: ['tex1']));
      graph.addPass(const RenderPassDescriptor(name: 'comp1_b', colorAttachments: ['backbuffer'], inputs: ['tex1']));

      // Component 2: C -> D (completely detached)
      graph.addAttachment(const AttachmentDescriptor(name: 'tex2'));
      graph.addAttachment(const AttachmentDescriptor(name: 'tex3'));
      graph.addPass(const RenderPassDescriptor(name: 'comp2_c', colorAttachments: ['tex2']));
      graph.addPass(const RenderPassDescriptor(name: 'comp2_d', colorAttachments: ['tex3'], inputs: ['tex2']));

      // Component 3: Isolated pass E with no inputs or outputs
      graph.addPass(const RenderPassDescriptor(name: 'comp3_e'));

      final compiled = graph.compile(pruneDeadPasses: false);
      final names = compiled.map((p) => p.name).toList();

      expect(names.length, 5);
      expect(names, containsAll(['comp1_a', 'comp1_b', 'comp2_c', 'comp2_d', 'comp3_e']));
      expect(names.indexOf('comp1_a'), lessThan(names.indexOf('comp1_b')));
      expect(names.indexOf('comp2_c'), lessThan(names.indexOf('comp2_d')));
    });

    test('disjoint components with pruneDeadPasses: true prunes unreferenced components', () {
      final graph = RenderGraph();
      graph.addAttachment(const AttachmentDescriptor(name: 'activeTex'));
      graph.addAttachment(const AttachmentDescriptor(name: 'backbuffer'));
      graph.addAttachment(const AttachmentDescriptor(name: 'offscreenTex'));

      graph.addPass(const RenderPassDescriptor(name: 'live_producer', colorAttachments: ['activeTex']));
      graph.addPass(const RenderPassDescriptor(name: 'live_present', colorAttachments: ['backbuffer'], inputs: ['activeTex']));
      graph.addPass(const RenderPassDescriptor(name: 'dead_compute', colorAttachments: ['offscreenTex']));

      final compiled = graph.compile(pruneDeadPasses: true);
      final names = compiled.map((p) => p.name).toList();

      expect(names, equals(['live_producer', 'live_present']));
      expect(names.contains('dead_compute'), isFalse);
    });
  });

  group('Adversarial Testing: Cycle Detection & Reporting', () {
    test('self-loop via dependency throws RenderGraphCycleException during compile and validate', () {
      final graph = RenderGraph();
      graph.addPass(const RenderPassDescriptor(
        name: 'self_dependent',
        dependencies: ['self_dependent'],
      ));

      expect(
        () => graph.compile(pruneDeadPasses: false),
        throwsA(isA<RenderGraphCycleException>().having(
          (e) => e.cycle,
          'cycle',
          equals(['self_dependent', 'self_dependent']),
        )),
      );

      expect(
        () => graph.validate(),
        throwsA(isA<RenderGraphCycleException>()),
      );
    });

    test('tight 2-node cycle: A <-> B reports exact cycle path', () {
      final graph = RenderGraph();
      graph.addPass(const RenderPassDescriptor(name: 'node_A', dependencies: ['node_B']));
      graph.addPass(const RenderPassDescriptor(name: 'node_B', dependencies: ['node_A']));

      expect(
        () => graph.compile(pruneDeadPasses: false),
        throwsA(isA<RenderGraphCycleException>().having(
          (e) => e.message,
          'message',
          matches(r'node_A -> node_B -> node_A|node_B -> node_A -> node_B'),
        )),
      );
    });

    test('3-node cycle via RAW attachment dependencies', () {
      final graph = RenderGraph();
      graph.addAttachment(const AttachmentDescriptor(name: 't1'));
      graph.addAttachment(const AttachmentDescriptor(name: 't2'));
      graph.addAttachment(const AttachmentDescriptor(name: 't3'));

      // P1 writes t1, reads t3
      graph.addPass(const RenderPassDescriptor(name: 'p1', colorAttachments: ['t1'], inputs: ['t3']));
      // P2 writes t2, reads t1
      graph.addPass(const RenderPassDescriptor(name: 'p2', colorAttachments: ['t2'], inputs: ['t1']));
      // P3 writes t3, reads t2
      graph.addPass(const RenderPassDescriptor(name: 'p3', colorAttachments: ['t3'], inputs: ['t2']));

      expect(
        () => graph.compile(pruneDeadPasses: false),
        throwsA(isA<RenderGraphCycleException>()),
      );
    });

    test('deep 20-node cyclic graph detected without stack overflow', () {
      final graph = RenderGraph();
      const count = 20;

      for (int i = 0; i < count; i++) {
        final nextIdx = (i + 1) % count;
        graph.addPass(RenderPassDescriptor(
          name: 'ring_node_$i',
          dependencies: ['ring_node_$nextIdx'],
        ));
      }

      expect(
        () => graph.compile(pruneDeadPasses: false),
        throwsA(isA<RenderGraphCycleException>().having(
          (e) => e.cycle.length,
          'cycle length',
          greaterThanOrEqualTo(count),
        )),
      );
    });

    test('butterfly/figure-8 dual-loop cycle detection', () {
      // Loop 1: A -> B -> C -> A
      // Loop 2: C -> D -> E -> C
      final graph = RenderGraph();
      graph.addPass(const RenderPassDescriptor(name: 'loopA', dependencies: ['loopC']));
      graph.addPass(const RenderPassDescriptor(name: 'loopB', dependencies: ['loopA']));
      graph.addPass(const RenderPassDescriptor(name: 'loopC', dependencies: ['loopB', 'loopE']));
      graph.addPass(const RenderPassDescriptor(name: 'loopD', dependencies: ['loopC']));
      graph.addPass(const RenderPassDescriptor(name: 'loopE', dependencies: ['loopD']));

      expect(
        () => graph.compile(pruneDeadPasses: false),
        throwsA(isA<RenderGraphCycleException>()),
      );
    });
  });

  group('Adversarial Testing: Large Trees & Dead-Pass Pruning Stress Test', () {
    test('stress test: binary tree with 127 passes where only 1 branch is live', () {
      final graph = RenderGraph();

      // Create a 7-level binary tree of passes (nodes 1..127)
      // Level 1: Node 1 (Root, writes backbuffer)
      // Node k has children 2k and 2k+1
      // Only the leftmost branch (1, 2, 4, 8, 16, 32, 64) is wired to backbuffer
      const totalNodes = 127;
      for (int i = 1; i <= totalNodes; i++) {
        final attName = 'att_$i';
        graph.addAttachment(AttachmentDescriptor(name: attName));

        if (i == 1) {
          graph.addAttachment(const AttachmentDescriptor(name: 'backbuffer'));
          graph.addPass(const RenderPassDescriptor(
            name: 'pass_1',
            colorAttachments: ['backbuffer'],
            inputs: ['att_2'], // Only depends on left child
          ));
        } else {
          final isLeftChildOfLeft = (i & (i - 1)) == 0; // Powers of 2: 2, 4, 8, 16, 32, 64
          final leftChild = i * 2;
          final inputs = (isLeftChildOfLeft && leftChild <= totalNodes) ? ['att_$leftChild'] : <String>[];

          graph.addPass(RenderPassDescriptor(
            name: 'pass_$i',
            colorAttachments: [attName],
            inputs: inputs,
          ));
        }
      }

      // Compile with pruning
      final compiled = graph.compile(pruneDeadPasses: true);
      final names = compiled.map((p) => p.name).toSet();

      // The active branch should contain exactly passes: 1, 2, 4, 8, 16, 32, 64 (7 passes)
      final expectedLive = {'pass_1', 'pass_2', 'pass_4', 'pass_8', 'pass_16', 'pass_32', 'pass_64'};
      expect(names, equals(expectedLive));
      expect(compiled.length, 7);

      // Verify topological order of live branch (bottom-up: 64 -> 32 -> 16 -> 8 -> 4 -> 2 -> 1)
      final listNames = compiled.map((p) => p.name).toList();
      expect(listNames, equals(['pass_64', 'pass_32', 'pass_16', 'pass_8', 'pass_4', 'pass_2', 'pass_1']));
    });

    test('stress test: 200-node linear dependency chain compiles within milliseconds', () {
      final graph = RenderGraph();
      const length = 200;

      for (int i = 0; i < length; i++) {
        final attName = i == length - 1 ? 'backbuffer' : 'chain_tex_$i';
        graph.addAttachment(AttachmentDescriptor(name: attName));

        final inputs = i == 0 ? <String>[] : ['chain_tex_${i - 1}'];
        graph.addPass(RenderPassDescriptor(
          name: 'chain_pass_$i',
          colorAttachments: [attName],
          inputs: inputs,
        ));
      }

      final stopwatch = Stopwatch()..start();
      final compiled = graph.compile(pruneDeadPasses: true);
      stopwatch.stop();

      expect(compiled.length, length);
      expect(compiled.first.name, 'chain_pass_0');
      expect(compiled.last.name, 'chain_pass_${length - 1}');
      expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // Highly performant
    });

    test('headless graph without backbuffer discovers root candidate passes', () {
      final graph = RenderGraph();
      graph.addAttachment(const AttachmentDescriptor(name: 'texA'));
      graph.addAttachment(const AttachmentDescriptor(name: 'texB'));

      // Headless pass produces texB (unconsumed)
      graph.addPass(const RenderPassDescriptor(name: 'pA', colorAttachments: ['texA']));
      graph.addPass(const RenderPassDescriptor(name: 'pB', colorAttachments: ['texB'], inputs: ['texA']));

      // Neither pass writes to 'backbuffer', so fallback live pass discovery finds pB as root candidate
      final compiled = graph.compile(pruneDeadPasses: true);
      final names = compiled.map((p) => p.name).toList();

      expect(names, equals(['pA', 'pB']));
    });
  });
}
