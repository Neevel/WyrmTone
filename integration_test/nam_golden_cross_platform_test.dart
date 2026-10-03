import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wyrmtone/services/nam_inference_engine.dart';
import 'package:wyrmtone/services/wyrmtone_reference_signal_v4.dart';

/// Android NAM Inference V1, sections 5-8: for each of the five golden
/// models, runs the full deterministic WyrmTone Reference Signal V4 through
/// the on-device NeuralAmpModelerCore build and prints length/finite/min/
/// max/SHA-256/timing -- the same stats a Windows-side script
/// (`tool/nam_inference/_scratch_windows_reference.dart`) already computed
/// via the desktop DLL, for a manual cross-platform diff (the two runs
/// cannot share one Dart process, so this is deliberately a print-and-
/// compare-externally design, not a fully automated single-process diff).
///
/// The .nam files are pushed ahead of time to /data/local/tmp (adb push,
/// world-readable) -- never bundled as a repo asset, and never a Sonicake
/// asset (these are the same five local golden .nam files the Windows
/// tooling already uses).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final models = <String, String>{
    'solid-rhythm-mid-hi': '/data/local/tmp/solid_rhythm.nam',
    'gojira-joe-duplantier': '/data/local/tmp/gojira.nam',
    'jvm410h-standard': '/data/local/tmp/jvm410h.nam',
    'fender-super-reverb-akg414': '/data/local/tmp/fender_akg414.nam',
    'fndr-pano-wavenet-054': '/data/local/tmp/fndr_pano.nam',
  };

  for (final entry in models.entries) {
    testWidgets('Reference Signal V4 through ${entry.key} on-device', (tester) async {
      // Fingerprint the reference signal itself once per case (section 5) --
      // pure Dart, expected identical to the Windows-pinned value.
      final refSignal = WyrmToneReferenceSignalV4.generate();
      final refSha = sha256.convert(refSignal.buffer.asUint8List()).toString();

      final loadWatch = Stopwatch()..start();
      final engine = NamInferenceEngine.create();
      addTearDown(engine.dispose);
      engine.load(entry.value, sampleRate: WyrmToneReferenceSignalV4.sampleRate.toDouble());
      loadWatch.stop();
      expect(engine.isLoaded, isTrue);

      final inferWatch = Stopwatch()..start();
      final output = engine.process(refSignal);
      inferWatch.stop();

      expect(output.length, WyrmToneReferenceSignalV4.totalFrames);
      var allFinite = true;
      var minV = double.infinity, maxV = double.negativeInfinity;
      for (final v in output) {
        if (!v.isFinite) allFinite = false;
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }
      expect(allFinite, isTrue, reason: 'no NaN/Infinity in on-device output');

      final outBytes = output.buffer.asUint8List();
      final outSha = sha256.convert(outBytes).toString();
      // Diagnostic only: dumped for an offline Windows-vs-Android sample-by-
      // sample diff (section 7-8), same pattern as the reference-signal dump.
      File('${Directory.systemTemp.path}/android_output_${entry.key}.bin').writeAsBytesSync(outBytes);

      // Determinism: repeat once more on a fresh engine, same input.
      final repeatEngine = NamInferenceEngine.create();
      repeatEngine.load(entry.value, sampleRate: WyrmToneReferenceSignalV4.sampleRate.toDouble());
      final repeatOutput = repeatEngine.process(refSignal);
      repeatEngine.dispose();
      final deterministic = _sameBytes(output, repeatOutput);
      expect(deterministic, isTrue, reason: 'same input on a fresh engine must repeat exactly');

      // Single-line, greppable machine-readable report line for this case.
      // ignore: avoid_print
      print(
        'NAM_GOLDEN_RESULT ${jsonEncode({
          'id': entry.key,
          'refSha256': refSha,
          'samples': output.length,
          'allFinite': allFinite,
          'min': minV,
          'max': maxV,
          'sha256': outSha,
          'loadMs': loadWatch.elapsedMilliseconds,
          'inferMs': inferWatch.elapsedMilliseconds,
          'deterministic': deterministic,
        })}',
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  // Diagnostic only: keeps the process (and its dumped output files) alive
  // long enough to `adb exec-out run-as ... cat` each one out before the
  // test runner uninstalls the app.
  testWidgets('hold process alive for output pull window', (tester) async {
    await Future<void>.delayed(const Duration(seconds: 45));
  });
}

bool _sameBytes(Float32List a, Float32List b) {
  final ba = a.buffer.asUint8List();
  final bb = b.buffer.asUint8List();
  if (ba.length != bb.length) return false;
  for (var i = 0; i < ba.length; i++) {
    if (ba[i] != bb[i]) return false;
  }
  return true;
}
