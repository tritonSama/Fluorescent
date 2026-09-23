// tests/tier1_feature_coverage_test.dart
//
// Tier 1: Feature Coverage (>=5 tests per feature)
// Validates each feature (Allocators, Zero-Copy Buffers, FFI Bridge, Desktop Editor) in isolation.

import 'dart:typed_data';
import 'e2e_test_harness.dart';
import 'fluorite_bridge_model.dart';

void registerTier1Tests() {
  // ---------------------------------------------------------------------------
  // Feature 1: Custom Memory Allocators (ArenaAllocator & FrameAllocator)
  // ---------------------------------------------------------------------------
  TestHarness.group('Tier 1 - Feature 1: Custom Memory Allocators', () {
    TestHarness.test('test_t1_f1_arena_alloc_slices', () {
      final arena = ArenaAllocatorModel(1024 * 1024); // 1 MB Arena
      final slice1 = arena.allocSlice(256, 0x11);
      final slice2 = arena.allocSlice(512, 0x22);

      expect(slice1.length, equals(256));
      expect(slice2.length, equals(512));
      expect(slice1[0], equals(0x11));
      expect(slice1[255], equals(0x11));
      expect(slice2[0], equals(0x22));
      expect(slice2[511], equals(0x22));
      expect(arena.allocatedBytes, greaterThanOrEqualTo(256 + 512));
      expect(arena.allocationCount, equals(2));
    });

    TestHarness.test('test_t1_f1_arena_bulk_reset', () {
      final arena = ArenaAllocatorModel(1024);
      arena.allocSlice(512, 0xAA);
      expect(arena.allocatedBytes, greaterThanOrEqualTo(512));

      // O(1) bulk reset
      arena.reset();
      expect(arena.allocatedBytes, equals(0));
      expect(arena.allocationCount, equals(0));

      // Reallocate from base offset
      final sliceAfter = arena.allocSlice(256, 0xBB);
      expect(sliceAfter.length, equals(256));
      expect(sliceAfter[0], equals(0xBB));
      expect(arena.allocatedBytes, greaterThanOrEqualTo(256));
    });

    TestHarness.test('test_t1_f1_arena_alignment_padding', () {
      final arena = ArenaAllocatorModel(1024 * 1024);
      final alignments = [1, 2, 4, 8, 16, 32, 64];

      for (final align in alignments) {
        // Allocate odd size with specific alignment
        final addr = arena.allocRaw(17, align);
        expect(addr % align, equals(0),
            reason: 'Address 0x${addr.toRadixString(16)} must be aligned to $align bytes');
      }
    });

    TestHarness.test('test_t1_f1_frame_allocator_ping_pong', () {
      final frameAlloc = DoubleBufferedFrameAllocatorModel(64 * 1024);

      // Frame 0: allocate in current arena
      final f0Arena = frameAlloc.currentArena;
      final f0Slice = f0Arena.allocSlice(1024, 0x01);
      expect(f0Slice[0], equals(0x01));
      expect(frameAlloc.frameIndex, equals(0));

      // Swap to Frame 1
      frameAlloc.swapBuffers();
      expect(frameAlloc.frameIndex, equals(1));
      final f1Arena = frameAlloc.currentArena;
      final f1Slice = f1Arena.allocSlice(2048, 0x02);
      expect(f1Slice[0], equals(0x02));

      // Frame 0 data remains intact in previous arena
      expect(frameAlloc.previousArena.allocatedBytes, greaterThanOrEqualTo(1024));
    });

    TestHarness.test('test_t1_f1_allocator_metrics_tracking', () {
      const capacity = 10000;
      final arena = ArenaAllocatorModel(capacity);
      expect(arena.capacityBytes, equals(capacity));
      expect(arena.remainingBytes, equals(capacity));
      expect(arena.allocatedBytes, equals(0));
      expect(arena.peakUsage, equals(0));

      arena.allocSlice(1000, 0);
      expect(arena.allocatedBytes, greaterThanOrEqualTo(1000));
      expect(arena.remainingBytes, lessThanOrEqualTo(capacity - 1000));
      expect(arena.peakUsage, greaterThanOrEqualTo(1000));
    });
  });

  // ---------------------------------------------------------------------------
  // Feature 2: Zero-Copy Continuous Buffers
  // ---------------------------------------------------------------------------
  TestHarness.group('Tier 1 - Feature 2: Zero-Copy Continuous Buffers', () {
    TestHarness.test('test_t1_f2_1mb_buffer_allocation', () {
      const oneMb = 1024 * 1024;
      final buffer = allocateEngineBuffer(oneMb);

      expect(buffer.length, equals(oneMb));
      expect(buffer, isNotNull);
      expect(buffer is Uint8List, isTrue);
    });

    TestHarness.test('test_t1_f2_sentinel_verification', () {
      const oneMb = 1024 * 1024;
      final buffer = allocateEngineBuffer(oneMb);

      expect(buffer[0], equals(0xAA), reason: 'Header sentinel must be 0xAA');
      expect(buffer[oneMb - 1], equals(0x55), reason: 'Footer sentinel must be 0x55');
      expect(verifyBufferSentinels(buffer), isTrue);
    });

    TestHarness.test('test_t1_f2_in_place_mutation', () {
      const size = 1024;
      final buffer = allocateEngineBuffer(size);
      writeBufferPattern(buffer, 0x77);

      for (int i = 0; i < size; i++) {
        expect(buffer[i], equals(0x77));
      }
    });

    TestHarness.test('test_t1_f2_pointer_address_sharing', () {
      final sharedBuffer = SharedFrameBufferModel(1024 * 1024);
      expect(sharedBuffer.len, equals(1024 * 1024));
      expect(sharedBuffer.ptrAddress, greaterThan(0));
      expect(sharedBuffer.ptrAddress % 8, equals(0), reason: 'Base address must be aligned');
    });

    TestHarness.test('test_t1_f2_typed_data_view_mapping', () {
      final sharedBuffer = SharedFrameBufferModel(1024);
      // View into the buffer without copying
      final view = Uint8List.sublistView(sharedBuffer.data, 0, 512);

      // Verify header pattern
      expect(view[0], equals(0xDE));
      expect(view[1], equals(0xAD));
      expect(view[2], equals(0xBE));
      expect(view[3], equals(0xEF));

      // Mutate view in place
      view[10] = 0x42;
      expect(sharedBuffer.data[10], equals(0x42));
    });
  });

  // ---------------------------------------------------------------------------
  // Feature 3: Zero-Copy FFI Bridge
  // ---------------------------------------------------------------------------
  TestHarness.group('Tier 1 - Feature 3: Zero-Copy FFI Bridge', () {
    TestHarness.test('test_t1_f3_start_engine_lifecycle', () async {
      final controller = EngineControllerModel();
      expect(controller.state, equals(EngineState.uninitialized));

      await controller.startEngine(config: null);
      expect(controller.state, equals(EngineState.running));
      expect(controller.status, isNotNull);
      expect(controller.status!.isInitialized, isTrue);
      expect(controller.status!.coreVersion, equals('0.1.0'));
      expect(controller.status!.allocatorName, equals('FluoriteArenaAllocator_v1'));
    });

    TestHarness.test('test_t1_f3_allocate_engine_buffer', () {
      const oneMb = 1024 * 1024;
      final buf = allocateEngineBuffer(oneMb);
      expect(buf.length, equals(oneMb));
      expect(verifyBufferSentinels(buf), isTrue);
    });

    TestHarness.test('test_t1_f3_get_engine_status', () async {
      final controller = EngineControllerModel();
      await controller.startEngine(config: null);
      await controller.allocate1MB();

      final status = controller.status!;
      expect(status.arenaAllocatedBytes, equals(1024 * 1024));
      expect(status.arenaCapacityBytes, greaterThan(status.arenaAllocatedBytes));
    });

    TestHarness.test('test_t1_f3_verify_buffer_sentinels', () {
      final validBuf = allocateEngineBuffer(1024);
      expect(verifyBufferSentinels(validBuf), isTrue);

      final corruptHeader = allocateEngineBuffer(1024);
      corruptHeader[0] = 0x00;
      expect(verifyBufferSentinels(corruptHeader), isFalse);

      final corruptFooter = allocateEngineBuffer(1024);
      corruptFooter[1023] = 0x00;
      expect(verifyBufferSentinels(corruptFooter), isFalse);
    });

    TestHarness.test('test_t1_f3_shared_frame_buffer_handle', () {
      final handle = SharedFrameBufferModel(256);
      expect(handle.len, equals(256));
      expect(handle.readByte(0), equals(0xDE));
      expect(handle.readByte(1), equals(0xAD));

      handle.writeByte(100, 0x99);
      expect(handle.readByte(100), equals(0x99));
    });
  });

  // ---------------------------------------------------------------------------
  // Feature 4: Flutter Desktop Editor & Controller Integration
  // ---------------------------------------------------------------------------
  TestHarness.group('Tier 1 - Feature 4: Flutter Desktop Editor & Controller', () {
    TestHarness.test('test_t1_f4_editor_controller_initial_state', () {
      final controller = EngineControllerModel();
      expect(controller.state, equals(EngineState.uninitialized));
      expect(controller.activeBuffer, isNull);
      expect(controller.allocationLatencyMicros, equals(0));
      expect(controller.status, isNull);
    });

    TestHarness.test('test_t1_f4_editor_controller_start_engine', () async {
      final controller = EngineControllerModel();
      await controller.startEngine(config: null);
      expect(controller.state, equals(EngineState.running));
      expect(controller.status!.isInitialized, isTrue);
    });

    TestHarness.test('test_t1_f4_editor_controller_allocate_1mb', () async {
      final controller = EngineControllerModel();
      final buf = await controller.allocate1MB();

      expect(controller.state, equals(EngineState.running));
      expect(controller.activeBuffer, isNotNull);
      expect(buf.length, equals(1024 * 1024));
      expect(controller.allocationLatencyMicros, greaterThanOrEqualTo(0));
      expect(verifyBufferSentinels(buf), isTrue);
    });

    TestHarness.test('test_t1_f4_editor_controller_reset', () async {
      final controller = EngineControllerModel();
      await controller.startEngine(config: null);
      await controller.allocate1MB();

      controller.reset();
      expect(controller.state, equals(EngineState.uninitialized));
      expect(controller.activeBuffer, isNull);
      expect(controller.allocationLatencyMicros, equals(0));
    });

    TestHarness.test('test_t1_f4_hex_memory_inspector_formatting', () {
      final buffer = allocateEngineBuffer(64);
      final lines = formatHexInspector(buffer, offset: 0, length: 64);

      expect(lines.length, equals(4)); // 64 bytes / 16 bytes per line = 4 lines
      expect(lines[0].contains('AA'), isTrue, reason: 'Header sentinel 0xAA must be visible in hex view');
    });
  });
}
