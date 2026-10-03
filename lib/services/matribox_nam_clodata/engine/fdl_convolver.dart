import 'dart:typed_data';

import 'f32.dart';
import 'tables.dart';

/// Fixed 128-point float32 radix-2 complex FFT (Q15-quantised sine table) and
/// the uniform partitioned convolver built on it (block 64, up to 32
/// partitions) as used by the editor's engine for its FIR stages.
const int _n = 128;

final Int32List _rev = () {
  final r = Int32List(_n);
  for (var i = 0; i < _n; i++) {
    var v = 0;
    for (var b = 0; b < 7; b++) {
      if ((i >> b) & 1 == 1) v |= 1 << (6 - b);
    }
    r[i] = v;
  }
  return r;
}();

/// In-place FFT of split re/im arrays (length 128). [inverse] scales by 1/128.
void fft128(Float32List re, Float32List im, bool inverse) {
  final tr = Float32List(_n), ti = Float32List(_n);
  for (var i = 0; i < _n; i++) {
    tr[i] = re[_rev[i]];
    ti[i] = im[_rev[i]];
  }
  re.setAll(0, tr);
  im.setAll(0, ti);
  final tw = fdlTwiddle;
  var half = 1;
  while (half < _n) {
    final m = 2 * half;
    final step = _n ~/ m;
    for (var lo = 0; lo < _n; lo += m) {
      final hi = lo + half;
      final rb = re[hi], ib = im[hi], ra = re[lo], ia = im[lo];
      re[hi] = f32(ra - rb);
      im[hi] = f32(ia - ib);
      re[lo] = f32(rb + ra);
      im[lo] = f32(ib + ia);
    }
    for (var j = 1; j < half; j++) {
      var c = tw[j * step];
      final s = tw[(_n ~/ 4 - j * step + _n) % _n];
      if (!inverse) c = -c;
      for (var base = 0; base < _n; base += m) {
        final lo = base + j;
        final hi = lo + half;
        final rh = re[hi], ih = im[hi], rl = re[lo], il = im[lo];
        final y1 = f32(f32(rh * s) - f32(ih * c));
        final y2 = f32(f32(rh * c) + f32(ih * s));
        re[hi] = f32(rl - y1);
        im[hi] = f32(il - y2);
        re[lo] = f32(rl + y1);
        im[lo] = f32(il + y2);
      }
    }
    half = m;
  }
  if (inverse) {
    for (var i = 0; i < _n; i++) {
      re[i] = f32(re[i] / 128.0);
      im[i] = f32(im[i] / 128.0);
    }
  }
}

/// Uniform partitioned FIR convolver (block 64); state persists across calls.
class FdlConvolver {
  FdlConvolver(Float32List taps) {
    partitions = (taps.length / 64.0).ceil();
    irRe = [for (var i = 0; i < partitions; i++) Float32List(_n)];
    irIm = [for (var i = 0; i < partitions; i++) Float32List(_n)];
    for (var i = 0; i < partitions; i++) {
      final re = irRe[i];
      for (var k = 0; k < 64; k++) {
        final idx = i * 64 + k;
        re[k] = idx < taps.length ? taps[idx] : 0.0;
      }
      fft128(re, irIm[i], false);
    }
    xRe = [for (var i = 0; i < partitions; i++) Float32List(_n)];
    xIm = [for (var i = 0; i < partitions; i++) Float32List(_n)];
  }

  late final int partitions;
  late final List<Float32List> irRe, irIm, xRe, xIm;
  int _cur = 0;
  final Float32List _ovl = Float32List(64);
  final Float32List _ar = Float32List(_n), _ai = Float32List(_n);

  /// Convolves one 64-sample block into [out] (offset [outOff]).
  void block(Float32List input, int inOff, Float32List out, int outOff) {
    final cur = _cur;
    final xr = xRe[cur], xi = xIm[cur];
    xr.fillRange(0, _n, 0.0);
    xi.fillRange(0, _n, 0.0);
    for (var k = 0; k < 64; k++) {
      xr[k] = input[inOff + k];
    }
    fft128(xr, xi, false);
    _ar.fillRange(0, _n, 0.0);
    _ai.fillRange(0, _n, 0.0);
    for (var p = 0; p < partitions; p++) {
      final j = ((cur - p) % partitions + partitions) % partitions;
      final ir = irRe[p], ii = irIm[p], xr2 = xRe[j], xi2 = xIm[j];
      for (var k = 0; k <= 64; k++) {
        final t1 = f32(f32(ir[k] * xr2[k]) - f32(ii[k] * xi2[k]));
        _ar[k] = f32(t1 + _ar[k]);
        final t2 = f32(f32(ir[k] * xi2[k]) + f32(ii[k] * xr2[k]));
        _ai[k] = f32(t2 + _ai[k]);
      }
      for (var k = 1; k < 64; k++) {
        _ar[128 - k] = _ar[k];
        _ai[128 - k] = -_ai[k];
      }
    }
    fft128(_ar, _ai, true);
    for (var k = 0; k < 64; k++) {
      out[outOff + k] = f32(_ovl[k] + _ar[k]);
      _ovl[k] = _ar[64 + k];
    }
    _cur = (cur + 1) % partitions;
  }
}

/// Filters [x] (n samples) with [taps] through a fresh [FdlConvolver]; the
/// tail block is zero padded exactly like the editor's wrapper does.
Float32List firFilter(Float32List taps, Float32List x, [int? length]) {
  final n = length ?? x.length;
  final cv = FdlConvolver(taps);
  final out = Float32List(n);
  final full = n - n % 64;
  for (var b = 0; b < full; b += 64) {
    cv.block(x, b, out, b);
  }
  final r = n % 64;
  if (r != 0) {
    final blk = Float32List(64);
    for (var k = 0; k < r; k++) {
      blk[k] = x[full + k];
    }
    final res = Float32List(64);
    cv.block(blk, 0, res, 0);
    for (var k = 0; k < r; k++) {
      out[full + k] = res[k];
    }
  }
  return out;
}
