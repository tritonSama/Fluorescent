## 2026-09-24T22:47:06Z

You are teamwork_preview_worker_m3.
Working directory: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_worker_m3\
Authoritative Request: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\ORIGINAL_REQUEST.md (YOU MUST READ THIS FILE FIRST).
Project Blueprint: c:\Users\blue-\projects\Fluorescent\PROJECT.md
Survey 2 Physics Blueprint: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_survey_2\report.md

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Exclusive Write Ownership:
You own and may modify ONLY:
- `fluorite_core/Cargo.toml`
- `fluorite_core/src/physics/` (`mod.rs`, `world.rs`, `character_controller.rs`, `sync.rs`)
- `fluorite_core/src/lib.rs` (ensure `pub mod physics;` is exported)
- `fluorite_core/tests/physics_pipeline_test.rs`
- `fluorite_core/tests/bvh_test.rs` (DELETE this obsolete orphan file so full cargo test passes)

Key Tasks for Milestone 3 (Physics Integration):
1. Review `fluorite_core/Cargo.toml`. `rapier3d = "0.17"` (or `"0.22"`) and `nalgebra` as required by Rapier. Ensure crate compiles cleanly.
2. Remove obsolete `fluorite_core/tests/bvh_test.rs` (the orphan test identified by Forensic Auditor M2 that was causing build errors for whole-crate tests).
3. Implement `fluorite_core/src/physics/world.rs`:
   - `PhysicsWorld` containing:
     - `gravity: nalgebra::Vector3<f32>` (default -9.81 on Y)
     - `integration_parameters: IntegrationParameters`
     - `physics_pipeline: PhysicsPipeline`
     - `island_manager: IslandManager`
     - `broad_phase: BroadPhaseMultiSap` (or default `BroadPhase`)
     - `narrow_phase: NarrowPhase`
     - `rigid_body_set: RigidBodySet`
     - `collider_set: ColliderSet`
     - `impulse_joint_set: ImpulseJointSet`
     - `multibody_joint_set: MultibodyJointSet`
     - `ccd_solver: CCDSolver`
     - `query_pipeline: QueryPipeline`
   - Fixed 60Hz timestep accumulator:
     - `fixed_timestep = 1.0 / 60.0`
     - `accumulator: f32`
     - `max_substeps: u32 = 4` (clamp to prevent spiral of death)
     - `pub fn step(&mut self, dt: f32) -> StepStats` (steps simulation, accumulates, sub-steps)
     - `pub fn step_single_frame(&mut self)` for exact 1-step advancement
   - Entity and body registration:
     - `insert_rigid_body(&mut self, body: RigidBody) -> RigidBodyHandle`
     - `insert_collider(&mut self, collider: Collider, parent: RigidBodyHandle) -> ColliderHandle`
     - `get_rigid_body(&self, handle: RigidBodyHandle) -> Option<&RigidBody>`
     - `get_rigid_body_mut(&mut self, handle: RigidBodyHandle) -> Option<&mut RigidBody>`
     - `remove_rigid_body(&mut self, handle: RigidBodyHandle)`
4. Implement `fluorite_core/src/physics/character_controller.rs`:
   - `CharacterController` wrapping `rapier3d::control::KinematicCharacterController`:
     - Autostep configuration (max height for stairs e.g. 0.35m-0.5m, min width e.g. 0.2m)
     - Ground snapping (e.g. 0.2m)
     - Max slope climb angle (e.g. 45 degrees)
     - Min slope slide angle (e.g. 50 degrees)
     - `slide: true`
     - `move_character(&self, world: &mut PhysicsWorld, character_body: RigidBodyHandle, character_collider: ColliderHandle, desired_movement: glam::Vec3, dt: f32) -> CharacterMovementResult`
     - `CharacterMovementResult { pub applied_translation: glam::Vec3, pub grounded: bool, pub sliding_on_slope: bool }`
5. Implement `fluorite_core/src/physics/sync.rs`:
   - Zero-copy transform synchronization between Rapier `Isometry3<f32>` and column-major `[f32; 16]` matrix.
   - `sync_body_transform_to_mat4(body: &RigidBody) -> [f32; 16]`
   - `sync_all_transforms_to_ecs(world: &PhysicsWorld, handles: &[RigidBodyHandle], out_transforms: &mut [[f32; 16]])`
6. Implement `fluorite_core/src/physics/mod.rs`:
   - Re-export all public types (`PhysicsWorld`, `CharacterController`, `CharacterMovementResult`, `StepStats`, handles, builders).
7. Export `pub mod physics;` in `fluorite_core/src/lib.rs`.
8. Implement comprehensive test suite in `fluorite_core/tests/physics_pipeline_test.rs`:
   - `test_rigid_body_gravity_fall`: Dynamic body falls downward under gravity over 60Hz steps.
   - `test_rigid_body_floor_collision`: Dynamic body falls and rests on a static floor collider.
   - `test_continuous_collision_detection_ccd`: Fast-moving dynamic sphere with CCD enabled does not tunnel through thin static wall.
   - `test_kinematic_character_controller_autostep`: KCC walks forward and successfully climbs a 0.3m step.
   - `test_kinematic_character_controller_slope_slide`: KCC on a 60-degree steep slope slides downward.
   - `test_fixed_timestep_accumulator`: Multiple variable dt increments step physics deterministically in 1/60s increments.
   - `test_zero_copy_transform_sync`: Converts Rapier body isometry to 4x4 matrix and validates translation and rotation match.
9. Verification:
   - Run `cargo check -p fluorite_core`
   - Run `cargo test -p fluorite_core --test physics_pipeline_test`
   - Run `cargo test -p fluorite_core --test bvh_culling_test`
   - Run `cargo test -p fluorite_core --test pbr_pipeline_test`
   - Run `cargo test -p fluorite_core` (ensure all tests in the crate pass!)
   - Run `dart run tests/e2e_runner.dart`
10. Deliverable:
    - Write report to `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_worker_m3\report.md`
    - Write handoff to `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_worker_m3\handoff.md`
    - Send completion message to parent.
