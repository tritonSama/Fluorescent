use crate::allocator::{
    verify_buffer_sentinels as verify_sentinels_internal, DoubleBufferedFrameAllocator,
    SENTINEL_FOOTER, SENTINEL_HEADER,
};
use serde::{Deserialize, Serialize};
use std::ffi::c_char;
use std::sync::RwLock;

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

    // Ensure engine allocator is initialized
    {
        let mut guard = ENGINE_ALLOCATOR
            .write()
            .expect("Lock poisoned during allocate_engine_buffer");

        if guard.is_none() {
            let allocator = DoubleBufferedFrameAllocator::new(DEFAULT_ENGINE_FRAME_CAPACITY)
                .expect("Failed to initialize engine frame allocator");
            *guard = Some(allocator);
        }
    }

    let mut buffer = vec![0u8; size_bytes];
    if size_bytes > 0 {
        buffer[0] = SENTINEL_HEADER;
        if size_bytes > 1 {
            buffer[size_bytes - 1] = SENTINEL_FOOTER;
        }
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
    pub data: Vec<u8>,
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

    /// Reads the byte at the specified offset with safe bounds checking.
    #[flutter_rust_bridge::frb(sync)]
    pub fn read_byte(&self, offset: usize) -> u8 {
        self.data.get(offset).copied().unwrap_or(0)
    }

    /// Writes a byte at the specified offset with safe bounds checking.
    #[flutter_rust_bridge::frb(sync)]
    pub fn write_byte(&mut self, offset: usize, value: u8) {
        if let Some(cell) = self.data.get_mut(offset) {
            *cell = value;
        }
    }
}

/// C-ABI compatible memory layout for passing EngineStatus across FFI boundaries.
#[repr(C)]
#[derive(Debug, Clone)]
// Helper to wrapper c_char pointer to satisfy Send/Sync
#[derive(Debug, Clone)]
pub struct CStringPtr(pub *const c_char);
unsafe impl Send for CStringPtr {}
unsafe impl Sync for CStringPtr {}

#[repr(C)]
#[derive(Debug, Clone)]
pub struct EngineStatusC {
    pub is_initialized: bool,
    pub total_memory_allocated: usize,
    pub arena_capacity: usize,
    pub frame_index: u64,
    pub status_message: CStringPtr,
    pub core_version: CStringPtr,
    pub allocator_name: CStringPtr,
}

// Ensure EngineStatusC is Send/Sync so FRB can pass it across isolate boundaries.
unsafe impl Send for EngineStatusC {}
unsafe impl Sync for EngineStatusC {}

static MSG_INITIALIZED: &[u8] = b"Fluorite Engine Core Initialized\0";
static MSG_RUNNING: &[u8] = b"Fluorite Engine Core Running\0";
static MSG_NOT_INITIALIZED: &[u8] = b"Fluorite Engine Core Not Initialized\0";
static VERSION_STR: &[u8] = b"0.1.0\0";
static ALLOC_NAME: &[u8] = b"FluoriteArenaAllocator_v1\0";

impl From<&EngineStatus> for EngineStatusC {
    fn from(status: &EngineStatus) -> Self {
        let msg_ptr = if !status.is_initialized {
            MSG_NOT_INITIALIZED.as_ptr() as *const c_char
        } else if status.status_message.contains("Initialized") {
            MSG_INITIALIZED.as_ptr() as *const c_char
        } else {
            MSG_RUNNING.as_ptr() as *const c_char
        };

        Self {
            is_initialized: status.is_initialized,
            total_memory_allocated: status.total_memory_allocated,
            arena_capacity: status.arena_capacity,
            frame_index: status.frame_index,
            status_message: CStringPtr(msg_ptr),
            core_version: CStringPtr(VERSION_STR.as_ptr() as *const c_char),
            allocator_name: CStringPtr(ALLOC_NAME.as_ptr() as *const c_char),
        }
    }
}
