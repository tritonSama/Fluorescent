use wgpu;
use bytemuck::{Pod, Zeroable};
use std::sync::Arc;

/// Camera Uniforms structure matching the WGSL definitions,
/// used for GPU-driven frustum and occlusion culling.
#[repr(C)]
#[derive(Clone, Copy, Debug, Pod, Zeroable)]
pub struct CameraUniforms {
    pub view_proj: [[f32; 4]; 4],       // 64 bytes
    pub camera_pos: [f32; 3],           // 12 bytes
    pub _pad0: f32,                     // 4 bytes (align to 16)
    pub frustum_planes: [[f32; 4]; 6],  // 96 bytes: 6 planes (Left, Right, Bottom, Top, Near, Far)
    pub viewport_size: [f32; 2],        // 8 bytes
    pub _pad1: [f32; 2],                // 8 bytes
}

/// ComputeCuller structure.
pub struct ComputeCuller {
    device: Arc<wgpu::Device>,
    #[allow(dead_code)]
    queue: Arc<wgpu::Queue>,

    // Pipelines
    frustum_pipeline: wgpu::ComputePipeline,
    hzb_downsample_pipeline: wgpu::ComputePipeline,
    hzb_culling_pipeline: wgpu::ComputePipeline,

    // Bind group layouts
    frustum_bind_group_layout: wgpu::BindGroupLayout,
    hzb_downsample_bind_group_layout: wgpu::BindGroupLayout,
    hzb_culling_bind_group_layout: wgpu::BindGroupLayout,
}

impl ComputeCuller {
    pub fn new(device: Arc<wgpu::Device>, queue: Arc<wgpu::Queue>) -> Self {
        // Frustum pipeline
        let frustum_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Fluoderpod Frustum Culling Shader"),
            source: wgpu::ShaderSource::Wgsl(include_str!("frustum_culling.wgsl").into()),
        });

        let frustum_bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("Frustum Culling Bind Group Layout"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 3,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
            ],
        });

        let frustum_pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Frustum Culling Pipeline Layout"),
            bind_group_layouts: &[&frustum_bind_group_layout],
            push_constant_ranges: &[],
        });

        let frustum_pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("Frustum Culling Pipeline"),
            layout: Some(&frustum_pipeline_layout),
            module: &frustum_shader,
            compilation_options: Default::default(),
            entry_point: "main",
        });

        // HZB Downsample pipeline
        let hzb_downsample_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Fluoderpod HZB Downsample Shader"),
            source: wgpu::ShaderSource::Wgsl(include_str!("hzb_downsample.wgsl").into()),
        });

        let hzb_downsample_bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("HZB Downsample Bind Group Layout"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: false },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::StorageTexture {
                        access: wgpu::StorageTextureAccess::WriteOnly,
                        format: wgpu::TextureFormat::R32Float,
                        view_dimension: wgpu::TextureViewDimension::D2,
                    },
                    count: None,
                },
            ],
        });

        let hzb_downsample_pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("HZB Downsample Pipeline Layout"),
            bind_group_layouts: &[&hzb_downsample_bind_group_layout],
            push_constant_ranges: &[],
        });

        let hzb_downsample_pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("HZB Downsample Pipeline"),
            layout: Some(&hzb_downsample_pipeline_layout),
            module: &hzb_downsample_shader,
            compilation_options: Default::default(),
            entry_point: "main",
        });

        // HZB Occlusion Culling pipeline
        let hzb_culling_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Fluoderpod HZB Occlusion Culling Shader"),
            source: wgpu::ShaderSource::Wgsl(include_str!("hzb_culling.wgsl").into()),
        });

        let hzb_culling_bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("HZB Occlusion Culling Bind Group Layout"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 3,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 4,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: false },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 5,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::NonFiltering),
                    count: None,
                },
            ],
        });

        let hzb_culling_pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("HZB Occlusion Culling Pipeline Layout"),
            bind_group_layouts: &[&hzb_culling_bind_group_layout],
            push_constant_ranges: &[],
        });

        let hzb_culling_pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("HZB Occlusion Culling Pipeline"),
            layout: Some(&hzb_culling_pipeline_layout),
            module: &hzb_culling_shader,
            compilation_options: Default::default(),
            entry_point: "main",
        });

        Self {
            device,
            queue,
            frustum_pipeline,
            hzb_downsample_pipeline,
            hzb_culling_pipeline,
            frustum_bind_group_layout,
            hzb_downsample_bind_group_layout,
            hzb_culling_bind_group_layout,
        }
    }

    #[cfg(test)]
    pub fn mock() -> Self {
        unimplemented!("Mock implementation not provided yet")
    }

    /// Dispatch frustum culling compute shader.
    pub fn dispatch_frustum_culling(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        camera_uniform_buffer: &wgpu::Buffer,
        instances_buffer: &wgpu::Buffer,
        indirect_draw_buffer: &wgpu::Buffer,
        compact_instances_buffer: &wgpu::Buffer,
        num_instances: u32,
    ) {
        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Frustum Culling Bind Group"),
            layout: &self.frustum_bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: camera_uniform_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: instances_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: indirect_draw_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: compact_instances_buffer.as_entire_binding(),
                },
            ],
        });

        let mut cpass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("Frustum Culling Pass"),
            timestamp_writes: None,
        });

        cpass.set_pipeline(&self.frustum_pipeline);
        cpass.set_bind_group(0, &bind_group, &[]);

        let workgroups = (num_instances + 63) / 64; // Assuming 64 threads per workgroup
        cpass.dispatch_workgroups(workgroups, 1, 1);
    }

    /// Dispatch HZB Downsample compute shader.
    pub fn dispatch_hzb_downsample(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        input_texture: &wgpu::TextureView,
        output_texture: &wgpu::TextureView,
        width: u32,
        height: u32,
    ) {
        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("HZB Downsample Bind Group"),
            layout: &self.hzb_downsample_bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(input_texture),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::TextureView(output_texture),
                },
            ],
        });

        let mut cpass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("HZB Downsample Pass"),
            timestamp_writes: None,
        });

        cpass.set_pipeline(&self.hzb_downsample_pipeline);
        cpass.set_bind_group(0, &bind_group, &[]);

        let workgroups_x = (width + 7) / 8; // Assuming 8x8 workgroup size
        let workgroups_y = (height + 7) / 8;
        cpass.dispatch_workgroups(workgroups_x, workgroups_y, 1);
    }

    /// Dispatch hierarchical Z-buffer (HZB) occlusion culling.
    pub fn dispatch_occlusion_culling(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        camera_uniform_buffer: &wgpu::Buffer,
        instances_buffer: &wgpu::Buffer,
        indirect_draw_buffer: &wgpu::Buffer,
        compact_instances_buffer: &wgpu::Buffer,
        hzb_texture: &wgpu::TextureView,
        hzb_sampler: &wgpu::Sampler,
        num_instances: u32,
    ) {
        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("HZB Occlusion Culling Bind Group"),
            layout: &self.hzb_culling_bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: camera_uniform_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: instances_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: indirect_draw_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: compact_instances_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 4,
                    resource: wgpu::BindingResource::TextureView(hzb_texture),
                },
                wgpu::BindGroupEntry {
                    binding: 5,
                    resource: wgpu::BindingResource::Sampler(hzb_sampler),
                },
            ],
        });

        let mut cpass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("HZB Occlusion Culling Pass"),
            timestamp_writes: None,
        });

        cpass.set_pipeline(&self.hzb_culling_pipeline);
        cpass.set_bind_group(0, &bind_group, &[]);

        let workgroups = (num_instances + 63) / 64; // Assuming 64 threads per workgroup
        cpass.dispatch_workgroups(workgroups, 1, 1);
    }
}
