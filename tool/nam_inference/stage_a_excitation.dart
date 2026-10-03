/// V4f: parameterized, original excitation-signal families for isolating
/// Stage A's non-linearity fit from the rest of the identification pipeline.
///
/// Every generator here is a pure function of its parameters (no RNG, no
/// file I/O, no dependency on any captured or Sonicake-derived waveform).
/// None of these are used for identification in production — they exist
/// only to probe how Stage A's curve fit (`stageA()` in
/// `tool/matribox_nam_analysis/engine/stages.dart`, UNCHANGED here) responds
/// to different excitation trajectories.
library;

import 'dart:math' as math;
import 'dart:typed_data';

const int stageASampleRate = 48000;

/// Shape of the amplitude envelope applied to a sine carrier.
enum RampShape { linear, exponential, triangle, slowSineEnvelope }

/// Families A/B/D/F: a sine carrier at [freqHz] under an amplitude envelope
/// from 0 (or [floor]) up to [peak] over [durationS] seconds.
///
/// - [RampShape.linear]: straight-line envelope (family A).
/// - [RampShape.exponential]: envelope grows as `peak*(1-exp(-3*t/T))`,
///   i.e. most of the range is covered quickly and the last stretch is a
///   slow approach to [peak] (family B).
/// - [RampShape.triangle]: envelope rises to [peak] at the midpoint and
///   back down to [floor] by the end -- a non-monotonic amplitude
///   trajectory, same total duration (family D).
/// - [RampShape.slowSineEnvelope]: the envelope itself is
///   `0.5*(1-cos(pi*t/T))`, i.e. a half-cosine (smooth start/end,
///   monotonic, slower initial slope than linear) -- used with a low
///   carrier frequency for "slow sine, increasing amplitude" (family F).
Float32List rampExcitation({
  required RampShape shape,
  required double freqHz,
  required double durationS,
  double peak = 1.0,
  double floor = 0.0,
  int sampleRate = stageASampleRate,
}) {
  final n = (durationS * sampleRate).round();
  final out = Float32List(n);
  final t = durationS <= 0 ? 1.0 : durationS;
  for (var i = 0; i < n; i++) {
    final time = i / sampleRate;
    final frac = (time / t).clamp(0.0, 1.0);
    double env;
    switch (shape) {
      case RampShape.linear:
        env = floor + (peak - floor) * frac;
        break;
      case RampShape.exponential:
        env = floor + (peak - floor) * (1 - math.exp(-3 * frac));
        break;
      case RampShape.triangle:
        final tri = frac <= 0.5 ? (frac / 0.5) : (1 - (frac - 0.5) / 0.5);
        env = floor + (peak - floor) * tri;
        break;
      case RampShape.slowSineEnvelope:
        env = floor + (peak - floor) * 0.5 * (1 - math.cos(math.pi * frac));
        break;
    }
    out[i] = (env * math.sin(2 * math.pi * freqHz * time)).toDouble();
  }
  return out;
}

/// Family C: a stepped amplitude sweep. [levels] amplitude levels (e.g.
/// 0.05..1.0), each held for [holdS] seconds at [freqHz], with [gapS]
/// seconds of silence between levels so Stage A's per-block max/min sees a
/// clean, isolated observation at each level.
Float32List steppedExcitation({
  required List<double> levels,
  required double freqHz,
  double holdS = 0.3,
  double gapS = 0.05,
  int sampleRate = stageASampleRate,
}) {
  final holdN = (holdS * sampleRate).round();
  final gapN = (gapS * sampleRate).round();
  final n = levels.length * (holdN + gapN);
  final out = Float32List(n);
  var pos = 0;
  for (final level in levels) {
    for (var i = 0; i < holdN; i++) {
      out[pos + i] = (level * math.sin(2 * math.pi * freqHz * i / sampleRate))
          .toDouble();
    }
    pos += holdN + gapN; // gap stays zero (silence)
  }
  return out;
}

/// Family E: separate positive-only and negative-only excitation halves.
/// First half: a half-wave-rectified sine (positive excursions only) with
/// a linear 0->peak envelope. Second half: the same but negated (negative
/// excursions only). Tests whether decoupling which polarity is "seen"
/// first/more changes the fitted a+/a-.
Float32List asymmetricExcitation({
  required double freqHz,
  required double durationS,
  double peak = 1.0,
  int sampleRate = stageASampleRate,
}) {
  final n = (durationS * sampleRate).round();
  final half = n ~/ 2;
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    final inSecondHalf = i >= half;
    final localI = inSecondHalf ? i - half : i;
    final localN = inSecondHalf ? (n - half) : half;
    final frac = localN <= 0 ? 0.0 : (localI / localN).clamp(0.0, 1.0);
    final env = peak * frac;
    final carrier = math.sin(2 * math.pi * freqHz * i / sampleRate);
    final rect = inSecondHalf ? -carrier.abs() : carrier.abs();
    out[i] = (env * rect).toDouble();
  }
  return out;
}

/// Family G: a multisine (several harmonically-unrelated tones summed,
/// deterministic fixed phases) under a [shape] 0->peak envelope (default
/// linear, family G proper; other shapes let the sweep check whether the
/// multisine's advantage survives a different envelope, same as family A/B
/// does for a single tone).
Float32List multisineRampExcitation({
  required List<double> freqsHz,
  required double durationS,
  double peak = 1.0,
  RampShape shape = RampShape.linear,
  int sampleRate = stageASampleRate,
}) {
  final n = (durationS * sampleRate).round();
  final out = Float32List(n);
  final k = freqsHz.length;
  for (var i = 0; i < n; i++) {
    final time = i / sampleRate;
    final frac = (time / durationS).clamp(0.0, 1.0);
    double envFrac;
    switch (shape) {
      case RampShape.linear:
        envFrac = frac;
        break;
      case RampShape.exponential:
        envFrac = 1 - math.exp(-3 * frac);
        break;
      case RampShape.triangle:
        envFrac = frac <= 0.5 ? (frac / 0.5) : (1 - (frac - 0.5) / 0.5);
        break;
      case RampShape.slowSineEnvelope:
        envFrac = 0.5 * (1 - math.cos(math.pi * frac));
        break;
    }
    var sum = 0.0;
    for (var j = 0; j < k; j++) {
      // Deterministic fixed phase offset per tone, same construction
      // pattern as an equal-amplitude multisine (not Schroeder-phase, to
      // keep this family distinct from WyrmToneReferenceSignal's own).
      final phase = math.pi * j / (k + 1);
      sum += math.sin(2 * math.pi * freqsHz[j] * time + phase);
    }
    final env = peak * envFrac / k;
    out[i] = (env * sum).toDouble();
  }
  return out;
}

/// Family H: deterministic broadband (summed odd harmonics of [baseFreqHz],
/// approximating a band-limited square-ish wave) under a stepped gain
/// schedule ([levels], each held [holdS] seconds).
Float32List broadbandSteppedGainExcitation({
  required List<double> levels,
  required double baseFreqHz,
  double holdS = 0.3,
  int harmonics = 7,
  int sampleRate = stageASampleRate,
}) {
  final holdN = (holdS * sampleRate).round();
  final n = levels.length * holdN;
  final out = Float32List(n);
  var pos = 0;
  for (final level in levels) {
    for (var i = 0; i < holdN; i++) {
      var sum = 0.0;
      var norm = 0.0;
      for (var h = 0; h < harmonics; h++) {
        final mult = (2 * h + 1).toDouble();
        final amp = 1.0 / mult;
        sum += amp * math.sin(2 * math.pi * baseFreqHz * mult * i / sampleRate);
        norm += amp;
      }
      out[pos + i] = (level * sum / norm).toDouble();
    }
    pos += holdN;
  }
  return out;
}
