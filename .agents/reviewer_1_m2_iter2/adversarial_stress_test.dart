// Adversarial Stress-Test Suite for Milestone 2 Iteration 2
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import '../../fluorite_editor/lib/src/rust/api/engine.dart';
import '../../fluorite_editor/lib/src/rust/frb_generated.dart';

void main() {
  print('=== START ADVERSARIAL STRESS TESTING ===');
  RustLib.resetForTesting();
  RustLib.initSync();

  int totalChallenges = 0;
  int passedChallenges = 0;

  void challenge(String name, void Function() fn) {
    totalChallenges++;
    try {
      fn();
      passedChallenges++;
      print('  [PASS] $name');
    } catch (e, st) {
      print('  [FAIL] $name: $e');
      print(st);
    }
  }

  // 1. Extreme Size Allocations
  challenge('Stress: 10MB buffer allocation and sentinel placement', () {
    const tenMb = 10 * 1024 * 1024;
    final buf = allocateEngineBuffer(sizeBytes: tenMb);
    if (buf.length != tenMb) throw Exception('Expected 10MB buffer');
    if (buf[0] != 0xAA) throw Exception('Header sentinel corrupted');
    if (buf[tenMb - 1] != 0x55) throw Exception('Footer sentinel corrupted');
    if (!verifyBufferSentinels(buffer: buf)) throw Exception('Sentinels failed verification');
  });

  // 2. High-volume SharedFrameBuffer allocations and real pointer dereferencing
  challenge('Stress: 500 consecutive SharedFrameBuffers dereferenced via ffi.Pointer', () {
    for (int i = 0; i < 500; i++) {
      final size = 128 + (i % 256);
      final sfb = SharedFrameBuffer(sizeBytes: size);
      final addr = sfb.ptrAddress();
      if (addr == 0 || addr == 0x40000000) {
        throw Exception('Invalid pointer address: 0x${addr.toRadixString(16)}');
      }
      final ptr = ffi.Pointer<ffi.Uint8>.fromAddress(addr);
      final view = ptr.asTypedList(size);
      if (view[0] != 0xDE || view[1] != 0xAD || view[2] != 0xBE || view[3] != 0xEF) {
        throw Exception('DEADBEEF corrupted at iteration $i');
      }
      // Mutate via pointer directly
      view[10] = (i & 0xFF);
      if (sfb.readByte(offset: 10) != (i & 0xFF)) {
        throw Exception('Direct pointer mutation not reflected in sfb.readByte at iteration $i');
      }
    }
  });

  // 3. Out of Bounds safety on SharedFrameBuffer
  challenge('Adversarial: Bounds checking on readByte and writeByte', () {
    final sfb = SharedFrameBuffer(sizeBytes: 10);
    // Boundary offset: len
    bool caughtReadAtLen = false;
    try {
      sfb.readByte(offset: 10);
    } catch (e) {
      caughtReadAtLen = true;
    }
    if (!caughtReadAtLen) throw Exception('readByte(10) did not throw RangeError on len=10');

    bool caughtWriteAtLen = false;
    try {
      sfb.writeByte(offset: 10, value: 42);
    } catch (e) {
      caughtWriteAtLen = true;
    }
    if (!caughtWriteAtLen) throw Exception('writeByte(10) did not throw RangeError on len=10');

    // Negative offset
    bool caughtReadNeg = false;
    try {
      sfb.readByte(offset: -1);
    } catch (e) {
      caughtReadNeg = true;
    }
    if (!caughtReadNeg) throw Exception('readByte(-1) did not throw');

    // Huge offset
    bool caughtReadHuge = false;
    try {
      sfb.readByte(offset: 1000000);
    } catch (e) {
      caughtReadHuge = true;
    }
    if (!caughtReadHuge) throw Exception('readByte(1000000) did not throw');
  });

  // 4. Sentinel Ladder Challenge: sizes 0, 1, 2, 3, 4, 1024, 1MB
  challenge('Adversarial: Sentinel ladder across various sizes', () {
    // 0 bytes
    final b0 = allocateEngineBuffer(sizeBytes: 0);
    if (verifyBufferSentinels(buffer: b0)) throw Exception('0-byte buffer must not pass sentinels');

    // 1 byte: should have header (0xAA) only, NOT footer, must NOT pass verify (needs >= 2)
    final b1 = allocateEngineBuffer(sizeBytes: 1);
    if (b1[0] != 0xAA) throw Exception('1-byte buffer header must be 0xAA');
    if (verifyBufferSentinels(buffer: b1)) throw Exception('1-byte buffer cannot pass verifyBufferSentinels');

    // 2 bytes: header at 0, footer at 1. Must pass!
    final b2 = allocateEngineBuffer(sizeBytes: 2);
    if (b2[0] != 0xAA || b2[1] != 0x55) throw Exception('2-byte sentinels invalid');
    if (!verifyBufferSentinels(buffer: b2)) throw Exception('2-byte buffer must pass verifyBufferSentinels');

    // 3 bytes: header at 0, 0 in middle, footer at 2. Must pass!
    final b3 = allocateEngineBuffer(sizeBytes: 3);
    if (b3[0] != 0xAA || b3[1] != 0x00 || b3[2] != 0x55) throw Exception('3-byte sentinels invalid');
    if (!verifyBufferSentinels(buffer: b3)) throw Exception('3-byte buffer must pass verifyBufferSentinels');

    // Corrupted footer in 2-byte buffer
    final b2Corrupted = Uint8List.fromList([0xAA, 0x00]);
    if (verifyBufferSentinels(buffer: b2Corrupted)) throw Exception('Corrupted 2-byte buffer must fail');
  });

  // 5. Dynamic sizeBytes type polymorphism (int vs BigInt)
  challenge('Adversarial: allocateEngineBuffer accepts both int and BigInt', () {
    final bInt = allocateEngineBuffer(sizeBytes: 1024);
    if (bInt.length != 1024) throw Exception('int sizeBytes failed');

    final bBigInt = allocateEngineBuffer(sizeBytes: BigInt.from(1024));
    if (bBigInt.length != 1024) throw Exception('BigInt sizeBytes failed');
  });

  // 6. Rapid startEngine idempotency and memory retention
  challenge('Adversarial: Rapid idempotent startEngine calls do not reset memory', () {
    RustLib.resetForTesting();
    startEngine();
    allocateEngineBuffer(sizeBytes: 1024 * 1024);
    final s1 = getEngineStatus();
    if (s1.totalMemoryAllocated < BigInt.from(1024 * 1024)) {
      throw Exception('Memory not tracked');
    }

    // Call startEngine 10 more times
    for (int i = 0; i < 10; i++) {
      final s = startEngine();
      if (!s.isInitialized) throw Exception('Engine became uninitialized');
      if (s.totalMemoryAllocated < BigInt.from(1024 * 1024)) {
        throw Exception('Memory was reset during subsequent startEngine call');
      }
    }
  });

  // 7. SharedFrameBuffer 0-byte edge case
  challenge('Adversarial: SharedFrameBuffer with sizeBytes=0', () {
    final sfb0 = SharedFrameBuffer(sizeBytes: 0);
    if (sfb0.len() != 0) throw Exception('Expected len=0');
    if (!sfb0.isEmpty()) throw Exception('Expected isEmpty()=true');
    if (sfb0.asTypedList().isNotEmpty) throw Exception('Expected empty typed list');
  });

  print('\n=== ADVERSARIAL STRESS RESULTS: $passedChallenges / $totalChallenges PASSED ===');
  if (passedChallenges != totalChallenges) {
    throw Exception('Some adversarial challenges failed!');
  }
}
