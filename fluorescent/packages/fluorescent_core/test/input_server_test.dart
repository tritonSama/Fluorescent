import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:fluorescent_core/src/servers/servers.dart';

void main() {
  group('InputServer Tests', () {
    late InputServer inputServer;

    setUp(() async {
      inputServer = LocalInputServer();
      await inputServer.initialize();
    });

    tearDown(() async {
      await inputServer.dispose();
    });

    test('registers action and processes key events', () {
      inputServer.registerAction('jump');
      inputServer.bindKey('jump', 32); // Spacebar

      expect(inputServer.isActionPressed('jump'), isFalse);

      inputServer.processEvent(KeyEvent(32, true));
      expect(inputServer.isActionPressed('jump'), isTrue);
      expect(inputServer.isActionJustPressed('jump'), isTrue);

      inputServer.step(0.016); // clear just pressed/released
      expect(inputServer.isActionJustPressed('jump'), isFalse);
      expect(inputServer.isActionPressed('jump'), isTrue);

      inputServer.processEvent(KeyEvent(32, false));
      expect(inputServer.isActionPressed('jump'), isFalse);
      expect(inputServer.isActionJustReleased('jump'), isTrue);
    });

    test('processes mouse events', () {
      expect(inputServer.getMousePosition(), equals(Vector2.zero()));
      expect(inputServer.getMouseDelta(), equals(Vector2.zero()));

      inputServer.processEvent(MouseMoveEvent(Vector2(100, 100), Vector2(10, -5)));

      expect(inputServer.getMousePosition().x, equals(100));
      expect(inputServer.getMousePosition().y, equals(100));
      expect(inputServer.getMouseDelta().x, equals(10));
      expect(inputServer.getMouseDelta().y, equals(-5));

      inputServer.step(0.016); // clear delta
      expect(inputServer.getMouseDelta(), equals(Vector2.zero()));
    });
  });
}
