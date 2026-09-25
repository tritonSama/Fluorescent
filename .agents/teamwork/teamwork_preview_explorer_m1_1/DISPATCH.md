# Task Assignment: Milestone 1 Explorer 1 — Shaders & PBR Material Pipeline

You are teamwork_preview_explorer_m1_1.
Working directory: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_m1_1\
Authoritative Request: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\ORIGINAL_REQUEST.md
Project Blueprint: c:\Users\blue-\projects\Fluorescent\PROJECT.md
Survey 1 Report: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_survey_1\report.md

## Objective
Analyze and specify the exact WGSL shaders and material pipeline for Milestone 1:
- `pbr_forward.wgsl`: Cook-Torrance microfacet BRDF (GGX D, Smith V, Schlick F), glTF 2.0 conventions, clustered light evaluation loop.
- `cluster_cull.wgsl`: Compute shader for 16x9x24 cluster grid slicing and light culling.
- `shadow_depth.wgsl`: Directional shadow map depth pass with 3x3 PCF filtering.
- Uniform buffer layouts (`PbrMaterialUniforms` 48B, `CameraUniforms` 320B, `GpuLight` 64B) with 16-byte alignment and bytemuck compatibility.

## Deliverable
Write your implementation plan and exact code recommendations to:
`c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_m1_1\report.md`
and write your handoff to:

## 2026-09-24T18:08:08Z
You are teamwork_preview_explorer_m1_1.
Working directory: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_m1_1\
Authoritative Request: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\ORIGINAL_REQUEST.md (YOU MUST READ THIS FILE FIRST).
Project Blueprint: c:\Users\blue-\projects\Fluorescent\PROJECT.md

Mission:
Analyze and specify the exact WGSL shaders and uniform structures for Milestone 1 (PBR & Clustered Forward+ Renderer):
1. `pbr_forward.wgsl`: Complete Cook-Torrance microfacet BRDF (Trowbridge-Reitz GGX, Smith GGX correlated, Schlick Fresnel) with glTF 2.0 texture conventions (Albedo, Metallic-Roughness, Normal, AO, Emissive) and clustered forward light evaluation loop.
2. `cluster_cull.wgsl`: Compute shader for 16x9x24 logarithmic cluster grid slicing and light culling.
3. `shadow_depth.wgsl`: Directional shadow depth pass with 3x3 PCF and slope-scaled depth bias.
4. Uniform buffer structures (`PbrMaterialUniforms` 48B, `CameraUniforms` 320B, `GpuLight` 64B) with bytemuck compatibility and 16-byte alignment.
5. Write detailed report to `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_m1_1\report.md` and handoff to `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_explorer_m1_1\handoff.md`.
