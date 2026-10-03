import 'dart:typed_data';

import '../matribox_nam_analysis/engine/fdl_convolver.dart';
import '../matribox_nam_analysis/engine/filters.dart';
import '../matribox_nam_analysis/engine/stages.dart' show ModelParams;

/// V4e: offline evaluator for the amplifier a [ModelParams] + FIR1 + FIR2
/// triple (as returned by the frozen `runEngine`, `engine/stages.dart`)
/// represents — used only to compare Pipeline A vs Pipeline B's extracted
/// parameters against a shared probe signal. Nothing here sends anything
/// anywhere; it is pure offline signal math.
///
/// The confirmed high-pass biquad coefficients below are copied from V1–V3
/// evidence (the same constant `engine/stages.dart`'s private `_hp` uses),
/// not re-derived — duplicated into this new, separate file instead of
/// exporting it from the frozen engine, so nothing there is touched.
const List<double> confirmedHpBiquad = [
  0.9963043928146362,
  -1.9926087856292725,
  0.9963043928146362,
  -1.9925950765609741,
  0.9926224946975708,
];

/// Runs [input] through the chain the extracted parameters represent:
/// unity biquad -> FIR1 -> waveshaper(P,N,a+,a-) -> HP biquad -> FIR2 — the
/// exact same building blocks (`Biquad`, `Waveshaper`, `firFilter`) the
/// frozen engine's own Stage L/F signal path uses. Operates in the
/// engine's native 48 kHz domain, using [fir1]/[fir2] BEFORE the lossy
/// 48->44.1 kHz resample/truncation that CloData itself stores (see
/// docs/MATRIBOX_NAM_TRANSFER_RESEARCH.md V4e for why that scope was
/// chosen).
Float32List evaluateAmp(
  ModelParams params,
  Float32List fir1,
  Float32List fir2,
  Float32List input,
) {
  final bq1 = Biquad(1.0, 0.0, 0.0, 0.0, 0.0);
  var sig = Float32List(input.length);
  for (var i = 0; i < input.length; i++) {
    sig[i] = bq1.process(input[i]);
  }
  sig = firFilter(fir1, sig);
  final ws = Waveshaper(
    params.peakPos,
    params.peakNeg,
    params.gainPos,
    params.gainNeg,
  );
  final bq2 = Biquad(
    confirmedHpBiquad[0],
    confirmedHpBiquad[1],
    confirmedHpBiquad[2],
    confirmedHpBiquad[3],
    confirmedHpBiquad[4],
  );
  for (var i = 0; i < sig.length; i++) {
    sig[i] = bq2.process(ws.process(sig[i]));
  }
  return firFilter(fir2, sig);
}

/// Evaluates only the nonlinear waveshaper (no FIRs) at a set of input
/// levels — for comparing the represented transfer curve directly.
double evaluateWaveshaperAt(ModelParams p, double x) {
  final ws = Waveshaper(p.peakPos, p.peakNeg, p.gainPos, p.gainNeg);
  // A fresh Waveshaper has empty oversampling-filter state; run a short
  // silence lead-in so the polyphase allpass state settles before reading
  // the sample of interest (the filters are IIR allpasses; a handful of
  // samples is sufficient for their coefficients).
  for (var i = 0; i < 32; i++) {
    ws.process(0.0);
  }
  double y = 0;
  for (var i = 0; i < 8; i++) {
    y = ws.process(x);
  }
  return y;
}
