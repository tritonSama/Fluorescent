use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct NavigationServerStatus {
    pub is_running: bool,
    pub loaded_navmeshes: usize,
}

#[flutter_rust_bridge::frb(sync)]
pub fn start_navigation_server() -> NavigationServerStatus {
    NavigationServerStatus {
        is_running: true,
        loaded_navmeshes: 0,
    }
}
