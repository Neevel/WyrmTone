@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/services/nam_inference_engine.dart';
import 'package:wyrmtone/tonematch/analysis_interfaces.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/evaluation_signal_loader.dart';
import 'package:wyrmtone/tonematch/nam_inference_analyzer.dart';
import 'package:wyrmtone/tonematch/stft_feature_extractor.dart';
import 'package:wyrmtone/tonematch/tone_features.dart';
import 'package:wyrmtone/tonematch/tone_match_cache.dart';

import '../../tool/tonematch_gate/gate_dsp.dart';

/// Validation/ablation gate experiment (AnalysisVersion 1 frozen). Collects raw data only; the
/// statistics are computed by tool/tonematch_gate/analyze.py. Runs only with
/// WYRMTONE_RUN_GATE=1 so it never joins a normal test run. Writes to tool/tonematch_gate/results/.
const _dll = 'native/nam_bridge/build/wyrmtone_nam.dll';

void main() {
  final run = Platform.environment['WYRMTONE_RUN_GATE'] == '1';
  final setFile = File('tool/tonematch_gate/ten_nam_set.json');
  test('gate experiment: 10 NAMs x signals x variants', () async {
    final nams = (jsonDecode(setFile.readAsStringSync()) as List).cast<Map<String, Object?>>();
    for (final n in nams) {
      expect(sha256.convert(File(n['path']! as String).readAsBytesSync()).toString(), n['sha'], reason: 'NAM changed: ${n['id']}');
    }
    NamInferenceEngine engine() => NamInferenceEngine.create(_dll);
    const loader = FileEvaluationSignalLoader(_read);
    const extractor = StftFeatureExtractor();
    final analyzer = NamInferenceAnalyzer(createEngine: engine);

    final prepared = {for (final d in EvaluationSignalRegistry.bundled) d.role: await loader.prepare(d)};
    final variantsByRole = <EvaluationRole, List<GateVariant>>{
      EvaluationRole.rhythm: buildVariants(prepared[EvaluationRole.rhythm]!.samples, contentSeconds: [15, 10, 5]),
      EvaluationRole.lead: buildVariants(prepared[EvaluationRole.lead]!.samples, contentSeconds: [15, 10, 5]),
      EvaluationRole.clean: buildVariants(prepared[EvaluationRole.clean]!.samples, contentSeconds: [10, 5]),
    };

    final raw = <String, Object?>{
      'analysisVersion': toneAnalysisVersion,
      'signals': {
        for (final e in variantsByRole.entries)
          e.key.name: {
            for (final v in e.value)
              v.id: {
                'seconds': v.samples.length / evaluationSampleRate,
                'contentSeconds': v.contentSeconds,
                'derivedSha256': sha256.convert(v.samples.buffer.asUint8List(v.samples.offsetInBytes, v.samples.lengthInBytes)).toString(),
              },
          },
      },
      'runs': <String, Object?>{},
      'probe': <String, Object?>{},
    };

    final probes = {-30.0: probeNoise(-30), -20.0: probeNoise(-20)};
    for (final n in nams) {
      final id = n['id']! as String;
      final path = n['path']! as String;
      final perNam = <String, Object?>{};
      (raw['runs']! as Map)[id] = perNam;
      for (final e in variantsByRole.entries) {
        for (final v in e.value) {
          final eng = engine();
          try {
            final load = Stopwatch()..start();
            eng.load(path, sampleRate: evaluationSampleRate.toDouble());
            load.stop();
            final inf = Stopwatch()..start();
            final out = analyzer.runModel(eng, v.samples);
            inf.stop();
            final ex = Stopwatch()..start();
            final f = extractor.extract(input: v.samples, output: out);
            ex.stop();
            final entry = <String, Object?>{
              'level': f.level,
              'tone': f.tone,
              'ms': {'load': load.elapsedMilliseconds, 'inference': inf.elapsedMilliseconds, 'extraction': ex.elapsedMilliseconds},
            };
            if (v.id == 'FULL') {
              entry['alt'] = altMetrics(v.samples, out);
              entry['ltas'] = ltasBands(out);
            }
            perNam['${e.key.name}/${v.id}'] = entry;
          } finally {
            eng.dispose();
          }
        }
      }
      final probe = <String, Object?>{};
      for (final p in probes.entries) {
        final eng = engine();
        try {
          eng.load(path, sampleRate: evaluationSampleRate.toDouble());
          probe['tilt${p.key.toInt()}'] = tiltDb(eng.process(p.value)) - tiltDb(p.value);
        } finally {
          eng.dispose();
        }
      }
      (raw['probe']! as Map)[id] = probe;
    }

    // Cache effect: cold vs warm for FULL and T10, RHYTHM and LEAD, all ten NAMs (wall time).
    final cacheReport = <String, Object?>{};
    for (final variantId in ['FULL', 'T10']) {
      final cache = InMemoryToneMatchCache();
      final cached = CachedNamAnalyzer(analyzer, cache, analysisVersion: toneAnalysisVersion);
      Future<int> pass() async {
        final w = Stopwatch()..start();
        for (final n in nams) {
          for (final role in [EvaluationRole.rhythm, EvaluationRole.lead]) {
            final v = variantsByRole[role]!.firstWhere((x) => x.id == variantId);
            final d = EvaluationSignalRegistry.forRole(role)!;
            final derived = EvaluationSignalDescriptor.fromJson({
              ...d.toJson(),
              'id': variantId == 'FULL' ? d.id : '${d.id}#$variantId',
              'sha256': sha256.convert(v.samples.buffer.asUint8List(v.samples.offsetInBytes, v.samples.lengthInBytes)).toString(),
            });
            await cached.analyze(
              NamAnalysisSource(path: n['path']! as String, sha256: n['sha']! as String),
              PreparedEvaluationSignal(descriptor: derived, samples: v.samples, decodeMs: 0, resampleMs: 0),
            );
          }
        }
        return w.elapsedMilliseconds;
      }

      final cold = await pass();
      final warm = await pass();
      cacheReport[variantId] = {'coldMs': cold, 'warmMs': warm, 'hits': cached.hits, 'misses': cached.misses, 'analyses': 20};
    }
    raw['cache'] = cacheReport;

    final dir = Directory('tool/tonematch_gate/results')..createSync(recursive: true);
    File('${dir.path}/raw.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(raw));
  }, skip: run ? false : 'set WYRMTONE_RUN_GATE=1', timeout: const Timeout(Duration(minutes: 40)));
}

Future<Uint8List> _read(String p) => File(p).readAsBytes();
