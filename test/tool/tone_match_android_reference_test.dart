@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/services/nam_inference_engine.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/evaluation_signal_loader.dart';
import 'package:wyrmtone/tonematch/nam_inference_analyzer.dart';
import 'package:wyrmtone/tonematch/stft_feature_extractor.dart';
import 'package:wyrmtone/tonematch/tone_features.dart';

import '../../tool/tonematch_gate/gate_dsp.dart';

/// Desktop reference of the T15 feature summaries the Android harness reports, to check that the
/// Android native bridge yields the same analysis (docs section 10). Runs only with WYRMTONE_RUN_ANDROID_REF=1.
void main() {
  final run = Platform.environment['WYRMTONE_RUN_ANDROID_REF'] == '1';
  test('desktop T15 summaries for the Android comparison', () async {
    final nams = (jsonDecode(File('tool/tonematch_gate/ten_nam_set.json').readAsStringSync()) as List).cast<Map<String, Object?>>();
    const loader = FileEvaluationSignalLoader(_read);
    final analyzer = NamInferenceAnalyzer(createEngine: () => NamInferenceEngine.create('native/nam_bridge/build/wyrmtone_nam.dll'));
    final out = <String, Map<String, Object?>>{};
    for (final role in [EvaluationRole.rhythm, EvaluationRole.lead]) {
      final prepared = await loader.prepare(EvaluationSignalRegistry.forRole(role)!);
      final t15 = buildVariants(prepared.samples, contentSeconds: [15]).firstWhere((v) => v.id == 'T15').samples;
      for (final n in nams) {
        final eng = NamInferenceEngine.create('native/nam_bridge/build/wyrmtone_nam.dll');
        try {
          eng.load(n['path']! as String, sampleRate: evaluationSampleRate.toDouble());
          final f = const StftFeatureExtractor().extract(input: t15, output: analyzer.runModel(eng, t15)).tone;
          (out[role.name] ??= <String, Object?>{})[n['id']! as String] = {for (final k in [ToneFeatureIds.centroidHz, ToneFeatureIds.crestDb, ToneFeatureIds.saturationComposite, ToneFeatureIds.attackMs]) k: f[k]};
        } finally {
          eng.dispose();
        }
      }
    }
    File('tool/tonematch_android_bench/results/desktop_t15_summary.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
  }, skip: run ? false : 'set WYRMTONE_RUN_ANDROID_REF=1', timeout: const Timeout(Duration(minutes: 20)));
}

Future<Uint8List> _read(String p) => File(p).readAsBytes();
