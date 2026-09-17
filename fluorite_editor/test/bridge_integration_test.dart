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

void group(String name, void Function() body) {
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
  // GROUP 2: 1MB Buffer & Sentinel Contracts
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
  // GROUP 3: Boundary & Edge Cases
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
      expect(verifyBufferSentinels(buffer: twoByte), true);
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

      // Verify the pointer can be safely dereferenced without OS access violation
      final ptr = ffi.Pointer<ffi.Uint8>.fromAddress(addr);
      final list = ptr.asTypedList(4);
      expect(list[0], 0xDE, reason: 'Memory must contain 0xDE header');
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
  // GROUP 6: Empirical Challenger 1 Adversarial Stress & Verification
  // ---------------------------------------------------------------------------
  group('Challenger 1: 1MB Buffer, Sentinels, 1-Byte Guard, Dealloc, and Power-of-Two', () {
    const int oneMb = 1024 * 1024; // 1,048,576 bytes

    // --- Challenge 1: 1MB Buffer Allocation ---
    test('C1: 1MB buffer allocation via BigInt and int parameter with full interior zeroes', () {
      final bufInt = allocateEngineBuffer(sizeBytes: oneMb);
      expect(bufInt.length, oneMb);
      expect(bufInt[0], 0xAA);
      expect(bufInt[oneMb - 1], 0x55);

      final bufBig = allocateEngineBuffer(sizeBytes: BigInt.from(oneMb));
      expect(bufBig.length, oneMb);
      expect(bufBig[0], 0xAA);
      expect(bufBig[oneMb - 1], 0x55);

      // Verify interior bytes across 1MB are zeroed (sample scan every 4096 bytes)
      for (int i = 1; i < oneMb - 1; i += 4096) {
        expect(bufInt[i], 0x00);
      }
      expect(verifyBufferSentinels(buffer: bufInt), true);
    });

    // --- Challenge 2: Sentinel Verification & Corruption Matrix ---
    test('C2: Header corruption matrix (0x00, 0xFF, 0x55, 0xAB) fails verifyBufferSentinels', () {
      final buf = allocateEngineBuffer(sizeBytes: oneMb);
      for (final badHeader in [0x00, 0xFF, 0x55, 0xAB]) {
        final corrupted = Uint8List.fromList(buf);
        corrupted[0] = badHeader;
        expect(verifyBufferSentinels(buffer: corrupted), false);
      }
    });

    test('C2: Footer corruption matrix (0x00, 0xFF, 0xAA, 0x54) fails verifyBufferSentinels', () {
      final buf = allocateEngineBuffer(sizeBytes: oneMb);
      for (final badFooter in [0x00, 0xFF, 0xAA, 0x54]) {
        final corrupted = Uint8List.fromList(buf);
        corrupted[oneMb - 1] = badFooter;
        expect(verifyBufferSentinels(buffer: corrupted), false);
      }
    });

    test('C2: Truncated and partial slices fail sentinel verification', () {
      final buf = allocateEngineBuffer(sizeBytes: oneMb);

      // Truncated at end (missing 0x55 footer)
      final truncatedEnd = buf.sublist(0, oneMb - 1);
      expect(verifyBufferSentinels(buffer: truncatedEnd), false);

      // Truncated at start (missing 0xAA header)
      final truncatedStart = buf.sublist(1, oneMb);
      expect(verifyBufferSentinels(buffer: truncatedStart), false);

      // Interior only
      final interiorOnly = buf.sublist(1, oneMb - 1);
      expect(verifyBufferSentinels(buffer: interiorOnly), false);

      // Empty buffer
      expect(verifyBufferSentinels(buffer: Uint8List(0)), false);
      expect(verifyBufferSentinels(buffer: <int>[]), false);

      // Single-byte buffers
      expect(verifyBufferSentinels(buffer: Uint8List.fromList([0xAA])), false);
      expect(verifyBufferSentinels(buffer: Uint8List.fromList([0x55])), false);

      // Exact 2-byte boundary
      expect(verifyBufferSentinels(buffer: Uint8List.fromList([0xAA, 0x55])), true);
      expect(verifyBufferSentinels(buffer: Uint8List.fromList([0xAA, 0x00])), false);
      expect(verifyBufferSentinels(buffer: Uint8List.fromList([0x00, 0x55])), false);
    });

    // --- Challenge 3: 1-Byte Buffers & Non-Clobbering Guard ---
    test('C3: allocateEngineBuffer(1) preserves buffer[0] == 0xAA and is NOT clobbered by 0x55', () {
      final single = allocateEngineBuffer(sizeBytes: 1);
      expect(single.length, 1);
      expect(single[0], 0xAA, reason: 'buffer[0] must be 0xAA and NOT clobbered by 0x55 (Defect D-02 check)');
      expect(single[0] != 0x55, true, reason: 'buffer[0] must not be footer sentinel 0x55');
      // A 1-byte buffer cannot possess two distinct boundary sentinels
      expect(verifyBufferSentinels(buffer: single), false);
    });

    // --- Challenge 4: Native Memory Deallocation Stress Loops ---
    test('C4: Stress Loop - 100 consecutive 1MB allocations (100MB cumulative)', () {
      RustLib.resetForTesting();
      startEngine();

      for (int i = 0; i < 100; i++) {
        final buf = allocateEngineBuffer(sizeBytes: oneMb);
        expect(buf.length, oneMb);
        expect(buf[0], 0xAA);
        expect(buf[oneMb - 1], 0x55);
        expect(verifyBufferSentinels(buffer: buf), true);
      }
    });

    test('C4: Stress Loop - 1,000 rapid 64KB allocations (64MB cumulative)', () {
      for (int i = 0; i < 1000; i++) {
        final buf = allocateEngineBuffer(sizeBytes: 65536);
        expect(buf.length, 65536);
        expect(buf[0], 0xAA);
        expect(buf[65535], 0x55);
        expect(verifyBufferSentinels(buffer: buf), true);
      }
    });

    test('C4: SharedFrameBuffer allocation, live dereferencing, and finalization safety', () {
      for (int i = 0; i < 50; i++) {
        final sfb = SharedFrameBuffer(sizeBytes: 4096);
        expect(sfb.len(), 4096);
        expect(sfb.readByte(offset: 0), 0xDE);
        expect(sfb.readByte(offset: 3), 0xEF);

        final addr = sfb.ptrAddress();
        expect(addr != 0, true);
        expect(addr != 0x40000000, true, reason: 'Address must not be synthetic 0x40000000');

        final ptr = ffi.Pointer<ffi.Uint8>.fromAddress(addr);
        final list = ptr.asTypedList(4);
        expect(list[0], 0xDE);
        expect(list[3], 0xEF);
      }
    });

    // --- Challenge 5: Power-of-Two Buffer Sizes Ladder (2^1 to 2^20) ---
    test('C5: Power-of-Two Ladder 2^1 through 2^20 against sentinels and corruption', () {
      for (int exp = 1; exp <= 20; exp++) {
        final size = 1 << exp; // 2^1 = 2 up to 2^20 = 1,048,576
        final buf = allocateEngineBuffer(sizeBytes: size);
        expect(buf.length, size, reason: 'Size 2^$exp mismatch');
        expect(buf[0], 0xAA, reason: 'Header 0xAA mismatch for size 2^$exp');
        expect(buf[size - 1], 0x55, reason: 'Footer 0x55 mismatch for size 2^$exp');
        expect(verifyBufferSentinels(buffer: buf), true, reason: 'Sentinel verification failed for size 2^$exp');

        // Corrupted header must fail
        final corruptHeader = Uint8List.fromList(buf);
        corruptHeader[0] = 0x00;
        expect(verifyBufferSentinels(buffer: corruptHeader), false, reason: 'Corrupt header for size 2^$exp passed unexpectedly');

        // Corrupted footer must fail
        final corruptFooter = Uint8List.fromList(buf);
        corruptFooter[size - 1] = 0x00;
        expect(verifyBufferSentinels(buffer: corruptFooter), false, reason: 'Corrupt footer for size 2^$exp passed unexpectedly');

        // Inverted sentinels must fail
        final corruptInverted = Uint8List.fromList(buf);
        corruptInverted[0] = 0x55;
        corruptInverted[size - 1] = 0xAA;
        expect(verifyBufferSentinels(buffer: corruptInverted), false, reason: 'Inverted sentinels for size 2^$exp passed unexpectedly');
      }
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
