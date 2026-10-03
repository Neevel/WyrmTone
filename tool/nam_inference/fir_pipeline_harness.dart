/// V4g: an offline, read-only harness that isolates Stages B/C/L/F (the
/// FIR1/FIR2 estimation pipeline) for excitation-dependence experiments.
///
/// This is a faithful REPRODUCTION of `runEngine()`'s own orchestration
/// (`tool/matribox_nam_analysis/engine/stages.dart`, lines ~490-547) built
/// entirely out of that file's own PUBLIC functions (`stageA`, `stageC`,
/// `stageL`, `stageF`, `shapeChain`) plus the public `WelchEstimator` -- it
/// does not reimplement or alter any of their internals, only calls them in
/// the same order on the same windows and captures the intermediate values
/// `runEngine()` itself discards. Scope boundary: does not touch
/// NeuralAmpModelerCore, the FFI layer, Stage A's own implementation,
/// Reference Signal V1/V2, the frozen converter, the transport encoder, or
/// the CloData wire format.
library;

import 'dart:typed_data';

import '../matribox_nam_analysis/engine/dsp_helpers.dart';
import '../matribox_nam_analysis/engine/f32.dart';
import '../matribox_nam_analysis/engine/spectral.dart';
import '../matribox_nam_analysis/engine/stages.dart';
import '../matribox_nam_analysis/engine/ucrt_float.dart';

/// One Stage-L iteration's diagnostics, as logged by the frozen `stageL()`
/// (parsed from its `log` callback -- `stageL()` itself is never modified).
class StageLIterationLog {
  StageLIterationLog(this.windowSec, this.iteration, this.err, this.decision);
  final int windowSec;
  final int iteration;
  final double err;
  final String decision; // "improved" | "RESET" | "kept"
}

/// A read-only snapshot of `StageLState.fir1`/`fir2` right after one of the
/// three `stageL()` window calls finishes (V4h: "at which window does
/// FIR1/FIR2 diverge from Pipeline A" needs the trajectory, not just the
/// final value). Copies, not views -- safe to keep after the state moves on.
class LWindowSnapshot {
  LWindowSnapshot(this.windowSec, this.fir1, this.fir2);
  final int windowSec;
  final Float32List fir1;
  final Float32List fir2;
}

class BclfResult {
  BclfResult({
    required this.params,
    required this.delay,
    required this.bMagPeak,
    required this.bMagMeanNonZero,
    required this.stageC,
    required this.lIterations,
    required this.lSnapshots,
    required this.fir1,
    required this.fir2x4,
  });

  final ModelParams params;
  final int delay;

  /// Peak / mean of the "Stage B" threshold-reference magnitude array
  /// (6-21s window) -- diagnostic only, exactly what stageC() receives.
  final double bMagPeak;
  final double bMagMeanNonZero;

  final StageCResult stageC;
  final List<StageLIterationLog> lIterations;

  /// FIR1/FIR2 right after each of the three stageL() window calls, in
  /// call order (23s, 6s, 30s) -- see [stageLWindows].
  final List<LWindowSnapshot> lSnapshots;

  /// First response, 128 taps at 48 kHz (pre-Stage-F).
  final Float32List fir1;

  /// Second response, 2048 taps at 48 kHz, scaled by four (post-Stage-F,
  /// exactly as `EngineResult.fir2x4` is).
  final Float32List fir2x4;
}

const int _fs = engineRate; // 48000, re-exported by stages.dart

/// The exact window layout `runEngine()` hardcodes, reproduced verbatim
/// (seconds-offset, sample-count, iterations) for the three `stageL()`
/// calls, in the SAME order `runEngine()` calls them (23s window first,
/// then 6s, then 30s -- state accumulates across all three).
const List<(int, int, int)> stageLWindows = [
  (23, 240000, 3),
  (6, 720000, 2),
  (30, 960000, 5),
];

/// Runs Stages B/C/L/F on [x] (reference input) / [yRaw] (model output),
/// both >= [engineLength] samples (zero-padded, same requirement as
/// `runEngine()`). Returns every intermediate value `runEngine()` itself
/// discards. [x]/[yRaw] are read-only; nothing here mutates them.
BclfResult runBclf(Float32List x, Float32List yRaw, {void Function(String)? log}) {
  final y = detrend(yRaw);
  final d = findDelay(y);
  final p = stageA(
    Float32List.sublistView(x, 0, 5 * _fs),
    Float32List.sublistView(y, d, d + 5 * _fs),
    5 * _fs,
  );

  Float32List xs(int sec, int n) => Float32List.sublistView(x, sec * _fs, sec * _fs + n);
  Float32List ys(int sec, int n) => Float32List.sublistView(y, sec * _fs + d, sec * _fs + d + n);

  final bMag = WelchEstimator(6000, 2048)
      .magnitude(shapeChain(Float32List.fromList(xs(6, 15 * _fs)), p), 0, y, 6 * _fs + d, 15 * _fs)
      .$1;
  var bPeak = 0.0, bSum = 0.0;
  var bCount = 0;
  for (final v in bMag) {
    if (v.isNaN) continue;
    if (v > bPeak) bPeak = v;
    if (v > 0) {
      bSum += v;
      bCount++;
    }
  }

  final c = stageC(xs(23, 240000), ys(23, 240000), p, bMag);

  const nb = 1025;
  final b0 = Float32List(nb)..fillRange(0, nb, 1.0);
  final b1 = Float32List(nb)..fillRange(0, nb, 1.0);
  final c20 = f32(2.0 / _fs.toDouble());
  final esi = f32(f32(c20 * 80.0) * f32(nb.toDouble())).floor();
  final tail = linspace32(1.0, 0.5, nb - esi + 1);
  for (var i = 0; i < tail.length; i++) {
    b1[esi - 1 + i] = tail[i];
  }
  final q512 = _makeQ512();
  final st = StageLState(
    c.ratio,
    c.mag,
    c.freq,
    Float32List(128)..[0] = 1.0,
    Float32List(2048)..[0] = 1.0,
  );

  final iterationLogs = <StageLIterationLog>[];
  final snapshots = <LWindowSnapshot>[];
  final logPattern = RegExp(r'L it=(\d+) err=([\d.eE+-]+) (improved|RESET|kept)');
  for (final (sec, n, it) in stageLWindows) {
    stageL(
      st,
      xs(sec, n),
      ys(sec, n),
      it,
      b0,
      b1,
      q512,
      p,
      c20,
      log: (s) {
        log?.call(s);
        final m = logPattern.firstMatch(s);
        if (m != null) {
          iterationLogs.add(
            StageLIterationLog(sec, int.parse(m.group(1)!), double.parse(m.group(2)!), m.group(3)!),
          );
        }
      },
    );
    snapshots.add(LWindowSnapshot(sec, Float32List.fromList(st.fir1), Float32List.fromList(st.fir2)));
  }

  final f2 = stageF(xs(50, 960000), ys(50, 960000), st.fir1, st.fir2, p);
  final f2x4 = Float32List(f2.length);
  for (var i = 0; i < f2.length; i++) {
    f2x4[i] = f2[i] * 4.0;
  }

  return BclfResult(
    params: p,
    delay: d,
    bMagPeak: bPeak,
    bMagMeanNonZero: bCount == 0 ? 0.0 : bSum / bCount,
    stageC: c,
    lIterations: iterationLogs,
    lSnapshots: snapshots,
    fir1: st.fir1,
    fir2x4: f2x4,
  );
}

/// Bit-exact copy of `stages.dart`'s private `_makeQ512()` (mel-like query
/// grid for Stage L's error metric): same float32-precision `f32()`/
/// `log10f()`/`powf()` calls, same `linspace32()`, duplicated here
/// read-only so `stageL()`/`_makeQ512()` need no export changes. Verified
/// bit-identical against `runEngine()`'s own FIR1/FIR2 output in
/// `native/nam_bridge/out/v4g_bclf_harness_check.dart`.
Float32List _makeQ512() {
  final m0 = f32(log10f(f32(1.1142857074737549)) * 2595.0);
  final m1 = f32(log10f(f32(15.285714149475098)) * 2595.0);
  final g = linspace32(m0, m1, 512);
  final q = Float32List(512);
  q[0] = 80.0;
  for (var i = 1; i < 511; i++) {
    q[i] = f32(f32(powf(10.0, f32(g[i] / 2595.0)) - 1.0) * 700.0);
  }
  q[511] = 10000.0;
  return q;
}
