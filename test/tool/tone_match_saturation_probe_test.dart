import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/tonematch_saturation_gate/probe.dart';

String _sha(Float32List x) => sha256.convert(x.buffer.asUint8List(x.offsetInBytes, x.lengthInBytes)).toString();

/// Builds a stationary test signal long enough for the measurement window.
Float32List synth(double f0, double Function(double phase, int n) f) {
  final x = Float32List(probeLength);
  for (var n = 0; n < probeLength; n++) {
    x[n] = f(2 * math.pi * f0 * n / probeSampleRate, n);
  }
  return x;
}

/// Fourier sine coefficient of a hard-clipped sine by numerical quadrature (independent of the analyzer).
double clipHarmonic(double a, double c, int k) {
  const steps = 400000;
  var s = 0.0;
  for (var i = 0; i < steps; i++) {
    final th = (i + 0.5) / steps * math.pi; // 0..pi, odd-symmetric extension
    final v = (a * math.sin(th)).clamp(-c, c);
    s += v * math.sin(k * th);
  }
  return 2 / math.pi * s * (math.pi / steps);
}

void main() {
  group('probe generator', () {
    test('bit-identical for the same frequency and level; different otherwise', () {
      for (final f in probeFrequencies) {
        for (final l in probeLevelsDbfs) {
          expect(_sha(generateProbe(f, l)), _sha(generateProbe(f, l)));
        }
      }
      expect(_sha(generateProbe(110, -12)), isNot(_sha(generateProbe(110, -9))));
      expect(_sha(generateProbe(110, -12)), isNot(_sha(generateProbe(220, -12))));
    });

    test('structure: 48 kHz, fades, stationary window at full amplitude, zero tail, peak = level', () {
      final p = generateProbe(440, -12);
      expect(p.length, probeLength);
      expect(p[0], 0.0);
      expect(p.sublist(probeLength - probeTail).every((v) => v == 0), isTrue);
      var peak = 0.0;
      for (var i = probeMeasureStart; i < probeMeasureStart + probeMeasureLength; i++) {
        peak = math.max(peak, p[i].abs());
      }
      expect(20 * math.log(peak) / math.ln10, closeTo(-12, 0.01));
      expect(probeMeasureStart, greaterThan(probeFadeIn));
      expect(probeMeasureStart + probeMeasureLength, lessThanOrEqualTo(probeFadeIn + probeSteady));
    });

    test('probe set: the required frequencies and levels, no -6 dBFS', () {
      expect(probeFrequencies, [82.4, 110, 220, 440, 880, 1760]);
      expect(probeLevelsDbfs, [-36, -30, -24, -18, -12, -9]);
    });

    test('valid harmonics: only those below 0.45 fs; nothing aliased is counted', () {
      expect(validHarmonics(1760), [2, 3, 4, 5, 6, 7, 8]);
      expect(validHarmonics(82.4), [2, 3, 4, 5, 6, 7, 8]);
      expect(validHarmonics(3500), [2, 3, 4, 5, 6]); // 7 * 3500 = 24.5 kHz > Nyquist
      expect(validHarmonics(10000), [2]);
    });
  });

  group('harmonic analyzer on synthetic signals', () {
    test('pure sine: exact amplitude, no harmonics, tiny THD', () {
      for (final f in <double>[82.4, 220, 1760]) {
        final r = HarmonicAnalyzer(f).analyze(synth(f, (p, n) => 0.1 * math.sin(p)));
        expect(r.fundamental, closeTo(0.1, 1e-6), reason: '$f');
        expect(r.thd, lessThan(1e-4), reason: '$f'); // Float32 quantisation floor
        expect(r.dc.abs(), lessThan(1e-6));
      }
    });

    test('sine + known H2: recovered amplitude and THD', () {
      const f = 110.0;
      final r = HarmonicAnalyzer(f).analyze(synth(f, (p, n) => 0.1 * math.sin(p) + 0.01 * math.sin(2 * p + 0.7)));
      expect(r.harmonics[2]!, closeTo(0.01, 2e-6));
      expect(r.harmonics[3]!, lessThan(2e-6));
      expect(r.thd, closeTo(0.1, 5e-5));
      expect(r.evenEnergy, closeTo(0.01 * 0.01 / 2, 1e-9));
      expect(r.oddEnergy, closeTo(0, 1e-9));
    });

    test('sine + known H3 and H5: odd energy, THD, no cross-talk', () {
      const f = 82.4; // non-integer cycles in the window
      final r = HarmonicAnalyzer(f).analyze(synth(f, (p, n) => 0.2 * math.sin(p) + 0.01 * math.sin(3 * p + 1.1) + 0.004 * math.cos(5 * p)));
      expect(r.harmonics[3]!, closeTo(0.01, 2e-6));
      expect(r.harmonics[5]!, closeTo(0.004, 2e-6));
      expect(r.harmonics[2]!, lessThan(2e-6));
      expect(r.harmonics[4]!, lessThan(2e-6));
      expect(r.thd, closeTo(math.sqrt(0.01 * 0.01 + 0.004 * 0.004) / 0.2, 5e-5));
      expect(r.evenEnergy, lessThan(1e-11));
    });

    test('known clipping function: odd harmonics only, amplitudes match numerical Fourier coefficients', () {
      const f = 220.0, a = 0.4, c = 0.2;
      final r = HarmonicAnalyzer(f).analyze(synth(f, (p, n) => math.sin(p) * a > c ? c : (math.sin(p) * a < -c ? -c : a * math.sin(p))));
      for (final k in [1, 3, 5, 7]) {
        final want = clipHarmonic(a, c, k).abs();
        final got = k == 1 ? r.fundamental : r.harmonics[k]!;
        expect(got, closeTo(want, 3e-5 + want * 1e-3), reason: 'H$k');
      }
      for (final k in [2, 4, 6, 8]) {
        expect(r.harmonics[k]!, lessThan(2e-5), reason: 'even H$k of a symmetric clipper');
      }
      expect(r.oddEnergy, greaterThan(100 * r.evenEnergy));
    });

    test('THD+N counts noise, THD does not; aliased components are not harmonics', () {
      final rng = math.Random(11);
      const f = 440.0, noiseRms = 0.002;
      final noisy = synth(f, (p, n) => 0.1 * math.sin(p) + noiseRms * (rng.nextDouble() * 2 - 1) * math.sqrt(3));
      final r = HarmonicAnalyzer(f).analyze(noisy);
      expect(r.thd, lessThan(1e-3));
      expect(r.thdPlusN, closeTo(noiseRms / (0.1 / math.sqrt2), 0.03 * noiseRms / (0.1 / math.sqrt2)));
      // 3500 Hz fundamental: a component at 24.5 kHz would alias to 23.5 kHz; it is NOT H7.
      final aliased = synth(3500, (p, n) => 0.1 * math.sin(p) + 0.01 * math.sin(2 * math.pi * 23500 * n / probeSampleRate));
      final ra = HarmonicAnalyzer(3500).analyze(aliased);
      expect(ra.harmonics.keys.every((k) => k <= 6), isTrue);
      expect(ra.harmonics.values.every((v) => v < 1e-4), isTrue);
      expect(ra.residualRms, closeTo(0.01 / math.sqrt2, 2e-4));
    });
  });
}
