struct CameraUniform {
    position: vec3<f32>,
    _padding: f32,
    view_proj: mat4x4<f32>,
    viewport_size: vec2<f32>,
    fov: f32,
    _padding2: f32,
}

struct ClusterHeader {
    sphere_center: vec3<f32>,
    sphere_radius: f32,
    lod_error: f32,
    parent_lod_error: f32,
    cluster_id: u32,
    parent_cluster_id: u32,
    vertex_offset: u32,
    vertex_count: u32,
    index_offset: u32,
    index_count: u32,
}

struct ClusterMetadataBuffer {
    clusters: array<ClusterHeader>,
}

struct OutputClustersBuffer {
    count: atomic<u32>,
    cluster_ids: array<u32>,
}

@group(0) @binding(0) var<uniform> camera: CameraUniform;
@group(0) @binding(1) var<storage, read> metadata_buffer: ClusterMetadataBuffer;
@group(0) @binding(2) var<storage, read_write> output_buffer: OutputClustersBuffer;

fn get_screen_space_error(cluster_error: f32, center: vec3<f32>, radius: f32) -> f32 {
    let dist = length(center - camera.position);
    let clamped_dist = max(dist - radius, 0.0001);

    // rho = (error / max(dist - r, epsilon)) * (height / (2 * tan(fov / 2)))
    let error_factor = cluster_error / clamped_dist;
    let projection_factor = camera.viewport_size.y / (2.0 * tan(camera.fov / 2.0));

    return error_factor * projection_factor;
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let idx = global_id.x;

    // Bounds check
    let num_clusters = arrayLength(&metadata_buffer.clusters);
    if idx >= num_clusters {
        return;
    }

    let cluster = metadata_buffer.clusters[idx];

    // Evaluate error
    let cluster_sse = get_screen_space_error(cluster.lod_error, cluster.sphere_center, cluster.sphere_radius);
    let parent_sse = get_screen_space_error(cluster.parent_lod_error, cluster.sphere_center, cluster.sphere_radius);

    let threshold = 1.0; // 1.0 pixel threshold

    // The root node has parent_lod_error = infinity (or a very large number), so it will always pass the parent condition.
    // If the cluster error is within the threshold, but the parent's error is too large, we select this cluster.
    if cluster_sse <= threshold && parent_sse > threshold {
        let output_idx = atomicAdd(&output_buffer.count, 1u);
        output_buffer.cluster_ids[output_idx] = cluster.cluster_id;
    }
}
