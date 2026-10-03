import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wyrmtone/services/nam_inference_engine.dart';

/// Android NAM Inference V1, section 15: on-device failure-case coverage
/// against the real Android .so (mirrors `test/tool/nam_inference_test.dart`'s
/// Windows-side coverage of the same cases -- kept here rather than merged,
/// since that file is `@TestOn('windows')` and this one only runs on-device).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('missing file is rejected with fileNotFound, never a crash', (tester) async {
    final engine = NamInferenceEngine.create();
    addTearDown(engine.dispose);
    expect(
      () => engine.load('/data/local/tmp/does_not_exist.nam'),
      throwsA(isA<NamInferenceException>().having((e) => e.kind, 'kind', NamInferenceErrorKind.fileNotFound)),
    );
    expect(engine.isLoaded, isFalse);
  });

  testWidgets('truncated/invalid-JSON NAM is rejected, never a crash', (tester) async {
    final bad = File('${Directory.systemTemp.path}/wyrmtone_bad_${DateTime.now().microsecondsSinceEpoch}.nam');
    bad.writeAsStringSync('not json');
    addTearDown(() => bad.deleteSync());
    final engine = NamInferenceEngine.create();
    addTearDown(engine.dispose);
    expect(
      () => engine.load(bad.path),
      throwsA(isA<NamInferenceException>().having((e) => e.kind, 'kind', NamInferenceErrorKind.loadFailed)),
    );
    expect(engine.isLoaded, isFalse);
  });

  testWidgets('processing without a loaded model throws notLoaded, never a crash', (tester) async {
    final engine = NamInferenceEngine.create();
    addTearDown(engine.dispose);
    expect(
      () => engine.process(Float32List(10)),
      throwsA(isA<NamInferenceException>().having((e) => e.kind, 'kind', NamInferenceErrorKind.notLoaded)),
    );
  });

  testWidgets('repeated load/dispose and repeated inference on real hardware, no leak, deterministic', (
    tester,
  ) async {
    const namPath = '/data/local/tmp/jvm410h.nam';
    final input = Float32List.fromList([for (var i = 0; i < 4000; i++) 0.2 * math.sin(i * 0.02)]);
    Float32List? first;
    for (var i = 0; i < 3; i++) {
      final engine = NamInferenceEngine.create();
      engine.load(namPath, sampleRate: 48000.0);
      expect(engine.isLoaded, isTrue);
      final out = engine.process(input);
      expect(out.length, input.length);
      expect(out.every((v) => v.isFinite), isTrue);
      first ??= out;
      if (i > 0) {
        expect(out, orderedEquals(first), reason: 'a fresh engine on the same input must repeat exactly');
      }
      engine.unload();
      expect(engine.isLoaded, isFalse);
      engine.dispose();
      engine.dispose(); // idempotent
      expect(() => engine.isLoaded, throwsStateError);
    }
  });

  testWidgets('dispose after a failed load is safe (no leak, no crash)', (tester) async {
    final engine = NamInferenceEngine.create();
    expect(() => engine.load('/data/local/tmp/does_not_exist.nam'), throwsA(isA<NamInferenceException>()));
    engine.dispose();
    engine.dispose(); // idempotent, still safe
    expect(() => engine.isLoaded, throwsStateError);
  });

  testWidgets('an unresolvable native library surfaces as a controlled error, never a crash', (tester) async {
    expect(
      () => NamInferenceEngine.create('/data/local/tmp/does_not_exist.so'),
      throwsA(isA<NamLibraryUnavailableException>()),
    );
  });
}
