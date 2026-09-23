# Fluorescent Engine Specification

**Version:** 0.2.0  
**Status:** Architectural Specification  
**Last Updated:** 2026-09-18

---

## 1. What This Engine Is

Fluorescent is **not** a modified Fluorite engine. It is a **new, layered game/runtime platform** built from Fluorite's ideas and technology.

The central idea:

> **Flutter for the application/editor experience, Rust for the core runtime, Fluorite/Filament-inspired rendering for the visual layer, and an O3DE/Unreal-class systems architecture underneath.**

### Philosophy

- **Fluorite** gives you the seed.
- **Flutter** gives you the interface.
- **Rust** gives you the heart.
- **Vulkan** gives you the hardware abstraction.
- **Godot** gives you lessons in developer experience.
- **O3DE** gives you lessons in modular AAA architecture.
- **Unreal** gives you the benchmark for AAA capability.

The goal is **not** to make a Frankenstein of those engines. It is to **extract the architectural ideas you need and build a coherent engine around them**.

---

## 2. High-Level Architecture

```text
                         ┌───────────────────────────────┐
                         │        YOUR GAME ENGINE       │
                         │                               │
                         │   AAA • OPEN • CROSS-PLATFORM │
                         └───────────────┬───────────────┘
                                         │
                 ┌───────────────────────┴───────────────────────┐
                 │                                               │
        ┌────────▼────────┐                             ┌────────▼────────┐
        │  FLUTTER LAYER  │                             │   RUST RUNTIME  │
        │                 │                             │                 │
        │ Editor          │                             │ ECS             │
        │ UI              │                             │ Gameplay        │
        │ HUD             │                             │ Networking      │
        │ Menus           │                             │ Physics         │
        │ Tools           │                             │ Animation       │
        │ Launcher        │                             │ Audio           │
        │ Social          │                             │ AI              │
        └────────┬────────┘                             │ Assets          │
                 │                                      │ Scripting       │
                 │                                      └────────┬────────┘
                 │                                               │
                 └──────────────────────┬────────────────────────┘
                                        │
                              ┌─────────▼─────────┐
                              │ ENGINE SERVICES   │
                              │                   │
                              │ Rendering         │
                              │ Physics           │
                              │ Animation         │
                              │ VFX               │
                              │ Audio             │
                              │ World             │
                              │ AI                │
                              │ Networking        │
                              └─────────┬─────────┘
                                        │
                         ┌──────────────▼──────────────┐
                         │       PLATFORM ABSTRACTION │
                         │                            │
                         │ Android │ Desktop │ Linux  │
                         │ Vulkan  │ Vulkan  │ Vulkan │
                         └──────────────┬─────────────┘
                                        │
                                ┌───────▼───────┐
                                │    HARDWARE   │
                                │ GPU / CPU /   │
                                │ Memory / I/O  │
                                └───────────────┘
```

---

## 3. Two Engines in One: Creation Runtime & Game Runtime

The engine has two distinct runtime modes that share the same project.

```text
                  YOUR ENGINE
                       │
          ┌────────────┴────────────┐
          │                         │
     CREATION RUNTIME          GAME RUNTIME
          │                         │
       Flutter                     Rust
          │                         │
       Editor                  ECS / Systems
       Inspector                  Renderer
       Scene tools                Physics
       Material tools             Animation
       VFX tools                  Audio
       World tools                AI
       Profiler                   Networking
          │                         │
          └────────────┬────────────┘
                       │
                 SAME PROJECT
```

**The editor is not an afterthought.** The Creation Runtime is a first-class citizen of the engine, built in Flutter, capable of live-editing the same world that the Game Runtime executes.

---

## 4. Rust Is the Heart

Instead of Dart/Flutter being the engine's core, **Rust is the authoritative runtime**. All gameplay state, physics, networking, and rendering commands originate from and are owned by Rust.

```text
                       RUST
                         │
       ┌─────────────────┼─────────────────┐
       │                 │                 │
      ECS              Systems          Runtime
       │                 │                 │
       ├── Entity        ├── Physics       ├── Threads
       ├── Component     ├── Animation     ├── Jobs
       ├── Archetype     ├── Audio         ├── Memory
       └── World         ├── AI            └── Scheduling
                         ├── Networking
                         ├── Gameplay
                         └── Rendering
```

Flutter is a **high-level interface to the engine**, not the engine itself:

```text
Flutter
   │
   │ FFI (Zero-Copy)
   ▼
Rust API
   │
   ▼
Game World
   │
   ├── Entity
   ├── Component
   ├── System
   └── Resource
```

This gives a very clean separation of concerns. Flutter never owns gameplay state; it reads and displays it.

---

## 5. The Renderer as Its Own Engine

Rather than scattering rendering logic throughout the codebase, the renderer is conceptualized as a self-contained sub-engine with clear boundaries.

```text
                 RENDERING ENGINE
                       │
          ┌────────────┼────────────┐
          │            │            │
       Geometry     Lighting      Materials
          │            │            │
       Virtual       GI           Shaders
       Geometry      Shadows      Textures
          │            │            │
          └────────────┼────────────┘
                       │
                    Vulkan
```

The initial implementation can leverage **Fluorite/Filament technology**, while progressively replacing pieces with Rust-native systems. This provides an evolutionary path rather than a giant rewrite.

### Renderer Target Feature Set

```text
YOUR RENDERER
├── PBR
├── HDR
├── Forward+
├── Deferred
├── GPU-driven rendering
├── Virtual geometry
├── Virtual textures
├── Dynamic GI
├── Ray tracing
├── Global illumination
├── Virtual shadows
├── Screen-space effects
├── Volumetrics
├── HDR tonemapping
├── Temporal reconstruction
├── Upscaling
└── GPU particles
```

---

## 6. The 10 Major Engine Subsystems

### Game Engine Layer

```text
┌───────────────────────────────────────────┐
│                 GAME ENGINE                │
├───────────────────────────────────────────┤
│ 1. Core / ECS                              │
│ 2. Rendering                               │
│ 3. Physics                                 │
│ 4. Animation                               │
│ 5. Audio                                   │
│ 6. VFX                                     │
│ 7. World / Terrain                         │
│ 8. AI                                      │
│ 9. Networking                              │
│ 10. Asset / Build Pipeline                 │
└───────────────────────────────────────────┘
```

### Creator Platform Layer

```text
┌───────────────────────────────────────────┐
│             CREATOR PLATFORM              │
├───────────────────────────────────────────┤
│ Scene Editor                              │
│ World Editor                              │
│ Material Editor                           │
│ Animation Editor                          │
│ VFX Editor                                │
│ Audio Editor                              │
│ AI/Behavior Editor                        │
│ Visual Scripting                           │
│ Profiler                                  │
│ Debugger                                  │
└───────────────────────────────────────────┘
```

---

## 7. Flutter as First-Class UI Runtime

This is where the engine diverges from Unreal/Unity. Flutter is a **first-class UI runtime**, not a wrapper.

A game developer writes:

```text
Game
 ├── 3D World
 │    ├── Player
 │    ├── NPCs
 │    ├── Vehicles
 │    └── Environment
 │
 └── Flutter UI
      ├── Inventory
      ├── Map
      ├── Quest Log
      ├── Chat
      ├── Shop
      └── Settings
```

The 3D world is rendered by Rust/native GPU systems. Flutter handles the complex UI. This is a **very compelling combination** because Flutter's widget system is vastly superior to any in-engine UI framework (UMG, UGUI, etc.) for building complex application-quality interfaces.

---

## 8. Everything Is an Entity (ECS Model)

Borrow heavily from ECS thinking. Every object in the world is an entity composed of data-only components.

### Player Entity Example

```text
Player
├── Transform
├── Mesh
├── Material
├── PhysicsBody
├── CharacterController
├── AnimationController
├── Health
├── Inventory
├── NetworkIdentity
└── AIController
```

### NPC Entity Example

```text
NPC
├── Transform
├── Mesh
├── Animation
├── NavAgent
├── Behavior
├── Dialogue
└── NetworkIdentity
```

This gives a common language across the entire engine. Systems operate on component archetypes, not inheritance hierarchies.

---

## 9. Hardware Capability Tiers

The Android/Desktop strategy is fundamental, not an export option. The engine defines **capability tiers** and the same game project runs across all of them.

```text
                    ENGINE
                       │
                Hardware Detection
                       │
        ┌──────────────┼──────────────┐
        │              │              │
      MOBILE        DESKTOP         HIGH-END
        │              │              │
     Tier 1         Tier 2           Tier 3
        │              │              │
      Vulkan         Vulkan          Vulkan
        │              │              │
   Reduced GI      Dynamic GI      Full GI
   Simple VFX      GPU VFX         Advanced VFX
   Lower LOD       Adaptive LOD    Virtual Geometry
```

The engine automatically detects what the hardware can support and scales the rendering pipeline accordingly. This is a key differentiator.

---

## 10. Data-Driven Engine

Instead of baking everything into compiled code, the engine interprets data resources. This becomes extremely useful for modding and eventually an asset ecosystem.

### Project Structure

```text
Game Project
│
├── project.yaml
├── scenes/
├── entities/
├── materials/
├── shaders/
├── textures/
├── meshes/
├── animations/
├── audio/
├── VFX/
├── scripts/
└── plugins/
```

The engine interprets those resources at runtime. Game logic, materials, VFX, and world layout are all described as data that the engine loads, validates, and executes.

---

## 11. The Ultimate Layered Architecture

```text
                  ┌─────────────────────┐
                  │     GAME / APP      │
                  └──────────┬──────────┘
                             │
                  ┌──────────▼──────────┐
                  │     FLUTTER UI      │
                  └──────────┬──────────┘
                             │
                  ┌──────────▼──────────┐
                  │     ENGINE API      │
                  └──────────┬──────────┘
                             │
                  ┌──────────▼──────────┐
                  │    RUST RUNTIME     │
                  │                     │
                  │ ECS • Jobs • Memory │
                  │ Gameplay • Network  │
                  └──────────┬──────────┘
                             │
          ┌──────────────────┼───────────────────┐
          │                  │                   │
     ┌────▼────┐       ┌─────▼─────┐       ┌─────▼─────┐
     │ RENDER  │       │ SIMULATION│       │ SERVICES  │
     │         │       │           │       │           │
     │ Vulkan  │       │ Physics   │       │ AI        │
     │ Filament│       │ Animation │       │ Audio     │
     │ GI      │       │ Vehicles  │       │ Network   │
     │ VFX     │       │ Destruct. │       │ Streaming │
     └────┬────┘       └─────┬─────┘       └─────┬─────┘
          │                  │                   │
          └──────────────────┼───────────────────┘
                             │
                  ┌──────────▼──────────┐
                  │ PLATFORM ABSTRACTION│
                  └──────────┬──────────┘
                             │
             ┌───────────────┼────────────────┐
             │               │                │
          Android          Desktop          Server
             │               │                │
          Vulkan           Vulkan           Headless
```

---

## 12. AAA Subsystem Detail

### 12.1 World Streaming

Inspired by Unreal's World Partition and O3DE's large-world terrain.

```text
World
│
├── World coordinates (double-precision / origin rebasing)
├── Streaming cells
├── Level of detail
├── Entity streaming
├── Terrain streaming
├── Asset streaming
├── Physics streaming
├── AI streaming
└── Network relevance
```

Cell-based loading/unloading:

```text
                 WORLD
                   │
        ┌──────────┼──────────┐
        │          │          │
      Cell A     Cell B     Cell C
        │          │          │
      Loaded     Loaded    Unloaded
```

### 12.2 VFX System (Niagara-class)

A unified GPU particle/VFX system. All visual effects (fire, smoke, explosion, magic, rain, snow, dust, sparks, destruction, weather) are built from the same underlying graph-based system.

```text
VFX Graph Particle
│
├── Position
├── Velocity
├── Rotation
├── Scale
├── Color
├── Collision
├── Forces
├── Noise
├── GPU simulation
└── Events
```

### 12.3 Animation System

For AAA, the engine needs considerably more than skeletal animation playback.

```text
Animation System
│
├── Animation Graph
├── State Machines
├── Blend Trees
├── IK (Inverse Kinematics)
├── Full Body IK
├── Motion Matching
├── Retargeting
├── Procedural Animation
├── Facial Animation
├── Cloth
├── Ragdolls
└── Animation Compression
```

### 12.4 Destruction Pipeline

Physics, destruction, VFX, audio, and gameplay are all connected through events:

```text
Building → Fracture → Rigid bodies → Debris → Dust → Particles → Sound

Physics → Destruction → VFX → Audio → Gameplay
```

### 12.5 Procedural Content Generation (PCG)

Node-based procedural world generation, particularly powerful when combined with world streaming.

```text
PCG GRAPH

Input
 │
 ├── Terrain
 ├── Biome
 ├── Density
 ├── Slope
 ├── Height
 └── Noise
       │
       ▼
 Distribution
       │
 ┌─────┼─────┐
 │     │     │
Trees Rocks Buildings
 │     │     │
 └─────┴─────┘
       │
       ▼
 Generated World
```

### 12.6 Multiplayer Networking

A first-class engine subsystem, not an add-on. Rust is particularly attractive for deterministic, low-latency networking.

```text
Rust Networking
├── Client
├── Server
├── Replication
├── Prediction
├── Interpolation
├── Lag compensation
├── Rollback
├── Interest management
├── Entity ownership
├── Authentication
├── Matchmaking
└── Dedicated server
```

### 12.7 Visual Scripting

Not because programmers need it, but because artists and designers do. Visual scripts compile down to Rust ECS commands for native performance.

```text
Visual Script → Rust ECS Commands → Native Runtime
```

### 12.8 Developer Tooling & Profiler

```text
Profiler
├── CPU
├── GPU
├── Memory
├── Network
├── ECS
├── Rendering
└── Asset loading
```

Plus: frame debugger, GPU capture, entity inspector, network debugger, physics debugger, animation debugger, shader debugger, asset dependency viewer, memory leak detection, and performance budgets.

---

## 13. The Flutter Editor

The editor is Flutter-based, making it cross-platform by default.

```text
┌───────────────────────────────────────────┐
│ File  Edit  GameObject  Window  Build     │
├──────────┬────────────────────┬───────────┤
│ Assets   │                    │ Inspector │
│          │                    │           │
│ Models   │     3D VIEW        │ Transform │
│ Textures │                    │ Material  │
│ Audio    │                    │ Physics   │
│ Scripts  │                    │ AI        │
├──────────┴────────────────────┴───────────┤
│ Timeline │ Console │ Profiler │ Animation │
└───────────────────────────────────────────┘
```

---

## 14. Phased Roadmap

### Phase 1 — Foundation
Fluorite → Rust core → ECS → Flutter integration → Vulkan

### Phase 2 — Engine
Rendering, Physics, Animation, Audio, Assets, Scenes, Input, Scripting

### Phase 3 — AAA
GPU-driven rendering, Virtual geometry, Dynamic GI, Virtual shadows, GPU VFX, Advanced animation, Destruction, World streaming, PCG

### Phase 4 — Online
Replication, Prediction, Rollback, Dedicated servers, Matchmaking, Voice, Accounts, Persistence

### Phase 5 — Developer Ecosystem
Editor, Visual scripting, Material editor, Shader editor, Animation editor, VFX editor, World editor, Profiler, Asset marketplace, SDK

### Phase 6 — Android Desktop Specialization
Hardware detection, Dynamic quality tiers, Vulkan optimization, Desktop windowing, Gamepad, Keyboard/mouse, Multi-monitor, High refresh rate, HDR, Upscaling, Dynamic resolution, Power/performance management

---

## 15. Module Boundaries & FFI Contract

### Rust → Flutter Communication
- **Zero-Copy FFI** via `flutter_rust_bridge` v2
- Shared memory buffers (`Float32List`) backed by Rust `ArenaAllocator`
- `NativeFinalizer` attached to all Dart-side handles for leak-free lifecycle
- No serialization overhead; Dart reads Rust memory directly via native pointers

### Flutter → Rust Communication
- Synchronous FFI calls for queries (entity position, health, etc.)
- Asynchronous FFI calls for commands (spawn entity, apply force, etc.)
- Event channels for streaming updates (network state, physics events, etc.)

### Native Platform Interop & Bridges
- Traditional C++ implementations for platform-specific capabilities (like JNI bindings and `AHardwareBuffer` setup for Vulkan on Android) are deprecated.
- Native bridges are now implemented entirely in Rust (e.g., within `fluoderpod_render`) utilizing `jni`, `ndk-sys`, and `ash` directly.
- The ultimate architectural goal is for `fluoderpod` to make direct native connections to hardware features (GPS, Sensors, I/O) bypassing standard JNI layers (or rewriting them internally) for maximum memory safety and throughput.

### Renderer Boundary
- The renderer accepts a command buffer from the ECS/Systems layer
- It does not know about gameplay, entities, or Flutter
- It only knows about draw calls, materials, lights, and geometry

---

## 16. Strategic Differentiators

1. **Rust + Flutter**: Memory-safe, high-performance core with the best cross-platform UI framework for tooling and in-game interfaces.
2. **Scalable Renderer**: Same game project, automatically adapted from mobile to desktop to high-end via hardware capability tiers.
3. **Flutter-Native Editor**: The editor itself is a Flutter application, making it instantly cross-platform and extensible with the entire Flutter/Dart ecosystem.
4. **Unified Application/Game Runtime**: One platform for game + launcher + UI + social + inventory + marketplace + settings + editor tooling.
5. **Data-Driven Architecture**: All game content described as data, enabling modding, hot-reloading, and eventual marketplace support.
6. **Two Runtimes, One Project**: Creation Runtime (editor) and Game Runtime (player) share the same project and world representation.
