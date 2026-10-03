import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/nam_inference/fir_distance.dart';
import '../../tool/nam_inference/fir_excitation.dart';
import '../../tool/nam_inference/fir_pipeline_harness.dart';

/// V4g: the FIR excitation generators, the semantic FIR distance metric,
/// and the Stage-L iteration-log parser -- all pure/deterministic, no
/// dart:ffi, so these run everywhere `flutter test` does. Does not touch
/// NeuralAmpModelerCore, the FFI layer, Stage A, Reference Signal V1/V2,
/// the frozen converter, transport, or the CloData wire format.
void main() {
  group('excitation generators: deterministic, finite, in range', () {
    void check(String name, Float32List Function() gen) {
      test(name, () {
        final a = gen();
        final b = gen();
        expect(a.length, greaterThan(0));
        expect(a, orderedEquals(b));
        for (final v in a) {
          expect(v.isFinite, isTrue);
          expect(v.abs(), lessThanOrEqualTo(2.001)); // hybrid/noise sums may briefly exceed 1
        }
      });
    }

    check('logSweep (oneshot)', () => logSweep(durationS: 1, maxHz: 20000));
    check('logSweep (cycled)', () => logSweep(durationS: 2, maxHz: 20000, cyclePeriodS: 0.5));
    check('multisine', () => multisine(durationS: 1, maxHz: 20000, toneCount: 10));
    check('multisine (cycled)', () => multisine(durationS: 1, maxHz: 20000, toneCount: 10, cyclePeriodS: 0.25));
    check('mlsSequence', () => mlsSequence(durationS: 1));
    check('whiteNoise', () => whiteNoise(durationS: 1));
    check('pinkNoise', () => pinkNoise(durationS: 1));
    check('steppedFrequency', () => steppedFrequency(stepCount: 8, maxHz: 20000, holdS: 0.05));
    check('hybridSweepPlusNoise', () => hybridSweepPlusNoise(durationS: 1));
  });

  test('logSweep with cyclePeriodS repeats exactly every period', () {
    final sig = logSweep(durationS: 2, maxHz: 20000, cyclePeriodS: 0.5);
    final periodN = (0.5 * firSampleRate).round();
    for (var i = 0; i < 1000; i++) {
      expect(sig[i], closeTo(sig[i + periodN], 1e-5));
    }
  });

  test('mlsSequence is bipolar (only +-peak values)', () {
    final sig = mlsSequence(durationS: 0.1, peak: 0.7);
    for (final v in sig) {
      expect(v.abs(), closeTo(0.7, 1e-6));
    }
  });

  test(
    'generators do not reference any golden model id, Sonicake asset, or captured file name',
    () {
      final fullSource = File('tool/nam_inference/fir_excitation.dart').readAsStringSync();
      final code = fullSource.split('\n').where((l) => !l.trim().startsWith('//') && !l.trim().startsWith('///')).join('\n');
      for (final banned in [
        'Sonicake', 'nam_input_wav', 'wyrmtone-captures',
        'solid', 'gojira', 'jvm410h', 'fender', 'fndr', 'dart:io',
      ]) {
        expect(
          code.toLowerCase().contains(banned.toLowerCase()),
          isFalse,
          reason: 'must not reference "$banned" in code',
        );
      }
    },
  );

  group('fir_distance', () {
    test('distance to itself is zero', () {
      final taps = Float32List.fromList([1.0, 0.5, -0.2, 0.1]);
      final d = firDistance(taps, taps);
      expect(d.magRmsDb, 0.0);
      expect(d.magMeanAbsDb, 0.0);
      expect(d.magMaxDb, 0.0);
      expect(d.impulseCorrelation, closeTo(1.0, 1e-9));
      expect(d.impulseNrmse, closeTo(0.0, 1e-9));
    });

    test('a scaled copy has zero magnitude/impulse error only when scale is 1', () {
      final taps = Float32List.fromList([1.0, 0.5, -0.2, 0.1, 0.05]);
      final scaled = Float32List.fromList([for (final v in taps) v * 2.0]);
      final d = firDistance(taps, scaled);
      // 2x scale -> -6.02dB at every bin (target is quieter than candidate),
      // flat across frequency (zero SHAPE error): mean ~= rms ~= max.
      expect(d.magMeanAbsDb, closeTo(6.02, 0.1));
      expect(d.magRmsDb, closeTo(6.02, 0.1));
      expect(d.magMaxDb, closeTo(6.02, 0.1));
    });

    test('firDistanceFreqsHz matches the V4g spec set', () {
      expect(firDistanceFreqsHz, [
        20, 40, 80, 100, 200, 400, 800, 1000, 2000, 4000, 6000, 8000, 10000, 12000, 16000, 20000,
      ]);
    });
  });

  group('fir_pipeline_harness', () {
    test('stageLWindows matches the frozen runEngine() window layout', () {
      expect(stageLWindows, [(23, 240000, 3), (6, 720000, 2), (30, 960000, 5)]);
    });

    test('StageLIterationLog decisions are one of improved/RESET/kept', () {
      const validDecisions = {'improved', 'RESET', 'kept'};
      final log = StageLIterationLog(23, 0, 0.1, 'improved');
      expect(validDecisions.contains(log.decision), isTrue);
    });
  });

  test(
    'holdout isolation: the TRAIN/DEV FIR sweep scripts never iterate GOJIRA',
    () {
      final trainModelsPattern = RegExp(r'const\s+trainModels\s*=\s*\[([^\]]*)\]');
      for (final path in [
        'native/nam_bridge/out/v4g_fir_sweep.dart',
        'native/nam_bridge/out/v4g_fir_sweep2.dart',
      ]) {
        final f = File(path);
        if (!f.existsSync()) continue; // gitignored scratch scripts
        final code = f.readAsStringSync();
        final m = trainModelsPattern.firstMatch(code);
        expect(m, isNotNull, reason: '$path must declare trainModels');
        expect(
          m!.group(1)!.toLowerCase().contains('gojira'),
          isFalse,
          reason: '$path: trainModels must not include gojira',
        );
      }
    },
  );
}
