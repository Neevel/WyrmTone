import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wyrmtone/services/nam_inference_engine.dart';

/// Android NAM Inference V1, section 4: the first real on-device smoke
/// test. Runs on the connected Android device (never in a host-side
/// `flutter test`, which cannot load `libwyrmtone_nam.so`) via
/// `flutter test integration_test/nam_inference_smoke_test.dart -d <device>`.
///
/// Deliberately narrow, matching section 4's own steps exactly: load the
/// native library, load one real .nam, process one small deterministic
/// buffer, check the output, dispose. No Reference Signal V4 here (that is
/// section 6) and no Matribox/MIDI access of any kind.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('JVM410H Standard loads and processes a deterministic buffer on-device', (tester) async {
    // 1. native .so laden (implicit: NamInferenceEngine.create() opens
    //    libwyrmtone_nam.so via DynamicLibrary.open on this platform).
    final engine = NamInferenceEngine.create();
    // dispose() is idempotent (see NamInferenceEngine docs), so registering
    // it here is safe even though the test also calls it explicitly below.
    addTearDown(engine.dispose);

    // 2. NAM laden -- pushed to /data/local/tmp (world-readable, adb push)
    //    ahead of this run; not bundled as a repo asset.
    const namPath = '/data/local/tmp/jvm410h.nam';
    engine.load(namPath, sampleRate: 48000.0, maxBlockSize: 4096);
    expect(engine.isLoaded, isTrue);
    expect(engine.expectedSampleRate, greaterThan(0));

    // 3. kleinen deterministischen Testbuffer verarbeiten.
    final input = Float32List.fromList([for (var i = 0; i < 2000; i++) 0.1 * math.sin(i * 0.05)]);

    // 4. Output zurück nach Dart.
    final output = engine.process(input);

    // 5. prüfen.
    expect(output.length, input.length, reason: 'Output-Länge korrekt');
    for (final sample in output) {
      expect(sample.isNaN, isFalse, reason: 'keine NaN');
      expect(sample.isInfinite, isFalse, reason: 'keine Infinity');
      expect(sample.isFinite, isTrue, reason: 'alle Werte finite');
    }
    expect(output.any((s) => s != 0.0), isTrue, reason: 'Output nicht komplett Null');

    // 6. Model sauber dispose.
    engine.dispose();
    expect(() => engine.isLoaded, throwsStateError);
  });
}
