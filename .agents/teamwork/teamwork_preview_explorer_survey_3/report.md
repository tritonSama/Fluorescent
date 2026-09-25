# Technical Survey & Architectural Report: Requirement 4 (Flutter Editor 3D Viewport & Inspector)

**Agent ID**: `teamwork_preview_explorer_survey_3`  
**Date**: 2026-09-24  
**Target Milestone**: Phase 2 Wave 1 — Fluorite AAA Engine  
**Authoritative Reference**: `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\ORIGINAL_REQUEST.md`

---

## 1. Executive Summary & Problem Boundary

### 1.1 Mission & Requirement Scope
The objective of this survey is to investigate the existing repository foundation and design the complete technical specification for **Requirement 4 (R4)**:
> **R4. Flutter Editor 3D Viewport & Inspector (`fluorite_editor`)**: Expand `fluorite_editor` with a dockable editor shell, scene outliner, entity inspector, and an active 3D Viewport rendering the Rust scene directly via zero-copy FFI texture handles.
> **Acceptance Criteria**:
> - `fluorite_editor` launches on Desktop (Windows/macOS/Linux) with an interactive 3D Viewport rendering a PBR mesh with dynamic shadows and camera controls.
> - E2E integration test verifies zero-copy memory stability during real-time physics simulation and rendering.

### 1.2 Core Architectural Findings
1. **Existing Assets**:
   - `fluorite_editor/` exists but currently **only contains generated Flutter Rust Bridge (FRB) v2 bindings** (`lib/src/rust/`) and Phase 1 bridge tests (`test/bridge_integration_test.dart`, `test/empirical_challenger_2_test.dart`). It possesses **no UI code**, **no `lib/main.dart`**, and **no platform runner folders (`windows/`, `macos/`, `linux/`)**.
   - `flutter_rust_bridge.yaml` at repo root configures:
     - `rust_root: "fluorite_core"`
     - `rust_input: "crate::api"`
     - `dart_root: "fluorite_editor"`
     - `dart_output: "fluorite_editor/lib/src/rust"`
   - `fluorite_core/` provides the memory infrastructure: `ArenaAllocator`, `DoubleBufferedFrameAllocator` (16MB capacity per frame, 0xAA/0x55 sentinels), `SharedFrameBuffer` (raw pointer address via `ptr_address()`), and baseline FFI methods `start_engine()`, `allocate_engine_buffer()`, `get_engine_status()`.
   - `fluorescent/packages/fluorescent_flame/` provides the conceptual bridge pattern: `FluorescentViewport` wraps a native `textureId` and renders `Texture(textureId: textureId)` into Flutter's compositor tree.
   - `fluorescent/packages/fluorescent_ecs/` provides a contiguous 16-float stride `TransformStorage` (64 bytes per entity: translation, rotation quaternion, scale, flags, bounding sphere) matching CPU hardware cache lines.

2. **Primary Technical Gaps to Fulfill R4**:
   - **Desktop Launch Scaffolding**: `fluorite_editor` requires desktop platform runner files (`windows/`, `macos/`, `linux/`) and `lib/main.dart` configured to boot the editor application.
   - **Dockable Editor Shell**: Multi-split responsive workspace (Header Toolbar, Left Scene Outliner, Center 3D Viewport, Right Entity Inspector, Bottom Diagnostics Console & Profiler).
   - **Scene Outliner**: Hierarchical scene graph tree, entity selection synchronization, parent-child nesting, entity creation/deletion.
   - **Entity Inspector**: Component property cards for Transform (Euler & Quaternion sync), Mesh (glTF/primitives), PBR Material (Albedo, Metallic, Roughness, Normal, Emissive), Lights (Clustered Forward+ point/spot/directional), and Physics (RigidBody, Collider, KCC).
   - **Active 3D Viewport & Zero-Copy Pipeline**: Integration with Flutter's `Texture(textureId: ...)` widget backed by platform-specific GPU texture handles (DXGI shared handle / D3D11 on Windows, Metal IOSurface on macOS, dmabuf/EGL on Linux, AHardwareBuffer on Android) and fallbacks for testing.
   - **Interactive Camera Controls**: Orbit camera (RMB/Alt+LMB drag, mouse wheel zoom, pan) and Flycam / FPS mode (RMB hold + WASD + QE flight).
   - **E2E Real-Time Physics & Rendering Memory Stability**: Continuous simulation/render tick verifying the 16MB per-frame allocator budget and sentinel boundaries under 1,000+ frames.

---

## 2. Codebase Topology & Component Inventory

```text
Fluorescent/
├── fluorite_core/                     # Rust Engine Core (CDYLIB + RLIB)
│   ├── src/
│   │   ├── allocator/                 # ArenaAllocator & DoubleBufferedFrameAllocator
│   │   ├── api/engine.rs              # FFI-exported FRB entry points (start_engine, buffers)
│   │   ├── rendering/renderer.rs      # Quality tiers (Tier 1-4) & renderer foundation
│   │   └── servers/                   # PhysicsServer & NavigationServer FFI stubs
│   └── Cargo.toml                     # FRB v2.13.0, serde, thiserror
│
├── fluorite_editor/                   # Flutter Desktop Editor Application
│   ├── lib/
│   │   └── src/rust/                  # FRB-generated Dart bindings (engine.dart, frb_generated.dart)
│   ├── test/                          # bridge_integration_test.dart, empirical_challenger_2_test.dart
│   ├── pubspec.yaml                   # Missing desktop platform dependencies & runner scaffolding
│   └── [GAPS: lib/main.dart, ui/, viewport/, outliner/, inspector/, windows/, macos/, linux/]
│
├── fluoderpod_render/                 # Low-level GPU-Driven Renderer
│   ├── src/
│   │   ├── android_vulkan.rs          # AHardwareBuffer allocation & JNI bindings
│   │   ├── unified_pipeline/          # wgpu unified pipeline manager
│   │   ├── culling/                   # Frustum & occlusion culling
│   │   └── virtual_geometry/          # Nanite-style micro-polygon clustering
│   └── Cargo.toml
│
├── fluorescent/                       # Dart/Flutter Engine Subsystems (Melos monorepo)
│   ├── packages/
│   │   ├── fluorescent_core/          # World3D, Camera3D, MaterialResource, TextureResource
│   │   ├── fluorescent_ecs/           # Sparse-set ECS & contiguous Float32List TransformStorage
│   │   ├── fluorescent_flame/         # FluorescentViewport & FluorescentTextureOverlay
│   │   └── fluorescent_vulkan/        # C-FFI bindings (init_vulkan, render_frame, etc.)
│   └── examples/
│       ├── hybrid_2d_3d/              # Working demo compositing 2D Flame over 3D TextureOverlay
│       └── functional_test_app/       # Live telemetry & geofencing prototype
│
└── tests/                             # E2E Multi-Tier Test Suite
    ├── fluorite_bridge_model.dart     # EngineControllerModel, Allocator simulation
    ├── e2e_runner.dart                # Tiers 1-4 master runner
    └── run_e2e_tests.bat              # Batch automated runner
```

---

## 3. Rust-Flutter Communication & FFI Architecture

### 3.1 Flutter Rust Bridge (FRB) v2 Foundation
The project currently standardizes on **Flutter Rust Bridge v2.13.0**:
- Rust crate: `fluorite_core` (`crate-type = ["cdylib", "rlib"]`).
- Configuration (`flutter_rust_bridge.yaml`):
  ```yaml
  rust_root: "fluorite_core"
  rust_input: "crate::api"
  dart_root: "fluorite_editor"
  dart_output: "fluorite_editor/lib/src/rust"
  ```
- **Sync & Async Semantics**:
  - Small control functions use `#[flutter_rust_bridge::frb(sync)]` (e.g. `start_engine`, `get_engine_status`, `allocate_engine_buffer`), executing synchronously on the calling thread without async isolate task hops.
  - Large buffers return `Vec<u8>`, which in FRB v2 is transferred zero-copy to Dart as `Uint8List` via `Dart_NewExternalTypedDataWithFinalizer`.
  - Opaque pointers use `#[flutter_rust_bridge::frb(opaque)]` (e.g. `SharedFrameBuffer`), exposing native pointer addresses via `ptr_address()` for direct Dart `Pointer.fromAddress()` / `asTypedList()`.

### 3.2 Dynamic Library Loading on Desktop
In `fluorite_editor/lib/src/rust/frb_generated.dart`:
```dart
static const kDefaultExternalLibraryLoaderConfig = ExternalLibraryLoaderConfig(
  stem: 'fluorite_core',
  ioDirectory: '../fluorite_core/target/release/',
  webPrefix: 'pkg/',
  wasmBindgenName: 'wasm_bindgen',
);
```
- On **Windows**: Looks for `fluorite_core.dll` in executable dir or `../fluorite_core/target/release/`.
- On **macOS**: Looks for `libfluorite_core.dylib`.
- On **Linux**: Looks for `libfluorite_core.so`.
- For editor desktop testing and running, compiling `fluorite_core` in release mode (`cargo build --release --manifest-path fluorite_core/Cargo.toml`) places the native shared library directly where FRB locates it.

---

## 4. Zero-Copy Texture Sharing Pipeline

### 4.1 How Flutter Composites Hardware Textures
Flutter's `Texture(textureId: int)` widget does **not** copy pixel data over FFI every frame. Instead, the Flutter Engine composites a hardware texture rendered by an external GPU context directly into the Skia/Impeller render pass:

```text
┌─────────────────────────────────────────────────────────────┐
│                    RUST GRAPHICS CORE                       │
│  (wgpu / Vulkan / Direct3D 11 / Metal)                      │
│                                                             │
│  Render Target: PBR Scene Offscreen Color Attachment        │
│         │                                                   │
│         ▼                                                   │
│  Native Texture Handle (DXGI Handle / IOSurface / AHB)      │
└─────────┬───────────────────────────────────────────────────┘
          │ (Zero-copy GPU VRAM handle, no CPU readback)
          ▼
┌─────────────────────────────────────────────────────────────┐
│             PLATFORM TEXTURE REGISTRAR                      │
│  - Windows: FlutterDesktopGpuSurfaceDescriptor (DXGI/D3D11) │
│  - macOS:   CVPixelBufferRef / IOSurfaceRef (Metal)         │
│  - Android: AHardwareBuffer / SurfaceTexture (Vulkan)       │
│  - Linux:   FlPixelBufferTexture / EGLImage / dmabuf        │
│         │                                                   │
│         ▼ (Registers with engine, assigns textureId = 1)    │
└─────────┬───────────────────────────────────────────────────┘
          │
          ▼ (integer textureId passed via FFI)
┌─────────────────────────────────────────────────────────────┐
│                     FLUTTER ENGINE UI                       │
│                                                             │
│  Widget Tree:                                               │
│    Texture(textureId: 1)                                    │
│    └── Composited directly into Flutter Viewport            │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Platform-Specific Zero-Copy Implementations

| Platform | Graphics API | Native Handle Type | Flutter Desktop Texture Interface |
|:---|:---|:---|:---|
| **Windows** | Direct3D 11 / 12 / Vulkan (`ash`) | DXGI Shared Handle (`HANDLE`) / `ID3D11Texture2D` | `FlutterDesktopGpuSurfaceTexture` via `FlutterDesktopTextureRegistrarRegisterExternalTexture` |
| **macOS** | Metal / MoltenVK | `IOSurfaceRef` / `CVPixelBufferRef` | `FlutterTextureRegistry` (`registerTexture:`) returning `int64_t` |
| **Linux** | Vulkan / OpenGL | dmabuf file descriptor / `EGLImage` | `FlPixelBufferTexture` or EGL external texture |
| **Android** | Vulkan NDK | `AHardwareBuffer*` (`ndk_sys`) | `TextureRegistry.SurfaceTextureEntry` / HardwareBuffer |

#### Windows Detail:
1. Rust initializes `wgpu` or Direct3D 11 device.
2. Allocates a color attachment texture with `D3D11_RESOURCE_MISC_SHARED` or `D3D11_RESOURCE_MISC_SHARED_NTHANDLE`.
3. Queries `IDXGIResource::GetSharedHandle(&shared_handle)`.
4. The Windows C++ runner or texture plugin registers a `FlutterDesktopGpuSurfaceTexture` callback that supplies `FlutterDesktopGpuSurfaceDescriptor { handle = shared_handle, ... }`.
5. Flutter's D3D11/Impeller compositor opens the shared handle on its device and renders without any CPU copying.

#### Multi-Tier Fallback Strategy for Editor & Headless Testing:
1. **Tier 1 (GPU Zero-Copy Texture)**: Direct hardware texture handle registered with Flutter's Texture Registrar (`Texture(textureId: textureId)`).
2. **Tier 2 (Shared Memory Frame Buffer Fallback)**: Uses `fluorite_core`'s `SharedFrameBuffer` (`ptr_address()` / `asTypedList()`). Useful when running on environments without dedicated GPU shared handle extensions (e.g. software renderers or virtualized CI).
3. **Tier 3 (Interactive Viewport Preview / Wireframe Canvas)**: When `textureId == null` or in offline test mode, the Viewport component falls back to a high-speed CustomPainter rendering wireframe grids, gizmos, and entity bounding boxes, matching `FluorescentViewport`'s fallback pattern.

---

## 5. Flutter Editor Architecture (`fluorite_editor`)

### 5.1 Dockable Editor Shell Layout

```text
┌───────────────────────────────────────────────────────────────────────────────┐
│ [Fluorescent] File  Edit  View  Entity  Physics  Rendering  Help              │
├───────────────────────────────────────────────────────────────────────────────┤
│ [▶ Play] [⏸ Pause] [⏹ Stop] | Gizmo: [Translate|Rotate|Scale] | FPS: 60  16MB │
├─────────────────────┬───────────────────────────────────┬─────────────────────┤
│ SCENE OUTLINER      │ 3D VIEWPORT                       │ ENTITY INSPECTOR    │
│                     │                                   │                     │
│ 🔍 Filter entities  │ [Perspective | Shaded | Grid ON]  │ Selected: "PBR_Cube"│
│ ▼ Root Scene        │ ┌───────────────────────────────┐ │                     │
│   ├─ 📷 Main Camera │ │                               │ │ ▼ Transform         │
│   ├─ 💡 Sun Light   │ │          [ 3D PBR ]           │ │   Position: [0,1,0] │
│   ├─ 📦 PBR_Cube    │ │       [ Render Target ]       │ │   Rotation: [0,0,0] │
│   ├─ ⚽ PhysicsBall │ │       Texture(id: 1)          │ │   Scale:    [1,1,1] │
│   └─ 🔲 GroundPlane │ │                               │ │                     │
│                     │ └───────────────────────────────┘ │ ▼ Mesh: "Cube.gltf" │
│ ─────────────────── │ ◄── Orbit: RMB | Flycam: WASD ──► │ ▼ Material: PBR     │
│ ASSET BROWSER       │                                   │   Metallic:  [0.85] │
│ 📁 meshes/          │                                   │   Roughness: [0.15] │
│ 📁 materials/       │                                   │ ▼ Physics Body      │
│ 📁 shaders/         │                                   │   Dynamic | 5.0 kg  │
├─────────────────────┴───────────────────────────────────┴─────────────────────┤
│ DIAGNOSTICS & CONSOLE: [Rust Core Running] [Frame: 1420] [BVH Culling: 0.8ms] │
└───────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Scene Outliner (Hierarchical Entity Tree)
- **Data Model**:
  ```dart
  class EditorEntity {
    final int id;
    String name;
    EntityType type; // mesh, light, camera, physicsBody, empty
    bool isVisible;
    bool isLocked;
    int? parentId;
    List<int> childrenIds;
    // Component map
    TransformData transform;
    MeshData? mesh;
    MaterialData? material;
    LightData? light;
    PhysicsData? physics;
  }
  ```
- **Features**:
  - Tree expansion and collapse for nested scene hierarchies.
  - Single-click selection updating `EditorSelectionState`.
  - Add Entity menu: Primitive Mesh (Cube, Sphere, Cylinder, Plane), Lights (Directional, Point, Spot), Physics RigidBody (Dynamic, Static), Camera.
  - Delete, duplicate, and rename operations with immediate scene graph synchronization.
  - Filter bar searching by entity name or component type.

### 5.3 Entity Inspector
The Inspector inspects and live-edits components attached to the selected entity:
1. **Transform Card**:
   - Translation `(X, Y, Z)` with numeric inputs and drag scrubbing.
   - Rotation: Dual Euler Angles `(Pitch, Yaw, Roll)` and Quaternion `(qx, qy, qz, qw)`. Editing Euler dynamically recomputes the quaternion and updates the 16-float stride in `TransformStorage`.
   - Scale `(X, Y, Z)` with uniform scale lock toggle.
2. **Mesh Card**:
   - Primitive type selector (`cube`, `sphere`, `plane`, `cylinder`, `custom_gltf`).
   - Vertex and polygon statistics display.
3. **PBR Material Card**:
   - Base Color (Albedo) RGB picker / hex input.
   - Metallic slider `[0.0 .. 1.0]`.
   - Roughness slider `[0.0 .. 1.0]`.
   - Emissive Color & Intensity `[0.0 .. 10.0]`.
   - Normal Map toggle & normal strength.
4. **Light Card (Clustered Forward+)**:
   - Type: `Directional`, `Point`, `Spot`.
   - Light Color and Intensity (Lumens).
   - Attenuation Radius and Spot Angle.
   - Cast Shadows toggle and shadow map resolution.
5. **Physics Card (`rapier3d` Integration)**:
   - Body Type: `Dynamic`, `Static`, `Kinematic`.
   - Mass (kg), Linear Damping, Angular Damping.
   - Collider Shape: `Box`, `Sphere`, `Capsule`, `Trimesh`.
   - Material: Friction `[0.0 .. 1.0]`, Restitution / Bounciness `[0.0 .. 1.0]`.

### 5.4 Active 3D Viewport Widget
- **Widget Integration**:
  ```dart
  class EditorViewport extends StatefulWidget { ... }
  ```
  - Displays `Texture(textureId: engineStatus.textureId ?? 1)`.
  - Listens to mouse and keyboard events via `Listener`, `MouseRegion`, and `Focus` / `KeyboardListener`.
  - Renders overlay HUD (Current FPS, Active Frame Index, Memory Allocation telemetry, Viewport Gizmo).
  - Maintains aspect ratio and dispatches viewport resize events (`resolution_width`, `resolution_height`) to `fluorite_core` so the offscreen render target matches the screen viewport dimensions without scaling distortion.

---

## 6. Camera Controls & Viewport Interaction

### 6.1 Two Navigation Modes

#### Mode 1: Orbit Camera (Default Inspection)
- **Math & Spherical Coordinates**:
  $$\text{position} = \text{target} + r \cdot \begin{pmatrix} \cos(\theta)\cos(\phi) \\ \sin(\phi) \\ \sin(\theta)\cos(\phi) \end{pmatrix}$$
  Where $r$ is orbit radius, $\theta$ is yaw angle, and $\phi$ is pitch angle (clamped to $[-89^\circ, 89^\circ]$ to prevent gimbal lock).
- **Interactions**:
  - **Orbit Rotation**: Right Mouse Button (RMB) drag or Alt + Left Mouse Button (LMB) drag.
  - **Zoom**: Mouse scroll wheel (adjusts $r$ exponentially: $r \leftarrow r \cdot (1 - \text{delta} \cdot 0.1)$).
  - **Pan**: Middle Mouse Button (MMB) drag or Shift + RMB drag (translates both $\text{position}$ and $\text{target}$ along the camera's local right and up vectors).
  - **Focus ("F" Key)**: Animates $\text{target}$ to the selected entity's position and sets $r$ to $2 \times \text{bounding\_radius}$.

#### Mode 2: Flycam / FPS Mode (Free Flight)
- **Activation**: Hold RMB inside the Viewport. Cursor is locked or hidden.
- **Flight Movement**:
  - `W` / `S`: Move forward / backward along camera look vector.
  - `A` / `D`: Strafe left / right along camera right vector.
  - `E` / `Q` (or `Space` / `C`): Move up / down along world up vector $(0, 1, 0)$.
  - `Shift`: Boost speed multiplier ($3\times$).
  - Mouse Scroll Wheel during flight: Dynamically scales base flight speed.

---

## 7. Desktop Launch Support & Dependencies

### 7.1 `fluorite_editor/pubspec.yaml`
The current `pubspec.yaml` contains:
```yaml
name: fluorite_editor
description: "A new Flutter desktop project for Fluorite Editor Integration."
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ">=3.4.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_rust_bridge: 2.13.0
  vector_math: ^2.1.4

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
```

### 7.2 Platform Runner Directory Scaffolding
To enable `flutter run -d windows` / `macos` / `linux`:
- **Windows**:
  - `windows/CMakeLists.txt`
  - `windows/runner/main.cpp`
  - `windows/runner/flutter_window.cpp` & `flutter_window.h`
  - `windows/runner/win32_window.cpp` & `win32_window.h`
  - `windows/runner/Runner.rc` & `resource.h`
- **macOS**:
  - `macos/Runner/AppDelegate.swift`
  - `macos/Runner/MainFlutterWindow.swift`
  - `macos/Runner.xcodeproj`
- **Linux**:
  - `linux/CMakeLists.txt`
  - `linux/main.cc`
  - `linux/my_application.cc` & `my_application.h`

---

## 8. E2E Memory Stability During Real-Time Physics & Rendering

### 8.1 The Zero-Fragmentation Guarantee
In high-performance AAA engines, per-frame memory churn causes severe GC pauses in managed runtimes and heap fragmentation in C/C++.
Fluorite Engine solves this via the **`DoubleBufferedFrameAllocator`** in `fluorite_core/src/allocator/frame.rs`:
- Per-frame capacity: **16 Megabytes** (`DEFAULT_ENGINE_FRAME_CAPACITY`).
- Hardware alignment: **64 bytes** (CPU cache-line boundary).
- Diagnostic sentinels: Byte 0 = `0xAA`, Byte $N-1$ = `0x55`.
- Ping-pong swap at frame boundary:
  ```rust
  pub fn swap_buffers(&self) {
      let old_idx = self.current_index.load(Ordering::Relaxed);
      let next_idx = (old_idx + 1) % 2;
      self.arenas[next_idx].reset(); // O(1) bulk reset
      self.frame_index.fetch_add(1, Ordering::Relaxed);
      self.current_index.store(next_idx, Ordering::Release);
  }
  ```
- Physics simulation (`rapier3d`) and BVH frustum culling allocate transient query contacts, raycast hit lists, and draw commands strictly out of the active frame arena.
- At the end of each frame, the alternate arena is reset in $O(1)$ without releasing the backing memory to the OS.
- Result: **Zero OS malloc/free calls per frame**, **zero GC pressure**, and strictly bounded memory usage.

### 8.2 E2E Verification Test Methodology
The E2E test verifies memory stability across a simulated continuous editor workload:
1. Initialize engine via `start_engine()`.
2. Run a 1,000-frame simulation loop at 60 FPS:
   - Step physics simulation (`rapier3d` rigid body contacts and character controller updates).
   - Perform BVH spatial queries and frustum culling over entities.
   - Dispatch PBR rendering draw commands and update offscreen render target.
   - Inspect memory metrics: `total_memory_allocated <= arena_capacity (16MB)`.
   - Verify sentinel integrity on shared frame buffers (`verify_buffer_sentinels() == true`).
   - Assert zero memory leak (allocated bytes cleanly resets after frame buffer swap).

---

## 9. Feature Breakdown & Implementation Recommendations

To transition from the current state to full acceptance of Requirement 4, the implementation should be organized into 5 structured packages of work:

| Work Package | Deliverables | Target Files |
|:---|:---|:---|
| **WP 1: Desktop Runners & Entry Point** | Create `lib/main.dart` and desktop runner directories (`windows/`, `macos/`, `linux/`). Ensure `fluorite_editor` compiles and boots into a Material Desktop Shell. | `fluorite_editor/lib/main.dart`<br>`fluorite_editor/windows/`<br>`fluorite_editor/macos/`<br>`fluorite_editor/linux/` |
| **WP 2: State Model & Scene Graph** | Implement `EditorState`, `SceneModel`, `EditorEntity`, and component data structures (Transform, Mesh, PBR Material, Light, Physics). | `fluorite_editor/lib/src/models/scene_model.dart`<br>`fluorite_editor/lib/src/models/components.dart`<br>`fluorite_editor/lib/src/models/editor_state.dart` |
| **WP 3: Dockable Shell & Panes** | Implement the multi-split dockable UI: MenuBar, Toolbar (Play/Pause), Scene Outliner, Entity Inspector, and Diagnostics Console. | `fluorite_editor/lib/src/ui/editor_shell.dart`<br>`fluorite_editor/lib/src/ui/scene_outliner.dart`<br>`fluorite_editor/lib/src/ui/entity_inspector.dart`<br>`fluorite_editor/lib/src/ui/diagnostics_bar.dart` |
| **WP 4: 3D Viewport & Camera** | Implement `EditorViewport` with `Texture(textureId: ...)`, Orbit and Flycam camera controllers, mouse/keyboard listeners, and Viewport HUD. | `fluorite_editor/lib/src/viewport/editor_viewport.dart`<br>`fluorite_editor/lib/src/viewport/camera_controller.dart`<br>`fluorite_editor/lib/src/viewport/viewport_overlay.dart` |
| **WP 5: E2E Integration Test Suite** | Implement automated E2E test verifying editor lifecycle, scene updates, camera movement, and 1,000-frame zero-copy memory stability during real-time physics and rendering. | `fluorite_editor/test/editor_e2e_stability_test.dart`<br>`tests/e2e_runner.dart` |

---

## 10. Conclusion
The repository possesses a mature, battle-tested memory and FFI bridge foundation in `fluorite_core` and `fluorite_editor/test/`. The required Phase 2 Wave 1 enhancements for Requirement 4 can be cleanly implemented without external bloat by following Flutter's native desktop conventions and standardizing on the zero-copy texture sharing architecture. All findings, interfaces, and recommendations are fully documented and ready for execution.
