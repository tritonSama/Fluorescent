use execution_rail::ExecutionRail;
use execution_rail::models::{ComputeTask, TaskResult};
use mobile_vault_sdk::VaultClient;
use std::sync::Arc;

pub struct ComputeSubstrate {
    pub execution_rail: Arc<ExecutionRail>,
    pub vault: Arc<VaultClient>,
}

impl ComputeSubstrate {
    pub fn new(execution_rail: Arc<ExecutionRail>, vault: Arc<VaultClient>) -> Self {
        Self { execution_rail, vault }
    }

    /// Dispatches a heavy rendering or physics task to the nexus-core edge network.
    pub fn dispatch_background_task(&self, payload: Vec<u8>) {
        let task = ComputeTask {
            id: uuid::Uuid::new_v4().to_string(),
            payload,
            priority: 1,
        };

        // In a real scenario, this would await or use an asynchronous channel
        // self.execution_rail.submit_task(task);
        println!("Dispatched background compute task to execution-rail: {}", task.id);
    }

    /// Receives results from edge nodes.
    pub fn receive_task_result(&self, result: TaskResult) {
        println!("Received task result: {} (success: {})", result.task_id, result.success);
        // Integrate into ECS or world state.
    }

    /// Hook to sign or verify a compute transaction via Mobile Sovereign Vault
    pub fn verify_compute_transaction(&self, data: &[u8]) -> bool {
        self.vault.verify_signature(data)
    }
}
