use crate::ecs::world::{EngineWorld, TransformComponent, PhysicsComponent};
use rust_core::net::MeshNode;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct EntityStateUpdate {
    pub entity_id: u64,
    pub transform: Option<TransformComponent>,
    pub physics: Option<PhysicsComponent>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub enum ReplicationMessage {
    FullSync(Vec<EntityStateUpdate>),
    DeltaUpdate(Vec<EntityStateUpdate>),
}

pub struct ReplicationSystem {
    pub mesh_node: Box<dyn MeshNode>,
}

impl ReplicationSystem {
    pub fn new(mesh_node: Box<dyn MeshNode>) -> Self {
        Self { mesh_node }
    }

    pub fn broadcast_world_state(&self, world: &mut EngineWorld) {
        let mut updates = Vec::new();

        // In a real scenario, we would map hecs::Entity to a stable networked ID.
        // For simplicity, we use the entity's raw ID as `u64`.
        for (entity, (transform, phys)) in world.ecs.query::<(&TransformComponent, &PhysicsComponent)>().iter() {
            updates.push(EntityStateUpdate {
                entity_id: entity.to_bits(),
                transform: Some(*transform),
                physics: Some(*phys),
            });
        }

        let message = ReplicationMessage::FullSync(updates);
        if let Ok(data) = bincode::serialize(&message) {
            self.mesh_node.broadcast(&data);
        }
    }

    pub fn receive_update(&self, world: &mut EngineWorld, data: &[u8]) {
        if let Ok(message) = bincode::deserialize::<ReplicationMessage>(data) {
            match message {
                ReplicationMessage::FullSync(updates) | ReplicationMessage::DeltaUpdate(updates) => {
                    for update in updates {
                        let entity = hecs::Entity::from_bits(update.entity_id);

                        // Apply transform if present
                        if let Some(t) = update.transform {
                            // If entity doesn't exist or lacks component, we could spawn it,
                            // but here we just update if it exists.
                            if let Ok(mut current_transform) = world.ecs.get_mut::<TransformComponent>(entity) {
                                *current_transform = t;
                            }
                        }
                    }
                }
            }
        }
    }
}
