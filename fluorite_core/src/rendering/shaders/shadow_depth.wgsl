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
