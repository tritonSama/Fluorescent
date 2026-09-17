# Dispatch Log

## 2026-09-17T03:34:42Z

Implement the 6 core architectural pillars for the Fluorescent 3D engine concurrently:
1. Server Architecture: PhysicsServer and NavigationServer abstract interfaces alongside RenderingServer. ServerManager using Dart Isolates for background processing and message passing.
2. Render Graph & Asset Pipeline: Data-driven RenderGraph (parsing JSON/YAML) replacing hardcoded WebGPU passes. Dart CLI tool (asset_pipeline) compiling .gltf and .wgsl into compressed .fworld binary formats.
3. Resource Management & ECS: ResourceManager with reference counting for Textures, Meshes, Materials. Refactor fluorescent_ecs to use memory-contiguous Float32List arrays for core components like Transforms.
4. Shader Toolchain: Integrate Naga or SPIRV-Cross via FFI into the asset pipeline to transpile WGSL into SPIR-V and MSL.

Integrity mode: demo.
Fulfill all acceptance criteria:
- Automated tests confirm Dart Isolates successfully spawn and communicate without blocking the main thread.
- asset_pipeline CLI tool successfully compiles a test .gltf and .wgsl file into a binary format.
- ECS benchmark test successfully spawns and iterates over 10,000 entities using TypedData without throwing memory errors.
- Resource manager successfully loads a mock texture, increments reference count, and frees it when destroyed.
