import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/matribox_nam_analysis/engine/stages.dart';
import '../../tool/nam_inference/stage_a_distance.dart';
import '../../tool/nam_inference/stage_a_excitation.dart';
import '../../tool/nam_inference/stage_a_harness.dart';

/// V4f: the Stage-A excitation generators, the offline harness, and the
/// distance metric -- all pure/deterministic, no dart:ffi, so these run
/// everywhere `flutter test` does. Does NOT touch NeuralAmpModelerCore, the
/// FFI layer, the frozen converter, FIR stages, transport, or the CloData
/// encoder.
void main() {
  group('excitation generators: deterministic and finite', () {
    void checkDeterministicFinite(String name, List<double> Function() gen) {
      test(name, () {
        final a = gen();
        final b = gen();
        expect(a.length, greaterThan(0));
        expect(a, orderedEquals(b));
        for (final v in a) {
          expect(v.isFinite, isTrue);
          expect(v.abs(), lessThanOrEqualTo(1.0001));
        }
      });
    }

    checkDeterministicFinite(
      'rampExcitation (linear)',
      () => rampExcitation(
        shape: RampShape.linear,
        freqHz: 110,
        durationS: 1,
        peak: 1.0,
      ).toList(),
    );
    checkDeterministicFinite(
      'rampExcitation (exponential)',
      () => rampExcitation(
        shape: RampShape.exponential,
        freqHz: 110,
        durationS: 1,
        peak: 1.0,
      ).toList(),
    );
    checkDeterministicFinite(
      'rampExcitation (triangle)',
      () => rampExcitation(
        shape: RampShape.triangle,
        freqHz: 110,
        durationS: 1,
        peak: 1.0,
      ).toList(),
    );
    checkDeterministicFinite(
      'rampExcitation (slowSineEnvelope)',
      () => rampExcitation(
        shape: RampShape.slowSineEnvelope,
        freqHz: 40,
        durationS: 1,
        peak: 1.0,
      ).toList(),
    );
    checkDeterministicFinite(
      'steppedExcitation',
      () => steppedExcitation(
        levels: const [0.1, 0.5, 1.0],
        freqHz: 110,
        holdS: 0.05,
        gapS: 0.01,
      ).toList(),
    );
    checkDeterministicFinite(
      'asymmetricExcitation',
      () => asymmetricExcitation(freqHz: 110, durationS: 1, peak: 1.0).toList(),
    );
    checkDeterministicFinite(
      'multisineRampExcitation',
      () => multisineRampExcitation(
        freqsHz: const [80, 200, 440, 1000, 2000],
        durationS: 1,
        peak: 1.0,
      ).toList(),
    );
    checkDeterministicFinite(
      'broadbandSteppedGainExcitation',
      () => broadbandSteppedGainExcitation(
        levels: const [0.2, 0.6, 1.0],
        baseFreqHz: 110,
        holdS: 0.05,
      ).toList(),
    );
  });

  test('rampExcitation: peak envelope reaches (approximately) peak at the end', () {
    final sig = rampExcitation(
      shape: RampShape.linear,
      freqHz: 1000,
      durationS: 1,
      peak: 0.7,
    );
    var m = 0.0;
    for (var i = sig.length - 500; i < sig.length; i++) {
      m = math.max(m, sig[i].abs());
    }
    expect(m, closeTo(0.7, 0.02));
  });

  test('multisineRampExcitation: envelope grows monotonically in block-max terms', () {
    final sig = multisineRampExcitation(
      freqsHz: const [80, 200, 440, 1000, 2000],
      durationS: 2,
      peak: 1.0,
    );
    const block = 4800;
    final blockMax = <double>[];
    for (var k = 0; k * block < sig.length; k++) {
      var m = 0.0;
      for (var i = k * block; i < (k + 1) * block && i < sig.length; i++) {
        m = math.max(m, sig[i].abs());
      }
      blockMax.add(m);
    }
    // Not strictly monotonic sample-by-sample (it's a multisine, not an
    // envelope follower), but the trend across the whole ramp must rise:
    // the first quarter's max must be well below the last quarter's.
    final firstQ = blockMax.take(blockMax.length ~/ 4).reduce(math.max);
    final lastQ = blockMax
        .skip(3 * blockMax.length ~/ 4)
        .reduce(math.max);
    expect(lastQ, greaterThan(firstQ));
  });

  group('stageADiagnostics matches stageA()', () {
    test('eP/eN from the read-only mirror equal the ones stageA() logs', () {
      final sig = rampExcitation(
        shape: RampShape.linear,
        freqHz: 110,
        durationS: 5,
        peak: 1.0,
      );
      // A trivial "model": output = input (no NAM involved) -- this test
      // only checks the harness's own diagnostic mirror against stageA()'s
      // internal log output, not any inference result.
      const n5 = 5 * 48000;
      int? loggedEP, loggedEN;
      final logPattern = RegExp(r'A eP=(\d+) eN=(\d+)');
      stageA(
        sig,
        sig,
        n5,
        log: (s) {
          final m = logPattern.firstMatch(s);
          if (m != null) {
            loggedEP = int.parse(m.group(1)!);
            loggedEN = int.parse(m.group(2)!);
          }
        },
      );
      final diag = stageADiagnostics(sig, sig, n5);
      expect(diag.eP, loggedEP);
      expect(diag.eN, loggedEN);
    });
  });

  group('stageADistance', () {
    test('distance to itself is zero', () {
      const p = ModelParams(0.2, 0.18, 5.0, 4.5);
      final d = stageADistance(p, p);
      expect(d.pErr, 0.0);
      expect(d.nErr, 0.0);
      expect(d.apErr, 0.0);
      expect(d.anErr, 0.0);
      expect(d.curveErrMean, 0.0);
      expect(d.score, 0.0);
    });

    test('a larger a+/a- mismatch produces a larger curve error', () {
      const target = ModelParams(0.2, 0.2, 5.0, 5.0);
      const near = ModelParams(0.2, 0.2, 5.5, 5.0);
      const far = ModelParams(0.2, 0.2, 50.0, 5.0);
      final dNear = stageADistance(target, near);
      final dFar = stageADistance(target, far);
      expect(dFar.curveErrMean, greaterThan(dNear.curveErrMean));
      expect(dFar.score, greaterThan(dNear.score));
    });

    test('stageACurveValue matches the P(1-e^-ax)/N(e^ax-1) formula', () {
      const p = ModelParams(0.3, 0.25, 4.0, 3.0);
      expect(
        stageACurveValue(p, 0.5),
        closeTo(0.3 * (1 - math.exp(-0.5 * 4.0)), 1e-9),
      );
      expect(
        stageACurveValue(p, -0.5),
        closeTo(0.25 * (math.exp(-0.5 * 3.0) - 1), 1e-9),
      );
      expect(stageACurveValue(p, 0.0), 0.0);
    });
  });

  test('parameter-sweep reproducibility: same params -> same excitation, twice', () {
    Float32List Function() build() => () => multisineRampExcitation(
      freqsHz: const [80, 200, 440, 1000, 2000],
      durationS: 5,
      peak: 1.0,
      shape: RampShape.linear,
    );
    final a = build()();
    final b = build()();
    expect(a, orderedEquals(b));
  });

  test(
    'generators do not reference any golden model id, Sonicake asset, or '
    'captured/output file name (no model-specific signal constants)',
    () {
      final fullSource = File(
        'tool/nam_inference/stage_a_excitation.dart',
      ).readAsStringSync();
      final code = fullSource
          .split('\n')
          .where((line) => !line.trim().startsWith('//'))
          .join('\n');
      for (final banned in [
        'Sonicake',
        'nam_input_wav',
        'wyrmtone-captures',
        'solid-rhythm',
        'gojira',
        'jvm410h',
        'fender',
        'fndr',
        'GOJIRA',
        'dart:io',
      ]) {
        expect(
          code.toLowerCase().contains(banned.toLowerCase()),
          isFalse,
          reason: 'must not reference "$banned" in code (comments are fine)',
        );
      }
    },
  );

  test(
    'holdout isolation: the TRAIN/DEV sweep scripts never iterate GOJIRA',
    () {
      // Structural guard matching the V4f spec's requirement that GOJIRA is
      // used only once, after selection. The sweep scripts may legitimately
      // list GOJIRA's Pipeline-A target value for documentation (it is
      // never modified), but the actual `trainModels` loop they run
      // experiments over must not include it -- that loop is what
      // "selection" means here.
      final trainModelsListPattern = RegExp(
        r'const\s+trainModels\s*=\s*\[([^\]]*)\]',
      );
      for (final path in [
        'native/nam_bridge/out/v4f_stage_a_sweep.dart',
        'native/nam_bridge/out/v4f_stage_a_sweep2.dart',
      ]) {
        final f = File(path);
        if (!f.existsSync()) continue; // gitignored scratch scripts
        final code = f.readAsStringSync();
        final m = trainModelsListPattern.firstMatch(code);
        expect(
          m,
          isNotNull,
          reason: '$path must declare a `const trainModels = [...]` list',
        );
        expect(
          m!.group(1)!.toLowerCase().contains('gojira'),
          isFalse,
          reason: '$path: trainModels must not include gojira',
        );
      }
    },
  );
}
