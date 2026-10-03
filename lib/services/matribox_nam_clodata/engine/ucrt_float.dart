import 'dart:math' as math;

import 'f32.dart';
import 'tables.dart';

/// Clean-room ports of the single-precision math functions of the Windows UCRT
/// (FMA code path) that the editor's engine calls: `expf`, `cosf`, `sinf`,
/// `logf`, `log10f`, `powf`. They are not correctly rounded, so the exact
/// algorithm matters for bit-identical results. Inputs and outputs are floats
/// held in doubles.

double _rne(double t) {
  final r = t.roundToDouble();
  if ((t - t.truncateToDouble()).abs() == 0.5) {
    // Ties to even.
    final f = t.floorToDouble();
    return (f % 2 == 0) ? f : f + 1;
  }
  return r;
}

double _pow2(int e) => f64FromBits((e + 1023) << 52);

const double _c64ln2 = 92.33248261689366;
const double _cLn2_64 = 0.010830424696249145;

double expf(double x32) {
  final x = x32;
  if (x.isNaN) return x;
  if (x < -104.0) return 0.0;
  if (x > 89.0) return double.infinity;
  final t = x * _c64ln2;
  final n = t.abs() < 2147483648.0 ? _rne(t).toInt() : 0;
  final r = fma64(-n.toDouble(), _cLn2_64, x);
  final j = n & 63;
  final e = (n - j) >> 6;
  final p = fma64(1 / 6, r, 0.5);
  final q = fma64(r * r, p, r);
  final s = ucrtTe64[j];
  final y = fma64(q, s, s) * _pow2(e);
  return f32(y);
}

const double _twoOverPi = 0.6366197723675814;
const double _c1 = 1.5707963267341256;
const double _c2 = 6.077100506506192e-11;
const List<double> _s = [
  -0.0001984126984126984,
  2.7557319223985893e-06,
  0.008333333333333333,
  -0.16666666666666666,
];
const List<double> _k = [
  2.4801587301587298e-05,
  -2.755731922398589e-07,
  -0.0013888888888888887,
  0.041666666666666664,
];

double _sinPoly(double r) {
  final r2 = r * r;
  var p = fma64(r2, _s[1], _s[0]);
  p = fma64(p, r2, _s[2]);
  p = fma64(p, r2, _s[3]);
  final r3 = r * r2;
  return fma64(p, r3, r);
}

double _cosPoly(double r) {
  final r2 = r * r;
  final base = 1.0 - r2 * 0.5;
  var p = fma64(r2, _k[1], _k[0]);
  p = fma64(p, r2, _k[2]);
  p = fma64(p, r2, _k[3]);
  final r4 = r2 * r2;
  return fma64(p, r4, base);
}

(int, double) _reduce(double a) {
  final n = fma64(_twoOverPi, a, 0.5).truncate();
  final nd = n.toDouble();
  final t = fma64(-nd, _c1, a);
  return (n, t - nd * _c2);
}

double cosf(double x32) {
  final ax = f32Bits(x32.abs());
  if (ax >= 0x7f800000) return double.nan;
  final a = x32.abs();
  if (ax <= 0x3f490fdb) {
    if (ax >= 0x3c000000) return f32(_cosPoly(a));
    if (ax >= 0x39000000) return f32(fma64(-(a * 0.5), a, 1.0));
    return 1.0;
  }
  final (n, r) = _reduce(a);
  final q = n & 3;
  var v = (q & 1) != 0 ? _sinPoly(r) : _cosPoly(r);
  if ((((q + 1) >> 1) & 1) != 0) v = -v;
  return f32(v);
}

double sinf(double x32) {
  final ax = f32Bits(x32.abs());
  if (ax >= 0x7f800000) return double.nan;
  final a = x32.abs();
  if (ax <= 0x3f490fdb) {
    if (ax >= 0x3c000000) return f32(_sinPoly(x32));
    if (ax >= 0x39000000) return f32(fma64(-(x32 * x32 * x32), 1 / 6, x32));
    return x32;
  }
  final (n, r) = _reduce(a);
  final q = n & 3;
  var v = (q & 1) != 0 ? _cosPoly(r) : _sinPoly(r);
  final neg = (q == 2 || q == 3) != x32.isNegative;
  if (neg) v = -v;
  return f32(v);
}

// ---- logf / log10f

double _logTail(double x) {
  final xs = f32(2.0 + x);
  final q = f32(x / xs);
  final xm = f32(x * q);
  final q2 = f32(q + q);
  final sq = f32(q2 * q2);
  final cube = f32(q2 * sq);
  var pp = fma32(sq, f32(0.012500000186264515), f32(0.0833333358168602));
  pp = fma32(pp, cube, -xm);
  return pp;
}

double logf(double x32) {
  if (!(x32 > 0)) return x32 < 0 ? double.nan : double.negativeInfinity;
  final xb = f32Bits(x32);
  final ecx = xb >> 23;
  final mant = xb & 0x7fffff;
  if (ecx == 0) throw UnsupportedError('denormal');
  final e = (ecx - 127).toDouble();
  final d = f32(x32 - 1.0).abs();
  if (d >= f32(0.0625)) {
    final m = f32FromBits(mant | 0x3f000000);
    final idx = (mant >> 16) + ((mant >> 15) & 1);
    final c = f32FromBits((idx << 16) | 0x3f000000);
    final r = f32(f32(c - m) * logfLt1[idx]);
    final p = fma32(f32(0.3333333432674408), r, 0.5);
    final r2 = f32(r * r);
    final t = fma32(p, r2, r);
    final u = fma32(f32(3.194618329871446e-05), e, -t);
    final hi = fma32(f32(0.693115234375), e, logfLt3[idx]);
    final lo = f32(u + logfLt2[idx]);
    return f32(hi + lo);
  }
  final x = f32(x32 - 1.0);
  final pp = _logTail(x);
  return f32(x + pp);
}

double log10f(double x32) {
  if (!(x32 > 0)) return x32 < 0 ? double.nan : double.negativeInfinity;
  final xb = f32Bits(x32);
  final ecx = xb >> 23;
  final mant = xb & 0x7fffff;
  if (ecx == 0) throw UnsupportedError('denormal');
  final e = (ecx - 127).toDouble();
  final d = f32(x32 - 1.0).abs();
  if (d >= f32(0.0625)) {
    final m = f32FromBits(mant | 0x3f000000);
    final idx = (mant >> 16) + ((mant >> 15) & 1);
    final c = f32FromBits((idx << 16) | 0x3f000000);
    final r = f32(f32(c - m) * logfLt1[idx]);
    final p = fma32(f32(0.3333333432674408), r, f32(0.5));
    final r2 = f32(r * r);
    var t = fma32(p, r2, r);
    t = f32(t * f32(0.4342944920063019));
    final u = fma32(f32(0.0002487456367816776), e, -t);
    final hi = fma32(f32(0.30078125), e, log10fGt3[idx]);
    final lo = f32(u + log10fGt2[idx]);
    return f32(hi + lo);
  }
  final x = f32(x32 - 1.0);
  var pp = _logTail(x);
  final xhi = f32FromBits(f32Bits(x) & 0xffff0000);
  final xlo = f32(x - xhi);
  pp = f32(pp + xlo);
  final r1 = f32(pp * f32(0.43359375));
  var r0 = f32(xhi * f32(0.0007007318781688809));
  final r5 = f32(xhi * f32(0.43359375));
  r0 = fma32(pp, f32(0.0007007318781688809), r0);
  r0 = f32(r0 + r1);
  return f32(r0 + r5);
}

// ---- powf (positive finite x, finite y)

const double _ln2 = 0.6931471805599453;
const double _l64 = 0.010830424696249145;
const double _k64 = 92.33248261689366;
const double _pc0 = 0.012500000003771751;
const double _pc1 = 0.0004348877777076146;
const double _pc2 = 0.08333333333333179;
const double _pc3 = 0.0022321399879194482;

double powf(double x32, double y32) {
  final x = x32;
  final y = y32;
  final xb = f32Bits(x);
  final xm1 = x - 1.0;
  final near = xb < 0x3f880000 && xm1.abs() < 0.0625;
  double v;
  int n;
  if (near) {
    final s = xm1 / (xm1 + 2.0);
    final sxm = s * xm1;
    final s2 = s + s;
    final vv = s2 * s2;
    final a3 = s2 * vv;
    var p0 = vv * _pc0;
    var p1 = vv * _pc1;
    p0 += _pc2;
    p1 += _pc3;
    final v2 = vv * vv;
    final a7 = v2 * a3;
    final t0 = a3 * p0;
    final t1 = a7 * p1;
    final lnx = xm1 + ((t1 + t0) - sxm);
    final t = y * lnx;
    if (t > 88.72283935546875 || t <= -103.2789306640625) {
      throw UnsupportedError('powf range');
    }
    n = _rne(t * _k64).toInt();
    final r = t - n.toDouble() * _l64;
    final p = (1.0 / 6.0) * r + 0.5;
    var q = r * r;
    q = q * p + r;
    final tt = ucrtTe64[n & 63];
    v = q * tt + tt;
  } else {
    final bits = f64Bits(x);
    final mant = bits & 0x000fffffffffffff;
    final idx = (mant >> 44) + ((mant >> 43) & 1);
    final c0 = f64FromBits((idx | 0x3fe00) << 44);
    final m = f64FromBits(mant | 0x3fe0000000000000);
    final e = ((bits >> 52) & 0x7ff) - 1023;
    final z = (c0 - m) * powInv257[idx];
    var p = fma64(1.0 / 3.0, z, 0.5);
    p = fma64(p, z, 1.0);
    final pl = z * p;
    final l = (e.toDouble() * _ln2 + powLog257[idx]) - pl;
    final t = y * l;
    if (t > 88.72283935546875 || t <= -103.2789306640625) {
      throw UnsupportedError('powf range');
    }
    n = _rne(t * _k64).toInt();
    final r = fma64(-n.toDouble(), _l64, t);
    var p2 = fma64(1.0 / 6.0, r, 0.5);
    p2 = fma64(p2, r, 1.0);
    final q = r * p2;
    final tt = ucrtTe64[n & 63];
    v = fma64(q, tt, tt);
  }
  final bits = f64Bits(v) + (((n >> 6) & 0xfff) << 52);
  return f32(f64FromBits(bits));
}

double sqrtf(double x) => f32(math.sqrt(x));
