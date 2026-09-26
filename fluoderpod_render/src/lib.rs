pub mod culling;
#[cfg(not(target_arch = "wasm32"))]
pub mod nexus_client;
pub mod unified_pipeline;
pub mod virtual_geometry;

/// The main entry point for the fluoderpod GPU-driven render graph.
pub struct FluoderpodRenderer {
    // The unified pipeline manager handles wgpu device/queue
    pub pipeline_manager: unified_pipeline::PipelineManager,
    // Add systems to manage dispatch
    pub culling_system: Option<culling::ComputeCuller>,
    pub virtual_geometry_system: Option<virtual_geometry::VirtualGeometrySystem>,

    // Buffers needed for passes
    pub camera_uniform_buffer: Option<wgpu::Buffer>,
    pub instances_buffer: Option<wgpu::Buffer>,
    pub compact_instances_buffer: Option<wgpu::Buffer>,
    pub cluster_metadata_buffer: Option<wgpu::Buffer>,
    pub output_clusters_buffer: Option<wgpu::Buffer>,
    pub hzb_texture: Option<wgpu::TextureView>,
    pub hzb_sampler: Option<wgpu::Sampler>,

    pub num_instances: u32,
    pub num_clusters: u32,
}

impl FluoderpodRenderer {
    pub fn new(pipeline_manager: unified_pipeline::PipelineManager) -> Self {
        Self {
            pipeline_manager,
            culling_system: None,
            virtual_geometry_system: None,
            camera_uniform_buffer: None,
            instances_buffer: None,
            compact_instances_buffer: None,
            cluster_metadata_buffer: None,
            output_clusters_buffer: None,
            hzb_texture: None,
            hzb_sampler: None,
            num_instances: 0,
            num_clusters: 0,
        }
    }

    /// Ingests a raw contiguous buffer of 48-byte PackedEntityInstance structs directly from FFI.
    /// This bypasses CPU-side iteration and prepares the data for compute culling.
    pub fn ingest_fluoderpod_batch(&mut self, raw_entity_data: &[u8]) -> Result<usize, &'static str> {
        if raw_entity_data.len() % std::mem::size_of::<unified_pipeline::PackedEntityInstance>() != 0 {
            return Err("Entity buffer byte length is not a multiple of 48 bytes");
        }

        // Validate bytemuck cast without copying
        let _instances: &[unified_pipeline::PackedEntityInstance] = bytemuck::try_cast_slice(raw_entity_data)
            .map_err(|_| "Failed to cast entity slice to PackedEntityInstance")?;

        let instance_count = _instances.len();
        self.num_instances = instance_count as u32;

        // High-throughput upload to GPU buffers handled by the unified pipeline
        self.pipeline_manager.update_entity_buffer(raw_entity_data);

        Ok(instance_count)
    }

    /// Executes the full GPU-driven frame: Culling -> Virtual Geometry LOD -> Indirect Draw
    pub fn execute_frame<'a>(&'a mut self, encoder: &mut wgpu::CommandEncoder, render_pass: &mut wgpu::RenderPass<'a>) {
        // 1. Dispatch Frustum & Occlusion Culling
        if let (Some(culler), Some(camera_buf), Some(instances_buf), Some(indirect_buf), Some(compact_buf), Some(hzb_tex), Some(hzb_samp)) = (
            &self.culling_system,
            &self.camera_uniform_buffer,
            &self.instances_buffer,
            &self.pipeline_manager.indirect_draw_buffer,
            &self.compact_instances_buffer,
            &self.hzb_texture,
            &self.hzb_sampler
        ) {
            culler.dispatch_occlusion_culling(
                encoder,
                camera_buf,
                instances_buf,
                indirect_buf,
                compact_buf,
                hzb_tex,
                hzb_samp,
                self.num_instances
            );
        } else if let (Some(culler), Some(camera_buf), Some(instances_buf), Some(indirect_buf), Some(compact_buf)) = (
            &self.culling_system,
            &self.camera_uniform_buffer,
            &self.instances_buffer,
            &self.pipeline_manager.indirect_draw_buffer,
            &self.compact_instances_buffer
        ) {
            // Fallback to frustum culling if HZB is not available
            culler.dispatch_frustum_culling(
                encoder,
                camera_buf,
                instances_buf,
                indirect_buf,
                compact_buf,
                self.num_instances
            );
        }

        // 2. Dispatch Virtual Geometry Cluster Selection
        if let (Some(vg_system), Some(camera_buf), Some(metadata_buf), Some(output_buf)) = (
            &self.virtual_geometry_system,
            &self.camera_uniform_buffer,
            &self.cluster_metadata_buffer,
            &self.output_clusters_buffer
        ) {
            vg_system.dispatch_cluster_evaluation(
                encoder,
                camera_buf,
                metadata_buf,
                output_buf,
                self.num_clusters,
                &self.pipeline_manager.device
            );
        }

        // 3. Issue Unified Indirect Draw commands
        self.pipeline_manager.submit_indirect_draws(render_pass);
    }
}
#[cfg(target_os = "android")]
pub mod android_vulkan;

#[cfg(target_arch = "wasm32")]
pub async fn create_webgpu_surface_from_canvas(
    instance: &wgpu::Instance,
    canvas_id: &str,
) -> Result<wgpu::Surface<'static>, Box<dyn std::error::Error>> {
    use wasm_bindgen::JsCast;
    let window = web_sys::window().ok_or("No global window found")?;
    let document = window.document().ok_or("No document found")?;
    let canvas = document
        .get_element_by_id(canvas_id)
        .ok_or_else(|| format!("Canvas element '{}' not found", canvas_id))?;
    let html_canvas: web_sys::HtmlCanvasElement = canvas.dyn_into().map_err(|_| "Element is not a canvas")?;
    let surface = instance.create_surface(wgpu::SurfaceTarget::Canvas(html_canvas))?;
    Ok(surface)
}

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

#[cfg(not(target_arch = "wasm32"))]
pub mod webrtc_signalling;
#[cfg(not(target_arch = "wasm32"))]
pub mod webrtc_streamer;

#[cfg(not(target_arch = "wasm32"))]
pub mod headless_render;

#[cfg(not(target_arch = "wasm32"))]
pub mod video_encoder;

#[cfg(test)]
mod tests {
    use super::*;
    use unified_pipeline::PackedEntityInstance;

    #[test]
    fn test_packed_entity_instance_layout_48_bytes() {
        assert_eq!(std::mem::size_of::<PackedEntityInstance>(), 48);
        assert_eq!(std::mem::align_of::<PackedEntityInstance>(), 4);

        let instance = PackedEntityInstance {
            position: [1.0, 2.0, 3.0],
            sphere_radius: 5.0,
            rotation_quat: [0.0, 0.0, 0.0, 1.0],
            scale: [1.0, 1.0, 1.0],
            cluster_and_flags: 0x1234_5678,
        };

        let bytes = bytemuck::bytes_of(&instance);
        assert_eq!(bytes.len(), 48);

        let casted: &PackedEntityInstance = bytemuck::from_bytes(bytes);
        assert_eq!(*casted, instance);
    }

    #[test]
    fn test_batch_byte_length_validation() {
        let valid_single = vec![0u8; 48];
        let valid_double = vec![0u8; 96];
        let invalid_odd = vec![0u8; 24];
        let invalid_unaligned = vec![0u8; 50];

        assert_eq!(valid_single.len() % std::mem::size_of::<PackedEntityInstance>(), 0);
        assert_eq!(valid_double.len() % std::mem::size_of::<PackedEntityInstance>(), 0);
        assert_ne!(invalid_odd.len() % std::mem::size_of::<PackedEntityInstance>(), 0);
        assert_ne!(invalid_unaligned.len() % std::mem::size_of::<PackedEntityInstance>(), 0);
    }
}

