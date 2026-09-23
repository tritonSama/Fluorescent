// tests/challenger_1_m2_iter2_suite.dart
//
// Empirical Adversarial Challenge Suite for Milestone 2 Iteration 2:
// 1. Challenge 1MB Buffer Allocation: exact 1,048,576 bytes, 0xAA header, 0x55 footer, interior zeroes
// 2. Challenge Sentinel Verification & Corruption: header/footer corruption, inverted sentinels, truncated slices
// 3. Challenge 1-Byte Buffers: allocateEngineBuffer(1), ensure 0xAA is NOT clobbered by 0x55
// 4. Challenge Native Memory Deallocation: stress loops (100MB+), Finalizer / free_engine_buffer_auto contracts
// 5. Challenge Power-of-Two Buffer Sizes: 2^1 through 2^20 against verifyBufferSentinels & corruption

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../fluorite_editor/lib/src/rust/api/engine.dart';
import '../fluorite_editor/lib/src/rust/frb_generated.dart';

int _totalTests = 0;
int _passedTests = 0;
int _failedTests = 0;

void group(String name, void Function() body) {
  print('\n=== [CHALLENGE GROUP] $name ===');
  body();
}

void test(String name, void Function() body) {
  _totalTests++;
  try {
    body();
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
  } else if (actual != expected) {
    throw Exception('${reason ?? "Equality mismatch"}: expected <$expected>, got <$actual>');
  }
}

void main() {
  print('================================================================');
  print('  EMPIRICAL CHALLENGER 1 (M2-ITER2) — ADVERSARIAL TEST SUITE   ');
  print('================================================================');

  RustLib.resetForTesting();
  RustLib.initSync();

  final hasNative = RustLib.instance.platform?.hasNativeBindings ?? false;
  print('Linkage Mode: ${hasNative ? "NATIVE C-ABI (fluorite_core.dll)" : "MANAGED FALLBACK (_SystemAlloc via msvcrt.dll)"}');

  // ---------------------------------------------------------------------------
  // CHALLENGE 1: 1MB Buffer Allocation & Sentinel Integrity
  // ---------------------------------------------------------------------------
  group('1. 1MB Buffer Allocation & Sentinel Integrity', () {
    const int oneMb = 1024 * 1024; // 1,048,576 bytes

    test('allocateEngineBuffer(1048576) via int creates exact 1MB buffer', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      expect(buffer.length, oneMb, reason: 'Buffer size must be exactly 1,048,576 bytes');
    });

    test('allocateEngineBuffer via BigInt creates exact 1MB buffer', () {
      final buffer = allocateEngineBuffer(sizeBytes: BigInt.from(oneMb));
      expect(buffer.length, oneMb, reason: 'Buffer size must be exactly 1,048,576 bytes');
    });

    test('Header sentinel byte 0 is 0xAA and Footer sentinel byte 1048575 is 0x55', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      expect(buffer[0], 0xAA, reason: 'Byte 0 must be 0xAA (header sentinel)');
      expect(buffer[oneMb - 1], 0x55, reason: 'Byte 1048575 must be 0x55 (footer sentinel)');
    });

    test('All interior bytes across 1MB buffer are zeroed', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      expect(buffer[1], 0x00, reason: 'Byte 1 must be zero');
      expect(buffer[2], 0x00, reason: 'Byte 2 must be zero');
      expect(buffer[1024], 0x00, reason: 'Byte 1024 must be zero');
      expect(buffer[524288], 0x00, reason: 'Byte 524288 (midpoint) must be zero');
      expect(buffer[oneMb - 2], 0x00, reason: 'Byte 1048574 must be zero');

      // Thorough sample scan across 1MB buffer (every 4KB)
      for (int i = 1; i < oneMb - 1; i += 4096) {
        if (buffer[i] != 0x00) {
          throw Exception('Interior byte at offset $i was not 0x00: ${buffer[i]}');
        }
      }
    });

    test('Fresh 1MB buffer passes verifyBufferSentinels', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      final isValid = verifyBufferSentinels(buffer: buffer);
      expect(isValid, true, reason: 'Untouched 1MB buffer must pass verifyBufferSentinels');
    });
  });

  // ---------------------------------------------------------------------------
  // CHALLENGE 2: Sentinel Verification & Corruption
  // ---------------------------------------------------------------------------
  group('2. Sentinel Verification & Corruption Matrix', () {
    const int oneMb = 1024 * 1024;

    test('Corrupting byte 0 (0xAA -> 0x00) strictly fails verifyBufferSentinels', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      final corrupted = Uint8List.fromList(buffer);
      corrupted[0] = 0x00;
      expect(verifyBufferSentinels(buffer: corrupted), false);
    });

    test('Corrupting byte 0 (0xAA -> 0xFF, 0x55, 0xAB) strictly fails verifyBufferSentinels', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      for (final badVal in [0xFF, 0x55, 0xAB, 0x01]) {
        final corrupted = Uint8List.fromList(buffer);
        corrupted[0] = badVal;
        expect(verifyBufferSentinels(buffer: corrupted), false,
            reason: 'Corrupted header 0x${badVal.toRadixString(16)} must fail');
      }
    });

    test('Corrupting byte 1048575 (0x55 -> 0x00) strictly fails verifyBufferSentinels', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      final corrupted = Uint8List.fromList(buffer);
      corrupted[oneMb - 1] = 0x00;
      expect(verifyBufferSentinels(buffer: corrupted), false);
    });

    test('Corrupting byte 1048575 (0x55 -> 0xFF, 0xAA, 0x54) strictly fails verifyBufferSentinels', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      for (final badVal in [0xFF, 0xAA, 0x54, 0x10]) {
        final corrupted = Uint8List.fromList(buffer);
        corrupted[oneMb - 1] = badVal;
        expect(verifyBufferSentinels(buffer: corrupted), false,
            reason: 'Corrupted footer 0x${badVal.toRadixString(16)} must fail');
      }
    });

    test('Dual corruption of header AND footer strictly fails verifyBufferSentinels', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      final corrupted = Uint8List.fromList(buffer);
      corrupted[0] = 0x00;
      corrupted[oneMb - 1] = 0x00;
      expect(verifyBufferSentinels(buffer: corrupted), false);
    });

    test('Inverted sentinels (0x55 header, 0xAA footer) strictly fail verifyBufferSentinels', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      final corrupted = Uint8List.fromList(buffer);
      corrupted[0] = 0x55;
      corrupted[oneMb - 1] = 0xAA;
      expect(verifyBufferSentinels(buffer: corrupted), false);
    });

    test('Truncated slice (0..1048575, missing footer) strictly fails verifyBufferSentinels', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      final truncated = buffer.sublist(0, oneMb - 1);
      expect(truncated.length, oneMb - 1);
      expect(verifyBufferSentinels(buffer: truncated), false,
          reason: 'Truncated slice ending at 0x00 must fail verification');
    });

    test('Truncated slice (1..1048576, missing header) strictly fails verifyBufferSentinels', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      final truncated = buffer.sublist(1, oneMb);
      expect(truncated.length, oneMb - 1);
      expect(verifyBufferSentinels(buffer: truncated), false,
          reason: 'Truncated slice starting at 0x00 must fail verification');
    });

    test('Interior subslice (1..1048575, neither header nor footer) strictly fails', () {
      final buffer = allocateEngineBuffer(sizeBytes: oneMb);
      final truncated = buffer.sublist(1, oneMb - 1);
      expect(verifyBufferSentinels(buffer: truncated), false);
    });

    test('Empty slice (0 bytes) strictly fails verifyBufferSentinels', () {
      expect(verifyBufferSentinels(buffer: Uint8List(0)), false);
      expect(verifyBufferSentinels(buffer: <int>[]), false);
    });

    test('Single-byte slice strictly fails verifyBufferSentinels', () {
      expect(verifyBufferSentinels(buffer: Uint8List.fromList([0xAA])), false);
      expect(verifyBufferSentinels(buffer: Uint8List.fromList([0x55])), false);
    });

    test('Two-byte minimal slice sentinel contracts', () {
      expect(verifyBufferSentinels(buffer: Uint8List.fromList([0xAA, 0x55])), true);
      expect(verifyBufferSentinels(buffer: Uint8List.fromList([0xAA, 0x00])), false);
      expect(verifyBufferSentinels(buffer: Uint8List.fromList([0x00, 0x55])), false);
      expect(verifyBufferSentinels(buffer: Uint8List.fromList([0x55, 0xAA])), false);
    });
  });

  // ---------------------------------------------------------------------------
  // CHALLENGE 3: 1-Byte Buffers & Sentinel Non-Clobbering Guard
  // ---------------------------------------------------------------------------
  group('3. 1-Byte Buffers & Sentinel Non-Clobbering Guard', () {
    test('allocateEngineBuffer(1) allocates exactly 1 byte', () {
      final buffer = allocateEngineBuffer(sizeBytes: 1);
      expect(buffer.length, 1, reason: 'Buffer size must be 1');
    });

    test('allocateEngineBuffer(1) sets buffer[0] == 0xAA and is NOT clobbered by 0x55', () {
      final buffer = allocateEngineBuffer(sizeBytes: 1);
      // In Gate 1 defect D-02: buffer[size - 1] = 0x55 overwrote buffer[0] with 0x55.
      // In M2-Iter2: buffer[0] MUST be 0xAA and MUST NOT be 0x55!
      expect(buffer[0], 0xAA, reason: 'buffer[0] must be 0xAA (NOT clobbered by 0x55)');
      if (buffer[0] == 0x55) {
        throw Exception('REGRESSION D-02: 1-byte buffer header was clobbered by 0x55 footer!');
      }
    });

    test('verifyBufferSentinels rejects 1-byte buffer (cannot satisfy dual sentinels)', () {
      final buffer = allocateEngineBuffer(sizeBytes: 1);
      // Length 1 cannot satisfy both 0xAA header AND 0x55 footer simultaneously
      expect(verifyBufferSentinels(buffer: buffer), false,
          reason: '1-byte buffer cannot possess two distinct boundary sentinels');
    });

    test('allocateEngineBuffer(0) returns empty buffer without exception', () {
      final buffer = allocateEngineBuffer(sizeBytes: 0);
      expect(buffer.length, 0);
      expect(verifyBufferSentinels(buffer: buffer), false);
    });
  });

  // ---------------------------------------------------------------------------
  // CHALLENGE 4: Native Memory Deallocation & Stress-Testing Allocation Loops
  // ---------------------------------------------------------------------------
  group('4. Native Memory Deallocation & Stress-Testing Loops', () {
    test('Stress Loop: 100 consecutive 1MB allocations (100MB cumulative)', () {
      RustLib.resetForTesting();
      startEngine(config: null);

      for (int i = 0; i < 100; i++) {
        final buf = allocateEngineBuffer(sizeBytes: 1024 * 1024);
        expect(buf.length, 1024 * 1024);
        expect(buf[0], 0xAA);
        expect(buf[1048575], 0x55);
        expect(verifyBufferSentinels(buffer: buf), true);
      }
    });

    test('Stress Loop: 1,000 rapid small buffer allocations (64KB each = 64MB cumulative)', () {
      for (int i = 0; i < 1000; i++) {
        final buf = allocateEngineBuffer(sizeBytes: 65536);
        expect(buf.length, 65536);
        expect(buf[0], 0xAA);
        expect(buf[65535], 0x55);
        expect(verifyBufferSentinels(buffer: buf), true);
      }
    });

    test('Direct _SystemAlloc verification: real OS heap allocation and free', () {
      // Test the underlying system allocator that backs fallback mode
      final sysAlloc = _SystemAlloc.instance;
      if (sysAlloc.isAvailable) {
        const int allocSize = 1048576; // 1MB
        final ptr = sysAlloc.allocate(allocSize);
        if (ptr == null || ptr == ffi.nullptr) {
          throw Exception('_SystemAlloc.allocate(1MB) returned null or nullptr');
        }

        // Verify write and read to allocated memory
        final view = ptr.asTypedList(allocSize);
        view[0] = 0xAA;
        view[allocSize - 1] = 0x55;
        expect(view[0], 0xAA);
        expect(view[allocSize - 1], 0x55);

        // Verify freeFnPtr is available for NativeFinalizer
        expect(sysAlloc.freeFnPtr != ffi.nullptr, true, reason: 'freeFnPtr must be non-null');

        // Free the memory cleanly
        sysAlloc.free(ptr);
      } else {
        print('    [INFO] _SystemAlloc not available on this platform (using standard Dart VM)');
      }
    });

    test('SharedFrameBuffer allocation, dereferencing, mutation, and safe cleanup', () {
      for (int i = 0; i < 50; i++) {
        final sfb = SharedFrameBuffer(sizeBytes: 4096);
        expect(sfb.len(), 4096);
        expect(sfb.readByte(offset: 0), 0xDE);
        expect(sfb.readByte(offset: 1), 0xAD);
        expect(sfb.readByte(offset: 2), 0xBE);
        expect(sfb.readByte(offset: 3), 0xEF);

        final addr = sfb.ptrAddress();
        expect(addr != 0, true);
        expect(addr != 0x40000000, true, reason: 'ptrAddress must not be synthetic 0x40000000');

        // Verify dereferencing without crash
        final ptr = ffi.Pointer<ffi.Uint8>.fromAddress(addr);
        final list = ptr.asTypedList(4);
        expect(list[0], 0xDE);
        expect(list[3], 0xEF);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // CHALLENGE 5: Power-of-Two Buffer Sizes Ladder (2^1 to 2^20)
  // ---------------------------------------------------------------------------
  group('5. Power-of-Two Buffer Sizes Ladder (2^1 through 2^20)', () {
    // Powers of two: 2^1 (2 bytes) to 2^20 (1,048,576 bytes)
    for (int exp = 1; exp <= 20; exp++) {
      final size = 1 << exp; // 2^exp

      test('Buffer size 2^$exp ($size bytes): allocation, sentinels, and corruption detection', () {
        final buffer = allocateEngineBuffer(sizeBytes: size);
        expect(buffer.length, size, reason: 'Length must be exactly $size bytes');

        // Sentinels
        expect(buffer[0], 0xAA, reason: 'Header sentinel must be 0xAA');
        expect(buffer[size - 1], 0x55, reason: 'Footer sentinel must be 0x55');

        // Sentinel verification passes on fresh buffer
        expect(verifyBufferSentinels(buffer: buffer), true,
            reason: 'Untouched buffer of size $size must pass verifyBufferSentinels');

        // Corrupt header
        final corruptHeader = Uint8List.fromList(buffer);
        corruptHeader[0] = 0x00;
        expect(verifyBufferSentinels(buffer: corruptHeader), false,
            reason: 'Corrupted header on size $size must fail');

        // Corrupt footer
        final corruptFooter = Uint8List.fromList(buffer);
        corruptFooter[size - 1] = 0x00;
        expect(verifyBufferSentinels(buffer: corruptFooter), false,
            reason: 'Corrupted footer on size $size must fail');

        // Inverted sentinels
        final corruptInverted = Uint8List.fromList(buffer);
        corruptInverted[0] = 0x55;
        corruptInverted[size - 1] = 0xAA;
        expect(verifyBufferSentinels(buffer: corruptInverted), false,
            reason: 'Inverted sentinels on size $size must fail');

        // Payload mutation does NOT invalidate sentinels (if size > 2)
        if (size > 2) {
          buffer[1] = 0x99;
          expect(verifyBufferSentinels(buffer: buffer), true,
              reason: 'Payload mutation must not invalidate sentinels');
        }
      });
    }
  });

  // ---------------------------------------------------------------------------
  // SUMMARY
  // ---------------------------------------------------------------------------
  print('\n================================================================');
  print('EMPIRICAL CHALLENGER 1 (M2-ITER2) SUMMARY:');
  print('  Total Tests Executed: $_totalTests');
  print('  Passed:               $_passedTests');
  print('  Failed:               $_failedTests');
  print('================================================================\n');

  if (_failedTests > 0) {
    exit(1);
  }
}
