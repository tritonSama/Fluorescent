import 'dart:async';
import 'dart:typed_data';
import 'material_resource.dart';
import 'mesh_resource.dart';
import 'resource.dart';
import 'texture_resource.dart';

/// Exception thrown when a resource allocation would exceed [ResourceManager.maxMemoryBudget].
class GpuMemoryBudgetExceededException implements Exception {
  /// The resource identifier that failed allocation.
  final String resourceId;

  /// Number of bytes requested for allocation.
  final int requiredBytes;

  /// Current GPU memory used in bytes.
  final int currentUsage;

  /// Maximum allowed budget in bytes.
  final int maxBudget;

  GpuMemoryBudgetExceededException({
    required this.resourceId,
    required this.requiredBytes,
    required this.currentUsage,
    required this.maxBudget,
  });

  @override
  String toString() =>
      'GpuMemoryBudgetExceededException: Allocating resource "$resourceId" ($requiredBytes bytes) '
      'would exceed memory budget. Used: $currentUsage bytes, Max: $maxBudget bytes.';
}

/// Central manager for GPU resources (Textures, Meshes, Materials) with
/// reference counting, caching, and VRAM memory budget accounting.
class ResourceManager {
  /// Maximum GPU memory budget in bytes.
  final int maxMemoryBudget;

  /// Whether to throw [GpuMemoryBudgetExceededException] if an allocation exceeds [maxMemoryBudget].
  final bool enforceBudget;

  int _totalGpuMemoryUsed = 0;
  final Map<String, Resource> _cache = <String, Resource>{};

  /// Creates a [ResourceManager] with an optional [maxMemoryBudget] (default 512 MB).
  ResourceManager({
    this.maxMemoryBudget = 512 * 1024 * 1024,
    this.enforceBudget = false,
  }) : assert(maxMemoryBudget >= 0, 'maxMemoryBudget cannot be negative');

  /// Total GPU memory allocated by active cached resources in bytes.
  int get totalGpuMemoryUsed => _totalGpuMemoryUsed;

  /// Remaining GPU memory budget in bytes before reaching [maxMemoryBudget].
  int get remainingMemoryBudget => maxMemoryBudget - _totalGpuMemoryUsed;

  /// Whether current memory usage exceeds [maxMemoryBudget].
  bool get isOverBudget => _totalGpuMemoryUsed > maxMemoryBudget;

  /// Fraction of the memory budget currently consumed (0.0 to 1.0+).
  double get memoryUsageRatio =>
      maxMemoryBudget > 0 ? _totalGpuMemoryUsed / maxMemoryBudget : 0.0;

  /// Total number of active cached resources.
  int get cachedResourceCount => _cache.length;

  /// An unmodifiable view of all active cached resources.
  Iterable<Resource> get cachedResources => _cache.values;

  /// Whether a resource with the specified [id] is currently cached.
  bool isCached(String id) => _cache.containsKey(id);

  /// Whether a resource with the specified [id] is currently cached.
  bool contains(String id) => _cache.containsKey(id);

  /// Retrieves a cached resource by [id] without altering its reference count.
  /// Returns `null` if not cached or if not of type [T].
  T? get<T extends Resource>(String id) {
    final res = _cache[id];
    if (res is T) return res;
    return null;
  }

  /// Manually registers an existing [Resource] into the manager.
  ///
  /// Throws [StateError] if a resource with the same id is already registered.
  /// Throws [GpuMemoryBudgetExceededException] if [enforceBudget] is true and
  /// registering exceeds [maxMemoryBudget].
  void register(Resource resource) {
    if (_cache.containsKey(resource.id)) {
      throw StateError(
        'Resource with id "${resource.id}" is already registered.',
      );
    }
    if (enforceBudget &&
        (_totalGpuMemoryUsed + resource.byteSize > maxMemoryBudget)) {
      throw GpuMemoryBudgetExceededException(
        resourceId: resource.id,
        requiredBytes: resource.byteSize,
        currentUsage: _totalGpuMemoryUsed,
        maxBudget: maxMemoryBudget,
      );
    }
    _registerResource(resource);
  }

  /// Acquires a resource by [id].
  ///
  /// If the resource is already cached, its reference count is incremented via
  /// [Resource.retain] and the cached instance is returned.
  ///
  /// If not cached, [loader] is executed to create the resource, which is then
  /// registered into the cache and tracked in [totalGpuMemoryUsed].
  ///
  /// Throws [StateError] if a cached resource with [id] exists but is not of type [T].
  /// Throws [ArgumentError] if the resource is not cached and no [loader] is provided.
  /// Throws [GpuMemoryBudgetExceededException] if [enforceBudget] is true and allocation exceeds budget.
  T acquire<T extends Resource>(String id, [T Function()? loader]) {
    final cached = _cache[id];
    if (cached != null) {
      if (cached is! T) {
        throw StateError(
          'Cached resource "$id" is of type ${cached.runtimeType}, expected $T.',
        );
      }
      cached.retain();
      return cached;
    }

    if (loader == null) {
      throw ArgumentError(
        'Resource "$id" is not cached and no loader callback was provided.',
      );
    }

    final resource = loader();

    if (enforceBudget &&
        (_totalGpuMemoryUsed + resource.byteSize > maxMemoryBudget)) {
      throw GpuMemoryBudgetExceededException(
        resourceId: id,
        requiredBytes: resource.byteSize,
        currentUsage: _totalGpuMemoryUsed,
        maxBudget: maxMemoryBudget,
      );
    }

    _registerResource(resource);
    return resource;
  }

  /// Asynchronously acquires a resource by [id].
  ///
  /// If the resource is already cached, its reference count is incremented via
  /// [Resource.retain] and the cached instance is returned immediately.
  ///
  /// Otherwise, [loader] is awaited to create the resource, which is registered
  /// and returned.
  Future<T> acquireAsync<T extends Resource>(
    String id,
    Future<T> Function() loader,
  ) async {
    final cached = _cache[id];
    if (cached != null) {
      if (cached is! T) {
        throw StateError(
          'Cached resource "$id" is of type ${cached.runtimeType}, expected $T.',
        );
      }
      cached.retain();
      return cached;
    }

    final resource = await loader();

    if (enforceBudget &&
        (_totalGpuMemoryUsed + resource.byteSize > maxMemoryBudget)) {
      throw GpuMemoryBudgetExceededException(
        resourceId: id,
        requiredBytes: resource.byteSize,
        currentUsage: _totalGpuMemoryUsed,
        maxBudget: maxMemoryBudget,
      );
    }

    _registerResource(resource);
    return resource;
  }

  /// Releases a reference to the given [resource].
  ///
  /// Decrements [resource.refCount]. If the reference count drops to 0,
  /// the resource is automatically disposed, removed from cache, and its
  /// [byteSize] is deducted from [totalGpuMemoryUsed].
  void release(Resource resource) {
    resource.release();
    if (resource.isDisposed && _cache[resource.id] == resource) {
      _unregisterResource(resource);
    }
  }

  /// Releases a resource by its [id].
  ///
  /// Does nothing if no resource with [id] is cached.
  void releaseById(String id) {
    final resource = _cache[id];
    if (resource != null) {
      release(resource);
    }
  }

  /// Loads or retrieves a mock texture for testing and headless execution.
  ///
  /// If [id] is already cached, increments its ref count and returns the existing texture.
  /// Otherwise, instantiates a new [TextureResource] with the provided parameters.
  Future<TextureResource> loadMockTexture(
    String id, {
    int width = 256,
    int height = 256,
    String format = 'rgba8unorm',
    int? gpuTextureId,
    void Function(TextureResource)? onDispose,
  }) async {
    return loadMockTextureSync(
      id,
      width: width,
      height: height,
      format: format,
      gpuTextureId: gpuTextureId,
      onDispose: onDispose,
    );
  }

  /// Synchronously loads or retrieves a mock texture for testing.
  TextureResource loadMockTextureSync(
    String id, {
    int width = 256,
    int height = 256,
    String format = 'rgba8unorm',
    int? gpuTextureId,
    void Function(TextureResource)? onDispose,
  }) {
    return acquire<TextureResource>(
      id,
      () => TextureResource(
        id: id,
        width: width,
        height: height,
        format: format,
        gpuTextureId: gpuTextureId,
        onDispose: onDispose,
      ),
    );
  }

  /// Loads or retrieves a mock mesh for testing.
  MeshResource loadMockMesh(
    String id, {
    required int vertexCount,
    int indexCount = 0,
    Float32List? vertexData,
    TypedData? indexData,
    int? gpuBufferId,
    void Function(MeshResource)? onDispose,
  }) {
    return acquire<MeshResource>(
      id,
      () => MeshResource(
        id: id,
        vertexCount: vertexCount,
        indexCount: indexCount,
        vertexData: vertexData,
        indexData: indexData,
        gpuBufferId: gpuBufferId,
        onDispose: onDispose,
      ),
    );
  }

  /// Loads or retrieves a mock material for testing.
  MaterialResource loadMockMaterial(
    String id, {
    required String shaderId,
    Map<String, dynamic>? uniforms,
    Map<String, TextureResource>? textures,
    void Function(MaterialResource)? onDispose,
  }) {
    return acquire<MaterialResource>(
      id,
      () => MaterialResource(
        id: id,
        shaderId: shaderId,
        uniforms: uniforms,
        textures: textures,
        onDispose: onDispose,
      ),
    );
  }

  /// Disposes all active cached resources, clears the cache, and resets [totalGpuMemoryUsed] to 0.
  void disposeAll() {
    final resources = _cache.values.toList();
    for (final resource in resources) {
      if (!resource.isDisposed) {
        resource.dispose();
      }
    }
    _cache.clear();
    _totalGpuMemoryUsed = 0;
  }

  void _registerResource(Resource resource) {
    _cache[resource.id] = resource;
    _totalGpuMemoryUsed += resource.byteSize;

    // Attach disposal hook so if resource is disposed externally (e.g. cascading release),
    // ResourceManager automatically purges it from cache and updates memory budget.
    final existingHook = resource.onResourceDisposed;
    resource.onResourceDisposed = (res) {
      existingHook?.call(res);
      _unregisterResource(res);
    };
  }

  void _unregisterResource(Resource resource) {
    if (_cache[resource.id] == resource) {
      _cache.remove(resource.id);
      _totalGpuMemoryUsed -= resource.byteSize;
      if (_totalGpuMemoryUsed < 0) {
        _totalGpuMemoryUsed = 0;
      }
    }
  }
}
