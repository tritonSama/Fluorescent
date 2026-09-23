# Dispatch: Rendering Architect Agent

## Assigned Tasks (Phase 2)
- Currently on standby. Provide graphics/rendering support as needed for the Functional Test App.

## Assigned Tasks (Phase 3)

### 1. GPU-Driven Rendering & Virtual Geometry
*(Note: These tasks have been delegated to the `Compute Culling Agent`, `Virtual Geometry Agent`, and `Unified Pipeline Agent` working within the `fluoderpod_render` crate. The Rendering Architect will oversee their integration into the wider engine).*

### 2. Advanced Lighting (Dynamic GI & Virtual Shadows)
- Implement screen-space or hardware-accelerated raytraced Dynamic Global Illumination.
- Build Virtual Shadow Maps (VSM) for high-resolution, scalable shadow rendering.
- Integrate temporal upscaling techniques (TAA, FSR2) into the render graph.

### 3. GPU VFX & Particles
- Build a node-based GPU particle simulation framework.
- Enable high-count particle rendering (Niagara-style) interacting with the depth/GBuffer.
