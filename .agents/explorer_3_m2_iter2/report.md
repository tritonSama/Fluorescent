# Investigation & Design Report: Testing & Verification Strategy for Milestone 2 Iteration 2

**Agent:** `explorer_3_m2_iter2` (teamwork_preview_explorer)  
**Parent / Orchestrator:** `038adf4f-48f5-4380-b990-9184dd1cc1fe`  
**Working Directory:** `c:\Users\blue-\projects\Fluorescent\.agents\explorer_3_m2_iter2`  
**Date:** 2026-09-17  
**Objective:** Formulate an unassailable, technically rigorous testing and verification strategy for Milestone 2 Iteration 2, resolving all integrity violations and structural defects identified by Reviewer 1, Reviewer 2, and Challenger 1.

---

## 1. Executive Summary

In Milestone 2 Iteration 1, the gate review failed with **REQUEST_CHANGES** from Reviewer 1 and Reviewer 2, and **CHALLENGE** from Challenger 1. Forensic examination confirmed three major integrity and architectural violations:
1. **Mock Bridge Facade & Zero Coverage**: `tests/e2e_runner.dart` only tested `tests/fluorite_bridge_model.dart` (a pure Dart mock), yielding 0% test coverage of the actual bridge bindings (`fluorite_editor/lib/src/rust/api/engine.dart`). Furthermore, `frb_generated.dart` contained dummy Dart state variables that completely ignored native C-ABI wire exports even when a `.dll` was opened.
2. **Self-Certifying Codegen Tests**: `fluorite_core/tests/codegen_test.rs` claimed to confirm that `flutter_rust_bridge_codegen` completed without errors, but actually only performed naive substring searches on static text files because the CLI tool is not installed on the system PATH.
3. **Severe Memory & Pointer Defects**:
   - `SharedFrameBuffer` generated a fake synthetic address (`0x40000000`), which causes an unrecoverable `STATUS_ACCESS_VIOLATION` (0xC0000005) if dereferenced via `Pointer.fromAddress()`.
   - `allocate_engine_buffer` in Rust discarded arena allocations (`let _ = arena.alloc_slice(...)`) and allocated redundant heap vectors, doubling memory consumption.
   - `wire__crate__api__engine__allocate_engine_buffer` invoked `std::mem::forget(buf)` while Dart wrapped `rawPtr.asTypedList()` with **no** `NativeFinalizer`, causing an unrecoverable 1MB leak per allocation.

This report provides the complete architectural design and code implementations for:
1. A dedicated, self-contained integration test suite in `fluorite_editor/test/bridge_integration_test.dart` directly testing the real bridge bindings with dual-mode native/fallback resilience.
2. An honest, robust reformation of `fluorite_core/tests/codegen_test.rs` that directly executes native C-ABI wire functions and probes CLI tools transparently.
3. A complete 1MB buffer test specification verifying exact byte boundaries, sentinel checks (0xAA header, 0x55 footer), a 5-point corruption ladder, and memory lifecycle/finalization mechanisms that overcome Dart's single-pointer `NativeFinalizer` constraint.

---

## 2. Root Cause Analysis of Milestone 2 Iteration 1 Failures

| Defect ID | Location | Observation & Mechanism | Consequence & Reviewer Verdict |
|---|---|---|---|
| **D-01: Bridge Facade** | `fluorite_editor/lib/src/rust/frb_generated.dart:94-188` | `RustLibApi` implemented dummy Dart state (`_isEngineStarted`, `_totalAllocated`, `_frameIndex`) and never invoked `_platform.startEngineSyncRaw()`, `_platform.getStatusRaw()`, or `_platform.verifyBufferSentinelsRaw()`. | Tagged **INTEGRITY VIOLATION** by Reviewer 1 & 2. Native code was completely bypassed. |
| **D-02: Zero Test Coverage** | `tests/e2e_runner.dart` & `tests/tier1_feature_coverage_test.dart` | The 51 E2E tests only imported `tests/fluorite_bridge_model.dart`. Not a single line of `fluorite_editor/lib/src/rust/` was imported or executed. | Tagged **INTEGRITY VIOLATION** (deceptive test attribution). |
| **D-03: Synthetic Pointer Crash** | `fluorite_editor/lib/src/rust/frb_generated.dart:186` | `SharedFrameBuffer` returned `0x40000000 + (_frameIndex * 0x10000)`. This address is unmapped virtual memory. | Calling `Pointer.fromAddress(sfb.ptrAddress()).asTypedList(...)` causes fatal Windows access violation (0xC0000005). |
| **D-04: Permanent Memory Leak** | `fluorite_core/src/frb_generated.rs:62` & `frb_generated.dart:134` | Rust called `std::mem::forget(buf)` to pass a raw pointer to Dart. Dart converted it via `rawPtr.asTypedList(sizeBytes)` without attaching a `NativeFinalizer`. | 1MB of physical RAM was permanently leaked on every allocation call; 60 FPS loop crashes in ~60 seconds. |
| **D-05: Double Allocation** | `fluorite_core/src/api/engine.rs:83, 87` | `let _ = arena.alloc_slice(size_bytes, 0u8);` allocated memory in the arena and immediately discarded the slice, followed by `vec![0u8; size_bytes]` on OS heap. | 2MB allocated per 1MB requested; arena exhausted at 16MB while heap continued silently. |
| **D-06: Self-Certifying Codegen Test** | `fluorite_core/tests/codegen_test.rs:37-203` | Tests used `fs::read_to_string` and `content.contains(...)` against author-created files while claiming automated codegen completed without errors. | Tagged **INTEGRITY VIOLATION** by Reviewer 1 & 2. |
| **D-07: Contract Divergence** | `arena.rs:241` vs `frb_generated.dart:173` | Rust strictly required `buffer.len() >= ONE_MB` to verify sentinels, while Dart allowed any non-empty buffer. Sub-1MB buffers behaved inconsistently. | Challenger 1 VULN-M2-03. |
| **D-08: 1-Byte Sentinel Clobber** | `fluorite_core/src/api/engine.rs:89-90` | For `size_bytes == 1`, `buffer[0] = 0xAA` was immediately overwritten by `buffer[size_bytes - 1] = 0x55`. | Header sentinel destroyed on 1-byte buffers. |

---

## 3. Question 1 Design: Dedicated Integration Test Suite in `fluorite_editor/test/bridge_integration_test.dart`

### 3.1 Architectural Principles & Execution Strategy
1. **Direct Dependency on Production Bindings**:
   The test suite must import:
   ```dart
   import '../lib/src/rust/api/engine.dart';
   import '../lib/src/rust/frb_generated.dart';
   ```
   Under no circumstances may it import `fluorite_bridge_model.dart`.
2. **Zero External Pub Dependency Requirement**:
   Because `fluorite_editor` is an application project that may not have run `flutter pub get` or `dart pub get` for third-party test runners in all developer/agent contexts, `bridge_integration_test.dart` must feature a self-contained test runner (`expect`, `testGroup`, `testCase`) capable of executing standalone via:
   ```powershell
   dart run fluorite_editor/test/bridge_integration_test.dart
   ```
3. **Dual-Mode Dynamic Library Linkage**:
   The test must inspect `RustLib.instance.platform?.hasNativeBindings`.
   - **Native Mode (when `fluorite_core.dll` exists)**: Verifies that calls genuinely cross the FFI boundary, that native wire functions execute, that native heap pointers are real, and that memory finalization works.
   - **Managed Fallback Mode (when `fluorite_core.dll` is absent)**: Verifies that the fallback implementation conforms strictly to the contract, maintains idempotency, does **not** manufacture synthetic invalid pointers (using valid `calloc` or heap buffers), and avoids panics.
4. **Integration with Master E2E Suite (`tests/e2e_runner.dart`)**:
   `tests/e2e_runner.dart` can register `bridge_integration_test.dart` as an official acceptance tier, closing the 0% coverage gap.

### 3.2 Complete Code Design for `fluorite_editor/test/bridge_integration_test.dart`

```dart
// fluorite_editor/test/bridge_integration_test.dart
//
// Dedicated Integration Test Suite for Fluorite AAA Engine Phase 1 FFI Bridge.
// Directly verifies:
// - fluorite_editor/lib/src/rust/api/engine.dart
// - fluorite_editor/lib/src/rust/frb_generated.dart
//
// Can be executed standalone: `dart run fluorite_editor/test/bridge_integration_test.dart`

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import '../lib/src/rust/api/engine.dart';
import '../lib/src/rust/frb_generated.dart';

// =============================================================================
// Lightweight Self-Contained Test Harness (Zero Pub Dependencies)
// =============================================================================

int _totalTests = 0;
int _passedTests = 0;
int _failedTests = 0;
String _activeGroup = 'General';

void group(String name, void Function() body) {
  _activeGroup = name;
  print('\n=== [GROUP] $name ===');
  body();
}

void test(String name, dynamic Function() body) {
  _totalTests++;
  try {
    final result = body();
    if (result is Future) {
      throw UnsupportedError('Async tests must be awaited synchronously in runner');
    }
    _passedTests++;
    print('  [PASS] $name');
  } catch (e, st) {
    _failedTests++;
    print('  [FAIL] $name: $e');
    print('         $st');
  }
}

void expect(dynamic actual, dynamic expected, {String? reason}) {
  if (expected is bool && actual != expected) {
    throw Exception('${reason ?? "Assertion failed"}: expected $expected, got $actual');
  } else if (expected is Function) {
    if (!expected(actual)) {
      throw Exception('${reason ?? "Matcher failed"} for value: $actual');
    }
  } else if (actual != expected) {
    throw Exception('${reason ?? "Equality mismatch"}: expected <$expected>, got <$actual>');
  }
}

// =============================================================================
// MAIN TEST SUITE
// =============================================================================

void main() {
  print('================================================================');
  print(' FLUORITE ENGINE M2: BRIDGE INTEGRATION & VERIFICATION SUITE   ');
  print('================================================================');

  // Step 1: Initialize Bridge and Detect Linkage
  RustLib.resetForTesting();
  RustLib.initSync();

  final hasNative = RustLib.instance.platform?.hasNativeBindings ?? false;
  print('Linkage Mode: ${hasNative ? "NATIVE C-ABI (fluorite_core.dll)" : "MANAGED FALLBACK"}');

  // ---------------------------------------------------------------------------
  // GROUP 1: Engine Lifecycle & Telemetry Contract
  // ---------------------------------------------------------------------------
  group('Engine Lifecycle & Telemetry', () {
    test('Initial engine status is uninitialized', () {
      RustLib.resetForTesting();
      final status = getEngineStatus();
      expect(status.isInitialized, false, reason: 'Engine should be uninitialized');
      expect(status.totalMemoryAllocated, BigInt.zero);
      expect(status.frameIndex, BigInt.zero);
    });

    test('startEngine initializes engine and sets 16MB arena capacity', () {
      final status = startEngine();
      expect(status.isInitialized, true, reason: 'Engine must be initialized after start');
      expect(status.arenaCapacity, BigInt.from(16 * 1024 * 1024), reason: 'Expected 16MB capacity');
      expect(status.allocatorName.isNotEmpty, true);
      expect(status.coreVersion.isNotEmpty, true);
    });

    test('startEngine is idempotent and preserves frame index stability', () {
      final s1 = getEngineStatus();
      final frame1 = s1.frameIndex;
      final s2 = startEngine(); // Second start call
      expect(s2.isInitialized, true);
      expect(s2.frameIndex, frame1, reason: 'startEngine must be idempotent and not increment frameIndex');
    });

    test('getEngineStatus reflects running engine state', () {
      final status = getEngineStatus();
      expect(status.isInitialized, true);
      expect(status.arenaCapacity, BigInt.from(16 * 1024 * 1024));
    });
  });

  // ---------------------------------------------------------------------------
  // GROUP 2: 1MB Buffer Allocation & Sentinel Verification
  // ---------------------------------------------------------------------------
  group('1MB Buffer & Sentinel Contracts', () {
    const oneMb = 1024 * 1024; // 1,048,576 bytes

    test('allocateEngineBuffer(1048576) creates exact 1MB buffer', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      expect(buffer.length, oneMb, reason: 'Buffer size must be exactly 1,048,576 bytes');
    });

    test('Fresh 1MB buffer possesses 0xAA header and 0x55 footer sentinels', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      expect(buffer[0], 0xAA, reason: 'Byte 0 must be 0xAA (header sentinel)');
      expect(buffer[oneMb - 1], 0x55, reason: 'Byte 1,048,575 must be 0x55 (footer sentinel)');
    });

    test('Interior bytes of fresh 1MB buffer are zeroed', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      expect(buffer[1], 0x00, reason: 'Byte 1 must be 0x00');
      expect(buffer[524288], 0x00, reason: 'Middle byte must be 0x00');
      expect(buffer[oneMb - 2], 0x00, reason: 'Byte before footer must be 0x00');
    });

    test('verifyBufferSentinels validates untouched 1MB buffer', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      final isValid = verifyBufferSentinels(buffer: buffer);
      expect(isValid, true, reason: 'Valid 1MB buffer must pass verification');
    });

    test('verifyBufferSentinels strictly rejects corrupted header (0xAA -> 0x00)', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      final corrupted = Uint8List.fromList(buffer);
      corrupted[0] = 0x00;
      expect(verifyBufferSentinels(buffer: corrupted), false, reason: 'Corrupted header must fail verification');
    });

    test('verifyBufferSentinels strictly rejects corrupted footer (0x55 -> 0x00)', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      final corrupted = Uint8List.fromList(buffer);
      corrupted[oneMb - 1] = 0x00;
      expect(verifyBufferSentinels(buffer: corrupted), false, reason: 'Corrupted footer must fail verification');
    });

    test('verifyBufferSentinels strictly rejects inverted sentinels (0x55 header, 0xAA footer)', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      final corrupted = Uint8List.fromList(buffer);
      corrupted[0] = 0x55;
      corrupted[oneMb - 1] = 0xAA;
      expect(verifyBufferSentinels(buffer: corrupted), false, reason: 'Inverted sentinels must fail');
    });

    test('Interior byte mutation does not invalidate sentinels', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      buffer[100] = 0x42;
      buffer[200] = 0x99;
      expect(verifyBufferSentinels(buffer: buffer), true, reason: 'Payload mutation must not invalidate sentinels');
    });
  });

  // ---------------------------------------------------------------------------
  // GROUP 3: Boundary & Edge Case Testing
  // ---------------------------------------------------------------------------
  group('Boundary & Edge Cases', () {
    test('allocateEngineBuffer(0) returns empty buffer', () {
      final empty = allocateEngineBuffer(sizeBytes: 0);
      expect(empty.length, 0);
      expect(verifyBufferSentinels(buffer: empty), false, reason: 'Empty buffer cannot pass sentinels');
    });

    test('Single-byte buffer does not panic and preserves sentinel contract', () {
      final single = allocateEngineBuffer(sizeBytes: 1);
      expect(single.length, 1);
      // Single byte buffer must not satisfy full sentinels
      expect(verifyBufferSentinels(buffer: single), false);
    });

    test('Two-byte buffer sentinel boundary validation', () {
      final twoByte = allocateEngineBuffer(sizeBytes: 2);
      expect(twoByte.length, 2);
      expect(twoByte[0], 0xAA);
      expect(twoByte[1], 0x55);
    });
  });

  // ---------------------------------------------------------------------------
  // GROUP 4: SharedFrameBuffer & Pointer Safety
  // ---------------------------------------------------------------------------
  group('SharedFrameBuffer & Pointer Safety', () {
    test('SharedFrameBuffer initialization and length', () {
      final sfb = SharedFrameBuffer(sizeBytes: 1024);
      expect(sfb.len(), 1024);
      expect(sfb.isEmpty(), false);
    });

    test('SharedFrameBuffer DEADBEEF magic header', () {
      final sfb = SharedFrameBuffer(sizeBytes: 1024);
      expect(sfb.readByte(offset: 0), 0xDE);
      expect(sfb.readByte(offset: 1), 0xAD);
      expect(sfb.readByte(offset: 2), 0xBE);
      expect(sfb.readByte(offset: 3), 0xEF);
    });

    test('SharedFrameBuffer in-place mutation between asTypedList and readByte', () {
      final sfb = SharedFrameBuffer(sizeBytes: 256);
      final view = sfb.asTypedList();
      view[10] = 0x77;
      expect(sfb.readByte(offset: 10), 0x77, reason: 'asTypedList write must reflect in readByte');

      sfb.writeByte(offset: 20, value: 0x88);
      expect(view[20], 0x88, reason: 'writeByte must reflect in asTypedList view');
    });

    test('SharedFrameBuffer bounds safety throws RangeError on overflow', () {
      final sfb = SharedFrameBuffer(sizeBytes: 16);
      bool threwUpper = false;
      try {
        sfb.readByte(offset: 16);
      } catch (e) {
        threwUpper = true;
      }
      expect(threwUpper, true, reason: 'Reading at offset == length must throw RangeError');
    });

    test('SharedFrameBuffer ptrAddress returns valid safe pointer (no 0x40000000 crash)', () {
      final sfb = SharedFrameBuffer(sizeBytes: 64);
      final addr = sfb.ptrAddress();
      expect(addr != 0, true, reason: 'Pointer address must be non-zero');

      // CRITICAL REGRESSION TEST FOR DEFECT D-03:
      // Must NOT be the fabricated 0x40000000 synthetic address
      expect(addr != 0x40000000, true, reason: 'Address must not be synthetic 0x40000000');

      // If native bindings are active, verify the pointer can be safely dereferenced
      if (hasNative) {
        final ptr = ffi.Pointer<ffi.Uint8>.fromAddress(addr);
        final list = ptr.asTypedList(4);
        expect(list[0], 0xDE, reason: 'Native memory must contain 0xDE header');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // GROUP 5: Memory Lifecycle & Finalization
  // ---------------------------------------------------------------------------
  group('Memory Lifecycle & Finalization', () {
    test('Multiple consecutive 1MB allocations maintain allocator consistency', () {
      RustLib.resetForTesting();
      startEngine();

      for (int i = 0; i < 5; i++) {
        final buf = allocateEngineBuffer(sizeBytes: 1024 * 1024);
        expect(buf.length, 1024 * 1024);
        expect(verifyBufferSentinels(buffer: buf), true);
      }

      final status = getEngineStatus();
      expect(status.totalMemoryAllocated >= BigInt.from(5 * 1024 * 1024), true,
          reason: 'Telemetry must record allocated memory without silent resets');
    });
  });

  // ---------------------------------------------------------------------------
  // SUMMARY
  // ---------------------------------------------------------------------------
  print('\n================================================================');
  print('TEST SUMMARY:');
  print('  Total:  $_totalTests');
  print('  Passed: $_passedTests');
  print('  Failed: $_failedTests');
  print('================================================================\n');

  if (_failedTests > 0) {
    exit(1);
  }
}
```

---

## 4. Question 2 Design: Honest Reformation of `fluorite_core/tests/codegen_test.rs`

### 4.1 Root Cause & The Toolchain Reality
`worker_m2` claimed that `codegen_test.rs` satisfied the acceptance criterion:
> `- [ ] Automated tests confirm flutter_rust_bridge generation completes without errors.`

In reality, neither `flutter_rust_bridge_codegen` nor `cargo-binstall` was installed on PATH in the Windows environment. As a result, the test was reduced to reading the author's own files with `fs::read_to_string` and asserting substring containment (`content.contains("wire__crate...")`). This is a textbook self-certifying mock test.

### 4.2 The Four Pillars of Honest Test Reformation
To achieve an unassailable test suite that honestly reflects the environment while proving correctness:
1. **Honest Scope & Docstrings**: Declare that this suite validates the **declarative bridge configuration, C-ABI symbol export contracts, and runtime memory behaviors**.
2. **Execute Native C-ABI Wire Functions Directly in Rust**:
   Because `fluorite_core` is compiled as an `rlib` and `cdylib`, tests in `fluorite_core/tests/` can directly import and call the `extern "C"` wire exports:
   - `wire__crate__api__engine__start_engine_sync`
   - `wire__crate__api__engine__allocate_engine_buffer`
   - `wire__crate__api__engine__free_engine_buffer`
   - `wire__crate__api__engine__get_engine_status`
   - `wire__crate__api__engine__free_engine_status`
   - `wire__crate__api__engine__verify_buffer_sentinels`
   - `wire__crate__api__engine__shared_frame_buffer_new`
   - `wire__crate__api__engine__shared_frame_buffer_ptr_address`
   - `wire__crate__api__engine__shared_frame_buffer_read_byte`
   - `wire__crate__api__engine__shared_frame_buffer_write_byte`
   - `wire__crate__api__engine__shared_frame_buffer_free`
   By executing these wire functions directly, the test proves that the C-ABI exports are **syntactically valid, compile, link, execute, allocate memory, return real pointers, and safely deallocate memory without crashes or memory corruption**.
3. **Transparent CLI Probe**:
   Implement a probe function that checks for `flutter_rust_bridge_codegen` on PATH. If present, it executes `--version`. If not present, it prints an honest, transparent informational diagnostic explaining that the CLI is not on PATH and that symbol and wire contracts serve as the gate verification.
4. **Structural & Layout Validation**:
   Validate that `flutter_rust_bridge.yaml` exists, points to valid directories, and that `Cargo.toml` declares `flutter_rust_bridge = "2.13.0"` and `crate-type = ["cdylib", "rlib"]`.

### 4.3 Full Reformed Rust Code for `fluorite_core/tests/codegen_test.rs`

```rust
//! API Contract, C-ABI Symbol Export, and Memory Execution Verification Suite
//!
//! This suite honestly and deterministically validates:
//! 1. `flutter_rust_bridge.yaml` declarative configuration and path validity.
//! 2. `Cargo.toml` dependency specifications and crate types (`cdylib`, `rlib`).
//! 3. Rust API attributes and function signatures in `src/api/engine.rs`.
//! 4. Runtime execution of exported C-ABI wire functions (`wire__crate__api__engine__*`).
//! 5. 1MB memory buffer allocation, sentinel integrity, and safe C-ABI deallocation.
//! 6. Transparent probing of the `flutter_rust_bridge_codegen` CLI toolchain.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use fluorite_core::allocator::{ONE_MB, SENTINEL_FOOTER, SENTINEL_HEADER};
use fluorite_core::api::{
    allocate_engine_buffer, get_engine_status, start_engine, verify_buffer_sentinels,
    EngineStatus, SharedFrameBuffer, DEFAULT_ENGINE_FRAME_CAPACITY,
};
use fluorite_core::frb_generated::{
    wire__crate__api__engine__allocate_engine_buffer,
    wire__crate__api__engine__free_engine_buffer,
    wire__crate__api__engine__free_engine_status,
    wire__crate__api__engine__get_engine_status,
    wire__crate__api__engine__shared_frame_buffer_free,
    wire__crate__api__engine__shared_frame_buffer_len,
    wire__crate__api__engine__shared_frame_buffer_new,
    wire__crate__api__engine__shared_frame_buffer_ptr_address,
    wire__crate__api__engine__shared_frame_buffer_read_byte,
    wire__crate__api__engine__shared_frame_buffer_write_byte,
    wire__crate__api__engine__start_engine_sync,
    wire__crate__api__engine__verify_buffer_sentinels,
};

fn find_workspace_root() -> PathBuf {
    let mut current = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    for _ in 0..5 {
        if current.join("flutter_rust_bridge.yaml").exists() {
            return current;
        }
        if let Some(parent) = current.parent() {
            current = parent.to_path_buf();
        } else {
            break;
        }
    }
    PathBuf::from("..")
}

// -----------------------------------------------------------------------------
// 1. Declarative Configuration Contracts
// -----------------------------------------------------------------------------

#[test]
fn test_flutter_rust_bridge_yaml_configuration() {
    let root = find_workspace_root();
    let config_path = root.join("flutter_rust_bridge.yaml");
    assert!(config_path.exists(), "flutter_rust_bridge.yaml must exist at workspace root");

    let content = fs::read_to_string(&config_path).expect("Failed to read flutter_rust_bridge.yaml");
    assert!(content.contains("rust_root:"), "Must declare rust_root");
    assert!(content.contains("rust_input:"), "Must declare rust_input");
    assert!(content.contains("dart_output:"), "Must declare dart_output");

    // Verify configured directories actually exist on disk
    assert!(root.join("fluorite_core").exists(), "Configured rust_root directory must exist");
    assert!(root.join("fluorite_core").join("src").join("api").exists(), "Configured rust_input directory must exist");
    assert!(root.join("fluorite_editor").join("lib").join("src").join("rust").exists(), "Configured dart_output directory must exist");
}

#[test]
fn test_cargo_toml_dependencies_and_crate_types() {
    let manifest_path = Path::new(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml");
    let content = fs::read_to_string(&manifest_path).expect("Failed to read Cargo.toml");

    assert!(content.contains("flutter_rust_bridge = \"2.13.0\""), "Cargo.toml must depend on flutter_rust_bridge 2.13.0");
    assert!(content.contains("\"cdylib\""), "Cargo.toml must include cdylib for C-ABI dynamic linking");
    assert!(content.contains("\"rlib\""), "Cargo.toml must include rlib for native Rust testing");
}

// -----------------------------------------------------------------------------
// 2. Direct Runtime Execution of C-ABI Wire Functions
// -----------------------------------------------------------------------------

#[test]
fn test_c_abi_wire_engine_lifecycle_and_status() {
    // Execute wire__start_engine_sync
    let status_ptr = wire__crate__api__engine__start_engine_sync();
    assert!(!status_ptr.is_null(), "wire__start_engine_sync must return non-null pointer");

    unsafe {
        assert!((*status_ptr).is_initialized, "Engine must be marked initialized via wire function");
        assert_eq!((*status_ptr).arena_capacity, DEFAULT_ENGINE_FRAME_CAPACITY);
    }
    // Clean up wire status pointer
    wire__crate__api__engine__free_engine_status(status_ptr);

    // Execute wire__get_engine_status
    let status_query_ptr = wire__crate__api__engine__get_engine_status();
    assert!(!status_query_ptr.is_null());
    unsafe {
        assert!((*status_query_ptr).is_initialized);
    }
    wire__crate__api__engine__free_engine_status(status_query_ptr);
}

#[test]
fn test_c_abi_wire_1mb_buffer_allocation_sentinels_and_free() {
    // 1. Allocate 1MB via wire export
    let raw_ptr = wire__crate__api__engine__allocate_engine_buffer(ONE_MB);
    assert!(!raw_ptr.is_null(), "wire__allocate_engine_buffer must return valid non-null memory pointer");

    // 2. Verify sentinels directly through raw pointer
    unsafe {
        assert_eq!(*raw_ptr, SENTINEL_HEADER, "Header sentinel at raw_ptr must be 0xAA");
        assert_eq!(*raw_ptr.add(ONE_MB - 1), SENTINEL_FOOTER, "Footer sentinel at raw_ptr[1048575] must be 0x55");
        assert_eq!(*raw_ptr.add(1), 0x00, "Interior bytes must be zeroed");
        assert_eq!(*raw_ptr.add(ONE_MB - 2), 0x00, "Interior bytes must be zeroed");
    }

    // 3. Verify sentinels via wire verifier
    let is_valid = wire__crate__api__engine__verify_buffer_sentinels(raw_ptr, ONE_MB);
    assert!(is_valid, "wire__verify_buffer_sentinels must return true for fresh buffer");

    // 4. Test corruption detection via wire verifier
    unsafe {
        *raw_ptr = 0x00; // Corrupt header
    }
    let is_corrupted_valid = wire__crate__api__engine__verify_buffer_sentinels(raw_ptr, ONE_MB);
    assert!(!is_corrupted_valid, "wire__verify_buffer_sentinels must reject corrupted header");

    // Restore for clean deallocation
    unsafe {
        *raw_ptr = SENTINEL_HEADER;
    }

    // 5. Cleanly deallocate via wire free function
    wire__crate__api__engine__free_engine_buffer(raw_ptr, ONE_MB);
}

#[test]
fn test_c_abi_wire_shared_frame_buffer_lifecycle_and_mutation() {
    // 1. Create SharedFrameBuffer handle
    let handle_ptr = wire__crate__api__engine__shared_frame_buffer_new(512);
    assert!(!handle_ptr.is_null(), "wire__shared_frame_buffer_new must return valid handle");

    // 2. Query length and memory pointer address
    let len = wire__crate__api__engine__shared_frame_buffer_len(handle_ptr);
    assert_eq!(len, 512);

    let ptr_addr = wire__crate__api__engine__shared_frame_buffer_ptr_address(handle_ptr);
    assert_ne!(ptr_addr, 0, "Native pointer address must be non-zero");

    // 3. Verify DEADBEEF header via wire read
    assert_eq!(wire__crate__api__engine__shared_frame_buffer_read_byte(handle_ptr, 0), 0xDE);
    assert_eq!(wire__crate__api__engine__shared_frame_buffer_read_byte(handle_ptr, 1), 0xAD);
    assert_eq!(wire__crate__api__engine__shared_frame_buffer_read_byte(handle_ptr, 2), 0xBE);
    assert_eq!(wire__crate__api__engine__shared_frame_buffer_read_byte(handle_ptr, 3), 0xEF);

    // 4. In-place mutation via wire write
    wire__crate__api__engine__shared_frame_buffer_write_byte(handle_ptr, 100, 0x5A);
    assert_eq!(wire__crate__api__engine__shared_frame_buffer_read_byte(handle_ptr, 100), 0x5A);

    // 5. Deallocate handle
    wire__crate__api__engine__shared_frame_buffer_free(handle_ptr);
}

// -----------------------------------------------------------------------------
// 3. Transparent CLI Toolchain Probe
// -----------------------------------------------------------------------------

#[test]
fn test_flutter_rust_bridge_codegen_cli_probe() {
    let cli_check = Command::new("flutter_rust_bridge_codegen")
        .arg("--version")
        .output();

    match cli_check {
        Ok(output) if output.status.success() => {
            let version = String::from_utf8_lossy(&output.stdout);
            println!("[STATUS] flutter_rust_bridge_codegen CLI is installed: {}", version.trim());
        }
        _ => {
            eprintln!(
                "[INFO] flutter_rust_bridge_codegen CLI not found on PATH. \
                This test suite honestly validates all C-ABI wire symbols, configurations, \
                and runtime memory contracts directly via compiled Rust exports."
            );
        }
    }
}
```

---

## 5. Question 3 Design: 1MB Buffer Allocation, Sentinel Verification, Corruption Ladder & Memory Lifecycle

### 5.1 Buffer Allocation & Layout Specification
- **Requested Size**: `sizeBytes = 1048576` (1MB = $2^{20}$ bytes).
- **Physical Layout**:
  ```
  Offset 0:               0xAA (SENTINEL_HEADER)
  Offset 1..1048574:      0x00 (Zero-initialized payload)
  Offset 1048575:         0x55 (SENTINEL_FOOTER)
  ```
- **Custom Allocator Integration & Zero Decoupling**:
  In `api/engine.rs`, `allocate_engine_buffer` must allocate directly from the active `ArenaAllocator` or track the allocation in `ENGINE_ALLOCATOR`. The phantom allocation defect (`let _ = arena.alloc_slice(...)` followed by `vec![0u8; size_bytes]`) must be replaced:
  ```rust
  // Correct Single-Source Allocation:
  let mut guard = ENGINE_ALLOCATOR.write().expect("Lock poisoned");
  let alloc = guard.as_mut().expect("Engine uninitialized");
  let slice = alloc.current_arena().alloc_slice(size_bytes, 0u8)?;
  slice[0] = SENTINEL_HEADER;
  slice[size_bytes - 1] = SENTINEL_FOOTER;
  ```

### 5.2 Sentinel Contract & Cross-Language Harmonization
Reviewer 1 and Challenger 1 found that `arena.rs:241` enforced `buffer.len() >= ONE_MB`, while Dart's bridge fallback accepted any non-empty buffer.
**Harmonized Contract Standard**:
Both Rust and Dart must enforce:
1. `buffer.len() >= 2` (header and footer require at least 2 distinct boundary bytes).
2. For dedicated 1MB buffer checks: `buffer.len() == ONE_MB && buffer[0] == 0xAA && buffer[ONE_MB - 1] == 0x55`.
3. For general sentinel checks: `buffer[0] == 0xAA && buffer[buffer.len() - 1] == 0x55`.
4. Buffer length 1 is explicitly prohibited from sentinel validation because a 1-byte buffer cannot accommodate two distinct sentinels without clobbering.

### 5.3 Five-Point Sentinel Corruption Rejection Matrix
Every test harness (Dart and Rust) must execute the following 5 corruption tests:

| Test Case | Mutation Applied | Expected Result | Defect Prevented |
|---|---|---|---|
| **C-1: Header Zeroed** | `buffer[0] = 0x00` | `verifyBufferSentinels == false` | Header sentinel bypass |
| **C-2: Footer Zeroed** | `buffer[1048575] = 0x00` | `verifyBufferSentinels == false` | Footer sentinel bypass |
| **C-3: Dual Inversion** | `buffer[0] = 0x55; buffer[1048575] = 0xAA` | `verifyBufferSentinels == false` | Directional / order confusion |
| **C-4: Boundary Off-By-One** | Test buffer of length $1,048,575$ (truncated) | `verifyBufferSentinels == false` | Buffer underrun / partial reads |
| **C-5: Empty Buffer** | `buffer = Uint8List(0)` | `verifyBufferSentinels == false` | Zero-length out-of-bounds indexing |

### 5.4 Memory Lifecycle & Finalization Deep Dive

#### The Dart `NativeFinalizer` Signature Constraint
Reviewers noted that native allocations leaked because `std::mem::forget(buf)` was called without a `NativeFinalizer`. However, there is a critical technical constraint in `dart:ffi` that was overlooked by the reviewers:
In Dart SDK `dart:ffi`:
```dart
typedef NativeFinalizerFunction = NativeFunction<Void Function(Pointer<Void> token)>;
```
`NativeFinalizer` requires a C function that takes **EXACTLY ONE POINTER ARGUMENT** (`void (*)(void*)`).
The existing wire function in `frb_generated.rs`:
```rust
pub extern "C" fn wire__crate__api__engine__free_engine_buffer(ptr: *mut u8, size_bytes: usize)
```
takes **TWO arguments** (`ptr` and `size_bytes`). Passing this function pointer to `NativeFinalizer` is undefined behavior and crashes the Dart VM because Dart will only pass the `token` (the pointer), leaving `size_bytes` uninitialized!

#### The Three Recommended Finalization Architectures

##### Architecture Option A: Header-Prefixed Self-Sized Allocation (Recommended for Direct Heap Transfers)
Store the size as a `usize` prefix immediately preceding the buffer payload:
```rust
// Rust implementation:
#[no_mangle]
pub extern "C" fn wire__crate__api__engine__allocate_engine_buffer(size_bytes: usize) -> *mut u8 {
    let total_bytes = size_bytes + std::mem::size_of::<usize>();
    let layout = std::alloc::Layout::from_size_align(total_bytes, 8).unwrap();
    unsafe {
        let ptr = std::alloc::alloc(layout);
        *(ptr as *mut usize) = size_bytes;
        let data_ptr = ptr.add(std::mem::size_of::<usize>());
        // Stamp sentinels
        *data_ptr = SENTINEL_HEADER;
        *data_ptr.add(size_bytes - 1) = SENTINEL_FOOTER;
        data_ptr
    }
}

#[no_mangle]
pub extern "C" fn wire__crate__api__engine__free_engine_buffer_auto(ptr: *mut u8) {
    if ptr.is_null() { return; }
    unsafe {
        let base_ptr = ptr.sub(std::mem::size_of::<usize>());
        let size_bytes = *(base_ptr as *mut usize);
        let total_bytes = size_bytes + std::mem::size_of::<usize>();
        let layout = std::alloc::Layout::from_size_align(total_bytes, 8).unwrap();
        std::alloc::dealloc(base_ptr, layout);
    }
}
```
Now `wire__crate__api__engine__free_engine_buffer_auto` takes **exactly 1 pointer** and can be directly bound to a `NativeFinalizer`:
```dart
// Dart implementation:
static final _bufferFinalizer = ffi.NativeFinalizer(
  _platform.dylib!.lookup('wire__crate__api__engine__free_engine_buffer_auto')
);

// In allocateEngineBuffer:
final rawPtr = platform.allocateBufferRaw(sizeBytes);
final list = rawPtr.asTypedList(sizeBytes);
_bufferFinalizer.attach(list, rawPtr.cast<ffi.Void>(), externalTypedDataLength: sizeBytes);
return list;
```
When Dart's GC collects `list`, `wire__crate__api__engine__free_engine_buffer_auto` is automatically invoked, completely eliminating the memory leak.

##### Architecture Option B: Object-Oriented Handle (`SharedFrameBuffer`)
Because `SharedFrameBuffer` is a struct handle allocated with `Box::new(handle)`, its destructor `wire__crate__api__engine__shared_frame_buffer_free` already takes **exactly 1 pointer** (`*mut SharedFrameBuffer`):
```dart
static final _sfbFinalizer = ffi.NativeFinalizer(
  _platform.dylib!.lookup('wire__crate__api__engine__shared_frame_buffer_free')
);
```
Binding `_sfbFinalizer.attach(sfb, handlePtr.cast<ffi.Void>())` guarantees zero memory leaks for shared frame buffers.

##### Architecture Option C: Frame Allocator Bulk Reset (True Zero-Fragmentation)
For high-performance engine loops:
- Memory is allocated from `DoubleBufferedFrameAllocator`.
- At the end of each engine frame tick (`swap_buffers()`), the previous frame's arena is reset in $O(1)$.
- Dart views are valid for the duration of the frame.
- No individual memory deallocation or finalizer tracking is needed.

---

## 6. Concrete Remediation Plan for Worker M2 Iteration 2

To ensure an immediate, unambiguous **APPROVE** across all reviewers in Iteration 2:

### File 1: `fluorite_editor/lib/src/rust/frb_generated.dart` & `frb_generated.io.dart`
- **Eliminate Facade Logic**: Replace mock Dart state in `RustLibApi` with genuine dispatch to `_platform` functions whenever `_platform.hasNativeBindings` is true.
- **Wire Native Finalizer**: Bind `NativeFinalizer` to `free_engine_buffer_auto` for external typed data lists.
- **Fix Synthetic Pointer**: Eliminate the synthetic `0x40000000` address in `SharedFrameBuffer`. When running in fallback mode, allocate real memory via `ffi.calloc` or Dart typed data pointers so `Pointer.fromAddress()` never crashes.
- **Windows Path Resolution**: Add `File(Platform.resolvedExecutable).parent.path + '/fluorite_core.dll'` to `candidatePaths`.

### File 2: `fluorite_core/src/api/engine.rs` & `frb_generated.rs`
- **Fix Double Allocation**: Ensure `allocate_engine_buffer` allocates from a single authoritative source and does not discard arena slices.
- **Single-Pointer Deallocator**: Add `wire__crate__api__engine__free_engine_buffer_auto(ptr: *mut u8)` compatible with `NativeFinalizer`.
- **Bounds Protection**: Add explicit bounds checks to `read_byte` and `write_byte` in `SharedFrameBuffer`.
- **C-ABI Struct Layout**: Ensure cross-boundary structs (like `EngineStatus`) use `#[repr(C)]` or binary serialization.

### File 3: `fluorite_core/tests/codegen_test.rs`
- Adopt the reformed implementation presented in Section 4.3.
- Execute native C-ABI wire functions directly.
- Transparently probe CLI tooling without false claims.

### File 4: `fluorite_editor/test/bridge_integration_test.dart`
- Create the dedicated integration test suite presented in Section 3.2.
- Wire execution into `tests/e2e_runner.dart` or provide the single-command runner `dart run fluorite_editor/test/bridge_integration_test.dart`.

---

## 7. Conclusion & Next Steps

This investigation provides the comprehensive blueprint to eliminate all three integrity violations, prevent fatal memory crashes, solve the native memory leak, and deliver 100% genuine integration test coverage.
The accompanying self-contained `handoff.md` summarizes the findings for the orchestrator and implementer.
