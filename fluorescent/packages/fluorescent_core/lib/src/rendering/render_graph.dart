import 'dart:collection';
import 'render_graph_schema.dart';
import 'render_pass.dart';

/// Exception thrown when a cyclic dependency is detected in the [RenderGraph].
class RenderGraphCycleException implements Exception {
  final String message;
  final List<String> cycle;

  RenderGraphCycleException(this.message, {this.cycle = const []});

  @override
  String toString() => 'RenderGraphCycleException: $message';
}

/// Exception thrown when [RenderGraph] validation fails.
class RenderGraphValidationException implements Exception {
  final String message;

  RenderGraphValidationException(this.message);

  @override
  String toString() => 'RenderGraphValidationException: $message';
}

/// Data-driven Render Graph that orchestrates render passes and resource attachments
/// into a deterministic Directed Acyclic Graph (DAG) for GPU execution.
class RenderGraph {
  final Map<String, AttachmentDescriptor> _attachments;
  final Map<String, RenderPassDescriptor> _passes;
  final Map<String, RenderPass> _executablePasses;
  String outputAttachment;

  RenderGraph({
    Map<String, AttachmentDescriptor>? attachments,
    Map<String, RenderPassDescriptor>? passes,
    Map<String, RenderPass>? executablePasses,
    this.outputAttachment = 'backbuffer',
  })  : _attachments = attachments != null
            ? Map<String, AttachmentDescriptor>.from(attachments)
            : <String, AttachmentDescriptor>{},
        _passes = passes != null
            ? Map<String, RenderPassDescriptor>.from(passes)
            : <String, RenderPassDescriptor>{},
        _executablePasses = executablePasses != null
            ? Map<String, RenderPass>.from(executablePasses)
            : <String, RenderPass>{};

  /// Parse a [RenderGraph] from a JSON-compatible [Map].
  factory RenderGraph.fromJson(Map<String, dynamic> json) {
    return RenderGraphSchema.parseMap(json);
  }

  /// Parse a [RenderGraph] from a JSON string.
  factory RenderGraph.fromJsonString(String jsonString) {
    return RenderGraphSchema.parseJson(jsonString);
  }

  /// Parse a [RenderGraph] from a YAML or YAML-compatible string.
  factory RenderGraph.fromYaml(String yamlString) {
    return RenderGraphSchema.parseYaml(yamlString);
  }

  /// Parse a [RenderGraph] from a raw Map (JSON or YAML).
  factory RenderGraph.fromMap(Map<dynamic, dynamic> map) {
    return RenderGraphSchema.parseMap(map);
  }

  /// Read-only map of registered attachments.
  Map<String, AttachmentDescriptor> get attachments =>
      UnmodifiableMapView(_attachments);

  /// Read-only map of registered pass descriptors.
  Map<String, RenderPassDescriptor> get passes => UnmodifiableMapView(_passes);

  /// Add an attachment descriptor to the graph.
  void addAttachment(AttachmentDescriptor attachment) {
    _attachments[attachment.name] = attachment;
  }

  /// Add a render pass descriptor to the graph, optionally pairing with an executable pass.
  void addPass(RenderPassDescriptor pass, {RenderPass? executablePass}) {
    _passes[pass.name] = pass;
    if (executablePass != null) {
      _executablePasses[pass.name] = executablePass;
    }
  }

  /// Register or replace an executable implementation for a pass.
  void registerExecutablePass(String passName, RenderPass pass) {
    if (!_passes.containsKey(passName)) {
      _passes[passName] = pass.descriptor;
    }
    _executablePasses[passName] = pass;
  }

  /// Retrieve an attachment by name.
  AttachmentDescriptor? getAttachment(String name) => _attachments[name];

  /// Retrieve a pass descriptor by name.
  RenderPassDescriptor? getPass(String name) => _passes[name];

  /// Remove a pass from the graph by name.
  bool removePass(String name) {
    _executablePasses.remove(name);
    return _passes.remove(name) != null;
  }

  /// Remove an attachment from the graph by name.
  bool removeAttachment(String name) {
    return _attachments.remove(name) != null;
  }

  /// Validate graph integrity:
  /// - All referenced attachments in passes must be defined.
  /// - Depth-stencil attachments must have depth type.
  /// - All explicit dependencies must exist.
  /// - Graph must not contain any cyclic dependencies.
  void validate() {
    for (final pass in _passes.values) {
      // Validate color attachments
      for (final colorAtt in pass.colorAttachments) {
        if (!_attachments.containsKey(colorAtt)) {
          throw RenderGraphValidationException(
              'Pass "${pass.name}" references undefined color attachment "$colorAtt"');
        }
      }

      // Validate depth stencil attachment
      if (pass.depthStencilAttachment != null) {
        final depthAtt = _attachments[pass.depthStencilAttachment];
        if (depthAtt == null) {
          throw RenderGraphValidationException(
              'Pass "${pass.name}" references undefined depth attachment "${pass.depthStencilAttachment}"');
        }
        if (depthAtt.type != AttachmentType.depth) {
          throw RenderGraphValidationException(
              'Pass "${pass.name}" depth attachment "${pass.depthStencilAttachment}" must have type "depth", found "${depthAtt.type.name}"');
        }
      }

      // Validate input attachments
      for (final inputAtt in pass.inputs) {
        if (!_attachments.containsKey(inputAtt)) {
          throw RenderGraphValidationException(
              'Pass "${pass.name}" references undefined input attachment "$inputAtt"');
        }
      }

      // Validate dependencies
      for (final dep in pass.dependencies) {
        if (!_passes.containsKey(dep)) {
          throw RenderGraphValidationException(
              'Pass "${pass.name}" references undefined dependency pass "$dep"');
        }
        if (dep == pass.name) {
          throw RenderGraphCycleException(
            'Self-referential dependency in pass "${pass.name}"',
            cycle: [pass.name, pass.name],
          );
        }
      }
    }

    // Check for cycles across all passes
    _detectCyclesAndThrow(_passes.keys.toSet());
  }

  /// Compile the RenderGraph into a linearly ordered list of [RenderPassDescriptor]s.
  ///
  /// Steps:
  /// 1. Dead pass elimination: prunes passes not contributing to [outputAttachment].
  /// 2. Builds dependency DAG combining explicit dependencies and attachment Read-After-Write (RAW) data dependencies.
  /// 3. Detects cycles and throws [RenderGraphCycleException] if any cycle is present.
  /// 4. Executes Kahn's algorithm for deterministic topological sorting.
  List<RenderPassDescriptor> compile({
    String? outputAttachment,
    bool pruneDeadPasses = true,
  }) {
    final targetOutput = outputAttachment ?? this.outputAttachment;

    // Step 1: Identify active passes (dead pass pruning)
    final Set<String> activePassNames;
    if (pruneDeadPasses) {
      activePassNames = _findLivePasses(targetOutput);
    } else {
      activePassNames = Set<String>.from(_passes.keys);
    }

    if (activePassNames.isEmpty) {
      return const <RenderPassDescriptor>[];
    }

    // Step 2: Build dependency graph edges
    final outgoingEdges = <String, Set<String>>{
      for (final name in activePassNames) name: <String>{},
    };
    final incomingEdges = <String, Set<String>>{
      for (final name in activePassNames) name: <String>{},
    };

    // Map attachments to the passes that write to them
    final attachmentWriters = <String, Set<String>>{};
    for (final passName in activePassNames) {
      final pass = _passes[passName]!;
      for (final color in pass.colorAttachments) {
        attachmentWriters.putIfAbsent(color, () => <String>{}).add(passName);
      }
      if (pass.depthStencilAttachment != null) {
        attachmentWriters
            .putIfAbsent(pass.depthStencilAttachment!, () => <String>{})
            .add(passName);
      }
    }

    for (final consumerName in activePassNames) {
      final consumer = _passes[consumerName]!;

      // 1. Explicit pass dependencies
      for (final depName in consumer.dependencies) {
        if (activePassNames.contains(depName)) {
          outgoingEdges[depName]!.add(consumerName);
          incomingEdges[consumerName]!.add(depName);
        }
      }

      // 2. Data dependencies: Read-After-Write (RAW)
      for (final inputName in consumer.inputs) {
        final writers = attachmentWriters[inputName];
        if (writers != null) {
          for (final writerName in writers) {
            if (writerName != consumerName) {
              outgoingEdges[writerName]!.add(consumerName);
              incomingEdges[consumerName]!.add(writerName);
            }
          }
        }
      }
    }

    // Step 3: Cycle detection using DFS with full cycle path reporting
    _detectCyclesInEdgesAndThrow(activePassNames, outgoingEdges);

    // Step 4: Topological sorting using Kahn's algorithm
    final inDegree = <String, int>{
      for (final name in activePassNames) name: incomingEdges[name]!.length,
    };

    final readyQueue = SplayTreeSet<String>((a, b) => a.compareTo(b));
    for (final entry in inDegree.entries) {
      if (entry.value == 0) {
        readyQueue.add(entry.key);
      }
    }

    final executionOrder = <RenderPassDescriptor>[];

    while (readyQueue.isNotEmpty) {
      final current = readyQueue.first;
      readyQueue.remove(current);
      executionOrder.add(_passes[current]!);

      for (final neighbor in outgoingEdges[current]!) {
        final newDegree = inDegree[neighbor]! - 1;
        inDegree[neighbor] = newDegree;
        if (newDegree == 0) {
          readyQueue.add(neighbor);
        }
      }
    }

    if (executionOrder.length != activePassNames.length) {
      throw RenderGraphCycleException(
        'Cycle detected in RenderGraph during Kahn topological sort',
      );
    }

    return executionOrder;
  }

  /// Execute the compiled render graph in topological order.
  void execute(
    RenderContext context, {
    String? outputAttachment,
    bool pruneDeadPasses = true,
  }) {
    final compiledPasses = compile(
      outputAttachment: outputAttachment,
      pruneDeadPasses: pruneDeadPasses,
    );

    for (final passDesc in compiledPasses) {
      final executable =
          _executablePasses[passDesc.name] ?? RenderPass(descriptor: passDesc);
      executable.execute(context);
    }
  }

  /// Identify all passes that contribute to [targetOutput] directly or indirectly.
  Set<String> _findLivePasses(String targetOutput) {
    // Map attachments to the passes that write them
    final attachmentWriters = <String, Set<String>>{};
    for (final pass in _passes.values) {
      for (final color in pass.colorAttachments) {
        attachmentWriters.putIfAbsent(color, () => <String>{}).add(pass.name);
      }
      if (pass.depthStencilAttachment != null) {
        attachmentWriters
            .putIfAbsent(pass.depthStencilAttachment!, () => <String>{})
            .add(pass.name);
      }
    }

    // Identify root passes that write directly to the target output
    final rootPasses = <String>{};
    final writersToTarget = attachmentWriters[targetOutput];
    if (writersToTarget != null && writersToTarget.isNotEmpty) {
      rootPasses.addAll(writersToTarget);
    } else {
      // If no pass writes to the target output (e.g. headless graph or terminal outputs),
      // treat passes whose outputs are not consumed as root candidates
      final consumedAttachments = <String>{};
      for (final p in _passes.values) {
        consumedAttachments.addAll(p.inputs);
      }

      for (final p in _passes.values) {
        final writes = <String>{
          ...p.colorAttachments,
          if (p.depthStencilAttachment != null) p.depthStencilAttachment!,
        };
        // If pass produces outputs that are not consumed, or has no outputs (e.g. side-effecting compute)
        if (writes.isEmpty || writes.any((w) => !consumedAttachments.contains(w))) {
          rootPasses.add(p.name);
        }
      }
    }

    // Traverse backwards from root passes to collect all required passes
    final livePasses = <String>{};
    final queue = Queue<String>();

    for (final root in rootPasses) {
      livePasses.add(root);
      queue.add(root);
    }

    while (queue.isNotEmpty) {
      final currentPassName = queue.removeFirst();
      final pass = _passes[currentPassName];
      if (pass == null) continue;

      // 1. Explicit dependencies
      for (final depName in pass.dependencies) {
        if (_passes.containsKey(depName) && !livePasses.contains(depName)) {
          livePasses.add(depName);
          queue.add(depName);
        }
      }

      // 2. Passes that wrote to attachments read by this pass
      for (final inputName in pass.inputs) {
        final writers = attachmentWriters[inputName];
        if (writers != null) {
          for (final writer in writers) {
            if (!livePasses.contains(writer)) {
              livePasses.add(writer);
              queue.add(writer);
            }
          }
        }
      }
    }

    return livePasses;
  }

  /// Detect cycles across a set of pass names by building full edges and running DFS.
  void _detectCyclesAndThrow(Set<String> passNames) {
    final outgoingEdges = <String, Set<String>>{
      for (final name in passNames) name: <String>{},
    };

    final attachmentWriters = <String, Set<String>>{};
    for (final passName in passNames) {
      final pass = _passes[passName]!;
      for (final color in pass.colorAttachments) {
        attachmentWriters.putIfAbsent(color, () => <String>{}).add(passName);
      }
      if (pass.depthStencilAttachment != null) {
        attachmentWriters
            .putIfAbsent(pass.depthStencilAttachment!, () => <String>{})
            .add(passName);
      }
    }

    for (final consumerName in passNames) {
      final consumer = _passes[consumerName]!;
      for (final depName in consumer.dependencies) {
        if (passNames.contains(depName)) {
          outgoingEdges[depName]!.add(consumerName);
        }
      }
      for (final inputName in consumer.inputs) {
        final writers = attachmentWriters[inputName];
        if (writers != null) {
          for (final writer in writers) {
            if (writer != consumerName && passNames.contains(writer)) {
              outgoingEdges[writer]!.add(consumerName);
            }
          }
        }
      }
    }

    _detectCyclesInEdgesAndThrow(passNames, outgoingEdges);
  }

  /// DFS cycle detection using 3-color node states (unvisited, visiting, visited).
  void _detectCyclesInEdgesAndThrow(
    Set<String> nodes,
    Map<String, Set<String>> outgoingEdges,
  ) {
    const unvisited = 0;
    const visiting = 1;
    const visited = 2;

    final state = <String, int>{for (final node in nodes) node: unvisited};
    final parent = <String, String>{};

    List<String>? detectedCycle;

    bool dfs(String u) {
      state[u] = visiting;

      // Sort outgoing neighbors for deterministic cycle reporting
      final neighbors = outgoingEdges[u]?.toList() ?? [];
      neighbors.sort();

      for (final v in neighbors) {
        if (state[v] == visiting) {
          // Cycle found! Reconstruct cycle path
          final cycle = <String>[v];
          String? curr = u;
          while (curr != null && curr != v) {
            cycle.add(curr);
            curr = parent[curr];
          }
          cycle.add(v);
          detectedCycle = cycle.reversed.toList();
          return true;
        } else if (state[v] == unvisited) {
          parent[v] = u;
          if (dfs(v)) return true;
        }
      }

      state[u] = visited;
      return false;
    }

    final sortedNodes = nodes.toList()..sort();
    for (final node in sortedNodes) {
      if (state[node] == unvisited) {
        if (dfs(node)) break;
      }
    }

    if (detectedCycle != null) {
      throw RenderGraphCycleException(
        'Cycle detected in RenderGraph: ${detectedCycle!.join(' -> ')}',
        cycle: detectedCycle!,
      );
    }
  }
}
