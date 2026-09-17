import 'dart:typed_data';

import '../entity.dart';
import 'sparse_set.dart';

/// Base storage for typed components backed by contiguous [Float32List] memory.
///
/// Wraps [SparseSet] to provide type-safe [Entity] indexing and zero-allocation linear
/// iterations over densely packed component arrays.
class TypedComponentStorage {
  /// The underlying sparse set data structure.
  final SparseSet _sparseSet;

  /// The number of 32-bit float values per component.
  final int stride;

  /// Creates a [TypedComponentStorage] with the specified component [stride]
  /// and initial buffer capacities.
  TypedComponentStorage({
    required this.stride,
    int initialCapacity = 64,
    int initialSparseCapacity = 256,
  })  : _sparseSet = SparseSet(
          stride: stride,
          initialCapacity: initialCapacity,
          initialSparseCapacity: initialSparseCapacity,
        );

  /// Number of active components currently stored.
  int get count => _sparseSet.count;

  /// Current allocated capacity for entities in the dense buffer.
  int get capacity => _sparseSet.capacity;

  /// Whether the storage contains no components.
  bool get isEmpty => _sparseSet.isEmpty;

  /// Whether the storage contains at least one component.
  bool get isNotEmpty => _sparseSet.isNotEmpty;

  /// The underlying contiguous float data buffer.
  Float32List get rawData => _sparseSet.data;

  /// Synonym for [rawData].
  Float32List get data => _sparseSet.data;

  /// The dense array containing packed entity IDs from index `0` to `count - 1`.
  Int32List get denseEntities => _sparseSet.dense;

  /// Synonym for [denseEntities].
  Int32List get dense => _sparseSet.dense;

  /// The sparse array mapping `entityId` to dense index.
  Int32List get sparse => _sparseSet.sparse;

  /// Returns whether [entity] has a component stored in this buffer.
  bool has(Entity entity) => _sparseSet.contains(entity.id);

  /// Allocates component space for [entity] and returns the float offset in [rawData].
  ///
  /// If [entity] already has a component in this storage, returns its existing offset.
  int allocate(Entity entity) => _sparseSet.add(entity.id);

  /// Removes the component for [entity] using swap-and-pop to preserve dense packing.
  ///
  /// Returns `true` if the entity was present and removed, `false` otherwise.
  bool remove(Entity entity) => _sparseSet.remove(entity.id);

  /// Returns the float offset into [rawData] for [entity], or `-1` if not present.
  int getOffset(Entity entity) => _sparseSet.getOffset(entity.id);

  /// Returns the dense index for [entity], or `-1` if not present.
  int getDenseIndex(Entity entity) => _sparseSet.getDenseIndex(entity.id);

  /// Returns the [Entity] at the specified [denseIndex].
  Entity getEntityAt(int denseIndex) => Entity(_sparseSet.getEntityAt(denseIndex));

  /// Clears all component data and entity associations without deallocating buffers.
  void clear() => _sparseSet.clear();

  /// Returns a zero-copy sub-view of the float data for [entity], or `null` if not found.
  Float32List? getSlice(Entity entity) => _sparseSet.getComponentSlice(entity.id);

  /// Executes [action] linearly over all densely packed components without GC allocations.
  void forEach(void Function(Entity entity, Float32List data, int offset) action) {
    final count = _sparseSet.count;
    final dense = _sparseSet.dense;
    final data = _sparseSet.data;
    for (int i = 0; i < count; i++) {
      action(Entity(dense[i]), data, i * stride);
    }
  }

  /// Executes [action] linearly over raw integer entity IDs and component data.
  void forEachRaw(void Function(int entityId, Float32List data, int offset) action) {
    _sparseSet.forEach(action);
  }
}
