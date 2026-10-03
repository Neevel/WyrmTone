import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wyrmtone/services/matribox_nam_clodata/clone_data.dart';
import 'package:wyrmtone/services/matribox_nam_payload.dart';
import 'package:wyrmtone/services/nam_preparation_service.dart';

/// Android NAM Inference V1, final on-device CloData gate, section 3: the
/// FIRST model through the complete on-device product pipeline (local .nam
/// -> Reference Signal V4 -> Android inference -> frozen V4 CloData
/// estimator -> MatriboxNamPayload), entirely through the real
/// [NamPreparationService.prepare] product API -- no shortcuts, no
/// Windows-side participation. If this fails, the remaining four golden
/// models are deliberately NOT attempted in a separate test run.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('JVM410H Standard: complete on-device preparation produces a valid MatriboxNamPayload', (
    tester,
  ) async {
    final service = NamPreparationService();
    final stages = <NamPreparationStage>[];

    final result = await service.prepare(
      '/data/local/tmp/jvm410h.nam',
      namName: 'JVM410H Standard',
      namSha256: '8e2c468813e0332d4c0907b2dd3ec120bdc863ac1778b7ddb7f34ed32f0ef859',
      onProgress: stages.add,
    );

    expect(result.outcome, NamPreparationOutcome.success, reason: 'prepare() must succeed: ${result.error}');
    expect(stages, [NamPreparationStage.loadingModel, NamPreparationStage.ready]);

    final payload = result.payload!;
    expect(payload.cloData.length, MatriboxCloneData.totalLength);
    expect(payload.cloData.length, 8232);
    expect(payload.namName, 'JVM410H Standard');
    expect(payload.cloDataSha256, isNotEmpty);
    expect(() => MatriboxNamPayload.validate(payload.cloData), returnsNormally);

    // Deterministic: a second, fully independent preparation of the same
    // NAM must produce byte-identical CloData.
    final second = await service.prepare(
      '/data/local/tmp/jvm410h.nam',
      namName: 'JVM410H Standard',
      namSha256: '8e2c468813e0332d4c0907b2dd3ec120bdc863ac1778b7ddb7f34ed32f0ef859',
    );
    expect(second.outcome, NamPreparationOutcome.success);
    expect(second.payload!.cloDataSha256, payload.cloDataSha256, reason: 'must be deterministic on repeat');

    // ignore: avoid_print
    print(
      'GATE_RESULT {"model":"jvm410h-standard","cloDataLength":${payload.cloData.length},'
      '"cloDataSha256":"${payload.cloDataSha256}","preparationMs":${payload.preparationDuration.inMilliseconds},'
      '"deterministic":true}',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
