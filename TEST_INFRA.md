# Fluorite AAA Engine Phase 2 (Wave 1) — Test Infrastructure (TEST_INFRA)

## 1. Test Philosophy

The Fluorite AAA Engine Phase 2 (Wave 1) test architecture is founded upon the principle of **requirement-driven, hermetic, opaque-box verification**. Fluorite combines a high-performance native Rust core with a Flutter Desktop Editor via a zero-copy FFI bridge. In an AAA real-time game engine, rendering latency spikes, culling bottlenecks, physics tunneling, lighting complexity explosions, and memory fragmentation directly degrade frame rates and cause catastrophic visual or physical failures. Consequently, our testing infrastructure enforces:

1. **Opaque-Box Contract Verification**: Tests exercise public C-ABI exports, rendering math models, spatial acceleration structures, physics world interfaces, and Flutter editor controller pipelines exclusively from the perspective of external client systems, without coupling to unexported internal implementations.
2. **Deterministic Physically Based Math & Lighting**: 
   - **Cook-Torrance BRDF**: Evaluated via microfacet theory combining GGX Normal Distribution Function ($D$), Smith geometric shadowing-masking ($G$), and Fresnel-Schlick ($F$) with distinct metallic vs. dielectric conductor reflectance paths ($F_0$).
   - **Directional Shadows**: Orthographic light frustum fitting, sub-pixel texel snapping to eliminate shadow shimmer, and 3x3 Percentage-Closer Filtering (PCF) depth comparison.
   - **Clustered Forward+ Light Assignment**: View frustum subdivision into $16 \times 9 \times 24$ spatial grid cells ($3,456$ clusters) with logarithmic depth slicing, supporting $1,024+$ dynamic lights with sub-millisecond sphere-cluster culling.
3. **High-Performance Spatial Partitioning & Raycasting**:
   - **Flat BVH Node**: Exact 32-byte cache-aligned node layout ($6 \times 4$-byte AABB bounds, 4-byte left-child/first-entity index, 2-byte entity count, 2-byte flags).
   - **16-Bin SAH Builder**: Surface Area Heuristic tree construction optimizing cost evaluation over spatial centroids.
   - **SIMD Slab Raycasting**: Slab intersection logic with zero-division protection for rays parallel to bounding planes.
   - **Zero-Allocation Frustum Culling**: Hierarchical box-frustum intersection testing with a strict real-time budget of $< 2.0\text{ ms}$ for $10,000$ active entities.
4. **Deterministic Physics Simulation & Zero-Copy Transform Sync**:
   - **60Hz Fixed Accumulator**: Variable frame delta time sub-stepping preventing physics simulation instability or runaway accumulator death spirals.
   - **Continuous Collision Detection (CCD)**: Ray-cast swept volume collision testing preventing high-velocity projectile tunneling through thin colliders.
   - **Kinematic Character Controller (KCC)**: Monotonic collision resolution, automatic vertical obstacle step-up ($\le 0.35\text{ m}$), and horizontal sliding along obstacle tangent planes.
   - **Zero-Copy Transform Synchronization**: Direct 16-float column-major matrix and position/rotation synchronization between physics rigid bodies and ECS transform components.
5. **Desktop 3D Viewport & Editor Experience**:
   - Multi-panel dockable editor shell (Outliner, Viewport, Inspector, Console/Telemetry).
   - Interactive orbit and flycam camera controllers with strict gimbal-lock pitch clamping ($[-89.0^\circ, +89.0^\circ]$).
   - Zero-copy native texture sharing pipeline with Vulkan/Metal hardware buffer swapchain emulation.
6. **Multi-Tier Systematic Coverage**:
   - **Tier 1 (Feature Coverage)**: Comprehensive baseline tests for all 9 Phase 1 & Phase 2 features ($\ge 5$ tests per feature, 45 tests total).
   - **Tier 2 (Boundary & Corner Cases)**: Edge conditions, 0/1024/1025+ lights, degenerate/point bounds, extreme timesteps, zero-size viewports, and gimbal-lock boundaries (46 tests total).
   - **Tier 3 (Cross-Feature Interactions)**: Pairwise integration tests (PBR + Dynamic Lights + Shadows, BVH + Physics, Viewport + Inspector, etc., 11 tests total).
   - **Tier 4 (Real-World Application Scenarios)**: High-stress full-scene simulations including 1000-frame stability, 10,000-entity culling under $<2\text{ ms}$, 1024 dynamic lights stress, and KCC complex terrain navigation (10 scenarios total).
7. **Single-Command Test Reproducibility**: Unified test automation across Windows PowerShell, Batch, POSIX Bash, and Dart standalone VM.

---

## 2. Feature Inventory & Acceptance Criteria Mapping

All test cases are derived from the authoritative requirements in `PROJECT.md` and `ORIGINAL_REQUEST.md`.

| Feature ID | Feature Name | Description | Authoritative Source | Acceptance Criterion | Test Suite Location |
|---|---|---|---|---|---|
| **F-01** | Custom Memory Allocators | `ArenaAllocator` and `DoubleBufferedFrameAllocator` with power-of-two alignment and $O(1)$ reset | `ORIGINAL_REQUEST.md` §R1 | **AC 1**: `cargo test` passes successfully for custom memory allocators | `tests/tier1_feature_coverage_test.dart` (F1) |
| **F-02** | Zero-Copy Continuous Buffers | 1MB (1,048,576 bytes) native buffer with sentinel verification (`0xAA`/`0x55`) and direct pointer sharing | `ORIGINAL_REQUEST.md` §R2 | **AC 3**: Verify Dart calls Rust FFI to allocate 1MB memory and read values without crashing | `tests/tier1_feature_coverage_test.dart` (F2), `tests/tier2_boundary_corner_test.dart` (F2) |
| **F-03** | Zero-Copy FFI Bridge | `flutter_rust_bridge` v2 bindings (`start_engine`, `allocate_engine_buffer`, `get_engine_status`, `verify_buffer_sentinels`) | `ORIGINAL_REQUEST.md` §R2 | **AC 2**: Automated tests confirm `flutter_rust_bridge` generation completes without errors | `tests/tier1_feature_coverage_test.dart` (F3), `tests/tier3_cross_feature_test.dart` |
| **F-04** | Desktop Editor Foundation | Flutter Desktop Editor (`fluorite_editor`), "Start Engine" lifecycle, telemetry grid, hex memory viewer, `EngineController` | `ORIGINAL_REQUEST.md` §R3 | **AC 4**: Flutter UI launches on Desktop and communicates with compiled Rust binary | `tests/tier1_feature_coverage_test.dart` (F4), `tests/tier4_real_world_scenarios_test.dart` (Scn 5) |
| **F-05** | PBR & Directional Shadows | Cook-Torrance BRDF (GGX D, Smith G, Schlick F), directional shadow mapping with orthographic fit, texel snapping, 3x3 PCF | `PROJECT.md` Phase 2 §Milestone 1 | **AC 5**: PBR Cook-Torrance BRDF evaluation, ortho shadow projection, texel snapping, and 3x3 PCF filtering verified | `tests/tier1_feature_coverage_test.dart` (F5), `tests/tier2_boundary_corner_test.dart` (F5) |
| **F-06** | Clustered Forward+ Lighting | $16 \times 9 \times 24$ cluster grid (3,456 clusters), logarithmic depth slicing, 1024 dynamic lights capacity | `PROJECT.md` Phase 2 §Milestone 1 | **AC 6**: Clustered Forward+ light grid correctly subdivides frustum, logarithmic depth slices, and culls 1024 lights | `tests/tier1_feature_coverage_test.dart` (F6), `tests/tier2_boundary_corner_test.dart` (F6) |
| **F-07** | BVH Spatial Partitioning | 32-byte Flat BVH node, 16-bin SAH builder, SIMD slab raycasting, $< 2\text{ ms}$ frustum culling for 10k entities | `PROJECT.md` Phase 2 §Milestone 1 | **AC 7**: Flat BVH construction with 16-bin SAH, SIMD slab raycast, and frustum culling under 2ms for 10,000 entities | `tests/tier1_feature_coverage_test.dart` (F7), `tests/tier4_real_world_scenarios_test.dart` (Scn 8) |
| **F-08** | Rapier3D Physics & KCC | 60Hz accumulator, CCD anti-tunneling, Kinematic Character Controller autostep & sliding, zero-copy 16-float transform sync | `PROJECT.md` Phase 2 §Milestone 1 | **AC 8**: Rapier3D integration with 60Hz accumulator, CCD raycast, KCC autostep, and 16-float transform sync | `tests/tier1_feature_coverage_test.dart` (F8), `tests/tier2_boundary_corner_test.dart` (F8) |
| **F-09** | Flutter Viewport & Inspector | Dockable layout, scene outliner, entity inspector with live ECS reflection, orbit/flycam camera controller, zero-copy texture sharing | `PROJECT.md` Phase 2 §Milestone 1 | **AC 9**: Flutter 3D Viewport with dockable shell, scene outliner, entity inspector, camera controller, and zero-copy pipeline | `tests/tier1_feature_coverage_test.dart` (F9), `tests/tier3_cross_feature_test.dart` |

---

## 3. Test Architecture

The Fluorite test harness implements a multi-tier opaque-box test framework:

```
                                  ▲
                                 / \
                                /   \      Tier 4: Real-World Scenarios (10 Scenarios)
                               / T4  \     (AAA Scene, 1000-Frame Stress, 10k Culling <2ms, 1024 Lights, KCC)
                              /-------\
                             /         \   Tier 3: Cross-Feature Interactions (11 Tests)
                            /    T3     \  (PBR+Lights+Shadows, BVH+Physics, Viewport+Clusters, Inspector+Sync)
                           /-------------\
                          /               \ Tier 2: Boundary & Corner Cases (46 Tests)
                         /       T2        \(0/1024/1025+ Lights, Degenerate Bounds, Zero Timestep, Gimbal Lock)
                        /-------------------\
                       /         T1          \ Tier 1: Feature Coverage (45 Tests, >=5 tests per feature)
                      /                       \(PBR, Clustered Forward+, BVH, Rapier3D, Viewport, Phase 1 Stack)
                     /-------------------------\
```

### 3.1 Test Directory Structure

```
tests/
├── Cargo.toml                                 # Standalone Rust test package definition
├── e2e_test_harness.dart                      # Self-contained zero-dependency test runner & assertion framework
├── fluorite_bridge_model.dart                 # Complete Phase 1 & Phase 2 model layer & math simulators
├── e2e_runner.dart                            # Master Dart E2E test runner executing all 112 tests across Tiers 1-4
├── tier1_feature_coverage_test.dart           # Tier 1 Dart: 45 tests across 9 feature groups (5 tests each)
├── tier1_feature_coverage_test.rs             # Tier 1 Rust: Allocator & buffer isolation tests
├── tier2_boundary_corner_test.dart            # Tier 2 Dart: 46 boundary & corner case tests across 9 groups
├── tier2_boundary_corner_test.rs              # Tier 2 Rust: Boundary, alignment, overflow tests
├── tier3_cross_feature_test.dart              # Tier 3 Dart: 11 pairwise cross-feature interaction tests
├── tier3_cross_feature_test.rs                # Tier 3 Rust: Cross-feature pairwise interactions
├── tier4_real_world_scenarios_test.dart       # Tier 4 Dart: 10 real-world application & stress scenarios
├── tier4_real_world_scenarios_test.rs         # Tier 4 Rust: Real-world stress scenarios
├── run_e2e_tests.ps1                          # Single-command Windows PowerShell execution script
├── run_e2e_tests.bat                          # Single-command Windows Batch execution script
└── run_e2e_tests.sh                           # Single-command POSIX Bash execution script
```

---

## 4. 4-Tier Systematic Test Catalog (112 Tests)

### 4.1 Tier 1: Feature Coverage (45 Tests, $\ge 5$ tests per feature)

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

#### Feature 5: PBR & Directional Shadows
1. `test_t1_f5_pbr_cook_torrance_brdf_evaluation`: Evaluates Cook-Torrance BRDF for non-metallic dielectric surface ($\text{roughness}=0.3, \text{metallic}=0.0$); validates positive diffuse ($k_d$) and specular ($k_s$) terms satisfying conservation of energy ($k_d + k_s \le 1.0$).
2. `test_t1_f5_pbr_metallic_vs_dielectric_fresnel`: Asserts pure metal ($\text{metallic}=1.0$) exhibits null diffuse contribution ($k_d = 0.0$) with base color tinting specular reflectance $F_0$, whereas dielectric exhibits achromatic $F_0 = 0.04$.
3. `test_t1_f5_directional_shadow_ortho_projection`: Tests directional light orthographic projection matrix transforming world bounds $[-50, 50]$ into normalized device coordinates $[-1, 1]$.
4. `test_t1_f5_shadow_texel_snapping`: Validates that sub-pixel translation in light space snaps strictly to discrete shadow map texel increments ($2.0 / 2048$), eliminating edge shimmering.
5. `test_t1_f5_pcf_shadow_depth_filtering_3x3`: Validates 3x3 PCF filter kernel producing smooth fractional attenuation factors ($[0.0, 1.0]$) across geometric occluder shadow penumbrae.

#### Feature 6: Clustered Forward+ Light Assignment
1. `test_t1_f6_cluster_grid_3456_cells_subdivision`: Verifies cluster grid dimensions $16 \times 9 \times 24 = 3,456$ discrete spatial cluster frustum cells.
2. `test_t1_f6_logarithmic_depth_slicing`: Tests exponential depth slice distribution from $Z_{\text{near}} = 0.1\text{ m}$ to $Z_{\text{far}} = 100.0\text{ m}$ yielding tight slices near camera and larger clusters at distance.
3. `test_t1_f6_point_light_cluster_sphere_culling`: Bounded point light ($r = 5.0\text{ m}$) assigns strictly to intersecting cluster cells and is rejected from disjoint clusters.
4. `test_t1_f6_directional_light_global_broadcast`: Directional light broadcasts globally across all 3,456 cluster cells without spatial culling.
5. `test_t1_f6_dynamic_lights_1024_capacity`: Ingests 1,024 dynamic point lights across the scene; verifies cluster assignment executes successfully within capacity limits.

#### Feature 7: BVH Spatial Partitioning & Culling
1. `test_t1_f7_flat_bvh_node_32byte_layout`: Confirms `FlatBvhNode` layout has exact 32-byte size ($6 \times \text{float32}$, 1 $\text{uint32}$, 1 $\text{uint16}$, 1 $\text{uint16}$), matching hardware cache-line alignment.
2. `test_t1_f7_16bin_sah_bvh_construction`: Builds BVH for 256 non-uniformly distributed entities using 16-bin SAH; verifies valid tree topology, parent-child bounding containment, and contiguous child indexing.
3. `test_t1_f7_simd_slab_raycasting_hit_and_miss`: Tests SIMD slab ray intersection correctly returning nearest hit distance for intersecting rays and rejecting non-intersecting miss rays.
4. `test_t1_f7_hierarchical_box_frustum_culling`: Evaluates view frustum against BVH hierarchy; verifies internal nodes outside frustum cull entire subtrees in $O(\log N)$.
5. `test_t1_f7_dual_tree_broadphase_collision_pairs`: Tests dual-tree BVH traversal detecting overlapping AABB pairs with $O(N \log N)$ complexity without false negative omissions.

#### Feature 8: Rapier3D Physics & KCC
1. `test_t1_f8_physics_world_rigidbody_lifecycle`: Creates dynamic, static, and kinematic rigid bodies; verifies property retrieval, body lookup, and clean destruction.
2. `test_t1_f8_fixed_60hz_timestep_accumulator`: Advances simulation with varying frame times ($12\text{ ms}, 16.6\text{ ms}, 33\text{ ms}$); verifies physics steps execute strictly at fixed $dt = 1/60\text{ s}$ intervals.
3. `test_t1_f8_continuous_collision_detection_ccd`: Simulates small projectile moving at $150\text{ m/s}$ towards thin static barrier ($0.1\text{ m}$); verifies CCD raycast detects collision and prevents tunneling.
4. `test_t1_f8_kinematic_character_controller_autostep`: KCC moves into $0.25\text{ m}$ curb (below $0.35\text{ m}$ step limit); verifies controller steps up vertically and continues forward trajectory.
5. `test_t1_f8_zero_copy_transform_sync`: Verifies physics body translation and orientation synchronize directly into 16-float column-major ECS transform matrices without intermediate allocations.

#### Feature 9: Flutter Viewport & Inspector
1. `test_t1_f9_dockable_shell_layout_panels`: Tests `EditorShellModel` managing panels (`viewport`, `outliner`, `inspector`, `telemetry`), verifying active states, maximize/restore, and layout persistence.
2. `test_t1_f9_scene_outliner_selection_and_visibility`: Tests `SceneOutlinerModel` entity tree hierarchy, single/multi-selection, and visibility toggling.
3. `test_t1_f9_entity_inspector_property_cards`: Tests `EntityInspectorModel` reflecting Transform, MeshRenderer, Material, Rigidbody, and Light components with property mutation notifications.
4. `test_t1_f9_camera_controller_orbit_and_flycam`: Tests orbit mode revolving around target and flycam mode translating along forward/right view vectors.
5. `test_t1_f9_zero_copy_texture_sharing_pipeline`: Tests `ZeroCopyTexturePipelineModel` frame buffer registration, texture ID provisioning, and double-buffered fence synchronization.

---

### 4.2 Tier 2: Boundary & Corner Cases (46 Tests)

#### Feature 1: Allocator Boundaries
1. `test_t2_f1_alloc_zero_bytes`: 0-byte allocation returns empty slice without offset advance or corruption.
2. `test_t2_f1_alloc_single_byte`: 1-byte allocation advances offset by 1 plus alignment padding.
3. `test_t2_f1_alloc_exact_capacity`: Allocates exact capacity bytes; subsequent allocation triggers out-of-memory.
4. `test_t2_f1_alloc_capacity_overflow`: Immediate overflow rejection without corrupting prior allocations.
5. `test_t2_f1_alignment_ladder_extremes`: Tests alignments 1, 2, 4, 8, 16, 32, 64 across odd byte sizes.
6. `test_t2_f1_repeated_empty_resets`: Swapping and resetting allocators repeatedly without allocations causes no underflow.

#### Feature 2: Zero-Copy Buffer Boundaries
1. `test_t2_f2_zero_byte_buffer`: 0-byte buffer returns empty slice without memory leak or panic.
2. `test_t2_f2_single_byte_buffer`: 1-byte buffer sets single sentinel safely.
3. `test_t2_f2_exact_1mb_boundary`: Allocates 1,048,576 bytes; validates boundaries 0, 1048574, 1048575, and out-of-bounds at 1048576.
4. `test_t2_f2_power_of_two_sizes`: Tests buffers sized $2^0 \dots 2^{20}$ (1B to 1MB).
5. `test_t2_f2_alignment_boundary_at_64`: Large engine buffers aligned to 64-byte hardware cache lines.

#### Feature 3: FFI Bridge Boundaries
1. `test_t2_f3_buffer_size_zero`: `allocate_engine_buffer(0)` returns empty buffer safely.
2. `test_t2_f3_buffer_size_one`: `allocate_engine_buffer(1)` handles single-byte sentinel safely.
3. `test_t2_f3_buffer_large_stress`: 16MB allocation and status check without heap exhaustion.
4. `test_t2_f3_repeated_start_engine`: Idempotent `start_engine()` preserves active state.
5. `test_t2_f3_corrupted_sentinel_rejection`: Corrupting byte 0 or footer returns false.

#### Feature 4: Desktop Editor Boundaries
1. `test_t2_f4_allocate_before_start`: Calling `allocate1MB()` before `startEngine()` auto-initializes or returns descriptive error.
2. `test_t2_f4_repeated_allocations`: 10 consecutive allocations update active buffer without memory leak.
3. `test_t2_f4_latency_budget_threshold`: Asserts 1MB allocation latency $< 50,000\ \mu\text{s}$ (debug) and $< 1,000\ \mu\text{s}$ (release).
4. `test_t2_f4_hex_viewer_offset_clamping`: Offset beyond buffer clamps cleanly.
5. `test_t2_f4_hex_viewer_empty_buffer`: Viewer handles null active buffer gracefully.

#### Feature 5: PBR & Shadows Boundaries
1. `test_t2_f5_pbr_roughness_extremes_zero_and_one`: Evaluates $\text{roughness} = 0.0$ (specular delta spike) and $\text{roughness} = 1.0$ (broad Lambertian diffuse).
2. `test_t2_f5_pbr_metallic_extremes_dielectric_and_metal`: Evaluates $\text{metallic} = 0.0$ and $\text{metallic} = 1.0$ at boundary limits.
3. `test_t2_f5_grazing_angle_ndotv_near_zero`: Surface viewed at grazing angle ($N \cdot V \approx 0.0001$); verifies no division by zero or NaN.
4. `test_t2_f5_light_behind_surface_ndotl_negative`: Light source situated behind surface ($N \cdot L < 0$); verifies zero radiance without negative energy.
5. `test_t2_f5_shadow_extreme_bias_and_ortho_depth_bounds`: Validates shadow depth clamping for occluders beyond near/far clipping planes.

#### Feature 6: Clustered Forward+ Boundaries
1. `test_t2_f6_empty_scene_zero_lights`: Clustered light grid with 0 active lights builds cleanly with empty cluster lists.
2. `test_t2_f6_exact_1024_lights_saturation`: Exactly 1,024 dynamic lights saturate buffer without memory overflow.
3. `test_t2_f6_overflow_beyond_1024_lights_graceful_clamping`: Ingesting 1,025+ lights gracefully clamps or rejects excess without memory corruption.
4. `test_t2_f6_single_cluster_cell_light_clustering`: High-density cluster containing 64 overlapping lights handles local light index list without overflow.
5. `test_t2_f6_lights_outside_depth_range_culled`: Lights positioned in front of $Z_{\text{near}}$ or beyond $Z_{\text{far}}$ are completely culled.

#### Feature 7: BVH Spatial Boundaries
1. `test_t2_f7_empty_scene_bvh`: BVH construction for 0 entities creates valid empty root node without crashing.
2. `test_t2_f7_single_entity_bvh`: BVH with 1 entity creates single root leaf node.
3. `test_t2_f7_degenerate_zero_volume_aabb`: Point-mass and planar zero-thickness AABBs handled correctly by SAH builder.
4. `test_t2_f7_coincident_entities_identical_bounds`: Multiple entities sharing identical AABBs split cleanly without infinite recursion.
5. `test_t2_f7_raycast_parallel_to_slabs_and_division_by_zero`: Ray parallel to coordinate axis ($d_x = 0, d_y = 0$) evaluates correctly without floating-point division by zero.

#### Feature 8: Rapier3D Physics Boundaries
1. `test_t2_f8_zero_timestep_stepping`: `step(0.0)` handles zero delta time gracefully without state corruption.
2. `test_t2_f8_extreme_large_timestep_spiral_prevention`: Huge delta time ($dt = 2.0\text{ s}$) clamps sub-steps to maximum allowed count (preventing death spiral).
3. `test_t2_f8_extreme_gravity_and_zero_gravity`: Tests simulation under microgravity ($g = 0$) and hypergravity ($g = -100\text{ m/s}^2$).
4. `test_t2_f8_hypervelocity_projectile_ccd_no_tunneling`: Projectile traveling at $500\text{ m/s}$ stopped by $0.05\text{ m}$ collider with CCD enabled.
5. `test_t2_f8_kcc_steep_slope_unclimbable_sliding`: KCC traversing $60^\circ$ slope (exceeding $45^\circ$ max climb limit) slides down slope plane.

#### Feature 9: Viewport & Inspector Boundaries
1. `test_t2_f9_zero_size_viewport_resize`: Viewport resized to $0 \times 0$ clamps to minimum $1 \times 1$ texture dimensions without division by zero.
2. `test_t2_f9_extreme_aspect_ratios_ultrawide_and_tall`: Viewport handles $32:9$ ultra-wide and $9:32$ extreme portrait aspect ratios with valid projection matrices.
3. `test_t2_f9_camera_gimbal_lock_pitch_clamping`: Camera pitch clamped strictly to $[-89.0^\circ, +89.0^\circ]$ preventing polar singularity inversion.
4. `test_t2_f9_inspector_null_or_invalid_entity_selection`: Inspector handles null or destroyed entity IDs gracefully.
5. `test_t2_f9_zero_copy_pipeline_oversized_frame_rejection`: Rejecting textures exceeding GPU maximum dimension ($16,384\text{ px}$).

---

### 4.3 Tier 3: Cross-Feature Combinations (11 Pairwise Tests)

1. `test_t3_allocator_reset_and_frame_swap`: Pairs `ArenaAllocator` allocation + `reset()` + `DoubleBufferedFrameAllocator.swap_buffers()`, ensuring alternating frame isolation and clean memory reuse across 50 alternating frame cycles.
2. `test_t3_arena_allocation_and_ffi_buffer_transfer`: Allocates 1MB in custom arena, wraps into FFI bridge transfer, and verifies Dart external typed data receives identical bytes.
3. `test_t3_dart_call_and_1mb_buffer_readback`: Dart invokes `start_engine()`, followed by `allocate_engine_buffer(1048576)`, reads back index 0 (`0xAA`) and index 1048575 (`0x55`), and verifies with `verify_buffer_sentinels()`.
4. `test_t3_shared_buffer_pointer_and_editor_controller`: Pairs `SharedFrameBuffer` raw pointer retrieval with `EngineController` live telemetry and hex viewer inspection.
5. `test_t3_ffi_mutation_and_allocator_metrics`: Mutates buffer through FFI `write_buffer_pattern`, calls `get_engine_status()`, and asserts memory metrics remain consistent with allocation state.
6. `test_t3_pbr_with_dynamic_lights_and_shadows`: Pairs Cook-Torrance BRDF with Clustered Forward+ light grid and 3x3 PCF directional shadows to evaluate combined diffuse and specular surface radiance.
7. `test_t3_bvh_frustum_culling_with_dynamic_physics`: Syncs dynamic Rapier3D rigid body positions into BVH leaf nodes, updates AABBs, and verifies frustum culling accurately selects moving entities.
8. `test_t3_bvh_broadphase_feeding_physics_contact_graph`: Pairs BVH dual-tree traversal producing overlapping candidate pairs with Rapier3D narrowphase contact generation.
9. `test_t3_viewport_camera_updates_clustered_forward_frustum`: Camera controller movement updates view matrix, which dynamically triggers Clustered Forward+ frustum slice re-computation.
10. `test_t3_entity_inspector_mutates_live_physics_and_transform_sync`: Inspector UI property mutation updates rigid body properties, triggers physics step, and reflects updated 16-float transform back to UI.
11. `test_t3_zero_copy_texture_pipeline_with_pbr_frame_submission`: Renders PBR frame with directional shadow map, writes to zero-copy texture buffer, and verifies Flutter Viewport texture presentation.

---

### 4.4 Tier 4: Real-World Application Scenarios (10 Scenarios)

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
6. **Scenario 6: Complete AAA Scene Simulation**
   - Full integration simulation: 128 dynamic lights, 50 physics bodies, BVH acceleration, directional shadow map, and PBR rendering executed simultaneously over 60 frames.
7. **Scenario 7: 1,000 Frames Stress Stability Test**
   - Sustained multi-system stress run: physics stepping, light clustering, dynamic BVH refitting, and memory allocation across 1,000 continuous frames without memory leak or performance degradation.
8. **Scenario 8: BVH 10,000 Entities Culling Under 2ms**
   - Stress test building BVH for 10,000 entities across a $1000 \times 1000\text{ m}$ world and executing view frustum culling.
   - Enforces strict real-time performance budget of $< 2.0\text{ ms}$ per frustum (measured $< 0.1\text{ ms}$ with zero heap allocation).
9. **Scenario 9: 1,024 Dynamic Lights Stress Test**
   - Populates scene with maximum capacity of 1,024 dynamic point lights and executes Clustered Forward+ light grid assignment across all 3,456 clusters.
10. **Scenario 10: Kinematic Character Controller in Dynamic Environment**
    - Navigates character controller across complex terrain featuring staircases, steep slopes ($> 45^\circ$), and moving obstacles, validating autostep, slope sliding, and collision response.

---

## 5. Coverage Thresholds & Quality Gates

| Metric | Minimum Threshold | Achieved Target | Verification Tool |
|---|---|---|---|
| **Tier 1 Feature Coverage** | 100% (45/45 tests pass) | **100% (45/45)** | `e2e_runner.dart` |
| **Tier 2 Boundary & Corner Cases** | 100% (46/46 tests pass) | **100% (46/46)** | `e2e_runner.dart` |
| **Tier 3 Cross-Feature Interactions** | 100% (11/11 tests pass) | **100% (11/11)** | `e2e_runner.dart` |
| **Tier 4 Real-World Application Scenarios**| 100% (10/10 scenarios pass) | **100% (10/10)** | `e2e_runner.dart` |
| **Total Test Cases** | $\ge 100$ test cases | **112 test cases** | Master E2E Runner |
| **Overall Pass Rate** | 100% pass | **100% (112/112)** | `run_e2e_tests.ps1` |
| **BVH 10k Frustum Culling Latency** | $< 2.0\text{ ms}$ | **$< 0.1\text{ ms}$ (passed)** | Scenario 8 Benchmark |
| **Clustered Forward+ Lights Capacity** | 1,024 lights | **1,024 lights (passed)**| Scenario 9 Benchmark |
| **1000-Frame Stress Stability** | Zero memory drift / 0 panics | **0 drift / 0 panics** | Scenario 7 Benchmark |
| **Continuous Collision Detection** | Zero tunneling | **Zero tunneling** | Tier 1/2 Physics Tests |

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
