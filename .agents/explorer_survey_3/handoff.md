# Handoff Report: Pillar 3 Survey (Resource Management & ECS)

**Agent:** `explorer_survey_3`  
**Date:** 2026-09-17T03:40:00Z  
**Target:** Parent Orchestrator (`3e5e2dab-1a8d-4421-8c4a-2cf0334d1240`)  
**Scope:** Survey of Fluorescent codebase focusing on Pillar 3 (Resource Management & ECS) per `.agents/ORIGINAL_REQUEST.md`

---

## 1. Observation

### 1.1 Monorepo Structure & Package Layout
- The primary codebase resides at `C:\Users\blue-\projects\Fluorescent\fluorescent` and is orchestrated via `melos.yaml` (`name: fluorescent`, packages: `packages/*`, `examples/*`).
- A duplicate or root-level `packages/` directory exists at `c:\Users\blue-\projects\Fluorescent\packages`, but contains only empty directories with `pubspec.lock` files. The actual working packages are in `c:\Users\blue-\projects\Fluorescent\fluorescent\packages`.
- Current packages in `fluorescent/packages`:
  - `fluorescent_core`
  - `fluorescent_ecs`
  - `fluorescent_flame`
  - `fluorescent_fluorite`
  - `fluorescent_metal`
  - `fluorescent_vulkan`
  - `fluorescent_webgpu`

### 1.2 Current State of ECS (`fluorescent_ecs` vs `fluorescent_core`)
- **`fluorescent_ecs` inspection**:
  - `c:\Users\blue-\projects\Fluorescent\fluorescent\packages\fluorescent_ecs\lib\fluorescent_ecs.dart` (lines 14-34):
    ```dart
    int sum(int a, int b) => _bindings.sum(a, b);
    Future<int> sumAsync(int a, int b) async { ... }
    ```
  - `c:\Users\blue-\projects\Fluorescent\fluorescent\packages\fluorescent_ecs\src\fluorite_ecs_core.cpp` (lines 5-16):
    ```cpp
    FFI_PLUGIN_EXPORT intptr_t sum(intptr_t a, intptr_t b) { return a + b; }
    FFI_PLUGIN_EXPORT intptr_t sum_long_running(intptr_t a, intptr_t b) { ... }
    ```
  - `fluorescent_ecs` is currently an unmodified Flutter FFI plugin boilerplate template. It contains **no ECS implementation**, no entity management, no component storage, and has **no `test/` directory**.
  - Running `flutter test` in `fluorescent_ecs` outputs:
    ```
    Test directory "test" not found.
    (exit code 1)
    ```
- **`fluorescent_core` scene graph inspection**:
  - `c:\Users\blue-\projects\Fluorescent\fluorescent\packages\fluorescent_core\lib\src\scene\entity.dart` (lines 5-22):
    ```dart
    class Entity3D {
      final String id;
      final List<Component3D> _components = [];
      Entity3D(this.id);
      void addComponent(Component3D component) {
        _components.add(component);
        component.onAddedToEntity(this);
      }
      T? getComponent<T extends Component3D>() {
        for (var c in _components) {
          if (c is T) return c;
        }
        return null;
      }
    }
    ```
  - `c:\Users\blue-\projects\Fluorescent\fluorescent\packages\fluorescent_core\lib\src\scene\component.dart` (lines 4-12):
    ```dart
    abstract class Component3D {
      Entity3D? entity;
      void onAddedToEntity(Entity3D entity) { this.entity = entity; }
      void update(double dt) {}
    }
    ```
  - This is an object-oriented Scene Graph / Component model (allocating individual heap objects per entity and per component), **not** a data-oriented ECS.

### 1.3 Current State of Resource Management
- A ripgrep pattern search for `ResourceManager` across the repository yielded:
  ```
  No results found
  ```
- No reference counting classes, GPU memory tracking, or resource abstractions (`Texture`, `Mesh`, `Material`) exist in Dart code in `fluorescent_core` or any other package.
- `c:\Users\blue-\projects\Fluorescent\fluorescent\packages\fluorescent_vulkan\src\model_loader.h` has a C++ `Mesh` struct (`std::vector<Vertex> vertices; std::vector<uint32_t> indices;`), but no Dart wrappers or reference counting.
- `c:\Users\blue-\projects\Fluorescent\fluorescent\packages\fluorescent_core\lib\src\rendering\rendering_server.dart` (lines 3-12) declares low-level rendering stubs:
  ```dart
  abstract class RenderingServer {
    Future<void> initialize();
    void submitDrawCall();
    void renderToTexture(int textureId);
  }
  ```
  No GPU resource lifetime management or reference tracking is wired to this interface.

### 1.4 Test Infrastructure
- `flutter test` in `fluorescent_core` runs successfully:
  ```
  00:00 +0: loading C:/Users/blue-/projects/Fluorescent/fluorescent/packages/fluorescent_core/test/fluorescent_core_test.dart
  00:00 +0: placeholder test
  00:00 +1: All tests passed!
  ```
- Dependency linking between monorepo packages uses path dependencies (e.g. `fluorescent_flame/pubspec.yaml` uses `fluorescent_core: path: ../fluorescent_core`).

---

## 2. Logic Chain

1. **Premise**: `ORIGINAL_REQUEST.md` (R3) states:
   > "Create a `ResourceManager` with reference counting for Textures, Meshes, and Materials to manage GPU memory. Refactor `fluorescent_ecs` to use memory-contiguous `Float32List` arrays for core components like Transforms."
   And Acceptance Criteria:
   > "- ECS benchmark test successfully spawns and iterates over 10,000 entities using TypedData without throwing memory errors."
   > "- Resource manager successfully loads a mock texture, increments its reference count, and frees it when destroyed."

2. **Observation to Inference on ECS (`fluorescent_ecs`)**:
   - `fluorescent_ecs` is currently just the Flutter FFI plugin skeleton.
   - The current `Entity3D` / `Component3D` in `fluorescent_core` stores components in dynamic `List<Component3D>` collections on the Dart garbage-collected heap.
   - For 10,000 entities, an OOP model requires ~50,000+ distinct Dart heap allocations (Entity object, Component list, Transform object, Vector3 positions, Quaternions, Scales), leading to heavy GC overhead, cache misses, and heap fragmentation.
   - Using a **Sparse-Set ECS with contiguous `Float32List` arrays** stores all 10,000 entity Transforms inside a single contiguous typed memory buffer.
   - Storing 10,000 transforms with stride = 16 floats (Position x,y,z; Quaternion x,y,z,w; Scale x,y,z; dirty flags / metadata) consumes only `10,000 * 16 * 4 bytes = 640 KB` of total memory, completely eliminating GC allocations during frame iterations and fitting comfortably inside CPU L2/L3 caches.
   - Therefore, `fluorescent_ecs` must be refactored to provide a high-performance Sparse Set ECS architecture where core components like `Transform` are backed by contiguous `Float32List` storage, with a dedicated benchmark test in `packages/fluorescent_ecs/test/ecs_benchmark_test.dart`.

3. **Observation to Inference on `ResourceManager`**:
   - Neither `fluorescent_core` nor any other package provides resource caching, reference counting, or GPU memory accounting.
   - In 3D graphics (Vulkan/Metal/WebGPU), GPU allocations are unmanaged by the Dart GC and must be freed deterministically to prevent VRAM exhaustion or validation faults.
   - A `ResourceManager` in `fluorescent_core` (at `lib/src/resources/`) provides the natural hub for:
     1. Abstract `Resource` base class implementing intrusive reference counting (`retain()`, `release()`, `refCount`, `byteSize`, `isDisposed`).
     2. Concrete resource wrappers: `TextureResource`, `MeshResource`, `MaterialResource`.
     3. Cascading reference counting: `MaterialResource` retains referenced `TextureResource`s and decrements their ref count upon its own destruction.
     4. GPU memory budget tracking: enforcing memory ceilings (e.g. mobile 512MB, automotive 128MB per `docs/architecture.md`).
     5. Mock texture loading and destruction lifecycle for headless verification tests in `packages/fluorescent_core/test/resource_manager_test.dart`.

---

## 3. Caveats

1. **FFI Plugin Nature of `fluorescent_ecs`**:
   - `packages/fluorescent_ecs` was scaffolded as an FFI plugin (`ffiPlugin: true` in `pubspec.yaml`).
   - However, the ECS data structures (`Float32List`, `Int32List`, sparse set, entity pooling) can and should be implemented in pure Dart within `fluorescent_ecs`. This allows headless execution on any platform, fast test execution via `flutter test`, and isolate sharing without requiring platform-specific C++ compilation during Dart tests.
   - The contiguous `Float32List` layout has the bonus that if native C++/Vulkan passes need the transforms (e.g. uniform buffers, instanced draw matrices), the typed buffer can be passed directly across FFI via pointer without data repacking.
2. **Monorepo Directory Redundancy**:
   - The root-level `packages/` directory at `c:\Users\blue-\projects\Fluorescent\packages` contains ghost folders with only `pubspec.lock` files. All changes must strictly target `c:\Users\blue-\projects\Fluorescent\fluorescent\packages`.
3. **No GPU Hardware in Automated Test Environments**:
   - Automated tests in CI/CD run in headless environments without guaranteed Vulkan/WebGPU hardware.
   - Therefore, `ResourceManager` must support mock/headless texture and buffer allocation with disposal hooks to satisfy the acceptance criteria without external GPU driver dependencies.

---

## 4. Conclusion & Concrete Implementation Blueprint

### 4.1 Architecture for `ResourceManager` (Package: `fluorescent_core`)

#### File Layout
```
fluorescent/packages/fluorescent_core/
├── lib/
│   ├── fluorescent_core.dart (export resources)
│   └── src/
│       └── resources/
│           ├── resource.dart
│           ├── texture_resource.dart
│           ├── mesh_resource.dart
│           ├── material_resource.dart
│           └── resource_manager.dart
└── test/
    └── resource_manager_test.dart
```

#### Detailed Class Specifications

1. **`Resource` (`lib/src/resources/resource.dart`)**:
   - `abstract class Resource`
   - Properties:
     - `final String id`: Unique identifier (path or key).
     - `int _refCount = 1`: Begins at 1 when loaded/created.
     - `int get refCount => _refCount;`
     - `final int byteSize`: GPU memory footprint in bytes.
     - `bool _isDisposed = false;`
     - `bool get isDisposed => _isDisposed;`
   - Methods:
     - `void retain()`: Throws `StateError` if `_isDisposed`. Increments `_refCount++`.
     - `void release()`: Decrements `_refCount--`. If `_refCount <= 0`, calls `dispose()`.
     - `void dispose()`: Sets `_isDisposed = true`, frees GPU resources/callbacks. Throws if called twice.

2. **`TextureResource` (`lib/src/resources/texture_resource.dart`)**:
   - Subclasses `Resource`.
   - Properties:
     - `final int width;`
     - `final int height;`
     - `final String format;` (e.g. `'rgba8unorm'`)
     - `final int? gpuTextureId;` (native texture ID or mock handle)
     - `final void Function(TextureResource resource)? onDispose;`
   - ByteSize calculation: `width * height * 4` (for standard 32-bit RGBA).
   - `dispose()` triggers `onDispose?.call(this)`.

3. **`MeshResource` (`lib/src/resources/mesh_resource.dart`)**:
   - Subclasses `Resource`.
   - Properties:
     - `final int vertexCount;`
     - `final int indexCount;`
     - `final Float32List? vertexData;`
     - `final Uint32List? indexData;`
     - `final int? gpuBufferId;`
     - `final void Function(MeshResource resource)? onDispose;`
   - ByteSize calculation: `(vertexCount * 8 * 4) + (indexCount * 4)`.

4. **`MaterialResource` (`lib/src/resources/material_resource.dart`)**:
   - Subclasses `Resource`.
   - Properties:
     - `final String shaderId;`
     - `final Map<String, dynamic> uniforms;`
     - `final Map<String, TextureResource> textures;`
   - Cascading Lifecycle:
     - In constructor, each texture in `textures` has `texture.retain()` called.
     - In `dispose()`, each texture has `texture.release()` called.

5. **`ResourceManager` (`lib/src/resources/resource_manager.dart`)**:
   - Properties:
     - `final int maxMemoryBudget;` (default e.g. 512MB)
     - `int _totalGpuMemoryUsed = 0;`
     - `int get totalGpuMemoryUsed => _totalGpuMemoryUsed;`
     - `final Map<String, Resource> _cache = {};`
     - `int get cachedResourceCount => _cache.length;`
   - Methods:
     - `bool isCached(String id) => _cache.containsKey(id);`
     - `T? get<T extends Resource>(String id) => _cache[id] as T?;`
     - `T acquire<T extends Resource>(String id, T Function() loader)`:
       - If `_cache.containsKey(id)`: increments ref count of existing resource, returns it.
       - Else: invokes `loader()`, adds to `_cache`, adds `byteSize` to `_totalGpuMemoryUsed`, returns resource.
     - `void release(Resource resource)`:
       - Calls `resource.release()`.
       - If `resource.isDisposed`: removes from `_cache`, subtracts `byteSize` from `_totalGpuMemoryUsed`.
     - `Future<TextureResource> loadMockTexture(String id, {int width = 256, int height = 256, void Function(TextureResource)? onDispose})`:
       - Helper for tests/mocking.
     - `void disposeAll()`: Force-disposes all cached resources, clears `_cache`, resets `_totalGpuMemoryUsed = 0`.

---

### 4.2 Architecture for `fluorescent_ecs`

#### File Layout
```
fluorescent/packages/fluorescent_ecs/
├── lib/
│   ├── fluorescent_ecs.dart (primary export)
│   └── src/
│       ├── entity.dart
│       ├── storage/
│       │   ├── sparse_set.dart
│       │   └── typed_component_storage.dart
│       ├── components/
│       │   └── transform_component.dart
│       ├── systems/
│       │   └── system.dart
│       └── world.dart
└── test/
    ├── ecs_test.dart
    └── ecs_benchmark_test.dart
```

#### Core Data Structures

1. **Entity Representation (`entity.dart`)**:
   - Lightweight integer ID (`typedef Entity = int;` or `extension type Entity(int id)`).
   - Generational index supported via 20-bit index and 12-bit generation if needed, or flat integer IDs with an recycled free list.

2. **Contiguous Transform Storage (`transform_component.dart` & `typed_component_storage.dart`)**:
   - Core Problem: 10,000 separate `Transform` heap objects cause massive GC and memory overhead.
   - Solution: Contiguous `Float32List` array storage.
   - Stride: **16 floats per entity** (64 bytes):
     - Offsets `0..2`: Translation `(x, y, z)`
     - Offset `3`: Flags / dirty bit
     - Offsets `4..7`: Quaternion Rotation `(x, y, z, w)`
     - Offsets `8..10`: Scale `(sx, sy, sz)`
     - Offset `11`: Reserved
     - Offsets `12..15`: Bounding sphere / custom payload
   - **Sparse-Set Indexing**:
     - `Int32List _sparse`: Maps `entityId -> denseIndex`.
     - `Int32List _dense`: Maps `denseIndex -> entityId`.
     - `Float32List _data`: Contiguous buffer of floats of size `capacity * stride`.
     - `int _count`: Number of active entities.
   - **Performance Benefits**:
     - O(1) component lookup by entity ID: `_data[_sparse[entity] * stride + field]`.
     - O(1) removal via swap-and-pop: swap last dense item into removed slot, update sparse index, decrement `_count`.
     - Dense iteration: Loops traverse index `0` to `_count * stride - 1` linearly. The CPU prefetcher streams memory with zero pointer indirection.

3. **`EcsWorld` (`world.dart`)**:
   - `Entity createEntity()`
   - `void destroyEntity(Entity entity)`
   - `TransformStorage transforms`
   - `void updateTransforms(void Function(int entity, Float32List data, int offset) callback)` or direct system loops.

---

## 5. Verification Method

### 5.1 Resource Manager Acceptance Test
**File:** `packages/fluorescent_core/test/resource_manager_test.dart`  
**Command:** `flutter test test/resource_manager_test.dart` inside `fluorescent/packages/fluorescent_core`  
**Test Spec:**
1. **Mock Texture Ref-Count & Free Verification**:
   - Create `final rm = ResourceManager(maxMemoryBudget: 1024 * 1024);`
   - Track disposal with a boolean `bool gpuFreed = false;`
   - Load mock texture:
     `final tex1 = await rm.loadMockTexture('tex/wood.png', width: 128, height: 128, onDispose: (_) => gpuFreed = true);`
   - Verify `tex1.refCount == 1`, `tex1.byteSize == 128 * 128 * 4 == 65536`.
   - Verify `rm.totalGpuMemoryUsed == 65536`, `rm.isCached('tex/wood.png') == true`.
   - Acquire again: `final tex2 = await rm.loadMockTexture('tex/wood.png');`
   - Verify `identical(tex1, tex2)`, `tex1.refCount == 2`, `rm.totalGpuMemoryUsed == 65536` (no duplicate memory allocation).
   - Release once: `rm.release(tex1);`
   - Verify `tex1.refCount == 1`, `tex1.isDisposed == false`, `gpuFreed == false`, `rm.isCached('tex/wood.png') == true`.
   - Release again: `rm.release(tex2);`
   - Verify `tex1.refCount == 0`, `tex1.isDisposed == true`, `gpuFreed == true`, `rm.isCached('tex/wood.png') == false`, `rm.totalGpuMemoryUsed == 0`.
2. **Material Cascading Reference Count Verification**:
   - Verify that when a `MaterialResource` holding a `TextureResource` is destroyed, the child texture's reference count is automatically decremented and freed if it reaches 0.

### 5.2 ECS 10,000 Entities Benchmark Test
**File:** `packages/fluorescent_ecs/test/ecs_benchmark_test.dart`  
**Command:** `flutter test test/ecs_benchmark_test.dart` inside `fluorescent/packages/fluorescent_ecs`  
**Test Spec:**
1. **Spawn 10,000 Entities with Contiguous Transforms**:
   - Instantiate `final world = EcsWorld();`
   - Spawn loop:
     ```dart
     final stopwatch = Stopwatch()..start();
     for (int i = 0; i < 10000; i++) {
       final entity = world.createEntity();
       world.transforms.set(entity, x: i * 1.0, y: 0.0, z: 0.0, sx: 1.0, sy: 1.0, sz: 1.0);
     }
     stopwatch.stop();
     ```
   - Verify `world.entityCount == 10000`.
   - Verify no `OutOfMemoryError` or exceptions are thrown.
   - Assert spawn time is < 100 ms.
2. **Iterate Over 10,000 Entities with TypedData**:
   - Simulate 60 frame iterations:
     ```dart
     final iterStopwatch = Stopwatch()..start();
     for (int frame = 0; frame < 60; frame++) {
       world.transforms.forEach((entity, data, offset) {
         data[offset + 1] += 0.5; // Translate Y
       });
     }
     iterStopwatch.stop();
     ```
   - Verify data integrity: for entity 0, `world.transforms.getY(0) == 60 * 0.5 == 30.0`.
   - Assert total iteration time for 60 frames (600,000 entity component updates) is < 100 ms (< 1.6 ms/frame, well exceeding 60 FPS performance).

### 5.3 Invalidation Conditions
- Any solution that leaves `fluorescent_ecs` as an un-implemented FFI boilerplate.
- Any ECS storage model that relies on heap `List<Component3D>` objects for core transform loops, which fails cache locality and incurs GC pressure.
- Any `ResourceManager` implementation lacking deterministic reference counting or failing to reclaim GPU memory when reference counts drop to zero.
