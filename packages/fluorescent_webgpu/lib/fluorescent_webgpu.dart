import 'dart:async';
import 'dart:js_interop';

@JS('window.fluorescentBridge.initCanvas')
external JSPromise _initCanvas(JSString canvasId);

/// Interface for interacting with the Fluorescent WebGPU JavaScript bridge.
class FluorescentWebGPU {
  static const String canvasElementId = 'fluorescent-webgpu-canvas';

  /// Initializes the WebGPU bridge on the given canvas ID.
  /// Resolves to true if WebGPU was successfully initialized.
  static Future<bool> initCanvas(String canvasId) async {
    try {
      final jsString = canvasId.toJS;
      final promise = _initCanvas(jsString);
      // Wait for the JS promise to resolve
      final result = await promise.toDart;

      if (result != null) {
        return (result as JSBoolean).toDart;
      }
      return false;
    } catch (e) {
      // Safely catch errors
      return false;
    }
  }
}
