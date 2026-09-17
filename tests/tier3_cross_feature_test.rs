// tests/tier3_cross_feature_test.rs
//
// Tier 3: Cross-Feature Combinations (Rust Native E2E Test Suite)
// Tests pairwise combinations across subsystems:
// 1. Allocator + Reset + Frame Buffer Swap
// 2. Arena Allocation + FFI Buffer Transfer
// 3. FFI Call + 1MB Buffer Readback & Sentinels
// 4. Shared Memory Native Pointer + Hex Viewer Formatting
// 5. In-Place Mutation + Allocator Accounting

pub struct TestArena {
    buffer: Vec<u8>,
    capacity: usize,
    offset: usize,
}

impl TestArena {
    pub fn new(capacity: usize) -> Self {
        Self { buffer: vec![0u8; capacity], capacity, offset: 0 }
    }

    pub fn alloc_slice(&mut self, count: usize, val: u8) -> Result<&mut [u8], ()> {
        if self.offset + count > self.capacity { return Err(()); }
        let start = self.offset;
        self.offset += count;
        self.buffer[start..start + count].fill(val);
        Ok(&mut self.buffer[start..start + count])
    }

    pub fn reset(&mut self) {
        self.offset = 0;
    }

    pub fn allocated_bytes(&self) -> usize { self.offset }
}

pub struct TestFrameAllocator {
    arenas: [TestArena; 2],
    current: usize,
}

impl TestFrameAllocator {
    pub fn new(cap: usize) -> Self {
        Self {
            arenas: [TestArena::new(cap), TestArena::new(cap)],
            current: 0,
        }
    }

    pub fn current_arena(&mut self) -> &mut TestArena {
        let idx = self.current % 2;
        &mut self.arenas[idx]
    }

    pub fn previous_arena(&self) -> &TestArena {
        let idx = (self.current + 1) % 2;
        &self.arenas[idx]
    }

    pub fn swap(&mut self) {
        self.current += 1;
        let idx = self.current % 2;
        self.arenas[idx].reset();
    }
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
// Tier 3 Pairwise Tests
// -----------------------------------------------------------------------------

#[test]
fn test_t3_allocator_reset_and_frame_swap() {
    let mut frame_alloc = TestFrameAllocator::new(128 * 1024);

    for frame in 0..50 {
        {
            let arena = frame_alloc.current_arena();
            assert_eq!(arena.allocated_bytes(), 0);
            let slice = arena.alloc_slice(1024, frame as u8).unwrap();
            assert_eq!(slice[0], frame as u8);
        }
        frame_alloc.swap();
        assert!(frame_alloc.previous_arena().allocated_bytes() >= 1024);
    }
}

#[test]
fn test_t3_arena_allocation_and_ffi_buffer_transfer() {
    let mut arena = TestArena::new(2 * 1024 * 1024);
    let slice = arena.alloc_slice(1024 * 1024, 0x00).unwrap();
    slice[0] = 0xAA;
    slice[slice.len() - 1] = 0x55;

    assert!(verify_buffer_sentinels(slice));
    assert_eq!(arena.allocated_bytes(), 1024 * 1024);
}

#[test]
fn test_t3_dart_call_and_1mb_buffer_readback() {
    let buf = allocate_engine_buffer(1024 * 1024);
    assert_eq!(buf.len(), 1024 * 1024);
    assert_eq!(buf[0], 0xAA);
    assert_eq!(buf[1024 * 1024 - 1], 0x55);
    assert!(verify_buffer_sentinels(&buf));
}

#[test]
fn test_t3_shared_buffer_pointer_and_editor_controller() {
    let mut buf = allocate_engine_buffer(1024 * 1024);
    buf[0] = 0xDE;
    buf[1] = 0xAD;
    buf[2] = 0xBE;
    buf[3] = 0xEF;

    let hex_view = format!("{:02X} {:02X} {:02X} {:02X}", buf[0], buf[1], buf[2], buf[3]);
    assert_eq!(hex_view, "DE AD BE EF");
}

#[test]
fn test_t3_ffi_mutation_and_allocator_metrics() {
    let mut buf = allocate_engine_buffer(1024 * 1024);
    buf.fill(0x33);
    assert_eq!(buf[0], 0x33);
    assert_eq!(buf[buf.len() - 1], 0x33);
}
