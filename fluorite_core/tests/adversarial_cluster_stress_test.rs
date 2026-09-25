//! Adversarial Stress Test Suite for Clustered Forward+ Light Grid (`ClusterLightGrid`)
//! Authored by: teamwork_preview_challenger_m1_1 (Empirical Challenger)
//!
//! Evaluates the robustness, boundary conditions, invariant preservation,
//! and GPU memory layout parity of `fluorite_core::rendering::cluster::ClusterLightGrid`.

use glam::{Mat4, Vec3};
use fluorite_core::rendering::cluster::{
    ClusterLightGrid, GpuLight, PointLight, SpotLight,
    NUM_CLUSTERS_X, NUM_CLUSTERS_Y, NUM_CLUSTERS_Z, TOTAL_CLUSTERS,
};

/// Validates the core invariant for all 3,456 cluster cells:
/// `cell.offset + cell.count <= output.light_indices.len()`
/// and every referenced index is strictly within `[0, total_lights)`.
fn validate_cluster_grid_invariants(
    grid: &ClusterLightGrid,
    point_lights: &[PointLight],
    spot_lights: &[SpotLight],
    view_matrix: Mat4,
) {
    let total_lights = point_lights.len() + spot_lights.len();
    let output = grid.bin_lights(point_lights, spot_lights, view_matrix);

    assert_eq!(
        output.cells.len(),
        TOTAL_CLUSTERS,
        "Cluster cell count must be exactly TOTAL_CLUSTERS (3,456)"
    );
    assert_eq!(
        output.gpu_lights.len(),
        total_lights,
        "GPU lights buffer count must match input light count"
    );

    let total_indices = output.light_indices.len();
    let mut calculated_total_assignments = 0;
    let mut observed_max_lights = 0;

    for (c_idx, cell) in output.cells.iter().enumerate() {
        let start = cell.offset as usize;
        let count = cell.count as usize;
        let end = start + count;

        // Invariant: offset + count <= light_indices.len()
        assert!(
            end <= total_indices,
            "Cluster {} offset ({}) + count ({}) = {} exceeds total light_indices ({})",
            c_idx,
            start,
            count,
            end,
            total_indices
        );

        observed_max_lights = observed_max_lights.max(cell.count);
        calculated_total_assignments += count;

        // Verify index valid range
        for &light_id in &output.light_indices[start..end] {
            assert!(
                (light_id as usize) < total_lights,
                "Cluster {} references out-of-bounds light_id {} (total_lights = {})",
                c_idx,
                light_id,
                total_lights
            );
        }
    }

    assert_eq!(
        output.total_assignments, calculated_total_assignments,
        "Reported total_assignments must match sum of all cell counts"
    );
    assert_eq!(
        output.max_lights_per_cluster, observed_max_lights,
        "Reported max_lights_per_cluster must match highest observed cell count"
    );
}

// ============================================================================
// Stress Dimension 1: Pathological Dynamic Light Counts (0, 1, 1024, 2048, 4096, 10000)
// ============================================================================

#[test]
fn test_adversarial_light_counts_0_lights() {
    let grid = ClusterLightGrid::new(1.0, 16.0 / 9.0, 0.1, 100.0);
    let view_matrix = Mat4::IDENTITY;

    let output = grid.bin_lights(&[], &[], view_matrix);

    assert_eq!(output.cells.len(), TOTAL_CLUSTERS);
    assert_eq!(output.light_indices.len(), 0);
    assert_eq!(output.gpu_lights.len(), 0);
    assert_eq!(output.max_lights_per_cluster, 0);
    assert_eq!(output.total_assignments, 0);

    for (c_idx, cell) in output.cells.iter().enumerate() {
        assert_eq!(cell.offset, 0, "Cluster {} offset must be 0", c_idx);
        assert_eq!(cell.count, 0, "Cluster {} count must be 0", c_idx);
    }
}

#[test]
fn test_adversarial_light_counts_1_light() {
    let grid = ClusterLightGrid::new(1.0, 16.0 / 9.0, 0.1, 100.0);
    let view_matrix = Mat4::IDENTITY;

    let point_lights = vec![PointLight {
        position: Vec3::new(0.0, 0.0, -10.0),
        radius: 2.0,
        color: Vec3::ONE,
        intensity: 50.0,
    }];

    validate_cluster_grid_invariants(&grid, &point_lights, &[], view_matrix);
}

#[test]
fn test_adversarial_light_counts_1024_lights() {
    let grid = ClusterLightGrid::new(1.0, 16.0 / 9.0, 0.1, 100.0);
    let view_matrix = Mat4::IDENTITY;

    let mut point_lights = Vec::with_capacity(1024);
    for i in 0..1024 {
        let fi = i as f32;
        point_lights.push(PointLight {
            position: Vec3::new(
                (fi * 1.7).sin() * 20.0,
                (fi * 2.3).cos() * 12.0,
                -((fi % 90.0) + 1.0),
            ),
            radius: 3.0 + (fi % 4.0),
            color: Vec3::new(1.0, 0.9, 0.8),
            intensity: 100.0,
        });
    }

    validate_cluster_grid_invariants(&grid, &point_lights, &[], view_matrix);
}

#[test]
fn test_adversarial_light_counts_2048_lights() {
    let grid = ClusterLightGrid::new(1.0, 16.0 / 9.0, 0.1, 100.0);
    let view_matrix = Mat4::IDENTITY;

    let mut point_lights = Vec::with_capacity(1500);
    for i in 0..1500 {
        let fi = i as f32;
        point_lights.push(PointLight {
            position: Vec3::new(
                (fi * 3.1).sin() * 25.0,
                (fi * 1.9).cos() * 15.0,
                -((fi % 95.0) + 0.5),
            ),
            radius: 2.5 + (fi % 3.0),
            color: Vec3::new(0.9, 0.8, 1.0),
            intensity: 80.0,
        });
    }

    let mut spot_lights = Vec::with_capacity(548);
    for i in 0..548 {
        let fi = i as f32;
        spot_lights.push(SpotLight {
            position: Vec3::new(
                (fi * 2.7).cos() * 20.0,
                (fi * 4.1).sin() * 10.0,
                -((fi % 80.0) + 5.0),
            ),
            direction: Vec3::new(0.0, 0.0, -1.0),
            range: 6.0,
            inner_angle: 0.3,
            outer_angle: 0.6,
            color: Vec3::new(1.0, 1.0, 0.5),
            intensity: 120.0,
        });
    }

    assert_eq!(point_lights.len() + spot_lights.len(), 2048);
    validate_cluster_grid_invariants(&grid, &point_lights, &spot_lights, view_matrix);
}

#[test]
fn test_adversarial_light_counts_4096_lights() {
    let grid = ClusterLightGrid::new(1.0, 16.0 / 9.0, 0.1, 100.0);
    let view_matrix = Mat4::IDENTITY;

    let mut point_lights = Vec::with_capacity(3096);
    for i in 0..3096 {
        let fi = i as f32;
        point_lights.push(PointLight {
            position: Vec3::new(
                (fi * 0.73).sin() * 30.0,
                (fi * 1.13).cos() * 20.0,
                -((fi % 98.0) + 0.2),
            ),
            radius: 2.0 + (fi % 3.0),
            color: Vec3::ONE,
            intensity: 50.0,
        });
    }

    let mut spot_lights = Vec::with_capacity(1000);
    for i in 0..1000 {
        let fi = i as f32;
        spot_lights.push(SpotLight {
            position: Vec3::new(
                (fi * 1.37).cos() * 25.0,
                (fi * 0.89).sin() * 15.0,
                -((fi % 85.0) + 2.0),
            ),
            direction: Vec3::new(0.0, -0.707, -0.707).normalize(),
            range: 5.0,
            inner_angle: 0.25,
            outer_angle: 0.55,
            color: Vec3::new(0.7, 0.9, 1.0),
            intensity: 90.0,
        });
    }

    assert_eq!(point_lights.len() + spot_lights.len(), 4096);
    validate_cluster_grid_invariants(&grid, &point_lights, &spot_lights, view_matrix);
}

#[test]
fn test_adversarial_light_counts_10000_lights() {
    let grid = ClusterLightGrid::new(1.0, 16.0 / 9.0, 0.1, 100.0);
    let view_matrix = Mat4::IDENTITY;

    let mut point_lights = Vec::with_capacity(10000);
    for i in 0..10000 {
        let fi = i as f32;
        point_lights.push(PointLight {
            position: Vec3::new(
                (fi * 0.41).sin() * 40.0,
                (fi * 0.67).cos() * 25.0,
                -((fi % 99.0) + 0.15),
            ),
            radius: 1.5,
            color: Vec3::ONE,
            intensity: 30.0,
        });
    }

    validate_cluster_grid_invariants(&grid, &point_lights, &[], view_matrix);
}

// ============================================================================
// Stress Dimension 2: Pathological Coordinates and Boundary Conditions
// ============================================================================

#[test]
fn test_adversarial_boundary_exact_near_and_far_planes() {
    let z_near = 0.1;
    let z_far = 100.0;
    let grid = ClusterLightGrid::new(1.0, 16.0 / 9.0, z_near, z_far);
    let view_matrix = Mat4::IDENTITY;

    let boundary_lights = vec![
        // Exactly on near plane (z_depth = 0.1)
        PointLight {
            position: Vec3::new(0.0, 0.0, -z_near),
            radius: 0.05,
            color: Vec3::ONE,
            intensity: 10.0,
        },
        // Exactly on far plane (z_depth = 100.0)
        PointLight {
            position: Vec3::new(0.0, 0.0, -z_far),
            radius: 1.0,
            color: Vec3::ONE,
            intensity: 10.0,
        },
        // Near plane with 0 radius
        PointLight {
            position: Vec3::new(0.0, 0.0, -z_near),
            radius: 0.0,
            color: Vec3::ONE,
            intensity: 10.0,
        },
        // Far plane with 0 radius
        PointLight {
            position: Vec3::new(0.0, 0.0, -z_far),
            radius: 0.0,
            color: Vec3::ONE,
            intensity: 10.0,
        },
    ];

    validate_cluster_grid_invariants(&grid, &boundary_lights, &[], view_matrix);
}

#[test]
fn test_adversarial_boundary_all_cluster_slice_boundaries() {
    let z_near = 0.1;
    let z_far = 100.0;
    let grid = ClusterLightGrid::new(1.0, 16.0 / 9.0, z_near, z_far);
    let view_matrix = Mat4::IDENTITY;

    let mut lights = Vec::new();

    // Place a light exactly at the z_min boundary of every single slice
    for slice in 0..NUM_CLUSTERS_Z {
        let (z_min, _) = grid.slice_to_depth_range(slice);
        lights.push(PointLight {
            position: Vec3::new(0.0, 0.0, -z_min),
            radius: 0.1,
            color: Vec3::ONE,
            intensity: 10.0,
        });
    }

    validate_cluster_grid_invariants(&grid, &lights, &[], view_matrix);
}

// ============================================================================
// Stress Dimension 3: Zero and Negative Radius Handling
// ============================================================================

#[test]
fn test_adversarial_zero_radius_lights() {
    let grid = ClusterLightGrid::new(1.0, 16.0 / 9.0, 0.1, 100.0);
    let view_matrix = Mat4::IDENTITY;

    let lights = vec![
        PointLight {
            position: Vec3::new(0.0, 0.0, -5.0),
            radius: 0.0,
            color: Vec3::ONE,
            intensity: 50.0,
        },
        PointLight {
            position: Vec3::new(2.0, 1.0, -20.0),
            radius: 0.0,
            color: Vec3::ONE,
            intensity: 50.0,
        },
    ];

    let spot_lights = vec![
        SpotLight {
            position: Vec3::new(0.0, 0.0, -10.0),
            direction: Vec3::new(0.0, 0.0, -1.0),
            range: 0.0,
            inner_angle: 0.3,
            outer_angle: 0.5,
            color: Vec3::ONE,
            intensity: 50.0,
        },
    ];

    validate_cluster_grid_invariants(&grid, &lights, &spot_lights, view_matrix);
}

#[test]
fn test_adversarial_negative_radius_lights() {
    let grid = ClusterLightGrid::new(1.0, 16.0 / 9.0, 0.1, 100.0);
    let view_matrix = Mat4::IDENTITY;

    // Negative radius lights must not panic, trigger out-of-bounds, or violate invariants
    let lights = vec![
        PointLight {
            position: Vec3::new(0.0, 0.0, -5.0),
            radius: -5.0, // Large negative radius
            color: Vec3::ONE,
            intensity: 50.0,
        },
        PointLight {
            position: Vec3::new(0.0, 0.0, -10.0),
            radius: -0.00001, // Micro negative radius (same slice)
            color: Vec3::ONE,
            intensity: 50.0,
        },
        PointLight {
            position: Vec3::new(0.0, 0.0, -50.0),
            radius: -100.0,
            color: Vec3::ONE,
            intensity: 50.0,
        },
    ];

    let spot_lights = vec![
        SpotLight {
            position: Vec3::new(0.0, 0.0, -15.0),
            direction: Vec3::new(0.0, 0.0, -1.0),
            range: -10.0,
            inner_angle: 0.3,
            outer_angle: 0.5,
            color: Vec3::ONE,
            intensity: 50.0,
        },
    ];

    validate_cluster_grid_invariants(&grid, &lights, &spot_lights, view_matrix);
}

// ============================================================================
// Stress Dimension 4: Lights Behind Near Plane and Beyond Far Plane
// ============================================================================

#[test]
fn test_adversarial_lights_behind_near_plane_and_camera() {
    let z_near = 1.0;
    let z_far = 100.0;
    let grid = ClusterLightGrid::new(1.0, 16.0 / 9.0, z_near, z_far);
    let view_matrix = Mat4::IDENTITY;

    let lights = vec![
        // 1. Far behind camera: z = +100.0 (z_depth = -100.0), radius = 5.0 (does not reach near plane)
        PointLight {
            position: Vec3::new(0.0, 0.0, 100.0),
            radius: 5.0,
            color: Vec3::ONE,
            intensity: 10.0,
        },
        // 2. Just behind camera: z = +0.5 (z_depth = -0.5), radius = 0.2 (does not reach near plane 1.0)
        PointLight {
            position: Vec3::new(0.0, 0.0, 0.5),
            radius: 0.2,
            color: Vec3::ONE,
            intensity: 10.0,
        },
        // 3. Between camera and near plane: z = -0.5 (z_depth = 0.5), radius = 0.2 (does not reach near plane 1.0)
        PointLight {
            position: Vec3::new(0.0, 0.0, -0.5),
            radius: 0.2,
            color: Vec3::ONE,
            intensity: 10.0,
        },
        // 4. Behind near plane but sphere PENETRATES near plane into frustum:
        // z = -0.5 (z_depth = 0.5), radius = 2.0 (reaches depth 2.5 > z_near 1.0)
        PointLight {
            position: Vec3::new(0.0, 0.0, -0.5),
            radius: 2.0,
            color: Vec3::ONE,
            intensity: 10.0,
        },
    ];

    let output = grid.bin_lights(&lights, &[], view_matrix);

    // Lights 1, 2, 3 must be completely culled (0 assignments).
    // Light 4 must be assigned to the near clusters it penetrates.
    for &light_id in &output.light_indices {
        assert_eq!(
            light_id, 3,
            "Only light 4 (index 3) penetrates the near plane; lights 0, 1, 2 must be culled"
        );
    }

    validate_cluster_grid_invariants(&grid, &lights, &[], view_matrix);
}

#[test]
fn test_adversarial_lights_beyond_far_plane() {
    let z_near = 1.0;
    let z_far = 100.0;
    let grid = ClusterLightGrid::new(1.0, 16.0 / 9.0, z_near, z_far);
    let view_matrix = Mat4::IDENTITY;

    let lights = vec![
        // 1. Far beyond far plane: z = -200.0 (z_depth = 200.0), radius = 10.0 (does not reach far plane 100.0)
        PointLight {
            position: Vec3::new(0.0, 0.0, -200.0),
            radius: 10.0,
            color: Vec3::ONE,
            intensity: 10.0,
        },
        // 2. Beyond far plane but penetrates back: z = -105.0 (z_depth = 105.0), radius = 10.0 (reaches 95.0 < 100.0)
        PointLight {
            position: Vec3::new(0.0, 0.0, -105.0),
            radius: 10.0,
            color: Vec3::ONE,
            intensity: 10.0,
        },
    ];

    let output = grid.bin_lights(&lights, &[], view_matrix);

    for &light_id in &output.light_indices {
        assert_eq!(
            light_id, 1,
            "Only light 2 (index 1) penetrates into frustum; light 0 must be culled"
        );
    }

    validate_cluster_grid_invariants(&grid, &lights, &[], view_matrix);
}

// ============================================================================
// Stress Dimension 5: Pathological Floating Point Values (NaN, Inf)
// ============================================================================

#[test]
fn test_adversarial_nan_and_inf_inputs() {
    let grid = ClusterLightGrid::new(1.0, 16.0 / 9.0, 0.1, 100.0);
    let view_matrix = Mat4::IDENTITY;

    let lights = vec![
        // NaN position
        PointLight {
            position: Vec3::new(f32::NAN, 0.0, -10.0),
            radius: 5.0,
            color: Vec3::ONE,
            intensity: 10.0,
        },
        // NaN radius
        PointLight {
            position: Vec3::new(0.0, 0.0, -10.0),
            radius: f32::NAN,
            color: Vec3::ONE,
            intensity: 10.0,
        },
        // Inf position
        PointLight {
            position: Vec3::new(f32::INFINITY, 0.0, -10.0),
            radius: 5.0,
            color: Vec3::ONE,
            intensity: 10.0,
        },
    ];

    // Must not panic or cause memory safety violation
    validate_cluster_grid_invariants(&grid, &lights, &[], view_matrix);
}

// ============================================================================
// Stress Dimension 6: Memory Layout Parity (Rust GpuLight vs WGSL GpuLight)
// ============================================================================

/// Adversarially probes the byte layout discrepancy between `cluster.rs::GpuLight`
/// and the WGSL struct definition in `pbr_forward.wgsl` and `cluster_cull.wgsl`.
#[test]
fn test_adversarial_gpu_light_layout_parity_investigation() {
    assert_eq!(
        std::mem::size_of::<GpuLight>(),
        64,
        "Total size must be 64 bytes"
    );

    // In WGSL:
    // struct GpuLight {
    //     position_ws: vec3<f32>,   // offset 0..12
    //     radius: f32,              // offset 12..16
    //     color: vec3<f32>,         // offset 16..28
    //     intensity: f32,           // offset 28..32
    //     direction_ws: vec3<f32>,  // offset 32..44
    //     light_type: u32,          // offset 44..48 (0 = Dir, 1 = Point, 2 = Spot)
    //     inner_cone_cos: f32,      // offset 48..52
    //     outer_cone_cos: f32,      // offset 52..56
    //     shadow_map_index: i32,    // offset 56..60
    //     _padding: u32,            // offset 60..64
    // };

    // Create a PointLight and a SpotLight via bin_lights
    let grid = ClusterLightGrid::new(1.0, 16.0 / 9.0, 0.1, 100.0);
    let point_light = PointLight {
        position: Vec3::new(1.0, 2.0, -3.0),
        radius: 4.0,
        color: Vec3::new(1.0, 0.5, 0.25),
        intensity: 100.0,
    };
    let spot_light = SpotLight {
        position: Vec3::new(4.0, 5.0, -6.0),
        direction: Vec3::new(0.0, 0.0, -1.0),
        range: 8.0,
        inner_angle: 0.3,
        outer_angle: 0.6,
        color: Vec3::new(0.2, 0.4, 0.8),
        intensity: 150.0,
    };

    let output = grid.bin_lights(&[point_light], &[spot_light], Mat4::IDENTITY);
    let point_gpu = output.gpu_lights[0];
    let spot_gpu = output.gpu_lights[1];

    let point_bytes: [u8; 64] = bytemuck::cast(point_gpu);
    let spot_bytes: [u8; 64] = bytemuck::cast(spot_gpu);

    // Read byte offset 44..48 as u32 (what WGSL reads as light_type)
    let point_offset_44_u32 = u32::from_ne_bytes(point_bytes[44..48].try_into().unwrap());
    let spot_offset_44_u32 = u32::from_ne_bytes(spot_bytes[44..48].try_into().unwrap());

    // Verify field offsets match WGSL std430 alignment exactly
    assert_eq!(core::mem::offset_of!(GpuLight, position_ws), 0);
    assert_eq!(core::mem::offset_of!(GpuLight, radius), 12);
    assert_eq!(core::mem::offset_of!(GpuLight, color), 16);
    assert_eq!(core::mem::offset_of!(GpuLight, intensity), 28);
    assert_eq!(core::mem::offset_of!(GpuLight, direction_ws), 32);
    assert_eq!(core::mem::offset_of!(GpuLight, light_type), 44);
    assert_eq!(core::mem::offset_of!(GpuLight, inner_cone_cos), 48);
    assert_eq!(core::mem::offset_of!(GpuLight, outer_cone_cos), 52);
    assert_eq!(core::mem::offset_of!(GpuLight, shadow_map_index), 56);
    assert_eq!(core::mem::offset_of!(GpuLight, _padding), 60);

    // Verify byte values match WGSL expectation:
    // Point light: light_type = 1u (Point)
    assert_eq!(
        point_offset_44_u32, 1,
        "Point light must have light_type 1u at byte offset 44"
    );
    assert_eq!(point_gpu.light_type, 1);
    assert_eq!(point_gpu.radius, 4.0);
    assert_eq!(point_gpu.inner_cone_cos, 1.0);
    assert_eq!(point_gpu.outer_cone_cos, 1.0);

    // Spot light: light_type = 2u (Spot)
    assert_eq!(
        spot_offset_44_u32, 2,
        "Spot light must have light_type 2u at byte offset 44"
    );
    assert_eq!(spot_gpu.light_type, 2);
    assert_eq!(spot_gpu.radius, 8.0);
    assert!((spot_gpu.inner_cone_cos - 0.3_f32.cos()).abs() < 1e-6);
    assert!((spot_gpu.outer_cone_cos - 0.6_f32.cos()).abs() < 1e-6);
}
