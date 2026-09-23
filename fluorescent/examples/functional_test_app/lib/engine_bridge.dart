import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

// Note: In a real implementation this would invoke the generated flutter_rust_bridge FFI calls.
// For now, we simulate the `fluorite_core` FFI Bridge and the connection to the nexus-core websocket.

class FluoriteEngineBridge {
  static final FluoriteEngineBridge _instance = FluoriteEngineBridge._internal();

  factory FluoriteEngineBridge() {
    return _instance;
  }

  FluoriteEngineBridge._internal();

  bool isInitialized = false;
  WebSocketChannel? _channel;

  Future<int?> startEngine({dynamic config}) async {
    // Stub for starting the Rust core
    await Future.delayed(const Duration(milliseconds: 100));
    isInitialized = true;
    debugPrint("Fluorite AAA Engine Core Initialized via FFI.");

    _connectToNexus();
    return 1; // Return stub textureId
  }

  void _connectToNexus() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:9001'));

      _channel?.ready.catchError((error) {
        // Swallow connection refused errors during tests
        debugPrint('Nexus Execution Rail (WS) ready error caught');
      });

      _channel?.stream.listen(
        (message) {
          debugPrint('Nexus Execution Rail (WS) received: $message');
        },
        onError: (error) {
          // Swallow connection refused errors during tests
          // debugPrint('Nexus Execution Rail (WS) error: $error');
        },
        onDone: () {
          debugPrint('Nexus Execution Rail (WS) closed');
        },
        cancelOnError: true,
      );
      debugPrint("Connected to Nexus Execution Rail (WS)");
    } catch (e) {
      debugPrint("Failed to connect to Nexus Execution Rail: $e");
    }
  }

  void sendTelemetry(String payload) {
    if (_channel != null) {
      final msg = jsonEncode({
        "type": "Telemetry",
        "payload": payload,
      });
      _channel?.sink.add(msg);
      debugPrint("Sent Telemetry to Nexus: $payload");
    }
  }

  void disconnect() {
    _channel?.sink.close(status.goingAway);
  }

  /// Evaluates spatial geofencing logic within the Rust Core
  /// (e.g. NavigationServer or PhysicsServer).
  bool checkGeofenceIntersection(double lat, double lng, double geofenceLat, double geofenceLng, double radius) {
    if (!isInitialized) return false;

    // Haversine formula stub (in reality Rust would calculate this)
    // Here we use a naive distance check for simulation.
    final double distSq = (lat - geofenceLat) * (lat - geofenceLat) + (lng - geofenceLng) * (lng - geofenceLng);

    // Very roughly: 0.001 degree is ~111 meters.
    final bool isInside = distSq <= (radius * radius);

    // Simulate sending telemetry to nexus-core when location is checked
    sendTelemetry("Checked Geofence: ${lat}, ${lng}");

    return isInside;
  }
}
