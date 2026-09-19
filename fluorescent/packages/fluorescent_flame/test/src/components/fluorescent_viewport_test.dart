import 'dart:ui';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluorescent_flame/src/components/fluorescent_viewport.dart';
import 'package:fluorescent_core/fluorescent_core.dart';

class _FluorescentGame extends FlameGame {}

class _MockCanvas implements Canvas {
  bool drawRectCalled = false;
  Color? drawnColor;
  Rect? drawnRect;

  @override
  void drawRect(Rect rect, Paint paint) {
    drawRectCalled = true;
    drawnRect = rect;
    drawnColor = paint.color;
  }

  @override
  void noSuchMethod(Invocation invocation) {}
}

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

    test('renders a purple rectangle when textureId is null (mock)', () {
      final world = World3D(name: 'TestWorld');
      final camera = Camera3D();
      final viewport = FluorescentViewport(
        world: world,
        camera: camera,
        position: Vector2.zero(),
        size: Vector2(100, 200),
      );

      final canvas = _MockCanvas();

      viewport.render(canvas);

      expect(canvas.drawRectCalled, isTrue);
      expect(canvas.drawnRect, equals(const Rect.fromLTWH(0, 0, 100, 200)));
      expect(canvas.drawnColor?.toARGB32(), equals(0xFF6200EE));
    });

    testWidgets('renders a purple rectangle when textureId is null (paints matcher)', (WidgetTester tester) async {
      final world = World3D(name: 'TestWorld');
      final camera = Camera3D();
      final viewport = FluorescentViewport(
        world: world,
        camera: camera,
        position: Vector2.zero(),
        size: Vector2(100, 200),
      );

      // The `paints` matcher uses cascade operators strictly.
      expect(
        (Canvas canvas) => viewport.render(canvas),
        paints..rect(color: const Color(0xFF6200EE), rect: const Rect.fromLTWH(0, 0, 100, 200)),
      );
    });

    test('does not render stub when textureId is provided', () {
      final world = World3D(name: 'TestWorld');
      final camera = Camera3D();
      final viewport = FluorescentViewport(
        world: world,
        camera: camera,
        textureId: 42,
        position: Vector2.zero(),
        size: Vector2(100, 200),
      );

      final canvas = _MockCanvas();
      
      viewport.render(canvas);

      expect(canvas.drawRectCalled, isFalse);
    });
  });
}
