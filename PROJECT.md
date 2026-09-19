# Project: Fluorescent 3D Engine Core Architectural Pillars

## Architecture
Fluorescent is a high-performance 3D engine monorepo for Flutter, Flame, Web, and native platforms.
The architecture is decoupled into distinct subsystems:
- `fluorescent_core`: Hosts the scene graph, resource management, render graph, and server abstractions (`RenderingServer`, `PhysicsServer`, `NavigationServer`) coordinated by `ServerManager` via Dart Isolates.
- `fluorescent_ecs`: High-performance Data-Oriented Entity Component System backed by contiguous `Float32List` arrays using a Sparse-Set design for zero GC pressure during frame iterations.
- `tools/asset_pipeline`: Standalone Dart CLI tool compiling `.gltf` meshes and `.wgsl` shaders into a compressed `.fworld` binary format, embedding transpiled multi-target bytecode (SPIR-V and MSL) via a dual-mode FFI/Demo shader toolchain.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Server Interfaces | `PhysicsServer` and `NavigationServer` abstract interfaces alongside `RenderingServer` with Godot-inspired handle IDs | M1 | ORIGINAL_REQUEST §R1 |
| 2 | ServerManager Isolates | Multi-isolate coordination using `Isolate.spawn`, bidirectional ports, non-blocking command/query protocol | M1 | ORIGINAL_REQUEST §R1 |
| 3 | Server Concurrency Verification | Automated test verifying Dart Isolates spawn and communicate without blocking main thread | M1 | ORIGINAL_REQUEST §Verification |
| 4 | Resource Reference Counting | `Resource`, `TextureResource`, `MeshResource`, `MaterialResource` with retain/release lifecycle | M2 | ORIGINAL_REQUEST §R3 |
| 5 | GPU Memory Management | `ResourceManager` caching, GPU memory tracking, cascading texture release on material disposal | M2 | ORIGINAL_REQUEST §R3 |
| 6 | Mock Texture Lifecycle Test | Automated test verifying mock texture loading, ref count increment, and free on destroy | M2 | ORIGINAL_REQUEST §Verification |
| 7 | Contiguous TypedData ECS Storage | Sparse-Set contiguous `Float32List` array storage with 16-float stride for Transforms in `fluorescent_ecs` | M3 | ORIGINAL_REQUEST §R3 |
| 8 | ECS 10k Benchmark Test | Spawning and iterating over 10,000 entities using TypedData without throwing memory errors | M3 | ORIGINAL_REQUEST §Verification |
| 9 | Data-driven RenderGraph | JSON/YAML configurable RenderGraph with Attachment and Pass descriptors | M4 | ORIGINAL_REQUEST §R2 |
| 10 | RenderGraph DAG Resolution | Dependency resolution, cycle detection, and topological sort for pass execution order | M4 | ORIGINAL_REQUEST §R2 |
| 11 | Asset Pipeline CLI Tool | Standalone Dart CLI (`tools/asset_pipeline/bin/asset_pipeline.dart`) compiling `.gltf` and `.wgsl` | M5 | ORIGINAL_REQUEST §R2 |
| 12 | `.fworld` Binary Format | Compressed binary serialization (`FWLD` magic, TOC, mesh chunks, shader chunks) using gzip/zlib | M5 | ORIGINAL_REQUEST §R2 |
| 13 | Shader Toolchain FFI & Fallback | Naga/SPIRV-Cross FFI interface with demo fallback transpiler to SPIR-V (`0x07230203`) and MSL | M5 | ORIGINAL_REQUEST §R4 |
| 14 | Asset Pipeline Verification Test | Automated test confirming compilation of test `.gltf` and `.wgsl` into `.fworld` binary | M5 | ORIGINAL_REQUEST §Verification |
| 15 | E2E Integration Suite | Multi-tier opaque-box E2E test suite covering all 6 pillars and 4 acceptance criteria | M6 | ORIGINAL_REQUEST §Verification |


## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Server Architecture & Isolates | `PhysicsServer`, `NavigationServer`, `ServerManager` isolate message passing | None | DONE |
| M2 | Resource Management | `ResourceManager` reference counting, GPU memory budget, mock texture lifecycle | None | DONE |
| M3 | Contiguous TypedData ECS | `fluorescent_ecs` sparse-set `Float32List` storage, 10k entity benchmark | None | DONE |
| M4 | Data-Driven RenderGraph | `RenderGraph` JSON/YAML parsing, DAG cycle detection, topological sort | None | DONE |
| M5 | Asset Pipeline & Shaders | CLI tool, `.fworld` packaging, Naga/SPIRV-Cross FFI & demo shader transpiler | None | DONE |
| M6 | E2E Verification & Hardening | Pass 100% E2E tests (Tiers 1-4) followed by Phase 2 adversarial hardening (Tier 5) | M1, M2, M3, M4, M5 | DONE |

## Phase 1-6 Roadmap

### Phase 1 — Foundation
* Fluorite
* Rust core
* ECS
* Flutter integration
* Vulkan

### Phase 2 — Engine
* Rendering
* Physics
* Animation
* Audio
* Assets
* Scenes
* Input
* Scripting

### Phase 3 — AAA
* GPU-driven rendering
* Virtual geometry
* Dynamic GI
* Virtual shadows
* GPU VFX
* Advanced animation
* Destruction
* World streaming
* PCG

### Phase 4 — Online
* Replication
* Prediction
* Rollback
* Dedicated servers
* Matchmaking
* Voice
* Accounts
* Persistence

### Phase 5 — Developer ecosystem
* Editor
* Visual scripting
* Material editor
* Shader editor
* Animation editor
* VFX editor
* World editor
* Profiler
* Asset marketplace
* SDK

### Phase 6 — Android Desktop specialization
* Hardware detection
* Dynamic quality tiers
* Vulkan optimization
* Desktop windowing
* Gamepad
* Keyboard/mouse
* Multi-monitor
* High refresh rate
* HDR
* Upscaling
* Dynamic resolution
* Power/performance management


## Interface Contracts

### `fluorescent_core` Server Contract
- `Server`: Base class with `initialize()`, `step(double dt)`, `dispose()`.
- `PhysicsServer`: `createSpace()`, `createBody()`, `setBodyTransform()`, `applyForce()`, `raycast()`.
- `NavigationServer`: `createMap()`, `createRegion()`, `createAgent()`, `findPath()`.
- `ServerManager`: `initialize()`, `physics: PhysicsServer`, `navigation: NavigationServer`, `dispose()`. Background Isolate communicates via `ServerMessage` records.

### `fluorescent_core` Resource Contract
- `Resource`: `String id`, `int refCount`, `int byteSize`, `bool isDisposed`, `retain()`, `release()`, `dispose()`.
- `ResourceManager`: `acquire<T>()`, `release()`, `loadMockTexture()`, `totalGpuMemoryUsed`.

### `fluorescent_ecs` Storage Contract
- `TransformStorage`: Contiguous `Float32List` storage with 16 floats per entity:
  - `0..2`: Translation `(x, y, z)`
  - `3`: Flags/dirty
  - `4..7`: Quaternion `(x, y, z, w)`
  - `8..10`: Scale `(sx, sy, sz)`
  - `11..15`: Reserved/bounds
- `EcsWorld`: `createEntity()`, `destroyEntity()`, `TransformStorage transforms`.

### `RenderGraph` Contract
- `RenderGraph`: `fromJson(Map<String, dynamic>)`, `compile() -> List<RenderPassDescriptor>`, `validate()`.

### Asset Pipeline & `.fworld` Contract
- CLI command: `dart run tools/asset_pipeline/bin/asset_pipeline.dart --gltf <path> --shader <path> --output <path>`
- Binary format: Magic `0x46, 0x57, 0x4C, 0x44` ("FWLD"), version uint32, compression uint32, uncompressed size uint32, payload.
- `ShaderTranspiler`: `transpileWgsl({required String wgslSource}) -> ShaderBundle(wgsl, spirv, msl)`.

## Code Layout
- `fluorescent/packages/fluorescent_core/lib/src/servers/`: `server.dart`, `server_manager.dart`
- `fluorescent/packages/fluorescent_core/lib/src/physics/`: `physics_server.dart`
- `fluorescent/packages/fluorescent_core/lib/src/navigation/`: `navigation_server.dart`
- `fluorescent/packages/fluorescent_core/lib/src/resources/`: `resource.dart`, `resource_manager.dart`, `texture_resource.dart`, `mesh_resource.dart`, `material_resource.dart`
- `fluorescent/packages/fluorescent_core/lib/src/rendering/`: `render_graph.dart`, `render_graph_schema.dart`
- `fluorescent/packages/fluorescent_ecs/lib/src/`: `entity.dart`, `storage/sparse_set.dart`, `storage/typed_component_storage.dart`, `world.dart`
- `fluorescent/tools/asset_pipeline/`: `pubspec.yaml`, `bin/asset_pipeline.dart`, `lib/gltf_compiler.dart`, `lib/fworld_writer.dart`, `lib/shader_toolchain/`
- `fluorescent/packages/fluorescent_core/test/`: `server_architecture_test.dart`, `resource_manager_test.dart`, `render_graph_test.dart`
- `fluorescent/packages/fluorescent_ecs/test/`: `ecs_benchmark_test.dart`, `ecs_test.dart`
- `fluorescent/tools/asset_pipeline/test/`: `asset_pipeline_test.dart`


## Phase 1 Updates & Memory Enhancements
- Phase 1 of the Fluorite AAA Engine is complete (The Rust Core Foundation, Memory Allocators, and the Zero-Copy FFI Bridge to Flutter).
- **Architecture Inspirations**: Godot Server pattern (`RenderingServer`) and O3DE ECS with Atom renderer abstraction.
- **Strategic Vision**: Targets a 'Unified Application/Game Runtime' combining Flutter for UI/Editor and Rust for core game runtime (ECS, networking).
- **Integration**: Integrates with Fluorite 3D PBR engine (HeavenlyBound project) using Dart FFI and WebGPU/WebGL2 viewport support.
- **Target Platforms**: iOS 15+, Android 10+ (Vulkan minSdk 26), Web (WebGPU), Automotive (AAOS/QNX).
- **Workspace**: Uses Dart 3.5.0+ workspaces (`resolution: workspace`) and Melos.
- **Testing**: Testing is performed via `melos run test` and `bash test/e2e/run_e2e_tests.sh`.

## Strategic Vision

Fluorescent is **not** a modified Fluorite engine — it is a **new, layered game/runtime platform** built from Fluorite's ideas and technology. The formal engine specification is documented in [`fluorescent/docs/ENGINE_SPECIFICATION.md`](fluorescent/docs/ENGINE_SPECIFICATION.md).

The core architectural principle:

> **Flutter for the application/editor experience, Rust for the core runtime, Fluorite/Filament-inspired rendering for the visual layer, and an O3DE/Unreal-class systems architecture underneath.**

Key concepts:
- **Two Engines in One**: A Creation Runtime (Flutter editor) and a Game Runtime (Rust core) sharing the same project.
- **Rust Is the Heart**: All gameplay state, physics, networking, and rendering commands are owned by Rust. Flutter is a high-level interface, not the engine itself.
- **Scalable Renderer**: Same game, automatically adapted from mobile (Tier 1) to desktop (Tier 2) to high-end (Tier 3) via hardware capability detection.
- **Data-Driven**: All game content described as data (YAML/JSON), enabling modding, hot-reloading, and marketplace support.
- **10 Major Subsystems**: Core/ECS, Rendering, Physics, Animation, Audio, VFX, World/Terrain, AI, Networking, Asset/Build Pipeline.
- **10 Creator Tools**: Scene Editor, World Editor, Material Editor, Animation Editor, VFX Editor, Audio Editor, AI/Behavior Editor, Visual Scripting, Profiler, Debugger.

```text
                  ┌─────────────────────┐
                  │     GAME / APP      │
                  └──────────┬──────────┘
                             │
                  ┌──────────▼──────────┐
                  │     FLUTTER UI      │
                  └──────────┬──────────┘
                             │
                  ┌──────────▼──────────┐
                  │     ENGINE API      │
                  └──────────┬──────────┘
                             │
                  ┌──────────▼──────────┐
                  │    RUST RUNTIME     │
                  │                     │
                  │ ECS • Jobs • Memory │
                  │ Gameplay • Network  │
                  └──────────┬──────────┘
                             │
          ┌──────────────────┼───────────────────┐
          │                  │                   │
     ┌────▼────┐       ┌─────▼─────┐       ┌─────▼─────┐
     │ RENDER  │       │ SIMULATION│       │ SERVICES  │
     └────┬────┘       └─────┬─────┘       └─────┬─────┘
          │                  │                   │
          └──────────────────┼───────────────────┘
                             │
                  ┌──────────▼──────────┐
                  │ PLATFORM ABSTRACTION│
                  └──────────┬──────────┘
                             │
             ┌───────────────┼────────────────┐
             │               │                │
          Android          Desktop          Server
```

The goal is a scalable engine where developers can build the game, launcher, UI, social systems, inventory, marketplace, settings, and editor tooling within a single cohesive environment.

## Agent Roles

To effectively implement this complex architecture, we define the following agent roles for concurrent multi-agent execution:

1. **Rendering Architect Agent**: Focuses on the core graphics pipeline, including the Vulkan/Metal bindings, the Render Graph, and Shader Toolchain (Phase 2 and Phase 3 features like dynamic quality tiers and GPU VFX).
2. **Systems Programmer Agent**: Responsible for the underlying Rust core foundation, ECS, memory management, and `flutter_rust_bridge` zero-copy communication.
3. **Gameplay/Simulation Agent**: Implements the Physics, Navigation, Animation, and Procedural Content Generation (PCG) systems.
4. **Networking & Cloud Agent**: Handles Phase 4 requirements, including multiplayer replication, rollback, dedicated server logic, and cloud integrations (e.g., Firebase, OpenRouteService for mapping).
5. **Tools & Editor Agent**: Develops the Flutter-based Editor UI, Visual Scripting, Profiler, and Asset Pipeline tooling (Phase 5).
6. **UI/UX & Mobile Integration Agent**: Focuses on Flutter UI application layers, including social feeds, background location tracking, battery-efficient GPS, and push notifications.

## Functional Test App & Geofencing Visuals

To validate the engine's capabilities, we will build a Functional Test App demonstrating a real-world scenario:

### Test App Scope: Community & Rally Map
A live social mapping app showcasing location tracking and geofencing.

#### Features
- **Live Social Map**: Integrates `google_maps_flutter` with custom Slippy Map tiles, displaying drivers within a specified radius.
- **Geofencing Visuals**: Overlay a dynamic visual layer on the map representing Geofences (e.g., event zones or speed traps), with enter/exit events firing in the engine.
- **Background Location**: Integrates background location tracking for continuous updates.
- **Multiplayer Sync**: Connects to the Rust core for sub-second position broadcasting using a websocket/data-channel.
- **Social Feed**: A basic UI layer (Flutter) to display user check-ins and rally events, verifying the Unified Application Runtime model.
