/// V4g: semantic distance between two FIR responses (never raw coefficient
/// equality). Magnitude response at a dense, explicit frequency set,
/// impulse-response correlation/NRMSE. Read-only / analysis-only.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// The frequency set the V4g spec requires (20 Hz .. 20 kHz).
const List<double> firDistanceFreqsHz = [
  20, 40, 80, 100, 200, 400, 800, 1000, 2000, 4000, 6000, 8000, 10000, 12000, 16000, 20000,
];

double _dftMagPhase(Float32List taps, double hz, int sr) {
  final omega = 2 * math.pi * hz / sr;
  var re = 0.0, im = 0.0;
  for (var i = 0; i < taps.length; i++) {
    re += taps[i] * math.cos(omega * i);
    im -= taps[i] * math.sin(omega * i);
  }
  return math.sqrt(re * re + im * im);
}

double _dftPhase(Float32List taps, double hz, int sr) {
  final omega = 2 * math.pi * hz / sr;
  var re = 0.0, im = 0.0;
  for (var i = 0; i < taps.length; i++) {
    re += taps[i] * math.cos(omega * i);
    im -= taps[i] * math.sin(omega * i);
  }
  return math.atan2(im, re);
}

double toDb(double mag) => 20 * math.log(math.max(mag, 1e-12)) / math.ln10;

class FirDistance {
  FirDistance({
    required this.magRmsDb,
    required this.magMeanAbsDb,
    required this.magMaxDb,
    required this.phaseMeanAbs,
    required this.impulseCorrelation,
    required this.impulseNrmse,
    required this.perFreqDeltaDb,
  });

  final double magRmsDb, magMeanAbsDb, magMaxDb;
  final double phaseMeanAbs;
  final double impulseCorrelation, impulseNrmse;
  final Map<double, double> perFreqDeltaDb;

  @override
  String toString() =>
      'magDb(rms/mean/max)=${magRmsDb.toStringAsFixed(2)}/${magMeanAbsDb.toStringAsFixed(2)}/'
      '${magMaxDb.toStringAsFixed(2)} phase=${phaseMeanAbs.toStringAsFixed(3)}rad '
      'impulse(corr/nrmse)=${impulseCorrelation.toStringAsFixed(3)}/${impulseNrmse.toStringAsFixed(3)}';
}

/// Compares [candidate] against [target] (a Pipeline-A research value,
/// never modified), both taps at [sampleRate] Hz.
FirDistance firDistance(Float32List target, Float32List candidate, {int sampleRate = 48000}) {
  var sumSq = 0.0, sumAbs = 0.0, maxAbs = 0.0;
  var sumPhase = 0.0;
  final perFreq = <double, double>{};
  for (final hz in firDistanceFreqsHz) {
    final mt = _dftMagPhase(target, hz, sampleRate);
    final mc = _dftMagPhase(candidate, hz, sampleRate);
    final d = toDb(mt) - toDb(mc);
    perFreq[hz] = d;
    sumSq += d * d;
    sumAbs += d.abs();
    if (d.abs() > maxAbs) maxAbs = d.abs();
    final pt = _dftPhase(target, hz, sampleRate);
    final pc = _dftPhase(candidate, hz, sampleRate);
    var dp = (pt - pc).abs();
    if (dp > math.pi) dp = 2 * math.pi - dp;
    sumPhase += dp;
  }
  final nF = firDistanceFreqsHz.length;

  final n = math.min(target.length, candidate.length);
  var dot = 0.0, tt = 0.0, cc = 0.0, errSq = 0.0;
  for (var i = 0; i < n; i++) {
    dot += target[i] * candidate[i];
    tt += target[i] * target[i];
    cc += candidate[i] * candidate[i];
    final e = target[i] - candidate[i];
    errSq += e * e;
  }
  final corr = dot / (math.sqrt(tt * cc) + 1e-30);
  final nrmse = math.sqrt(errSq / n) / (math.sqrt(tt / n) + 1e-30);

  return FirDistance(
    magRmsDb: math.sqrt(sumSq / nF),
    magMeanAbsDb: sumAbs / nF,
    magMaxDb: maxAbs,
    phaseMeanAbs: sumPhase / nF,
    impulseCorrelation: corr,
    impulseNrmse: nrmse,
    perFreqDeltaDb: perFreq,
  );
}
