//! Physically Based Rendering (PBR) Metallic-Roughness Material and Camera Uniforms.
//!
//! Conforms to glTF 2.0 specifications and WebGPU std140/std430 memory alignment rules:
//! - PbrMaterialUniforms: 48 bytes (16-byte aligned).
//! - CameraUniforms: 320 bytes (16-byte aligned, explicit 4-byte padding at offset 300).
//! - Cook-Torrance microfacet BRDF reference implementation for CPU validation and software tests.

use std::f32::consts::PI;
use glam::{Mat4, Vec3, Vec4};

// ----------------------------------------------------------------------------
// Material Bitflags
// ----------------------------------------------------------------------------
pub const MATERIAL_FLAG_HAS_ALBEDO_MAP: u32             = 1 << 0; // 0x01
pub const MATERIAL_FLAG_HAS_NORMAL_MAP: u32             = 1 << 1; // 0x02
pub const MATERIAL_FLAG_HAS_METALLIC_ROUGHNESS_MAP: u32 = 1 << 2; // 0x04
pub const MATERIAL_FLAG_HAS_OCCLUSION_MAP: u32          = 1 << 3; // 0x08
pub const MATERIAL_FLAG_HAS_EMISSIVE_MAP: u32           = 1 << 4; // 0x10
pub const MATERIAL_FLAG_ALPHA_BLEND: u32                = 1 << 5; // 0x20

/// PBR Material parameters packed for WebGPU uniform buffer upload.
///
/// Size: 48 bytes (3 x 16-byte blocks).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, bytemuck::Pod, bytemuck::Zeroable)]
pub struct PbrMaterialUniforms {
    /// Linear base color factor (RGBA). Bytes 0..16.
    pub base_color_factor: [f32; 4],
    /// Linear emissive radiant factor (RGB). Bytes 16..28.
    pub emissive_factor: [f32; 3],
    /// Microfacet metalness factor in [0.0, 1.0]. Bytes 28..32.
    pub metallic_factor: f32,
    /// Perceptual roughness factor in [0.04, 1.0]. Bytes 32..36.
    pub roughness_factor: f32,
    /// Normal map perturbation multiplier. Bytes 36..40.
    pub normal_scale: f32,
    /// Ambient occlusion strength in [0.0, 1.0]. Bytes 40..44.
    pub occlusion_strength: f32,
    /// Feature enable bitfield. Bytes 44..48.
    pub flags: u32,
}

impl Default for PbrMaterialUniforms {
    fn default() -> Self {
        Self {
            base_color_factor: [1.0, 1.0, 1.0, 1.0],
            emissive_factor: [0.0, 0.0, 0.0],
            metallic_factor: 0.0,
            roughness_factor: 0.5,
            normal_scale: 1.0,
            occlusion_strength: 1.0,
            flags: 0,
        }
    }
}

const _: () = assert!(std::mem::size_of::<PbrMaterialUniforms>() == 48);
const _: () = assert!(std::mem::align_of::<PbrMaterialUniforms>() == 4);

/// Camera View, Projection, and Clustered Grid Configuration Uniforms.
///
/// Size: 320 bytes (20 x 16-byte blocks).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, bytemuck::Pod, bytemuck::Zeroable)]
pub struct CameraUniforms {
    /// Combined View-Projection matrix. Bytes 0..64.
    pub view_proj: [[f32; 4]; 4],
    /// View transform matrix. Bytes 64..128.
    pub view: [[f32; 4]; 4],
    /// Projection matrix. Bytes 128..192.
    pub proj: [[f32; 4]; 4],
    /// Inverse Projection matrix. Bytes 192..256.
    pub inv_proj: [[f32; 4]; 4],
    /// World-space camera position. Bytes 256..268.
    pub camera_pos: [f32; 3],
    /// Near clipping plane depth. Bytes 268..272.
    pub z_near: f32,
    /// Far clipping plane depth. Bytes 272..276.
    pub z_far: f32,
    /// Viewport width in pixels. Bytes 276..280.
    pub screen_width: f32,
    /// Viewport height in pixels. Bytes 280..284.
    pub screen_height: f32,
    /// Cluster count along X axis (e.g. 16). Bytes 284..288.
    pub cluster_dim_x: u32,
    /// Cluster count along Y axis (e.g. 9). Bytes 288..292.
    pub cluster_dim_y: u32,
    /// Cluster count along Z axis (e.g. 24). Bytes 292..296.
    pub cluster_dim_z: u32,
    /// Number of active dynamic lights in scene. Bytes 296..300.
    pub num_dynamic_lights: u32,
    /// Explicit padding byte ensuring 16-byte alignment of `ambient_light`. Bytes 300..304.
    pub _padding: u32,
    /// Ambient radiant light flux (RGB + pad). Bytes 304..320.
    pub ambient_light: [f32; 4],
}

const _: () = assert!(std::mem::size_of::<CameraUniforms>() == 320);
const _: () = assert!(std::mem::align_of::<CameraUniforms>() == 4);

// ----------------------------------------------------------------------------
// Pure Rust Cook-Torrance Microfacet BRDF Reference Implementation
// ----------------------------------------------------------------------------

/// Trowbridge-Reitz GGX normal distribution function (D).
#[inline]
pub fn distribution_ggx(n_dot_h: f32, roughness: f32) -> f32 {
    let alpha = roughness * roughness;
    let alpha2 = alpha * alpha;
    let n_dot_h2 = n_dot_h * n_dot_h;
    let denom = n_dot_h2 * (alpha2 - 1.0) + 1.0;
    alpha2 / (PI * denom * denom)
}

/// Heitz (2014) Correlated Smith GGX visibility function (V = G / (4 * NdotV * NdotL)).
#[inline]
pub fn visibility_smith_ggx_correlated(n_dot_v: f32, n_dot_l: f32, roughness: f32) -> f32 {
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

/// Schlick Fresnel approximation (F).
#[inline]
pub fn fresnel_schlick(v_dot_h: f32, f0: Vec3) -> Vec3 {
    f0 + (Vec3::ONE - f0) * (1.0 - v_dot_h).clamp(0.0, 1.0).powi(5)
}

/// Evaluates the complete Cook-Torrance microfacet BRDF.
///
/// Returns `(diffuse_radiance, specular_radiance, total_reflection_coefficients)`.
pub fn evaluate_cook_torrance_brdf(
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
