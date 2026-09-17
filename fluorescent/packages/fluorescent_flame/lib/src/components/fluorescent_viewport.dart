import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/rendering.dart';

/// A stub component for rendering 3D viewports in Flame.
class FluorescentViewport extends PositionComponent {
  FluorescentViewport({
    super.position,
    super.size,
  });

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Draw a colored quad to stub the 3D viewport rendering
    final paint = Paint()..color = const Color(0xFF00FF00); // Green colored quad stub
    canvas.drawRect(size.toRect(), paint);
  }
}
