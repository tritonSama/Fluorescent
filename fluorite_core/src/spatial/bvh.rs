//! Flat-array Bounding Volume Hierarchy (BVH) with 16-bin SAH construction and SIMD slab raycasting.

use glam::Vec3A;

use crate::spatial::broadphase;
use crate::spatial::culling;
use crate::spatial::math::{Aabb, Frustum, Ray};

/// A flat, cache-aligned BVH node designed for SIMD acceleration and direct GPU upload.
///
/// Layout:
/// - `aabb_min`: 3x f32 (12 bytes)
/// - `left_or_first_child`: u32 (4 bytes)
/// - `aabb_max`: 3x f32 (12 bytes)
/// - `count`: u32 (4 bytes)
/// Total size: exactly 32 bytes.
/// Alignment: 32 bytes (2 nodes fit perfectly into a single 64-byte hardware cache line).
#[repr(C, align(32))]
#[derive(Clone, Copy, Debug, PartialEq, bytemuck::Pod, bytemuck::Zeroable)]
pub struct FlatBvhNode {
    /// Bounding box minimum coordinates [min_x, min_y, min_z].
    pub aabb_min: [f32; 3],
    /// If count == 0 (internal node): index of the left child. (Right child is at index + 1).
    /// If count > 0 (leaf node): offset into the BVH `primitive_indices` array.
    pub left_or_first_child: u32,
    /// Bounding box maximum coordinates [max_x, max_y, max_z].
    pub aabb_max: [f32; 3],
    /// Number of primitives in this node. 0 indicates an internal node.
    pub count: u32,
}

impl Default for FlatBvhNode {
    #[inline]
    fn default() -> Self {
        Self {
            aabb_min: [0.0; 3],
            left_or_first_child: 0,
            aabb_max: [0.0; 3],
            count: 0,
        }
    }
}

impl FlatBvhNode {
    /// Creates a leaf node containing primitives.
    #[inline]
    pub fn leaf(first_primitive: u32, count: u32, aabb: &Aabb) -> Self {
        Self {
            aabb_min: aabb.min_array(),
            left_or_first_child: first_primitive,
            aabb_max: aabb.max_array(),
            count,
        }
    }

    /// Creates an internal node referencing its left child.
    #[inline]
    pub fn internal(left_child: u32, aabb: &Aabb) -> Self {
        Self {
            aabb_min: aabb.min_array(),
            left_or_first_child: left_child,
            aabb_max: aabb.max_array(),
            count: 0,
        }
    }

    /// Returns true if this node is a leaf containing primitives.
    #[inline]
    pub fn is_leaf(&self) -> bool {
        self.count > 0
    }

    /// Reconstructs the node's `Aabb`.
    #[inline]
    pub fn aabb(&self) -> Aabb {
        Aabb::from_arrays(self.aabb_min, self.aabb_max)
    }

    /// Updates this node's bounding box coordinates.
    #[inline]
    pub fn set_aabb(&mut self, aabb: &Aabb) {
        self.aabb_min = aabb.min_array();
        self.aabb_max = aabb.max_array();
    }

    /// Left child index (internal nodes only).
    #[inline]
    pub fn left_child(&self) -> u32 {
        self.left_or_first_child
    }

    /// Right child index (internal nodes only, always adjacent to left child).
    #[inline]
    pub fn right_child(&self) -> u32 {
        self.left_or_first_child + 1
    }

    /// First primitive offset into `primitive_indices` (leaf nodes only).
    #[inline]
    pub fn first_primitive(&self) -> u32 {
        self.left_or_first_child
    }

    /// Primitive count (leaf nodes only).
    #[inline]
    pub fn primitive_count(&self) -> u32 {
        self.count
    }
}

/// Hit information resulting from a raycast against the BVH.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RayHit {
    /// Index / entity ID of the hit primitive.
    pub entity_id: u32,
    /// Distance along the ray to the entry point.
    pub distance: f32,
    /// World-space intersection point.
    pub point: Vec3A,
}

/// Temporary struct used during BVH build.
#[derive(Clone, Copy, Debug)]
struct PrimitiveInfo {
    index: u32,
    aabb: Aabb,
    centroid: Vec3A,
}

/// Flat linear Bounding Volume Hierarchy.
///
/// Stores nodes in depth-first order such that left and right children are always contiguous
/// in memory (`right_child = left_child + 1`).
#[derive(Clone, Debug)]
pub struct FlatBvh {
    /// Flat array of 32-byte cache-aligned BVH nodes.
    pub nodes: Vec<FlatBvhNode>,
    /// Indirection array storing reordered primitive indices.
    pub primitive_indices: Vec<u32>,
}

impl Default for FlatBvh {
    fn default() -> Self {
        Self {
            nodes: Vec::new(),
            primitive_indices: Vec::new(),
        }
    }
}

impl FlatBvh {
    /// Builds a BVH from a slice of bounding boxes using the default 16-bin SAH builder.
    pub fn build(boxes: &[Aabb]) -> Self {
        Self::build_binned_sah(boxes, 16)
    }

    /// Builds a BVH from a slice of bounding boxes using binned Surface Area Heuristic (SAH).
    pub fn build_binned_sah(boxes: &[Aabb], num_bins: usize) -> Self {
        let indices: Vec<u32> = (0..boxes.len() as u32).collect();
        Self::build_with_indices(boxes, &indices, num_bins)
    }

    /// Builds a BVH from bounding boxes and associated entity IDs.
    pub fn build_with_indices(boxes: &[Aabb], indices: &[u32], num_bins: usize) -> Self {
        let n = boxes.len();
        if n == 0 {
            return Self {
                nodes: vec![FlatBvhNode::default()],
                primitive_indices: Vec::new(),
            };
        }

        if n == 1 {
            return Self {
                nodes: vec![FlatBvhNode::leaf(0, 1, &boxes[0])],
                primitive_indices: vec![indices[0]],
            };
        }

        let mut items: Vec<PrimitiveInfo> = (0..n)
            .map(|i| PrimitiveInfo {
                index: indices[i],
                aabb: boxes[i],
                centroid: boxes[i].center(),
            })
            .collect();

        let mut nodes = Vec::with_capacity(2 * n);
        nodes.push(FlatBvhNode::default()); // Root node slot at index 0

        Self::build_recursive(&mut nodes, &mut items, 0, 0, n, num_bins.clamp(2, 32));

        let primitive_indices = items.iter().map(|item| item.index).collect();

        Self {
            nodes,
            primitive_indices,
        }
    }

    fn build_recursive(
        nodes: &mut Vec<FlatBvhNode>,
        items: &mut [PrimitiveInfo],
        node_idx: usize,
        start: usize,
        count: usize,
        num_bins: usize,
    ) {
        // Compute bounding box and centroid bounds for this partition
        let mut node_aabb = items[start].aabb;
        let mut centroid_aabb = Aabb::from_point(items[start].centroid);

        for item in &items[start + 1..start + count] {
            node_aabb = node_aabb.merge(&item.aabb);
            centroid_aabb = centroid_aabb.expand_to_point(item.centroid);
        }

        // Base case: small primitive count -> create leaf
        if count <= 4 {
            nodes[node_idx] = FlatBvhNode::leaf(start as u32, count as u32, &node_aabb);
            return;
        }

        // Check for degenerate centroid span
        let centroid_span = centroid_aabb.size();
        if centroid_span.x <= 1e-6 && centroid_span.y <= 1e-6 && centroid_span.z <= 1e-6 {
            nodes[node_idx] = FlatBvhNode::leaf(start as u32, count as u32, &node_aabb);
            return;
        }

        // Evaluate SAH cost across 3 axes
        let parent_sa = node_aabb.surface_area().max(1e-6);
        let leaf_cost = count as f32;
        let mut best_cost = f32::INFINITY;
        let mut best_axis = 0;
        let mut best_split_bin = 0;

        for axis in 0..3 {
            let axis_min = centroid_aabb.min[axis];
            let axis_max = centroid_aabb.max[axis];
            let span = axis_max - axis_min;
            if span <= 1e-6 {
                continue;
            }

            #[derive(Clone, Copy)]
            struct Bin {
                count: u32,
                aabb: Aabb,
            }
            let mut bins = [Bin {
                count: 0,
                aabb: Aabb::EMPTY,
            }; 32];
            let bins_slice = &mut bins[..num_bins];

            let scale = num_bins as f32 / span;
            for item in &items[start..start + count] {
                let bin_idx =
                    (((item.centroid[axis] - axis_min) * scale) as usize).min(num_bins - 1);
                bins_slice[bin_idx].count += 1;
                bins_slice[bin_idx].aabb = bins_slice[bin_idx].aabb.merge(&item.aabb);
            }

            // Prefix sweep (left to right)
            let mut left_boxes = [Aabb::EMPTY; 32];
            let mut left_counts = [0u32; 32];
            let mut acc_box = Aabb::EMPTY;
            let mut acc_count = 0u32;
            for k in 0..num_bins {
                acc_box = acc_box.merge(&bins_slice[k].aabb);
                acc_count += bins_slice[k].count;
                left_boxes[k] = acc_box;
                left_counts[k] = acc_count;
            }

            // Suffix sweep (right to left)
            let mut right_boxes = [Aabb::EMPTY; 32];
            let mut right_counts = [0u32; 32];
            acc_box = Aabb::EMPTY;
            acc_count = 0u32;
            for k in (0..num_bins).rev() {
                acc_box = acc_box.merge(&bins_slice[k].aabb);
                acc_count += bins_slice[k].count;
                right_boxes[k] = acc_box;
                right_counts[k] = acc_count;
            }

            // Test candidate split planes between bin k and bin k + 1
            for k in 0..(num_bins - 1) {
                let count_l = left_counts[k];
                let count_r = right_counts[k + 1];
                if count_l == 0 || count_r == 0 {
                    continue;
                }
                let sa_l = left_boxes[k].surface_area();
                let sa_r = right_boxes[k + 1].surface_area();

                // C_split = C_trav (1.0) + (SA_L * N_L + SA_R * N_R) / SA_Parent
                let cost = 1.0 + (sa_l * count_l as f32 + sa_r * count_r as f32) / parent_sa;
                if cost < best_cost {
                    best_cost = cost;
                    best_axis = axis;
                    best_split_bin = k;
                }
            }
        }

        // If split does not improve cost over making a leaf, and primitive count is small
        if best_cost >= leaf_cost && count <= 8 {
            nodes[node_idx] = FlatBvhNode::leaf(start as u32, count as u32, &node_aabb);
            return;
        }

        // Partition primitives around optimal split plane
        let mut left_count = 0;
        if best_cost < f32::INFINITY {
            let axis_min = centroid_aabb.min[best_axis];
            let span = centroid_aabb.max[best_axis] - axis_min;
            let scale = num_bins as f32 / span;
            let split_bin = best_split_bin;
            let axis = best_axis;

            let mut left = 0;
            for idx in 0..count {
                let bin = (((items[start + idx].centroid[axis] - axis_min) * scale) as usize)
                    .min(num_bins - 1);
                if bin <= split_bin {
                    items.swap(start + left, start + idx);
                    left += 1;
                }
            }
            left_count = left;
        }

        // If partition failed to split (e.g. edge-case numerical rounding), fall back to median split
        if left_count == 0 || left_count == count {
            let extent = centroid_span;
            let axis = if extent.x >= extent.y && extent.x >= extent.z {
                0
            } else if extent.y >= extent.z {
                1
            } else {
                2
            };
            let mid = count / 2;
            items[start..start + count].select_nth_unstable_by(mid, |a, b| {
                a.centroid[axis]
                    .partial_cmp(&b.centroid[axis])
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            left_count = mid;
        }

        let right_count = count - left_count;

        // Allocate left and right children contiguously
        let left_idx = nodes.len() as u32;
        let right_idx = left_idx + 1;
        nodes.push(FlatBvhNode::default());
        nodes.push(FlatBvhNode::default());
        nodes[node_idx] = FlatBvhNode::internal(left_idx, &node_aabb);

        // Recurse left and right
        Self::build_recursive(nodes, items, left_idx as usize, start, left_count, num_bins);
        Self::build_recursive(
            nodes,
            items,
            right_idx as usize,
            start + left_count,
            right_count,
            num_bins,
        );
    }

    /// Returns true if the BVH contains no primitives.
    #[inline]
    pub fn is_empty(&self) -> bool {
        self.primitive_indices.is_empty()
    }

    /// Returns the root bounding box of the entire hierarchy.
    pub fn root_aabb(&self) -> Option<Aabb> {
        if self.is_empty() || self.nodes.is_empty() {
            None
        } else {
            Some(self.nodes[0].aabb())
        }
    }

    /// Refits bounding boxes of an existing BVH after dynamic entities have moved.
    ///
    /// Executes a bottom-up pass in $O(N)$ time with zero heap allocations.
    pub fn refit(&mut self, boxes: &[Aabb]) {
        if self.is_empty() {
            return;
        }

        for i in (0..self.nodes.len()).rev() {
            if self.nodes[i].is_leaf() {
                let start = self.nodes[i].left_or_first_child as usize;
                let count = self.nodes[i].count as usize;
                let mut aabb = Aabb::EMPTY;
                for &entity_id in &self.primitive_indices[start..start + count] {
                    aabb = aabb.merge(&boxes[entity_id as usize]);
                }
                self.nodes[i].set_aabb(&aabb);
            } else {
                let left_idx = self.nodes[i].left_or_first_child as usize;
                let right_idx = left_idx + 1;
                let left_aabb = self.nodes[left_idx].aabb();
                let right_aabb = self.nodes[right_idx].aabb();
                let merged = left_aabb.merge(&right_aabb);
                self.nodes[i].set_aabb(&merged);
            }
        }
    }

    /// Casts a ray through the BVH using branchless SIMD slab tests with front-to-back ordering
    /// and dynamic `t_max` clipping.
    pub fn raycast(&self, ray: &Ray, boxes: &[Aabb]) -> Option<RayHit> {
        if self.is_empty() {
            return None;
        }

        let mut nearest_hit: Option<RayHit> = None;
        let mut current_t_max = ray.t_max;

        let mut stack = [0u32; 64];
        let mut stack_ptr = 1;
        stack[0] = 0; // Root node index

        while stack_ptr > 0 {
            stack_ptr -= 1;
            let node_idx = stack[stack_ptr] as usize;
            let node = &self.nodes[node_idx];

            let min = Vec3A::from_slice(&node.aabb_min);
            let max = Vec3A::from_slice(&node.aabb_max);
            let (hit, t_enter) = ray.slab_test_with_tmax(min, max, current_t_max);
            if !hit || t_enter > current_t_max {
                continue;
            }

            if node.is_leaf() {
                let start = node.left_or_first_child as usize;
                let count = node.count as usize;
                for &entity_id in &self.primitive_indices[start..start + count] {
                    let box_aabb = &boxes[entity_id as usize];
                    if let Some(t) = ray.intersects_aabb_tmax(box_aabb, current_t_max) {
                        if t < current_t_max {
                            current_t_max = t;
                            nearest_hit = Some(RayHit {
                                entity_id,
                                distance: t,
                                point: ray.at(t),
                            });
                        }
                    }
                }
            } else {
                let left_idx = node.left_or_first_child as usize;
                let right_idx = left_idx + 1;

                let left_node = &self.nodes[left_idx];
                let right_node = &self.nodes[right_idx];

                let left_min = Vec3A::from_slice(&left_node.aabb_min);
                let left_max = Vec3A::from_slice(&left_node.aabb_max);
                let (left_hit, left_t) = ray.slab_test_with_tmax(left_min, left_max, current_t_max);

                let right_min = Vec3A::from_slice(&right_node.aabb_min);
                let right_max = Vec3A::from_slice(&right_node.aabb_max);
                let (right_hit, right_t) =
                    ray.slab_test_with_tmax(right_min, right_max, current_t_max);

                match (
                    left_hit && left_t <= current_t_max,
                    right_hit && right_t <= current_t_max,
                ) {
                    (true, true) => {
                        if left_t < right_t {
                            stack[stack_ptr] = right_idx as u32;
                            stack[stack_ptr + 1] = left_idx as u32;
                        } else {
                            stack[stack_ptr] = left_idx as u32;
                            stack[stack_ptr + 1] = right_idx as u32;
                        }
                        stack_ptr += 2;
                    }
                    (true, false) => {
                        stack[stack_ptr] = left_idx as u32;
                        stack_ptr += 1;
                    }
                    (false, true) => {
                        stack[stack_ptr] = right_idx as u32;
                        stack_ptr += 1;
                    }
                    (false, false) => {}
                }
            }
        }

        nearest_hit
    }

    /// Fast shadow / occlusion test returning `true` immediately upon finding any intersection.
    pub fn raycast_any(&self, ray: &Ray, boxes: &[Aabb]) -> bool {
        if self.is_empty() {
            return false;
        }

        let mut stack = [0u32; 64];
        let mut stack_ptr = 1;
        stack[0] = 0;

        while stack_ptr > 0 {
            stack_ptr -= 1;
            let node_idx = stack[stack_ptr] as usize;
            let node = &self.nodes[node_idx];

            let min = Vec3A::from_slice(&node.aabb_min);
            let max = Vec3A::from_slice(&node.aabb_max);
            let (hit, t_enter) = ray.slab_test_with_tmax(min, max, ray.t_max);
            if !hit || t_enter > ray.t_max {
                continue;
            }

            if node.is_leaf() {
                let start = node.left_or_first_child as usize;
                let count = node.count as usize;
                for &entity_id in &self.primitive_indices[start..start + count] {
                    let box_aabb = &boxes[entity_id as usize];
                    if ray.intersects_aabb(box_aabb).is_some() {
                        return true;
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

        false
    }

    /// Executes hierarchical box-frustum culling with inside-inheritance and outside-pruning.
    #[inline]
    pub fn cull_frustum(&self, frustum: &Frustum, visible_entities: &mut Vec<u32>) {
        culling::cull_frustum_hierarchical(self, frustum, visible_entities);
    }

    /// Generates candidate overlapping entity pairs via dual-tree traversal.
    #[inline]
    pub fn find_overlapping_pairs(&self, boxes: &[Aabb]) -> Vec<(u32, u32)> {
        broadphase::find_broadphase_pairs(self, boxes)
    }

    /// Generates candidate overlapping entity pairs between two separate BVHs.
    #[inline]
    pub fn find_overlapping_pairs_with(
        &self,
        other: &FlatBvh,
        boxes_self: &[Aabb],
        boxes_other: &[Aabb],
    ) -> Vec<(u32, u32)> {
        broadphase::find_broadphase_pairs_dual(self, other, boxes_self, boxes_other)
    }
}
