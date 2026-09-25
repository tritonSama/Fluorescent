# Milestone 1 Adversarial Challenge Report: Clustered Forward+ Light Grid

**Author**: `teamwork_preview_challenger_m1_1` (Empirical Challenger)  
**Target Module**: `fluorite_core::rendering::cluster::ClusterLightGrid`  
**Verdict**: `REQUEST_CHANGES`  
**Overall Risk Assessment**: **HIGH** (Critical GPU struct memory layout mismatch between Rust CPU packing and WGSL storage buffer unpacking; Medium edge case on negative radius handling)

---

## 1. Observation

### Observation 1: Cluster Invariant Preservation (`offset + count <= light_indices.len()`)
In `fluorite_core/src/rendering/cluster.rs` (lines 360–378):
```rust
        // 3. Flatten cluster index lists into contiguous GPU-ready buffers
        let mut cells = Vec::with_capacity(TOTAL_CLUSTERS);
        let mut light_indices = Vec::new();
        let mut max_lights_per_cluster: u32 = 0;
        let mut total_assignments: usize = 0;

        for list in cluster_light_lists {
            let count = list.len() as u32;
            let offset = light_indices.len() as u32;
            max_lights_per_cluster = max_lights_per_cluster.max(count);
            total_assignments += list.len();

            light_indices.extend_from_slice(&list);
            cells.push(ClusterCell {
                offset,
                count,
                _pad: [0, 0],
            });
        }
```
For all 3,456 clusters, `offset` is initialized to the current length of `light_indices`, and `count` elements are immediately appended. The sum $\text{offset}_i + \text{count}_i = \sum_{j=0}^{i} \text{count}_j \le \text{light\_indices.len()}$ holds for all $i \in [0, 3455]$. This holds across 0, 1, 1,024, 2,048, 4,096, and 10,000 dynamic lights.

### Observation 2: Boundary Depth and Coordinate Handling
In `fluorite_core/src/rendering/cluster.rs` (lines 204–213):
```rust
    pub fn depth_to_slice(&self, depth: f32) -> usize {
        if depth <= self.z_near {
            0
        } else if depth >= self.z_far {
            NUM_CLUSTERS_Z - 1
        } else {
            let slice = ((depth.ln() - self.log_near) * self.log_factor).floor() as usize;
            slice.min(NUM_CLUSTERS_Z - 1)
        }
    }
```
- Lights at $z\_depth \le z_{near}$ clamp to slice `0`.
- Lights at $z\_depth \ge z_{far}$ clamp to slice `NUM_CLUSTERS_Z - 1` (23).
- Continuous logarithmic spacing ensures no cluster boundaries produce gaps.

### Observation 3: Frustum Culling Behind Near Plane and Beyond Far Plane
In `fluorite_core/src/rendering/cluster.rs` (lines 292–296, 338–342):
```rust
    let min_z = z_depth - light.radius;
    let max_z = z_depth + light.radius;
    if max_z < self.z_near || min_z > self.z_far {
        continue;
    }
```
- Lights behind camera ($z\_depth \le 0$) with $z\_depth + \text{radius} < z_{near}$ are strictly culled (`continue;`).
- Lights beyond far plane ($z\_depth > z_{far}$) with $z\_depth - \text{radius} > z_{far}$ are strictly culled (`continue;`).
- Lights whose bounding sphere penetrates through the near plane ($z\_depth + \text{radius} \ge z_{near}$) or far plane ($z\_depth - \text{radius} \le z_{far}$) properly clamp their depth range via `min_z.max(self.z_near)` and `max_z.min(self.z_far)` and intersect only relevant clusters.

### Observation 4: Negative Radius Handling
In `fluorite_core/src/rendering/cluster.rs` (lines 292–304):
When `light.radius < 0.0`:
`min_z = z_depth - light.radius = z_depth + |r|`.
`max_z = z_depth + light.radius = z_depth - |r|`.
If $z\_depth$ is inside the frustum, `min_z > max_z`.
- For large negative radii, `slice_min > slice_max`. In Rust, `for z in slice_min..=slice_max` produces an empty iterator (0 iterations), so the light is culled.
- However, if `|light.radius|` is very small (e.g. $-0.00001$), `min_z` and `max_z` can fall in the same slice, so `slice_min == slice_max`. The loop then executes for that slice.
- Inside `ClusterAabb::intersects_sphere` (lines 56–64):
```rust
    pub fn intersects_sphere(&self, center: Vec3, radius: f32) -> bool {
        let closest = Vec3::new(
            center.x.clamp(self.min.x, self.max.x),
            center.y.clamp(self.min.y, self.max.y),
            center.z.clamp(self.min.z, self.max.z),
        );
        let dist_sq = (closest - center).length_squared();
        dist_sq <= radius * radius
    }
```
Because $\text{radius}^2 = (-r)^2 = r^2 > 0$, negative radius is squared, treating a negative radius light as a positive radius light instead of rejecting it!

### Observation 5: CRITICAL DEFECT — Struct Memory Layout Mismatch for `GpuLight`
Compare the struct definition in `fluorite_core/src/rendering/cluster.rs` (lines 90–100) vs `fluorite_core/src/rendering/shaders/pbr_forward.wgsl` (lines 38–49) and `cluster_cull.wgsl` (lines 27–38):

**Rust `cluster.rs`**:
```rust
#[repr(C)]
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
pub struct GpuLight {
    /// xyz: World position, w: Attenuation radius / range
    pub position_range: [f32; 4],      // Bytes 0..16
    /// xyz: Linear RGB color, w: Luminous intensity (cd / lm)
    pub color_intensity: [f32; 4],     // Bytes 16..32
    /// xyz: Unit light direction (for spot lights), w: cos(inner_angle)
    pub direction_inner: [f32; 4],     // Bytes 32..48 (direction.xyz at 32..44, cos(inner) at 44..48)
    /// x: cos(outer_angle), y: Light type (0.0 = Point, 1.0 = Spot), zw: padding
    pub params: [f32; 4],              // Bytes 48..64 (cos(outer) at 48..52, light_type f32 at 52..56)
}
```

**WGSL `pbr_forward.wgsl` and `cluster_cull.wgsl`**:
```wgsl
struct GpuLight {
    position_ws: vec3<f32>,   // align 16, offset 0..12
    radius: f32,              // align 4,  offset 12..16
    color: vec3<f32>,         // align 16, offset 16..28
    intensity: f32,           // align 4,  offset 28..32
    direction_ws: vec3<f32>,  // align 16, offset 32..44
    light_type: u32,          // align 4,  offset 44..48 !!! (0 = Directional, 1 = Point, 2 = Spot)
    inner_cone_cos: f32,      // align 4,  offset 48..52 !!!
    outer_cone_cos: f32,      // align 4,  offset 52..56 !!!
    shadow_map_index: i32,    // align 4,  offset 56..60
    _padding: u32,            // align 4,  offset 60..64
};
```

Notice the offset comparison:
| Byte Offset | Rust `GpuLight` (`cluster.rs`) | WGSL `GpuLight` (`pbr_forward.wgsl`) |
|---|---|---|
| **0..12** | `position_range[0..3]` ($x, y, z$) | `position_ws` ($x, y, z$) |
| **12..16** | `position_range[3]` (radius) | `radius` |
| **16..28** | `color_intensity[0..3]` ($r, g, b$) | `color` ($r, g, b$) |
| **28..32** | `color_intensity[3]` (intensity) | `intensity` |
| **32..44** | `direction_inner[0..3]` ($x, y, z$) | `direction_ws` ($x, y, z$) |
| **44..48** | `direction_inner[3]` = **`cos(inner_angle)` as `f32`** | **`light_type` as `u32`** |
| **48..52** | `params[0]` = **`cos(outer_angle)` as `f32`** | **`inner_cone_cos` as `f32`** |
| **52..56** | `params[1]` = **`light_type` as `f32`** | **`outer_cone_cos` as `f32`** |
| **56..60** | `params[2]` (padding) | `shadow_map_index` as `i32` |
| **60..64** | `params[3]` (padding) | `_padding` as `u32` |

In `cluster.rs` for Point Lights (lines 287–288):
```rust
direction_inner: [0.0, 0.0, 0.0, 1.0],
params: [1.0, 0.0, 0.0, 0.0], // light_type = 0.0 (Point)
```
Rust places `1.0_f32` at byte offset 44. In IEEE-754, `1.0_f32` is bit pattern `0x3F800000`, which equals `1,065,353,216` when read as a `u32`!
When `pbr_forward.wgsl` executes:
```wgsl
if (light.light_type == 0u) { ... }
else if (light.light_type == 1u) { ... }
else if (light.light_type == 2u) { ... }
```
The GPU reads `light.light_type == 1065353216u`. None of the branches match!
**All point lights and spot lights uploaded to the GPU will be completely ignored, causing dynamic lights to render completely black on screen!**

---

## 2. Logic Chain

1. From **Observation 1**, `offset` is always the running total length of `light_indices`, and `count` is the number of elements added for that cluster cell. Because memory indices are non-negative and monotonically concatenated, $\text{offset} + \text{count} \le \text{light\_indices.len()}$ is mathematically guaranteed for all 3,456 clusters.
2. From **Observation 2**, `depth_to_slice` clamps $z \le z_{near}$ to slice 0 and $z \ge z_{far}$ to slice 23. This prevents any out-of-bounds array access in `aabbs` and ensures stable boundary behavior across frustum boundaries.
3. From **Observation 3**, out-of-frustum lights are culled conservatively: lights behind camera or beyond far plane do not allocate cluster entries unless their radius actually penetrates the frustum.
4. From **Observation 4**, negative radii are not guarded. In `intersects_sphere`, $\text{dist\_sq} \le r^2$ squares negative values, which allows micro-negative radii to be treated as positive radii. Adding `if light.radius <= 0.0 { continue; }` is required for defensive robustness.
5. From **Observation 5**, the byte offset layout of `GpuLight` in Rust differs critically from `GpuLight` in `pbr_forward.wgsl` and `cluster_cull.wgsl`:
   - Offset 44 is `direction_inner[3]` (`f32`) in Rust, but `light_type` (`u32`) in WGSL.
   - Offset 48 is `params[0]` (`outer_cone_cos`) in Rust, but `inner_cone_cos` in WGSL.
   - Offset 52 is `params[1]` (`light_type` as `f32`) in Rust, but `outer_cone_cos` in WGSL.
   - Consequently, the shader reads garbage for `light_type` (`1,065,353,216`), rendering all dynamic lights invisible on the GPU.

---

## 3. Caveats

- CPU-side light binning tests alone do not catch this bug because `bin_lights` runs entirely on the CPU in Rust without uploading or executing the WGSL shader.
- Headless shader compilation tests (`test_wgsl_shader_compilation_headless`) pass because the shader itself is valid WGSL; Naga/WGPU compiler only checks intra-shader validity, not Rust-to-WGSL struct parity.
- The invariant `offset + count <= light_indices.len()` is strictly satisfied on the CPU, but runtime rendering would fail on the GPU until `GpuLight` layout is synchronized.

---

## 4. Conclusion

- **Verdict**: `REQUEST_CHANGES`
- **Required Action 1 (CRITICAL)**: Synchronize `GpuLight` layout in `fluorite_core/src/rendering/cluster.rs` with `pbr_forward.wgsl` and `cluster_cull.wgsl`:
  ```rust
  #[repr(C)]
  #[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
  pub struct GpuLight {
      pub position_ws: [f32; 3],
      pub radius: f32,
      pub color: [f32; 3],
      pub intensity: f32,
      pub direction_ws: [f32; 3],
      pub light_type: u32,       // 0 = Directional, 1 = Point, 2 = Spot
      pub inner_cone_cos: f32,
      pub outer_cone_cos: f32,
      pub shadow_map_index: i32,
      pub _padding: u32,
  }
  ```
  And update `bin_lights` point light packing to write `light_type: 1` (Point) and spot light packing to write `light_type: 2` (Spot), with `inner_cone_cos` and `outer_cone_cos` at their respective fields.
- **Required Action 2 (MEDIUM)**: Add early-out guard in `bin_lights` for non-positive radii:
  ```rust
  if light.radius <= 0.0 {
      continue;
  }
  ```

---

## 5. Verification Method

1. **Adversarial Test File**:
   Inspect `fluorite_core/tests/adversarial_cluster_stress_test.rs` (created).
2. **Execution**:
   Run `cargo test --test adversarial_cluster_stress_test` in `fluorite_core`:
   - `test_adversarial_light_counts_0_lights` (PASSED)
   - `test_adversarial_light_counts_1_light` (PASSED)
   - `test_adversarial_light_counts_1024_lights` (PASSED)
   - `test_adversarial_light_counts_2048_lights` (PASSED)
   - `test_adversarial_light_counts_4096_lights` (PASSED)
   - `test_adversarial_light_counts_10000_lights` (PASSED)
   - `test_adversarial_boundary_exact_near_and_far_planes` (PASSED)
   - `test_adversarial_boundary_all_cluster_slice_boundaries` (PASSED)
   - `test_adversarial_zero_radius_lights` (PASSED)
   - `test_adversarial_negative_radius_lights` (PASSED)
   - `test_adversarial_lights_behind_near_plane_and_camera` (PASSED)
   - `test_adversarial_lights_beyond_far_plane` (PASSED)
   - `test_adversarial_nan_and_inf_inputs` (PASSED)
   - `test_adversarial_gpu_light_layout_parity_investigation` (DEMONSTRATES CRITICAL DISCREPANCY)
3. **Invalidation Condition**:
   If `GpuLight` is updated such that `offset_of!(GpuLight, light_type) == 44`, `light_type: u32`, and point/spot lights are packed with 1u and 2u respectively, this challenge is resolved and can be converted to `APPROVE`.
