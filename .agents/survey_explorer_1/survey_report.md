# Technical Survey Report: Rust Core Foundation & Custom Memory Allocators (Requirement 1)

**Agent ID:** `survey_explorer_1` (teamwork_preview_explorer)  
**Date:** 2026-09-17  
**Target Subsystem:** `fluorite_core` (Phase 1 AAA Engine Core Foundation)  
**Authoritative Requirement:** `ORIGINAL_REQUEST.md` (§R1, 2026-09-17T16:50:21Z)  

---

## 1. Environment & Workspace Layout Survey

### 1.1 Workspace Boundary & Directory Reconciliation
- **User Prompt Specification:** `Working directory: C:\Users\blue-\projects\Fluorite`
- **Active Workspace Sandbox:** `c:\Users\blue-\projects\Fluorescent` (mapped to `tritonSama/Fluorescent`)
- **Inspection Findings:**
  - Attempting to access file paths outside `c:\Users\blue-\projects\Fluorescent` (e.g., `C:\Users\blue-\projects\Fluorite` or global system directories) triggers security permission prompts that time out in automated execution.
  - The repository root currently contains Dart/Flutter packages (`packages/`, `fluorescent/`), documentation, and test infrastructure. There are currently no existing Rust crates or `.rs` files.
- **Architectural Resolution for Project Structure:**
  - `fluorite_core` MUST be created within the active workspace root:
    `c:\Users\blue-\projects\Fluorescent\fluorite_core` (or `c:\Users\blue-\projects\Fluorescent\packages\fluorite_core`).
  - Creating `fluorite_core` as `c:\Users\blue-\projects\Fluorescent\fluorite_core` provides clean separation from Dart packages while staying within the accessible sandbox.
  - Sibling project `fluorite_editor` can be co-located at `c:\Users\blue-\projects\Fluorescent\fluorite_editor`.

### 1.2 Toolchain & Crate Standards
- **Rust Toolchain:** Standard Rust 2021 edition (compatible with stable `rustc` 1.75+).
- **Compilation Targets:**
  - Windows x86_64 (`x86_64-pc-windows-msvc` / `gnu`).
- **Crate Output Types:**
  - `cdylib`: Dynamic link library (`fluorite_core.dll` on Windows) providing C-compatible ABI exports for `flutter_rust_bridge` / Dart FFI.
  - `rlib`: Static Rust library enabling native integration tests (`cargo test`), benchmarks, and internal module reuse.

---

## 2. Architecture & Design of Custom Game Engine Allocators

### 2.1 The Game Loop Allocation Problem
Standard system allocators (`malloc`, `free`, or default Rust global allocators) suffer from severe limitations in real-time game engines:
1. **Non-Deterministic Latency:** Lock contention across engine threads and search loops (free lists, segregated bins) introduce micro-stutters that violate 16.6ms (60 FPS) or 6.94ms (144 FPS) frame budgets.
2. **Memory Fragmentation:** Allocating millions of transient objects (draw calls, particle states, transform matrices, collision pairs, visibility query results) fragments virtual memory, causing memory bloat and cache thrashing.
3. **Deallocation Overhead:** Individual pointer chasing and destructor execution on thousands of short-lived objects wastes significant CPU cycles.

Game engine allocators categorize allocations by **lifetime scopes**:
- **Transient Frame Lifetime:** Allocated during the current frame, completely discarded at the end of the frame.
- **Inter-Frame / Double-Buffered Lifetime:** Produced in frame $N$ to be consumed by rendering/physics in frame $N+1$.
- **Phase / Level Lifetime:** Persists throughout a level, game mode, or asset stream.

---

### 2.2 Basic Arena Allocator (Linear / Bump Allocator)

#### 2.2.1 Core Architectural Principles
A bump allocator manages a contiguous memory block. Allocation simply aligns the current offset and increments it by the requested size. Deallocation of individual objects is a no-op; all allocated memory is reclaimed simultaneously in $O(1)$ by resetting the offset to zero.

#### 2.2.2 Data Structures & Internal Layout

```
Contiguous Buffer (Capacity = C)
+-------------------------------------------------------------------------------+
| [Object 1] | pad | [Object 2] | pad | [Object 3] | (Available Space)          |
+-------------------------------------------------------------------------------+
^                                                  ^                            ^
|                                                  |                            |
base_ptr                                           bump_ptr / offset            capacity
```

```rust
// Proposed architecture for fluorite_core::allocator::arena
use core::alloc::Layout;
use core::ptr::NonNull;
use std::alloc::{alloc, dealloc};

#[derive(Debug, PartialEq, Eq)]
pub enum AllocError {
    OutOfMemory,
    InvalidLayout,
    UnsupportedAlignment,
}

pub struct ArenaAllocator {
    /// Pointer to the pre-allocated block of memory
    buffer: NonNull<u8>,
    /// Total capacity of the buffer in bytes
    capacity: usize,
    /// Current allocation offset from buffer base
    offset: usize,
    /// Maximum high-water mark recorded (for telemetry/profiling)
    peak_usage: usize,
}
```

#### 2.2.3 Bump Allocation Algorithm
```rust
impl ArenaAllocator {
    pub fn new(capacity: usize) -> Result<Self, AllocError> {
        if capacity == 0 {
            return Err(AllocError::InvalidLayout);
        }
        // Base buffer aligned to maximum hardware cache line (64 bytes)
        let layout = Layout::from_size_align(capacity, 64)
            .map_err(|_| AllocError::InvalidLayout)?;
        
        let ptr = unsafe { alloc(layout) };
        let buffer = NonNull::new(ptr).ok_or(AllocError::OutOfMemory)?;

        Ok(Self {
            buffer,
            capacity,
            offset: 0,
            peak_usage: 0,
        })
    }

    /// Allocates raw memory according to the specified Layout.
    pub fn alloc_raw(&mut self, layout: Layout) -> Result<NonNull<u8>, AllocError> {
        let size = layout.size();
        let align = layout.align();

        // Current raw address
        let current_ptr = unsafe { self.buffer.as_ptr().add(self.offset) };
        let current_addr = current_ptr as usize;

        // Calculate alignment padding
        let padding = (align - (current_addr & (align - 1))) & (align - 1);
        let next_offset = self.offset.checked_add(padding)
            .and_then(|val| val.checked_add(size))
            .ok_or(AllocError::OutOfMemory)?;

        if next_offset > self.capacity {
            return Err(AllocError::OutOfMemory);
        }

        let aligned_ptr = unsafe { current_ptr.add(padding) };
        self.offset = next_offset;
        if self.offset > self.peak_usage {
            self.peak_usage = self.offset;
        }

        NonNull::new(aligned_ptr).ok_or(AllocError::OutOfMemory)
    }

    /// Allocates typed slot for type T and initializes it.
    pub fn alloc<T>(&mut self, value: T) -> Result<&mut T, AllocError> {
        let layout = Layout::new::<T>();
        let ptr = self.alloc_raw(layout)?.as_ptr() as *mut T;
        unsafe {
            ptr.write(value);
            Ok(&mut *ptr)
        }
    }

    /// Allocates a contiguous slice of T initialized with default values or clones.
    pub fn alloc_slice<T: Clone>(&mut self, count: usize, initial: T) -> Result<&mut [T], AllocError> {
        let layout = Layout::array::<T>(count).map_err(|_| AllocError::InvalidLayout)?;
        let ptr = self.alloc_raw(layout)?.as_ptr() as *mut T;
        unsafe {
            for i in 0..count {
                ptr.add(i).write(initial.clone());
            }
            Ok(std::slice::from_raw_parts_mut(ptr, count))
        }
    }

    /// O(1) bulk reset of the arena. Discards all previous allocations.
    pub fn reset(&mut self) {
        self.offset = 0;
    }

    pub fn allocated_bytes(&self) -> usize {
        self.offset
    }

    pub fn remaining_bytes(&self) -> usize {
        self.capacity.saturating_sub(self.offset)
    }

    pub fn capacity(&self) -> usize {
        self.capacity
    }
}

impl Drop for ArenaAllocator {
    fn drop(&mut self) {
        let layout = Layout::from_size_align(self.capacity, 64).unwrap();
        unsafe {
            dealloc(self.buffer.as_ptr(), layout);
        }
    }
}
```

#### 2.2.4 Chunked Arena (Dynamic Growth Variant)
For workloads where total capacity cannot be strictly bounded at startup:
- `ChunkedArena` maintains a chain or `Vec<Chunk>` of pre-allocated blocks (e.g., 64KB, 128KB, 256KB or fixed 1MB chunks).
- When the active chunk runs out of space, allocate a new chunk.
- On `reset()`, all chunks are retained (avoiding OS page faults in future frames), and allocation resets to the start of Chunk 0.

---

### 2.3 Frame Allocator (Double-Buffered & Ring Allocators)

#### 2.3.1 Double-Buffered Frame Allocator
In modern game engines, the main simulation loop runs concurrently or in pipelined lockstep with the rendering pipeline:
- **Frame $N$ (Logic):** Simulation (ECS, physics, AI) generates rendering commands and transforms.
- **Frame $N-1$ (Render/GPU):** Render thread or GPU driver consumes transforms and meshes prepared in the previous frame.

A **Double-Buffered Frame Allocator** maintains two distinct arenas (`arenas[0]` and `arenas[1]`):
- Active write arena: `arenas[current_frame % 2]`
- Active read / previous arena: `arenas[(current_frame + 1) % 2]`
- At the frame boundary (`end_frame()` / `swap_buffers()`):
  1. Advance frame counter: `current_frame += 1`
  2. Reset the new write arena: `arenas[current_frame % 2].reset()`
  3. The previous frame's data is now safely retained in the alternate buffer!

```rust
// Proposed architecture for fluorite_core::allocator::frame
pub struct DoubleBufferedFrameAllocator {
    arenas: [ArenaAllocator; 2],
    current_frame: usize,
}

impl DoubleBufferedFrameAllocator {
    pub fn new(frame_capacity: usize) -> Result<Self, AllocError> {
        Ok(Self {
            arenas: [
                ArenaAllocator::new(frame_capacity)?,
                ArenaAllocator::new(frame_capacity)?,
            ],
            current_frame: 0,
        })
    }

    /// Allocate memory for the current frame
    pub fn alloc_raw(&mut self, layout: Layout) -> Result<NonNull<u8>, AllocError> {
        let idx = self.current_frame % 2;
        self.arenas[idx].alloc_raw(layout)
    }

    /// Allocate a 1MB contiguous byte buffer (for zero-copy FFI bridge verification)
    pub fn alloc_buffer(&mut self, size: usize) -> Result<&mut [u8], AllocError> {
        let idx = self.current_frame % 2;
        self.arenas[idx].alloc_slice(size, 0u8)
    }

    /// Advance to the next frame and clear the incoming buffer
    pub fn next_frame(&mut self) {
        self.current_frame = self.current_frame.wrapping_add(1);
        let idx = self.current_frame % 2;
        self.arenas[idx].reset();
    }

    pub fn current_frame_index(&self) -> usize {
        self.current_frame
    }
}
```

#### 2.3.2 Ring Allocator (Circular Transient Allocator)
For asynchronous GPU fence synchronization or multi-buffered workloads (triple-buffering):
- Operates a circular buffer with a `head` (current allocation point) and `tail` (reclaimed point confirmed by GPU fence or frame token).
- Allows variable-latency frame completion without hard stalls.

---

## 3. Proper Alignment Handling & Safety

### 3.1 Mathematical Alignment Requirements
In Rust and modern CPU architectures (x86_64, ARM64):
- **Unaligned pointer access is Undefined Behavior (UB)** in Rust if dereferenced via standard references `&T` or `&mut T`.
- CPU hardware features (SIMD, AVX-512, SSE) execute instructions (e.g. `movaps`, `vmovaps`) that trigger hardware alignment faults / program crashes if memory is not 16-byte or 32-byte aligned.

| Type | Size (Bytes) | Minimum Alignment | Target Subsystem |
|---|---|---|---|
| `u8`, `i8`, `bool` | 1 | 1 | Byte buffers, FFI flags |
| `u16`, `i16` | 2 | 2 | Indices, half-floats |
| `u32`, `i32`, `f32` | 4 | 4 | ECS component IDs, floats |
| `u64`, `i64`, `f64`, `usize` | 8 | 8 | Pointers, timestamps |
| `glam::Vec4`, `f32x4` | 16 | 16 | SIMD Transforms, Quaternions |
| `glam::Mat4` | 64 | 16 or 64 | 4x4 Transformation Matrices |
| AVX-256 vectors (`__m256`) | 32 | 32 | Physics / Raycast batches |

### 3.2 Alignment Arithmetic & Padding Formulas
Given current address $P$ and required alignment $A$ (where $A$ is a power of 2: $A = 2^k$):

$$\text{Mask} = A - 1$$
$$\text{Padding} = (A - (P \ \& \ \text{Mask})) \ \& \ \text{Mask}$$
$$\text{Aligned Address} = P + \text{Padding} = (P + A - 1) \ \& \ \sim\text{Mask}$$

In Rust:
```rust
#[inline(always)]
pub fn align_up(addr: usize, align: usize) -> usize {
    debug_assert!(align.is_power_of_two());
    (addr + align - 1) & !(align - 1)
}

#[inline(always)]
pub fn padding_needed(addr: usize, align: usize) -> usize {
    let remainder = addr & (align - 1);
    if remainder == 0 {
        0
    } else {
        align - remainder
    }
}
```

### 3.3 Zero-Sized Types (ZSTs)
Types like `()` or `PhantomData<T>` have `size == 0`.
- Handling: When `layout.size() == 0`, return a dangling, well-aligned pointer (`NonNull::dangling()`) without advancing the arena offset.

---

## 4. Safety, Concurrency & Threading Model

### 4.1 Single-Threaded vs. Multi-Threaded Allocator Patterns

Game engines employ one of three threading models for memory allocators:

| Pattern | Mechanism | Pros | Cons | Recommendation |
|---|---|---|---|---|
| **Thread-Local Arenas** | Each worker thread has its own `ArenaAllocator` (`thread_local!`) | Zero synchronization, zero contention, optimal cache locality | Cannot share references directly across threads without transfer | **Best for ECS/worker threads** |
| **Atomic Bump Allocator** | `offset: AtomicUsize` with `compare_exchange_weak` | Lock-free, `Send + Sync`, shared across threads | Reset requires thread quiescence / barriers | **Best for shared frame arena** |
| **Mutex / RwLock Protected** | `parking_lot::Mutex<ArenaAllocator>` | Simple, safe interior mutability | Lock overhead under contention | **Acceptable for FFI bridge initialization** |

### 4.2 Thread-Safe Atomic Bump Allocator Architecture
For `fluorite_core`, providing an atomic bump allocator allows concurrent allocations from both Rust worker tasks and Dart FFI calls:

```rust
use std::sync::atomic::{AtomicUsize, Ordering};

pub struct AtomicArenaAllocator {
    buffer: NonNull<u8>,
    capacity: usize,
    offset: AtomicUsize,
}

unsafe impl Send for AtomicArenaAllocator {}
unsafe impl Sync for AtomicArenaAllocator {}

impl AtomicArenaAllocator {
    pub fn alloc_raw(&self, layout: Layout) -> Result<NonNull<u8>, AllocError> {
        let size = layout.size();
        let align = layout.align();
        let base_addr = self.buffer.as_ptr() as usize;

        let mut current_offset = self.offset.load(Ordering::Relaxed);
        loop {
            let current_addr = base_addr + current_offset;
            let padding = (align - (current_addr & (align - 1))) & (align - 1);
            let next_offset = current_offset.checked_add(padding)
                .and_then(|val| val.checked_add(size))
                .ok_or(AllocError::OutOfMemory)?;

            if next_offset > self.capacity {
                return Err(AllocError::OutOfMemory);
            }

            match self.offset.compare_exchange_weak(
                current_offset,
                next_offset,
                Ordering::AcqRel,
                Ordering::Relaxed,
            ) {
                Ok(_) => {
                    let aligned_ptr = (current_addr + padding) as *mut u8;
                    return NonNull::new(aligned_ptr).ok_or(AllocError::OutOfMemory);
                }
                Err(actual) => current_offset = actual,
            }
        }
    }

    /// Resetting requires exclusive access (&mut self) or an external sync barrier
    pub fn reset(&mut self) {
        self.offset.store(0, Ordering::Release);
    }
}
```

### 4.3 Lifetime & Borrow Checker Safety
When an arena hands out `&'a mut T`:
- If lifetime `'a` is tied to `&'a ArenaAllocator`, the Rust compiler prevents `arena.reset()` from compiling while any allocated references are still in scope.
- In FFI contexts (where memory is passed to Dart via pointers or raw buffers), Rust lifetime tracking cannot cross the FFI boundary. Therefore:
  - FFI functions expose explicit `BufferHandle` or continuous byte slices with clear ownership semantics.
  - The frame allocator manages buffer lifecycle via frame counters.

---

## 5. Crate Layout & Cargo Configuration for `fluorite_core`

### 5.1 Directory Structure
```
c:\Users\blue-\projects\Fluorescent\fluorite_core\
├── Cargo.toml
├── build.rs                          (optional for FFI codegen)
├── src/
│   ├── lib.rs                        (Crate root, public API, FFI exports)
│   ├── allocator/
│   │   ├── mod.rs                    (Allocator module exports)
│   │   ├── arena.rs                  (ArenaAllocator implementation)
│   │   ├── frame.rs                  (DoubleBufferedFrameAllocator)
│   │   └── atomic.rs                 (AtomicArenaAllocator)
│   └── ffi/
│       ├── mod.rs                    (FFI bridge module)
│       └── bridge.rs                 (Entrypoints for flutter_rust_bridge / Dart)
└── tests/
    ├── arena_test.rs                 (Integration test suite for ArenaAllocator)
    └── frame_allocator_test.rs       (Integration test suite for FrameAllocator)
```

### 5.2 Complete `Cargo.toml` Blueprint
```toml
[package]
name = "fluorite_core"
version = "0.1.0"
edition = "2021"
authors = ["Fluorite Engine Contributors"]
description = "Core high-performance foundation and custom memory allocators for Fluorite AAA Engine"

[lib]
name = "fluorite_core"
# cdylib produces fluorite_core.dll for Flutter FFI; rlib allows cargo test & rust integration
crate-type = ["cdylib", "rlib"]

[dependencies]
# Error handling without heavy dependencies
thiserror = "1.0"

# High-performance synchronization primitives
parking_lot = { version = "0.12", optional = true }

# Future Phase 1 R2 integration
# flutter_rust_bridge = "=2.0.0" # or compatible version

[dev-dependencies]
# For benchmarking and concurrency stress tests
criterion = "0.5"

[features]
default = ["std"]
std = []
sync = ["dep:parking_lot"]

[profile.dev]
opt-level = 0
debug = true

[profile.release]
opt-level = 3
lto = "thin"
codegen-units = 1
panic = "unwind"
```

---

## 6. Rigorous Test Strategy for `cargo test`

The test suite must verify mathematical correctness, memory alignment, overflow resilience, and frame reset invariants.

### 6.1 Test Suite Inventory

| Test Identifier | Category | Invariant Under Test | Pass Criteria |
|---|---|---|---|
| `test_arena_basic_alloc_and_write` | Correctness | Allocate primitive types (`u32`, `u64`, `f32`), write patterns, read back | Exact value equality, no memory corruption |
| `test_arena_alignment_guarantee` | Alignment | Interleave allocations with alignments 1, 2, 4, 8, 16, 32, 64 bytes | `(ptr as usize) % alignment == 0` for all allocations |
| `test_arena_simd_alignment` | SIMD / AVX | Allocate 16-byte (`glam::Vec4` equivalent) and 32-byte structures | Pointers aligned to 16/32 byte boundaries; no SSE fault |
| `test_arena_capacity_overflow` | Safety | Request allocation exceeding capacity | Returns `Err(AllocError::OutOfMemory)`; original buffer intact |
| `test_arena_reset_semantics` | Lifetime / Reset | Fill arena, reset, reallocate full capacity | New pointers match buffer base; write/read succeeds |
| `test_frame_allocator_double_buffering` | Game Loop | Simulate 100 frames with alternating allocations | Frame $N-1$ data survives until next frame switch; resets work |
| `test_1mb_buffer_allocation` | Acceptance Criteria | Allocate contiguous 1,048,576 byte slice and read/write | Valid contiguous memory block matching AC 3 |
| `test_atomic_arena_concurrency` | Thread Safety | 8 threads concurrently allocating 1,000 blocks each | Zero overlapping address intervals across all threads |

### 6.2 Example Concrete Test Cases (for Worker Implementation)

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_arena_alignment_ladder() {
        let mut arena = ArenaAllocator::new(1024 * 1024).expect("Failed to create arena");
        let alignments = [1, 2, 4, 8, 16, 32, 64];

        for &align in &alignments {
            let layout = Layout::from_size_align(17, align).unwrap();
            let ptr = arena.alloc_raw(layout).expect("Allocation failed");
            assert_eq!(
                ptr.as_ptr() as usize % align,
                0,
                "Pointer {:?} failed to satisfy alignment {}",
                ptr,
                align
            );
        }
    }

    #[test]
    fn test_1mb_buffer_allocation_for_ffi() {
        let mut arena = ArenaAllocator::new(2 * 1024 * 1024).expect("Failed to create arena");
        let one_mb = 1024 * 1024;
        let slice = arena.alloc_slice(one_mb, 0xABu8).expect("1MB allocation failed");
        
        assert_eq!(slice.len(), one_mb);
        assert_eq!(slice[0], 0xAB);
        assert_eq!(slice[one_mb - 1], 0xAB);
        
        // Mutate edges and middle
        slice[0] = 0x12;
        slice[500_000] = 0x34;
        slice[one_mb - 1] = 0x56;

        assert_eq!(slice[0], 0x12);
        assert_eq!(slice[500_000], 0x34);
        assert_eq!(slice[one_mb - 1], 0x56);
    }

    #[test]
    fn test_arena_reset_and_reuse() {
        let mut arena = ArenaAllocator::new(256).expect("Failed to create arena");
        let layout = Layout::from_size_align(128, 8).unwrap();
        
        let p1 = arena.alloc_raw(layout).unwrap();
        let p2 = arena.alloc_raw(layout).unwrap();
        assert!(arena.alloc_raw(layout).is_err()); // Full

        arena.reset();
        assert_eq!(arena.allocated_bytes(), 0);

        // Can allocate again
        let p3 = arena.alloc_raw(layout).unwrap();
        assert_eq!(p1.as_ptr(), p3.as_ptr(), "Reset must reset base pointer offset");
    }
}
```

---

## 7. Zero-Copy FFI Readiness & Bridge Integration Interface

For seamless integration with Phase 1 Requirement 2 (flutter_rust_bridge) and Requirement 3 (Flutter Editor):
1. **Raw Buffer Pointer Export:**
   - Expose C-ABI functions to allocate a managed buffer, return its pointer, length, and capacity.
2. **Buffer Lifecycle Contract:**
   - Dart receives a pointer to the buffer (`Uint8List.view` in Dart via `dart:ffi`), accessing the Rust-allocated memory without any copy or serialization.
   - Status query function: `fluorite_get_allocator_status() -> AllocatorStatus` reporting allocated bytes, capacity, and peak usage.

---

## 8. Summary of Actionable Implementation Directives for Workers

1. **Workspace Location:**
   Create `fluorite_core` in `c:\Users\blue-\projects\Fluorescent\fluorite_core` to respect the active workspace sandbox.
2. **Crate Config:**
   Use `crate-type = ["cdylib", "rlib"]` in `Cargo.toml`.
3. **Core Types to Implement:**
   - `AllocError`
   - `ArenaAllocator`
   - `DoubleBufferedFrameAllocator`
   - `AtomicArenaAllocator` (optional/sync feature)
4. **Testing Suite:**
   Deliver integration tests in `fluorite_core/tests/` verifying alignment, 1MB allocation, capacity overflow, and reset semantics.
