import 'dart:ffi' as ffi;
import 'dart:io';

// Typedefs for the FFI bridge
typedef InitVulkanC = ffi.Bool Function();
typedef InitVulkanDart = bool Function();

typedef RenderFrameC = ffi.Void Function();
typedef RenderFrameDart = void Function();

typedef CleanupVulkanC = ffi.Void Function();
typedef CleanupVulkanDart = void Function();

/// A wrapper class for the Vulkan native library.
class VulkanBindings {
  late final ffi.DynamicLibrary _lib;
  late final InitVulkanDart initVulkan;
  late final RenderFrameDart renderFrame;
  late final CleanupVulkanDart cleanupVulkan;

  VulkanBindings() {
    _loadLibrary();
    _bindMethods();
  }

  void _loadLibrary() {
    if (Platform.isAndroid || Platform.isLinux) {
      _lib = ffi.DynamicLibrary.open('libfluorescent_vulkan.so');
    } else if (Platform.isWindows) {
      _lib = ffi.DynamicLibrary.open('fluorescent_vulkan.dll');
    } else {
      throw UnsupportedError('Vulkan is not supported on this platform');
    }
  }

  void _bindMethods() {
    initVulkan = _lib.lookupFunction<InitVulkanC, InitVulkanDart>('init_vulkan');
    renderFrame = _lib.lookupFunction<RenderFrameC, RenderFrameDart>('render_frame');
    cleanupVulkan = _lib.lookupFunction<CleanupVulkanC, CleanupVulkanDart>('cleanup_vulkan');
  }
}
