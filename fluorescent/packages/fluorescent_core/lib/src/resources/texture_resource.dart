import 'resource.dart';

/// Represents a 2D GPU texture resource with format and dimension metadata.
class TextureResource extends Resource {
  /// Width of the texture in pixels.
  final int width;

  /// Height of the texture in pixels.
  final int height;

  /// Pixel format (e.g. 'rgba8unorm', 'bgra8unorm', 'rgba16float', etc.).
  final String format;

  /// Platform/native GPU texture identifier or mock handle.
  final int? gpuTextureId;

  /// Optional callback invoked when the texture is disposed to free GPU handles.
  final void Function(TextureResource resource)? onDispose;

  /// Creates a [TextureResource].
  ///
  /// If [byteSize] is not explicitly specified, it is calculated based on
  /// [width], [height], and [format].
  TextureResource({
    required super.id,
    required this.width,
    required this.height,
    this.format = 'rgba8unorm',
    this.gpuTextureId,
    this.onDispose,
    int? byteSize,
    super.initialRefCount,
  }) : super(
          byteSize: byteSize ?? _computeByteSize(width, height, format),
        );

  /// Computes the estimated GPU byte footprint for texture dimensions and format.
  static int _computeByteSize(int width, int height, String format) {
    final bytesPerPixel = switch (format.toLowerCase()) {
      'r8unorm' || 'r8snorm' || 'r8uint' || 'r8sint' => 1,
      'rg8unorm' || 'rg8snorm' || 'rg8uint' || 'rg8sint' => 2,
      'rgba8unorm' ||
      'rgba8unorm-srgb' ||
      'rgba8snorm' ||
      'rgba8uint' ||
      'rgba8sint' ||
      'bgra8unorm' ||
      'bgra8unorm-srgb' =>
        4,
      'rgba16float' || 'rgba16uint' || 'rgba16sint' => 8,
      'rgba32float' || 'rgba32uint' || 'rgba32sint' => 16,
      _ => 4, // Default to 4 bytes per pixel (32-bit RGBA)
    };
    return width * height * bytesPerPixel;
  }

  @override
  void dispose() {
    if (isDisposed) {
      throw StateError('TextureResource "$id" is already disposed.');
    }
    super.dispose();
    onDispose?.call(this);
  }

  @override
  String toString() =>
      'TextureResource(id: $id, ${width}x$height, format: $format, byteSize: $byteSize, refCount: $refCount, isDisposed: $isDisposed)';
}
