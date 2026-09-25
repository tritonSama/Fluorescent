# Orchestration Plan — Fluorite AAA Engine Phase 2 (Wave 1)

## Phase 0: Survey & Discovery (Current Phase)
Objective: Map out the existing repository, packages, dependencies, and architecture to establish ground truth.
- **Explorer 1 (Rendering)**: Map `fluorite_core`, `fluoderpod_render`, and graphics packages. Identify existing render graph, wgpu/Vulkan backend, PBR metallic-roughness setup, clustered forward+ lighting infrastructure, and shadow mapping approach.
- **Explorer 2 (Spatial & Physics)**: Map spatial data structures and math in `fluorite_core`. Identify BVH requirements, bounding boxes (AABB), SIMD/frustum culling, raycasting queries, and Rapier3D integration points (rigid bodies, colliders, character controller).
- **Explorer 3 (Editor & Zero-Copy FFI)**: Map `fluorite_editor`, `fluorescent_flame`, and FFI bindings. Identify texture sharing mechanisms, Flutter Texture widget integration, dockable panels, scene outliner, and inspector.

## Phase 1: Architecture & Decomposition (PROJECT.md)
- Synthesize explorer survey reports.
- Enumerate every required feature into `PROJECT.md § Feature Inventory`.
- Define Milestones:
  - M1: PBR Metallic-Roughness & Clustered Forward+ Renderer (1024+ lights, shadow mapping).
  - M2: Bounding Volume Hierarchy (BVH) & Frustum Culling (<2ms for 10k entities).
  - M3: Rapier3D Physics Integration (Rigid bodies, colliders, character controller).
  - M4: Flutter Editor 3D Viewport, Dockable Shell, Scene Outliner, Entity Inspector.
  - M5: E2E Integration, Benchmarks, and Zero-Copy Texture Pipeline verification.
- Establish strict Interface Contracts and Code Layout.

## Phase 2: Dual Track Execution
- **Track A (Implementation Track)**: Execute Milestones sequentially/interleaved with full iteration cycle:
  - 3 Explorers per milestone
  - 1 Worker (armed with strict domain expertise and integrity warning)
  - 2 Reviewers (code quality, interface compliance, tests)
  - 2 Challengers (adversarial test harnesses, benchmarks, edge cases)
  - 1 Forensic Auditor (binary veto against cheating, stubbing, or mock passes)
  - Gate check (strict AND condition)
- **Track B (E2E Testing Track)**:
  - Design comprehensive opaque-box test suites across Tiers 1-4.
  - Publish `TEST_READY.md`.

## Phase 3: Final Acceptance & Reporting
- Verify all acceptance criteria:
  - `cargo test` in `fluorite_core` passes (PBR, BVH, Rapier).
  - Automated benchmark: BVH frustum culls 10,000 entities in <2ms.
  - `fluorite_editor` launches with active interactive 3D Viewport.
  - E2E zero-copy stability verified.
- Deliver comprehensive handoff to Sentinel.
