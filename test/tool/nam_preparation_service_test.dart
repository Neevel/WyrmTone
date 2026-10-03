@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:wyrmtone/services/nam_inference_engine.dart';
import 'package:wyrmtone/services/nam_preparation_service.dart';
import 'package:wyrmtone/services/wyrmtone_reference_signal_v4.dart';

/// Android NAM Inference V1, sections 11-13: [NamPreparationService]'s
/// isolate-based execution and cooperative cancellation. Windows-only for
/// the same reason as `nam_inference_test.dart` (the native bridge under
/// test here is the Windows DLL in this validation stage); the isolate/
/// cancellation logic itself is platform-agnostic Dart and will behave the
/// same way once the equivalent runs against the Android .so.
void main() {
  final dllExists = File('native/nam_bridge/build/wyrmtone_nam.dll').existsSync();
  final skipNoNative = dllExists ? false : 'native/nam_bridge/build/wyrmtone_nam.dll not built';

  final fndrPano = File(
    r'D:\Desktop 3d sachen\Desktop\AMP Presets\Fender Pano-Verb\FNDR PANO Clean2 BAL 6V6 CAB.nam',
  );
  final skipNoFixture = fndrPano.existsSync() ? false : 'local FNDR PANO .nam not available';

  test(
    'runs the full Reference Signal V4 through a real model on a background isolate',
    () async {
      final service = NamPreparationService();
      final out = await service.runReferenceSignalInference(fndrPano.path);
      expect(out.length, WyrmToneReferenceSignalV4.totalFrames);
      expect(out.any((v) => !v.isFinite), isFalse);
    },
    skip: skipNoNative != false ? skipNoNative : skipNoFixture,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'cancelling before the isolate call finishes discards the result',
    () async {
      final service = NamPreparationService();
      final token = service.createCancelToken();
      final future = service.runReferenceSignalInference(fndrPano.path, cancelToken: token);
      service.cancel(token); // race is intentional: the isolate call takes seconds, this runs first
      await expectLater(
        future,
        throwsA(
          isA<NamInferenceException>().having((e) => e.kind, 'kind', NamInferenceErrorKind.cancelled),
        ),
      );
    },
    skip: skipNoNative != false ? skipNoNative : skipNoFixture,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('an unresolvable native library surfaces as a controlled error, never a crash', () {
    expect(
      () => NamInferenceEngine.create('does/not/exist.dll'),
      throwsA(isA<NamLibraryUnavailableException>()),
    );
  });
}
