import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:fluorescent_core/fluorescent_core.dart';
import 'package:fluorescent_flame/fluorescent_flame.dart';
import 'package:fluorescent_webgpu/fluorescent_webgpu.dart';

void main() {
  runApp(GameWidget(game: MyOpenWorldGame()));
}

class MyOpenWorldGame extends FlameGame {
  @override
  Color backgroundColor() => const Color(0x00000000);
  bool _webGpuInitialized = false;

  @override
  Future<void> onLoad() async {
    final world3d = World3D(name: 'OpenWorld');
    final camera3d = ThirdPersonCamera(fov: 60, near: 0.1, far: 1000);

    // Initialize WebGPU backend
    _webGpuInitialized = await FluorescentWebGPU.initCanvas(FluorescentWebGPU.canvasElementId);

    // Add 3D background viewport
    add(FluorescentViewport(
      world: world3d,
      camera: camera3d,
      textureId: 1, // Pass a textureId to clear the placeholder
      position: Vector2.zero(),
      size: size,
    ));
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // Resize viewport to match game size
    children.whereType<FluorescentViewport>().forEach((viewport) {
      viewport.size = size;
    });
  }
}
