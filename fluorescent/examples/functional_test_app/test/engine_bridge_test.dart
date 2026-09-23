import 'package:flutter_test/flutter_test.dart';
import 'package:functional_test_app/engine_bridge.dart';

void main() {
  group('FluoriteEngineBridge', () {
    test('is a singleton', () {
      final bridge1 = FluoriteEngineBridge();
      final bridge2 = FluoriteEngineBridge();
      expect(identical(bridge1, bridge2), isTrue);
    });

    test('starts engine and returns textureId', () async {
      final bridge = FluoriteEngineBridge();
      // Ensure we start from a clean state for the test
      bridge.isInitialized = false;

      final result = await bridge.startEngine();
      expect(result, equals(1));
      expect(bridge.isInitialized, isTrue);
      // Wait for the asynchronous websocket error to occur so it doesn't leak into other tests
      await Future.delayed(const Duration(milliseconds: 100));
    });

    test('checkGeofenceIntersection returns false if not initialized', () {
      final bridge = FluoriteEngineBridge();
      bridge.isInitialized = false;
      final result = bridge.checkGeofenceIntersection(0, 0, 0, 0, 10);
      expect(result, isFalse);
    });

    test('checkGeofenceIntersection calculates distance correctly', () {
      final bridge = FluoriteEngineBridge();
      bridge.isInitialized = true;

      // Point inside radius
      expect(bridge.checkGeofenceIntersection(0, 0, 0.001, 0, 0.002), isTrue);

      // Point outside radius
      expect(bridge.checkGeofenceIntersection(0, 0, 0.005, 0, 0.002), isFalse);
    });
  });
}
