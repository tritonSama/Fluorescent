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
pub mod ecs;
pub mod ffi;
pub mod frb_generated;
pub mod jni;
pub mod physics;
pub mod rendering;
pub mod servers;
pub mod spatial;

pub use allocator::{
    AllocError, ArenaAllocator, CustomAllocator, DoubleBufferedFrameAllocator, ONE_MB,
    SENTINEL_FOOTER, SENTINEL_HEADER,
};

pub use api::{
    allocate_engine_buffer, get_engine_status, start_engine, verify_buffer_sentinels,
    verify_buffer_sentinels_slice, EngineStatus, EngineStatusC, SharedFrameBuffer,
    DEFAULT_ENGINE_FRAME_CAPACITY,
};

pub use physics::{CharacterController, CharacterMovementResult, PhysicsWorld, StepStats};

pub use rendering::{QualityTier, Renderer};

pub use spatial::{
    Aabb, FlatBvh, FlatBvhNode, Frustum, FrustumCullingStats, FrustumIntersection, Plane, Ray,
    RayHit,
};
