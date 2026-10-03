import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Raw dart:ffi bindings to the native NAM bridge (see
/// `native/nam_bridge/include/wyrmtone_nam.h`). Private: nothing outside
/// `nam_inference_engine.dart` is allowed to see these signatures.
///
/// Lives in `lib/` so the SAME bindings (typedefs, symbol names, error
/// codes, library-resolution shape) serve both the Windows desktop
/// validation tooling (`tool/nam_inference/`, which re-exports this file)
/// and the Android product app -- never two independent FFI
/// implementations of the one stable C ABI.

typedef CreateFnNative = Pointer<Void> Function();
typedef CreateFnDart = Pointer<Void> Function();

typedef LoadFnNative = Int32 Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Double,
  Int32,
);
typedef LoadFnDart = int Function(Pointer<Void>, Pointer<Utf8>, double, int);

typedef SampleRateFnNative = Double Function(Pointer<Void>);
typedef SampleRateFnDart = double Function(Pointer<Void>);

typedef ProcessFnNative = Int32 Function(
  Pointer<Void>,
  Pointer<Float>,
  Pointer<Float>,
  Int32,
);
typedef ProcessFnDart = int Function(
  Pointer<Void>,
  Pointer<Float>,
  Pointer<Float>,
  int,
);

typedef UnloadFnNative = Void Function(Pointer<Void>);
typedef UnloadFnDart = void Function(Pointer<Void>);

typedef DestroyFnNative = Void Function(Pointer<Void>);
typedef DestroyFnDart = void Function(Pointer<Void>);

typedef LastErrorFnNative = Pointer<Utf8> Function(Pointer<Void>);
typedef LastErrorFnDart = Pointer<Utf8> Function(Pointer<Void>);

/// Thrown when the native library itself cannot be found/opened -- distinct
/// from any [NamInferenceException] the loaded library's own functions can
/// raise, since here no handle exists yet to carry a native error message.
class NamLibraryUnavailableException implements Exception {
  const NamLibraryUnavailableException(this.message);
  final String message;
  @override
  String toString() => 'NamLibraryUnavailableException: $message';
}

class NativeNamBindings {
  /// Resolves and opens the native bridge library for the current
  /// platform, then looks up every symbol. Throws
  /// [NamLibraryUnavailableException] (never lets a raw dart:ffi
  /// [ArgumentError]/native exception escape) if the library cannot be
  /// opened or a required symbol is missing -- callers must be able to
  /// turn this into a controlled product error (LIBRARY_UNAVAILABLE),
  /// never an app crash.
  factory NativeNamBindings.load([String? explicitPath]) {
    final DynamicLibrary lib;
    try {
      lib = DynamicLibrary.open(explicitPath ?? _resolveLibraryPath());
    } catch (e) {
      throw NamLibraryUnavailableException('Could not open native NAM library: $e');
    }
    try {
      return NativeNamBindings._(lib);
    } catch (e) {
      throw NamLibraryUnavailableException('Native NAM library is missing an expected symbol: $e');
    }
  }

  NativeNamBindings._(this._lib)
    : create = _lib.lookupFunction<CreateFnNative, CreateFnDart>(
        'wyrmtone_nam_create',
      ),
      load = _lib.lookupFunction<LoadFnNative, LoadFnDart>('wyrmtone_nam_load'),
      expectedSampleRate = _lib
          .lookupFunction<SampleRateFnNative, SampleRateFnDart>(
            'wyrmtone_nam_expected_sample_rate',
          ),
      process = _lib.lookupFunction<ProcessFnNative, ProcessFnDart>(
        'wyrmtone_nam_process',
      ),
      unload = _lib.lookupFunction<UnloadFnNative, UnloadFnDart>(
        'wyrmtone_nam_unload',
      ),
      destroy = _lib.lookupFunction<DestroyFnNative, DestroyFnDart>(
        'wyrmtone_nam_destroy',
      ),
      lastError = _lib.lookupFunction<LastErrorFnNative, LastErrorFnDart>(
        'wyrmtone_nam_last_error',
      );

  // ignore: unused_field
  final DynamicLibrary _lib;
  final CreateFnDart create;
  final LoadFnDart load;
  final SampleRateFnDart expectedSampleRate;
  final ProcessFnDart process;
  final UnloadFnDart unload;
  final DestroyFnDart destroy;
  final LastErrorFnDart lastError;

  /// Android: the bridge is packaged as `lib/arm64-v8a/libwyrmtone_nam.so`
  /// inside the APK (via `android/app/build.gradle.kts`'s
  /// `externalNativeBuild`) -- the dynamic linker resolves it by soname
  /// alone, no path needed, exactly like every other bundled `.so`.
  ///
  /// Desktop (Windows): no product deployment target -- this path only
  /// serves `tool/nam_inference/`'s own offline validation scripts and
  /// `flutter test` runs on a developer machine, so it looks for the DLL
  /// relative to the repository root (where every such script/test is
  /// always invoked from) rather than any hardcoded absolute developer-PC
  /// path.
  static String _resolveLibraryPath() {
    if (Platform.isAndroid) return 'libwyrmtone_nam.so';
    const relative = 'native/nam_bridge/build/wyrmtone_nam.dll';
    if (File(relative).existsSync()) return relative;
    throw NamLibraryUnavailableException(
      '$relative not found; build native/nam_bridge first (see native/nam_bridge/build.bat).',
    );
  }
}

/// Converts [path] to a NUL-terminated UTF-8 native buffer that stays valid
/// until [free] is called with the same pointer (use `calloc.free`).
Pointer<Utf8> pathToNativeUtf8(String path) => path.toNativeUtf8();
