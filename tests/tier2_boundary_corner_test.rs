// tests/tier2_boundary_corner_test.rs
//
// Tier 2: Boundary & Corner Cases (Rust Native E2E Test Suite)
// Tests: 0 bytes, 1 byte, exact 1MB, power-of-two boundaries, alignment ladder 1..64, capacity saturation.

use std::alloc::Layout;

#[derive(Debug, PartialEq, Eq)]
pub enum AllocError {
    OutOfMemory,
    InvalidLayout,
}

pub struct TestArenaAllocator {
    buffer: Vec<u8>,
    capacity: usize,
    offset: usize,
}

impl TestArenaAllocator {
    pub fn new(capacity: usize) -> Result<Self, AllocError> {
        if capacity == 0 { return Err(AllocError::InvalidLayout); }
        Ok(Self { buffer: vec![0u8; capacity], capacity, offset: 0 })
    }

    pub fn alloc_raw(&mut self, layout: Layout) -> Result<*mut u8, AllocError> {
        let size = layout.size();
        let align = layout.align();

        if size == 0 {
            let base_addr = self.buffer.as_ptr() as usize;
            let padding = (align - (base_addr & (align - 1))) & (align - 1);
            return Ok((base_addr + padding) as *mut u8);
        }

        let base_addr = self.buffer.as_ptr() as usize;
        let current_addr = base_addr + self.offset;
        let padding = (align - (current_addr & (align - 1))) & (align - 1);
        let next_offset = self.offset.checked_add(padding)
            .and_then(|val| val.checked_add(size))
            .ok_or(AllocError::OutOfMemory)?;

        if next_offset > self.capacity {
            return Err(AllocError::OutOfMemory);
        }

        let ptr = unsafe { self.buffer.as_mut_ptr().add(self.offset + padding) };
        self.offset = next_offset;
        Ok(ptr)
    }

    pub fn allocated_bytes(&self) -> usize { self.offset }
    pub fn remaining_bytes(&self) -> usize { self.capacity.saturating_sub(self.offset) }
}

pub fn allocate_engine_buffer(size_bytes: usize) -> Vec<u8> {
    let mut buffer = vec![0u8; size_bytes];
    if size_bytes > 0 {
        buffer[0] = 0xAA;
        buffer[size_bytes - 1] = 0x55;
    }
    buffer
}

pub fn verify_buffer_sentinels(buffer: &[u8]) -> bool {
    if buffer.is_empty() { return false; }
    buffer[0] == 0xAA && buffer[buffer.len() - 1] == 0x55
}

// -----------------------------------------------------------------------------
// Tier 2 Boundary Tests
// -----------------------------------------------------------------------------

#[test]
fn test_t2_f1_alloc_zero_bytes() {
    let mut arena = TestArenaAllocator::new(1024).unwrap();
    let layout = Layout::from_size_align(0, 8).unwrap();
    let ptr = arena.alloc_raw(layout).unwrap();
    assert!(!ptr.is_null());
    assert_eq!(arena.allocated_bytes(), 0);
}

#[test]
fn test_t2_f1_alloc_single_byte() {
    let mut arena = TestArenaAllocator::new(1024).unwrap();
    let layout = Layout::from_size_align(1, 1).unwrap();
    let ptr = arena.alloc_raw(layout).unwrap();
    assert!(!ptr.is_null());
    assert!(arena.allocated_bytes() >= 1);
}

#[test]
fn test_t2_f1_alloc_exact_capacity() {
    let mut arena = TestArenaAllocator::new(256).unwrap();
    let layout = Layout::from_size_align(256, 1).unwrap();
    let ptr = arena.alloc_raw(layout).unwrap();
    assert!(!ptr.is_null());
    assert_eq!(arena.allocated_bytes(), 256);
    assert_eq!(arena.remaining_bytes(), 0);

    let overflow = arena.alloc_raw(Layout::from_size_align(1, 1).unwrap());
    assert_eq!(overflow, Err(AllocError::OutOfMemory));
}

#[test]
fn test_t2_f1_alloc_capacity_overflow() {
    let mut arena = TestArenaAllocator::new(128).unwrap();
    let layout = Layout::from_size_align(129, 1).unwrap();
    let res = arena.alloc_raw(layout);
    assert_eq!(res, Err(AllocError::OutOfMemory));
    assert_eq!(arena.allocated_bytes(), 0);
}

#[test]
fn test_t2_f1_alignment_ladder_extremes() {
    let mut arena = TestArenaAllocator::new(1024 * 1024).unwrap();
    let alignments = [1, 2, 4, 8, 16, 32, 64];
    let odd_sizes = [3, 7, 13, 19, 31, 47, 63];

    for i in 0..alignments.len() {
        let align = alignments[i];
        let size = odd_sizes[i];
        let layout = Layout::from_size_align(size, align).unwrap();
        let ptr = arena.alloc_raw(layout).unwrap();
        assert_eq!(ptr as usize % align, 0);
    }
}

#[test]
fn test_t2_f2_zero_byte_buffer() {
    let buf = allocate_engine_buffer(0);
    assert!(buf.is_empty());
    assert!(!verify_buffer_sentinels(&buf));
}

#[test]
fn test_t2_f2_single_byte_buffer() {
    let buf = allocate_engine_buffer(1);
    assert_eq!(buf.len(), 1);
}

#[test]
fn test_t2_f2_exact_1mb_boundary() {
    const ONE_MB: usize = 1024 * 1024;
    let buf = allocate_engine_buffer(ONE_MB);
    assert_eq!(buf.len(), ONE_MB);
    assert_eq!(buf[0], 0xAA);
    assert_eq!(buf[ONE_MB - 1], 0x55);
}

#[test]
fn test_t2_f2_power_of_two_sizes() {
    for p in 1..=20 {
        let size = 1 << p;
        let buf = allocate_engine_buffer(size);
        assert_eq!(buf.len(), size);
        assert!(verify_buffer_sentinels(&buf));
    }
}

#[test]
fn test_t2_f2_alignment_boundary_at_64() {
    let mut arena = TestArenaAllocator::new(1024 * 1024).unwrap();
    let layout = Layout::from_size_align(1024 * 1024, 64).unwrap();
    let ptr = arena.alloc_raw(layout).unwrap();
    assert_eq!(ptr as usize % 64, 0);
}

#[test]
fn test_t2_f3_corrupted_sentinel_rejection() {
    let mut buf = allocate_engine_buffer(1024);
    assert!(verify_buffer_sentinels(&buf));

    buf[0] = 0x12;
    assert!(!verify_buffer_sentinels(&buf));

    buf[0] = 0xAA;
    buf[1023] = 0x34;
    assert!(!verify_buffer_sentinels(&buf));
}
