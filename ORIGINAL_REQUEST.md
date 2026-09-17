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
