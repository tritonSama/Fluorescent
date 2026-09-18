# Fluorescent Engine Architecture

## High-Level Concept

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

## Two Engines in One

Your project has a Game Runtime and a Creation Runtime, existing side-by-side in the same project. The editor is not an afterthought.

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

## Rust as the Authoritative Runtime

Instead of Dart/Flutter being the engine's core, Rust is the authoritative runtime.

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

Flutter serves as a high-level interface to the engine via FFI:

```text
Flutter
   │
   │ FFI
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

## Rendering as its own Engine

Rendering is not scattered but conceptually isolated, providing an evolutionary path from Fluorite/Filament technology to custom Rust-native systems.

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

## The AAA Layer & Creator Platform

### Game Engine (10 Major Subsystems)
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

### Creator Platform
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

## Flutter: First-Class UI Runtime

Flutter handles the complex UI while the 3D world is rendered by Rust/native GPU systems.

```text
Game
 ├── 3D World (Rust/Native GPU)
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

## Everything is an Entity (ECS)

Common language across the engine using a Data-Oriented ECS approach:

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

## Capability Tiers

Capability tiers are fundamental. The same game project runs across all tiers gracefully.

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

## Data-Driven Engine

Instead of baking everything into C++/Rust code, the engine is data-driven, facilitating modding and asset ecosystems.

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

## Ultimate Architecture

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

## Philosophy

- **Fluorite** gives you the seed.
- **Flutter** gives you the interface.
- **Rust** gives you the heart.
- **Vulkan** gives you the hardware abstraction.
- **Godot** gives you lessons in developer experience.
- **O3DE** gives you lessons in modular AAA architecture.
- **Unreal** gives you the benchmark for AAA capability.

The goal is to extract architectural ideas and build a coherent engine centered around a formal engine specification, preventing the project from turning into an increasingly difficult fork.

## Functional Test App Focus
The architecture is actively being validated through a **Functional Test App** designed to showcase both runtimes (Game Runtime and Creation Runtime) operating concurrently. A major goal of this test application is to render an over layer of visuals for geofencing.
- Rust computes spatial partitioning and handles simulation logic for entities crossing geofences.
- The Renderer constructs glowing/transparent geometric bounds representing the fence.
- Flutter UI overlays control panels and real-time alerts when entities breach these boundaries.
