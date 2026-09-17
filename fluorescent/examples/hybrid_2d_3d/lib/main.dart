import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/palette.dart';
import 'package:flutter/material.dart';
import 'package:fluorescent_core/fluorescent_core.dart';
import 'package:fluorescent_flame/fluorescent_flame.dart';

void main() {
  runApp(
    GameWidget(
      game: Hybrid2D3DGame(),
      // Add the texture overlay to Flame's overlay system
      // For this example, we assume textureId is 1 (mock)
      overlayBuilderMap: {
        'TextureOverlay': (BuildContext context, Hybrid2D3DGame game) {
          return const FluorescentTextureOverlay(
            textureId: 1,
            width: 300,
            height: 300,
          );
        },
      },
      initialActiveOverlays: const ['TextureOverlay'],
    ),
  );
}

class Hybrid2D3DGame extends FlameGame {
  @override
  Future<void> onLoad() async {
    // Add the 3D viewport behind the 2D elements
    final world3d = await World3D.load('assets/worlds/demo.fworld');
    final camera3d = ThirdPersonCamera(fov: 60, near: 0.1, far: 1000);
    
    // We pass textureId to prevent the viewport from drawing its placeholder fallback
    add(FluorescentViewport(
      world: world3d,
      camera: camera3d,
      textureId: 1, 
      position: Vector2(50, 50),
      size: Vector2(300, 300),
    ));

    // Add standard Flame 2D component on top
    final paint = BasicPalette.red.paint();
    add(
      RectangleComponent(
        position: Vector2(200, 200),
        size: Vector2(100, 100),
        paint: paint,
      ),
    );
    
    add(
      TextComponent(
        text: 'Standard Flame 2D Text',
        position: Vector2(210, 240),
      ),
    );
  }
}
