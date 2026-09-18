# Task Division and Agent Assignment

This document outlines the organization and task assignments for the upcoming phases of the Fluorescent 3D Engine and Fluorite AAA Engine integration. Multiple specialized agents are assigned to handle concurrent execution across different domains.

## 1. Rust Core Agent (`agent_rust_core`)
**Scope:** `fluorite_core/`
**Responsibilities:**
- Extend the `fluorite_core` custom memory allocators (Arena Allocator, Frame Allocator) created in Phase 1 to support dynamic growth if needed.
- Implement the core ECS (Entity Component System) in Rust to handle game state and multiplayer networking (replication, prediction, rollback).
- Ensure zero-fragmentation allocation for game loops and verify lock-free atomic behaviors.

## 2. FFI Integration Agent (`agent_ffi_bridge`)
**Scope:** FFI boundaries between `fluorite_core`, `fluorescent_core`, and `fluorescent_fluorite`
**Responsibilities:**
- Utilize `flutter_rust_bridge` to maintain safe, zero-copy FFI bindings between the Rust core and Dart.
- Ensure the architecture supports sharing large continuous memory buffers (like the 1MB buffer implemented in Phase 1) without serialization overhead.
- Map the Vulkan backend Uniform Buffer Objects (UBOs) to the FFI `update_camera` function to synchronize camera matrices (View-Projection) between Dart and C++.

## 3. Flutter Editor Agent (`agent_flutter_editor`)
**Scope:** `fluorite_editor/` and `fluorescent/` Flutter packages
**Responsibilities:**
- Enhance the `fluorite_editor` Flutter desktop project.
- Implement the Editor UI to interact with the engine (e.g., beyond the "Start Engine" button).
- Integrate the `FluorescentViewport` component and `FluorescentTextureOverlay` widget to render the 3D output alongside standard 2D Flame components using the Flutter `Texture` widget pipeline.
- Maintain the 'extend, don't replace' philosophy with Flame.

## 4. Web & Native Renderer Agent (`agent_renderers`)
**Scope:** `packages/fluorescent_vulkan/`, `packages/fluorescent_webgpu/`, etc.
**Responsibilities:**
- Manage native rendering backends (Vulkan, Metal, WebGPU).
- Maintain the Android Vulkan implementation using NDK and `AHardwareBuffer` (`minSdk 26`).
- Maintain the `fluorescent_webgpu` package for WebGPU support via JavaScript interop (`webgpu_bridge.js`, `dart:js_interop`, `package:web`).
- Ensure the `cgltf` single-header C library is correctly utilized for glTF parsing in the native backends.

## 5. Verification & Testing Agent (`agent_verification`)
**Scope:** Workspace-wide (`tests/`, `test/e2e/`)
**Responsibilities:**
- Execute the `melos run test` and `bash test/e2e/run_e2e_tests.sh` testing suites.
- Perform opaque-box E2E tests covering architectural pillars and ensure no regressions occur during multi-agent concurrent execution.
- Validate FFI memory sharing and isolate communication concurrency.

## 6. Pipeline & Tools Agent (`agent_tools`)
**Scope:** `tools/asset_pipeline/`, `tools/blender_sync/`, `tools/higgsfield_bridge/`
**Responsibilities:**
- Enhance the Dart CLI `asset_pipeline` for compiling `.gltf` and `.wgsl` files into the compressed `.fworld` format.
- Maintain integrations with Blender via WebSockets for live scene updates.
- Maintain the Python API wrapper for Higgsfield AI for programmatic 3D asset generation.
