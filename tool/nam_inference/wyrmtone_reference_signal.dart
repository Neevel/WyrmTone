import 'dart:math' as math;
import 'dart:typed_data';

/// WyrmTone's own, fully algorithmic NAM identification/excitation signal
/// (V4d) — a drop-in replacement for the proprietary Sonicake
/// `nam_input_wav.wav` as the *input* to a NAM model, for use with the
/// existing frozen `MatriboxNamCloDataConverter` / `runEngine`
/// (`tool/matribox_nam_analysis/`).
///
/// Nothing here reads, hashes, or is derived from any Sonicake file. Every
/// sample is the closed-form result of the formulas documented below, with
/// no random-number generator (so there is no seed/portability question):
/// a linear-amplitude ramp, a raised-cosine burst, and a Schroeder-phase
/// multitone. All three are standard, textbook DSP test-signal
/// constructions; none of it is copied from, or fit to, any recording.
///
/// ## Why this exact layout
///
/// `runEngine` (`engine/stages.dart`) analyses fixed time windows of a
/// 70 s / 48 kHz signal (Stage A: 0–5 s; latency search: 6.000–6.0125 s;
/// Stage B and one Stage L call: 6–21 s; Stage C and another Stage L call:
/// 23–28 s; a third Stage L call: 30–50 s; Stage F: 50–70 s). That layout
/// is a genuine, unavoidable dependency of the *existing, frozen* engine —
/// see docs/MATRIBOX_NAM_TRANSFER_RESEARCH.md (V4d) for the
/// GENERIC/SIGNAL-LAYOUT-DEPENDENT/SONICAKE-SPECIFIC classification of
/// every stage. This generator reproduces that *timing* only (so the
/// unmodified engine can be reused without forking it) and fills every
/// section with WyrmTone's own content:
///
/// - **0–5 s**: a 110 Hz tone whose amplitude ramps linearly from 0 to full
///   scale, so Stage A's 100 ms analysis blocks see a steadily growing
///   positive and negative peak (the property Stage A actually needs — it
///   never inspects the ramp's exact shape, only per-block extrema).
/// - **5–6 s**: silence, so the latency search's assumption of "quiet
///   before the transient" holds regardless of which NAM is loaded.
/// - **6.000–6.005 s**: a 5 ms, 1 kHz raised-cosine-windowed burst at 0.5
///   peak — a clean, broadband-ish transient any causal model responds to
///   well inside the 600-sample (12.5 ms) search window.
/// - **6.005–70 s (64 s)**: a deterministic Schroeder-phase multitone
///   (300 tones, log-spaced 80 Hz–18 kHz, phases chosen to minimise crest
///   factor) at a moderate 0.2 peak — spectrally dense, flat-ish broadband
///   content for the Welch/FIR estimation stages, which only need energy
///   at each frequency bin, not any particular waveform.
class WyrmToneReferenceSignal {
  const WyrmToneReferenceSignal._();

  static const int sampleRate = 48000;
  static const int totalFrames = 70 * sampleRate; // 3,360,000

  /// Generates the full 70 s / 48 kHz mono signal. Deterministic: calling
  /// this twice yields bit-identical output (see
  /// `test/tool/nam_inference_test.dart`).
  static Float32List generate() {
    final out = Float32List(totalFrames);
    _writeRamp(out, 0, 5 * sampleRate);
    // 5–6 s stays silent (Float32List is zero-initialized).
    final burstStart = 6 * sampleRate;
    const burstLength = 240; // 5 ms
    _writeBurst(out, burstStart, burstLength);
    final broadbandStart = burstStart + burstLength;
    _writeMultitone(out, broadbandStart, totalFrames - broadbandStart);
    return out;
  }

  /// 110 Hz tone, linear amplitude ramp 0 -> 1 over [offset, offset+length).
  static void _writeRamp(Float32List out, int offset, int length) {
    const freqHz = 110.0;
    final omega = 2 * math.pi * freqHz / sampleRate;
    for (var i = 0; i < length; i++) {
      final envelope = i / length;
      out[offset + i] = envelope * math.sin(omega * i);
    }
  }

  /// 1 kHz tone under a raised-cosine (Hann) window, peak 0.5.
  static void _writeBurst(Float32List out, int offset, int length) {
    const freqHz = 1000.0;
    const peak = 0.5;
    final omega = 2 * math.pi * freqHz / sampleRate;
    for (var i = 0; i < length; i++) {
      final window = 0.5 - 0.5 * math.cos(2 * math.pi * i / length);
      out[offset + i] = peak * window * math.sin(omega * i);
    }
  }

  /// Schroeder-phase multitone: `toneCount` sinusoids log-spaced from
  /// [minHz] to [maxHz], phase_k = -pi*k*(k+1)/toneCount (the classic
  /// Schroeder 1970 formula for a low-crest-factor multitone), summed and
  /// scaled to [peak].
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
