# FLUORESCENT TECHNICAL SPECIFICATION & PROJECT SCAFFOLD

> [!IMPORTANT]
> **This document is the original 0.1.0-alpha scaffold.** For the current formal engine specification — including the dual-runtime architecture, Rust-as-heart philosophy, AAA subsystem breakdown, and phased roadmap — see **[ENGINE_SPECIFICATION.md](ENGINE_SPECIFICATION.md)**.

**Version:** 0.1.0-alpha 
**Status:** Superseded by ENGINE_SPECIFICATION.md v0.2.0  
**Target Platforms:** iOS 15+, Android 10+, Web (WebGPU), Automotive (AAOS/QNX) 
 
## 1. EXECUTIVE SUMMARY 
 
Fluorescent is a 3D rendering bridge for the Flame engine, enabling AAA-quality open world games within Flutter's ecosystem. It wraps Flame (preserving 2D maturity) and renders via Vulkan/Metal/WebGPU into Flutter's texture pipeline, with optional integration into Toyota's Fluorite HMI for automotive deployments. 
 
**Core Philosophy:** Extend, don't replace. Flame handles 2D/game logic; Fluorescent adds 3D viewport capabilities. 
 
--- 
 
## 2. SYSTEM ARCHITECTURE 
 
### 2.1 Layer Stack 
 
``` 
┌─────────────────────────────────────┐ 
│         Application Layer           │ 
│  (Flutter Widgets + Flame Game)     │ 
├─────────────────────────────────────┤ 
│      Fluorescent Bridge             │ 
│  ┌─────────────┐ ┌─────────────┐   │ 
│  │ 3D Viewport │ │ Asset Stream│   │ 
│  │ Component   │ │ Manager     │   │ 
│  └─────────────┘ └─────────────┘   │ 
│  ┌─────────────┐ ┌─────────────┐   │ 
│  │ Render      │ │ Fluorite    │   │ 
│  │ Pipeline    │ │ Automotive  │   │ 
│  │ (Vulkan/    │ │ Adapter     │   │ 
│  │  WebGPU)    │ │ (Optional)  │   │ 
│  └─────────────┘ └─────────────┘   │ 
├─────────────────────────────────────┤ 
│         Flame Engine                │ 
│  (2D, Input, Audio, Lifecycle)      │ 
├─────────────────────────────────────┤ 
│         Flutter SDK                 │ 
│  (Platform Channels, Textures)      │ 
├─────────────────────────────────────┤ 
│         Platform                    │ 
│  (iOS/Android/Web/Automotive)       │ 
└─────────────────────────────────────┘ 
``` 
 
### 2.2 Component Model 
 
**FluorescentViewport** (Extends Flame's PositionComponent) 
 
```dart 
class FluorescentViewport extends PositionComponent { 
  final World3D world; 
  final Camera3D camera; 
  final RenderConfig config; 
   
  // Renders 3D to texture, composites as Flame component 
  // Respects Flame's priority, camera transforms, layering 
} 
``` 
 
**Integration Pattern:** 
- 2D UI overlays 3D (HUD on viewport) 
- 3D renders behind 2D sprites (parallax backgrounds) 
- Split-screen: Multiple viewports in one Flame game 
 
--- 
 
## 3. TECHNICAL SPECIFICATIONS 
 
### 3.1 Rendering Pipeline 
 
**API Abstraction:** 
 
| Platform | API | Fallback | Notes | 
| --- | --- | --- | --- | 
| Android | Vulkan 1.3 | OpenGL ES 3.2 | Mesh shaders on Snapdragon 8+ | 
| iOS | Metal 3 | Metal 2 | iPhone 15 Pro+ for RT | 
| Web | WebGPU | WebGL 2 | Chrome 113+, Safari 26+ | 
| Automotive | Vulkan 1.1 | OpenGL ES 3.0 | Safety-throttled | 
 
**Rendering Features:** 
- **Clustered Forward+**: 1024 dynamic lights, O(1) per-pixel cost 
- **Virtual Shadow Maps**: 2048px effective resolution, 16x anisotropic 
- **Temporal Upsampling**: 1080p internal → 4K output (FSR 2.0 equivalent) 
- **Mesh Shader Pipeline**: GPU-driven rendering, 10x draw call reduction 
- **Virtual Texturing**: 128k×128k terrain, 128px tile streaming 
 
### 3.2 Memory Budgets 
 
| Platform | RAM Limit | Texture Budget | Mesh Budget | Strategy | 
| --- | --- | --- | --- | --- | 
| Mobile (Base) | 1.5GB | 512MB | 256MB | Aggressive LOD | 
| Mobile (High) | 3GB | 1GB | 512MB | Full quality | 
| Web | 2GB | 768MB | 384MB | Browser tab limits | 
| Automotive | 512MB | 128MB | 64MB | Safety reserve | 
 
**Streaming Architecture:** 
- **Chunk Size**: 64m×64m (configurable) 
- **LOD Levels**: 0-7 (0 = full geometry, 7 = billboard imposter) 
- **Async Loading**: Isolate-based decompression, main thread only for GPU upload 
- **Eviction**: LRU with gameplay priority override 
 
### 3.3 Physics Bridge 
 
**Dual Physics System:** 
- **2D**: Forge2D (Box2D) - Flame native, unchanged 
- **3D**: Jolt Physics (C++ via FFI) - deterministic, multi-threaded 
 
**Interop:** 
 
```dart 
// 2D character walking on 3D terrain 
final height = joltPhysics.raycastDown(position3D); 
forge2DBody.setTransform(2DPosition(height)); 
``` 
 
### 3.4 Fluorite Automotive Integration (Optional) 
 
**Safety Constraints:** 
- **Process Isolation**: Runs in `isolatedProcess` (Android) or separate QNX process 
- **ASIL Degradation**: Automatic 30fps cap when vehicle in Drive 
- **Memory Watchdog**: Hard 512MB limit, graceful degradation on exceed 
- **Input Routing**: Fluorite captures steering wheel → maps to Flame gamepad events 
 
**Data Interface (Read-Only):** 
 
```dart 
class FluoriteVehicleData { 
  final double speedKph;        // For speed-limited gameplay 
  final double steeringAngle;   // For mirror mode 
  final bool isParked;          // Enable full features 
  final String? routeHistory;   // Ghost racing data 
} 
``` 
 
--- 
 
## 4. IMPLEMENTATION PHASES 
 
### Phase 1: Core Bridge (Months 1-3) 
**Goal:** Render static 3D scene in Flame widget 
 
- `FluorescentViewport` component (basic) 
- Vulkan backend (Android) 
- Metal backend (iOS) 
- Texture interop (Flutter `Texture` widget) 
- Basic glTF loading (static meshes) 
 
### Phase 2: Rendering Features (Months 4-6) 
**Goal:** AAA visual quality 
 
- Clustered forward+ lighting 
- Shadow mapping (CSM) 
- PBR materials (metallic-roughness) 
- Post-processing (bloom, SSAO, tonemapping) 
- Shader hot-reload 
 
### Phase 3: Streaming & Physics (Months 7-9) 
**Goal:** Open world capability 
 
- Chunk streaming system 
- Virtual texturing 
- Jolt Physics integration 
- LOD generation tools 
- Memory management (budget enforcement) 
 
### Phase 4: Platform Expansion (Months 10-12) 
**Goal:** Full platform support 
 
- WebGPU backend 
- Automotive/Fluorite adapter 
- Performance profiling tools 
- Asset pipeline CLI 
 
### Phase 5: Ecosystem (Months 13-15) 
**Goal:** Production readiness 
 
- Visual shader editor 
- Level design tools 
- Documentation/tutorials 
- Performance optimization guides 
 
--- 
 
## 5. API SPECIFICATION (Preview) 
 
### 5.1 Basic Usage 
 
```dart 
import 'package:flame/game.dart'; 
import 'package:fluorescent_flame/fluorescent_flame.dart'; 
 
class OpenWorldGame extends FlameGame { 
  late final FluorescentViewport world3D; 
   
  @override 
  Future<void> onLoad() async { 
    // Load 3D world 
    world3D = FluorescentViewport( 
      world: await StreamingWorld.load('assets/worlds/island.fworld'), 
      camera: ThirdPersonCamera( 
        fov: 60, 
        near: 0.1, 
        far: 1000, 
      ), 
      config: RenderConfig( 
        quality: QualityPreset.high, 
        targetFps: 60, 
      ), 
    ); 
     
    add(world3D); 
     
    // 2D UI overlay (standard Flame) 
    add(JoystickComponent()); 
    add(HUD()); 
  } 
   
  @override 
  void update(double dt) { 
    super.update(dt); 
     
    // Update 3D camera from 2D input 
    world3D.camera.move(joystick.delta); 
  } 
} 
```