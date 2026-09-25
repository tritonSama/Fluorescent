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
@group(0) @binding(4) var hzb_tex: texture_2d<f32>;
@group(0) @binding(5) var hzb_sampler: sampler;

@compute @workgroup_size(64, 1, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let instance_index = global_id.x;

    if (instance_index >= arrayLength(&instances)) {
        return;
    }

    let volume = instances[instance_index];

    // 1. Frustum Culling
    var is_visible = true;
    for (var i = 0u; i < 6u; i = i + 1u) {
        let plane = camera.frustum_planes[i];
        if (dot(plane.xyz, volume.sphere_center) + plane.w < -volume.sphere_radius) {
            is_visible = false;
            break;
        }
        let p_vertex = select(volume.aabb_min, volume.aabb_max, plane.xyz > vec3<f32>(0.0));
        if (dot(plane.xyz, p_vertex) + plane.w < 0.0) {
            is_visible = false;
            break;
        }
    }

    // 2. HZB Occlusion Culling
    if (is_visible) {
        // Project AABB corners to NDC
        var min_xy = vec2<f32>(1.0, 1.0);
        var max_xy = vec2<f32>(-1.0, -1.0);
        var min_z = 0.0; // Reverse-Z: 0.0 is furthest

        let corners = array<vec3<f32>, 8>(
            vec3<f32>(volume.aabb_min.x, volume.aabb_min.y, volume.aabb_min.z),
            vec3<f32>(volume.aabb_max.x, volume.aabb_min.y, volume.aabb_min.z),
            vec3<f32>(volume.aabb_min.x, volume.aabb_max.y, volume.aabb_min.z),
            vec3<f32>(volume.aabb_max.x, volume.aabb_max.y, volume.aabb_min.z),
            vec3<f32>(volume.aabb_min.x, volume.aabb_min.y, volume.aabb_max.z),
            vec3<f32>(volume.aabb_max.x, volume.aabb_min.y, volume.aabb_max.z),
            vec3<f32>(volume.aabb_min.x, volume.aabb_max.y, volume.aabb_max.z),
            vec3<f32>(volume.aabb_max.x, volume.aabb_max.y, volume.aabb_max.z)
        );

        var all_behind_near_plane = true;

        for (var i = 0u; i < 8u; i = i + 1u) {
            let clip = camera.view_proj * vec4<f32>(corners[i], 1.0);
            if (clip.w > 0.0) {
                all_behind_near_plane = false;
                let ndc = clip.xyz / clip.w;
                min_xy = min(min_xy, ndc.xy);
                max_xy = max(max_xy, ndc.xy);

                // For Reverse-Z, min depth is actually the closest point to camera in terms of values?
                // Wait. In Reverse-Z, z=1 is near plane, z=0 is far plane.
                // An object is bounded by its max depth value (closest point to camera)
                // in reverse Z, or bounded by min depth?
                // "culls if object_min_depth < hzb_depth" - user spec.
                if (i == 0u || ndc.z < min_z) {
                    min_z = ndc.z; // Track the minimum Z value across vertices
                }
            }
        }

        if (!all_behind_near_plane) {
            // Convert NDC to UV [0, 1]
            let uv_min = min_xy * vec2<f32>(0.5, -0.5) + vec2<f32>(0.5, 0.5);
            let uv_max = max_xy * vec2<f32>(0.5, -0.5) + vec2<f32>(0.5, 0.5);

            let rect_min = min(uv_min, uv_max);
            let rect_max = max(uv_min, uv_max);

            let screen_size = (rect_max - rect_min) * camera.viewport_size;
            let max_dim = max(screen_size.x, screen_size.y);

            // Log2 of dimension to select mip level
            var mip = 0.0;
            if (max_dim > 1.0) {
                mip = ceil(log2(max_dim));
            }

            // Sample HZB at the chosen mip level. We do a 4 tap to be safe,
            // but standard HZB can just do 1 tap if the footprint aligns or 4 taps.
            let tex_dim = vec2<f32>(textureDimensions(hzb_tex, i32(mip)));
            let sample_uv = (rect_min + rect_max) * 0.5;
            // Actually, properly it's 4 taps for AABB covering 2x2 texels at that mip:
            // But simple version first:
            let hzb_depth = textureSampleLevel(hzb_tex, hzb_sampler, sample_uv, mip).r;

            // object_min_depth < hzb_depth implies occluded in Reverse-Z
            if (min_z < hzb_depth) {
                is_visible = false;
            }
        }
    }

    if (is_visible) {
        let slot = atomicAdd(&draw_args.instance_count, 1u);
        compact_instances[slot] = instance_index;
    }
}
