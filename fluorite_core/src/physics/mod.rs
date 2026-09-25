//! Physics Subsystem: High-performance 3D rigid body dynamics, continuous collision
//! detection (CCD), kinematic character controller (KCC), and zero-copy ECS transform sync.

pub mod character_controller;
pub mod sync;
pub mod world;

pub use character_controller::{CharacterController, CharacterMovementResult};
pub use sync::{
    sync_all_transforms_to_ecs, sync_all_transforms_to_slice, sync_body_transform_to_mat4,
    sync_isometry_to_mat4,
};
pub use world::{PhysicsWorld, StepStats};

// Re-export nalgebra via Rapier
pub use rapier3d::na as nalgebra;

// Re-export common Rapier types and builders for consumer convenience
pub use rapier3d::prelude::{
    ActiveCollisionTypes, ActiveEvents, Ball, BroadPhaseMultiSap, CCDSolver, Capsule,
    Collider, ColliderBuilder, ColliderHandle, ColliderSet, Cone, Cuboid, Cylinder,
    DefaultBroadPhase, ImpulseJointHandle, ImpulseJointSet, IntegrationParameters,
    IslandManager, KinematicCharacterController, MultibodyJointHandle, MultibodyJointSet,
    NarrowPhase, PhysicsPipeline, QueryFilter, QueryPipeline, Real, RigidBody,
    RigidBodyActivation, RigidBodyBuilder, RigidBodyHandle, RigidBodySet, RigidBodyType,
};
