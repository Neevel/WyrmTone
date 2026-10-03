import 'dart:math' as math;
import 'dart:typed_data';

import 'f32.dart';
import 'ooura_fft.dart';
import 'tables.dart';

/// 48 kHz -> 44.1 kHz FIR resampler of the editor's engine: a 2x
/// block-convolver (zero-phase half-band kernel) followed by a fractional
/// interpolator that uses a static 673-phase, 24-tap bank with quadratic
/// coefficients (r8brain-style).

const int _fracs = 673;
const double _len2 = 12.0;
const int _fl2 = 12;
const double _beta = 12.55262798;
const double _power = 1.51553897;

double _besselI0(double x) {
  final ax = x.abs();
  if (ax < 3.75) {
    var y = x / 3.75;
    y *= y;
    return 1.0 +
        y *
            (3.5156229 +
                y *
                    (3.0899424 +
                        y *
                            (1.2067492 +
                                y *
                                    (0.2659732 +
                                        y * (0.360768e-1 + y * 0.45813e-2)))));
  }
  final y = 3.75 / ax;
  return math.exp(ax) /
      math.sqrt(ax) *
      (0.39894228 +
          y *
              (0.1328592e-1 +
                  y *
                      (0.225319e-2 +
                          y *
                              (-0.157565e-2 +
                                  y *
                                      (0.916281e-2 +
                                          y *
                                              (-0.2057706e-1 +
                                                  y *
                                                      (0.2635537e-1 +
                                                          y *
                                                              (-0.1647633e-1 +
                                                                  y * 0.392377e-2))))))));
}

List<double> _genRow(double fd) {
  final bI0 = _besselI0(_beta);
  final klf = fd / _len2;
  var wn = -_fl2;
  double win() {
    final t = (wn / _len2) + klf;
    final n = 1.0 - t * t;
    wn++;
    if (n < 0.0) return 0.0;
    return _besselI0(_beta * math.sqrt(n)) / bI0;
  }

  double pw(double v) => math.pow(v, _power).toDouble();
  final s = math.sin(fd * math.pi);
  final sg = [s, -s];
  final out = List<double>.filled(24, 0.0);
  var idx = 0, t = -_fl2;
  if (t + fd < -_len2) {
    win();
    out[idx] = 0.0;
    idx++;
    t++;
  }
  final zx = 0.9999999999999 <= fd && fd <= 1.0000000000001;
  final mt = 0 - (zx ? 1 : 0);
  while (t < mt) {
    out[idx] = ((pw(win()) * sg[t & 1]) / (t + fd)) / math.pi;
    idx++;
    t++;
  }
  final x = t + fd;
  out[idx] = x.abs() <= 1e-13
      ? pw(win())
      : ((pw(win()) * sg[t & 1]) / x) / math.pi;
  while (t < _fl2 - 2) {
    idx++;
    t++;
    out[idx] = ((pw(win()) * sg[t & 1]) / (t + fd)) / math.pi;
  }
  idx++;
  t++;
  final ut = t + fd;
  out[idx] = ut > _len2 ? 0.0 : ((pw(win()) * sg[t & 1]) / ut) / math.pi;
  return out;
}

/// Static interpolation bank: [phase][tap][c0, c1, c2] flattened to 72 per phase.
Float64List _buildBank() {
  final rows = <List<double>>[];
  for (var i = -3; i < _fracs; i++) {
    final r = _genRow((_fracs - i) / _fracs);
    var s = 0.0;
    for (final v in r) {
      s += v;
    }
    s = 1.0 / s;
    rows.add([for (final v in r) v * s]);
  }
  for (var i = 0; i < 8; i++) {
    rows.add(List<double>.filled(24, 0.0));
  }
  final out = Float64List(_fracs * 72);
  for (var k = 0; k < _fracs; k++) {
    for (var j = 0; j < 24; j++) {
      final xm3 = rows[k][j],
          xm2 = rows[k + 1][j],
          xm1 = rows[k + 2][j],
          x0 = rows[k + 3][j];
      final x1 = rows[k + 4][j],
          x2 = rows[k + 5][j],
          x3 = rows[k + 6][j],
          x4 = rows[k + 7][j];
      final c1 =
          ((16.0 * (xm2 - x2) + 61.0 * (x1 - xm1)) + 3.0 * (x3 - xm3)) / 76.0;
      var a = 106.0 * (xm1 + x1);
      a = a + 10.0 * x3;
      a = a + 6.0 * xm3;
      a = a - 3.0 * x4;
      a = a - 29.0 * (xm2 + x2);
      a = a - 167.0 * x0;
      out[k * 72 + 3 * j] = x0;
      out[k * 72 + 3 * j + 1] = c1;
      out[k * 72 + 3 * j + 2] = a / 76.0;
    }
  }
  return out;
}

/// Kernel block spectrum (Ooura layout) of the 4096-point zero-phase kernel.
Float64List _buildKernelBlock() {
  final arr = Float64List(4096);
  for (var i = 0; i < 772; i++) {
    arr[i] = r8bKernelHalf[i];
  }
  for (var i = 772; i < 4096; i++) {
    final m = 4096 - i;
    arr[i] = m < 772 ? arr[m] : 0.0;
  }
  OouraRdft(4096).forward(arr);
  return arr;
}

class _ConvUp2 {
  _ConvUp2(this.kernel)
    : blockLen2 = 2 << 11,
      prevInputLen = (1543 - 1 + 1) ~/ 2,
      outOffset = 771 {
    inputLen = blockLen2 - prevInputLen * 2;
    latencyLeft = inputLen + outOffset;
    inDataLeft = inputLen;
    prevInput = Float64List(prevInputLen);
    curInput = Float64List(blockLen2);
    curOutput = Float64List(blockLen2);
    fin = OouraRdft(blockLen2 >> 1);
    fout = OouraRdft(blockLen2);
  }

  final Float64List kernel;
  final int blockLen2, prevInputLen, outOffset;
  late final int inputLen;
  late final OouraRdft fin, fout;
  late Float64List prevInput, curInput, curOutput;
  late int latencyLeft, inDataLeft;

  void _copyOut(int offs, List<double> out, int b) {
    if (offs < 0) {
      if (offs + b <= 0) {
        offs += blockLen2;
      } else {
        _copyOut(offs + blockLen2, out, -offs);
        b += offs;
        offs = 0;
      }
    }
    if (latencyLeft != 0) {
      if (latencyLeft >= b) {
        latencyLeft -= b;
        return;
      }
      offs += latencyLeft;
      b -= latencyLeft;
      latencyLeft = 0;
    }
    for (var i = 0; i < b; i++) {
      out.add(curOutput[offs + i]);
    }
  }

  List<double> process(Float64List ip, int l0) {
    final out = <double>[];
    var pos = 0;
    var l = l0 * 2;
    while (l > 0) {
      final offs = inputLen - inDataLeft;
      if (l < inDataLeft) {
        inDataLeft -= l;
        final k = l >> 1;
        for (var i = 0; i < k; i++) {
          curInput[(offs >> 1) + i] = ip[pos + i];
        }
        _copyOut(offs - outOffset, out, l);
        break;
      }
      final b = inDataLeft;
      l -= b;
      inDataLeft = inputLen;
      final bu = b >> 1;
      for (var i = 0; i < bu; i++) {
        curInput[(offs >> 1) + i] = ip[pos + i];
      }
      pos += bu;
      final ilu = inputLen >> 1;
      for (var i = 0; i < prevInputLen; i++) {
        curInput[ilu + i] = prevInput[i];
      }
      for (var i = 0; i < prevInputLen; i++) {
        prevInput[i] = curInput[ilu - prevInputLen + i];
      }
      final spec = Float64List(blockLen2 >> 1);
      for (var i = 0; i < spec.length; i++) {
        spec[i] = curInput[i];
      }
      fin.forward(spec);
      final p = Float64List(blockLen2);
      for (var i = 0; i < spec.length; i++) {
        p[i] = spec[i];
      }
      final bl1 = blockLen2 >> 1, bl2 = bl1 * 2;
      for (var i = bl1 + 2; i < bl2; i += 2) {
        p[i] = p[bl2 - i];
        p[i + 1] = -p[bl2 - i + 1];
      }
      p[bl1] = p[1];
      p[bl1 + 1] = 0.0;
      p[1] = p[0];
      p[0] = p[0] * kernel[0];
      p[1] = kernel[1] * p[1];
      for (var i = 2; i < blockLen2; i += 2) {
        final g = kernel[i];
        p[i] = g * p[i];
        p[i + 1] = g * p[i + 1];
      }
      fout.inverse(p);
      curInput = p;
      _copyOut(offs - outOffset, out, b);
      final tmp = curInput;
      curInput = curOutput;
      curOutput = tmp;
    }
    return out;
  }
}

class _Frac {
  _Frac(this.bank, double src, double dst)
    : fracStep = src / dst,
      src = src,
      dst = dst {
    readPos = flb;
  }

  static const int bufLen = 256, mask = 255, flo = 23, flb = bufLen - 11;
  final Float64List bank;
  final double fracStep, src, dst;
  final Float64List buf = Float64List(bufLen + 29);
  int bufLeft = 0, writePos = 0, readPos = 0, inPosInt = 0;
  double inPosFrac = 0.0, inPosShift = 0.0;

  List<double> process(List<double> ip) {
    final out = <double>[];
    var l = ip.length, pos = 0;
    while (l > 0) {
      final b = math.min(l, math.min(bufLen - writePos, flb - bufLeft));
      final wp = writePos;
      for (var i = 0; i < b; i++) {
        buf[wp + i] = ip[pos + i];
      }
      final ec = flo - wp;
      if (ec > 0) {
        final m = math.min(b, ec);
        for (var i = 0; i < m; i++) {
          buf[wp + bufLen + i] = ip[pos + i];
        }
      }
      pos += b;
      writePos = (wp + b) & mask;
      l -= b;
      bufLeft += b;
      _conv(out);
    }
    if (inPosShift.toInt() > 1000) {
      inPosInt = 0;
      inPosShift = inPosFrac / src * dst;
    }
    return out;
  }

  void _conv(List<double> out) {
    var bl = bufLeft - _fl2;
    var rpos = readPos;
    var ipos = inPosInt;
    var fpos = inPosFrac;
    var psh = inPosShift;
    while (bl > 0) {
      var x = fpos * 673.0;
      final fti = x.toInt();
      x -= fti;
      final x2 = x * x;
      final base = fti * 72;
      var s = 0.0;
      for (var i = 0; i < 24; i++) {
        s +=
            ((bank[base + 3 * i] + bank[base + 3 * i + 1] * x) +
                bank[base + 3 * i + 2] * x2) *
            buf[rpos + i];
      }
      out.add(s);
      psh += 1.0;
      final nxt = psh * fracStep;
      final ni = nxt.toInt();
      final incr = ni - ipos;
      fpos = nxt - ni;
      ipos = ni;
      bl -= incr;
      rpos = (rpos + incr) & mask;
    }
    bufLeft = bl + _fl2;
    readPos = rpos;
    inPosInt = ipos;
    inPosFrac = fpos;
    inPosShift = psh;
  }
}

Float64List? _bank;
Float64List? _kernel;

/// Resamples [x] (n samples at 48 kHz) to `int(n * 44100 / 48000)` samples
/// with the editor's wrapper semantics (zero-flush passes until enough output).
Float32List resample48to44(Float32List x) {
  final n = x.length;
  final bank = _bank ??= _buildBank();
  final kernel = _kernel ??= _buildKernelBlock();
  final conv = _ConvUp2(kernel);
  final frac = _Frac(bank, 96000.0, 44100.0);
  final needed = f32(f32(f32(n.toDouble()) * 44100.0) / 48000.0).toInt();
  final res = <double>[];
  var inbuf = Float64List.fromList(x);
  var first = true;
  while (res.length < needed) {
    if (!first) inbuf = Float64List(n);
    res.addAll(frac.process(conv.process(inbuf, n)));
    first = false;
  }
  final out = Float32List(needed);
  for (var i = 0; i < needed; i++) {
    out[i] = res[i];
  }
  return out;
}
