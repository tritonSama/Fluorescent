import 'resource.dart';
import 'texture_resource.dart';

/// Represents a rendering material resource, binding a shader program,
/// uniform parameters, and texture attachments.
///
/// Creating a [MaterialResource] automatically performs cascading [retain]
/// on all attached [TextureResource]s. When the material is disposed,
/// it performs cascading [release] on each attached texture.
class MaterialResource extends Resource {
  /// Identifier or path of the shader used by this material.
  final String shaderId;

  final Map<String, dynamic> _uniforms;
  final Map<String, TextureResource> _textures;

  /// Optional callback invoked when the material is disposed.
  final void Function(MaterialResource resource)? onDispose;

  /// Creates a [MaterialResource] and cascades [retain] on all provided [textures].
  MaterialResource({
    required super.id,
    required this.shaderId,
    Map<String, dynamic>? uniforms,
    Map<String, TextureResource>? textures,
    this.onDispose,
    int? byteSize,
    super.initialRefCount,
  })  : _uniforms = uniforms != null
            ? Map<String, dynamic>.from(uniforms)
            : <String, dynamic>{},
        _textures = textures != null
            ? Map<String, TextureResource>.from(textures)
            : <String, TextureResource>{},
        super(byteSize: byteSize ?? 256) {
    // Cascading retain on all attached textures
    for (final texture in _textures.values) {
      texture.retain();
    }
  }

  /// Immutable view of the material's uniform values.
  Map<String, dynamic> get uniforms => Map.unmodifiable(_uniforms);

  /// Immutable view of the material's texture attachments.
  Map<String, TextureResource> get textures => Map.unmodifiable(_textures);

  /// Retrieves a uniform value by [name].
  dynamic getUniform(String name) => _uniforms[name];

  /// Sets or updates a uniform parameter on this material.
  void setUniform(String name, dynamic value) {
    if (isDisposed) {
      throw StateError('Cannot set uniform on disposed MaterialResource "$id".');
    }
    _uniforms[name] = value;
  }

  /// Retrieves an attached texture by [slotName].
  TextureResource? getTexture(String slotName) => _textures[slotName];

  /// Sets or replaces a texture attachment, retaining the new texture and
  /// releasing the previous texture in that slot (if any).
  void setTexture(String slotName, TextureResource texture) {
    if (isDisposed) {
      throw StateError(
          'Cannot set texture on disposed MaterialResource "$id".');
    }
    final previous = _textures[slotName];
    if (identical(previous, texture)) return;

    texture.retain();
    _textures[slotName] = texture;
    previous?.release();
  }

  /// Removes a texture attachment from [slotName] and releases it.
  TextureResource? removeTexture(String slotName) {
    if (isDisposed) {
      throw StateError(
          'Cannot remove texture from disposed MaterialResource "$id".');
    }
    final removed = _textures.remove(slotName);
    removed?.release();
    return removed;
  }

  @override
  void dispose() {
    if (isDisposed) {
      throw StateError('MaterialResource "$id" is already disposed.');
    }
    // Cascading release on all attached textures
    for (final texture in _textures.values) {
      texture.release();
    }
    _textures.clear();
    _uniforms.clear();
    super.dispose();
    onDispose?.call(this);
  }

  @override
  String toString() =>
      'MaterialResource(id: $id, shader: $shaderId, textures: ${_textures.length}, byteSize: $byteSize, refCount: $refCount, isDisposed: $isDisposed)';
}
