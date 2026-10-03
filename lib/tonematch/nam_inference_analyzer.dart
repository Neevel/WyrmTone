import 'dart:typed_data';

import '../services/nam_inference_engine.dart';
import 'analysis_interfaces.dart';
import 'evaluation_signal.dart';
import 'stft_feature_extractor.dart';
import 'tone_features.dart';
import 'tone_match_models.dart';

/// Analyzer on the EXISTING [NamInferenceEngine] (no second NAM runtime). One engine per
/// analysis, always disposed. The signal is processed in chunks of [chunkFrames] (0 = one call);
/// cancellation is checked between chunks, never inside a native call.
class NamInferenceAnalyzer implements NamAnalyzer {
  NamInferenceAnalyzer({
    required this.createEngine,
    this.extractor = const StftFeatureExtractor(),
    this.chunkFrames = ToneAnalysisParams.inferenceChunkFrames,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final NamInferenceEngine Function() createEngine;
  final AudioFeatureExtractor extractor;
  final int chunkFrames;
  final DateTime Function() _clock;

  @override
  int get analysisVersion => extractor.analysisVersion;

  /// Runs the loaded model over [input] (exposed for the chunked-vs-whole golden test).
  Float32List runModel(NamInferenceEngine engine, Float32List input, {bool Function()? isCancelled}) {
    if (chunkFrames <= 0 || chunkFrames >= input.length) return engine.process(input);
    final out = Float32List(input.length);
    for (var start = 0; start < input.length; start += chunkFrames) {
      if (isCancelled?.call() ?? false) throw const AnalysisCancelled();
      final end = start + chunkFrames < input.length ? start + chunkFrames : input.length;
      out.setRange(start, end, engine.process(Float32List.sublistView(input, start, end)));
    }
    return out;
  }

  @override
  Future<NamAnalysis> analyze(NamAnalysisSource nam, PreparedEvaluationSignal signal, {bool Function()? isCancelled}) async {
    final engine = createEngine();
    try {
      final loadWatch = Stopwatch()..start();
      engine.load(nam.path, sampleRate: evaluationSampleRate.toDouble());
      final expected = engine.expectedSampleRate;
      loadWatch.stop();
      if (expected != 0 && expected != evaluationSampleRate) {
        throw EvaluationSignalException('NAM erwartet $expected Hz; Tone Match analysiert nur mit $evaluationSampleRate Hz.');
      }
      if (isCancelled?.call() ?? false) throw const AnalysisCancelled();
      final inferWatch = Stopwatch()..start();
      final output = runModel(engine, signal.samples, isCancelled: isCancelled);
      inferWatch.stop();
      if (isCancelled?.call() ?? false) throw const AnalysisCancelled(); // discard a finished result
      final extractWatch = Stopwatch()..start();
      final features = extractor.extract(input: signal.samples, output: output);
      extractWatch.stop();
      return NamAnalysis(
        key: NamAnalysisKey(
          namSha256: nam.sha256,
          signalSha256: signal.descriptor.sha256,
          signalId: signal.descriptor.id,
          analysisVersion: analysisVersion,
        ),
        features: features,
        timings: AnalysisTimings(
          namLoadMs: loadWatch.elapsedMilliseconds,
          inferenceMs: inferWatch.elapsedMilliseconds,
          extractionMs: extractWatch.elapsedMilliseconds,
        ),
        analyzedAt: _clock().toUtc(),
      );
    } finally {
      engine.dispose();
    }
  }
}
