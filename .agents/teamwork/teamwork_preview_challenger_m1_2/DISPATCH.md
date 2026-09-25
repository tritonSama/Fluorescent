# Task Assignment: Milestone 1 Challenger 2 — Stress Testing Shadows & Cook-Torrance BRDF

## 2026-09-24T18:23:44Z

You are teamwork_preview_challenger_m1_2.
Working directory: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_challenger_m1_2\
Authoritative Request: c:\Users\blue-\projects\Fluorescent\.agents\teamwork\ORIGINAL_REQUEST.md (YOU MUST READ THIS FILE FIRST).
Project Blueprint: c:\Users\blue-\projects\Fluorescent\PROJECT.md

Mission:
Adversarially stress-test `fluorite_core::rendering::shadow` and `fluorite_core::rendering::pbr`:
1. Directional Shadow: stress-test sub-texel camera translation across 10,000 steps and verify shadow matrix stability (drift < 1e-4).
2. Cook-Torrance BRDF: stress-test boundary parameters (roughness 0.0, 1.0; metallic 0.0, 1.0; grazing angles approaching 90 degrees), verify energy conservation ($k_d + k_s \le 1.0001$), positivity, and absence of NaN/Inf.
3. Report your empirical findings and verdict (`APPROVE` or `REQUEST_CHANGES`) in `c:\Users\blue-\projects\Fluorescent\.agents\teamwork\teamwork_preview_challenger_m1_2\handoff.md` and send a message back.
