# Strategic Vision

The core strategic vision for Fluorescent is **not** a modified Fluorite engine — it is a **new, layered game/runtime platform** built from Fluorite's ideas and technology.

> **Flutter for the application/editor experience, Rust for the core runtime, Fluorite/Filament-inspired rendering for the visual layer, and an O3DE/Unreal-class systems architecture underneath.**

For the full formal engine specification, see [ENGINE_SPECIFICATION.md](fluorescent/docs/ENGINE_SPECIFICATION.md).

---

## Core Philosophy

- **Fluorite** gives you the seed.
- **Flutter** gives you the interface.
- **Rust** gives you the heart.
- **Vulkan** gives you the hardware abstraction.
- **Godot** gives you lessons in developer experience.
- **O3DE** gives you lessons in modular AAA architecture.
- **Unreal** gives you the benchmark for AAA capability.

The goal isn't to make a Frankenstein of those engines. It's to **extract the architectural ideas you need and build a coherent engine around them**.

---

## Two Engines in One

The engine has a **Creation Runtime** (the Flutter editor) and a **Game Runtime** (the Rust core). They share the same project and world representation.

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

---

## Rust Is the Heart

Rust is the authoritative runtime. All gameplay state, physics, networking, and rendering commands are owned by Rust. Flutter is a high-level interface to the engine, not the engine itself.

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

---

## The Unified Application/Game Runtime

```text
                     YOUR ENGINE
                          │
              ┌───────────┴───────────┐
              │                       │
           Flutter                  Rust
              │                       │
        Application UI          Game Runtime
              │                       │
              └───────────┬───────────┘
                          │
                     3D Renderer
                          │
               ┌──────────┴──────────┐
               │                     │
            Android               Desktop
               │                     │
            Vulkan                Vulkan
```

The developer can build: game + launcher + UI + social + inventory + marketplace + settings + editor tooling using one underlying platform.

---

## AAA Renderer Scalability (Dynamic Tiers)

Don't blindly reproduce Nanite/Lumen. Build a scalable renderer:

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

The engine automatically determines what the hardware can support. The same game project runs across all tiers.

---

## Phased Roadmap

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

## Agent Roles

To effectively implement this complex architecture, we define the following agent roles for concurrent multi-agent execution:

1. **Rendering Architect Agent**: Focuses on the core graphics pipeline, including the Vulkan/Metal bindings, the Render Graph, and Shader Toolchain (Phase 2 and Phase 3 features like dynamic quality tiers and GPU VFX).
2. **Systems Programmer Agent**: Responsible for the underlying Rust core foundation, ECS, memory management, and `flutter_rust_bridge` zero-copy communication.
3. **Gameplay/Simulation Agent**: Implements the Physics, Navigation, Animation, and Procedural Content Generation (PCG) systems.
4. **Networking & Cloud Agent**: Handles Phase 4 requirements, including multiplayer replication, rollback, dedicated server logic, and cloud integrations (e.g., Firebase, OpenRouteService for mapping).
5. **Tools & Editor Agent**: Develops the Flutter-based Editor UI, Visual Scripting, Profiler, and Asset Pipeline tooling (Phase 5).
6. **UI/UX & Mobile Integration Agent**: Focuses on Flutter UI application layers, including social feeds, background location tracking, battery-efficient GPS, and push notifications.
