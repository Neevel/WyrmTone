@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/services/nam_inference_engine.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/evaluation_signal_loader.dart';
import 'package:wyrmtone/tonematch/nam_inference_analyzer.dart';
import 'package:wyrmtone/tonematch/stft_feature_extractor.dart';

import '../../tool/tonematch_envelope_v2/hop1_reference.dart';
import '../../tool/tonematch_gate/gate_dsp.dart';

/// Final envelope-stability gate (docs/TONE_MATCH.md section 9). Hold-out offsets are fixed in the
/// docs BEFORE this runs. Runs only with WYRMTONE_RUN_FINAL_GATE=1.
const _dll = 'native/nam_bridge/build/wyrmtone_nam.dll';
const holdoutOffsets = [1, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61];

void main() {
  final run = Platform.environment['WYRMTONE_RUN_FINAL_GATE'] == '1';
  test('final envelope gate: V1 vs 4/8/16 phases on hold-out offsets, hop-1 accuracy, cost', () async {
    final nams = (jsonDecode(File('tool/tonematch_gate/ten_nam_set.json').readAsStringSync()) as List).cast<Map<String, Object?>>();
    for (final n in nams) {
      expect(sha256.convert(File(n['path']! as String).readAsBytesSync()).toString(), n['sha'], reason: 'NAM changed: ${n['id']}');
    }
    NamInferenceEngine engine() => NamInferenceEngine.create(_dll);
    const loader = FileEvaluationSignalLoader(_read);
    final signals = {for (final r in [EvaluationRole.rhythm, EvaluationRole.lead]) r: await loader.prepare(EvaluationSignalRegistry.forRole(r)!)};
    final t15 = {for (final e in signals.entries) e.key: buildVariants(e.value.samples, contentSeconds: [15]).firstWhere((v) => v.id == 'T15')};
    final candidates = <String, StftFeatureExtractor>{
      'v1': const StftFeatureExtractor(),
      'v2_4': const StftFeatureExtractor(analysisVersion: 2, envelopePhaseCount: 4),
      'v2_8': const StftFeatureExtractor(analysisVersion: 2, envelopePhaseCount: 8),
      'v2_16': const StftFeatureExtractor(analysisVersion: 2, envelopePhaseCount: 16),
    };
    final analyzer = NamInferenceAnalyzer(createEngine: engine);
    final raw = <String, Object?>{'holdoutOffsets': holdoutOffsets, 'candidates': candidates.keys.toList(), 'offsets': <String, Object?>{}, 'reference': <String, Object?>{}, 'perf': <String, Object?>{}};

    for (final n in nams) {
      final id = n['id']! as String;
      final path = n['path']! as String;
      final per = <String, Object?>{};
      (raw['offsets']! as Map)[id] = per;
      for (final e in signals.entries) {
        final eng = engine();
        try {
          eng.load(path, sampleRate: evaluationSampleRate.toDouble());
          final input = e.value.samples;
          final output = analyzer.runModel(eng, input);
          final ref = hop1Reference(input, output);
          (raw['reference']! as Map)['$id/${e.key.name}'] = {'attackMs': ref.attackMs, 'decayDbPerSec': ref.decayDbPerSec, 'transientPeakToBodyDb': ref.transientPeakToBodyDb, 'onsets': ref.onsets};
          for (final o in [0, ...holdoutOffsets]) {
            final a = Float32List.sublistView(input, o), b = Float32List.sublistView(output, o);
            per['${e.key.name}/$o'] = {for (final c in candidates.entries) c.key: c.value.extract(input: a, output: b).tone};
          }
        } finally {
          eng.dispose();
        }

        final eng2 = engine();
        try {
          eng2.load(path, sampleRate: evaluationSampleRate.toDouble());
          final x = t15[e.key]!.samples;
          final inf = Stopwatch()..start();
          final out = analyzer.runModel(eng2, x);
          inf.stop();
          final perf = <String, Object?>{'inferenceMs': inf.elapsedMilliseconds, 'seconds': x.length / evaluationSampleRate};
          for (final c in candidates.entries) {
            c.value.extract(input: x, output: out); // warm-up
            final w = Stopwatch()..start();
            for (var i = 0; i < 5; i++) {
              c.value.extract(input: x, output: out);
            }
            perf['${c.key}Us'] = w.elapsedMicroseconds ~/ 5;
          }
          (raw['perf']! as Map)['$id/${e.key.name}'] = perf;
        } finally {
          eng2.dispose();
        }
      }
    }
    final dir = Directory('tool/tonematch_envelope_v2/results')..createSync(recursive: true);
    File('${dir.path}/final_gate_raw.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(raw));
  }, skip: run ? false : 'set WYRMTONE_RUN_FINAL_GATE=1', timeout: const Timeout(Duration(minutes: 60)));
}

Future<Uint8List> _read(String p) => File(p).readAsBytes();
