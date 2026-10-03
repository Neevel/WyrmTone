import 'dart:typed_data';

/// Single-precision arithmetic helpers.
///
/// The offline converter reproduces the editor's engine bit for bit, so every
/// intermediate value has to be rounded to the width the original used. Dart
/// has no `float`, therefore each single-precision operation is evaluated in
/// double precision (exact for `+ - * / sqrt` of two floats) and rounded once.
final Float32List _f32 = Float32List(1);
final Float64List _f64 = Float64List(1);
final Uint64List _u64 = Uint64List.view(_f64.buffer);
final Uint32List _u32 = Uint32List.view(_f32.buffer);

/// Rounds [x] to the nearest single-precision value (ties to even).
double f32(double x) {
  _f32[0] = x;
  return _f32[0];
}

int f32Bits(double x) {
  _f32[0] = x;
  return _u32[0];
}

double f32FromBits(int bits) {
  _u32[0] = bits & 0xffffffff;
  return _f32[0];
}

int f64Bits(double x) {
  _f64[0] = x;
  return _u64[0];
}

double f64FromBits(int bits) {
  _u64[0] = bits;
  return _f64[0];
}

/// Error-free sum: `a + b = s + e` exactly.
(double, double) _twoSum(double a, double b) {
  final s = a + b;
  final bb = s - a;
  final e = (a - (s - bb)) + (b - bb);
  return (s, e);
}

/// Error-free product via Veltkamp splitting: `a * b = p + e` exactly.
(double, double) _twoProd(double a, double b) {
  final p = a * b;
  final ta = 134217729.0 * a;
  final ah = ta - (ta - a);
  final al = a - ah;
  final tb = 134217729.0 * b;
  final bh = tb - (tb - b);
  final bl = b - bh;
  final e = ((ah * bh - p) + ah * bl + al * bh) + al * bl;
  return (p, e);
}

/// Rounds the exact sum `s + e` (with `|e| <= ulp(s)/2`) to odd, in double.
double _roundToOdd(double s, double e) {
  if (e == 0.0) return s;
  final bits = f64Bits(s);
  if ((bits & 1) == 0) {
    // Step one ulp towards the sign of the error so the result becomes odd.
    final towardsPositive = e > 0.0;
    final positive = s > 0.0 || (s == 0.0 && !s.isNegative);
    return f64FromBits(bits + (towardsPositive == positive ? 1 : -1));
  }
  return s;
}

/// Correctly rounded fused multiply-add for doubles (`a * b + c`).
///
/// Boldo–Melquiond emulation; exact for values without overflow/underflow.
double fma64(double a, double b, double c) {
  final (uh, ul) = _twoProd(a, b);
  final (th, tl) = _twoSum(c, uh);
  final (sv, se) = _twoSum(tl, ul);
  final v = _roundToOdd(sv, se);
  return th + v;
}

/// Correctly rounded single-precision fused multiply-add of float operands.
double fma32(double a, double b, double c) {
  final p = a * b; // exact: 24 x 24 bits fit into 53
  final (s, e) = _twoSum(p, c);
  return f32(_roundToOdd(s, e));
}
