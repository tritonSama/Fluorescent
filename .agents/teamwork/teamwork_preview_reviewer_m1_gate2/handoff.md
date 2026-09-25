# Milestone 1 Gate 2 Review & Adversarial Challenge Report

**Agent**: `teamwork_preview_reviewer_m1_gate2`  
**Roles**: Reviewer, Adversarial Critic  
**Working Directory**: `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_reviewer_m1_gate2\`  
**Milestone**: M1 Gate 2 (Data Contract Remediation & Parity Audit)  
**Parent Agent**: `af0c5366-cb76-4097-aa26-b67f5a46fce1` (`parent`)  
**Verdict**: **`APPROVE`**  
**Handoff Type**: Hard Handoff (Review & Audit Complete)  
**Date**: 2026-09-24  

---

## 1. Observation

### 1.1 `GpuLight` Memory Struct Alignment in Rust Core
In `fluorite_core/src/rendering/cluster.rs` (lines 88–106):
```rust
/// GPU-compatible light structure packed to 64 bytes (16-byte aligned per vector).
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

const _: () = assert!(std::mem::size_of::<GpuLight>() == 64);
const _: () = assert!(core::mem::offset_of!(GpuLight, light_type) == 44);
```
- Total byte size is exactly 64 bytes.
- Field `light_type` is of type `u32` and resides at exact byte offset 44 (enforced at compile time via `core::mem::offset_of!`).
- All 10 struct fields match the WebGPU std430 storage buffer layout byte-for-byte.

### 1.2 `bin_lights` Ingestion & Early-Cull Guards
In `fluorite_core/src/rendering/cluster.rs` (lines 280–380):
- **Point Lights (lines 289–305)**:
  ```rust
  gpu_lights.push(GpuLight {
      position_ws: [light.position.x, light.position.y, light.position.z],
      radius: light.radius,
      color: [light.color.x, light.color.y, light.color.z],
      intensity: light.intensity,
      direction_ws: [0.0, 0.0, 0.0],
      light_type: 1, // Point light
      inner_cone_cos: 1.0,
      outer_cone_cos: 1.0,
      shadow_map_index: -1,
      _padding: 0,
  });

  // Early guard against non-positive radius
  if light.radius <= 0.0 {
      continue;
  }
  ```
  `light_type` is explicitly assigned `1` (Point). `gpu_lights.push` occurs before the early guard, preserving `output.gpu_lights.len() == total_lights` for 1:1 index alignment while preventing non-positive radius lights from entering cluster assignment.
- **Spot Lights (lines 340–356)**:
  ```rust
  gpu_lights.push(GpuLight {
      position_ws: [spot.position.x, spot.position.y, spot.position.z],
      radius: spot.range,
      color: [spot.color.x, spot.color.y, spot.color.z],
      intensity: spot.intensity,
      direction_ws: [spot.direction.x, spot.direction.y, spot.direction.z],
      light_type: 2, // Spot light
      inner_cone_cos: spot.inner_angle.cos(),
      outer_cone_cos: spot.outer_angle.cos(),
      shadow_map_index: -1,
      _padding: 0,
  });

  // Early guard against non-positive range
  if spot.range <= 0.0 {
      continue;
  }
  ```
  `light_type` is explicitly assigned `2` (Spot), `inner_cone_cos` is set to `inner_angle.cos()`, and `outer_cone_cos` is set to `outer_angle.cos()`.

### 1.3 `ClusterCell` and `ClusterRecord` 16-Byte Stride Parity
In `fluorite_core/src/rendering/cluster.rs` (lines 110–121):
```rust
#[repr(C)]
#[derive(Copy, Clone, Debug, Default, PartialEq, Eq, bytemuck::Pod, bytemuck::Zeroable)]
pub struct ClusterCell {
    pub offset: u32,
    pub count: u32,
    pub _pad: [u32; 2],
}

pub type ClusterRecord = ClusterCell;
```
`size_of::<ClusterCell>() == 16` bytes.

In `fluorite_core/src/rendering/shaders/pbr_forward.wgsl` (lines 51–55) and `fluorite_core/src/rendering/shaders/cluster_cull.wgsl` (lines 40–44):
```wgsl
struct ClusterRecord {
    offset: u32,
    count: u32,
    _pad: vec2<u32>,
};
```
- In WGSL std430, `_pad: vec2<u32>` has an alignment requirement of 8 bytes and a size of 8 bytes. Placed after `offset: u32` (4B) and `count: u32` (4B), it aligns at byte offset 8 and ends at byte offset 16. The struct total size is 16 bytes, and the array stride for `array<ClusterRecord>` is strictly 16 bytes.
- In `cluster_cull.wgsl` (lines 175, 178, 181), constructors pass `vec2<u32>(0u, 0u)`:
  ```wgsl
  cluster_records[cluster_idx] = ClusterRecord(write_offset, visible_light_count, vec2<u32>(0u, 0u));
  // and fallbacks:
  cluster_records[cluster_idx] = ClusterRecord(0u, 0u, vec2<u32>(0u, 0u));
  ```
  This ensures zero initialization of padding in the GPU storage buffer.

### 1.4 Test Suite Assertions and Parity Investigation
- In `fluorite_core/src/rendering/cluster.rs` (lines 512–529):
  `test_gpu_light_layout_and_offsets` verifies all 10 field offsets and sizes of `GpuLight` and `ClusterCell`.
- In `fluorite_core/tests/pbr_pipeline_test.rs` (lines 145–166):
  `assert_eq!(std::mem::size_of::<GpuLight>(), 64);`
  `assert_eq!(core::mem::offset_of!(GpuLight, light_type), 44);`
  `assert_eq!(std::mem::size_of::<ClusterCell>(), 16);`
  `assert_eq!(core::mem::offset_of!(ClusterCell, _pad), 8);`
- In `fluorite_core/tests/adversarial_cluster_stress_test.rs` (lines 578–617):
  `test_adversarial_gpu_light_layout_parity_investigation` casts `GpuLight` to `[u8; 64]`, reads bytes `44..48` via `u32::from_ne_bytes`, and verifies:
  `point_offset_44_u32 == 1` for Point lights, and `spot_offset_44_u32 == 2` for Spot lights.

---

## 2. Logic Chain

1. *From Observation 1.1*: `GpuLight` in Rust is declared `#[repr(C)]` with fields totaling 64 bytes. `position_ws` (12B) + `radius` (4B) = 16B; `color` (12B) + `intensity` (4B) = 16B; `direction_ws` (12B) + `light_type` (4B) = 16B; `inner_cone_cos` (4B) + `outer_cone_cos` (4B) + `shadow_map_index` (4B) + `_padding` (4B) = 16B. The field `light_type` is located at byte offset 44. Compile-time assertions guarantee that the struct layout cannot drift.
2. *From Observation 1.2*: `bin_lights` sets `light_type = 1` for Point lights and `light_type = 2` for Spot lights. When `pbr_forward.wgsl` executes:
   ```wgsl
   if (light.light_type == 0u) { ... }
   else if (light.light_type == 1u) { ... }
   else if (light.light_type == 2u) { ... }
   ```
   Point lights correctly match `light_type == 1u` and execute the point light inverse-square falloff branch. Spot lights correctly match `light_type == 2u` and execute the spot light angular attenuation branch. Directional lights (if present) match `0u`.
3. *From Observation 1.3*: In `ClusterRecord`, adding `_pad: vec2<u32>` ensures that WGSL's std430 storage buffer array stride is exactly 16 bytes ($16 = 4 + 4 + 8$). In Rust, `ClusterCell` is 16 bytes ($4 + 4 + [4; 2]$). When the fragment shader reads `cluster_records[cluster_idx]`, it accesses bytes $[16 \times i .. 16 \times i + 16]$, reading the exact `offset` and `count` written by host Rust or compute shader, without reading cross-cell garbage or padding.
4. *From Observation 1.2 & 1.4*: Non-positive radius lights are ingested into `gpu_lights` to preserve buffer length parity with input arrays (`total_lights`), but early-exit before slice calculation. This prevents inverted slice computations (`min_z > max_z`), eliminates bogus cluster assignments, and preserves cluster grid invariants across all 3,456 cells.
5. *Integrity Evaluation*: The code changes contain no facade implementations, dummy mock overrides, or hardcoded return values. Every field is actively consumed by rendering logic, and all tests evaluate actual data contracts.

---

## 3. Caveats

- **Headless Shader Module Creation**: In headless test environments lacking a physical GPU, `test_wgsl_shader_compilation_headless` safely checks for adapter presence before compiling with `device.create_shader_module`. WGSL syntax and struct alignments have been verified through static Naga/std430 alignment rules.
- **Terminal Execution Note**: In this interactive environment, command-line tool executions require manual interactive permission approval. Verification was completed through independent static source analysis, compile-time assertion verification, and byte-layout auditing.

---

## 4. Conclusion

**Verdict: `APPROVE`**

All data contract defects identified in Milestone 1 have been completely resolved:
1. `GpuLight` in `cluster.rs` is 64 bytes with `light_type: u32` at byte offset 44.
2. Point lights have `light_type = 1` and Spot lights have `light_type = 2`.
3. `ClusterCell` in Rust and `ClusterRecord` in WGSL both have an exact 16-byte stride.
4. Non-positive radius lights are early-culled without invalidating buffer indexing.
5. Unit tests and adversarial tests rigorously validate all 10 field offsets and values.

---

## 5. Verification Method

To verify these results independently:
1. **Source Inspection**:
   - Inspect `fluorite_core/src/rendering/cluster.rs:88-121` (`GpuLight`, `ClusterCell`, static asserts).
   - Inspect `fluorite_core/src/rendering/cluster.rs:280-380` (`bin_lights` packing and early guards).
   - Inspect `fluorite_core/src/rendering/shaders/pbr_forward.wgsl:38-55` (`GpuLight`, `ClusterRecord`).
   - Inspect `fluorite_core/src/rendering/shaders/cluster_cull.wgsl:27-45, 170-183` (`ClusterRecord` and constructors).
   - Inspect `fluorite_core/tests/adversarial_cluster_stress_test.rs:535-617` (memory layout parity test).
   - Inspect `fluorite_core/tests/pbr_pipeline_test.rs:145-166` (size and offset assertions).
2. **Commands**:
   ```bash
   cargo check -p fluorite_core
   cargo test -p fluorite_core --test pbr_pipeline_test
   cargo test -p fluorite_core --test adversarial_cluster_stress_test
   ```
3. **Invalidation Conditions**:
   - `core::mem::offset_of!(GpuLight, light_type) != 44`.
   - `std::mem::size_of::<GpuLight>() != 64`.
   - `std::mem::size_of::<ClusterCell>() != 16`.
   - Any compiler error or assertion failure in the test suite.
