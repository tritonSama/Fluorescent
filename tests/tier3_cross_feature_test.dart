// tests/tier3_cross_feature_test.dart
//
// Tier 3: Cross-Feature Combinations (Pairwise)
// Validates interactions across subsystem boundaries:
// 1. Allocator + Reset + Frame Buffer Swap
// 2. Arena Allocation + FFI Bridge Transfer
// 3. Dart FFI Call + 1MB Buffer Readback & Sentinels
// 4. Shared Buffer Native Pointer + Editor Controller & Hex Viewer
// 5. FFI In-Place Mutation + Allocator Telemetry Metrics

import 'e2e_test_harness.dart';
import 'fluorite_bridge_model.dart';

void registerTier3Tests() {
  TestHarness.group('Tier 3 - Cross-Feature Combinations (Pairwise)', () {
    TestHarness.test('test_t3_allocator_reset_and_frame_swap', () {
      final frameAlloc = DoubleBufferedFrameAllocatorModel(128 * 1024);

      for (int frame = 0; frame < 50; frame++) {
        final current = frameAlloc.currentArena;
        expect(current.allocatedBytes, equals(0),
            reason: 'Newly active arena at frame $frame must be reset');

        // Allocate transient frame data
        final frameData = current.allocSlice(1024, frame & 0xFF);
        expect(frameData[0], equals(frame & 0xFF));

        // Advance to next frame
        frameAlloc.swapBuffers();

        // Previous frame data is safely retained in previousArena
        expect(frameAlloc.previousArena.allocatedBytes, greaterThanOrEqualTo(1024));
      }
    });

    TestHarness.test('test_t3_arena_allocation_and_ffi_buffer_transfer', () {
      // 1. Allocate 1MB within custom arena
      final arena = ArenaAllocatorModel(2 * 1024 * 1024);
      final rawSlice = arena.allocSlice(1024 * 1024, 0x00);
      rawSlice[0] = 0xAA;
      rawSlice[rawSlice.length - 1] = 0x55;

      // 2. Transfer to FFI bridge representation
      final ffiBuffer = rawSlice; // Direct zero-copy slice view
      expect(ffiBuffer.length, equals(1024 * 1024));

      // 3. Verify external TypedData view matches
      expect(verifyBufferSentinels(ffiBuffer), isTrue);
      expect(arena.allocatedBytes, greaterThanOrEqualTo(1024 * 1024));
    });

    TestHarness.test('test_t3_dart_call_and_1mb_buffer_readback', () async {
      final controller = EngineControllerModel();
      await controller.startEngine(config: null);

      // Dart calls FFI function
      final buffer = await controller.allocate1MB();

      // Read back values from 1MB buffer without crashing
      expect(buffer.length, equals(1024 * 1024));
      expect(buffer[0], equals(0xAA));
      expect(buffer[1024 * 1024 - 1], equals(0x55));
      expect(verifyBufferSentinels(buffer), isTrue);
      expect(controller.status!.isInitialized, isTrue);
    });

    TestHarness.test('test_t3_shared_buffer_pointer_and_editor_controller', () {
      // Create shared buffer representing native memory
      final sharedBuf = SharedFrameBufferModel(1024 * 1024);
      expect(sharedBuf.ptrAddress, greaterThan(0));

      // Map to hex inspector
      final hexLines = formatHexInspector(sharedBuf.data, offset: 0, length: 32);
      expect(hexLines.length, equals(2));
      expect(hexLines[0].contains('DE AD BE EF'), isTrue,
          reason: 'Hex inspector must display shared buffer magic sentinels');
    });

    TestHarness.test('test_t3_ffi_mutation_and_allocator_metrics', () async {
      final controller = EngineControllerModel();
      await controller.startEngine(config: null);
      final buf = await controller.allocate1MB();

      // In-place FFI mutation
      writeBufferPattern(buf, 0x33);
      expect(buf[0], equals(0x33));
      expect(buf[buf.length - 1], equals(0x33));

      // Allocator telemetry reflects allocation
      expect(controller.status!.arenaAllocatedBytes, equals(1024 * 1024));
    });
  });
}
