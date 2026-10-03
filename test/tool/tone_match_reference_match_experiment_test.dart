@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/services/nam_inference_engine.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/evaluation_signal_loader.dart';
import 'package:wyrmtone/tonematch/evaluation_signal_t15.dart';
import 'package:wyrmtone/tonematch/stft_feature_extractor.dart';

import '../../tool/tonematch_gate/gate_dsp.dart';
import '../../tool/tonematch_reference_match/spike.dart';

/// Reference Tone Match spike, gate A (digital). Runs only with WYRMTONE_RUN_REFMATCH=1; writes
/// tool/tonematch_reference_match/results/results.json. Research only, see spike.dart.
const _dll = 'native/nam_bridge/build/wyrmtone_nam.dll';
const _desk = 'D:/Desktop 3d sachen/Desktop/AMP Presets';

// name -> (path, category by NAM NAME ONLY, pre-registered: clean / crunch / highgain / '' = unlabeled)
const _extra = <String, (String, String)>{
  'MkV-Clean': (
    '$_desk/Boogie Mark V - Rhythm, Lead and Clean/Clean.nam',
    'clean',
  ),
  'MkV-Rhythm': ('$_desk/Boogie Mark V - Rhythm, Lead and Clean/Rythm.nam', ''),
  'MkV-Lead': ('$_desk/Boogie Mark V - Rhythm, Lead and Clean/Lead.nam', ''),
  'FenderSR': (
    'D:/Desktop 3d sachen/Desktop/Fender Super Reverb 1977/Fender Super Reverb_ EQ Flat, Volume 3, sm57.nam',
    'clean',
  ),
};
const _category = {
  '01': 'clean',
  '02': 'crunch',
  '03': 'crunch',
  '04': 'highgain',
  '05': 'highgain',
  '06': 'highgain',
  '07': 'highgain',
  '08': 'highgain',
  '09': 'highgain',
  '10': '',
};

Float32List _render(NamInferenceEngine e, Float32List input) {
  const chunk = 48000;
  final out = Float32List(input.length);
  for (var s = 0; s < input.length; s += chunk) {
    final end = s + chunk < input.length ? s + chunk : input.length;
    out.setRange(s, end, e.process(Float32List.sublistView(input, s, end)));
  }
  return out;
}

void main() {
  final run = Platform.environment['WYRMTONE_RUN_REFMATCH'] == '1';
  test(
    'reference match gate A (A1 same performance, A2-excerpt disjoint halves)',
    () async {
      final ten = (jsonDecode(
        File('tool/tonematch_gate/ten_nam_set.json').readAsStringSync(),
      ) as List).cast<Map<String, Object?>>();
      final nams = <String, ({String path, String cat, String name})>{
        for (final n in ten)
          n['id']! as String: (
            path: n['path']! as String,
            cat: _category[n['id']] ?? '',
            name: (n['path']! as String).split(RegExp(r'[\\/]')).last,
          ),
        for (final e in _extra.entries)
          e.key: (
            path: e.value.$1,
            cat: e.value.$2,
            name: e.value.$1.split('/').last,
          ),
      };
      const loader = FileEvaluationSignalLoader(_read);
      const extractor = StftFeatureExtractor();

      // signals per role: A1 = the production derivation; A2 = disjoint halves of the active span
      final signals =
          <String, ({Float32List a1, Float32List half1, Float32List half2})>{};
      for (final d in EvaluationSignalRegistry.bundled) {
        final di = (await loader.prepare(d)).samples;
        final clean = d.role == EvaluationRole.clean;
        final (a, b) = activeSpan(di);
        final mid = (a + b) ~/ 2;
        Float32List derive(Float32List x) =>
            clean ? x : EvaluationSignalT15.derive(x);
        signals[d.role.name] = (
          a1: derive(di),
          half1: derive(Float32List.sublistView(di, clean ? 0 : a, mid)),
          half2: derive(
            Float32List.sublistView(di, mid, clean ? di.length : b),
          ),
        );
      }

      // render every usable NAM on every distinct signal
      final feats =
          <
            String,
            Map<String, ({RefFeatures di, RefFeatures blind})>
          >{}; // key: role|a1/h1/h2 -> nam -> feats
      final skipped = <String, String>{};
      for (final entry in nams.entries) {
        final engine = NamInferenceEngine.create(_dll);
        try {
          engine.load(
            entry.value.path,
            sampleRate: evaluationSampleRate.toDouble(),
          );
          final expected = engine.expectedSampleRate;
          if (expected != 0 && expected != evaluationSampleRate)
            throw StateError('expects $expected Hz');
          for (final role in signals.entries) {
            for (final v in {
              'a1': role.value.a1,
              'h1': role.value.half1,
              'h2': role.value.half2,
            }.entries) {
              final out = _render(engine, v.value);
              final key = '${role.key}|${v.key}';
              // DI-gated = production extraction; blind = gate decided from the output itself (no DI available)
              (feats[key] ??= {})[entry.key] = (
                di: RefFeatures.from(
                  entry.key,
                  extractor.extract(input: v.value, output: out),
                ),
                blind: RefFeatures.from(
                  entry.key,
                  extractor.extract(input: out, output: out),
                ),
              );
            }
          }
        } on Object catch (e) {
          skipped[entry.key] = '$e';
        } finally {
          engine.dispose();
        }
      }
      final usable = nams.keys.where((k) => !skipped.containsKey(k)).toList();

      final results = <String, Object?>{
        'usedNams': {
          for (final k in usable)
            k: {'file': nams[k]!.name, 'category': nams[k]!.cat},
        },
        'skipped': skipped,
        'cases': <Map<String, Object?>>[],
      };
      for (final role in signals.keys) {
        for (final (gate, refKey, candKey) in [
          ('A1', '$role|a1', '$role|a1'),
          ('A2x', '$role|h1', '$role|h2'),
        ]) {
          for (final refMode in ['di', 'blind']) {
            for (final method in ['D1', 'D2', 'D3']) {
              for (final loo in [false, true]) {
                for (final ref in usable) {
                  final reference = refMode == 'di'
                      ? feats[refKey]![ref]!.di
                      : feats[refKey]![ref]!.blind;
                  // candidates are always analysed the production way (DI-gated)
                  final cands = [
                    for (final k in usable)
                      if (!(loo && k == ref)) feats[candKey]![k]!.di,
                  ];
                  final ranked = rank(reference, cands, method);
                  results['cases']! as List<Map<String, Object?>>..add({
                    'role': role,
                    'gate': gate,
                    'refMode': refMode,
                    'method': method,
                    'loo': loo,
                    'ref': ref,
                    'refCat': nams[ref]!.cat,
                    'rank': loo
                        ? null
                        : ranked.indexWhere((r) => r.id == ref) + 1,
                    'top3': [
                      for (final r in ranked.take(3))
                        {'id': r.id, 'd': r.distance, 'cat': nams[r.id]!.cat},
                    ],
                    'margin12': ranked.length > 1
                        ? ranked[1].distance - ranked[0].distance
                        : null,
                  });
                }
              }
            }
          }
        }
      }
      results['features'] = {
        for (final e in feats.entries)
          e.key: {for (final n in e.value.entries) n.key: n.value.di.toJson()},
      };
      Directory('tool/tonematch_reference_match/results')
          .createSync(recursive: true);
      File(
        'tool/tonematch_reference_match/results/results.json',
      ).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(results));
      expect(usable.length, greaterThanOrEqualTo(10));
    },
    skip: run ? false : 'set WYRMTONE_RUN_REFMATCH=1',
    timeout: const Timeout(Duration(minutes: 40)),
  );
}

Future<Uint8List> _read(String p) => File(p).readAsBytes();
