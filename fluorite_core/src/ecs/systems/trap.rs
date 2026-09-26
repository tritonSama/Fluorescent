use crate::ecs::components::pieces::Trap;
use crate::ecs::components::player::PlayerStats;
use rand::Rng;

pub struct TrapSystem;

impl TrapSystem {
    pub fn resolve_trap(player: &mut PlayerStats, trap: &mut Trap) -> Result<bool, &'static str> {
        trap.revealed = true;
        let mut rng = rand::thread_rng();
        let roll: i32 = rng.gen_range(1..=12);

        if roll <= trap.value {
            // Hit!
            let damage = trap.value - roll;
            player.hp -= damage;
            Ok(true) // Trap hit
        } else {
            // Miss! Disarmed.
            Ok(false) // Trap disarmed
        }
    }
}
