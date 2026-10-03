@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/services/nam_inference_engine.dart';
import 'package:wyrmtone/tonematch/analysis_interfaces.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/evaluation_signal_loader.dart';
import 'package:wyrmtone/tonematch/nam_inference_analyzer.dart';
import 'package:wyrmtone/tonematch/tone_features.dart';
import 'package:wyrmtone/tonematch/tone_match_cache.dart';
import 'package:wyrmtone/tonematch/tone_match_models.dart';

/// Slice 2 on REAL NAM inference with the real WyrmTone DI evaluation recordings (Windows dev
/// bridge, like the other tests in test/tool). Cases without their external evidence (native
/// DLL, local .nam files) are skipped, never reported as passed.
///
/// The three NAMs were fixed by name BEFORE any analysis ran (clean / crunch / modern high gain)
/// and are not changed to obtain a result.
const _dll = 'native/nam_bridge/build/wyrmtone_nam.dll';
const _root = r'D:\Desktop 3d sachen\Desktop\AMP Presets';
final _nams = <String, String>{
  'CLEAN  Fender Pano-Verb Clean2': '$_root\\Fender Pano-Verb\\FNDR PANO Clean2 BAL 6V6 CAB.nam',
  'CRUNCH Marshall JVM410 crunch': '$_root\\Marshall JVM410H with c83 mod\\JVM410_crunch_green_sd1.nam',
  'HIGHGAIN Bugera 6262': '$_root\\Bugera 6262 1 Hit Quitter.nam',
};
const _goldenPath = 'test/golden/tonematch_slice2_golden.json';

NamInferenceEngine _engine() => NamInferenceEngine.create(_dll);

void main() {
  final available = File(_dll).existsSync() && _nams.values.every((p) => File(p).existsSync());
  final skip = available ? false : 'native DLL or local NAM files not available';

  test('Slice 2: real NAMs x real DI evaluation signals', () async {
    const loader = FileEvaluationSignalLoader(_readFile);
    final signals = <PreparedEvaluationSignal>[
      for (final d in EvaluationSignalRegistry.bundled) await loader.prepare(d),
    ];
    final report = <String, Object?>{'signals': <String, Object?>{}, 'nams': <String, Object?>{}, 'analyses': <String, Object?>{}};
    for (final s in signals) {
      (report['signals']! as Map)[s.descriptor.id] = {
        'originalSha256': s.descriptor.sha256,
        'derivedPcmSha256': sha256.convert(s.samples.buffer.asUint8List()).toString(),
        'samples48k': s.samples.length,
        'decodeMs': s.decodeMs,
        'resampleMs': s.resampleMs,
      };
    }

    final analyzer = NamInferenceAnalyzer(createEngine: _engine);
    final byNam = <String, Map<String, NamAnalysis>>{};
    for (final entry in _nams.entries) {
      final sha = sha256.convert(File(entry.value).readAsBytesSync()).toString();
      final src = NamAnalysisSource(path: entry.value, sha256: sha);
      (report['nams']! as Map)[entry.key] = {'sha256': sha, 'bytes': File(entry.value).lengthSync()};
      for (final s in signals) {
        final a = await analyzer.analyze(src, s);
        final b = await analyzer.analyze(src, s); // determinism: fresh engine, same inputs
        for (final k in {...a.features.tone.keys, ...b.features.tone.keys}) {
          expect(b.features.tone[k], isNotNull, reason: '${entry.key} ${s.descriptor.id} $k');
          expect(b.features.tone[k]!, closeTo(a.features.tone[k]!, 1e-9 * (a.features.tone[k]!.abs() + 1)), reason: '${entry.key} ${s.descriptor.id} $k');
        }
        expect(b.features.level, a.features.level);
        byNam.putIfAbsent(entry.key, () => {})[s.descriptor.id] = a;
        (report['analyses']! as Map)['${entry.key} | ${s.descriptor.id}'] = {
          'level': a.features.level,
          'tone': a.features.tone,
          'timingsMs': {'namLoad': a.timings.namLoadMs, 'inference': a.timings.inferenceMs, 'extraction': a.timings.extractionMs, 'total': a.timings.totalMs},
        };
      }
    }

    // Differentiation: the three NAMs must be separated on several independent tone features,
    // by more than the (zero) repeat variation and by a stated margin.
    final names = _nams.keys.toList();
    final differentiation = <String, Object?>{};
    for (final s in signals) {
      final id = s.descriptor.id;
      var pairsOk = 0;
      for (var i = 0; i < names.length; i++) {
        for (var j = i + 1; j < names.length; j++) {
          final a = byNam[names[i]]![id]!.features.tone, b = byNam[names[j]]![id]!.features.tone;
          final separated = [
            (a[ToneFeatureIds.saturationComposite]! - b[ToneFeatureIds.saturationComposite]!).abs() > 0.05,
            (a[ToneFeatureIds.centroidHz]! - b[ToneFeatureIds.centroidHz]!).abs() / math.max(a[ToneFeatureIds.centroidHz]!, b[ToneFeatureIds.centroidHz]!) > 0.05,
            (a[ToneFeatureIds.crestDb]! - b[ToneFeatureIds.crestDb]!).abs() > 1.0,
            [for (final band in GuitarBand.values) (a[ToneFeatureIds.band(band)]! - b[ToneFeatureIds.band(band)]!).abs()].reduce(math.max) > 0.05,
          ].where((v) => v).length;
          if (separated >= 2) pairsOk++;
        }
      }
      differentiation[id] = {'pairsSeparatedOn>=2Features': pairsOk, 'pairs': 3};
      expect(pairsOk, 3, reason: 'all NAM pairs must be separable on $id');
    }
    report['differentiation'] = differentiation;

    // Sanity of the measurement (not a quality claim): the clean NAM is less saturated than the
    // modern high-gain NAM on the rhythm signal.
    final clean = byNam[names[0]]!['wyrmtone-rhythm-v1']!.features.tone[ToneFeatureIds.saturationComposite]!;
    final high = byNam[names[2]]!['wyrmtone-rhythm-v1']!.features.tone[ToneFeatureIds.saturationComposite]!;
    expect(clean, lessThan(high));

    Directory('build').createSync(recursive: true);
    File('build/tonematch_slice2_report.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(report));

    final golden = File(_goldenPath);
    if (Platform.environment['WYRMTONE_UPDATE_GOLDEN'] == '1') {
      golden.parent.createSync(recursive: true);
      golden.writeAsStringSync(const JsonEncoder.withIndent(' ').convert({'signals': report['signals'], 'analyses': {
        for (final e in (report['analyses']! as Map).entries) e.key: {'tone': (e.value as Map)['tone'], 'level': (e.value as Map)['level']},
      }}));
    } else if (golden.existsSync()) {
      final g = jsonDecode(golden.readAsStringSync()) as Map<String, Object?>;
      for (final e in (g['analyses']! as Map).entries) {
        final now = (report['analyses']! as Map)[e.key] as Map;
        for (final group in ['tone', 'level']) {
          for (final f in ((e.value as Map)[group] as Map).entries) {
            final want = (f.value as num).toDouble(), got = ((now[group] as Map)[f.key] as num).toDouble();
            expect(got, closeTo(want, 1e-4 * (want.abs() + 1)), reason: '${e.key} $group ${f.key}');
          }
        }
      }
      for (final e in (g['signals']! as Map).entries) {
        expect(((report['signals']! as Map)[e.key] as Map)['samples48k'], (e.value as Map)['samples48k']);
        expect(((report['signals']! as Map)[e.key] as Map)['derivedPcmSha256'], (e.value as Map)['derivedPcmSha256']);
      }
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 20)));

  test('chunked and whole-signal inference agree', () async {
    const loader = FileEvaluationSignalLoader(_readFile);
    final signal = await loader.prepare(EvaluationSignalRegistry.forRole(EvaluationRole.lead)!);
    for (final entry in _nams.entries) {
      Float32List run(int chunk) {
        final analyzer = NamInferenceAnalyzer(createEngine: _engine, chunkFrames: chunk);
        final engine = _engine();
        try {
          engine.load(entry.value);
          return analyzer.runModel(engine, signal.samples);
        } finally {
          engine.dispose();
        }
      }

      final whole = run(0), chunked = run(48000), small = run(4096);
      var worst = 0.0;
      for (var i = 0; i < whole.length; i++) {
        worst = math.max(worst, math.max((whole[i] - chunked[i]).abs(), (whole[i] - small[i]).abs()));
      }
      expect(worst, lessThan(1e-5), reason: entry.key);
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 20)));

  test('cancel between chunks discards the result and releases the engine; cache hit skips inference', () async {
    const loader = FileEvaluationSignalLoader(_readFile);
    final signal = await loader.prepare(EvaluationSignalRegistry.forRole(EvaluationRole.clean)!);
    final path = _nams.values.first;
    final src = NamAnalysisSource(path: path, sha256: sha256.convert(File(path).readAsBytesSync()).toString());
    var created = 0;
    final inner = NamInferenceAnalyzer(createEngine: () {
      created++;
      return _engine();
    });
    var calls = 0;
    await expectLater(inner.analyze(src, signal, isCancelled: () => ++calls > 3), throwsA(isA<AnalysisCancelled>()));
    final cached = CachedNamAnalyzer(inner, InMemoryToneMatchCache(), analysisVersion: toneAnalysisVersion);
    final first = await cached.analyze(src, signal);
    final second = await cached.analyze(src, signal);
    expect((cached.hits, cached.misses), (1, 1));
    expect(second.features.tone, first.features.tone);
    expect(created, 2); // cancelled run + one real run; the cache hit created no engine
  }, skip: skip, timeout: const Timeout(Duration(minutes: 10)));
}

Future<Uint8List> _readFile(String path) => File(path).readAsBytes();
