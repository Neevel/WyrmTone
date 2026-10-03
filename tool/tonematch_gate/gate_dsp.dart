/// Offline experiment code for the Tone Match validation/ablation gate. NOT product code and not
/// part of AnalysisVersion 1: nothing here is imported by lib/.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:wyrmtone/tonematch/dsp_fft.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/tone_features.dart';

const _rate = evaluationSampleRate;

class GateVariant {
  const GateVariant(this.id, this.samples, this.contentSeconds);
  final String id;
  final Float32List samples;
  final double contentSeconds;
}

/// Active span of the DI in samples: first/last 10 ms frame within 35 dB of the loudest frame.
(int, int) activeSpan(Float32List x) {
  const f = 480;
  final frames = x.length ~/ f;
  final rms = Float64List(frames);
  var maxRms = 0.0;
  for (var i = 0; i < frames; i++) {
    var s = 0.0;
    for (var j = i * f; j < (i + 1) * f; j++) {
      s += x[j] * x[j];
    }
    rms[i] = math.sqrt(s / f);
    if (rms[i] > maxRms) maxRms = rms[i];
  }
  final thr = maxRms * math.pow(10, -ToneAnalysisParams.activeGateDbBelowInputPeak / 20);
  var a = 0, b = frames - 1;
  while (a < frames && rms[a] < thr) {
    a++;
  }
  while (b > a && rms[b] < thr) {
    b--;
  }
  return (a * f, (b + 1) * f);
}

/// FULL, SPAN and Tn variants as pre-registered in docs/TONE_MATCH.md section 6.2.
List<GateVariant> buildVariants(Float32List di, {required List<int> contentSeconds}) {
  final (a, b) = activeSpan(di);
  final out = <GateVariant>[GateVariant('FULL', di, di.length / _rate)];
  final spanStart = math.max(0, a - _rate ~/ 2), spanEnd = math.min(di.length, b + _rate * 3 ~/ 2);
  out.add(GateVariant('SPAN', Float32List.sublistView(di, spanStart, spanEnd), (b - a) / _rate));
  const fade = 960; // 20 ms
  for (final n in contentSeconds) {
    final k = (n / 2.5).round();
    final len = (n / k * _rate).round();
    final part = (b - a) / k;
    final head = Float32List.sublistView(di, math.max(0, a - _rate ~/ 2), a);
    final pieces = <Float32List>[head];
    for (var i = 0; i < k; i++) {
      var start = (a + (i + 0.5) * part - len / 2).round();
      start = start.clamp(a, b - len);
      final w = Float32List.fromList(Float32List.sublistView(di, start, start + len));
      for (var j = 0; j < fade; j++) {
        final g = j / fade;
        w[j] *= g;
        w[len - 1 - j] *= g;
      }
      pieces.add(w);
    }
    final total = pieces.fold(0, (s, p) => s + p.length);
    final y = Float32List(total);
    var o = 0;
    for (final p in pieces) {
      y.setRange(o, o + p.length, p);
      o += p.length;
    }
    out.add(GateVariant('T$n', y, n.toDouble()));
  }
  return out;
}

/// Alternative high-frequency / saturation descriptors, computed OFFLINE for comparison only.
Map<String, double> altMetrics(Float32List input, Float32List output) {
  const frame = ToneAnalysisParams.frameSize, hop = ToneAnalysisParams.hopSize;
  final frames = (input.length - frame) ~/ hop + 1;
  final ms = Float64List(frames);
  for (var f = 0; f < frames; f++) {
    var s = 0.0;
    for (var i = f * hop; i < f * hop + frame; i++) {
      s += input[i] * input[i];
    }
    ms[f] = s / frame;
  }
  final gate = ms.reduce(math.max) * math.pow(10, -ToneAnalysisParams.activeGateDbBelowInputPeak / 10);
  final fft = Fft(frame);
  final re = Float64List(frame), im = Float64List(frame);
  const bins = frame ~/ 2 + 1;
  final binHz = _rate / frame;
  final win = Float64List.fromList([for (var i = 0; i < frame; i++) 0.5 - 0.5 * math.cos(2 * math.pi * i / frame)]);
  List<Float64List> spec(Float32List x, int f) {
    for (var i = 0; i < frame; i++) {
      re[i] = x[f * hop + i] * win[i];
      im[i] = 0;
    }
    fft.transform(re, im);
    return [Float64List.fromList([for (var b = 0; b < bins; b++) re[b] * re[b] + im[b] * im[b]])];
  }

  final ltasIn = Float64List(bins), ltasOut = Float64List(bins);
  final v0 = (200 / binHz).ceil(), v1 = (4000 / binHz).floor();
  var valleyOut = 0.0, totalOut = 0.0, valleyIn = 0.0, totalIn = 0.0;
  for (var f = 0; f < frames; f++) {
    if (ms[f] < gate) continue;
    final pin = spec(input, f).first, pout = spec(output, f).first;
    for (var b = 0; b < bins; b++) {
      ltasIn[b] += pin[b];
      ltasOut[b] += pout[b];
    }
    final sorted = [for (var b = v0; b <= v1; b++) pin[b]]..sort();
    final thr = sorted[(sorted.length * 0.3).floor()];
    for (var b = v0; b <= v1; b++) {
      totalOut += pout[b];
      totalIn += pin[b];
      if (pin[b] <= thr) {
        valleyOut += pout[b];
        valleyIn += pin[b];
      }
    }
  }
  double e(Float64List l, double lo, double hi) {
    var s = 0.0;
    for (var b = (lo / binHz).ceil(); b * binHz < hi; b++) {
      s += l[b];
    }
    return s;
  }

  double db(double v) => 10 * math.log(v + 1e-30) / math.ln10;
  double slope(Float64List l) {
    // least squares of dB(power) against log2(f), 1-8 kHz
    var n = 0, sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    for (var b = (1000 / binHz).ceil(); b * binHz <= 8000; b++) {
      final x = math.log(b * binHz) / math.ln2, y = db(l[b]);
      n++;
      sx += x;
      sy += y;
      sxx += x * x;
      sxy += x * y;
    }
    return (n * sxy - sx * sy) / (n * sxx - sx * sx);
  }

  final hfOverMidOut = db(e(ltasOut, 3500, 8000) / e(ltasOut, 600, 3500));
  final hfOverMidIn = db(e(ltasIn, 3500, 8000) / e(ltasIn, 600, 3500));
  final midOverLowMid = db(e(ltasOut, 600, 1500) / e(ltasOut, 250, 600));
  final highMidOverMid = db(e(ltasOut, 1500, 3500) / e(ltasOut, 600, 1500));
  return {
    'alt.B.hfOverMidOutDb': hfOverMidOut,
    'alt.B.hfOverMidDeltaDb': hfOverMidOut - hfOverMidIn,
    'alt.C.slopeOutDbPerOct': slope(ltasOut),
    'alt.C.slopeDeltaDbPerOct': slope(ltasOut) - slope(ltasIn),
    'alt.D.valleyFillDb': db((valleyOut / totalOut) / (valleyIn / totalIn)),
    'alt.E.midOverLowMidDb': midOverLowMid,
    'alt.E.highMidOverMidDb': highMidOverMid,
  };
}

/// Diagnostic probe: seeded Gaussian noise at [rmsDbfs] through the NAM; the tilt of the OUTPUT
/// (3.5-8 kHz over 250-1500 Hz) describes cab/voicing filtering independent of playing material.
Float32List probeNoise(double rmsDbfs, {int seconds = 3}) {
  final rng = math.Random(42);
  final n = _rate * seconds;
  final x = Float32List(n);
  for (var i = 0; i < n; i += 2) {
    final u1 = rng.nextDouble().clamp(1e-12, 1.0), u2 = rng.nextDouble();
    final r = math.sqrt(-2 * math.log(u1));
    x[i] = r * math.cos(2 * math.pi * u2);
    if (i + 1 < n) x[i + 1] = r * math.sin(2 * math.pi * u2);
  }
  final k = math.pow(10, rmsDbfs / 20).toDouble();
  for (var i = 0; i < n; i++) {
    x[i] = x[i] * k;
  }
  return x;
}

double tiltDb(Float32List x) {
  const frame = ToneAnalysisParams.frameSize, hop = ToneAnalysisParams.hopSize;
  final fft = Fft(frame);
  final re = Float64List(frame), im = Float64List(frame);
  const bins = frame ~/ 2 + 1;
  final binHz = _rate / frame;
  final ltas = Float64List(bins);
  for (var f = 0; f + frame <= x.length; f += hop) {
    for (var i = 0; i < frame; i++) {
      re[i] = x[f + i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / frame));
      im[i] = 0;
    }
    fft.transform(re, im);
    for (var b = 0; b < bins; b++) {
      ltas[b] += re[b] * re[b] + im[b] * im[b];
    }
  }
  double e(double lo, double hi) {
    var s = 0.0, c = 0;
    for (var b = (lo / binHz).ceil(); b * binHz < hi; b++) {
      s += ltas[b];
      c++;
    }
    return s / c;
  }

  return 10 * math.log(e(3500, 8000) / e(250, 1500)) / math.ln10;
}

/// Output LTAS in 24 log-spaced bands (60 Hz-16 kHz), dB relative to the band mean.
List<double> ltasBands(Float32List x) {
  const frame = ToneAnalysisParams.frameSize, hop = ToneAnalysisParams.hopSize;
  final fft = Fft(frame);
  final re = Float64List(frame), im = Float64List(frame);
  const bins = frame ~/ 2 + 1;
  final binHz = _rate / frame;
  final ltas = Float64List(bins);
  for (var f = 0; f + frame <= x.length; f += hop) {
    for (var i = 0; i < frame; i++) {
      re[i] = x[f + i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / frame));
      im[i] = 0;
    }
    fft.transform(re, im);
    for (var b = 0; b < bins; b++) {
      ltas[b] += re[b] * re[b] + im[b] * im[b];
    }
  }
  final edges = [for (var i = 0; i <= 24; i++) 60 * math.pow(16000 / 60, i / 24).toDouble()];
  final out = <double>[];
  for (var i = 0; i < 24; i++) {
    var s = 0.0;
    var c = 0;
    for (var b = (edges[i] / binHz).ceil(); b * binHz < edges[i + 1]; b++) {
      s += ltas[b];
      c++;
    }
    out.add(10 * math.log((s / math.max(c, 1)) + 1e-30) / math.ln10);
  }
  final mean = out.reduce((a, b) => a + b) / out.length;
  return [for (final v in out) v - mean];
}
