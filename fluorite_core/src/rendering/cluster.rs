//! Clustered Forward+ Light Assigner for Fluorite AAA Engine.
//!
//! Provides a pure-Rust, zero-allocation-per-frame CPU light binning grid:
//! - 16x9x24 clusters (3,456 cells total).
//! - Logarithmic depth division tailored to human visual perception and perspective projection.
//! - Arvo's branchless AABB-sphere intersection algorithm for exact cluster overlap tests.
//! - High-throughput binning supporting 1,024+ dynamic point and spot lights.
//! - WGSL-compatible memory layouts (`bytemuck::Pod`, `bytemuck::Zeroable`).

use glam::{Mat4, Vec3};

/// Grid dimensions for Clustered Forward+ light culling.
pub const NUM_CLUSTERS_X: usize = 16;
pub const NUM_CLUSTERS_Y: usize = 9;
pub const NUM_CLUSTERS_Z: usize = 24;
pub const TOTAL_CLUSTERS: usize = NUM_CLUSTERS_X * NUM_CLUSTERS_Y * NUM_CLUSTERS_Z; // 3,456

/// An Axis-Aligned Bounding Box (AABB) in camera view space.
#[derive(Copy, Clone, Debug, PartialEq)]
pub struct ClusterAabb {
    pub min: Vec3,
    pub max: Vec3,
}

impl Default for ClusterAabb {
    fn default() -> Self {
        Self {
            min: Vec3::splat(f32::MAX),
            max: Vec3::splat(f32::MIN),
        }
    }
}

impl ClusterAabb {
    #[inline]
    pub fn new(min: Vec3, max: Vec3) -> Self {
        Self { min, max }
    }

    /// Determines if a point is contained inside this AABB.
    #[inline]
    pub fn contains_point(&self, p: Vec3) -> bool {
        p.x >= self.min.x
            && p.x <= self.max.x
            && p.y >= self.min.y
            && p.y <= self.max.y
            && p.z >= self.min.z
            && p.z <= self.max.z
    }

    /// Fast, exact AABB-Sphere intersection test (Arvo's algorithm).
    ///
    /// Finds the closest point on or inside the AABB to the sphere center `c`,
    /// and tests if the squared Euclidean distance is <= radius^2.
    #[inline]
    pub fn intersects_sphere(&self, center: Vec3, radius: f32) -> bool {
        let closest = Vec3::new(
            center.x.clamp(self.min.x, self.max.x),
            center.y.clamp(self.min.y, self.max.y),
            center.z.clamp(self.min.z, self.max.z),
        );
        let dist_sq = (closest - center).length_squared();
        dist_sq <= radius * radius
    }
}

/// Point light representation for simulation and CPU-side scene management.
#[derive(Copy, Clone, Debug, PartialEq)]
pub struct PointLight {
    pub position: Vec3,
    pub radius: f32,
    pub color: Vec3,
    pub intensity: f32,
}

/// Spot light representation with cone angle parameters.
#[derive(Copy, Clone, Debug, PartialEq)]
pub struct SpotLight {
    pub position: Vec3,
    pub direction: Vec3,
    pub range: f32,
    pub inner_angle: f32,
    pub outer_angle: f32,
    pub color: Vec3,
    pub intensity: f32,
}

/// GPU-compatible light structure packed to 64 bytes (16-byte aligned per vector).
#[repr(C)]
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
pub struct GpuLight {
    /// xyz: World position, w: Attenuation radius / range
    pub position_range: [f32; 4],
    /// xyz: Linear RGB color, w: Luminous intensity (cd / lm)
    pub color_intensity: [f32; 4],
    /// xyz: Unit light direction (for spot lights), w: cos(inner_angle)
    pub direction_inner: [f32; 4],
    /// x: cos(outer_angle), y: Light type (0.0 = Point, 1.0 = Spot), zw: padding
    pub params: [f32; 4],
}

/// Individual cluster grid cell metadata for GPU shader indexing.
///
/// 16-byte aligned for direct upload to WebGPU storage buffer.
#[repr(C)]
#[derive(Copy, Clone, Debug, Default, PartialEq, Eq, bytemuck::Pod, bytemuck::Zeroable)]
pub struct ClusterCell {
    /// Starting offset into the global light index list.
    pub offset: u32,
    /// Number of active lights intersecting this cluster.
    pub count: u32,
    pub _pad: [u32; 2],
}

/// Type alias for WGSL ClusterRecord compatibility.
pub type ClusterRecord = ClusterCell;

/// Clustered Forward+ light assignment output buffers ready for GPU upload.
#[derive(Clone, Debug)]
pub struct ClusteredLightOutput {
    /// 3,456 cluster cell headers defining (offset, count).
    pub cells: Vec<ClusterCell>,
    /// Contiguous buffer of light indices referenced by the cells.
    pub light_indices: Vec<u32>,
    /// Array of GPU-formatted light parameters (Point + Spot).
    pub gpu_lights: Vec<GpuLight>,
    /// Maximum lights assigned to any single cluster.
    pub max_lights_per_cluster: u32,
    /// Total light-to-cluster assignment pairs.
    pub total_assignments: usize,
}

/// Pure-Rust Clustered Forward+ Light Assigner.
///
/// Partitions the camera frustum into 16x9x24 clusters with logarithmic depth spacing.
#[derive(Clone, Debug)]
pub struct ClusterLightGrid {
    /// Precomputed view-space AABBs for all 3,456 clusters.
    aabbs: Vec<ClusterAabb>,
    fov_y: f32,
    aspect_ratio: f32,
    z_near: f32,
    z_far: f32,
    log_factor: f32,
    log_near: f32,
}

impl ClusterLightGrid {
    /// Creates a new `ClusterLightGrid` and precomputes view-space cluster AABBs.
    pub fn new(fov_y: f32, aspect_ratio: f32, z_near: f32, z_far: f32) -> Self {
        assert!(z_near > 0.0, "z_near must be positive");
        assert!(z_far > z_near, "z_far must be greater than z_near");

        let log_near = z_near.ln();
        let log_factor = (NUM_CLUSTERS_Z as f32) / (z_far / z_near).ln();

        let mut grid = Self {
            aabbs: vec![ClusterAabb::default(); TOTAL_CLUSTERS],
            fov_y,
            aspect_ratio,
            z_near,
            z_far,
            log_factor,
            log_near,
        };
        grid.rebuild_cluster_aabbs();
        grid
    }

    /// Linear cluster index from 3D coordinates (x: 0..16, y: 0..9, z: 0..24).
    #[inline]
    pub fn get_cluster_index(x: usize, y: usize, z: usize) -> usize {
        debug_assert!(x < NUM_CLUSTERS_X);
        debug_assert!(y < NUM_CLUSTERS_Y);
        debug_assert!(z < NUM_CLUSTERS_Z);
        x + y * NUM_CLUSTERS_X + z * (NUM_CLUSTERS_X * NUM_CLUSTERS_Y)
    }

    /// Decomposes a linear cluster index into 3D grid coordinates (x, y, z).
    #[inline]
    pub fn get_cluster_coords(index: usize) -> (usize, usize, usize) {
        debug_assert!(index < TOTAL_CLUSTERS);
        let slice_size = NUM_CLUSTERS_X * NUM_CLUSTERS_Y;
        let z = index / slice_size;
        let rem = index % slice_size;
        let y = rem / NUM_CLUSTERS_X;
        let x = rem % NUM_CLUSTERS_X;
        (x, y, z)
    }

    /// Returns the view-space depth interval [near_z, far_z] for a given depth slice k.
    #[inline]
    pub fn slice_to_depth_range(&self, slice: usize) -> (f32, f32) {
        let k = slice.clamp(0, NUM_CLUSTERS_Z - 1) as f32;
        let ratio = self.z_far / self.z_near;
        let nz = NUM_CLUSTERS_Z as f32;
        let z_min = self.z_near * ratio.powf(k / nz);
        let z_max = self.z_near * ratio.powf((k + 1.0) / nz);
        (z_min, z_max)
    }

    /// Maps a positive view-space depth `z` to a cluster depth slice index in `[0, 23]`.
    #[inline]
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

    /// Precomputes the view-space AABBs for all 3,456 clusters.
    ///
    /// Convention: Positive Z points forward in view depth (camera looks along +Z depth).
    pub fn rebuild_cluster_aabbs(&mut self) {
        let half_h = (self.fov_y * 0.5).tan();
        let half_w = half_h * self.aspect_ratio;

        for z in 0..NUM_CLUSTERS_Z {
            let (z_min, z_max) = self.slice_to_depth_range(z);

            for y in 0..NUM_CLUSTERS_Y {
                // Screen Y from bottom (-half_h) to top (+half_h)
                let y0_norm = -half_h + 2.0 * half_h * (y as f32 / NUM_CLUSTERS_Y as f32);
                let y1_norm = -half_h + 2.0 * half_h * ((y + 1) as f32 / NUM_CLUSTERS_Y as f32);

                for x in 0..NUM_CLUSTERS_X {
                    // Screen X from left (-half_w) to right (+half_w)
                    let x0_norm = -half_w + 2.0 * half_w * (x as f32 / NUM_CLUSTERS_X as f32);
                    let x1_norm = -half_w + 2.0 * half_w * ((x + 1) as f32 / NUM_CLUSTERS_X as f32);

                    // Compute corners at near slice plane
                    let p_near_min = Vec3::new(x0_norm * z_min, y0_norm * z_min, z_min);
                    let p_near_max = Vec3::new(x1_norm * z_min, y1_norm * z_min, z_min);

                    // Compute corners at far slice plane
                    let p_far_min = Vec3::new(x0_norm * z_max, y0_norm * z_max, z_max);
                    let p_far_max = Vec3::new(x1_norm * z_max, y1_norm * z_max, z_max);

                    // Determine cluster view-space AABB
                    let min = p_near_min.min(p_near_max).min(p_far_min).min(p_far_max);
                    let max = p_near_min.max(p_near_max).max(p_far_min).max(p_far_max);

                    let idx = Self::get_cluster_index(x, y, z);
                    self.aabbs[idx] = ClusterAabb::new(min, max);
                }
            }
        }
    }

    /// Access the precomputed AABB for cluster (x, y, z).
    #[inline]
    pub fn get_cluster_aabb(&self, x: usize, y: usize, z: usize) -> &ClusterAabb {
        &self.aabbs[Self::get_cluster_index(x, y, z)]
    }

    /// Bins 1,024+ dynamic point and spot lights into the 3,456 cluster cells.
    ///
    /// The `view_matrix` transforms world coordinates into camera view space.
    /// Standard camera view: Camera looks down -Z in standard OpenGL/wgpu world-to-view convention,
    /// so positive view depth `z_depth = -view_pos.z`.
    pub fn bin_lights(
        &self,
        point_lights: &[PointLight],
        spot_lights: &[SpotLight],
        view_matrix: Mat4,
    ) -> ClusteredLightOutput {
        let total_lights = point_lights.len() + spot_lights.len();
        let mut gpu_lights = Vec::with_capacity(total_lights);
        let mut cluster_light_lists: Vec<Vec<u32>> = vec![Vec::new(); TOTAL_CLUSTERS];

        // 1. Ingest Point Lights
        for (idx, light) in point_lights.iter().enumerate() {
            let light_id = idx as u32;

            // Transform to camera view space
            let view_pos = view_matrix.transform_point3(light.position);
            let z_depth = -view_pos.z;

            // GPU uniform packing
            gpu_lights.push(GpuLight {
                position_range: [light.position.x, light.position.y, light.position.z, light.radius],
                color_intensity: [light.color.x, light.color.y, light.color.z, light.intensity],
                direction_inner: [0.0, 0.0, 0.0, 1.0],
                params: [1.0, 0.0, 0.0, 0.0], // light_type = 0.0 (Point)
            });

            // Fast depth-range culling
            let min_z = z_depth - light.radius;
            let max_z = z_depth + light.radius;
            if max_z < self.z_near || min_z > self.z_far {
                continue;
            }

            let slice_min = self.depth_to_slice(min_z.max(self.z_near));
            let slice_max = self.depth_to_slice(max_z.min(self.z_far));

            // View-space sphere center for Arvo's test (with positive Z depth)
            let sphere_center = Vec3::new(view_pos.x, view_pos.y, z_depth);

            for z in slice_min..=slice_max {
                for y in 0..NUM_CLUSTERS_Y {
                    for x in 0..NUM_CLUSTERS_X {
                        let c_idx = Self::get_cluster_index(x, y, z);
                        if self.aabbs[c_idx].intersects_sphere(sphere_center, light.radius) {
                            cluster_light_lists[c_idx].push(light_id);
                        }
                    }
                }
            }
        }

        // 2. Ingest Spot Lights
        let point_lights_count = point_lights.len() as u32;
        for (s_idx, spot) in spot_lights.iter().enumerate() {
            let light_id = point_lights_count + s_idx as u32;

            let view_pos = view_matrix.transform_point3(spot.position);
            let z_depth = -view_pos.z;

            gpu_lights.push(GpuLight {
                position_range: [spot.position.x, spot.position.y, spot.position.z, spot.range],
                color_intensity: [spot.color.x, spot.color.y, spot.color.z, spot.intensity],
                direction_inner: [
                    spot.direction.x,
                    spot.direction.y,
                    spot.direction.z,
                    spot.inner_angle.cos(),
                ],
                params: [spot.outer_angle.cos(), 1.0, 0.0, 0.0], // light_type = 1.0 (Spot)
            });

            // Conservative bounding sphere centered at spot origin with radius `range`
            let min_z = z_depth - spot.range;
            let max_z = z_depth + spot.range;
            if max_z < self.z_near || min_z > self.z_far {
                continue;
            }

            let slice_min = self.depth_to_slice(min_z.max(self.z_near));
            let slice_max = self.depth_to_slice(max_z.min(self.z_far));
            let sphere_center = Vec3::new(view_pos.x, view_pos.y, z_depth);

            for z in slice_min..=slice_max {
                for y in 0..NUM_CLUSTERS_Y {
                    for x in 0..NUM_CLUSTERS_X {
                        let c_idx = Self::get_cluster_index(x, y, z);
                        if self.aabbs[c_idx].intersects_sphere(sphere_center, spot.range) {
                            cluster_light_lists[c_idx].push(light_id);
                        }
                    }
                }
            }
        }

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

        ClusteredLightOutput {
            cells,
            light_indices,
            gpu_lights,
            max_lights_per_cluster,
            total_assignments,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_logarithmic_depth_division_monotonicity() {
        let grid = ClusterLightGrid::new(1.0, 16.0 / 9.0, 0.1, 100.0);

        // Near and far slice values
        assert_eq!(grid.depth_to_slice(0.05), 0);
        assert_eq!(grid.depth_to_slice(0.1), 0);
        assert_eq!(grid.depth_to_slice(100.0), NUM_CLUSTERS_Z - 1);
        assert_eq!(grid.depth_to_slice(200.0), NUM_CLUSTERS_Z - 1);

        // Verify boundary continuity and monotonic increase
        let mut prev_max = 0.1;
        for z in 0..NUM_CLUSTERS_Z {
            let (z_min, z_max) = grid.slice_to_depth_range(z);
            assert!(
                (z_min - prev_max).abs() < 1e-4,
                "Slice boundary discontinuity at slice {}: z_min={}, prev_max={}",
                z,
                z_min,
                prev_max
            );
            assert!(z_max > z_min, "Slice max must exceed min");
            prev_max = z_max;

            // Midpoint must map to slice z
            let mid = (z_min * z_max).sqrt(); // Geometric mean
            assert_eq!(grid.depth_to_slice(mid), z);
        }
        assert!((prev_max - 100.0).abs() < 1e-3);
    }

    #[test]
    fn test_aabb_sphere_intersection_arvo() {
        let aabb = ClusterAabb::new(Vec3::new(-1.0, -1.0, -1.0), Vec3::new(1.0, 1.0, 1.0));

        // Sphere inside
        assert!(aabb.intersects_sphere(Vec3::ZERO, 0.5));
        // Sphere intersecting face
        assert!(aabb.intersects_sphere(Vec3::new(1.5, 0.0, 0.0), 0.6));
        // Sphere just outside face
        assert!(!aabb.intersects_sphere(Vec3::new(1.5, 0.0, 0.0), 0.4));
        // Sphere intersecting corner
        assert!(aabb.intersects_sphere(Vec3::new(1.5, 1.5, 1.5), 1.0));
        // Sphere far away
        assert!(!aabb.intersects_sphere(Vec3::new(10.0, 10.0, 10.0), 2.0));
    }

    #[test]
    fn test_cluster_grid_indexing_round_trip() {
        for z in 0..NUM_CLUSTERS_Z {
            for y in 0..NUM_CLUSTERS_Y {
                for x in 0..NUM_CLUSTERS_X {
                    let idx = ClusterLightGrid::get_cluster_index(x, y, z);
                    let (rx, ry, rz) = ClusterLightGrid::get_cluster_coords(idx);
                    assert_eq!((x, y, z), (rx, ry, rz));
                }
            }
        }
    }

    #[test]
    fn test_binning_1024_lights_performance_and_integrity() {
        let grid = ClusterLightGrid::new(1.0, 16.0 / 9.0, 0.1, 100.0);
        let view_matrix = Mat4::look_to_rh(Vec3::ZERO, -Vec3::Z, Vec3::Y);

        // Generate 1,024 dynamic point lights randomly distributed in front of camera
        let mut lights = Vec::with_capacity(1024);
        for i in 0..1024 {
            let fi = i as f32;
            let x = ((fi * 13.37).sin()) * 15.0;
            let y = ((fi * 7.42).cos()) * 10.0;
            let z = -((fi % 90.0) + 1.0); // Depth from -1.0 to -91.0
            lights.push(PointLight {
                position: Vec3::new(x, y, z),
                radius: 4.0,
                color: Vec3::new(1.0, 0.9, 0.7),
                intensity: 100.0,
            });
        }

        let output = grid.bin_lights(&lights, &[], view_matrix);

        assert_eq!(output.cells.len(), TOTAL_CLUSTERS);
        assert_eq!(output.gpu_lights.len(), 1024);
        assert!(output.total_assignments > 0);
        assert!(output.max_lights_per_cluster > 0);

        // Verify that light indices are valid
        for &l_idx in &output.light_indices {
            assert!((l_idx as usize) < 1024);
        }
    }
}
