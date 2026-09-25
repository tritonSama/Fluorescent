//! Hierarchical box-frustum culling with inside-inheritance and outside-pruning.

use glam::Vec3A;

use crate::spatial::bvh::FlatBvh;
use crate::spatial::math::{Aabb, Frustum, FrustumIntersection};

/// Diagnostic performance statistics for a frustum culling query.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct FrustumCullingStats {
    /// Total number of BVH nodes tested against frustum planes.
    pub nodes_tested: usize,
    /// Number of subtrees pruned because they were strictly outside the frustum.
    pub subtrees_pruned_outside: usize,
    /// Number of subtrees accepted without plane tests due to inside-inheritance.
    pub subtrees_inherited_inside: usize,
    /// Number of visible entity IDs emitted.
    pub visible_count: usize,
}

/// Executes hierarchical box-frustum culling on a `FlatBvh`.
///
/// Features:
/// - Outside-pruning: rejects entire subtrees in $O(1)$ when their AABB lies outside any frustum plane.
/// - Inside-inheritance: when an AABB is fully inside all 6 frustum planes, all sub-nodes and leaf
///   primitives are unconditionally accepted, bypassing all subsequent plane tests.
/// - Zero heap allocations during traversal (uses an explicit fixed stack of 64 entries).
pub fn cull_frustum_hierarchical(
    bvh: &FlatBvh,
    frustum: &Frustum,
    visible_entities: &mut Vec<u32>,
) {
    visible_entities.clear();
    if bvh.is_empty() || bvh.nodes.is_empty() {
        return;
    }

    let mut stack = [0u32; 64];
    let mut stack_ptr = 1;
    stack[0] = 0; // Root node index

    while stack_ptr > 0 {
        stack_ptr -= 1;
        let node_idx = stack[stack_ptr] as usize;
        let node = &bvh.nodes[node_idx];

        let min = Vec3A::from_slice(&node.aabb_min);
        let max = Vec3A::from_slice(&node.aabb_max);

        match frustum.test_min_max(min, max) {
            FrustumIntersection::Outside => {
                // Prune entire subtree
                continue;
            }
            FrustumIntersection::Inside => {
                // Inside-inheritance: all descendants are guaranteed to be inside.
                // Harvest all primitives in this subtree without any further plane checks.
                collect_subtree_primitives(bvh, node_idx, visible_entities);
            }
            FrustumIntersection::Intersecting => {
                if node.is_leaf() {
                    let start = node.left_or_first_child as usize;
                    let count = node.count as usize;
                    visible_entities
                        .extend_from_slice(&bvh.primitive_indices[start..start + count]);
                } else {
                    let left_child = node.left_or_first_child;
                    let right_child = left_child + 1;
                    stack[stack_ptr] = right_child;
                    stack[stack_ptr + 1] = left_child;
                    stack_ptr += 2;
                }
            }
        }
    }
}

/// Frustum culling variant collecting detailed diagnostic metrics.
pub fn cull_frustum_with_stats(
    bvh: &FlatBvh,
    frustum: &Frustum,
    visible_entities: &mut Vec<u32>,
) -> FrustumCullingStats {
    let mut stats = FrustumCullingStats::default();
    visible_entities.clear();

    if bvh.is_empty() || bvh.nodes.is_empty() {
        return stats;
    }

    let mut stack = [0u32; 64];
    let mut stack_ptr = 1;
    stack[0] = 0;

    while stack_ptr > 0 {
        stack_ptr -= 1;
        let node_idx = stack[stack_ptr] as usize;
        let node = &bvh.nodes[node_idx];
        stats.nodes_tested += 1;

        let min = Vec3A::from_slice(&node.aabb_min);
        let max = Vec3A::from_slice(&node.aabb_max);

        match frustum.test_min_max(min, max) {
            FrustumIntersection::Outside => {
                stats.subtrees_pruned_outside += 1;
                continue;
            }
            FrustumIntersection::Inside => {
                stats.subtrees_inherited_inside += 1;
                collect_subtree_primitives(bvh, node_idx, visible_entities);
            }
            FrustumIntersection::Intersecting => {
                if node.is_leaf() {
                    let start = node.left_or_first_child as usize;
                    let count = node.count as usize;
                    visible_entities
                        .extend_from_slice(&bvh.primitive_indices[start..start + count]);
                } else {
                    let left_child = node.left_or_first_child;
                    let right_child = left_child + 1;
                    stack[stack_ptr] = right_child;
                    stack[stack_ptr + 1] = left_child;
                    stack_ptr += 2;
                }
            }
        }
    }

    stats.visible_count = visible_entities.len();
    stats
}

/// Executes exact primitive-level frustum culling.
///
/// In intersecting leaf nodes, each individual entity AABB is tested against the frustum,
/// eliminating any conservative false positives at the frustum boundaries.
pub fn cull_frustum_exact(
    bvh: &FlatBvh,
    frustum: &Frustum,
    boxes: &[Aabb],
    visible_entities: &mut Vec<u32>,
) {
    visible_entities.clear();
    if bvh.is_empty() || bvh.nodes.is_empty() {
        return;
    }

    let mut stack = [0u32; 64];
    let mut stack_ptr = 1;
    stack[0] = 0;

    while stack_ptr > 0 {
        stack_ptr -= 1;
        let node_idx = stack[stack_ptr] as usize;
        let node = &bvh.nodes[node_idx];

        let min = Vec3A::from_slice(&node.aabb_min);
        let max = Vec3A::from_slice(&node.aabb_max);

        match frustum.test_min_max(min, max) {
            FrustumIntersection::Outside => continue,
            FrustumIntersection::Inside => {
                collect_subtree_primitives(bvh, node_idx, visible_entities);
            }
            FrustumIntersection::Intersecting => {
                if node.is_leaf() {
                    let start = node.left_or_first_child as usize;
                    let count = node.count as usize;
                    for &entity_id in &bvh.primitive_indices[start..start + count] {
                        let box_aabb = &boxes[entity_id as usize];
                        if frustum.test_aabb(box_aabb) != FrustumIntersection::Outside {
                            visible_entities.push(entity_id);
                        }
                    }
                } else {
                    let left_child = node.left_or_first_child;
                    let right_child = left_child + 1;
                    stack[stack_ptr] = right_child;
                    stack[stack_ptr + 1] = left_child;
                    stack_ptr += 2;
                }
            }
        }
    }
}

/// Fast unconditional traversal appending all primitives in a subtree without any plane tests.
fn collect_subtree_primitives(bvh: &FlatBvh, root_idx: usize, visible: &mut Vec<u32>) {
    let mut stack = [0u32; 64];
    let mut stack_ptr = 1;
    stack[0] = root_idx as u32;

    while stack_ptr > 0 {
        stack_ptr -= 1;
        let node_idx = stack[stack_ptr] as usize;
        let node = &bvh.nodes[node_idx];

        if node.is_leaf() {
            let start = node.left_or_first_child as usize;
            let count = node.count as usize;
            visible.extend_from_slice(&bvh.primitive_indices[start..start + count]);
        } else {
            let left_child = node.left_or_first_child;
            let right_child = left_child + 1;
            stack[stack_ptr] = right_child;
            stack[stack_ptr + 1] = left_child;
            stack_ptr += 2;
        }
    }
}
