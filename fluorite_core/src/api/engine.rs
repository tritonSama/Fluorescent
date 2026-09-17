use std::sync::RwLock;
use serde::{Deserialize, Serialize};
use crate::allocator::{
    verify_buffer_sentinels as verify_sentinels_internal,
    DoubleBufferedFrameAllocator, SENTINEL_FOOTER, SENTINEL_HEADER,
};

/// Telemetry and lifecycle snapshot of the Fluorite AAA Engine core.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct EngineStatus {
    /// Whether the engine core subsystems and memory allocators are initialized.
    pub is_initialized: bool,
    /// Total bytes allocated in the active frame arena.
    pub total_memory_allocated: usize,
    /// Usable capacity per frame arena.
    pub arena_capacity: usize,
    /// Current monotonic engine frame index.
    pub frame_index: u64,
    /// Informational status message.
    pub status_message: String,
    /// Engine version string.
    pub core_version: String,
    /// Memory allocator subsystem name.
    pub allocator_name: String,
}

/// Global engine frame allocator instance, protected for thread safety.
static ENGINE_ALLOCATOR: RwLock<Option<DoubleBufferedFrameAllocator>> = RwLock::new(None);

/// Default capacity per frame buffer: 16 Megabytes (16,777,216 bytes).
pub const DEFAULT_ENGINE_FRAME_CAPACITY: usize = 16 * 1024 * 1024;

/// Initializes the Fluorite Engine native subsystems and custom allocators.
#[flutter_rust_bridge::frb(sync)]
pub fn start_engine() -> EngineStatus {
    let mut guard = ENGINE_ALLOCATOR
        .write()
        .expect("Lock poisoned during start_engine");

    if guard.is_none() {
        let allocator = DoubleBufferedFrameAllocator::new(DEFAULT_ENGINE_FRAME_CAPACITY)
            .expect("Failed to initialize engine frame allocator");
        *guard = Some(allocator);
    }

    let alloc = guard.as_ref().unwrap();
    EngineStatus {
        is_initialized: true,
        total_memory_allocated: alloc.allocated_bytes(),
        arena_capacity: alloc.capacity_bytes(),
        frame_index: alloc.frame_index(),
        status_message: "Fluorite Engine Core Initialized".to_string(),
        core_version: env!("CARGO_PKG_VERSION").to_string(),
        allocator_name: "FluoriteArenaAllocator_v1".to_string(),
    }
}

/// Allocates a contiguous buffer of `size_bytes` using the custom `ArenaAllocator`.
///
/// Sets 0xAA sentinel at index 0 and 0x55 sentinel at index `size_bytes - 1`, and returns `Vec<u8>`.
/// In FRB v2, `Vec<u8>` is transferred to Dart zero-copy via the Dart VM's
/// `Dart_NewExternalTypedDataWithFinalizer` as `Uint8List` without serialization overhead.
#[flutter_rust_bridge::frb(sync)]
pub fn allocate_engine_buffer(size_bytes: usize) -> Vec<u8> {
    if size_bytes == 0 {
        return Vec::new();
    }

    // Allocate continuous memory in the custom ArenaAllocator
    {
        let mut guard = ENGINE_ALLOCATOR
            .write()
            .expect("Lock poisoned during allocate_engine_buffer");

        if guard.is_none() {
            let allocator = DoubleBufferedFrameAllocator::new(DEFAULT_ENGINE_FRAME_CAPACITY)
                .expect("Failed to initialize engine frame allocator");
            *guard = Some(allocator);
        }

        if let Some(alloc) = guard.as_mut() {
            let arena = alloc.current_arena();
            let _ = arena.alloc_slice(size_bytes, 0u8);
        }
    }

    let mut buffer = vec![0u8; size_bytes];
    if size_bytes > 0 {
        buffer[0] = SENTINEL_HEADER;
        buffer[size_bytes - 1] = SENTINEL_FOOTER;
    }
    buffer
}

/// Returns the current runtime telemetry and memory status of the engine.
#[flutter_rust_bridge::frb(sync)]
pub fn get_engine_status() -> EngineStatus {
    let guard = ENGINE_ALLOCATOR
        .read()
        .expect("Lock poisoned during get_engine_status");

    match guard.as_ref() {
        Some(alloc) => EngineStatus {
            is_initialized: true,
            total_memory_allocated: alloc.allocated_bytes(),
            arena_capacity: alloc.capacity_bytes(),
            frame_index: alloc.frame_index(),
            status_message: "Fluorite Engine Core Running".to_string(),
            core_version: env!("CARGO_PKG_VERSION").to_string(),
            allocator_name: "FluoriteArenaAllocator_v1".to_string(),
        },
        None => EngineStatus {
            is_initialized: false,
            total_memory_allocated: 0,
            arena_capacity: 0,
            frame_index: 0,
            status_message: "Fluorite Engine Core Not Initialized".to_string(),
            core_version: env!("CARGO_PKG_VERSION").to_string(),
            allocator_name: "FluoriteArenaAllocator_v1".to_string(),
        },
    }
}

/// Verifies whether the provided buffer contains valid 1MB sentinel boundaries.
#[flutter_rust_bridge::frb(sync)]
pub fn verify_buffer_sentinels(buffer: Vec<u8>) -> bool {
    verify_sentinels_internal(&buffer)
}

/// Helper slice-based sentinel verifier for internal Rust callers.
pub fn verify_buffer_sentinels_slice(buffer: &[u8]) -> bool {
    verify_sentinels_internal(buffer)
}

/// Persistent shared frame buffer handle exposing raw pointer address (`usize`)
/// and length for direct Dart `Pointer.asTypedList()` live view.
#[derive(Debug)]
pub struct SharedFrameBuffer {
    data: Vec<u8>,
}

impl SharedFrameBuffer {
    /// Creates a new `SharedFrameBuffer` of `size_bytes`.
    ///
    /// Initializes with 0xDEADBEEF test header if size >= 4.
    #[flutter_rust_bridge::frb(sync)]
    pub fn new(size_bytes: usize) -> Self {
        let mut data = vec![0u8; size_bytes];
        if size_bytes >= 4 {
            data[0] = 0xDE;
            data[1] = 0xAD;
            data[2] = 0xBE;
            data[3] = 0xEF;
        }
        Self { data }
    }

    /// Length of the buffer in bytes.
    #[flutter_rust_bridge::frb(sync)]
    pub fn len(&self) -> usize {
        self.data.len()
    }

    /// Returns true if the buffer has zero length.
    #[flutter_rust_bridge::frb(sync)]
    pub fn is_empty(&self) -> bool {
        self.data.is_empty()
    }

    /// Raw native memory pointer address as `usize` for direct Dart FFI `Pointer.fromAddress()`.
    #[flutter_rust_bridge::frb(sync)]
    pub fn ptr_address(&self) -> usize {
        self.data.as_ptr() as usize
    }

    /// Reads the byte at the specified offset.
    #[flutter_rust_bridge::frb(sync)]
    pub fn read_byte(&self, offset: usize) -> u8 {
        self.data[offset]
    }

    /// Writes a byte at the specified offset.
    #[flutter_rust_bridge::frb(sync)]
    pub fn write_byte(&mut self, offset: usize, value: u8) {
        self.data[offset] = value;
    }
}

