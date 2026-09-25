// ============================================================================
// Fluorite Engine — Milestone 1: Cluster Slicing & Light Culling Compute Shader
// File: cluster_cull.wgsl
// ============================================================================

const MAX_LIGHTS_PER_CLUSTER: u32 = 128u;
const MAX_GLOBAL_LIGHT_INDICES: u32 = 262144u; // 256K indices buffer

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

// ----------------------------------------------------------------------------
// Resource Bindings
// ----------------------------------------------------------------------------

@group(0) @binding(0) var<uniform> camera: CameraUniforms;
@group(0) @binding(1) var<storage, read> lights: array<GpuLight>;
@group(0) @binding(2) var<storage, read_write> cluster_records: array<ClusterRecord>;
@group(0) @binding(3) var<storage, read_write> cluster_light_indices: array<u32>;
@group(0) @binding(4) var<storage, read_write> global_index_counter: atomic<u32>;

// ----------------------------------------------------------------------------
// Compute Shader Entry Point
// ----------------------------------------------------------------------------

@compute @workgroup_size(64, 1, 1)
fn cs_main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let cluster_idx = global_id.x;
    let total_clusters = camera.cluster_dim_x * camera.cluster_dim_y * camera.cluster_dim_z;
    if (cluster_idx >= total_clusters) {
        return;
    }

    // Unpack 1D index to (tile_x, tile_y, tile_z)
    let tile_x = cluster_idx % camera.cluster_dim_x;
    let tile_y = (cluster_idx / camera.cluster_dim_x) % camera.cluster_dim_y;
    let tile_z = cluster_idx / (camera.cluster_dim_x * camera.cluster_dim_y);

    // 1. NDC Tile Coordinates
    let u0 = f32(tile_x) / f32(camera.cluster_dim_x);
    let u1 = f32(tile_x + 1u) / f32(camera.cluster_dim_x);
    let v0 = f32(tile_y) / f32(camera.cluster_dim_y);
    let v1 = f32(tile_y + 1u) / f32(camera.cluster_dim_y);

    let ndc_x_min = u0 * 2.0 - 1.0;
    let ndc_x_max = u1 * 2.0 - 1.0;
    let ndc_y_min = 1.0 - v1 * 2.0;
    let ndc_y_max = 1.0 - v0 * 2.0;

    // 2. Exponential Depth Slices
    let z_ratio = camera.z_far / camera.z_near;
    let slice_near = camera.z_near * pow(z_ratio, f32(tile_z) / f32(camera.cluster_dim_z));
    let slice_far  = camera.z_near * pow(z_ratio, f32(tile_z + 1u) / f32(camera.cluster_dim_z));

    // 3. View-Space Cluster AABB
    let p00 = camera.proj[0][0];
    let p11 = camera.proj[1][1];

    let x_near_min = (ndc_x_min * slice_near) / p00;
    let x_near_max = (ndc_x_max * slice_near) / p00;
    let y_near_min = (ndc_y_min * slice_near) / p11;
    let y_near_max = (ndc_y_max * slice_near) / p11;

    let x_far_min = (ndc_x_min * slice_far) / p00;
    let x_far_max = (ndc_x_max * slice_far) / p00;
    let y_far_min = (ndc_y_min * slice_far) / p11;
    let y_far_max = (ndc_y_max * slice_far) / p11;

    let aabb_min = vec3<f32>(
        min(min(x_near_min, x_near_max), min(x_far_min, x_far_max)),
        min(min(y_near_min, y_near_max), min(y_far_min, y_far_max)),
        -slice_far
    );
    let aabb_max = vec3<f32>(
        max(max(x_near_min, x_near_max), max(x_far_min, x_far_max)),
        max(max(y_near_min, y_near_max), max(y_far_min, y_far_max)),
        -slice_near
    );

    // 4. Cull Dynamic Lights against AABB
    var visible_light_count: u32 = 0u;
    var local_indices: array<u32, 128>;

    for (var l: u32 = 0u; l < camera.num_dynamic_lights; l = l + 1u) {
        if (visible_light_count >= MAX_LIGHTS_PER_CLUSTER) {
            break;
        }

        let light = lights[l];

        // Directional lights intersect every cluster
        if (light.light_type == 0u) {
            local_indices[visible_light_count] = l;
            visible_light_count = visible_light_count + 1u;
            continue;
        }

        // Transform light center to View Space
        let pos_view = (camera.view * vec4<f32>(light.position_ws, 1.0)).xyz;
        let r = light.radius;

        // Arvo's Sphere-AABB test
        var d2: f32 = 0.0;
        if (pos_view.x < aabb_min.x) {
            let d = aabb_min.x - pos_view.x;
            d2 += d * d;
        } else if (pos_view.x > aabb_max.x) {
            let d = pos_view.x - aabb_max.x;
            d2 += d * d;
        }

        if (pos_view.y < aabb_min.y) {
            let d = aabb_min.y - pos_view.y;
            d2 += d * d;
        } else if (pos_view.y > aabb_max.y) {
            let d = pos_view.y - aabb_max.y;
            d2 += d * d;
        }

        if (pos_view.z < aabb_min.z) {
            let d = aabb_min.z - pos_view.z;
            d2 += d * d;
        } else if (pos_view.z > aabb_max.z) {
            let d = pos_view.z - aabb_max.z;
            d2 += d * d;
        }

        if (d2 <= (r * r)) {
            local_indices[visible_light_count] = l;
            visible_light_count = visible_light_count + 1u;
        }
    }

    // 5. Atomic Global Allocation & Writeback
    if (visible_light_count > 0u) {
        let write_offset = atomicAdd(&global_index_counter, visible_light_count);
        if (write_offset + visible_light_count <= MAX_GLOBAL_LIGHT_INDICES) {
            for (var k: u32 = 0u; k < visible_light_count; k = k + 1u) {
                cluster_light_indices[write_offset + k] = local_indices[k];
            }
            cluster_records[cluster_idx] = ClusterRecord(write_offset, visible_light_count);
        } else {
            // Buffer overflow fallback: cap lights
            cluster_records[cluster_idx] = ClusterRecord(0u, 0u);
        }
    } else {
        cluster_records[cluster_idx] = ClusterRecord(0u, 0u);
    }
}
