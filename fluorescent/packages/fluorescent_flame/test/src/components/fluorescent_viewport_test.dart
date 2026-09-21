import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:fluorescent_core/fluorescent_core.dart';
import 'package:fluorescent_flame/src/components/fluorescent_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class TestGame extends FlameGame {}

class MockCanvas implements Canvas {
  @override
  void noSuchMethod(Invocation invocation) {}
}

void main() {
  group('FluorescentViewport', () {
    testWithGame<TestGame>(
      'renders placeholder when textureId is null',
      TestGame.new,
      (game) async {
        final world = World3D(name: 'Test World');
        final camera = Camera3D();

        final viewport = FluorescentViewport(
          world: world,
          camera: camera,
          size: Vector2(100, 100),
        );

        await game.ensureAdd(viewport);

        expect(
          (Canvas canvas) => viewport.render(canvas),
          paints
            ..rect(color: const Color(0xFF00FF00))
            ..something((Symbol methodName, List<dynamic> arguments) {
              return methodName == #drawParagraph;
            }),
        );
      },
    );

    testWithGame<TestGame>(
      'renders nothing when textureId is provided',
      TestGame.new,
      (game) async {
        final world = World3D(name: 'Test World');
        final camera = Camera3D();

        final viewport = FluorescentViewport(
          world: world,
          camera: camera,
          textureId: 1,
          size: Vector2(100, 100),
        );

        await game.ensureAdd(viewport);

        final canvas = MockCanvas();
        expect(
          () => viewport.render(canvas),
          returnsNormally,
        );
      },
    );
  });
}
