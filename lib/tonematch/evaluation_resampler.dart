import 'dart:math' as math;
import 'dart:typed_data';

/// THE one resampling step of Tone Match: 44.1 kHz -> 48 kHz (rational 160/147).
///
/// Algorithm: polyphase windowed-sinc interpolation. Output sample n sits at input position
/// n * 147/160; its phase is (n*147) mod 160 and the 160 phase filters are precomputed.
/// Filter: sinc low-pass, cutoff 21.5 kHz (0.4875 of the input rate), Kaiser window (beta 9),
/// 48 taps per phase, each phase normalised to unity DC gain.
/// Edge handling: the signal is extended with ZEROS before the first and after the last sample
/// (the recordings start and end in near-silence); output length = floor(N * 160 / 147).
/// Determinism: no randomness, no dependence on block size, a fixed evaluation order of
/// double-precision sums; the same input gives bit-identical output on the same platform and
/// agrees to ~1e-6 across platforms (libm differences only affect the filter tables).
abstract final class EvaluationResampler {
  static const inputRate = 44100;
  static const outputRate = 48000;
  static const _up = 160, _down = 147; // 48000/44100 = 160/147
  static const _halfTaps = 24;
  static const _cutoff = 21500.0 / 44100.0; // cycles per input sample
  static const _kaiserBeta = 9.0;

  static List<Float64List>? _phases;

  static double _i0(double x) {
    var sum = 1.0, term = 1.0;
    for (var k = 1; k < 50; k++) {
      term *= (x / (2 * k)) * (x / (2 * k));
      sum += term;
      if (term < 1e-17 * sum) break;
    }
    return sum;
  }

  static List<Float64List> _table() => _phases ??= () {
    final i0Beta = _i0(_kaiserBeta);
    final table = <Float64List>[];
    for (var p = 0; p < _up; p++) {
      final frac = p / _up; // output lies `frac` after input index i
      final taps = Float64List(2 * _halfTaps);
      var sum = 0.0;
      for (var k = 0; k < 2 * _halfTaps; k++) {
        final x = (k - (_halfTaps - 1)) - frac; // distance of tap input (i + k - 23) from output
        final w = x.abs() >= _halfTaps ? 0.0 : _i0(_kaiserBeta * math.sqrt(1 - (x / _halfTaps) * (x / _halfTaps))) / i0Beta;
        final s = x == 0 ? 2 * _cutoff : math.sin(2 * math.pi * _cutoff * x) / (math.pi * x);
        taps[k] = s * w;
        sum += taps[k];
      }
      for (var k = 0; k < taps.length; k++) {
        taps[k] /= sum;
      }
      table.add(taps);
    }
    return table;
  }();

  static Float32List to48k(Float32List input) {
    final n = input.length;
    final outLen = n * _up ~/ _down;
    final out = Float32List(outLen);
    final table = _table();
    for (var m = 0; m < outLen; m++) {
      final pos = m * _down;
      final i = pos ~/ _up;
      final taps = table[pos % _up];
      var acc = 0.0;
      final first = i - (_halfTaps - 1);
      for (var k = 0; k < taps.length; k++) {
        final idx = first + k;
        if (idx >= 0 && idx < n) acc += taps[k] * input[idx];
      }
      out[m] = acc;
    }
    return out;
  }
}
