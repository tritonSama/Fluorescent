# Empirical Challenge Report: Milestone 2 — Zero-Copy FFI Bridge & Buffer Architecture

**Agent:** `challenger_1_m2_rep` (teamwork_preview_challenger)  
**Recipient:** `orchestrator_phase1` (Conversation ID: `038adf4f-48f5-4380-b990-9184dd1cc1fe`)  
**Timestamp:** 2026-09-17T20:07:30Z  
**Type:** Hard Handoff (Adversarial Challenge Complete)  
**Verdict:** **CHALLENGE** (Rejected with 4 verified failure modes)

---

## 1. Observation

Direct code review, grep search, and architectural analysis of `fluorite_core` and `fluorite_editor` revealed the following exact observations:

### 1.1 Custom Allocator Decoupling & Phantom Allocation in `allocate_engine_buffer`
In `fluorite_core/src/api/engine.rs` (lines 64–93):
```rust
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
```
- Line 83: `let _ = arena.alloc_slice(size_bytes, 0u8);` allocates memory from the arena and immediately discards the resulting slice.
- Line 87: `let mut buffer = vec![0u8; size_bytes];` allocates an entirely independent heap vector using the standard Rust OS allocator.
- Lines 89–90: Sentinels (0xAA / 0x55) are written exclusively to `buffer` (the OS heap vector).
- The memory returned to the caller is the OS heap `buffer`, NOT the memory from `ArenaAllocator`.
- If the arena is exhausted (e.g. after 16 calls of 1MB against a 16MB capacity), `arena.alloc_slice` returns `Err(AllocError::OutOfMemory)`. Because line 83 ignores the result with `let _ = ...`, the error is silently suppressed, and `vec![0u8; size_bytes]` succeeds, decoupling telemetry from actual allocations.

### 1.2 Unbounded Native Memory Leak via `std::mem::forget` and Missing Finalizer
In `fluorite_core/src/frb_generated.rs` (lines 57–77):
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

#[no_mangle]
pub extern "C" fn wire__crate__api__engine__free_engine_buffer(
    ptr: *mut u8,
    size_bytes: usize,
) {
    if !ptr.is_null() && size_bytes > 0 {
        unsafe {
            let _ = Vec::from_raw_parts(ptr, size_bytes, size_bytes);
        }
    }
}
```
In `fluorite_editor/lib/src/rust/frb_generated.dart` (lines 125–146):
```dart
  Uint8List crateApiEngineAllocateEngineBuffer({required int sizeBytes}) {
    if (sizeBytes == 0) {
      return Uint8List(0);
    }

    _totalAllocated += sizeBytes;

    final platform = _lib.platform;
    if (platform != null && platform.hasNativeBindings) {
      final rawPtr = platform.allocateBufferRaw(sizeBytes);
      if (rawPtr != null && rawPtr != ffi.nullptr) {
        // Zero-copy view using Dart VM's Pointer.asTypedList
        return rawPtr.asTypedList(sizeBytes);
      }
    }

    // Direct contiguous byte buffer allocation with sentinels
    final buffer = Uint8List(sizeBytes);
    buffer[0] = 0xAA;
    buffer[sizeBytes - 1] = 0x55;
    return buffer;
  }
```
- Line 62 of `frb_generated.rs`: Rust deliberately leaks the vector via `std::mem::forget(buf)`.
- Line 137 of `frb_generated.dart`: Dart converts `rawPtr` via `rawPtr.asTypedList(sizeBytes)`.
- In `dart:ffi`, `Pointer.asTypedList` creates a `Uint8List` view backed by native memory, but Dart's garbage collector **never deallocates the underlying pointer**.
- Search for `NativeFinalizer` or `Finalizer` across the entire codebase returned **0 results**.
- Although `wire__crate__api__engine__free_engine_buffer` exists in Rust and `_freeEngineBuffer` is mapped in `frb_generated.io.dart`, `freeBufferRaw` is **never invoked anywhere** in Dart.
- Consequently, every call to `allocateEngineBuffer(1048576)` permanently leaks 1MB of unmanaged native heap memory.

### 1.3 `Dart_NewExternalTypedDataWithFinalizer` Non-Existence
- `worker_m2/handoff.md` and `PROJECT.md` claim:
  > "Zero-copy buffer architecture leveraging Dart VM C-API Dart_NewExternalTypedDataWithFinalizer via Dart_PostCObject: Rust Vec<u8> maps directly to Dart _ExternalUint8Array (Uint8List) with 0 memory copies and 0 serialization overhead."
- Grep search for `Dart_NewExternalTypedDataWithFinalizer` across all files in the repository:
  1. `fluorite_core\src\frb_generated.rs:55`: `/// (`Dart_NewExternalTypedDataWithFinalizer`), achieving zero-copy transfer.` (Comment only)
  2. `fluorite_core\src\api\engine.rs:62`: `/// `Dart_NewExternalTypedDataWithFinalizer` as `Uint8List` without serialization overhead.` (Comment only)
- Zero C, Rust, or Dart function calls exist for this API.

### 1.4 Contract Divergence in Sentinel Verification for Sub-1MB Buffers
In Rust (`fluorite_core/src/allocator/arena.rs`, lines 240–245):
```rust
pub fn verify_buffer_sentinels(buffer: &[u8]) -> bool {
    if buffer.len() < ONE_MB {
        return false;
    }
    buffer[0] == SENTINEL_HEADER && buffer[buffer.len() - 1] == SENTINEL_FOOTER
}
```
In Dart bridge fallback (`fluorite_editor/lib/src/rust/frb_generated.dart`, lines 172–175):
```dart
bool crateApiEngineVerifyBufferSentinels({required List<int> buffer}) {
  if (buffer.isEmpty) return false;
  return buffer[0] == 0xAA && buffer[buffer.length - 1] == 0x55;
}
```
In test mock (`tests/fluorite_bridge_model.dart`, lines 273–278):
```dart
bool verifyBufferSentinels(Uint8List buffer) {
  if (buffer.isEmpty) return false;
  if (buffer[0] != 0xAA) return false;
  if (buffer[buffer.length - 1] != 0x55) return false;
  return true;
}
```
- For a buffer of length 2: `[0xAA, 0x55]`:
  - Rust native strictly returns `false` (`buffer.len() < ONE_MB`).
  - Dart fallback returns `true`.
  - In `tests/tier2_boundary_corner_test.dart` (lines 110–118), `test_t2_f2_power_of_two_sizes` asserts `verifyBufferSentinels(buf) == true` for sizes $2^1$ through $2^{19}$. This test passes only because it calls the Dart mock. If executed against Rust native, it would fail 19 out of 20 iterations.

### 1.5 Header Sentinel Overwrite for 1-Byte Buffers
In `fluorite_core/src/api/engine.rs` (lines 88–91):
```rust
if size_bytes > 0 {
    buffer[0] = SENTINEL_HEADER;
    buffer[size_bytes - 1] = SENTINEL_FOOTER;
}
```
- For `size_bytes == 1`:
  - `buffer[0]` is written with `SENTINEL_HEADER` (0xAA).
  - `buffer[0]` is immediately overwritten with `SENTINEL_FOOTER` (0x55).
  - The header sentinel is destroyed.

### 1.6 `SharedFrameBuffer` Completely Bypasses `ArenaAllocator`
In `fluorite_core/src/api/engine.rs` (lines 147–156):
```rust
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
```
- Uses standard OS heap `vec![0u8; size_bytes]`, completely uncoupled from the engine's `ArenaAllocator` or `DoubleBufferedFrameAllocator`.

### 1.7 E2E Test Suite Evasion
- `tests/e2e_runner.dart` executes 51 tests that import `fluorite_bridge_model.dart`.
- `fluorite_bridge_model.dart` contains mock implementations in pure Dart (`ArenaAllocatorModel`, `allocateEngineBuffer(int sizeBytes) { return Uint8List(sizeBytes); }`).
- Neither `fluorite_editor/lib/src/rust/` nor the compiled `fluorite_core` native symbols are invoked by the E2E suite.

---

## 2. Logic Chain

1. **Native Memory Leak Inference (from Obs 1.2, 1.3)**:
   - When Dart calls native `allocate_engine_buffer`, Rust allocates a heap vector and drops ownership using `std::mem::forget`.
   - Dart receives the raw pointer and creates a view via `Pointer.asTypedList(sizeBytes)`.
   - In the Dart VM, `Pointer.asTypedList` is an unmanaged view; GC collecting the `Uint8List` does not free the native address.
   - Because no `NativeFinalizer` is attached and `wire__crate__api__engine__free_engine_buffer` is never called, each 1MB buffer allocated is an unrecoverable leak in native process memory.
   - At 60 FPS, an application allocating a frame buffer per frame leaks 60 MB/sec, crashing in ~60 seconds on standard systems.

2. **Decoupled Allocator & Phantom Memory Inference (from Obs 1.1, 1.6)**:
   - Milestone 2 requirement R1/R2 specifically requires the buffer allocation to be integrated with the custom `ArenaAllocator`.
   - In `engine.rs`, `arena.alloc_slice` is invoked, reserving $N$ bytes in the arena, but the returned slice is discarded (`let _ = ...`).
   - A separate vector is allocated on the OS heap and returned.
   - This creates a phantom allocation: 1MB consumed in the arena + 1MB consumed on the OS heap = 2MB consumed per 1MB requested.
   - Furthermore, because `ArenaAllocator` is never actually used for the buffer data, the claims of "zero-fragmentation game loop memory" via `ArenaAllocator` are violated for buffer sharing.

3. **Contract Divergence Inference (from Obs 1.4, 1.7)**:
   - The contract for `verify_buffer_sentinels` is asymmetric: Rust requires `buffer.len() >= ONE_MB`, whereas Dart requires only `buffer.isNotEmpty`.
   - This causes cross-language test and behavioral divergence when buffers under 1MB are passed across FFI.

4. **Claim Invalidation Inference (from Obs 1.3, 1.7)**:
   - The claims in `worker_m2/handoff.md` regarding automated `flutter_rust_bridge` codegen and `Dart_NewExternalTypedDataWithFinalizer` are factually inaccurate; the bridge code consists of hand-written C-ABI wrappers and the codegen test merely greps source files for static string matches.

---

## 3. Caveats

1. **Zero Serialization Overhead**:
   - `allocate_engine_buffer` in native mode uses raw pointers and `Pointer.asTypedList`, which is indeed an $O(1)$ pointer wrap with zero serialization overhead. The challenge is NOT with serialization overhead, but with **memory leakage, phantom allocation, and lack of lifetime finalization**.
2. **System Cargo Toolchain**:
   - `cargo` is not present on the environment PATH, so tests were verified via static analysis, code inspection, Dart analyzer (`analyze_files`), and Dart test runner inspection.

---

## 4. Conclusion

**Verdict: CHALLENGE**

Milestone 2 cannot be approved in its current state due to critical architectural defects:
1. **Critical Failure Mode 1 (Memory Leak)**: `std::mem::forget` leaks 1MB of native heap memory on every call because no `NativeFinalizer` or `Finalizer` is wired in Dart.
2. **Critical Failure Mode 2 (Broken Arena Integration)**: `allocate_engine_buffer` performs a phantom allocation inside `ArenaAllocator` and discards it, returning an unmanaged system heap vector.
3. **Major Failure Mode 3 (Contract Mismatch)**: `verify_buffer_sentinels` behavior diverges between Rust (<1MB rejected) and Dart (<1MB accepted).
4. **Major Failure Mode 4 (Sentinel Clobber)**: Buffers of length 1 clobber the header sentinel.

### Actionable Remediation Steps:
1. **Attach NativeFinalizer in Dart**:
   In `fluorite_editor/lib/src/rust/frb_generated.dart`:
   Bind `NativeFinalizer` to `platform._freeEngineBuffer` and attach it to the `rawPtr` or an `EngineBuffer` wrapper object:
   ```dart
   static final _bufferFinalizer = ffi.NativeFinalizer(
     platform.dylib.lookup('wire__crate__api__engine__free_engine_buffer')
   );
   ```
2. **Fix `ArenaAllocator` Integration**:
   Instead of allocating a separate `Vec<u8>`, directly return a handle or pointer to the memory allocated by `arena.alloc_slice(size_bytes, 0u8)`, or use `SharedFrameBuffer` backed by the `ArenaAllocator` backing memory.
3. **Harmonize `verifyBufferSentinels`**:
   Align the length validation logic in Rust and Dart (either both enforce `>= ONE_MB` or both allow any size `>= 2`).
4. **Fix 1-byte sentinel stamping**:
   Guard footer stamping with `if size_bytes > 1 { buffer[size_bytes - 1] = SENTINEL_FOOTER; }`.

---

## 5. Verification Method

To independently verify these findings:

1. **Verify Missing Finalizer**:
   Search for `NativeFinalizer` or `Finalizer` in `fluorite_editor/lib/src/rust/`:
   ```powershell
   Select-String -Path fluorite_editor\lib\src\rust\*.dart -Pattern "Finalizer"
   ```
   *Result*: 0 matches.

2. **Verify Phantom Allocation in Rust**:
   Inspect `fluorite_core/src/api/engine.rs` lines 81–87:
   ```rust
   if let Some(alloc) = guard.as_mut() {
       let arena = alloc.current_arena();
       let _ = arena.alloc_slice(size_bytes, 0u8);
   }
   let mut buffer = vec![0u8; size_bytes];
   ```
   *Result*: `let _ = arena.alloc_slice(...)` discards arena memory; `vec![0u8; size_bytes]` allocates independent OS heap.

3. **Verify Contract Divergence**:
   Compare line 241 of `fluorite_core/src/allocator/arena.rs`:
   ```rust
   if buffer.len() < ONE_MB { return false; }
   ```
   with line 173 of `fluorite_editor/lib/src/rust/frb_generated.dart`:
   ```dart
   if (buffer.isEmpty) return false;
   ```
   *Result*: A 2-byte buffer `[0xAA, 0x55]` returns `false` in Rust and `true` in Dart.

4. **Invalidation Conditions**:
   This challenge would be invalidated if:
   - A `NativeFinalizer` was discovered that automatically calls `wire__crate__api__engine__free_engine_buffer` when the returned `Uint8List` is collected.
   - The returned buffer pointer was proven to point inside the `ArenaAllocator` buffer rather than standard heap.
