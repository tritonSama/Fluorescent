use std::time::{Duration, Instant};

use fluorite_core::spatial::{cull_frustum_with_stats, Aabb, FlatBvh, Frustum};
use glam::{Mat4, Vec3, Vec3A};

#[test]
fn test_bvh_frustum_culling_benchmark_10k_entities() {
    let num_entities = 10_000;
    let mut boxes = Vec::with_capacity(num_entities);

    // Populate 10,000 entities distributed across a 3D world (500m x 100m x 500m)
    for i in 0..num_entities {
        let x = (i % 100) as f32 * 5.0 - 250.0;
        let z = (i / 100) as f32 * 5.0 - 250.0;
        let y = ((i * 17) % 20) as f32;
        let min = Vec3A::new(x - 1.0, y - 1.0, z - 1.0);
        let max = Vec3A::new(x + 1.0, y + 1.0, z + 1.0);
        boxes.push(Aabb::new(min, max));
    }

    // Build Flat BVH with 16-bin SAH
    let build_start = Instant::now();
    let bvh = FlatBvh::build_binned_sah(&boxes, 16);
    let build_elapsed = build_start.elapsed();

    assert!(!bvh.is_empty(), "BVH must not be empty");
    assert_eq!(bvh.primitive_indices.len(), num_entities);

    // Setup Camera View-Projection Frustum
    let view = Mat4::look_at_rh(Vec3::new(0.0, 50.0, 200.0), Vec3::ZERO, Vec3::Y);
    let proj = Mat4::perspective_rh(60.0_f32.to_radians(), 16.0 / 9.0, 0.1, 500.0);
    let frustum = Frustum::from_view_projection(proj * view);

    let mut visible = Vec::with_capacity(num_entities);

    // Warm-up runs (20 iterations)
    for _ in 0..20 {
        bvh.cull_frustum(&frustum, &mut visible);
    }

    // Benchmark 100 iterations as specified in Key Tasks
    let iterations = 100;
    let start = Instant::now();
    for _ in 0..iterations {
        bvh.cull_frustum(&frustum, &mut visible);
    }
    let elapsed = start.elapsed();
    let avg_time = elapsed / iterations;

    let stats = cull_frustum_with_stats(&bvh, &frustum, &mut visible);

    println!("============================================================");
    println!("BVH Frustum Culling Benchmark (10,000 Entities):");
    println!("  BVH Node Count: {}", bvh.nodes.len());
    println!("  BVH Build Time: {:?}", build_elapsed);
    println!("  Total Culling Time ({} iterations): {:?}", iterations, elapsed);
    println!("  Average Time per Cull: {:?}", avg_time);
    println!("  Visible Entities Count: {}", visible.len());
    println!("  Nodes Tested: {}", stats.nodes_tested);
    println!("  Subtrees Inherited Inside: {}", stats.subtrees_inherited_inside);
    println!("  Subtrees Pruned Outside: {}", stats.subtrees_pruned_outside);
    println!("  Target Threshold: < 2.0ms");
    println!("============================================================");

    assert!(!visible.is_empty(), "Some entities must be visible in frustum");
    assert!(
        visible.len() < num_entities,
        "Culling must prune off-screen entities"
    );
    assert!(
        avg_time < Duration::from_millis(2),
        "Frustum culling exceeded 2ms threshold: {:?}",
        avg_time
    );
}
