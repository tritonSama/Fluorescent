//! Kinematic Character Controller: Provides smooth movement, autostep over stairs,
//! slope sliding, and ground snapping wrapping Rapier3D's KinematicCharacterController.

use super::world::PhysicsWorld;
use rapier3d::control::{CharacterAutostep, CharacterLength, KinematicCharacterController};
use rapier3d::na::{Isometry3, Vector3};
use rapier3d::pipeline::QueryFilter;
use rapier3d::prelude::{ColliderHandle, RigidBodyHandle};

/// Result of a kinematic character movement calculation.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CharacterMovementResult {
    /// Actual translation applied after resolving collisions, autostep, and slopes.
    pub applied_translation: glam::Vec3,
    /// Whether the character is currently touching the ground.
    pub grounded: bool,
    /// Whether the character is sliding down a steep slope exceeding the slide angle.
    pub sliding_on_slope: bool,
}

/// Kinematic Character Controller (KCC) wrapper configured for AAA character dynamics.
pub struct CharacterController {
    /// Underlying Rapier3D kinematic character controller.
    pub kcc: KinematicCharacterController,
}

impl Default for CharacterController {
    fn default() -> Self {
        Self::new(
            0.35,                  // 35cm autostep max height (stairs)
            0.2,                   // 20cm autostep min width
            0.2,                   // 20cm ground snap distance
            45.0_f32.to_radians(), // 45 degree max climb angle
            50.0_f32.to_radians(), // 50 degree min slide angle
        )
    }
}

impl CharacterController {
    /// Creates a new `CharacterController` with customized movement and climbing parameters.
    pub fn new(
        autostep_max_height: f32,
        autostep_min_width: f32,
        snap_to_ground_distance: f32,
        max_slope_climb_angle_rad: f32,
        min_slope_slide_angle_rad: f32,
    ) -> Self {
        let kcc = KinematicCharacterController {
            up: Vector3::y_axis(),
            offset: CharacterLength::Absolute(0.02),
            slide: true,
            autostep: Some(CharacterAutostep {
                max_height: CharacterLength::Absolute(autostep_max_height),
                min_width: CharacterLength::Absolute(autostep_min_width),
                include_dynamic_bodies: false,
            }),
            max_slope_climb_angle: max_slope_climb_angle_rad,
            min_slope_slide_angle: min_slope_slide_angle_rad,
            snap_to_ground: Some(CharacterLength::Absolute(snap_to_ground_distance)),
            ..Default::default()
        };

        Self { kcc }
    }

    /// Moves the kinematic character in the physics world according to `desired_movement`,
    /// accounting for stairs autostepping, slopes, and environmental obstacles.
    pub fn move_character(
        &self,
        world: &mut PhysicsWorld,
        character_body: RigidBodyHandle,
        character_collider: ColliderHandle,
        desired_movement: glam::Vec3,
        dt: f32,
    ) -> CharacterMovementResult {
        let (shape, current_pos) = {
            let collider = match world.collider_set.get(character_collider) {
                Some(c) => c,
                None => {
                    return CharacterMovementResult {
                        applied_translation: glam::Vec3::ZERO,
                        grounded: false,
                        sliding_on_slope: false,
                    };
                }
            };
            let body = match world.rigid_body_set.get(character_body) {
                Some(b) => b,
                None => {
                    return CharacterMovementResult {
                        applied_translation: glam::Vec3::ZERO,
                        grounded: false,
                        sliding_on_slope: false,
                    };
                }
            };
            (collider.shape(), *body.position())
        };

        let desired_na = Vector3::new(
            desired_movement.x,
            desired_movement.y,
            desired_movement.z,
        );

        let filter = QueryFilter::default()
            .exclude_rigid_body(character_body)
            .exclude_collider(character_collider);

        let movement = self.kcc.move_shape(
            dt,
            &world.rigid_body_set,
            &world.collider_set,
            &world.query_pipeline,
            shape,
            &current_pos,
            desired_na,
            filter,
            |_| {},
        );

        // Apply calculated translation to the kinematic rigid body
        if let Some(body) = world.rigid_body_set.get_mut(character_body) {
            let new_pos = Isometry3::from_parts(
                (current_pos.translation.vector + movement.translation).into(),
                current_pos.rotation,
            );
            if body.is_kinematic() {
                body.set_next_kinematic_position(new_pos);
                body.set_position(new_pos, true);
            } else {
                body.set_position(new_pos, true);
            }
        }

        // Re-synchronize query pipeline with the updated position
        world.query_pipeline.update(&world.rigid_body_set, &world.collider_set);

        CharacterMovementResult {
            applied_translation: glam::Vec3::new(
                movement.translation.x,
                movement.translation.y,
                movement.translation.z,
            ),
            grounded: movement.grounded,
            sliding_on_slope: movement.is_sliding_down_slope,
        }
    }
}
