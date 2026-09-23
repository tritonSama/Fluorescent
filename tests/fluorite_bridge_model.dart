// tests/fluorite_bridge_model.dart
//
// Authoritative client model, FFI bridge interface, and native allocator
// verification engine for Fluorite AAA Engine Phase 1.
//
// Implements the exact interface contracts defined in PROJECT.md:
// - R1: ArenaAllocator, DoubleBufferedFrameAllocator, alignment ladder
// - R2: Zero-copy 1MB buffer, sentinels (0xAA / 0x55), shared frame buffer
// - R3: EngineController, telemetry metrics, hex inspector

import 'dart:typed_data';

/// Exception thrown when allocator requests exceed capacity or have invalid layout.
class AllocException implements Exception {
  final String message;
  AllocException(this.message);
  @override
  String toString() => 'AllocException: $message';
}

/// Telemetry status struct matching FFI EngineStatus.
class EngineStatus {
  final bool isInitialized;
  final String coreVersion;
  final String allocatorName;
  final int arenaCapacityBytes;
  final int arenaAllocatedBytes;
  final int frameIndex;

  final int? textureId;

  const EngineStatus({
    required this.isInitialized,
    required this.coreVersion,
    required this.allocatorName,
    required this.arenaCapacityBytes,
    required this.arenaAllocatedBytes,
    required this.frameIndex,
    this.textureId,
  });

  @override
  String toString() =>
      'EngineStatus(init: $isInitialized, ver: $coreVersion, alloc: $allocatorName, '
      'cap: $arenaCapacityBytes, used: $arenaAllocatedBytes, frame: $frameIndex, tex: $textureId)';
}

/// Bump-pointer arena allocator implementing power-of-two alignment arithmetic.
class ArenaAllocatorModel {
  final int capacity;
  final Uint8List _buffer;
  int _offset = 0;
  int _peakUsage = 0;
  int _allocCount = 0;
  final int baseAddress;

  ArenaAllocatorModel(this.capacity, {int? simulatedBaseAddress})
      : _buffer = Uint8List(capacity),
        baseAddress = simulatedBaseAddress ?? 0x10000000 {
    if (capacity <= 0) {
      throw AllocException('Invalid capacity: $capacity');
    }
  }

  int get allocatedBytes => _offset;
  int get capacityBytes => capacity;
  int get remainingBytes => capacity - _offset;
  int get peakUsage => _peakUsage;
  int get allocationCount => _allocCount;

  /// Allocates a raw chunk with strict power-of-two alignment.
  /// Formula: padding = (align - (currentAddr & (align - 1))) & (align - 1)
  int allocRaw(int size, int align) {
    if (size == 0) {
      // Zero-size allocation returns current aligned address without advancing offset
      return _calculateAlignedAddress(_offset, align);
    }
    if (align <= 0 || (align & (align - 1)) != 0) {
      throw AllocException('Alignment must be a non-zero power of two: $align');
    }

    final currentAddr = baseAddress + _offset;
    final padding = (align - (currentAddr & (align - 1))) & (align - 1);
    final nextOffset = _offset + padding + size;

    if (nextOffset > capacity) {
      throw AllocException(
          'OutOfMemory: requested $size bytes (with $padding padding), remaining $remainingBytes');
    }

    final allocatedAddr = currentAddr + padding;
    _offset = nextOffset;
    _allocCount++;
    if (_offset > _peakUsage) {
      _peakUsage = _offset;
    }
    return allocatedAddr;
  }

  /// Allocates a contiguous slice of bytes within the arena.
  Uint8List allocSlice(int count, int initialValue) {
    if (count == 0) {
      return Uint8List(0);
    }
    final align = 8; // Default 8-byte alignment for slices
    final currentAddr = baseAddress + _offset;
    final padding = (align - (currentAddr & (align - 1))) & (align - 1);
    final nextOffset = _offset + padding + count;

    if (nextOffset > capacity) {
      throw AllocException(
          'OutOfMemory: slice count $count exceeds remaining $remainingBytes');
    }

    final startIdx = _offset + padding;
    _offset = nextOffset;
    _allocCount++;
    if (_offset > _peakUsage) {
      _peakUsage = _offset;
    }

    for (int i = 0; i < count; i++) {
      _buffer[startIdx + i] = initialValue;
    }

    // Return view into internal buffer
    return Uint8List.sublistView(_buffer, startIdx, startIdx + count);
  }

  /// O(1) bulk reset. Discards all previous allocations instantly.
  void reset() {
    _offset = 0;
    _allocCount = 0;
  }

  int _calculateAlignedAddress(int offset, int align) {
    final addr = baseAddress + offset;
    final padding = (align - (addr & (align - 1))) & (align - 1);
    return addr + padding;
  }
}

/// Double-buffered ping-pong allocator for decoupling game loop simulation and rendering.
class DoubleBufferedFrameAllocatorModel {
  final List<ArenaAllocatorModel> arenas;
  int currentFrame = 0;

  DoubleBufferedFrameAllocatorModel(int frameCapacity)
      : arenas = [
          ArenaAllocatorModel(frameCapacity, simulatedBaseAddress: 0x10000000),
          ArenaAllocatorModel(frameCapacity, simulatedBaseAddress: 0x20000000),
        ];

  ArenaAllocatorModel get currentArena => arenas[currentFrame % 2];
  ArenaAllocatorModel get previousArena => arenas[(currentFrame + 1) % 2];

  /// Advance to the next frame and reset the newly active arena.
  void swapBuffers() {
    currentFrame++;
    currentArena.reset();
  }

  int get frameIndex => currentFrame;
}

/// Persistent shared frame buffer handle.
class SharedFrameBufferModel {
  final Uint8List data;
  final int ptrAddress;

  SharedFrameBufferModel(int sizeBytes, {int? baseAddr})
      : data = Uint8List(sizeBytes),
        ptrAddress = baseAddr ?? 0x30000000 {
    if (sizeBytes >= 4) {
      data[0] = 0xDE;
      data[1] = 0xAD;
      data[2] = 0xBE;
      data[3] = 0xEF;
    }
  }

  int get len => data.length;

  int readByte(int offset) {
    if (offset >= data.length) {
      throw RangeError.index(offset, data);
    }
    return data[offset];
  }

  void writeByte(int offset, int value) {
    if (offset >= data.length) {
      throw RangeError.index(offset, data);
    }
    data[offset] = value;
  }
}

/// Engine state machine enum.
enum EngineState { uninitialized, initializing, running, error }

/// Editor UI engine controller model matching lib/src/engine_controller.dart.
class EngineControllerModel {
  EngineState state = EngineState.uninitialized;
  EngineStatus? status;
  Uint8List? activeBuffer;
  int allocationLatencyMicros = 0;
  String? errorMessage;
  final DoubleBufferedFrameAllocatorModel allocator;

  EngineControllerModel({int arenaCapacity = 1024 * 1024 * 64})
      : allocator = DoubleBufferedFrameAllocatorModel(arenaCapacity);

  Future<int?> startEngine({dynamic config}) async {
    state = EngineState.initializing;
    // Simulate brief initialization
    await Future.delayed(Duration(microseconds: 100));
    state = EngineState.running;
    status = EngineStatus(
      isInitialized: true,
      coreVersion: '0.1.0',
      allocatorName: 'FluoriteArenaAllocator_v1',
      arenaCapacityBytes: allocator.currentArena.capacityBytes,
      arenaAllocatedBytes: allocator.currentArena.allocatedBytes,
      frameIndex: allocator.frameIndex,
      textureId: 1,
    );
    return 1;
  }

  void drawWireframe({required List<double> transform, required int color, required double thickness}) {
    // Stub
  }

  Future<Uint8List> allocate1MB() async {
    if (state != EngineState.running) {
      await startEngine();
    }
    final sw = Stopwatch()..start();
    const oneMb = 1024 * 1024;
    final buffer = allocateEngineBuffer(oneMb);
    sw.stop();
    allocationLatencyMicros = sw.elapsedMicroseconds;
    activeBuffer = buffer;

    // Update status
    status = EngineStatus(
      isInitialized: true,
      coreVersion: '0.1.0',
      allocatorName: 'FluoriteArenaAllocator_v1',
      arenaCapacityBytes: allocator.currentArena.capacityBytes,
      arenaAllocatedBytes: oneMb,
      frameIndex: allocator.frameIndex,
      textureId: 1,
    );
    return buffer;
  }

  void reset() {
    activeBuffer = null;
    allocationLatencyMicros = 0;
    allocator.currentArena.reset();
    state = EngineState.uninitialized;
    status = null;
  }
}

// -----------------------------------------------------------------------------
// Top-Level Bridge Functions (matching PROJECT.md Interface Contracts)
// -----------------------------------------------------------------------------

/// Allocates an engine buffer with 0xAA header and 0x55 footer sentinels.
Uint8List allocateEngineBuffer(int sizeBytes) {
  final buffer = Uint8List(sizeBytes);
  if (sizeBytes > 0) {
    buffer[0] = 0xAA; // Diagnostic sentinel: Header byte
    buffer[sizeBytes - 1] = 0x55; // Diagnostic sentinel: Footer byte
  }
  return buffer;
}

/// Verifies sentinel bytes in a buffer.
bool verifyBufferSentinels(Uint8List buffer) {
  if (buffer.isEmpty) return false;
  if (buffer[0] != 0xAA) return false;
  if (buffer[buffer.length - 1] != 0x55) return false;
  return true;
}

/// Writes pattern to continuous buffer in-place.
Uint8List writeBufferPattern(Uint8List buffer, int fillByte) {
  buffer.fillRange(0, buffer.length, fillByte);
  return buffer;
}

/// Formats a byte slice into a standard hex dump inspector view.
List<String> formatHexInspector(Uint8List buffer, {int offset = 0, int length = 64}) {
  if (buffer.isEmpty) return ['<Empty Buffer>'];
  final safeOffset = offset.clamp(0, buffer.length);
  final safeLength = length.clamp(0, buffer.length - safeOffset);
  final lines = <String>[];

  for (int i = 0; i < safeLength; i += 16) {
    final chunkEnd = (i + 16).clamp(0, safeLength);
    final chunk = buffer.sublist(safeOffset + i, safeOffset + chunkEnd);

    final hexParts = chunk.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    final asciiParts = chunk.map((b) => (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.').join();

    final addrStr = (safeOffset + i).toRadixString(16).padLeft(8, '0').toUpperCase();
    lines.add('$addrStr  ${hexParts.padRight(47)}  |$asciiParts|');
  }
  return lines;
}
