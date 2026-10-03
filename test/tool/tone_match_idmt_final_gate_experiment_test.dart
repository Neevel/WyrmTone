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
import 'package:wyrmtone/tonematch/tone_features.dart';

import '../../tool/tonematch_reference_match/spike.dart';

/// FINAL controlled Hoer-Match gate (research only). Runs with WYRMTONE_RUN_FINALGATE=1. Everything it uses is
/// defined in tool/tonematch_reference_match/final_gate_preregistration.json whose SHA-256 is checked first.
const _dll = 'native/nam_bridge/build/wyrmtone_nam.dll';
const _dir = 'tool/tonematch_reference_match';
const _desk = 'D:/Desktop 3d sachen/Desktop/';
const _extra = <String, String>{
  'MkV-Clean':
      '${_desk}AMP Presets/Boogie Mark V - Rhythm, Lead and Clean/Clean.nam',
  'MkV-Rhythm':
      '${_desk}AMP Presets/Boogie Mark V - Rhythm, Lead and Clean/Rythm.nam',
  'MkV-Lead':
      '${_desk}AMP Presets/Boogie Mark V - Rhythm, Lead and Clean/Lead.nam',
  'FenderSR':
      '${_desk}Fender Super Reverb 1977/Fender Super Reverb_ EQ Flat, Volume 3, sm57.nam',
};

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
          _ => throw StateError('unsupported wav format $fmt/$bits'),
        };
      }
      return out;
    }
    o += 8 + size + (size & 1);
  }
  throw StateError('no data chunk in $path');
}

/// Production definition of the active RMS of a DI (see StftFeatureExtractor): frames within activeGateDbBelowInputPeak
/// dB of the loudest input frame, mean of the frame mean squares, in dB.
double _activeRmsDb(Float32List x) {
  const frame = ToneAnalysisParams.frameSize, hop = ToneAnalysisParams.hopSize;
  final frames = (x.length - frame) ~/ hop + 1;
  final ms = Float64List(frames);
  for (var f = 0; f < frames; f++) {
    var s = 0.0;
    for (var i = f * hop; i < f * hop + frame; i++) {
      s += x[i] * x[i];
    }
    ms[f] = s / frame;
  }
  final gate =
      ms.reduce(math.max) *
      math.pow(10, -ToneAnalysisParams.activeGateDbBelowInputPeak / 10);
  final active = [
    for (var f = 0; f < frames; f++)
      if (ms[f] >= gate) ms[f],
  ];
  return 10 *
      math.log(active.fold(0.0, (a, b) => a + b) / active.length + 1e-20) /
      math.ln10;
}

Float32List _scaleTo(Float32List x, double targetDb) {
  final g = math.pow(10, (targetDb - _activeRmsDb(x)) / 20).toDouble();
  return Float32List.fromList([for (final v in x) (v * g).toDouble()]);
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
  final run = Platform.environment['WYRMTONE_RUN_FINALGATE'] == '1';
  test(
    'hoer-match final controlled gate: render and rank exactly as pre-registered',
    () async {
      final preBytes = File('$_dir/final_gate_preregistration.json')
          .readAsBytesSync();
      final preSha = sha256.convert(preBytes).toString();
      expect(
        preSha,
        File('$_dir/final_gate_preregistration.sha256')
            .readAsStringSync()
            .trim(),
        reason: 'pre-registration changed',
      );
      final pre = jsonDecode(utf8.decode(preBytes)) as Map<String, Object?>;
      final target =
          ((pre['inputLevel']! as Map)['targetActiveRmsDbfs']! as num)
              .toDouble();
      final clipMeta = (pre['clips']! as Map<String, Object?>)
          .cast<String, Object?>();
      final namMeta = (pre['nams']! as Map<String, Object?>)
          .cast<String, Object?>();
      final pairs = (pre['pairs']! as List).cast<Map<String, Object?>>();
      for (final e in clipMeta.entries) {
        expect(
          sha256
              .convert(File('$_dir/data/idmt/${e.key}.wav').readAsBytesSync())
              .toString(),
          (e.value! as Map)['sha256'],
          reason: 'clip changed ${e.key}',
        );
      }
      final namPath = <String, String>{};
      final ten = (jsonDecode(
        File('tool/tonematch_gate/ten_nam_set.json').readAsStringSync(),
      ) as List).cast<Map<String, Object?>>();
      for (final n in ten) {
        namPath[n['id']! as String] = n['path']! as String;
      }
      namPath.addAll(_extra);
      for (final e in namMeta.entries) {
        expect(
          sha256.convert(File(namPath[e.key]!).readAsBytesSync()).toString(),
          (e.value! as Map)['sha256'],
          reason: 'NAM changed ${e.key}',
        );
      }

      const extractor = StftFeatureExtractor();
      final raw48 = <String, Float32List>{
        for (final id in clipMeta.keys)
          id: EvaluationResampler.to48k(_readWav('$_dir/data/idmt/$id.wav')),
      };
      final scaled = <String, Float32List>{
        for (final e in raw48.entries) e.key: _scaleTo(e.value, target),
      };
      final levels = {
        for (final e in raw48.entries)
          e.key: {
            'activeRmsBeforeDb': _activeRmsDb(e.value),
            'activeRmsAfterDb': _activeRmsDb(scaled[e.key]!),
            'gainDb': target - _activeRmsDb(e.value),
            'peakAfterDbfs':
                20 *
                math.log(
                  scaled[e.key]!.fold(0.0, (m, v) => math.max(m, v.abs())) +
                      1e-20,
                ) /
                math.ln10,
          },
      };

      final feat =
          <
            String,
            Map<String, ({RefFeatures di, RefFeatures blind})>
          >{}; // nam -> clip -> features
      final timing = Stopwatch()..start();
      var rendered = 0;
      for (final nam in namMeta.keys) {
        final engine = NamInferenceEngine.create(_dll);
        try {
          engine.load(
            namPath[nam]!,
            sampleRate: evaluationSampleRate.toDouble(),
          );
          expect(
            engine.expectedSampleRate == 0 ||
                engine.expectedSampleRate == evaluationSampleRate,
            isTrue,
            reason: 'BLOCKED: NAM $nam not loadable at 48 kHz',
          );
          for (final c in clipMeta.keys) {
            final out = _render(engine, scaled[c]!);
            (feat[nam] ??= {})[c] = (
              di: RefFeatures.from(
                nam,
                extractor.extract(input: scaled[c]!, output: out),
              ),
              blind: RefFeatures.from(
                nam,
                extractor.extract(input: out, output: out),
              ),
            );
            rendered++;
          }
        } finally {
          engine.dispose();
        }
      }
      timing.stop();
      stdout.writeln(
        'FINALGATE_RENDERINGS=$rendered ELAPSED_S=${timing.elapsedMilliseconds / 1000}',
      );

      final cases = <Map<String, Object?>>[];
      final nams = namMeta.keys.toList();
      for (var pi = 0; pi < pairs.length; pi++) {
        final rc = pairs[pi]['ref']! as String,
            cc = pairs[pi]['cand']! as String;
        for (final mode in ['blind', 'di']) {
          for (final method in ['D1', 'D2', 'D3']) {
            for (final loo in [false, true]) {
              for (final ref in nams) {
                final reference = mode == 'blind'
                    ? feat[ref]![rc]!.blind
                    : feat[ref]![rc]!.di;
                final cands = [
                  for (final k in nams)
                    if (!(loo && k == ref)) feat[k]![cc]!.di,
                ];
                final ranked = rank(reference, cands, method);
                cases.add({
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

      // level-sensitivity control (documentation only)
      final ctl = pre['levelSensitivityControl']! as Map<String, Object?>;
      final sens = <Map<String, Object?>>[];
      for (final nam in (ctl['nams']! as List).cast<String>()) {
        final engine = NamInferenceEngine.create(_dll);
        try {
          engine.load(
            namPath[nam]!,
            sampleRate: evaluationSampleRate.toDouble(),
          );
          for (final c in (ctl['clips']! as List).cast<String>()) {
            for (final lv in (ctl['levelsDbfs']! as List).map(
              (e) => (e as num).toDouble(),
            )) {
              final x = _scaleTo(raw48[c]!, lv);
              final out = _render(engine, x);
              sens.add({
                'nam': nam,
                'clip': c,
                'levelDbfs': lv,
                ...RefFeatures.from(
                  nam,
                  extractor.extract(input: x, output: out),
                ).toJson(),
              });
            }
          }
        } finally {
          engine.dispose();
        }
      }

      File('$_dir/results/idmt_final_gate_raw.json').writeAsStringSync(
        jsonEncode({
          'preregistrationSha256': preSha,
          'targetActiveRmsDbfs': target,
          'levels': levels,
          'nams': namMeta,
          'pairs': pairs,
          'cases': cases,
          'levelSensitivity': sens,
          'features': {
            for (final n in nams)
              n: {for (final c in clipMeta.keys) c: feat[n]![c]!.di.toJson()},
          },
          'renderings': rendered,
          'elapsedSeconds': timing.elapsedMilliseconds / 1000,
        }),
      );
      expect(rendered, nams.length * clipMeta.length);
    },
    skip: run ? false : 'set WYRMTONE_RUN_FINALGATE=1',
    timeout: const Timeout(Duration(hours: 3)),
  );
}
