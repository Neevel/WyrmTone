import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/tone_match_cache.dart';
import 'support/recommendation_fakes.dart' show MemoryStringStore;
import 'package:wyrmtone/tonematch/tone_features.dart';
import 'package:wyrmtone/tonematch/tone_match_models.dart';

EvaluationSignalDescriptor desc({String id = 'wyrmtone-rhythm-v1', int sr = 44100, int ch = 2, int bits = 24, double dur = 28, String? sha}) =>
    EvaluationSignalDescriptor(
      id: id,
      version: 1,
      role: EvaluationRole.rhythm,
      file: 'x.wav',
      sampleRate: sr,
      channels: ch,
      bitDepth: bits,
      durationSeconds: dur,
      sha256: sha ?? 'a' * 64,
    );

void main() {
  test('descriptor accepts only the specified format and round-trips JSON', () {
    expect(desc().validate(), isEmpty);
    expect(EvaluationSignalDescriptor.fromJson(desc().toJson()).validate(), isEmpty);
    expect(desc(sr: 48000).validate(), isNotEmpty);
    expect(desc(ch: 1).validate(), isNotEmpty);
    expect(desc(bits: 16).validate(), isNotEmpty);
    expect(desc(dur: 45).validate(), isNotEmpty);
    expect(desc(sha: 'ABC').validate(), isNotEmpty);
    expect(desc(id: 'wyrmtone-lead-v1').validate(), isNotEmpty);
  });

  test('the three bundled descriptors are valid, hash-identified originals', () {
    expect(EvaluationSignalRegistry.bundled.map((d) => d.id), ['wyrmtone-rhythm-v1', 'wyrmtone-lead-v1', 'wyrmtone-clean-v1']);
    for (final d in EvaluationSignalRegistry.bundled) {
      expect(d.validate(), isEmpty, reason: d.id);
      expect(EvaluationSignalRegistry.forRole(d.role), d);
    }
    final v2 = EvaluationSignalDescriptor.fromJson({...desc().toJson(), 'id': 'wyrmtone-rhythm-v2', 'version': 2});
    expect(EvaluationSignalRegistry.forRole(EvaluationRole.rhythm, [desc(), v2])!.version, 2);
  });

  test('cache key changes with every component and ignores the file name', () {
    const base = NamAnalysisKey(namSha256: 'n', signalSha256: 's', signalId: 'wyrmtone-rhythm-v1', analysisVersion: 1);
    expect(base, const NamAnalysisKey(namSha256: 'n', signalSha256: 's', signalId: 'wyrmtone-rhythm-v1', analysisVersion: 1));
    for (final other in [
      const NamAnalysisKey(namSha256: 'n2', signalSha256: 's', signalId: 'wyrmtone-rhythm-v1', analysisVersion: 1),
      const NamAnalysisKey(namSha256: 'n', signalSha256: 's2', signalId: 'wyrmtone-rhythm-v1', analysisVersion: 1),
      const NamAnalysisKey(namSha256: 'n', signalSha256: 's', signalId: 'wyrmtone-rhythm-v2', analysisVersion: 1),
      const NamAnalysisKey(namSha256: 'n', signalSha256: 's', signalId: 'wyrmtone-rhythm-v1', analysisVersion: 2),
    ]) {
      expect(other, isNot(base));
    }
  });

  test('guitar bands are contiguous, ordered and below Nyquist; level features are never tone features', () {
    final bands = GuitarBand.values;
    for (var i = 1; i < bands.length; i++) {
      expect(bands[i].lowHz, bands[i - 1].highHz);
    }
    expect(bands.first.lowHz, lessThan(82)); // low E
    expect(bands.last.highHz, lessThan(evaluationSampleRate / 2));
    expect(evaluationOriginalSampleRate, 44100);
    expect(ToneFeatureIds.classOf(ToneFeatureIds.rmsDb), FeatureClass.level);
    expect(ToneFeatureIds.classOf(ToneFeatureIds.gainDbVsInput), FeatureClass.level);
    expect(ToneFeatureIds.classOf(ToneFeatureIds.crestDb), FeatureClass.tone);
    expect(ToneFeatureIds.classOf(ToneFeatureIds.band(GuitarBand.mid)), FeatureClass.tone);
  });

  test('saturation composite needs all parts and is their plain mean', () {
    expect(SaturationDescriptor.composite({ToneFeatureIds.flatness1to8k: 1}), isNull);
    final all = {for (final c in SaturationDescriptor.components) c: 0.5};
    expect(SaturationDescriptor.composite(all), 0.5);
  });

  test('persistent cache round-trips an analysis and never returns a different key', () async {
    final cache = StringStoreToneMatchCache(MemoryStringStore());
    const key = NamAnalysisKey(namSha256: 'n', signalSha256: 's', signalId: 'wyrmtone-rhythm-v1', analysisVersion: 1);
    final a = NamAnalysis(
      key: key,
      features: const AudioFeatureVector(analysisVersion: 1, level: {'level.rmsDb': -20.5}, tone: {'tone.crestDb': 12.25}),
      timings: const AnalysisTimings(namLoadMs: 1, inferenceMs: 2, extractionMs: 3),
      analyzedAt: DateTime.utc(2026, 10, 2),
    );
    expect(await cache.read(key), isNull);
    await cache.write(a);
    final back = (await cache.read(key))!;
    expect(back.features.tone, a.features.tone);
    expect(back.timings.totalMs, 6);
    expect(await cache.read(const NamAnalysisKey(namSha256: 'n', signalSha256: 's', signalId: 'wyrmtone-rhythm-v1', analysisVersion: 2)), isNull);
  });
}
