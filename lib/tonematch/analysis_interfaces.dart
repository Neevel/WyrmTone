import 'dart:typed_data';

import 'evaluation_signal.dart';
import 'tone_match_models.dart';

/// The evaluation signal ready for the NAM engine: LEFT/DRY only, mono Float32, 48 kHz, produced
/// by the single resampling step. Timings are measured once per signal.
class PreparedEvaluationSignal {
  const PreparedEvaluationSignal({required this.descriptor, required this.samples, required this.decodeMs, required this.resampleMs});
  final EvaluationSignalDescriptor descriptor;
  final Float32List samples;
  final int decodeMs, resampleMs;
}

/// Loads and verifies an evaluation signal: the SHA-256 of the ORIGINAL WAV must equal the
/// descriptor's, the format must match, then LEFT/DRY extraction -> 24-bit decode -> resample.
abstract interface class EvaluationSignalLoader {
  Future<PreparedEvaluationSignal> prepare(EvaluationSignalDescriptor descriptor);
}

/// Pure DSP: DI input + NAM output -> features. No I/O, no inference, deterministic.
abstract interface class AudioFeatureExtractor {
  /// Part of every cache key: a different version never reuses another version's features.
  int get analysisVersion;

  AudioFeatureVector extract({required Float32List input, required Float32List output});
}

/// Identity of a NAM for analysis: where to load it and its content hash (never the file name).
class NamAnalysisSource {
  const NamAnalysisSource({required this.path, required this.sha256});
  final String path, sha256;
}

class AnalysisCancelled implements Exception {
  const AnalysisCancelled();
  @override
  String toString() => 'AnalysisCancelled';
}

/// Runs one NAM over the evaluation signal with the EXISTING NamInferenceEngine (chunked, cancel
/// check between chunks; a result finished after cancel is discarded) and extracts features.
abstract interface class NamAnalyzer {
  int get analysisVersion;

  /// Throws [AnalysisCancelled] if [isCancelled] turned true between chunks.
  Future<NamAnalysis> analyze(NamAnalysisSource nam, PreparedEvaluationSignal signal, {bool Function()? isCancelled});
}

abstract interface class ToneMatchCache {
  Future<NamAnalysis?> read(NamAnalysisKey key);
  Future<void> write(NamAnalysis analysis);
}
