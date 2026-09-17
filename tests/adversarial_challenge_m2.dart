// tests/adversarial_challenge_m2.dart
//
// Empirical Adversarial Challenge Suite for Milestone 2:
// - SharedFrameBuffer live pointer access, bounds, and Pointer.asTypedList()
// - C-ABI symbol contracts and memory safety
// - Contract robustness: empty buffers, oversized allocations, repeated start_engine

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import '../fluorite_editor/lib/src/rust/api/engine.dart';
import '../fluorite_editor/lib/src/rust/frb_generated.dart';

void main() {
  print('================================================================');
  print('    EMPIRICAL CHALLENGER 2 (M2) — ADVERSARIAL STRESS SUITE     ');
  print('================================================================\n');

  int passed = 0;
  int failed = 0;
  int findings = 0;

  void test(String name, void Function() fn) {
    try {
      fn();
      print('  [PASS] $name');
      passed++;
    } catch (e, st) {
      print('  [FAIL] $name: $e');
      print('         $st');
      failed++;
    }
  }

  void reportFinding(String id, String title, String detail) {
    print('  [FINDING - $id] $title');
    print('    -> $detail\n');
    findings++;
  }

  // ---------------------------------------------------------------------------
  // SECTION 1: SharedFrameBuffer & Live Pointer Access
  // ---------------------------------------------------------------------------
  print('[CHALLENGE GROUP 1] SharedFrameBuffer & Live Pointer Access');

  test('SharedFrameBuffer initialization and DEADBEEF header', () {
    RustLib.initSync();
    final buf = SharedFrameBuffer(sizeBytes: 1024);
    if (buf.len() != 1024) throw 'Expected length 1024, got ${buf.len()}';
    if (buf.isEmpty()) throw 'Buffer should not be empty';
    if (buf.readByte(offset: 0) != 0xDE ||
        buf.readByte(offset: 1) != 0xAD ||
        buf.readByte(offset: 2) != 0xBE ||
        buf.readByte(offset: 3) != 0xEF) {
      throw 'Header sentinels 0xDEADBEEF not found';
    }
  });

  test('SharedFrameBuffer in-place mutation through asTypedList', () {
    final buf = SharedFrameBuffer(sizeBytes: 256);
    final view = buf.asTypedList();
    view[10] = 0x77;
    if (buf.readByte(offset: 10) != 0x77) {
      throw 'Mutation through asTypedList not reflected in readByte';
    }
    buf.writeByte(offset: 20, value: 0x88);
    if (view[20] != 0x88) {
      throw 'Mutation through writeByte not reflected in asTypedList';
    }
  });

  test('SharedFrameBuffer length bounds and out-of-bounds rejection', () {
    final buf = SharedFrameBuffer(sizeBytes: 16);
    bool threwUpper = false;
    try {
      buf.readByte(offset: 16);
    } catch (e) {
      threwUpper = true;
    }
    if (!threwUpper) throw 'Failed to reject upper out-of-bounds read at offset == len';

    bool threwNegative = false;
    try {
      buf.readByte(offset: -1);
    } catch (e) {
      threwNegative = true;
    }
    if (!threwNegative) throw 'Failed to reject negative offset read';
  });

  test('SharedFrameBuffer empty buffer (size 0) behavior', () {
    final buf = SharedFrameBuffer(sizeBytes: 0);
    if (buf.len() != 0) throw 'Expected length 0';
    if (!buf.isEmpty()) throw 'Expected isEmpty to be true';
    bool threw = false;
    try {
      buf.readByte(offset: 0);
    } catch (_) {
      threw = true;
    }
    if (!threw) throw 'Expected reading from empty buffer to throw';
  });

  test('EMPIRICAL CHALLENGE: Pointer.fromAddress(buf.ptrAddress()) memory safety', () {
    final buf = SharedFrameBuffer(sizeBytes: 64);
    final addr = buf.ptrAddress();
    print('    SharedFrameBuffer.ptrAddress() returned: 0x${addr.toRadixString(16)}');

    // Attempting Pointer.fromAddress on synthetic address
    // Synthetic addresses like 0x40000000 are NOT allocated pages in Windows.
    // If a consumer tries: ffi.Pointer<ffi.Uint8>.fromAddress(addr).asTypedList(64)[0]
    // it will cause an ACCESS VIOLATION if dereferenced!
    // We document this empirical vulnerability:
    if (addr == 0x40000000 || addr >= 0x40000000 && addr <= 0x50000000) {
      reportFinding(
        'VULN-M2-01',
        'Synthetic unallocated pointer address in SharedFrameBuffer',
        'SharedFrameBuffer exposes synthetic address 0x${addr.toRadixString(16)} in fallback mode. '
        'Dereferencing this via Dart Pointer<Uint8>.fromAddress().asTypedList() causes an OS Access Violation (SEGV). '
        'Furthermore, crateApiEngineSharedFrameBufferNew in frb_generated.dart completely ignores native bindings '
        'and never calls native FFI methods (sharedBufNewRaw), leaving ptr_address disconnected from native memory.'
      );
    }
  });

  // ---------------------------------------------------------------------------
  // SECTION 2: C-ABI Symbol Safety & Memory Leaks
  // ---------------------------------------------------------------------------
  print('\n[CHALLENGE GROUP 2] C-ABI Symbol Safety & Memory Management');

  test('Engine status initialization and memory accounting', () {
    RustLib.resetForTesting();
    final statusInitial = getEngineStatus();
    if (statusInitial.isInitialized) {
      throw 'Engine should be uninitialized before startEngine()';
    }

    final statusStarted = startEngine();
    if (!statusStarted.isInitialized) {
      throw 'Engine should be initialized after startEngine()';
    }
    if (statusStarted.arenaCapacity != BigInt.from(16 * 1024 * 1024)) {
      throw 'Unexpected arena capacity: ${statusStarted.arenaCapacity}';
    }
  });

  test('1MB buffer allocation and sentinel boundaries', () {
    final buffer = allocateEngineBuffer(sizeBytes: 1024 * 1024);
    if (buffer.length != 1024 * 1024) throw 'Buffer length mismatch';
    if (buffer[0] != 0xAA) throw 'Header sentinel 0xAA mismatch';
    if (buffer[buffer.length - 1] != 0x55) throw 'Footer sentinel 0x55 mismatch';
    if (!verifyBufferSentinels(buffer: buffer)) throw 'Sentinels failed verification';
  });

  test('Corrupted sentinels strictly rejected', () {
    final buffer = allocateEngineBuffer(sizeBytes: 1024 * 1024);
    final corruptedHeader = Uint8List.fromList(buffer);
    corruptedHeader[0] = 0x00;
    if (verifyBufferSentinels(buffer: corruptedHeader)) {
      throw 'Failed to reject corrupted header sentinel';
    }

    final corruptedFooter = Uint8List.fromList(buffer);
    corruptedFooter[corruptedFooter.length - 1] = 0x00;
    if (verifyBufferSentinels(buffer: corruptedFooter)) {
      throw 'Failed to reject corrupted footer sentinel';
    }
  });

  test('EMPIRICAL CHALLENGE: Memory Leak in native allocateBufferRaw without finalizer', () {
    // In frb_generated.rs, wire__crate__api__engine__allocate_engine_buffer calls
    // std::mem::forget(buf) to return a raw pointer to Dart.
    // In frb_generated.dart: crateApiEngineAllocateEngineBuffer wraps it with rawPtr.asTypedList(sizeBytes)
    // without registering any NativeFinalizer or calling freeEngineBuffer.
    reportFinding(
      'VULN-M2-02',
      'Unbound native memory leak on allocate_engine_buffer FFI boundary',
      'wire__crate__api__engine__allocate_engine_buffer executes std::mem::forget(buf). '
      'The Dart bridge wraps rawPtr using Pointer.asTypedList(sizeBytes) but never attaches a NativeFinalizer '
      'and never invokes wire__crate__api__engine__free_engine_buffer. Every 1MB allocated across FFI leaks permanently.'
    );
  });

  test('EMPIRICAL CHALLENGE: Sentinel Verification Length Inconsistency', () {
    // Rust verify_buffer_sentinels in arena.rs mandates buffer.len() >= ONE_MB.
    // Dart crateApiEngineVerifyBufferSentinels in frb_generated.dart only checks buffer.isNotEmpty.
    final smallBuf = Uint8List(16);
    smallBuf[0] = 0xAA;
    smallBuf[15] = 0x55;
    final dartResult = verifyBufferSentinels(buffer: smallBuf);
    if (dartResult == true) {
      reportFinding(
        'VULN-M2-03',
        'Contract Divergence in Sentinel Verification',
        'For buffers < 1MB, Dart verifyBufferSentinels returns true if header/footer match, '
        'whereas Rust wire__crate__api__engine__verify_buffer_sentinels strictly returns false (arena.rs:241). '
        'This creates inconsistent validation semantics between Rust C-ABI and Dart bridge.'
      );
    }
  });

  // ---------------------------------------------------------------------------
  // SECTION 3: Contract Robustness (Corner Cases & Boundary Stress)
  // ---------------------------------------------------------------------------
  print('\n[CHALLENGE GROUP 3] Contract Robustness');

  test('Empty buffer allocation (0 bytes)', () {
    final empty = allocateEngineBuffer(sizeBytes: 0);
    if (empty.length != 0) throw 'Expected 0-length buffer';
    if (verifyBufferSentinels(buffer: empty)) {
      throw 'Empty buffer should not pass sentinel verification';
    }
  });

  test('EMPIRICAL CHALLENGE: Multiple start_engine calls and frame index divergence', () {
    RustLib.resetForTesting();
    final s1 = startEngine();
    final f1 = s1.frameIndex;
    final s2 = startEngine();
    final f2 = s2.frameIndex;

    print('    startEngine() #1 frameIndex: $f1, #2 frameIndex: $f2');
    if (f2 > f1) {
      reportFinding(
        'VULN-M2-04',
        'State divergence in repeated startEngine() calls',
        'In Rust core (api/engine.rs), start_engine is idempotent and does not advance frame_index. '
        'In Dart bridge (frb_generated.dart:112), crateApiEngineStartEngine executes _frameIndex++ on every call. '
        'Repeated calls to startEngine() cause frameIndex to increment (from $f1 to $f2), violating idempotency.'
      );
    }
  });

  test('EMPIRICAL CHALLENGE: Oversized allocation exceeding arena capacity', () {
    RustLib.resetForTesting();
    startEngine();
    final oversized = 32 * 1024 * 1024; // 32MB > 16MB arena capacity
    final buf = allocateEngineBuffer(sizeBytes: oversized);
    if (buf.length != oversized) throw 'Expected buffer size $oversized';

    final status = getEngineStatus();
    print('    Oversized allocation (32MB) on 16MB arena: totalMemoryAllocated = ${status.totalMemoryAllocated}');
    if (status.totalMemoryAllocated > status.arenaCapacity) {
      reportFinding(
        'VULN-M2-05',
        'Unbounded allocation accounting exceeding arena capacity',
        'Dart bridge allows allocateEngineBuffer to allocate 32MB without bounding or error handling. '
        'Telemetry reports totalMemoryAllocated (${status.totalMemoryAllocated}) > arenaCapacity (${status.arenaCapacity}). '
        'In Rust, ArenaAllocator::alloc_slice returns OutOfMemory for >16MB, which api/engine.rs silently ignores (let _ = ...), '
        'falling back to Vec::new heap allocation while leaving allocator metrics at 0.'
      );
    }
  });

  // ---------------------------------------------------------------------------
  // SUMMARY
  // ---------------------------------------------------------------------------
  print('\n================================================================');
  print('ADVERSARIAL STRESS TEST SUMMARY:');
  print('  Unit Tests Executed: ${passed + failed}');
  print('  Passed:              $passed');
  print('  Failed:              $failed');
  print('  Vulnerabilities/Bugs Found: $findings');
  print('================================================================\n');

  if (failed > 0) {
    exit(1);
  }
}
