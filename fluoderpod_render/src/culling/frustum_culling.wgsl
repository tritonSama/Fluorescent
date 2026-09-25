struct CameraUniforms {
    view_proj: mat4x4<f32>,
    camera_pos: vec3<f32>,
    _pad0: f32,
    frustum_planes: array<vec4<f32>, 6>,
    viewport_size: vec2<f32>,
    _pad1: vec2<f32>,
};

@group(0) @binding(0) var<uniform> camera: CameraUniforms;

struct BoundingVolume {
    sphere_center: vec3<f32>,
    sphere_radius: f32,
    aabb_min: vec3<f32>,
    _pad0: f32,
    aabb_max: vec3<f32>,
    _pad1: f32,
};

@group(0) @binding(1) var<storage, read> instances: array<BoundingVolume>;

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

    let volume = instances[instance_index];

    // 1. Frustum Culling
    var is_visible = true;
    for (var i = 0u; i < 6u; i = i + 1u) {
        let plane = camera.frustum_planes[i];

        // Coarse test: Bounding Sphere
        if (dot(plane.xyz, volume.sphere_center) + plane.w < -volume.sphere_radius) {
            is_visible = false;
            break;
        }

        // Fine test: AABB
        let p_vertex = select(volume.aabb_min, volume.aabb_max, plane.xyz > vec3<f32>(0.0));
        if (dot(plane.xyz, p_vertex) + plane.w < 0.0) {
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
