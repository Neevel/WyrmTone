/// V4f: distance metric between a candidate Stage-A fit and a Pipeline-A
/// research target, both [ModelParams]. Read-only / analysis-only -- not
/// used by the frozen converter.
library;

import 'dart:math' as math;

import '../matribox_nam_analysis/engine/stages.dart';

/// The exact transfer-curve formula `stageA()` fits against (see
/// `engine/stages.dart::stageA`'s inner `err()`), evaluated directly rather
/// than through the oversampled [Waveshaper] -- this is what Stage A's
/// least-squares fit actually optimizes, so it is the right space to
/// compare two fitted [ModelParams] in.
double stageACurveValue(ModelParams p, double x) {
  if (x > 0) {
    return p.peakPos * (1 - math.exp(-x * p.gainPos));
  }
  return p.peakNeg * (math.exp(x * p.gainNeg) - 1);
}

class StageADistance {
  StageADistance({
    required this.pErr,
    required this.nErr,
    required this.apErr,
    required this.anErr,
    required this.curveErrMean,
    required this.curveErrPos,
    required this.curveErrNeg,
    required this.score,
  });

  final double pErr, nErr, apErr, anErr;
  final double curveErrMean, curveErrPos, curveErrNeg;

  /// Aggregate score used to rank excitation candidates: dominated by the
  /// dense transfer-curve error (the primary semantic metric per the V4f
  /// spec), with the four individual parameter errors as a secondary,
  /// smaller contribution.
  final double score;

  @override
  String toString() =>
      'P=${pErr.toStringAsFixed(4)} N=${nErr.toStringAsFixed(4)} '
      'a+=${apErr.toStringAsFixed(4)} a-=${anErr.toStringAsFixed(4)} '
      'curve(mean/+/-)=${curveErrMean.toStringAsFixed(4)}/'
      '${curveErrPos.toStringAsFixed(4)}/${curveErrNeg.toStringAsFixed(4)} '
      'score=${score.toStringAsFixed(4)}';
}

double _relErr(double target, double cand) {
  final denom = target.abs() < 1e-9 ? 1e-9 : target.abs();
  return (cand - target).abs() / denom;
}

/// Compares [candidate] against [target] (a Pipeline-A research value,
/// never modified). [gridPoints] samples x uniformly over [-1, 1].
StageADistance stageADistance(
  ModelParams target,
  ModelParams candidate, {
  int gridPoints = 401,
}) {
  final pErr = _relErr(target.peakPos, candidate.peakPos);
  final nErr = _relErr(target.peakNeg, candidate.peakNeg);
  final apErr = _relErr(target.gainPos, candidate.gainPos);
  final anErr = _relErr(target.gainNeg, candidate.gainNeg);

  var sumPos = 0.0, sumNeg = 0.0;
  var nPos = 0, nNeg = 0;
  for (var i = 0; i < gridPoints; i++) {
    final x = -1.0 + 2.0 * i / (gridPoints - 1);
    final tv = stageACurveValue(target, x);
    final cv = stageACurveValue(candidate, x);
    final d = (tv - cv).abs();
    if (x >= 0) {
      sumPos += d;
      nPos++;
    } else {
      sumNeg += d;
      nNeg++;
    }
  }
  final curveErrPos = nPos == 0 ? 0.0 : sumPos / nPos;
  final curveErrNeg = nNeg == 0 ? 0.0 : sumNeg / nNeg;
  final curveErrMean = (sumPos + sumNeg) / gridPoints;

  final score =
      curveErrMean * 10.0 + (pErr + nErr + apErr + anErr) * 0.25;

  return StageADistance(
    pErr: pErr,
    nErr: nErr,
    apErr: apErr,
    anErr: anErr,
    curveErrMean: curveErrMean,
    curveErrPos: curveErrPos,
    curveErrNeg: curveErrNeg,
    score: score,
  );
}
