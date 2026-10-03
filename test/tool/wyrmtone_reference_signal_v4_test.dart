import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/nam_inference/wyrmtone_reference_signal_v4.dart';

/// V4i: Reference Signal V4 (only the 6-21s window's level changed from
/// V3; everything else, incl. the 23-70s sweep tail's own content,
/// unchanged).
void main() {
  test('V4: deterministic, exact length, finite', () {
    final a = WyrmToneReferenceSignalV4.generate();
    final b = WyrmToneReferenceSignalV4.generate();
    expect(a.length, WyrmToneReferenceSignalV4.totalFrames);
    expect(a, orderedEquals(b));
    for (final v in a) {
      expect(v.isFinite, isTrue);
      expect(v.abs(), lessThanOrEqualTo(1.0001));
    }
  });

  test('V4: 6-21s window peak is ~quietWindowFraction of the unattenuated sweep peak', () {
    final sig = WyrmToneReferenceSignalV4.generate();
    double peakIn(int startSec, int lenSec) {
      var m = 0.0;
      for (var i = startSec * 48000; i < (startSec + lenSec) * 48000; i++) {
        m = math.max(m, sig[i].abs());
      }
      return m;
    }

    final quietPeak = peakIn(
      WyrmToneReferenceSignalV4.quietWindowStartSec,
      WyrmToneReferenceSignalV4.quietWindowLengthSec,
    );
    final loudPeak = peakIn(23, 5); // untouched 23-28s window
    expect(loudPeak, closeTo(WyrmToneReferenceSignalV4.tailSweepPeak, 0.02));
    expect(
      quietPeak / loudPeak,
      closeTo(WyrmToneReferenceSignalV4.quietWindowFraction, 0.005),
    );
  });

  test('V4: regions outside 6-21s are byte-identical to an unattenuated sweep tail', () {
    final sig = WyrmToneReferenceSignalV4.generate();
    // Spot-check the 23-28s window matches the plain (unattenuated) log
    // sweep formula directly -- i.e. this region was NOT touched.
    const minHz = 20.0, maxHz = 20000.0, periodS = 5.0, peak = 0.5;
    final k = math.log(maxHz / minHz) / periodS;
    final periodN = (periodS * 48000).round();
    const start = 23 * 48000;
    for (var i = 0; i < 200; i++) {
      final globalI = start + i - (6 * 48000 + 240); // offset within the tail
      final tCycle = (globalI % periodN) / 48000;
      final phase = 2 * math.pi * minHz / k * (math.exp(k * tCycle) - 1);
      expect(sig[start + i], closeTo(peak * math.sin(phase), 1e-4));
    }
  });

  // Android NAM Inference V1, section 5: a stable fingerprint of the actual
  // float samples so the exact same value can be recomputed on-device and
  // compared -- this generator is pure Dart (dart:math/dart:typed_data, no
  // FFI), so it is expected to be byte-identical on every platform Dart
  // runs on. Pinned value computed on Windows/host Dart VM.
  test('V4: SHA-256 fingerprint of the generated float32 samples is pinned', () {
    final sig = WyrmToneReferenceSignalV4.generate();
    final bytes = sig.buffer.asUint8List();
    expect(bytes.length, WyrmToneReferenceSignalV4.totalFrames * 4);
    final hash = sha256.convert(bytes).toString();
    expect(
      hash,
      '63673d3de9c5259f2f540fab722469a85599bbf54a7c672aead8a7337bf0b3d2',
      reason:
          'If this legitimately changes, recompute on Windows AND verify the '
          'same value on Android before updating this pin -- a mismatch here '
          'means the two platforms no longer share the identical reference '
          'signal definition.',
    );
  });

  test('V4: does not reference Sonicake or any golden model id', () {
    final fullSource = File('tool/nam_inference/wyrmtone_reference_signal_v4.dart').readAsStringSync();
    final code = fullSource.split('\n').where((l) => !l.trim().startsWith('///')).join('\n');
    for (final banned in ['Sonicake', 'nam_input_wav', 'wyrmtone-captures', '48000.wav']) {
      expect(code.contains(banned), isFalse, reason: 'must not reference "$banned"');
    }
    expect(code.contains('dart:io'), isFalse);
  });
}
