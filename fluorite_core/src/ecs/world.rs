use crate::physics::sync::sync_body_transform_to_mat4;
use crate::physics::world::PhysicsWorld;
use hecs::{Entity, World as HecsWorld};
use rapier3d::prelude::RigidBodyHandle;
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
pub struct TransformComponent {
    pub matrix: [f32; 16],
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
pub struct PhysicsComponent {
    #[serde(skip)]
    pub handle: Option<RigidBodyHandle>,
}

pub struct EngineWorld {
    pub ecs: HecsWorld,
    pub physics: PhysicsWorld,
}

impl Default for EngineWorld {
    fn default() -> Self {
        Self::new()
    }
}

impl EngineWorld {
    pub fn new() -> Self {
        Self {
            ecs: HecsWorld::new(),
            physics: PhysicsWorld::new(),
        }
    }

    pub fn sync_physics_to_ecs(&mut self) {
        let mut query = self
            .ecs
            .query::<(&PhysicsComponent, &mut TransformComponent)>();
        for (phys, transform) in query.iter() {
            if let Some(body) = self.physics.get_rigid_body(phys.handle.unwrap()) {
                transform.matrix = sync_body_transform_to_mat4(body);
            }
        }
    }
}
