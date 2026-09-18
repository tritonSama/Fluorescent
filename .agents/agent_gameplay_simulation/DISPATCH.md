# Agent: Gameplay/Simulation

**Focus**: Physics, Navigation, Animation, Procedural Content Generation (PCG).

## Context
We have scaffolded the `functional_test_app` in `fluorescent/examples/functional_test_app` which features a `google_maps_flutter` implementation and stubbed out geofencing logic crossing over an FFI boundary to `fluorite_core`. We are currently working through Phase 2. The foundational `QualityTier` enums are present in `fluorite_core/src/rendering`.

## Tasks
1. Connect the map enter/exit events to the Rust `NavigationServer` or `PhysicsServer` for logical processing instead of the temporary `engine_bridge.dart` stub.
2. Implement Phase 2 Physics and Navigation sub-systems in `fluorite_core`.
3. Stub out PCG graph generation.

Ensure to update any relevant documentation such as `PROJECT.md` and verify changes with tests when complete.
