// # Fluorite Core
//
// High-performance Rust native foundation and custom zero-fragmentation memory allocators
// for the Fluorite AAA Game Engine.
//
// ## Modules
// - `allocator`: Custom memory allocators (`ArenaAllocator`, `DoubleBufferedFrameAllocator`).
// - `api`: Engine lifecycle and memory allocation API for zero-copy FFI bridge.
// - `rendering`: Phase 2 Rendering Foundation with dynamic quality tiers.

pub mod allocator;
pub mod api;
pub mod frb_generated;
pub mod jni;
pub mod rendering;
pub mod servers;

pub use allocator::{
    AllocError, ArenaAllocator, CustomAllocator, DoubleBufferedFrameAllocator, ONE_MB,
    SENTINEL_FOOTER, SENTINEL_HEADER,
};

pub use api::{
    allocate_engine_buffer, get_engine_status, start_engine, verify_buffer_sentinels,
    verify_buffer_sentinels_slice, EngineStatus, SharedFrameBuffer,
    DEFAULT_ENGINE_FRAME_CAPACITY,
};

pub use rendering::{QualityTier, Renderer};
