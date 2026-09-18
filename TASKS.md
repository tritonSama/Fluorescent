# Task Division and Agent Assignment

This document outlines the organization and task assignments for the upcoming phases of the Fluorescent 3D Engine and Fluorite AAA Engine integration. Multiple specialized agents are assigned to handle concurrent execution across different domains, mapped against the newly defined 10 Major Subsystems and the Creation vs. Game runtime split (see `ARCHITECTURE.md`).

## The 10 Major Engine Subsystems (Rust / Native)
1. Core / ECS
2. Rendering
3. Physics
4. Animation
5. Audio
6. VFX
7. World / Terrain
8. AI
9. Networking
10. Asset / Build Pipeline

## Creation Platform (Flutter UI)
- Scene Editor
- World Editor
- Material Editor
- Animation Editor
- VFX Editor
- Audio Editor
- AI/Behavior Editor
- Visual Scripting
- Profiler
- Debugger

---

## Agent Task Assignments

### 1. Rust Core Agent (`agent_rust_core`)
**Subsystems:** Core / ECS, Networking, Physics, Animation, Audio, World / Terrain, AI
**Scope:** `fluorite_core/`
**Responsibilities:**
- Implement the core ECS (Entity Component System) in Rust as the authoritative Game Runtime to handle game state and multiplayer networking (replication, prediction, rollback).
- Extend the custom memory allocators (Arena Allocator, Frame Allocator) created in Phase 1 to support dynamic growth if needed.
- Enforce the "Everything is an Entity" design paradigm.
- Lay foundations for subsequent Rust-native systems (Physics, Animation, Audio, AI).

### 2. Rendering & VFX Agent (`agent_renderers`)
**Subsystems:** Rendering, VFX
**Scope:** `packages/fluorescent_vulkan/`, `packages/fluorescent_webgpu/`, `fluorite_core/src/rendering/`
**Responsibilities:**
- Manage native rendering backends (Vulkan, Metal, WebGPU).
- Maintain the Android Vulkan implementation using NDK and `AHardwareBuffer` (`minSdk 26`).
- Define the rendering capability tiers (Tier 1 Mobile, Tier 2 Desktop, Tier 3 High-End) allowing adaptive LOD and GI.
- Conceptualize the renderer as its own isolated engine, leveraging Filament/Fluorite technology while progressively building out Rust-native rendering components.

### 3. Flutter Creator Platform Agent (`agent_flutter_editor`)
**Subsystems:** Creator Platform (Editors, Profilers, Debuggers), Game UI Layer
**Scope:** `fluorite_editor/` and `fluorescent/` Flutter packages
**Responsibilities:**
- Enhance the `fluorite_editor` Flutter desktop project, building out the Creation Runtime tools (Scene Editor, Inspector, Material Tools, etc.).
- Establish Flutter as a first-class Game UI runtime (Inventory, Map, Chat) overlaying the native 3D world.
- Integrate the `FluorescentViewport` component and `FluorescentTextureOverlay` widget to render the 3D output alongside standard 2D Flame components using the Flutter `Texture` widget pipeline.

### 4. FFI Integration Agent (`agent_ffi_bridge`)
**Subsystems:** Engine API (Rust <-> Flutter Bridge)
**Scope:** FFI boundaries between `fluorite_core`, `fluorescent_core`, and `fluorescent_fluorite`
**Responsibilities:**
- Utilize `flutter_rust_bridge` to maintain safe, zero-copy FFI bindings between the Rust core and Dart.
- Act as the strict translation layer between the Flutter UI runtime and the Rust Game Runtime, exposing ECS entities, components, and resources.
- Synchronize camera matrices and engine data without serialization overhead.

### 5. Asset Pipeline & Tools Agent (`agent_tools`)
**Subsystems:** Asset / Build Pipeline
**Scope:** `tools/asset_pipeline/`, Data-Driven Engine Architecture
**Responsibilities:**
- Shift the engine towards a data-driven model (`project.yaml`, `scenes/`, `materials/`) instead of hardcoded Rust/C++.
- Enhance the Dart CLI `asset_pipeline` for compiling `.gltf` and `.wgsl` files into the compressed `.fworld` format.
- Ensure the pipeline can ingest and serve assets optimally to the Rust runtime.

### 6. Verification & Validation Agent (`agent_verification`)
**Subsystems:** QA & Testing
**Scope:** Workspace-wide (`tests/`, `test/e2e/`)
**Responsibilities:**
- Execute the `melos run test` and `bash test/e2e/run_e2e_tests.sh` testing suites.
- Perform opaque-box E2E tests covering architectural pillars and ensure no regressions occur during multi-agent concurrent execution.
- Validate FFI memory sharing, isolate communication concurrency, and engine specification compliance.
