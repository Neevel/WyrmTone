import 'dart:math' as math;
import 'dart:typed_data';

import 'evaluation_signal.dart';
import 'tone_features.dart';

/// Attack / decay / transient values of ONE envelope raster phase.
class EnvelopePhaseResult {
  const EnvelopePhaseResult({required this.onsetCount, this.attackMs, this.decayDbPerSec, this.transientPeakToBodyDb});
  final double onsetCount;
  final double? attackMs, decayDbPerSec, transientPeakToBodyDb;
}

/// The envelope primitive behind `attackMs`, `decayDbPerSec` and `transientPeakToBodyDb`.
///
/// [atPhase] is the AnalysisVersion-1 computation, unchanged, on an envelope raster that starts
/// [phase] samples into the signal (window 256, hop 64). `phase == 0` is exactly V1.
/// AnalysisVersion 2 evaluates the same logic on [v2Phases] and aggregates by the median (see
/// docs/TONE_MATCH.md). No other feature uses this primitive: `envelopeRangeDb` and
/// `envelopeCompressionDb` come from the 2048/512 STFT frames and are not touched.
abstract final class EnvelopeFeatures {
  /// Envelope raster phases of the 4-phase V2 prototype (samples; the hop stays 64).
  static const v2Phases = [0, 16, 32, 48];

  /// [count] raster phases evenly spread over one 64-sample hop (4: 0,16,32,48; 8: 0,8,..,56;
  /// 16: 0,4,..,60). Only these counts take part in the final envelope gate (docs section 9).
  static List<int> phasesFor(int count) {
    if (count != 4 && count != 8 && count != 16) throw ArgumentError.value(count, 'count', 'must be 4, 8 or 16');
    return [for (var i = 0; i < count; i++) i * (ToneAnalysisParams.envHop ~/ count)];
  }

  static EnvelopePhaseResult atPhase(Float32List input, Float32List output, double k, int phase) {
    const w = ToneAnalysisParams.envWindow, h = ToneAnalysisParams.envHop;
    final n = input.length - phase;
    final count = (n - w) ~/ h + 1;
    final envIn = Float64List(count), envOut = Float64List(count);
    for (var j = 0; j < count; j++) {
      var si = 0.0, so = 0.0;
      for (var i = phase + j * h; i < phase + j * h + w; i++) {
        si += input[i] * input[i];
        final o = output[i] * k;
        so += o * o;
      }
      envIn[j] = _db10(si / w);
      envOut[j] = _db10(so / w);
    }
    double hops(double ms) => ms * evaluationSampleRate / 1000 / h;
    final maxIn = envIn.reduce(math.max);
    final minLevel = maxIn - ToneAnalysisParams.activeGateDbBelowInputPeak;
    final rise = hops(10).round(), refractory = hops(120).round();
    final onsets = <int>[];
    for (var j = rise; j < count; j++) {
      if (envIn[j] >= minLevel && envIn[j] - envIn[j - rise] >= 9.0 && (onsets.isEmpty || j - onsets.last >= refractory)) {
        onsets.add(j);
      }
    }
    final peakWin = hops(120).round();
    final bodyFrom = hops(60).round(), bodyTo = hops(160).round();
    final decFrom = hops(30).round(), decTo = hops(200).round();
    final attacks = <double>[], bodies = <double>[], decays = <double>[];
    for (var o = 0; o < onsets.length; o++) {
      final j = onsets[o];
      final next = o + 1 < onsets.length ? onsets[o + 1] : count;
      if (j + peakWin >= count) continue;
      var jp = j;
      for (var q = j; q <= j + peakWin; q++) {
        if (envOut[q] > envOut[jp]) jp = q;
      }
      if (jp + decTo >= next || jp + decTo >= count) continue; // needs 200 ms undisturbed
      attacks.add((jp - j) * h * 1000 / evaluationSampleRate);
      var bp = 0.0;
      for (var q = jp + bodyFrom; q <= jp + bodyTo; q++) {
        bp += math.pow(10, envOut[q] / 10);
      }
      bodies.add(envOut[jp] - _db10(bp / (bodyTo - bodyFrom + 1)));
      // least-squares slope (dB per second) over the decay window
      final m = decTo - decFrom + 1;
      var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
      for (var q = 0; q < m; q++) {
        final x = (decFrom + q) * h / evaluationSampleRate, y = envOut[jp + decFrom + q];
        sx += x;
        sy += y;
        sxx += x * x;
        sxy += x * y;
      }
      decays.add((m * sxy - sx * sy) / (m * sxx - sx * sx));
    }
    return EnvelopePhaseResult(
      onsetCount: attacks.length.toDouble(),
      attackMs: attacks.isEmpty ? null : median(attacks),
      transientPeakToBodyDb: attacks.isEmpty ? null : median(bodies),
      decayDbPerSec: attacks.isEmpty ? null : median(decays),
    );
  }

  /// V2 aggregation: the median over [results] of each feature that exists in at least one phase.
  static EnvelopePhaseResult medianOf(List<EnvelopePhaseResult> results) {
    double? m(Iterable<double?> v) {
      final x = [for (final e in v) ?e];
      return x.isEmpty ? null : median(x);
    }

    return EnvelopePhaseResult(
      // The median number of valid onsets over the phases (not rounded).
      onsetCount: median([for (final r in results) r.onsetCount]),
      attackMs: m(results.map((r) => r.attackMs)),
      decayDbPerSec: m(results.map((r) => r.decayDbPerSec)),
      transientPeakToBodyDb: m(results.map((r) => r.transientPeakToBodyDb)),
    );
  }

  static double _db10(double v) => 10 * math.log(v + 1e-30) / math.ln10;

  static double median(List<double> v) {
    final s = [...v]..sort();
    final pos = 0.5 * (s.length - 1);
    final lo = pos.floor(), hi = pos.ceil();
    return s[lo] + (s[hi] - s[lo]) * (pos - lo);
  }
}
