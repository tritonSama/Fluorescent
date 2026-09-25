# Task Assignment: Milestone 1 Explorer 3 — Headless Verification & Test Strategy

You are teamwork_preview_explorer_m1_3.
Working directory: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_m1_3\
Authoritative Request: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\ORIGINAL_REQUEST.md
Project Blueprint: c:\Users\blue-\projects\Fluorescent\PROJECT.md
Survey 1 Report: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_survey_1\report.md

## Objective
Analyze and specify the test strategy and headless verification for Milestone 1:
- Acceptance criterion: "`cargo test` passes in `fluorite_core` verifying PBR shader compilation...".
- Design `fluorite_core/tests/pbr_pipeline_test.rs`:
  - Validate WGSL shader compilation for `pbr_forward.wgsl`, `cluster_cull.wgsl`, and `shadow_depth.wgsl` using `wgpu::ShaderModuleDescriptor` or naga validator headlessly.
  - Test 1024 dynamic lights in `ClusterLightGrid`: assert all clusters populated without index overflow.
  - Test directional shadow projection: assert texel-snapping matrix stability under camera movement.
  - Test Cook-Torrance BRDF properties: energy conservation ($k_d + k_s \le 1.0$), non-negative radiance.
- Fix existing pre-existing test defect in `fluorite_core/tests/engine_api_test.rs` where `start_engine()` was called with 0 args instead of `start_engine(None)`.

## Deliverable
Write your implementation plan and exact test design to:
`c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_m1_3\report.md`
and write your handoff to:
`c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_m1_3\handoff.md`

## 2026-09-24T18:08:08Z

<USER_REQUEST>
You are teamwork_preview_explorer_m1_3.
Working directory: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_m1_3\
Authoritative Request: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\ORIGINAL_REQUEST.md (YOU MUST READ THIS FILE FIRST).
Project Blueprint: c:\Users\blue-\projects\Fluorescent\PROJECT.md

Mission:
Analyze and specify the headless verification and test strategy for Milestone 1 in `fluorite_core`:
1. Design `fluorite_core/tests/pbr_pipeline_test.rs` to satisfy the acceptance criterion: "`cargo test` passes in `fluorite_core` verifying PBR shader compilation...".
2. Headless verification: Validate WGSL compilation of `pbr_forward.wgsl`, `cluster_cull.wgsl`, and `shadow_depth.wgsl` using `wgpu::ShaderModuleDescriptor`.
3. Cluster light grid test: assign 1024 dynamic lights and assert all clusters populated without index out-of-bounds.
4. Shadow projection test: assert texel-snapping matrix stability under camera movement.
5. Cook-Torrance BRDF test: verify energy conservation and physical plausibility.
6. Fix existing test defect in `fluorite_core/tests/engine_api_test.rs` line 12 where `start_engine()` was called with 0 arguments instead of `start_engine(None)`.
7. Write detailed report to `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_m1_3\report.md` and handoff to `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_m1_3\handoff.md`.
</USER_REQUEST>
