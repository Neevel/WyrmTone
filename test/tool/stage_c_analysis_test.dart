import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/matribox_nam_analysis/engine/stages.dart';

/// V4i: Stage-C equation/implementation equivalence + holdout isolation.
/// Pure calls into the UNCHANGED, frozen `stageC()` -- no NAM, no capture
/// data, no waveform reconstruction of any Sonicake signal.
void main() {
  group('stageC regularization floor (bMag-derived threshold on m3)', () {
    (Float32List, Float32List, ModelParams) synthPair(int n) {
      const p = ModelParams(0.3, 0.28, 4.0, 3.5);
      final x = Float32List(n), y = Float32List(n);
      for (var i = 0; i < n; i++) {
        final t = i / 48000.0;
        x[i] = (0.5 * math.sin(2 * math.pi * 300 * t)).toDouble();
        y[i] = (0.4 * math.sin(2 * math.pi * 300 * t)).toDouble();
      }
      return (x, y, p);
    }

    test('a near-silent bMag drives m3 toward a small, non-zero floor', () {
      final (x, y, p) = synthPair(240000);
      // bMag near-silent (matches the V4i finding: the official 6-21s
      // window is near-silent, RMS 0.0018 vs the 23-28s window's 0.40).
      final quietBMag = Float32List(1025)..fillRange(0, 1025, 1e-6);
      final res = stageC(x, y, p, quietBMag);
      expect(res.mag.length, 1025);
      expect(res.ratio.length, 1025);
      for (final v in res.mag) {
        expect(v.isFinite, isTrue);
        expect(v, greaterThanOrEqualTo(0.0));
      }
      // With bMag's peak near 1e-6, thr = 1e-6*0.001 = 1e-9 -- the floor is
      // tiny, so m3 (Stage C's own 23-28s magnitude estimate) should be
      // dominated by its OWN signal, not clamped up to bMag's scale.
      var anyAboveFloor = false;
      for (final v in res.mag) {
        if (v > 1e-6) anyAboveFloor = true;
      }
      expect(anyAboveFloor, isTrue);
    });

    test('stageC is deterministic for a fixed synthetic pair (same bMag)', () {
      final (x, y, p) = synthPair(240000);
      final bMag = Float32List(1025)..fillRange(0, 1025, 1.0);
      final a = stageC(x, y, p, bMag);
      final b = stageC(x, y, p, bMag);
      expect(a.mag, orderedEquals(b.mag));
      expect(a.ratio, orderedEquals(b.ratio));
      expect(a.freq, orderedEquals(b.freq));
    });
  });

  test(
    'holdout isolation: the V4i Stage-C scripts never iterate GOJIRA outside the dedicated holdout script',
    () {
      final trainModelsPattern = RegExp(r'const\s+trainModels\s*=\s*\[([^\]]*)\]');
      for (final path in [
        'native/nam_bridge/out/v4i_stagec_analysis.dart',
        'native/nam_bridge/out/v4i_stagec_candidate.dart',
      ]) {
        final f = File(path);
        if (!f.existsSync()) continue; // gitignored scratch scripts
        final code = f.readAsStringSync();
        final m = trainModelsPattern.firstMatch(code);
        expect(m, isNotNull, reason: '$path must declare trainModels');
        expect(
          m!.group(1)!.toLowerCase().contains('gojira'),
          isFalse,
          reason: '$path: trainModels must not include gojira',
        );
      }
    },
  );
}
