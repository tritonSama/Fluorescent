import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:fluorescent_flame/src/components/fluorescent_viewport.dart';
import 'package:fluorescent_core/fluorescent_core.dart';

// Copying the component logic but with the unoptimized render loop to demonstrate the baseline
class FluorescentViewportUnoptimized extends PositionComponent {
  final World3D world;
  final Camera3D camera;
  final RenderConfig config;

  final int? textureId;

  late final TextPainter _textPainter;

  FluorescentViewportUnoptimized({
    required this.world,
    required this.camera,
    this.textureId,
    RenderConfig? config,
    super.position,
    super.size,
  }) : config = config ?? RenderConfig();

  @override
  Future<void> onLoad() async {
    _textPainter = TextPainter(
      text: TextSpan(
        text: '3D Viewport Stub\nWorld: ${world.name}',
        style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    if (textureId == null) {
      // Unoptimized logic (instantiating Paint on every frame)
      final paint = Paint()..color = const Color(0xFF6200EE);
      canvas.drawRect(size.toRect(), paint);

      _textPainter.paint(
        canvas,
        Offset(size.x / 2 - _textPainter.width / 2, size.y / 2 - _textPainter.height / 2),
      );
    }
  }
}

class MockCanvas implements Canvas {
  int drawRectCount = 0;

  @override
  void drawRect(Rect rect, Paint paint) {
    drawRectCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

void main() {
  group('Render benchmark comparison', () {
    test('Unoptimized (Allocates Paint every frame)', () async {
      final world = World3D(name: 'Benchmark World');
      final camera = Camera3D();
      final viewport = FluorescentViewportUnoptimized(
        world: world,
        camera: camera,
        size: Vector2(800, 600),
      );

      await viewport.onLoad();

      final canvas = MockCanvas();

      // Warmup
      for (int i = 0; i < 10000; i++) {
        viewport.render(canvas);
      }

      // Benchmark
      final stopwatch = Stopwatch()..start();
      const iterations = 5000000;
      for (int i = 0; i < iterations; i++) {
        viewport.render(canvas);
      }
      stopwatch.stop();

      print('Total time for $iterations iterations (unoptimized): ${stopwatch.elapsedMilliseconds} ms');
      print('Average time per iteration: ${stopwatch.elapsedMicroseconds / iterations} us');
    });

    test('Optimized (Reuses Paint instance)', () async {
      final world = World3D(name: 'Benchmark World');
      final camera = Camera3D();
      final viewport = FluorescentViewport(
        world: world,
        camera: camera,
        size: Vector2(800, 600),
      );

      await viewport.onLoad();

      final canvas = MockCanvas();

      // Warmup
      for (int i = 0; i < 10000; i++) {
        viewport.render(canvas);
      }

      // Benchmark
      final stopwatch = Stopwatch()..start();
      const iterations = 5000000;
      for (int i = 0; i < iterations; i++) {
        viewport.render(canvas);
      }
      stopwatch.stop();

      print('Total time for $iterations iterations (optimized): ${stopwatch.elapsedMilliseconds} ms');
      print('Average time per iteration: ${stopwatch.elapsedMicroseconds / iterations} us');
    });
  });
}
