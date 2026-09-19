import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluorescent_flame/src/components/fluorescent_viewport.dart';
import 'package:fluorescent_core/fluorescent_core.dart';

class _FluorescentGame extends FlameGame {}

void main() {
  group('FluorescentViewport', () {
    testWithGame<_FluorescentGame>(
      'can be added to a game',
      _FluorescentGame.new,
      (game) async {
        final world = World3D(name: 'TestWorld');
        final camera = Camera3D();
        final viewport = FluorescentViewport(
          world: world,
          camera: camera,
          position: Vector2(10, 20),
          size: Vector2(100, 200),
        );

        await game.ensureAdd(viewport);

        expect(viewport.position, equals(Vector2(10, 20)));
        expect(viewport.size, equals(Vector2(100, 200)));
        expect(game.children.contains(viewport), isTrue);
      },
    );

    test('renders a purple rectangle as stub and text', () {
      final world = World3D(name: 'TestWorld');
      final camera = Camera3D();
      final viewport = FluorescentViewport(
        world: world,
        camera: camera,
        position: Vector2.zero(),
        size: Vector2(100, 200),
      );

      expect(
        (Canvas canvas) => viewport.render(canvas),
        paints
          ..rect(
            rect: const Rect.fromLTWH(0, 0, 100, 200),
            color: const Color(0xFF6200EE),
            style: PaintingStyle.fill,
          )
          ..paragraph(),
      );
    });

    test('does not render stub when textureId is provided', () {
      final world = World3D(name: 'TestWorld');
      final camera = Camera3D();
      final viewport = FluorescentViewport(
        world: world,
        camera: camera,
        position: Vector2.zero(),
        size: Vector2(100, 200),
        textureId: 1,
      );

      expect(
        (Canvas canvas) {
          viewport.render(canvas);
        },
        paintsNothing,
      );
    });
  });
}
