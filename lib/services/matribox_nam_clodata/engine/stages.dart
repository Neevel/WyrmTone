import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp_helpers.dart';
import 'f32.dart';
import 'fdl_convolver.dart';
import 'filters.dart';
import 'spectral.dart';
import 'svml_float.dart';
import 'tables.dart';
import 'ucrt_float.dart';

/// Stages of the editor's identification engine (clean-room ports, each
/// verified bit-exactly against the reference implementation).
///
/// Inputs are the reference signal x and the model output y, both 48 kHz
/// float32, zero padded to [engineLength] samples. Outputs are four
/// non-linearity parameters plus the two FIR responses.

const int engineRate = 48000;

/// Padded length of both signals (70 s plus a 600 sample search margin).
const int engineLength = 70 * engineRate + 600;

const List<double> _hp = [
  0.9963043928146362,
  -1.9926087856292725,
  0.9963043928146362,
  -1.9925950765609741,
  0.9926224946975708,
];

const double _eps = 1.1920928955078125e-07;

class ModelParams {
  const ModelParams(this.peakPos, this.peakNeg, this.gainPos, this.gainNeg);

  final double peakPos, peakNeg, gainPos, gainNeg;

  List<double> get values => [peakPos, peakNeg, gainPos, gainNeg];
}

/// Sample chain used by all stages: unity biquad -> waveshaper -> high-pass
/// biquad.
Float32List shapeChain(Float32List x, ModelParams p) {
  final bq1 = Biquad(1.0, 0.0, 0.0, 0.0, 0.0);
  final out = Float32List(x.length);
  for (var i = 0; i < x.length; i++) {
    out[i] = bq1.process(x[i]);
  }
  return _waveshapeHp(out, p);
}

Float32List _waveshapeHp(Float32List sig, ModelParams p) {
  final ws = Waveshaper(p.peakPos, p.peakNeg, p.gainPos, p.gainNeg);
  final bq2 = Biquad(_hp[0], _hp[1], _hp[2], _hp[3], _hp[4]);
  for (var i = 0; i < sig.length; i++) {
    sig[i] = bq2.process(ws.process(sig[i]));
  }
  return sig;
}

double _ratioDiv(double num, double den) => f32(num * 1e6 / (den * 1e6 + _eps));

Float32List _slice(Float32List a, int off, int n) =>
    Float32List.sublistView(a, off, off + n);

// ---- preprocessing of the model output

/// Removes mean and linear trend (float32, sequential sums).
Float32List detrend(Float32List y) {
  final n = y.length;
  final nf = f32(n.toDouble());
  final mean = f32(seqSum(y) / nf);
  final c = Float32List(n);
  for (var i = 0; i < n; i++) {
    c[i] = f32(y[i] - mean);
  }
  var si = 0.0, sy = 0.0, siy = 0.0, sii = 0.0;
  for (var i = 0; i < n; i++) {
    final iv = (i + 1).toDouble();
    si = f32(si + iv);
    sy = f32(sy + c[i]);
    siy = f32(siy + f32(c[i] * iv));
    sii = f32(sii + f32(iv * iv));
  }
  final num = f32(f32(nf * siy) - f32(sy * si));
  final den = f32(f32(nf * sii) - f32(si * si));
  final slope = f32(num / den);
  final icpt = f32(f32(sy - f32(slope * si)) / nf);
  for (var i = 0; i < n; i++) {
    final iv = (i + 1).toDouble();
    c[i] = f32(c[i] - f32(f32(iv * slope) + icpt));
  }
  return c;
}

/// Latency of the model output: first sample above 0.01 in the 600 samples
/// after 6 s; 600 if there is none.
int findDelay(Float32List y) {
  for (var i = 0; i < 600; i++) {
    if (y[6 * engineRate + i].abs() > 0.01) return i;
  }
  return 600;
}

// ---- stage A: non-linearity parameters

ModelParams stageA(
  Float32List x,
  Float32List y,
  int n5, {
  void Function(String)? log,
}) {
  final bs = f32(engineRate * 0.1);
  final nb = (f32(n5.toDouble()) / bs).floor();
  final xm = Float32List(nb), pm = Float32List(nb), nm = Float32List(nb);
  for (var k = 0; k < nb; k++) {
    final a = f32(k.toDouble() * bs).toInt();
    final b = f32((k + 1).toDouble() * bs).toInt();
    var mx = -double.infinity, mp = -double.infinity, mn = double.infinity;
    for (var i = a; i < b; i++) {
      mx = math.max(mx, x[i].abs());
      mp = math.max(mp, y[i]);
      mn = math.min(mn, y[i]);
    }
    xm[k] = mx;
    pm[k] = math.max(0.0, mp);
    nm[k] = math.min(0.0, mn);
  }
  var pmax = 0.0, nmax = 0.0;
  for (var k = 0; k < nb; k++) {
    pmax = math.max(pmax, pm[k]);
    nmax = math.max(nmax, -nm[k]);
  }
  final thrP = pmax * 0.5, thrN = nmax * -0.5;
  var eP = 0, eN = 0;
  for (var k = 0; k < nb; k++) {
    if (pm[k] >= thrP) {
      eP = k + 1;
      break;
    }
  }
  for (var k = 0; k < nb; k++) {
    if (thrN >= nm[k]) {
      eN = k + 1;
      break;
    }
  }
  double dsum(Float32List a, int n) {
    var acc = 0.0;
    for (var i = 0; i < n; i++) {
      acc += a[i] * xm[i];
    }
    return acc;
  }

  double accx(int n) {
    var acc = 0.0;
    for (var i = 0; i < n; i++) {
      acc += xm[i] * xm[i];
    }
    return acc;
  }

  log?.call('A eP=$eP eN=$eN');
  final gp = dsum(pm, eP) / accx(eP);
  final gn = (-dsum(nm, eN)) / accx(eN);
  final aP = f32(f32(gp) / pmax);
  final aN = f32(f32(gn) / nmax);
  final u = Float32List(2 * nb), v = Float32List(2 * nb);
  for (var i = 0; i < nb; i++) {
    u[i] = -xm[nb - 1 - i];
    u[nb + i] = xm[i];
    v[i] = nm[nb - 1 - i];
    v[nb + i] = pm[i];
  }
  final grid = <double>[f32(0.8)];
  while (true) {
    final nxt = f32(grid.last + 0.05);
    if (!(1.2 >= nxt)) break;
    grid.add(nxt);
  }
  double err(double ap, double an) {
    var acc = 0.0;
    for (var i = 0; i < u.length; i++) {
      final pred = u[i] > 0
          ? f32(f32(1.0 - expf(-f32(u[i] * ap))) * pmax)
          : f32(f32(expf(f32(u[i] * an)) - 1.0) * nmax);
      final d = f32(v[i] - pred);
      acc = f32(acc + f32(d * d));
    }
    return acc;
  }

  var best = f32(3.4028235e38), sp = 1.0;
  for (final s in grid) {
    final e = err(f32(s * aP), aN);
    if (!(best < e)) {
      best = e;
      sp = s;
    }
  }
  final ap2 = f32(aP * sp);
  best = f32(3.4028235e38);
  var sn = 1.0;
  for (final s in grid) {
    final e = err(ap2, f32(s * aN));
    if (!(best < e)) {
      best = e;
      sn = s;
    }
  }
  log?.call('A scale+=$sp scale-=$sn');
  return ModelParams(pmax, nmax, ap2, f32(sn * aN));
}

// ---- stage C

class StageCResult {
  StageCResult(this.ratio, this.mag, this.freq);

  final Float32List ratio, mag, freq;
}

StageCResult stageC(
  Float32List x,
  Float32List y,
  ModelParams p,
  Float32List bMag,
) {
  const cnt = 1025;
  final xf = firFilter(fir50Taps48k, x);
  final w = shapeChain(xf, p);
  final (mag, freq) = WelchEstimator(
    6000,
    2048,
  ).magnitude(w, 0, y, 0, w.length);
  final t = gaussSmooth(mag, (cnt * 0.001).toInt());
  final m3 = gaussSmooth(t, (cnt * 0.005).toInt());
  var mx = 0.0;
  for (final v in bMag) {
    if (!v.isNaN) mx = f32(math.max(v, mx));
  }
  final thr = f32(mx * 0.001);
  final two = f32(thr + thr);
  final k = f32(f32(two - thr) / f32(two * two));
  for (var i = 0; i < cnt; i++) {
    final v = m3[i];
    if (two > v) m3[i] = f32(f32(f32(v * k) * v) + thr);
  }
  final ratio = Float32List(cnt);
  for (var i = 0; i < cnt; i++) {
    ratio[i] = _ratioDiv(bMag[i], m3[i]);
  }
  return StageCResult(ratio, m3, freq);
}

// ---- stage L: iterative fitting of the two FIR responses

class StageLState {
  StageLState(this.a9, this.a10, this.a11, this.fir1, this.fir2);

  Float32List a9, a10, a11, fir1, fir2;
}

/// One pass of the iterative fit; updates [st] in place.
void stageL(
  StageLState st,
  Float32List x,
  Float32List y,
  int iterations,
  Float32List b0Init,
  Float32List b1,
  Float32List q512,
  ModelParams p,
  double c20, {
  void Function(String)? log,
}) {
  const nb = 1025, nfft = 2048;
  var a9 = Float32List.fromList(st.a9);
  var a10 = Float32List.fromList(st.a10);
  var a11 = Float32List.fromList(st.a11);
  var a12 = Float32List.fromList(st.fir1);
  var a13 = Float32List.fromList(st.fir2);
  var b0 = Float32List.fromList(b0Init);
  var b7 = Float32List.fromList(b0);
  Float32List? b8, b9, b11, b12;
  var g = 1.0, best = 100.0;
  final n = x.length;
  final welch = WelchEstimator(6000, nfft);
  final lowClamp = f32FromBits(0x3e4ccccd);
  for (var k = 0; k < iterations; k++) {
    for (var i = 0; i < nb; i++) {
      var v = powf(b0[i], f32(g * b1[i]));
      if (v > 5.0) v = 5.0;
      if (0.2 > v) v = lowClamp;
      b0[i] = v;
    }
    g = f32(g * 0.8999999761581421);
    final (b2, b4) = melResample(b0, a11, nb, nb);
    (b0, a11) = melResample(b2, b4, nb, nb);
    // the editor multiplies the a10 buffer in place
    for (var i = 0; i < nb; i++) {
      a10[i] = f32(b0[i] * a10[i]);
      a9[i] = f32(a9[i] / b0[i]);
    }
    a9 = geoSmooth(a9, nb, 60.0, c20);
    final (b10, _) = melResample(a9, a11, nb, 128);
    a12 = designFir(b10, 128, 128);
    var sig = Float32List(n);
    final bq1 = Biquad(1.0, 0.0, 0.0, 0.0, 0.0);
    for (var i = 0; i < n; i++) {
      sig[i] = bq1.process(x[i]);
    }
    sig = firFilter(a12, sig);
    sig = _waveshapeHp(sig, p);
    final (b5, f1) = welch.magnitude(sig, 0, y, 0, n);
    a11 = f1;
    final b2r = Float32List(nb);
    for (var i = 0; i < nb; i++) {
      b2r[i] = _ratioDiv(b5[i], a10[i]);
    }
    (b0, a11) = melResample(b2r, a11, nb, nb);
    a13 = designFir(b5, nb, nfft);
    sig = firFilter(a13, sig);
    final (b6, f2) = welch.magnitude(sig, 0, y, 0, n);
    a11 = f2;
    final b3 = interp1(a11, b6, q512);
    var acc = 0.0;
    for (var i = 0; i < 512; i++) {
      acc = f32(acc + logf(f32(b3[i] + _eps)).abs());
    }
    final err = f32(acc * 0.001953125);
    if (best > err) {
      log?.call('L it=$k err=$err improved');
      best = err;
      b7 = Float32List.fromList(b0);
      b11 = Float32List.fromList(a12);
      b12 = Float32List.fromList(a13);
      b8 = Float32List.fromList(a9);
      b9 = Float32List.fromList(a10);
    } else if (err > best * 1.2) {
      log?.call('L it=$k err=$err RESET');
      b0 = Float32List.fromList(b7);
      a12 = Float32List.fromList(b11!);
      a13 = Float32List.fromList(b12!);
      a9 = Float32List.fromList(b8!);
      a10 = Float32List.fromList(b9!);
      g = f32(g * 0.5);
    } else {
      log?.call('L it=$k err=$err kept');
    }
  }
  if (b11 == null) log?.call('L never improved');
  if (b11 != null) {
    a12 = b11;
    a13 = b12!;
    a9 = b8!;
    a10 = b9!;
  }
  st.a9 = a9;
  st.a10 = a10;
  st.a11 = a11;
  st.fir1 = a12;
  st.fir2 = a13;
}

// ---- stage F: final correction of the second FIR response

Float32List _hammingF(int n) {
  final w = Float32List(n);
  final twoPi = f32(6.2831854820251465);
  final den = (n - 1).toDouble();
  final ne = n - (n & 1);
  for (var i = 0; i < ne; i++) {
    final ang = f32(f32(i.toDouble() * twoPi) / den);
    w[i] = f32(0.54 - svmlCosf(ang) * 0.46);
  }
  for (var i = ne; i < n; i++) {
    final ang = f32(f32(i.toDouble() * twoPi) / den);
    w[i] = f32(0.54 - cosf(ang) * 0.46);
  }
  return w;
}

Float32List _clampF(Float32List r) {
  final out = Float32List.fromList(r);
  final low = f32FromBits(0x3dcccccd);
  for (var i = 0; i < out.length; i++) {
    var v = out[i];
    if (v > 10.0) v = 10.0;
    if (0.1 > v) v = low;
    out[i] = v;
  }
  return out;
}

Float32List stageF(
  Float32List x,
  Float32List y,
  Float32List fir1,
  Float32List fir2,
  ModelParams p,
) {
  const seg = 4800, nb = seg ~/ 2 + 1, k = 2048;
  final n = x.length;
  final bq1 = Biquad(1.0, 0.0, 0.0, 0.0, 0.0);
  var sig = Float32List(n);
  for (var i = 0; i < n; i++) {
    sig[i] = bq1.process(x[i]);
  }
  sig = firFilter(fir1, sig);
  sig = _waveshapeHp(sig, p);
  final s2 = firFilter(fir2, sig);
  final fx = foldSegments(s2, n, seg);
  final fy = foldSegments(y, n, seg);
  final mx = f32(seqSum(fx) / seg.toDouble());
  final my = f32(seqSum(fy) / seg.toDouble());
  final w = _hammingF(seg);
  for (var i = 0; i < seg; i++) {
    fx[i] = f32(w[i] * f32(fx[i] - mx));
    fy[i] = f32(w[i] * f32(fy[i] - my));
  }
  final (sT, cT) = trigTables(seg);
  final (xr, xi) = dftRealUnscaled(fx, seg, sT, cT, nb);
  final (yr, yi) = dftRealUnscaled(fy, seg, sT, cT, nb);
  final magA = Float32List(nb), magB = Float32List(nb);
  for (var i = 0; i < nb; i++) {
    magA[i] = f32(math.sqrt(f32(f32(xr[i] * xr[i]) + f32(xi[i] * xi[i]))));
    magB[i] = f32(math.sqrt(f32(f32(yi[i] * yi[i]) + f32(yr[i] * yr[i]))));
  }
  final grid = linspace32(0.0, 24000.0, nb);
  final (d1, _) = melResample(magA, grid, nb, nb);
  final (d2, _) = melResample(magB, grid, nb, nb);
  final r0 = Float32List(nb);
  for (var i = 0; i < nb; i++) {
    r0[i] = _ratioDiv(d2[i], d1[i]);
  }
  final r = _clampF(gaussSmooth(_clampF(r0), (nb * 0.1).toInt()));
  final fir2n = shapeWithCurve(fir2, r, linspace32(0.0, 24000.0, nb), nb, k);
  final sigf = firFilter(fir2n, sig);
  final sqy = Float32List(n), sqs = Float32List(n);
  for (var i = 0; i < n; i++) {
    sqy[i] = f32(y[i] * y[i]);
    sqs[i] = f32(sigf[i] * sigf[i]);
  }
  final scale = f32(f32(math.sqrt(seqSum(sqy))) / f32(math.sqrt(seqSum(sqs))));
  final out = Float32List(k);
  for (var i = 0; i < k; i++) {
    out[i] = f32(fir2n[i] * scale);
  }
  return out;
}

// ---- whole engine

class EngineResult {
  EngineResult(this.params, this.fir1, this.fir2x4);

  final ModelParams params;

  /// First response, 128 taps at 48 kHz.
  final Float32List fir1;

  /// Second response, 2048 taps at 48 kHz, already scaled by four.
  final Float32List fir2x4;
}

Float32List _makeQ512() {
  final m0 = f32(log10f(f32(1.1142857074737549)) * 2595.0);
  final m1 = f32(log10f(f32(15.285714149475098)) * 2595.0);
  final g = linspace32(m0, m1, 512);
  final q = Float32List(512);
  q[0] = 80.0;
  for (var i = 1; i < 511; i++) {
    q[i] = f32(f32(powf(10.0, f32(g[i] / 2595.0)) - 1.0) * 700.0);
  }
  q[511] = 10000.0;
  return q;
}

/// Runs the complete identification. [x] and [yRaw] must have [engineLength]
/// samples (zero padded); [log] receives coarse progress messages.
EngineResult runEngine(
  Float32List x,
  Float32List yRaw, {
  void Function(String)? log,
}) {
  const nb = 1025, fs = engineRate;
  final y = detrend(yRaw);
  final d = findDelay(y);
  log?.call('delay $d');
  final p = stageA(
    _slice(x, 0, 5 * fs),
    _slice(y, d, 5 * fs),
    5 * fs,
    log: log,
  );
  log?.call('params ${p.values}');
  final bMag = WelchEstimator(6000, 2048)
      .magnitude(
        shapeChain(Float32List.fromList(_slice(x, 6 * fs, 15 * fs)), p),
        0,
        y,
        6 * fs + d,
        15 * fs,
      )
      .$1;
  log?.call('B done');
  Float32List xs(int sec, int n) =>
      Float32List.fromList(_slice(x, sec * fs, n));
  Float32List ys(int sec, int n) =>
      Float32List.fromList(_slice(y, sec * fs + d, n));
  final c = stageC(xs(23, 240000), ys(23, 240000), p, bMag);
  log?.call('C done');
  final b0 = Float32List(nb)..fillRange(0, nb, 1.0);
  final b1 = Float32List(nb)..fillRange(0, nb, 1.0);
  final c20 = f32(f32(2.0) / f32(fs.toDouble()));
  final esi = f32(f32(c20 * 80.0) * f32(nb.toDouble())).floor();
  final tail = linspace32(1.0, 0.5, nb - esi + 1);
  for (var i = 0; i < tail.length; i++) {
    b1[esi - 1 + i] = tail[i];
  }
  final q512 = _makeQ512();
  final st = StageLState(
    c.ratio,
    c.mag,
    c.freq,
    Float32List(128)..[0] = 1.0,
    Float32List(2048)..[0] = 1.0,
  );
  for (final (sec, n, it) in [
    (23, 240000, 3),
    (6, 720000, 2),
    (30, 960000, 5),
  ]) {
    stageL(st, xs(sec, n), ys(sec, n), it, b0, b1, q512, p, c20, log: log);
    log?.call('L $sec done');
  }
  final f2 = stageF(xs(50, 960000), ys(50, 960000), st.fir1, st.fir2, p);
  log?.call('F done');
  final f2x4 = Float32List(f2.length);
  for (var i = 0; i < f2.length; i++) {
    f2x4[i] = f32(f2[i] * 4.0);
  }
  return EngineResult(p, st.fir1, f2x4);
}
