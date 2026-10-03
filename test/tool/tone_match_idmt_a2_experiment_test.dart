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

/// IDMT-SMT-Guitar A2 + multi-performance signature for the Reference Tone Match spike. Research only;
/// runs with WYRMTONE_RUN_IDMT=1 (WYRMTONE_IDMT_CLIPS limits the clips for the timing run). Clips, pairs and
/// signature clip sets are frozen in tool/tonematch_reference_match/idmt_selection.json BEFORE any result.
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

/// Mono (first channel) PCM 16/24/32-bit integer or 32-bit float WAV.
Float32List _readWav(String path) {
  final b = File(path).readAsBytesSync();
  final d = ByteData.sublistView(b);
  var o = 12, fmt = 1, ch = 1, bits = 16;
  while (o + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(o, o + 4));
    final size = d.getUint32(o + 4, Endian.little);
    if (id == 'fmt ') {
      fmt = d.getUint16(o + 8, Endian.little);
      ch = d.getUint16(o + 10, Endian.little);
      bits = d.getUint16(o + 22, Endian.little);
      if (fmt == 0xFFFE) fmt = d.getUint16(o + 8 + 24, Endian.little);
    } else if (id == 'data') {
      final bytes = bits ~/ 8;
      final n = math.min(size, b.length - o - 8) ~/ (bytes * ch);
      final out = Float32List(n);
      for (var i = 0; i < n; i++) {
        final p = o + 8 + i * bytes * ch;
        out[i] = switch ((fmt, bits)) {
          (1, 16) => d.getInt16(p, Endian.little) / 32768.0,
          (1, 24) =>
            (((d.getUint8(p + 2) << 16 |
                            d.getUint8(p + 1) << 8 |
                            d.getUint8(p)) ^
                        0x800000) -
                    0x800000) /
                8388608.0,
          (1, 32) => d.getInt32(p, Endian.little) / 2147483648.0,
          (3, 32) => d.getFloat32(p, Endian.little),
          _ => throw StateError('unsupported wav format $fmt/$bits'),
        };
      }
      return out;
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

double _median(List<double> v) {
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

void main() {
  final run = Platform.environment['WYRMTONE_RUN_IDMT'] == '1';
  test(
    'idmt A2 renderings, single-performance and multi-performance rankings',
    () async {
      final limit =
          int.tryParse(Platform.environment['WYRMTONE_IDMT_CLIPS'] ?? '') ??
          1000;
      final sel = jsonDecode(
        File('$_dir/idmt_selection.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final allClips = (sel['clips']! as List).cast<Map<String, Object?>>();
      final clips = allClips.take(limit).toList();
      for (final c in clips) {
        expect(
          sha256
              .convert(File('$_dir/data/idmt/${c['id']}.wav').readAsBytesSync())
              .toString(),
          c['sha256'],
          reason: 'clip changed: ${c['id']}',
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

      final cacheFile = File('$_dir/results/idmt_features_cache.json');
      final cache = cacheFile.existsSync()
          ? (jsonDecode(cacheFile.readAsStringSync()) as Map<String, Object?>)
                .cast<String, Object?>()
          : <String, Object?>{};
      const extractor = StftFeatureExtractor();
      final di = <String, Float32List>{
        for (final c in clips)
          c['id']! as String: EvaluationResampler.to48k(
            _readWav('$_dir/data/idmt/${c['id']}.wav'),
          ),
      };
      final clipInfo = <String, Object?>{
        for (final e in di.entries)
          e.key: () {
            var s = 0.0, pk = 0.0;
            for (final v in e.value) {
              s += v * v;
              pk = math.max(pk, v.abs());
            }
            return {
              'seconds': e.value.length / evaluationSampleRate,
              'rmsDb': 10 * math.log(s / e.value.length + 1e-20) / math.ln10,
              'peakDb': 20 * math.log(pk + 1e-20) / math.ln10,
            };
          }(),
      };

      final watch = Stopwatch()..start();
      var rendered = 0;
      final skipped = <String, String>{};
      for (final n in nams.entries) {
        final todo = [
          for (final c in di.keys)
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
        'IDMT_RENDERINGS_THIS_RUN=$rendered ELAPSED_S=${watch.elapsedMilliseconds / 1000} SKIPPED=$skipped',
      );
      if (limit < allClips.length) return; // timing run only

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

      final cases = <Map<String, Object?>>[];
      // single-performance: reference clip vs candidates rendered from a DIFFERENT clip
      final pairs = (sel['pairs']! as List).cast<Map<String, Object?>>();
      for (var pi = 0; pi < pairs.length; pi++) {
        final rc = pairs[pi]['ref']! as String,
            cc = pairs[pi]['cand']! as String;
        for (final mode in ['blind', 'di']) {
          for (final method in ['D1', 'D2', 'D3']) {
            for (final loo in [false, true]) {
              for (final ref in usable) {
                final cands = [
                  for (final k in usable)
                    if (!(loo && k == ref)) f(k, cc, 'di'),
                ];
                final ranked = rank(f(ref, rc, mode), cands, method);
                cases.add({
                  'kind': 'single',
                  'pair': pi,
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
      // multi-performance: NAM signature = per-feature MEDIAN over N frozen signature clips (never the reference clip, other guitars only)
      final sigs = (sel['signatures']! as Map<String, Object?>)
          .cast<String, Object?>();
      final multi = <Map<String, Object?>>[];
      for (final entry in sigs.entries) {
        final rc = entry.key;
        for (final nEntry in (entry.value! as Map<String, Object?>).entries) {
          final sigClips = (nEntry.value! as List).cast<String>();
          expect(
            sigClips.contains(rc),
            isFalse,
            reason: 'leakage: reference clip in its own signature',
          );
          RefFeatures signature(String nam) => RefFeatures(
            nam,
            _median([for (final c in sigClips) f(nam, c, 'di').lnCentroid]),
            _median([for (final c in sigClips) f(nam, c, 'di').lnRolloff]),
            _median([for (final c in sigClips) f(nam, c, 'di').midLogit]),
            _median([for (final c in sigClips) f(nam, c, 'di').crestDb]),
          );
          final sigByNam = {for (final k in usable) k: signature(k)};
          for (final mode in ['blind', 'di']) {
            for (final method in ['D1', 'D2', 'D3']) {
              for (final loo in [false, true]) {
                for (final ref in usable) {
                  final cands = [
                    for (final k in usable)
                      if (!(loo && k == ref)) sigByNam[k]!,
                  ];
                  final ranked = rank(f(ref, rc, mode), cands, method);
                  multi.add({
                    'kind': 'multi',
                    'refClip': rc,
                    'n': int.parse(nEntry.key),
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
      }
      final features = {
        for (final nam in usable)
          nam: {
            for (final c in di.keys)
              c: ((cache['$nam|$c']! as Map)['di']! as Map),
          },
      };
      File('$_dir/results/idmt_a2_raw.json').writeAsStringSync(
        jsonEncode({
          'clips': allClips.map((c) => c['id']).toList(),
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
          'single': cases,
          'multi': multi,
          'features': features,
        }),
      );
      expect(usable.length, 14);
    },
    skip: run ? false : 'set WYRMTONE_RUN_IDMT=1',
    timeout: const Timeout(Duration(hours: 4)),
  );
}
