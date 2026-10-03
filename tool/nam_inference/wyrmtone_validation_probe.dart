import 'dart:math' as math;
import 'dart:typed_data';

/// V4e: a THIRD, independent, purely mathematical excitation signal, used
/// only to *validate* already-extracted CloData parameters (Pipeline A vs
/// Pipeline B) — never for identification. It is built from different
/// primitives than both `WyrmToneReferenceSignal` (Schroeder multitone +
/// linear ramp) and Sonicake's own signal (unknown construction, evidence
/// only): a logarithmic sine sweep, isolated impulses and a distinct
/// non-monotonic envelope. Nothing here is derived from either.
///
/// No `dart:io`, no randomness, no external file — every sample is a
/// closed-form formula, documented inline.
class WyrmToneValidationProbe {
  const WyrmToneValidationProbe._();

  static const int sampleRate = 48000;

  /// Sample offsets of the impulse/burst regions, for tests that need to
  /// locate them without re-deriving the layout.
  static const int unitImpulseAt = 0 + (sampleRate ~/ 20); // 50 ms in
  static const int lowLevelImpulseAt = unitImpulseAt + sampleRate ~/ 4;
  static const int burstAt = lowLevelImpulseAt + sampleRate ~/ 4;
  static const int burstLength = 144; // 3 ms at 2 kHz
  static const int sweepMidAt = burstAt + burstLength + sampleRate ~/ 4;
  static const int sweepLength = 4 * sampleRate; // 4 s
  static const int sweepLowAt = sweepMidAt + sweepLength;
  static const int sweepHighAt = sweepLowAt + sweepLength;
  static const int envelopeAt = sweepHighAt + sweepLength;
  static const int envelopeLength = 2 * sampleRate; // 2 s
  static const int totalFrames = envelopeAt + envelopeLength;

  static Float32List generate() {
    final out = Float32List(totalFrames);
    out[unitImpulseAt] = 1.0;
    out[lowLevelImpulseAt] = 0.05;
    _writeBurst(out, burstAt, burstLength);
    _writeLogSweep(out, sweepMidAt, sweepLength, amplitude: 0.3);
    _writeLogSweep(out, sweepLowAt, sweepLength, amplitude: 0.05);
    _writeLogSweep(out, sweepHighAt, sweepLength, amplitude: 0.9);
    _writeAsymmetricEnvelope(out, envelopeAt, envelopeLength);
    return out;
  }

  /// 2 kHz tone under a Hann window (a different centre frequency and
  /// length than the identification signal's 1 kHz/5 ms burst).
  static void _writeBurst(Float32List out, int offset, int length) {
    const freqHz = 2000.0;
    final omega = 2 * math.pi * freqHz / sampleRate;
    for (var i = 0; i < length; i++) {
      final window = 0.5 - 0.5 * math.cos(2 * math.pi * i / length);
      out[offset + i] = window * math.sin(omega * i);
    }
  }

  /// Logarithmic ("exponential") sine sweep 20 Hz -> 20 kHz, the classic
  /// closed-form chirp: phase(t) = 2*pi*f0*T/ln(f1/f0) * (exp(t/T*ln(f1/f0)) - 1).
  static void _writeLogSweep(
    Float32List out,
    int offset,
    int length, {
    required double amplitude,
  }) {
    const f0 = 20.0, f1 = 20000.0;
    final durationS = length / sampleRate;
    final k = math.log(f1 / f0);
    for (var i = 0; i < length; i++) {
      final t = i / sampleRate;
      final phase =
          2 * math.pi * f0 * durationS / k * (math.exp(t / durationS * k) - 1);
      // Half-cosine fade-in/out (5 %) to avoid edge clicks between regions.
      final fade = math.min(
        1.0,
        math.min(i / (0.05 * length), (length - 1 - i) / (0.05 * length)),
      );
      out[offset + i] = amplitude * fade * math.sin(phase);
    }
  }

  /// 150 Hz tone whose amplitude follows a non-monotonic envelope that
  /// rises to +1, falls through 0 to -1 and returns to 0 — unlike either
  /// identification signal's monotonic ramp, this explicitly exercises
  /// positive AND negative excursions at every magnitude in one pass.
  static void _writeAsymmetricEnvelope(
    Float32List out,
    int offset,
    int length,
  ) {
    const freqHz = 150.0;
    final omega = 2 * math.pi * freqHz / sampleRate;
    for (var i = 0; i < length; i++) {
      final t = i / length; // 0..1
      final envelope = math.sin(2 * math.pi * t); // one full +/- cycle
      out[offset + i] = envelope * math.sin(omega * i);
    }
  }
}
