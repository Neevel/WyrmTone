/// Central definition of the Slice-2 feature set: frequency bands, feature ids and whether a
/// feature is a LEVEL feature (loudness dependent, stored, never scored) or a TONE feature
/// (computed on the level-normalised output, may be compared). Definitions only; the extractor
/// comes with the DI files.
library;

/// Bump when any feature, band edge or extraction parameter changes: part of the cache key.
const toneAnalysisVersion = 1;

/// RESEARCH ONLY. The multi-phase envelope prototype (4/8/16 raster phases) was REJECTED by the
/// final envelope gate (docs/TONE_MATCH.md section 9). There is no production AnalysisVersion 2;
/// this value only labels experiment runs (`StftFeatureExtractor(analysisVersion: 2)`) and the
/// persistent cache refuses it. V1 is the frozen envelope architecture.
const toneAnalysisVersionV2 = 2;

enum FeatureClass { level, tone }

/// Analysis parameters, fixed per [toneAnalysisVersion].
abstract final class ToneAnalysisParams {
  static const frameSize = 2048; // 42.7 ms at 48 kHz: resolves 82 Hz (low E) with ~23 Hz bins
  static const hopSize = 512;

  /// Envelope resolution for attack/decay: 256-sample window, 64-sample hop (1.33 ms).
  static const envWindow = 256;
  static const envHop = 64;
  static const window = 'hann';

  /// A frame is "active" when its RMS is within this many dB of the loudest frame of the DI input
  /// (not of the output), so a louder NAM does not change which frames count.
  /// 35 dB (not more): high-gain NAMs expand decay tails and noise by tens of dB, so a wider gate
  /// would let near-silent tails dominate the tone features.
  static const activeGateDbBelowInputPeak = 35.0;

  /// Tone features are computed after scaling the output so that its active-frame RMS equals this.
  static const toneReferenceRmsDbfs = -20.0;

  /// Output is processed in chunks of this many frames (cancel point between chunks).
  static const inferenceChunkFrames = 48000;
}

/// Guitar-specific bands (Hz). Lower edge 60 Hz: low E is 82 Hz and Drop A reaches 55 Hz.
/// Upper edge 8 kHz: above it a guitar signal carries mostly fizz/noise and many full-rig NAMs
/// roll off; energy above 8 kHz is not bucketed (rolloff/centroid still see it).
enum GuitarBand {
  low('LOW', 60, 250), // fundamentals, thump, palm-mute body
  lowMid('LOW_MID', 250, 600), // boxiness / warmth
  mid('MID', 600, 1500), // core of the guitar, "honk"
  highMid('HIGH_MID', 1500, 3500), // pick attack, presence, bite
  high('HIGH', 3500, 8000); // fizz, air

  const GuitarBand(this.id, this.lowHz, this.highHz);
  final String id;
  final double lowHz, highHz;
}

/// Feature ids. LEVEL features are stored but must never enter a similarity score.
abstract final class ToneFeatureIds {
  // LEVEL (raw output, absolute)
  static const rmsDb = 'level.rmsDb';
  static const peakDb = 'level.peakDb';
  static const gainDbVsInput = 'level.gainDbVsInput';

  // TONE (level-normalised)
  /// Crest factor is scale-invariant (peak/RMS ratio), so it is a TONE feature; it is needed for
  /// the saturation components. Absolute RMS/peak stay LEVEL.
  static const crestDb = 'tone.crestDb';
  static const centroidHz = 'tone.centroidHz';
  static const rolloff85Hz = 'tone.rolloff85Hz';
  static const bandwidthHz = 'tone.bandwidthHz';
  static String band(GuitarBand b) => 'tone.band.${b.id}'; // share of total banded energy, sums to 1

  // Dynamics / envelope (tone class, level-independent by construction)
  static const attackMs = 'tone.attackMs';
  static const decayDbPerSec = 'tone.decayDbPerSec';
  static const envelopeRangeDb = 'tone.envelopeRangeDb'; // p95-p10 of active short-time RMS
  static const transientPeakToBodyDb = 'tone.transientPeakToBodyDb'; // onset peak vs. body, median over onsets
  static const onsetCount = 'tone.onsetCount'; // how many onsets the attack/decay values rest on

  // Saturation components (see [SaturationDescriptor])
  static const flatness1to8k = 'tone.sat.flatness1to8k';
  static const hfGenerationDb = 'tone.sat.hfGenerationDb';
  static const crestReductionDb = 'tone.sat.crestReductionDb';
  static const envelopeCompressionDb = 'tone.sat.envelopeCompressionDb';
  static const saturationComposite = 'tone.sat.composite';

  static FeatureClass classOf(String id) => id.startsWith('level.') ? FeatureClass.level : FeatureClass.tone;
}

/// Saturation is NOT measured by one number. The composite is the plain mean of four components,
/// each mapped to 0..1 by a fixed documented range, and always shown together with its parts:
///  - flatness1to8k: spectral flatness of 1-8 kHz (noise-/harmonic-rich -> higher)
///  - hfGenerationDb: HIGH+HIGH_MID energy share of output vs. the DI input (new HF = harmonics)
///  - crestReductionDb: DI crest factor minus output crest factor
///  - envelopeCompressionDb: DI envelope range minus output envelope range (short-time RMS p95-p10)
/// No component is claimed to "be" gain. Ranges are calibrated with the three-NAM validation.
abstract final class SaturationDescriptor {
  /// Provisional normalisation ranges (component value -> 0..1), set a priori and not yet
  /// calibrated: flatness 0..0.3, hfGeneration 0..20 dB, crestReduction 0..15 dB, compression 0..15 dB.
  static const ranges = <String, (double, double)>{
    ToneFeatureIds.flatness1to8k: (0.0, 0.3),
    ToneFeatureIds.hfGenerationDb: (0.0, 20.0),
    ToneFeatureIds.crestReductionDb: (0.0, 15.0),
    ToneFeatureIds.envelopeCompressionDb: (0.0, 15.0),
  };

  static const components = [
    ToneFeatureIds.flatness1to8k,
    ToneFeatureIds.hfGenerationDb,
    ToneFeatureIds.crestReductionDb,
    ToneFeatureIds.envelopeCompressionDb,
  ];

  /// [normalised] maps component id -> 0..1; missing components make the composite null.
  static double normalise(String component, double value) {
    final (lo, hi) = ranges[component]!;
    return ((value - lo) / (hi - lo)).clamp(0.0, 1.0);
  }

  static double? composite(Map<String, double> normalised) {
    if (components.any((c) => !normalised.containsKey(c))) return null;
    return components.map((c) => normalised[c]!.clamp(0.0, 1.0)).reduce((a, b) => a + b) / components.length;
  }
}
