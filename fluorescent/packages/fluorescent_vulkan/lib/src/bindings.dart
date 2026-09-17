import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

// Typedefs for the FFI bridge
typedef InitVulkanC = ffi.Bool Function();
typedef InitVulkanDart = bool Function();

typedef RenderFrameC = ffi.Void Function();
typedef RenderFrameDart = void Function();

typedef CleanupVulkanC = ffi.Void Function();
typedef CleanupVulkanDart = void Function();

typedef LoadGltfModelC = ffi.Bool Function(ffi.Pointer<Utf8> filepath);
typedef LoadGltfModelDart = bool Function(ffi.Pointer<Utf8> filepath);

typedef UpdateCameraC = ffi.Void Function(ffi.Pointer<ffi.Float> viewProjMatrix);
typedef UpdateCameraDart = void Function(ffi.Pointer<ffi.Float> viewProjMatrix);

/// A wrapper class for the Vulkan native library.
class VulkanBindings {
  late final ffi.DynamicLibrary _lib;
  late final InitVulkanDart initVulkan;
  late final RenderFrameDart renderFrame;
  late final CleanupVulkanDart cleanupVulkan;
  late final LoadGltfModelDart loadGltfModel;
  late final UpdateCameraDart updateCamera;

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
    loadGltfModel = _lib.lookupFunction<LoadGltfModelC, LoadGltfModelDart>('load_gltf_model');
    updateCamera = _lib.lookupFunction<UpdateCameraC, UpdateCameraDart>('update_camera');
  }

  /// Helper method to load a glTF model from a string path.
  bool loadModel(String filepath) {
    final pointer = filepath.toNativeUtf8();
    final result = loadGltfModel(pointer);
    calloc.free(pointer);
    return result;
  }
}
