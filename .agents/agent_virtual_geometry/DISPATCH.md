# Dispatch: Virtual Geometry Agent

## Objective
Build the Nanite-style micro-polygon rendering and virtual geometry system for the `fluoderpod_render` crate.

## Primary Responsibilities
- Implement mesh clustering algorithms and cluster LOD generation during the asset pipeline phase.
- Develop the runtime streaming system to page in geometry clusters based on camera proximity and occlusion.
- Write compute shaders to perform cluster-level and triangle-level culling.
- Implement software rasterizer fallbacks for tiny triangles to reduce hardware rasterizer quad overdraw, or utilize mesh shaders where hardware permits.

## Architectural Boundaries
- Work closely with the Compute Culling Agent to ensure visibility data flows correctly into the cluster selection logic.
- Operate exclusively within `fluoderpod_render`.
- Do not build traditional forward/deferred lighting, focus only on the virtualized geometry output (e.g., writing to a visibility buffer).