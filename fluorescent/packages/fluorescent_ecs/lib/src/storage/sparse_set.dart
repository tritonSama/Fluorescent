import 'dart:typed_data';

/// A high-performance Sparse-Set data structure for contiguous TypedData component storage.
///
/// Maps sparse entity IDs to contiguous dense indices, maintaining a tightly-packed
/// [Float32List] buffer with zero holes for maximum cache locality and zero GC pressure.
class SparseSet {
  /// The number of 32-bit floats allocated per component entry.
  final int stride;

  /// Sparse array mapping `entityId -> denseIndex`. Unmapped slots contain `-1`.
  Int32List _sparse;

  /// Dense array mapping `denseIndex -> entityId`.
  Int32List _dense;

  /// Contiguous memory buffer holding component data (`capacity * stride` floats).
  Float32List _data;

  /// The number of active entities currently stored in the set.
  int _count = 0;

  /// The current capacity of the dense and data buffers.
  int _capacity;

  /// Creates a [SparseSet] with a fixed component [stride] and initial buffer capacities.
  SparseSet({
    required this.stride,
    int initialCapacity = 64,
    int initialSparseCapacity = 256,
  })  : assert(stride > 0, 'stride must be positive'),
        assert(initialCapacity > 0, 'initialCapacity must be positive'),
        assert(initialSparseCapacity > 0, 'initialSparseCapacity must be positive'),
        _capacity = initialCapacity,
        _sparse = Int32List(initialSparseCapacity)..fillRange(0, initialSparseCapacity, -1),
        _dense = Int32List(initialCapacity)..fillRange(0, initialCapacity, -1),
        _data = Float32List(initialCapacity * stride);

  /// Number of active components currently stored.
  int get count => _count;

  /// Current allocated capacity for entities in the dense buffer.
  int get capacity => _capacity;

  /// Current capacity of the sparse lookup table.
  int get sparseCapacity => _sparse.length;

  /// Whether the sparse set contains no elements.
  bool get isEmpty => _count == 0;

  /// Whether the sparse set contains at least one element.
  bool get isNotEmpty => _count > 0;

  /// The underlying contiguous float data buffer.
  Float32List get data => _data;

  /// The dense array containing packed entity IDs from index `0` to `count - 1`.
  Int32List get dense => _dense;

  /// The sparse array mapping `entityId` to dense index.
  Int32List get sparse => _sparse;

  /// Returns whether [entityId] has an entry in this sparse set.
  bool contains(int entityId) {
    if (entityId < 0 || entityId >= _sparse.length) return false;
    final denseIndex = _sparse[entityId];
    return denseIndex >= 0 && denseIndex < _count && _dense[denseIndex] == entityId;
  }

  /// Returns the dense index for [entityId], or `-1` if not found.
  int getDenseIndex(int entityId) {
    if (entityId < 0 || entityId >= _sparse.length) return -1;
    final denseIndex = _sparse[entityId];
    if (denseIndex >= 0 && denseIndex < _count && _dense[denseIndex] == entityId) {
      return denseIndex;
    }
    return -1;
  }

  /// Returns the float offset into [data] for [entityId], or `-1` if not present.
  int getOffset(int entityId) {
    final denseIndex = getDenseIndex(entityId);
    return denseIndex >= 0 ? denseIndex * stride : -1;
  }

  /// Returns the entity ID located at the specified [denseIndex].
  int getEntityAt(int denseIndex) {
    if (denseIndex < 0 || denseIndex >= _count) {
      throw RangeError.range(denseIndex, 0, _count - 1, 'denseIndex');
    }
    return _dense[denseIndex];
  }

  /// Adds [entityId] to the sparse set and returns the float offset into [data].
  ///
  /// If [entityId] is already present, its existing offset is returned without re-allocating.
  int add(int entityId) {
    if (entityId < 0) {
      throw ArgumentError.value(entityId, 'entityId', 'Entity ID must be non-negative');
    }

    final existingIndex = getDenseIndex(entityId);
    if (existingIndex >= 0) {
      return existingIndex * stride;
    }

    // Expand sparse array if entity ID exceeds current bounds
    if (entityId >= _sparse.length) {
      int newSparseCap = _sparse.length * 2;
      if (newSparseCap <= entityId) {
        newSparseCap = entityId + 1;
      }
      if (newSparseCap < 256) newSparseCap = 256;
      final newSparse = Int32List(newSparseCap);
      newSparse.setRange(0, _sparse.length, _sparse);
      newSparse.fillRange(_sparse.length, newSparseCap, -1);
      _sparse = newSparse;
    }

    // Expand dense and data buffers if capacity reached
    if (_count >= _capacity) {
      final newDenseCap = _capacity == 0 ? 16 : _capacity * 2;
      final newDense = Int32List(newDenseCap);
      newDense.setRange(0, _count, _dense);
      newDense.fillRange(_count, newDenseCap, -1);

      final newData = Float32List(newDenseCap * stride);
      newData.setRange(0, _count * stride, _data);

      _dense = newDense;
      _data = newData;
      _capacity = newDenseCap;
    }

    final denseIndex = _count;
    _dense[denseIndex] = entityId;
    _sparse[entityId] = denseIndex;
    _count++;

    final offset = denseIndex * stride;
    _data.fillRange(offset, offset + stride, 0.0);
    return offset;
  }

  /// Removes [entityId] using swap-and-pop to preserve dense contiguous packing.
  ///
  /// Returns `true` if the entity was present and removed, `false` otherwise.
  bool remove(int entityId) {
    if (entityId < 0 || entityId >= _sparse.length) return false;
    final denseIndex = _sparse[entityId];
    if (denseIndex < 0 || denseIndex >= _count || _dense[denseIndex] != entityId) {
      return false;
    }

    final lastDenseIndex = _count - 1;
    if (denseIndex != lastDenseIndex) {
      // Swap the last element into the removed slot
      final lastEntityId = _dense[lastDenseIndex];
      _dense[denseIndex] = lastEntityId;
      _sparse[lastEntityId] = denseIndex;

      // Copy component data contiguous slice
      final srcOffset = lastDenseIndex * stride;
      final dstOffset = denseIndex * stride;
      _data.setRange(dstOffset, dstOffset + stride, _data, srcOffset);
    }

    _sparse[entityId] = -1;
    _dense[lastDenseIndex] = -1;
    _count--;
    return true;
  }

  /// Clears all entries from the sparse set without deallocating backing buffers.
  void clear() {
    for (int i = 0; i < _count; i++) {
      _sparse[_dense[i]] = -1;
      _dense[i] = -1;
    }
    _count = 0;
  }

  /// Returns a zero-copy sub-view of the float data for [entityId], or `null` if not found.
  Float32List? getComponentSlice(int entityId) {
    final offset = getOffset(entityId);
    if (offset < 0) return null;
    return Float32List.sublistView(_data, offset, offset + stride);
  }

  /// Executes [action] linearly over all densely packed components without GC allocation.
  void forEach(void Function(int entityId, Float32List data, int offset) action) {
    for (int i = 0; i < _count; i++) {
      action(_dense[i], _data, i * stride);
    }
  }
}
