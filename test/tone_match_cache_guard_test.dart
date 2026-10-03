import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/tonematch/tone_match_cache.dart';
import 'package:wyrmtone/tonematch/tone_match_models.dart';

import 'support/recommendation_fakes.dart' show MemoryStringStore;

NamAnalysis analysis(int version) => NamAnalysis(
  key: NamAnalysisKey(namSha256: 'n', signalSha256: 's', signalId: 'wyrmtone-rhythm-v1', analysisVersion: version),
  features: AudioFeatureVector(analysisVersion: version, level: const {}, tone: const {'tone.attackMs': 1.0}),
  timings: const AnalysisTimings(namLoadMs: 0, inferenceMs: 0, extractionMs: 0),
  analyzedAt: DateTime.utc(2026),
);

void main() {
  test('the persistent cache stores production version 1 only and never serves or stores the rejected version 2', () async {
    final store = MemoryStringStore();
    final cache = StringStoreToneMatchCache(store);
    await cache.write(analysis(1));
    expect(await cache.read(analysis(1).key), isNotNull);
    await expectLater(cache.write(analysis(2)), throwsStateError);
    expect(await cache.read(analysis(2).key), isNull);
    // even a stray entry under the version-2 key is not served
    await store.write('tonematch.analysis.${analysis(2).key.value}', '{}');
    expect(await cache.read(analysis(2).key), isNull);
  });
}
