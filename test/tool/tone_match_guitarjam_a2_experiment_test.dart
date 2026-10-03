@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/services/nam_inference_engine.dart';
import 'package:wyrmtone/tonematch/evaluation_resampler.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/stft_feature_extractor.dart';

import '../../tool/tonematch_reference_match/spike.dart';

/// GuitarJam A2 (independent performances) for the Reference Tone Match spike. Research only; runs with
/// WYRMTONE_RUN_GJA2=1 (WYRMTONE_GJ_CLIPS limits the number of clips for the timing run). The clip list is
/// frozen in tool/tonematch_reference_match/guitarjam_selection.json BEFORE any result is looked at.
/// Renders are cached in results/guitarjam_features_cache.json (research artefact, not a product cache).
const _dll = 'native/nam_bridge/build/wyrmtone_nam.dll';
const _dir = 'tool/tonematch_reference_match';

const _desk = 'D:/Desktop 3d sachen/Desktop/AMP Presets';
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

Float32List _readMono16(String path) {
  final b = File(path).readAsBytesSync();
  final d = ByteData.sublistView(b);
  var o = 12;
  while (o + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(o, o + 4));
    final size = d.getUint32(o + 4, Endian.little);
    if (id == 'data') {
      final n = size ~/ 2;
      return Float32List.fromList([
        for (var i = 0; i < n; i++)
          d.getInt16(o + 8 + 2 * i, Endian.little) / 32768.0,
      ]);
    }
    o += 8 + size + (size & 1);
  }
  throw StateError('no data chunk in $path');
}

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
  final run = Platform.environment['WYRMTONE_RUN_GJA2'] == '1';
  test(
    'guitarjam A2 renderings and rankings',
    () async {
      final limit =
          int.tryParse(Platform.environment['WYRMTONE_GJ_CLIPS'] ?? '') ?? 30;
      final sel = jsonDecode(
        File('$_dir/guitarjam_selection.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final clips = [
        for (final c in (sel['clips']! as List).cast<Map<String, Object?>>())
          c['file']! as String,
      ].take(limit).toList();
      for (final c in (sel['clips']! as List).cast<Map<String, Object?>>().take(
        limit,
      )) {
        expect(
          sha256
              .convert(
                File('$_dir/data/guitarjam/${c['file']}').readAsBytesSync(),
              )
              .toString(),
          c['sha256'],
          reason: 'clip changed: ${c['file']}',
        );
      }
      final ten = (jsonDecode(
        File('tool/tonematch_gate/ten_nam_set.json').readAsStringSync(),
      ) as List).cast<Map<String, Object?>>();
      final nams =
          <String, ({String path, String cat, String name, String sha})>{
            for (final n in ten)
              n['id']! as String: (
                path: n['path']! as String,
                cat: _category[n['id']] ?? '',
                name: (n['path']! as String).split(RegExp(r'[\\/]')).last,
                sha: n['sha']! as String,
              ),
            for (final e in _extra.entries)
              e.key: (
                path: e.value.$1,
                cat: e.value.$2,
                name: e.value.$1.split('/').last,
                sha: sha256
                    .convert(File(e.value.$1).readAsBytesSync())
                    .toString(),
              ),
          };

      final cacheFile = File('$_dir/results/guitarjam_features_cache.json');
      final cache = cacheFile.existsSync()
          ? (jsonDecode(cacheFile.readAsStringSync()) as Map<String, Object?>)
                .cast<String, Object?>()
          : <String, Object?>{};
      const extractor = StftFeatureExtractor();
      final di = <String, Float32List>{
        for (final c in clips)
          c: EvaluationResampler.to48k(_readMono16('$_dir/data/guitarjam/$c')),
      };
      final clipInfo = <String, Object?>{
        for (final c in clips)
          c: () {
            final x = di[c]!;
            var s = 0.0, pk = 0.0;
            for (final v in x) {
              s += v * v;
              pk = math.max(pk, v.abs());
            }
            return {
              'seconds': x.length / evaluationSampleRate,
              'rmsDb': 10 * math.log(s / x.length + 1e-20) / math.ln10,
              'peakDb': 20 * math.log(pk + 1e-20) / math.ln10,
            };
          }(),
      };

      final watch = Stopwatch()..start();
      var rendered = 0;
      final skipped = <String, String>{};
      for (final n in nams.entries) {
        final todo = [
          for (final c in clips)
            if (!cache.containsKey('${n.key}|$c')) c,
        ];
        if (todo.isEmpty) continue;
        final engine = NamInferenceEngine.create(_dll);
        try {
          engine.load(
            n.value.path,
            sampleRate: evaluationSampleRate.toDouble(),
          );
          final expected = engine.expectedSampleRate;
          if (expected != 0 && expected != evaluationSampleRate)
            throw StateError('expects $expected Hz');
          for (final c in todo) {
            final out = _render(engine, di[c]!);
            cache['${n.key}|$c'] = {
              'di': RefFeatures.from(
                n.key,
                extractor.extract(input: di[c]!, output: out),
              ).toJson(),
              'blind': RefFeatures.from(
                n.key,
                extractor.extract(input: out, output: out),
              ).toJson(),
            };
            rendered++;
          }
        } on Object catch (e) {
          skipped[n.key] = '$e';
        } finally {
          engine.dispose();
        }
      }
      watch.stop();
      Directory('$_dir/results').createSync(recursive: true);
      cacheFile.writeAsStringSync(jsonEncode(cache));
      stdout.writeln(
        'GJ_RENDERINGS_THIS_RUN=$rendered ELAPSED_S=${watch.elapsedMilliseconds / 1000} SKIPPED=$skipped',
      );
      if (limit < 30) return; // timing run only

      // pairs, frozen: reference clip i against candidate clips (i+5), (i+11), (i+17) modulo 30
      final usable = nams.keys.where((k) => !skipped.containsKey(k)).toList();
      RefFeatures f(String nam, String clip, String mode) {
        final j = ((cache['$nam|$clip']! as Map)[mode]! as Map)
            .cast<String, num>();
        return RefFeatures(
          nam,
          j['lnCentroid']!.toDouble(),
          j['lnRolloff']!.toDouble(),
          j['midLogit']!.toDouble(),
          j['crestDb']!.toDouble(),
        );
      }

      final pairs = <List<int>>[
        for (var i = 0; i < clips.length; i++)
          for (final s in [5, 11, 17]) [i, (i + s) % clips.length],
      ];
      final cases = <Map<String, Object?>>[];
      for (final p in pairs) {
        final rc = clips[p[0]], cc = clips[p[1]];
        for (final mode in ['blind', 'di']) {
          for (final method in ['D1', 'D2', 'D3']) {
            for (final loo in [false, true]) {
              for (final ref in usable) {
                final reference = f(ref, rc, mode);
                final cands = [
                  for (final k in usable)
                    if (!(loo && k == ref)) f(k, cc, 'di'),
                ];
                final ranked = rank(reference, cands, method);
                cases.add({
                  'rc': p[0],
                  'cc': p[1],
                  'mode': mode,
                  'method': method,
                  'loo': loo,
                  'ref': ref,
                  'rank': loo
                      ? null
                      : ranked.indexWhere((r) => r.id == ref) + 1,
                  'top3': [for (final r in ranked.take(3)) r.id],
                });
              }
            }
          }
        }
      }
      final features = {
        for (final nam in usable)
          nam: {
            for (final c in clips)
              c: ((cache['$nam|$c']! as Map)['di']! as Map),
          },
      };
      File('$_dir/results/guitarjam_a2_raw.json').writeAsStringSync(
        jsonEncode({
          'clips': clips,
          'clipInfo': clipInfo,
          'nams': {
            for (final k in usable)
              k: {
                'file': nams[k]!.name,
                'category': nams[k]!.cat,
                'sha256': nams[k]!.sha,
              },
          },
          'skipped': skipped,
          'pairs': pairs,
          'cases': cases,
          'features': features,
        }),
      );
      expect(usable.length, 14);
    },
    skip: run ? false : 'set WYRMTONE_RUN_GJA2=1',
    timeout: const Timeout(Duration(hours: 3)),
  );
}
