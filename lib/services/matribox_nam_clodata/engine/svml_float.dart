import 'dart:math' as math;

import 'f32.dart';
import 'tables.dart';

/// Lane-wise ports of the 4-wide single-precision vector functions the
/// editor's engine calls for full groups of four values (the remainder goes
/// through the scalar UCRT functions). Fast path only: positive normal inputs
/// (`log`, `pow`) or |x| <= 9999 (`cos`); the engine never leaves it.

double _fb(int bits) => f32FromBits(bits);

double _logCore(
  double x,
  double? k,
  double ca,
  double cb,
  double cc,
  double ce,
) {
  final bits = f32Bits(x);
  final mant = bits & 0x7fffff;
  final t = (mant + 0x4afb10) & 0x800000;
  final mp = f32FromBits(mant | (0x3f800000 ^ t));
  final e = ((bits >> 23) - 127 + (t >> 23)).toDouble();
  final den = f32(1.0 + mp);
  final f = f32(mp - 1.0);
  final g = k == null ? f : f32(k * f);
  final z = f32(f / den);
  final s = f32(z * z);
  final s2 = f32(s * s);
  var p = f32(ca * s2);
  final q = f32(s2 * cb);
  p = f32(p + cc);
  p = f32(p * s);
  p = f32(p + q);
  p = f32(p - g);
  p = f32(p * z);
  p = f32(p + g);
  return f32(f32(e * ce) + p);
}

double svmlLogf(double x) => _logCore(
  x,
  null,
  _fb(0x3e9e361e),
  _fb(0x3ecc6ffa),
  _fb(0x3f2aab10),
  _fb(0x3f317218),
);

double svmlLog10f(double x) => _logCore(
  x,
  _fb(0x3ede5bd9),
  _fb(0x3e096bb1),
  _fb(0x3e319274),
  _fb(0x3e943d93),
  _fb(0x3e9a209b),
);

double svmlCosf(double x) {
  final a = x.abs();
  final t = f32(f32(a + _fb(0x3fc90fdb)) * _fb(0x3ea2f983));
  final k = t.roundToDouble() == t ? t : _rneFloat(t);
  final kf = f32(k - 0.5);
  final sign = k.toInt() & 1;
  var r = a;
  for (final c in const [0x40490000, 0x3a7da000, 0x34222000]) {
    r = f32(r - f32(_fb(c) * kf));
  }
  final r1 = f32(r - f32(_fb(0x2cb4611a) * kf));
  final r2 = f32(r * r);
  var p = f32(_fb(0x362f0519) * r2);
  p = f32(p + _fb(0xb94fbaf1));
  p = f32(p * r2);
  p = f32(p + _fb(0x3c088773));
  p = f32(p * r2);
  p = f32(p + _fb(0xbe2aaaa5));
  p = f32(p * r2);
  p = f32(p * r1);
  p = f32(p + r1);
  return sign == 0 ? p : -p;
}

double _rneFloat(double t) {
  final f = t.floorToDouble();
  final d = t - f;
  if (d < 0.5) return f;
  if (d > 0.5) return f + 1;
  return f % 2 == 0 ? f : f + 1;
}

const double _big = 6755399441055744.0; // 1.5 * 2^52
const double _c1 = 0.33333333333308374;
const double _c2 = -0.49999999999988803;
const double _ln2 = 0.6931471805599453;
const double _s = 2954.639443740597; // 2048 / ln 2
const double _f = 0.00033850805268231294; // ln 2 / 2048

/// `powf(x, y)` of the 4-wide routine; exact for the editor's use (x = 10).
double svmlPowf(double x, double y) {
  final bits = f64Bits(x);
  final mp = f64FromBits((bits & 0x000fffffffffffff) | 0x3f50000000000000);
  final mf = f32(mp);
  final rcp = f32(1.0 / mf);
  final c = (rcp + _big) - _big;
  final r = (mp * c) - 1.0;
  final i1 = ((f64Bits(c) >>> 40) - 0x408000) ~/ 8;
  final e = (bits >>> 52).toDouble();
  final kk = 720.0 < c ? 1023.0 : 1022.0;
  final ee = e - kk;
  final r2 = r * r;
  final p = (_c1 * r + _c2) * r2;
  final pol = r + p;
  final l = (pol + svmlPowT1[i1]) + ee * _ln2;
  final t = l * y;
  final s = _s * t;
  final big = (s - 0.5) + _big;
  final n = big - _big;
  final fp = s - n;
  final ff = fp * _f;
  final bb = f64Bits(big);
  final j = bb & 0x7ff;
  final e2 = (bb >>> 11) << 52;
  final t2 = svmlPowT2[j];
  final v = (ff * t2) + t2;
  return f32(f64FromBits(f64Bits(v) + e2));
}

double sqrtF32(double x) => f32(math.sqrt(x));
