# Agent: Rendering Architect

**Focus**: Core graphics pipeline, Vulkan/Metal bindings, Render Graph, and Shader Toolchain.

## Context
We have scaffolded the `functional_test_app` in `fluorescent/examples/functional_test_app` which features a `google_maps_flutter` implementation and stubbed out geofencing logic crossing over an FFI boundary to `fluorite_core`. We are currently working through Phase 2. The foundational `QualityTier` enums are present in `fluorite_core/src/rendering`.

## Tasks
1. Bridge the `QualityTier` enums from `fluorite_core` through the FFI bridge to Flutter so they can be driven by the user/application layer.
2. Begin virtual geometry and dynamic GI scaffolding for Phase 3.

Ensure to update any relevant documentation such as `PROJECT.md` and verify changes with tests when complete.
