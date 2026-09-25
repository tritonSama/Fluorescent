# Technical Survey Report: Requirement 1 — Rendering & Graphics Core (PBR, Clustered Forward+, Directional Shadows)

**Date**: 2026-09-24  
**Author**: `teamwork_preview_explorer_survey_1`  
**Target Milestone**: Phase 2 (Wave 1) — R1  
**Authoritative Specification**: `.agents/teamwork/ORIGINAL_REQUEST.md`  

---

## 1. Executive Summary & Problem Scope

Requirement 1 mandates the implementation of a AAA-grade graphics foundation within the native Rust core (`fluorite_core` and/or `fluoderpod_render`):
1. **PBR Metallic-Roughness Rendering Pipeline**: A complete Cook-Torrance microfacet BRDF pipeline with physically based shading, texture mapping, and energy conservation.
2. **Clustered Forward+ Light Assignment**: A scalable frustum-clustered lighting architecture capable of dynamically assigning **1024+ dynamic point and spot lights** to screen-space/depth clusters with sub-millisecond execution.
3. **Directional Shadow Mapping**: High-fidelity directional depth passes with orthographic projection, texel snapping for stability, and Percentage-Closer Filtering (PCF).
4. **Acceptance Criteria Verification**: Headless, deterministic validation where `cargo test` passes in `fluorite_core`, specifically verifying PBR shader compilation, light assignment correctness, and memory layouts.

This survey provides a comprehensive audit of the existing codebase, identifies architectural gaps, and specifies mathematical formulations, GPU buffer layouts, shader designs, and an execution roadmap.

---

## 2. Codebase Discovery & Current Technical State

### 2.1 Workspace & Crate Topography

The Fluorescent repository contains a hybrid architecture divided between native Rust systems and Flutter/Dart UI/tooling:

```
c:\Users\blue-\projects\Fluorescent\
├── Cargo.toml                     [ABSENT - No root Cargo workspace currently]
├── fluorite_core/                 [Primary Rust Core Crate]
│   ├── Cargo.toml                 [v0.1.0: thiserror, serde, flutter_rust_bridge=2.13.0, bellman, rand]
│   ├── src/
│   │   ├── allocator/             [ArenaAllocator, DoubleBufferedFrameAllocator]
│   │   ├── api/                   [start_engine, allocate_engine_buffer, SharedFrameBuffer]
│   │   ├── rendering/             [renderer.rs: QualityTier enum (Tier1-Tier4), Renderer struct]
│   │   ├── servers/               [physics.rs, navigation.rs stubs]
│   │   └── frb_generated.rs       [Generated C-ABI bridge for Dart]
│   └── tests/                     [arena_test, codegen_test, engine_api_test, frame_test]
├── fluoderpod_render/             [GPU-Driven Rendering Architecture Crate]
│   ├── Cargo.toml                 [wgpu 0.20, bytemuck 1.16, ash 0.38, jni, ndk, ndk-sys, tokio]
│   └── src/
│       ├── culling/               [Compute culler stub]
│       ├── unified_pipeline/      [PipelineManager stub]
│       ├── virtual_geometry/      [Virtual geometry LOD stub]
│       ├── android_vulkan.rs      [AHardwareBuffer NDK allocation & release]
│       └── nexus_client.rs        [Telemetry & WebSocket client]
├── tests/                         [Rust Native & Dart E2E Test Suite]
│   ├── Cargo.toml                 [Self-contained test package: tier1-tier4 test binaries]
│   └── run_e2e_tests.ps1          [Automated test runner: Dart runner + Cargo test]
├── fluorite_editor/               [Flutter Desktop Editor App]
│   ├── pubspec.yaml               [flutter, flutter_rust_bridge 2.13.0]
│   └── lib/src/rust/              [Dart bindings generated from fluorite_core/src/api]
└── fluorescent/                   [Dart Monorepo managed via Melos]
    ├── packages/
    │   ├── fluorescent_core/      [RenderGraph DAG, ResourceManager, MaterialResource]
    │   ├── fluorescent_ecs/       [SparseSet contiguous Float32List transforms (16-stride)]
    │   ├── fluorescent_flame/     [FluorescentViewport, FluorescentTextureOverlay]
    │   ├── fluorescent_vulkan/    [C++ Vulkan backend, cgltf, hardcoded SPIR-V shaders]
    │   ├── fluorescent_metal/     [Swift/ObjC Metal texture bridge]
    │   └── fluorescent_webgpu/    [WebGPU canvas bridge]
    └── tools/asset_pipeline/      [NagaFfiTranspiler, DemoShaderTranspiler, fworld binary format]
```

### 2.2 Key Findings & Gaps

1. **Rendering Dependency Split**:
   - `fluoderpod_render` already includes `wgpu = "0.20"`, `bytemuck = { version = "1.16", features = ["derive"] }`, and `ash = "0.38.0"`.
   - `fluorite_core` currently only has `flutter_rust_bridge`, `serde`, and `thiserror`. It does **not** have `wgpu`, `glam`, or `naga` in its dependencies.
   - However, the authoritative acceptance criteria explicitly state:
     > `cargo test` passes in `fluorite_core` verifying PBR shader compilation...
   - Therefore, `fluorite_core` must either:
     - Directly depend on `fluoderpod_render` (`fluoderpod_render = { path = "../fluoderpod_render" }`), or
     - Add `wgpu = "0.20"`, `glam = "0.27"`, and `bytemuck` directly in `fluorite_core/Cargo.toml` so that `fluorite_core::rendering` can compile and test shaders, math, and light binning autonomously.
2. **Current Shader State**:
   - There are currently **no WGSL PBR shaders** in the codebase.
   - `fluorescent_vulkan` has hardcoded 32-bit SPIR-V hex arrays in `shaders.h` that only draw a unlit triangle.
   - `tools/asset_pipeline` has `ShaderTranspiler` with a mock `DemoShaderTranspiler` and a FFI stub for `Naga`.
3. **Current Material Model**:
   - In Dart (`fluorescent_core`), `MaterialResource` exists and holds `uniforms: Map<String, dynamic>` and `textures: Map<String, TextureResource>`.
   - In Rust, no material structs exist yet.
4. **Zero-Copy Texture Bridge**:
   - `FluorescentViewport` in Flame and `FluorescentTextureOverlay` in Flutter accept an external `textureId: int` and render it via Flutter's `Texture(textureId: textureId)` widget.
   - In `fluorite_core/src/api/engine.rs`, `start_engine` returns `EngineStatus { texture_id: Some(1), ... }`.
   - Connecting `wgpu` rendering to a shared native texture handle (or offscreen frame buffer with FFI handle) completes the zero-copy pipeline for the desktop editor.

---

## 3. Requirement 1.1: PBR Metallic-Roughness Rendering Pipeline

### 3.1 Mathematical Formulation (Cook-Torrance Microfacet BRDF)

The rendering pipeline must evaluate the standard Cook-Torrance BRDF for every surface point:

$$f_r(\mathbf{p}, \omega_i, \omega_o) = f_{\text{diffuse}} + f_{\text{specular}}$$

#### 1. Diffuse Term
Lambertian diffuse with metallic cancellation:
$$f_{\text{diffuse}} = \frac{\mathbf{c}_{\text{diff}}}{\pi}, \quad \mathbf{c}_{\text{diff}} = \text{albedo} \cdot (1.0 - \text{metallic})$$

#### 2. Specular Term (Microfacet Model)
$$f_{\text{specular}} = \frac{D(\mathbf{n}, \mathbf{h}, \alpha) \cdot G(\mathbf{n}, \mathbf{v}, \mathbf{l}, \alpha) \cdot F(\mathbf{v}, \mathbf{h}, \mathbf{F}_0)}{4 (\mathbf{n} \cdot \mathbf{v}) (\mathbf{n} \cdot \mathbf{l})}$$
where $\mathbf{h} = \frac{\mathbf{l} + \mathbf{v}}{\|\mathbf{l} + \mathbf{v}\|}$, $\alpha = \text{roughness}^2$.

#### 3. Normal Distribution Function $D$ (Trowbridge-Reitz GGX)
$$D(\mathbf{n}, \mathbf{h}, \alpha) = \frac{\alpha^2}{\pi \left( (\mathbf{n} \cdot \mathbf{h})^2 (\alpha^2 - 1) + 1 \right)^2}$$

#### 4. Geometric Shadowing-Masking $G$ (Smith GGX Correlated)
Using the correlated visibility formulation $V = \frac{G}{4(\mathbf{n}\cdot\mathbf{v})(\mathbf{n}\cdot\mathbf{l})}$ (Heitz 2014) to prevent numerical instability at grazing angles:
$$V(\mathbf{n}, \mathbf{v}, \mathbf{l}, \alpha) = \frac{0.5}{(\mathbf{n} \cdot \mathbf{l}) \sqrt{(\mathbf{n} \cdot \mathbf{v})^2(1 - \alpha^2) + \alpha^2} + (\mathbf{n} \cdot \mathbf{v}) \sqrt{(\mathbf{n} \cdot \mathbf{l})^2(1 - \alpha^2) + \alpha^2}}$$
$$f_{\text{specular}} = D(\mathbf{n}, \mathbf{h}, \alpha) \cdot V(\mathbf{n}, \mathbf{v}, \mathbf{l}, \alpha) \cdot F(\mathbf{v}, \mathbf{h}, \mathbf{F}_0)$$

#### 5. Fresnel Reflectance $F$ (Schlick Approximation)
$$F(\mathbf{v}, \mathbf{h}, \mathbf{F}_0) = \mathbf{F}_0 + (1 - \mathbf{F}_0) (1 - (\mathbf{v} \cdot \mathbf{h}))^5$$
where $\mathbf{F}_0 = \text{lerp}(0.04, \text{albedo}, \text{metallic})$.

### 3.2 Material Inputs & Texture Conventions (glTF 2.0 Compliant)

| Parameter | Type | Channel / Encoding | Description |
|---|---|---|---|
| `base_color` | `vec4<f32>` | RGBA, sRGB $\to$ Linear | Linear surface diffuse albedo and alpha |
| `metallic_roughness` | `vec2<f32>` | Linear: Green = Roughness, Blue = Metallic | Microfacet roughness $[0.04, 1.0]$ and metalness $[0.0, 1.0]$ |
| `normal_map` | `vec3<f32>` | RGB Linear $[0, 1] \to [-1, 1]$ | Tangent-space normal vector with TBN perturbation |
| `occlusion` | `f32` | Red channel in ORM texture | Baked ambient occlusion attenuation $[0.0, 1.0]$ |
| `emissive` | `vec3<f32>` | RGB sRGB $\to$ Linear | Self-illuminating radiance factor |

### 3.3 GPU Buffer Layouts (std140 / std430 Alignment)

```rust
#[repr(C)]
#[derive(Debug, Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
pub struct PbrMaterialUniforms {
    pub base_color_factor: [f32; 4], // 16 bytes: RGBA
    pub emissive_factor: [f32; 3],   // 12 bytes: RGB
    pub metallic_factor: f32,        // 4 bytes
    pub roughness_factor: f32,       // 4 bytes
    pub normal_scale: f32,           // 4 bytes
    pub occlusion_strength: f32,     // 4 bytes
    pub flags: u32,                  // 4 bytes: bitfield for has_albedo_tex, has_normal_tex, etc.
} // Total: 48 bytes (multiple of 16)

#[repr(C)]
#[derive(Debug, Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
pub struct CameraUniforms {
    pub view_proj: [[f32; 4]; 4],    // 64 bytes
    pub view: [[f32; 4]; 4],         // 64 bytes
    pub proj: [[f32; 4]; 4],         // 64 bytes
    pub inv_proj: [[f32; 4]; 4],     // 64 bytes
    pub camera_pos: [f32; 3],        // 12 bytes
    pub z_near: f32,                 // 4 bytes
    pub z_far: f32,                  // 4 bytes
    pub screen_width: f32,           // 4 bytes
    pub screen_height: f32,          // 4 bytes
    pub cluster_dim_x: u32,          // 4 bytes (e.g. 16)
    pub cluster_dim_y: u32,          // 4 bytes (e.g. 9)
    pub cluster_dim_z: u32,          // 4 bytes (e.g. 24)
    pub num_dynamic_lights: u32,     // 4 bytes (e.g. 1024)
    pub ambient_light: [f32; 4],     // 16 bytes: RGB intensity + padding
} // Total: 320 bytes (multiple of 16)
```

---

## 4. Requirement 1.2: Clustered Forward+ Light Assignment (1024+ Lights)

### 4.1 Cluster Grid Division Architecture

In standard Forward rendering, each draw call must loop through all scene lights ($O(M \times L)$). Tiled Forward+ partitions the 2D screen into $16 \times 16$ tiles, but suffers from severe depth discontinuities. 

**Clustered Forward+** partitions the viewing frustum into a 3D grid of sub-frusta (clusters) in view space:
- **Grid Configuration**:
  - $N_x = 16$ (horizontal screen tiles)
  - $N_y = 9$ (vertical screen tiles)
  - $N_z = 24$ (exponential depth slices)
  - **Total Clusters**: $16 \times 9 \times 24 = 3,456$ clusters.

### 4.2 Depth Slicing Formulation (Logarithmic / Exponential)

Linear depth slicing places too many clusters in distant, empty space. Exponential depth slicing concentrates clusters near the near plane where spatial density is highest:

For a fragment at view-space depth $z_v = -(\mathbf{V} \cdot \mathbf{p}_w)_z > 0$:

$$i_z = \min\left( \left\lfloor \frac{\ln(z_v / z_{\text{near}})}{\ln(z_{\text{far}} / z_{\text{near}})} \cdot N_z \right\rfloor, N_z - 1 \right)$$

Screen-space tile coordinate:
$$i_x = \min\left( \left\lfloor \frac{\text{frag\_coord}.x}{\text{screen\_width}} \cdot N_x \right\rfloor, N_x - 1 \right)$$
$$i_y = \min\left( \left\lfloor \frac{\text{frag\_coord}.y}{\text{screen\_height}} \cdot N_y \right\rfloor, N_y - 1 \right)$$

1D Cluster Index:
$$\text{cluster\_index} = i_x + i_y \cdot N_x + i_z \cdot (N_x \cdot N_y)$$

### 4.3 GPU Buffer Layout for 1024+ Dynamic Lights

```rust
#[repr(C)]
#[derive(Debug, Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
pub struct GpuLight {
    pub position_ws: [f32; 3],       // 12 bytes
    pub radius: f32,                 // 4 bytes: attenuation reach (sphere radius)
    pub color: [f32; 3],             // 12 bytes: RGB linear radiant intensity
    pub intensity: f32,              // 4 bytes: lumens / candela multiplier
    pub direction_ws: [f32; 3],      // 12 bytes: spot / directional vector
    pub light_type: u32,             // 4 bytes: 0 = Directional, 1 = Point, 2 = Spot
    pub inner_cone_cos: f32,         // 4 bytes: cos(inner_angle) for spot lights
    pub outer_cone_cos: f32,         // 4 bytes: cos(outer_angle) for spot lights
    pub shadow_map_index: i32,       // 4 bytes: -1 if unshadowed
    pub _padding: u32,               // 4 bytes: 16-byte alignment
} // Total: 64 bytes per light.
// 1024 lights = 65,536 bytes (64 KB). Fits directly in storage buffer or uniform buffer.

#[repr(C)]
#[derive(Debug, Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
pub struct ClusterRecord {
    pub offset: u32,                 // Starting index in GlobalLightIndexList
    pub count: u32,                  // Number of active lights intersecting this cluster
} // Total: 8 bytes per cluster.
// 3,456 clusters = 27,648 bytes (27 KB).
```

### 4.4 Light Assignment Pipeline (Compute & CPU Dual-Path)

To satisfy both high-throughput GPU rendering and deterministic headless CI testing:

```text
┌─────────────────────────────────────────────────────────────┐
│ 1024+ Scene Dynamic Lights (Positions, Radii, Cones)        │
└──────────────┬──────────────────────────────┬───────────────┘
               │                              │
     [GPU Execution Path]            [CPU Fallback / Test Path]
               │                              │
 ┌─────────────▼──────────────┐  ┌────────────▼──────────────┐
 │ Pass 1: Cluster AABB Gen   │  │ Pure-Rust Light Assigner  │
 │ Compute shader calculates  │  │ Bins lights into clusters │
 │ view-space AABBs           │  │ using SIMD/rayon or linear│
 └─────────────┬──────────────┘  │ tests without GPU context │
               │                 └────────────┬──────────────┘
 ┌─────────────▼──────────────┐               │
 │ Pass 2: Light Binning      │               │
 │ 1 thread per cluster.      │               │
 │ Sphere-AABB & Cone-AABB    │               │
 │ intersections recorded via │               │
 │ atomic counter             │               │
 └─────────────┬──────────────┘               │
               │                              │
               └──────────────┬───────────────┘
                              │
               ┌──────────────▼──────────────┐
               │ PBR Fragment Shader         │
               │ Computes cluster_idx, loops │
               │ only over assigned lights!  │
               └─────────────────────────────┘
```

1. **Sphere-AABB Intersection Test** (Point Lights):
   Distance from sphere center $\mathbf{c}$ to view-space cluster AABB $[\mathbf{b}_{\min}, \mathbf{b}_{\max}]$:
   $$d^2 = \sum_{i \in \{x,y,z\}} \left( \max(0, b_{\min, i} - c_i)^2 + \max(0, c_i - b_{\max, i})^2 \right)$$
   Intersection occurs if $d^2 \le r^2$.
2. **Cone-AABB Intersection Test** (Spot Lights):
   Sphere cull first; if sphere passes, test cone axis dot product against AABB corners.

---

## 5. Requirement 1.3: Directional Shadow Mapping

### 5.1 Orthographic Projection & Cascades

Directional light sources (sun/moon) require orthographic projections:
1. **Light View Matrix**:
   $\mathbf{V}_L = \text{look\_at}(\mathbf{p}_{\text{target}} - \mathbf{d} \cdot d_{\text{dist}}, \mathbf{p}_{\text{target}}, \mathbf{u})$
2. **Light Orthographic Projection**:
   $\mathbf{P}_L = \text{ortho}(x_{\min}, x_{\max}, y_{\min}, y_{\max}, z_{\text{near}}, z_{\text{far}})$
   For the primary directional shadow map, bounds are tightly fitted around the camera's viewing frustum.
3. **Texel Snapping (Eliminating Shadow Swimming)**:
   As the camera moves, shadows crawl and shimmer if the shadow matrix origin shifts by fractions of a shadow map texel.
   $$\text{world\_units\_per\_texel} = \frac{2 \cdot \text{ortho\_extent}}{\text{shadow\_map\_resolution}}$$
   $$\mathbf{p}_{\text{snapped}} = \left\lfloor \frac{\mathbf{p}_{\text{light}}}{\text{texel\_size}} \right\rfloor \cdot \text{texel\_size}$$
   Rebuilding the light view matrix with $\mathbf{p}_{\text{snapped}}$ locks the texel raster grid in world space.

### 5.2 Percentage-Closer Filtering (PCF)

Fragment shading samples the depth texture using hardware comparison samplers:
```wgsl
@group(2) @binding(0) var shadow_map: texture_depth_2d;
@group(2) @binding(1) var shadow_sampler: sampler_comparison;

fn sample_directional_shadow(shadow_coord: vec4<f32>, n_dot_l: f32) -> f32 {
    let proj = shadow_coord.xyz / shadow_coord.w;
    // Map NDC [-1, 1] to UV [0, 1]
    let uv = vec2<f32>(proj.x * 0.5 + 0.5, -proj.y * 0.5 + 0.5);
    let depth = proj.z;
    
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || depth > 1.0) {
        return 1.0;
    }
    
    // Slope-scaled depth bias to eliminate acne and shadow acne
    let bias = max(0.005 * (1.0 - n_dot_l), 0.001);
    let current_depth = depth - bias;
    
    // 3x3 PCF Kernel
    let texel_size = 1.0 / vec2<f32>(textureDimensions(shadow_map));
    var shadow: f32 = 0.0;
    for (var x = -1; x <= 1; x++) {
        for (var y = -1; y <= 1; y++) {
            let offset = vec2<f32>(f32(x), f32(y)) * texel_size;
            shadow += textureSampleCompare(shadow_map, shadow_sampler, uv + offset, current_depth);
        }
    }
    return shadow / 9.0;
}
```

---

## 6. Concrete WGSL Shader Architecture

The PBR pipeline is driven by three cohesive WGSL shader modules:

### 6.1 `pbr_forward.wgsl` (Main Forward+ Pass)
- **Vertex Stage**:
  - Inputs: `position: vec3<f32>`, `normal: vec3<f32>`, `tangent: vec4<f32>`, `uv: vec2<f32>`.
  - Computes world-space position, normal, tangent, bitangent ($B = \text{cross}(N, T) \times T.w$).
  - Outputs `clip_position` and view-space depth for cluster selection.
- **Fragment Stage**:
  - Samples material textures (Albedo, Normal, Metallic-Roughness, AO, Emissive).
  - Calculates view-space cluster index $(i_x, i_y, i_z)$ from `frag_coord` and view depth.
  - Fetches `ClusterRecord` from cluster storage buffer.
  - Loops over cluster's lights, evaluates Cook-Torrance BRDF for each light.
  - Samples directional shadow map with PCF and modulates directional sunlight.
  - Applies ambient lighting + emissive radiance.
  - Applies ACES tonemapping and writes RGBA linear output.

### 6.2 `cluster_cull.wgsl` (Light Binning Compute Pass)
- Workgroup size: `@workgroup_size(16, 1, 1)`.
- Input: Cluster grid configuration, Camera inverse projection, 1024+ `GpuLight` array.
- Output: `ClusterRecord` array, `GlobalLightIndices` array, atomic light counter.

### 6.3 `shadow_depth.wgsl` (Directional Shadow Pass)
- Vertex-only shader projecting geometry into light view-projection space.
- No color output; writes depth buffer directly.

---

## 7. Testing Infrastructure & Acceptance Criteria Verification

### 7.1 Existing Test Harness (`run_e2e_tests.ps1`)
The repository uses `tests/run_e2e_tests.ps1` as the single-command runner:
1. Runs `dart run tests/e2e_runner.dart` (51 Dart tests).
2. Runs `cargo test --manifest-path tests/Cargo.toml` (Tier 1-4 Rust tests).
3. `fluorite_core` has integration tests in `fluorite_core/tests/`:
   - `arena_test.rs`
   - `codegen_test.rs`
   - `engine_api_test.rs`
   - `frame_test.rs`
   - `adversarial_challenge_test.rs`

### 7.2 Headless Verification of Requirement 1

To fulfill the acceptance criteria:
> `cargo test` passes in `fluorite_core` verifying PBR shader compilation...

We introduce a dedicated integration test in `fluorite_core/tests/pbr_pipeline_test.rs`:
1. **PBR Shader Compilation Test**:
   - Uses `wgpu::ShaderModuleDescriptor` or `naga::front::wgsl::parse_str` to validate `pbr_forward.wgsl`, `cluster_cull.wgsl`, and `shadow_depth.wgsl`.
   - Ensures zero syntax errors, valid bind group interfaces, and verified SPIR-V translation headlessly without needing physical GPU hardware.
2. **Clustered Forward+ Light Assignment Test**:
   - Spawns 1024 dynamic point and spot lights distributed across a $100 \times 100 \times 100$ scene.
   - Executes the CPU light assignment algorithm.
   - Asserts:
     - Clusters distant from lights have count == 0.
     - Clusters containing lights contain the exact expected light IDs.
     - Total assigned light count does not overflow index buffer.
     - Execution completes in <1.0ms for 1024 lights.
3. **Directional Shadow Projection & PCF Test**:
   - Verifies orthographic bounding box fits camera frustum corners.
   - Verifies texel snapping yields identical matrix when camera translates by $<1$ texel.
   - Verifies PCF kernel weights sum to 1.0.
4. **Cook-Torrance BRDF Energy Conservation Test**:
   - Validates that $f_r \cdot (\mathbf{n} \cdot \mathbf{l}) \le 1.0$ across the full range of roughness $[0.05, 1.0]$ and metallic $[0.0, 1.0]$.
   - Validates that metallic $= 1.0$ produces zero diffuse contribution.

---

## 8. Implementation Roadmap & Subtask Breakdown

```
Requirement 1 Implementation Plan
│
├── Step 1: Crate & Dependency Setup
│   ├── Update `fluorite_core/Cargo.toml` to add `wgpu = "0.20"`, `glam = "0.27"`, `bytemuck = "1.16"`
│   └── (Optional) Link `fluoderpod_render = { path = "../fluoderpod_render" }`
│
├── Step 2: WGSL Shader Toolchain & Shader Source Files
│   ├── Create `fluorite_core/src/rendering/shaders/pbr_forward.wgsl`
│   ├── Create `fluorite_core/src/rendering/shaders/cluster_cull.wgsl`
│   └── Create `fluorite_core/src/rendering/shaders/shadow_depth.wgsl`
│
├── Step 3: PBR Materials & Buffer Layouts
│   ├── Implement `PbrMaterialUniforms`, `CameraUniforms`, `GpuLight`, `ClusterRecord` in Rust
│   └── Provide bytemuck zero-copy conversions and default presets
│
├── Step 4: Clustered Forward+ Light Assigners
│   ├── Implement compute-based light culler (`cluster_cull.wgsl`)
│   └── Implement pure-Rust CPU light assigner (`ClusterLightGrid`) for headless CI & testing
│
├── Step 5: Directional Shadow Mapping System
│   ├── Implement `DirectionalShadowMap` (render pass, orthographic camera, texel snapping)
│   └── Integrate comparison sampler and PCF kernel into fragment pass
│
├── Step 6: Pipeline Integration & Quality Tier Hooks
│   ├── Expose `ForwardPlusRenderer` in `fluorite_core::rendering`
│   └── Hook into `QualityTier` (Tier 1 disables shadows/reduces clusters; Tier 4 enables 5x5 PCF and full clusters)
│
└── Step 7: Headless Unit & Integration Tests
    ├── Add `fluorite_core/tests/pbr_pipeline_test.rs`
    ├── Verify `cargo test --manifest-path fluorite_core/Cargo.toml`
    └── Verify E2E runner compatibility
```

---

## 9. Conclusion

Requirement 1 is architecturally sound and directly buildable on top of `wgpu 0.20` and `fluorite_core`. By incorporating both GPU compute shaders and a mirrored CPU light binning module, the engine achieves AAA rendering capability while remaining 100% testable in headless CI environments.
