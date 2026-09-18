import 'dart:async';
import 'package:vector_math/vector_math.dart';
import '../servers/server.dart';

enum InputDeviceType {
  keyboard,
  mouse,
  gamepad,
  touch,
}

abstract class InputServer extends Server {
  void registerAction(String actionName);
  void bindKey(String actionName, int keyCode);
  void bindGamepadButton(String actionName, int buttonId);

  bool isActionPressed(String actionName);
  bool isActionJustPressed(String actionName);
  bool isActionJustReleased(String actionName);

  Vector2 getMousePosition();
  Vector2 getMouseDelta();

  void processEvent(InputEvent event);
}

abstract class InputEvent {
  final InputDeviceType device;
  InputEvent(this.device);
}

class KeyEvent extends InputEvent {
  final int keyCode;
  final bool isDown;
  KeyEvent(this.keyCode, this.isDown) : super(InputDeviceType.keyboard);
}

class MouseMoveEvent extends InputEvent {
  final Vector2 position;
  final Vector2 delta;
  MouseMoveEvent(this.position, this.delta) : super(InputDeviceType.mouse);
}

class GamepadButtonEvent extends InputEvent {
  final int buttonId;
  final bool isDown;
  GamepadButtonEvent(this.buttonId, this.isDown) : super(InputDeviceType.gamepad);
}

class LocalInputServer extends InputServer {
  bool _isInitialized = false;

  final Map<String, Set<int>> _keyBindings = {};
  final Map<String, Set<int>> _gamepadBindings = {};

  final Set<String> _actionsPressed = {};
  final Set<String> _actionsJustPressed = {};
  final Set<String> _actionsJustReleased = {};

  final Vector2 _mousePos = Vector2.zero();
  final Vector2 _mouseDelta = Vector2.zero();

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize() async {
    _isInitialized = true;
  }

  @override
  void step(double dt) {
    _actionsJustPressed.clear();
    _actionsJustReleased.clear();
    _mouseDelta.setZero();
  }

  @override
  Future<void> dispose() async {
    _isInitialized = false;
    _keyBindings.clear();
    _gamepadBindings.clear();
    _actionsPressed.clear();
    _actionsJustPressed.clear();
    _actionsJustReleased.clear();
  }

  @override
  void registerAction(String actionName) {
    _keyBindings.putIfAbsent(actionName, () => {});
    _gamepadBindings.putIfAbsent(actionName, () => {});
  }

  @override
  void bindKey(String actionName, int keyCode) {
    if (_keyBindings.containsKey(actionName)) {
      _keyBindings[actionName]!.add(keyCode);
    }
  }

  @override
  void bindGamepadButton(String actionName, int buttonId) {
    if (_gamepadBindings.containsKey(actionName)) {
      _gamepadBindings[actionName]!.add(buttonId);
    }
  }

  @override
  bool isActionPressed(String actionName) => _actionsPressed.contains(actionName);

  @override
  bool isActionJustPressed(String actionName) => _actionsJustPressed.contains(actionName);

  @override
  bool isActionJustReleased(String actionName) => _actionsJustReleased.contains(actionName);

  @override
  Vector2 getMousePosition() => _mousePos.clone();

  @override
  Vector2 getMouseDelta() => _mouseDelta.clone();

  @override
  void processEvent(InputEvent event) {
    if (event is KeyEvent) {
      _handleActionTrigger(_keyBindings, event.keyCode, event.isDown);
    } else if (event is GamepadButtonEvent) {
      _handleActionTrigger(_gamepadBindings, event.buttonId, event.isDown);
    } else if (event is MouseMoveEvent) {
      _mousePos.setFrom(event.position);
      _mouseDelta.add(event.delta);
    }
  }

  void _handleActionTrigger(Map<String, Set<int>> bindings, int code, bool isDown) {
    for (final entry in bindings.entries) {
      if (entry.value.contains(code)) {
        if (isDown) {
          if (!_actionsPressed.contains(entry.key)) {
            _actionsJustPressed.add(entry.key);
          }
          _actionsPressed.add(entry.key);
        } else {
          if (_actionsPressed.contains(entry.key)) {
            _actionsJustReleased.add(entry.key);
          }
          _actionsPressed.remove(entry.key);
        }
      }
    }
  }
}
