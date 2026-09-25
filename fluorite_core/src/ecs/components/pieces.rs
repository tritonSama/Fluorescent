use serde::{Deserialize, Serialize};
use super::player::PlayerId;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Piece {
    pub owner: PlayerId,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Trap {
    pub owner: PlayerId,
    pub value: i32,
    pub is_flag: bool,
    pub revealed: bool,
}
