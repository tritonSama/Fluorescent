import 'package:meta/meta.dart';

/// Base class for GPU and engine resources managed with intrusive reference counting.
///
/// When a resource is created, its [refCount] begins at 1 (or [initialRefCount]).
/// Call [retain] to increment the reference count when sharing ownership.
/// Call [release] to decrement the reference count. When [refCount] reaches 0,
/// [dispose] is automatically invoked to free underlying GPU memory and handles.
abstract class Resource {
  /// Unique identifier or asset path for this resource.
  final String id;

  /// GPU memory footprint of this resource in bytes.
  final int byteSize;

  int _refCount;
  bool _isDisposed = false;

  /// Internal callback invoked when this resource is disposed, used by
  /// `ResourceManager` to automatically synchronize cache and memory accounting.
  @internal
  void Function(Resource resource)? onResourceDisposed;

  /// Creates a new [Resource] with the given [id], [byteSize], and optional [initialRefCount].
  Resource({
    required this.id,
    required this.byteSize,
    int initialRefCount = 1,
  })  : assert(byteSize >= 0, 'byteSize cannot be negative'),
        assert(initialRefCount >= 1, 'initialRefCount must be at least 1'),
        _refCount = initialRefCount;

  /// The current reference count of this resource.
  int get refCount => _refCount;

  /// Whether this resource has been disposed.
  bool get isDisposed => _isDisposed;

  /// Increments the reference count by 1.
  ///
  /// Throws [StateError] if the resource is already disposed.
  void retain() {
    if (_isDisposed) {
      throw StateError('Cannot retain disposed resource "$id".');
    }
    _refCount++;
  }

  /// Decrements the reference count by 1.
  ///
  /// If [refCount] drops to 0 or below, [dispose] is automatically called.
  /// Throws [StateError] if the resource is already disposed.
  void release() {
    if (_isDisposed) {
      throw StateError('Cannot release disposed resource "$id".');
    }
    _refCount--;
    if (_refCount <= 0) {
      dispose();
    }
  }

  /// Disposes this resource, marking it as disposed and releasing native/GPU resources.
  ///
  /// Throws [StateError] if called more than once.
  @mustCallSuper
  void dispose() {
    if (_isDisposed) {
      throw StateError('Resource "$id" is already disposed.');
    }
    _isDisposed = true;
    _refCount = 0;
    onResourceDisposed?.call(this);
  }

  @override
  String toString() =>
      '$runtimeType(id: $id, refCount: $_refCount, byteSize: $byteSize, isDisposed: $_isDisposed)';
}
