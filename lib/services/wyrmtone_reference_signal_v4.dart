/// V4i — Reference Signal V4: WyrmToneReferenceSignalV3 (V4g) with ONLY
/// the 6-21s window's level changed, per the V4i Stage-C two-window
/// analysis.
///
/// Finding (external evidence only -- scalar RMS/peak/crest statistics of
/// the official Sonicake reference WAV, no waveform reconstructed): that
/// window's RMS is 0.0018 with a crest factor of 528 (i.e. near-silent,
/// with one brief transient), against the 23-28s window's RMS of 0.40 and
/// crest factor 1.4 (normal broadband level) -- a ~220x RMS difference.
/// V1/V2/V3 use the SAME broadband level in both windows (RMS ratio
/// 1.000), which does not match this structural property of Stage C: its
/// `bMag` (from the 6-21s window) sets a noise-floor regularization
/// threshold (`thr = max(bMag) * 0.001`) for `m3` (from the 23-28s
/// window) -- a role that only makes sense if 6-21s is meant to be a
/// quiet/floor reference, not a second loud broadband window.
///
/// Reducing 6-21s to 2% of V3's level (kept non-zero: full silence there
/// makes the frozen `stageL()` diverge to NaN, per V4g's window-ablation
/// finding) improved FIR1's magnitude-response RMS error by 17-76% across
/// all 5 models (TRAIN/DEV: Solid 16.51->12.73dB, JVM410H 9.24->7.13dB,
/// Fender 6.75->1.70dB, FNDR PANO 11.78->2.85dB; GOJIRA holdout, never
/// used for selection: 15.96->13.22dB), with FIR2 essentially unchanged
/// (<=1.1dB, mixed sign) and Stage A untouched (0-5s is not part of this
/// change). See `docs/MATRIBOX_NAM_TRANSFER_RESEARCH.md` (V4i) for the
/// full numbers.
///
/// The 0-6.005s Stage-A prefix and the 23-70s FIR-identification content
/// are UNCHANGED from V3 -- intentionally duplicated here rather than
/// importing V3's private helpers, so V1/V2/V3 all stay frozen and
/// untouched (their own hash-locked tests keep guarding them).
///
/// Lives in `lib/` (Android NAM Inference V1) so the SAME generator serves
/// both the Windows offline research tooling (`tool/nam_inference/`, which
/// re-exports this file) and on-device Android inference -- one signal
/// definition, never two. Pure Dart (`dart:math`/`dart:typed_data`, no
/// FFI), so it is expected to produce byte-identical output on every
/// platform Dart runs on.
library;

import 'dart:math' as math;
import 'dart:typed_data';

class WyrmToneReferenceSignalV4 {
  const WyrmToneReferenceSignalV4._();

  static const int sampleRate = 48000;
  static const int totalFrames = 70 * sampleRate; // 3,360,000

  static const List<double> rampFreqsHz = [80.0, 200.0, 440.0, 1000.0, 2000.0];

  static const double tailSweepMinHz = 20.0;
  static const double tailSweepMaxHz = 20000.0;
  static const double tailSweepCyclePeriodS = 5.0;
  static const double tailSweepPeak = 0.5;

  /// The V4i-selected reduction of the 6-21s window, relative to the
  /// unchanged 23-70s sweep's own level.
  static const double quietWindowFraction = 0.02;
  static const int quietWindowStartSec = 6;
  static const int quietWindowLengthSec = 15;

  static Float32List generate() {
    final out = Float32List(totalFrames);
    _writeMultisineRamp(out, 0, 5 * sampleRate);
    // 5-6 s stays silent (Float32List is zero-initialized), same as V1/V2/V3.
    final burstStart = 6 * sampleRate;
    const burstLength = 240; // 5 ms
    _writeBurst(out, burstStart, burstLength);
    final tailStart = burstStart + burstLength;
    _writeSweepTail(out, tailStart, totalFrames - tailStart);
    _applyQuietWindow(out);
    return out;
  }

  /// Unchanged from V2/V3: 5-tone multisine, linear 0->1 envelope.
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

  /// Unchanged from V1/V2/V3: 1 kHz tone under a raised-cosine (Hann)
  /// window, peak 0.5.
  static void _writeBurst(Float32List out, int offset, int length) {
    const freqHz = 1000.0;
    const peak = 0.5;
    final omega = 2 * math.pi * freqHz / sampleRate;
    for (var i = 0; i < length; i++) {
      final window = 0.5 - 0.5 * math.cos(2 * math.pi * i / length);
      out[offset + i] = peak * window * math.sin(omega * i);
    }
  }

  /// Unchanged from V3: logarithmic sine sweep, 20 Hz-20 kHz, restarting
  /// every 5 s, peak 0.5.
  static void _writeSweepTail(Float32List out, int offset, int length) {
    final periodN = (tailSweepCyclePeriodS * sampleRate).round().clamp(1, length);
    final k = math.log(tailSweepMaxHz / tailSweepMinHz) / tailSweepCyclePeriodS;
    for (var i = 0; i < length; i++) {
      final tCycle = (i % periodN) / sampleRate;
      final phase = 2 * math.pi * tailSweepMinHz / k * (math.exp(k * tCycle) - 1);
      out[offset + i] = tailSweepPeak * math.sin(phase);
    }
  }

  /// New in V4: attenuates the 6-21s window (part of the otherwise
  /// unchanged sweep tail) to [quietWindowFraction] of its V3 level.
  static void _applyQuietWindow(Float32List out) {
    final start = quietWindowStartSec * sampleRate;
    final end = start + quietWindowLengthSec * sampleRate;
    for (var i = start; i < end; i++) {
      out[i] = out[i] * quietWindowFraction;
    }
  }
}
