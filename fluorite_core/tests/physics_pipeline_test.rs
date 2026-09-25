//! Comprehensive test suite for Fluorite Physics subsystem (Milestone 3).
//! Validates rigid body dynamics, floor collisions, continuous collision detection (CCD),
//! kinematic character controller autostepping and slope sliding, fixed timestep accumulation,
//! and zero-copy transform synchronization.

use fluorite_core::physics::{
    sync_all_transforms_to_ecs, sync_body_transform_to_mat4, CharacterController, ColliderBuilder,
    PhysicsWorld, RigidBodyBuilder,
};
use rapier3d::na::vector;

#[test]
fn test_rigid_body_gravity_fall() {
    let mut world = PhysicsWorld::new();
    let body = RigidBodyBuilder::dynamic()
        .translation(vector![0.0, 10.0, 0.0])
        .build();
    let body_handle = world.insert_rigid_body(body);
    let collider = ColliderBuilder::ball(0.5).build();
    world.insert_collider(collider, body_handle);

    // Step 60 times at 1/60 second (1.0 second total)
    for _ in 0..60 {
        world.step_single_frame();
    }

    let body = world.get_rigid_body(body_handle).unwrap();
    let y = body.translation().y;
    // Freefall formula: y(t) = y0 - 0.5 * g * t^2 = 10.0 - 0.5 * 9.81 * 1.0 = 5.095m
    assert!(y < 10.0, "Body must fall downward under gravity");
    assert!(
        (y - 5.095).abs() < 0.25,
        "Freefall position expected ~5.095, got {}",
        y
    );
    assert!(
        body.linvel().y < -9.0,
        "Vertical velocity expected ~ -9.81, got {}",
        body.linvel().y
    );
}

#[test]
fn test_rigid_body_floor_collision() {
    let mut world = PhysicsWorld::new();

    // Static floor at y = 0.0, half-extents (10.0, 0.1, 10.0) -> top surface at y = 0.1
    let floor_body = RigidBodyBuilder::fixed()
        .translation(vector![0.0, 0.0, 0.0])
        .build();
    let floor_handle = world.insert_rigid_body(floor_body);
    let floor_collider = ColliderBuilder::cuboid(10.0, 0.1, 10.0).build();
    world.insert_collider(floor_collider, floor_handle);

    // Dynamic ball falling from y = 3.0, radius 0.5, restitution 0.0 to rest quickly
    let ball_body = RigidBodyBuilder::dynamic()
        .translation(vector![0.0, 3.0, 0.0])
        .build();
    let ball_handle = world.insert_rigid_body(ball_body);
    let ball_collider = ColliderBuilder::ball(0.5).restitution(0.0).build();
    world.insert_collider(ball_collider, ball_handle);

    // Step for 120 frames (2.0 seconds) to ensure it reaches rest on the floor
    for _ in 0..120 {
        world.step_single_frame();
    }

    let ball = world.get_rigid_body(ball_handle).unwrap();
    let y = ball.translation().y;
    // Floor top is at y = 0.1, ball radius is 0.5 -> expected rest position is y ~ 0.6
    assert!(
        (y - 0.6).abs() < 0.1,
        "Ball should rest on floor at y ~ 0.6, got {}",
        y
    );
    assert!(y >= 0.55, "Ball must not fall through static floor");
}

#[test]
fn test_continuous_collision_detection_ccd() {
    let mut world = PhysicsWorld::with_gravity(vector![0.0, 0.0, 0.0]); // Zero gravity for ballistic test

    // Thin static wall at x = 0.0, thickness = 0.1m (half-extent x = 0.05)
    let wall_body = RigidBodyBuilder::fixed()
        .translation(vector![0.0, 0.0, 0.0])
        .build();
    let wall_handle = world.insert_rigid_body(wall_body);
    let wall_collider = ColliderBuilder::cuboid(0.05, 5.0, 5.0).build();
    world.insert_collider(wall_collider, wall_handle);

    // Fast dynamic projectile moving at 300 m/s along +X.
    // In one 1/60s step, it travels 5.0 meters! Without CCD, it would tunnel completely from x = -2.0 to x = +3.0.
    let bullet_body = RigidBodyBuilder::dynamic()
        .translation(vector![-2.0, 0.0, 0.0])
        .linvel(vector![300.0, 0.0, 0.0])
        .ccd_enabled(true)
        .build();
    let bullet_handle = world.insert_rigid_body(bullet_body);
    let bullet_collider = ColliderBuilder::ball(0.1).build();
    world.insert_collider(bullet_collider, bullet_handle);

    // Step 1 single frame
    world.step_single_frame();

    let bullet = world.get_rigid_body(bullet_handle).unwrap();
    let x = bullet.translation().x;
    // With CCD, the bullet must hit the wall (x <= 0.05) and NOT tunnel through to x > 1.0!
    assert!(
        x <= 0.05,
        "CCD projectile must not tunnel through thin wall; got x = {}",
        x
    );
}

#[test]
fn test_kinematic_character_controller_autostep() {
    let mut world = PhysicsWorld::new();

    // Floor 1: y = 0.0, from x = -10.0 to x = 0.0
    let ground1_body = RigidBodyBuilder::fixed()
        .translation(vector![-5.0, -0.1, 0.0])
        .build();
    let ground1_handle = world.insert_rigid_body(ground1_body);
    let ground1_collider = ColliderBuilder::cuboid(5.0, 0.1, 5.0).build();
    world.insert_collider(ground1_collider, ground1_handle);

    // Step 2: 0.3m height step starting at x = 0.0. Top of step is at y = 0.3.
    // Half height = 0.25, center at y = 0.05 -> top is at 0.05 + 0.25 = 0.30
    let step_body = RigidBodyBuilder::fixed()
        .translation(vector![5.0, 0.05, 0.0])
        .build();
    let step_handle = world.insert_rigid_body(step_body);
    let step_collider = ColliderBuilder::cuboid(5.0, 0.25, 5.0).build();
    world.insert_collider(step_collider, step_handle);

    // Create KCC with autostep max_height = 0.35m (capable of climbing 0.3m step)
    let kcc = CharacterController::new(
        0.35, // autostep max height = 0.35m
        0.20,
        0.20,
        45.0_f32.to_radians(),
        50.0_f32.to_radians(),
    );

    // Kinematic character capsule standing at x = -0.5 on ground (y = 0.5)
    let char_body = RigidBodyBuilder::kinematic_position_based()
        .translation(vector![-0.5, 0.5, 0.0])
        .build();
    let char_body_handle = world.insert_rigid_body(char_body);
    let char_collider = ColliderBuilder::capsule_y(0.25, 0.25).build();
    let char_collider_handle = world.insert_collider(char_collider, char_body_handle);

    // Initial query pipeline update
    world.query_pipeline.update(&world.rigid_body_set, &world.collider_set);

    // Move forward in +X towards the step
    let dt = 1.0 / 60.0;
    for _ in 0..60 {
        kcc.move_character(
            &mut world,
            char_body_handle,
            char_collider_handle,
            glam::Vec3::new(1.0, 0.0, 0.0), // 1 m/s forward
            dt,
        );
    }

    let char_body = world.get_rigid_body(char_body_handle).unwrap();
    let pos = char_body.translation();
    // Character should have climbed the 0.3m step and moved forward past x = 0.0
    assert!(
        pos.x > 0.0,
        "Character should move forward past the step (x > 0), got x = {}",
        pos.x
    );
    assert!(
        pos.y >= 0.75,
        "Character should climb onto the 0.3m step (y >= 0.75), got y = {}",
        pos.y
    );
}

#[test]
fn test_kinematic_character_controller_slope_slide() {
    let mut world = PhysicsWorld::new();

    // Create a 60-degree steep slope (> min_slope_slide_angle of 50 degrees)
    let angle = 60.0_f32.to_radians();
    let slope_body = RigidBodyBuilder::fixed()
        .translation(vector![0.0, 0.0, 0.0])
        .rotation(vector![0.0, 0.0, angle])
        .build();
    let slope_handle = world.insert_rigid_body(slope_body);
    let slope_collider = ColliderBuilder::cuboid(10.0, 0.2, 10.0).build();
    world.insert_collider(slope_collider, slope_handle);

    let kcc = CharacterController::new(
        0.35,
        0.20,
        0.20,
        45.0_f32.to_radians(), // max climb = 45 deg
        50.0_f32.to_radians(), // min slide = 50 deg
    );

    // Place character on the upper part of the 60-degree slope
    let char_body = RigidBodyBuilder::kinematic_position_based()
        .translation(vector![-2.0, 4.0, 0.0])
        .build();
    let char_body_handle = world.insert_rigid_body(char_body);
    let char_collider = ColliderBuilder::capsule_y(0.25, 0.25).build();
    let char_collider_handle = world.insert_collider(char_collider, char_body_handle);

    world.query_pipeline.update(&world.rigid_body_set, &world.collider_set);

    // Move character slightly downwards
    let dt = 1.0 / 60.0;
    let mut slid = false;
    for _ in 0..30 {
        let res = kcc.move_character(
            &mut world,
            char_body_handle,
            char_collider_handle,
            glam::Vec3::new(0.0, -9.81 * dt, 0.0),
            dt,
        );
        if res.sliding_on_slope {
            slid = true;
            break;
        }
    }

    assert!(
        slid,
        "KCC must detect sliding on a 60-degree slope (steeper than 50-degree threshold)"
    );
}

#[test]
fn test_fixed_timestep_accumulator() {
    let mut world = PhysicsWorld::new();
    let fixed_dt = 1.0 / 60.0;

    // Small dt less than 1 frame -> 0 substeps, accumulated
    let stats1 = world.step(0.005);
    assert_eq!(stats1.substeps, 0);
    assert!((stats1.remaining_accumulator - 0.005).abs() < 1e-5);

    // Second small dt (0.012) -> total 0.017 > 1/60 -> 1 substep executed
    let stats2 = world.step(0.012);
    assert_eq!(stats2.substeps, 1);
    assert!((stats2.remaining_accumulator - (0.017 - fixed_dt)).abs() < 1e-4);

    // Larger dt (0.050) -> should execute 3 substeps (3 * 0.016667 = 0.050)
    let stats3 = world.step(0.050);
    assert!(stats3.substeps >= 2 && stats3.substeps <= 4);

    // Massive dt (1.0 second) -> clamped to max_substeps (4) to prevent spiral of death
    let stats_massive = world.step(1.0);
    assert_eq!(
        stats_massive.substeps, 4,
        "Massive delta time must be clamped to max_substeps (4)"
    );
}

#[test]
fn test_zero_copy_transform_sync() {
    let mut world = PhysicsWorld::new();

    // Create a body with rotation 90 degrees around Y and translation (1.5, 2.5, 3.5)
    let rotation = rapier3d::na::UnitQuaternion::from_axis_angle(
        &rapier3d::na::Vector3::y_axis(),
        std::f32::consts::FRAC_PI_2,
    );
    let body = RigidBodyBuilder::dynamic()
        .translation(vector![1.5, 2.5, 3.5])
        .rotation(rotation.scaled_axis())
        .build();
    let handle = world.insert_rigid_body(body);

    let fetched_body = world.get_rigid_body(handle).unwrap();
    let mat16 = sync_body_transform_to_mat4(fetched_body);

    // Reconstruct glam Mat4
    let mat4 = glam::Mat4::from_cols_array(&mat16);

    // Verify translation column (col 3: elements 12, 13, 14)
    let translation = mat4.w_axis.truncate();
    assert!((translation.x - 1.5).abs() < 1e-4);
    assert!((translation.y - 2.5).abs() < 1e-4);
    assert!((translation.z - 3.5).abs() < 1e-4);

    // Verify rotation: unit X vector rotated 90 degrees around +Y should point to (0, 0, -1)
    let local_x = glam::Vec4::new(1.0, 0.0, 0.0, 0.0);
    let transformed_x = mat4 * local_x;
    assert!((transformed_x.x - 0.0).abs() < 1e-4);
    assert!((transformed_x.y - 0.0).abs() < 1e-4);
    assert!((transformed_x.z - (-1.0)).abs() < 1e-4);

    // Verify batch ECS sync
    let mut ecs_transforms = [[0.0f32; 16]; 3];
    let handles = [handle];
    sync_all_transforms_to_ecs(&world, &handles, &mut ecs_transforms);
    assert_eq!(ecs_transforms[0], mat16);
    assert_eq!(ecs_transforms[1], [0.0f32; 16]); // untouched
}
