use core::alloc::Layout;
use core::ptr::NonNull;
use core::sync::atomic::{AtomicUsize, Ordering};
use thiserror::Error;

/// 1 Megabyte in bytes (1024 * 1024).
pub const ONE_MB: usize = 1_048_576;

/// Header sentinel written to the first byte of a 1MB test buffer.
pub const SENTINEL_HEADER: u8 = 0xAA;

/// Footer sentinel written to the last byte of a 1MB test buffer.
pub const SENTINEL_FOOTER: u8 = 0x55;

/// Errors that can occur during memory allocation.
#[derive(Error, Debug, Clone, Copy, PartialEq, Eq)]
pub enum AllocError {
    #[error("Out of memory: requested allocation exceeds arena capacity")]
    OutOfMemory,
    #[error("Invalid layout: size or alignment calculation overflowed")]
    InvalidLayout,
    #[error("Unsupported alignment: alignment must be a non-zero power of two")]
    UnsupportedAlignment,
}

/// A high-performance bump-pointer arena allocator designed for zero-fragmentation game loops.
///
/// Features:
/// - Pre-allocated contiguous backing buffer with 64-byte hardware cache-line alignment.
/// - Atomic bump pointer enabling concurrent allocations and interior mutability (`&self`).
/// - Strict power-of-two alignment padding using `(align - (addr & (align - 1))) & (align - 1)`.
/// - O(1) bulk reset that reclaims all memory in a single instruction without freeing the backing buffer.
/// - Comprehensive telemetry: allocated bytes, capacity, remaining bytes, allocation count, and peak usage.
pub struct ArenaAllocator {
    /// Pointer to the pre-allocated backing memory block.
    buffer: NonNull<u8>,
    /// Memory layout used to allocate and deallocate the backing block.
    layout: Layout,
    /// Total usable capacity of the backing buffer in bytes.
    capacity: usize,
    /// Current allocation offset from the buffer base.
    offset: AtomicUsize,
    /// Total number of allocations performed since the last reset.
    allocation_count: AtomicUsize,
    /// High-water mark of allocated bytes recorded across lifetimes.
    peak_usage: AtomicUsize,
}

// Safety: ArenaAllocator internally uses atomic operations for bump-pointer adjustments
// and guarantees that concurrent allocations receive non-overlapping memory regions.
unsafe impl Send for ArenaAllocator {}
unsafe impl Sync for ArenaAllocator {}

impl ArenaAllocator {
    /// Creates a new `ArenaAllocator` with the requested capacity in bytes.
    ///
    /// The backing memory is allocated aligned to 64 bytes (CPU cache-line boundary).
    pub fn new(capacity: usize) -> Result<Self, AllocError> {
        if capacity == 0 {
            return Err(AllocError::InvalidLayout);
        }

        // Base buffer aligned to 64 bytes (hardware cache-line boundary)
        let layout = Layout::from_size_align(capacity, 64)
            .map_err(|_| AllocError::InvalidLayout)?;

        let ptr = unsafe { std::alloc::alloc(layout) };
        let buffer = NonNull::new(ptr).ok_or(AllocError::OutOfMemory)?;

        Ok(Self {
            buffer,
            layout,
            capacity,
            offset: AtomicUsize::new(0),
            allocation_count: AtomicUsize::new(0),
            peak_usage: AtomicUsize::new(0),
        })
    }

    /// Allocates raw memory satisfying the given `Layout`.
    ///
    /// The returned pointer is guaranteed to be aligned to `layout.align()`.
    /// Returns `AllocError::OutOfMemory` if the remaining capacity cannot satisfy the request.
    pub fn alloc_raw(&self, layout: Layout) -> Result<*mut u8, AllocError> {
        let size = layout.size();
        let align = layout.align();

        if !align.is_power_of_two() {
            return Err(AllocError::UnsupportedAlignment);
        }

        // Zero-sized types do not consume arena memory but must satisfy layout alignment
        if size == 0 {
            return Ok(align as *mut u8);
        }

        let base_addr = self.buffer.as_ptr() as usize;
        let mut current_offset = self.offset.load(Ordering::Relaxed);

        loop {
            let current_addr = base_addr + current_offset;

            // Rigorous power-of-two alignment padding: (align - (addr & (align - 1))) & (align - 1)
            let padding = (align - (current_addr & (align - 1))) & (align - 1);

            let start_offset = match current_offset.checked_add(padding) {
                Some(val) => val,
                None => return Err(AllocError::OutOfMemory),
            };

            let end_offset = match start_offset.checked_add(size) {
                Some(val) => val,
                None => return Err(AllocError::OutOfMemory),
            };

            if end_offset > self.capacity {
                return Err(AllocError::OutOfMemory);
            }

            match self.offset.compare_exchange_weak(
                current_offset,
                end_offset,
                Ordering::AcqRel,
                Ordering::Relaxed,
            ) {
                Ok(_) => {
                    self.allocation_count.fetch_add(1, Ordering::Relaxed);

                    // Update high-water peak usage telemetry
                    let mut current_peak = self.peak_usage.load(Ordering::Relaxed);
                    while end_offset > current_peak {
                        match self.peak_usage.compare_exchange_weak(
                            current_peak,
                            end_offset,
                            Ordering::Relaxed,
                            Ordering::Relaxed,
                        ) {
                            Ok(_) => break,
                            Err(actual) => current_peak = actual,
                        }
                    }

                    let aligned_ptr = (base_addr + start_offset) as *mut u8;
                    return Ok(aligned_ptr);
                }
                Err(actual) => current_offset = actual,
            }
        }
    }

    /// Allocates a contiguous mutable slice of `count` elements initialized to `default_val`.
    #[allow(clippy::mut_from_ref)]
    pub fn alloc_slice<T: Copy>(&self, count: usize, default_val: T) -> Result<&mut [T], AllocError> {
        if count == 0 {
            return Ok(&mut []);
        }

        let layout = Layout::array::<T>(count).map_err(|_| AllocError::InvalidLayout)?;
        let raw_ptr = self.alloc_raw(layout)? as *mut T;

        unsafe {
            let slice = core::slice::from_raw_parts_mut(raw_ptr, count);
            slice.fill(default_val);
            Ok(slice)
        }
    }

    /// Allocates a typed slot initialized to `value`.
    #[allow(clippy::mut_from_ref)]
    pub fn alloc<T: Copy>(&self, value: T) -> Result<&mut T, AllocError> {
        let layout = Layout::new::<T>();
        let raw_ptr = self.alloc_raw(layout)? as *mut T;

        unsafe {
            raw_ptr.write(value);
            Ok(&mut *raw_ptr)
        }
    }

    /// Allocates a contiguous 1MB buffer (1,048,576 bytes) with sentinels:
    /// - Header sentinel: `0xAA` at index 0.
    /// - Footer sentinel: `0x55` at index 1,048,575.
    #[allow(clippy::mut_from_ref)]
    pub fn alloc_1mb_buffer(&self) -> Result<&mut [u8], AllocError> {
        let slice = self.alloc_slice(ONE_MB, 0u8)?;
        slice[0] = SENTINEL_HEADER;
        slice[ONE_MB - 1] = SENTINEL_FOOTER;
        Ok(slice)
    }

    /// Resets the allocator offset to zero in O(1).
    ///
    /// This instantly reclaims all memory allocated from this arena for the next frame
    /// without deallocating or reallocating the backing OS buffer.
    pub fn reset(&self) {
        self.offset.store(0, Ordering::Release);
        self.allocation_count.store(0, Ordering::Release);
    }

    /// Returns the number of bytes currently allocated (including alignment padding).
    pub fn allocated_bytes(&self) -> usize {
        self.offset.load(Ordering::Acquire)
    }

    /// Returns the total capacity of the arena in bytes.
    pub fn capacity_bytes(&self) -> usize {
        self.capacity
    }

    /// Returns the remaining available bytes before exhaustion.
    pub fn remaining_bytes(&self) -> usize {
        self.capacity.saturating_sub(self.allocated_bytes())
    }

    /// Returns the number of allocations performed since initialization or the last reset.
    pub fn allocation_count(&self) -> usize {
        self.allocation_count.load(Ordering::Acquire)
    }

    /// Returns the highest byte offset reached by the allocator.
    pub fn peak_usage_bytes(&self) -> usize {
        self.peak_usage.load(Ordering::Acquire)
    }

    /// Returns the raw pointer to the base of the backing buffer.
    pub fn buffer_base_ptr(&self) -> *const u8 {
        self.buffer.as_ptr()
    }
}

impl Drop for ArenaAllocator {
    fn drop(&mut self) {
        unsafe {
            std::alloc::dealloc(self.buffer.as_ptr(), self.layout);
        }
    }
}

/// Verifies whether the given buffer has valid sentinels (0xAA header and 0x55 footer).
///
/// Requires buffer length >= 2 to accommodate two distinct boundary sentinels.
pub fn verify_buffer_sentinels(buffer: &[u8]) -> bool {
    buffer.len() >= 2 && buffer[0] == SENTINEL_HEADER && buffer[buffer.len() - 1] == SENTINEL_FOOTER
}
