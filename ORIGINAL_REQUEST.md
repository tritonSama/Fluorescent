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
