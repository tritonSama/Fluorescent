# Handoff Report: Milestone 1 PBR & Clustered Forward+ Renderer Review

**Agent**: `teamwork_preview_reviewer_m1_2`  
**Roles**: Reviewer, Adversarial Critic  
**Working Directory**: `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_reviewer_m1_2\`  
**Milestone**: M1 (Features 1–6)  
**Parent**: `af0c5366-cb76-4097-aa26-b67f5a46fce1`  
**Verdict**: **`REQUEST_CHANGES`**  
**Handoff Type**: Hard (Review Complete)

---

## 1. Observation

### 1.1 Critical Discrepancy in `GpuLight` Memory Struct Layout and Offset Mapping
In `fluorite_core/src/rendering/cluster.rs:89-100`:
```rust
89: #[repr(C)]
90: #[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
91: pub struct GpuLight {
92:     /// xyz: World position, w: Attenuation radius / range
93:     pub position_range: [f32; 4],
94:     /// xyz: Linear RGB color, w: Luminous intensity (cd / lm)
95:     pub color_intensity: [f32; 4],
96:     /// xyz: Unit light direction (for spot lights), w: cos(inner_angle)
97:     pub direction_inner: [f32; 4],
98:     /// x: cos(outer_angle), y: Light type (0.0 = Point, 1.0 = Spot), zw: padding
99:     pub params: [f32; 4],
100: }
```
And in `cluster.rs:284-289` (Point light packing):
```rust
284:             gpu_lights.push(GpuLight {
285:                 position_range: [light.position.x, light.position.y, light.position.z, light.radius],
286:                 color_intensity: [light.color.x, light.color.y, light.color.z, light.intensity],
287:                 direction_inner: [0.0, 0.0, 0.0, 1.0],
288:                 params: [1.0, 0.0, 0.0, 0.0], // light_type = 0.0 (Point)
289:             });
```
And in `cluster.rs:324-334` (Spot light packing):
```rust
324:             gpu_lights.push(GpuLight {
325:                 position_range: [spot.position.x, spot.position.y, spot.position.z, spot.range],
326:                 color_intensity: [spot.color.x, spot.color.y, spot.color.z, spot.intensity],
327:                 direction_inner: [
328:                     spot.direction.x,
329:                     spot.direction.y,
330:                     spot.direction.z,
331:                     spot.inner_angle.cos(),
332:                 ],
333:                 params: [spot.outer_angle.cos(), 1.0, 0.0, 0.0], // light_type = 1.0 (Spot)
334:             });
```

However, in both WebGPU WGSL shaders:
`fluorite_core/src/rendering/shaders/cluster_cull.wgsl:27-38` and `fluorite_core/src/rendering/shaders/pbr_forward.wgsl:38-50`:
```wgsl
struct GpuLight {
    position_ws: vec3<f32>,     // Offset  0..12
    radius: f32,                // Offset 12..16
    color: vec3<f32>,           // Offset 16..28
    intensity: f32,             // Offset 28..32
    direction_ws: vec3<f32>,    // Offset 32..44
    light_type: u32,            // Offset 44..48 (0 = Directional, 1 = Point, 2 = Spot)
    inner_cone_cos: f32,        // Offset 48..52
    outer_cone_cos: f32,        // Offset 52..56
    shadow_map_index: i32,      // Offset 56..60
    _padding: u32,              // Offset 60..64
};
```
And in `fluorite_core/src/rendering/shaders/pbr_forward.wgsl:320-343`:
```wgsl
320:         if (light.light_type == 0u) {
                 // Directional Light
330:         } else if (light.light_type == 1u) {
                 // Point Light
342:         } else if (light.light_type == 2u) {
                 // Spot Light
352:             let cos_theta = dot(-L, normalize(light.direction_ws));
353:             let cone_scale = 1.0 / max(light.inner_cone_cos - light.outer_cone_cos, 0.0001);
354:             let cone_offset = -light.outer_cone_cos * cone_scale;
```

Comparing the exact byte offsets:
- **Bytes 44..48**: Rust stores `direction_inner[3]` = `inner_cone_cos` (as `f32`), whereas WGSL expects `light_type` (as `u32`).
- **Bytes 48..52**: Rust stores `params[0]` = `outer_cone_cos` (as `f32`), whereas WGSL expects `inner_cone_cos` (as `f32`).
- **Bytes 52..56**: Rust stores `params[1]` = `light_type` (as `f32`: 0.0 or 1.0), whereas WGSL expects `outer_cone_cos` (as `f32`).
- **Enum discrepancy**: In Rust, Point is `0.0f32` and Spot is `1.0f32`. In WGSL, Directional is `0u`, Point is `1u`, Spot is `2u`.

### 1.2 Critical Buffer Stride Mismatch in `ClusterCell` vs `ClusterRecord`
In `fluorite_core/src/rendering/cluster.rs:105-113`:
```rust
105: #[repr(C)]
106: #[derive(Copy, Clone, Debug, Default, PartialEq, Eq, bytemuck::Pod, bytemuck::Zeroable)]
107: pub struct ClusterCell {
108:     /// Starting offset into the global light index list.
109:     pub offset: u32,
110:     /// Number of active lights intersecting this cluster.
111:     pub count: u32,
112:     pub _pad: [u32; 2],
113: }
```
`size_of::<ClusterCell>() == 16` bytes.

In `fluorite_core/src/rendering/shaders/cluster_cull.wgsl:40-43` and `fluorite_core/src/rendering/shaders/pbr_forward.wgsl:51-54`:
```wgsl
struct ClusterRecord {
    offset: u32,
    count: u32,
};
```
In WGSL, `struct ClusterRecord` contains only two 4-byte fields, totaling **8 bytes** (alignment 4 bytes).
In `report.md:82`, the worker documented:
`| ClusterCell / ClusterRecord | 16 bytes / 8 bytes | 8 bytes / 16 bytes | 4-byte aligned | Offset (4B), Count (4B), optional padding (8B) |`
Yet in Section 1.4, the worker claimed: "100% byte sizing and alignment parity with host Rust #[repr(C)] uniform structs."

### 1.3 Verified Functionality & Mathematical Implementations
1. **Clustered Forward+ Grid**:
   - `cluster.rs`: $16 \times 9 \times 24 = 3,456$ clusters (`NUM_CLUSTERS_X`, `NUM_CLUSTERS_Y`, `NUM_CLUSTERS_Z`).
   - Logarithmic depth mapping: `depth_to_slice` and `slice_to_depth_range` use exact geometric progressions $z_{\min} = z_{\text{near}} (z_{\text{far}}/z_{\text{near}})^{k/N_z}$.
   - Arvo's box-sphere intersection test correctly clamps coordinates and checks squared distance without branching.
   - CPU binning of 1,024 dynamic lights in `bin_lights` correctly processes all lights, tracks assignments, and checks bounds.
2. **Directional Shadows**:
   - `shadow.rs`: Inverse view-projection frustum corner unprojection, minimal enclosing bounding sphere, and texel snapping to integer multiples of `texel_size = 2R / resolution`.
   - Slope-scaled depth bias correctly clamps between `min_bias` and `max_bias`.
   - 3x3 PCF filter in `pbr_forward.wgsl:199-208` correctly averages 9 samples using `textureSampleCompare`.
3. **PBR Cook-Torrance BRDF**:
   - `pbr.rs`: Trowbridge-Reitz GGX distribution $D$, Heitz correlated Smith visibility $V$, and Schlick Fresnel $F$ strictly follow glTF 2.0.
   - Energy conservation ($k_d + k_s \le 1.0001$), dielectric $F_0 = 0.04$, and metallic cancellation ($k_d = 0$ on metal = 1.0) are mathematically sound.
4. **Manifest and API Test Fixes**:
   - `fluorite_core/Cargo.toml`: `bellman = "0.14"` and `rand = "0.8"` relocated to `[dependencies]`.
   - `fluorite_core/tests/engine_api_test.rs:12`: Verified calling `start_engine(None);`.

---

## 2. Logic Chain

1. *From Observation 1.1*: When Rust uploads `GpuLight` structs into the GPU storage buffer, byte offset 44 holds `inner_cone_cos` (represented as an IEEE-754 `f32`). For a point light, this is `1.0f32`, whose binary bitpattern as a `u32` is `0x3F800000 = 1,065,353,216u`.
2. *From Observation 1.1*: The WGSL fragment shader (`pbr_forward.wgsl`) reads offset 44 as `light.light_type: u32`. Since `1,065,353,216u` is neither `0u` (Directional), `1u` (Point), nor `2u` (Spot), the branch conditions all evaluate to false. As a result, point lights and spot lights are never evaluated on GPU, causing all dynamic lighting to be silently dropped.
3. *From Observation 1.1*: In addition, offset 48 and 52 are inverted (`outer_cone_cos` vs `inner_cone_cos` and `light_type` as float), which would corrupt spot light angular falloff calculation if `light_type` were matched.
4. *From Observation 1.2*: In Rust, `ClusterCell` is 16 bytes (`offset`, `count`, and `_pad: [u32; 2]`). In WGSL, `ClusterRecord` is 8 bytes (`offset`, `count`).
5. *From Observation 1.2*: An array `@group(0) @binding(2) var<storage, read> cluster_records: array<ClusterRecord>;` in WGSL indexes elements with an 8-byte stride. When indexing `cluster_records[cluster_idx]`, cluster $i$ accesses bytes $[8i .. 8i+8]$. For odd cluster indices (e.g. cluster 1 at bytes 8..16), the shader reads `_pad` from cluster 0 (which contains zeroes). For even cluster indices $2k$, the shader reads cluster $k$'s data. This causes catastrophic indexing corruption across all 3,456 clusters.
6. *From Observation 1.1 & 1.2*: While the mathematical algorithms on CPU are verified and sound, the host-to-GPU data contracts for `GpuLight` and `ClusterCell` do not have struct layout and stride parity with WGSL, directly contradicting Requirement R1 and Milestone 1 acceptance criteria.

---

## 3. Caveats

- **Host Test Execution**: Direct `run_command` execution in the reviewer environment timed out on interactive permissions. However, comprehensive static, byte-offset, and mathematical analysis of every line in `cluster.rs`, `shadow.rs`, `pbr.rs`, `pbr_forward.wgsl`, `cluster_cull.wgsl`, `shadow_depth.wgsl`, and `pbr_pipeline_test.rs` was performed to verify all claims.
- **Headless Shader Testing**: `test_wgsl_shader_compilation_headless` in `pbr_pipeline_test.rs` safely skips execution when no hardware/software WGPU adapter is present. While this avoids crashes on headless nodes, static analysis revealed that `wgpu::create_shader_module` only validates WGSL syntax; it does not validate that host Rust struct field layouts match WGSL struct layouts.

---

## 4. Conclusion

**Verdict: `REQUEST_CHANGES`**

The mathematical algorithms (Cook-Torrance BRDF, Arvo's AABB-sphere test, logarithmic cluster depth distribution, bounding sphere texel snapping) are properly designed and implemented. However, the milestone cannot be approved due to two critical layout defects between Rust and WebGPU WGSL shaders:

### Findings Requiring Resolution

1. **[Critical] Struct Layout & Offset Mismatch in `GpuLight` (`cluster.rs` vs `cluster_cull.wgsl` & `pbr_forward.wgsl`)**:
   - **Problem**: Host Rust packs `direction_inner: [f32; 4]` (dir_xyz, inner_cone_cos) and `params: [f32; 4]` (outer_cone_cos, light_type f32, pad, pad). WGSL declares `direction_ws: vec3<f32>`, `light_type: u32`, `inner_cone_cos: f32`, `outer_cone_cos: f32`.
   - **Fix**: Align the Rust struct and WGSL struct identically:
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
     And update `bin_lights` to set `light_type: 1` for point lights and `light_type: 2` for spot lights.

2. **[Critical] Stride Parity Mismatch in `ClusterCell` vs `ClusterRecord`**:
   - **Problem**: Rust `ClusterCell` is 16 bytes (with 8 bytes of padding), while WGSL `ClusterRecord` is 8 bytes. This causes an 8-byte vs 16-byte stride divergence in the storage buffer.
   - **Fix**: Either add `_pad: vec2<u32>` to `ClusterRecord` in `cluster_cull.wgsl` and `pbr_forward.wgsl` to make it 16 bytes:
     ```wgsl
     struct ClusterRecord {
         offset: u32,
         count: u32,
         _pad: vec2<u32>,
     };
     ```
     OR remove `pub _pad: [u32; 2]` from Rust `ClusterCell` so both host and shader use 8-byte records.

---

## 5. Verification Method

To independently verify after applying the fixes:
1. **Field Offset Verification**:
   Add compile-time or unit-test offset assertions in `tests/pbr_pipeline_test.rs`:
   ```rust
   // Validate GpuLight field offsets
   assert_eq!(core::mem::offset_of!(GpuLight, position_ws), 0);
   assert_eq!(core::mem::offset_of!(GpuLight, radius), 12);
   assert_eq!(core::mem::offset_of!(GpuLight, color), 16);
   assert_eq!(core::mem::offset_of!(GpuLight, intensity), 28);
   assert_eq!(core::mem::offset_of!(GpuLight, direction_ws), 32);
   assert_eq!(core::mem::offset_of!(GpuLight, light_type), 44);
   assert_eq!(core::mem::offset_of!(GpuLight, inner_cone_cos), 48);
   assert_eq!(core::mem::offset_of!(GpuLight, outer_cone_cos), 52);
   assert_eq!(core::mem::offset_of!(GpuLight, shadow_map_index), 56);
   assert_eq!(core::mem::size_of::<GpuLight>(), 64);

   // Validate ClusterCell size parity with WGSL
   assert_eq!(core::mem::size_of::<ClusterCell>(), 16); // or 8 if unpadded
   ```
2. **Execute Test Commands**:
   ```bash
   cargo test -p fluorite_core --test pbr_pipeline_test
   cargo test -p fluorite_core --lib rendering::cluster::tests
   cargo test -p fluorite_core --lib rendering::shadow::tests
   ```
3. **Invalidation Conditions**:
   - `GpuLight` offset at byte 44 does not match `light_type: u32`.
   - `size_of::<ClusterCell>()` does not equal WGSL `ClusterRecord` struct size.
   - Any test failure in `pbr_pipeline_test`.
