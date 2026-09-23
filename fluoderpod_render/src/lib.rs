pub mod culling;
pub mod virtual_geometry;
pub mod unified_pipeline;

/// The main entry point for the fluoderpod GPU-driven render graph.
pub struct FluoderpodRenderer {
    // The unified pipeline manager handles wgpu device/queue
    pub pipeline_manager: unified_pipeline::PipelineManager,
}

impl FluoderpodRenderer {
    pub fn new(pipeline_manager: unified_pipeline::PipelineManager) -> Self {
        Self { pipeline_manager }
    }

    /// Ingests a raw contiguous buffer of entity data directly from fluoderpod.
    /// This bypasses CPU-side iteration and prepares the data for compute culling.
    pub fn ingest_fluoderpod_batch(&mut self, _raw_entity_data: &[u8]) {
        // High-throughput upload to GPU buffers handled by the unified pipeline
    }

    /// Executes the full GPU-driven frame: Culling -> Virtual Geometry LOD -> Indirect Draw
    pub fn execute_frame(&mut self) {
        // 1. Dispatch Frustum & Occlusion Culling
        // 2. Dispatch Virtual Geometry Cluster Selection
        // 3. Issue Unified Indirect Draw commands
    }
}
