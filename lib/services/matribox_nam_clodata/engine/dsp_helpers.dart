import 'dart:math' as math;
import 'dart:typed_data';

import 'f32.dart';
import 'svml_float.dart';
import 'ucrt_float.dart';

/// Building blocks of the editor's engine (clean-room ports, verified stage by
/// stage against the reference implementation). Everything operates on
/// single-precision buffers with the exact operation order of the original.

/// Sequential float32 sum of `a[0..n)`.
double seqSum(Float32List a, [int? n]) {
  var acc = 0.0;
  final len = n ?? a.length;
  for (var i = 0; i < len; i++) {
    acc = f32(acc + a[i]);
  }
  return acc;
}

/// `count` points from [a] to [b]: cumulative float32 steps, last point forced.
Float32List linspace32(double a, double b, int count) {
  final step = f32(f32(b - a) / (count - 1).toDouble());
  final out = Float32List(count);
  out[0] = a;
  for (var i = 1; i < count; i++) {
    out[i] = f32(step + out[i - 1]);
  }
  out[count - 1] = b;
  return out;
}

// ---- table-driven O(n^2) DFT family (sequential in the summation index)

/// Real part of the inverse table DFT of a complex sequence, scaled by 1/n.
Float32List idftReal(
  Float32List re,
  Float32List im,
  int n,
  Float32List sinT,
  Float32List cosT,
) {
  final inv = f32(1.0 / n);
  final out = Float32List(n);
  for (var k = 0; k < n; k++) {
    var acc = 0.0;
    var idx = 0;
    for (var j = 0; j < n; j++) {
      final t = f32(f32(cosT[idx] * re[j]) - f32(sinT[idx] * im[j]));
      acc = f32(acc + t);
      idx += k;
      if (idx >= n) idx -= n;
    }
    out[k] = f32(acc * inv);
  }
  return out;
}

/// Real -> complex table DFT of the first [kmax] bins, `(sum x cos, -sum x sin)`.
(Float32List, Float32List) dftRealUnscaled(
  Float32List x,
  int n,
  Float32List sinT,
  Float32List cosT,
  int kmax,
) {
  final ar = Float32List(kmax), ai = Float32List(kmax);
  for (var k = 0; k < kmax; k++) {
    var accR = 0.0, accI = 0.0;
    var idx = 0;
    for (var j = 0; j < n; j++) {
      accR = f32(accR + f32(x[j] * cosT[idx]));
      accI = f32(accI - f32(x[j] * sinT[idx]));
      idx += k;
      if (idx >= n) idx -= n;
    }
    ar[k] = accR;
    ai[k] = accI;
  }
  return (ar, ai);
}

/// Real -> complex table DFT scaled by 1/n, `(sum x cos, sum x sin) / n`.
(Float32List, Float32List) dftRealScaled(
  Float32List x,
  int n,
  Float32List sinT,
  Float32List cosT,
) {
  final inv = f32(1.0 / n);
  final ar = Float32List(n), ai = Float32List(n);
  for (var k = 0; k < n; k++) {
    var accR = 0.0, accI = 0.0;
    var idx = 0;
    for (var j = 0; j < n; j++) {
      accR = f32(accR + f32(x[j] * cosT[idx]));
      accI = f32(accI + f32(x[j] * sinT[idx]));
      idx += k;
      if (idx >= n) idx -= n;
    }
    ar[k] = f32(accR * inv);
    ai[k] = f32(accI * inv);
  }
  return (ar, ai);
}

/// Complex -> complex forward table DFT (unscaled).
(Float32List, Float32List) dftComplex(
  Float32List re,
  Float32List im,
  int n,
  Float32List sinT,
  Float32List cosT,
) {
  final ar = Float32List(n), ai = Float32List(n);
  for (var k = 0; k < n; k++) {
    var accR = 0.0, accI = 0.0;
    var idx = 0;
    for (var j = 0; j < n; j++) {
      final tr = f32(f32(im[j] * sinT[idx]) + f32(re[j] * cosT[idx]));
      final ti = f32(f32(im[j] * cosT[idx]) - f32(re[j] * sinT[idx]));
      accR = f32(accR + tr);
      accI = f32(accI + ti);
      idx += k;
      if (idx >= n) idx -= n;
    }
    ar[k] = accR;
    ai[k] = accI;
  }
  return (ar, ai);
}

/// sin/cos tables of [n] entries: the first `n ~/ 2` from the double sin/cos
/// of float angles, the rest as the negated first half.
(Float32List, Float32List) trigTables(int n) {
  final step = f32(f32(6.2831854820251465) / n.toDouble());
  final h = f32(n * 0.5).toInt();
  final s = Float32List(n), c = Float32List(n);
  for (var k = 0; k < h; k++) {
    final ang = f32(k.toDouble() * step);
    s[k] = math.sin(ang);
    c[k] = math.cos(ang);
  }
  for (var i = h; i < n; i++) {
    s[i] = -s[i - h];
    c[i] = -c[i - h];
  }
  return (s, c);
}

/// One-sided spectrum `out[k] = in[k] + conj(in[n-k])`.
(Float32List, Float32List) oneSided(Float32List re, Float32List im, int n) {
  final orr = Float32List(n), oi = Float32List(n);
  if (n < 3) {
    for (var i = 0; i < n; i++) {
      orr[i] = re[i];
      oi[i] = im[i];
    }
    return (orr, oi);
  }
  orr[0] = re[0];
  oi[0] = im[0];
  final h = n.isOdd ? (n + 1) ~/ 2 : n ~/ 2;
  for (var k = 1; k < h; k++) {
    orr[k] = f32(re[k] + re[n - k]);
    oi[k] = f32(im[k] - im[n - k]);
  }
  if (n.isEven) {
    orr[h] = re[h];
    oi[h] = f32(-im[h]);
  }
  return (orr, oi);
}

/// Copy of `x[0..n)` with entries below `10^(0.05*thrDb) * max|x|` raised to
/// that floor (only for negative [thrDb]).
Float32List floorRelative(Float32List x, int n, double thrDb) {
  final out = Float32List(n);
  var mx = 0.0;
  for (var i = 0; i < n; i++) {
    out[i] = x[i];
    final v = x[i].abs();
    if (!v.isNaN) mx = f32(math.max(v, mx));
  }
  if (mx != 0 && !(f32(thrDb) >= 0)) {
    final e = f32(f32(thrDb) * f32(0.05000000074505806));
    final p = math.pow(10.0, e).toDouble();
    final fl = f32(p * mx);
    for (var i = 0; i < n; i++) {
      if (fl > x[i].abs()) out[i] = fl;
    }
  }
  return out;
}

/// In-place geometric neighbour smoothing of `a[0..m]`, `m = floor(x3*c*n)`.
Float32List geoSmooth(Float32List a, int n, double x3, double c20ec8) {
  final out = Float32List.fromList(a);
  final m = f32(f32(f32(x3) * f32(c20ec8)) * n.toDouble()).floor();
  if (m > 1) {
    double sq(double v) => f32(math.sqrt(v));
    out[0] = sq(f32(sq(f32(out[0] * out[1])) * out[0]));
    for (var i = 1; i < m; i++) {
      out[i] = sq(f32(sq(f32(out[i - 1] * out[i + 1])) * out[i]));
    }
  }
  return out;
}

/// Alias-fold: `out[j] = sum_s x[s*seg + j]` over the full segments.
Float32List foldSegments(Float32List x, int total, int seg) {
  final out = Float32List(seg);
  for (var s = 0; s < total ~/ seg; s++) {
    for (var j = 0; j < seg; j++) {
      out[j] = f32(x[s * seg + j] + out[j]);
    }
  }
  return out;
}

// ---- resampling / smoothing of magnitude curves

/// Normalised Gaussian smoothing with window [m] (edge-normalised).
Float32List gaussSmooth(Float32List x, int m) {
  final n = x.length;
  final c = (m * 0.5).ceil();
  final s6 = 5.0 / m;
  final g = List<double>.filled(m, 0.0);
  var acc = 0.0;
  for (var i = 0; i < m; i++) {
    final t = (i + 1 - c) * s6;
    final v = math.exp((t * -0.5) * t);
    g[i] = v;
    acc += v;
  }
  final scale = 1000000.0 / acc;
  final len = m.isOdd ? m : m + 1;
  final k2 = List<double>.filled(len, 0.0);
  for (var k = 0; k < m; k++) {
    k2[k] = scale * g[m - 1 - k];
  }
  final h = (len * 0.5).ceil();
  final radius = h - 1;
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    if (i - radius >= 0 && i + radius < n) {
      var num = 0.0;
      for (var kk = 0; kk < len; kk++) {
        num = num + x[i - radius + kk] * k2[kk];
      }
      out[i] = num * 1e-06;
    } else {
      final lo = -math.min(radius, i);
      final hi = math.min(n - 1 - i, radius);
      var num = 0.0, den = 0.0;
      for (var off = lo; off <= hi; off++) {
        final kv = k2[radius + off];
        den = den + kv;
        num = num + x[i + off] * kv;
      }
      out[i] = num / den;
    }
  }
  return out;
}

/// Piecewise-linear interpolation as computed by the engine (float32 math);
/// queries below the first sample return FLT_MAX.
Float32List interp1(Float32List x, Float32List y, Float32List xq) {
  final n = x.length;
  final slope = Float32List(n), icpt = Float32List(n);
  for (var i = 0; i < n - 1; i++) {
    final s = f32(f32(y[i + 1] - y[i]) / f32(x[i + 1] - x[i]));
    slope[i] = s;
    icpt[i] = f32(y[i] - f32(s * x[i]));
  }
  if (n >= 2) {
    slope[n - 1] = slope[n - 2];
    icpt[n - 1] = icpt[n - 2];
  }
  final out = Float32List(xq.length);
  const fltMax = 3.4028234663852886e+38;
  for (var qi = 0; qi < xq.length; qi++) {
    final q = xq[qi];
    var best = fltMax;
    var bi = -1;
    for (var i = 0; i < n; i++) {
      final d = f32(q - x[i]);
      if (d < 0) continue;
      if (best > d) {
        best = d;
        bi = i;
      }
    }
    out[qi] = bi < 0 ? fltMax : f32(f32(slope[bi] * q) + icpt[bi]);
  }
  return out;
}

// ---- mel-scale resampling of a magnitude curve (engine helper "mel")

double _mel(double f) => f32(log10f(f32(f32(f / 700.0) + 1.0)) * 2595.0);

Float32List _pow10Grid(Float32List y) {
  final n = y.length;
  final out = Float32List(n);
  final nv = n - (n & 3);
  for (var i = 0; i < nv; i++) {
    out[i] = svmlPowf(10.0, y[i]);
  }
  for (var i = nv; i < n; i++) {
    out[i] = powf(10.0, y[i]);
  }
  return out;
}

Float32List _melToHz(Float32List g) {
  final n = g.length;
  final scaled = Float32List(n);
  for (var i = 0; i < n; i++) {
    scaled[i] = f32(g[i] / 2595.0);
  }
  final p = _pow10Grid(scaled);
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = f32(f32(p[i] - 1.0) * 700.0);
  }
  return out;
}

/// Mel-smoothed resampling of a spectrum: values at [m] linear-frequency
/// points plus that grid.
(Float32List, Float32List) melResample(
  Float32List val,
  Float32List freq,
  int n,
  int m,
) {
  final mel0 = _mel(freq[0]), melN = _mel(freq[n - 1]);
  final g1 = linspace32(mel0, melN, n);
  final hz1 = _melToHz(g1);
  hz1[0] = freq[0];
  hz1[n - 1] = freq[n - 1];
  final g2 = linspace32(mel0, melN, m);
  final hz2 = _melToHz(g2);
  hz2[0] = freq[0];
  hz2[m - 1] = freq[n - 1];
  final lin = linspace32(freq[0], freq[n - 1], m);
  final db = Float32List(n);
  final nv = n - (n & 3);
  for (var i = 0; i < nv; i++) {
    db[i] = f32(svmlLog10f(val[i]) * 20.0);
  }
  for (var i = nv; i < n; i++) {
    db[i] = f32(log10f(val[i]) * 20.0);
  }
  final sm1 = gaussSmooth(db, (n * 0.002).toInt());
  final y1 = interp1(freq, sm1, hz1);
  final sm2 = gaussSmooth(y1, 2 * (n ~/ m));
  final y2 = n != m ? interp1(g1, sm2, g2) : sm2;
  final res = interp1(hz2, y2, lin);
  final scaled = Float32List(m);
  for (var i = 0; i < m; i++) {
    scaled[i] = f32(res[i] * 0.05000000074505806);
  }
  return (_pow10Grid(scaled), lin);
}

// ---- minimum-phase FIR design

/// Minimum-phase complex spectrum from a magnitude curve (`n` points -> `nfft`).
(Float32List, Float32List) minPhaseSpectrum(Float32List mag, int n, int nfft) {
  final a = floorRelative(mag, n, -100.0);
  const eps = 1.1920928955078125e-07;
  final y = Float32List(n);
  final nv = n - (n & 3);
  for (var i = 0; i < nv; i++) {
    y[i] = svmlLogf(f32(a[i] + eps));
  }
  for (var i = nv; i < n; i++) {
    y[i] = logf(f32(a[i] + eps));
  }
  Float32List r;
  if (n != nfft) {
    final g1 = linspace32(0.0, (n - 1).toDouble(), n);
    final g2 = linspace32(0.0, (n - 1).toDouble(), nfft);
    r = interp1(g1, y, g2);
    for (var i = 0; i < nfft ~/ 2; i++) {
      r[i] = r[nfft - 1 - i];
    }
  } else {
    r = Float32List.fromList(y);
  }
  final (sT, cT) = trigTables(nfft);
  final (xr, xi) = dftRealScaled(r, nfft, sT, cT);
  final (fr, fi) = oneSided(xr, xi, nfft);
  final (gr, gi) = dftComplex(fr, fi, nfft, sT, cT);
  final outR = Float32List(nfft), outI = Float32List(nfft);
  for (var k = 0; k < nfft; k++) {
    final ex = expf(gr[k]);
    outR[k] = f32(cosf(gi[k]) * ex);
    outI[k] = f32(sinf(gi[k]) * ex);
  }
  return (outR, outI);
}

/// FIR of [m] taps from a magnitude curve: mirror, minimum-phase spectrum,
/// table IDFT, mean removal, energy normalisation.
Float32List designFir(Float32List curve, int n, int m) {
  final l = 2 * n - 2;
  final sym = Float32List(l);
  for (var i = 0; i < n; i++) {
    sym[i] = curve[i];
  }
  for (var i = n; i < l; i++) {
    sym[i] = curve[l - i];
  }
  final (cr, ci) = minPhaseSpectrum(sym, l, l);
  final (sT, cT) = trigTables(l);
  final h = idftReal(cr, ci, l, sT, cT);
  final sq = Float32List(l);
  for (var i = 0; i < l; i++) {
    sq[i] = f32(h[i] * h[i]);
  }
  final normA = f32(math.sqrt(seqSum(sq)));
  final out = Float32List(m);
  for (var i = 0; i < m; i++) {
    out[i] = h[i];
  }
  final mean = f32(seqSum(out) / m.toDouble());
  for (var i = 0; i < m; i++) {
    out[i] = f32(out[i] - mean);
  }
  final sq2 = Float32List(m);
  for (var i = 0; i < m; i++) {
    sq2[i] = f32(out[i] * out[i]);
  }
  final normB = f32(math.sqrt(seqSum(sq2)));
  final scale = f32(normA / normB);
  for (var i = 0; i < m; i++) {
    out[i] = f32(out[i] * scale);
  }
  return out;
}

/// Shapes [x] (K samples) with a 256-tap FIR designed from (val, freq):
/// convolution (first K outputs) followed by mean removal.
Float32List shapeWithCurve(
  Float32List x,
  Float32List val,
  Float32List freq,
  int nIn,
  int k,
) {
  final (v256, _) = melResample(val, freq, nIn, 256);
  final h = designFir(v256, 256, 256);
  final y = Float32List(k + 255);
  for (var i = 0; i < k; i++) {
    final xi = x[i];
    for (var j = 0; j < 256; j++) {
      y[i + j] = f32(f32(h[j] * xi) + y[i + j]);
    }
  }
  final out = Float32List(k);
  for (var i = 0; i < k; i++) {
    out[i] = y[i];
  }
  final mean = f32(seqSum(out) / k.toDouble());
  for (var i = 0; i < k; i++) {
    out[i] = f32(out[i] - mean);
  }
  return out;
}
