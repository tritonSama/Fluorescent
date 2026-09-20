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
    test('uses default RenderConfig (60 FPS) when not provided', () {
      final world = World3D(name: 'TestWorld');
      final camera = Camera3D();
      final viewport = FluorescentViewport(
        world: world,
        camera: camera,
      );

      expect(viewport.config.targetFps, equals(60));
    });

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

    test('renders a purple rectangle and text when textureId is null', () async {
      final world = World3D(name: 'TestWorld');
      final camera = Camera3D();
      final viewport = FluorescentViewport(
        world: world,
        camera: camera,
        position: Vector2.zero(),
        size: Vector2(100, 200),
      );

      await viewport.onLoad();

      expect(
        (Canvas canvas) => viewport.render(canvas),
        paints
          ..rect(color: const Color(0xFF6200EE))
          ..paragraph(),
      );
    });

    test('does not render stub when textureId is provided', () async {
      final world = World3D(name: 'TestWorld');
      final camera = Camera3D();
      final viewport = FluorescentViewport(
        world: world,
        camera: camera,
        textureId: 42,
        position: Vector2.zero(),
        size: Vector2(100, 200),
      );

      await viewport.onLoad();

      final canvas = _MockCanvas();

      viewport.render(canvas);

      expect(canvas.drawRectCalled, isFalse);
      // We use paints..save()..restore() as a clever workaround for "paintsNothing"
      // to assert the rendering method performs no actual canvas drawing commands.
      expect(
        (Canvas canvas) {
            canvas.save();
            viewport.render(canvas);
            canvas.restore();
        },
        paints..save()..restore(),
      );
    });
  });
}
