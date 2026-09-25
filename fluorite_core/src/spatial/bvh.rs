//! BVH (Bounding Volume Hierarchy) implementation for spatial partitioning.
//! This module provides a simple flat‑array SAH‑binned BVH used for frustum culling,
//! ray‑casting and broad‑phase collision detection.

use std::cmp::Ordering;
use glam::Vec3A;

/// Axis‑aligned bounding box.
#[derive(Copy, Clone, Debug, PartialEq)]
pub struct Aabb {
    pub min: Vec3A,
    pub max: Vec3A,
}

impl Aabb {
    /// Returns a new AABB from min and max vectors.
    #[inline]
    pub fn new(min: Vec3A, max: Vec3A) -> Self {
        Self { min, max }
    }

    /// Returns the surface area (used for SAH).
    #[inline]
    pub fn surface_area(&self) -> f32 {
        let d = self.max - self.min;
        2.0 * (d.x * d.y + d.y * d.z + d.z * d.x)
    }

    /// Returns a merged AABB containing `self` and `other`.
    #[inline]
    pub fn union(&self, other: &Aabb) -> Aabb {
        Aabb {
            min: self.min.min(other.min),
            max: self.max.max(other.max),
        }
    }
}

/// Flat‑array BVH node.
#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct BvhNode {
    pub aabb_min: [f32; 3],
    pub aabb_max: [f32; 3],
    pub left: u32,          // index of left child (or primitive start if leaf)
    pub right: u32,         // index of right child (or primitive count if leaf)
    pub first_primitive: u32,
    pub primitive_count: u32,
}

impl BvhNode {
    #[inline]
    fn leaf(first: u32, count: u32, bounds: &Aabb) -> Self {
        Self {
            aabb_min: bounds.min.to_array(),
            aabb_max: bounds.max.to_array(),
            left: 0,
            right: 0,
            first_primitive: first,
            primitive_count: count,
        }
    }

    #[inline]
    fn interior(left: u32, right: u32, bounds: &Aabb) -> Self {
        Self {
            aabb_min: bounds.min.to_array(),
            aabb_max: bounds.max.to_array(),
            left,
            right,
            first_primitive: 0,
            primitive_count: 0,
        }
    }
}

/// Simple BVH builder using recursive median split.
pub struct BvhBuilder {
    nodes: Vec<BvhNode>,
    primitives: Vec<Aabb>,
}

impl BvhBuilder {
    /// Build a BVH from a slice of primitives.
    /// Returns the flat node list.
    pub fn build(primitives: &[Aabb]) -> Vec<BvhNode> {
        let mut builder = Self {
            nodes: Vec::new(),
            primitives: primitives.to_vec(),
        };
        builder.build_recursive(0, primitives.len() as u32);
        builder.nodes
    }

    fn build_recursive(&mut self, start: u32, count: u32) -> u32 {
        // Compute bounds for this range.
        let mut bounds = self.primitives[start as usize];
        for i in (start + 1)..(start + count) {
            bounds = bounds.union(&self.primitives[i as usize]);
        }

        if count <= 4 {
            // Create leaf node.
            let leaf = BvhNode::leaf(start, count, &bounds);
            let idx = self.nodes.len() as u32;
            self.nodes.push(leaf);
            return idx;
        }

        // Choose split axis by longest extent.
        let extent = bounds.max - bounds.min;
        let axis = if extent.x > extent.y && extent.x > extent.z {
            0
        } else if extent.y > extent.z {
            1
        } else {
            2
        };

        // Partition primitives around median.
        let mid = (start + count / 2) as usize;
        self.primitives[start as usize..(start + count) as usize]
            .select_nth_unstable_by(mid - start as usize, |a, b| {
                a.min[axis]
                    .partial_cmp(&b.min[axis])
                    .unwrap_or(Ordering::Equal)
            });

        let left_idx = self.build_recursive(start, count / 2);
        let right_idx = self.build_recursive(start + count / 2, count - count / 2);

        let interior = BvhNode::interior(left_idx, right_idx, &bounds);
        let idx = self.nodes.len() as u32;
        self.nodes.push(interior);
        idx
    }
}

/// Utility function for ray–AABB intersection (used by queries).
#[inline]
pub fn intersect_aabb(origin: Vec3A, dir_inv: Vec3A, aabb: &Aabb) -> bool {
    let t1 = (aabb.min - origin) * dir_inv;
    let t2 = (aabb.max - origin) * dir_inv;
    let tmin = t1.min(t2);
    let tmax = t1.max(t2);
    let t_enter = tmin.max_element();
    let t_exit = tmax.min_element();
    t_exit >= t_enter && t_exit >= 0.0
}

// The module is intentionally lightweight; more advanced SAH binning can be added later.
