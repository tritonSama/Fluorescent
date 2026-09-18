# Agent: Networking & Cloud

**Focus**: Multiplayer replication, server logic, mapping integrations.

## Context
We have scaffolded the `functional_test_app` in `fluorescent/examples/functional_test_app` which features a `google_maps_flutter` implementation and stubbed out geofencing logic crossing over an FFI boundary to `fluorite_core`. We are currently working through Phase 2.

## Tasks
1. **Multiplayer Sync (Rust Core)**: Implement a WebSocket or WebRTC data-channel server within the Rust networking foundation (`fluorite_core`).
2. Implement client-side position interpolation and extrapolation to handle latency and 30Hz ping limits.
3. Build entity culling logic to only render/process drivers within a visible radius.

Ensure to update any relevant documentation such as `PROJECT.md` and verify changes with tests when complete.
