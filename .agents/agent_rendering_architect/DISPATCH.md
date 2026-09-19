# Dispatch: Rendering Architect Agent

## Assigned Tasks (Phase 2)
- Currently on standby. Provide graphics/rendering support as needed for the Functional Test App.

## Assigned Tasks (Phase 3)

### 1. GPU-Driven Rendering & Virtual Geometry
- Implement compute shader-based culling (frustum, occlusion).
- Develop virtual geometry system (Nanite-style micro-polygon rendering).
- Transition to unified GPU command buffers to minimize CPU submission overhead.

### 2. Advanced Lighting (Dynamic GI & Virtual Shadows)
- Implement screen-space or hardware-accelerated raytraced Dynamic Global Illumination.
- Build Virtual Shadow Maps (VSM) for high-resolution, scalable shadow rendering.
- Integrate temporal upscaling techniques (TAA, FSR2) into the render graph.

### 3. GPU VFX & Particles
- Build a node-based GPU particle simulation framework.
- Enable high-count particle rendering (Niagara-style) interacting with the depth/GBuffer.
