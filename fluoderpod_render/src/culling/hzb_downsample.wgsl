@group(0) @binding(0) var input_tex: texture_2d<f32>;
@group(0) @binding(1) var output_tex: texture_storage_2d<r32float, write>;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let output_size = textureDimensions(output_tex);
    if (global_id.x >= output_size.x || global_id.y >= output_size.y) {
        return;
    }

    let input_coord = vec2<i32>(global_id.xy) * 2;

    // Sample 2x2 footprint
    let d0 = textureLoad(input_tex, input_coord + vec2<i32>(0, 0), 0).r;
    let d1 = textureLoad(input_tex, input_coord + vec2<i32>(1, 0), 0).r;
    let d2 = textureLoad(input_tex, input_coord + vec2<i32>(0, 1), 0).r;
    let d3 = textureLoad(input_tex, input_coord + vec2<i32>(1, 1), 0).r;

    // We assume Reverse-Z [1.0 -> 0.0]. Max depth is the furthest away.
    // A smaller depth value (closer to 0.0) is further in a standard reverse-Z.
    // Wait, typical reverse-Z means 1.0 is near and 0.0 is far.
    // So minimum depth value represents the furthest point.
    // "downsamples ... taking max(depth) for Reverse-Z [1.0 -> 0.0]"
    // The requirement explicitly states "max(depth)".
    let max_depth = max(max(d0, d1), max(d2, d3));

    textureStore(output_tex, vec2<i32>(global_id.xy), vec4<f32>(max_depth, 0.0, 0.0, 0.0));
}
