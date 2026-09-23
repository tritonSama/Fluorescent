# Dispatch: Unified Pipeline Agent

## Objective
Design and implement the unified GPU command buffer architecture for the `fluoderpod_render` crate.

## Primary Responsibilities
- Abstract the differences between Vulkan, Metal, and WebGPU into a unified, high-performance command submission structure.
- Define the core structures for Indirect Drawing (multi-draw indirect).
- Handle the memory allocation and buffer management for the data fed in by `fluoderpod`.
- Act as the primary dispatcher for the compute passes written by the Compute Culling Agent and Virtual Geometry Agent.

## Architectural Boundaries
- Do not write the specific culling or geometry logic; focus on the API abstractions, render graph orchestration, and buffer lifecycle.
- Guarantee that all FFI boundaries with `fluoderpod` are zero-copy, memory-safe, and panic-free.