# Project: Fluorite AAA Engine Phase 1

## Architecture
Fluorite Phase 1 establishes the high-performance native foundation of the Fluorite AAA Game Engine, connecting high-performance Rust core systems to a Flutter Desktop Editor via a zero-copy FFI bridge.

The architecture comprises three main components:
1. `fluorite_core` (`c:\Users\blue-\projects\Fluorescent\fluorite_core`):
   - High-performance Rust library compiled as both `cdylib` (for dynamic C-ABI FFI linking) and `rlib` (for native Rust testing).
   - Custom memory allocators designed for zero-fragmentation game loops:
     - `ArenaAllocator`: Chunked bump-pointer allocator with $O(1)$ bulk reset and power-of-two alignment padding.
     - `DoubleBufferedFrameAllocator`: Decoupled ping-pong buffers for game logic and render pipeline frames.
     - Contiguous 1MB+ buffer allocation API for engine assets, framebuffers, and zero-copy transfers.
2. `Zero-Copy FFI Bridge`:
   - Powered by `flutter_rust_bridge` v2 (`2.13.0`).
   - Zero-copy buffer architecture leveraging Dart VM C-API `Dart_NewExternalTypedDataWithFinalizer` via `Dart_PostCObject`:
     - Transferable snapshot: Rust `Vec<u8>` maps directly to Dart `_ExternalUint8Array` (`Uint8List`) with 0 memory copies and 0 serialization overhead.
     - Persistent arena buffer view: `SharedFrameBuffer` handle exposing raw native pointer address for live mutable viewing via Dart `ffi.Pointer.asTypedList()`.
3. `fluorite_editor` (`c:\Users\blue-\projects\Fluorescent\fluorite_editor`):
   - Modern Flutter Desktop application for Windows x64.
   - Dynamic library linkage via CMake `POST_BUILD` copy of `fluorite_core.dll` and resilient runtime Dart library resolution.
   - Editor UI featuring a "Start Engine" action button, 4-card telemetry grid (Engine Lifecycle, Allocator Metrics, Zero-Copy Pointer/Sentinels, Latency), and Hex Memory Inspector.
   - Dual-tier automated test harness: headless FFI contract test (`test/engine_ffi_test.dart`) and desktop GUI integration test (`integration_test/app_test.dart`).

---

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Rust Library Initialization | Initialize `fluorite_core` with `cdylib` and `rlib` crate types and Rust 2021 edition | M1 | ORIGINAL_REQUEST §R1 |
| 2 | Arena Allocator | Custom bump-pointer allocator with strict power-of-two alignment padding | M1 | ORIGINAL_REQUEST §R1 |
| 3 | Bulk Zero-Cost Reset | $O(1)$ bulk reset for `ArenaAllocator` ensuring zero fragmentation across game loop frames | M1 | ORIGINAL_REQUEST §R1 |
| 4 | Double-Buffered Frame Allocator | Ping-pong frame allocator alternating between logic tick and render tick | M1 | ORIGINAL_REQUEST §R1 |
| 5 | Contiguous 1MB Buffer Allocation | Dedicated API to allocate 1MB contiguous byte buffer with sentinel verification | M1 | ORIGINAL_REQUEST §Verification |
| 6 | Allocator Unit & Integration Tests | Comprehensive `cargo test` suite verifying alignment ladder, 1MB buffer, overflow handling, reset | M1 | ORIGINAL_REQUEST §Verification |
| 7 | FRB v2 Configuration | `flutter_rust_bridge.yaml` configuration defining rust_root, rust_input, and dart_output | M2 | ORIGINAL_REQUEST §R2 |
| 8 | Bridge API Definitions | Rust API exposing `start_engine()`, `allocate_engine_buffer()`, `get_engine_status()`, sentinels | M2 | ORIGINAL_REQUEST §R2 |
| 9 | Zero-Copy External TypedData | Native heap `Vec<u8>` exposed to Dart as external `Uint8List` with zero memory copies | M2 | ORIGINAL_REQUEST §R2 |
| 10 | Persistent Arena Buffer View | `SharedFrameBuffer` exposing native memory address for Dart `Pointer.asTypedList()` live view | M2 | ORIGINAL_REQUEST §R2 |
| 11 | Automated Codegen Tests | Automated test verifying `flutter_rust_bridge` code generation completes without errors | M2 | ORIGINAL_REQUEST §Verification |
| 12 | Flutter Desktop Project Setup | Initialize `fluorite_editor` Flutter Desktop project with Windows target enabled | M3 | ORIGINAL_REQUEST §R3 |
| 13 | Windows DLL Linkage & Resolver | CMake `POST_BUILD` DLL copy rule and resilient Dart `resolveFluoriteCoreDllPath()` loader | M3 | ORIGINAL_REQUEST §R3 |
| 14 | Editor UI Dashboard | Dark modern theme, "Start Engine" button, and 4-card telemetry grid displaying status & memory | M3 | ORIGINAL_REQUEST §R3 |
| 15 | Hex Memory Inspector | UI widget displaying live bytes of the allocated 1MB buffer with sentinel verification | M3 | ORIGINAL_REQUEST §R3 |
| 16 | Headless FFI Integration Test | Dart test verifying calling Rust FFI to allocate 1MB memory and read values without crashing | M3 | ORIGINAL_REQUEST §Verification |
| 17 | Desktop GUI Launch Verification | Automated verification that Flutter UI launches on Desktop and communicates with Rust binary | M3 | ORIGINAL_REQUEST §Verification |
| 18 | E2E Acceptance Test Suite | 100% pass across all 4 tiers of requirement-driven opaque-box E2E test suite | M4 | ORIGINAL_REQUEST §Verification |
| 19 | Adversarial Coverage Hardening | Tier 5 adversarial stress testing on memory boundaries, concurrency, and buffer integrity | M4 | Project Pattern |

---

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Rust Core & Memory Allocators | Initialize `fluorite_core`, implement `ArenaAllocator` & `DoubleBufferedFrameAllocator`, pass `cargo test` | None | DONE |
| M2 | Zero-Copy FFI Bridge | Configure FRB v2, define Rust API, generate bindings, verify zero-copy buffer transfer, codegen test, and 30 bridge integration tests | M1 | DONE |
| M3 | Flutter Desktop Editor Integration | Initialize `fluorite_editor`, link `fluorite_core.dll`, build Editor UI & Telemetry, pass integration tests | M2 | PLANNED (FROZEN per USER COMMAND) |
| M4 | Final Milestone: E2E Verification & Hardening | Pass 100% of E2E test suite (Tiers 1-4) followed by Phase 2 adversarial hardening (Tier 5) | M1, M2, M3 | PLANNED (FROZEN per USER COMMAND) |

---

## Interface Contracts

### 1. `fluorite_core` Native Allocator Interface (`allocator.rs`)
```rust
pub struct AllocError;

pub trait CustomAllocator {
    unsafe fn alloc_raw(&self, layout: std::alloc::Layout) -> Result<*mut u8, AllocError>;
    fn reset(&self);
    fn allocated_bytes(&self) -> usize;
    fn capacity_bytes(&self) -> usize;
}

pub struct ArenaAllocator { ... }
impl ArenaAllocator {
    pub fn new(capacity: usize) -> Self;
    pub fn alloc_slice<T: Copy>(&self, count: usize, default_val: T) -> Result<&mut [T], AllocError>;
    pub fn reset(&self);
    pub fn allocated_bytes(&self) -> usize;
    pub fn capacity_bytes(&self) -> usize;
}

pub struct DoubleBufferedFrameAllocator { ... }
impl DoubleBufferedFrameAllocator {
    pub fn new(per_frame_capacity: usize) -> Self;
    pub fn current_arena(&self) -> &ArenaAllocator;
    pub fn swap_buffers(&self);
}
```

### 2. Zero-Copy FFI Bridge Interface (`api/engine.rs` ↔ `lib/src/rust/api/engine.dart`)
```rust
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct EngineStatus {
    pub is_initialized: bool,
    pub total_memory_allocated: usize,
    pub arena_capacity: usize,
    pub frame_index: u64,
    pub status_message: String,
}

#[frb(sync)]
pub fn start_engine() -> EngineStatus;

#[frb(sync)]
pub fn allocate_engine_buffer(size_bytes: usize) -> Vec<u8>;

#[frb(sync)]
pub fn get_engine_status() -> EngineStatus;

#[frb(sync)]
pub fn verify_buffer_sentinels(buffer: &[u8]) -> bool;
```

Dart Equivalent:
```dart
class EngineStatus {
  final bool isInitialized;
  final BigInt totalMemoryAllocated;
  final BigInt arenaCapacity;
  final BigInt frameIndex;
  final String statusMessage;
}

EngineStatus startEngine();
Uint8List allocateEngineBuffer({required BigInt sizeBytes});
EngineStatus getEngineStatus();
bool verifyBufferSentinels({required List<int> buffer});
```

### 3. Editor UI State Contract (`engine_controller.dart`)
```dart
enum EngineState { uninitialized, initializing, running, error }

class EngineController extends ChangeNotifier {
  EngineState state = EngineState.uninitialized;
  EngineStatus? status;
  Uint8List? activeBuffer;
  int allocationLatencyMicros = 0;
  String? errorMessage;

  Future<void> startEngine();
  Future<void> allocate1MB();
  void reset();
}
```

---

## Code Layout
- `fluorite_core/`:
  - `Cargo.toml`: `crate-type = ["cdylib", "rlib"]`, `flutter_rust_bridge = "2.13.0"`
  - `src/lib.rs`: Module exports and C-ABI symbols
  - `src/allocator/mod.rs`: Custom allocator interfaces
  - `src/allocator/arena.rs`: `ArenaAllocator` implementation
  - `src/allocator/frame.rs`: `DoubleBufferedFrameAllocator` implementation
  - `src/api/mod.rs`: Engine API definitions for FRB
  - `src/api/engine.rs`: Engine lifecycle, buffer allocation, and status
  - `tests/arena_test.rs`: Allocator unit and alignment tests
  - `tests/frame_test.rs`: Frame allocator tests
  - `tests/codegen_test.rs`: FRB codegen verification test
- `fluorite_editor/`:
  - `pubspec.yaml`: Flutter dependencies (`flutter_rust_bridge: 2.13.0`, `ffi`)
  - `flutter_rust_bridge.yaml`: FRB codegen configuration
  - `windows/runner/CMakeLists.txt`: `POST_BUILD` DLL copy rule
  - `lib/main.dart`: Desktop app entrypoint and `RustLib.init()`
  - `lib/src/engine_controller.dart`: Engine state management
  - `lib/src/ui/editor_screen.dart`: Editor UI dashboard & telemetry
  - `lib/src/ui/memory_inspector.dart`: Hex memory view
  - `lib/src/rust/`: Generated Dart bridge bindings
  - `test/engine_ffi_test.dart`: Headless 1MB allocation & FFI contract test
  - `integration_test/app_test.dart`: Desktop GUI integration test
