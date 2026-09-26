//! PhysicsWorld: Encapsulates Rapier3D physics pipeline, rigid body and collider sets,
//! fixed 60Hz timestep substepping accumulator, and entity registration.

use rapier3d::na::Vector3;
use rapier3d::prelude::*;

/// Statistics returned after stepping the physics world.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct StepStats {
    /// Number of fixed-timestep substeps executed during this step call.
    pub substeps: u32,
    /// Time remaining in the accumulator (< fixed_timestep).
    pub remaining_accumulator: f32,
    /// Total simulated time across all substeps executed.
    pub simulated_time: f32,
}

/// The Fluorite physics simulation world managing Rapier3D pipelines and state.
pub struct PhysicsWorld {
    /// Gravity vector in world space (default: [0.0, -9.81, 0.0]).
    pub gravity: Vector3<f32>,
    /// Integration parameters (timestep, solver iterations, etc.).
    pub integration_parameters: IntegrationParameters,
    /// Main physics simulation pipeline.
    pub physics_pipeline: PhysicsPipeline,
    /// Simulation island manager for sleep and wake states.
    pub island_manager: IslandManager,
    /// Broad phase collision detection.
    pub broad_phase: BroadPhase,
    /// Narrow phase collision detection and contact manifold computation.
    pub narrow_phase: NarrowPhase,
    /// Collection of all active rigid bodies.
    pub rigid_body_set: RigidBodySet,
    /// Collection of all colliders.
    pub collider_set: ColliderSet,
    /// Impulse joints (revolute, prismatic, spherical, fixed).
    pub impulse_joint_set: ImpulseJointSet,
    /// Multibody articulated joints.
    pub multibody_joint_set: MultibodyJointSet,
    /// Continuous collision detection solver to prevent tunneling.
    pub ccd_solver: CCDSolver,
    /// Query pipeline for raycasting, shapecasting, and point queries.
    pub query_pipeline: QueryPipeline,

    /// Fixed timestep delta time in seconds (default: 1.0 / 60.0).
    pub fixed_timestep: f32,
    /// Accumulator for fractional frame time.
    pub accumulator: f32,
    /// Maximum number of substeps allowed per frame to prevent spiral of death.
    pub max_substeps: u32,
}

impl Default for PhysicsWorld {
    fn default() -> Self {
        Self::new()
    }
}

impl PhysicsWorld {
    /// Creates a new `PhysicsWorld` with default gravity (-9.81 on Y) and a 60Hz fixed timestep.
    pub fn new() -> Self {
        Self::with_gravity(Vector3::new(0.0, -9.81, 0.0))
    }

    /// Creates a new `PhysicsWorld` with a specified gravity vector.
    pub fn with_gravity(gravity: Vector3<f32>) -> Self {
        let fixed_timestep = 1.0 / 60.0;
        let mut integration_parameters = IntegrationParameters::default();
        integration_parameters.dt = fixed_timestep;

        Self {
            gravity,
            integration_parameters,
            physics_pipeline: PhysicsPipeline::new(),
            island_manager: IslandManager::new(),
            broad_phase: BroadPhase::new(),
            narrow_phase: NarrowPhase::new(),
            rigid_body_set: RigidBodySet::new(),
            collider_set: ColliderSet::new(),
            impulse_joint_set: ImpulseJointSet::new(),
            multibody_joint_set: MultibodyJointSet::new(),
            ccd_solver: CCDSolver::new(),
            query_pipeline: QueryPipeline::new(),
            fixed_timestep,
            accumulator: 0.0,
            max_substeps: 4,
        }
    }

    /// Sets the world gravity vector.
    pub fn set_gravity(&mut self, gravity: Vector3<f32>) {
        self.gravity = gravity;
    }

    /// Steps the physics simulation by `dt` seconds, accumulating delta time
    /// and executing fixed-timestep substeps (up to `max_substeps`).
    pub fn step(&mut self, dt: f32) -> StepStats {
        self.accumulator += dt;

        // Spiral-of-death clamp
        let max_accum = self.fixed_timestep * self.max_substeps as f32;
        if self.accumulator > max_accum {
            self.accumulator = max_accum;
        }

        let mut substeps = 0;
        while self.accumulator >= self.fixed_timestep && substeps < self.max_substeps {
            self.step_single_frame();
            self.accumulator -= self.fixed_timestep;
            substeps += 1;
        }

        StepStats {
            substeps,
            remaining_accumulator: self.accumulator,
            simulated_time: substeps as f32 * self.fixed_timestep,
        }
    }

    /// Advances the physics simulation by exactly one fixed timestep.
    pub fn step_single_frame(&mut self) {
        let physics_hooks = ();
        let event_handler = ();

        self.physics_pipeline.step(
            &self.gravity,
            &self.integration_parameters,
            &mut self.island_manager,
            &mut self.broad_phase,
            &mut self.narrow_phase,
            &mut self.rigid_body_set,
            &mut self.collider_set,
            &mut self.impulse_joint_set,
            &mut self.multibody_joint_set,
            &mut self.ccd_solver,
            Some(&mut self.query_pipeline),
            &event_handler,
            &event_handler,
        );

        // Synchronize the query pipeline with updated rigid bodies and colliders
        self.query_pipeline
            .update(&self.rigid_body_set, &self.collider_set);
    }

    /// Inserts a rigid body into the simulation and returns its handle.
    pub fn insert_rigid_body(&mut self, body: RigidBody) -> RigidBodyHandle {
        self.rigid_body_set.insert(body)
    }

    /// Inserts a collider attached to a parent rigid body.
    pub fn insert_collider(
        &mut self,
        collider: Collider,
        parent: RigidBodyHandle,
    ) -> ColliderHandle {
        self.collider_set
            .insert_with_parent(collider, parent, &mut self.rigid_body_set)
    }

    /// Inserts a standalone collider (e.g. static environment) not attached to any rigid body.
    pub fn insert_standalone_collider(&mut self, collider: Collider) -> ColliderHandle {
        self.collider_set.insert(collider)
    }

    /// Retrieves an immutable reference to a rigid body.
    pub fn get_rigid_body(&self, handle: RigidBodyHandle) -> Option<&RigidBody> {
        self.rigid_body_set.get(handle)
    }

    /// Retrieves a mutable reference to a rigid body.
    pub fn get_rigid_body_mut(&mut self, handle: RigidBodyHandle) -> Option<&mut RigidBody> {
        self.rigid_body_set.get_mut(handle)
    }

    /// Removes a rigid body and all attached colliders and joints from the world.
    pub fn remove_rigid_body(&mut self, handle: RigidBodyHandle) -> Option<RigidBody> {
        self.rigid_body_set.remove(
            handle,
            &mut self.island_manager,
            &mut self.collider_set,
            &mut self.impulse_joint_set,
            &mut self.multibody_joint_set,
            true,
        )
    }

    /// Retrieves an immutable reference to a collider.
    pub fn get_collider(&self, handle: ColliderHandle) -> Option<&Collider> {
        self.collider_set.get(handle)
    }

    /// Retrieves a mutable reference to a collider.
    pub fn get_collider_mut(&mut self, handle: ColliderHandle) -> Option<&mut Collider> {
        self.collider_set.get_mut(handle)
    }

    /// Removes a collider from the simulation.
    pub fn remove_collider(&mut self, handle: ColliderHandle) -> Option<Collider> {
        self.collider_set.remove(
            handle,
            &mut self.island_manager,
            &mut self.rigid_body_set,
            true,
        )
    }

    /// Returns the number of active rigid bodies.
    pub fn num_rigid_bodies(&self) -> usize {
        self.rigid_body_set.len()
    }

    /// Returns the number of active colliders.
    pub fn num_colliders(&self) -> usize {
        self.collider_set.len()
    }
}
