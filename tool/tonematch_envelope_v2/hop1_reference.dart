/// Independent reference implementation of the envelope metric DEFINITION at hop 1 (the limit of
/// infinitely many raster phases): same window (256), same detection rule and the same windows
/// (converted to samples exactly as V1's rounded hops) as EnvelopeFeatures. Experiment code only.
library;

import 'dart:math' as math;
import 'dart:typed_data';

class Hop1Reference {
  const Hop1Reference({required this.attackMs, required this.decayDbPerSec, required this.transientPeakToBodyDb, required this.onsets});
  final double? attackMs, decayDbPerSec, transientPeakToBodyDb;
  final int onsets;
}

Hop1Reference hop1Reference(Float32List input, Float32List output) {
  const w = 256, fs = 48000;
  final n = input.length;
  List<double> env(Float32List x) {
    final cum = Float64List(n + 1);
    for (var i = 0; i < n; i++) {
      cum[i + 1] = cum[i] + x[i] * x[i];
    }
    return [for (var j = 0; j <= n - w; j++) 10 * math.log((cum[j + w] - cum[j]) / w + 1e-30) / math.ln10];
  }

  final envIn = env(input), envOut = env(output);
  final count = envIn.length;
  final maxIn = envIn.reduce(math.max);
  const rise = 512, refractory = 5760, peakWin = 5760;
  const bodyFrom = 2880, bodyTo = 7680, decFrom = 1472, decTo = 9600;
  final onsets = <int>[];
  for (var j = rise; j < count; j++) {
    if (envIn[j] >= maxIn - 35 && envIn[j] - envIn[j - rise] >= 9.0 && (onsets.isEmpty || j - onsets.last >= refractory)) onsets.add(j);
  }
  final attacks = <double>[], bodies = <double>[], decays = <double>[];
  for (var o = 0; o < onsets.length; o++) {
    final j = onsets[o];
    final next = o + 1 < onsets.length ? onsets[o + 1] : count;
    if (j + peakWin >= count) continue;
    var jp = j;
    for (var q = j; q <= j + peakWin; q++) {
      if (envOut[q] > envOut[jp]) jp = q;
    }
    if (jp + decTo >= next || jp + decTo >= count) continue;
    attacks.add((jp - j) * 1000 / fs);
    var bp = 0.0;
    for (var q = jp + bodyFrom; q <= jp + bodyTo; q++) {
      bp += math.pow(10, envOut[q] / 10);
    }
    bodies.add(envOut[jp] - 10 * math.log(bp / (bodyTo - bodyFrom + 1) + 1e-30) / math.ln10);
    final m = decTo - decFrom + 1;
    var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    for (var q = 0; q < m; q++) {
      final x = (decFrom + q) / fs, y = envOut[jp + decFrom + q];
      sx += x;
      sy += y;
      sxx += x * x;
      sxy += x * y;
    }
    decays.add((m * sxy - sx * sy) / (m * sxx - sx * sx));
  }
  double? median(List<double> v) {
    if (v.isEmpty) return null;
    final s = [...v]..sort();
    final pos = 0.5 * (s.length - 1);
    return s[pos.floor()] + (s[pos.ceil()] - s[pos.floor()]) * (pos - pos.floor());
  }

  return Hop1Reference(attackMs: median(attacks), decayDbPerSec: median(decays), transientPeakToBodyDb: median(bodies), onsets: attacks.length);
}
