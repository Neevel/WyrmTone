/// V4g — Reference Signal V3: WyrmToneReferenceSignalV2 (V4f) with ONLY the
/// 6.005–70 s FIR-identification tail changed, per the V4g excitation sweep
/// (`native/nam_bridge/out/v4g_fir_sweep.dart` / `v4g_fir_sweep2.dart`,
/// TRAIN/DEV = {Solid, JVM410H Standard, Fender AKG414, FNDR PANO}, then
/// validated once on the GOJIRA holdout in `v4g_fir_holdout.dart`).
///
/// Finding: `WelchEstimator` (`engine/spectral.dart`), which Stages B/C/L
/// all use, computes an H1-style cross-spectrum magnitude
/// `|Sxy[k]| / (Sxx[k]+eps)` per frequency bin -- a bin where the
/// EXCITATION has near-zero energy gets an ill-conditioned estimate
/// regardless of how the model actually responds there. V1/V2's tail (a
/// Schroeder multitone that sweeps its whole spectrum only ONCE across the
/// full ~64 s) leaves any single analysis window (Stage C/L1: 5 s, Stage
/// B/L2: 15 s, Stage L3: 20 s, Stage F: 20 s) seeing only a FRAGMENT of
/// that one-shot spectrum. A logarithmic sine sweep (20 Hz-20 kHz) that
/// RESTARTS every 5 seconds -- so every window, however short, sees at
/// least one complete sweep -- reduced the mean TRAIN/DEV FIR1+FIR2 RMS
/// magnitude error from ~22.7 dB (V2 baseline) to ~17.2 dB, and still
/// improved (1.15x, driven mostly by FIR2) on the untouched GOJIRA holdout.
/// A moderate excitation level (peak 0.5 instead of 1.0) outperformed full
/// scale slightly, consistent with (but not conclusive proof of) some
/// nonlinear contamination of the linear-response estimate at full drive.
/// See `docs/MATRIBOX_NAM_TRANSFER_RESEARCH.md` (V4g) for the full numbers.
///
/// The 0–5 s Stage-A ramp, 5–6 s silence and 6.000–6.005 s burst are
/// UNCHANGED from V2 -- intentionally duplicated here rather than importing
/// V2's private helpers, so V1 and V2 both stay frozen and untouched (their
/// own hash-locked tests keep guarding them).
library;

import 'dart:math' as math;
import 'dart:typed_data';

class WyrmToneReferenceSignalV3 {
  const WyrmToneReferenceSignalV3._();

  static const int sampleRate = 48000;
  static const int totalFrames = 70 * sampleRate; // 3,360,000

  static const List<double> rampFreqsHz = [80.0, 200.0, 440.0, 1000.0, 2000.0];

  /// The V4g-selected FIR-identification tail: logarithmic sine sweep,
  /// 20 Hz-20 kHz, restarting every 5 s, peak 0.5.
  static const double tailSweepMinHz = 20.0;
  static const double tailSweepMaxHz = 20000.0;
  static const double tailSweepCyclePeriodS = 5.0;
  static const double tailSweepPeak = 0.5;

  static Float32List generate() {
    final out = Float32List(totalFrames);
    _writeMultisineRamp(out, 0, 5 * sampleRate);
    // 5-6 s stays silent (Float32List is zero-initialized), same as V1/V2.
    final burstStart = 6 * sampleRate;
    const burstLength = 240; // 5 ms
    _writeBurst(out, burstStart, burstLength);
    final tailStart = burstStart + burstLength;
    _writeSweepTail(out, tailStart, totalFrames - tailStart);
    return out;
  }

  /// Unchanged from V2: 5-tone multisine, linear 0->1 envelope.
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

  /// Unchanged from V1/V2: 1 kHz tone under a raised-cosine (Hann) window,
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

  /// New in V3: logarithmic sine sweep, [tailSweepMinHz]-[tailSweepMaxHz],
  /// restarting every [tailSweepCyclePeriodS] seconds, peak
  /// [tailSweepPeak]. Standard exponential-chirp phase formula.
  static void _writeSweepTail(Float32List out, int offset, int length) {
    final periodN = (tailSweepCyclePeriodS * sampleRate).round().clamp(1, length);
    final k = math.log(tailSweepMaxHz / tailSweepMinHz) / tailSweepCyclePeriodS;
    for (var i = 0; i < length; i++) {
      final tCycle = (i % periodN) / sampleRate;
      final phase = 2 * math.pi * tailSweepMinHz / k * (math.exp(k * tCycle) - 1);
      out[offset + i] = tailSweepPeak * math.sin(phase);
    }
  }
}
