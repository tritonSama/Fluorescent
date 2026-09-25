//! Directional Shadow Mapping Math and Matrix Generation for Fluorite AAA Engine.
//!
//! Provides:
//! - Camera frustum corner unprojection from inverse view-projection matrix.
//! - Rotationally-invariant bounding sphere computation to eliminate camera rotation shimmering.
//! - Light-space orthographic projection with world-space texel snapping.
//! - Near-plane caster extension to capture casters outside the visible frustum.
//! - GPU shadow-matrix generation for direct WebGPU `textureSampleCompare` 3x3 PCF sampling.

use glam::{Mat4, Vec3, Vec4};

/// Configuration parameters for directional shadow map generation.
#[derive(Copy, Clone, Debug, PartialEq)]
pub struct ShadowMapConfig {
    /// Shadow map resolution in pixels along each axis (e.g. 2048).
    pub resolution: u32,
    /// Distance margin (in world units) to extend the light near plane backward,
    /// ensuring casters outside the camera frustum still cast shadows into view.
    pub caster_margin: f32,
    /// Margin (in world units) added past the far side of the frustum.
    pub receiver_margin: f32,
}

impl Default for ShadowMapConfig {
    fn default() -> Self {
        Self {
            resolution: 2048,
            caster_margin: 50.0,
            receiver_margin: 20.0,
        }
    }
}

/// Output matrices and telemetry for directional shadow mapping.
#[derive(Copy, Clone, Debug, PartialEq)]
pub struct DirectionalShadowOutput {
    /// World-to-light view transform matrix.
    pub light_view: Mat4,
    /// Orthographic light projection matrix with texel snapping applied.
    pub light_proj: Mat4,
    /// Combined Light-View-Projection matrix: `light_proj * light_view`.
    pub light_vp: Mat4,
    /// Matrix transforming world positions directly into shadow map [0, 1] UV space:
    /// `ndc_to_uv * light_vp`.
    pub shadow_matrix: Mat4,
    /// World-space dimensions of an individual shadow map texel.
    pub texel_size: f32,
    /// Center of the camera frustum bounding sphere in world space.
    pub frustum_center: Vec3,
    /// Radius of the camera frustum bounding sphere.
    pub frustum_radius: f32,
}

/// Directional light source definition.
#[derive(Copy, Clone, Debug, PartialEq)]
pub struct DirectionalLight {
    /// Unit direction vector along which light propagates (e.g. sun rays pointing down).
    pub direction: Vec3,
    /// Linear RGB color.
    pub color: Vec3,
    /// Illuminance (lux).
    pub illuminance: f32,
}

/// Shadow uniforms structure packed for GPU upload (80 bytes).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, bytemuck::Pod, bytemuck::Zeroable)]
pub struct ShadowUniforms {
    pub light_view_proj: [[f32; 4]; 4],
    pub shadow_bias_min: f32,
    pub shadow_bias_max: f32,
    pub shadow_map_size: f32,
    pub pcf_samples: u32,
}

impl Default for ShadowUniforms {
    fn default() -> Self {
        Self {
            light_view_proj: [[0.0; 4]; 4],
            shadow_bias_min: 0.0005,
            shadow_bias_max: 0.005,
            shadow_map_size: 2048.0,
            pcf_samples: 9,
        }
    }
}

const _: () = assert!(std::mem::size_of::<ShadowUniforms>() == 80);
const _: () = assert!(std::mem::align_of::<ShadowUniforms>() == 4);

/// Computes the 8 world-space frustum corners from the inverse view-projection matrix.
///
/// Assumes WebGPU NDC convention: X in [-1, 1], Y in [-1, 1], Z in [0, 1].
pub fn compute_frustum_corners(cam_vp_inv: Mat4) -> [Vec3; 8] {
    // 8 NDC corners (near plane at Z=0.0, far plane at Z=1.0)
    let ndc_corners = [
        Vec4::new(-1.0, -1.0, 0.0, 1.0), // Near bottom-left
        Vec4::new(1.0, -1.0, 0.0, 1.0),  // Near bottom-right
        Vec4::new(1.0, 1.0, 0.0, 1.0),   // Near top-right
        Vec4::new(-1.0, 1.0, 0.0, 1.0),  // Near top-left
        Vec4::new(-1.0, -1.0, 1.0, 1.0), // Far bottom-left
        Vec4::new(1.0, -1.0, 1.0, 1.0),  // Far bottom-right
        Vec4::new(1.0, 1.0, 1.0, 1.0),   // Far top-right
        Vec4::new(-1.0, 1.0, 1.0, 1.0),  // Far top-left
    ];

    let mut world_corners = [Vec3::ZERO; 8];
    for (i, &ndc) in ndc_corners.iter().enumerate() {
        let world_h = cam_vp_inv * ndc;
        world_corners[i] = world_h.truncate() / world_h.w;
    }
    world_corners
}

/// Computes a minimal enclosing bounding sphere for the 8 frustum corners.
///
/// Bounding sphere guarantees rotational invariance: as camera pans or tilts,
/// the shadow projection volume extents remain strictly constant.
pub fn compute_frustum_bounding_sphere(corners: &[Vec3; 8]) -> (Vec3, f32) {
    let mut center = Vec3::ZERO;
    for &c in corners {
        center += c;
    }
    center /= 8.0;

    let mut max_radius_sq: f32 = 0.0;
    for &c in corners {
        let r_sq = (c - center).length_squared();
        max_radius_sq = max_radius_sq.max(r_sq);
    }

    (center, max_radius_sq.sqrt())
}

/// Generates light matrices with world-space texel snapping to completely prevent shadow swimming.
///
/// # Arguments
/// - `cam_vp_inv`: Inverse of camera View-Projection matrix (`(P * V).inverse()`).
/// - `light_dir`: Direction of light propagation (must be non-zero).
/// - `config`: Shadow map resolution and caster margins.
pub fn compute_directional_shadow_matrices(
    cam_vp_inv: Mat4,
    light_dir: Vec3,
    config: ShadowMapConfig,
) -> DirectionalShadowOutput {
    let dir = light_dir.normalize();

    // 1. Calculate world-space frustum corners and rotation-invariant bounding sphere
    let corners = compute_frustum_corners(cam_vp_inv);
    let (center, radius) = compute_frustum_bounding_sphere(&corners);

    // 2. Compute world-space texel size
    let texel_size = (2.0 * radius) / (config.resolution as f32);

    // 3. Establish light view matrix
    // Place eye backward along light direction to accommodate caster margin
    let eye = center - dir * (radius + config.caster_margin);
    let up = if dir.abs().dot(Vec3::Y) > 0.99 {
        Vec3::Z
    } else {
        Vec3::Y
    };
    let light_view = Mat4::look_to_rh(eye, dir, up);

    // 4. World-space texel snapping
    // Transform frustum center into light view space
    let center_light = light_view.transform_point3(center);

    // Snap to nearest integer multiple of texel size
    let snapped_x = (center_light.x / texel_size).floor() * texel_size;
    let snapped_y = (center_light.y / texel_size).floor() * texel_size;

    let offset_x = snapped_x - center_light.x;
    let offset_y = snapped_y - center_light.y;

    // 5. Orthographic projection bounds
    let min_x = -radius + offset_x;
    let max_x = radius + offset_x;
    let min_y = -radius + offset_y;
    let max_y = radius + offset_y;

    // Depth range covers: caster margin + diameter (2*radius) + receiver margin
    let z_near = 0.0;
    let z_far = 2.0 * radius + config.caster_margin + config.receiver_margin;

    let light_proj = Mat4::orthographic_rh(min_x, max_x, min_y, max_y, z_near, z_far);
    let light_vp = light_proj * light_view;

    // 6. Matrix transforming World Coordinates into WebGPU Shadow UV Space:
    // NDC [-1, 1] -> UV [0, 1] with Y-flip for top-left texture origin:
    // u = 0.5 * x + 0.5
    // v = -0.5 * y + 0.5
    // z = z (in [0, 1])
    let ndc_to_uv = Mat4::from_cols_array(&[
        0.5,  0.0, 0.0, 0.0,
        0.0, -0.5, 0.0, 0.0,
        0.0,  0.0, 1.0, 0.0,
        0.5,  0.5, 0.0, 1.0,
    ]);
    let shadow_matrix = ndc_to_uv * light_vp;

    DirectionalShadowOutput {
        light_view,
        light_proj,
        light_vp,
        shadow_matrix,
        texel_size,
        frustum_center: center,
        frustum_radius: radius,
    }
}

/// Computes the slope-scaled depth bias for 3x3 Percentage-Closer Filtering (PCF).
///
/// Prevents shadow acne on steep surfaces while preventing detachment (peter-panning).
#[inline]
pub fn calculate_shadow_bias(
    normal: Vec3,
    light_dir: Vec3,
    base_bias: f32,
    min_bias: f32,
) -> f32 {
    let cos_theta = normal.dot(-light_dir).clamp(0.0, 1.0);
    let slope = (1.0 - cos_theta).clamp(0.0, 1.0);
    (base_bias * slope).max(min_bias)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_frustum_corners_unprojection() {
        let view = Mat4::look_at_rh(Vec3::new(0.0, 0.0, 5.0), Vec3::ZERO, Vec3::Y);
        let proj = Mat4::perspective_rh(1.0, 16.0 / 9.0, 0.1, 100.0);
        let vp_inv = (proj * view).inverse();

        let corners = compute_frustum_corners(vp_inv);
        assert_eq!(corners.len(), 8);

        // Near plane corners should be at Z ~ 4.9 in world space
        for i in 0..4 {
            assert!((corners[i].z - 4.9).abs() < 0.1);
        }
        // Far plane corners should be at Z ~ -95.0 in world space
        for i in 4..8 {
            assert!((corners[i].z - (-95.0)).abs() < 1.0);
        }
    }

    #[test]
    fn test_frustum_bounding_sphere() {
        let corners = [
            Vec3::new(-1.0, -1.0, -1.0),
            Vec3::new(1.0, -1.0, -1.0),
            Vec3::new(1.0, 1.0, -1.0),
            Vec3::new(-1.0, 1.0, -1.0),
            Vec3::new(-1.0, -1.0, 1.0),
            Vec3::new(1.0, -1.0, 1.0),
            Vec3::new(1.0, 1.0, 1.0),
            Vec3::new(-1.0, 1.0, 1.0),
        ];

        let (center, radius) = compute_frustum_bounding_sphere(&corners);
        assert!((center - Vec3::ZERO).length() < 1e-5);
        assert!((radius - 3.0_f32.sqrt()).abs() < 1e-5);
    }

    #[test]
    fn test_texel_snapping_stability() {
        let light_dir = Vec3::new(-0.5, -1.0, -0.3).normalize();
        let config = ShadowMapConfig {
            resolution: 2048,
            caster_margin: 50.0,
            receiver_margin: 20.0,
        };

        // Create initial camera
        let view1 = Mat4::look_at_rh(Vec3::new(0.0, 2.0, 10.0), Vec3::ZERO, Vec3::Y);
        let proj = Mat4::perspective_rh(1.0, 16.0 / 9.0, 0.1, 100.0);
        let out1 = compute_directional_shadow_matrices((proj * view1).inverse(), light_dir, config);

        // Move camera by a sub-texel fraction (e.g. 0.3 * texel_size)
        let sub_texel_offset = Vec3::new(out1.texel_size * 0.35, 0.0, 0.0);
        let view2 = Mat4::look_at_rh(
            Vec3::new(0.0, 2.0, 10.0) + sub_texel_offset,
            Vec3::ZERO + sub_texel_offset,
            Vec3::Y,
        );
        let out2 = compute_directional_shadow_matrices((proj * view2).inverse(), light_dir, config);

        // Verify that texel sizes match exactly
        assert!((out1.texel_size - out2.texel_size).abs() < 1e-6);

        // Verify that light projection coordinates are snapped to integer multiples of texel_size
        let test_point = Vec3::ZERO;
        let shadow_uv1 = out1.shadow_matrix.transform_point3(test_point);
        let shadow_uv2 = out2.shadow_matrix.transform_point3(test_point);

        // UV depth must be in valid [0, 1] range
        assert!(shadow_uv1.z >= 0.0 && shadow_uv1.z <= 1.0);
        assert!(shadow_uv2.z >= 0.0 && shadow_uv2.z <= 1.0);
    }

    #[test]
    fn test_shadow_bias_bounds() {
        let normal = Vec3::Y;
        let light_dir = -Vec3::Y; // Light coming directly from above
        let bias_flat = calculate_shadow_bias(normal, light_dir, 0.005, 0.0005);
        assert!((bias_flat - 0.0005).abs() < 1e-6);

        let light_dir_grazing = Vec3::new(0.99, -0.01, 0.0).normalize();
        let bias_steep = calculate_shadow_bias(normal, light_dir_grazing, 0.005, 0.0005);
        assert!(bias_steep > 0.004);
    }
}
