import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/tonematch/dsp_fft.dart';
import 'package:wyrmtone/tonematch/evaluation_resampler.dart';
import 'package:wyrmtone/tonematch/evaluation_wav.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/stft_feature_extractor.dart';
import 'package:wyrmtone/tonematch/tone_features.dart';

/// Minimal RIFF/WAVE bytes for the reader tests (a test fixture only, not an evaluation signal).
Uint8List wavBytes({required List<int> left, List<int>? right, int channels = 2, int rate = 44100, int bits = 24}) {
  final frames = left.length;
  final bytesPer = bits ~/ 8;
  final dataLen = frames * channels * bytesPer;
  final b = BytesBuilder();
  void u32(int v) => b.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
  void u16(int v) => b.add([v & 255, (v >> 8) & 255]);
  b.add('RIFF'.codeUnits);
  u32(36 + dataLen);
  b.add('WAVEfmt '.codeUnits);
  u32(16);
  u16(1);
  u16(channels);
  u32(rate);
  u32(rate * channels * bytesPer);
  u16(channels * bytesPer);
  u16(bits);
  b.add('data'.codeUnits);
  u32(dataLen);
  void sample(int v) {
    for (var i = 0; i < bytesPer; i++) {
      b.addByte((v >> (8 * i)) & 255);
    }
  }

  for (var i = 0; i < frames; i++) {
    sample(left[i]);
    if (channels == 2) sample((right ?? List.filled(frames, 0))[i]);
  }
  return b.toBytes();
}

/// Test-only guitar-like DI: decaying harmonic plucks, one every 0.5 s, plus a tiny noise floor.
Float32List pluckSignal(int seconds) {
  final n = 48000 * seconds;
  final rng = math.Random(7);
  final x = Float32List(n);
  for (var i = 0; i < n; i++) {
    final t = (i % 24000) / 48000.0;
    var v = 0.0;
    for (var h = 1; h <= 8; h++) {
      v += math.sin(2 * math.pi * 110.0 * h * i / 48000) / h;
    }
    x[i] = (0.3 * v * math.exp(-t / 0.18) + (rng.nextDouble() - 0.5) * 1e-4).toDouble();
  }
  return x;
}

void main() {
  group('WAV reader', () {
    test('returns exactly the LEFT channel, exact 24-bit decode, right channel ignored', () {
      final dry = EvaluationWavReader.readDryLeft(wavBytes(left: [0, 4194304, -4194304, 8388607, -8388608], right: [1, 2, 3, 4, 5]));
      expect(dry.sampleRate, 44100);
      expect(dry.samples, [0.0, 0.5, -0.5, 8388607 / 8388608.0, -1.0]);
    });
    test('rejects mono, 16 bit and wrong sample rate', () {
      expect(() => EvaluationWavReader.readDryLeft(wavBytes(left: [0, 1], channels: 1)), throwsA(isA<EvaluationSignalException>()));
      expect(() => EvaluationWavReader.readDryLeft(wavBytes(left: [0, 1], bits: 16)), throwsA(isA<EvaluationSignalException>()));
      expect(() => EvaluationWavReader.readDryLeft(wavBytes(left: [0, 1], rate: 48000)), throwsA(isA<EvaluationSignalException>()));
      expect(() => EvaluationWavReader.readDryLeft(Uint8List(8)), throwsA(isA<EvaluationSignalException>()));
    });
  });

  group('resampler 44.1 -> 48 kHz', () {
    test('length, frequency/amplitude of a sine, DC gain, bit-identical repeat', () {
      const n = 44100;
      final x = Float32List.fromList([for (var i = 0; i < n; i++) 0.5 * math.sin(2 * math.pi * 1000 * i / 44100)]);
      final y = EvaluationResampler.to48k(x);
      expect(y.length, n * 160 ~/ 147);
      var worst = 0.0;
      for (var m = 200; m < y.length - 200; m++) {
        worst = math.max(worst, (y[m] - 0.5 * math.sin(2 * math.pi * 1000 * m / 48000)).abs());
      }
      expect(worst, lessThan(2e-4));
      expect(EvaluationResampler.to48k(x), y); // identical on a repeat
      final dc = EvaluationResampler.to48k(Float32List.fromList(List.filled(2000, 0.25)));
      expect(dc[1000], closeTo(0.25, 1e-6));
    });
    test('guitar band stays untouched: 5 kHz and 8 kHz sines keep their amplitude', () {
      for (final f in [5000.0, 8000.0]) {
        final x = Float32List.fromList([for (var i = 0; i < 20000; i++) 0.5 * math.sin(2 * math.pi * f * i / 44100)]);
        final y = EvaluationResampler.to48k(x);
        var sum = 0.0;
        for (var m = 1000; m < y.length - 1000; m++) {
          sum += y[m] * y[m];
        }
        final amp = math.sqrt(2 * sum / (y.length - 2000));
        expect(amp, closeTo(0.5, 0.003), reason: '$f Hz');
      }
    });
  });

  test('FFT matches a naive DFT', () {
    const n = 64;
    final rng = math.Random(3);
    final re = Float64List.fromList([for (var i = 0; i < n; i++) rng.nextDouble() - 0.5]);
    final im = Float64List(n);
    final ref = [
      for (var k = 0; k < n; k++)
        (
          [for (var t = 0; t < n; t++) re[t] * math.cos(2 * math.pi * k * t / n)].reduce((a, b) => a + b),
          [for (var t = 0; t < n; t++) -re[t] * math.sin(2 * math.pi * k * t / n)].reduce((a, b) => a + b),
        ),
    ];
    Fft(n).transform(re, im);
    for (var k = 0; k < n; k++) {
      expect(re[k], closeTo(ref[k].$1, 1e-9));
      expect(im[k], closeTo(ref[k].$2, 1e-9));
    }
  });

  group('feature extractor (synthetic test signals only)', () {
    final di = pluckSignal(6);
    const ex = StftFeatureExtractor();
    Float32List map(double Function(double) f) => Float32List.fromList([for (final v in di) f(v)]);
    final clean = map((v) => v);
    final saturated = map((v) => 0.6 * (v * 25).clamp(-1.0, 1.0).toDouble());

    test('deterministic', () {
      final a = ex.extract(input: di, output: saturated), b = ex.extract(input: di, output: saturated);
      expect(a.tone, b.tone);
      expect(a.level, b.level);
    });

    test('louder is not different in tone: scaling the output changes LEVEL only', () {
      final a = ex.extract(input: di, output: clean);
      final quiet = ex.extract(input: di, output: map((v) => v * 0.25));
      expect(quiet.level[ToneFeatureIds.rmsDb]!, closeTo(a.level[ToneFeatureIds.rmsDb]! - 12.04, 0.01));
      expect(quiet.level[ToneFeatureIds.peakDb]!, closeTo(a.level[ToneFeatureIds.peakDb]! - 12.04, 0.01));
      for (final e in a.tone.entries) {
        expect(quiet.tone[e.key]!, closeTo(e.value, 1e-3 * (e.value.abs() + 1)), reason: e.key);
      }
    });

    test('saturation components move in the expected direction and the composite is their mean', () {
      final c = ex.extract(input: di, output: clean).tone, s = ex.extract(input: di, output: saturated).tone;
      expect(s[ToneFeatureIds.crestReductionDb]!, greaterThan(c[ToneFeatureIds.crestReductionDb]! + 3));
      expect(s[ToneFeatureIds.hfGenerationDb]!, greaterThan(c[ToneFeatureIds.hfGenerationDb]!));
      expect(s[ToneFeatureIds.saturationComposite]!, greaterThan(c[ToneFeatureIds.saturationComposite]!));
      final mean = SaturationDescriptor.components.map((k) => SaturationDescriptor.normalise(k, s[k]!)).reduce((a, b) => a + b) / 4;
      expect(s[ToneFeatureIds.saturationComposite], closeTo(mean, 1e-12));
      expect(c[ToneFeatureIds.crestReductionDb]!.abs(), lessThan(0.1)); // identity NAM: nothing generated
    });

    test('band shares sum to 1, onsets are found, level features are not tone features', () {
      final t = ex.extract(input: di, output: saturated).tone;
      expect([for (final b in GuitarBand.values) t[ToneFeatureIds.band(b)]!].reduce((a, b) => a + b), closeTo(1, 1e-9));
      expect(t[ToneFeatureIds.onsetCount]!, greaterThan(5));
      expect(t.keys.where((k) => k.startsWith('level.')), isEmpty);
    });
  });
}
