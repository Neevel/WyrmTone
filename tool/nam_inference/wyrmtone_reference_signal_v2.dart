/// V4f — Reference Signal V2: WyrmToneReferenceSignal (V4d) with ONLY the
/// 0–5 s Stage-A ramp segment changed, per the V4f excitation sweep
/// (`native/nam_bridge/out/v4f_stage_a_sweep.dart` /
/// `v4f_stage_a_sweep2.dart`, TRAIN/DEV = {Solid, JVM410H Standard, Fender
/// AKG414, FNDR PANO}, then validated once on the GOJIRA holdout in
/// `v4f_stage_a_holdout.dart`).
///
/// Finding: a single low-frequency tone (V1's 110 Hz ramp) gives Stage A's
/// least-squares fit very few effectively-independent amplitude
/// observations for several models (its per-100ms-block peak saturates
/// within the FIRST block for 3 of 5 goldens — see `eP=eN=1` in
/// `v4f_stage_a_targets.dart`'s output), which makes the fitted a+/a- highly
/// sensitive to exactly which single frequency and ramp shape was used. A
/// 5-tone multisine (80/200/440/1000/2000 Hz, equal amplitude, fixed
/// deterministic phases, same textbook construction pattern as the
/// multitone below) under the SAME linear 0→1 envelope reduced the mean
/// TRAIN/DEV Stage-A distance score by roughly 2x, and still improved (by
/// ~1.07x, more modestly) on the untouched GOJIRA holdout — see
/// `docs/MATRIBOX_NAM_TRANSFER_RESEARCH.md` (V4f) for the full numbers.
///
/// The 5–6 s silence, 6.000–6.005 s burst, and 6.005–70 s Schroeder-phase
/// multitone are UNCHANGED from V1 (`wyrmtone_reference_signal.dart`) —
/// intentionally duplicated here rather than importing V1's private
/// helpers, so V1 stays frozen and untouched (its own hash-locked test
/// keeps guarding it).
library;

import 'dart:math' as math;
import 'dart:typed_data';

class WyrmToneReferenceSignalV2 {
  const WyrmToneReferenceSignalV2._();

  static const int sampleRate = 48000;
  static const int totalFrames = 70 * sampleRate; // 3,360,000

  /// The 5-tone Stage-A excitation set selected by the V4f sweep.
  static const List<double> rampFreqsHz = [80.0, 200.0, 440.0, 1000.0, 2000.0];

  static Float32List generate() {
    final out = Float32List(totalFrames);
    _writeMultisineRamp(out, 0, 5 * sampleRate);
    // 5–6 s stays silent (Float32List is zero-initialized), same as V1.
    final burstStart = 6 * sampleRate;
    const burstLength = 240; // 5 ms
    _writeBurst(out, burstStart, burstLength);
    final broadbandStart = burstStart + burstLength;
    _writeMultitone(out, broadbandStart, totalFrames - broadbandStart);
    return out;
  }

  /// 5-tone multisine (see [rampFreqsHz]), linear amplitude envelope 0->1
  /// over [offset, offset+length), equal-amplitude tones summed with fixed
  /// deterministic phase offsets (same pattern as [_writeMultitone]'s
  /// Schroeder phases, just not Schroeder-specific -- these phases only
  /// avoid all tones peaking simultaneously at t=0).
  static void _writeMultisineRamp(Float32List out, int offset, int length) {
    final k = rampFreqsHz.length;
    final omegas = [for (final f in rampFreqsHz) 2 * math.pi * f / sampleRate];
    final phases = [for (var j = 0; j < k; j++) math.pi * j / (k + 1)];
    for (var i = 0; i < length; i++) {
      final envelope = i / length;
      var s = 0.0;
      for (var j = 0; j < k; j++) {
        s += math.sin(omegas[j] * i + phases[j]);
      }
      out[offset + i] = envelope * s / k;
    }
  }

  /// Unchanged from V1: 1 kHz tone under a raised-cosine (Hann) window,
  /// peak 0.5.
  static void _writeBurst(Float32List out, int offset, int length) {
    const freqHz = 1000.0;
    const peak = 0.5;
    final omega = 2 * math.pi * freqHz / sampleRate;
    for (var i = 0; i < length; i++) {
      final window = 0.5 - 0.5 * math.cos(2 * math.pi * i / length);
      out[offset + i] = peak * window * math.sin(omega * i);
    }
  }

  /// Unchanged from V1: Schroeder-phase multitone, 300 tones log-spaced
  /// 80 Hz-18 kHz, peak 0.2.
  static void _writeMultitone(
    Float32List out,
    int offset,
    int length, {
    int toneCount = 300,
    double minHz = 80.0,
    double maxHz = 18000.0,
    double peak = 0.2,
  }) {
    final freqs = List<double>.generate(toneCount, (k) {
      final t = k / (toneCount - 1);
      return minHz * math.pow(maxHz / minHz, t);
    });
    final omegas = [for (final f in freqs) 2 * math.pi * f / sampleRate];
    final phases = List<double>.generate(
      toneCount,
      (k) => -math.pi * k * (k + 1) / toneCount,
    );
    final buf = Float64List(length);
    var peakAbs = 0.0;
    for (var i = 0; i < length; i++) {
      var s = 0.0;
      for (var k = 0; k < toneCount; k++) {
        s += math.sin(omegas[k] * i + phases[k]);
      }
      buf[i] = s;
      final a = s.abs();
      if (a > peakAbs) peakAbs = a;
    }
    final scale = peak / peakAbs;
    for (var i = 0; i < length; i++) {
      out[offset + i] = buf[i] * scale;
    }
  }
}
