//! Spatial partitioning and Bounding Volume Hierarchy (BVH) module.
//!
//! Provides high-performance 32-byte cache-aligned `FlatBvhNode` structures,
//! 16-bin Surface Area Heuristic (SAH) construction, branchless SIMD slab raycasting,
//! hierarchical box-frustum culling with inside-inheritance, and dual-tree broadphase collision pairs.

pub mod broadphase;
pub mod bvh;
pub mod culling;
pub mod math;

pub use broadphase::{find_broadphase_pairs, find_broadphase_pairs_dual, query_aabb_overlap};
pub use bvh::{FlatBvh, FlatBvhNode, RayHit};
pub use culling::{
    cull_frustum_exact, cull_frustum_hierarchical, cull_frustum_with_stats, FrustumCullingStats,
};
pub use math::{Aabb, Frustum, FrustumIntersection, Plane, Ray};
