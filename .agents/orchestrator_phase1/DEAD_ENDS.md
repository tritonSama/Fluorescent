# DEAD ENDS — orchestrator_phase1

| Iteration | Approach Tried | Why It Failed | Files Touched |
|---|---|---|---|
| M2-Iter1 | Hand-crafted Dart mock state simulation masquerading as FRB generated code (`RustLibApi` ignoring native C-ABI) | Bypassed native Rust code completely; `startEngine()`, `getEngineStatus()`, `verifyBufferSentinels()` never executed native symbols; violated integrity mandates (facade implementation). | `fluorite_editor/lib/src/rust/frb_generated.dart` |
| M2-Iter1 | Returning synthetic integer `0x40000000` as pointer address in `SharedFrameBuffer` | Caused immediate `STATUS_ACCESS_VIOLATION` (0xC0000005) when dereferenced via `Pointer.fromAddress()`. | `fluorite_editor/lib/src/rust/frb_generated.dart`, `fluorite_editor/lib/src/rust/api/engine.dart` |
| M2-Iter1 | Calling `std::mem::forget(buf)` in Rust without attaching `NativeFinalizer` in Dart | Caused permanent native heap memory leak of 1MB per allocation under continuous allocation loops. | `fluorite_core/src/frb_generated.rs`, `fluorite_editor/lib/src/rust/frb_generated.dart` |
| M2-Iter1 | Discarding arena memory with `let _ = arena.alloc_slice(...)` and allocating redundant `vec![0u8; size_bytes]` from OS heap | Consumed double memory (2MB per 1MB requested) and decoupled buffer from custom arena allocator. | `fluorite_core/src/api/engine.rs` |
| M2-Iter1 | Asserting static substrings in `codegen_test.rs` instead of testing genuine codegen / FFI invocation | Self-certifying mock testing; failed to verify actual bridge functionality. | `fluorite_core/tests/codegen_test.rs` |
