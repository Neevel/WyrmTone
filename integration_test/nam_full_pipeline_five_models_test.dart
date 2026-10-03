import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wyrmtone/services/nam_inference_engine.dart';
import 'package:wyrmtone/services/nam_preparation_service.dart';
import 'package:wyrmtone/services/matribox_nam_clodata/nam_clodata_converter.dart';
import 'package:wyrmtone/services/wyrmtone_reference_signal_v4.dart';

/// Android NAM Inference V1, final on-device CloData gate, sections 4-7:
/// the remaining four golden models through the real product
/// [NamPreparationService.prepare] pipeline, plus per-stage performance,
/// full-pipeline UI-thread-not-blocked proof, and a rough memory
/// observation. Only reached after `nam_full_pipeline_gate_test.dart`
/// (JVM410H) passed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final models = <String, (String path, String sha)>{
    'solid-rhythm-mid-hi': ('/data/local/tmp/solid_rhythm.nam', 'unknown'),
    'gojira-joe-duplantier': ('/data/local/tmp/gojira.nam', 'unknown'),
    'fender-super-reverb-akg414': ('/data/local/tmp/fender_akg414.nam', 'unknown'),
    'fndr-pano-wavenet-054': ('/data/local/tmp/fndr_pano.nam', 'unknown'),
  };

  for (final entry in models.entries) {
    testWidgets('full on-device preparation for ${entry.key}', (tester) async {
      final service = NamPreparationService();
      final result = await service.prepare(
        entry.value.$1,
        namName: entry.key,
        namSha256: entry.value.$2,
      );
      expect(result.outcome, NamPreparationOutcome.success, reason: '${entry.key}: ${result.error}');
      final payload = result.payload!;
      expect(payload.cloData.length, 8232);

      final second = await service.prepare(entry.value.$1, namName: entry.key, namSha256: entry.value.$2);
      expect(second.payload!.cloDataSha256, payload.cloDataSha256, reason: 'must be deterministic');

      // ignore: avoid_print
      print(
        'FIVE_MODEL_RESULT {"model":"${entry.key}","cloDataLength":${payload.cloData.length},'
        '"cloDataSha256":"${payload.cloDataSha256}","preparationMs":${payload.preparationDuration.inMilliseconds},'
        '"deterministic":true}',
      );
      // Two full prepare() calls per model; on a slower device each can take
      // well over a minute (observed up to ~90s/call on a Galaxy S21), so
      // this needs real headroom, not the 2-minute default used elsewhere.
    }, timeout: const Timeout(Duration(minutes: 6)));
  }

  // Section 5: per-stage performance, all five models. Replicates
  // NamPreparationService's internal stage sequence with a Stopwatch
  // between each stage -- diagnostic-only instrumentation, not a change to
  // the frozen production pipeline (which stays black-boxed in one
  // Isolate.run call, see nam_preparation_service.dart's own docs on why).
  final allModels = <String, String>{
    'solid-rhythm-mid-hi': '/data/local/tmp/solid_rhythm.nam',
    'gojira-joe-duplantier': '/data/local/tmp/gojira.nam',
    'jvm410h-standard': '/data/local/tmp/jvm410h.nam',
    'fender-super-reverb-akg414': '/data/local/tmp/fender_akg414.nam',
    'fndr-pano-wavenet-054': '/data/local/tmp/fndr_pano.nam',
  };

  for (final entry in allModels.entries) {
    testWidgets('per-stage performance for ${entry.key}', (tester) async {
      final sw = Stopwatch();

      sw.start();
      final engine = NamInferenceEngine.create();
      engine.load(entry.value, sampleRate: WyrmToneReferenceSignalV4.sampleRate.toDouble());
      final loadMs = sw.elapsedMilliseconds;

      sw.reset();
      final reference = WyrmToneReferenceSignalV4.generate();
      final referenceMs = sw.elapsedMilliseconds;

      sw.reset();
      final output = engine.process(reference);
      final inferenceMs = sw.elapsedMilliseconds;
      engine.dispose();

      sw.reset();
      const converter = MatriboxNamCloDataConverter();
      final refWav = _wavFloat32Mono(reference, 48000);
      final outWav = _wavFloat32Mono(output, 48000);
      final cloData = converter.convert(referenceWav: refWav, modelOutputWav: outWav, fileName: entry.key).bytes;
      final estimatorMs = sw.elapsedMilliseconds;

      expect(cloData.length, 8232);
      final totalMs = loadMs + referenceMs + inferenceMs + estimatorMs;

      // ignore: avoid_print
      print(
        'PERF_RESULT {"model":"${entry.key}","loadMs":$loadMs,"referenceMs":$referenceMs,'
        '"inferenceMs":$inferenceMs,"estimatorMs":$estimatorMs,"totalMs":$totalMs}',
      );
    }, timeout: const Timeout(Duration(minutes: 4)));
  }

  // Section 6: the FULL preparation (reference + inference + estimator via
  // the real product prepare() call) must not block the main isolate.
  testWidgets('main isolate stays responsive during the full JVM410H preparation', (tester) async {
    var ticks = 0;
    final ticker = Timer.periodic(const Duration(milliseconds: 50), (_) => ticks++);
    final service = NamPreparationService();
    final sw = Stopwatch()..start();
    final result = await service.prepare(
      '/data/local/tmp/jvm410h.nam',
      namName: 'JVM410H Standard',
      namSha256: 'unknown',
    );
    sw.stop();
    ticker.cancel();
    expect(result.outcome, NamPreparationOutcome.success);
    final expectedMinTicks = (sw.elapsedMilliseconds / 50 * 0.5).floor();
    // ignore: avoid_print
    print(
      'FULL_PIPELINE_UI_THREAD_RESULT {"prepareMs":${sw.elapsedMilliseconds},"ticks":$ticks,'
      '"expectedMinTicks":$expectedMinTicks}',
    );
    expect(ticks, greaterThanOrEqualTo(expectedMinTicks));
  }, timeout: const Timeout(Duration(minutes: 2)));

  // Section 7: rough memory observation, best-effort only.
  testWidgets('rough memory observation around one full preparation', (tester) async {
    int? before, after;
    try {
      before = ProcessInfo.currentRss;
    } catch (_) {
      before = null;
    }
    final service = NamPreparationService();
    final result = await service.prepare(
      '/data/local/tmp/jvm410h.nam',
      namName: 'JVM410H Standard',
      namSha256: 'unknown',
    );
    expect(result.outcome, NamPreparationOutcome.success);
    try {
      after = ProcessInfo.currentRss;
    } catch (_) {
      after = null;
    }
    // ignore: avoid_print
    print('MEMORY_RESULT {"rssBeforeBytes":$before,"rssAfterBytes":$after}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

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
  u16(3);
  u16(1);
  u32(sampleRate);
  u32(sampleRate * 4);
  u16(4);
  u16(32);
  header.add(ascii.encode('data'));
  u32(dataBytes.length);
  return Uint8List.fromList([...header.toBytes(), ...dataBytes]);
}
