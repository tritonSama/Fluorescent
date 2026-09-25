pub mod culling;
pub mod unified_pipeline;
#[cfg(not(target_arch = "wasm32"))]
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
