# Handoff Report: Technical Investigation & Fix Strategy for Rust Core FFI Exports

**Agent**: `explorer_2_m2_iter2` (teamwork_preview_explorer)  
**Recipient**: `orchestrator_phase1` (Conversation ID: `038adf4f-48f5-4380-b990-9184dd1cc1fe`)  
**Type**: Hard Handoff (Investigation Complete)  
**Target Files**: `fluorite_core/src/api/engine.rs`, `fluorite_core/src/frb_generated.rs`, `fluorite_core/src/allocator/arena.rs`, `fluorite_editor/lib/src/rust/`

---

## 1. Observation

### 1.1 Defect 1: Double Allocation in `allocate_engine_buffer`
In `fluorite_core/src/api/engine.rs` lines 81–93:
```rust
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
- Line 83 allocates `size_bytes` in `ArenaAllocator`, but immediately discards the returned slice with `let _ = ...`.
- Line 87 allocates an independent vector `vec![0u8; size_bytes]` from the OS global heap.
- The sentinels are stamped into the global heap vector, not the arena memory.
- If the arena reaches capacity, `arena.alloc_slice` returns `Err(AllocError::OutOfMemory)`, which is silently ignored by `let _ = ...`, while `vec![0u8; size_bytes]` succeeds, corrupting telemetry.
- Total memory consumed per 1MB allocation is 2MB (1MB arena + 1MB OS heap).

### 1.2 Defect 2: Native Memory Leak in `allocate_engine_buffer` Wire Export
In `fluorite_core/src/frb_generated.rs` lines 57–64:
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
In `fluorite_editor/lib/src/rust/frb_generated.dart` lines 133–139:
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
- Line 62 leaks the heap buffer via `std::mem::forget(buf)`.
- Line 137 in Dart converts `rawPtr` via `rawPtr.asTypedList(sizeBytes)`.
- Dart GC collects the `Uint8List` view, but never frees `rawPtr`.
- A grep search for `Finalizer` or `NativeFinalizer` across `fluorite_editor/lib/src/rust/` yielded 0 matches.
- `wire__crate__api__engine__free_engine_buffer` exists in Rust and is mapped in `frb_generated.io.dart`, but is never invoked anywhere in Dart.

### 1.3 Defect 3: Cross-Language Contract Divergence in `verify_buffer_sentinels`
In `fluorite_core/src/allocator/arena.rs` lines 240–245:
```rust
pub fn verify_buffer_sentinels(buffer: &[u8]) -> bool {
    if buffer.len() < ONE_MB {
        return false;
    }
    buffer[0] == SENTINEL_HEADER && buffer[buffer.len() - 1] == SENTINEL_FOOTER
}
```
In `fluorite_editor/lib/src/rust/frb_generated.dart` lines 172–175:
```dart
bool crateApiEngineVerifyBufferSentinels({required List<int> buffer}) {
  if (buffer.isEmpty) return false;
  return buffer[0] == 0xAA && buffer[buffer.length - 1] == 0x55;
}
```
In `tests/tier2_boundary_corner_test.dart` lines 111–118:
```dart
      for (int p = 1; p <= 20; p++) {
        final size = 1 << p;
        final buf = allocateEngineBuffer(size);
        expect(buf.length, equals(size));
        expect(buf[0], equals(0xAA));
        expect(buf[size - 1], equals(0x55));
        expect(verifyBufferSentinels(buf), isTrue);
      }
```
- Rust native rejects any buffer with `len < 1_048_576` (returning `false`).
- Dart accepts any non-empty buffer with matching ends (returning `true`).
- In `tier2_boundary_corner_test.dart`, sizes $2^1$ to $2^{19}$ (2 bytes to 512KB) fail in native Rust.

### 1.4 Defect 4: 1-Byte Buffer Sentinel Clobbering
In `fluorite_core/src/api/engine.rs` lines 88–91:
```rust
if size_bytes > 0 {
    buffer[0] = SENTINEL_HEADER;
    buffer[size_bytes - 1] = SENTINEL_FOOTER;
}
```
- When `size_bytes == 1`, `size_bytes - 1` equals 0.
- `buffer[0]` is written with `0xAA`, then immediately overwritten with `0x55`. The header sentinel is clobbered.

### 1.5 Defect 5: C-ABI Safety Deficiencies
In `fluorite_core/src/api/engine.rs` lines 177–186:
```rust
pub fn read_byte(&self, offset: usize) -> u8 { self.data[offset] }
pub fn write_byte(&mut self, offset: usize, value: u8) { self.data[offset] = value; }
```
- Missing bounds checks cause a panic if `offset >= self.data.len()`.
- Unhandled panics across `extern "C"` boundaries in `frb_generated.rs` cause immediate process aborts.
- `EngineStatus` lacks `#[repr(C)]` and contains Rust heap `String` fields, rendering its memory layout indeterminate for `dart:ffi`.

---

## 2. Logic Chain

1. **Double Allocation Inference**:
   - In `engine.rs:83`, `arena.alloc_slice(size_bytes, 0u8)` advances the arena offset by `size_bytes`.
   - In `engine.rs:87`, `vec![0u8; size_bytes]` allocates an additional `size_bytes` on the system heap.
   - The returned pointer in `frb_generated.rs:61` comes from `buf.as_mut_ptr()` (the heap vector).
   - Thus, 2MB is allocated per 1MB requested. Eliminating the unused arena slice or returning the arena pointer directly eliminates the redundant allocation.

2. **Native Memory Leak Inference**:
   - `std::mem::forget(buf)` transfers ownership of the heap memory to the caller across FFI.
   - Dart's `Pointer.asTypedList` wraps the raw pointer in an external TypedData view without registering a finalizer with the Dart VM GC.
   - Because `wire__crate__api__engine__free_engine_buffer` is never called, the heap allocation remains allocated until process termination.
   - Attaching Dart's `Finalizer` to the `Uint8List` view ensures that `freeBufferRaw` is called upon GC collection.

3. **Sentinel Contract Symmetry Inference**:
   - The condition `buffer.len() < ONE_MB` in `arena.rs:241` was introduced in M1 under the assumption of testing 1MB buffers.
   - In `adversarial_challenge_test.rs:294`, testing a truncated 1MB slice (`&buffer[0..ONE_MB - 1]`) fails because the last byte at index `ONE_MB - 2` is `0x00`, not `0x55`.
   - Thus, removing `< ONE_MB` and requiring only `len >= 2` maintains 100% pass on all M1 adversarial tests while allowing sub-1MB power-of-two tests in M2/M3 to pass across native FFI.

4. **1-Byte Clobber Guard Inference**:
   - Header sentinel belongs at index 0 (`size_bytes > 0`).
   - Footer sentinel belongs at index `size_bytes - 1` only when distinct from index 0 (`size_bytes > 1`).
   - Guarding footer stamping with `if size_bytes > 1` preserves `buffer[0] == 0xAA` for 1-byte buffers.

5. **C-ABI Robustness Inference**:
   - Replacing direct indexing with `.get(offset).copied().unwrap_or(0)` prevents out-of-bounds panics.
   - Wrapping `extern "C"` exports in `std::panic::catch_unwind` prevents cross-language stack unwinds and process aborts.
   - Using a defined `#[repr(C)]` struct for `EngineStatus` provides field offset stability for `dart:ffi`.

---

## 3. Caveats

1. **`flutter_rust_bridge_codegen` CLI Tooling**: In environments without `flutter_rust_bridge_codegen` in PATH, the C-ABI wire exports in `frb_generated.rs` and matching Dart bindings in `frb_generated.dart` and `frb_generated.io.dart` must maintain exact ABI compatibility (function signatures and struct layouts).
2. **Deterministic GC Timing**: Dart VM garbage collection is non-deterministic. While `Finalizer` prevents unbounded memory leaks over long sessions, performance-critical real-time loops (60 FPS) should also offer an explicit buffer release API (`freeBufferRaw` or `SharedFrameBuffer.dispose()`) for immediate reclamation.
3. **Arena vs Heap Lifetimes**: If buffers are allocated from `DoubleBufferedFrameAllocator`, memory is reclaimed on frame swap (`swap_buffers()`). Dart views over frame memory must not outlive the frame boundary unless copied.

---

## 4. Conclusion

The 5 defects from Gate 1 have verified, deterministic solutions:
1. **Unify Buffer Allocation**: In `allocate_engine_buffer`, eliminate the phantom `let _ = arena.alloc_slice` call when returning a heap vector, or return the arena slice pointer directly across C-ABI.
2. **Structure Deallocation across C-ABI**: Attach a `Finalizer<_EngineBufferFinalizerToken>` in Dart to invoke `freeBufferRaw` upon GC collection, and guard `wire__crate__api__engine__free_engine_buffer` against freeing arena memory.
3. **Harmonize Sentinel Contract**: Standardize `verify_buffer_sentinels` in both Rust and Dart to `len >= 2 && buffer[0] == 0xAA && buffer[len - 1] == 0x55`.
4. **Guard 1-Byte Sentinels**: Stamp footer sentinel only when `size_bytes > 1`.
5. **C-ABI Safety**: Add bounds checks to `SharedFrameBuffer`, wrap C-ABI exports in `std::panic::catch_unwind`, and stabilize `EngineStatus` with `#[repr(C)]`.

---

## 5. Verification Method

1. **Verify Double Allocation Fix**:
   - In `fluorite_core/src/api/engine.rs`: Confirm `let _ = arena.alloc_slice(...)` is removed when heap vectors are returned, or confirm that the returned pointer points directly to the arena memory.
2. **Verify Memory Deallocation & Finalizer**:
   - In `fluorite_editor/lib/src/rust/frb_generated.dart`: Search for `Finalizer` attached to the `Uint8List` created from `rawPtr.asTypedList(sizeBytes)`.
   - In `fluorite_core/src/frb_generated.rs`: Verify `wire__crate__api__engine__free_engine_buffer` safely handles deallocations.
3. **Verify Sentinel Contract Symmetry**:
   - Compare line 240 of `fluorite_core/src/allocator/arena.rs` with `frb_generated.dart`.
   - Confirm both verify `len >= 2` and matching endpoints without hardcoded `< ONE_MB`.
4. **Verify 1-Byte Sentinel Guard**:
   - Inspect `allocate_engine_buffer(1)` logic. Confirm `buffer[0] == 0xAA` and no footer write at index 0.
5. **Verify C-ABI Safety**:
   - Confirm `SharedFrameBuffer::read_byte` uses safe bounds checking.
   - Confirm wire functions in `frb_generated.rs` are protected with `std::panic::catch_unwind`.
