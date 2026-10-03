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

import '../../tool/tonematch_gate/gate_dsp.dart';

/// AnalysisVersion-2 acceptance experiment (docs/TONE_MATCH.md section 8): the offset experiment of
/// section 7.3 repeated for V1 and V2 on identical NAM outputs, plus the extraction-cost
/// measurement on T15. Runs only with WYRMTONE_RUN_V2_GATE=1.
const _dll = 'native/nam_bridge/build/wyrmtone_nam.dll';
const _exactOffsets = [0, 16, 32, 48, 128, 256, 384];
const _generalizationOffsets = [5, 11, 24, 37, 53];

void main() {
  final run = Platform.environment['WYRMTONE_RUN_V2_GATE'] == '1';
  test('V1 vs V2 offset experiment and extraction cost', () async {
    final nams = (jsonDecode(File('tool/tonematch_gate/ten_nam_set.json').readAsStringSync()) as List).cast<Map<String, Object?>>();
    for (final n in nams) {
      expect(sha256.convert(File(n['path']! as String).readAsBytesSync()).toString(), n['sha'], reason: 'NAM changed: ${n['id']}');
    }
    NamInferenceEngine engine() => NamInferenceEngine.create(_dll);
    const loader = FileEvaluationSignalLoader(_read);
    final signals = {for (final r in [EvaluationRole.rhythm, EvaluationRole.lead]) r: await loader.prepare(EvaluationSignalRegistry.forRole(r)!)};
    final t15 = {for (final e in signals.entries) e.key: buildVariants(e.value.samples, contentSeconds: [15]).firstWhere((v) => v.id == 'T15')};
    const v1 = StftFeatureExtractor();
    const v2 = StftFeatureExtractor(analysisVersion: 2, multiphaseTransient: true);
    final analyzer = NamInferenceAnalyzer(createEngine: engine);

    final raw = <String, Object?>{'exactOffsets': _exactOffsets, 'generalizationOffsets': _generalizationOffsets, 'offsets': <String, Object?>{}, 'perf': <String, Object?>{}};
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
          for (final o in [..._exactOffsets, ..._generalizationOffsets]) {
            final a = Float32List.sublistView(input, o), b = Float32List.sublistView(output, o);
            final f1 = v1.extract(input: a, output: b), f2 = v2.extract(input: a, output: b);
            per['${e.key.name}/$o'] = {'v1': {'level': f1.level, 'tone': f1.tone}, 'v2': {'level': f2.level, 'tone': f2.tone}};
          }
        } finally {
          eng.dispose();
        }

        // extraction cost on T15 (inference timed too); extraction measured as the mean of 5 runs after one warm-up
        final eng2 = engine();
        try {
          eng2.load(path, sampleRate: evaluationSampleRate.toDouble());
          final x = t15[e.key]!.samples;
          final inf = Stopwatch()..start();
          final out = analyzer.runModel(eng2, x);
          inf.stop();
          int timeIt(StftFeatureExtractor ex) {
            ex.extract(input: x, output: out);
            final w = Stopwatch()..start();
            for (var i = 0; i < 5; i++) {
              ex.extract(input: x, output: out);
            }
            return w.elapsedMicroseconds ~/ 5;
          }

          (raw['perf']! as Map)['$id/${e.key.name}'] = {'inferenceMs': inf.elapsedMilliseconds, 'v1ExtractUs': timeIt(v1), 'v2ExtractUs': timeIt(v2), 'seconds': x.length / evaluationSampleRate};
        } finally {
          eng2.dispose();
        }
      }
    }
    final dir = Directory('tool/tonematch_envelope_v2/results')..createSync(recursive: true);
    File('${dir.path}/raw.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(raw));
  }, skip: run ? false : 'set WYRMTONE_RUN_V2_GATE=1', timeout: const Timeout(Duration(minutes: 40)));
}

Future<Uint8List> _read(String p) => File(p).readAsBytes();
