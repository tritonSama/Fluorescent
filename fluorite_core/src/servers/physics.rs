use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PhysicsServerStatus {
    pub is_running: bool,
    pub active_bodies: usize,
}

#[flutter_rust_bridge::frb(sync)]
pub fn start_physics_server() -> PhysicsServerStatus {
    PhysicsServerStatus {
        is_running: true,
        active_bodies: 0,
    }
}
