import 'dart:math' as math;
import 'dart:typed_data';

import 'analysis_interfaces.dart';
import 'dsp_fft.dart';
import 'envelope_features.dart';
import 'evaluation_signal.dart';
import 'tone_features.dart';
import 'tone_match_models.dart';

/// Slice-2 feature extractor (V1). Pure DSP, deterministic, no I/O.
///
/// Inputs are the DI evaluation signal (48 kHz mono) and the NAM's output for it (same length).
/// Which frames count ("active") is decided from the DI input only (frame RMS within
/// [ToneAnalysisParams.activeGateDbBelowInputPeak] of the loudest input frame), never from the output.
///
/// LEVEL features (absolute, stored, never scored): rmsDb, peakDb, gainDbVsInput.
/// TONE features are computed on the output scaled to an active-frame RMS of -20 dBFS, so a
/// louder NAM does not look brighter/denser/"more gain"; ratios (crest, shares, compression) are
/// scale-invariant anyway. Everything is reproducible from (input, output, [toneAnalysisVersion]).
///
/// [analysisVersion] 1 is the frozen V1 definition (default, the only production version). Version 2
/// is a REJECTED research prototype (docs/TONE_MATCH.md section 9) kept to reproduce the gates; it differs ONLY in how
/// `attackMs`, `decayDbPerSec` (and, if [multiphaseTransient], `transientPeakToBodyDb`) are
/// computed: the V1 envelope logic runs on four raster phases and the median is taken
/// ([EnvelopeFeatures.v2Phases]). Every other feature is computed by the same code in both versions.
class StftFeatureExtractor implements AudioFeatureExtractor {
  const StftFeatureExtractor({this.analysisVersion = 1, this.multiphaseTransient = true, this.envelopePhaseCount = 4})
    : assert(analysisVersion == 1 || analysisVersion == 2),
      assert(envelopePhaseCount == 4 || envelopePhaseCount == 8 || envelopePhaseCount == 16);

  /// V2 only: number of envelope raster phases (4, 8 or 16; see docs section 9). Ignored in V1.
  final int envelopePhaseCount;

  @override
  final int analysisVersion;

  /// V2 only: also aggregate `transientPeakToBodyDb` over the phases (default). The offset
  /// experiment (docs/TONE_MATCH.md section 8) showed this is not worse than V1; `false` keeps the
  /// V1 definition for that one feature. Ignored in V1.
  final bool multiphaseTransient;

  static const _eps = 1e-20;

  @override
  AudioFeatureVector extract({required Float32List input, required Float32List output}) {
    if (input.length != output.length) throw ArgumentError('input/output length differ');
    const frame = ToneAnalysisParams.frameSize, hop = ToneAnalysisParams.hopSize;
    final n = input.length;
    if (n < frame) throw ArgumentError('signal shorter than one analysis frame');
    final frames = (n - frame) ~/ hop + 1;
    const rate = evaluationSampleRate;

    // --- active frames, decided on the DI input
    final inMs = Float64List(frames), outMs = Float64List(frames);
    for (var f = 0; f < frames; f++) {
      var si = 0.0, so = 0.0;
      for (var i = f * hop; i < f * hop + frame; i++) {
        si += input[i] * input[i];
        so += output[i] * output[i];
      }
      inMs[f] = si / frame;
      outMs[f] = so / frame;
    }
    final maxIn = inMs.reduce(math.max);
    final gate = maxIn * math.pow(10, -ToneAnalysisParams.activeGateDbBelowInputPeak / 10);
    final active = [for (var f = 0; f < frames; f++) if (inMs[f] >= gate) f];
    if (active.isEmpty) throw StateError('no active frames in the DI input');

    // --- LEVEL
    double meanOf(Float64List v) => active.fold(0.0, (a, f) => a + v[f]) / active.length;
    final inRmsDb = _db10(meanOf(inMs)), outRmsDb = _db10(meanOf(outMs));
    final inPeak = _peak(input), outPeak = _peak(output);
    final level = <String, double>{
      ToneFeatureIds.rmsDb: outRmsDb,
      ToneFeatureIds.peakDb: _db20(outPeak),
      ToneFeatureIds.gainDbVsInput: outRmsDb - inRmsDb,
    };

    // --- normalisation of the output for TONE features
    final k = math.pow(10, (ToneAnalysisParams.toneReferenceRmsDbfs - outRmsDb) / 20).toDouble();

    // --- spectra over active frames
    final fft = Fft(frame);
    final re = Float64List(frame), im = Float64List(frame);
    final win = Float64List(frame);
    for (var i = 0; i < frame; i++) {
      win[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / frame);
    }
    const bins = frame ~/ 2 + 1;
    final ltasOut = Float64List(bins), ltasIn = Float64List(bins);
    final binHz = rate / frame;
    final flatLo = (1000 / binHz).ceil(), flatHi = (8000 / binHz).floor();
    var flatSum = 0.0;
    void spectrum(Float32List x, double gain, int f, Float64List acc, {bool flat = false}) {
      for (var i = 0; i < frame; i++) {
        re[i] = x[f * hop + i] * gain * win[i];
        im[i] = 0;
      }
      fft.transform(re, im);
      var logSum = 0.0, sum = 0.0;
      for (var b = 0; b < bins; b++) {
        final p = re[b] * re[b] + im[b] * im[b];
        acc[b] += p;
        if (flat && b >= flatLo && b <= flatHi) {
          logSum += math.log(p + _eps);
          sum += p + _eps;
        }
      }
      if (flat) {
        final cnt = flatHi - flatLo + 1;
        flatSum += math.exp(logSum / cnt) / (sum / cnt);
      }
    }

    for (final f in active) {
      spectrum(output, k, f, ltasOut, flat: true);
      spectrum(input, 1.0, f, ltasIn);
    }
    final tone = <String, double>{};

    // --- long-term-average-spectrum descriptors on 60 Hz .. 20 kHz
    final lo = (60 / binHz).ceil(), hi = (20000 / binHz).floor();
    var total = 0.0, weighted = 0.0;
    for (var b = lo; b <= hi; b++) {
      total += ltasOut[b];
      weighted += ltasOut[b] * b * binHz;
    }
    final centroid = weighted / total;
    var varSum = 0.0, cum = 0.0, rolloff = hi * binHz;
    var rolled = false;
    for (var b = lo; b <= hi; b++) {
      final d = b * binHz - centroid;
      varSum += ltasOut[b] * d * d;
      cum += ltasOut[b];
      if (!rolled && cum >= 0.85 * total) {
        rolloff = b * binHz;
        rolled = true;
      }
    }
    tone[ToneFeatureIds.centroidHz] = centroid;
    tone[ToneFeatureIds.bandwidthHz] = math.sqrt(varSum / total);
    tone[ToneFeatureIds.rolloff85Hz] = rolloff;

    List<double> shares(Float64List ltas) {
      final e = [
        for (final band in GuitarBand.values)
          () {
            var s = 0.0;
            for (var b = (band.lowHz / binHz).ceil(); b * binHz < band.highHz; b++) {
              s += ltas[b];
            }
            return s;
          }(),
      ];
      final t = e.fold(0.0, (a, b) => a + b);
      return [for (final v in e) v / t];
    }

    final outShares = shares(ltasOut), inShares = shares(ltasIn);
    for (var i = 0; i < GuitarBand.values.length; i++) {
      tone[ToneFeatureIds.band(GuitarBand.values[i])] = outShares[i];
    }

    // --- dynamics: crest, envelope range (active frames)
    final crestIn = _db20(inPeak) - inRmsDb, crestOut = _db20(outPeak) - outRmsDb;
    tone[ToneFeatureIds.crestDb] = crestOut;
    final inRange = _range([for (final f in active) _db10(inMs[f])]);
    final outRange = _range([for (final f in active) _db10(outMs[f])]);
    tone[ToneFeatureIds.envelopeRangeDb] = outRange;

    // --- attack / decay from onsets detected on the DI envelope
    final env = analysisVersion == 1
        ? EnvelopeFeatures.atPhase(input, output, k, 0)
        : EnvelopeFeatures.medianOf([for (final p in EnvelopeFeatures.phasesFor(envelopePhaseCount)) EnvelopeFeatures.atPhase(input, output, k, p)]);
    tone[ToneFeatureIds.onsetCount] = env.onsetCount;
    if (env.attackMs != null) {
      tone[ToneFeatureIds.attackMs] = env.attackMs!;
      tone[ToneFeatureIds.transientPeakToBodyDb] = analysisVersion == 2 && !multiphaseTransient
          ? EnvelopeFeatures.atPhase(input, output, k, 0).transientPeakToBodyDb ?? env.transientPeakToBodyDb!
          : env.transientPeakToBodyDb!;
      tone[ToneFeatureIds.decayDbPerSec] = env.decayDbPerSec!;
    }

    // --- saturation components (no single number is "gain")
    final hfOut = outShares[3] + outShares[4], hfIn = inShares[3] + inShares[4];
    tone[ToneFeatureIds.flatness1to8k] = flatSum / active.length;
    tone[ToneFeatureIds.hfGenerationDb] = _db10(hfOut / hfIn);
    tone[ToneFeatureIds.crestReductionDb] = crestIn - crestOut;
    tone[ToneFeatureIds.envelopeCompressionDb] = inRange - outRange;
    final composite = SaturationDescriptor.composite({
      for (final c in SaturationDescriptor.components) c: SaturationDescriptor.normalise(c, tone[c]!),
    });
    tone[ToneFeatureIds.saturationComposite] = composite!;

    return AudioFeatureVector(analysisVersion: analysisVersion, level: level, tone: tone);
  }

  static double _peak(Float32List x) {
    var p = 0.0;
    for (final v in x) {
      final a = v.abs();
      if (a > p) p = a;
    }
    return p;
  }

  static double _db10(double v) => 10 * math.log(v + 1e-30) / math.ln10;
  static double _db20(double v) => 20 * math.log(v + 1e-15) / math.ln10;

  static double _percentile(List<double> sorted, double p) {
    final pos = p * (sorted.length - 1);
    final lo = pos.floor(), hi = pos.ceil();
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
  }

  static double _range(List<double> v) {
    final s = [...v]..sort();
    return _percentile(s, 0.95) - _percentile(s, 0.10);
  }

}
