# Milestone 1 Remediation Report: Host-to-GPU Data Contract & Cluster Parity

**Author**: `teamwork_preview_worker_m1_fix`  
**Working Directory**: `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_worker_m1_fix\`  
**Date**: 2026-09-25  

---

## Executive Summary

This remediation sprint addressed the 3 critical host-to-GPU data contract defects identified by Reviewer 2 and Challenger 1 in Milestone 1:
1. **`GpuLight` Layout and Enum Mismatch**: Aligning the Rust host struct `GpuLight` with WebGPU std430 storage buffer specifications in `pbr_forward.wgsl` and `cluster_cull.wgsl`.
2. **`ClusterRecord` 16-byte Stride Parity**: Aligning the WGSL `ClusterRecord` struct with Rust's 16-byte `ClusterCell` (`offset: u32, count: u32, _pad: [u32; 2]`) by introducing `_pad: vec2<u32>`.
3. **Negative Radius Early Guard**: Introducing early-culling guards in `bin_lights` to prevent inverted slice bounds and extraneous cluster tests for lights with `radius <= 0.0` or `range <= 0.0`.
4. **Adversarial & Pipeline Verification**: Updating and expanding unit tests in `cluster.rs`, `pbr_pipeline_test.rs`, and `adversarial_cluster_stress_test.rs` to assert compile-time byte offsets, 64-byte struct sizing, 16-byte cluster strides, and exact `light_type` values (`1u` for Point, `2u` for Spot).

---

## Detailed Remediation Actions

### 1. `GpuLight` Memory Struct Alignment (`fluorite_core/src/rendering/cluster.rs`)

**Issue**: The previous `GpuLight` implementation packed parameters into four `[f32; 4]` vectors (`position_range`, `color_intensity`, `direction_inner`, `params`). In that layout, byte offset 44 held `direction_inner[3] = 1.0f32` (which reinterpreted as `u32` equals `0x3F800000 = 1,065,353,216`), whereas the WGSL shader expected `light_type: u32` (`0 = Directional, 1 = Point, 2 = Spot`) at byte offset 44.

**Remediation**:
Replaced the definition in `fluorite_core/src/rendering/cluster.rs` with:
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

const _: () = assert!(std::mem::size_of::<GpuLight>() == 64);
const _: () = assert!(core::mem::offset_of!(GpuLight, light_type) == 44);
```

**Byte Offset Audit Table**:
| Field | Type | Rust Offset | WGSL Offset | Bytes | Description |
|---|---|---|---|---|---|
| `position_ws` | `[f32; 3]` / `vec3<f32>` | 0..12 | 0..12 | 12 | World-space coordinates |
| `radius` | `f32` | 12..16 | 12..16 | 4 | Attenuation radius / range |
| `color` | `[f32; 3]` / `vec3<f32>` | 16..28 | 16..28 | 12 | Linear RGB light color |
| `intensity` | `f32` | 28..32 | 28..32 | 4 | Radiant intensity (lm / cd) |
| `direction_ws` | `[f32; 3]` / `vec3<f32>` | 32..44 | 32..44 | 12 | Unit light direction vector |
| `light_type` | `u32` | 44..48 | 44..48 | 4 | 0 = Directional, 1 = Point, 2 = Spot |
| `inner_cone_cos` | `f32` | 48..52 | 48..52 | 4 | Cosine of spot inner angle |
| `outer_cone_cos` | `f32` | 52..56 | 52..56 | 4 | Cosine of spot outer angle |
| `shadow_map_index`| `i32` | 56..60 | 56..60 | 4 | Index into shadow atlas (-1 = none)|
| `_padding` | `u32` | 60..64 | 60..64 | 4 | 16-byte alignment tail padding |

### 2. `bin_lights` Ingestion & Early Guard Updates (`cluster.rs`)

**Remediation**:
- Point lights:
  - `gpu_lights.push` writes `light_type: 1`, `inner_cone_cos: 1.0`, `outer_cone_cos: 1.0`, `shadow_map_index: -1`, `_padding: 0`.
  - Added early guard: `if light.radius <= 0.0 { continue; }`.
- Spot lights:
  - `gpu_lights.push` writes `light_type: 2`, `inner_cone_cos: spot.inner_angle.cos()`, `outer_cone_cos: spot.outer_angle.cos()`, `shadow_map_index: -1`, `_padding: 0`.
  - Added early guard: `if spot.range <= 0.0 { continue; }`.
- Ingestion order: `gpu_lights.push` occurs before the culling guard to ensure that every input light is assigned a stable index in the GPU lights buffer, maintaining strict 1:1 parity between input light indices and `gpu_lights` entries as required by the engine's test invariants (`output.gpu_lights.len() == total_lights`).

### 3. WGSL `ClusterRecord` 16-byte Stride Parity

**Files Modified**:
- `fluorite_core/src/rendering/shaders/pbr_forward.wgsl`
- `fluorite_core/src/rendering/shaders/cluster_cull.wgsl`

**Remediation**:
Updated WGSL struct definition from:
```wgsl
struct ClusterRecord {
    offset: u32,
    count: u32,
};
```
to:
```wgsl
struct ClusterRecord {
    offset: u32,
    count: u32,
    _pad: vec2<u32>,
};
```
And updated constructor invocations in `cluster_cull.wgsl`:
```wgsl
cluster_records[cluster_idx] = ClusterRecord(write_offset, visible_light_count, vec2<u32>(0u, 0u));
// and fallback:
cluster_records[cluster_idx] = ClusterRecord(0u, 0u, vec2<u32>(0u, 0u));
```
**Layout Verification**:
- WGSL `ClusterRecord`: `offset` (4B) + `count` (4B) + `_pad` (`vec2<u32>`, 8B, aligned to 8) = 16 bytes total.
- Rust `ClusterCell`: `offset` (`u32`, 4B) + `count` (`u32`, 4B) + `_pad` (`[u32; 2]`, 8B) = 16 bytes total.
- Storage buffer indexing between Rust host uploads and GPU shader reads is now identically 16 bytes per cell.

### 4. Test Suite Harmonization

**Files Modified**:
- `fluorite_core/src/rendering/cluster.rs`: Added `test_gpu_light_layout_and_offsets` verifying all 10 field offsets and sizes at runtime.
- `fluorite_core/tests/pbr_pipeline_test.rs`: Added `core::mem::offset_of!` assertions for `GpuLight::light_type == 44` and `ClusterCell::_pad == 8`.
- `fluorite_core/tests/adversarial_cluster_stress_test.rs`: Updated `test_adversarial_gpu_light_layout_parity_investigation` to assert that byte offset 44 contains `1u` for Point lights and `2u` for Spot lights, verifying exact layout match across all fields.

---

## File Modification Summary

| File | Status | Modifications |
|---|---|---|
| `fluorite_core/src/rendering/cluster.rs` | Modified | Updated `GpuLight` struct, static compile assertions, `bin_lights` packing & culling guards, added `test_gpu_light_layout_and_offsets`. |
| `fluorite_core/src/rendering/shaders/pbr_forward.wgsl` | Modified | Added `_pad: vec2<u32>` to `ClusterRecord` (16 bytes). |
| `fluorite_core/src/rendering/shaders/cluster_cull.wgsl` | Modified | Added `_pad: vec2<u32>` to `ClusterRecord` and updated `ClusterRecord(...)` constructors. |
| `fluorite_core/tests/pbr_pipeline_test.rs` | Modified | Added `offset_of!` assertions for `GpuLight::light_type` and `ClusterCell::_pad`. |
| `fluorite_core/tests/adversarial_cluster_stress_test.rs` | Modified | Updated parity investigation test with strict assertions on byte offsets and `light_type` values. |

---

## Verification Strategy & Invariants

1. **Host-to-GPU Contract Integrity**:
   - `std::mem::size_of::<GpuLight>() == 64` (enforced at compile time via `const _: () = assert!(...);`).
   - `core::mem::offset_of!(GpuLight, light_type) == 44` (enforced at compile time).
   - `std::mem::size_of::<ClusterCell>() == 16`.
   - `core::mem::offset_of!(ClusterCell, _pad) == 8`.

2. **Cluster Grid Invariants**:
   - All 3,456 cluster cells maintain `offset + count <= light_indices.len()`.
   - Zero-radius and negative-radius lights are safely culled without panic or boundary inversion.
   - Lights with `radius > 0.0` retain accurate Arvo sphere-AABB intersection binning.
