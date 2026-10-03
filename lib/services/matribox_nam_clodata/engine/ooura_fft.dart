import 'dart:math' as math;
import 'dart:typed_data';

/// Real FFT in the layout of Ooura's `fft4g` (`rdft`), double precision.
///
/// The editor's engine uses this transform in two places (float wrapper for
/// the spectral estimator, double for the resampler). Twiddles come from the
/// platform `sin`/`cos`; results were verified bit-identical on Windows/UCRT.
class OouraRdft {
  OouraRdft(this.n)
    : ip = Int32List(2 + math.sqrt(n / 2).toInt() + 2),
      w = Float64List(n >> 1) {
    nw = n >> 2;
    _makewt(nw);
    nc = n >> 2;
    _makect(nc, nw);
  }

  final int n;
  final Int32List ip;
  final Float64List w;
  late final int nw;
  late final int nc;

  void _makewt(int nw) {
    ip[0] = nw;
    ip[1] = 1;
    if (nw > 2) {
      final nwh = nw >> 1;
      final delta = math.atan(1.0) / nwh;
      w[0] = 1.0;
      w[1] = 0.0;
      w[nwh] = math.cos(delta * nwh);
      w[nwh + 1] = w[nwh];
      if (nwh > 2) {
        for (var j = 2; j < nwh; j += 2) {
          final x = math.cos(delta * j);
          final y = math.sin(delta * j);
          w[j] = x;
          w[j + 1] = y;
          w[nw - j] = y;
          w[nw - j + 1] = x;
        }
        _bitrv2(nw, w);
      }
    }
  }

  void _makect(int nc, int co) {
    ip[1] = nc;
    if (nc > 1) {
      final nch = nc >> 1;
      final delta = math.atan(1.0) / nch;
      w[co] = math.cos(delta * nch);
      w[co + nch] = 0.5 * w[co];
      for (var j = 1; j < nch; j++) {
        w[co + j] = 0.5 * math.cos(delta * j);
        w[co + nc - j] = 0.5 * math.sin(delta * j);
      }
    }
  }

  void _swap(Float64List a, int j1, int k1) {
    final xr = a[j1];
    final xi = a[j1 + 1];
    a[j1] = a[k1];
    a[j1 + 1] = a[k1 + 1];
    a[k1] = xr;
    a[k1 + 1] = xi;
  }

  void _bitrv2(int n, Float64List a) {
    ip[2] = 0;
    var l = n;
    var m = 1;
    while ((m << 3) < l) {
      l >>= 1;
      for (var j = 0; j < m; j++) {
        ip[2 + m + j] = ip[2 + j] + l;
      }
      m <<= 1;
    }
    final m2 = 2 * m;
    if ((m << 3) == l) {
      for (var k = 0; k < m; k++) {
        for (var j = 0; j < k; j++) {
          var j1 = 2 * j + ip[2 + k];
          var k1 = 2 * k + ip[2 + j];
          _swap(a, j1, k1);
          j1 += m2;
          k1 += 2 * m2;
          _swap(a, j1, k1);
          j1 += m2;
          k1 -= m2;
          _swap(a, j1, k1);
          j1 += m2;
          k1 += 2 * m2;
          _swap(a, j1, k1);
        }
        final j1 = 2 * k + m2 + ip[2 + k];
        _swap(a, j1, j1 + m2);
      }
    } else {
      for (var k = 1; k < m; k++) {
        for (var j = 0; j < k; j++) {
          var j1 = 2 * j + ip[2 + k];
          var k1 = 2 * k + ip[2 + j];
          _swap(a, j1, k1);
          j1 += m2;
          k1 += m2;
          _swap(a, j1, k1);
        }
      }
    }
  }

  void _cft1st(int n, Float64List a) {
    var x0r = a[0] + a[2];
    var x0i = a[1] + a[3];
    var x1r = a[0] - a[2];
    var x1i = a[1] - a[3];
    var x2r = a[4] + a[6];
    var x2i = a[5] + a[7];
    var x3r = a[4] - a[6];
    var x3i = a[5] - a[7];
    a[0] = x0r + x2r;
    a[1] = x0i + x2i;
    a[4] = x0r - x2r;
    a[5] = x0i - x2i;
    a[2] = x1r - x3i;
    a[3] = x1i + x3r;
    a[6] = x1r + x3i;
    a[7] = x1i - x3r;
    var wk1r = w[2];
    x0r = a[8] + a[10];
    x0i = a[9] + a[11];
    x1r = a[8] - a[10];
    x1i = a[9] - a[11];
    x2r = a[12] + a[14];
    x2i = a[13] + a[15];
    x3r = a[12] - a[14];
    x3i = a[13] - a[15];
    a[8] = x0r + x2r;
    a[9] = x0i + x2i;
    a[12] = x2i - x0i;
    a[13] = x0r - x2r;
    x0r = x1r - x3i;
    x0i = x1i + x3r;
    a[10] = wk1r * (x0r - x0i);
    a[11] = wk1r * (x0r + x0i);
    x0r = x3i + x1r;
    x0i = x3r - x1i;
    a[14] = wk1r * (x0i - x0r);
    a[15] = wk1r * (x0i + x0r);
    var k1 = 0;
    for (var j = 16; j < n; j += 16) {
      k1 += 2;
      final k2 = 2 * k1;
      final wk2r = w[k1];
      final wk2i = w[k1 + 1];
      wk1r = w[k2];
      var wk1i = w[k2 + 1];
      var wk3r = wk1r - 2 * wk2i * wk1i;
      var wk3i = 2 * wk2i * wk1r - wk1i;
      x0r = a[j] + a[j + 2];
      x0i = a[j + 1] + a[j + 3];
      x1r = a[j] - a[j + 2];
      x1i = a[j + 1] - a[j + 3];
      x2r = a[j + 4] + a[j + 6];
      x2i = a[j + 5] + a[j + 7];
      x3r = a[j + 4] - a[j + 6];
      x3i = a[j + 5] - a[j + 7];
      a[j] = x0r + x2r;
      a[j + 1] = x0i + x2i;
      x0r -= x2r;
      x0i -= x2i;
      a[j + 4] = wk2r * x0r - wk2i * x0i;
      a[j + 5] = wk2r * x0i + wk2i * x0r;
      x0r = x1r - x3i;
      x0i = x1i + x3r;
      a[j + 2] = wk1r * x0r - wk1i * x0i;
      a[j + 3] = wk1r * x0i + wk1i * x0r;
      x0r = x1r + x3i;
      x0i = x1i - x3r;
      a[j + 6] = wk3r * x0r - wk3i * x0i;
      a[j + 7] = wk3r * x0i + wk3i * x0r;
      wk1r = w[k2 + 2];
      wk1i = w[k2 + 3];
      wk3r = wk1r - 2 * wk2r * wk1i;
      wk3i = 2 * wk2r * wk1r - wk1i;
      x0r = a[j + 8] + a[j + 10];
      x0i = a[j + 9] + a[j + 11];
      x1r = a[j + 8] - a[j + 10];
      x1i = a[j + 9] - a[j + 11];
      x2r = a[j + 12] + a[j + 14];
      x2i = a[j + 13] + a[j + 15];
      x3r = a[j + 12] - a[j + 14];
      x3i = a[j + 13] - a[j + 15];
      a[j + 8] = x0r + x2r;
      a[j + 9] = x0i + x2i;
      x0r -= x2r;
      x0i -= x2i;
      a[j + 12] = -wk2i * x0r - wk2r * x0i;
      a[j + 13] = -wk2i * x0i + wk2r * x0r;
      x0r = x1r - x3i;
      x0i = x1i + x3r;
      a[j + 10] = wk1r * x0r - wk1i * x0i;
      a[j + 11] = wk1r * x0i + wk1i * x0r;
      x0r = x1r + x3i;
      x0i = x1i - x3r;
      a[j + 14] = wk3r * x0r - wk3i * x0i;
      a[j + 15] = wk3r * x0i + wk3i * x0r;
    }
  }

  void _cftmdl(int n, int l, Float64List a) {
    final m = l << 2;
    for (var j = 0; j < l; j += 2) {
      final j1 = j + l;
      final j2 = j1 + l;
      final j3 = j2 + l;
      var x0r = a[j] + a[j1];
      var x0i = a[j + 1] + a[j1 + 1];
      final x1r = a[j] - a[j1];
      final x1i = a[j + 1] - a[j1 + 1];
      final x2r = a[j2] + a[j3];
      final x2i = a[j2 + 1] + a[j3 + 1];
      final x3r = a[j2] - a[j3];
      final x3i = a[j2 + 1] - a[j3 + 1];
      a[j] = x0r + x2r;
      a[j + 1] = x0i + x2i;
      a[j2] = x0r - x2r;
      a[j2 + 1] = x0i - x2i;
      a[j1] = x1r - x3i;
      a[j1 + 1] = x1i + x3r;
      a[j3] = x1r + x3i;
      a[j3 + 1] = x1i - x3r;
    }
    var wk1r = w[2];
    for (var j = m; j < l + m; j += 2) {
      final j1 = j + l;
      final j2 = j1 + l;
      final j3 = j2 + l;
      var x0r = a[j] + a[j1];
      var x0i = a[j + 1] + a[j1 + 1];
      final x1r = a[j] - a[j1];
      final x1i = a[j + 1] - a[j1 + 1];
      final x2r = a[j2] + a[j3];
      final x2i = a[j2 + 1] + a[j3 + 1];
      final x3r = a[j2] - a[j3];
      final x3i = a[j2 + 1] - a[j3 + 1];
      a[j] = x0r + x2r;
      a[j + 1] = x0i + x2i;
      a[j2] = x2i - x0i;
      a[j2 + 1] = x0r - x2r;
      x0r = x1r - x3i;
      x0i = x1i + x3r;
      a[j1] = wk1r * (x0r - x0i);
      a[j1 + 1] = wk1r * (x0r + x0i);
      x0r = x3i + x1r;
      x0i = x3r - x1i;
      a[j3] = wk1r * (x0i - x0r);
      a[j3 + 1] = wk1r * (x0i + x0r);
    }
    var k1 = 0;
    final m2 = 2 * m;
    for (var k = m2; k < n; k += m2) {
      k1 += 2;
      final k2 = 2 * k1;
      final wk2r = w[k1];
      final wk2i = w[k1 + 1];
      wk1r = w[k2];
      var wk1i = w[k2 + 1];
      var wk3r = wk1r - 2 * wk2i * wk1i;
      var wk3i = 2 * wk2i * wk1r - wk1i;
      for (var j = k; j < l + k; j += 2) {
        final j1 = j + l;
        final j2 = j1 + l;
        final j3 = j2 + l;
        var x0r = a[j] + a[j1];
        var x0i = a[j + 1] + a[j1 + 1];
        final x1r = a[j] - a[j1];
        final x1i = a[j + 1] - a[j1 + 1];
        final x2r = a[j2] + a[j3];
        final x2i = a[j2 + 1] + a[j3 + 1];
        final x3r = a[j2] - a[j3];
        final x3i = a[j2 + 1] - a[j3 + 1];
        a[j] = x0r + x2r;
        a[j + 1] = x0i + x2i;
        x0r -= x2r;
        x0i -= x2i;
        a[j2] = wk2r * x0r - wk2i * x0i;
        a[j2 + 1] = wk2r * x0i + wk2i * x0r;
        x0r = x1r - x3i;
        x0i = x1i + x3r;
        a[j1] = wk1r * x0r - wk1i * x0i;
        a[j1 + 1] = wk1r * x0i + wk1i * x0r;
        x0r = x1r + x3i;
        x0i = x1i - x3r;
        a[j3] = wk3r * x0r - wk3i * x0i;
        a[j3 + 1] = wk3r * x0i + wk3i * x0r;
      }
      wk1r = w[k2 + 2];
      wk1i = w[k2 + 3];
      wk3r = wk1r - 2 * wk2r * wk1i;
      wk3i = 2 * wk2r * wk1r - wk1i;
      for (var j = k + m; j < l + (k + m); j += 2) {
        final j1 = j + l;
        final j2 = j1 + l;
        final j3 = j2 + l;
        var x0r = a[j] + a[j1];
        var x0i = a[j + 1] + a[j1 + 1];
        final x1r = a[j] - a[j1];
        final x1i = a[j + 1] - a[j1 + 1];
        final x2r = a[j2] + a[j3];
        final x2i = a[j2 + 1] + a[j3 + 1];
        final x3r = a[j2] - a[j3];
        final x3i = a[j2 + 1] - a[j3 + 1];
        a[j] = x0r + x2r;
        a[j + 1] = x0i + x2i;
        x0r -= x2r;
        x0i -= x2i;
        a[j2] = -wk2i * x0r - wk2r * x0i;
        a[j2 + 1] = -wk2i * x0i + wk2r * x0r;
        x0r = x1r - x3i;
        x0i = x1i + x3r;
        a[j1] = wk1r * x0r - wk1i * x0i;
        a[j1 + 1] = wk1r * x0i + wk1i * x0r;
        x0r = x1r + x3i;
        x0i = x1i - x3r;
        a[j3] = wk3r * x0r - wk3i * x0i;
        a[j3 + 1] = wk3r * x0i + wk3i * x0r;
      }
    }
  }

  void _cftfsub(int n, Float64List a) {
    var l = 2;
    if (n > 8) {
      _cft1st(n, a);
      l = 8;
      while ((l << 2) < n) {
        _cftmdl(n, l, a);
        l <<= 2;
      }
    }
    if ((l << 2) == n) {
      for (var j = 0; j < l; j += 2) {
        final j1 = j + l;
        final j2 = j1 + l;
        final j3 = j2 + l;
        final x0r = a[j] + a[j1];
        final x0i = a[j + 1] + a[j1 + 1];
        final x1r = a[j] - a[j1];
        final x1i = a[j + 1] - a[j1 + 1];
        final x2r = a[j2] + a[j3];
        final x2i = a[j2 + 1] + a[j3 + 1];
        final x3r = a[j2] - a[j3];
        final x3i = a[j2 + 1] - a[j3 + 1];
        a[j] = x0r + x2r;
        a[j + 1] = x0i + x2i;
        a[j2] = x0r - x2r;
        a[j2 + 1] = x0i - x2i;
        a[j1] = x1r - x3i;
        a[j1 + 1] = x1i + x3r;
        a[j3] = x1r + x3i;
        a[j3 + 1] = x1i - x3r;
      }
    } else {
      for (var j = 0; j < l; j += 2) {
        final j1 = j + l;
        final x0r = a[j] - a[j1];
        final x0i = a[j + 1] - a[j1 + 1];
        a[j] += a[j1];
        a[j + 1] += a[j1 + 1];
        a[j1] = x0r;
        a[j1 + 1] = x0i;
      }
    }
  }

  void _cftbsub(int n, Float64List a) {
    var l = 2;
    if (n > 8) {
      _cft1st(n, a);
      l = 8;
      while ((l << 2) < n) {
        _cftmdl(n, l, a);
        l <<= 2;
      }
    }
    if ((l << 2) == n) {
      for (var j = 0; j < l; j += 2) {
        final j1 = j + l;
        final j2 = j1 + l;
        final j3 = j2 + l;
        final x0r = a[j] + a[j1];
        final x0i = -a[j + 1] - a[j1 + 1];
        final x1r = a[j] - a[j1];
        final x1i = -a[j + 1] + a[j1 + 1];
        final x2r = a[j2] + a[j3];
        final x2i = a[j2 + 1] + a[j3 + 1];
        final x3r = a[j2] - a[j3];
        final x3i = a[j2 + 1] - a[j3 + 1];
        a[j] = x0r + x2r;
        a[j + 1] = x0i - x2i;
        a[j2] = x0r - x2r;
        a[j2 + 1] = x0i + x2i;
        a[j1] = x1r - x3i;
        a[j1 + 1] = x1i - x3r;
        a[j3] = x1r + x3i;
        a[j3 + 1] = x1i + x3r;
      }
    } else {
      for (var j = 0; j < l; j += 2) {
        final j1 = j + l;
        final x0r = a[j] - a[j1];
        final x0i = -a[j + 1] + a[j1 + 1];
        a[j] += a[j1];
        a[j + 1] = -a[j + 1] - a[j1 + 1];
        a[j1] = x0r;
        a[j1 + 1] = x0i;
      }
    }
  }

  void _rftfsub(int n, Float64List a) {
    final m = n >> 1;
    final ks = 2 * nc ~/ m;
    var kk = 0;
    for (var j = 2; j < m; j += 2) {
      final k = n - j;
      kk += ks;
      final wkr = 0.5 - w[nw + nc - kk];
      final wki = w[nw + kk];
      final xr = a[j] - a[k];
      final xi = a[j + 1] + a[k + 1];
      final yr = wkr * xr - wki * xi;
      final yi = wkr * xi + wki * xr;
      a[j] -= yr;
      a[j + 1] -= yi;
      a[k] += yr;
      a[k + 1] -= yi;
    }
  }

  void _rftbsub(int n, Float64List a) {
    a[1] = -a[1];
    final m = n >> 1;
    final ks = 2 * nc ~/ m;
    var kk = 0;
    for (var j = 2; j < m; j += 2) {
      final k = n - j;
      kk += ks;
      final wkr = 0.5 - w[nw + nc - kk];
      final wki = w[nw + kk];
      final xr = a[j] - a[k];
      final xi = a[j + 1] + a[k + 1];
      final yr = wkr * xr + wki * xi;
      final yi = wkr * xi - wki * xr;
      a[j] -= yr;
      a[j + 1] = yi - a[j + 1];
      a[k] += yr;
      a[k + 1] = yi - a[k + 1];
    }
    a[m + 1] = -a[m + 1];
  }

  /// In-place forward transform (`rdft(n, +1, a)`).
  void forward(Float64List a) {
    if (n > 4) {
      _bitrv2(n, a);
      _cftfsub(n, a);
      _rftfsub(n, a);
    } else if (n == 4) {
      _cftfsub(n, a);
    }
    final xi = a[0] - a[1];
    a[0] += a[1];
    a[1] = xi;
  }

  /// In-place inverse transform (`rdft(n, -1, a)`, unscaled).
  void inverse(Float64List a) {
    a[1] = 0.5 * (a[0] - a[1]);
    a[0] -= a[1];
    if (n > 4) {
      _rftbsub(n, a);
      _bitrv2(n, a);
      _cftbsub(n, a);
    } else if (n == 4) {
      _cftfsub(n, a);
    }
  }
}
