use crate::allocator::arena::{AllocError, ArenaAllocator};
use crate::allocator::CustomAllocator;
use core::alloc::Layout;
use core::sync::atomic::{AtomicU64, AtomicUsize, Ordering};

/// A double-buffered ping-pong frame allocator designed to decouple game loop phases.
///
/// In modern game engines, the main simulation loop (ECS, physics, game logic) in frame N
/// produces draw calls, transform arrays, and transient buffers consumed by the render pipeline
/// or GPU driver in frame N-1.
///
/// `DoubleBufferedFrameAllocator` manages two alternating `ArenaAllocator` instances:
/// - Logic thread writes to `current_arena()`.
/// - Render thread or previous frame consumers read from `previous_arena()`.
/// - At the frame boundary, `swap_buffers()` advances the frame index and automatically
///   resets the newly active arena in O(1), ensuring zero fragmentation.
pub struct DoubleBufferedFrameAllocator {
    /// The two alternating arenas.
    arenas: [ArenaAllocator; 2],
    /// Index (0 or 1) of the currently active write arena.
    current_index: AtomicUsize,
    /// Monotonically increasing frame counter.
    frame_index: AtomicU64,
}

// Safety: Both backing arenas and atomic state support multi-threaded access.
unsafe impl Send for DoubleBufferedFrameAllocator {}
unsafe impl Sync for DoubleBufferedFrameAllocator {}

impl DoubleBufferedFrameAllocator {
    /// Creates a new `DoubleBufferedFrameAllocator` where each frame buffer has `per_frame_capacity` bytes.
    pub fn new(per_frame_capacity: usize) -> Result<Self, AllocError> {
        let arena_a = ArenaAllocator::new(per_frame_capacity)?;
        let arena_b = ArenaAllocator::new(per_frame_capacity)?;

        Ok(Self {
            arenas: [arena_a, arena_b],
            current_index: AtomicUsize::new(0),
            frame_index: AtomicU64::new(0),
        })
    }

    /// Returns a reference to the active arena for the current frame.
    pub fn current_arena(&self) -> &ArenaAllocator {
        let idx = self.current_index.load(Ordering::Acquire) % 2;
        &self.arenas[idx]
    }

    /// Returns a reference to the previous frame's arena (retaining frame N-1 data).
    pub fn previous_arena(&self) -> &ArenaAllocator {
        let idx = (self.current_index.load(Ordering::Acquire) + 1) % 2;
        &self.arenas[idx]
    }

    /// Swaps the active ping-pong buffers:
    /// 1. Increments the frame counter.
    /// 2. Alternates the active arena index (0 -> 1 -> 0).
    /// 3. Resets the incoming arena in O(1) so it is ready for fresh allocations.
    pub fn swap_buffers(&self) {
        let old_idx = self.current_index.load(Ordering::Relaxed);
        let new_idx = (old_idx + 1) % 2;

        // Reset incoming buffer FIRST before publishing new_idx
        self.arenas[new_idx].reset();

        self.frame_index.fetch_add(1, Ordering::Relaxed);
        self.current_index.store(new_idx, Ordering::Release);
    }

    /// Swaps buffers without resetting the new buffer (useful for inspection or custom recycling).
    pub fn swap_buffers_no_reset(&self) {
        let old_idx = self.current_index.load(Ordering::Relaxed);
        let new_idx = (old_idx + 1) % 2;

        self.current_index.store(new_idx, Ordering::Release);
        self.frame_index.fetch_add(1, Ordering::Relaxed);
    }

    /// Returns the monotonic frame count since initialization.
    pub fn frame_index(&self) -> u64 {
        self.frame_index.load(Ordering::Acquire)
    }

    /// Returns the raw active arena index (0 or 1).
    pub fn current_index(&self) -> usize {
        self.current_index.load(Ordering::Acquire) % 2
    }

    /// Allocates raw memory in the current active frame arena.
    pub fn alloc_raw(&self, layout: Layout) -> Result<*mut u8, AllocError> {
        self.current_arena().alloc_raw(layout)
    }

    /// Allocates a contiguous slice in the current active frame arena.
    #[allow(clippy::mut_from_ref)]
    pub fn alloc_slice<T: Copy>(
        &self,
        count: usize,
        default_val: T,
    ) -> Result<&mut [T], AllocError> {
        self.current_arena().alloc_slice(count, default_val)
    }

    /// Allocates a typed slot in the current active frame arena.
    #[allow(clippy::mut_from_ref)]
    pub fn alloc<T: Copy>(&self, value: T) -> Result<&mut T, AllocError> {
        self.current_arena().alloc(value)
    }

    /// Allocates a contiguous 1MB buffer with sentinels in the current active frame arena.
    #[allow(clippy::mut_from_ref)]
    pub fn alloc_1mb_buffer(&self) -> Result<&mut [u8], AllocError> {
        self.current_arena().alloc_1mb_buffer()
    }

    /// Returns bytes allocated in the active frame arena.
    pub fn allocated_bytes(&self) -> usize {
        self.current_arena().allocated_bytes()
    }

    /// Returns per-frame capacity of the active arena.
    pub fn capacity_bytes(&self) -> usize {
        self.current_arena().capacity_bytes()
    }

    /// Returns remaining bytes in the active frame arena.
    pub fn remaining_bytes(&self) -> usize {
        self.current_arena().remaining_bytes()
    }

    /// Returns allocation count in the active frame arena.
    pub fn allocation_count(&self) -> usize {
        self.current_arena().allocation_count()
    }
}

impl CustomAllocator for DoubleBufferedFrameAllocator {
    unsafe fn alloc_raw(&self, layout: Layout) -> Result<*mut u8, AllocError> {
        self.current_arena().alloc_raw(layout)
    }

    fn reset(&self) {
        self.current_arena().reset();
    }

    fn allocated_bytes(&self) -> usize {
        self.current_arena().allocated_bytes()
    }

    fn capacity_bytes(&self) -> usize {
        self.current_arena().capacity_bytes()
    }
}
