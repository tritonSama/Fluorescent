use super::components::grid::GridPosition;
use super::components::player::{PlayerId, PlayerStats};
use super::components::pieces::Piece;
use std::collections::HashMap;

pub struct MovementSystem;

impl MovementSystem {
    pub fn move_piece(
        player: &mut PlayerStats,
        pieces: &mut HashMap<GridPosition, Piece>,
        from: GridPosition,
        to: GridPosition,
    ) -> Result<(), &'static str> {
        if player.movement_points <= 0 {
            return Err("No movement points left");
        }

        if !from.is_adjacent(&to) {
            return Err("Invalid move: Must be adjacent");
        }

        if to.x < 0 || to.x >= 9 || to.y < 0 || to.y >= 9 {
            return Err("Invalid move: Out of bounds");
        }

        let piece = pieces.remove(&from).ok_or("No piece at source location")?;
        
        if piece.owner != player.id {
            pieces.insert(from, piece); // Put it back
            return Err("Piece does not belong to current player");
        }

        player.movement_points -= 1;
        pieces.insert(to, piece);
        
        Ok(())
    }
}
