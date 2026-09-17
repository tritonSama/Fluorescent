import '../servers/server.dart';

/// Inspired by Godot's RenderingServer, this acts as the low-level
/// API abstracting Vulkan/Metal/WebGPU calls from the high-level scene graph.
abstract class RenderingServer extends Server {
  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize();

  @override
  void step(double dt) {}

  @override
  Future<void> dispose() async {}

  /// Submits a draw command to the renderer.
  void submitDrawCall();

  /// Flushes the render queue to the target texture.
  void renderToTexture(int textureId);
}
