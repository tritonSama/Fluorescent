use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum PlayerId {
    P1,
    P2,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerStats {
    pub id: PlayerId,
    pub hp: i32,
    pub max_hp: i32,
    pub movement_points: i32,
}

impl PlayerStats {
    pub fn new(id: PlayerId) -> Self {
        Self {
            id,
            hp: 40,
            max_hp: 40,
            movement_points: 0,
        }
    }
}
