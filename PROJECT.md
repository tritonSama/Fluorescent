# Project: Fluorite AAA Engine — Phase 2 (Wave 1)

## Architecture
Fluorite combines a high-performance Rust core (`fluorite_core`, `fluoderpod_render`) with an ergonomic Flutter editor and runtime layer (`fluorite_editor`, `fluorescent_flame`, `fluorescent_ecs`).
- **Rendering**: Clustered Forward+ rendering pipeline supporting 1024+ dynamic lights, Cook-Torrance microfacet PBR metallic-roughness BRDF, and directional shadow mapping with texel snapping and 3x3 PCF.
- **Spatial**: 32-byte cache-aligned Bounding Volume Hierarchy (BVH) with 16-bin SAH construction, SIMD slab raycasting, and hierarchical frustum culling (<2ms for 10k entities).
- **Physics**: Pure Rust `rapier3d` integration with fixed 60Hz timestep, continuous collision detection (CCD), Kinematic Character Controller (KCC), and zero-copy synchronization with `fluorescent_ecs` 16-float transform storage.
- **Editor**: Dockable Flutter desktop shell with Scene Outliner, Entity Inspector, Orbit/Flycam controls, and an active 3D Viewport backed by zero-copy GPU texture handles.
- **Zero-Copy Pipeline**: Double-buffered 16MB frame arena with 64-byte hardware cache alignment and 0xAA/0x55 boundary sentinels, sharing surfaces with Flutter's `Texture` widget.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | PBR Metallic-Roughness BRDF Pipeline | Cook-Torrance microfacet model (GGX D, Smith V, Schlick F), glTF 2.0 conventions | M1 | Survey 1 |
| 2 | WGSL PBR Shaders | `pbr_forward.wgsl`, `shadow_depth.wgsl`, `cluster_cull.wgsl` | M1 | Survey 1 |
| 3 | Clustered Forward+ Light Assignment | 16x9x24 clusters (3,456 cells) supporting 1024+ dynamic lights via compute shader & CPU fallback | M1 | Survey 1 |
| 4 | Directional Shadow Mapping | Orthographic frustum fit, world-space texel snapping, 3x3 PCF with slope-scaled bias | M1 | Survey 1 |
| 5 | Headless PBR & Light Binning Tests | Unit tests validating shader compilation, 1024-light binning, shadow stability | M1 | Survey 1 |
| 6 | Core Cargo.toml & Test Bugfixes | Relocate bellman/rand from profile.release, fix start_engine() test call signature | M1 | Survey 2 |
| 7 | 32-Byte FlatBvhNode Layout | glam::Vec3A, 32-byte node layout, 2 nodes per 64-byte cache line, GPU WGSL parity | M2 | Survey 2 |
| 8 | 16-Bin SAH BVH Construction | Surface Area Heuristic builder for optimal raycasting and culling depth | M2 | Survey 2 |
| 9 | SIMD Slab Raycasting | Fast branchless ray-AABB traversal on flat BVH | M2 | Survey 2 |
| 10 | Hierarchical Box-Frustum Culling | Center-extents box-plane tests with descendant inside-inheritance | M2 | Survey 2 |
| 11 | Dual-Tree Broadphase Pairs | Fast collision candidate generation via recursive BVH self-overlap | M2 | Survey 2 |
| 12 | BVH 10,000 Entities <2ms Benchmark | Automated Criterion/test benchmark proving culling in <2ms (projected 0.05-0.20ms) | M2 | Survey 2 |
| 13 | Rapier3D PhysicsWorld Integration | rapier3d = "0.22" integration with RigidBodySet, ColliderSet, PhysicsPipeline | M3 | Survey 2 |
| 14 | 60Hz Fixed Timestep & CCD | Deterministic substepping accumulator with continuous collision detection | M3 | Survey 2 |
| 15 | Kinematic Character Controller | Autostep (stairs), slope sliding, ground snapping, dynamic obstacle interaction | M3 | Survey 2 |
| 16 | Zero-Copy Transform Synchronization | Direct sync between Rapier transforms and fluorescent_ecs 16-float stride storage | M3 | Survey 2 |
| 17 | Rapier Physics Stepping Tests | Unit tests verifying physics stepping, collision events, KCC movement | M3 | Survey 2 |
| 18 | Desktop Runners Scaffolding | Scaffold windows/, macos/, linux/ runner directories and main.dart in fluorite_editor | M4 | Survey 3 |
| 19 | Dockable Editor Shell | Multi-panel layout: Toolbar, Outliner, 3D Viewport, Inspector, Diagnostics | M4 | Survey 3 |
| 20 | Scene Outliner Widget | Hierarchical treeview of scene entities with selection and visibility toggles | M4 | Survey 3 |
| 21 | Entity Inspector Widget | Property cards for Transform, Mesh, PBR Material, Forward+ Lights, Rapier Physics | M4 | Survey 3 |
| 22 | Active 3D Viewport with Controls | Orbit and Flycam camera controls, mouse/keyboard interaction, Texture widget | M4 | Survey 3 |
| 23 | Zero-Copy Texture Sharing Pipeline | Texture ID integration connecting Rust/WGPU render targets to Flutter engine | M4 | Survey 3 |
| 24 | E2E Zero-Copy Memory Stability Test | 1,000-frame stability test under active PBR rendering and physics simulation | M5 | Survey 3 |
| 25 | Final Acceptance & Integration Suite | Workspace-wide verification: cargo test, benchmarks, desktop launch, E2E stability | M5 | Survey 1-3 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | PBR & Clustered Forward+ Renderer | Features 1-6 (Cargo fixes, Cook-Torrance BRDF, WGSL shaders, Clustered Forward+ 1024 lights, Directional Shadows, PBR tests) | None | DONE |
| M2 | Spatial Partitioning & BVH | Features 7-12 (FlatBvhNode, 16-bin SAH, SIMD Raycasting, Frustum Culling, Broadphase, 10k entities <2ms benchmark) | M1 | DONE |
| M3 | Physics Integration (Rapier3D) | Features 13-17 (Rapier3D PhysicsWorld, 60Hz accumulator, KCC, Zero-copy transform sync, Physics unit tests) | M2 | PLANNED |
| M4 | Flutter Editor 3D Viewport & Inspector | Features 18-23 (Desktop scaffolding, Dockable Shell, Scene Outliner, Entity Inspector, Viewport, Camera, Texture FFI) | M1, M3 | PLANNED |
| M5 | E2E Integration & Benchmarks | Features 24-25 (1000-frame memory stability test, <2ms BVH benchmark validation, full cargo test verification) | M1, M2, M3, M4 | PLANNED |

## Interface Contracts
### `fluorite_core::rendering` ↔ `fluorite_core::spatial`
- `FlatBvhNode`: 32 bytes (`min: [f32; 3]`, `left: u32`, `max: [f32; 3]`, `count: u32`).
- Frustum culling in BVH returns visible entity IDs / draw instances to renderer queue.
- `CameraUniforms` (320 bytes) provides View-Projection matrix to both culling and shaders.

### `fluorite_core::spatial` ↔ `fluorite_core::physics`
- BVH broadphase collision pairs feed into Rapier or can serve as custom spatial queries.
- Transforms updated by Rapier rigid bodies update entity AABBs in the BVH refit/rebuild step.

### `fluorite_core` ↔ `fluorite_editor`
- FFI Bridge (`flutter_rust_bridge` / C ABI):
  - `start_engine(config: Option<EngineConfig>) -> EngineStatus`
  - `step_engine(dt: f32) -> FrameTelemetry`
  - `get_scene_entities() -> Vec<EntityDescriptor>`
  - `update_entity_transform(id: u64, transform: [f32; 16])`
  - `SharedFrameBuffer` raw pointer export: `ptr_address(&self) -> usize`, `len: usize` with 0xAA/0x55 sentinels.
  - Zero-copy Texture Handle: integer `texture_id` mapped to DXGI/Metal/AHardwareBuffer surface.

## Code Layout
- `fluorite_core/`:
  - `Cargo.toml`: dependencies for `wgpu`, `bytemuck`, `glam`, `rapier3d`, `nalgebra`.
  - `src/rendering/`: PBR BRDF, Clustered Forward+ light grid, directional shadows, WGSL shaders.
  - `src/spatial/`: `FlatBvhNode`, AABB, Frustum, Ray, binned SAH builder, culling, raycast.
  - `src/physics/`: `PhysicsWorld`, Rapier sets, KCC, 60Hz stepper, transform sync.
  - `src/api/`: FRB engine API, telemetry, shared frame buffer.
  - `tests/`: `pbr_pipeline_test.rs`, `bvh_culling_test.rs`, `physics_pipeline_test.rs`.
  - `benches/`: `bvh_benchmark.rs` (<2ms for 10k entities).
- `fluorite_editor/`:
  - `lib/main.dart`: App entry point.
  - `lib/src/ui/`: `editor_shell.dart`, `scene_outliner.dart`, `entity_inspector.dart`, `toolbar.dart`.
  - `lib/src/viewport/`: `editor_viewport.dart`, `camera_controller.dart`.
  - `lib/src/models/`: `scene_model.dart`, `components.dart`.
  - `windows/`, `macos/`, `linux/`: Desktop platform runners.
  - `test/`: `editor_e2e_stability_test.dart`.
