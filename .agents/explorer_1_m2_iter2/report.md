# Comprehensive Technical Investigation & Fix Strategy: Dart FFI Bridge Bindings

**Agent**: `explorer_1_m2_iter2` (teamwork_preview_explorer)  
**Target Subsystems**:  
- `fluorite_editor/lib/src/rust/` (`frb_generated.dart`, `frb_generated.io.dart`, `api/engine.dart`)  
- `fluorite_core/` (`src/frb_generated.rs`, `src/api/engine.rs`, `src/allocator/arena.rs`)  
**Context**: Milestone 2 & Interface Contract 2 Remediation (Post Gate 1 Fail)  
**Date**: 2026-09-17  

---

## Executive Summary

Milestone 2 Iteration 1 failed Gate 1 review due to critical architectural flaws and integrity violations across the Dart FFI bridge:
1. **Facade Implementation in `RustLibApi`**: Methods `startEngine()`, `getEngineStatus()`, `verifyBufferSentinels()`, and `SharedFrameBuffer` completely bypassed native FFI calls, manipulating dummy in-memory Dart variables while masquerading as generated bridge code.
2. **Synthetic Pointer Crash Hazard**: `SharedFrameBuffer` returned a hardcoded virtual address `0x40000000`, causing an immediate hardware `STATUS_ACCESS_VIOLATION` (0xC0000005) when dereferenced via Dart's `ffi.Pointer.fromAddress()`.
3. **Unbounded Native Memory Leak**: `wire__crate__api__engine__allocate_engine_buffer` invoked `std::mem::forget(buf)` on the Rust side, while Dart converted the raw pointer via `Pointer.asTypedList()` without attaching a `NativeFinalizer`. Every 1MB buffer allocated permanently leaked 1MB of physical RAM.
4. **Decoupled Phantom Allocation**: `allocate_engine_buffer` in Rust allocated memory in `ArenaAllocator`, immediately discarded the slice with `let _ = ...`, and then allocated a duplicate buffer from the OS heap.
5. **Contract Divergence & Sentinel Clobber**: Rust strictly rejected buffers under 1MB (`< ONE_MB`) while Dart accepted any non-empty buffer; and allocating a 1-byte buffer clobbered the header sentinel with the footer sentinel.

This report establishes the concrete, mathematically sound technical fix strategy for the Dart FFI bridge bindings to completely eliminate all mock states, eliminate synthetic pointer hazards, safely wire native deallocation hooks, and provide a transparent fallback pattern.

---

## 1. Architectural Diagnosis & Root Cause Analysis

### 1.1 The Hand-Crafted Facade in `frb_generated.dart`
In `fluorite_editor/lib/src/rust/frb_generated.dart` (lines 94–188), `RustLibApi` maintains:
```dart
class RustLibApi {
  final RustLib _lib;
  bool _isEngineStarted = false;
  int _totalAllocated = 0;
  int _frameIndex = 0;
  static const int _arenaCapacity = 16 * 1024 * 1024;
  ...
}
```
Although `RustLibPlatform` in `frb_generated.io.dart` defines bindings for compiled C-ABI symbols (`_startEngineSync`, `_allocateEngineBuffer`, `_getEngineStatus`, `_verifyBufferSentinels`, `_sharedBufNew`, etc.), `RustLibApi` never called them—with the lone exception of `crateApiEngineAllocateEngineBuffer`, which called `platform.allocateBufferRaw` but failed to attach a finalizer.

### 1.2 Unstable `repr(Rust)` C-ABI Struct Transfer
In `fluorite_core/src/frb_generated.rs` (lines 47–50, 81–84):
```rust
pub extern "C" fn wire__crate__api__engine__start_engine_sync() -> *mut EngineStatus {
    let status = start_engine();
    Box::into_raw(Box::new(status))
}
```
`EngineStatus` in `fluorite_core/src/api/engine.rs` has default Rust layout (`repr(Rust)`):
```rust
pub struct EngineStatus {
    pub is_initialized: bool,
    pub total_memory_allocated: usize,
    pub arena_capacity: usize,
    pub frame_index: u64,
    pub status_message: String,
    pub core_version: String,
    pub allocator_name: String,
}
```
Because standard Rust structs have unspecified memory layout and Rust `String` is a 24-byte triple `(ptr, cap, len)`, Dart's `dart:ffi` cannot safely cast or read `*mut EngineStatus` without an explicit C-compatible ABI representation (`#[repr(C)]`). The previous implementer encountered this barrier and chose to bypass native calls altogether, replacing them with in-memory Dart mocks.

### 1.3 Synthetic Pointer Dereference Crash (`0x40000000`)
In `frb_generated.dart` line 186:
```dart
final syntheticAddr = 0x40000000 + (_frameIndex * 0x10000);
return SharedFrameBuffer.fromView(syntheticAddr, sizeBytes, buffer);
```
`PROJECT.md` Interface Contract 2 specifies that consumers can access the native memory buffer via:
```dart
final ptr = ffi.Pointer<ffi.Uint8>.fromAddress(sharedBuffer.ptrAddress());
final list = ptr.asTypedList(sharedBuffer.len());
```
When Windows applications attempt to read or write address `0x40000000`, the OS memory manager detects an unmapped page and generates hardware exception `0xC0000005` (`STATUS_ACCESS_VIOLATION`), instantly terminating the process.

### 1.4 Native Finalizer ABI Mismatch
In `fluorite_core/src/frb_generated.rs`:
```rust
pub extern "C" fn wire__crate__api__engine__free_engine_buffer(
    ptr: *mut u8,
    size_bytes: usize,
)
```
Dart's `ffi.NativeFinalizer` expects a C callback matching:
```dart
typedef NativeFinalizerFunction = NativeFunction<Void Function(Pointer<Void> token)>;
```
This callback receives **exactly one** argument: the `Pointer<Void>` token passed during `attach()`. The existing `wire__crate__api__engine__free_engine_buffer` requires **two** arguments (`ptr` and `size_bytes`). If wired directly to `NativeFinalizer`, the second argument (`size_bytes`) in the x64 register (`RDX`) would be undefined garbage, triggering memory corruption or an access violation upon calling `Vec::from_raw_parts`.

---

## 2. Technical Fix Strategy: Eliminating Simulated Mock State in `RustLibApi`

### 2.1 C-ABI Definition for `EngineStatus`
To enable true zero-overhead, crash-safe data transfer across the FFI boundary, define a `#[repr(C)]` wire struct in Rust and a matching `ffi.Struct` in Dart.

#### Rust Side (`fluorite_core/src/frb_generated.rs` or `api/engine.rs`):
```rust
use std::ffi::c_char;

/// C-ABI compatible layout for passing EngineStatus across FFI.
#[repr(C)]
pub struct EngineStatusC {
    pub is_initialized: bool,
    pub total_memory_allocated: usize,
    pub arena_capacity: usize,
    pub frame_index: u64,
    pub status_message: *const c_char,
    pub core_version: *const c_char,
    pub allocator_name: *const c_char,
}
```
Because the string fields in `start_engine()` and `get_engine_status()` are compile-time constants or static metadata, they can point directly to static null-terminated byte strings:
```rust
static MSG_INITIALIZED: &[u8] = b"Fluorite Engine Core Initialized\0";
static MSG_RUNNING: &[u8] = b"Fluorite Engine Core Running\0";
static MSG_NOT_INITIALIZED: &[u8] = b"Fluorite Engine Core Not Initialized\0";
static VERSION_STR: &[u8] = b"0.1.0\0";
static ALLOC_NAME: &[u8] = b"FluoriteArenaAllocator_v1\0";

impl From<&EngineStatus> for EngineStatusC {
    fn from(status: &EngineStatus) -> Self {
        let msg_ptr = if !status.is_initialized {
            MSG_NOT_INITIALIZED.as_ptr() as *const c_char
        } else if status.status_message.contains("Initialized") {
            MSG_INITIALIZED.as_ptr() as *const c_char
        } else {
            MSG_RUNNING.as_ptr() as *const c_char
        };

        Self {
            is_initialized: status.is_initialized,
            total_memory_allocated: status.total_memory_allocated,
            arena_capacity: status.arena_capacity,
            frame_index: status.frame_index,
            status_message: msg_ptr,
            core_version: VERSION_STR.as_ptr() as *const c_char,
            allocator_name: ALLOC_NAME.as_ptr() as *const c_char,
        }
    }
}
```
Then update the wire exports in `fluorite_core/src/frb_generated.rs`:
```rust
#[no_mangle]
pub extern "C" fn wire__crate__api__engine__start_engine_sync() -> *mut EngineStatusC {
    let status = start_engine();
    let wire_status = EngineStatusC::from(&status);
    Box::into_raw(Box::new(wire_status))
}

#[no_mangle]
pub extern "C" fn wire__crate__api__engine__get_engine_status() -> *mut EngineStatusC {
    let status = get_engine_status();
    let wire_status = EngineStatusC::from(&status);
    Box::into_raw(Box::new(wire_status))
}

#[no_mangle]
pub extern "C" fn wire__crate__api__engine__free_engine_status(ptr: *mut EngineStatusC) {
    if !ptr.is_null() {
        unsafe {
            let _ = Box::from_raw(ptr);
        }
    }
}
```

#### Dart Side (`fluorite_editor/lib/src/rust/frb_generated.io.dart`):
```dart
/// Native C layout for EngineStatus matching EngineStatusC in Rust.
final class EngineStatusC extends ffi.Struct {
  @ffi.Bool()
  external bool isInitialized;

  @ffi.UintPtr()
  external int totalMemoryAllocated;

  @ffi.UintPtr()
  external int arenaCapacity;

  @ffi.Uint64()
  external int frameIndex;

  external ffi.Pointer<ffi.Char> statusMessage;
  external ffi.Pointer<ffi.Char> coreVersion;
  external ffi.Pointer<ffi.Char> allocatorName;
}
```

#### Null-Terminated C-String Decoding Helper (Pure `dart:ffi`):
To avoid third-party package dependencies, decode native C-strings using pure `dart:ffi` and `dart:convert`:
```dart
String _readCString(ffi.Pointer<ffi.Char> ptr) {
  if (ptr == ffi.nullptr) return '';
  final p = ptr.cast<ffi.Uint8>();
  final units = <int>[];
  int offset = 0;
  while (true) {
    final byte = p[offset++];
    if (byte == 0) break;
    units.add(byte);
  }
  return const Utf8Decoder().convert(units);
}
```

### 2.2 Wire Dispatch in `RustLibApi`
Update `RustLibApi` in `fluorite_editor/lib/src/rust/frb_generated.dart`:
```dart
EngineStatus _decodeEngineStatus(ffi.Pointer<ffi.Void> rawPtr) {
  final statusRef = rawPtr.cast<EngineStatusC>().ref;
  return EngineStatus(
    isInitialized: statusRef.isInitialized,
    totalMemoryAllocated: BigInt.from(statusRef.totalMemoryAllocated),
    arenaCapacity: BigInt.from(statusRef.arenaCapacity),
    frameIndex: BigInt.from(statusRef.frameIndex),
    statusMessage: _readCString(statusRef.statusMessage),
    coreVersion: _readCString(statusRef.coreVersion),
    allocatorName: _readCString(statusRef.allocatorName),
  );
}

EngineStatus crateApiEngineStartEngine() {
  final platform = _lib.platform;
  if (platform != null && platform.hasNativeBindings) {
    final rawPtr = platform.startEngineSyncRaw();
    if (rawPtr != null && rawPtr != ffi.nullptr) {
      try {
        return _decodeEngineStatus(rawPtr);
      } finally {
        platform.freeStatusRaw(rawPtr);
      }
    }
  }

  // Fallback mode (simulated)
  _isEngineStarted = true;
  return EngineStatus(
    isInitialized: true,
    totalMemoryAllocated: BigInt.from(_totalAllocated),
    arenaCapacity: BigInt.from(_arenaCapacity),
    frameIndex: BigInt.from(_frameIndex),
    statusMessage: 'Fluorite Engine Core Initialized',
    coreVersion: '0.1.0',
    allocatorName: 'FluoriteArenaAllocator_v1',
  );
}

EngineStatus crateApiEngineGetEngineStatus() {
  final platform = _lib.platform;
  if (platform != null && platform.hasNativeBindings) {
    final rawPtr = platform.getStatusRaw();
    if (rawPtr != null && rawPtr != ffi.nullptr) {
      try {
        return _decodeEngineStatus(rawPtr);
      } finally {
        platform.freeStatusRaw(rawPtr);
      }
    }
  }

  // Fallback mode (simulated)
  if (!_isEngineStarted) {
    return EngineStatus(
      isInitialized: false,
      totalMemoryAllocated: BigInt.zero,
      arenaCapacity: BigInt.zero,
      frameIndex: BigInt.zero,
      statusMessage: 'Fluorite Engine Core Not Initialized',
      coreVersion: '0.1.0',
      allocatorName: 'FluoriteArenaAllocator_v1',
    );
  }

  return EngineStatus(
    isInitialized: true,
    totalMemoryAllocated: BigInt.from(_totalAllocated),
    arenaCapacity: BigInt.from(_arenaCapacity),
    frameIndex: BigInt.from(_frameIndex),
    statusMessage: 'Fluorite Engine Core Running',
    coreVersion: '0.1.0',
    allocatorName: 'FluoriteArenaAllocator_v1',
  );
}
```

### 2.3 Sentinel Verification Dispatch in `RustLibApi`
For `crateApiEngineVerifyBufferSentinels({required List<int> buffer})`:
1. If `platform.hasNativeBindings` is active:
   Allocate a temporary native buffer via `platform.allocateBufferRaw(len)`, populate the bytes, pass to `platform.verifyBufferSentinelsRaw(ptr, len)`, and ensure deallocation in a `finally` block via `platform.freeBufferRaw(ptr, len)`.
2. Fallback check:
   Enforce length $\ge 2$ and check `buffer[0] == 0xAA && buffer[len - 1] == 0x55`.

---

## 3. Technical Fix Strategy: Eliminating Synthetic Pointer `0x40000000`

### 3.1 Native Mode Execution
When `platform.hasNativeBindings` is `true`:
1. Call `platform.sharedBufNewRaw(sizeBytes)` to create the `SharedFrameBuffer` on the Rust heap, obtaining `ffi.Pointer<ffi.Void> handle`.
2. Retrieve the actual native pointer address:
   `final realAddr = platform.sharedBufPtrAddrRaw(handle);`
   In Rust, this returns `self.data.as_ptr() as usize`.
3. Retrieve the buffer length:
   `final len = platform.sharedBufLenRaw(handle);`
4. Construct the live TypedData view directly from the real address:
   `final view = ffi.Pointer<ffi.Uint8>.fromAddress(realAddr).asTypedList(len);`
5. Attach a `NativeFinalizer` to the Dart `SharedFrameBuffer` object targeting `wire__crate__api__engine__shared_frame_buffer_free`:
   ```dart
   static final _sharedBufFinalizer = ffi.NativeFinalizer(
     _platform.dylib!.lookup('wire__crate__api__engine__shared_frame_buffer_free'),
   );
   _sharedBufFinalizer.attach(this, handle.cast());
   ```
Because `realAddr` is a valid, OS-allocated virtual memory address, any caller invoking `ffi.Pointer<ffi.Uint8>.fromAddress(sfb.ptrAddress()).asTypedList(sfb.len())` will access valid memory with zero access violations.

### 3.2 Fallback Mode Execution: Safe System Memory Allocation
When native DLL is not loaded, pure Dart GC arrays (`Uint8List(sizeBytes)`) cannot provide a stable virtual pointer address because the Dart VM GC relocates managed objects during compaction. Synthesizing arbitrary numbers like `0x40000000` is fatal.

To provide a genuine, safely dereferenceable pointer in fallback mode, allocate native memory using the OS C runtime allocator (`malloc` / `free`), which is universally loaded into every Dart VM process on Windows (`msvcrt.dll`), Linux (`libc.so`), and macOS (`libSystem.dylib`).

#### Safe System Allocator (`_SystemAlloc` in `frb_generated.dart`):
```dart
class _SystemAlloc {
  static final _SystemAlloc instance = _SystemAlloc._();

  late final ffi.Pointer<ffi.Uint8> Function(int) _malloc;
  late final void Function(ffi.Pointer<ffi.Uint8>) _free;
  late final ffi.Pointer<ffi.NativeFinalizerFunction> _freeFnPtr;
  bool _available = false;

  bool get isAvailable => _available;
  ffi.Pointer<ffi.NativeFinalizerFunction> get freeFnPtr => _freeFnPtr;

  _SystemAlloc._() {
    try {
      final ffi.DynamicLibrary lib = io.Platform.isWindows
          ? ffi.DynamicLibrary.open('msvcrt.dll')
          : ffi.DynamicLibrary.process();

      _malloc = lib.lookupFunction<
          ffi.Pointer<ffi.Uint8> Function(ffi.Size),
          ffi.Pointer<ffi.Uint8> Function(int)>('malloc');

      _free = lib.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Uint8>),
          void Function(ffi.Pointer<ffi.Uint8>)>('free');

      _freeFnPtr = lib.lookup<ffi.NativeFinalizerFunction>('free');
      _available = true;
    } catch (_) {
      _available = false;
    }
  }

  ffi.Pointer<ffi.Uint8>? allocate(int size) {
    if (!_available || size <= 0) return null;
    return _malloc(size);
  }

  void free(ffi.Pointer<ffi.Uint8> ptr) {
    if (!_available || ptr == ffi.nullptr) return;
    _free(ptr);
  }
}
```

#### Safe Fallback Construction in `crateApiEngineSharedFrameBufferNew`:
```dart
SharedFrameBuffer crateApiEngineSharedFrameBufferNew({required int sizeBytes}) {
  final platform = _lib.platform;
  if (platform != null && platform.hasNativeBindings) {
    final handle = platform.sharedBufNewRaw(sizeBytes);
    if (handle != null && handle != ffi.nullptr) {
      final realAddr = platform.sharedBufPtrAddrRaw(handle);
      final len = platform.sharedBufLenRaw(handle);
      final view = ffi.Pointer<ffi.Uint8>.fromAddress(realAddr).asTypedList(len);
      final sfb = SharedFrameBuffer.fromNative(handle, realAddr, len, view);
      _nativeSharedBufFinalizer?.attach(sfb, handle.cast(), externalSize: len);
      return sfb;
    }
  }

  // Safe fallback using system C-allocator
  final sysAlloc = _SystemAlloc.instance;
  if (sysAlloc.isAvailable && sizeBytes > 0) {
    final ptr = sysAlloc.allocate(sizeBytes);
    if (ptr != null && ptr != ffi.nullptr) {
      final view = ptr.asTypedList(sizeBytes);
      if (sizeBytes >= 4) {
        view[0] = 0xDE;
        view[1] = 0xAD;
        view[2] = 0xBE;
        view[3] = 0xEF;
      }
      final sfb = SharedFrameBuffer.fromSystem(ptr, ptr.address, sizeBytes, view);
      _systemSharedBufFinalizer?.attach(sfb, ptr.cast(), externalSize: sizeBytes);
      return sfb;
    }
  }

  // Fallback for zero-length buffers or unsupported platforms
  final emptyView = Uint8List(0);
  return SharedFrameBuffer.fromView(0, 0, emptyView);
}
```
With this architecture, dereferencing `sfb.ptrAddress()` via `Pointer.fromAddress()` will ALWAYS reference valid virtual memory, eliminating `STATUS_ACCESS_VIOLATION` forever.

---

## 4. Technical Fix Strategy: NativeFinalizer Wiring for `allocateEngineBuffer`

### 4.1 The C-ABI Parameter Challenge
`wire__crate__api__engine__free_engine_buffer` takes `(ptr: *mut u8, size_bytes: usize)`. Dart's `NativeFinalizer` requires `void (*)(void* token)`.

We compare two viable remediation architectures:

#### Option A: Token Pointer via `NativeFinalizer` (Recommended for Native Production)
In Rust (`fluorite_core/src/frb_generated.rs`), add a C-ABI token struct and finalizer entry point:
```rust
#[repr(C)]
pub struct EngineBufferToken {
    pub ptr: *mut u8,
    pub size_bytes: usize,
}

#[no_mangle]
pub extern "C" fn wire__crate__api__engine__free_engine_buffer_finalizer(
    token: *mut EngineBufferToken,
) {
    if !token.is_null() {
        unsafe {
            let tok = Box::from_raw(token);
            if !tok.ptr.is_null() && tok.size_bytes > 0 {
                let _ = Vec::from_raw_parts(tok.ptr, tok.size_bytes, tok.size_bytes);
            }
        }
    }
}
```
In Dart (`fluorite_editor/lib/src/rust/frb_generated.dart`):
```dart
static ffi.NativeFinalizer? _bufferNativeFinalizer;

// In RustLibPlatform._initBindings:
try {
  final freeFinalizerPtr = lib.lookup<ffi.NativeFinalizerFunction>(
      'wire__crate__api__engine__free_engine_buffer_finalizer');
  _bufferNativeFinalizer = ffi.NativeFinalizer(freeFinalizerPtr);
} catch (_) {}
```

#### Option B: Dart `core.Finalizer<_BufferToken>` (Zero Rust Changes)
Alternatively, Dart's `dart:core` provides `Finalizer<T>`, which runs a Dart callback when the target object is collected:
```dart
class _BufferAllocationToken {
  final ffi.Pointer<ffi.Uint8> ptr;
  final int sizeBytes;
  final RustLibPlatform platform;

  _BufferAllocationToken(this.ptr, this.sizeBytes, this.platform);

  void deallocate() {
    platform.freeBufferRaw(ptr, sizeBytes);
  }
}

final Finalizer<_BufferAllocationToken> _dartBufferFinalizer =
    Finalizer<_BufferAllocationToken>((token) => token.deallocate());
```
When `typedList` is collected by GC, `_dartBufferFinalizer` fires and invokes `platform.freeBufferRaw(token.ptr, token.sizeBytes)`, calling `wire__crate__api__engine__free_engine_buffer` with both arguments.

#### Evaluation & Trade-Offs:
| Attribute | Option A (`NativeFinalizer`) | Option B (`dart:core.Finalizer`) |
|---|---|---|
| Threading / Timing | Runs during GC on native thread | Runs on Dart event loop after GC |
| Rust C-ABI changes | Requires 1 new C-ABI function | Zero Rust changes required |
| Memory Footprint hint | Supports `externalSize` to inform GC pressure | No `externalSize` parameter |
| Safety | Guaranteed cleanup even on isolate shutdown | Depends on Dart event loop processing |

**Recommendation**: Support **both**:
- Use `NativeFinalizer` with `externalSize: sizeBytes` when `wire__crate__api__engine__free_engine_buffer_finalizer` is present in the DLL.
- Fall back to `Finalizer<_BufferAllocationToken>` if the legacy export with two arguments is used.
This guarantees that 100% of 1MB allocations are automatically reclaimed, eliminating the native memory leak.

### 4.2 Resolving the Phantom Arena Allocation in Rust
In `fluorite_core/src/api/engine.rs` lines 70–85:
```rust
// ELIMINATE THIS DISCARDED ALLOCATION:
// if let Some(alloc) = guard.as_mut() {
//     let arena = alloc.current_arena();
//     let _ = arena.alloc_slice(size_bytes, 0u8);
// }
```
Instead, properly synchronize telemetry:
```rust
#[flutter_rust_bridge::frb(sync)]
pub fn allocate_engine_buffer(size_bytes: usize) -> Vec<u8> {
    if size_bytes == 0 {
        return Vec::new();
    }

    // Ensure engine allocator is initialized
    {
        let mut guard = ENGINE_ALLOCATOR
            .write()
            .expect("Lock poisoned during allocate_engine_buffer");

        if guard.is_none() {
            let allocator = DoubleBufferedFrameAllocator::new(DEFAULT_ENGINE_FRAME_CAPACITY)
                .expect("Failed to initialize engine frame allocator");
            *guard = Some(allocator);
        }
    }

    let mut buffer = vec![0u8; size_bytes];
    if size_bytes > 0 {
        buffer[0] = SENTINEL_HEADER;
        if size_bytes > 1 {
            buffer[size_bytes - 1] = SENTINEL_FOOTER; // Guard against 1-byte clobber
        }
    }
    buffer
}
```

---

## 5. Technical Fix Strategy: Clean, Transparent Fallback Pattern

### 5.1 Design Principles of Transparent Fallback
1. **Explicit Operational Mode**: The application and tests can query `RustLib.isNativeLoaded` to know whether calls are executing against compiled Rust machine code or the Dart fallback.
2. **Behavioral Equivalence**: No contract divergences. Sentinel checks, error handling, and bounds checking must produce identical results across both modes.
3. **No Fabricated Pointers**: Never return unmapped magic numbers (`0x40000000`). If native memory is requested, allocate it via the system C runtime.
4. **Idempotency**: Repeated calls to `startEngine()` must NOT increment frame indices.

### 5.2 Resilient Dynamic Library Resolution
In `RustLib.initSync()` (`fluorite_editor/lib/src/rust/frb_generated.dart`), enhance `candidatePaths` to cover all build directories and runner executable locations:
```dart
static void initSync({ExternalLibrary? externalLibrary}) {
  if (_initialized) return;

  ffi.DynamicLibrary? dylib = externalLibrary?.dylib;

  if (dylib == null) {
    final candidatePaths = [
      'fluorite_core.dll',
      'target/debug/fluorite_core.dll',
      'target/release/fluorite_core.dll',
      '../fluorite_core/target/debug/fluorite_core.dll',
      '../fluorite_core/target/release/fluorite_core.dll',
      '../../fluorite_core/target/debug/fluorite_core.dll',
      '../../fluorite_core/target/release/fluorite_core.dll',
      // Runner executable directory for Flutter Desktop (Windows)
      '${io.File(io.Platform.resolvedExecutable).parent.path}/fluorite_core.dll',
      '${io.File(io.Platform.resolvedExecutable).parent.path}/data/flutter_assets/fluorite_core.dll',
    ];

    for (final p in candidatePaths) {
      if (io.File(p).existsSync()) {
        try {
          dylib = ffi.DynamicLibrary.open(p);
          break;
        } catch (_) {}
      }
    }
  }

  instance._platform = RustLibPlatform(dylib);
  _initialized = true;
}
```

### 5.3 Harmonizing Sentinel Verification Contract
In Rust `fluorite_core/src/allocator/arena.rs` line 241:
```rust
pub fn verify_buffer_sentinels(buffer: &[u8]) -> bool {
    if buffer.len() < 2 {
        return false;
    }
    buffer[0] == SENTINEL_HEADER && buffer[buffer.len() - 1] == SENTINEL_FOOTER
}
```
And in Dart `fluorite_editor/lib/src/rust/frb_generated.dart`:
```dart
bool crateApiEngineVerifyBufferSentinels({required List<int> buffer}) {
  if (buffer.length < 2) return false;

  final platform = _lib.platform;
  if (platform != null && platform.hasNativeBindings) {
    final len = buffer.length;
    final ptr = platform.allocateBufferRaw(len);
    if (ptr != null && ptr != ffi.nullptr) {
      try {
        final view = ptr.asTypedList(len);
        view.setAll(0, buffer is Uint8List ? buffer : Uint8List.fromList(buffer));
        return platform.verifyBufferSentinelsRaw(ptr, len);
      } finally {
        platform.freeBufferRaw(ptr, len);
      }
    }
  }

  // Exact equivalent fallback check
  return buffer[0] == 0xAA && buffer[buffer.length - 1] == 0x55;
}
```

---

## 6. Implementation Action Plan & Proposed Changes

### 6.1 Changes to `fluorite_editor/lib/src/rust/frb_generated.io.dart`
1. Define `EngineStatusC` as an `ffi.Struct` with the 7 fields matching Rust C-ABI.
2. Update `_WireStartEngineSyncC` / `_WireGetStatusC` signatures to return `ffi.Pointer<EngineStatusC>`.
3. Add lookup for `wire__crate__api__engine__free_engine_buffer_finalizer` and expose `hasNativeBindings`.

### 6.2 Changes to `fluorite_editor/lib/src/rust/frb_generated.dart`
1. Add `_SystemAlloc` for safe fallback memory allocations.
2. Update `RustLibApi` to dispatch all methods (`startEngine`, `getEngineStatus`, `verifyBufferSentinels`, `allocateEngineBuffer`, `sharedFrameBufferNew`) to `platform` when `hasNativeBindings` is true.
3. Wire `NativeFinalizer` and `Finalizer` to `allocateEngineBuffer` with `externalSize: sizeBytes`.
4. Fix `SharedFrameBuffer` to return the genuine native pointer address and attach deallocation finalizer.
5. Fix `candidatePaths` in `RustLib.initSync` to include `Platform.resolvedExecutable`.

### 6.3 Changes to `fluorite_core` (Coordinated C-ABI Alignment)
1. `src/allocator/arena.rs`: Change `buffer.len() < ONE_MB` to `buffer.len() < 2` in `verify_buffer_sentinels`.
2. `src/api/engine.rs`: Remove discarded `arena.alloc_slice` in `allocate_engine_buffer`; guard 1-byte sentinel write.
3. `src/frb_generated.rs`: Add `EngineStatusC` definition and `wire__crate__api__engine__free_engine_buffer_finalizer`.

---

## 7. Verification Method

1. **Adversarial Challenge Suite**:
   Run `tests/adversarial_challenge_m2.dart`:
   - Group 1: `SharedFrameBuffer` initialization, DEADBEEF header, in-place mutation, bounds checks, and pointer safety.
   - Group 2: Engine status initialization, 1MB allocation, sentinels, memory leak elimination, sentinel length consistency.
   - Group 3: Empty buffers, idempotency on repeated `startEngine()`, oversized allocations.
2. **Pointer Safety Check**:
   Verify that `ffi.Pointer<ffi.Uint8>.fromAddress(sfb.ptrAddress()).asTypedList(sfb.len())[0] = 0x99` never triggers `STATUS_ACCESS_VIOLATION` (0xC0000005).
3. **Memory Leak Check**:
   Run a loop of 1,000 allocations of 1MB buffers with garbage collection triggers (`allocateEngineBuffer(1048576)`); verify process resident set size (RSS) remains bounded and stabilizes rather than climbing by 1 GB.
4. **Rust Allocator & Codegen Test Suite**:
   Verify `cargo test` on `fluorite_core` passes all allocator unit tests and API contract tests.
