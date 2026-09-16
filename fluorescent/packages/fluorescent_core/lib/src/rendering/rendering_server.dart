/// Inspired by Godot's RenderingServer, this acts as the low-level
/// API abstracting Vulkan/Metal/WebGPU calls from the high-level scene graph.
abstract class RenderingServer {
  /// Initializes the underlying graphics API.
  Future<void> initialize();

  /// Submits a draw command to the renderer.
  void submitDrawCall();

  /// Flushes the render queue to the target texture.
  void renderToTexture(int textureId);
}
