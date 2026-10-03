import 'package:flutter/foundation.dart';

import '../nam/local_nam_capture.dart';
import 'acoustic_target.dart';
import 'nam_candidate_provider.dart';
import 'tone_analysis_runner.dart';
import 'tone_knowledge_provider.dart';
import 'tone_match_models.dart';
import 'tone_plan_builder.dart';
import 'tone_similarity.dart';

enum ToneMatchPhase { idle, understanding, searching, analyzing, preparing, done }

/// Holds the state of one Tone Match search and runs the product flow:
///
///   text -> ToneIntent -> description pre-ranking over ALL local NAMs -> best [batchSize] ->
///   acoustic check (cache first) -> Similarity V1 -> at most three hits.
///
/// More sounds are only checked on an explicit [checkMore]; nothing is ever transferred
/// automatically. [coordinator] null means "no acoustic check": the hits then rest on the
/// description alone and are marked as such.
class ToneMatchController extends ChangeNotifier {
  ToneMatchController({
    required this.knowledge,
    required this.captures,
    this.coordinator,
    this.device,
    this.guitar,
    NamCandidateProvider? candidates,
    this.planBuilder = const TonePlanBuilder(),
    this.targetMapper = const AcousticTargetMapper(),
    this.batchSize = 5,
    this.maxHits = 3,
  }) : candidates = candidates ?? const NamCandidateProvider(maxCandidates: 1 << 30);

  /// Null = the knowledge could not be loaded.
  final Future<ToneKnowledgeProvider?> Function() knowledge;
  final List<LocalNamCapture> Function() captures;
  final ToneAnalysisCoordinator? coordinator;
  final ToneDeviceCapabilities? Function()? device;

  /// (name, pickup description) of the selected guitar, if any.
  final ({String name, String pickups})? Function()? guitar;
  final NamCandidateProvider candidates;
  final TonePlanBuilder planBuilder;
  final AcousticTargetMapper targetMapper;
  final int batchSize, maxHits;

  ToneMatchPhase phase = ToneMatchPhase.idle;
  ToneMatchResult? result;

  /// Real progress of the acoustic check (sounds finished out of sounds to check), else null.
  AnalysisProgress? progress;

  /// True from a cancel request until the running step has ended.
  bool cancelling = false;

  /// True if the last search was cancelled by the user (UI shows a calm notice, no error).
  bool wasCancelled = false;

  int _run = 0;
  _Search? _search;

  bool get busy => phase != ToneMatchPhase.idle && phase != ToneMatchPhase.done;

  /// Whether a "check more sounds" action is possible right now.
  bool get canCheckMore => phase == ToneMatchPhase.done && (result?.moreAvailable ?? 0) > 0;

  void cancel() {
    if (!busy || cancelling) return;
    cancelling = true;
    coordinator?.cancel();
    notifyListeners();
  }

  void reset() {
    _run++;
    coordinator?.cancel();
    _search = null;
    phase = ToneMatchPhase.idle;
    result = null;
    progress = null;
    cancelling = false;
    wasCancelled = false;
    notifyListeners();
  }

  bool _stale(int id) => id != _run;

  Future<void> start(String text) async {
    final id = ++_run;
    final g = guitar?.call();
    final request = ToneMatchRequest(text: text.trim(), guitarName: g?.name, guitarPickups: g?.pickups);
    _search = null;
    wasCancelled = false;
    cancelling = false;
    progress = null;
    if (request.text.isEmpty) {
      _finish(id, ToneMatchResult(request: request, intent: null, plan: null, failure: ToneMatchFailure.emptyQuery));
      return;
    }
    result = null;
    phase = ToneMatchPhase.understanding;
    notifyListeners();

    final provider = await knowledge();
    if (_stale(id)) return;
    final intent = provider == null ? null : await provider.resolve(request);
    if (_stale(id)) return;
    if (intent == null) {
      _finish(id, ToneMatchResult(request: request, intent: null, plan: null, failure: ToneMatchFailure.noKnowledge));
      return;
    }

    phase = ToneMatchPhase.searching;
    notifyListeners();
    await Future<void>.delayed(Duration.zero);
    if (_stale(id)) return;
    final all = captures();
    final ranked = candidates.rank(intent, all);
    if (all.isEmpty || ranked.ranked.isEmpty) {
      _finish(
        id,
        ToneMatchResult(
          request: request,
          intent: intent,
          plan: null,
          target: targetMapper.map(intent),
          failure: all.isEmpty ? ToneMatchFailure.noNams : ToneMatchFailure.noSuitableNams,
        ),
      );
      return;
    }
    final search = _Search(request: request, intent: intent, target: targetMapper.map(intent), ranked: ranked.ranked);
    _search = search;
    await _checkNext(id, search);
  }

  /// Explicit user action: check the next best sounds (never more than [batchSize]) and re-rank.
  Future<void> checkMore() async {
    final search = _search;
    if (!canCheckMore || search == null) return;
    await _checkNext(++_run, search, keepOnCancel: result);
  }

  Future<void> _checkNext(int id, _Search search, {ToneMatchResult? keepOnCancel}) async {
    final batch = search.nextBatch(batchSize);
    final coord = coordinator;
    var unavailable = false;
    if (coord != null && search.target.hasAcousticTargets && batch.isNotEmpty) {
      phase = ToneMatchPhase.analyzing;
      progress = AnalysisProgress(done: 0, total: batch.length);
      notifyListeners();
      final outcome = await coord.analyze(
        search.target.signalRole,
        [for (final c in batch) _asCandidate(c)],
        onProgress: (p) {
          if (_stale(id)) return;
          progress = p;
          notifyListeners();
        },
      );
      if (_stale(id)) return;
      if (outcome.cancelled) {
        // Back to a clean state: a first search disappears, "check more" keeps what was already shown.
        wasCancelled = true;
        cancelling = false;
        progress = null;
        if (keepOnCancel != null) {
          result = keepOnCancel;
          phase = ToneMatchPhase.done;
        } else {
          _search = null;
          result = null;
          phase = ToneMatchPhase.idle;
        }
        notifyListeners();
        return;
      }
      unavailable = outcome.unavailable;
      for (final c in batch) {
        final a = outcome.analyses[c.capture.localId];
        if (a != null) search.analyzed[c.capture.localId] = AnalyzedSound(id: c.capture.localId, name: c.capture.toneName, analysis: a, metadataScore: c.score);
      }
      search.skipped += outcome.failed.length;
      search.analysisUnavailable = search.analysisUnavailable || unavailable;
    }
    search.advance(batch.length);

    phase = ToneMatchPhase.preparing;
    progress = null;
    notifyListeners();
    await Future<void>.delayed(Duration.zero);
    if (_stale(id)) return;
    _finish(id, _build(search));
  }

  AnalysisCandidate _asCandidate(ToneMatchCandidate c) {
    final uri = Uri.tryParse(c.capture.localUri);
    final path = uri != null && uri.scheme == 'file' ? uri.toFilePath() : c.capture.localUri;
    return AnalysisCandidate(id: c.capture.localId, name: c.capture.toneName, path: path, sha256: c.capture.sha256);
  }

  ToneMatchResult _build(_Search s) {
    final measuredAny = s.analyzed.isNotEmpty;
    final moreAvailable = s.ranked.length - s.nextIndex;
    List<ToneMatchHit> hits;
    if (measuredAny) {
      final entries = SimilarityV1.rank(s.analyzed.values.toList(), s.target);
      final byId = {for (final c in s.ranked) c.capture.localId: c};
      hits = [
        for (final e in entries.take(maxHits))
          ToneMatchHit(
            candidate: byId[e.sound.id]!,
            rank: e.rank,
            reasons: SimilarityV1.explain(e, s.target, entries.length),
            measured: true,
          ),
      ];
    } else if (s.analysisUnavailable || coordinator == null || !s.target.hasAcousticTargets) {
      // No acoustic check possible: honest description-based order, labelled as such.
      hits = [
        for (var i = 0; i < s.ranked.length && i < maxHits; i++)
          ToneMatchHit(candidate: s.ranked[i], rank: i + 1, reasons: s.ranked[i].reasons, measured: false),
      ];
    } else {
      return ToneMatchResult(request: s.request, intent: s.intent, plan: null, target: s.target, checkedCount: 0, skippedCount: s.skipped, failure: ToneMatchFailure.analysisFailed);
    }
    final plan = planBuilder.adapt(planBuilder.build(s.intent, hits.first.candidate), device?.call());
    return ToneMatchResult(
      request: s.request,
      intent: s.intent,
      plan: plan,
      hits: hits,
      target: s.target,
      checkedCount: s.analyzed.length,
      moreAvailable: measuredAny ? moreAvailable : 0,
      measured: measuredAny,
      analysisUnavailable: s.analysisUnavailable,
      skippedCount: s.skipped,
    );
  }

  void _finish(int id, ToneMatchResult r) {
    if (_stale(id)) return;
    result = r;
    phase = ToneMatchPhase.done;
    progress = null;
    cancelling = false;
    notifyListeners();
  }
}

class _Search {
  _Search({required this.request, required this.intent, required this.target, required this.ranked});
  final ToneMatchRequest request;
  final ToneIntent intent;
  final AcousticTargetProfile target;

  /// Every compatible local NAM, best description match first (deterministic).
  final List<ToneMatchCandidate> ranked;
  final Map<String, AnalyzedSound> analyzed = {};
  int nextIndex = 0;
  int skipped = 0;
  bool analysisUnavailable = false;

  List<ToneMatchCandidate> nextBatch(int n) => ranked.skip(nextIndex).take(n).toList();
  void advance(int n) => nextIndex += n;
}
