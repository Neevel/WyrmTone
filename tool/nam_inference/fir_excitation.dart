/// V4g: parameterized, original excitation-signal generators for the
/// FIR1/FIR2 identification tail (Stages B/C/L/F). Every generator here is
/// a pure function of its parameters -- no file I/O, no dependency on any
/// captured or Sonicake-derived waveform. None of these are used in
/// production -- they exist only to probe which excitation properties
/// Stages B/C/L/F need. Deterministic pseudo-random families use a small,
/// fully self-contained generator (no dart:math Random) so the exact
/// sample stream is locked to this source, not to a platform RNG.
library;

import 'dart:math' as math;
import 'dart:typed_data';

const int firSampleRate = 48000;

/// Log-spaced sine sweep (20 Hz .. [maxHz]) using the standard exponential
/// chirp phase formula. If [cyclePeriodS] is null, the sweep runs once
/// across the whole [durationS] (matching how Reference Signal V1/V2 fill
/// their tail with one long construction); otherwise it restarts every
/// [cyclePeriodS] seconds, so any window shorter than [durationS] still
/// sees a full sweep.
Float32List logSweep({
  required double durationS,
  double minHz = 20.0,
  required double maxHz,
  double peak = 1.0,
  double? cyclePeriodS,
  int sampleRate = firSampleRate,
}) {
  final n = (durationS * sampleRate).round();
  final period = cyclePeriodS ?? durationS;
  final periodN = (period * sampleRate).round().clamp(1, n);
  final k = math.log(maxHz / minHz) / period;
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    final tCycle = (i % periodN) / sampleRate;
    final phase = 2 * math.pi * minHz / k * (math.exp(k * tCycle) - 1);
    out[i] = (peak * math.sin(phase)).toDouble();
  }
  return out;
}

/// Equal-amplitude multisine, [toneCount] tones log-spaced [minHz]..[maxHz],
/// deterministic fixed phases (same non-Schroeder pattern as V4f's family
/// G, kept distinct from Reference Signal V1/V2's own Schroeder multitone).
/// If [cyclePeriodS] is set, the tone frequencies are additionally snapped
/// to exact integer multiples of 1/cyclePeriodS so the whole construction
/// is periodic with that period (every window sees the identical spectrum).
Float32List multisine({
  required double durationS,
  double minHz = 20.0,
  required double maxHz,
  int toneCount = 40,
  double peak = 1.0,
  double? cyclePeriodS,
  int sampleRate = firSampleRate,
}) {
  final n = (durationS * sampleRate).round();
  var freqs = List<double>.generate(toneCount, (k) {
    final t = k / (toneCount - 1);
    return minHz * math.pow(maxHz / minHz, t);
  });
  if (cyclePeriodS != null) {
    final df = 1.0 / cyclePeriodS;
    freqs = [for (final f in freqs) (f / df).round() * df];
  }
  final omegas = [for (final f in freqs) 2 * math.pi * f / sampleRate];
  final phases = [
    for (var j = 0; j < toneCount; j++) math.pi * j / (toneCount + 1),
  ];
  final out = Float32List(n);
  final norm = peak / toneCount;
  for (var i = 0; i < n; i++) {
    var s = 0.0;
    for (var j = 0; j < toneCount; j++) {
      s += math.sin(omegas[j] * i + phases[j]);
    }
    out[i] = (norm * s).toDouble();
  }
  return out;
}

/// Deterministic maximal-length sequence (16-bit Fibonacci LFSR, taps at
/// bits 16/14/13/11 -- polynomial x^16+x^14+x^13+x^11+1, a standard
/// primitive polynomial), mapped to a bipolar +-[peak] signal. Period is
/// 65535 samples (~1.365 s at 48 kHz); the sequence repeats naturally, so
/// [cyclePeriodS] is not a free parameter here -- it is a property of the
/// generator itself (documented in [mlsPeriodS]).
const int mlsPeriodSamples = 65535;
double get mlsPeriodS => mlsPeriodSamples / firSampleRate;

Float32List mlsSequence({required double durationS, double peak = 1.0, int seed = 0xACE1}) {
  final n = (durationS * firSampleRate).round();
  final out = Float32List(n);
  var lfsr = seed & 0xFFFF;
  if (lfsr == 0) lfsr = 1;
  for (var i = 0; i < n; i++) {
    final bit = ((lfsr >> 15) ^ (lfsr >> 13) ^ (lfsr >> 12) ^ (lfsr >> 10)) & 1;
    lfsr = ((lfsr << 1) | bit) & 0xFFFF;
    out[i] = (bit == 1 ? peak : -peak).toDouble();
  }
  return out;
}

/// Deterministic broadband "white" noise from a self-contained linear
/// congruential generator (glibc constants), never dart:math's Random, so
/// the exact sample stream is fixed by this source alone.
Float32List whiteNoise({required double durationS, double peak = 1.0, int seed = 12345}) {
  final n = (durationS * firSampleRate).round();
  final out = Float32List(n);
  var state = seed & 0x7FFFFFFF;
  for (var i = 0; i < n; i++) {
    state = (1103515245 * state + 12345) & 0x7FFFFFFF;
    out[i] = (peak * (state / 0x7FFFFFFF * 2.0 - 1.0)).toDouble();
  }
  return out;
}

/// Deterministic pink-ish noise: [whiteNoise] through a simple one-pole
/// pinking approximation (Paul Kellet's "economy" filter, fixed
/// coefficients), then renormalized to [peak].
Float32List pinkNoise({required double durationS, double peak = 1.0, int seed = 12345}) {
  final white = whiteNoise(durationS: durationS, peak: 1.0, seed: seed);
  final out = Float32List(white.length);
  double b0 = 0, b1 = 0, b2 = 0;
  var maxAbs = 0.0;
  for (var i = 0; i < white.length; i++) {
    final w = white[i];
    b0 = 0.99765 * b0 + w * 0.0990460;
    b1 = 0.96300 * b1 + w * 0.2965164;
    b2 = 0.57000 * b2 + w * 1.0526913;
    final v = b0 + b1 + b2 + w * 0.1848;
    out[i] = v;
    if (v.abs() > maxAbs) maxAbs = v.abs();
  }
  final scale = maxAbs == 0 ? 1.0 : peak / maxAbs;
  for (var i = 0; i < out.length; i++) {
    out[i] = (out[i] * scale).toDouble();
  }
  return out;
}

/// Stepped-frequency sine: [levels] log-spaced frequencies from [minHz] to
/// [maxHz], each held for [holdS] seconds at [peak].
Float32List steppedFrequency({
  required int stepCount,
  double minHz = 20.0,
  required double maxHz,
  double holdS = 0.5,
  double peak = 1.0,
  int sampleRate = firSampleRate,
}) {
  final holdN = (holdS * sampleRate).round();
  final out = Float32List(stepCount * holdN);
  for (var s = 0; s < stepCount; s++) {
    final t = stepCount == 1 ? 0.0 : s / (stepCount - 1);
    final f = minHz * math.pow(maxHz / minHz, t);
    final omega = 2 * math.pi * f / sampleRate;
    for (var i = 0; i < holdN; i++) {
      out[s * holdN + i] = (peak * math.sin(omega * i)).toDouble();
    }
  }
  return out;
}

/// Hybrid: a one-shot log sweep plus a low-level additive dense multisine
/// texture (family J).
Float32List hybridSweepPlusNoise({
  required double durationS,
  double maxHz = 20000,
  double sweepPeak = 0.8,
  double noisePeak = 0.2,
  int seed = 999,
}) {
  final sweep = logSweep(durationS: durationS, maxHz: maxHz, peak: sweepPeak);
  final noise = whiteNoise(durationS: durationS, peak: noisePeak, seed: seed);
  final out = Float32List(sweep.length);
  for (var i = 0; i < out.length; i++) {
    out[i] = sweep[i] + noise[i];
  }
  return out;
}
