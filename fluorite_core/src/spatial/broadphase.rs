//! Dual-tree broadphase collision detection for fast candidate pair generation.

use glam::Vec3A;

use crate::spatial::bvh::FlatBvh;
use crate::spatial::math::Aabb;

/// Finds all overlapping entity pairs `(a, b)` with `a < b` within a single BVH.
///
/// Uses recursive self-collision and dual-tree traversal across disjoint subtrees,
/// pruning non-overlapping branches in $O(N \log N)$ expected time.
pub fn find_broadphase_pairs(bvh: &FlatBvh, boxes: &[Aabb]) -> Vec<(u32, u32)> {
    if bvh.is_empty() || bvh.nodes.is_empty() || boxes.len() < 2 {
        return Vec::new();
    }

    let mut pairs = Vec::new();
    collide_self(bvh, 0, boxes, &mut pairs);
    pairs.sort_unstable();
    pairs.dedup();
    pairs
}

/// Recursively detects collisions within a subtree and between its left and right children.
fn collide_self(bvh: &FlatBvh, node_idx: usize, boxes: &[Aabb], pairs: &mut Vec<(u32, u32)>) {
    let node = &bvh.nodes[node_idx];

    if node.is_leaf() {
        let start = node.left_or_first_child as usize;
        let count = node.count as usize;
        let indices = &bvh.primitive_indices[start..start + count];

        for i in 0..count {
            for j in (i + 1)..count {
                let id_a = indices[i];
                let id_b = indices[j];
                let box_a = &boxes[id_a as usize];
                let box_b = &boxes[id_b as usize];

                if box_a.intersects(box_b) {
                    let min_id = id_a.min(id_b);
                    let max_id = id_a.max(id_b);
                    pairs.push((min_id, max_id));
                }
            }
        }
    } else {
        let left_idx = node.left_or_first_child as usize;
        let right_idx = left_idx + 1;

        // Recurse into left and right subtrees
        collide_self(bvh, left_idx, boxes, pairs);
        collide_self(bvh, right_idx, boxes, pairs);

        // Test collisions between left and right subtrees
        collide_dual(bvh, left_idx, right_idx, boxes, pairs);
    }
}

/// Traverses two disjoint subtrees within the same BVH.
fn collide_dual(
    bvh: &FlatBvh,
    idx_a: usize,
    idx_b: usize,
    boxes: &[Aabb],
    pairs: &mut Vec<(u32, u32)>,
) {
    let node_a = &bvh.nodes[idx_a];
    let node_b = &bvh.nodes[idx_b];

    let a_min = Vec3A::from_slice(&node_a.aabb_min);
    let a_max = Vec3A::from_slice(&node_a.aabb_max);
    let b_min = Vec3A::from_slice(&node_b.aabb_min);
    let b_max = Vec3A::from_slice(&node_b.aabb_max);

    // Fast bounding box overlap test: if subtrees do not overlap, prune!
    if a_min.x > b_max.x
        || a_max.x < b_min.x
        || a_min.y > b_max.y
        || a_max.y < b_min.y
        || a_min.z > b_max.z
        || a_max.z < b_min.z
    {
        return;
    }

    if node_a.is_leaf() && node_b.is_leaf() {
        let start_a = node_a.left_or_first_child as usize;
        let count_a = node_a.count as usize;
        let start_b = node_b.left_or_first_child as usize;
        let count_b = node_b.count as usize;

        let indices_a = &bvh.primitive_indices[start_a..start_a + count_a];
        let indices_b = &bvh.primitive_indices[start_b..start_b + count_b];

        for &id_a in indices_a {
            for &id_b in indices_b {
                if id_a != id_b {
                    let box_a = &boxes[id_a as usize];
                    let box_b = &boxes[id_b as usize];
                    if box_a.intersects(box_b) {
                        let min_id = id_a.min(id_b);
                        let max_id = id_a.max(id_b);
                        pairs.push((min_id, max_id));
                    }
                }
            }
        }
    } else if node_a.is_leaf() {
        let left_b = node_b.left_or_first_child as usize;
        let right_b = left_b + 1;
        collide_dual(bvh, idx_a, left_b, boxes, pairs);
        collide_dual(bvh, idx_a, right_b, boxes, pairs);
    } else if node_b.is_leaf() {
        let left_a = node_a.left_or_first_child as usize;
        let right_a = left_a + 1;
        collide_dual(bvh, left_a, idx_b, boxes, pairs);
        collide_dual(bvh, right_a, idx_b, boxes, pairs);
    } else {
        // Both internal: split the one with larger surface area to minimize overlap volume
        let sa_a = (a_max - a_min).max(Vec3A::ZERO);
        let area_a = sa_a.x * sa_a.y + sa_a.y * sa_a.z + sa_a.z * sa_a.x;

        let sa_b = (b_max - b_min).max(Vec3A::ZERO);
        let area_b = sa_b.x * sa_b.y + sa_b.y * sa_b.z + sa_b.z * sa_b.x;

        if area_a > area_b {
            let left_a = node_a.left_or_first_child as usize;
            let right_a = left_a + 1;
            collide_dual(bvh, left_a, idx_b, boxes, pairs);
            collide_dual(bvh, right_a, idx_b, boxes, pairs);
        } else {
            let left_b = node_b.left_or_first_child as usize;
            let right_b = left_b + 1;
            collide_dual(bvh, idx_a, left_b, boxes, pairs);
            collide_dual(bvh, idx_a, right_b, boxes, pairs);
        }
    }
}

/// Finds all overlapping entity pairs `(a, b)` between two separate BVHs.
pub fn find_broadphase_pairs_dual(
    bvh_a: &FlatBvh,
    bvh_b: &FlatBvh,
    boxes_a: &[Aabb],
    boxes_b: &[Aabb],
) -> Vec<(u32, u32)> {
    if bvh_a.is_empty()
        || bvh_b.is_empty()
        || bvh_a.nodes.is_empty()
        || bvh_b.nodes.is_empty()
        || boxes_a.is_empty()
        || boxes_b.is_empty()
    {
        return Vec::new();
    }

    let mut pairs = Vec::new();
    collide_two_trees(bvh_a, 0, bvh_b, 0, boxes_a, boxes_b, &mut pairs);
    pairs.sort_unstable();
    pairs.dedup();
    pairs
}

fn collide_two_trees(
    bvh_a: &FlatBvh,
    idx_a: usize,
    bvh_b: &FlatBvh,
    idx_b: usize,
    boxes_a: &[Aabb],
    boxes_b: &[Aabb],
    pairs: &mut Vec<(u32, u32)>,
) {
    let node_a = &bvh_a.nodes[idx_a];
    let node_b = &bvh_b.nodes[idx_b];

    let a_min = Vec3A::from_slice(&node_a.aabb_min);
    let a_max = Vec3A::from_slice(&node_a.aabb_max);
    let b_min = Vec3A::from_slice(&node_b.aabb_min);
    let b_max = Vec3A::from_slice(&node_b.aabb_max);

    if a_min.x > b_max.x
        || a_max.x < b_min.x
        || a_min.y > b_max.y
        || a_max.y < b_min.y
        || a_min.z > b_max.z
        || a_max.z < b_min.z
    {
        return;
    }

    if node_a.is_leaf() && node_b.is_leaf() {
        let start_a = node_a.left_or_first_child as usize;
        let count_a = node_a.count as usize;
        let start_b = node_b.left_or_first_child as usize;
        let count_b = node_b.count as usize;

        let indices_a = &bvh_a.primitive_indices[start_a..start_a + count_a];
        let indices_b = &bvh_b.primitive_indices[start_b..start_b + count_b];

        for &id_a in indices_a {
            for &id_b in indices_b {
                let box_a = &boxes_a[id_a as usize];
                let box_b = &boxes_b[id_b as usize];
                if box_a.intersects(box_b) {
                    pairs.push((id_a, id_b));
                }
            }
        }
    } else if node_a.is_leaf() {
        let left_b = node_b.left_or_first_child as usize;
        let right_b = left_b + 1;
        collide_two_trees(bvh_a, idx_a, bvh_b, left_b, boxes_a, boxes_b, pairs);
        collide_two_trees(bvh_a, idx_a, bvh_b, right_b, boxes_a, boxes_b, pairs);
    } else if node_b.is_leaf() {
        let left_a = node_a.left_or_first_child as usize;
        let right_a = left_a + 1;
        collide_two_trees(bvh_a, left_a, bvh_b, idx_b, boxes_a, boxes_b, pairs);
        collide_two_trees(bvh_a, right_a, bvh_b, idx_b, boxes_a, boxes_b, pairs);
    } else {
        let sa_a = (a_max - a_min).max(Vec3A::ZERO);
        let area_a = sa_a.x * sa_a.y + sa_a.y * sa_a.z + sa_a.z * sa_a.x;

        let sa_b = (b_max - b_min).max(Vec3A::ZERO);
        let area_b = sa_b.x * sa_b.y + sa_b.y * sa_b.z + sa_b.z * sa_b.x;

        if area_a > area_b {
            let left_a = node_a.left_or_first_child as usize;
            let right_a = left_a + 1;
            collide_two_trees(bvh_a, left_a, bvh_b, idx_b, boxes_a, boxes_b, pairs);
            collide_two_trees(bvh_a, right_a, bvh_b, idx_b, boxes_a, boxes_b, pairs);
        } else {
            let left_b = node_b.left_or_first_child as usize;
            let right_b = left_b + 1;
            collide_two_trees(bvh_a, idx_a, bvh_b, left_b, boxes_a, boxes_b, pairs);
            collide_two_trees(bvh_a, idx_a, bvh_b, right_b, boxes_a, boxes_b, pairs);
        }
    }
}

/// Queries all entities in `bvh` whose bounding boxes intersect `query_box`.
pub fn query_aabb_overlap(
    bvh: &FlatBvh,
    query_box: &Aabb,
    boxes: &[Aabb],
    out: &mut Vec<u32>,
) {
    out.clear();
    if bvh.is_empty() || bvh.nodes.is_empty() {
        return;
    }

    let mut stack = [0u32; 64];
    let mut stack_ptr = 1;
    stack[0] = 0;

    let q_min = query_box.min;
    let q_max = query_box.max;

    while stack_ptr > 0 {
        stack_ptr -= 1;
        let node_idx = stack[stack_ptr] as usize;
        let node = &bvh.nodes[node_idx];

        let min = Vec3A::from_slice(&node.aabb_min);
        let max = Vec3A::from_slice(&node.aabb_max);

        if min.x > q_max.x
            || max.x < q_min.x
            || min.y > q_max.y
            || max.y < q_min.y
            || min.z > q_max.z
            || max.z < q_min.z
        {
            continue;
        }

        if node.is_leaf() {
            let start = node.left_or_first_child as usize;
            let count = node.count as usize;
            for &entity_id in &bvh.primitive_indices[start..start + count] {
                let box_aabb = &boxes[entity_id as usize];
                if query_box.intersects(box_aabb) {
                    out.push(entity_id);
                }
            }
        } else {
            let left_idx = node.left_or_first_child;
            let right_idx = left_idx + 1;
            stack[stack_ptr] = right_idx;
            stack[stack_ptr + 1] = left_idx;
            stack_ptr += 2;
        }
    }
}
