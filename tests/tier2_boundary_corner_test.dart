// tests/tier2_boundary_corner_test.dart
//
// Tier 2: Boundary & Corner Cases (>=5 tests per feature)
// Validates extreme edge cases: 0 bytes, 1 byte, exact 1MB, power-of-two boundaries,
// alignment boundaries 1..64, and capacity saturation.

import 'dart:typed_data';
import 'e2e_test_harness.dart';
import 'fluorite_bridge_model.dart';

void registerTier2Tests() {
  // ---------------------------------------------------------------------------
  // Feature 1: Custom Allocators Boundaries
  // ---------------------------------------------------------------------------
  TestHarness.group('Tier 2 - Feature 1: Allocator Boundaries', () {
    TestHarness.test('test_t2_f1_alloc_zero_bytes', () {
      final arena = ArenaAllocatorModel(1024);
      final slice = arena.allocSlice(0, 0);
      expect(slice.length, equals(0));
      expect(arena.allocatedBytes, equals(0));

      final addr = arena.allocRaw(0, 8);
      expect(addr, greaterThan(0));
      expect(arena.allocatedBytes, equals(0));
    });

    TestHarness.test('test_t2_f1_alloc_single_byte', () {
      final arena = ArenaAllocatorModel(1024);
      final slice = arena.allocSlice(1, 0xFF);
      expect(slice.length, equals(1));
      expect(slice[0], equals(0xFF));
      expect(arena.allocatedBytes, greaterThanOrEqualTo(1));
    });

    TestHarness.test('test_t2_f1_alloc_exact_capacity', () {
      const cap = 256;
      final arena = ArenaAllocatorModel(cap);
      // Raw allocate exact capacity with alignment 1
      final addr = arena.allocRaw(cap, 1);
      expect(addr, equals(arena.baseAddress));
      expect(arena.allocatedBytes, equals(cap));
      expect(arena.remainingBytes, equals(0));

      // Any subsequent allocation must fail with OutOfMemory
      expect(() => arena.allocRaw(1, 1), throwsA());
    });

    TestHarness.test('test_t2_f1_alloc_capacity_overflow', () {
      const cap = 128;
      final arena = ArenaAllocatorModel(cap);
      expect(() => arena.allocRaw(cap + 1, 1), throwsA());
      expect(arena.allocatedBytes, equals(0), reason: 'Failed allocation must not advance offset');
    });

    TestHarness.test('test_t2_f1_alignment_ladder_extremes', () {
      final arena = ArenaAllocatorModel(1024 * 1024);
      final alignments = [1, 2, 4, 8, 16, 32, 64];
      final oddSizes = [3, 7, 13, 19, 31, 47, 63];

      for (int i = 0; i < alignments.length; i++) {
        final align = alignments[i];
        final size = oddSizes[i];
        final addr = arena.allocRaw(size, align);
        expect(addr % align, equals(0),
            reason: 'Odd size $size with align $align yielded unaligned addr: 0x${addr.toRadixString(16)}');
      }
    });

    TestHarness.test('test_t2_f1_repeated_empty_resets', () {
      final frameAlloc = DoubleBufferedFrameAllocatorModel(1024);
      for (int i = 0; i < 20; i++) {
        frameAlloc.swapBuffers();
        expect(frameAlloc.currentArena.allocatedBytes, equals(0));
      }
      expect(frameAlloc.frameIndex, equals(20));
    });
  });

  // ---------------------------------------------------------------------------
  // Feature 2: Zero-Copy Continuous Buffers Boundaries
  // ---------------------------------------------------------------------------
  TestHarness.group('Tier 2 - Feature 2: Zero-Copy Buffer Boundaries', () {
    TestHarness.test('test_t2_f2_zero_byte_buffer', () {
      final buf = allocateEngineBuffer(0);
      expect(buf.length, equals(0));
      expect(verifyBufferSentinels(buf), isFalse, reason: 'Empty buffer cannot satisfy sentinels');
    });

    TestHarness.test('test_t2_f2_single_byte_buffer', () {
      final buf = allocateEngineBuffer(1);
      expect(buf.length, equals(1));
      // For size 1, byte 0 is set to 0xAA then overwritten by 0x55 or vice versa
      expect(buf[0], inRange(0x55, 0xAA));
    });

    TestHarness.test('test_t2_f2_exact_1mb_boundary', () {
      const oneMb = 1024 * 1024;
      final buf = allocateEngineBuffer(oneMb);

      expect(buf.length, equals(oneMb));
      expect(buf[0], equals(0xAA));
      expect(buf[oneMb - 1], equals(0x55));
      expect(buf[oneMb - 2], equals(0x00));

      // Boundary assertion
      expect(() => buf[oneMb], throwsA());
    });

    TestHarness.test('test_t2_f2_power_of_two_sizes', () {
      // Test powers of 2 from 2^0 (1) to 2^20 (1,048,576)
      for (int p = 1; p <= 20; p++) {
        final size = 1 << p;
        final buf = allocateEngineBuffer(size);
        expect(buf.length, equals(size));
        expect(buf[0], equals(0xAA));
        expect(buf[size - 1], equals(0x55));
        expect(verifyBufferSentinels(buf), isTrue);
      }
    });

    TestHarness.test('test_t2_f2_alignment_boundary_at_64', () {
      final arena = ArenaAllocatorModel(1024 * 1024, simulatedBaseAddress: 0x40000000);
      // Ensure large allocations respect 64-byte hardware cache line boundary
      final addr = arena.allocRaw(1024 * 1024, 64);
      expect(addr % 64, equals(0));
    });
  });

  // ---------------------------------------------------------------------------
  // Feature 3: Zero-Copy FFI Bridge Boundaries
  // ---------------------------------------------------------------------------
  TestHarness.group('Tier 2 - Feature 3: FFI Bridge Boundaries', () {
    TestHarness.test('test_t2_f3_buffer_size_zero', () {
      final buf = allocateEngineBuffer(0);
      expect(buf.length, equals(0));
      final mutated = writeBufferPattern(buf, 0xEE);
      expect(mutated.length, equals(0));
    });

    TestHarness.test('test_t2_f3_buffer_size_one', () {
      final buf = allocateEngineBuffer(1);
      expect(buf.length, equals(1));
      writeBufferPattern(buf, 0x99);
      expect(buf[0], equals(0x99));
    });

    TestHarness.test('test_t2_f3_buffer_large_stress', () {
      const sixteenMb = 16 * 1024 * 1024;
      final buf = allocateEngineBuffer(sixteenMb);
      expect(buf.length, equals(sixteenMb));
      expect(verifyBufferSentinels(buf), isTrue);
    });

    TestHarness.test('test_t2_f3_repeated_start_engine', () async {
      final controller = EngineControllerModel();
      await controller.startEngine();
      expect(controller.state, equals(EngineState.running));

      // Idempotent secondary call
      await controller.startEngine();
      expect(controller.state, equals(EngineState.running));
      expect(controller.status!.isInitialized, isTrue);
    });

    TestHarness.test('test_t2_f3_corrupted_sentinel_rejection', () {
      final buf = allocateEngineBuffer(1024);
      expect(verifyBufferSentinels(buf), isTrue);

      // Corrupt both ends
      buf[0] = 0x12;
      buf[1023] = 0x34;
      expect(verifyBufferSentinels(buf), isFalse);

      // Restore header only
      buf[0] = 0xAA;
      expect(verifyBufferSentinels(buf), isFalse);

      // Restore footer
      buf[1023] = 0x55;
      expect(verifyBufferSentinels(buf), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Feature 4: Flutter Desktop Editor & Controller Boundaries
  // ---------------------------------------------------------------------------
  TestHarness.group('Tier 2 - Feature 4: Desktop Editor Boundaries', () {
    TestHarness.test('test_t2_f4_allocate_before_start', () async {
      final controller = EngineControllerModel();
      expect(controller.state, equals(EngineState.uninitialized));

      // Calling allocate1MB auto-starts engine
      final buf = await controller.allocate1MB();
      expect(controller.state, equals(EngineState.running));
      expect(buf.length, equals(1024 * 1024));
    });

    TestHarness.test('test_t2_f4_repeated_allocations', () async {
      final controller = EngineControllerModel();
      for (int i = 0; i < 10; i++) {
        final buf = await controller.allocate1MB();
        expect(buf.length, equals(1024 * 1024));
        expect(controller.activeBuffer, isNotNull);
      }
    });

    TestHarness.test('test_t2_f4_latency_budget_threshold', () async {
      final controller = EngineControllerModel();
      await controller.allocate1MB();
      // Latency must be strictly under 50,000 microseconds (50ms)
      expect(controller.allocationLatencyMicros, lessThan(50000));
    });

    TestHarness.test('test_t2_f4_hex_viewer_offset_clamping', () {
      final buf = allocateEngineBuffer(64);
      // Request offset 1000 on a 64-byte buffer
      final lines = formatHexInspector(buf, offset: 1000, length: 16);
      expect(lines.isEmpty, isTrue);
    });

    TestHarness.test('test_t2_f4_hex_viewer_empty_buffer', () {
      final lines = formatHexInspector(Uint8List(0));
      expect(lines.length, equals(1));
      expect(lines[0], equals('<Empty Buffer>'));
    });
  });
}
