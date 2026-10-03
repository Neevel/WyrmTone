import 'dart:async';

import 'analysis_interfaces.dart';
import 'evaluation_signal.dart';
import 'tone_features.dart';
import 'tone_match_models.dart';

/// A NAM that may be measured: where its file is and its content hash (never the file name as key).
class AnalysisCandidate {
  const AnalysisCandidate({required this.id, required this.name, required this.path, required this.sha256});
  final String id, name, path, sha256;
}

/// The fixed test recording used for a role and its cache identity. The cache key uses the SHA-256 of
/// the ORIGINAL recording plus this id, so a lookup never needs the audio.
class CanonicalSignal {
  const CanonicalSignal(this.descriptor, this.keyId, {required this.derivesT15});
  final EvaluationSignalDescriptor descriptor;

  /// `wyrmtone-rhythm-v1#T15`, `wyrmtone-lead-v1#T15` or `wyrmtone-clean-v1` (the clean recording is already about 15 s).
  final String keyId;
  final bool derivesT15;

  static CanonicalSignal forRole(EvaluationRole role) {
    final d = EvaluationSignalRegistry.forRole(role)!;
    final t15 = role != EvaluationRole.clean;
    return CanonicalSignal(d, t15 ? '${d.id}#T15' : d.id, derivesT15: t15);
  }

  NamAnalysisKey keyFor(String namSha256) =>
      NamAnalysisKey(namSha256: namSha256, signalSha256: descriptor.sha256, signalId: keyId, analysisVersion: toneAnalysisVersion);
}

sealed class AnalysisEvent {
  const AnalysisEvent();
}

class CandidateStarted extends AnalysisEvent {
  const CandidateStarted(this.id);
  final String id;
}

class CandidateAnalyzed extends AnalysisEvent {
  const CandidateAnalyzed(this.id, this.analysis);
  final String id;
  final NamAnalysis analysis;
}

class CandidateFailed extends AnalysisEvent {
  const CandidateFailed(this.id, this.message);
  final String id, message;
}

/// The run stopped because of [ToneAnalysisRunner.cancel]; nothing further was started.
class AnalysisStopped extends AnalysisEvent {
  const AnalysisStopped();
}

/// Measures NAMs one after the other (never in parallel) and reports each one. Implementations must
/// not start another candidate after [cancel] and must release every engine they created.
abstract interface class ToneAnalysisRunner {
  /// Whether the fixed test recording for [role] is present on this device.
  Future<bool> isAvailableFor(EvaluationRole role);

  /// Measures exactly [candidates] (the ones not found in the cache) in order. The stream ends after
  /// the last candidate or after a cancellation.
  Stream<AnalysisEvent> run(EvaluationRole role, List<AnalysisCandidate> candidates);

  void cancel();
}

class AnalysisProgress {
  const AnalysisProgress({required this.done, required this.total, this.currentName});

  /// Sounds finished (from the cache or measured) out of [total].
  final int done, total;
  final String? currentName;
}

class AnalysisOutcome {
  const AnalysisOutcome({required this.analyses, required this.fromCache, required this.failed, required this.cancelled, required this.unavailable});
  final Map<String, NamAnalysis> analyses;
  final Set<String> fromCache;
  final List<String> failed;
  final bool cancelled, unavailable;
}

/// Cache-first orchestration: every sound whose key (NAM hash, recording hash, signal id, analysis
/// version) is in the cache is used immediately; only the rest is handed to the runner, and only a
/// COMPLETE result is written back.
class ToneAnalysisCoordinator {
  ToneAnalysisCoordinator({required this.runner, required this.cache});
  final ToneAnalysisRunner runner;
  final ToneMatchCache cache;
  bool _cancelRequested = false;

  void cancel() {
    _cancelRequested = true;
    runner.cancel();
  }

  Future<AnalysisOutcome> analyze(EvaluationRole role, List<AnalysisCandidate> candidates, {void Function(AnalysisProgress)? onProgress}) async {
    _cancelRequested = false;
    final signal = CanonicalSignal.forRole(role);
    final analyses = <String, NamAnalysis>{};
    final fromCache = <String>{};
    final misses = <AnalysisCandidate>[];
    final failed = <String>[];
    var done = 0;
    void report(String? name) => onProgress?.call(AnalysisProgress(done: done, total: candidates.length, currentName: name));
    report(null);
    for (final c in candidates) {
      final hit = await cache.read(signal.keyFor(c.sha256));
      if (hit != null) {
        analyses[c.id] = hit;
        fromCache.add(c.id);
        done++;
        report(null);
      } else {
        misses.add(c);
      }
    }
    if (misses.isEmpty) {
      return AnalysisOutcome(analyses: analyses, fromCache: fromCache, failed: failed, cancelled: false, unavailable: false);
    }
    if (!await runner.isAvailableFor(role)) {
      return AnalysisOutcome(analyses: analyses, fromCache: fromCache, failed: [for (final m in misses) m.id], cancelled: false, unavailable: true);
    }
    final byId = {for (final m in misses) m.id: m};
    var cancelled = false;
    await for (final e in runner.run(role, misses)) {
      if (_cancelRequested) {
        cancelled = true; // anything arriving after the cancel request is dropped, nothing is cached
        break;
      }
      switch (e) {
        case CandidateStarted(:final id):
          report(byId[id]?.name);
        case CandidateAnalyzed(:final id, :final analysis):
          await cache.write(analysis);
          analyses[id] = analysis;
          done++;
          report(null);
        case CandidateFailed(:final id):
          failed.add(id);
          done++;
          report(null);
        case AnalysisStopped():
          cancelled = true;
      }
    }
    if (_cancelRequested) cancelled = true;
    return AnalysisOutcome(analyses: analyses, fromCache: fromCache, failed: failed, cancelled: cancelled, unavailable: false);
  }
}
