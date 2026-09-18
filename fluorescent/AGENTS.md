# Agent Instructions for Fluorescent Monorepo

Welcome to the Fluorescent monorepo! This file contains instructions to help you navigate and develop within this project effectively.

## Project Structure
This repository is a Flutter monorepo managed via `melos.yaml`.
- `packages/`: Contains the core packages (`fluorescent_core`, `fluorescent_flame`, `fluorescent_vulkan`, `fluorescent_metal`, `fluorescent_webgpu`, `fluorescent_fluorite`).
- `examples/`: Contains sample applications demonstrating the packages (e.g., `hybrid_2d_3d`).
- `docs/`: Architecture specifications and spikes.

## Testing & Validation
Since this is a monorepo, you must run commands across all packages or within the specific package you are working on.

### Analyzing Code
To analyze all packages, run:
```bash
for d in packages/*/; do (cd "$d" && flutter analyze); done
(cd examples/hybrid_2d_3d && flutter analyze)
```
Or, if you modify a specific package, change into its directory and run `flutter analyze`.

### Running Tests
To run tests on all packages, run:
```bash
for d in packages/*/; do (cd "$d" && flutter test); done
```
Before committing any changes, ensure that all tests pass and `flutter analyze` reports no errors.

## Development Guidelines
- **Extend, don't replace**: We build on top of Flame. Avoid reinventing 2D capabilities, lifecycle management, or input handling that Flame already provides.
- **Null Safety**: All Dart code must be fully null-safe and target Dart SDK 3.4.0 or higher.
- **Dependencies**: For local packages, use path dependencies in `pubspec.yaml` (e.g., `path: ../../packages/fluorescent_core`).
- **Formatting**: Always format your Dart code. (Note: Flutter's default `dart format` is highly encouraged before submission).

## Usage Overview
Fluorescent integrates deeply with Flame to provide a hybrid 2D/3D development experience. Developers do not replace their `FlameGame`; instead, they add a `FluorescentViewport` component to render 3D scenes via native backends (Vulkan/Metal/WebGPU) into Flutter's zero-copy texture pipeline. 

### Core Components
* **`FluorescentViewport`**: A Flame `PositionComponent` that acts as the bridge, accepting a native texture ID and rendering the 3D output alongside standard 2D Flame components.
* **Zero-copy Texture Pipeline**: The native backends (e.g., Vulkan via Android NDK `AHardwareBuffer`) render directly into memory that Flutter composites via the `Texture` widget, avoiding expensive CPU readbacks.

## External Tooling
The `tools/` directory contains helper scripts to streamline 3D asset generation and scene design:
* **Blender Sync (`tools/blender_sync/`)**: A Blender Python add-on that connects via WebSockets to the local Fluorescent engine. When a developer modifies an object in Blender, the updates (location, rotation, scale) are streamed live into the running Flutter app without needing a rebuild.
* **Higgsfield Bridge (`tools/higgsfield_bridge/`)**: A Python API wrapper for Higgsfield AI. It allows the programmatic generation of 3D meshes (e.g., `.gltf`) and seamless textures via HTTP requests, which can then be automatically ingested into the Fluorescent asset pipeline.


## Important Memory Points (Appended)
- **Testing**: Testing is performed via `melos run test` across all workspace packages, and E2E integration tests are executed using `bash test/e2e/run_e2e_tests.sh`.
- **Architecture**: The core architecture specifically draws design inspiration from Godot (using the Server pattern, e.g., `RenderingServer`) and O3DE (using an Entity-Component-System and Atom renderer abstraction).
- **Android Vulkan**: The Android Vulkan implementation uses the NDK and `AHardwareBuffer` for zero-copy texture sharing, requiring a minimum SDK of 26 (`minSdk 26`) in `packages/fluorescent_vulkan/android/build.gradle`.
- **Performance Convention**: Avoid object allocation (e.g., creating `Paint` instances) inside Flame `render` loop methods. Cache heavily used objects as class-level static or final fields to minimize garbage collection overhead and maintain high frame rates.
- **cgltf Usage**: The project uses the `cgltf` single-header C library for loading and parsing glTF 3D models within the native Vulkan backend (located in `packages/fluorescent_vulkan/src/third_party/cgltf/`).
- **Tool Integrations**: The project includes tool integrations for Blender (`tools/blender_sync/`) and Higgsfield AI (`tools/higgsfield_bridge/`) for live scene updates and asset generation.
- **Vector2 Import**: When importing `Vector2` in Flame, rely on the export from `flame/game.dart` rather than explicitly importing `package:vector_math/vector_math_64.dart` to avoid namespace ambiguity errors.
- **Monorepo Structure**: The monorepo structure organizes code into `packages/`, `examples/`, `docs/`, and `tools/`.
- **Scalability**: The engine architecture prioritizes a scalable renderer with dynamic quality tiers (scaling from mobile Android to AAA desktop) and first-class multiplayer support (replication, prediction, rollback) built directly into the runtime.
- **Repository Purpose**: The repository 'Fluorescent' is a 3D rendering bridge for the Flutter Flame engine, structured as a Dart workspace monorepo.
- **Texture Widget**: The Flutter `Texture` widget is rendered over the Flame game using the `FluorescentTextureOverlay` widget, which is registered in the `GameWidget`'s `overlayBuilderMap`.
- **WebGPU Support**: The `fluorescent_webgpu` package provides WebGPU support for Flutter Web via a JavaScript interop bridge (`webgpu_bridge.js`) interacting with an HTML canvas element, utilizing `dart:js_interop` and `package:web`.
- **Strategic Vision**: The strategic vision for Fluorescent targets a 'Unified Application/Game Runtime' that combines Flutter for UI/Editor tooling and Rust for the core game runtime (ECS, networking) across Android and Desktop platforms.
- **Target Platforms**: Fluorescent targets iOS 15+, Android 10+, Web (WebGPU), and Automotive (AAOS/QNX) platforms.
- **Dart Workspaces**: The project uses Dart 3.5.0+ workspaces (`resolution: workspace`) and Melos to manage its multiple packages (e.g., core, flame, vulkan, metal, webgpu, fluorite). Run `flutter pub get` at the repository root to resolve dependencies across the entire workspace.
- **ECS Bridge**: The ECS bridge synchronizes camera matrices (View-Projection) between Dart and C++ by utilizing the `vector_math` package in `fluorescent_core` and an `update_camera` FFI function mapped to the Vulkan backend Uniform Buffer Objects (UBOs).
- **Fluorite Integration**: The `fluorescent_fluorite` package is intended to integrate with the Fluorite 3D PBR engine from the HeavenlyBound project, requiring native ECS synchronization via Dart FFI and WebGPU/WebGL2 viewport support.
- **Philosophy**: Fluorescent follows an 'extend, don't replace' philosophy, utilizing Flame for 2D logic, input, audio, and lifecycle, while adding 3D capabilities via a custom `FluorescentViewport` component.
- **PR Branches**: When submitting a PR, if encountering a 'base branch doesn't exist' error, use `git ls-remote --heads origin` to verify the exact remote target branch name, check for typos/case-sensitivity, and ensure the target branch has been pushed.
- **FluorescentViewport**: The `FluorescentViewport` component integrates with native rendering backends (such as Vulkan) using FFI bindings and utilizes a Flutter `Texture` widget via a `textureId` for composition.
