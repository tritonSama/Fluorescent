pub mod arena;
pub mod frame;

pub use arena::{
    AllocError, ArenaAllocator, ONE_MB, SENTINEL_FOOTER, SENTINEL_HEADER,
    verify_buffer_sentinels,
};
pub use frame::DoubleBufferedFrameAllocator;

use core::alloc::Layout;

/// Trait defining the core interface of engine memory allocators.
pub trait CustomAllocator {
    /// Allocates raw memory matching the specified `Layout`.
    ///
    /// # Safety
    /// Caller must ensure that references derived from this pointer do not outlive
    /// the allocator or survive across `reset()` invocations.
    unsafe fn alloc_raw(&self, layout: Layout) -> Result<*mut u8, AllocError>;

    /// O(1) bulk reset of allocated memory.
    fn reset(&self);

    /// Total bytes currently allocated.
    fn allocated_bytes(&self) -> usize;

    /// Usable capacity in bytes.
    fn capacity_bytes(&self) -> usize;
}

impl CustomAllocator for ArenaAllocator {
    unsafe fn alloc_raw(&self, layout: Layout) -> Result<*mut u8, AllocError> {
        self.alloc_raw(layout)
    }

    fn reset(&self) {
        self.reset();
    }

    fn allocated_bytes(&self) -> usize {
        self.allocated_bytes()
    }

    fn capacity_bytes(&self) -> usize {
        self.capacity_bytes()
    }
}
