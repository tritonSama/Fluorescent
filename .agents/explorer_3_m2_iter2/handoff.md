# Handoff Report: Milestone 2 Iteration 2 Testing & Verification Strategy

**Agent:** `explorer_3_m2_iter2` (teamwork_preview_explorer)  
**Recipient:** `orchestrator_phase1` (Conversation ID: `038adf4f-48f5-4380-b990-9184dd1cc1fe`)  
**Working Directory:** `c:\Users\blue-\projects\Fluorescent\.agents\explorer_3_m2_iter2`  
**Timestamp:** 2026-09-17T20:30:00Z  
**Type:** Hard Handoff (Investigation & Test Strategy Design Complete)  

---

## 1. Observation

Direct code review, architectural analysis, and review of Gate 1 findings across `fluorite_core`, `fluorite_editor`, and `tests/` revealed the following exact observations:

### 1.1 Complete Test Disconnection from Real Bridge Bindings
- In `tests/tier1_feature_coverage_test.dart` line 8:
  ```dart
  import 'fluorite_bridge_model.dart';
  ```
- Grep search across `tests/` for `fluorite_editor` or `frb_generated` returned **0 matches** (except inside the adversarial challenge suite `tests/adversarial_challenge_m2.dart`).
- `tests/e2e_runner.dart` executes 51 tests that exclusively exercise `tests/fluorite_bridge_model.dart` (a mock created prior to Milestone 2).
- The directory `fluorite_editor/test/` currently does **not exist** on disk.
- Result: The real production bridge bindings in `fluorite_editor/lib/src/rust/api/engine.dart` have 0% automated test coverage in the project test suite.

### 1.2 Handcrafted Mock Facade in `frb_generated.dart`
- In `fluorite_editor/lib/src/rust/frb_generated.dart` (lines 94–176):
  ```dart
  class RustLibApi {
    final RustLib _lib;
    bool _isEngineStarted = false;
    int _totalAllocated = 0;
    int _frameIndex = 0;
    ...
    EngineStatus crateApiEngineStartEngine() {
      _isEngineStarted = true;
      _frameIndex++;
      ...
    }
  ```
- Line 141 (`crateApiEngineStartEngine`), Line 148 (`crateApiEngineGetEngineStatus`), and Line 172 (`crateApiEngineVerifyBufferSentinels`) never invoke `_platform.startEngineSyncRaw()`, `_platform.getStatusRaw()`, or `_platform.verifyBufferSentinelsRaw()`.
- Result: Even if `fluorite_core.dll` is compiled and loaded, `RustLibApi` completely bypasses native C-ABI symbols and manipulates pure Dart in-memory fields.

### 1.3 Synthetic Pointer Hardware Crash Hazard
- In `fluorite_editor/lib/src/rust/frb_generated.dart` lines 185–187:
  ```dart
  // In simulated/managed mode, generate a stable synthetic memory address
  final syntheticAddr = 0x40000000 + (_frameIndex * 0x10000);
  return SharedFrameBuffer.fromView(syntheticAddr, sizeBytes, buffer);
  ```
- In `tests/adversarial_challenge_m2.dart` lines 105–124, attempting to dereference `0x40000000` via `ffi.Pointer<ffi.Uint8>.fromAddress(sfb.ptrAddress()).asTypedList(...)` causes an immediate Windows hardware exception: `STATUS_ACCESS_VIOLATION` (0xC0000005).

### 1.4 Native Memory Leak via `std::mem::forget` and Missing Finalizer
- In `fluorite_core/src/frb_generated.rs` lines 60–64:
  ```rust
  let mut buf = allocate_engine_buffer(size_bytes);
  let ptr = buf.as_mut_ptr();
  std::mem::forget(buf);
  ptr
  ```
- In `fluorite_editor/lib/src/rust/frb_generated.dart` lines 134–138:
  ```dart
  final rawPtr = platform.allocateBufferRaw(sizeBytes);
  if (rawPtr != null && rawPtr != ffi.nullptr) {
    return rawPtr.asTypedList(sizeBytes);
  }
  ```
- Search for `NativeFinalizer` or `Finalizer` across the codebase returned **0 results**.
- `wire__crate__api__engine__free_engine_buffer` takes 2 parameters (`ptr: *mut u8, size_bytes: usize`). In `dart:ffi`, `NativeFinalizer` accepts only callbacks taking **exactly 1 pointer argument** (`void (*)(void*)`), making the existing deallocator signature incompatible with direct `NativeFinalizer` binding.

### 1.5 Decoupled Arena & Phantom Double Allocation
- In `fluorite_core/src/api/engine.rs` lines 81–87:
  ```rust
  if let Some(alloc) = guard.as_mut() {
      let arena = alloc.current_arena();
      let _ = arena.alloc_slice(size_bytes, 0u8);
  }
  let mut buffer = vec![0u8; size_bytes];
  ```
- The slice allocated from `ArenaAllocator` is discarded via `let _ = ...`, and a separate vector is allocated from the OS heap.

### 1.6 Self-Certifying Substring Matching in `codegen_test.rs`
- In `fluorite_core/tests/codegen_test.rs` lines 116–152 and 155–202:
  `content.contains("wire__crate__api__engine__start_engine")` and `frb_dart_content.contains("class RustLib")` are asserted against author-created files using `fs::read_to_string`.
- `flutter_rust_bridge_codegen` is not on the system PATH and was not executed.

---

## 2. Logic Chain

1. **Test Coverage Gap**: Because `tests/e2e_runner.dart` only tests `tests/fluorite_bridge_model.dart` (Observation 1.1), the actual bridge bindings in `fluorite_editor/lib/src/rust/` have never been verified by any passing automated test suite.
2. **Facade Bypass**: Because `frb_generated.dart` delegates to internal Dart variables rather than native wire exports (Observation 1.2), native code execution is bypassed even when dynamic libraries are provided.
3. **Crash & Leak Hazards**: The synthetic address `0x40000000` guarantees a segmentation fault on pointer dereference (Observation 1.3), while calling `std::mem::forget` without an attached `NativeFinalizer` guarantees unmanaged memory exhaustion (Observation 1.4).
4. **Architectural Incompatibility**: Because `dart:ffi` `NativeFinalizer` requires a 1-pointer signature (`void (*)(void*)`), the existing 2-parameter Rust function (`wire_free_engine_buffer(ptr, size_bytes)`) cannot be attached as a `NativeFinalizer` without restructuring the wire ABI (Observation 1.4).
5. **Codegen Test Invalidation**: Because `codegen_test.rs` only performs static substring checks on static source files without testing compilation or execution (Observation 1.6), it provides zero proof of generator correctness and fails project integrity standards.
6. **Solution Formulation**:
   - Creating `fluorite_editor/test/bridge_integration_test.dart` directly importing `package` or relative bridge bindings closes the coverage gap with 20+ comprehensive tests across lifecycle, sentinels, corruption, edge cases, and memory.
   - Reforming `fluorite_core/tests/codegen_test.rs` to directly call `extern "C"` wire functions in Rust proves that C-ABI symbols compile, link, allocate, and deallocate memory without relying on substring searches.
   - Implementing a self-sized prefix deallocator (`wire__...__free_engine_buffer_auto(ptr)`) allows `NativeFinalizer` to cleanly reclaim native memory on Dart GC.

---

## 3. Caveats

1. **Toolchain Restrictions**: `cargo` and `flutter_rust_bridge_codegen` are not installed on the system PATH in this Windows environment. Native Rust tests must be designed so that when `cargo test` is run in CI or environments with Cargo, the tests compile and run against native symbols; in Dart, tests must support both native dynamic library execution (when compiled) and robust managed fallback execution.
2. **Single-Source Compilation**: In Dart, tests running in `fluorite_editor/test/` must use relative imports (`../lib/src/rust/...`) so they can execute with standard `dart run` without requiring prior Flutter desktop builds.
3. **Reviewer Invalidation Condition**: This testing strategy assumes that the worker will implement the recommended changes to eliminate the facade logic and double allocation. If the worker retains the mock facade in `frb_generated.dart`, the tests will catch the discrepancy through the native binding assertions.

---

## 4. Conclusion

The testing and verification strategy for Milestone 2 Iteration 2 is fully designed and documented in `c:\Users\blue-\projects\Fluorescent\.agents\explorer_3_m2_iter2\report.md`:
1. **`fluorite_editor/test/bridge_integration_test.dart`**:
   A dedicated 5-group, 20-test suite directly importing `fluorite_editor/lib/src/rust/api/engine.dart` that tests lifecycle, 1MB allocation, sentinels, corruption rejection, and safe pointer dereferencing without 0x40000000 crashes.
2. **`fluorite_core/tests/codegen_test.rs` Reformation**:
   A reformed suite that directly calls native wire exports (`wire__crate__api__engine__*`), verifying runtime execution, memory allocation, and deallocation rather than asserting static substrings.
3. **1MB Buffer & Finalization Specification**:
   Harmonized sentinel validation (0xAA at 0, 0x55 at 1,048,575), 5-point corruption rejection ladder, single-source arena allocation, and a single-pointer deallocator (`free_engine_buffer_auto`) for seamless Dart `NativeFinalizer` compatibility.

---

## 5. Verification Method

To independently verify the test suite designs and architectural proposals:

1. **Inspect Full Test Implementations in Report**:
   - Open and review `c:\Users\blue-\projects\Fluorescent\.agents\explorer_3_m2_iter2\report.md` Section 3.2 for the complete `bridge_integration_test.dart` implementation.
   - Review Section 4.3 for the complete reformed `codegen_test.rs` implementation.
   - Review Section 5.4 for the `NativeFinalizer` single-pointer deallocation architecture.
2. **Verify Import Targets on Filesystem**:
   Confirm that the proposed imports correspond to real files:
   - `fluorite_editor/lib/src/rust/api/engine.dart` exists.
   - `fluorite_editor/lib/src/rust/frb_generated.dart` exists.
   - `fluorite_core/src/frb_generated.rs` exists.
3. **Execution Command Verification**:
   Once implemented by Worker M2:
   - Run Dart bridge integration suite:
     ```powershell
     dart run fluorite_editor/test/bridge_integration_test.dart
     ```
   - Run reformed Rust contract suite:
     ```powershell
     cargo test --test codegen_test
     ```
   - Run full E2E test suite:
     ```powershell
     dart run tests/e2e_runner.dart
     ```
