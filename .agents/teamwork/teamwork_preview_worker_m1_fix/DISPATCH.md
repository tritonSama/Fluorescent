# Task Assignment: Milestone 1 Worker (Remediation Iteration)

You are teamwork_preview_worker_m1_fix.
Working directory: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_worker_m1_fix\
Authoritative Request: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\ORIGINAL_REQUEST.md
Project Blueprint: c:\Users\blue-\projects\Fluorescent\PROJECT.md

## MANDATORY INTEGRITY WARNING
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Exclusive Write Ownership
You own and may modify:
- `fluorite_core/src/rendering/cluster.rs`
- `fluorite_core/src/rendering/shaders/pbr_forward.wgsl`
- `fluorite_core/src/rendering/shaders/cluster_cull.wgsl`
- `fluorite_core/tests/pbr_pipeline_test.rs`
- `fluorite_core/tests/adversarial_cluster_stress_test.rs`

## Review Feedback to Remediate
Reviewer 2 and Challenger 1 identified 3 critical host-to-GPU data contract defects in Milestone 1:

1. **`GpuLight` Memory Struct Layout & Enum Mismatch**:
   In `fluorite_core/src/rendering/cluster.rs`:
   Update `GpuLight` definition to:
   ```rust
   #[repr(C)]
   #[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
   pub struct GpuLight {
       pub position_ws: [f32; 3],
       pub radius: f32,
       pub color: [f32; 3],
       pub intensity: f32,
       pub direction_ws: [f32; 3],
       pub light_type: u32, // 0 = Directional, 1 = Point, 2 = Spot
       pub inner_cone_cos: f32,
       pub outer_cone_cos: f32,
       pub shadow_map_index: i32,
       pub _padding: u32,
   }
   ```
   Add compile-time or unit-test assertions:
   - `assert!(std::mem::size_of::<GpuLight>() == 64);`
   - `assert!(core::mem::offset_of!(GpuLight, light_type) == 44);`
   In `bin_lights`:
   - Point lights: set `light_type: 1`, `inner_cone_cos: 1.0`, `outer_cone_cos: 1.0`.
   - Spot lights: set `light_type: 2`, `inner_cone_cos: spot.inner_angle.cos()`, `outer_cone_cos: spot.outer_angle.cos()`.

2. **`ClusterCell` vs `ClusterRecord` Stride Parity**:
   Rust `ClusterCell` is 16 bytes (`offset: u32, count: u32, _pad: [u32; 2]`).
   Update `struct ClusterRecord` in `fluorite_core/src/rendering/shaders/cluster_cull.wgsl` and `pbr_forward.wgsl` to:
   ```wgsl
   struct ClusterRecord {
       offset: u32,
       count: u32,
       _pad: vec2<u32>,
   };
   ```
   Ensuring exact 16-byte stride parity between host Rust and WebGPU storage buffer.

3. **Negative Radius Early Guard**:
   In `bin_lights` in `cluster.rs`:
   Add early-out guard:
   ```rust
   if light.radius <= 0.0 {
       continue;
   }
   ```

4. **Verify Tests**:
   Update `pbr_pipeline_test.rs` and `adversarial_cluster_stress_test.rs` to reflect the updated `GpuLight` struct and run:
   - `cargo check -p fluorite_core`
   - `cargo test -p fluorite_core --test pbr_pipeline_test`
   - `cargo test -p fluorite_core --test adversarial_cluster_stress_test`
   - `cargo test -p fluorite_core`
   - `dart run tests/e2e_runner.dart`

## Deliverable
Write your implementation report to:
`c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_worker_m1_fix\report.md`
and write your handoff to:
`c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_worker_m1_fix\handoff.md`.
Send a completion message back.
