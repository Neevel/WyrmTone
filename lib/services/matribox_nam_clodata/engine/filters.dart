import 'dart:typed_data';

import 'f32.dart';
import 'ucrt_float.dart';

/// Double-precision direct form II biquad as used by the engine: input scaled
/// by 1000, output by 0.001 (through float32).
class Biquad {
  Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  final double b0, b1, b2, a1, a2;
  double _s1 = 0.0, _s2 = 0.0;

  double process(double x32) {
    var w0 = x32 * 1000.0;
    w0 = w0 - a2 * _s2;
    w0 = w0 - a1 * _s1;
    var y = b1 * _s1 + b2 * _s2;
    y = y + w0 * b0;
    _s2 = _s1;
    _s1 = w0;
    final y32 = f32(y);
    return f32(y32 * 0.001);
  }
}

const List<double> _up1 = [
  0.04572814702987671,
  0.3325011134147644,
  0.6632020473480225,
  0.9338558316230774,
  0.16808754205703735,
  0.5044857263565063,
  0.8037808537483215,
];
const List<double> _up2 = [
  0.05423077940940857,
  0.3987969756126404,
  0.8629178404808044,
  0.19969958066940308,
  0.6210968494415283,
];
const List<double> _dn1 = [
  0.07076594978570938,
  0.5131675601005554,
  0.25785309076309204,
  0.8173173666000366,
];
const List<double> _dn2 = [
  0.05421752482652664,
  0.3830873370170593,
  0.7487209439277649,
  0.19679796695709229,
  0.5731363892555237,
  0.9142937064170837,
];

/// Cascade of first-order allpass sections (polyphase half-band).
class _Allpass {
  _Allpass(List<double> coefs)
    : c = Float32List.fromList(coefs),
      st = Float32List(coefs.length),
      ne = coefs.length - coefs.length ~/ 2;

  final Float32List c;
  final Float32List st;
  final int ne;

  double run(double x, int lo, int hi) {
    for (var k = lo; k < hi; k++) {
      final ck = c[k];
      final y = f32(f32(ck * x) + st[k]);
      st[k] = f32(x - f32(y * ck));
      x = y;
    }
    return x;
  }
}

/// Polyphase half-band decimator: two allpass branches averaged.
class _Down extends _Allpass {
  _Down(super.coefs);

  double prev = 0.0;

  double process(double aIn, double bIn) {
    final a = run(aIn, 0, ne);
    final b = run(bIn, ne, c.length);
    final out = f32(f32(a + prev) * 0.5);
    prev = b;
    return out;
  }
}

/// Non-linear waveshaper with 4x oversampling (2 x 2 polyphase allpass
/// up/down converters) around `y = P(1-e^{-a+x})` / `N(e^{a-x}-1)`.
class Waveshaper {
  Waveshaper(double p, double n, double ap, double an)
    : _p = f32(p),
      _n = f32(n),
      _ap = f32(ap),
      _an = f32(an);

  final double _p, _n, _ap, _an;
  final _Allpass _u1 = _Allpass(_up1), _u2 = _Allpass(_up2);
  final _Down _d1 = _Down(_dn1), _d2 = _Down(_dn2);

  double _nl(double x) {
    if (x > 0) {
      final e = expf(-f32(_ap * x));
      return f32(f32(1.0 - e) * _p);
    }
    final e = expf(f32(_an * x));
    return f32(f32(e - 1.0) * _n);
  }

  double process(double x32) {
    final x = f32(x32);
    final a0 = _u1.run(x, 0, _u1.ne);
    final a1 = _u1.run(x, _u1.ne, _u1.c.length);
    final s0 = _u2.run(a0, 0, _u2.ne);
    final s1 = _u2.run(a0, _u2.ne, _u2.c.length);
    final s2 = _u2.run(a1, 0, _u2.ne);
    final s3 = _u2.run(a1, _u2.ne, _u2.c.length);
    final h0 = _d1.process(_nl(s0), _nl(s1));
    final h1 = _d1.process(_nl(s2), _nl(s3));
    return _d2.process(h0, h1);
  }
}
