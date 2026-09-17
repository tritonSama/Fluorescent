bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Supported attachment resource types in the RenderGraph.
enum AttachmentType {
  color,
  depth,
  storage;

  static AttachmentType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'color':
        return AttachmentType.color;
      case 'depth':
      case 'depthstencil':
      case 'depth_stencil':
        return AttachmentType.depth;
      case 'storage':
        return AttachmentType.storage;
      default:
        throw ArgumentError('Unknown AttachmentType: $value');
    }
  }
}

/// Supported GPU texture formats.
enum TextureFormat {
  rgba8unorm,
  rgba16float,
  depth24plus,
  depth32float;

  static TextureFormat fromString(String value) {
    switch (value.toLowerCase()) {
      case 'rgba8unorm':
      case 'rgba8_unorm':
        return TextureFormat.rgba8unorm;
      case 'rgba16float':
      case 'rgba16_float':
        return TextureFormat.rgba16float;
      case 'depth24plus':
      case 'depth24_plus':
        return TextureFormat.depth24plus;
      case 'depth32float':
      case 'depth32_float':
        return TextureFormat.depth32float;
      default:
        throw ArgumentError('Unknown TextureFormat: $value');
    }
  }
}

/// Operation to perform when loading an attachment at pass start.
enum LoadOp {
  clear,
  load,
  dontCare;

  static LoadOp fromString(String value) {
    switch (value.toLowerCase()) {
      case 'clear':
        return LoadOp.clear;
      case 'load':
        return LoadOp.load;
      case 'dontcare':
      case 'dont_care':
        return LoadOp.dontCare;
      default:
        throw ArgumentError('Unknown LoadOp: $value');
    }
  }
}

/// Operation to perform when storing an attachment at pass end.
enum StoreOp {
  store,
  discard;

  static StoreOp fromString(String value) {
    switch (value.toLowerCase()) {
      case 'store':
        return StoreOp.store;
      case 'discard':
        return StoreOp.discard;
      default:
        throw ArgumentError('Unknown StoreOp: $value');
    }
  }
}

/// Type of render pass (rasterization vs compute).
enum PassType {
  raster,
  compute;

  static PassType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'raster':
        return PassType.raster;
      case 'compute':
        return PassType.compute;
      default:
        throw ArgumentError('Unknown PassType: $value');
    }
  }
}

/// Descriptor for a render target or texture attachment within the RenderGraph.
class AttachmentDescriptor {
  final String name;
  final AttachmentType type;
  final TextureFormat format;
  final List<int>? size;
  final List<double>? scale;
  final LoadOp loadOp;
  final StoreOp storeOp;
  final List<double> clearColor;
  final double clearDepth;

  const AttachmentDescriptor({
    required this.name,
    this.type = AttachmentType.color,
    this.format = TextureFormat.rgba8unorm,
    this.size,
    this.scale,
    this.loadOp = LoadOp.clear,
    this.storeOp = StoreOp.store,
    this.clearColor = const [0.0, 0.0, 0.0, 1.0],
    this.clearDepth = 1.0,
  });

  factory AttachmentDescriptor.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? '';
    final type = json['type'] != null
        ? AttachmentType.fromString(json['type'] as String)
        : AttachmentType.color;
    final format = json['format'] != null
        ? TextureFormat.fromString(json['format'] as String)
        : (type == AttachmentType.depth
            ? TextureFormat.depth24plus
            : TextureFormat.rgba8unorm);

    List<int>? size;
    if (json['size'] != null) {
      size = (json['size'] as List).map((e) => (e as num).toInt()).toList();
    }

    List<double>? scale;
    if (json['scale'] != null) {
      scale = (json['scale'] as List).map((e) => (e as num).toDouble()).toList();
    }

    final loadOp = json['loadOp'] != null
        ? LoadOp.fromString(json['loadOp'] as String)
        : LoadOp.clear;
    final storeOp = json['storeOp'] != null
        ? StoreOp.fromString(json['storeOp'] as String)
        : StoreOp.store;

    List<double> clearColor = const [0.0, 0.0, 0.0, 1.0];
    if (json['clearColor'] != null) {
      clearColor =
          (json['clearColor'] as List).map((e) => (e as num).toDouble()).toList();
    }

    final clearDepth = (json['clearDepth'] as num?)?.toDouble() ?? 1.0;

    return AttachmentDescriptor(
      name: name,
      type: type,
      format: format,
      size: size,
      scale: scale,
      loadOp: loadOp,
      storeOp: storeOp,
      clearColor: clearColor,
      clearDepth: clearDepth,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type.name,
      'format': format.name,
      if (size != null) 'size': size,
      if (scale != null) 'scale': scale,
      'loadOp': loadOp.name,
      'storeOp': storeOp.name,
      'clearColor': clearColor,
      'clearDepth': clearDepth,
    };
  }

  AttachmentDescriptor copyWith({
    String? name,
    AttachmentType? type,
    TextureFormat? format,
    List<int>? size,
    List<double>? scale,
    LoadOp? loadOp,
    StoreOp? storeOp,
    List<double>? clearColor,
    double? clearDepth,
  }) {
    return AttachmentDescriptor(
      name: name ?? this.name,
      type: type ?? this.type,
      format: format ?? this.format,
      size: size ?? this.size,
      scale: scale ?? this.scale,
      loadOp: loadOp ?? this.loadOp,
      storeOp: storeOp ?? this.storeOp,
      clearColor: clearColor ?? this.clearColor,
      clearDepth: clearDepth ?? this.clearDepth,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AttachmentDescriptor &&
        other.name == name &&
        other.type == type &&
        other.format == format &&
        _listEquals(other.size, size) &&
        _listEquals(other.scale, scale) &&
        other.loadOp == loadOp &&
        other.storeOp == storeOp &&
        _listEquals(other.clearColor, clearColor) &&
        other.clearDepth == clearDepth;
  }

  @override
  int get hashCode => Object.hash(
        name,
        type,
        format,
        Object.hashAll(size ?? []),
        Object.hashAll(scale ?? []),
        loadOp,
        storeOp,
        Object.hashAll(clearColor),
        clearDepth,
      );

  @override
  String toString() =>
      'AttachmentDescriptor(name: $name, type: ${type.name}, format: ${format.name})';
}

/// Descriptor for a single pass in the RenderGraph.
class RenderPassDescriptor {
  final String name;
  final PassType type;
  final List<String> colorAttachments;
  final String? depthStencilAttachment;
  final List<String> inputs;
  final List<String> dependencies;
  final String? shader;

  const RenderPassDescriptor({
    required this.name,
    this.type = PassType.raster,
    this.colorAttachments = const [],
    this.depthStencilAttachment,
    this.inputs = const [],
    this.dependencies = const [],
    this.shader,
  });

  factory RenderPassDescriptor.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? '';
    final type = json['type'] != null
        ? PassType.fromString(json['type'] as String)
        : PassType.raster;

    final colorAttachments = json['colorAttachments'] != null
        ? (json['colorAttachments'] as List).map((e) => e.toString()).toList()
        : const <String>[];

    final depthStencilAttachment = json['depthStencilAttachment'] as String?;

    final inputs = json['inputs'] != null
        ? (json['inputs'] as List).map((e) => e.toString()).toList()
        : const <String>[];

    final dependencies = json['dependencies'] != null
        ? (json['dependencies'] as List).map((e) => e.toString()).toList()
        : const <String>[];

    final shader = json['shader'] as String?;

    return RenderPassDescriptor(
      name: name,
      type: type,
      colorAttachments: colorAttachments,
      depthStencilAttachment: depthStencilAttachment,
      inputs: inputs,
      dependencies: dependencies,
      shader: shader,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type.name,
      'colorAttachments': colorAttachments,
      if (depthStencilAttachment != null)
        'depthStencilAttachment': depthStencilAttachment,
      'inputs': inputs,
      'dependencies': dependencies,
      if (shader != null) 'shader': shader,
    };
  }

  RenderPassDescriptor copyWith({
    String? name,
    PassType? type,
    List<String>? colorAttachments,
    String? depthStencilAttachment,
    List<String>? inputs,
    List<String>? dependencies,
    String? shader,
  }) {
    return RenderPassDescriptor(
      name: name ?? this.name,
      type: type ?? this.type,
      colorAttachments: colorAttachments ?? this.colorAttachments,
      depthStencilAttachment:
          depthStencilAttachment ?? this.depthStencilAttachment,
      inputs: inputs ?? this.inputs,
      dependencies: dependencies ?? this.dependencies,
      shader: shader ?? this.shader,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RenderPassDescriptor &&
        other.name == name &&
        other.type == type &&
        _listEquals(other.colorAttachments, colorAttachments) &&
        other.depthStencilAttachment == depthStencilAttachment &&
        _listEquals(other.inputs, inputs) &&
        _listEquals(other.dependencies, dependencies) &&
        other.shader == shader;
  }

  @override
  int get hashCode => Object.hash(
        name,
        type,
        Object.hashAll(colorAttachments),
        depthStencilAttachment,
        Object.hashAll(inputs),
        Object.hashAll(dependencies),
        shader,
      );

  @override
  String toString() =>
      'RenderPassDescriptor(name: $name, type: ${type.name}, colors: $colorAttachments, inputs: $inputs)';
}

/// Context provided to a [RenderPass] during execution.
class RenderContext {
  final Map<String, dynamic> state;
  final List<String> executedPasses;

  RenderContext({
    Map<String, dynamic>? state,
    List<String>? executedPasses,
  })  : state = state ?? <String, dynamic>{},
        executedPasses = executedPasses ?? <String>[];
}

/// An executable instance of a render pass.
class RenderPass {
  final RenderPassDescriptor descriptor;
  final void Function(RenderContext context)? onExecute;

  RenderPass({
    required this.descriptor,
    this.onExecute,
  });

  void execute(RenderContext context) {
    context.executedPasses.add(descriptor.name);
    onExecute?.call(context);
  }
}
