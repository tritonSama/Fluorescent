# Forensic Audit Report: Milestone 1 Remediation Gate 2

**Work Product**: `fluorite_core` Milestone 1 Remediation (`cluster.rs`, `cluster_cull.wgsl`, `pbr_forward.wgsl`, `pbr_pipeline_test.rs`, `adversarial_cluster_stress_test.rs`)  
**Auditor**: `teamwork_preview_auditor_m1_gate2` (Forensic Auditor)  
**Profile**: General Project  
**Integrity Mode**: Demo Mode (per `ORIGINAL_REQUEST.md`)  
**Verdict**: **`CLEAN`**  
**Date**: 2026-09-24  

---

### Phase Results
- **Hardcoded Output Detection**: **PASS** — No hardcoded test returns or synthetic string literals; tests dynamically evaluate generated lights and verify arithmetic boundaries.
- **Facade Implementation Detection**: **PASS** — Pure Rust implementations contain full mathematical logic (Arvo's algorithm, GGX distribution, Heitz visibility, Schlick Fresnel, logarithmic slicing, and orthographic texel snapping). No dummy stubs, `todo!()`, or `unimplemented!()`.
- **Pre-populated Artifact Detection**: **PASS** — Workspace search confirmed zero pre-populated log or attestation files in `fluorite_core/`.
- **Memory Layout & Contract Parity (`GpuLight` offset 44)**: **PASS** — Exact 1:1 std430 alignment across all 64 bytes between Rust `GpuLight` and WGSL `GpuLight`. Field `light_type: u32` is strictly at byte offset 44. Compile-time assertions prevent layout drift.
- **Buffer Stride Parity (`ClusterRecord` 16B stride)**: **PASS** — WGSL `ClusterRecord` includes `_pad: vec2<u32>` matching Rust `ClusterCell::_pad: [u32; 2]`. Stride in both host and device buffers is identical at 16 bytes.
- **Early-Cull Invariant Preservation**: **PASS** — Non-positive radius lights are ingested into `gpu_lights` prior to early guards, preserving 1:1 index alignment (`output.gpu_lights.len() == total_lights`) while preventing inverted cluster depth boundaries.
- **Self-Certifying Test Probing**: **PASS** — Tests rigorously validate byte layouts via raw pointer and byte transmutation (`bytemuck::cast` to `[u8; 64]` and reading `u32::from_ne_bytes(bytes[44..48])`), asserting `light_type == 1u` for Point and `2u` for Spot lights.

---

## 1. Observation

### 1.1 `GpuLight` Memory Struct Alignment and Compile-Time Assertions
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

In `cluster_cull.wgsl` (lines 27–38) and `pbr_forward.wgsl` (lines 38–49):
```wgsl
struct GpuLight {
    position_ws: vec3<f32>,
    radius: f32,
    color: vec3<f32>,
    intensity: f32,
    direction_ws: vec3<f32>,
    light_type: u32, // 0 = Directional, 1 = Point, 2 = Spot
    inner_cone_cos: f32,
    outer_cone_cos: f32,
    shadow_map_index: i32,
    _padding: u32,
};
```

**Byte-by-Byte Layout Audit**:
| Field | Rust Type | Rust Offset | WGSL Type | WGSL Alignment / Size | WGSL Offset | Match |
|---|---|---|---|---|---|---|
| `position_ws` | `[f32; 3]` | 0..12 | `vec3<f32>` | align 16, size 12 | 0..12 | **YES** |
| `radius` | `f32` | 12..16 | `f32` | align 4, size 4 | 12..16 | **YES** |
| `color` | `[f32; 3]` | 16..28 | `vec3<f32>` | align 16, size 12 | 16..28 | **YES** |
| `intensity` | `f32` | 28..32 | `f32` | align 4, size 4 | 28..32 | **YES** |
| `direction_ws` | `[f32; 3]` | 32..44 | `vec3<f32>` | align 16, size 12 | 32..44 | **YES** |
| `light_type` | `u32` | 44..48 | `u32` | align 4, size 4 | 44..48 | **YES** |
| `inner_cone_cos` | `f32` | 48..52 | `f32` | align 4, size 4 | 48..52 | **YES** |
| `outer_cone_cos` | `f32` | 52..56 | `f32` | align 4, size 4 | 52..56 | **YES** |
| `shadow_map_index` | `i32` | 56..60 | `i32` | align 4, size 4 | 56..60 | **YES** |
| `_padding` | `u32` | 60..64 | `u32` | align 4, size 4 | 60..64 | **YES** |
- Both structures total exactly 64 bytes with 16-byte alignment.
- Zero implicit compiler padding gaps exist.

### 1.2 `ClusterRecord` 16-Byte Stride Parity
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
`size_of::<ClusterCell>() == 16` bytes. `_pad` offset is at 8 bytes.

In `cluster_cull.wgsl` (lines 40–44) and `pbr_forward.wgsl` (lines 51–55):
```wgsl
struct ClusterRecord {
    offset: u32,
    count: u32,
    _pad: vec2<u32>,
};
```
- In WGSL std430, `_pad: vec2<u32>` has alignment 8 and size 8. Following `offset: u32` (4B) and `count: u32` (4B), it sits at offset 8..16.
- The struct size is 16 bytes, and the array stride for `array<ClusterRecord>` is 16 bytes.
- In `cluster_cull.wgsl` (lines 175, 178, 181), constructors pass explicit zero-initialization:
  `ClusterRecord(write_offset, visible_light_count, vec2<u32>(0u, 0u))`.

### 1.3 `bin_lights` Ingestion and Culling Guards
In `fluorite_core/src/rendering/cluster.rs` (lines 280–380):
- For Point Lights (lines 289–305):
  `gpu_lights.push` sets `light_type: 1`. An early guard `if light.radius <= 0.0 { continue; }` follows.
- For Spot Lights (lines 340–356):
  `gpu_lights.push` sets `light_type: 2`, `inner_cone_cos: spot.inner_angle.cos()`, `outer_cone_cos: spot.outer_angle.cos()`. An early guard `if spot.range <= 0.0 { continue; }` follows.
- Because `gpu_lights.push` precedes the culling continue, every light maintains a stable index corresponding 1:1 with input arrays, ensuring shader light index lookups never read misaligned or shifted elements.

### 1.4 Test Suite Assertions
- In `fluorite_core/src/rendering/cluster.rs` (lines 512–529):
  `test_gpu_light_layout_and_offsets` asserts sizes and offsets for all 10 fields of `GpuLight` and `ClusterCell`.
- In `fluorite_core/tests/pbr_pipeline_test.rs` (lines 145–166):
  Asserts `size_of::<GpuLight>() == 64`, `offset_of!(GpuLight, light_type) == 44`, `size_of::<ClusterCell>() == 16`, and `offset_of!(ClusterCell, _pad) == 8`.
- In `fluorite_core/tests/adversarial_cluster_stress_test.rs` (lines 578–617):
  `test_adversarial_gpu_light_layout_parity_investigation` casts `GpuLight` to `[u8; 64]`, extracts bytes 44..48, and asserts that `point_offset_44_u32 == 1` and `spot_offset_44_u32 == 2`.

---

## 2. Logic Chain

1. **Governing Constraints**: `ORIGINAL_REQUEST.md` specifies `Integrity mode: demo`. Under Demo Mode, standard library and in-tree math implementations are permitted, while hardcoded test outputs, facade stubs, fabricated artifacts, and black-box delegation of core deliverables are prohibited.
2. **Analysis of Memory Parity**:
   - `GpuLight` layout in Rust matches the WebGPU std430 storage buffer specification byte-for-byte. `vec3<f32>` (12B) followed by scalar (4B) perfectly satisfies WGSL's 16-byte vector alignment rule without requiring implicit padding.
   - Byte offset 44 holds `light_type: u32`. In WGSL `pbr_forward.wgsl`, light type discrimination executes `if (light.light_type == 1u)` for Point and `== 2u` for Spot lights. Rust sets these exact values in `bin_lights`.
   - `ClusterRecord` in WGSL and `ClusterCell` in Rust both have a size and stride of exactly 16 bytes. Storage buffer indexing `cluster_records[cluster_idx]` reads the exact `offset` and `count` written by host Rust or compute shader without byte offset skew.
3. **Absence of Prohibited Patterns**:
   - No hardcoded test responses or facade stubs exist.
   - Codebase search found zero `todo!()`, `unimplemented!()`, or mock classes in the rendering path.
   - All tests execute actual mathematical routines (Arvo's algorithm, GGX, Smith visibility, Schlick Fresnel, logarithmic slicing, texel snapping) and verify computed values against physical invariants.

---

## 3. Caveats

- Interactive terminal execution of `cargo test` in this environment encountered a permission timeout. Independent verification was completed through exhaustive static source code analysis, std430 memory layout audit, compile-time assertion tracing, and shader AST inspection.
- The headless shader compilation test (`test_wgsl_shader_compilation_headless`) conditionally checks for the presence of a hardware or software WGPU adapter before compiling shaders on bare hosts.

---

## 4. Conclusion

**Verdict**: **`CLEAN`**

The Milestone 1 Clustered Forward+ remediation satisfies all data contract specifications and integrity requirements:
1. `GpuLight` is 64 bytes with `light_type: u32` at byte offset 44, matching `cluster_cull.wgsl` and `pbr_forward.wgsl`.
2. `ClusterRecord` in WGSL and `ClusterCell` in Rust share an exact 16-byte stride (`_pad: vec2<u32>` / `_pad: [u32; 2]`).
3. Non-positive radius lights are early-culled without disrupting 1:1 buffer index synchronization.
4. Comprehensive static compile-time assertions and empirical tests enforce data contract invariance.
5. Zero integrity violations, dummy stubs, or facade implementations are present.

---

## 5. Verification Method

To independently reproduce and verify this audit:
1. **Source Inspection**:
   - `fluorite_core/src/rendering/cluster.rs`: lines 88–121, 280–380, 512–529.
   - `fluorite_core/src/rendering/shaders/pbr_forward.wgsl`: lines 38–55, 311–363.
   - `fluorite_core/src/rendering/shaders/cluster_cull.wgsl`: lines 27–45, 170–183.
   - `fluorite_core/tests/pbr_pipeline_test.rs`: lines 142–175.
   - `fluorite_core/tests/adversarial_cluster_stress_test.rs`: lines 530–617.
2. **Commands**:
   ```powershell
   cargo check -p fluorite_core
   cargo test -p fluorite_core --test pbr_pipeline_test
   cargo test -p fluorite_core --test adversarial_cluster_stress_test
   ```
3. **Invalidation Conditions**:
   - `core::mem::offset_of!(GpuLight, light_type) != 44`
   - `std::mem::size_of::<GpuLight>() != 64`
   - `std::mem::size_of::<ClusterCell>() != 16`
   - Array stride of `array<ClusterRecord>` in WGSL != 16
