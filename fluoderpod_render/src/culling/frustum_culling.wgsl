struct CameraUniforms {
    view_proj: mat4x4<f32>,
    camera_pos: vec3<f32>,
    _pad0: f32,
    frustum_planes: array<vec4<f32>, 6>,
    viewport_size: vec2<f32>,
    _pad1: vec2<f32>,
};

@group(0) @binding(0) var<uniform> camera: CameraUniforms;

struct PackedEntityInstance {
    pos_and_radius: vec4<f32>,     // xyz = position / sphere_center, w = sphere_radius
    rotation_quat: vec4<f32>,      // xyzw = unit quaternion
    scale_and_meta: vec4<f32>,     // xyz = scale, w = bitcast<f32>(meta_or_color)
};

@group(0) @binding(1) var<storage, read> instances: array<PackedEntityInstance>;

struct DrawIndexedIndirectArgs {
    index_count: u32,
    instance_count: atomic<u32>,
    first_index: u32,
    base_vertex: i32,
    first_instance: u32,
};

@group(0) @binding(2) var<storage, read_write> draw_args: DrawIndexedIndirectArgs;
@group(0) @binding(3) var<storage, read_write> compact_instances: array<u32>;

@compute @workgroup_size(64, 1, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let instance_index = global_id.x;

    // We don't have total_instances easily available here without an extra uniform/push constant.
    // However, if we assume the thread dispatch exactly matches, we can guard it by arrayLength.
    if (instance_index >= arrayLength(&instances)) {
        return;
    }

    let instance = instances[instance_index];

    // 1. Frustum Culling
    var is_visible = true;
    for (var i = 0u; i < 6u; i = i + 1u) {
        let plane = camera.frustum_planes[i];

        // Coarse test: Bounding Sphere
        if (dot(plane.xyz, instance.pos_and_radius.xyz) + plane.w < -instance.pos_and_radius.w) {
            is_visible = false;
            break;
        }
    }

    // Output
    if (is_visible) {
        let slot = atomicAdd(&draw_args.instance_count, 1u);
        compact_instances[slot] = instance_index;
    }
}
