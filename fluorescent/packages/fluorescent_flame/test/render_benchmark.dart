import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:fluorescent_flame/src/components/fluorescent_viewport.dart';
import 'package:fluorescent_core/fluorescent_core.dart';

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
  test('Render benchmark', () {
    final world = World3D(name: 'Benchmark World');
    final camera = Camera3D();
    final viewport = FluorescentViewport(
      world: world,
      camera: camera,
      size: Vector2(800, 600),
    );

    final canvas = MockCanvas();

    // Warmup
    for (int i = 0; i < 1000; i++) {
      viewport.render(canvas);
    }

    // Benchmark
    final stopwatch = Stopwatch()..start();
    const iterations = 100000;
    for (int i = 0; i < iterations; i++) {
      viewport.render(canvas);
    }
    stopwatch.stop();

    print('Total time for $iterations iterations: ${stopwatch.elapsedMilliseconds} ms');
    print('Average time per iteration: ${stopwatch.elapsedMicroseconds / iterations} us');
  });
}
