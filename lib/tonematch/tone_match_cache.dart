import 'dart:convert';

import '../services/local_persistence.dart';
import 'analysis_interfaces.dart';
import 'tone_features.dart';
import 'tone_match_models.dart';

/// Memory cache (tests, one session).
class InMemoryToneMatchCache implements ToneMatchCache {
  final _byKey = <String, NamAnalysis>{};
  @override
  Future<NamAnalysis?> read(NamAnalysisKey key) async => _byKey[key.value];
  @override
  Future<void> write(NamAnalysis analysis) async => _byKey[analysis.key.value] = analysis;
}

/// Persistent cache on the app's [StringStore]. The key is content-derived (NAM SHA, original
/// evaluation WAV SHA, signal id/version, analysis version); a changed analysis version simply
/// never finds old entries, so nothing stale is reused.
class StringStoreToneMatchCache implements ToneMatchCache {
  StringStoreToneMatchCache(this.store);
  final StringStore store;

  /// Only production analysis versions are persisted. The rejected multi-phase research prototype
  /// (version 2) must never be stored or served as if it were a final analysis.
  static const supportedAnalysisVersions = {toneAnalysisVersion};
  static String _storeKey(NamAnalysisKey k) => 'tonematch.analysis.${k.value}';

  @override
  Future<NamAnalysis?> read(NamAnalysisKey key) async {
    if (!supportedAnalysisVersions.contains(key.analysisVersion)) return null;
    final raw = await store.read(_storeKey(key));
    if (raw == null) return null;
    try {
      final a = NamAnalysis.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
      return a.key == key ? a : null;
    } on Object {
      return null; // corrupt entry: recompute
    }
  }

  @override
  Future<void> write(NamAnalysis analysis) async {
    if (!supportedAnalysisVersions.contains(analysis.key.analysisVersion)) {
      throw StateError('analysis version ${analysis.key.analysisVersion} is not persisted (research/rejected version)');
    }
    await store.write(_storeKey(analysis.key), jsonEncode(analysis.toJson()));
  }
}

/// Read-through cache around any analyzer; the inner analyzer runs only on a miss.
class CachedNamAnalyzer implements NamAnalyzer {
  CachedNamAnalyzer(this.inner, this.cache, {required this.analysisVersion}) {
    if (analysisVersion != inner.analysisVersion) {
      throw ArgumentError('cache version $analysisVersion must equal the analyzer version ${inner.analysisVersion}');
    }
  }
  final NamAnalyzer inner;
  final ToneMatchCache cache;
  @override
  final int analysisVersion;
  int hits = 0, misses = 0;

  @override
  Future<NamAnalysis> analyze(NamAnalysisSource nam, PreparedEvaluationSignal signal, {bool Function()? isCancelled}) async {
    final key = NamAnalysisKey(
      namSha256: nam.sha256,
      signalSha256: signal.descriptor.sha256,
      signalId: signal.descriptor.id,
      analysisVersion: analysisVersion,
    );
    final hit = await cache.read(key);
    if (hit != null) {
      hits++;
      return hit;
    }
    misses++;
    final result = await inner.analyze(nam, signal, isCancelled: isCancelled);
    await cache.write(result);
    return result;
  }
}
