import 'package:flutter/painting.dart';
import 'package:flame/components.dart';
import 'package:fluorescent_core/fluorescent_core.dart';

/// A rendering configuration for the 3D viewport.
class RenderConfig {
  final int targetFps;

  RenderConfig({this.targetFps = 60});
}

/// A component that acts as a bridge between the 3D world and Flame.
/// It renders the 3D scene to a texture and composites it into the Flame component tree.
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

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    if (textureId != null) {
      // In Flame, to render a Flutter Widget (like Texture), you'd typically
      // use a GameWidget overlay or a WidgetComponent. For raw canvas rendering
      // of a texture stream, flutter doesn't expose a direct `canvas.drawTexture`.
      //
      // For this initial integration stub within a component `render` method,
      // we'll draw a bounding box indicating where the texture overlay should be.
      //
      // The actual rendering of the `Texture` widget happens in the Flutter tree,
      // typically using Flame's `overlays` system.

      final paint = Paint()
        ..color = const Color(0xFF00FF00) // Green box to indicate active texture
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawRect(size.toRect(), paint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: '3D Texture ID: $textureId\n(Overlay managed by Flutter)',
          style: const TextStyle(
            color: Color(0xFF00FF00),
            fontSize: 14,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          size.x / 2 - textPainter.width / 2,
          size.y / 2 - textPainter.height / 2,
        ),
      );

    } else {
      // Stub: Draw a placeholder rectangle indicating the 3D viewport area
      final paint = Paint()
        ..color = const Color(0xFF6200EE) // A placeholder purple color
        ..style = PaintingStyle.fill;

      canvas.drawRect(size.toRect(), paint);

      // Draw text placeholder
      final textPainter = TextPainter(
        text: TextSpan(
          text: '3D Viewport Stub\nWorld: ${world.name}',
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 14,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          size.x / 2 - textPainter.width / 2,
          size.y / 2 - textPainter.height / 2,
        ),
      );
    }
  }
}
