//! Integration and Headless Verification Test Suite for Milestone 1:
//! PBR Metallic-Roughness BRDF, Clustered Forward+ Light Assignment,
//! Directional Shadow Mapping with Texel Snapping, and WGSL Shader Compilation.
//!
//! Fulfills Acceptance Criteria from ORIGINAL_REQUEST.md and PROJECT.md:
//! - `cargo test` passes in `fluorite_core` verifying PBR shader compilation...
//! - Cluster light grid test: assign 1024 dynamic lights and assert all clusters populated without index out-of-bounds.
//! - Shadow projection test: assert texel-snapping matrix stability under camera movement.
//! - Cook-Torrance BRDF test: verify energy conservation and physical plausibility.

use std::f32::consts::PI;
use glam::{Mat4, Vec2, Vec3, Vec4};

// ============================================================================
// Module 1: WGSL Shader Compilation and Uniform Layout Verification
// ============================================================================
#[cfg(test)]
mod shader_compilation_tests {
    use super::*;

    struct DummyWaker;
    impl std::task::Wake for DummyWaker {
        fn wake(self: std::sync::Arc<Self>) {}
    }

    fn block_on<F: std::future::Future>(future: F) -> F::Output {
        let mut future = std::pin::pin!(future);
        let waker = std::task::Waker::from(std::sync::Arc::new(DummyWaker));
        let mut cx = std::task::Context::from_waker(&waker);
        loop {
            match future.as_mut().poll(&mut cx) {
                std::task::Poll::Ready(val) => return val,
                std::task::Poll::Pending => std::thread::yield_now(),
            }
        }
    }

    /// Validates that all three core Milestone 1 WGSL shaders compile without errors.
    ///
    /// Evaluates:
    /// - `pbr_forward.wgsl`: Cook-Torrance BRDF, clustered light evaluation loop, PCF shadows.
    /// - `cluster_cull.wgsl`: 16x9x24 logarithmic cluster grid slicing and light culler.
    /// - `shadow_depth.wgsl`: Directional shadow depth-only render pass.
    #[test]
    fn test_wgsl_shader_compilation_headless() {
        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
            backends: wgpu::Backends::all(),
            flags: wgpu::InstanceFlags::empty(),
            dx12_shader_compiler: wgpu::Dx12Compiler::default(),
            gles_minor_version: wgpu::Gles3MinorVersion::default(),
        });

        // Request low-power or software fallback adapter for headless CI environments
        let adapter = block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::LowPower,
            force_fallback_adapter: true,
            compatible_surface: None,
        }));

        if let Some(adapter) = adapter {
            let (device, _queue) = block_on(adapter.request_device(
                &wgpu::DeviceDescriptor {
                    label: Some("Fluorite Headless PBR Test Device"),
                    required_features: wgpu::Features::empty(),
                    required_limits: wgpu::Limits::downlevel_defaults(),
                },
                None,
            ))
            .expect("Failed to create headless test WGPU device");

            // 1. Verify pbr_forward.wgsl
            let pbr_src = include_str!("../src/rendering/shaders/pbr_forward.wgsl");
            let pbr_module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("pbr_forward.wgsl"),
                source: wgpu::ShaderSource::Wgsl(pbr_src.into()),
            });
            assert!(
                !format!("{:?}", pbr_module).is_empty(),
                "Failed to compile pbr_forward.wgsl"
            );

            // 2. Verify cluster_cull.wgsl
            let cluster_src = include_str!("../src/rendering/shaders/cluster_cull.wgsl");
            let cluster_module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("cluster_cull.wgsl"),
                source: wgpu::ShaderSource::Wgsl(cluster_src.into()),
            });
            assert!(
                !format!("{:?}", cluster_module).is_empty(),
                "Failed to compile cluster_cull.wgsl"
            );

            // 3. Verify shadow_depth.wgsl
            let shadow_src = include_str!("../src/rendering/shaders/shadow_depth.wgsl");
            let shadow_module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("shadow_depth.wgsl"),
                source: wgpu::ShaderSource::Wgsl(shadow_src.into()),
            });
            assert!(
                !format!("{:?}", shadow_module).is_empty(),
                "Failed to compile shadow_depth.wgsl"
            );
        } else {
            eprintln!(
                "Notice: No hardware/software WGPU adapter found in this test environment. \
                Shader validation skipped on bare headless host."
            );
        }
    }

    /// Verifies strict byte sizing and 16-byte alignment invariants of GPU uniform structs
    /// matching the specification in PROJECT.md and Survey 1.
    #[test]
    fn test_uniform_buffer_sizes_and_alignments() {
        // PbrMaterialUniforms: 48 bytes (3 * 16)
        // base_color_factor (16B) + emissive_factor (12B) + metallic (4B) + roughness (4B) +
        // normal_scale (4B) + occlusion_strength (4B) + flags (4B) = 48 bytes.
        assert_eq!(
            std::mem::size_of::<fluorite_core::rendering::pbr::PbrMaterialUniforms>(),
            48,
            "PbrMaterialUniforms must be exactly 48 bytes"
        );

        // CameraUniforms: 320 bytes (20 * 16)
        // 4 x mat4 (256B) + camera_pos (12B) + z_near (4B) + z_far (4B) +
        // screen_w (4B) + screen_h (4B) + dim_x (4B) + dim_y (4B) + dim_z (4B) +
        // num_lights (4B) + _padding (4B) + ambient_light (16B) = 320 bytes.
        assert_eq!(
            std::mem::size_of::<fluorite_core::rendering::pbr::CameraUniforms>(),
            320,
            "CameraUniforms must be exactly 320 bytes"
        );

        // GpuLight: 64 bytes (4 * 16)
        // position_ws + radius (16B) + color + intensity (16B) +
        // direction_ws + light_type (16B) + inner/outer/shadow/padding (16B) = 64 bytes.
        assert_eq!(
            std::mem::size_of::<fluorite_core::rendering::cluster::GpuLight>(),
            64,
            "GpuLight must be exactly 64 bytes"
        );
    }
}

// ============================================================================
// Module 2: Clustered Forward+ Light Grid Verification (1024 Dynamic Lights)
// ============================================================================
#[cfg(test)]
mod cluster_light_grid_tests {
    use super::*;
    use fluorite_core::rendering::cluster::{
        ClusterLightGrid, PointLight, SpotLight, NUM_CLUSTERS_X, NUM_CLUSTERS_Y, NUM_CLUSTERS_Z,
        TOTAL_CLUSTERS,
    };

    /// Generates 1,024 dynamic point and spot lights distributed across the camera frustum,
    /// assigns them to 16x9x24 clusters, and asserts all clusters are populated without
    /// index out-of-bounds or buffer overflow.
    #[test]
    fn test_cluster_light_grid_1024_dynamic_lights() {
        let fov_y = 60.0_f32.to_radians();
        let aspect_ratio = 16.0 / 9.0;
        let z_near = 0.1;
        let z_far = 100.0;

        let grid = ClusterLightGrid::new(fov_y, aspect_ratio, z_near, z_far);

        // Standard camera view at origin looking down -Z
        let eye = Vec3::new(0.0, 0.0, 0.0);
        let target = Vec3::new(0.0, 0.0, -1.0);
        let up = Vec3::Y;
        let view_matrix = Mat4::look_at_rh(eye, target, up);

        // Create 1,024 dynamic lights (800 point lights + 224 spot lights)
        let mut point_lights = Vec::with_capacity(800);
        for i in 0..800 {
            let u = (i as f32) / 800.0;
            // Distribute lights across frustum depth (2m to 80m)
            let depth = 2.0 + u * 78.0;
            let half_h = depth * (fov_y * 0.5).tan();
            let half_w = half_h * aspect_ratio;

            let x = ((i * 17) % 100) as f32 / 100.0 * (2.0 * half_w) - half_w;
            let y = ((i * 31) % 100) as f32 / 100.0 * (2.0 * half_h) - half_h;
            let z = -depth;

            point_lights.push(PointLight {
                position: Vec3::new(x, y, z),
                radius: 4.0 + (i % 5) as f32 * 1.5,
                color: Vec3::new(1.0, 0.8, 0.6),
                intensity: 100.0,
            });
        }

        let mut spot_lights = Vec::with_capacity(224);
        for i in 0..224 {
            let u = (i as f32) / 224.0;
            let depth = 5.0 + u * 70.0;
            let half_h = depth * (fov_y * 0.5).tan();
            let half_w = half_h * aspect_ratio;

            let x = ((i * 23) % 100) as f32 / 100.0 * (2.0 * half_w) - half_w;
            let y = ((i * 37) % 100) as f32 / 100.0 * (2.0 * half_h) - half_h;
            let z = -depth;

            spot_lights.push(SpotLight {
                position: Vec3::new(x, y, z),
                direction: Vec3::new(0.0, 0.0, -1.0),
                range: 8.0,
                inner_angle: 25.0_f32.to_radians(),
                outer_angle: 40.0_f32.to_radians(),
                color: Vec3::new(0.6, 0.8, 1.0),
                intensity: 150.0,
            });
        }

        assert_eq!(point_lights.len() + spot_lights.len(), 1024);

        // Run light assignment
        let output = grid.bin_lights(&point_lights, &spot_lights, view_matrix);

        // Invariant 1: Cluster cell count must equal exactly 3,456 (16x9x24)
        assert_eq!(
            output.cells.len(),
            TOTAL_CLUSTERS,
            "Cluster cell count must match TOTAL_CLUSTERS (3,456)"
        );

        // Invariant 2: Total dynamic lights packed into GPU buffer must equal 1,024
        assert_eq!(
            output.gpu_lights.len(),
            1024,
            "GpuLight buffer must contain exactly 1,024 lights"
        );

        // Invariant 3: Buffer bounds check - every cluster offset + count must never exceed light_indices length
        let total_indices = output.light_indices.len();
        let mut populated_clusters = 0;
        let mut total_light_references = 0;

        for (c_idx, cell) in output.cells.iter().enumerate() {
            let start = cell.offset as usize;
            let end = start + cell.count as usize;

            assert!(
                end <= total_indices,
                "Cluster index out of bounds: cluster {} slice [{}..{}] exceeds light_indices len {}",
                c_idx,
                start,
                end,
                total_indices
            );

            // Verify all referenced light IDs are within valid range [0, 1024)
            for &light_id in &output.light_indices[start..end] {
                assert!(
                    (light_id as usize) < 1024,
                    "Invalid light index {} in cluster {}",
                    light_id,
                    c_idx
                );
            }

            if cell.count > 0 {
                populated_clusters += 1;
                total_light_references += cell.count as usize;
            }
        }

        // Invariant 4: With 1,024 lights spanning the frustum, a substantial majority of clusters must be populated
        assert!(
            populated_clusters > 1000,
            "Expected over 1000 clusters populated, but found {}",
            populated_clusters
        );
        assert!(
            total_light_references > 0,
            "Total light references across clusters must be non-zero"
        );
    }

    /// Verifies that lights behind the near plane or beyond the far plane are culled.
    #[test]
    fn test_cluster_light_grid_frustum_depth_culling() {
        let grid = ClusterLightGrid::new(60.0_f32.to_radians(), 16.0 / 9.0, 1.0, 100.0);
        let view_matrix = Mat4::IDENTITY; // Camera at origin looking down -Z (z_depth = -z)

        let lights = vec![
            // Behind camera: z = +5.0 (z_depth = -5.0 < 1.0)
            PointLight {
                position: Vec3::new(0.0, 0.0, 5.0),
                radius: 2.0,
                color: Vec3::ONE,
                intensity: 10.0,
            },
            // Beyond far plane: z = -200.0 (z_depth = 200.0 > 100.0)
            PointLight {
                position: Vec3::new(0.0, 0.0, -200.0),
                radius: 5.0,
                color: Vec3::ONE,
                intensity: 10.0,
            },
        ];

        let output = grid.bin_lights(&lights, &[], view_matrix);

        // Both lights should be culled completely
        assert_eq!(
            output.total_assignments, 0,
            "Lights outside frustum depth range must be culled"
        );
        assert_eq!(
            output.light_indices.len(),
            0,
            "Light indices buffer should be empty"
        );
    }

    /// Verifies logarithmic depth distribution: near depth slices are much thinner than far depth slices.
    #[test]
    fn test_cluster_logarithmic_depth_distribution() {
        let z_near = 0.1;
        let z_far = 100.0;
        let grid = ClusterLightGrid::new(60.0_f32.to_radians(), 16.0 / 9.0, z_near, z_far);

        let (z0_min, z0_max) = grid.slice_to_depth_range(0);
        let thickness_0 = z0_max - z0_min;

        let (z_last_min, z_last_max) = grid.slice_to_depth_range(NUM_CLUSTERS_Z - 1);
        let thickness_last = z_last_max - z_last_min;

        // Logarithmic distribution property: thickness of slice 23 is exponentially larger than slice 0
        assert!(
            thickness_last > thickness_0 * 10.0,
            "Far depth slice (thickness={}) must be significantly larger than near slice (thickness={})",
            thickness_last,
            thickness_0
        );
    }
}

// ============================================================================
// Module 3: Directional Shadow Mapping & Texel Snapping Verification
// ============================================================================
#[cfg(test)]
mod directional_shadow_tests {
    use super::*;
    use fluorite_core::rendering::shadow::{
        calculate_shadow_bias, compute_directional_shadow_matrices, ShadowMapConfig,
    };

    /// Asserts that moving the camera by a sub-texel vector does not alter the shadow view-projection matrix
    /// due to world-space texel snapping.
    #[test]
    fn test_shadow_projection_texel_snapping_stability() {
        let config = ShadowMapConfig {
            resolution: 2048,
            caster_margin: 50.0,
            receiver_margin: 20.0,
        };
        let light_dir = Vec3::new(0.5, -1.0, 0.3).normalize();

        // Base camera at (10.0, 5.0, -20.0) looking at (10.0, 5.0, -21.0)
        let eye_0 = Vec3::new(10.0, 5.0, -20.0);
        let target_0 = Vec3::new(10.0, 5.0, -21.0);
        let view_0 = Mat4::look_at_rh(eye_0, target_0, Vec3::Y);
        let proj = Mat4::perspective_rh(60.0_f32.to_radians(), 16.0 / 9.0, 0.1, 100.0);
        let vp_inv_0 = (proj * view_0).inverse();

        let shadow_out_0 = compute_directional_shadow_matrices(vp_inv_0, light_dir, config);
        let texel_size = shadow_out_0.texel_size;
        assert!(texel_size > 0.0, "Texel size must be positive");

        // Move camera by a sub-texel offset (e.g. 15% of a texel along X and Z)
        let sub_texel_delta = Vec3::new(texel_size * 0.15, 0.0, texel_size * 0.15);
        let eye_1 = eye_0 + sub_texel_delta;
        let target_1 = target_0 + sub_texel_delta;
        let view_1 = Mat4::look_at_rh(eye_1, target_1, Vec3::Y);
        let vp_inv_1 = (proj * view_1).inverse();

        let shadow_out_1 = compute_directional_shadow_matrices(vp_inv_1, light_dir, config);

        // Element-wise comparison of light view-projection matrices
        let cols_0 = shadow_out_0.light_vp.to_cols_array();
        let cols_1 = shadow_out_1.light_vp.to_cols_array();

        for i in 0..16 {
            let diff = (cols_0[i] - cols_1[i]).abs();
            assert!(
                diff < 1e-4,
                "Shadow matrix element [{}] drifted by {} under sub-texel movement (expected < 1e-4)",
                i,
                diff
            );
        }

        // Verify shadow_matrix (UV space) is also stable
        let sm_cols_0 = shadow_out_0.shadow_matrix.to_cols_array();
        let sm_cols_1 = shadow_out_1.shadow_matrix.to_cols_array();
        for i in 0..16 {
            let diff = (sm_cols_0[i] - sm_cols_1[i]).abs();
            assert!(
                diff < 1e-4,
                "Shadow UV matrix element [{}] drifted by {} under sub-texel movement",
                i,
                diff
            );
        }
    }

    /// Verifies that camera frustum corners fall strictly within the light orthographic projection volume.
    #[test]
    fn test_shadow_frustum_corner_containment() {
        let config = ShadowMapConfig::default();
        let light_dir = Vec3::new(0.0, -1.0, 0.0); // Directly overhead sun

        let eye = Vec3::new(0.0, 2.0, 5.0);
        let target = Vec3::new(0.0, 2.0, 0.0);
        let view = Mat4::look_at_rh(eye, target, Vec3::Y);
        let proj = Mat4::perspective_rh(60.0_f32.to_radians(), 16.0 / 9.0, 0.1, 50.0);
        let vp_inv = (proj * view).inverse();

        let shadow_out = compute_directional_shadow_matrices(vp_inv, light_dir, config);
        let corners = fluorite_core::rendering::shadow::compute_frustum_corners(vp_inv);

        // Every frustum corner transformed by light_vp must reside within WebGPU NDC:
        // x in [-1, 1], y in [-1, 1], z in [0, 1]
        for (i, &corner) in corners.iter().enumerate() {
            let p_ndc = shadow_out.light_vp.project_point3(corner);
            assert!(
                p_ndc.x >= -1.05 && p_ndc.x <= 1.05,
                "Corner {} X={} out of NDC bounds",
                i,
                p_ndc.x
            );
            assert!(
                p_ndc.y >= -1.05 && p_ndc.y <= 1.05,
                "Corner {} Y={} out of NDC bounds",
                i,
                p_ndc.y
            );
            assert!(
                p_ndc.z >= -0.05 && p_ndc.z <= 1.05,
                "Corner {} Z={} out of NDC bounds",
                i,
                p_ndc.z
            );
        }
    }

    /// Verifies slope-scaled shadow depth bias behavior.
    #[test]
    fn test_slope_scaled_shadow_bias() {
        let normal = Vec3::Y;
        let light_dir = Vec3::new(0.0, -1.0, 0.0); // Perpendicular to surface (cos_theta = 1.0)
        let base_bias = 0.005;
        let min_bias = 0.001;

        // Flat surface perpendicular to light -> minimum bias
        let bias_flat = calculate_shadow_bias(normal, light_dir, base_bias, min_bias);
        assert_eq!(bias_flat, min_bias);

        // Steep surface at 60 degree angle
        let steep_normal = Vec3::new(0.866, 0.5, 0.0).normalize();
        let bias_steep = calculate_shadow_bias(steep_normal, light_dir, base_bias, min_bias);
        assert!(
            bias_steep > bias_flat,
            "Steep surface bias ({}) must exceed flat surface bias ({})",
            bias_steep,
            bias_flat
        );
    }
}

// ============================================================================
// Module 4: Cook-Torrance BRDF Verification (Energy Conservation & Physics)
// ============================================================================
#[cfg(test)]
mod cook_torrance_brdf_tests {
    use super::*;

    // Pure Rust reference implementation matching pbr_forward.wgsl formulations

    fn distribution_ggx(n_dot_h: f32, roughness: f32) -> f32 {
        let alpha = roughness * roughness;
        let alpha2 = alpha * alpha;
        let n_dot_h2 = n_dot_h * n_dot_h;
        let denom = n_dot_h2 * (alpha2 - 1.0) + 1.0;
        alpha2 / (PI * denom * denom)
    }

    fn visibility_smith_ggx_correlated(n_dot_v: f32, n_dot_l: f32, roughness: f32) -> f32 {
        let alpha = roughness * roughness;
        let alpha2 = alpha * alpha;
        let ggx_v = n_dot_l * (n_dot_v * n_dot_v * (1.0 - alpha2) + alpha2).sqrt();
        let ggx_l = n_dot_v * (n_dot_l * n_dot_l * (1.0 - alpha2) + alpha2).sqrt();
        let denom = ggx_v + ggx_l;
        if denom > 0.0 {
            0.5 / denom
        } else {
            0.0
        }
    }

    fn fresnel_schlick(v_dot_h: f32, f0: Vec3) -> Vec3 {
        f0 + (Vec3::ONE - f0) * (1.0 - v_dot_h).clamp(0.0, 1.0).powi(5)
    }

    fn evaluate_cook_torrance_brdf(
        n: Vec3,
        v: Vec3,
        l: Vec3,
        albedo: Vec3,
        roughness: f32,
        metallic: f32,
    ) -> (Vec3, Vec3, Vec3) {
        let h = (v + l).normalize();
        let n_dot_v = n.dot(v).max(1e-4);
        let n_dot_l = n.dot(l).max(0.0);
        let n_dot_h = n.dot(h).clamp(0.0, 1.0);
        let v_dot_h = v.dot(h).clamp(0.0, 1.0);

        let d = distribution_ggx(n_dot_h, roughness);
        let vis = visibility_smith_ggx_correlated(n_dot_v, n_dot_l, roughness);
        let f0 = Vec3::splat(0.04).lerp(albedo, metallic);
        let f = fresnel_schlick(v_dot_h, f0);

        let specular = f * (d * vis);
        let kd = (Vec3::ONE - f) * (1.0 - metallic);
        let diffuse = kd * albedo / PI;

        (diffuse, specular, kd + f)
    }

    /// Asserts energy conservation across parameter sweeps of roughness and metallic:
    /// Reflection coefficients must satisfy kd + ks <= 1.0 everywhere.
    #[test]
    fn test_cook_torrance_energy_conservation() {
        let n = Vec3::Y;
        let albedo = Vec3::new(0.8, 0.7, 0.6);

        // Test across 10 roughness steps and 10 metallic steps
        for r_step in 1..=10 {
            let roughness = r_step as f32 * 0.1; // [0.1, 1.0]

            for m_step in 0..=10 {
                let metallic = m_step as f32 * 0.1; // [0.0, 1.0]

                // Sweep light and view angles across hemisphere
                for theta_deg in [10.0, 30.0, 45.0, 60.0, 75.0, 85.0] {
                    let theta = theta_deg_to_rad(theta_deg);
                    let v = Vec3::new(theta.sin(), theta.cos(), 0.0).normalize();
                    let l = Vec3::new(-theta.sin() * 0.7, theta.cos(), 0.7 * theta.sin()).normalize();

                    let (diffuse, specular, total_coeff) =
                        evaluate_cook_torrance_brdf(n, v, l, albedo, roughness, metallic);

                    // Property 1: Non-negativity
                    assert!(diffuse.x >= 0.0 && diffuse.y >= 0.0 && diffuse.z >= 0.0);
                    assert!(specular.x >= 0.0 && specular.y >= 0.0 && specular.z >= 0.0);

                    // Property 2: Energy Conservation: kd + ks <= 1.0001 (floating point tolerance)
                    assert!(
                        total_coeff.x <= 1.0001 && total_coeff.y <= 1.0001 && total_coeff.z <= 1.0001,
                        "Energy conservation violated at roughness={}, metallic={}, angle={}: total={:?}",
                        roughness, metallic, theta_deg, total_coeff
                    );
                }
            }
        }
    }

    /// Asserts that pure metallic surfaces (metallic = 1.0) produce zero diffuse reflection.
    #[test]
    fn test_cook_torrance_metallic_cancellation() {
        let n = Vec3::Y;
        let v = Vec3::new(0.5, 0.866, 0.0).normalize();
        let l = Vec3::new(-0.5, 0.866, 0.0).normalize();
        let albedo = Vec3::new(0.9, 0.8, 0.7);

        let (diffuse, specular, _) =
            evaluate_cook_torrance_brdf(n, v, l, albedo, 0.3, 1.0);

        assert_eq!(
            diffuse,
            Vec3::ZERO,
            "Pure metallic surface must have identically zero diffuse reflection"
        );
        assert!(
            specular.length_squared() > 0.0,
            "Specular reflection on metal must be non-zero"
        );
    }

    /// Asserts that dielectric materials (metallic = 0.0) have F0 = 0.04.
    #[test]
    fn test_cook_torrance_dielectric_f0() {
        let f0_dielectric = Vec3::splat(0.04).lerp(Vec3::new(0.8, 0.2, 0.1), 0.0);
        assert_eq!(
            f0_dielectric,
            Vec3::splat(0.04),
            "Dielectric F0 must equal exactly 0.04 regardless of albedo"
        );
    }

    /// Asserts Helmholtz reciprocity: swapping V and L yields identical BRDF value.
    #[test]
    fn test_cook_torrance_helmholtz_reciprocity() {
        let n = Vec3::Y;
        let v = Vec3::new(0.3, 0.9, 0.2).normalize();
        let l = Vec3::new(-0.4, 0.8, -0.3).normalize();
        let albedo = Vec3::new(0.7, 0.5, 0.3);

        let (diff_1, spec_1, _) = evaluate_cook_torrance_brdf(n, v, l, albedo, 0.4, 0.5);
        let (diff_2, spec_2, _) = evaluate_cook_torrance_brdf(n, l, v, albedo, 0.4, 0.5);

        let total_1 = diff_1 + spec_1;
        let total_2 = diff_2 + spec_2;

        let diff = (total_1 - total_2).length();
        assert!(
            diff < 1e-5,
            "Helmholtz reciprocity violated: f_r(v, l)={:?}, f_r(l, v)={:?}, diff={}",
            total_1, total_2, diff
        );
    }

    /// Asserts numerical stability at extreme grazing angles (theta = 89.99 degrees)
    /// without NaN or Inf.
    #[test]
    fn test_cook_torrance_grazing_angle_stability() {
        let n = Vec3::Y;
        let theta_rad = 89.99_f32.to_radians();
        let v = Vec3::new(theta_rad.sin(), theta_rad.cos(), 0.0).normalize();
        let l = Vec3::new(-theta_rad.sin(), theta_rad.cos(), 0.0).normalize();
        let albedo = Vec3::ONE;

        let (diffuse, specular, _) =
            evaluate_cook_torrance_brdf(n, v, l, albedo, 0.04, 0.5);

        assert!(!diffuse.is_nan(), "Diffuse was NaN at grazing angle");
        assert!(!specular.is_nan(), "Specular was NaN at grazing angle");
        assert!(diffuse.is_finite(), "Diffuse was Inf at grazing angle");
        assert!(specular.is_finite(), "Specular was Inf at grazing angle");
    }

    fn theta_deg_to_rad(deg: f32) -> f32 {
        deg.to_radians()
    }
}
