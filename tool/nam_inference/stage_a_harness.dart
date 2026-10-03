/// V4f: an offline, reusable harness that isolates Stage A (the
/// non-linearity fit) from the rest of the identification pipeline.
///
/// Scope boundary: this file calls the UNCHANGED, frozen [stageA] from
/// `engine/stages.dart` and the UNCHANGED [NamInferenceEngine]. It does not
/// touch NeuralAmpModelerCore integration, the FFI layer, the frozen
/// converter, FIR stages B/C/L/F, transport, or the CloData encoder.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../matribox_nam_analysis/engine/stages.dart';
import 'nam_inference_engine.dart';

/// Read-only mirror of the block-max/threshold computation `stageA()` does
/// internally to find eP/eN, kept here ONLY so those two diagnostic values
/// can be reported without modifying the frozen `stageA()` signature (which
/// returns [ModelParams] only). Must stay behaviourally identical to the
/// corresponding lines in `engine/stages.dart::stageA` -- it does not feed
/// back into [ModelParams], which is always produced by the real, frozen
/// `stageA()`.
({int eP, int eN, int nb}) stageADiagnostics(
  Float32List x,
  Float32List y,
  int n5,
) {
  const bs = 4800; // engineRate * 0.1s, matches stages.dart
  final nb = n5 ~/ bs;
  final xm = Float32List(nb), pm = Float32List(nb), nm = Float32List(nb);
  for (var k = 0; k < nb; k++) {
    final a = k * bs, b = (k + 1) * bs;
    var mx = -double.infinity, mp = -double.infinity, mn = double.infinity;
    for (var i = a; i < b; i++) {
      mx = math.max(mx, x[i].abs());
      mp = math.max(mp, y[i]);
      mn = math.min(mn, y[i]);
    }
    xm[k] = mx;
    pm[k] = math.max(0.0, mp);
    nm[k] = math.min(0.0, mn);
  }
  var pmax = 0.0, nmax = 0.0;
  for (var k = 0; k < nb; k++) {
    pmax = math.max(pmax, pm[k]);
    nmax = math.max(nmax, -nm[k]);
  }
  final thrP = pmax * 0.5, thrN = nmax * -0.5;
  var eP = 0, eN = 0;
  for (var k = 0; k < nb; k++) {
    if (pm[k] >= thrP) {
      eP = k + 1;
      break;
    }
  }
  for (var k = 0; k < nb; k++) {
    if (thrN >= nm[k]) {
      eN = k + 1;
      break;
    }
  }
  return (eP: eP, eN: eN, nb: nb);
}

class StageAExperimentResult {
  StageAExperimentResult({
    required this.familyName,
    required this.paramsDescription,
    required this.n5,
    required this.params,
    required this.eP,
    required this.eN,
    required this.nb,
    required this.inferenceMs,
    required this.stageAMs,
  });

  final String familyName;
  final String paramsDescription;
  final int n5;
  final ModelParams params;
  final int eP;
  final int eN;
  final int nb;
  final double inferenceMs;
  final double stageAMs;
}

/// Runs one Stage-A experiment: [excitation] (length >= [n5]) through the
/// already-loaded [engine], then through the frozen [stageA] over the first
/// [n5] samples. [engine] is reused across calls by the caller (loading a
/// NAM model is far more expensive than one inference + stageA call).
StageAExperimentResult runStageAExperiment({
  required NamInferenceEngine engine,
  required Float32List excitation,
  required int n5,
  required String familyName,
  required String paramsDescription,
}) {
  final swInfer = Stopwatch()..start();
  final y = engine.process(excitation);
  swInfer.stop();

  final swStageA = Stopwatch()..start();
  final params = stageA(excitation, y, n5);
  swStageA.stop();

  final diag = stageADiagnostics(excitation, y, n5);

  return StageAExperimentResult(
    familyName: familyName,
    paramsDescription: paramsDescription,
    n5: n5,
    params: params,
    eP: diag.eP,
    eN: diag.eN,
    nb: diag.nb,
    inferenceMs: swInfer.elapsedMicroseconds / 1000.0,
    stageAMs: swStageA.elapsedMicroseconds / 1000.0,
  );
}
