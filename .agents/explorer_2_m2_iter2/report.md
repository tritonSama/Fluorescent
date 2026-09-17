# Technical Investigation & Fix Strategy Report: Rust Core FFI Exports

**Agent**: `explorer_2_m2_iter2` (teamwork_preview_explorer)  
**Date**: 2026-09-17  
**Target Milestone**: Milestone 2 (Zero-Copy FFI Bridge via `flutter_rust_bridge` v2)  
**Files Investigated**:
- `fluorite_core/src/api/engine.rs`
- `fluorite_core/src/frb_generated.rs`
- `fluorite_core/src/allocator/arena.rs`
- `fluorite_core/src/allocator/frame.rs`
- `fluorite_core/src/allocator/mod.rs`
- `fluorite_core/tests/` (`engine_api_test.rs`, `adversarial_challenge_test.rs`, `codegen_test.rs`, `arena_test.rs`)
- `fluorite_editor/lib/src/rust/` (`frb_generated.dart`, `frb_generated.io.dart`, `api/engine.dart`)
- `tests/` (`tier2_boundary_corner_test.dart`, `fluorite_bridge_model.dart`, `e2e_runner.dart`)

---

## 1. Executive Summary

During Milestone 2 Iteration 1, Gate 1 failed due to multiple critical architectural defects identified by Reviewer 1, Reviewer 2, and Challenger 1. Specifically:
1. **Double Allocation**: `allocate_engine_buffer` allocated memory in the custom `ArenaAllocator`, discarded the slice with `let _ = ...`, and then allocated a second independent `vec![0u8; size_bytes]` from the system OS heap. This consumed 2x the requested RAM and decoupled the returned buffer from the custom allocator.
2. **Native Memory Leak**: `wire__crate__api__engine__allocate_engine_buffer` called `std::mem::forget(buf)` to pass raw heap memory across the C-ABI. Dart wrapped the pointer with `Pointer.asTypedList` without registering any `NativeFinalizer` or `Finalizer`, permanently leaking 1MB per allocation.
3. **Cross-Language Contract Divergence**: `verify_buffer_sentinels` in Rust rejected any buffer smaller than 1MB (`< ONE_MB`), whereas Dart accepted any non-empty buffer, causing cross-language test and assertion failures for sub-1MB buffers.
4. **1-Byte Sentinel Clobbering**: In 1-byte buffer allocations, `buffer[0] = 0xAA; buffer[size - 1] = 0x55;` evaluated to `buffer[0] = 0x55`, destroying the header sentinel.
5. **C-ABI Safety Deficiencies**: `SharedFrameBuffer` lacked bounds checking on `read_byte` and `write_byte` (triggering fatal panics), wire functions lacked `std::panic::catch_unwind` protection, and `EngineStatus` had an unstable `#[repr(Rust)]` layout containing Rust `String` heap handles that cannot be directly decoded across FFI.

This report provides the exhaustive technical analysis and exact code fix blueprints to resolve all five defects cleanly, robustly, and safely.

---

## 2. Defect 1: Double-Allocation Defect in `allocate_engine_buffer`

### 2.1 Direct Observation & Root Cause
In `fluorite_core/src/api/engine.rs` (lines 69–93):
```rust
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
```

**Root Cause**:
The prompt for Milestone 2 instructed the worker to:
> *"Implement `allocate_engine_buffer(size_bytes: usize) -> Vec<u8>`: Uses the custom ArenaAllocator to allocate continuous memory, sets 0xAA sentinel at index 0 and 0x55 sentinel at index size_bytes - 1, and returns Vec<u8>"*

In standard Rust (stable 2021 edition), `Vec<T>` is strictly tied to `std::alloc::Global`. Calling `Vec::from_raw_parts` on an interior pointer of an `ArenaAllocator` backing buffer is undefined behavior: when `Vec` is dropped, it passes the interior bump pointer to `std::alloc::dealloc`, immediately triggering a heap corruption crash (`STATUS_HEAP_CORRUPTION` or `free(): invalid pointer`).

Faced with this compiler/allocator constraint, `worker_m2` performed a "phantom" allocation in the arena (`let _ = arena.alloc_slice(...)`) solely to increment `alloc.allocated_bytes()` for telemetry, and then allocated a separate `vec![0u8; size_bytes]` from the OS global heap.

**Consequences**:
1. Every 1MB buffer requested allocated **2MB** of memory (1MB in the arena + 1MB on the OS heap).
2. The memory returned to the caller was the OS heap buffer, completely uncoupled from `ArenaAllocator`.
3. When the arena capacity (16MB) was exceeded, `arena.alloc_slice` returned `Err(AllocError::OutOfMemory)`, but `let _ = ...` silently swallowed the error, while `vec![0u8; size_bytes]` continued allocating, creating desynchronized telemetry.

---

### 2.2 Unification Architecture: Two Clean Options

To eliminate the double-allocation defect, we must align the memory source with the architectural purpose:

#### Option A: True Arena Allocation for Zero-Copy FFI Buffers (Recommended for Engine Frame Buffers)
In this design, memory is allocated **exclusively** from the active arena of `DoubleBufferedFrameAllocator`:
1. `allocate_engine_buffer_slice` (or `wire__crate__api__engine__allocate_engine_buffer`) allocates `&mut [u8]` from `DoubleBufferedFrameAllocator::current_arena().alloc_slice(size_bytes, 0u8)`.
2. Sentinels `0xAA` and `0x55` are stamped directly into the arena slice.
3. The raw pointer `slice.as_mut_ptr()` is returned across the C-ABI to Dart.
4. Dart wraps `rawPtr.asTypedList(sizeBytes)` as a true zero-copy view of the arena.
5. **No OS heap vector is ever created.** Exactly `size_bytes` is allocated, exclusively in the arena.

```rust
// Proposed Rust C-ABI implementation in frb_generated.rs / engine.rs:
#[no_mangle]
pub extern "C" fn wire__crate__api__engine__allocate_engine_buffer(
    size_bytes: usize,
) -> *mut u8 {
    if size_bytes == 0 {
        return std::ptr::null_mut();
    }
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut guard = match ENGINE_ALLOCATOR.write() {
            Ok(g) => g,
            Err(poisoned) => poisoned.into_inner(),
        };

        if guard.is_none() {
            let allocator = DoubleBufferedFrameAllocator::new(DEFAULT_ENGINE_FRAME_CAPACITY)
                .expect("Failed to initialize engine frame allocator");
            *guard = Some(allocator);
        }

        if let Some(alloc) = guard.as_mut() {
            match alloc.current_arena().alloc_slice(size_bytes, 0u8) {
                Ok(slice) => {
                    slice[0] = SENTINEL_HEADER;
                    if size_bytes > 1 {
                        slice[size_bytes - 1] = SENTINEL_FOOTER;
                    }
                    slice.as_mut_ptr()
                }
                Err(_) => std::ptr::null_mut(),
            }
        } else {
            std::ptr::null_mut()
        }
    }))
    .unwrap_or(std::ptr::null_mut())
}
```

#### Option B: Unified Single-Vector Allocation for Transferable Snapshots
If `allocate_engine_buffer(size_bytes: usize) -> Vec<u8>` is retained as a standalone Rust API returning owned `Vec<u8>` to satisfy Rust-side caller contracts:
1. **Remove the phantom arena allocation completely**: Remove lines 70–85 (`let _ = arena.alloc_slice(...)`).
2. Allocate `vec![0u8; size_bytes]` once.
3. Stamp sentinels on `buffer`.
4. Return `buffer`.
5. This eliminates the duplicate 1MB arena allocation.

#### Comparative Analysis & Recommendation
| Metric | Option A (True Arena Zero-Copy) | Option B (Single OS Heap Vec) |
|---|---|---|
| Memory Sources | 1 (Arena) | 1 (OS Global Heap) |
| Duplicate Allocation | 0 bytes | 0 bytes |
| Zero-Copy to Dart | Yes (`Pointer.asTypedList` directly over arena memory) | Yes (`Pointer.asTypedList` over leaked heap Vec) |
| Alignment Guarantee | 64-byte hardware cache line | Default OS alignment (typically 8 or 16 bytes) |
| Deallocation Mechanism | Bulk $O(1)$ reset / frame swap | Individual `free_engine_buffer` via finalizer |
| Telemetry Match | Exact match with `allocated_bytes()` | Requires manual telemetry accounting |

**Recommendation**:
- For the C-ABI wire function `wire__crate__api__engine__allocate_engine_buffer`: Adopt **Option A**. Memory is allocated directly from the engine's active `ArenaAllocator`, stamped in-place, and exposed as a raw pointer.
- For `pub fn allocate_engine_buffer(size_bytes: usize) -> Vec<u8>`: In native Rust, allocate the slice from the arena and return `slice.to_vec()` only if an owned `Vec` is requested, OR return a dedicated single heap vector without phantom arena allocation. If returning `Vec<u8>`, remove `let _ = arena.alloc_slice(size_bytes, 0u8)` so that phantom memory consumption is 0.

---

## 3. Defect 2: Native Memory Leak in `wire__crate__api__engine__allocate_engine_buffer`

### 3.1 Direct Observation
In `fluorite_core/src/frb_generated.rs` (lines 57–64):
```rust
#[no_mangle]
pub extern "C" fn wire__crate__api__engine__allocate_engine_buffer(
    size_bytes: usize,
) -> *mut u8 {
    let mut buf = allocate_engine_buffer(size_bytes);
    let ptr = buf.as_mut_ptr();
    std::mem::forget(buf);
    ptr
}
```
And in `fluorite_editor/lib/src/rust/frb_generated.dart` (lines 133–139):
```dart
    final platform = _lib.platform;
    if (platform != null && platform.hasNativeBindings) {
      final rawPtr = platform.allocateBufferRaw(sizeBytes);
      if (rawPtr != null && rawPtr != ffi.nullptr) {
        // Zero-copy view using Dart VM's Pointer.asTypedList
        return rawPtr.asTypedList(sizeBytes);
      }
    }
```

### 3.2 Root Cause Analysis
1. In Rust, `std::mem::forget(buf)` prevents the Rust drop checker from deallocating the memory when `buf` exits scope.
2. In Dart, `rawPtr.asTypedList(sizeBytes)` creates an `_ExternalUint8Array` or `_TypedListView` that references the native memory address `rawPtr`.
3. When the Dart `Uint8List` becomes unreachable, Dart's garbage collector collects the Dart object header, but **does not touch the native memory block**.
4. In `frb_generated.io.dart`, `_WireFreeBufferDart? _freeEngineBuffer` was loaded, and `freeBufferRaw` was declared:
   ```dart
   void freeBufferRaw(ffi.Pointer<ffi.Uint8> ptr, int sizeBytes) {
     _freeEngineBuffer?.call(ptr, sizeBytes);
   }
   ```
   However, `freeBufferRaw` was **never invoked anywhere in the codebase**.
5. No `NativeFinalizer` or `Finalizer` was registered.
6. Every invocation of `allocateEngineBuffer(1048576)` permanently leaked 1MB of physical RAM.

---

### 3.3 Deallocation Architecture across C-ABI

To structure memory deallocation properly across the C-ABI, we must address both heap-allocated and arena-allocated models.

#### Structure 1: Dart-Side Finalization via `dart:core` `Finalizer`
Because `wire__crate__api__engine__free_engine_buffer(ptr: *mut u8, size_bytes: usize)` requires both `ptr` and `size_bytes`, Dart's `dart:core` `Finalizer` is the ideal mechanism because its token can hold multiple fields:

```dart
/// Token containing native address and allocation size for deallocation.
class _EngineBufferFinalizerToken {
  final ffi.Pointer<ffi.Uint8> pointer;
  final int sizeBytes;
  final RustLibPlatform platform;

  _EngineBufferFinalizerToken(this.pointer, this.sizeBytes, this.platform);

  void free() {
    if (pointer != ffi.nullptr) {
      platform.freeBufferRaw(pointer, sizeBytes);
    }
  }
}

/// Finalizer attached to external typed data views to prevent native memory leaks.
final Finalizer<_EngineBufferFinalizerToken> _bufferFinalizer =
    Finalizer<_EngineBufferFinalizerToken>((token) => token.free());
```

In `frb_generated.dart`:
```dart
Uint8List crateApiEngineAllocateEngineBuffer({required int sizeBytes}) {
  if (sizeBytes == 0) return Uint8List(0);

  final platform = _lib.platform;
  if (platform != null && platform.hasNativeBindings) {
    final rawPtr = platform.allocateBufferRaw(sizeBytes);
    if (rawPtr != null && rawPtr != ffi.nullptr) {
      final typedList = rawPtr.asTypedList(sizeBytes);
      // Attach finalizer to trigger freeBufferRaw when typedList is garbage collected
      _bufferFinalizer.attach(
        typedList,
        _EngineBufferFinalizerToken(rawPtr, sizeBytes, platform),
      );
      return typedList;
    }
  }

  // Fallback managed allocation
  final buffer = Uint8List(sizeBytes);
  buffer[0] = 0xAA;
  if (sizeBytes > 1) {
    buffer[sizeBytes - 1] = 0x55;
  }
  return buffer;
}
```

#### Structure 2: Struct-Based Handle for `dart:ffi` `NativeFinalizer`
If a direct `NativeFinalizer` is required (which invokes a native C function directly without returning to Dart bytecode):
In `dart:ffi`, `NativeFinalizer` requires a C callback of type `void (*)(void* token)`.
We can wrap the allocation in a native handle:
```rust
#[repr(C)]
pub struct EngineBufferHandle {
    pub ptr: *mut u8,
    pub size: usize,
    pub is_arena: bool,
}

#[no_mangle]
pub extern "C" fn wire__crate__api__engine__free_engine_buffer_handle(
    handle: *mut EngineBufferHandle,
) {
    if !handle.is_null() {
        unsafe {
            let h = Box::from_raw(handle);
            if !h.is_arena && !h.ptr.is_null() && h.size > 0 {
                let _ = Vec::from_raw_parts(h.ptr, h.size, h.size);
            }
        }
    }
}
```

#### Structure 3: Dual-Mode Rust Deallocator
In `fluorite_core/src/frb_generated.rs`:
The free function must safely distinguish arena pointers from heap pointers:
```rust
#[no_mangle]
pub extern "C" fn wire__crate__api__engine__free_engine_buffer(
    ptr: *mut u8,
    size_bytes: usize,
) {
    if ptr.is_null() || size_bytes == 0 {
        return;
    }

    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        // Check if ptr is inside the active arena backing buffer
        let is_in_arena = {
            let guard = ENGINE_ALLOCATOR.read().unwrap_or_else(|p| p.into_inner());
            if let Some(alloc) = guard.as_ref() {
                let arena = alloc.current_arena();
                let base = arena.buffer_base_ptr() as usize;
                let cap = arena.capacity_bytes();
                let addr = ptr as usize;
                addr >= base && addr < (base + cap)
            } else {
                false
            }
        };

        if is_in_arena {
            // Arena memory is managed by DoubleBufferedFrameAllocator;
            // bulk reset / swap_buffers reclaims it. No individual heap dealloc.
        } else {
            // Heap-allocated buffer: reclaim via Vec::from_raw_parts
            unsafe {
                let _ = Vec::from_raw_parts(ptr, size_bytes, size_bytes);
            }
        }
    }))
    .ok();
}
```
This guarantees that calling `free_engine_buffer` will **never** corrupt the heap if an arena pointer is passed, while properly reclaiming heap-allocated buffers.

---

## 4. Defect 3: Cross-Language Contract Divergence in `verify_buffer_sentinels`

### 4.1 Direct Observation
In `fluorite_core/src/allocator/arena.rs` (lines 240–245):
```rust
pub fn verify_buffer_sentinels(buffer: &[u8]) -> bool {
    if buffer.len() < ONE_MB {
        return false;
    }
    buffer[0] == SENTINEL_HEADER && buffer[buffer.len() - 1] == SENTINEL_FOOTER
}
```
In `fluorite_editor/lib/src/rust/frb_generated.dart` (lines 172–175):
```dart
bool crateApiEngineVerifyBufferSentinels({required List<int> buffer}) {
  if (buffer.isEmpty) return false;
  return buffer[0] == 0xAA && buffer[buffer.length - 1] == 0x55;
}
```
In `tests/fluorite_bridge_model.dart` (lines 273–278):
```dart
bool verifyBufferSentinels(Uint8List buffer) {
  if (buffer.isEmpty) return false;
  if (buffer[0] != 0xAA) return false;
  if (buffer[buffer.length - 1] != 0x55) return false;
  return true;
}
```
In `tests/tier2_boundary_corner_test.dart` (lines 109–119 and 166–180):
```dart
    TestHarness.test('test_t2_f2_power_of_two_sizes', () {
      // Test powers of 2 from 2^1 (2) to 2^20 (1,048,576)
      for (int p = 1; p <= 20; p++) {
        final size = 1 << p;
        final buf = allocateEngineBuffer(size);
        expect(buf.length, equals(size));
        expect(buf[0], equals(0xAA));
        expect(buf[size - 1], equals(0x55));
        expect(verifyBufferSentinels(buf), isTrue);
      }
    });

    TestHarness.test('test_t2_f3_corrupted_sentinel_rejection', () {
      final buf = allocateEngineBuffer(1024);
      expect(verifyBufferSentinels(buf), isTrue);
      ...
    });
```

### 4.2 Impact Analysis
1. For any buffer where $2 \le \text{size} < 1\,048\,576$ (e.g. 2 bytes, 1024 bytes, 64KB, 512KB):
   - Dart returns `true`.
   - Rust native returns `false`.
2. The Dart tests in `tests/tier2_boundary_corner_test.dart` explicitly test powers of two from $2^1$ to $2^{20}$ and 1024-byte buffers, expecting `verifyBufferSentinels(buf) == true`.
3. If genuine native C-ABI dispatch is enabled, 19 out of 20 iterations in `test_t2_f2_power_of_two_sizes` fail immediately.

### 4.3 Invalidation Proof for the `< ONE_MB` Rust Condition
Why did the M1 code contain `if buffer.len() < ONE_MB { return false; }`?
In `fluorite_core/tests/adversarial_challenge_test.rs` (lines 277–295):
```rust
    let arena = ArenaAllocator::new(2 * ONE_MB).unwrap();
    let buffer = arena.alloc_1mb_buffer().unwrap();
    ...
    // Truncated slice fails
    assert!(!verify_buffer_sentinels(&buffer[0..ONE_MB - 1]));
```
Let's analyze what bytes are in `&buffer[0..ONE_MB - 1]`:
- Length is `ONE_MB - 1` (1,048,575 bytes).
- Byte 0 is `SENTINEL_HEADER` (`0xAA`).
- Last byte is index `ONE_MB - 2` (`1,048,574`).
- What is at index `ONE_MB - 2` in `buffer`?
  `buffer` was initialized with `slice.fill(0u8)` and only index 0 (`0xAA`) and index `ONE_MB - 1` (`0x55`) were set.
  Therefore, `buffer[ONE_MB - 2] == 0x00`!
- When checking footer sentinel on `&buffer[0..ONE_MB - 1]`:
  `slice[last_index] == 0x00 != SENTINEL_FOOTER (0x55)`.
- Therefore, **even without the `< ONE_MB` check**, `verify_buffer_sentinels(&buffer[0..ONE_MB - 1])` evaluates to `false` because the last byte is `0x00`, NOT `0x55`!
- The check `if buffer.len() < ONE_MB` was completely redundant and was an overly restrictive artifact that broke contract symmetry.

### 4.4 Recommended Harmonized Contract
In both Rust and Dart:
A buffer has valid sentinels if and only if:
1. `buffer.len() >= 2` (at least two distinct bytes for header and footer).
2. `buffer[0] == SENTINEL_HEADER (0xAA)`.
3. `buffer[buffer.len() - 1] == SENTINEL_FOOTER (0x55)`.

**Rust (`arena.rs` & `engine.rs`)**:
```rust
pub fn verify_buffer_sentinels(buffer: &[u8]) -> bool {
    if buffer.len() < 2 {
        return false;
    }
    buffer[0] == SENTINEL_HEADER && buffer[buffer.len() - 1] == SENTINEL_FOOTER
}
```

**Dart (`api/engine.dart` & `frb_generated.dart`)**:
```dart
bool crateApiEngineVerifyBufferSentinels({required List<int> buffer}) {
  if (buffer.length < 2) return false;
  return buffer[0] == 0xAA && buffer[buffer.length - 1] == 0x55;
}
```
This guarantees 100% symmetric behavior across all buffer sizes ($N=0, 1, 2, \dots, 1048576, \dots$).

---

## 5. Defect 4: 1-Byte Buffer Sentinel Clobbering Bug

### 5.1 Direct Observation
In `fluorite_core/src/api/engine.rs` (lines 88–92):
```rust
    if size_bytes > 0 {
        buffer[0] = SENTINEL_HEADER;
        buffer[size_bytes - 1] = SENTINEL_FOOTER;
    }
```
And in `fluorite_editor/lib/src/rust/frb_generated.dart` (lines 142–144):
```dart
    final buffer = Uint8List(sizeBytes);
    buffer[0] = 0xAA;
    buffer[sizeBytes - 1] = 0x55;
```

### 5.2 Mechanics of the Clobber
When `size_bytes == 1`:
1. `buffer[0] = 0xAA` (writes header sentinel to index 0).
2. `size_bytes - 1 == 0`.
3. `buffer[0] = 0x55` (immediately overwrites index 0 with footer sentinel).
4. The header sentinel `0xAA` is destroyed, leaving the buffer containing only `[0x55]`.

### 5.3 Exact Guard Fix
Guard footer stamping with `size_bytes > 1`:
```rust
if size_bytes > 0 {
    buffer[0] = SENTINEL_HEADER;
    if size_bytes > 1 {
        buffer[size_bytes - 1] = SENTINEL_FOOTER;
    }
}
```
And in Dart:
```dart
if (sizeBytes > 0) {
  buffer[0] = 0xAA;
  if (sizeBytes > 1) {
    buffer[sizeBytes - 1] = 0x55;
  }
}
```
**Verification**:
- For $N = 0$: No writes, buffer is empty.
- For $N = 1$: `buffer[0] = 0xAA`. No clobbering occurs.
- For $N \ge 2$: `buffer[0] = 0xAA` and `buffer[N - 1] = 0x55`. Distinct header and footer preserved.

---

## 6. Defect 5: C-ABI Safety & Robustness

### 6.1 Bounds Checking on `SharedFrameBuffer`
In `fluorite_core/src/api/engine.rs` (lines 177–186):
```rust
    #[flutter_rust_bridge::frb(sync)]
    pub fn read_byte(&self, offset: usize) -> u8 {
        self.data[offset]
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn write_byte(&mut self, offset: usize, value: u8) {
        self.data[offset] = value;
    }
```
If a caller supplies `offset >= len`, direct indexing triggers a Rust panic. When invoked across `extern "C" fn wire__crate__api__engine__shared_frame_buffer_read_byte`, panicking across the FFI boundary causes an immediate, unrecoverable hardware abort.

**Fix Blueprint**:
```rust
    pub fn read_byte(&self, offset: usize) -> u8 {
        self.data.get(offset).copied().unwrap_or(0)
    }

    pub fn write_byte(&mut self, offset: usize, value: u8) {
        if offset < self.data.len() {
            self.data[offset] = value;
        }
    }
```
In wire exports (`frb_generated.rs`):
```rust
#[no_mangle]
pub extern "C" fn wire__crate__api__engine__shared_frame_buffer_read_byte(
    ptr: *const SharedFrameBuffer,
    offset: usize,
) -> u8 {
    if ptr.is_null() {
        return 0;
    }
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
        (*ptr).read_byte(offset)
    }))
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn wire__crate__api__engine__shared_frame_buffer_write_byte(
    ptr: *mut SharedFrameBuffer,
    offset: usize,
    value: u8,
) {
    if ptr.is_null() {
        return;
    }
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
        (*ptr).write_byte(offset, value);
    }))
    .ok();
}
```

---

### 6.2 Panic Handling across `extern "C"` Wire Exports
Because `fluorite_core` sets `panic = "unwind"` in `Cargo.toml`, any unhandled panic across an `extern "C"` boundary will immediately crash the Flutter process.

**Fix Blueprint**:
Wrap the body of **all** C-ABI wire functions in `std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| { ... }))`.
- For pointer returns: return `std::ptr::null_mut()` on panic or error.
- For boolean returns: return `false` on panic.
- For integer returns: return `0` on panic.

Example for `start_engine_sync`:
```rust
#[no_mangle]
pub extern "C" fn wire__crate__api__engine__start_engine_sync() -> *mut EngineStatus {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let status = start_engine();
        Box::into_raw(Box::new(status))
    }))
    .unwrap_or(std::ptr::null_mut())
}
```

---

### 6.3 Struct Layout Stability for `EngineStatus`
In `fluorite_core/src/api/engine.rs`:
```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct EngineStatus {
    pub is_initialized: bool,
    pub total_memory_allocated: usize,
    pub arena_capacity: usize,
    pub frame_index: u64,
    pub status_message: String,
    pub core_version: String,
    pub allocator_name: String,
}
```
1. `EngineStatus` lacks `#[repr(C)]`. In default Rust `#[repr(Rust)]`, field ordering and padding are arbitrary and unpredictable.
2. `String` fields are Rust standard library structs (`ptr`, `cap`, `len`) allocated on the Rust heap, which Dart `dart:ffi` cannot parse directly without undefined behavior.

#### Recommended Strategy: C-ABI Wire Struct or JSON Bridge
Two viable strategies exist to bridge `EngineStatus`:

**Strategy 1: C-Compatible Wire Struct (`#[repr(C)]`)**:
Define a stable C struct for the wire:
```rust
use std::ffi::CString;
use std::os::raw::c_char;

#[repr(C)]
pub struct EngineStatusWire {
    pub is_initialized: bool,
    pub total_memory_allocated: usize,
    pub arena_capacity: usize,
    pub frame_index: u64,
    pub status_message: *mut c_char,
    pub core_version: *mut c_char,
    pub allocator_name: *mut c_char,
}

#[no_mangle]
pub extern "C" fn wire__crate__api__engine__start_engine_sync_c() -> *mut EngineStatusWire {
    let status = start_engine();
    let wire = Box::new(EngineStatusWire {
        is_initialized: status.is_initialized,
        total_memory_allocated: status.total_memory_allocated,
        arena_capacity: status.arena_capacity,
        frame_index: status.frame_index,
        status_message: CString::new(status.status_message).unwrap_or_default().into_raw(),
        core_version: CString::new(status.core_version).unwrap_or_default().into_raw(),
        allocator_name: CString::new(status.allocator_name).unwrap_or_default().into_raw(),
    });
    Box::into_raw(wire)
}

#[no_mangle]
pub extern "C" fn wire__crate__api__engine__free_engine_status_c(ptr: *mut EngineStatusWire) {
    if !ptr.is_null() {
        unsafe {
            let wire = Box::from_raw(ptr);
            if !wire.status_message.is_null() { let _ = CString::from_raw(wire.status_message); }
            if !wire.core_version.is_null() { let _ = CString::from_raw(wire.core_version); }
            if !wire.allocator_name.is_null() { let _ = CString::from_raw(wire.allocator_name); }
        }
    }
}
```
Matching Dart `ffi.Struct`:
```dart
final class EngineStatusWire extends ffi.Struct {
  @ffi.Bool()
  external bool isInitialized;
  @ffi.UintPtr()
  external int totalMemoryAllocated;
  @ffi.UintPtr()
  external int arenaCapacity;
  @ffi.Uint64()
  external int frameIndex;
  external ffi.Pointer<ffi.Char> statusMessage;
  external ffi.Pointer<ffi.Char> coreVersion;
  external ffi.Pointer<ffi.Char> allocatorName;
}
```

**Strategy 2: Primitive Field Wire Accessors (Zero Extra Allocation)**:
Expose stable C scalar accessors directly:
```rust
#[no_mangle]
pub extern "C" fn wire__engine_status_is_initialized(ptr: *const EngineStatus) -> bool {
    if ptr.is_null() { false } else { unsafe { (*ptr).is_initialized } }
}
#[no_mangle]
pub extern "C" fn wire__engine_status_total_allocated(ptr: *const EngineStatus) -> usize {
    if ptr.is_null() { 0 } else { unsafe { (*ptr).total_memory_allocated } }
}
#[no_mangle]
pub extern "C" fn wire__engine_status_arena_capacity(ptr: *const EngineStatus) -> usize {
    if ptr.is_null() { 0 } else { unsafe { (*ptr).arena_capacity } }
}
#[no_mangle]
pub extern "C" fn wire__engine_status_frame_index(ptr: *const EngineStatus) -> u64 {
    if ptr.is_null() { 0 } else { unsafe { (*ptr).frame_index } }
}
```

**Recommendation**: Adopt Strategy 1 (or individual primitive getters) so Dart can safely inspect live Rust telemetry without guessing struct memory layouts or crashing on Rust `String` pointers.

---

## 7. Concrete Patch Blueprint (Summary of Fix Proposals)

| File | Target Function / Symbol | Proposed Fix |
|---|---|---|
| `fluorite_core/src/api/engine.rs` | `allocate_engine_buffer` | Remove phantom arena allocation (`let _ = arena.alloc_slice`); unify memory allocation to single source; guard 1-byte sentinel stamping. |
| `fluorite_core/src/api/engine.rs` | `SharedFrameBuffer` | Add bounds checking to `read_byte` and `write_byte` (`get(offset).copied().unwrap_or(0)`). Back backing memory by arena if live frame buffer. |
| `fluorite_core/src/frb_generated.rs` | `wire__crate__api__engine__allocate_engine_buffer` | Allocate directly from `DoubleBufferedFrameAllocator` or clean heap vector; wrap in `std::panic::catch_unwind`. |
| `fluorite_core/src/frb_generated.rs` | `wire__crate__api__engine__free_engine_buffer` | Guard against crashing if an arena pointer is passed; wrap in `std::panic::catch_unwind`. |
| `fluorite_core/src/frb_generated.rs` | All wire functions | Wrap bodies in `std::panic::catch_unwind`. |
| `fluorite_core/src/allocator/arena.rs` | `verify_buffer_sentinels` | Remove `if buffer.len() < ONE_MB`; change to `if buffer.len() < 2 { return false; }`. |
| `fluorite_editor/lib/src/rust/frb_generated.dart` | `crateApiEngineAllocateEngineBuffer` | Attach `_bufferFinalizer` to returned `Uint8List` pointing to `freeBufferRaw`. |
| `fluorite_editor/lib/src/rust/frb_generated.dart` | `RustLibApi` methods | Remove facade simulation; dispatch to `_platform` functions when `hasNativeBindings` is true. |
| `fluorite_editor/lib/src/rust/frb_generated.dart` | `SharedFrameBuffer` | Remove synthetic `0x40000000` address; retrieve genuine pointer from native handle or allocate via FFI. |
| `fluorite_editor/lib/src/rust/frb_generated.dart` | `crateApiEngineVerifyBufferSentinels` | Standardize length check to `< 2`. |

---

## 8. Conclusion

All 5 defects identified during Gate 1 have been analyzed down to their root causes. The proposed technical fixes unify allocator memory usage, eliminate all double allocations and memory leaks, harmonize cross-language sentinel verification contracts, guard boundary corner cases, and establish rock-solid C-ABI safety.
