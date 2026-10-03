import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/nam_inference/wyrmtone_reference_signal_v2.dart';

/// V4f: Reference Signal V2 (only the 0-5s Stage-A ramp segment changed
/// from V1; same pattern of checks as V1's own test in
/// wyrmtone_reference_signal_test.dart).
void main() {
  test('V2: deterministic, exact length, finite', () {
    final a = WyrmToneReferenceSignalV2.generate();
    final b = WyrmToneReferenceSignalV2.generate();
    expect(a.length, WyrmToneReferenceSignalV2.totalFrames);
    expect(a, orderedEquals(b));
    for (final v in a) {
      expect(v.isFinite, isTrue);
    }
  });

  test('V2: silent 5-6s, unchanged from V1', () {
    final sig = WyrmToneReferenceSignalV2.generate();
    for (var i = 5 * 48000; i < 6 * 48000; i += 4800) {
      expect(sig[i], 0.0);
    }
  });

  test('V2: 0-5s ramp reaches full scale near the end (5-tone multisine)', () {
    final sig = WyrmToneReferenceSignalV2.generate();
    var m = 0.0;
    for (var i = 5 * 48000 - 500; i < 5 * 48000; i++) {
      m = sig[i].abs() > m ? sig[i].abs() : m;
    }
    expect(m, greaterThan(0.5));
  });

  test('V2: does not reference Sonicake or any golden model id', () {
    final fullSource = File(
      'tool/nam_inference/wyrmtone_reference_signal_v2.dart',
    ).readAsStringSync();
    final code = fullSource
        .split('\n')
        .where((line) => !line.trim().startsWith('///'))
        .join('\n');
    for (final banned in [
      'Sonicake',
      'nam_input_wav',
      'wyrmtone-captures',
      '48000.wav',
    ]) {
      expect(code.contains(banned), isFalse, reason: 'must not reference "$banned"');
    }
    expect(code.contains('dart:io'), isFalse);
  });
}
