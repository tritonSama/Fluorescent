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
