//! Zero-copy transform synchronization between Rapier3D isometries and column-major
//! 4x4 matrix storage for fluorescent_ecs and GPU rendering staging.

use super::world::PhysicsWorld;
use rapier3d::na::Isometry3;
use rapier3d::prelude::{RigidBody, RigidBodyHandle};

/// Converts a Rapier `Isometry3<f32>` (translation + unit quaternion) into a 16-element
/// column-major 4x4 transformation matrix (`[f32; 16]`).
pub fn sync_isometry_to_mat4(iso: &Isometry3<f32>) -> [f32; 16] {
    let q = glam::Quat::from_xyzw(
        iso.rotation.i,
        iso.rotation.j,
        iso.rotation.k,
        iso.rotation.w,
    );
    let t = glam::Vec3::new(iso.translation.x, iso.translation.y, iso.translation.z);
    glam::Mat4::from_rotation_translation(q, t).to_cols_array()
}

/// Extracts the world-space transform of a `RigidBody` and converts it into a 16-element
/// column-major 4x4 matrix format matching `fluorescent_ecs` 16-float stride storage.
pub fn sync_body_transform_to_mat4(body: &RigidBody) -> [f32; 16] {
    sync_isometry_to_mat4(body.position())
}

/// Batch synchronizes rigid body transforms from the `PhysicsWorld` into an ECS matrix array.
///
/// Handles are looked up in order; if a body handle is valid, its 4x4 matrix is written
/// into `out_transforms[i]`. If not found, the slot remains untouched.
pub fn sync_all_transforms_to_ecs(
    world: &PhysicsWorld,
    handles: &[RigidBodyHandle],
    out_transforms: &mut [[f32; 16]],
) {
    let count = handles.len().min(out_transforms.len());
    for i in 0..count {
        if let Some(body) = world.get_rigid_body(handles[i]) {
            out_transforms[i] = sync_body_transform_to_mat4(body);
        }
    }
}

/// Synchronizes rigid body transforms into a flat contiguous float slice (`&mut [f32]`),
/// with each matrix occupying 16 consecutive floats.
pub fn sync_all_transforms_to_slice(
    world: &PhysicsWorld,
    handles: &[RigidBodyHandle],
    out_buffer: &mut [f32],
) {
    let max_entities = handles.len().min(out_buffer.len() / 16);
    for i in 0..max_entities {
        if let Some(body) = world.get_rigid_body(handles[i]) {
            let mat = sync_body_transform_to_mat4(body);
            let start = i * 16;
            out_buffer[start..start + 16].copy_from_slice(&mat);
        }
    }
}
