use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum NodeRole {
    Leader,
    Worker,
    Candidate,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ClusterNode {
    pub id: String,
    pub role: NodeRole,
    pub h_score: f32, // $H_n$ score for dynamic job slicing
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RaftCluster {
    pub nodes: Vec<ClusterNode>,
    pub current_term: u64,
}

impl RaftCluster {
    pub fn new() -> Self {
        Self {
            nodes: Vec::new(),
            current_term: 0,
        }
    }

    pub fn add_node(&mut self, id: String, h_score: f32) {
        self.nodes.push(ClusterNode {
            id,
            role: NodeRole::Worker,
            h_score,
        });
    }

    pub fn elect_leader(&mut self) {
        // Select leader based on the highest $H_n$ score
        if self.nodes.is_empty() {
            return;
        }

        let mut max_score = -1.0;
        let mut leader_idx = 0;

        for (i, node) in self.nodes.iter().enumerate() {
            if node.h_score > max_score {
                max_score = node.h_score;
                leader_idx = i;
            }
        }

        for (i, node) in self.nodes.iter_mut().enumerate() {
            if i == leader_idx {
                node.role = NodeRole::Leader;
            } else {
                node.role = NodeRole::Worker;
            }
        }

        self.current_term += 1;
    }

    pub fn route_job(&self, job_complexity: f32) -> Option<String> {
        // Route job to the most capable worker (highest H_n) that isn't the leader,
        // or just the best node if it's a small cluster.
        let mut best_worker: Option<&ClusterNode> = None;
        for node in &self.nodes {
            if node.role == NodeRole::Worker {
                match best_worker {
                    Some(best) if node.h_score > best.h_score => best_worker = Some(node),
                    None => best_worker = Some(node),
                    _ => {}
                }
            }
        }

        best_worker.map(|n| n.id.clone())
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn initialize_raft_cluster() -> RaftCluster {
    let mut cluster = RaftCluster::new();
    // Initialize with a mock node
    cluster.add_node("local_node_1".to_string(), 1.0);
    cluster.elect_leader();
    cluster
}

#[flutter_rust_bridge::frb(sync)]
pub fn add_node_to_cluster(mut cluster: RaftCluster, id: String, h_score: f32) -> RaftCluster {
    cluster.add_node(id, h_score);
    cluster.elect_leader();
    cluster
}
