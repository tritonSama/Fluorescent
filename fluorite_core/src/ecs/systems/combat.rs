use super::components::player::{PlayerId, PlayerStats};
use super::components::pieces::Piece;
use super::components::grid::GridPosition;
use std::collections::HashMap;
use rand::Rng;

pub struct CombatSystem;

impl CombatSystem {
    pub fn resolve_combat(
        attacker_stats: &mut PlayerStats,
        defender_stats: &mut PlayerStats,
        location: GridPosition,
        pieces: &mut HashMap<GridPosition, Piece>,
    ) -> Result<(), &'static str> {
        let mut rng = rand::thread_rng();
        
        loop {
            let attacker_roll: i32 = rng.gen_range(1..=12);
            let defender_roll: i32 = rng.gen_range(1..=12);
            
            if attacker_roll == defender_roll {
                continue; // Tie, reroll
            }
            
            let damage = (attacker_roll - defender_roll).abs();
            
            if attacker_roll > defender_roll {
                // Attacker wins
                defender_stats.hp -= damage;
                // Defender piece is destroyed (replaced by attacker's piece, handled in move logic)
            } else {
                // Defender wins
                attacker_stats.hp -= damage;
                // Attacker piece is destroyed (already removed from map in move logic, so defender piece stays)
            }
            
            break;
        }
        
        Ok(())
    }
}
