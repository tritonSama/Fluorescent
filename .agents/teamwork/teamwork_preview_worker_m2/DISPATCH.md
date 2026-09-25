## 2026-09-25T03:31:08Z
You are teamwork_preview_worker_m2.
Working directory: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_worker_m2\
Authoritative Request: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\ORIGINAL_REQUEST.md (YOU MUST READ THIS FILE FIRST).
Project Blueprint: c:\Users\blue-\projects\Fluorescent\PROJECT.md
Survey 2 Architecture & Math Report: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_survey_2\report.md

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Exclusive Write Ownership:
- `fluorite_core/src/spatial/` (`mod.rs`, `bvh.rs`, `culling.rs`, `broadphase.rs`, `math.rs`)
- `fluorite_core/src/lib.rs` (ensure `pub mod spatial;` is exported)
- `fluorite_core/tests/bvh_culling_test.rs`
- `fluorite_core/tests/bvh_culling_benchmark_test.rs`

Key Tasks for Milestone 2:
1. Implement `FlatBvhNode` (exact 32 bytes, cache-aligned, `bytemuck::Pod`) and 16-bin SAH BVH builder.
2. Implement branchless SIMD slab raycasting with explicit stack.
3. Implement hierarchical box-frustum culling with inside-inheritance (all descendants skip plane tests when parent is inside) and outside-pruning.
4. Implement dual-tree broadphase collision pairs generation.
5. Implement `bvh_culling_test.rs` validating construction, raycasting, culling, and broadphase.
6. Implement `bvh_culling_benchmark_test.rs` executing 100 culls of 10,000 entities with assertion `avg_time < Duration::from_millis(2)`.
7. Execute:
   - `cargo check -p fluorite_core`
   - `cargo test -p fluorite_core --test bvh_culling_test`
   - `cargo test -p fluorite_core --test bvh_culling_benchmark_test -- --nocapture`
   - `cargo test -p fluorite_core`
   - `dart run tests/e2e_runner.dart`
8. Write report to `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_worker_m2\report.md` and handoff to `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_worker_m2\handoff.md`. Send completion message back.
