# Handoff Report: Requirement 4 (Flutter Editor 3D Viewport & Inspector)

**Agent ID**: `teamwork_preview_explorer_survey_3`  
**Date**: 2026-09-24  
**Handoff Type**: Hard (Investigation & Technical Survey Complete)  
**Authoritative Reference**: `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\ORIGINAL_REQUEST.md`

---

## 1. Observation

1. **Repository Layout and Crate Architecture**:
   - `flutter_rust_bridge.yaml` (lines 1–5):
     ```yaml
     rust_root: "fluorite_core"
     rust_input: "crate::api"
     dart_root: "fluorite_editor"
     dart_output: "fluorite_editor/lib/src/rust"
     ```
   - `fluorite_editor/pubspec.yaml` (lines 9–13):
     ```yaml
     dependencies:
       flutter:
         sdk: flutter
       flutter_rust_bridge: 2.13.0
     ```
   - `fluorite_editor/lib/` contains **only generated FRB code** in `lib/src/rust/` (`allocator/`, `api/engine.dart`, `frb_generated.dart`, `lib.dart`, `rendering/renderer.dart`, `servers/physics.dart`, `servers/navigation.dart`).
   - `fluorite_editor/` has **no `lib/main.dart`** and **no platform runner directories** (`windows/`, `macos/`, `linux/`).
   - `fluorite_editor/test/` contains `bridge_integration_test.dart` and `empirical_challenger_2_test.dart` directly testing native memory buffers and sentinels.

2. **Zero-Copy Memory Allocators & Telemetry in `fluorite_core`**:
   - `fluorite_core/src/api/engine.rs` (lines 44–68):
     ```rust
     #[flutter_rust_bridge::frb(sync)]
     pub fn start_engine(config: Option<EngineConfig>) -> EngineStatus {
         ...
         EngineStatus {
             is_initialized: true,
             total_memory_allocated: alloc.allocated_bytes(),
             arena_capacity: alloc.capacity_bytes(),
             frame_index: alloc.frame_index(),
             status_message: "Fluorite Engine Core Initialized".to_string(),
             core_version: env!("CARGO_PKG_VERSION").to_string(),
             allocator_name: "FluoriteArenaAllocator_v1".to_string(),
             texture_id: Some(1), // Dummy textureId
         }
     }
     ```
   - `fluorite_core/src/allocator/arena.rs` (lines 9–13, 26–34):
     `SENTINEL_HEADER = 0xAA`, `SENTINEL_FOOTER = 0x55`, with 64-byte hardware cache-line alignment and O(1) bulk reset.
   - `fluorite_core/src/allocator/frame.rs` (lines 17–24, 59–65):
     `DoubleBufferedFrameAllocator` implements ping-pong frame switching (`swap_buffers()`) resetting alternate arena in O(1) at frame boundaries.
   - `fluorite_core/src/api/engine.rs` (lines 155–194):
     `SharedFrameBuffer` exposes raw pointer address via `pub fn ptr_address(&self) -> usize` for zero-copy access in Dart via `Pointer.fromAddress(addr).asTypedList(len)`.

3. **Zero-Copy Texture & Viewport Patterns in `fluorescent`**:
   - `fluorescent/packages/fluorescent_flame/lib/src/components/fluorescent_viewport.dart` (lines 14–21, 89–101):
     `FluorescentViewport` wraps `textureId` and draws a placeholder fallback when `textureId == null`.
   - `fluorescent/packages/fluorescent_flame/lib/src/components/fluorescent_texture_overlay.dart` (lines 5–25):
     Composites `Texture(textureId: textureId)` into Flutter's render tree.
   - `fluoderpod_render/src/android_vulkan.rs` (lines 18–51):
     Directly allocates `AHardwareBuffer` via `ndk_sys::AHardwareBuffer_allocate` for zero-copy Vulkan texturing on Android.
   - `fluorescent/packages/fluorescent_core/lib/src/scene/camera_3d.dart` (lines 48–76):
     Provides base `Camera3D` and `CameraController` with orbit spherical coordinates and zoom.

4. **Contiguous ECS Component Data Layout**:
   - `fluorescent/packages/fluorescent_ecs/lib/src/components/transform_component.dart` (lines 6–58):
     `TransformOffsets` defines 16 floats per stride (64 bytes, exact cache-line size): translation (0..2), flags (3), quaternion (4..7), scale (8..10), reserved (11), bounding sphere (12..15).
   - `fluorescent/packages/fluorescent_ecs/lib/src/world.dart` (lines 11–45):
     `EcsWorld` with contiguous `TransformStorage` and sparse-set entity allocation.

---

## 2. Logic Chain

1. **Premise 1 (Acceptance Criteria & Requirement 4)**: Requirement 4 demands that `fluorite_editor` launch on Desktop (Windows/macOS/Linux) with an interactive 3D Viewport rendering the Rust scene directly via zero-copy FFI texture handles, alongside a dockable editor shell, scene outliner, and entity inspector.
2. **Premise 2 (Current Codebase State)**: Observation 1 confirms that `fluorite_editor` currently lacks `lib/main.dart`, UI components, and desktop runner files (`windows/`, `macos/`, `linux/`), meaning it cannot currently boot as an interactive desktop application.
3. **Premise 3 (Zero-Copy Texture Mechanism)**: Observation 2 & 3 demonstrate that Flutter's `Texture(textureId: ...)` widget is the standard integration mechanism for hardware-accelerated external surfaces. On Windows, this connects via `FlutterDesktopGpuSurfaceTexture` (DXGI shared handle / D3D11); on macOS via Metal `IOSurfaceRef`; on Linux via EGL/dmabuf; on Android via `AHardwareBuffer`. For headless and test environments, `SharedFrameBuffer` provides a validated zero-copy fallback with 0xAA/0x55 sentinels.
4. **Premise 4 (Editor UI & Component Inspectability)**: Observation 4 shows that ECS transforms and resources (`TransformStorage`, `MaterialResource`, `TextureResource`) are already structured for high-performance contiguous storage. To inspect and edit these in the editor, `fluorite_editor` needs an Outliner treeview and an Inspector with property controls for Transform (Euler & Quaternion sync), Mesh, PBR Material, Clustered Forward+ Lights, and Physics (Rapier3D rigid bodies and colliders).
5. **Premise 5 (E2E Memory Stability)**: Observation 2 shows that the Rust `DoubleBufferedFrameAllocator` provides a 16MB per-frame allocation arena with O(1) bulk reset. Real-time physics simulation and rendering must operate within this bounded arena across 1,000+ frames to prove zero heap fragmentation and memory stability.
6. **Conclusion**: To implement Requirement 4, the engineering team must:
   - Scaffold desktop runner folders and create `lib/main.dart` in `fluorite_editor`.
   - Build the dockable shell layout (Toolbar, Outliner, 3D Viewport, Inspector, Console).
   - Implement the active `EditorViewport` wrapping `Texture(textureId: ...)` with Orbit and Flycam controls.
   - Implement the `SceneModel` and Inspector property cards for Transform, Mesh, Material, Light, and Physics.
   - Write an automated E2E integration test validating real-time physics and rendering memory stability.

---

## 3. Caveats

1. **Physical GPU Dependency for Platform Textures**:
   - Creating a true DirectX 11/12 DXGI shared handle or Metal IOSurface requires an initialized GPU device on the host system.
   - In automated headless CI environments without a physical display/GPU, the editor viewport and test suites must seamlessly fall back to `SharedFrameBuffer` or synthetic texture testing (which is already proven in `tests/tier1_feature_coverage_test.dart` and `fluorite_editor/test/empirical_challenger_2_test.dart`).
2. **Rust Core Compilation**:
   - `cargo test` in `fluorite_core` and building `fluorite_core.dll` requires Cargo/Rust toolchain.
   - Flutter Rust Bridge codegen (`flutter_rust_bridge_codegen generate`) has already been run for the existing API, but if new FFI symbols are added to `fluorite_core/src/api/engine.rs`, FRB codegen must be executed or C-ABI exports matched.
3. **Third-Party Dependency Minimization**:
   - The editor shell and docking can be built using standard Flutter widgets (`Row`, `Column`, `Stack`, `CustomPainter`, `GestureDetector`, `Listener`, `Focus`) rather than external heavy docking packages, ensuring maximum cross-platform reliability and zero dependency conflicts.

---

## 4. Conclusion

The technical survey for Requirement 4 is complete. The detailed architectural report has been written to:
`c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_survey_3\report.md`

### Actionable Implementation Plan:
1. **WP 1 — Desktop Runners & App Entry**: Create `fluorite_editor/lib/main.dart` and scaffold `windows/`, `macos/`, and `linux/` runner directories. Add `vector_math: ^2.1.4` to `fluorite_editor/pubspec.yaml`.
2. **WP 2 — State Model & Scene Graph**: Create `fluorite_editor/lib/src/models/` (`scene_model.dart`, `editor_state.dart`, `components.dart`).
3. **WP 3 — Dockable Editor Shell**: Create `fluorite_editor/lib/src/ui/` (`editor_shell.dart`, `scene_outliner.dart`, `entity_inspector.dart`, `diagnostics_bar.dart`).
4. **WP 4 — Active 3D Viewport & Camera**: Create `fluorite_editor/lib/src/viewport/` (`editor_viewport.dart`, `camera_controller.dart`, `viewport_overlay.dart`).
5. **WP 5 — E2E Real-Time Stability Test**: Create `fluorite_editor/test/editor_e2e_stability_test.dart` and integrate into `tests/e2e_runner.dart` to verify zero-copy memory stability across 1,000 frames.

---

## 5. Verification Method

To independently verify this survey and subsequent implementation:

1. **Inspect Documentation & Design**:
   - Read `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_survey_3\report.md`.
   - Verify all file paths, class names, FFI bindings, and interface contracts.
2. **Run Existing Bridge Tests**:
   - Execute: `dart run fluorite_editor/test/bridge_integration_test.dart`
   - Execute: `dart run fluorite_editor/test/empirical_challenger_2_test.dart`
   - Execute: `dart run tests/e2e_runner.dart`
   - Invalidation condition: Any failure in memory allocation or sentinel verification (`0xAA`/`0x55`).
3. **Verify Editor Desktop Launch**:
   - Once WP 1–4 are implemented, run: `flutter run -d windows` (or macos/linux) inside `fluorite_editor/`.
   - Invalidation condition: App fails to launch, viewport does not render, or camera controls do not respond to mouse input.
4. **Verify E2E Real-Time Memory Stability**:
   - Execute: `dart run fluorite_editor/test/editor_e2e_stability_test.dart`
   - Invalidation condition: Active memory exceeds 16MB budget, sentinels are corrupted, or resident memory grows unbounded over 1,000 frames.
