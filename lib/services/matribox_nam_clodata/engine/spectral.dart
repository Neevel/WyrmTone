import 'dart:math' as math;
import 'dart:typed_data';

import 'f32.dart';
import 'ooura_fft.dart';
import 'ucrt_float.dart';

/// Float32 Hamming window `0.54 - 0.46 cos(2 pi i / (n-1))` as evaluated by
/// the spectral estimator (scalar UCRT `cosf`, float32 arithmetic).
Float32List hammingCosf(int n) {
  final twoPi = f32(6.2831854820251465);
  final den = (n - 1).toDouble();
  final w = Float32List(n);
  for (var i = 0; i < n; i++) {
    final a = f32(f32(i.toDouble() * twoPi) / den);
    final c = cosf(a);
    w[i] = f32(f32(0.54) - f32(c * f32(0.46)));
  }
  return w;
}

/// Averaged cross-spectrum magnitude `|Sxy| / (Sxx + eps)` of two signals
/// (50 % overlapping Hamming segments, float32 accumulation), plus the
/// frequency axis in Hz. Returns `nfft/2 + 1` bins.
class WelchEstimator {
  WelchEstimator(this.nperseg, this.nfft, {this._fs = 48000.0})
    : _win = hammingCosf(nperseg),
      _fft = OouraRdft(nfft);

  final int nperseg, nfft;
  final double _fs;
  final Float32List _win;
  final OouraRdft _fft;

  (Float32List, Float32List) magnitude(
    Float32List x,
    int xOff,
    Float32List y,
    int yOff,
    int n,
  ) {
    final cnt = nfft ~/ 2 + 1;
    final sxx = Float32List(cnt),
        sre = Float32List(cnt),
        sim = Float32List(cnt);
    final hop = nperseg ~/ 2;
    final sx = Float32List(nperseg), sy = Float32List(nperseg);
    final px = Float32List(nfft), py = Float32List(nfft);
    final a = Float64List(nfft);
    final xr = Float32List(cnt),
        xi = Float32List(cnt),
        yr = Float32List(cnt),
        yi = Float32List(cnt);
    var pos = 0;
    var done = false;
    while (!done) {
      final start = math.min(pos, n - nperseg);
      if (pos >= n - nperseg) done = true;
      for (var i = 0; i < nperseg; i++) {
        sx[i] = x[xOff + start + i] * 1000.0;
        sy[i] = y[yOff + start + i] * 1000.0;
      }
      final mx = f32(_seqSum(sx) / nperseg.toDouble());
      final my = f32(_seqSum(sy) / nperseg.toDouble());
      for (var i = 0; i < nperseg; i++) {
        sx[i] = f32(f32(sx[i] - mx) * _win[i]);
        sy[i] = f32(f32(sy[i] - my) * _win[i]);
      }
      px.fillRange(0, nfft, 0.0);
      py.fillRange(0, nfft, 0.0);
      if (nfft >= nperseg) {
        for (var i = 0; i < nperseg; i++) {
          px[i] = sx[i];
          py[i] = sy[i];
        }
      } else {
        for (var c0 = 0; c0 < nperseg; c0 += nfft) {
          final c1 = math.min(c0 + nfft, nperseg);
          for (var i = 0; i < c1 - c0; i++) {
            px[i] = f32(sx[c0 + i] + px[i]);
            py[i] = f32(sy[c0 + i] + py[i]);
          }
        }
      }
      _rfft(px, a, xr, xi);
      _rfft(py, a, yr, yi);
      for (var k = 0; k < cnt; k++) {
        sxx[k] = f32(f32(f32(xi[k] * xi[k]) + f32(xr[k] * xr[k])) + sxx[k]);
        sre[k] = f32(f32(f32(yi[k] * xi[k]) + f32(yr[k] * xr[k])) + sre[k]);
        sim[k] = f32(f32(f32(yi[k] * xr[k]) - f32(yr[k] * xi[k])) + sim[k]);
      }
      pos = start + hop;
    }
    const eps = 1.1920928955078125e-07;
    final mag = Float32List(cnt), freq = Float32List(cnt);
    for (var k = 0; k < cnt; k++) {
      final num = f32(
        math.sqrt(f32(f32(sim[k] * sim[k]) + f32(sre[k] * sre[k]))),
      );
      mag[k] = f32(num / f32(sxx[k] + eps));
      freq[k] = f32(f32(k.toDouble() / nfft.toDouble()) * _fs);
    }
    return (mag, freq);
  }

  void _rfft(Float32List input, Float64List a, Float32List re, Float32List im) {
    for (var i = 0; i < nfft; i++) {
      a[i] = input[i];
    }
    _fft.forward(a);
    for (var i = 0; i < nfft ~/ 2; i++) {
      re[i] = a[2 * i];
      im[i] = -a[2 * i + 1];
    }
    re[nfft ~/ 2] = -im[0];
    im[0] = 0.0;
    im[nfft ~/ 2] = 0.0;
  }
}

double _seqSum(Float32List a) {
  var acc = 0.0;
  for (var i = 0; i < a.length; i++) {
    acc = f32(acc + a[i]);
  }
  return acc;
}
