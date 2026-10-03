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
import 'package:wyrmtone/tonematch/tone_features.dart';

import '../../tool/tonematch_saturation_gate/probe.dart';

/// Saturation validation gate (AnalysisVersion 1 frozen). Raw data only; statistics are computed by
/// tool/tonematch_saturation_gate/analyze.py. Runs only with WYRMTONE_RUN_SAT_GATE=1.
const _dll = 'native/nam_bridge/build/wyrmtone_nam.dll';
const _offsets = [0, 16, 32, 48, 128, 256, 384];

void main() {
  final run = Platform.environment['WYRMTONE_RUN_SAT_GATE'] == '1';
  test('saturation gate: probes x 10 NAMs and frame-offset experiment', () async {
    final nams = (jsonDecode(File('tool/tonematch_gate/ten_nam_set.json').readAsStringSync()) as List).cast<Map<String, Object?>>();
    for (final n in nams) {
      expect(sha256.convert(File(n['path']! as String).readAsBytesSync()).toString(), n['sha'], reason: 'NAM changed: ${n['id']}');
    }
    NamInferenceEngine engine() => NamInferenceEngine.create(_dll);
    final analyzers = {for (final f in probeFrequencies) f: HarmonicAnalyzer(f)};
    final probes = {
      for (final f in probeFrequencies)
        for (final l in probeLevelsDbfs) '$f/$l': generateProbe(f, l),
    };

    final raw = <String, Object?>{
      'frequencies': probeFrequencies,
      'levels': probeLevelsDbfs,
      'validHarmonics': {for (final f in probeFrequencies) '$f': validHarmonics(f)},
      'probeSha256': {for (final e in probes.entries) e.key: sha256.convert(e.value.buffer.asUint8List()).toString()},
      'probes': <String, Object?>{},
      'offsets': <String, Object?>{},
    };

    const loader = FileEvaluationSignalLoader(_read);
    final signals = {
      for (final role in [EvaluationRole.rhythm, EvaluationRole.lead]) role: await loader.prepare(EvaluationSignalRegistry.forRole(role)!),
    };
    const extractor = StftFeatureExtractor();
    final analyzer = NamInferenceAnalyzer(createEngine: engine);

    for (final n in nams) {
      final id = n['id']! as String;
      final path = n['path']! as String;
      final perNam = <String, Object?>{};
      (raw['probes']! as Map)[id] = perNam;
      for (final f in probeFrequencies) {
        for (final l in probeLevelsDbfs) {
          final eng = engine(); // fresh load per probe: no state carried over
          try {
            eng.load(path, sampleRate: probeSampleRate.toDouble());
            final out = eng.process(probes['$f/$l']!);
            final r = analyzers[f]!.analyze(out);
            perNam['$f/$l'] = {
              'fundamental': r.fundamental,
              'harmonics': {for (final e in r.harmonics.entries) '${e.key}': e.value},
              'dc': r.dc,
              'rms': r.rms,
              'peak': r.peak,
              'crest': r.crest,
              'residualRms': r.residualRms,
              'thd': r.thd,
              'thdPlusN': r.thdPlusN,
              'odd': r.oddEnergy,
              'even': r.evenEnergy,
              'expectedRate': eng.expectedSampleRate,
            };
          } finally {
            eng.dispose();
          }
        }
      }

      final perOffset = <String, Object?>{};
      (raw['offsets']! as Map)[id] = perOffset;
      for (final e in signals.entries) {
        final eng = engine();
        try {
          eng.load(path, sampleRate: probeSampleRate.toDouble());
          final input = e.value.samples;
          final output = analyzer.runModel(eng, input);
          for (final o in _offsets) {
            final f = extractor.extract(input: Float32List.sublistView(input, o), output: Float32List.sublistView(output, o));
            (perOffset['${e.key.name}/$o'] = <String, Object?>{})['tone'] = f.tone;
          }
        } finally {
          eng.dispose();
        }
      }
    }
    raw['analysisVersion'] = toneAnalysisVersion;
    final dir = Directory('tool/tonematch_saturation_gate/results')..createSync(recursive: true);
    File('${dir.path}/raw.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(raw));
  }, skip: run ? false : 'set WYRMTONE_RUN_SAT_GATE=1', timeout: const Timeout(Duration(minutes: 40)));
}

Future<Uint8List> _read(String p) => File(p).readAsBytes();
