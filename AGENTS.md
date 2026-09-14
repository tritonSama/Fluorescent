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
