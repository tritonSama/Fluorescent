import 'dart:typed_data';
import 'resource.dart';

/// Represents a 3D geometry mesh resource on the GPU, containing vertex and index buffers.
class MeshResource extends Resource {
  /// Number of vertices in the mesh.
  final int vertexCount;

  /// Number of indices in the mesh. 0 if non-indexed.
  final int indexCount;

  /// Optional client-side or staging vertex data.
  final Float32List? vertexData;

  /// Optional client-side or staging index data.
  final TypedData? indexData;

  /// Platform/native GPU buffer identifier or mock handle.
  final int? gpuBufferId;

  /// Optional callback invoked when the mesh is disposed to free GPU buffers.
  final void Function(MeshResource resource)? onDispose;

  /// Creates a [MeshResource].
  ///
  /// If [byteSize] is not explicitly specified, it is calculated based on
  /// [vertexData]/[indexData] lengths or [vertexCount] (assuming 32 bytes/vertex)
  /// and [indexCount] (assuming 4 bytes/index).
  MeshResource({
    required super.id,
    required this.vertexCount,
    this.indexCount = 0,
    this.vertexData,
    this.indexData,
    this.gpuBufferId,
    this.onDispose,
    int? byteSize,
    super.initialRefCount,
  }) : super(
          byteSize: byteSize ??
              _computeByteSize(vertexCount, indexCount, vertexData, indexData),
        );

  static int _computeByteSize(
    int vertexCount,
    int indexCount,
    Float32List? vertexData,
    TypedData? indexData,
  ) {
    // 8 floats per vertex: position (3), normal (3), uv (2) = 32 bytes
    final vertexBytes =
        vertexData != null ? vertexData.lengthInBytes : (vertexCount * 8 * 4);
    // 32-bit indices = 4 bytes per index
    final indexBytes =
        indexData != null ? indexData.lengthInBytes : (indexCount * 4);
    return vertexBytes + indexBytes;
  }

  /// Whether this mesh uses index buffering.
  bool get isIndexed => indexCount > 0 || indexData != null;

  @override
  void dispose() {
    if (isDisposed) {
      throw StateError('MeshResource "$id" is already disposed.');
    }
    super.dispose();
    onDispose?.call(this);
  }

  @override
  String toString() =>
      'MeshResource(id: $id, vertices: $vertexCount, indices: $indexCount, byteSize: $byteSize, refCount: $refCount, isDisposed: $isDisposed)';
}
