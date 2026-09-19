import 'package:flutter/widgets.dart';
import 'package:flame/components.dart';
import 'package:fluorescent_core/fluorescent_core.dart';

/// A rendering configuration for the 3D viewport.
class RenderConfig {
  final int targetFps;

  RenderConfig({this.targetFps = 60});
}

/// A component that acts as a bridge between the 3D world and Flame.
/// It wraps a Flutter [Texture] widget and composites it into the Flame component tree.
class FluorescentViewport extends PositionComponent {
  final World3D world;
  final Camera3D camera;
  final RenderConfig config;
  
  /// The ID of the native texture. If null, a fallback is rendered.
  final int? textureId;

  FluorescentViewport({
    required this.world,
    required this.camera,
    this.textureId,
    RenderConfig? config,
    super.position,
    super.size,
  }) : config = config ?? RenderConfig();

  // Cache heavily used objects to avoid GC overhead in the render loop.
  static final _stubPaint = Paint()
    ..color = const Color(0xFF6200EE) // A placeholder purple color
    ..style = PaintingStyle.fill;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    
    // In Flame, to render a Flutter Widget (like Texture) inline directly on the canvas,
    // we would typically use an overlay or a custom WidgetComponent. However, Flame
    // does not support drawing a Flutter `Texture` widget directly via Canvas API
    // (there is no `canvas.drawTexture()`). 
    //
    // For full zero-copy integration, the Texture needs to be in the Flutter Widget tree.
    // So this component itself manages its layout in Flame, but the actual Texture
    // is expected to be placed behind/in the Flame GameWidget using an overlay, OR
    // wrapped inside a Flame WidgetComponent.

    if (textureId == null) {
      // Stub: Draw a placeholder rectangle indicating the 3D viewport area
      canvas.drawRect(size.toRect(), _stubPaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: '3D Viewport Stub\nWorld: ${world.name}',
          style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(size.x / 2 - textPainter.width / 2, size.y / 2 - textPainter.height / 2),
      );
    }
  }
}
