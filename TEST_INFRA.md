# Fluorescent 3D Engine — Test Infrastructure (TEST_INFRA)

## 1. Test Philosophy

The Fluorescent 3D Engine test architecture is anchored on the principle of **hermetic, deterministic, opaque-box verification**. Fluorescent is designed as a high-performance 3D engine spanning multiple targets (WebGPU, Vulkan, Metal, Flame, Flutter). Because game loops and graphics pipelines are unforgiving of latency spikes, memory leaks, and concurrency deadlocks, our testing philosophy mandates:

1. **Opaque-Box Contract Verification**: Tests evaluate observable public interfaces, handle IDs, data transformations, and lifecycle invariants without depending on private implementation details.
2. **Deterministic Concurrency**: Background isolate message passing, command routing, and asynchronous query-response loops are tested under high message pressure with microsecond timer assertions to verify non-blocking execution on the main thread.
3. **Zero-Allocation Data Integrity**: Typed array storage (contiguously packed `Float32List` ECS storage with 16-float strides) is benchmarked under sustained multi-frame iteration (10,000 entities x 60 frames) to prove absence of garbage-collection spikes, heap fragmentation, and memory errors.
4. **VRAM Lifetime Accounting**: GPU resources (Textures, Meshes, Materials) are subjected to strict retain/release lifecycle tests to prove leak-free memory reclamation, cascading texture release on material destruction, and memory budget enforcement.
5. **Multi-Target Shader & Asset Reproducibility**: Asset compilation and shader transpilation pipelines produce reproducible binary `.fworld` files verified against magic byte headers (`0x46, 0x57, 0x4C, 0x44`), table-of-contents manifests, and valid SPIR-V bytecode headers (`0x07230203`).

---

## 2. Feature Inventory & Acceptance Criteria Mapping

| ID | Feature / Pillar | Scope | Authoritative Source | Acceptance Criterion | Test Suite |
|---|---|---|---|---|---|
| **F-01** | Server Architecture & Dart Isolates | Background simulation stepping, isolate handshake, asynchronous query-response completers | `PROJECT.md` §R1, M1 | **AC 1**: Dart Isolates spawn & communicate without blocking main thread | `ac1_server_isolate_e2e_test.dart` |
| **F-02** | Render Graph & DAG Resolution | Data-driven JSON/YAML render graph compilation, topological sorting, DAG cycle detection | `PROJECT.md` §R2, M4 | Pillar 2 verification | `pillar2_render_graph_e2e_test.dart` |
| **F-03** | Asset Pipeline CLI & `.fworld` Packaging | Standalone CLI tool, GLTF 2.0 ingestion, compressed binary packaging (zlib/gzip/none) | `PROJECT.md` §R2, M5 | **AC 2**: CLI compiles test .gltf and .wgsl into .fworld binary | `ac2_asset_pipeline_e2e_test.dart` |
| **F-04** | Resource Management & GPU Memory | Reference counting, retain/release semantics, VRAM budget tracking, cascading disposal | `PROJECT.md` §R3, M2 | **AC 4**: Resource manager loads mock texture, increments ref count, frees on destroy | `ac4_resource_manager_e2e_test.dart` |
| **F-05** | Contiguous TypedData ECS Storage | Sparse-Set contiguous `Float32List` storage, 16-float stride for transforms, ID recycling | `PROJECT.md` §R3, M3 | **AC 3**: ECS benchmark spawns and iterates over 10,000 entities without memory errors | `ac3_ecs_benchmark_e2e_test.dart` |
| **F-06** | Shader Toolchain (WGSL -> SPIR-V/MSL) | Naga FFI with demo fallback transpiler, multi-target bytecode embedding (`0x07230203`) | `PROJECT.md` §R4, M5 | Pillar 6 verification | `pillar6_shader_toolchain_e2e_test.dart` |

---

## 3. Test Architecture

The Fluorescent test hierarchy is organized into a three-tier test pyramid:

```
                  ▲
                 / \
                /   \     Tier 3: Opaque-Box E2E Integration Suite
               / E2E \    (fluorescent/test/e2e/)
              /-------\   - End-to-end multi-isolate concurrency
             /         \  - Full CLI compilation (.gltf + .wgsl -> .fworld)
            / Component \ - 10,000 entity ECS TypedData stress benchmarks
           /   Suites    \- VRAM retain/release cascading lifecycles
          /---------------\
         /   Unit Tests    \ Tier 1 & 2: Package-level Unit & Contract Tests
        /                   \ (packages/fluorescent_*/test, tools/asset_pipeline/test)
       /---------------------\
```

### 3.1 Test Suite Directory Structure
```
fluorescent/
├── test/
│   └── e2e/
│       ├── e2e_test_harness.dart              # Self-contained testing harness & matchers
│       ├── ac1_server_isolate_e2e_test.dart   # AC 1 & Pillar 1: ServerManager Isolate concurrency
│       ├── ac2_asset_pipeline_e2e_test.dart   # AC 2 & Pillar 3: CLI GLTF + WGSL compilation to .fworld
│       ├── ac3_ecs_benchmark_e2e_test.dart    # AC 3 & Pillar 5: 10k entity TypedData benchmark
│       ├── ac4_resource_manager_e2e_test.dart # AC 4 & Pillar 4: Mock texture retain/release/free
│       ├── pillar2_render_graph_e2e_test.dart # Pillar 2: RenderGraph YAML/JSON, DAG sort & cycles
│       ├── pillar6_shader_toolchain_e2e_test.dart # Pillar 6: Naga FFI / Demo WGSL -> SPIR-V/MSL
│       ├── e2e_runner_test.dart               # Unified test runner orchestrating all suites
│       ├── run_e2e_tests.ps1                  # Windows PowerShell execution script
│       └── run_e2e_tests.sh                   # POSIX Bash execution script
```

### 3.2 Dual Execution Modes
The test suite supports dual execution modes:
1. **Unified Test Runner (`e2e_runner_test.dart`)**:
   Can be run directly with the Dart VM (`dart test/e2e/e2e_runner_test.dart`), via standard `dart test`, or with `flutter test test/e2e/e2e_runner_test.dart`. It includes automated test discovery, timed execution per test case, TAP-compatible output, aggregate pass/fail metrics, and an exit code protocol (0 for clean pass, 1 on failure).
2. **Modular Granular Execution**:
   Each test file (`ac1_server_isolate_e2e_test.dart`, etc.) has an independent `main()` function and can be executed individually for focused debugging and regression isolation.

---

## 4. Scenario Catalog

### 4.1 AC 1: Dart Isolates & Server Architecture
- **E2E-AC1-001 (Isolate Handshake & Lifecycle)**:
  - Spawns background worker isolate via `ServerManager.initialize()`.
  - Verifies bidirectional port exchange, ack handshake completion, and `isInitialized == true`.
  - Disposes `ServerManager` and confirms worker isolate termination.
- **E2E-AC1-002 (Non-Blocking Concurrency Under Pressure)**:
  - Runs a high-frequency main thread event loop counter (microtasks and periodic timers).
  - Fires 2,000 asynchronous commands (`physics_create_body`, `physics_apply_force`, `nav_set_agent_position`) to background isolate.
  - Verifies that main thread latency remains sub-millisecond and zero frames are dropped.
- **E2E-AC1-003 (Asynchronous Query-Response Completers)**:
  - Dispatches multiple parallel queries (`raycast`, `getBodyTransform`, `findPath`).
  - Asserts that completers resolve concurrently with exact geometric values without race conditions.
- **E2E-AC1-004 (Simulation Tick Broadcast Stream)**:
  - Listens to `ServerManager.onTickUpdate` stream over 10 background simulation ticks.
  - Asserts that body transform positions and agent positions update deterministically.

### 4.2 AC 2: Asset Pipeline CLI Tooling & Binary Serialization
- **E2E-AC2-001 (CLI End-to-End Compilation)**:
  - Generates valid test `.gltf` (with positions, normals, UVs, indices) and valid `.wgsl` shader.
  - Runs CLI entrypoint: `bin/asset_pipeline.dart --gltf <gltf> --shader <shader> --output <fworld> --compress zlib`.
  - Asserts exit code 0 and non-empty output file.
- **E2E-AC2-002 (`.fworld` Container Verification)**:
  - Reads binary bytes from generated `.fworld` file.
  - Asserts 4-byte magic signature `[0x46, 0x57, 0x4C, 0x44]` ('FWLD').
  - Deserializes payload using `FWorldReader.readPackage()`.
  - Verifies manifest TOC contains extracted mesh and shader counts.
  - Validates mesh buffer sizes, indices, and bounding boxes.
  - Validates shader bundle contains original WGSL, compiled SPIR-V with magic `0x07230203`, and MSL source code.
- **E2E-AC2-003 (Compression Algorithm Modes)**:
  - Compiles identical assets under `zlib`, `gzip`, and `none` compression modes.
  - Asserts all three decompress and yield bit-for-bit identical mesh and shader structures.

### 4.3 AC 3: ECS Contiguous TypedData Storage & 10,000 Entity Benchmark
- **E2E-AC3-001 (10,000 Entity Spawning)**:
  - Creates 10,000 entities in `EcsWorld`.
  - Sets contiguous 16-float transform components (translation, rotation, scale, bounds).
  - Asserts `world.entityCount == 10000` and `world.transforms.count == 10000`.
- **E2E-AC3-002 (Memory Footprint Validation)**:
  - Inspects `world.transforms.data.lengthInBytes`.
  - Asserts total memory buffer is strictly bounded (< 2 MB, nominal ~640 KB for 10k entities).
  - Asserts zero `OutOfMemoryError` and zero GC allocation churn.
- **E2E-AC3-003 (60-Frame Sustained Iteration Benchmark)**:
  - Iterates 60 frames updating all 10,000 entities via `world.transforms.forEach()` (600,000 updates).
  - Asserts execution completes well within 16ms/frame budget (typically < 100ms total for all 60 frames).
  - Verifies numerical correctness: entity `i` has updated Y coordinate equal to `frame_count * delta`.
- **E2E-AC3-004 (Entity Destruction & ID Recycling)**:
  - Destroys 2,500 entities; verifies sparse set compaction and count drops to 7,500.
  - Spawns 1,000 new entities; asserts recycled IDs are reused in LIFO order with zero memory leaks.

### 4.4 AC 4: Resource Manager Reference Counting & GPU VRAM Management
- **E2E-AC4-001 (Mock Texture Load & Initial RefCount)**:
  - Loads mock texture `tex_player` (512x512, RGBA8).
  - Asserts `refCount == 1`, `isDisposed == false`, and `totalGpuMemoryUsed == 1048576` bytes (1 MB).
- **E2E-AC4-002 (Cache Hit & RefCount Increment)**:
  - Calls `loadMockTexture('tex_player')` a second time.
  - Asserts same instance returned (`identical(tex1, tex2) == true`), `refCount == 2`.
  - Asserts `totalGpuMemoryUsed` remains 1 MB (no duplicate GPU allocation).
- **E2E-AC4-003 (Release & Automated Destruction)**:
  - Releases first reference: `resourceManager.release(tex1)`.
  - Asserts `refCount == 1`, `isDisposed == false`, resource remains cached.
  - Releases second reference: `resourceManager.release(tex2)`.
  - Asserts `refCount == 0`, `isDisposed == true`, resource removed from cache.
  - Asserts `totalGpuMemoryUsed == 0` and `cachedResourceCount == 0`.
- **E2E-AC4-004 (Cascading Material Release)**:
  - Creates `MaterialResource` referencing diffuse and normal `TextureResource`s.
  - Retains textures through material registration.
  - Releases material: asserts that underlying textures are automatically released and GPU memory reclaimed.
- **E2E-AC4-005 (VRAM Budget Enforcement)**:
  - Configures `ResourceManager` with 2 MB memory budget and `enforceBudget == true`.
  - Allocates two 1 MB textures successfully.
  - Attempts to allocate a third 1 MB texture; asserts `GpuMemoryBudgetExceededException` is thrown.

### 4.5 Pillar 2: Data-Driven RenderGraph DAG
- **E2E-P2-001 (JSON / YAML Schema Parsing)**:
  - Parses multi-pass render graph specification containing `ShadowPass`, `GBufferPass`, `LightingPass`, `PostProcessPass`.
  - Validates pass dependencies and attachment bindings.
- **E2E-P2-002 (DAG Cycle Detection)**:
  - Constructs cyclic dependency graph (`Pass A -> Pass B -> Pass C -> Pass A`).
  - Asserts `compile()` throws `RenderGraphCycleException` with cycle path diagnostics.
- **E2E-P2-003 (Topological Sort Execution Order)**:
  - Compiles valid DAG; asserts compiled pass execution order strictly respects dependency prerequisites.

### 4.6 Pillar 6: Multi-Target Shader Toolchain
- **E2E-P6-001 (WGSL to SPIR-V Binary Transpilation)**:
  - Transpiles WGSL vertex and fragment shaders.
  - Asserts generated SPIR-V binary words begin with magic number `0x07230203`.
  - Validates entry point names and memory layout.
- **E2E-P6-002 (WGSL to Metal Shading Language Translation)**:
  - Transpiles WGSL shader; asserts output contains valid MSL attributes (`vertex`, `fragment`, `[[position]]`, `float4`).
- **E2E-P6-003 (Resilient Dual-Mode Toolchain)**:
  - Verifies seamless fallback to `DemoShaderTranspiler` when native Naga dynamic libraries are not installed on the host.

---

## 5. Coverage Thresholds & Quality Gates

The Fluorescent engine enforces the following quality gates for test execution:

| Subsystem | Line Coverage | Contract Completeness | Invariant Verification |
|---|---|---|---|
| **Pillar 1: Server Architecture** | >= 90% | 100% of methods in `PhysicsServer`, `NavigationServer`, `ServerManager` | Zero main-thread blocking, clean isolate shutdown |
| **Pillar 2: Render Graph** | >= 90% | 100% of JSON/YAML descriptors, DAG sort, cycle detection | Cycle exception throw on loops, strict topological order |
| **Pillar 3: Asset Pipeline** | >= 90% | 100% of CLI arguments (`--gltf`, `--shader`, `--output`, `--compress`) | Magic bytes `FWLD`, valid TOC, valid geometry buffers |
| **Pillar 4: Resource Management** | >= 95% | 100% of `Resource`, `ResourceManager`, `TextureResource`, `MaterialResource` | Zero GPU memory leaks, strict ref count lifecycle |
| **Pillar 5: Contiguous ECS** | >= 95% | 100% of `SparseSet`, `TypedComponentStorage`, `TransformStorage`, `EcsWorld` | Zero memory errors on 10k entities, 60-frame loop pass |
| **Pillar 6: Shader Toolchain** | >= 90% | 100% of `ShaderTranspiler`, `ShaderBundle`, fallback transpiler | SPIR-V magic `0x07230203`, MSL syntax compliance |
| **Overall E2E Suite** | **100% Pass** | **4 / 4 Acceptance Criteria Covered** | **Zero unhandled exceptions or memory leaks** |
