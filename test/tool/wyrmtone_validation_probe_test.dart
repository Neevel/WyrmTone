import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/nam_inference/clodata_offline_evaluator.dart';
import '../../tool/nam_inference/wyrmtone_validation_probe.dart';
import '../../tool/matribox_nam_analysis/engine/stages.dart';

/// V4e: the independent, third validation probe (never used for
/// identification) and the offline CloData evaluator. Platform-independent
/// (pure sin/cos + the existing, already-tested Biquad/Waveshaper/FIR
/// building blocks) — no dart:ffi, runs everywhere `flutter test` does.
void main() {
  test('probe: deterministic, finite, correct length', () {
    final a = WyrmToneValidationProbe.generate();
    final b = WyrmToneValidationProbe.generate();
    expect(a.length, WyrmToneValidationProbe.totalFrames);
    expect(a, orderedEquals(b));
    for (final v in a) {
      expect(v.isFinite, isTrue);
    }
  });

  test(
    'probe: unit impulse and low-level impulse are exactly where documented',
    () {
      final sig = WyrmToneValidationProbe.generate();
      expect(sig[WyrmToneValidationProbe.unitImpulseAt], 1.0);
      expect(
        sig[WyrmToneValidationProbe.lowLevelImpulseAt],
        closeTo(0.05, 1e-6),
      );
      // Nothing else nearby should be anywhere near full scale.
      expect(sig[WyrmToneValidationProbe.unitImpulseAt - 1], 0.0);
      expect(sig[WyrmToneValidationProbe.unitImpulseAt + 1], 0.0);
    },
  );

  test('probe: the three sweeps hit their intended peak amplitude', () {
    final sig = WyrmToneValidationProbe.generate();
    double peakIn(int start, int len) {
      var m = 0.0;
      for (var i = start; i < start + len; i++) {
        m = math.max(m, sig[i].abs());
      }
      return m;
    }

    // Sampled mid-sweep (past the 5% fade-in) so the check is robust.
    const margin = 20000;
    expect(
      peakIn(
        WyrmToneValidationProbe.sweepMidAt + margin,
        WyrmToneValidationProbe.sweepLength - 2 * margin,
      ),
      closeTo(0.3, 0.02),
    );
    expect(
      peakIn(
        WyrmToneValidationProbe.sweepLowAt + margin,
        WyrmToneValidationProbe.sweepLength - 2 * margin,
      ),
      closeTo(0.05, 0.01),
    );
    expect(
      peakIn(
        WyrmToneValidationProbe.sweepHighAt + margin,
        WyrmToneValidationProbe.sweepLength - 2 * margin,
      ),
      closeTo(0.9, 0.02),
    );
  });

  test(
    'probe: does not reference either identification signal or Sonicake',
    () {
      // Structural guard, same pattern as the V4d reference-signal test: the
      // GENERATOR source (not this test file) must not reference Sonicake or
      // WyrmToneReferenceSignal's own construction (Schroeder multitone).
      final fullSource = File(
        'tool/nam_inference/wyrmtone_validation_probe.dart',
      ).readAsStringSync();
      final code = fullSource
          .split('\n')
          .where((line) => !line.trim().startsWith('//'))
          .join('\n');
      for (final banned in [
        'Sonicake',
        'nam_input_wav',
        'wyrmtone-captures',
        '48000.wav',
        'Schroeder',
        'WyrmToneReferenceSignal',
      ]) {
        expect(
          code.contains(banned),
          isFalse,
          reason: 'must not reference "$banned" in code (comments are fine)',
        );
      }
      expect(code.contains('dart:io'), isFalse);
    },
  );

  group('offline evaluator', () {
    ModelParams sampleParams() => const ModelParams(0.3, 0.28, 4.0, 3.5);
    Float32List identityFir(int n) => Float32List(n)..[0] = 1.0;

    test(
      'identity FIRs + zero input -> zero output (no NaN/Inf, no explosion)',
      () {
        final input = Float32List(2000);
        final out = evaluateAmp(
          sampleParams(),
          identityFir(128),
          identityFir(2048),
          input,
        );
        expect(out.length, input.length);
        for (final v in out) {
          expect(v.isFinite, isTrue);
        }
      },
    );

    test('a nonzero probe segment produces a finite, bounded, deterministic output', () {
      final probe = WyrmToneValidationProbe.generate();
      final seg = Float32List.sublistView(probe, 0, 20000);
      final a = evaluateAmp(
        sampleParams(),
        identityFir(128),
        identityFir(2048),
        seg,
      );
      final b = evaluateAmp(
        sampleParams(),
        identityFir(128),
        identityFir(2048),
        seg,
      );
      expect(a, orderedEquals(b));
      for (final v in a) {
        expect(v.isFinite, isTrue);
        expect(v.abs(), lessThan(10.0));
      }
    });

    test('waveshaper evaluation is monotonic in the positive branch for a plausible model', () {
      final p = sampleParams();
      final xs = [0.0, 0.1, 0.3, 0.6, 1.0];
      double? prev;
      for (final x in xs) {
        final y = evaluateWaveshaperAt(p, x);
        expect(y.isFinite, isTrue);
        if (prev != null) expect(y, greaterThanOrEqualTo(prev - 1e-6));
        prev = y;
      }
    });
  });
}
