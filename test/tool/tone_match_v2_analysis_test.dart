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

/// AnalysisVersion 2 on the REAL evaluation WAVs and the same three NAMs as the V1 golden.
/// The V1 golden (test/golden/tonematch_slice2_golden.json) is only READ here, never written.
/// EXPERIMENTAL 4-phase prototype (REJECTED, docs section 9): its golden is the file named
/// ...experimental_4phase_rejected.json (WYRMTONE_UPDATE_GOLDEN_V2=1 would write it).
const _dll = 'native/nam_bridge/build/wyrmtone_nam.dll';
const _root = r'D:\Desktop 3d sachen\Desktop\AMP Presets';
final _nams = <String, String>{
  'CLEAN  Fender Pano-Verb Clean2': '$_root\\Fender Pano-Verb\\FNDR PANO Clean2 BAL 6V6 CAB.nam',
  'CRUNCH Marshall JVM410 crunch': '$_root\\Marshall JVM410H with c83 mod\\JVM410_crunch_green_sd1.nam',
  'HIGHGAIN Bugera 6262': '$_root\\Bugera 6262 1 Hit Quitter.nam',
};
const _v1Golden = 'test/golden/tonematch_slice2_golden.json';
const _v2Golden = 'test/golden/tonematch_slice2_golden_experimental_4phase_rejected.json';
const _changed = {'tone.attackMs', 'tone.decayDbPerSec', 'tone.transientPeakToBodyDb', 'tone.onsetCount'};

NamInferenceEngine _engine() => NamInferenceEngine.create(_dll);

void main() {
  final available = File(_dll).existsSync() && _nams.values.every((p) => File(p).existsSync());
  final skip = available ? false : 'native DLL or local NAM files not available';

  test('V2 on real NAMs x real DI signals: deterministic, V2 golden, only envelope fields differ from the V1 golden', () async {
    const loader = FileEvaluationSignalLoader(_read);
    final signals = [for (final d in EvaluationSignalRegistry.bundled) await loader.prepare(d)];
    final analyzer = NamInferenceAnalyzer(createEngine: _engine, extractor: const StftFeatureExtractor(analysisVersion: 2));
    expect(analyzer.analysisVersion, 2);

    final analyses = <String, Object?>{};
    for (final e in _nams.entries) {
      final src = NamAnalysisSource(path: e.value, sha256: sha256.convert(File(e.value).readAsBytesSync()).toString());
      for (final s in signals) {
        final a = await analyzer.analyze(src, s);
        final b = await analyzer.analyze(src, s);
        expect(a.key.analysisVersion, 2);
        for (final k in a.features.tone.keys) {
          expect(b.features.tone[k]!, closeTo(a.features.tone[k]!, 1e-9 * (a.features.tone[k]!.abs() + 1)), reason: '${e.key} ${s.descriptor.id} $k');
        }
        analyses['${e.key} | ${s.descriptor.id}'] = {'tone': a.features.tone, 'level': a.features.level};
      }
    }
    final current = {
      'analysisVersion': 2,
      'signals': {
        for (final s in signals)
          s.descriptor.id: {
            'originalSha256': s.descriptor.sha256,
            'derivedPcmSha256': sha256.convert(s.samples.buffer.asUint8List()).toString(),
            'samples48k': s.samples.length,
          },
      },
      'analyses': analyses,
    };

    // Compared to the (read-only) V1 golden: every non-envelope value identical, changed fields listed.
    final v1 = jsonDecode(File(_v1Golden).readAsStringSync()) as Map<String, Object?>;
    final changedFields = <String>{};
    for (final e in (v1['analyses']! as Map).entries) {
      final now = analyses[e.key]! as Map;
      for (final group in ['tone', 'level']) {
        for (final f in ((e.value as Map)[group] as Map).entries) {
          final want = (f.value as num).toDouble(), got = ((now[group] as Map)[f.key] as num).toDouble();
          if (_changed.contains(f.key)) {
            if ((got - want).abs() > 1e-9 * (want.abs() + 1)) changedFields.add(f.key as String);
          } else {
            expect(got, closeTo(want, 1e-9 * (want.abs() + 1)), reason: 'unaffected field changed: ${e.key} $group ${f.key}');
          }
        }
      }
    }
    expect(changedFields.difference(_changed), isEmpty);
    // ignore: avoid_print
    print('fields that differ from V1: ${(changedFields.toList()..sort()).join(', ')}');

    final golden = File(_v2Golden);
    if (Platform.environment['WYRMTONE_UPDATE_GOLDEN_V2'] == '1') {
      golden.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(current));
    } else {
      expect(golden.existsSync(), isTrue, reason: 'V2 golden missing');
      final g = jsonDecode(golden.readAsStringSync()) as Map<String, Object?>;
      expect(g['analysisVersion'], 2);
      for (final e in (g['analyses']! as Map).entries) {
        final now = analyses[e.key]! as Map;
        for (final group in ['tone', 'level']) {
          for (final f in ((e.value as Map)[group] as Map).entries) {
            final want = (f.value as num).toDouble(), got = ((now[group] as Map)[f.key] as num).toDouble();
            expect(got, closeTo(want, 1e-4 * (want.abs() + 1)), reason: '${e.key} $group ${f.key}');
          }
        }
      }
      for (final e in (g['signals']! as Map).entries) {
        expect(((current['signals']! as Map)[e.key] as Map)['derivedPcmSha256'], (e.value as Map)['derivedPcmSha256']);
      }
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 20)));

  test('V1/V2 cache isolation with the real analyzers: a V1 entry is never served to V2 and stays intact', () async {
    const loader = FileEvaluationSignalLoader(_read);
    final signal = await loader.prepare(EvaluationSignalRegistry.forRole(EvaluationRole.clean)!);
    final path = _nams.values.first;
    final src = NamAnalysisSource(path: path, sha256: sha256.convert(File(path).readAsBytesSync()).toString());
    final cache = InMemoryToneMatchCache();
    final v1 = CachedNamAnalyzer(NamInferenceAnalyzer(createEngine: _engine), cache, analysisVersion: toneAnalysisVersion);
    final v2 = CachedNamAnalyzer(
      NamInferenceAnalyzer(createEngine: _engine, extractor: const StftFeatureExtractor(analysisVersion: 2)),
      cache,
      analysisVersion: toneAnalysisVersionV2,
    );
    final a1 = await v1.analyze(src, signal);
    final a2 = await v2.analyze(src, signal);
    expect((v1.misses, v2.misses, v2.hits), (1, 1, 0)); // V2 did not take V1's entry
    expect(a1.key.value, isNot(a2.key.value));
    expect(a1.features.analysisVersion, 1);
    expect(a2.features.analysisVersion, 2);
    final again1 = await v1.analyze(src, signal), again2 = await v2.analyze(src, signal);
    expect((again1.features.analysisVersion, again2.features.analysisVersion), (1, 2));
    expect((v1.hits, v2.hits), (1, 1));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 10)));
}

Future<Uint8List> _read(String p) => File(p).readAsBytes();
