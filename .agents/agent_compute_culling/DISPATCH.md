# Dispatch: Compute Culling Agent

## Objective
Design and implement the compute shader-based frustum and occlusion culling systems for the GPU-driven rendering architecture.

## Primary Responsibilities
- Integrate with `fluoderpod`'s zero-copy FFI batching (Option B) to ingest massive entity transformation arrays directly to the GPU.
- Write compute shaders (WGSL/SPIR-V) to perform frustum culling.
- Implement two-pass occlusion culling (Hierarchical Z-Buffer / HZB generation and testing).
- Ensure output is correctly formatted as indirect draw arguments for the `fluoderpod_render` unified pipeline.

## Architectural Boundaries
- Keep the CPU entirely out of the per-entity visibility loop.
- Operate entirely inside the `fluoderpod_render` crate.
- Rely on the Unified Pipeline Agent for overarching buffer definitions and API submission.