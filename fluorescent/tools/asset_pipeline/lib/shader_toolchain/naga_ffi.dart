import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'demo_transpiler.dart';
import 'shader_transpiler.dart';

// Native FFI typedefs
typedef _NagaCompileSpirvC = Int32 Function(
  Pointer<Utf8> wgsl,
  Pointer<Utf8> stage,
  Pointer<Pointer<Uint32>> outWords,
  Pointer<Uint32> outWordCount,
);
typedef _NagaCompileSpirvDart = int Function(
  Pointer<Utf8> wgsl,
  Pointer<Utf8> stage,
  Pointer<Pointer<Uint32>> outWords,
  Pointer<Uint32> outWordCount,
);

typedef _NagaCompileMslC = Pointer<Utf8> Function(
  Pointer<Utf8> wgsl,
);
typedef _NagaCompileMslDart = Pointer<Utf8> Function(
  Pointer<Utf8> wgsl,
);

typedef _NagaFreeBufferC = Void Function(Pointer<Void> ptr);
typedef _NagaFreeBufferDart = void Function(Pointer<Void> ptr);

/// Naga / SPIRV-Cross FFI bindings for native shader compilation,
/// with graceful fallback to [DemoShaderTranspiler] when the native library
/// is not installed on the host system.
class NagaFfiTranspiler implements ShaderTranspiler {
  final ShaderTranspiler _fallbackTranspiler;
  final String? customLibraryPath;

  DynamicLibrary? _dylib;
  _NagaCompileSpirvDart? _compileSpirvFn;
  _NagaCompileMslDart? _compileMslFn;
  _NagaFreeBufferDart? _freeBufferFn;

  bool _initialized = false;
  bool _nativeAvailable = false;

  NagaFfiTranspiler({
    this.customLibraryPath,
    ShaderTranspiler? fallbackTranspiler,
  }) : _fallbackTranspiler = fallbackTranspiler ?? DemoShaderTranspiler();

  /// Whether the native dynamic library was successfully loaded.
  bool get isNativeAvailable {
    _ensureInitialized();
    return _nativeAvailable;
  }

  /// Whether compilation is currently falling back to the demo/pure-Dart transpiler.
  bool get usingFallback => !isNativeAvailable;

  void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    try {
      final libPath = customLibraryPath ?? _resolveLibraryName();
      if (libPath != null) {
        _dylib = DynamicLibrary.open(libPath);
        _compileSpirvFn = _dylib!.lookupFunction<_NagaCompileSpirvC, _NagaCompileSpirvDart>(
          'naga_compile_spirv',
        );
        _compileMslFn = _dylib!.lookupFunction<_NagaCompileMslC, _NagaCompileMslDart>(
          'naga_compile_msl',
        );
        _freeBufferFn = _dylib!.lookupFunction<_NagaFreeBufferC, _NagaFreeBufferDart>(
          'naga_free_buffer',
        );
        _nativeAvailable = true;
      }
    } catch (_) {
      // Graceful fallback when library is missing or symbol lookup fails
      _dylib = null;
      _compileSpirvFn = null;
      _compileMslFn = null;
      _freeBufferFn = null;
      _nativeAvailable = false;
    }
  }

  static String? _resolveLibraryName() {
    final envPath = Platform.environment['NAGA_LIB_PATH'];
    if (envPath != null && File(envPath).existsSync()) {
      return envPath;
    }

    if (Platform.isWindows) {
      return 'naga_ffi.dll';
    } else if (Platform.isMacOS || Platform.isIOS) {
      return 'libnaga_ffi.dylib';
    } else if (Platform.isLinux || Platform.isAndroid) {
      return 'libnaga_ffi.so';
    }
    return null;
  }

  @override
  ShaderBundle transpileWgsl({
    required String wgslSource,
    String shaderName = 'shader',
    String vertexEntryPoint = 'vertexMain',
    String fragmentEntryPoint = 'fragmentMain',
  }) {
    _ensureInitialized();

    if (_nativeAvailable && _compileSpirvFn != null && _compileMslFn != null) {
      try {
        final wgslPtr = wgslSource.toNativeUtf8();
        final stagePtr = 'all'.toNativeUtf8();

        final outWordsPtr = calloc<Pointer<Uint32>>();
        final outWordCountPtr = calloc<Uint32>();

        final int spirvRes = _compileSpirvFn!(wgslPtr, stagePtr, outWordsPtr, outWordCountPtr);
        if (spirvRes == 0 && outWordsPtr.value != nullptr) {
          final wordCount = outWordCountPtr.value;
          final words = Uint32List(wordCount);
          final rawWords = outWordsPtr.value;
          for (int i = 0; i < wordCount; i++) {
            words[i] = rawWords[i];
          }

          final mslPtr = _compileMslFn!(wgslPtr);
          final mslStr = mslPtr != nullptr ? mslPtr.toDartString() : '';

          if (_freeBufferFn != null) {
            _freeBufferFn!(outWordsPtr.value.cast<Void>());
            if (mslPtr != nullptr) _freeBufferFn!(mslPtr.cast<Void>());
          }

          calloc.free(wgslPtr);
          calloc.free(stagePtr);
          calloc.free(outWordsPtr);
          calloc.free(outWordCountPtr);

          return ShaderBundle(
            name: shaderName,
            wgsl: wgslSource,
            spirvWords: words,
            msl: mslStr,
            vertexEntryPoint: vertexEntryPoint,
            fragmentEntryPoint: fragmentEntryPoint,
          );
        }

        calloc.free(wgslPtr);
        calloc.free(stagePtr);
        calloc.free(outWordsPtr);
        calloc.free(outWordCountPtr);
      } catch (_) {
        // Fallback on unexpected native call failure
      }
    }

    // Seamless fallback to demo transpiler
    return _fallbackTranspiler.transpile(
      shaderName: shaderName,
      wgslSource: wgslSource,
      vertexEntryPoint: vertexEntryPoint,
      fragmentEntryPoint: fragmentEntryPoint,
    );
  }

  @override
  ShaderBundle transpile({
    required String shaderName,
    required String wgslSource,
    String vertexEntryPoint = 'vertexMain',
    String fragmentEntryPoint = 'fragmentMain',
  }) {
    return transpileWgsl(
      wgslSource: wgslSource,
      shaderName: shaderName,
      vertexEntryPoint: vertexEntryPoint,
      fragmentEntryPoint: fragmentEntryPoint,
    );
  }
}
