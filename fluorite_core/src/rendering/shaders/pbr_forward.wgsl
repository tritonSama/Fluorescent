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
