pub mod culling;
pub mod unified_pipeline;
pub mod nexus_client;
pub mod virtual_geometry;

/// The main entry point for the fluoderpod GPU-driven render graph.
pub struct FluoderpodRenderer {
    // The unified pipeline manager handles wgpu device/queue
    pub pipeline_manager: unified_pipeline::PipelineManager,
}

impl FluoderpodRenderer {
    pub fn new(pipeline_manager: unified_pipeline::PipelineManager) -> Self {
        Self { pipeline_manager }
    }

    /// Ingests a raw contiguous buffer of 96-byte EntityInstance structs directly from FFI.
    /// This bypasses CPU-side iteration and prepares the data for compute culling.
    pub fn ingest_fluoderpod_batch(&mut self, raw_entity_data: &[u8]) -> Result<usize, &'static str> {
        if raw_entity_data.len() % std::mem::size_of::<unified_pipeline::EntityInstance>() != 0 {
            return Err("Entity buffer byte length is not a multiple of 96 bytes");
        }

        // Validate bytemuck cast without copying
        let _instances: &[unified_pipeline::EntityInstance] = bytemuck::try_cast_slice(raw_entity_data)
            .map_err(|_| "Failed to cast entity slice to EntityInstance")?;

        let instance_count = _instances.len();

        // High-throughput upload to GPU buffers handled by the unified pipeline
        self.pipeline_manager.update_entity_buffer(raw_entity_data);

        Ok(instance_count)
    }

    /// Executes the full GPU-driven frame: Culling -> Virtual Geometry LOD -> Indirect Draw
    pub fn execute_frame(&mut self) {
        // 1. Dispatch Frustum & Occlusion Culling
        // 2. Dispatch Virtual Geometry Cluster Selection
        // 3. Issue Unified Indirect Draw commands
    }
}
#[cfg(target_os = "android")]
pub mod android_vulkan;

/// C-ABI FFI function for Flutter to pass byte pointers directly via dart:ffi
#[no_mangle]
pub unsafe extern "C" fn fluoderpod_ingest_batch(
    renderer_ptr: *mut FluoderpodRenderer,
    data_ptr: *const u8,
    data_len: usize,
) -> i32 {
    if renderer_ptr.is_null() || data_ptr.is_null() {
        return -1;
    }
    let renderer = &mut *renderer_ptr;
    let data_slice = std::slice::from_raw_parts(data_ptr, data_len);
    match renderer.ingest_fluoderpod_batch(data_slice) {
        Ok(count) => count as i32,
        Err(_) => -2,
    }
}
