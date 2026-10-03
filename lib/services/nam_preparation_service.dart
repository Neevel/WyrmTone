import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'matribox_nam_clodata/nam_clodata_converter.dart';
import 'matribox_nam_payload.dart';
import 'nam_inference_engine.dart';
import 'wyrmtone_reference_signal_v4.dart';

/// Android NAM Inference V1, section 11 (and the later gap-closing
/// milestone's sections 2/8): the product-facing entry point for "local
/// validated NAM file -> [MatriboxNamPayload]". UI code depends only on
/// this file, [MatriboxNamPayload], [NamInferenceException] and
/// [NamInferenceErrorKind] -- never on `dart:ffi`, a native pointer, a raw
/// inference buffer, or an estimator-stage internal. TONE3000-specific
/// logic (download, library storage, metadata) intentionally does not live
/// here; this service only ever sees a local file path plus a display
/// name. No MIDI/Matribox import anywhere in this file -- preparation never
/// touches hardware (see `test/nam_preparation_service_test.dart`'s static
/// check).
enum NamPreparationStage {
  loadingModel,
  generatingReference,
  runningInference,
  generatingMatriboxModel,
  ready,
}

enum NamPreparationOutcome { success, failed, cancelled }

/// The result of one [NamPreparationService.prepare] call. Exactly one of
/// [payload] (on [NamPreparationOutcome.success]) or [error] (on
/// [NamPreparationOutcome.failed]) is non-null; neither is set on
/// [NamPreparationOutcome.cancelled].
class NamPreparationResult {
  const NamPreparationResult._({required this.outcome, this.payload, this.error, required this.duration});

  /// Test-only construction helpers (e.g. widget tests driving
  /// [NamPreparationRunner] without real FFI) -- production code only ever
  /// gets instances back from [NamPreparationService.prepare] itself.
  const NamPreparationResult.successForTest(
    MatriboxNamPayload this.payload, {
    this.duration = const Duration(seconds: 70),
  }) : outcome = NamPreparationOutcome.success,
       error = null;
  const NamPreparationResult.failedForTest(NamInferenceException this.error)
    : outcome = NamPreparationOutcome.failed,
      payload = null,
      duration = Duration.zero;
  const NamPreparationResult.cancelledForTest()
    : outcome = NamPreparationOutcome.cancelled,
      payload = null,
      error = null,
      duration = Duration.zero;

  final NamPreparationOutcome outcome;
  final MatriboxNamPayload? payload;
  final NamInferenceException? error;
  final Duration duration;

  bool get isSuccess => outcome == NamPreparationOutcome.success;
}

class NamPreparationService {
  final Set<Object> _cancelledTokens = {};

  /// A cancellation token for one [runReferenceSignalInference] call. Pass
  /// the same token to [cancel]; each token is single-use (removed once
  /// observed).
  Object createCancelToken() => Object();

  /// Requests cancellation of whichever [runReferenceSignalInference] call
  /// [token] was passed to. See section 13 / the class docs on
  /// [runReferenceSignalInference] for exactly what this does and does not
  /// interrupt.
  void cancel(Object token) => _cancelledTokens.add(token);

  /// Loads [namPath], runs the full deterministic WyrmTone Reference Signal
  /// V4 through it, and returns the raw inference output (same length as
  /// the reference signal, [WyrmToneReferenceSignalV4.totalFrames]).
  ///
  /// Section 12 (async/UI thread): the entire native load+process+dispose
  /// sequence runs inside [Isolate.run] -- a fresh isolate for this one
  /// call, matching [NamInferenceEngine]'s own documented constraint that
  /// its native handle cannot cross an isolate boundary (the whole
  /// lifecycle stays inside the spawned isolate; only the resulting
  /// [Float32List] crosses back). This is the Dart-standard way to keep the
  /// Flutter UI isolate responsive during a long native call, not a custom
  /// threading abstraction.
  ///
  /// Section 13 (cancellation): NeuralAmpModelerCore's C ABI
  /// (`wyrmtone_nam_process`) is one synchronous, blocking call with no
  /// mid-call abort hook, so a call already running always finishes
  /// in full -- there is no safe way to kill it partway without risking
  /// native-side corruption, and this V1 does not attempt one. If [cancel]
  /// was called with [cancelToken] before the isolate call completes, its
  /// result is discarded and this throws [NamInferenceException] with kind
  /// [NamInferenceErrorKind.cancelled] instead of returning it.
  Future<Float32List> runReferenceSignalInference(
    String namPath, {
    Object? cancelToken,
  }) async {
    final result = await Isolate.run(() {
      final engine = NamInferenceEngine.create();
      try {
        engine.load(namPath, sampleRate: WyrmToneReferenceSignalV4.sampleRate.toDouble());
        return engine.process(WyrmToneReferenceSignalV4.generate());
      } finally {
        // Runs even if load()/process() threw -- no native resource is ever
        // leaked out of this isolate, and the isolate itself is torn down
        // by Isolate.run once this callback returns/throws.
        engine.dispose();
      }
    });
    if (cancelToken != null && _cancelledTokens.remove(cancelToken)) {
      throw const NamInferenceException(
        NamInferenceErrorKind.cancelled,
        -1,
        'Cancelled while running; result discarded.',
      );
    }
    return result;
  }

  /// The full product preparation pipeline: local .nam -> Reference Signal
  /// V4 -> on-device NeuralAmpModelerCore inference -> the frozen V4
  /// CloData estimator -> [MatriboxNamPayload]. Never opens MIDI, never
  /// touches a Matribox device.
  ///
  /// [onProgress], if given, is called with [NamPreparationStage.loadingModel]
  /// immediately before the native/estimator work starts and with
  /// [NamPreparationStage.ready] immediately after it successfully
  /// completes -- both on the calling (UI) isolate. The stages in between
  /// ([NamPreparationStage.generatingReference],
  /// [NamPreparationStage.runningInference],
  /// [NamPreparationStage.generatingMatriboxModel]) run inside ONE
  /// [Isolate.run] call and are NOT individually reported: NAM inference is
  /// one atomic, synchronous native call with no mid-call progress hook
  /// (same constraint as [runReferenceSignalInference]), and the CloData
  /// estimator is a second, shorter atomic Dart computation. Faking
  /// percentage progress for either would be dishonest; a future UI should
  /// show one indeterminate spinner for the whole
  /// loadingModel-through-generatingMatriboxModel stretch. The enum values
  /// exist now so that a later milestone can upgrade to
  /// `Isolate.spawn`/`SendPort`-based live progress without changing this
  /// method's public shape.
  ///
  /// Cancellation: identical contract to [runReferenceSignalInference] --
  /// [cancelToken] is only checked before starting and after the isolate
  /// call returns; a run already in flight always finishes in full and its
  /// result (and any [MatriboxNamPayload] it would have produced) is
  /// discarded, never partially returned.
  Future<NamPreparationResult> prepare(
    String namPath, {
    required String namName,
    required String namSha256,
    Object? cancelToken,
    void Function(NamPreparationStage stage)? onProgress,
  }) async {
    final overall = Stopwatch()..start();
    if (cancelToken != null && _cancelledTokens.remove(cancelToken)) {
      overall.stop();
      return NamPreparationResult._(outcome: NamPreparationOutcome.cancelled, duration: overall.elapsed);
    }
    onProgress?.call(NamPreparationStage.loadingModel);
    try {
      final cloData = await Isolate.run(() => _prepareOnBackgroundIsolate(namPath, namName));
      if (cancelToken != null && _cancelledTokens.remove(cancelToken)) {
        overall.stop();
        return NamPreparationResult._(outcome: NamPreparationOutcome.cancelled, duration: overall.elapsed);
      }
      MatriboxNamPayload.validate(cloData); // throws FormatException, never returns a half-checked payload
      overall.stop();
      final payload = MatriboxNamPayload(
        cloData: cloData,
        namName: namName,
        namSha256: namSha256,
        cloDataSha256: sha256.convert(cloData).toString(),
        preparationDuration: overall.elapsed,
      );
      onProgress?.call(NamPreparationStage.ready);
      return NamPreparationResult._(
        outcome: NamPreparationOutcome.success,
        payload: payload,
        duration: overall.elapsed,
      );
    } on NamInferenceException catch (e) {
      overall.stop();
      return NamPreparationResult._(outcome: NamPreparationOutcome.failed, error: e, duration: overall.elapsed);
    } on NamLibraryUnavailableException catch (e) {
      overall.stop();
      return NamPreparationResult._(
        outcome: NamPreparationOutcome.failed,
        error: NamInferenceException(NamInferenceErrorKind.libraryUnavailable, -1, e.message),
        duration: overall.elapsed,
      );
    } on FormatException catch (e) {
      // The estimator (or MatriboxNamPayload.validate) rejected the input --
      // never a native/FFI failure, but still surfaced through the same
      // single exception type so callers only ever catch one thing.
      overall.stop();
      return NamPreparationResult._(
        outcome: NamPreparationOutcome.failed,
        error: NamInferenceException(NamInferenceErrorKind.unknown, -1, e.message),
        duration: overall.elapsed,
      );
    }
  }

  /// Runs entirely inside the background isolate [prepare] spawns: load,
  /// Reference Signal V4 generation, inference, and CloData estimation are
  /// all pure computation over bytes already in memory or read from
  /// [namPath] -- nothing here reaches a device or a UI widget.
  ///
  /// [namName] becomes the CloData's 16-byte name field via
  /// [MatriboxNamCloDataConverter.nameBytes] -- the SAME, already
  /// hardware-correlated truncation/zero-pad rule the official Sonicake
  /// editor's own output matches byte-for-byte in the golden-corpus tests
  /// (`test/tool/matribox_nam_analysis_test.dart`). This used to be the
  /// hardcoded literal `'nam'`, which is why a real product transfer showed
  /// the Matribox's AMP block labelled just "nam" instead of the actual
  /// NAM's name -- see the product NAM name fix milestone for the full
  /// analysis. Nothing about the CloData layout, the frozen V4 estimator,
  /// or the 8232-byte format changes; only this already-existing 16-byte
  /// region's input changes.
  static Uint8List _prepareOnBackgroundIsolate(String namPath, String namName) {
    final engine = NamInferenceEngine.create();
    final Float32List output;
    try {
      engine.load(namPath, sampleRate: WyrmToneReferenceSignalV4.sampleRate.toDouble());
      final reference = WyrmToneReferenceSignalV4.generate();
      output = engine.process(reference);
    } finally {
      engine.dispose();
    }
    final referenceWav = _wavFloat32Mono(WyrmToneReferenceSignalV4.generate(), WyrmToneReferenceSignalV4.sampleRate);
    final outputWav = _wavFloat32Mono(output, WyrmToneReferenceSignalV4.sampleRate);
    const converter = MatriboxNamCloDataConverter();
    final conversion = converter.convert(referenceWav: referenceWav, modelOutputWav: outputWav, fileName: namName);
    return conversion.requireComplete();
  }
}

/// Minimal RIFF/WAVE (IEEE float32, mono) encoder -- the frozen
/// [MatriboxNamCloDataConverter] only accepts WAV bytes, never a raw
/// [Float32List], so this wraps one without pulling in any WAV-writing
/// dependency. Byte-for-byte inverse of `MatriboxNamWav.parse`'s float32
/// branch (`matribox_nam_clodata/nam_clodata_converter.dart`).
Uint8List _wavFloat32Mono(Float32List samples, int sampleRate) {
  final dataBytes = samples.buffer.asUint8List(samples.offsetInBytes, samples.lengthInBytes);
  final header = BytesBuilder();
  void u32(int v) => header.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) => header.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());

  header.add(ascii.encode('RIFF'));
  u32(36 + dataBytes.length);
  header.add(ascii.encode('WAVE'));
  header.add(ascii.encode('fmt '));
  u32(16);
  u16(3); // IEEE float
  u16(1); // mono
  u32(sampleRate);
  u32(sampleRate * 4); // byte rate (4 bytes/frame: 1 channel * 32-bit float)
  u16(4); // block align
  u16(32); // bits per sample
  header.add(ascii.encode('data'));
  u32(dataBytes.length);
  return Uint8List.fromList([...header.toBytes(), ...dataBytes]);
}
