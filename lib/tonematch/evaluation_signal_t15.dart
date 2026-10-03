import 'dart:math' as math;
import 'dart:typed_data';

import 'evaluation_signal.dart';
import 'tone_features.dart';

/// The fixed derivation of the 15-second evaluation variant ("T15") from the resampled 48 kHz DI of
/// an original evaluation recording. This is the exact rule used in the validation gates
/// (docs/TONE_MATCH.md 6.2) and by the Android performance gate; it must not change without a new
/// signal id/version. Deterministic, no randomness.
///
///  - active span [a, b]: first/last 10 ms frame within 35 dB of the loudest frame;
///  - k = 6 windows of 2.5 s, each centred in one of k equal parts of the active span;
///  - 0.5 s of original material before `a` as lead-in; 20 ms linear fades at both ends of each window.
abstract final class EvaluationSignalT15 {
  static const contentSeconds = 15;
  static const _fade = 960; // 20 ms

  static Float32List derive(Float32List di) {
    const rate = evaluationSampleRate;
    final (a, b) = _activeSpan(di);
    const k = 6; // round(15 / 2.5)
    const len = (contentSeconds / k * rate) ~/ 1;
    final part = (b - a) / k;
    final head = Float32List.sublistView(di, math.max(0, a - rate ~/ 2), a);
    final pieces = <Float32List>[head];
    for (var i = 0; i < k; i++) {
      var start = (a + (i + 0.5) * part - len / 2).round();
      start = start.clamp(a, b - len);
      final w = Float32List.fromList(Float32List.sublistView(di, start, start + len));
      for (var j = 0; j < _fade; j++) {
        final g = j / _fade;
        w[j] *= g;
        w[len - 1 - j] *= g;
      }
      pieces.add(w);
    }
    final y = Float32List(pieces.fold(0, (s, p) => s + p.length));
    var o = 0;
    for (final p in pieces) {
      y.setRange(o, o + p.length, p);
      o += p.length;
    }
    return y;
  }

  static (int, int) _activeSpan(Float32List x) {
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
}
