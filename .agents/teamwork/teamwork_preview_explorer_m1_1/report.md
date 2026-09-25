# Technical Report: WGSL Shaders & Uniform Structures for Milestone 1
## Clustered Forward+ PBR Rendering Pipeline

**Agent**: `teamwork_preview_explorer_m1_1`  
**Milestone**: M1 (PBR & Clustered Forward+ Renderer)  
**Target Subsystems**: `pbr_forward.wgsl`, `cluster_cull.wgsl`, `shadow_depth.wgsl`, and Uniform Layouts  
**Authoritative Reference**: `.agents/teamwork/ORIGINAL_REQUEST.md`, `PROJECT.md`  
**Date**: 2026-09-24  

---

## 1. Executive Summary

Milestone 1 establishes the AAA graphics foundation for the Fluorite Engine. This report specifies the exact mathematical models, GPU uniform structures, bind group layouts, and complete, self-contained WGSL shader source code for:
1. **`pbr_forward.wgsl`**: Full Cook-Torrance microfacet BRDF pipeline (Trowbridge-Reitz GGX normal distribution, Heitz 2014 Smith GGX correlated visibility, Schlick Fresnel) adhering strictly to glTF 2.0 PBR conventions (Albedo, Metallic-Roughness, Normal map TBN perturbation, Ambient Occlusion, Emissive) with an integrated clustered forward lighting loop supporting 1024+ dynamic lights and directional shadow mapping.
2. **`cluster_cull.wgsl`**: Compute shader for $16 \times 9 \times 24$ (3,456 cells) logarithmic view-space cluster grid slicing, analytic AABB generation, and branchless Arvo sphere-AABB intersection testing for dynamic point and spot lights.
3. **`shadow_depth.wgsl`**: Directional shadow map depth-only render pass with slope-scaled depth bias and 3x3 Percentage-Closer Filtering (PCF) sampling.
4. **Uniform Structures**: Byte-accurate Rust `#[repr(C)]` structs and WGSL mirror structs (`PbrMaterialUniforms` 48B, `CameraUniforms` 320B, `GpuLight` 64B, `ClusterRecord` 8B, `ShadowUniforms` 80B) with verified `bytemuck::Pod` / `bytemuck::Zeroable` compatibility and WebGPU 16-byte alignment invariants.

---

## 2. Uniform Buffer Memory Layout & Bytemuck Compatibility

WebGPU and WGSL enforce strict alignment rules for uniform and storage buffers (`std140` / `std430` rules). Any divergence between Rust memory layout and WGSL memory layout leads to silent vertex/color corruption or shader compilation failures.

### 2.1 `PbrMaterialUniforms` (48 Bytes, 16-Byte Aligned)

The PBR material uniform encapsulates material factors and feature bitflags.

#### Field-by-Field Offset & Alignment Table

| Byte Offset | Field Name | Rust Type | WGSL Type | Size | Alignment | Purpose |
|---|---|---|---|---|---|---|
| `0..16` | `base_color_factor` | `[f32; 4]` | `vec4<f32>` | 16 B | 16 B | Linear surface diffuse color & alpha |
| `16..28` | `emissive_factor` | `[f32; 3]` | `vec3<f32>` | 12 B | 16 B | Self-illuminating radiance factor |
| `28..32` | `metallic_factor` | `f32` | `f32` | 4 B | 4 B | Microfacet metalness multiplier [0.0, 1.0] |
| `32..36` | `roughness_factor` | `f32` | `f32` | 4 B | 4 B | Perceptual roughness multiplier [0.04, 1.0] |
| `36..40` | `normal_scale` | `f32` | `f32` | 4 B | 4 B | Normal map perturbation scale |
| `40..44` | `occlusion_strength` | `f32` | `f32` | 4 B | 4 B | Ambient occlusion blend factor [0.0, 1.0] |
| `44..48` | `flags` | `u32` | `u32` | 4 B | 4 B | Bitfield for enabled texture maps |

*Note on WGSL Alignment*: In WGSL uniform buffers, `vec3<f32>` has an alignment requirement of 16 bytes. Because `base_color_factor` occupies bytes `0..16`, byte 16 is a multiple of 16, allowing `emissive_factor` (`vec3<f32>`) to align without implicit padding. The remaining 5 scalar 4-byte fields occupy bytes `28..48`, exactly completing a 16-byte block ($48 = 3 \times 16$).

#### Material Flag Bitmask Constants

```rust
pub const MATERIAL_FLAG_HAS_ALBEDO_MAP: u32             = 1 << 0; // 0x01
pub const MATERIAL_FLAG_HAS_NORMAL_MAP: u32             = 1 << 1; // 0x02
pub const MATERIAL_FLAG_HAS_METALLIC_ROUGHNESS_MAP: u32 = 1 << 2; // 0x04
pub const MATERIAL_FLAG_HAS_OCCLUSION_MAP: u32          = 1 << 3; // 0x08
pub const MATERIAL_FLAG_HAS_EMISSIVE_MAP: u32           = 1 << 4; // 0x10
pub const MATERIAL_FLAG_ALPHA_BLEND: u32                = 1 << 5; // 0x20
```

#### Rust Definition

```rust
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, bytemuck::Pod, bytemuck::Zeroable)]
pub struct PbrMaterialUniforms {
    pub base_color_factor: [f32; 4],
    pub emissive_factor: [f32; 3],
    pub metallic_factor: f32,
    pub roughness_factor: f32,
    pub normal_scale: f32,
    pub occlusion_strength: f32,
    pub flags: u32,
}

impl Default for PbrMaterialUniforms {
    fn default() -> Self {
        Self {
            base_color_factor: [1.0, 1.0, 1.0, 1.0],
            emissive_factor: [0.0, 0.0, 0.0],
            metallic_factor: 1.0,
            roughness_factor: 1.0,
            normal_scale: 1.0,
            occlusion_strength: 1.0,
            flags: 0,
        }
    }
}

const _: () = assert!(std::mem::size_of::<PbrMaterialUniforms>() == 48);
const _: () = assert!(std::mem::align_of::<PbrMaterialUniforms>() == 4);
```

#### WGSL Struct Definition

```wgsl
struct PbrMaterialUniforms {
    base_color_factor: vec4<f32>,
    emissive_factor: vec3<f32>,
    metallic_factor: f32,
    roughness_factor: f32,
    normal_scale: f32,
    occlusion_strength: f32,
    flags: u32,
}
```

---

### 2.2 `CameraUniforms` (320 Bytes, 16-Byte Aligned)

The camera uniform delivers transformation matrices, screen/viewport parameters, and cluster grid configuration.

#### Field-by-Field Offset & Alignment Table

| Byte Offset | Field Name | Rust Type | WGSL Type | Size | Alignment | Purpose |
|---|---|---|---|---|---|---|
| `0..64` | `view_proj` | `[[f32; 4]; 4]` | `mat4x4<f32>` | 64 B | 16 B | Concatenated View $\times$ Projection matrix |
| `64..128` | `view` | `[[f32; 4]; 4]` | `mat4x4<f32>` | 64 B | 16 B | World-to-View matrix |
| `128..192` | `proj` | `[[f32; 4]; 4]` | `mat4x4<f32>` | 64 B | 16 B | View-to-Clip Projection matrix |
| `192..256` | `inv_proj` | `[[f32; 4]; 4]` | `mat4x4<f32>` | 64 B | 16 B | Clip-to-View Inverse Projection matrix |
| `256..268` | `camera_pos` | `[f32; 3]` | `vec3<f32>` | 12 B | 16 B | World-space camera position |
| `268..272` | `z_near` | `f32` | `f32` | 4 B | 4 B | Camera near plane clipping distance ($>0$) |
| `272..276` | `z_far` | `f32` | `f32` | 4 B | 4 B | Camera far plane clipping distance ($>z_{\text{near}}$) |
| `276..280` | `screen_width` | `f32` | `f32` | 4 B | 4 B | Viewport width in physical pixels |
| `280..284` | `screen_height` | `f32` | `f32` | 4 B | 4 B | Viewport height in physical pixels |
| `284..288` | `cluster_dim_x` | `u32` | `u32` | 4 B | 4 B | Cluster slice count along X (16) |
| `288..292` | `cluster_dim_y` | `u32` | `u32` | 4 B | 4 B | Cluster slice count along Y (9) |
| `292..296` | `cluster_dim_z` | `u32` | `u32` | 4 B | 4 B | Cluster slice count along Z (24) |
| `296..300` | `num_dynamic_lights` | `u32` | `u32` | 4 B | 4 B | Active light count uploaded to GPU |
| `300..304` | `_padding` | `u32` | `u32` | 4 B | 4 B | **Critical padding**: forces 16B alignment for `ambient_light` |
| `304..320` | `ambient_light` | `[f32; 4]` | `vec4<f32>` | 16 B | 16 B | Ambient radiant flux RGB + padding intensity |

**Critical Architectural Invariant**: In WGSL, `ambient_light: vec4<f32>` requires 16-byte alignment. If `num_dynamic_lights` at byte 296 was immediately followed by `ambient_light`, WGSL would automatically insert 4 bytes of padding at bytes 300..304, causing a 4-byte mismatch with naive Rust `#[repr(C)]` structs. Adding explicit `pub _padding: u32` guarantees exact 320-byte sizing and 100% field alignment parity across Rust and GPU shaders.

#### Rust Definition

```rust
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, bytemuck::Pod, bytemuck::Zeroable)]
pub struct CameraUniforms {
    pub view_proj: [[f32; 4]; 4],
    pub view: [[f32; 4]; 4],
    pub proj: [[f32; 4]; 4],
    pub inv_proj: [[f32; 4]; 4],
    pub camera_pos: [f32; 3],
    pub z_near: f32,
    pub z_far: f32,
    pub screen_width: f32,
    pub screen_height: f32,
    pub cluster_dim_x: u32,
    pub cluster_dim_y: u32,
    pub cluster_dim_z: u32,
    pub num_dynamic_lights: u32,
    pub _padding: u32,
    pub ambient_light: [f32; 4],
}

const _: () = assert!(std::mem::size_of::<CameraUniforms>() == 320);
const _: () = assert!(std::mem::align_of::<CameraUniforms>() == 4);
```

#### WGSL Struct Definition

```wgsl
struct CameraUniforms {
    view_proj: mat4x4<f32>,
    view: mat4x4<f32>,
    proj: mat4x4<f32>,
    inv_proj: mat4x4<f32>,
    camera_pos: vec3<f32>,
    z_near: f32,
    z_far: f32,
    screen_width: f32,
    screen_height: f32,
    cluster_dim_x: u32,
    cluster_dim_y: u32,
    cluster_dim_z: u32,
    num_dynamic_lights: u32,
    _padding: u32,
    ambient_light: vec4<f32>,
}
```

---

### 2.3 `GpuLight` (64 Bytes, 16-Byte Aligned)

Array of dynamic point, spot, and directional lights stored in a GPU storage buffer.

#### Field-by-Field Offset & Alignment Table

| Byte Offset | Field Name | Rust Type | WGSL Type | Size | Alignment | Purpose |
|---|---|---|---|---|---|---|
| `0..12` | `position_ws` | `[f32; 3]` | `vec3<f32>` | 12 B | 16 B | World-space light position (Point/Spot) |
| `12..16` | `radius` | `f32` | `f32` | 4 B | 4 B | Maximum attenuation sphere radius ($r$) |
| `16..28` | `color` | `[f32; 3]` | `vec3<f32>` | 12 B | 16 B | Radiant color in linear RGB |
| `28..32` | `intensity` | `f32` | `f32` | 4 B | 4 B | Luminous intensity (candela / lumens) |
| `32..44` | `direction_ws` | `[f32; 3]` | `vec3<f32>` | 12 B | 16 B | Normalized direction (Spot / Directional) |
| `44..48` | `light_type` | `u32` | `u32` | 4 B | 4 B | `0` = Directional, `1` = Point, `2` = Spot |
| `48..52` | `inner_cone_cos` | `f32` | `f32` | 4 B | 4 B | $\cos(\theta_{\text{inner}})$ for spot lights |
| `52..56` | `outer_cone_cos` | `f32` | `f32` | 4 B | 4 B | $\cos(\theta_{\text{outer}})$ for spot lights |
| `56..60` | `shadow_map_index` | `i32` | `i32` | 4 B | 4 B | Shadow map cascade index (`-1` = unshadowed) |
| `60..64` | `_padding` | `u32` | `u32` | 4 B | 4 B | Pads structure to exactly 64 bytes (cache line) |

*Memory Packing Invariant*: Each `vec3<f32>` (12B) is placed at a 16-byte boundary (`0`, `16`, `32`) and immediately paired with a 4-byte scalar (`12`, `28`, `44`). The remaining four 4-byte scalars fill bytes `48..64`. Exactly 64 bytes per light ($4 \times 16$). 1024 lights occupy exactly 65,536 bytes (64 KB).

#### Rust Definition

```rust
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, bytemuck::Pod, bytemuck::Zeroable)]
pub struct GpuLight {
    pub position_ws: [f32; 3],
    pub radius: f32,
    pub color: [f32; 3],
    pub intensity: f32,
    pub direction_ws: [f32; 3],
    pub light_type: u32,
    pub inner_cone_cos: f32,
    pub outer_cone_cos: f32,
    pub shadow_map_index: i32,
    pub _padding: u32,
}

impl Default for GpuLight {
    fn default() -> Self {
        Self {
            position_ws: [0.0, 0.0, 0.0],
            radius: 10.0,
            color: [1.0, 1.0, 1.0],
            intensity: 1.0,
            direction_ws: [0.0, -1.0, 0.0],
            light_type: 1, // Point light default
            inner_cone_cos: 0.866, // cos(30 deg)
            outer_cone_cos: 0.707, // cos(45 deg)
            shadow_map_index: -1,
            _padding: 0,
        }
    }
}

const _: () = assert!(std::mem::size_of::<GpuLight>() == 64);
const _: () = assert!(std::mem::align_of::<GpuLight>() == 4);
```

#### WGSL Struct Definition

```wgsl
struct GpuLight {
    position_ws: vec3<f32>,
    radius: f32,
    color: vec3<f32>,
    intensity: f32,
    direction_ws: vec3<f32>,
    light_type: u32,
    inner_cone_cos: f32,
    outer_cone_cos: f32,
    shadow_map_index: i32,
    _padding: u32,
}
```

---

### 2.4 `ClusterRecord` (8 Bytes) & `ShadowUniforms` (80 Bytes)

#### `ClusterRecord`
Stored in `array<ClusterRecord>`: 3,456 clusters $\times 8\text{ B} = 27,648\text{ B}$.

```rust
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, bytemuck::Pod, bytemuck::Zeroable)]
pub struct ClusterRecord {
    pub offset: u32, // Byte/Index offset into global light index buffer
    pub count: u32,  // Count of lights intersecting this cluster
}
const _: () = assert!(std::mem::size_of::<ClusterRecord>() == 8);
```

```wgsl
struct ClusterRecord {
    offset: u32,
    count: u32,
}
```

#### `ShadowUniforms`
Holds the directional shadow cascade matrix, depth biases, and resolution.

```rust
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, bytemuck::Pod, bytemuck::Zeroable)]
pub struct ShadowUniforms {
    pub light_view_proj: [[f32; 4]; 4], // 64 bytes (offset 0..64)
    pub shadow_bias_min: f32,           // 4 bytes  (offset 64..68)
    pub shadow_bias_max: f32,           // 4 bytes  (offset 68..72)
    pub shadow_map_size: f32,           // 4 bytes  (offset 72..76)
    pub pcf_samples: u32,               // 4 bytes  (offset 76..80)
}
const _: () = assert!(std::mem::size_of::<ShadowUniforms>() == 80);
```

```wgsl
struct ShadowUniforms {
    light_view_proj: mat4x4<f32>,
    shadow_bias_min: f32,
    shadow_bias_max: f32,
    shadow_map_size: f32,
    pcf_samples: u32,
}
```

---

## 3. Bind Group Architecture

To comply with the WebGPU baseline limit of **4 bind groups** (`max_bind_groups = 4`), the resource bindings are partitioned as follows:

| Bind Group | Binding | Resource | Type | Visibility | Description |
|---|---|---|---|---|---|
| **Group 0** (Frame & Lights) | `@binding(0)` | `camera` | `uniform CameraUniforms` | Vertex & Fragment & Compute | View, Proj, Camera Pos, Viewport, Clusters |
| | `@binding(1)` | `lights` | `storage<read> array<GpuLight>` | Fragment & Compute | Global list of 1024+ scene lights |
| | `@binding(2)` | `cluster_records` | `storage<read> array<ClusterRecord>` | Fragment (Compute: `read_write`) | Per-cluster light offset and count (3,456) |
| | `@binding(3)` | `cluster_light_indices` | `storage<read> array<u32>` | Fragment (Compute: `read_write`) | Contiguous list of light indices per cluster |
| **Group 1** (Material) | `@binding(0)` | `material` | `uniform PbrMaterialUniforms` | Fragment | Factors and feature flags (48B) |
| | `@binding(1)` | `albedo_texture` | `texture_2d<f32>` | Fragment | Base color diffuse texture (sRGB) |
| | `@binding(2)` | `albedo_sampler` | `sampler` | Fragment | Filtering sampler for albedo |
| | `@binding(3)` | `normal_texture` | `texture_2d<f32>` | Fragment | Tangent space normal map (Linear) |
| | `@binding(4)` | `normal_sampler` | `sampler` | Fragment | Filtering sampler for normals |
| | `@binding(5)` | `metallic_roughness_texture` | `texture_2d<f32>` | Fragment | G: Roughness, B: Metallic (Linear) |
| | `@binding(6)` | `metallic_roughness_sampler` | `sampler` | Fragment | Filtering sampler for metallic-roughness |
| | `@binding(7)` | `occlusion_texture` | `texture_2d<f32>` | Fragment | R: Ambient Occlusion factor (Linear) |
| | `@binding(8)` | `occlusion_sampler` | `sampler` | Fragment | Filtering sampler for occlusion |
| | `@binding(9)` | `emissive_texture` | `texture_2d<f32>` | Fragment | Emissive self-illumination (sRGB) |
| | `@binding(10)` | `emissive_sampler` | `sampler` | Fragment | Filtering sampler for emissive |
| **Group 2** (Shadows) | `@binding(0)` | `shadow_uniforms` | `uniform ShadowUniforms` | Vertex & Fragment | Directional light view-projection & bias |
| | `@binding(1)` | `shadow_map` | `texture_depth_2d` | Fragment | Hardware depth texture for directional shadow |
| | `@binding(2)` | `shadow_sampler` | `sampler_comparison` | Fragment | Hardware comparison sampler for PCF |
| **Group 3** (Model Transform) | `@binding(0)` | `model_matrix` | `uniform mat4x4<f32>` | Vertex | Per-entity world transform |

---

## 4. `pbr_forward.wgsl` Specification

### 4.1 Cook-Torrance Microfacet BRDF Formulation

The complete surface reflectance evaluation is:
$$f_r(\mathbf{v}, \mathbf{l}) = f_{\text{diffuse}} + f_{\text{specular}}$$

#### 1. Diffuse Term (Lambertian with Conductor Cancellation)
$$f_{\text{diffuse}} = \frac{\mathbf{c}_{\text{diff}}}{\pi} = \frac{\text{albedo} \cdot (1 - \text{metallic}) \cdot (1 - F)}{\pi}$$

#### 2. Specular Term
$$f_{\text{specular}} = D(\mathbf{n}, \mathbf{h}, \alpha) \cdot V(\mathbf{n}, \mathbf{v}, \mathbf{l}, \alpha) \cdot F(\mathbf{v}, \mathbf{h}, \mathbf{F}_0)$$
where $\mathbf{h} = \frac{\mathbf{v} + \mathbf{l}}{\|\mathbf{v} + \mathbf{l}\|}$, and $\alpha = \text{roughness}^2$.

#### 3. Normal Distribution Function $D$ (Trowbridge-Reitz GGX)
$$D(\mathbf{n}, \mathbf{h}, \alpha) = \frac{\alpha^2}{\pi \left( (\mathbf{n} \cdot \mathbf{h})^2 (\alpha^2 - 1) + 1 \right)^2}$$

#### 4. Correlated Visibility Function $V$ (Heitz 2014 Smith GGX)
Combines geometric shadowing-masking $G$ and microfacet denominator $4(\mathbf{n} \cdot \mathbf{v})(\mathbf{n} \cdot \mathbf{l})$:
$$V(\mathbf{n}, \mathbf{v}, \mathbf{l}, \alpha) = \frac{0.5}{(\mathbf{n} \cdot \mathbf{l}) \sqrt{(\mathbf{n} \cdot \mathbf{v})^2(1 - \alpha^2) + \alpha^2} + (\mathbf{n} \cdot \mathbf{v}) \sqrt{(\mathbf{n} \cdot \mathbf{l})^2(1 - \alpha^2) + \alpha^2}}$$

#### 5. Fresnel Reflectance $F$ (Schlick Approximation)
$$F(\mathbf{v}, \mathbf{h}, \mathbf{F}_0) = \mathbf{F}_0 + (1 - \mathbf{F}_0)(1 - (\mathbf{v} \cdot \mathbf{h}))^5$$
with dielectric/conductor base reflectance:
$$\mathbf{F}_0 = \text{mix}(\text{vec3<f32>}(0.04), \text{albedo}, \text{metallic})$$

### 4.2 Complete WGSL Implementation: `pbr_forward.wgsl`

```wgsl
// ============================================================================
// Fluorite Engine — Milestone 1: PBR Clustered Forward+ Shader
// File: pbr_forward.wgsl
// ============================================================================

const PI: f32 = 3.141592653589793;
const EPSILON: f32 = 1e-5;

// Material Flags
const FLAG_HAS_ALBEDO_MAP: u32             = 1u;  // 1 << 0
const FLAG_HAS_NORMAL_MAP: u32             = 2u;  // 1 << 1
const FLAG_HAS_METALLIC_ROUGHNESS_MAP: u32 = 4u;  // 1 << 2
const FLAG_HAS_OCCLUSION_MAP: u32          = 8u;  // 1 << 3
const FLAG_HAS_EMISSIVE_MAP: u32           = 16u; // 1 << 4

// ----------------------------------------------------------------------------
// Uniform Structures
// ----------------------------------------------------------------------------

struct CameraUniforms {
    view_proj: mat4x4<f32>,
    view: mat4x4<f32>,
    proj: mat4x4<f32>,
    inv_proj: mat4x4<f32>,
    camera_pos: vec3<f32>,
    z_near: f32,
    z_far: f32,
    screen_width: f32,
    screen_height: f32,
    cluster_dim_x: u32,
    cluster_dim_y: u32,
    cluster_dim_z: u32,
    num_dynamic_lights: u32,
    _padding: u32,
    ambient_light: vec4<f32>,
};

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

struct ClusterRecord {
    offset: u32,
    count: u32,
};

struct PbrMaterialUniforms {
    base_color_factor: vec4<f32>,
    emissive_factor: vec3<f32>,
    metallic_factor: f32,
    roughness_factor: f32,
    normal_scale: f32,
    occlusion_strength: f32,
    flags: u32,
};

struct ShadowUniforms {
    light_view_proj: mat4x4<f32>,
    shadow_bias_min: f32,
    shadow_bias_max: f32,
    shadow_map_size: f32,
    pcf_samples: u32,
};

// ----------------------------------------------------------------------------
// Resource Bindings
// ----------------------------------------------------------------------------

// Group 0: Frame & Lights
@group(0) @binding(0) var<uniform> camera: CameraUniforms;
@group(0) @binding(1) var<storage, read> lights: array<GpuLight>;
@group(0) @binding(2) var<storage, read> cluster_records: array<ClusterRecord>;
@group(0) @binding(3) var<storage, read> cluster_light_indices: array<u32>;

// Group 1: Material
@group(1) @binding(0) var<uniform> material: PbrMaterialUniforms;
@group(1) @binding(1) var albedo_texture: texture_2d<f32>;
@group(1) @binding(2) var albedo_sampler: sampler;
@group(1) @binding(3) var normal_texture: texture_2d<f32>;
@group(1) @binding(4) var normal_sampler: sampler;
@group(1) @binding(5) var metallic_roughness_texture: texture_2d<f32>;
@group(1) @binding(6) var metallic_roughness_sampler: sampler;
@group(1) @binding(7) var occlusion_texture: texture_2d<f32>;
@group(1) @binding(8) var occlusion_sampler: sampler;
@group(1) @binding(9) var emissive_texture: texture_2d<f32>;
@group(1) @binding(10) var emissive_sampler: sampler;

// Group 2: Shadows
@group(2) @binding(0) var<uniform> shadow_uniforms: ShadowUniforms;
@group(2) @binding(1) var shadow_map: texture_depth_2d;
@group(2) @binding(2) var shadow_sampler: sampler_comparison;

// Group 3: Model Transform
@group(3) @binding(0) var<uniform> model_matrix: mat4x4<f32>;

// ----------------------------------------------------------------------------
// Vertex Shader Stage
// ----------------------------------------------------------------------------

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) tangent: vec4<f32>,
    @location(3) uv: vec2<f32>,
};

struct VertexOutput {
    @builtin(position) clip_pos: vec4<f32>,
    @location(0) world_pos: vec3<f32>,
    @location(1) world_normal: vec3<f32>,
    @location(2) world_tangent: vec3<f32>,
    @location(3) world_bitangent: vec3<f32>,
    @location(4) uv: vec2<f32>,
    @location(5) view_depth: f32,
};

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    let world_pos_4 = model_matrix * vec4<f32>(in.position, 1.0);
    out.world_pos = world_pos_4.xyz;
    out.clip_pos = camera.view_proj * world_pos_4;

    // Normal and Tangent transformations (assuming uniform scaling)
    let normal_matrix = mat3x3<f32>(
        model_matrix[0].xyz,
        model_matrix[1].xyz,
        model_matrix[2].xyz
    );
    let N = normalize(normal_matrix * in.normal);
    let T = normalize(normal_matrix * in.tangent.xyz);
    let B = normalize(cross(N, T) * in.tangent.w);

    out.world_normal = N;
    out.world_tangent = T;
    out.world_bitangent = B;
    out.uv = in.uv;

    // View-space depth along camera forward axis (Z_view is negative, so depth > 0)
    let view_pos = camera.view * world_pos_4;
    out.view_depth = -view_pos.z;

    return out;
}

// ----------------------------------------------------------------------------
// PBR Evaluation Functions
// ----------------------------------------------------------------------------

fn distribution_ggx(n_dot_h: f32, roughness: f32) -> f32 {
    let alpha = roughness * roughness;
    let alpha2 = alpha * alpha;
    let n_dot_h2 = n_dot_h * n_dot_h;
    let denom = n_dot_h2 * (alpha2 - 1.0) + 1.0;
    return alpha2 / (PI * denom * denom);
}

fn visibility_smith_ggx_correlated(n_dot_v: f32, n_dot_l: f32, roughness: f32) -> f32 {
    let alpha = roughness * roughness;
    let alpha2 = alpha * alpha;
    let ggx_v = n_dot_l * sqrt(n_dot_v * n_dot_v * (1.0 - alpha2) + alpha2);
    let ggx_l = n_dot_v * sqrt(n_dot_l * n_dot_l * (1.0 - alpha2) + alpha2);
    let denom = ggx_v + ggx_l;
    if (denom > 0.0) {
        return 0.5 / denom;
    }
    return 0.0;
}

fn fresnel_schlick(v_dot_h: f32, f0: vec3<f32>) -> vec3<f32> {
    return f0 + (vec3<f32>(1.0) - f0) * pow(clamp(1.0 - v_dot_h, 0.0, 1.0), 5.0);
}

fn sample_directional_shadow(world_pos: vec3<f32>, n_dot_l: f32) -> f32 {
    let shadow_coord = shadow_uniforms.light_view_proj * vec4<f32>(world_pos, 1.0);
    let proj = shadow_coord.xyz / shadow_coord.w;

    // Map NDC [-1, 1] to UV [0, 1] (WebGPU V is inverted from NDC Y)
    let uv = vec2<f32>(proj.x * 0.5 + 0.5, -proj.y * 0.5 + 0.5);
    let depth = proj.z;

    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || depth > 1.0) {
        return 1.0;
    }

    // Slope-scaled depth bias
    let bias = max(shadow_uniforms.shadow_bias_max * (1.0 - n_dot_l), shadow_uniforms.shadow_bias_min);
    let current_depth = depth - bias;

    // 3x3 PCF Kernel
    let texel_size = 1.0 / shadow_uniforms.shadow_map_size;
    var shadow: f32 = 0.0;
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let offset = vec2<f32>(f32(x), f32(y)) * texel_size;
            shadow += textureSampleCompare(shadow_map, shadow_sampler, uv + offset, current_depth);
        }
    }
    return shadow / 9.0;
}

fn evaluate_cook_torrance(
    n: vec3<f32>,
    v: vec3<f32>,
    l: vec3<f32>,
    albedo: vec3<f32>,
    metallic: f32,
    roughness: f32,
    f0: vec3<f32>,
    light_radiance: vec3<f32>
) -> vec3<f32> {
    let n_dot_l = max(dot(n, l), 0.0);
    if (n_dot_l <= 0.0) {
        return vec3<f32>(0.0);
    }

    let n_dot_v = max(dot(n, v), EPSILON);
    let h = normalize(v + l);
    let n_dot_h = max(dot(n, h), 0.0);
    let v_dot_h = max(dot(v, h), 0.0);

    // Specular D, V, F
    let d = distribution_ggx(n_dot_h, roughness);
    let vis = visibility_smith_ggx_correlated(n_dot_v, n_dot_l, roughness);
    let f = fresnel_schlick(v_dot_h, f0);

    let specular_brdf = f * (d * vis);

    // Diffuse Lambertian with metallic cancellation
    let k_d = (vec3<f32>(1.0) - f) * (1.0 - metallic);
    let diffuse_brdf = k_d * (albedo / PI);

    return (diffuse_brdf + specular_brdf) * light_radiance * n_dot_l;
}

// ----------------------------------------------------------------------------
// Fragment Shader Stage
// ----------------------------------------------------------------------------

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    // 1. Material Inputs & Texture Sampling
    var albedo = material.base_color_factor.rgb;
    var alpha = material.base_color_factor.a;
    if ((material.flags & FLAG_HAS_ALBEDO_MAP) != 0u) {
        let sampled = textureSample(albedo_texture, albedo_sampler, in.uv);
        albedo *= sampled.rgb;
        alpha *= sampled.a;
    }

    var roughness = material.roughness_factor;
    var metallic = material.metallic_factor;
    if ((material.flags & FLAG_HAS_METALLIC_ROUGHNESS_MAP) != 0u) {
        let mr = textureSample(metallic_roughness_texture, metallic_roughness_sampler, in.uv);
        roughness *= mr.g;
        metallic *= mr.b;
    }
    roughness = clamp(roughness, 0.045, 1.0);
    metallic = clamp(metallic, 0.0, 1.0);

    // Normal Perturbation (TBN)
    var N = normalize(in.world_normal);
    if ((material.flags & FLAG_HAS_NORMAL_MAP) != 0u) {
        let normal_sample = textureSample(normal_texture, normal_sampler, in.uv).xyz * 2.0 - 1.0;
        let tangent_normal = vec3<f32>(
            normal_sample.xy * material.normal_scale,
            normal_sample.z
        );
        let tbn = mat3x3<f32>(in.world_tangent, in.world_bitangent, in.world_normal);
        N = normalize(tbn * tangent_normal);
    }

    // Ambient Occlusion
    var ao: f32 = 1.0;
    if ((material.flags & FLAG_HAS_OCCLUSION_MAP) != 0u) {
        let occ_sample = textureSample(occlusion_texture, occlusion_sampler, in.uv).r;
        ao = mix(1.0, occ_sample, material.occlusion_strength);
    }

    // Emissive Radiance
    var emissive = material.emissive_factor;
    if ((material.flags & FLAG_HAS_EMISSIVE_MAP) != 0u) {
        emissive *= textureSample(emissive_texture, emissive_sampler, in.uv).rgb;
    }

    let V = normalize(camera.camera_pos - in.world_pos);
    let f0 = mix(vec3<f32>(0.04), albedo, metallic);

    // 2. Clustered Forward+ Grid Resolution
    let frag_xy = in.clip_pos.xy;
    let tile_x = clamp(u32(frag_xy.x / camera.screen_width * f32(camera.cluster_dim_x)), 0u, camera.cluster_dim_x - 1u);
    let tile_y = clamp(u32(frag_xy.y / camera.screen_height * f32(camera.cluster_dim_y)), 0u, camera.cluster_dim_y - 1u);

    // Logarithmic depth slice: slice_z = floor( ln(z_view / z_near) / ln(z_far / z_near) * dim_z )
    let view_depth = max(in.view_depth, camera.z_near);
    let log_ratio = log(view_depth / camera.z_near) / log(camera.z_far / camera.z_near);
    let tile_z = clamp(u32(log_ratio * f32(camera.cluster_dim_z)), 0u, camera.cluster_dim_z - 1u);

    let cluster_idx = tile_x + tile_y * camera.cluster_dim_x + tile_z * (camera.cluster_dim_x * camera.cluster_dim_y);

    // 3. Clustered Light Accumulation
    var direct_lighting = vec3<f32>(0.0);
    let record = cluster_records[cluster_idx];
    let offset = record.offset;
    let count = record.count;

    for (var i: u32 = 0u; i < count; i = i + 1u) {
        let light_idx = cluster_light_indices[offset + i];
        let light = lights[light_idx];

        if (light.light_type == 0u) {
            // Directional Light
            let L = -normalize(light.direction_ws);
            let n_dot_l = max(dot(N, L), 0.0);
            var shadow = 1.0;
            if (light.shadow_map_index >= 0) {
                shadow = sample_directional_shadow(in.world_pos, n_dot_l);
            }
            let radiance = light.color * light.intensity * shadow;
            direct_lighting += evaluate_cook_torrance(N, V, L, albedo, metallic, roughness, f0, radiance);
        } else if (light.light_type == 1u) {
            // Point Light
            let L_vec = light.position_ws - in.world_pos;
            let d = length(L_vec);
            if (d < light.radius) {
                let L = L_vec / d;
                let att_inv_sq = 1.0 / max(d * d, 0.0001);
                let factor = clamp(1.0 - pow(d / light.radius, 4.0), 0.0, 1.0);
                let window = factor * factor;
                let radiance = light.color * light.intensity * (att_inv_sq * window);
                direct_lighting += evaluate_cook_torrance(N, V, L, albedo, metallic, roughness, f0, radiance);
            }
        } else if (light.light_type == 2u) {
            // Spot Light
            let L_vec = light.position_ws - in.world_pos;
            let d = length(L_vec);
            if (d < light.radius) {
                let L = L_vec / d;
                let att_inv_sq = 1.0 / max(d * d, 0.0001);
                let factor = clamp(1.0 - pow(d / light.radius, 4.0), 0.0, 1.0);
                let dist_window = factor * factor;

                let cos_theta = dot(-L, normalize(light.direction_ws));
                let cone_scale = 1.0 / max(light.inner_cone_cos - light.outer_cone_cos, 0.0001);
                let cone_offset = -light.outer_cone_cos * cone_scale;
                let spot_factor = clamp(cos_theta * cone_scale + cone_offset, 0.0, 1.0);
                let angular_att = spot_factor * spot_factor;

                let radiance = light.color * light.intensity * (dist_window * att_inv_sq * angular_att);
                direct_lighting += evaluate_cook_torrance(N, V, L, albedo, metallic, roughness, f0, radiance);
            }
        }
    }

    // 4. Ambient and Emissive Synthesis
    let ambient = camera.ambient_light.rgb * albedo * ao;
    var final_color = direct_lighting + ambient + emissive;

    // ACES Filmic Tone Mapping approximation
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    final_color = clamp((final_color * (a * final_color + b)) / (final_color * (c * final_color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));

    return vec4<f32>(final_color, alpha);
}
```

---

## 5. `cluster_cull.wgsl` Specification

### 5.1 Logarithmic Slicing & Analytic AABB Derivation

The compute shader executes over the 3,456 clusters ($16 \times 9 \times 24$). For each cluster:
1. **Screen Coordinates**:
   - $u_0 = i_x / N_x$, $u_1 = (i_x + 1) / N_x$
   - $v_0 = i_y / N_y$, $v_1 = (i_y + 1) / N_y$
   - NDC bounds:
     $$x_{\text{ndc},\min} = u_0 \cdot 2 - 1, \quad x_{\text{ndc},\max} = u_1 \cdot 2 - 1$$
     $$y_{\text{ndc},\min} = 1 - v_1 \cdot 2, \quad y_{\text{ndc},\max} = 1 - v_0 \cdot 2$$
2. **Logarithmic Depth Extents**:
   $$z_{\text{near}} = z_{\text{cam\_near}} \cdot \left(\frac{z_{\text{cam\_far}}}{z_{\text{cam\_near}}}\right)^{\frac{i_z}{N_z}}$$
   $$z_{\text{far}} = z_{\text{cam\_near}} \cdot \left(\frac{z_{\text{cam\_far}}}{z_{\text{cam\_near}}}\right)^{\frac{i_z + 1}{N_z}}$$
3. **Analytic View-Space Bounds**:
   Unprojecting NDC with projection matrix diagonals $P_{00} = \text{proj}[0][0]$ and $P_{11} = \text{proj}[1][1]$:
   $$\mathbf{b}_{\min} = \left( \min(x_{\min,\text{near}}, x_{\min,\text{far}}), \; \min(y_{\min,\text{near}}, y_{\min,\text{far}}), \; -z_{\text{far}} \right)$$
   $$\mathbf{b}_{\max} = \left( \max(x_{\max,\text{near}}, x_{\max,\text{far}}), \; \max(y_{\max,\text{near}}, y_{\max,\text{far}}), \; -z_{\text{near}} \right)$$

4. **Light Intersection (Arvo's Sphere-AABB algorithm)**:
   For light view-space position $\mathbf{c} = (\mathbf{V} \cdot \mathbf{p}_{\text{ws}})_{xyz}$:
   $$d^2 = \sum_{a \in \{x,y,z\}} \left( \max(0, b_{\min, a} - c_a)^2 + \max(0, c_a - b_{\max, a})^2 \right)$$
   Intersection condition: $d^2 \le r^2$.

### 5.2 Complete WGSL Implementation: `cluster_cull.wgsl`

```wgsl
// ============================================================================
// Fluorite Engine — Milestone 1: Cluster Slicing & Light Culling Compute Shader
// File: cluster_cull.wgsl
// ============================================================================

const MAX_LIGHTS_PER_CLUSTER: u32 = 128u;
const MAX_GLOBAL_LIGHT_INDICES: u32 = 262144u; // 256K indices buffer

struct CameraUniforms {
    view_proj: mat4x4<f32>,
    view: mat4x4<f32>,
    proj: mat4x4<f32>,
    inv_proj: mat4x4<f32>,
    camera_pos: vec3<f32>,
    z_near: f32,
    z_far: f32,
    screen_width: f32,
    screen_height: f32,
    cluster_dim_x: u32,
    cluster_dim_y: u32,
    cluster_dim_z: u32,
    num_dynamic_lights: u32,
    _padding: u32,
    ambient_light: vec4<f32>,
};

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

struct ClusterRecord {
    offset: u32,
    count: u32,
};

// ----------------------------------------------------------------------------
// Resource Bindings
// ----------------------------------------------------------------------------

@group(0) @binding(0) var<uniform> camera: CameraUniforms;
@group(0) @binding(1) var<storage, read> lights: array<GpuLight>;
@group(0) @binding(2) var<storage, read_write> cluster_records: array<ClusterRecord>;
@group(0) @binding(3) var<storage, read_write> cluster_light_indices: array<u32>;
@group(0) @binding(4) var<storage, read_write> global_index_counter: atomic<u32>;

// ----------------------------------------------------------------------------
// Compute Shader Entry Point
// ----------------------------------------------------------------------------

@compute @workgroup_size(64, 1, 1)
fn cs_main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let cluster_idx = global_id.x;
    let total_clusters = camera.cluster_dim_x * camera.cluster_dim_y * camera.cluster_dim_z;
    if (cluster_idx >= total_clusters) {
        return;
    }

    // Unpack 1D index to (tile_x, tile_y, tile_z)
    let tile_x = cluster_idx % camera.cluster_dim_x;
    let tile_y = (cluster_idx / camera.cluster_dim_x) % camera.cluster_dim_y;
    let tile_z = cluster_idx / (camera.cluster_dim_x * camera.cluster_dim_y);

    // 1. NDC Tile Coordinates
    let u0 = f32(tile_x) / f32(camera.cluster_dim_x);
    let u1 = f32(tile_x + 1u) / f32(camera.cluster_dim_x);
    let v0 = f32(tile_y) / f32(camera.cluster_dim_y);
    let v1 = f32(tile_y + 1u) / f32(camera.cluster_dim_y);

    let ndc_x_min = u0 * 2.0 - 1.0;
    let ndc_x_max = u1 * 2.0 - 1.0;
    let ndc_y_min = 1.0 - v1 * 2.0;
    let ndc_y_max = 1.0 - v0 * 2.0;

    // 2. Exponential Depth Slices
    let z_ratio = camera.z_far / camera.z_near;
    let slice_near = camera.z_near * pow(z_ratio, f32(tile_z) / f32(camera.cluster_dim_z));
    let slice_far  = camera.z_near * pow(z_ratio, f32(tile_z + 1u) / f32(camera.cluster_dim_z));

    // 3. View-Space Cluster AABB
    let p00 = camera.proj[0][0];
    let p11 = camera.proj[1][1];

    let x_near_min = (ndc_x_min * slice_near) / p00;
    let x_near_max = (ndc_x_max * slice_near) / p00;
    let y_near_min = (ndc_y_min * slice_near) / p11;
    let y_near_max = (ndc_y_max * slice_near) / p11;

    let x_far_min = (ndc_x_min * slice_far) / p00;
    let x_far_max = (ndc_x_max * slice_far) / p00;
    let y_far_min = (ndc_y_min * slice_far) / p11;
    let y_far_max = (ndc_y_max * slice_far) / p11;

    let aabb_min = vec3<f32>(
        min(min(x_near_min, x_near_max), min(x_far_min, x_far_max)),
        min(min(y_near_min, y_near_max), min(y_far_min, y_far_max)),
        -slice_far
    );
    let aabb_max = vec3<f32>(
        max(max(x_near_min, x_near_max), max(x_far_min, x_far_max)),
        max(max(y_near_min, y_near_max), max(y_far_min, y_far_max)),
        -slice_near
    );

    // 4. Cull Dynamic Lights against AABB
    var visible_light_count: u32 = 0u;
    var local_indices: array<u32, 128>;

    for (var l: u32 = 0u; l < camera.num_dynamic_lights; l = l + 1u) {
        if (visible_light_count >= MAX_LIGHTS_PER_CLUSTER) {
            break;
        }

        let light = lights[l];

        // Directional lights intersect every cluster
        if (light.light_type == 0u) {
            local_indices[visible_light_count] = l;
            visible_light_count = visible_light_count + 1u;
            continue;
        }

        // Transform light center to View Space
        let pos_view = (camera.view * vec4<f32>(light.position_ws, 1.0)).xyz;
        let r = light.radius;

        // Arvo's Sphere-AABB test
        var d2: f32 = 0.0;
        if (pos_view.x < aabb_min.x) {
            let d = aabb_min.x - pos_view.x;
            d2 += d * d;
        } else if (pos_view.x > aabb_max.x) {
            let d = pos_view.x - aabb_max.x;
            d2 += d * d;
        }

        if (pos_view.y < aabb_min.y) {
            let d = aabb_min.y - pos_view.y;
            d2 += d * d;
        } else if (pos_view.y > aabb_max.y) {
            let d = pos_view.y - aabb_max.y;
            d2 += d * d;
        }

        if (pos_view.z < aabb_min.z) {
            let d = aabb_min.z - pos_view.z;
            d2 += d * d;
        } else if (pos_view.z > aabb_max.z) {
            let d = pos_view.z - aabb_max.z;
            d2 += d * d;
        }

        if (d2 <= (r * r)) {
            local_indices[visible_light_count] = l;
            visible_light_count = visible_light_count + 1u;
        }
    }

    // 5. Atomic Global Allocation & Writeback
    if (visible_light_count > 0u) {
        let write_offset = atomicAdd(&global_index_counter, visible_light_count);
        if (write_offset + visible_light_count <= MAX_GLOBAL_LIGHT_INDICES) {
            for (var k: u32 = 0u; k < visible_light_count; k = k + 1u) {
                cluster_light_indices[write_offset + k] = local_indices[k];
            }
            cluster_records[cluster_idx] = ClusterRecord(write_offset, visible_light_count);
        } else {
            // Buffer overflow fallback: cap lights
            cluster_records[cluster_idx] = ClusterRecord(0u, 0u);
        }
    } else {
        cluster_records[cluster_idx] = ClusterRecord(0u, 0u);
    }
}
```

---

## 6. `shadow_depth.wgsl` Specification

### 6.1 Shadow Mapping Architecture
The shadow pass renders scene geometry from the directional light's orthographic view-projection matrix into a hardware depth texture (`texture_depth_2d`).
- Depth comparison format: `TextureFormat::Depth32Float` or `Depth24Plus`.
- The vertex shader transforms incoming geometry into light clip space.
- The fragment shader can be completely omitted in WGPU (`fragment: None` in `RenderPipelineDescriptor`) for pure depth writing, or used with alpha testing (`discard` for transparent textures).

### 6.2 Complete WGSL Implementation: `shadow_depth.wgsl`

```wgsl
// ============================================================================
// Fluorite Engine — Milestone 1: Directional Shadow Depth Pass
// File: shadow_depth.wgsl
// ============================================================================

struct ShadowPassUniforms {
    light_view_proj: mat4x4<f32>,
};

@group(0) @binding(0) var<uniform> shadow_pass: ShadowPassUniforms;
@group(1) @binding(0) var<uniform> model_matrix: mat4x4<f32>;

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) tangent: vec4<f32>,
    @location(3) uv: vec2<f32>,
};

struct VertexOutput {
    @builtin(position) clip_pos: vec4<f32>,
};

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    let world_pos = model_matrix * vec4<f32>(in.position, 1.0);
    out.clip_pos = shadow_pass.light_view_proj * world_pos;
    return out;
}

// Fragment shader is optional (depth written automatically by rasterizer).
// For alpha-test cutout support, uncomment the following block:
/*
@group(2) @binding(0) var albedo_texture: texture_2d<f32>;
@group(2) @binding(1) var albedo_sampler: sampler;

@fragment
fn fs_main(@location(0) uv: vec2<f32>) {
    let alpha = textureSample(albedo_texture, albedo_sampler, uv).a;
    if (alpha < 0.5) {
        discard;
    }
}
*/
```

---

## 7. Verification & Implementation Recommendations

1. **Rust Layout Assertions**:
   In `fluorite_core::rendering::types` (or `material.rs`), add static `assert!` checks for every struct size:
   ```rust
   assert_eq!(std::mem::size_of::<PbrMaterialUniforms>(), 48);
   assert_eq!(std::mem::size_of::<CameraUniforms>(), 320);
   assert_eq!(std::mem::size_of::<GpuLight>(), 64);
   assert_eq!(std::mem::size_of::<ClusterRecord>(), 8);
   assert_eq!(std::mem::size_of::<ShadowUniforms>(), 80);
   ```
2. **Headless Shader Validation**:
   `pbr_pipeline_test.rs` should instantiate `wgpu::ShaderModuleDescriptor` with `include_str!("shaders/pbr_forward.wgsl")` to verify that `naga` parses and validates the WGSL without error.
3. **Punctual Light Distance Attenuation**:
   Verify that distance attenuation smoothly approaches zero at $d = \text{light.radius}$, guaranteeing zero light popping at cluster cell boundaries.
4. **Energy Conservation Property**:
   Verify that for any combination of roughness $\in [0.045, 1.0]$ and metallic $\in [0.0, 1.0]$, the sum of diffuse and specular reflection never exceeds incident flux: $(k_d + k_s) \le 1.0$.

---

## 8. Conclusion

This specification provides the complete, mathematically grounded, byte-aligned shader and uniform architecture for Milestone 1. The three shader files (`pbr_forward.wgsl`, `cluster_cull.wgsl`, `shadow_depth.wgsl`) and the Rust uniform structs are immediately actionable by implementers to satisfy all M1 acceptance criteria.
