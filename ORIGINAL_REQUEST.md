# Original User Request

## 2026-09-17T03:33:37Z

# Teamwork Project Prompt

> Requested team: Full team (for concurrent multi-agent execution)

Implement the 6 core architectural pillars for the Fluorescent 3D engine (Server Architecture, Render Graph, Asset Pipeline, Resource Manager, ECS storage, and Shader Toolchain) concurrently. 

Working directory: C:\Users\blue-\projects\Fluorescent\fluorescent
Integrity mode: demo

## Requirements

### R1. Server Architecture
Implement `PhysicsServer` and `NavigationServer` abstract interfaces alongside the existing `RenderingServer`. Set up a `ServerManager` using Dart Isolates for background processing and message passing.

### R2. Render Graph & Asset Pipeline
Implement a data-driven `RenderGraph` (parsing JSON/YAML) to replace hardcoded WebGPU passes. Build a Dart CLI tool (`asset_pipeline`) to compile `.gltf` and `.wgsl` files into compressed `.fworld` binary formats.

### R3. Resource Management & ECS
Create a `ResourceManager` with reference counting for Textures, Meshes, and Materials to manage GPU memory. Refactor `fluorescent_ecs` to use memory-contiguous `Float32List` arrays for core components like Transforms.

### R4. Shader Toolchain
Integrate `Naga` or `SPIRV-Cross` via FFI into the asset pipeline to automatically transpile WGSL shaders into SPIR-V and MSL.

## Acceptance Criteria

### Verification
- [ ] Automated tests confirm Dart Isolates successfully spawn and communicate without blocking the main thread.
- [ ] The `asset_pipeline` CLI tool successfully compiles a test `.gltf` and `.wgsl` file into a binary format.
- [ ] ECS benchmark test successfully spawns and iterates over 10,000 entities using TypedData without throwing memory errors.
- [ ] Resource manager successfully loads a mock texture, increments its reference count, and frees it when destroyed.

## 2026-09-17T16:50:21Z

# Teamwork Project Prompt

> Requested team: Full team (for concurrent multi-agent execution)

Implement Phase 1 of the Fluorite AAA Engine: The Rust Core Foundation, Memory Allocators, and the Zero-Copy FFI Bridge to Flutter.

Working directory: C:\Users\blue-\projects\Fluorite
Integrity mode: demo

## Requirements

### R1. Rust Core & Memory Allocators
Initialize a new Rust library project (`fluorite_core`). Implement custom memory allocators (e.g., a basic Arena Allocator or Frame Allocator) to ensure zero-fragmentation allocation for game loops.

### R2. Zero-Copy FFI Bridge
Use the `flutter_rust_bridge` package to automatically generate safe, zero-copy FFI bindings between the Rust core and Dart. Ensure the architecture supports sharing large continuous memory buffers without serialization overhead.

### R3. Flutter Editor Integration
Initialize a new Flutter desktop project (`fluorite_editor`). Integrate the generated `flutter_rust_bridge` bindings. Build a basic Editor UI with a "Start Engine" button that allocates memory in Rust and reads the status back into Flutter.

## Acceptance Criteria

### Verification
- [ ] `cargo test` passes successfully for the custom memory allocators in Rust.
- [ ] Automated tests confirm `flutter_rust_bridge` generation completes without errors.
- [ ] A Flutter integration test verifies that Dart can successfully call a Rust FFI function to allocate 1MB of memory and read a value from it without crashing.
- [ ] The Flutter UI successfully launches on Desktop and communicates with the compiled Rust binary.

## 2026-09-17T20:35:27Z

USER COMMAND: Pause and freeze the swarm execution immediately after Milestone 2 (The Zero-Copy FFI Bridge) passes the verification gate. Do not proceed to Milestone 3. Wait for further instructions.

## 2026-09-24T17:55:33Z

# Teamwork Project Prompt

> Requested team: Full team (for concurrent multi-agent execution)

Implement Phase 2 (Wave 1) of the Fluorite AAA Engine: PBR & Forward+ Rendering, BVH Spatial Partitioning, Physics Integration, and the Flutter Desktop Editor 3D Viewport.

Working directory: C:\Users\blue-\projects\Fluorescent
Integrity mode: demo

## Requirements

### R1. PBR & Forward+ Renderer (Rust Core)
Implement a PBR metallic-roughness rendering pipeline in `fluorite_core` (or `fluoderpod_render`) with Clustered Forward+ light assignment supporting 1024+ dynamic lights and directional shadow mapping.

### R2. Spatial Partitioning & BVH (Rust Core)
Implement a Bounding Volume Hierarchy (BVH) in Rust for fast CPU/GPU frustum culling, raycasting, and broadphase collision detection.

### R3. Physics Integration (Rust Core)
Integrate `rapier3d` (or Jolt FFI) into `fluorite_core` for rigid body dynamics, colliders, and a Kinematic Character Controller.

### R4. Flutter Editor 3D Viewport & Inspector
Expand `fluorite_editor` with a dockable editor shell, scene outliner, entity inspector, and an active 3D Viewport rendering the Rust scene directly via zero-copy FFI texture handles.

## Acceptance Criteria

### Verification
- [ ] `cargo test` passes in `fluorite_core` verifying PBR shader compilation, BVH raycasting, and Rapier physics stepping.
- [ ] Automated benchmarks demonstrate BVH frustum culling 10,000 entities in <2ms.
- [ ] `fluorite_editor` launches on Desktop with an interactive 3D Viewport rendering a PBR mesh with dynamic shadows and camera controls.
- [ ] E2E integration test verifies zero-copy memory stability during real-time physics simulation and rendering.

