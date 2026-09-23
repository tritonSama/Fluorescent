use serde::{Deserialize, Serialize};

/// Type of execution pass in the render graph.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum PassType {
    /// A GPU compute pass (e.g., culling, physics simulation, particles).
    Compute,
    /// A traditional rasterization graphics pass.
    Raster,
    /// A hardware raytracing pass (e.g., DXR, Vulkan RT).
    Raytrace,
}

/// Represents a single render or compute pass within the graph.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenderPassDefinition {
    /// Unique identifier for the pass.
    pub name: String,
    /// What kind of pipeline this pass requires.
    pub pass_type: PassType,
    /// Which shader asset this pass uses.
    pub shader: String,
    /// List of input resources (e.g., GBuffer, Depth buffer, UBOs).
    pub inputs: Vec<String>,
    /// List of output resources (e.g., Color target, Indirect Draw buffer).
    pub outputs: Vec<String>,
    /// Optional minimum quality tier required to execute this pass.
    pub min_quality_tier: Option<super::renderer::QualityTier>,
}

/// The fully data-driven sequence of passes that defines how a frame is rendered.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenderGraphDefinition {
    /// The name of this graph configuration.
    pub name: String,
    /// The sequential list of passes to execute.
    pub passes: Vec<RenderPassDefinition>,
}

impl Default for RenderGraphDefinition {
    fn default() -> Self {
        Self {
            name: "Empty Graph".to_string(),
            passes: Vec::new(),
        }
    }
}
