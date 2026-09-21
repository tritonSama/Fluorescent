import 'dart:ui';
import 'package:flame/components.dart';
import 'package:fluorescent_core/fluorescent_core.dart';
import 'package:fluorescent_flame/src/components/fluorescent_viewport.dart';
import 'package:flutter_test/flutter_test.dart';

class MockCanvas implements Canvas {
  @override
  void drawRect(Rect rect, Paint paint) {}

  @override
  void noSuchMethod(Invocation invocation) {}
}

void main() async {
  // Setup component
  final world = World3D(name: 'Test World');
  final camera = Camera3D();
  final viewport = FluorescentViewport(
    world: world,
    camera: camera,
    size: Vector2(800, 600),
  );

  await viewport.onLoad();

  final canvas = MockCanvas();

  // Warmup
  for (var i = 0; i < 10000; i++) {
    viewport.render(canvas);
  }

  // Benchmark
  final stopwatch = Stopwatch()..start();
  final iterations = 1000000;
  for (var i = 0; i < iterations; i++) {
    viewport.render(canvas);
  }
  stopwatch.stop();

  print('FluorescentViewport render benchmark:');
  print('Iterations: $iterations');
  print('Elapsed time: ${stopwatch.elapsedMilliseconds}ms');
  print(
      'Average time per render: ${(stopwatch.elapsedMicroseconds / iterations).toStringAsFixed(3)} μs');
}
