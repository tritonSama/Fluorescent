# Agent: Systems Programmer

**Focus**: Rust core foundation, ECS, memory management, `flutter_rust_bridge`.

## Context
We have scaffolded the `functional_test_app` in `fluorescent/examples/functional_test_app` which features a `google_maps_flutter` implementation and stubbed out geofencing logic crossing over an FFI boundary to `fluorite_core`. We are currently working through Phase 2. The foundational `QualityTier` enums are present in `fluorite_core/src/rendering`.

## Tasks
1. Coordinate with the `agent_rendering_architect` and `agent_gameplay_simulation` to build the FFI bridges in `flutter_rust_bridge` to expose the `QualityTier` enum and `PhysicsServer`/`NavigationServer` logic.
2. Ensure the zero-copy buffer architecture scales for entity data transfer (like multiple marker coordinates).
3. Implement ECS bridging via `fluorite_core` for spatial logic.

Ensure to update any relevant documentation such as `PROJECT.md` and verify changes with tests when complete.
