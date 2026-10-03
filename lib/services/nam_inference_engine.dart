import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'nam_native_bindings.dart';

export 'nam_native_bindings.dart' show NamLibraryUnavailableException;

/// Structured, product-facing error classification (section 14). Kept as
/// one extended enum (not a rename/replacement) so the pre-existing
/// Windows-tooling call sites (`test/tool/nam_inference_test.dart`,
/// `tool/nam_inference/stage_a_harness.dart`) keep working unchanged --
/// [libraryUnavailable], [invalidNam], [unsupportedArchitecture],
/// [nonFiniteOutput] and [cancelled] are the ones section 14 adds on top of
/// what the native bridge's own status enum already distinguished.
enum NamInferenceErrorKind {
  invalidArgument,
  fileNotFound,
  loadFailed,
  notLoaded,
  alreadyLoaded,
  processFailed,
  outOfMemory,
  unknown,
  libraryUnavailable,
  invalidNam,
  unsupportedArchitecture,
  nonFiniteOutput,
  cancelled,
}

/// Structured error from the native NAM engine. [kind] is the stable,
/// product-facing classification (section 14); [code] is the raw native
/// `wyrmtone_nam_status` (see `native/nam_bridge/include/wyrmtone_nam.h`)
/// kept only for diagnostics -- callers must branch on [kind], not on
/// [code], since the exact native enum is an internal bridge detail.
class NamInferenceException implements Exception {
  const NamInferenceException(this.kind, this.code, this.message);

  final NamInferenceErrorKind kind;
  final int code;
  final String message;

  @override
  String toString() => 'NamInferenceException($kind, code=$code): $message';

  /// The native bridge's own status enum does not (and structurally cannot,
  /// without deeper NAM-file-format knowledge than the C ABI exposes)
  /// distinguish "malformed/unsupported .nam" ([invalidNam] /
  /// [unsupportedArchitecture]) from any other load failure -- all three
  /// surface as the same `WYRMTONE_NAM_ERR_LOAD_FAILED`. Rather than
  /// fabricate a distinction the native layer cannot actually make,
  /// [loadFailed] is the honest catch-all for that status; a caller that
  /// needs finer classification must inspect [message]. This is a known,
  /// documented V1 limitation (see the final report), not an oversight.
  static NamInferenceErrorKind _kindOf(int code) => switch (code) {
    1 => NamInferenceErrorKind.invalidArgument,
    2 => NamInferenceErrorKind.fileNotFound,
    3 => NamInferenceErrorKind.loadFailed,
    4 => NamInferenceErrorKind.notLoaded,
    5 => NamInferenceErrorKind.alreadyLoaded,
    6 => NamInferenceErrorKind.processFailed,
    7 => NamInferenceErrorKind.outOfMemory,
    _ => NamInferenceErrorKind.unknown,
  };
}

/// Product-facing NAM inference engine. Callers never see that
/// NeuralAmpModelerCore is used underneath, or any FFI detail -- only
/// [load], [process], [dispose] and [NamInferenceException].
///
/// Lifecycle: one engine owns at most one loaded model. Not safe to share
/// across isolates (the underlying native pointer cannot cross an isolate
/// boundary) and not safe to call concurrently from multiple threads on the
/// SAME instance; create one engine per isolate/worker if you need
/// concurrency -- that is a normal, cheap operation. [dispose] is idempotent
/// (a second call is a no-op); every other method throws [StateError] once
/// [dispose] has run, to catch use-after-free bugs early instead of
/// touching a dangling native pointer.
///
/// Cancellation (section 13): the native C ABI's `wyrmtone_nam_process` is a
/// single synchronous, blocking call with no mid-call abort hook -- there is
/// no safe way to interrupt it partway without risking native-side
/// corruption, so this V1 does not attempt one (no artificial thread-kill).
/// [requestCancel] only prevents a *future* [process] call from starting
/// once a cancellation has been requested; a call already in flight always
/// finishes and its result is discarded by the caller if cancellation was
/// requested meanwhile -- see [NamPreparationService] for how a caller
/// should honor this.
class NamInferenceEngine {
  NamInferenceEngine._(this._bindings, this._handle);

  /// Creates an engine backed by the platform-appropriate native bridge
  /// library (Android: `libwyrmtone_nam.so` bundled in the APK; Windows
  /// dev/test only: `wyrmtone_nam.dll`). Throws
  /// [NamLibraryUnavailableException] if the library cannot be opened and
  /// [StateError] if native allocation fails.
  factory NamInferenceEngine.create([String? libraryPathOverride]) {
    final bindings = NativeNamBindings.load(libraryPathOverride);
    final handle = bindings.create();
    if (handle == nullptr) {
      throw StateError(
        'native wyrmtone_nam_create() returned null (out of memory?)',
      );
    }
    return NamInferenceEngine._(bindings, handle);
  }

  final NativeNamBindings _bindings;
  final Pointer<Void> _handle;
  bool _disposed = false;
  bool _loaded = false;
  bool _cancelRequested = false;

  void _checkAlive() {
    if (_disposed) throw StateError('NamInferenceEngine used after dispose()');
  }

  /// Marks this engine as cancelled: the next [load]/[process] call throws
  /// [NamInferenceException] with kind [NamInferenceErrorKind.cancelled]
  /// instead of doing any native work. Idempotent; safe to call at any time,
  /// including after [dispose].
  void requestCancel() => _cancelRequested = true;

  bool get isCancelled => _cancelRequested;

  void _checkNotCancelled() {
    if (_cancelRequested) {
      throw const NamInferenceException(
        NamInferenceErrorKind.cancelled,
        -1,
        'Cancelled before this native call started.',
      );
    }
  }

  /// Loads [namPath] and resets the model for [sampleRate] Hz with
  /// [maxBlockSize] frames per internal processing block. Throws
  /// [NamInferenceException] on any failure (invalid path, corrupt/
  /// unsupported .nam, a model already loaded on this engine, …); the
  /// engine is left unloaded and reusable after such a failure -- no
  /// partial native resource is retained (see `wyrmtone_nam.cpp`: the
  /// engine's `model` unique_ptr is only assigned after a fully successful
  /// load).
  void load(
    String namPath, {
    double sampleRate = 48000.0,
    int maxBlockSize = 4096,
  }) {
    _checkAlive();
    _checkNotCancelled();
    final pathPtr = pathToNativeUtf8(namPath);
    try {
      final status = _bindings.load(_handle, pathPtr, sampleRate, maxBlockSize);
      if (status != 0) {
        throw NamInferenceException(
          NamInferenceException._kindOf(status),
          status,
          _lastError(),
        );
      }
      _loaded = true;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// The loaded model's own training/expected sample rate in Hz, or 0.0 if
  /// nothing is loaded.
  double get expectedSampleRate {
    _checkAlive();
    return _bindings.expectedSampleRate(_handle);
  }

  bool get isLoaded {
    _checkAlive();
    return _loaded;
  }

  /// Runs mono inference over [input] and returns a new buffer of the same
  /// length. Throws [NamInferenceException] with kind
  /// [NamInferenceErrorKind.notLoaded] if no model is loaded, or kind
  /// [NamInferenceErrorKind.nonFiniteOutput] if any output sample is
  /// NaN/Infinity (the native bridge itself does not guard this -- see
  /// section 14 -- so this engine checks every sample before returning).
  /// Deterministic for a freshly loaded model given the same input.
  Float32List process(Float32List input) {
    _checkAlive();
    _checkNotCancelled();
    final n = input.length;
    final inPtr = calloc<Float>(n);
    final outPtr = calloc<Float>(n);
    try {
      inPtr.asTypedList(n).setAll(0, input);
      final status = _bindings.process(_handle, inPtr, outPtr, n);
      if (status != 0) {
        throw NamInferenceException(
          NamInferenceException._kindOf(status),
          status,
          _lastError(),
        );
      }
      final result = Float32List.fromList(outPtr.asTypedList(n));
      for (final sample in result) {
        if (!sample.isFinite) {
          throw NamInferenceException(
            NamInferenceErrorKind.nonFiniteOutput,
            0,
            'Native inference produced a non-finite sample (NaN or Infinity).',
          );
        }
      }
      return result;
    } finally {
      calloc.free(inPtr);
      calloc.free(outPtr);
    }
  }

  /// Releases the loaded model so the engine can [load] a different one.
  /// Safe to call when nothing is loaded.
  void unload() {
    _checkAlive();
    _bindings.unload(_handle);
    _loaded = false;
  }

  /// Frees the native handle. Idempotent -- a second call is a no-op, never
  /// throws. Safe (and required) to call after any failed [load]/[process]:
  /// the native side always leaves the handle itself valid and destroyable
  /// even when an operation on it failed.
  void dispose() {
    if (_disposed) return;
    _bindings.destroy(_handle);
    _disposed = true;
    _loaded = false;
  }

  String _lastError() {
    final ptr = _bindings.lastError(_handle);
    return ptr == nullptr ? '' : ptr.toDartString();
  }
}
