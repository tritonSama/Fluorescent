import 'package:flutter/material.dart';
import 'package:flame/game.dart';

import 'package:fluorescent_flame/fluorescent_flame.dart';

void main() {
  runApp(GameWidget(game: MyOpenWorldGame()));
}

class MyOpenWorldGame extends FlameGame {
  @override
  Future<void> onLoad() async {
    // Add 3D background viewport
    add(FluorescentViewport(
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
