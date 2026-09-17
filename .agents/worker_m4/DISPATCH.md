## 2026-09-17T03:42:44Z
You are worker_m4, a Worker agent.
Your working directory is: c:\Users\blue-\projects\Fluorescent\.agents\worker_m4
Your parent orchestrator is: 3e5e2dab-1a8d-4421-8c4a-2cf0334d1240

MANDATORY FIRST STEP: Read the user's authoritative request at c:\Users\blue-\projects\Fluorescent\.agents\ORIGINAL_REQUEST.md and PROJECT.md at c:\Users\blue-\projects\Fluorescent\PROJECT.md.
Also read explorer findings at: c:\Users\blue-\projects\Fluorescent\.agents\explorer_survey_2\handoff.md.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

SCOPE & WRITE OWNERSHIP (Exclusive):
- `fluorescent/packages/fluorescent_core/lib/src/rendering/render_graph.dart`
- `fluorescent/packages/fluorescent_core/lib/src/rendering/render_graph_schema.dart`
- `fluorescent/packages/fluorescent_core/lib/src/rendering/render_pass.dart`
- `fluorescent/packages/fluorescent_core/test/render_graph_test.dart`

TASK:
Implement Milestone 4 (Data-Driven RenderGraph):
1. Implement `AttachmentDescriptor` (name, type, format, size/scale, loadOp, storeOp, clearColor, clearDepth).
2. Implement `RenderPassDescriptor` (name, type, colorAttachments, depthStencilAttachment, inputs, dependencies, shader).
3. Implement `RenderGraph` in `fluorescent_core`:
   - Parse JSON (and YAML-compatible map) schema.
   - Build dependency DAG.
   - Detect cycles with descriptive `RenderGraphCycleException`.
   - Perform topological sorting (Kahn's algorithm) to compute execution order.
   - Prune dead passes not contributing to outputs/backbuffer.
4. Write test in `fluorescent/packages/fluorescent_core/test/render_graph_test.dart`.
5. Run `flutter test test/render_graph_test.dart` inside `fluorescent/packages/fluorescent_core` and ensure all tests pass.

Maintain progress.md, write handoff.md with test execution evidence, and notify parent via send_message when done.
