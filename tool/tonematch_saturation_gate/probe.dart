/// OFFLINE DIAGNOSTIC PROBE for the Tone Match saturation validation gate.
///
/// This is NOT a Tone Match evaluation signal: it must never replace RHYTHM/LEAD/CLEAN, enter a
/// user-facing score, ship in the APK or be read as a guitar sound. Nothing in lib/ imports it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

const probeSampleRate = 48000;
const probeFrequencies = <double>[82.4, 110, 220, 440, 880, 1760];

/// Peak amplitude of the sine in dBFS. -6 dBFS is intentionally absent (docs/TONE_MATCH.md 7.1).
const probeLevelsDbfs = <double>[-36, -30, -24, -18, -12, -9];

const probeFadeIn = 4800; // 0.1 s raised cosine
const probeSteady = 67200; // 1.4 s
const probeFadeOut = 4800; // 0.1 s
const probeTail = 4800; // 0.1 s zeros
const probeLength = probeFadeIn + probeSteady + probeFadeOut + probeTail;

/// Stationary measurement window: 0.4 s ... 1.4 s (no fade inside, 0.3 s after the fade-in).
const probeMeasureStart = 19200;
const probeMeasureLength = 48000;

const maxHarmonic = 8;

/// Highest frequency (Hz) a harmonic may have to count as a harmonic at all.
const maxValidHarmonicHz = 0.45 * probeSampleRate;

/// Harmonics H2..H[maxHarmonic] that are measurable for fundamental [f0] (below 0.45 * fs).
List<int> validHarmonics(double f0) => [for (var k = 2; k <= maxHarmonic; k++) if (k * f0 <= maxValidHarmonicHz) k];

/// Deterministic: a pure function of ([freq], [levelDbfs]); identical calls give identical PCM.
Float32List generateProbe(double freq, double levelDbfs) {
  final amp = math.pow(10, levelDbfs / 20).toDouble();
  final out = Float32List(probeLength);
  for (var n = 0; n < probeFadeIn + probeSteady + probeFadeOut; n++) {
    double env;
    if (n < probeFadeIn) {
      env = 0.5 - 0.5 * math.cos(math.pi * n / probeFadeIn);
    } else if (n < probeFadeIn + probeSteady) {
      env = 1.0;
    } else {
      env = 0.5 + 0.5 * math.cos(math.pi * (n - probeFadeIn - probeSteady) / probeFadeOut);
    }
    out[n] = amp * env * math.sin(2 * math.pi * freq * n / probeSampleRate);
  }
  return out;
}

class HarmonicResult {
  const HarmonicResult({
    required this.fundamental,
    required this.harmonics,
    required this.dc,
    required this.rms,
    required this.peak,
    required this.residualRms,
  });

  /// Amplitude (peak, linear) of the fundamental.
  final double fundamental;

  /// Amplitude of Hk for each VALID k >= 2 (invalid ones are absent, never aliased in).
  final Map<int, double> harmonics;
  final double dc, rms, peak, residualRms;

  double get _harmSq => harmonics.values.fold(0.0, (a, b) => a + b * b);
  double get thd => math.sqrt(_harmSq) / fundamental;

  /// THD+N: everything except the fundamental (and DC) relative to the fundamental.
  double get thdPlusN => math.sqrt(_harmSq / 2 + residualRms * residualRms) / (fundamental / math.sqrt2);
  double get oddEnergy => harmonics.entries.where((e) => e.key.isOdd).fold(0.0, (a, e) => a + e.value * e.value / 2);
  double get evenEnergy => harmonics.entries.where((e) => e.key.isEven).fold(0.0, (a, e) => a + e.value * e.value / 2);
  double get totalHarmonicEnergy => oddEnergy + evenEnergy;
  double get crest => peak / rms;
}

/// Joint least-squares fit of DC + sin/cos at f0 .. Hk over a stationary window. The fit is exact
/// for non-integer cycle counts (the Gram matrix is solved, not assumed diagonal). Built once per
/// frequency and reused for every NAM and level.
class HarmonicAnalyzer {
  // ignore: prefer_initializing_formals
  HarmonicAnalyzer(this.f0, {int start = probeMeasureStart, int length = probeMeasureLength})
    : _start = start,
      _len = length,
      _ks = [1, ...validHarmonics(f0)] {
    _p = 1 + 2 * _ks.length;
    _basis = Float64List(_p * _len);
    for (var i = 0; i < _len; i++) {
      _basis[i] = 1.0;
    }
    for (var j = 0; j < _ks.length; j++) {
      for (var i = 0; i < _len; i++) {
        final ph = 2 * math.pi * _ks[j] * f0 * (_start + i) / probeSampleRate;
        _basis[(1 + 2 * j) * _len + i] = math.sin(ph);
        _basis[(2 + 2 * j) * _len + i] = math.cos(ph);
      }
    }
    final g = List.generate(_p, (_) => Float64List(_p));
    for (var a = 0; a < _p; a++) {
      for (var b = a; b < _p; b++) {
        var s = 0.0;
        for (var i = 0; i < _len; i++) {
          s += _basis[a * _len + i] * _basis[b * _len + i];
        }
        g[a][b] = s;
        g[b][a] = s;
      }
    }
    _chol = _cholesky(g);
  }

  final double f0;
  final int _start, _len;
  final List<int> _ks;
  late final int _p;
  late final Float64List _basis;
  late final List<Float64List> _chol;

  static List<Float64List> _cholesky(List<Float64List> a) {
    final n = a.length;
    final l = List.generate(n, (_) => Float64List(n));
    for (var i = 0; i < n; i++) {
      for (var j = 0; j <= i; j++) {
        var s = a[i][j];
        for (var k = 0; k < j; k++) {
          s -= l[i][k] * l[j][k];
        }
        l[i][j] = i == j ? math.sqrt(s) : s / l[j][j];
      }
    }
    return l;
  }

  HarmonicResult analyze(Float32List x) {
    final rhs = Float64List(_p);
    var sumSq = 0.0, peak = 0.0;
    for (var i = 0; i < _len; i++) {
      final v = x[_start + i].toDouble();
      sumSq += v * v;
      if (v.abs() > peak) peak = v.abs();
    }
    for (var a = 0; a < _p; a++) {
      var s = 0.0;
      for (var i = 0; i < _len; i++) {
        s += _basis[a * _len + i] * x[_start + i];
      }
      rhs[a] = s;
    }
    // solve L L^T c = rhs
    final y = Float64List(_p);
    for (var i = 0; i < _p; i++) {
      var s = rhs[i];
      for (var k = 0; k < i; k++) {
        s -= _chol[i][k] * y[k];
      }
      y[i] = s / _chol[i][i];
    }
    final c = Float64List(_p);
    for (var i = _p - 1; i >= 0; i--) {
      var s = y[i];
      for (var k = i + 1; k < _p; k++) {
        s -= _chol[k][i] * c[k];
      }
      c[i] = s / _chol[i][i];
    }
    var resSq = 0.0;
    for (var i = 0; i < _len; i++) {
      var fit = 0.0;
      for (var a = 0; a < _p; a++) {
        fit += c[a] * _basis[a * _len + i];
      }
      final r = x[_start + i] - fit;
      resSq += r * r;
    }
    final harm = <int, double>{};
    double fundamental = 0;
    for (var j = 0; j < _ks.length; j++) {
      final amp = math.sqrt(c[1 + 2 * j] * c[1 + 2 * j] + c[2 + 2 * j] * c[2 + 2 * j]);
      if (_ks[j] == 1) {
        fundamental = amp;
      } else {
        harm[_ks[j]] = amp;
      }
    }
    return HarmonicResult(
      fundamental: fundamental,
      harmonics: harm,
      dc: c[0],
      rms: math.sqrt(sumSq / _len),
      peak: peak,
      residualRms: math.sqrt(resSq / _len),
    );
  }
}
