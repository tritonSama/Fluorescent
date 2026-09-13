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

  FluorescentViewport({
    required this.world,
    required this.camera,
    RenderConfig? config,
    super.position,
    super.size,
  }) : config = config ?? RenderConfig();

  @override
  void render(Canvas canvas) {
    super.render(canvas);

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
