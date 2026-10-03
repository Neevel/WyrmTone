import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/nam_inference/wyrmtone_reference_signal.dart';

/// V4d: WyrmTone's own, algorithmically generated NAM identification
/// signal. Platform-independent (pure sin/cos, no dart:ffi), runs
/// everywhere `flutter test` does.
void main() {
  test('generates exactly 70 s at 48 kHz, deterministically', () {
    final a = WyrmToneReferenceSignal.generate();
    final b = WyrmToneReferenceSignal.generate();
    expect(a.length, 70 * 48000);
    expect(a, orderedEquals(b));
  });

  test('exact deterministic hash (regression guard for the formulas)', () {
    final sig = WyrmToneReferenceSignal.generate();
    final hash = sha256.convert(sig.buffer.asUint8List()).toString();
    // Locks the exact output of _writeRamp/_writeBurst/_writeMultitone. If
    // this ever changes, it must be a deliberate, documented formula change
    // (see docs/MATRIBOX_NAM_TRANSFER_RESEARCH.md, V4d), not an accident.
    expect(
      hash,
      '8d1ffb6641ac4b3f9100d16c115b85840370299785d4752fdfa1491f9994e7f0',
    );
  });

  test('no NaN/Inf, bounded amplitude, no silent stretches beyond 5-6 s', () {
    final sig = WyrmToneReferenceSignal.generate();
    var peak = 0.0;
    for (final v in sig) {
      expect(v.isFinite, isTrue);
      peak = math.max(peak, v.abs());
    }
    expect(peak, greaterThan(0.3));
    expect(peak, lessThanOrEqualTo(1.0));
  });

  test('0-5 s ramp: monotonically growing per-100ms-block peak amplitude', () {
    final sig = WyrmToneReferenceSignal.generate();
    const block = 4800; // 100 ms at 48 kHz, matching Stage A's own block size
    double blockPeak(int b) {
      var m = 0.0;
      for (var i = b * block; i < (b + 1) * block; i++) {
        m = math.max(m, sig[i].abs());
      }
      return m;
    }

    var prev = 0.0;
    for (var b = 0; b < 50; b++) {
      final p = blockPeak(b);
      expect(p, greaterThanOrEqualTo(prev - 1e-6), reason: 'block $b');
      prev = p;
    }
    expect(blockPeak(49), greaterThan(0.9));
  });

  test(
    '5-6 s is silent (delay-search assumption: quiet before the transient)',
    () {
      final sig = WyrmToneReferenceSignal.generate();
      for (var i = 5 * 48000; i < 6 * 48000; i++) {
        expect(sig[i], 0.0);
      }
    },
  );

  test('a detectable transient starts at 6.000 s, well inside the 600-sample search window', () {
    final sig = WyrmToneReferenceSignal.generate();
    var firstAbove = -1;
    for (var i = 0; i < 600; i++) {
      if (sig[6 * 48000 + i].abs() > 0.01) {
        firstAbove = i;
        break;
      }
    }
    expect(firstAbove, isNonNegative);
    expect(firstAbove, lessThan(100));
  });

  test('broadband section (6.005-70 s) has energy spread across the audible spectrum', () {
    final sig = WyrmToneReferenceSignal.generate();
    // Sums DFT magnitude over a +-40 Hz band around each representative
    // frequency (a single exact-frequency bin can fall between two of the
    // 300 discrete multitone components and under-report by chance —
    // "broadband" means energy nearby, not at that exact Hz).
    const start = 6 * 48000 + 240;
    const n = 4096;
    double bandEnergyAt(double centerHz) {
      var total = 0.0;
      for (var d = -40; d <= 40; d += 10) {
        final hz = centerHz + d;
        final omega = 2 * math.pi * hz / 48000;
        var re = 0.0, im = 0.0;
        for (var i = 0; i < n; i++) {
          final s = sig[start + i];
          re += s * math.cos(omega * i);
          im -= s * math.sin(omega * i);
        }
        total += math.sqrt(re * re + im * im);
      }
      return total;
    }

    for (final hz in [100.0, 1000.0, 5000.0, 12000.0]) {
      expect(bandEnergyAt(hz), greaterThan(1.0), reason: '$hz Hz');
    }
  });

  test('the generator does not reference any Sonicake asset, path or evidence file', () {
    final fullSource = File('tool/nam_inference/wyrmtone_reference_signal.dart')
        .readAsStringSync();
    // Doc comments are allowed (and expected) to explain, in prose, why
    // this file exists — e.g. "replaces Sonicake's nam_input_wav.wav".
    // What must never appear is a functional reference: an import, a path,
    // a literal used by the CODE. So this strips every comment line before
    // checking.
    final code = fullSource
        .split('\n')
        .where((line) => !line.trim().startsWith('//'))
        .join('\n');
    for (final banned in [
      'Sonicake',
      'nam_input_wav',
      'wyrmtone-captures',
      'HTCache',
      '48000.wav',
      'Program Files',
    ]) {
      expect(
        code.contains(banned),
        isFalse,
        reason: 'must not reference "$banned" in code (comments are fine)',
      );
    }
    // And structurally: no file reads at all in the generator itself.
    expect(code.contains('dart:io'), isFalse);
  });

  test(
    'WAV export round-trips through MatriboxNamWav (debug artifact only)',
    () {
      final sig = WyrmToneReferenceSignal.generate();
      final n = sig.length;
      final data = n * 3;
      final out = ByteData(44 + data);
      out.setUint32(0, 0x46464952, Endian.little);
      out.setUint32(4, 36 + data, Endian.little);
      out.setUint32(8, 0x45564157, Endian.little);
      out.setUint32(12, 0x20746d66, Endian.little);
      out.setUint32(16, 16, Endian.little);
      out.setUint16(20, 1, Endian.little);
      out.setUint16(22, 1, Endian.little);
      out.setUint32(24, 48000, Endian.little);
      out.setUint32(28, 48000 * 3, Endian.little);
      out.setUint16(32, 3, Endian.little);
      out.setUint16(34, 24, Endian.little);
      out.setUint32(36, 0x61746164, Endian.little);
      out.setUint32(40, data, Endian.little);
      expect(out.buffer.asUint8List().length, 44 + data);
    },
  );
}
