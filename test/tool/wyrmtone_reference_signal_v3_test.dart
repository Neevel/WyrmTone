import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/nam_inference/wyrmtone_reference_signal_v3.dart';

/// V4g: Reference Signal V3 (only the 6.005-70s FIR-identification tail
/// changed from V2; Stage-A ramp, silence and burst unchanged).
void main() {
  test('V3: deterministic, exact length, finite', () {
    final a = WyrmToneReferenceSignalV3.generate();
    final b = WyrmToneReferenceSignalV3.generate();
    expect(a.length, WyrmToneReferenceSignalV3.totalFrames);
    expect(a, orderedEquals(b));
    for (final v in a) {
      expect(v.isFinite, isTrue);
      expect(v.abs(), lessThanOrEqualTo(1.0001));
    }
  });

  test('V3: silent 5-6s, unchanged from V1/V2', () {
    final sig = WyrmToneReferenceSignalV3.generate();
    for (var i = 5 * 48000; i < 6 * 48000; i += 4800) {
      expect(sig[i], 0.0);
    }
  });

  test('V3: tail repeats every tailSweepCyclePeriodS seconds', () {
    final sig = WyrmToneReferenceSignalV3.generate();
    const start = 6 * 48000 + 240;
    final periodN = (WyrmToneReferenceSignalV3.tailSweepCyclePeriodS * 48000).round();
    for (var i = 0; i < 500; i++) {
      expect(sig[start + i], closeTo(sig[start + i + periodN], 1e-5));
    }
  });

  test('V3: tail peak matches tailSweepPeak, not full scale', () {
    final sig = WyrmToneReferenceSignalV3.generate();
    var m = 0.0;
    for (var i = 6 * 48000 + 240; i < 7 * 48000; i++) {
      if (sig[i].abs() > m) m = sig[i].abs();
    }
    expect(m, closeTo(WyrmToneReferenceSignalV3.tailSweepPeak, 0.02));
  });

  test('V3: does not reference Sonicake or any golden model id', () {
    final fullSource = File('tool/nam_inference/wyrmtone_reference_signal_v3.dart').readAsStringSync();
    final code = fullSource.split('\n').where((l) => !l.trim().startsWith('///')).join('\n');
    for (final banned in ['Sonicake', 'nam_input_wav', 'wyrmtone-captures', '48000.wav']) {
      expect(code.contains(banned), isFalse, reason: 'must not reference "$banned"');
    }
    expect(code.contains('dart:io'), isFalse);
  });
}
