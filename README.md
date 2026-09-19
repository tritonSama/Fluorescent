<p align="center">
  <h1 align="center">🔬 Fluorescent Engine</h1>
  <p align="center">
    <strong>AAA • Open Source • Cross-Platform</strong>
  </p>
  <p align="center">
    Flutter for the interface. Rust for the heart. Vulkan for the hardware.
  </p>
  <p align="center">
    <a href="docs/ENGINE_SPECIFICATION.md"><img src="https://img.shields.io/badge/docs-engine_spec-blue?style=flat-square" alt="Engine Spec"></a>
    <img src="https://img.shields.io/badge/rust-1.70%2B-orange?style=flat-square&logo=rust" alt="Rust">
    <img src="https://img.shields.io/badge/flutter-3.22%2B-02569B?style=flat-square&logo=flutter" alt="Flutter">
    <img src="https://img.shields.io/badge/vulkan-1.3-red?style=flat-square&logo=vulkan" alt="Vulkan">
    <img src="https://img.shields.io/badge/license-Apache_2.0-green?style=flat-square" alt="License">
    <img src="https://img.shields.io/badge/status-alpha-yellow?style=flat-square" alt="Status">
  </p>
</p>

---

Fluorescent is a **new, layered game engine and runtime platform** that combines a Rust-native core with Flutter's UI framework and a scalable Vulkan renderer. It is not a fork — it is a ground-up architecture that extracts the best ideas from Godot, O3DE, Unity, and Unreal and builds a coherent, modern engine around them.

```
                  ┌─────────────────────┐
                  │     GAME / APP      │
                  └──────────┬──────────┘
                             │
                  ┌──────────▼──────────┐
                  │     FLUTTER UI      │  ← Editor, HUD, Menus, Tools
                  └──────────┬──────────┘
                             │
                  ┌──────────▼──────────┐
                  │     ENGINE API      │  ← Zero-Copy FFI Bridge
                  └──────────┬──────────┘
                             │
                  ┌──────────▼──────────┐
                  │    RUST RUNTIME     │  ← ECS, Jobs, Memory, Gameplay
                  └──────────┬──────────┘
                             │
          ┌──────────────────┼───────────────────┐
          │                  │                   │
     ┌────▼────┐       ┌─────▼─────┐       ┌─────▼─────┐
     │ RENDER  │       │SIMULATION │       │ SERVICES  │
     │ Vulkan  │       │ Physics   │       │ AI        │
     │ GI/VFX  │       │ Animation │       │ Audio     │
     └────┬────┘       └─────┬─────┘       └─────┬─────┘
          │                  │                   │
          └──────────────────┼───────────────────┘
                             │
                  ┌──────────▼──────────┐
                  │ PLATFORM ABSTRACTION│
                  └──────────┬──────────┘
                             │
             ┌───────────────┼────────────────┐
          Android          Desktop          Server
          Vulkan           Vulkan           Headless
```

## ✨ Why Fluorescent?

| What | How |
|------|-----|
| **Rust is the heart** | All gameplay state, physics, networking, and rendering commands are owned by Rust. Memory-safe, data-race-free, zero-GC. |
| **Flutter is the interface** | The editor, HUDs, menus, inventory, chat, and all game UI are built with Flutter — the best cross-platform UI framework. |
| **Two engines in one** | A **Creation Runtime** (Flutter editor) and a **Game Runtime** (Rust core) share the same project. The editor is a first-class citizen. |
| **Scalable renderer** | One game project automatically adapts from mobile Tier 1 (reduced GI) to desktop Tier 3 (full GI, virtual geometry) via hardware detection. |
| **Data-driven** | Scenes, materials, VFX, and world layout are described as data (YAML/JSON), enabling modding, hot-reload, and marketplace support. |
| **Everything is an entity** | Pure ECS architecture — contiguous `Float32List` storage, sparse-set indexing, zero GC pressure at 10,000+ entities. |
| **Zero-copy FFI** | Rust and Flutter share memory directly via `flutter_rust_bridge` v2. No serialization. No copies. No frame drops. |

## 🧬 Two Runtimes, One Engine

```
                  FLUORESCENT ENGINE
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

## 📦 Repository Structure

```
Fluorescent/
├── fluorescent/                    # Dart/Flutter engine monorepo (Melos)
│   ├── packages/
│   │   ├── fluorescent_core/       # Scene graph, servers, resources, render graph
│   │   ├── fluorescent_ecs/        # High-performance sparse-set ECS (Float32List)
│   │   ├── fluorescent_flame/      # Flame integration (FluorescentViewport)
│   │   ├── fluorescent_vulkan/     # Vulkan backend (Android/Linux)
│   │   ├── fluorescent_metal/      # Metal backend (iOS/macOS)
│   │   ├── fluorescent_webgpu/     # WebGPU backend (Web)
│   │   └── fluorescent_fluorite/   # Automotive adapter (AAOS/QNX)
│   ├── tools/
│   │   ├── asset_pipeline/         # CLI: .gltf/.wgsl → .fworld binary compiler
│   │   ├── shader_compiler/        # WGSL → SPIR-V/MSL transpiler
│   │   ├── blender_sync/           # Live Blender ↔ Engine sync (WebSocket)
│   │   ├── higgsfield_bridge/      # AI mesh generation API
│   │   └── profiler/               # CPU/GPU/Memory profiling tools
│   ├── examples/
│   │   ├── hybrid_2d_3d/           # 2D + 3D compositing demo
│   │   ├── open_world_demo/        # Streaming open world
│   │   ├── automotive_mirror/      # AAOS rear-view mirror
│   │   └── functional_test_app/    # Community & rally map test app
│   └── docs/
│       └── ENGINE_SPECIFICATION.md # ← Formal engine spec (start here)
│
├── fluorite_core/                  # Rust runtime core
│   ├── src/
│   │   ├── allocator/              # Arena & Frame allocators (zero-fragmentation)
│   │   ├── api/                    # FFI-exported engine API
│   │   └── rendering/              # Render commands & pipeline
│   └── Cargo.toml
│
├── fluorite_editor/                # Flutter desktop editor application
│   ├── lib/
│   └── test/
│
├── PROJECT.md                      # Master project tracker & milestones
├── STRATEGIC_VISION.md             # Architectural philosophy
└── AGENTS.md                       # Multi-agent development roles
```

## 🏗️ Architecture at a Glance

### 10 Engine Subsystems

| # | Subsystem | Description |
|---|-----------|-------------|
| 1 | **Core / ECS** | Archetype-based ECS with contiguous TypedData storage, job system, custom memory allocators |
| 2 | **Rendering** | Data-driven render graph, PBR, Forward+/Deferred, GPU-driven rendering, virtual geometry & textures |
| 3 | **Physics** | Deterministic physics (Jolt/Rapier via FFI), destruction, vehicles, ragdolls |
| 4 | **Animation** | Animation graphs, state machines, blend trees, IK, motion matching, retargeting, facial animation |
| 5 | **Audio** | Spatial audio, procedural audio, environmental effects |
| 6 | **VFX** | GPU particle system (Niagara-class), node-based VFX graphs |
| 7 | **World / Terrain** | World partition, streaming cells, LOD, terrain erosion, procedural generation (PCG) |
| 8 | **AI** | Navigation meshes, behavior trees, utility AI, crowd simulation |
| 9 | **Networking** | Client/server replication, prediction, rollback, interest management, dedicated servers |
| 10 | **Asset Pipeline** | Offline asset processor, `.fworld` binary format, shader transpilation (WGSL → SPIR-V/MSL) |

### 10 Creator Tools (Flutter-based)

| Tool | Purpose |
|------|---------|
| Scene Editor | Place, transform, and configure entities in 3D |
| World Editor | Design streaming worlds with terrain and biomes |
| Material Editor | Visual PBR material authoring |
| Animation Editor | Animation graphs, state machines, blend trees |
| VFX Editor | Node-based GPU particle/VFX system |
| Audio Editor | Spatial audio placement and mixing |
| AI/Behavior Editor | Behavior trees and navigation |
| Visual Scripting | Node-based gameplay logic (compiles to Rust ECS commands) |
| Profiler | CPU/GPU/Memory/Network flame graphs |
| Debugger | Entity inspector, physics visualizer, network debugger |

## 🎮 Hardware Capability Tiers

The same game automatically scales across hardware:

| Tier | Target | Rendering | VFX | Geometry |
|------|--------|-----------|-----|----------|
| **Tier 1** | Mobile | Reduced GI, Forward+ | Simple particles | Lower LOD |
| **Tier 2** | Desktop | Dynamic GI, Deferred | GPU VFX | Adaptive LOD |
| **Tier 3** | High-End | Full GI, Ray Tracing | Advanced VFX | Virtual Geometry |

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.22+
- [Rust](https://www.rust-lang.org/tools/install) 1.70+
- [Melos](https://melos.invertase.dev/) (`dart pub global activate melos`)

### Clone & Setup

```bash
git clone https://github.com/YOUR_USERNAME/Fluorescent.git
cd Fluorescent/fluorescent
melos bootstrap
```

### Run an Example

```bash
cd examples/hybrid_2d_3d
flutter run
```

### Build the Rust Core

```bash
cd fluorite_core
cargo build --release
cargo test
```

### Run the Asset Pipeline

```bash
cd fluorescent/tools/asset_pipeline
dart run bin/asset_pipeline.dart --gltf assets/test.gltf --shader assets/test.wgsl --output out.fworld
```

## 🗺️ Roadmap

| Phase | Focus | Status |
|-------|-------|--------|
| **Phase 1** | Foundation — Rust core, ECS, Flutter integration, Vulkan | 🟡 In Progress |
| **Phase 2** | Engine — Rendering, Physics, Animation, Audio, Assets, Input | ⬜ Planned |
| **Phase 3** | AAA — GPU-driven rendering, GI, VFX, Destruction, World Streaming, PCG | ⬜ Planned |
| **Phase 4** | Online — Replication, Prediction, Rollback, Dedicated Servers | ⬜ Planned |
| **Phase 5** | Ecosystem — Editor, Visual Scripting, Profiler, Marketplace, SDK | ⬜ Planned |
| **Phase 6** | Platform — Hardware tiers, HDR, Upscaling, Dynamic Resolution | ⬜ Planned |

## 📐 Design Principles

1. **Extend, don't replace.** Flame handles 2D/game logic; Fluorescent adds 3D capabilities.
2. **Rust owns the state.** Flutter reads and displays; Rust computes and decides.
3. **Zero-copy everything.** The FFI boundary shares memory, never serializes it.
4. **Data over code.** Game content is described as data files the engine interprets.
5. **The editor is not an afterthought.** It's a first-class Flutter application.
6. **Scale automatically.** One project, every hardware tier, no manual configuration.

## 🧪 Testing

```bash
# Analyze all packages
cd fluorescent && melos run analyze

# Run unit tests across all packages
melos run test

# Run Rust tests
cd fluorite_core && cargo test

# Run E2E integration suite
cd fluorescent && dart test/e2e/e2e_runner_test.dart
```

## 📖 Documentation

| Document | Description |
|----------|-------------|
| [ENGINE_SPECIFICATION.md](fluorescent/docs/ENGINE_SPECIFICATION.md) | **Start here.** Formal engine spec — architecture, philosophy, subsystems, FFI contracts, roadmap |
| [STRATEGIC_VISION.md](STRATEGIC_VISION.md) | High-level vision and strategic differentiators |
| [PROJECT.md](PROJECT.md) | Master project tracker, milestones, interface contracts, code layout |
| [architecture.md](fluorescent/docs/architecture.md) | Original technical scaffold (v0.1.0-alpha) |
| [AGENTS.md](AGENTS.md) | Multi-agent development roles for concurrent implementation |

## 🤝 Contributing

Fluorescent is in active early development. We welcome contributions across all subsystems. Check the [ENGINE_SPECIFICATION.md](fluorescent/docs/ENGINE_SPECIFICATION.md) for the full architectural vision before diving in.

## 📄 License

This project is licensed under the Apache License 2.0 — see [LICENSE](LICENSE) for details.

---

<p align="center">
  <sub>Built with 🔬 by the Fluorescent community</sub>
</p>
