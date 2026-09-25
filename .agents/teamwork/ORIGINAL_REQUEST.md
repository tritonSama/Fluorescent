# Original User Request

## 2026-09-24T17:55:33Z

# Teamwork Project Prompt

> Requested team: Full team (for concurrent multi-agent execution)

Implement Phase 2 (Wave 1) of the Fluorite AAA Engine: PBR & Forward+ Rendering, BVH Spatial Partitioning, Physics Integration, and the Flutter Desktop Editor 3D Viewport.

Working directory: C:\Users\blue-\projects\Fluorescent
Integrity mode: demo

## Requirements

### R1. PBR & Forward+ Renderer (Rust Core)
Implement a PBR metallic-roughness rendering pipeline in `fluorite_core` (or `fluoderpod_render`) with Clustered Forward+ light assignment supporting 1024+ dynamic lights and directional shadow mapping.

### R2. Spatial Partitioning & BVH (Rust Core)
Implement a Bounding Volume Hierarchy (BVH) in Rust for fast CPU/GPU frustum culling, raycasting, and broadphase collision detection.

### R3. Physics Integration (Rust Core)
Integrate `rapier3d` (or Jolt FFI) into `fluorite_core` for rigid body dynamics, colliders, and a Kinematic Character Controller.

### R4. Flutter Editor 3D Viewport & Inspector
Expand `fluorite_editor` with a dockable editor shell, scene outliner, entity inspector, and an active 3D Viewport rendering the Rust scene directly via zero-copy FFI texture handles.

## Acceptance Criteria

### Verification
- [ ] `cargo test` passes in `fluorite_core` verifying PBR shader compilation, BVH raycasting, and Rapier physics stepping.
- [ ] Automated benchmarks demonstrate BVH frustum culling 10,000 entities in <2ms.
- [ ] `fluorite_editor` launches on Desktop with an interactive 3D Viewport rendering a PBR mesh with dynamic shadows and camera controls.
- [ ] E2E integration test verifies zero-copy memory stability during real-time physics simulation and rendering.
