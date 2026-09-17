# Fluorite AAA Engine Phase 1 — Test Infrastructure (TEST_INFRA)

## 1. Test Philosophy

The Fluorite AAA Engine Phase 1 test architecture is founded upon the principle of **requirement-driven, hermetic, opaque-box verification**. Fluorite establishes a high-performance native core in Rust connected to a Flutter Desktop Editor via a zero-copy FFI bridge. In game engine architecture, memory allocation latency spikes, alignment violations, and heap fragmentation directly degrade frame rates and cause catastrophic segmentation faults. Consequently, our testing methodology enforces:

1. **Opaque-Box Contract Verification**: Tests exercise public C-ABI exports, Rust allocator APIs, FFI bridge channels, and Dart TypedData memory views exclusively from the perspective of an external caller or client system, without relying on private implementation details.
2. **Deterministic Memory Accounting**: The custom memory allocators (`ArenaAllocator` and `DoubleBufferedFrameAllocator`) are validated under strict mathematical alignment guarantees ($1, 2, 4, 8, 16, 32, 64$ bytes), capacity boundaries, and $O(1)$ bulk resets to guarantee zero heap fragmentation across game loops.
3. **Zero-Copy Integrity & Sentinel Protection**: Continuous memory buffers (notably the 1MB buffer mandated by `ORIGINAL_REQUEST.md`) are verified via physical pointer sharing, sentinel boundary tags (`0xAA` header and `0x55` footer), and in-place mutation without intermediate serialization or byte copying.
4. **Multi-Tier Systematic Coverage**: A rigorous 4-Tier methodology provides full vertical coverage:
   - **Tier 1 (Feature Coverage)**: Independent isolation tests for all 4 core features ($\ge 5$ tests per feature).
   - **Tier 2 (Boundary & Corner Cases)**: Edge conditions, extreme alignments, capacity saturation, and 0/1/1MB limits ($\ge 5$ tests per feature).
   - **Tier 3 (Cross-Feature Combinations)**: Pairwise interactions between allocators, FFI bridge transfers, and Dart buffer readbacks.
   - **Tier 4 (Real-World Application Scenarios)**: High-stress simulations including 60 FPS game loop execution, 1,000 continuous frames without fragmentation, and asset buffer streaming.
5. **Single-Command Test Reproducibility**: Test suites are fully automated and executable through unified runners across Windows PowerShell, Batch, and POSIX environments.

---

## 2. Feature Inventory & Acceptance Criteria Mapping

All test cases are derived directly from the authoritative requirements in `ORIGINAL_REQUEST.md` (§ 2026-09-17T16:50:21Z) and `PROJECT.md`.

| Feature ID | Feature Name | Description | Authoritative Source | Acceptance Criterion | Test Suite Location |
|---|---|---|---|---|---|
| **F-01** | Custom Memory Allocators | `ArenaAllocator` and `DoubleBufferedFrameAllocator` with power-of-two alignment padding and $O(1)$ bulk reset | `ORIGINAL_REQUEST.md` §R1 | **AC 1**: `cargo test` passes successfully for custom memory allocators | `tests/tier1_feature_coverage_test.*` |
| **F-02** | Zero-Copy Continuous Buffers | 1MB (1,048,576 bytes) contiguous native buffer with sentinel verification (`0xAA`/`0x55`) and direct pointer sharing | `ORIGINAL_REQUEST.md` §R2, §Verification | **AC 3**: Verify Dart calls Rust FFI to allocate 1MB memory and read values without crashing | `tests/tier1_feature_coverage_test.*`, `tests/tier2_boundary_corner_test.*` |
| **F-03** | Zero-Copy FFI Bridge | `flutter_rust_bridge` v2 bindings (`start_engine`, `allocate_engine_buffer`, `get_engine_status`, `verify_buffer_sentinels`, `SharedFrameBuffer`) | `ORIGINAL_REQUEST.md` §R2 | **AC 2**: Automated tests confirm `flutter_rust_bridge` generation completes without errors | `tests/tier1_feature_coverage_test.*`, `tests/tier3_cross_feature_test.*` |
| **F-04** | Desktop Editor Integration | Flutter Desktop Editor (`fluorite_editor`), "Start Engine" lifecycle, telemetry grid, hex memory viewer, and `EngineController` | `ORIGINAL_REQUEST.md` §R3 | **AC 4**: Flutter UI launches on Desktop and communicates with compiled Rust binary | `tests/tier1_feature_coverage_test.*`, `tests/tier4_real_world_scenarios_test.*` |

---

## 3. Test Architecture

The Fluorite test harness implements a dual-stack architecture enabling comprehensive validation in both native Rust environments (`cargo test`) and Dart/Flutter execution runtimes (`dart test` / standalone Dart VM):

```
                                  ▲
                                 / \
                                /   \      Tier 4: Real-World Scenarios
                               / T4  \     (60 FPS Game Loop, 1000 Frames, 1MB Asset Stream)
                              /-------\
                             /         \   Tier 3: Cross-Feature Combinations
                            /    T3     \  (Allocator + Frame Swap + FFI Bridge + Dart Readback)
                           /-------------\
                          /               \ Tier 2: Boundary & Corner Cases
                         /       T2        \(0B, 1B, 1MB, Alignment Ladder 1..64, Overflow)
                        /-------------------\
                       /         T1          \ Tier 1: Feature Coverage (>=5 tests per feature)
                      /                       \(Allocators, Zero-Copy, FFI Bridge, Desktop Editor)
                     /-------------------------\
```

### 3.1 Test Directory Structure

```
tests/
├── Cargo.toml                                 # Standalone Rust test package definition
├── e2e_test_harness.dart                      # Self-contained zero-dependency test runner & assertion framework
├── e2e_runner.dart                            # Unified Dart E2E test runner executing Tiers 1-4
├── tier1_feature_coverage_test.rs             # Tier 1 Rust: Allocator & buffer isolation tests (>=5 tests/feat)
├── tier1_feature_coverage_test.dart           # Tier 1 Dart: FFI, zero-copy, and editor controller tests (>=5 tests/feat)
├── tier2_boundary_corner_test.rs              # Tier 2 Rust: Boundary, alignment, overflow, 0B/1B/1MB tests
├── tier2_boundary_corner_test.dart            # Tier 2 Dart: Sentinel corruption, power-of-two sizes, edge offsets
├── tier3_cross_feature_test.rs                # Tier 3 Rust: Cross-feature pairwise interactions
├── tier3_cross_feature_test.dart              # Tier 3 Dart: Cross-feature FFI bridge & Dart readback tests
├── tier4_real_world_scenarios_test.rs         # Tier 4 Rust: 60 FPS loop, 1000-frame stress, dynamic memory pressure
├── tier4_real_world_scenarios_test.dart       # Tier 4 Dart: Multi-turn editor lifecycle, 1MB asset streaming
├── run_e2e_tests.ps1                          # Single-command Windows PowerShell execution script
├── run_e2e_tests.bat                          # Single-command Windows Batch script
└── run_e2e_tests.sh                           # Single-command POSIX Bash script
```

---

## 4. 4-Tier Systematic Test Catalog

### 4.1 Tier 1: Feature Coverage ($\ge 5$ tests per feature)

#### Feature 1: Custom Memory Allocators (`ArenaAllocator`, `DoubleBufferedFrameAllocator`)
1. `test_t1_f1_arena_alloc_slices`: Verifies allocating slices of `u8`, `u32`, and `u64`, verifying values, correct lengths, and offset advancement.
2. `test_t1_f1_arena_bulk_reset`: Allocates memory up to capacity, calls `reset()`, verifies `allocated_bytes() == 0`, and reallocates from base address.
3. `test_t1_f1_arena_alignment_padding`: Validates strict alignment enforcement across 1, 2, 4, 8, 16, 32, and 64 byte layouts.
4. `test_t1_f1_frame_allocator_ping_pong`: Verifies double-buffered ping-pong allocator retains Frame $N-1$ data in previous arena while current arena is active.
5. `test_t1_f1_allocator_metrics_tracking`: Confirms `allocated_bytes()`, `capacity_bytes()`, `remaining_bytes()`, and allocation counter match exact expected quantities.

#### Feature 2: Zero-Copy Continuous Buffers
1. `test_t1_f2_1mb_buffer_allocation`: Requests contiguous 1,048,576 byte buffer; asserts non-null pointer, exact byte length, and memory contiguity.
2. `test_t1_f2_sentinel_verification`: Verifies byte 0 contains header sentinel `0xAA` and byte 1,048,575 contains footer sentinel `0x55`.
3. `test_t1_f2_in_place_mutation`: Writes test patterns to buffer and verifies mutations are reflected immediately at raw pointer address with zero copying.
4. `test_t1_f2_pointer_address_sharing`: Confirms `ptr_address()` returns a valid virtual memory address aligned to 8+ bytes.
5. `test_t1_f2_typed_data_view_mapping`: Maps raw pointer via Dart `Pointer.asTypedList` and verifies simultaneous read/write consistency.

#### Feature 3: Zero-Copy FFI Bridge
1. `test_t1_f3_start_engine_lifecycle`: Calls `start_engine()`; asserts `is_initialized == true`, valid version string, and initial telemetry.
2. `test_t1_f3_allocate_engine_buffer`: Calls `allocate_engine_buffer(1048576)`; confirms return type is `Uint8List` with exact size and valid sentinels.
3. `test_t1_f3_get_engine_status`: Calls `get_engine_status()`; confirms reported allocated memory, capacity, and frame counter.
4. `test_t1_f3_verify_buffer_sentinels`: Verifies `verify_buffer_sentinels()` returns `true` for unmodified buffer and `false` when corrupted.
5. `test_t1_f3_shared_frame_buffer_handle`: Instantiates `SharedFrameBuffer`, tests byte read/write methods, and verifies pointer stability.

#### Feature 4: Flutter Desktop Editor & Controller Integration
1. `test_t1_f4_editor_controller_initial_state`: `EngineController` starts in `EngineState.uninitialized` with null activeBuffer and zero latency.
2. `test_t1_f4_editor_controller_start_engine`: Invoking `startEngine()` transitions state to `EngineState.running` and populates telemetry.
3. `test_t1_f4_editor_controller_allocate_1mb`: Invoking `allocate1MB()` creates 1MB activeBuffer, measures `allocationLatencyMicros > 0`, and updates telemetry.
4. `test_t1_f4_editor_controller_reset`: Invoking `reset()` clears active buffer and latency, returning controller to ready state.
5. `test_t1_f4_hex_memory_inspector_formatting`: Formats 1MB buffer slices into standard hex dump strings (offset, hex pairs, ASCII representation) and highlights sentinels.

---

### 4.2 Tier 2: Boundary & Corner Cases ($\ge 5$ tests per feature)

#### Feature 1: Custom Memory Allocators
1. `test_t2_f1_alloc_zero_bytes`: Allocating 0 bytes returns valid zero-length slice / dangling pointer without advancing offset or corrupting state.
2. `test_t2_f1_alloc_single_byte`: Allocating exactly 1 byte advances offset by 1 (plus alignment padding).
3. `test_t2_f1_alloc_exact_capacity`: Allocating exactly `capacity` bytes succeeds; subsequent 1-byte allocation returns `AllocError::OutOfMemory`.
4. `test_t2_f1_alloc_capacity_overflow`: Requesting `capacity + 1` bytes immediately returns `AllocError::OutOfMemory` without state corruption.
5. `test_t2_f1_alignment_ladder_extremes`: Tests alignments 1, 2, 4, 8, 16, 32, and 64 with odd sizes (3, 7, 13, 31, 63 bytes) across 100 allocations.
6. `test_t2_f1_repeated_empty_resets`: Swapping and resetting allocators repeatedly without allocations causes no underflow or corruption.

#### Feature 2: Zero-Copy Continuous Buffers
1. `test_t2_f2_zero_byte_buffer`: Allocating 0-byte buffer returns empty slice without memory leak or panic.
2. `test_t2_f2_single_byte_buffer`: Allocating 1-byte buffer sets single sentinel or valid byte without out-of-bounds access.
3. `test_t2_f2_exact_1mb_boundary`: Allocates exact 1,048,576 bytes; checks boundary indices 0, 1048574, 1048575, and verifies index 1048576 is out of bounds.
4. `test_t2_f2_power_of_two_sizes`: Tests buffers sized $2^0, 2^1, \dots, 2^{20}$ (1B to 1MB), verifying correct length and integrity at all boundaries.
5. `test_t2_f2_alignment_boundary_at_64`: Verifies that large buffers allocated by the engine are aligned to 64-byte hardware cache line boundaries.

#### Feature 3: Zero-Copy FFI Bridge
1. `test_t2_f3_buffer_size_zero`: `allocate_engine_buffer(0)` returns empty buffer without C-ABI violation or panic.
2. `test_t2_f3_buffer_size_one`: `allocate_engine_buffer(1)` handles single-byte sentinel logic safely.
3. `test_t2_f3_buffer_large_stress`: `allocate_engine_buffer(16 * 1024 * 1024)` (16MB) allocation and status check without heap exhaustion.
4. `test_t2_f3_repeated_start_engine`: Calling `start_engine()` idempotently when already started preserves existing state.
5. `test_t2_f3_corrupted_sentinel_rejection`: Corrupting byte 0, byte `size - 1`, or both correctly causes `verify_buffer_sentinels()` to return false.

#### Feature 4: Flutter Desktop Editor & Controller Integration
1. `test_t2_f4_allocate_before_start`: Calling `allocate1MB()` before `startEngine()` gracefully handles auto-initialization or returns descriptive error.
2. `test_t2_f4_repeated_allocations`: Triggering `allocate1MB()` 10 times consecutively updates activeBuffer reference without memory leaks.
3. `test_t2_f4_latency_budget_threshold`: Asserts `allocationLatencyMicros` for 1MB allocation is within real-time budget (< 50,000 µs in debug, < 1,000 µs in release).
4. `test_t2_f4_hex_viewer_offset_clamping`: Hex viewer handles requested offset beyond buffer length gracefully (clamping to max valid offset).
5. `test_t2_f4_hex_viewer_empty_buffer`: Hex viewer renders empty / placeholder state when `activeBuffer == null`.

---

### 4.3 Tier 3: Cross-Feature Combinations (Pairwise)

1. `test_t3_allocator_reset_and_frame_swap`: Pairs `ArenaAllocator` allocation + `reset()` + `DoubleBufferedFrameAllocator.swap_buffers()`, ensuring alternating frame isolation and clean memory reuse across 50 alternating frame cycles.
2. `test_t3_arena_allocation_and_ffi_buffer_transfer`: Allocates 1MB in custom arena, wraps into FFI bridge transfer, and verifies Dart external typed data receives identical bytes.
3. `test_t3_dart_call_and_1mb_buffer_readback`: Dart invokes `start_engine()`, followed by `allocate_engine_buffer(1048576)`, reads back index 0 (`0xAA`) and index 1048575 (`0x55`), and verifies with `verify_buffer_sentinels()`.
4. `test_t3_shared_buffer_pointer_and_editor_controller`: Pairs `SharedFrameBuffer` raw pointer retrieval with `EngineController` live telemetry and hex viewer inspection.
5. `test_t3_ffi_mutation_and_allocator_metrics`: Mutates buffer through FFI `write_buffer_pattern`, calls `get_engine_status()`, and asserts memory metrics remain consistent with allocation state.

---

### 4.4 Tier 4: Real-World Application Scenarios ($\ge 5$ scenarios)

1. **Scenario 1: Game Loop 60 FPS Frame Simulation (60 consecutive frames)**
   - Simulates 60 discrete game loop ticks (1 second of real-time 60 FPS gameplay).
   - In each frame: allocates transient per-frame entities (transforms, draw command buffers, raycast hits: 16KB - 64KB), swaps double-buffer, writes render packet, and resets previous frame.
   - Asserts zero memory leakage, strictly bounded memory usage, and zero memory fragmentation.
2. **Scenario 2: 1,000 Consecutive Frame Allocations Without Fragmentation**
   - Simulates extended gameplay of 1,000 frames.
   - Allocates varying numbers of transient objects (sizes 64B to 8KB) per frame, followed by frame swap and reset.
   - Asserts total memory allocated across 1,000 frames is reclaimed completely, peak heap usage never exceeds arena capacity, and address space does not drift.
3. **Scenario 3: 1MB Asset Buffer Transfer & Verification**
   - Simulates streaming a 1MB texture/mesh asset into Rust core buffer, transferring via zero-copy bridge to Flutter Editor, verifying sentinels and byte payload, and freeing memory.
4. **Scenario 4: Dynamic Memory Pressure & Recovery**
   - Simulates memory spike: arena is filled to 99% capacity, an allocation attempts to exceed capacity (gracefully rejected with `OutOfMemory`), engine triggers emergency bulk reset, and normal allocation resumes cleanly.
5. **Scenario 5: Multi-Turn Editor Lifecycle Simulation**
   - Simulates an editor session: Start Engine $\to$ Allocate 1MB Buffer $\to$ View Hex Memory $\to$ Re-allocate Different Pattern $\to$ Reset Engine $\to$ Re-start Engine $\to$ Allocate 2MB Buffer $\to$ Clean Shutdown.

---

## 5. Coverage Thresholds & Quality Gates

| Metric | Minimum Threshold | Target | Verification Tool |
|---|---|---|---|
| **Tier 1 Feature Coverage** | 100% (20/20 tests pass) | 100% | `run_e2e_tests.ps1` |
| **Tier 2 Boundary & Corner Cases** | 100% (21/21 tests pass) | 100% | `run_e2e_tests.ps1` |
| **Tier 3 Cross-Feature Combinations** | 100% (5/5 tests pass) | 100% | `run_e2e_tests.ps1` |
| **Tier 4 Real-World Application Scenarios**| 100% (5/5 scenarios pass) | 100% | `run_e2e_tests.ps1` |
| **Total Test Cases** | $\ge 50$ test cases | 51 test cases | E2E Runner |
| **Memory Fragmentation** | 0 bytes leaked / 0 drift | 0 bytes | Frame Allocator Tests |
| **1MB Contiguous Allocation** | Passed | Passed | FFI & Allocator Tests |
| **Sentinel Byte Integrity** | 100% pass | 100% pass | FFI & Sentinel Tests |

---

## 6. Test Execution Guide

The entire E2E test suite can be executed via a single automated command:

### 6.1 Windows PowerShell (Recommended)
```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run_e2e_tests.ps1
```

### 6.2 Windows Command Prompt (Batch)
```cmd
.\tests\run_e2e_tests.bat
```

### 6.3 POSIX Shell (Linux / macOS / WSL)
```bash
bash ./tests/run_e2e_tests.sh
```

### 6.4 Standalone Dart VM Runner
```bash
dart run tests/e2e_runner.dart
```

### 6.5 Native Cargo Test Runner (Rust Core)
```bash
cargo test --manifest-path tests/Cargo.toml
# Or inside fluorite_core:
cargo test --manifest-path fluorite_core/Cargo.toml
```
