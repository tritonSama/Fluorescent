# Handoff Report: Survey 1 — Rendering & Graphics Core (Requirement 1)

**Agent**: `teamwork_preview_explorer_survey_1`  
**Working Directory**: `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_survey_1\`  
**Target Milestone**: Phase 2 (Wave 1) — R1  
**Report Document**: `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_survey_1\report.md`  

---

## 1. Observation

1. **Crate Configurations**:
   - `fluorite_core/Cargo.toml` lines 12-18:
     ```toml
     [dependencies]
     thiserror = "1.0"
     serde = { version = "1.0", features = ["derive"] }
     flutter_rust_bridge = "=2.13.0"
     execution-rail = { path = "../third_party/tithX/nexus-core/execution-rail" }
     mobile-vault-sdk = { path = "../third_party/tithX/nexus-core/mobile-vault-sdk" }
     ```
     `fluorite_core` lacks `wgpu`, `bytemuck`, `glam`, and `naga`.
   - `fluoderpod_render/Cargo.toml` lines 13-24:
     ```toml
     [dependencies]
     wgpu = "0.20"
     bytemuck = { version = "1.16", features = ["derive"] }
     log = "0.4"
     tokio = { version = "1.30.0", features = ["full"] }
     tokio-tungstenite = "0.20.0"
     futures-util = "0.3.28"
     serde = { version = "1.0.180", features = ["derive"] }
     serde_json = "1.0.100"
     jni = "0.22.4"
     ndk = "0.9.0"
     ndk-sys = "0.6.0"
     ash = "0.38.0"
     ```
     `fluoderpod_render` already depends on `wgpu = "0.20"`, `bytemuck = "1.16"`, and `ash = "0.38.0"`.

2. **Existing Rendering Modules**:
   - `fluorite_core/src/rendering/renderer.rs` lines 4-14:
     ```rust
     pub enum QualityTier {
         Tier1,
         Tier2,
         Tier3,
         Tier4,
     }
     ```
     Contains only `QualityTier` and stub `Renderer { tier: QualityTier }`.
   - `fluoderpod_render/src/unified_pipeline/mod.rs` lines 3-5:
     ```rust
     pub struct PipelineManager {
         // Abstracted WGPU Device and Queue
     }
     ```
     Contains stubs for `update_entity_buffer` and `submit_indirect_draws`.
   - `fluoderpod_render/src/culling/mod.rs` lines 3-5:
     ```rust
     pub struct ComputeCuller {
         // Defines bindings to the compute shader, HZB textures, etc.
     }
     ```
     Contains stubs for `dispatch_frustum_culling` and `dispatch_occlusion_culling`.

3. **Shader Infrastructure**:
   - `fluorescent/packages/fluorescent_vulkan/src/shaders.h` contains hardcoded SPIR-V words for a basic unlit triangle (`VERTEX_SHADER` 32 words, `FRAGMENT_SHADER` 47 words).
   - `fluorescent/tools/asset_pipeline/lib/shader_toolchain/demo_transpiler.dart` provides demo SPIR-V bytecode generation with magic `0x07230203`.
   - There are currently **no WGSL PBR shaders** or lighting compute shaders anywhere in the codebase.

4. **Acceptance Criteria & Test Framework**:
   - `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\ORIGINAL_REQUEST.md` lines 30-31:
     ```markdown
     ### Verification
     - [ ] `cargo test` passes in `fluorite_core` verifying PBR shader compilation, BVH raycasting, and Rapier physics stepping.
     ```
   - `fluorite_core/tests/` contains integration tests (`arena_test.rs`, `codegen_test.rs`, `engine_api_test.rs`, `frame_test.rs`, `adversarial_challenge_test.rs`), which run via `cargo test --manifest-path fluorite_core/Cargo.toml`.
   - `tests/run_e2e_tests.ps1` executes both `dart run tests/e2e_runner.dart` and `cargo test --manifest-path tests/Cargo.toml`.

---

## 2. Logic Chain

1. **Target Crate Alignment**:
   - The authoritative acceptance criteria state: "`cargo test` passes in `fluorite_core` verifying PBR shader compilation...".
   - From Observation 1, `fluorite_core` currently does not depend on `wgpu` or `naga`.
   - From Observation 1, `fluoderpod_render` already depends on `wgpu = "0.20"`.
   - Therefore, to ensure `cargo test` in `fluorite_core` can compile and verify PBR shaders headlessly:
     - `fluorite_core/Cargo.toml` must add `wgpu = "0.20"`, `bytemuck = { version = "1.16", features = ["derive"] }`, and `glam = "0.27"`, and/or reference `fluoderpod_render = { path = "../fluoderpod_render" }`.

2. **PBR Metallic-Roughness Pipeline Design**:
   - Real-time AAA rendering requires Cook-Torrance microfacet BRDF: Trowbridge-Reitz GGX normal distribution $D$, Smith GGX correlated shadowing-masking $V$, and Schlick Fresnel approximation $F$.
   - Material parameters require glTF 2.0 compatibility: Albedo (sRGB), Metallic-Roughness (Linear green/blue), Tangent-space Normal, AO (red), and Emissive.
   - Buffer layouts (`PbrMaterialUniforms` 48 bytes, `CameraUniforms` 320 bytes) align to 16 bytes for std140/std430 compatibility with `bytemuck`.

3. **Clustered Forward+ Light Assignment (1024+ Lights)**:
   - Forward rendering with 1024 dynamic lights causes excessive fragment shader loops ($O(M \times L)$). Tiled Forward+ suffers from depth discontinuity over-allocation.
   - Clustered Forward+ divides the view frustum into $16 \times 9 \times 24 = 3,456$ clusters with logarithmic/exponential depth slicing ($z_{\text{slice}} \propto \ln(z_v / z_{\text{near}})$).
   - Buffer layout: `GpuLight` (64 bytes aligned; 1024 lights = 64 KB storage buffer), `ClusterRecord` (offset, count: 8 bytes per cluster), `GlobalLightIndices` flattened buffer, and an atomic counter.
   - To ensure deterministic headless testability in CI where physical GPUs are unavailable, the engine requires a dual-path architecture:
     - GPU Compute Shader (`cluster_cull.wgsl`) for high-throughput runtime execution.
     - Pure-Rust CPU Light Assigner (`ClusterLightGrid`) in `fluorite_core::rendering::lights` for headless CI validation in `cargo test`.

4. **Directional Shadow Mapping**:
   - Directional light sources require an orthographic projection tightly bounded to the camera frustum corners.
   - To eliminate shadow shimmering/swimming during camera motion, light projection coordinates must snap to the world texel grid ($\mathbf{p}_{\text{snapped}} = \lfloor \mathbf{p} / \Delta_{\text{texel}} \rfloor \cdot \Delta_{\text{texel}}$).
   - Percentage-Closer Filtering (PCF) with $3 \times 3$ kernel and slope-scaled depth bias ($\text{bias} = \max(0.005(1 - \mathbf{n}\cdot\mathbf{l}), 0.001)$) eliminates shadow acne.

5. **Test Strategy**:
   - Implementing `fluorite_core/tests/pbr_pipeline_test.rs` will validate WGSL shader compilation via `wgpu::ShaderModuleDescriptor`, test 1024 dynamic lights in the cluster grid, test shadow projection matrix stability, and verify Cook-Torrance BRDF energy conservation.

---

## 3. Caveats

- **No Caveats on Architecture**: The mathematical formulation and buffer layouts for Cook-Torrance BRDF, Clustered Forward+, and PCF Directional Shadows are standard, proven AAA techniques.
- **Hardware Context in CI**: Standard CI environments often lack physical Vulkan/Metal GPU hardware. The design explicitly decouples shader parsing/validation and algorithmic light binning so that `cargo test` runs 100% headless using `wgpu` validation and pure-Rust test harnesses.

---

## 4. Conclusion

Requirement 1 is thoroughly analyzed and mapped to concrete, actionable deliverables:
1. **Dependencies**: Add `wgpu = "0.20"`, `bytemuck = { version = "1.16", features = ["derive"] }`, and `glam = "0.27"` to `fluorite_core/Cargo.toml`.
2. **Shaders**: Implement `pbr_forward.wgsl` (Cook-Torrance fragment pass), `cluster_cull.wgsl` (light assignment compute pass), and `shadow_depth.wgsl` (directional depth pass).
3. **Data Structures**: Implement `PbrMaterialUniforms`, `CameraUniforms`, `GpuLight` (64B), and `ClusterRecord` in `fluorite_core::rendering`.
4. **Light Assigner**: Implement both the WGSL compute pass and the pure-Rust `ClusterLightGrid` CPU assigner.
5. **Shadows**: Implement orthographic directional shadow pass with texel snapping and 3x3 PCF.
6. **Verification**: Implement `fluorite_core/tests/pbr_pipeline_test.rs` to satisfy the acceptance criterion: `cargo test passes in fluorite_core verifying PBR shader compilation...`.

---

## 5. Verification Method

1. **Inspect Report**:
   - Read `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_survey_1\report.md` for full mathematical equations, buffer structs, WGSL snippets, and execution roadmap.
2. **Inspect Existing Crate Files**:
   - Check `fluorite_core/Cargo.toml` and `fluoderpod_render/Cargo.toml`.
   - Check `fluorite_core/src/rendering/renderer.rs`.
3. **Execution Command (Post-Implementation)**:
   - `cargo test --manifest-path fluorite_core/Cargo.toml` to verify PBR shader compilation and light binning tests.
   - `powershell -ExecutionPolicy Bypass -File .\tests\run_e2e_tests.ps1` to verify workspace-wide integration.
4. **Invalidation Conditions**:
   - If the team decides `fluorite_core` must not depend on `wgpu`, all shader compilation tests must be performed via `naga` directly in `fluorite_core` or delegated via FFI to `fluoderpod_render`.
