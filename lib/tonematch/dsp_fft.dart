import 'dart:math' as math;
import 'dart:typed_data';

/// In-place iterative radix-2 complex FFT (size must be a power of two). Own implementation on
/// purpose: no dependency, fixed evaluation order, deterministic.
class Fft {
  Fft(this.size)
    : assert(size > 0 && (size & (size - 1)) == 0),
      _cos = Float64List(size ~/ 2),
      _sin = Float64List(size ~/ 2),
      _rev = Int32List(size) {
    for (var i = 0; i < size ~/ 2; i++) {
      _cos[i] = math.cos(2 * math.pi * i / size);
      _sin[i] = -math.sin(2 * math.pi * i / size);
    }
    final bits = (math.log(size) / math.ln2).round();
    for (var i = 0; i < size; i++) {
      var r = 0, x = i;
      for (var b = 0; b < bits; b++) {
        r = (r << 1) | (x & 1);
        x >>= 1;
      }
      _rev[i] = r;
    }
  }

  final int size;
  final Float64List _cos, _sin;
  final Int32List _rev;

  void transform(Float64List re, Float64List im) {
    for (var i = 0; i < size; i++) {
      final j = _rev[i];
      if (j > i) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var len = 2; len <= size; len <<= 1) {
      final half = len >> 1, step = size ~/ len;
      for (var start = 0; start < size; start += len) {
        for (var k = 0; k < half; k++) {
          final c = _cos[k * step], s = _sin[k * step];
          final a = start + k, b = a + half;
          final xr = re[b] * c - im[b] * s;
          final xi = re[b] * s + im[b] * c;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
        }
      }
    }
  }
}
