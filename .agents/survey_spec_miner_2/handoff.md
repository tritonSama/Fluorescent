# Handoff Report: R2 Zero-Copy FFI Bridge via flutter_rust_bridge

**Agent**: `survey_spec_miner_2` (teamwork_preview_spec_miner)  
**Task**: Technical Specification Mining for Requirement 2 (Zero-Copy FFI Bridge via flutter_rust_bridge)  
**Date**: 2026-09-17  
**Type**: Hard Handoff (Task Complete)

---

## 1. Observation

1. **Original User Request Specification**:
   In `ORIGINAL_REQUEST.md` (lines 52–65):
   > "### R2. Zero-Copy FFI Bridge
   > Use the `flutter_rust_bridge` package to automatically generate safe, zero-copy FFI bindings between the Rust core and Dart. Ensure the architecture supports sharing large continuous memory buffers without serialization overhead.
   > ### R3. Flutter Editor Integration
   > Initialize a new Flutter desktop project (`fluorite_editor`). Integrate the generated `flutter_rust_bridge` bindings. Build a basic Editor UI with a 'Start Engine' button that allocates memory in Rust and reads the status back into Flutter.
   > ## Acceptance Criteria
   > ### Verification
   > - [ ] `cargo test` passes successfully for the custom memory allocators in Rust.
   > - [ ] Automated tests confirm `flutter_rust_bridge` generation completes without errors.
   > - [ ] A Flutter integration test verifies that Dart can successfully call a Rust FFI function to allocate 1MB of memory and read a value from it without crashing.
   > - [ ] The Flutter UI successfully launches on Desktop and communicates with the compiled Rust binary."

2. **System Toolchain Discovery**:
   - Initial execution attempt of `powershell -Command "cargo --version; rustc --version; flutter --version; where.exe flutter_rust_bridge_codegen"` timed out due to IDE permission prompt.
   - Authoritative package repository queries revealed that `flutter_rust_bridge` and `flutter_rust_bridge_codegen` are active on crates.io and pub.dev at version **2.13.0** (v2.x line).
   - Build-time dependency `lib_flutter_rust_bridge_codegen` provides direct Rust API access to the code generator (`lib_flutter_rust_bridge_codegen::codegen::generate`).

3. **Zero-Copy Architecture Ground Truth**:
   - Official FRB v2 documentation specifies:
     > "In `flutter_rust_bridge`, zero-copy refers to the ability to transfer data (typically `Vec<u8>`, `Vec<i8>`, and similar types) between Rust and Dart without the overhead of copying the memory... achieved by utilizing the Dart VM's 'external typed data' capability through `Dart_PostCObject`... In V2, types like `Vec<u8>` are now automatically zero-copied by default."
   - Dart VM C-API `Dart_NewExternalTypedDataWithFinalizer` associates native heap pointers with Dart `_ExternalUint8Array` objects, triggering Rust's `drop` implementation when the Dart object is garbage collected.
   - Direct memory viewing is supported via Dart FFI `ffi.Pointer<ffi.Uint8>.asTypedList(length)`, providing live mutable zero-copy access over persistent Rust native buffers.

4. **Code Generation Configuration**:
   - FRB v2 relies on `flutter_rust_bridge.yaml` (using `snake_case` keys: `rust_root`, `rust_input`, `dart_output`, `rust_output`).
   - Generation is triggered via `flutter_rust_bridge_codegen generate` or programmatically via `codegen::generate()`.
   - Dart runtime initialization requires `await RustLib.init()`, with optional `externalLibrary` parameter for loading dynamic libraries (`.dll` on Windows).

---

## 2. Logic Chain

1. **Version Selection (v1 vs v2)**:
   - *Observation*: FRB v1 required manual `ZeroCopyBuffer<Vec<u8>>` wrappers, lacked folder-based modular Rust inputs, required clumsy `SyncReturn<T>`, and had deprecated tooling. FRB v2 provides automatic zero-copy mapping for `Vec<u8>`, multi-file folder support (`rust/src/api/**/*.rs`), `#[frb(sync)]` synchronous execution, `RustAutoOpaque<T>`, and direct CMake integration on Windows.
   - *Inference*: `flutter_rust_bridge` v2 is unconditionally selected for Phase 1.

2. **Zero-Copy Memory Architecture**:
   - *Observation*: Traditional IPC / MethodChannels require 2–3 memory copies and serialization overhead. The acceptance criteria explicitly demands: "sharing large continuous memory buffers without serialization overhead" and "verifies that Dart can successfully call a Rust FFI function to allocate 1MB of memory and read a value from it without crashing."
   - *Inference*: By returning `Vec<u8>` from Rust functions (or exposing pointer addresses from persistent `SharedFrameBuffer` handles), FRB v2 leverages `Dart_NewExternalTypedDataWithFinalizer`. Dart's `Uint8List` points directly to the native Rust allocation. Memory copy count is 0, serialization overhead is 0, and reading `buffer[0]` in Dart executes in $O(1)$ time directly from the native heap.

3. **Dual Zero-Copy Patterns**:
   - *Inference*: Two distinct architectural patterns must be supported:
     - **Pattern A (Transferable / Snapshot)**: Rust allocates 1MB `Vec<u8>`, passes ownership to Dart as `Uint8List`. Dart GC finalizer triggers Rust drop. Ideal for frame snapshots and verification tests.
     - **Pattern B (Persistent Arena / Game Loop)**: Rust engine owns continuous buffer via custom `ArenaAllocator` (R1), wraps it in `RustAutoOpaque`, exposes raw pointer address. Dart creates an FFI view with `Pointer.asTypedList()`. Both environments mutate identical bytes in place with zero GC pressure.

4. **Automated Verification Strategy**:
   - *Observation*: Acceptance criteria requires: "Automated tests confirm `flutter_rust_bridge` generation completes without errors."
   - *Inference*: This can be verified at three independent levels:
     1. Rust unit test in `fluorite_core/tests/codegen_test.rs` executing `lib_flutter_rust_bridge_codegen::codegen::generate()`.
     2. CI/CLI verification executing `flutter_rust_bridge_codegen generate` and verifying zero git diff drift (`git diff --exit-code`).
     3. Dart integration test in `fluorite_editor/test/zero_copy_integration_test.dart` allocating 1MB and verifying header/footer sentinels.

---

## 3. Caveats

1. **System Terminal Execution Prompt**: Interactive terminal command execution timed out due to IDE safety prompts. However, authoritative upstream documentation, crate registries, and Dart VM specifications were comprehensively mined via web search.
2. **Platform Zero-Copy Limitations**: While zero-copy is natively supported on Windows Desktop (the specified platform for `fluorite_editor`), Dart VM external typed data is not supported on Web (falls back to copying). Since Phase 1 targets Windows Desktop, this does not affect delivery.
3. **Synchronization for Persistent Buffers**: When using Pattern B (direct pointer views via `asTypedList`), concurrent multi-threaded writes between Dart Isolates and Rust threads require synchronization (e.g. `Mutex` or `RwLock`) to prevent data races.

---

## 4. Conclusion

The technical specifications for Requirement 2 (Zero-Copy FFI Bridge via `flutter_rust_bridge`) have been mined, rigorously detailed, and documented in:
`c:\Users\blue-\projects\Fluorescent\.agents\survey_spec_miner_2\survey_report.md`.

Key Deliverables Specified:
* **Toolchain & Version**: `flutter_rust_bridge = "2.13.0"`, `flutter_rust_bridge_codegen = "2.13.0"`, configured for Windows MSVC desktop (`cdylib`).
* **Zero-Copy Architecture**: Automatic `Vec<u8>` <-> `Uint8List` mapping via `Dart_NewExternalTypedDataWithFinalizer` and direct FFI pointer views (`asTypedList`).
* **API Contracts**: Concrete signatures for `start_engine()`, `allocate_engine_buffer(size_bytes)`, and `SharedFrameBuffer`.
* **Codegen & Verification**: Standard `flutter_rust_bridge.yaml`, CLI commands, and automated test implementations verifying clean codegen and 1MB memory allocation.

The downstream builder agents have complete, unambiguous blueprints to implement R2 without guesswork.

---

## 5. Verification Method

To independently verify the findings and specifications in this report:

1. **Inspect Specification Artifacts**:
   - Review `c:\Users\blue-\projects\Fluorescent\.agents\survey_spec_miner_2\survey_report.md`.
   - Confirm all 12 discovered features and 12 edge cases are documented in the required table formats.

2. **Verify Toolchain & Codegen Commands**:
   - Command: `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml`
   - Invalidation Condition: Codegen fails or outputs legacy v1 `bridge_generated.dart` instead of v2 `frb_generated.dart`.

3. **Verify 1MB Zero-Copy Allocation in Dart**:
   - Test Command: `flutter test test/zero_copy_integration_test.dart`
   - Invalidation Condition: Allocation of 1MB throws OOM, causes segmentation fault, or fails sentinel value verification (`expect(buffer[0], equals(0xAA))`).
