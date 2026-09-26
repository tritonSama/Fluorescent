import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/widgets.dart';

class VirtualControls extends PositionComponent with TapCallbacks, DragCallbacks {
  // Input states
  double leftStickX = 0;
  double leftStickY = 0;
  double rightStickX = 0;
  double rightStickY = 0;
  bool buttonA = false;
  bool buttonB = false;

  final void Function(List<int> payload)? onInputUpdate;

  VirtualControls({this.onInputUpdate, super.position, super.size}) {
    // Add child components for visual representation
  }

  void _sendUpdate() {
    if (onInputUpdate == null) return;

    // Simple 16-byte payload layout
    // [lx: float32, ly: float32, rx: float32, ry: float32, btnA: bool, btnB: bool, pad, pad]
    // In Dart, we can pack this manually or use ByteData

    final data = ByteData(18); // 4*4 + 2
    data.setFloat32(0, leftStickX, Endian.little);
    data.setFloat32(4, leftStickY, Endian.little);
    data.setFloat32(8, rightStickX, Endian.little);
    data.setFloat32(12, rightStickY, Endian.little);
    data.setInt8(16, buttonA ? 1 : 0);
    data.setInt8(17, buttonB ? 1 : 0);

    onInputUpdate!(data.buffer.asUint8List().toList());
  }

  // Example handlers for left stick and buttons
  @override
  void onDragUpdate(DragUpdateEvent event) {
    // Basic mapping logic
    // Usually this requires distinct components for each stick, simplified here
    _sendUpdate();
  }

  @override
  void onDragEnd(DragEndEvent event) {
    leftStickX = 0;
    leftStickY = 0;
    _sendUpdate();
  }
}
