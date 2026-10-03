import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/matribox_nam_analysis/engine/stages.dart';

/// V4h: unit tests for the analytical scale-propagation claim (derived
/// from `stageA()`'s own equations, empirically confirmed in
/// `native/nam_bridge/out/v4h_scale_experiment.dart` against real NAM
/// output): scaling a model's output y by a constant k scales P and N by
/// exactly k, while a+ and a- stay invariant. These are pure, deterministic
/// calls into the UNCHANGED, frozen `stageA()` -- no dart:ffi, no NAM
/// model, no capture data.
void main() {
  group('stageA scale propagation (P/N linear in k, a+/a- invariant)', () {
    // A small synthetic (x, y) pair: no NAM, no captured/Sonicake data --
    // just enough samples for stageA's 100ms-block analysis to run.
    (Float32List, Float32List) syntheticPair(int n5) {
      final x = Float32List(n5), y = Float32List(n5);
      for (var i = 0; i < n5; i++) {
        final t = i / 48000.0;
        final env = (i / n5).clamp(0.0, 1.0);
        x[i] = env * (0.7 * math.sin(2 * math.pi * 110 * t)).toDouble();
        // A deliberately nonlinear (saturating) synthetic "model": mimics
        // the P(1-e^-a x) shape stageA fits, so the fit is well-posed.
        final xv = x[i];
        y[i] = xv >= 0 ? 0.3 * (1 - math.exp(-4.0 * xv)) : 0.28 * (math.exp(4.5 * xv) - 1);
      }
      return (x, y);
    }

    test('P and N scale exactly linearly with k; a+/a- stay fixed', () {
      const n5 = 5 * 48000;
      final (x, y) = syntheticPair(n5);
      final base = stageA(x, y, n5);
      for (final k in [0.25, 0.5, 2.0, 4.0]) {
        final yScaled = Float32List(n5);
        for (var i = 0; i < n5; i++) {
          yScaled[i] = y[i] * k;
        }
        final scaled = stageA(x, yScaled, n5);
        expect(scaled.peakPos / base.peakPos, closeTo(k, k * 0.02));
        expect(scaled.peakNeg / base.peakNeg, closeTo(k, k * 0.02));
        expect(scaled.gainPos, closeTo(base.gainPos, base.gainPos * 0.05));
        expect(scaled.gainNeg, closeTo(base.gainNeg, base.gainNeg * 0.05));
      }
    });
  });

  test(
    'holdout isolation: the V4h checkpoint/scale/matrix scripts never '
    'iterate GOJIRA outside the dedicated holdout script',
    () {
      final trainModelsPattern = RegExp(r'const\s+trainModels\s*=\s*\[([^\]]*)\]');
      for (final path in [
        'native/nam_bridge/out/v4h_checkpoint_and_scaleflow.dart',
        'native/nam_bridge/out/v4h_fir1_matrix.dart',
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
