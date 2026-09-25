use std::mem::{align_of, size_of};

use fluorite_core::spatial::{
    cull_frustum_exact, cull_frustum_with_stats, find_broadphase_pairs,
    find_broadphase_pairs_dual, query_aabb_overlap, Aabb, FlatBvh, FlatBvhNode, Frustum,
    FrustumIntersection, Plane, Ray,
};
use glam::{Mat4, Vec3, Vec3A};

#[test]
fn test_flat_bvh_node_memory_layout_and_size() {
    // Hard architectural contract: exactly 32 bytes and 32-byte alignment
    assert_eq!(
        size_of::<FlatBvhNode>(),
        32,
        "FlatBvhNode must be exactly 32 bytes"
    );
    assert_eq!(
        align_of::<FlatBvhNode>(),
        32,
        "FlatBvhNode must be 32-byte aligned for cache and GPU parity"
    );

    // Verify 2 nodes fit in a 64-byte cache line
    assert_eq!(size_of::<[FlatBvhNode; 2]>(), 64);

    // Verify bytemuck Pod round-trip
    let node = FlatBvhNode {
        aabb_min: [-10.0, -5.0, -2.0],
        left_or_first_child: 42,
        aabb_max: [10.0, 5.0, 2.0],
        count: 7,
    };
    let bytes: &[u8] = bytemuck::bytes_of(&node);
    assert_eq!(bytes.len(), 32);

    let deserialized: FlatBvhNode = *bytemuck::from_bytes(bytes);
    assert_eq!(deserialized, node);

    // Verify zeroable
    let zeroed: FlatBvhNode = bytemuck::Zeroable::zeroed();
    assert_eq!(zeroed.left_or_first_child, 0);
    assert_eq!(zeroed.count, 0);
}

#[test]
fn test_empty_bvh_lifecycle() {
    let bvh = FlatBvh::build(&[]);
    assert!(bvh.is_empty());
    assert_eq!(bvh.nodes.len(), 1);
    assert_eq!(bvh.nodes[0].count, 0);
    assert!(bvh.root_aabb().is_none());

    // Raycast on empty BVH returns None
    let ray = Ray::new(Vec3A::ZERO, -Vec3A::Z, 0.0, 100.0);
    assert!(bvh.raycast(&ray, &[]).is_none());
    assert!(!bvh.raycast_any(&ray, &[]));

    // Frustum cull on empty BVH returns 0
    let mut visible = Vec::new();
    let frustum = Frustum::new([Plane::new(Vec3A::Y, 0.0); 6]);
    bvh.cull_frustum(&frustum, &mut visible);
    assert!(visible.is_empty());

    // Broadphase on empty BVH returns 0 pairs
    let pairs = bvh.find_overlapping_pairs(&[]);
    assert!(pairs.is_empty());
}

#[test]
fn test_single_entity_bvh() {
    let boxes = [Aabb::new(
        Vec3A::new(-1.0, -1.0, -5.0),
        Vec3A::new(1.0, 1.0, -3.0),
    )];
    let bvh = FlatBvh::build(&boxes);

    assert!(!bvh.is_empty());
    assert_eq!(bvh.nodes.len(), 1);
    assert!(bvh.nodes[0].is_leaf());
    assert_eq!(bvh.nodes[0].primitive_count(), 1);
    assert_eq!(bvh.primitive_indices, vec![0]);

    // Direct raycast hit
    let hit_ray = Ray::new(Vec3A::ZERO, -Vec3A::Z, 0.0, 100.0);
    let hit = bvh.raycast(&hit_ray, &boxes);
    assert!(hit.is_some());
    let hit = hit.unwrap();
    assert_eq!(hit.entity_id, 0);
    // Nearest face is at z = -3.0, distance from origin (0,0,0) is 3.0
    assert!((hit.distance - 3.0).abs() < 1e-4);
    assert!((hit.point.z - (-3.0)).abs() < 1e-4);

    // Missing raycast
    let miss_ray = Ray::new(Vec3A::ZERO, Vec3A::Y, 0.0, 100.0);
    assert!(bvh.raycast(&miss_ray, &boxes).is_none());
    assert!(!bvh.raycast_any(&miss_ray, &boxes));
    assert!(bvh.raycast_any(&hit_ray, &boxes));
}

#[test]
fn test_degenerate_zero_volume_aabb() {
    let point_box = Aabb::new(Vec3A::new(0.0, 0.0, -5.0), Vec3A::new(0.0, 0.0, -5.0));
    assert_eq!(point_box.surface_area(), 0.0);

    let boxes = [point_box];
    let bvh = FlatBvh::build(&boxes);
    assert!(!bvh.is_empty());

    let ray = Ray::new(Vec3A::ZERO, -Vec3A::Z, 0.0, 100.0);
    let hit = bvh.raycast(&ray, &boxes);
    assert!(hit.is_some());
    let hit = hit.unwrap();
    assert_eq!(hit.entity_id, 0);
    assert!((hit.distance - 5.0).abs() < 1e-4);
}

#[test]
fn test_bvh_construction_sah_multi_entity() {
    // 64 entities spaced along the X axis
    let entities: Vec<Aabb> = (0..64)
        .map(|i| {
            let x = i as f32 * 2.0;
            Aabb::new(Vec3A::new(x, 0.0, 0.0), Vec3A::new(x + 1.0, 1.0, 1.0))
        })
        .collect();

    let bvh = FlatBvh::build_binned_sah(&entities, 16);
    assert!(!bvh.is_empty());
    assert!(bvh.nodes.len() > 1);

    // Root node bounding box must enclose all entities
    let root_bounds = bvh.root_aabb().unwrap();
    assert!((root_bounds.min.x - 0.0).abs() < 1e-3);
    assert!((root_bounds.max.x - (63.0 * 2.0 + 1.0)).abs() < 1e-3);

    // Ensure all 64 entities are present in primitive_indices
    assert_eq!(bvh.primitive_indices.len(), 64);
    let mut sorted_indices = bvh.primitive_indices.clone();
    sorted_indices.sort_unstable();
    let expected: Vec<u32> = (0..64).collect();
    assert_eq!(sorted_indices, expected);
}

#[test]
fn test_raycast_nearest_hit_and_shadow_occlusion() {
    // 3 boxes aligned along the negative Z axis
    let boxes = [
        Aabb::new(Vec3A::new(-1.0, -1.0, -11.0), Vec3A::new(1.0, 1.0, -9.0)),  // Nearest (dist 9)
        Aabb::new(Vec3A::new(-1.0, -1.0, -21.0), Vec3A::new(1.0, 1.0, -19.0)), // Mid (dist 19)
        Aabb::new(Vec3A::new(-1.0, -1.0, -31.0), Vec3A::new(1.0, 1.0, -29.0)), // Far (dist 29)
    ];

    let bvh = FlatBvh::build(&boxes);

    let ray = Ray::new(Vec3A::ZERO, -Vec3A::Z, 0.0, 100.0);
    let hit = bvh.raycast(&ray, &boxes).expect("Must hit nearest box");
    assert_eq!(hit.entity_id, 0, "Nearest box (entity 0) must be hit first");
    assert!((hit.distance - 9.0).abs() < 1e-3);

    // Raycast behind origin (opposite direction) must miss
    let reverse_ray = Ray::new(Vec3A::ZERO, Vec3A::Z, 0.0, 100.0);
    assert!(bvh.raycast(&reverse_ray, &boxes).is_none());
}

#[test]
fn test_hierarchical_box_frustum_culling_inside_outside() {
    // 10 boxes in front of camera (-Z) and 10 boxes behind camera (+Z)
    let mut boxes = Vec::new();
    for i in 0..10 {
        let z = -10.0 - (i as f32 * 3.0);
        boxes.push(Aabb::new(
            Vec3A::new(-1.0, -1.0, z - 1.0),
            Vec3A::new(1.0, 1.0, z + 1.0),
        ));
    }
    for i in 0..10 {
        let z = 10.0 + (i as f32 * 3.0);
        boxes.push(Aabb::new(
            Vec3A::new(-1.0, -1.0, z - 1.0),
            Vec3A::new(1.0, 1.0, z + 1.0),
        ));
    }

    let bvh = FlatBvh::build(&boxes);

    // Camera at origin looking down -Z
    let view = Mat4::look_at_rh(Vec3::ZERO, -Vec3::Z, Vec3::Y);
    let proj = Mat4::perspective_rh(60.0_f32.to_radians(), 16.0 / 9.0, 0.1, 100.0);
    let frustum = Frustum::from_view_projection(proj * view);

    let mut visible = Vec::new();
    bvh.cull_frustum(&frustum, &mut visible);

    // Entities behind camera (indices 10..20) must be completely culled
    for &id in &visible {
        assert!(id < 10, "Entity {} behind camera must be culled!", id);
    }
    // Entities in front of camera (indices 0..10) must be visible
    assert!(
        visible.len() >= 8,
        "Front entities should be visible, got {}",
        visible.len()
    );
}

#[test]
fn test_frustum_culling_inside_inheritance() {
    // Create a tightly clustered group of 16 boxes positioned at (0, 0, -20)
    let mut boxes = Vec::new();
    for x in 0..4 {
        for y in 0..4 {
            let cx = x as f32 * 0.5 - 1.0;
            let cy = y as f32 * 0.5 - 1.0;
            boxes.push(Aabb::new(
                Vec3A::new(cx - 0.2, cy - 0.2, -21.0),
                Vec3A::new(cx + 0.2, cy + 0.2, -19.0),
            ));
        }
    }

    let bvh = FlatBvh::build(&boxes);

    let view = Mat4::look_at_rh(Vec3::ZERO, -Vec3::Z, Vec3::Y);
    let proj = Mat4::perspective_rh(60.0_f32.to_radians(), 16.0 / 9.0, 0.1, 100.0);
    let frustum = Frustum::from_view_projection(proj * view);

    let mut visible = Vec::new();
    let stats = cull_frustum_with_stats(&bvh, &frustum, &mut visible);

    // The entire cluster should be recognized as Inside, inheriting inside state
    assert_eq!(visible.len(), 16, "All 16 clustered boxes must be visible");
    assert!(
        stats.subtrees_inherited_inside >= 1,
        "Inside-inheritance must be triggered for fully contained subtrees"
    );
}

#[test]
fn test_dual_tree_broadphase_collision_pairs() {
    let boxes = [
        Aabb::new(Vec3A::new(0.0, 0.0, 0.0), Vec3A::new(1.0, 1.0, 1.0)),       // 0: overlaps with 1
        Aabb::new(Vec3A::new(0.5, 0.5, 0.5), Vec3A::new(1.5, 1.5, 1.5)),       // 1: overlaps with 0
        Aabb::new(Vec3A::new(100.0, 100.0, 100.0), Vec3A::new(101.0, 101.0, 101.0)), // 2: overlaps with 3
        Aabb::new(Vec3A::new(100.5, 100.5, 100.5), Vec3A::new(101.5, 101.5, 101.5)), // 3: overlaps with 2
        Aabb::new(Vec3A::new(500.0, 500.0, 500.0), Vec3A::new(501.0, 501.0, 501.0)), // 4: isolated
    ];

    let bvh = FlatBvh::build(&boxes);
    let pairs = find_broadphase_pairs(&bvh, &boxes);

    assert_eq!(pairs.len(), 2, "Expected exactly 2 collision pairs");
    assert!(pairs.contains(&(0, 1)));
    assert!(pairs.contains(&(2, 3)));
    assert!(!pairs.contains(&(0, 2)));
    assert!(!pairs.contains(&(1, 3)));
    assert!(!pairs.contains(&(0, 4)));

    // Triangle of 3 mutually overlapping boxes
    let triangle_boxes = [
        Aabb::new(Vec3A::new(0.0, 0.0, 0.0), Vec3A::new(2.0, 2.0, 2.0)),
        Aabb::new(Vec3A::new(1.0, 0.0, 0.0), Vec3A::new(3.0, 2.0, 2.0)),
        Aabb::new(Vec3A::new(0.5, 1.0, 0.0), Vec3A::new(2.5, 3.0, 2.0)),
    ];
    let tri_bvh = FlatBvh::build(&triangle_boxes);
    let tri_pairs = tri_bvh.find_overlapping_pairs(&triangle_boxes);
    assert_eq!(tri_pairs.len(), 3);
    assert!(tri_pairs.contains(&(0, 1)));
    assert!(tri_pairs.contains(&(0, 2)));
    assert!(tri_pairs.contains(&(1, 2)));
}

#[test]
fn test_dual_tree_broadphase_between_two_bvhs() {
    let scenery = [
        Aabb::new(Vec3A::new(0.0, 0.0, 0.0), Vec3A::new(5.0, 5.0, 5.0)),
        Aabb::new(Vec3A::new(50.0, 0.0, 0.0), Vec3A::new(55.0, 5.0, 5.0)),
    ];
    let dynamic_entities = [
        Aabb::new(Vec3A::new(2.0, 2.0, 2.0), Vec3A::new(3.0, 3.0, 3.0)),   // Hits scenery 0
        Aabb::new(Vec3A::new(20.0, 20.0, 20.0), Vec3A::new(21.0, 21.0, 21.0)), // Hits nothing
    ];

    let bvh_scenery = FlatBvh::build(&scenery);
    let bvh_dynamic = FlatBvh::build(&dynamic_entities);

    let pairs = find_broadphase_pairs_dual(&bvh_dynamic, &bvh_scenery, &dynamic_entities, &scenery);
    assert_eq!(pairs.len(), 1);
    assert_eq!(pairs[0], (0, 0)); // dynamic 0 overlaps with scenery 0
}

#[test]
fn test_query_aabb_overlap() {
    let boxes = [
        Aabb::new(Vec3A::new(0.0, 0.0, 0.0), Vec3A::new(1.0, 1.0, 1.0)),
        Aabb::new(Vec3A::new(2.0, 0.0, 0.0), Vec3A::new(3.0, 1.0, 1.0)),
        Aabb::new(Vec3A::new(10.0, 0.0, 0.0), Vec3A::new(11.0, 1.0, 1.0)),
    ];
    let bvh = FlatBvh::build(&boxes);

    let query = Aabb::new(Vec3A::new(0.5, 0.0, 0.0), Vec3A::new(2.5, 1.0, 1.0));
    let mut out = Vec::new();
    query_aabb_overlap(&bvh, &query, &boxes, &mut out);

    assert_eq!(out.len(), 2);
    assert!(out.contains(&0));
    assert!(out.contains(&1));
    assert!(!out.contains(&2));
}

#[test]
fn test_bvh_dynamic_refit() {
    let mut boxes = vec![
        Aabb::new(Vec3A::new(0.0, 0.0, -10.0), Vec3A::new(1.0, 1.0, -9.0)),
        Aabb::new(Vec3A::new(5.0, 0.0, -10.0), Vec3A::new(6.0, 1.0, -9.0)),
    ];

    let mut bvh = FlatBvh::build(&boxes);

    let ray_at_old = Ray::new(Vec3A::new(0.5, 0.5, 0.0), -Vec3A::Z, 0.0, 100.0);
    assert!(bvh.raycast(&ray_at_old, &boxes).is_some());

    // Move entity 0 to (20.0, 0.0, -10.0)
    boxes[0] = Aabb::new(Vec3A::new(20.0, 0.0, -10.0), Vec3A::new(21.0, 1.0, -9.0));
    bvh.refit(&boxes);

    // Old location should now miss
    assert!(bvh.raycast(&ray_at_old, &boxes).is_none());

    // New location should now hit
    let ray_at_new = Ray::new(Vec3A::new(20.5, 0.5, 0.0), -Vec3A::Z, 0.0, 100.0);
    let hit = bvh.raycast(&ray_at_new, &boxes).expect("Must hit at new position");
    assert_eq!(hit.entity_id, 0);
}

#[test]
fn test_cull_frustum_exact() {
    let boxes = [
        Aabb::new(Vec3A::new(-1.0, -1.0, -10.0), Vec3A::new(1.0, 1.0, -8.0)),
        Aabb::new(Vec3A::new(-1.0, -1.0, 10.0), Vec3A::new(1.0, 1.0, 12.0)),
    ];
    let bvh = FlatBvh::build(&boxes);

    let view = Mat4::look_at_rh(Vec3::ZERO, -Vec3::Z, Vec3::Y);
    let proj = Mat4::perspective_rh(60.0_f32.to_radians(), 16.0 / 9.0, 0.1, 100.0);
    let frustum = Frustum::from_view_projection(proj * view);

    let mut visible = Vec::new();
    cull_frustum_exact(&bvh, &frustum, &boxes, &mut visible);

    assert_eq!(visible.len(), 1);
    assert_eq!(visible[0], 0);
}
