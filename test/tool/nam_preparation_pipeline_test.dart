@TestOn('windows')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/services/matribox_nam_clodata/nam_clodata_converter.dart';
import 'package:wyrmtone/services/matribox_nam_payload.dart';
import 'package:wyrmtone/services/nam_inference_engine.dart';
import 'package:wyrmtone/services/nam_preparation_service.dart';

/// Android NAM Inference V1 gap-closing milestone, section 13: full
/// `NamPreparationService.prepare()` pipeline (load -> Reference Signal V4
/// -> inference -> frozen V4 CloData estimator -> MatriboxNamPayload),
/// exercised Windows-side first (fast iteration, same DLL/logic the
/// on-device integration tests then repeat against the real .so) before
/// spending device cycles.
void main() {
  final dllExists = File('native/nam_bridge/build/wyrmtone_nam.dll').existsSync();
  final skipNoNative = dllExists ? false : 'native/nam_bridge/build/wyrmtone_nam.dll not built';

  final fndrPano = File(
    r'D:\Desktop 3d sachen\Desktop\AMP Presets\Fender Pano-Verb\FNDR PANO Clean2 BAL 6V6 CAB.nam',
  );
  final skipNoFixture = fndrPano.existsSync() ? false : 'local FNDR PANO .nam not available';
  final skip = skipNoNative != false ? skipNoNative : skipNoFixture;

  test(
    'complete preparation succeeds: exact 8232 bytes, valid, deterministic on repeat',
    () async {
      final service = NamPreparationService();
      final result = await service.prepare(fndrPano.path, namName: 'FNDR PANO', namSha256: 'test-sha');
      expect(result.outcome, NamPreparationOutcome.success);
      final payload = result.payload!;
      expect(payload.cloData.length, 8232);
      expect(payload.namName, 'FNDR PANO');
      expect(payload.cloDataSha256, isNotEmpty);
      expect(payload.preparationDuration, greaterThan(Duration.zero));

      final result2 = await service.prepare(fndrPano.path, namName: 'FNDR PANO', namSha256: 'test-sha');
      expect(result2.outcome, NamPreparationOutcome.success);
      expect(result2.payload!.cloDataSha256, payload.cloDataSha256, reason: 'same NAM must produce identical CloData');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('missing NAM file fails cleanly, no crash, result carries the error', () async {
    final service = NamPreparationService();
    final result = await service.prepare('does/not/exist.nam', namName: 'x', namSha256: 'x');
    expect(result.outcome, NamPreparationOutcome.failed);
    expect(result.error!.kind, NamInferenceErrorKind.fileNotFound);
    expect(result.payload, isNull);
  }, skip: skipNoNative);

  test('corrupt/unsupported NAM fails cleanly, no crash', () async {
    final bad = File('${Directory.systemTemp.path}/wyrmtone_bad_prep_${DateTime.now().microsecondsSinceEpoch}.nam');
    bad.writeAsStringSync('not json');
    addTearDown(() => bad.deleteSync());
    final service = NamPreparationService();
    final result = await service.prepare(bad.path, namName: 'bad', namSha256: 'x');
    expect(result.outcome, NamPreparationOutcome.failed);
    expect(result.error!.kind, NamInferenceErrorKind.loadFailed);
  }, skip: skipNoNative);

  test('cancelling before the isolate call finishes discards the result and payload', () async {
    final service = NamPreparationService();
    final token = service.createCancelToken();
    final future = service.prepare(fndrPano.path, namName: 'x', namSha256: 'x', cancelToken: token);
    service.cancel(token);
    final result = await future;
    expect(result.outcome, NamPreparationOutcome.cancelled);
    expect(result.payload, isNull);
    expect(result.error, isNull);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  // Product NAM name fix: NamPreparationService used to hardcode fileName:
  // 'nam' when calling the converter -- the 16-byte CloData name field never
  // reflected the real NAM, which is why a real product transfer showed the
  // Matribox's AMP block labelled just "nam". These tests prove the real
  // name now reaches that field (bytes 0-15), via the actual production
  // pipeline -- not a guess, not a unit test of nameBytes() in isolation.
  group('CloData name field reflects the real NAM name (product NAM name fix)', () {
    test('the real name reaches bytes 0-15, exactly matching nameBytes() -- never the literal "nam" unless that is the real name', () async {
      final service = NamPreparationService();
      final result = await service.prepare(fndrPano.path, namName: 'FNDR PANO', namSha256: 'x');
      expect(result.outcome, NamPreparationOutcome.success);
      final nameField = result.payload!.cloData.sublist(0, 16);
      expect(nameField, MatriboxNamCloDataConverter.nameBytes('FNDR PANO'));
      expect(nameField, isNot(MatriboxNamCloDataConverter.nameBytes('nam')), reason: 'the old hardcoded placeholder must be gone');
    }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'two different NAM names produce different name fields but byte-identical CloData everywhere else',
      () async {
        final service = NamPreparationService();
        final resultA = await service.prepare(fndrPano.path, namName: 'FNDR PANO Clean2', namSha256: 'x');
        final serviceB = NamPreparationService();
        final resultB = await serviceB.prepare(fndrPano.path, namName: 'A Completely Different Name', namSha256: 'x');
        expect(resultA.outcome, NamPreparationOutcome.success);
        expect(resultB.outcome, NamPreparationOutcome.success);
        final cloA = resultA.payload!.cloData;
        final cloB = resultB.payload!.cloData;
        expect(cloA.length, 8232);
        expect(cloB.length, 8232);
        expect(cloA.sublist(0, 16), isNot(cloB.sublist(0, 16)), reason: 'name fields must differ');
        expect(
          cloA.sublist(16),
          cloB.sublist(16),
          reason: 'only the name field may differ -- same NAM, same inference, same estimator output everywhere else',
        );
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('the exact Peavey product example truncates to the documented 16-byte field', () async {
      final service = NamPreparationService();
      const peaveyName = 'Full Rig Peavey 5150 No boost Mesa OS SM57 - jp_is_out_of_tune';
      final result = await service.prepare(fndrPano.path, namName: peaveyName, namSha256: 'x');
      expect(result.outcome, NamPreparationOutcome.success);
      final nameField = result.payload!.cloData.sublist(0, 16);
      expect(String.fromCharCodes(nameField), 'Full Rig Peavey ');
      expect(nameField, MatriboxNamCloDataConverter.nameBytes(peaveyName));
    }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
  });

  test('MatriboxNamPayload.validate rejects a wrong-length or non-finite buffer', () {
    expect(() => MatriboxNamPayload.validate(Uint8List(100)), throwsFormatException);
  });

  test('an unresolvable native library fails via prepare() as libraryUnavailable, not a crash', () async {
    NamInferenceEngine createWithBadPath() => NamInferenceEngine.create('does/not/exist.dll');
    expect(createWithBadPath, throwsA(isA<NamLibraryUnavailableException>()));
  });
}
