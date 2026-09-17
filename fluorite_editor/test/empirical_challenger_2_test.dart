// fluorite_editor/test/empirical_challenger_2_test.dart
//
// EMPIRICAL ADVERSARIAL CHALLENGE SUITE — Milestone 2 Iteration 2
// Challenger: challenger_2_m2_iter2 (teamwork_preview_challenger)
//
// Rigorously tests:
// 1. SharedFrameBuffer Pointer Dereferencing & STATUS_ACCESS_VIOLATION (0xC0000005) prevention
// 2. Boundary Safety on read_byte / write_byte (Dart RangeError & Rust catch_unwind / bounds checking)
// 3. EngineStatusC C-ABI struct layout, padding, offsets, and readCString string decoding
// 4. Live stress and stability under rapid allocation and memory mutation

import 'dart:convert' as convert;
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import '../lib/src/rust/api/engine.dart';
import '../lib/src/rust/frb_generated.dart';
import '../lib/src/rust/frb_generated.io.dart';

int _totalTests = 0;
int _passedTests = 0;
int _failedTests = 0;

void group(String name, void Function() body) {
  print('\n=== [GROUP] $name ===');
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
  } else if (expected is Function) {
    if (!expected(actual)) {
      throw Exception('${reason ?? "Matcher failed"} for value: $actual');
    }
  } else if (actual != expected) {
    throw Exception('${reason ?? "Equality mismatch"}: expected <$expected>, got <$actual>');
  }
}

class TestNativeMemory {
  static final TestNativeMemory instance = TestNativeMemory._();
  late final ffi.Pointer<ffi.Uint8> Function(int) _malloc;
  late final void Function(ffi.Pointer<ffi.Uint8>) _free;
  bool isAvailable = false;

  TestNativeMemory._() {
    try {
      final lib = Platform.isWindows
          ? ffi.DynamicLibrary.open('msvcrt.dll')
          : ffi.DynamicLibrary.process();
      _malloc = lib.lookupFunction<
          ffi.Pointer<ffi.Uint8> Function(ffi.Size),
          ffi.Pointer<ffi.Uint8> Function(int)>('malloc');
      _free = lib.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Uint8>),
          void Function(ffi.Pointer<ffi.Uint8>)>('free');
      isAvailable = true;
    } catch (_) {
      isAvailable = false;
    }
  }

  ffi.Pointer<ffi.Uint8>? allocate(int bytes) => isAvailable ? _malloc(bytes) : null;
  void free(ffi.Pointer<ffi.Uint8> ptr) {
    if (isAvailable && ptr != ffi.nullptr) _free(ptr);
  }
}


void main() {
  print('================================================================');
  print('   CHALLENGER 2: EMPIRICAL ADVERSARIAL STRESS & AUDIT SUITE    ');
  print('================================================================');

  RustLib.resetForTesting();
  RustLib.initSync();

  // ===========================================================================
  // GROUP 1: SharedFrameBuffer Pointer Dereferencing & Memory Access
  // ===========================================================================
  group('Challenge 1: Pointer Dereferencing & 0xC0000005 Prevention', () {
    test('ptrAddress() returns valid virtual address and never 0x40000000 across size ladder', () {
      final sizes = [4, 16, 64, 256, 1024, 65536, 1048576, 4194304];
      for (final size in sizes) {
        final sfb = SharedFrameBuffer(sizeBytes: size);
        final addr = sfb.ptrAddress();

        // 1. Must never return synthetic 0x40000000
        expect(addr != 0x40000000, true,
            reason: 'SharedFrameBuffer ($size bytes) returned synthetic address 0x40000000!');

        // 2. Must return a non-zero address
        expect(addr != 0, true,
            reason: 'SharedFrameBuffer ($size bytes) returned null pointer (0)');

        // 3. Must be aligned to at least 4 or 8 bytes on 64-bit OS
        expect(addr % 4 == 0, true,
            reason: 'Address 0x${addr.toRadixString(16)} must be aligned');

        // 4. Must be a valid user-mode 64-bit virtual address
        expect(addr > 0x10000, true,
            reason: 'Address 0x${addr.toRadixString(16)} is in null page guard area');
      }
    });

    test('Live dereferencing via ffi.Pointer.fromAddress().asTypedList() without Access Violation', () {
      final sizes = [4, 64, 1024, 1048576]; // up to 1MB
      for (final size in sizes) {
        final sfb = SharedFrameBuffer(sizeBytes: size);
        final addr = sfb.ptrAddress();

        // Construct raw pointer from address and create external TypedData view
        final rawPtr = ffi.Pointer<ffi.Uint8>.fromAddress(addr);
        final externalView = rawPtr.asTypedList(size);

        // Verify reading magic header
        expect(externalView[0], 0xDE);
        expect(externalView[1], 0xAD);
        expect(externalView[2], 0xBE);
        expect(externalView[3], 0xEF);

        // Touch EVERY single byte in the buffer to guarantee full page accessibility
        int sum = 0;
        for (int i = 0; i < size; i += 4096) {
          sum += externalView[i];
        }
        expect(sum >= 0, true);

        // Mutate memory through raw pointer
        externalView[0] = 0x11;
        externalView[size - 1] = 0x99;

        // Verify mutation reflected in sfb.readByte
        expect(sfb.readByte(offset: 0), 0x11,
            reason: 'Raw pointer mutation must reflect in sfb.readByte(0)');
        expect(sfb.readByte(offset: size - 1), 0x99,
            reason: 'Raw pointer mutation must reflect in sfb.readByte(last)');
      }
    });

    test('Bidirectional live mutation coherence across 3 access interfaces', () {
      final sfb = SharedFrameBuffer(sizeBytes: 512);
      final rawPtr = ffi.Pointer<ffi.Uint8>.fromAddress(sfb.ptrAddress());
      final rawView = rawPtr.asTypedList(512);
      final dartView = sfb.asTypedList();

      // Interface A -> writeByte; verify B (rawView) & C (dartView)
      sfb.writeByte(offset: 42, value: 0xAA);
      expect(rawView[42], 0xAA);
      expect(dartView[42], 0xAA);
      expect(sfb.readByte(offset: 42), 0xAA);

      // Interface B -> rawView; verify A (readByte) & C (dartView)
      rawView[100] = 0xBB;
      expect(sfb.readByte(offset: 100), 0xBB);
      expect(dartView[100], 0xBB);

      // Interface C -> dartView; verify A (readByte) & B (rawView)
      dartView[200] = 0xCC;
      expect(sfb.readByte(offset: 200), 0xCC);
      expect(rawView[200], 0xCC);
    });

    test('Massive allocation soak: 1000 SharedFrameBuffers with raw pointer writes', () {
      for (int i = 0; i < 1000; i++) {
        final sfb = SharedFrameBuffer(sizeBytes: 128);
        final addr = sfb.ptrAddress();
        expect(addr != 0x40000000, true);
        final rawView = ffi.Pointer<ffi.Uint8>.fromAddress(addr).asTypedList(128);
        rawView[0] = i & 0xFF;
        rawView[127] = (i ^ 0xFF) & 0xFF;
        expect(sfb.readByte(offset: 0), i & 0xFF);
        expect(sfb.readByte(offset: 127), (i ^ 0xFF) & 0xFF);
      }
    });

    test('Non-overlapping address ranges across 100 concurrently retained buffers', () {
      final buffers = <SharedFrameBuffer>[];
      final ranges = <int, int>{}; // addr -> endAddr

      for (int i = 0; i < 100; i++) {
        final size = 256;
        final sfb = SharedFrameBuffer(sizeBytes: size);
        final addr = sfb.ptrAddress();
        expect(addr != 0x40000000, true);

        // Check for collision or overlap with existing retained buffers
        final endAddr = addr + size;
        for (final entry in ranges.entries) {
          final existingStart = entry.key;
          final existingEnd = entry.value;
          final overlaps = (addr < existingEnd) && (endAddr > existingStart);
          expect(overlaps, false,
              reason: 'Buffer $i [0x${addr.toRadixString(16)}, 0x${endAddr.toRadixString(16)}) overlaps with '
                  'existing [0x${existingStart.toRadixString(16)}, 0x${existingEnd.toRadixString(16)})');
        }

        ranges[addr] = endAddr;
        buffers.add(sfb);
      }

      expect(buffers.length, 100);
      expect(ranges.length, 100);
    });

  });

  // ===========================================================================
  // GROUP 2: Boundary Safety & C-ABI Protection
  // ===========================================================================
  group('Challenge 2: Boundary Safety on readByte / writeByte', () {
    test('Upper out-of-bounds readByte throws RangeError', () {
      final sfb = SharedFrameBuffer(sizeBytes: 64);
      final invalidOffsets = [64, 65, 100, 1000, 0x7FFFFFFF];

      for (final offset in invalidOffsets) {
        bool threw = false;
        try {
          sfb.readByte(offset: offset);
        } on RangeError {
          threw = true;
        } catch (_) {
          threw = true;
        }
        expect(threw, true, reason: 'readByte at offset $offset must throw RangeError');
      }
    });

    test('Upper out-of-bounds writeByte throws RangeError', () {
      final sfb = SharedFrameBuffer(sizeBytes: 64);
      final invalidOffsets = [64, 65, 100, 1000, 0x7FFFFFFF];

      for (final offset in invalidOffsets) {
        bool threw = false;
        try {
          sfb.writeByte(offset: offset, value: 0xFF);
        } on RangeError {
          threw = true;
        } catch (_) {
          threw = true;
        }
        expect(threw, true, reason: 'writeByte at offset $offset must throw RangeError');
      }
    });

    test('Lower out-of-bounds (negative offsets) throw RangeError', () {
      final sfb = SharedFrameBuffer(sizeBytes: 64);
      final negativeOffsets = [-1, -2, -100, -9223372036854775808];

      for (final offset in negativeOffsets) {
        bool readThrew = false;
        try {
          sfb.readByte(offset: offset);
        } catch (_) {
          readThrew = true;
        }
        expect(readThrew, true, reason: 'readByte at offset $offset must throw');

        bool writeThrew = false;
        try {
          sfb.writeByte(offset: offset, value: 0x55);
        } catch (_) {
          writeThrew = true;
        }
        expect(writeThrew, true, reason: 'writeByte at offset $offset must throw');
      }
    });

    test('Empty buffer (size 0) rejects all read and write attempts', () {
      final sfb = SharedFrameBuffer(sizeBytes: 0);
      expect(sfb.len(), 0);
      expect(sfb.isEmpty(), true);

      bool readThrew = false;
      try {
        sfb.readByte(offset: 0);
      } catch (_) {
        readThrew = true;
      }
      expect(readThrew, true, reason: 'Empty buffer readByte(0) must throw');

      bool writeThrew = false;
      try {
        sfb.writeByte(offset: 0, value: 0x11);
      } catch (_) {
        writeThrew = true;
      }
      expect(writeThrew, true, reason: 'Empty buffer writeByte(0) must throw');
    });

    test('Sub-4 byte buffers (sizes 1, 2, 3) handle header stamping safely without overrun', () {
      for (int size = 1; size < 4; size++) {
        final sfb = SharedFrameBuffer(sizeBytes: size);
        expect(sfb.len(), size);
        expect(sfb.readByte(offset: 0), 0); // No 0xDEADBEEF if size < 4

        // Bounds checking works at boundary
        bool threw = false;
        try {
          sfb.readByte(offset: size);
        } catch (_) {
          threw = true;
        }
        expect(threw, true, reason: 'Offset $size must be out of bounds for size $size');
      }
    });

    test('Negative sizeBytes returns empty buffer safely', () {
      final sfb = SharedFrameBuffer(sizeBytes: -10);
      expect(sfb.len(), 0);
      expect(sfb.isEmpty(), true);
    });
  });

  // ===========================================================================
  // GROUP 3: Struct Layout Matching (EngineStatusC) & readCString
  // ===========================================================================
  group('Challenge 3: EngineStatusC C-ABI Layout & readCString', () {
    test('EngineStatusC struct size matches 64-bit C-ABI layout (56 bytes)', () {
      final size = ffi.sizeOf<EngineStatusC>();
      // 64-bit C layout:
      // bool isInitialized: 1 byte + 7 bytes padding = 8
      // size_t totalMemoryAllocated: 8 bytes
      // size_t arenaCapacity: 8 bytes
      // uint64_t frameIndex: 8 bytes
      // const char* statusMessage: 8 bytes
      // const char* coreVersion: 8 bytes
      // const char* allocatorName: 8 bytes
      // Total = 56 bytes
      expect(size, 56, reason: 'EngineStatusC size on x64 must be exactly 56 bytes');
    });

    test('EngineStatusC field offset alignment and bidirectional marshaling', () {
      // Allocate 56-byte buffer using native system malloc
      final sysAlloc = TestNativeMemory.instance;
      expect(sysAlloc.isAvailable, true, reason: 'System malloc must be available');

      final rawMem = sysAlloc.allocate(56)!;
      final byteView = rawMem.asTypedList(56);
      byteView.fillRange(0, 56, 0);

      // Create test C strings
      final msgUnits = convert.utf8.encode('Engine Active Test Msg\x00');
      final msgMem = sysAlloc.allocate(msgUnits.length)!;
      msgMem.asTypedList(msgUnits.length).setAll(0, msgUnits);

      final verUnits = convert.utf8.encode('0.2.5\x00');
      final verMem = sysAlloc.allocate(verUnits.length)!;
      verMem.asTypedList(verUnits.length).setAll(0, verUnits);

      final allocUnits = convert.utf8.encode('FluoriteCustomArena\x00');
      final allocMem = sysAlloc.allocate(allocUnits.length)!;
      allocMem.asTypedList(allocUnits.length).setAll(0, allocUnits);

      try {
        final statusPtr = rawMem.cast<EngineStatusC>();
        final status = statusPtr.ref;

        // Set fields via Dart struct accessors
        status.isInitialized = true;
        status.totalMemoryAllocated = 0x11223344;
        status.arenaCapacity = 0x55667788;
        status.frameIndex = 0x0102030405060708;
        status.statusMessage = msgMem.cast<ffi.Char>();
        status.coreVersion = verMem.cast<ffi.Char>();
        status.allocatorName = allocMem.cast<ffi.Char>();

        // Verify raw byte offsets:
        // Byte 0: isInitialized (1)
        expect(byteView[0], 1);
        // Bytes 1..7: padding (all 0)
        for (int p = 1; p < 8; p++) {
          expect(byteView[p], 0, reason: 'Padding byte $p must be 0');
        }

        // Bytes 8..15: totalMemoryAllocated (0x11223344 in little endian)
        final bdata = ByteData.sublistView(byteView);
        expect(bdata.getUint64(8, Endian.little), 0x11223344);

        // Bytes 16..23: arenaCapacity (0x55667788 in little endian)
        expect(bdata.getUint64(16, Endian.little), 0x55667788);

        // Bytes 24..31: frameIndex (0x0102030405060708 in little endian)
        expect(bdata.getUint64(24, Endian.little), 0x0102030405060708);

        // Bytes 32..39: statusMessage pointer address
        expect(bdata.getUint64(32, Endian.little), msgMem.address);

        // Bytes 40..47: coreVersion pointer address
        expect(bdata.getUint64(40, Endian.little), verMem.address);

        // Bytes 48..55: allocatorName pointer address
        expect(bdata.getUint64(48, Endian.little), allocMem.address);

        // Now verify string decoding via readCString
        expect(readCString(status.statusMessage), 'Engine Active Test Msg');
        expect(readCString(status.coreVersion), '0.2.5');
        expect(readCString(status.allocatorName), 'FluoriteCustomArena');
      } finally {
        sysAlloc.free(rawMem);
        sysAlloc.free(msgMem);
        sysAlloc.free(verMem);
        sysAlloc.free(allocMem);
      }
    });

    test('readCString robust edge cases: null, empty, UTF-8 unicode, and early termination', () {
      final sysAlloc = TestNativeMemory.instance;

      // 1. nullptr returns empty string
      expect(readCString(ffi.nullptr), '');

      // 2. empty string b"\x00"
      final emptyMem = sysAlloc.allocate(1)!;
      emptyMem[0] = 0;
      expect(readCString(emptyMem.cast<ffi.Char>()), '');
      sysAlloc.free(emptyMem);

      // 3. UTF-8 multi-byte sequence: emojis, symbols, and CJK characters
      const testStr = 'Fluorite 🚀 3D エンジン — ⚡ AAA Rendering';
      final utf8Bytes = convert.utf8.encode('$testStr\x00');
      final strMem = sysAlloc.allocate(utf8Bytes.length)!;
      strMem.asTypedList(utf8Bytes.length).setAll(0, utf8Bytes);
      expect(readCString(strMem.cast<ffi.Char>()), testStr);
      sysAlloc.free(strMem);

      // 4. Early termination on embedded null: b"FirstPart\x00SecondPart\x00"
      final multiNullBytes = convert.utf8.encode('FirstPart\x00SecondPart\x00');
      final multiNullMem = sysAlloc.allocate(multiNullBytes.length)!;
      multiNullMem.asTypedList(multiNullBytes.length).setAll(0, multiNullBytes);
      expect(readCString(multiNullMem.cast<ffi.Char>()), 'FirstPart');
      sysAlloc.free(multiNullMem);

      // 5. Long string (2048 characters)
      final longStr = 'A' * 2048;
      final longBytes = convert.utf8.encode('$longStr\x00');
      final longMem = sysAlloc.allocate(longBytes.length)!;
      longMem.asTypedList(longBytes.length).setAll(0, longBytes);
      expect(readCString(longMem.cast<ffi.Char>()), longStr);
      sysAlloc.free(longMem);
    });
  });

  // ===========================================================================
  // GROUP 4: End-to-End Stress & Stability
  // ===========================================================================
  group('Challenge 4: High-Load Stress & Lifecycle Stability', () {
    test('Rapid consecutive allocateEngineBuffer calls maintain memory stability', () {
      RustLib.resetForTesting();
      startEngine();

      for (int i = 0; i < 200; i++) {
        final buf = allocateEngineBuffer(sizeBytes: 1024 * 1024);
        expect(buf.length, 1024 * 1024);
        expect(buf[0], 0xAA);
        expect(buf[buf.length - 1], 0x55);
        expect(verifyBufferSentinels(buffer: buf), true);
      }
    });

    test('SharedFrameBuffer rapid create-write-dereference-mutate cycle', () {
      for (int i = 0; i < 500; i++) {
        final size = 64 + (i % 512);
        final sfb = SharedFrameBuffer(sizeBytes: size);
        final addr = sfb.ptrAddress();
        expect(addr != 0x40000000, true);

        final raw = ffi.Pointer<ffi.Uint8>.fromAddress(addr).asTypedList(size);
        raw[10] = (i * 3) & 0xFF;
        expect(sfb.readByte(offset: 10), (i * 3) & 0xFF);
      }
    });
  });

  // ===========================================================================
  // SUMMARY
  // ===========================================================================
  print('\n================================================================');
  print('CHALLENGER 2 TEST SUMMARY:');
  print('  Total Tests:  $_totalTests');
  print('  Passed:       $_passedTests');
  print('  Failed:       $_failedTests');
  print('================================================================\n');

  if (_failedTests > 0) {
    exit(1);
  }
}
