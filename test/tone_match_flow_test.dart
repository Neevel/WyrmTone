import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/nam/local_nam_capture.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/tone_analysis_runner.dart';
import 'package:wyrmtone/tonematch/tone_knowledge_provider.dart';
import 'package:wyrmtone/tonematch/tone_match_cache.dart';
import 'package:wyrmtone/tonematch/tone_match_controller.dart';
import 'package:wyrmtone/tonematch/tone_match_models.dart';

import 'support/sound_flow_support.dart';
import 'support/tone_match_fakes.dart';

/// Product flow: description pre-ranking over the whole library -> best five -> cache-first
/// acoustic check -> Similarity V1 -> at most three hits. Uses an in-process stand-in for the
/// isolate runner (the real one is covered by test/tool/tone_match_product_runner_test.dart).
void main() {
  late LocalToneKnowledgeProvider provider;
  setUpAll(() async => provider = LocalToneKnowledgeProvider(await loadTestVault()));

  /// [n] NAMs; the first [matching] carry high-gain/british metadata (they pre-rank first for Heresy).
  List<LocalNamCapture> library(int n, {int? matching}) {
    final m = matching ?? n;
    return [
      for (var i = 0; i < n; i++)
        i < m
            ? fakeNam('m${i.toString().padLeft(2, '0')}', 'High Gain ${i.toString().padLeft(2, '0')}', make: 'british', tags: ['high gain'])
            : fakeNam('c${i.toString().padLeft(2, '0')}', 'Clean ${i.toString().padLeft(2, '0')}', tags: ['clean']),
    ];
  }

  ({ToneMatchController c, FakeToneAnalysisRunner runner, InMemoryToneMatchCache cache}) rig(
    List<LocalNamCapture> Function() lib, {
    FakeToneAnalysisRunner? runner,
    InMemoryToneMatchCache? cache,
  }) {
    final r = runner ?? FakeToneAnalysisRunner();
    final ch = cache ?? InMemoryToneMatchCache();
    final c = ToneMatchController(
      knowledge: () async => provider,
      captures: lib,
      coordinator: ToneAnalysisCoordinator(runner: r, cache: ch),
    );
    addTearDown(c.dispose);
    return (c: c, runner: r, cache: ch);
  }

  test('0 NAMs: calm empty state, nothing is analysed', () async {
    final x = rig(() => const []);
    await x.c.start('Pantera - Heresy');
    expect(x.c.result!.failure, ToneMatchFailure.noNams);
    expect(x.runner.runCalls, 0);
  });

  test('1 to 5 NAMs: all of them are checked, no error when fewer than five exist; at most three are shown', () async {
    for (final n in [1, 4, 5]) {
      final x = rig(() => library(n));
      await x.c.start('Pantera - Heresy');
      final r = x.c.result!;
      expect(r.ok, isTrue, reason: '$n NAMs');
      expect(r.checkedCount, n);
      expect(x.runner.startedIds.length, n);
      expect(r.hits.length, n < 3 ? n : 3);
      expect(r.moreAvailable, 0);
      expect(r.measured, isTrue);
    }
  });

  test('10 NAMs: only the five best by description are measured; more only on explicit request, never automatically', () async {
    final lib = [...library(5, matching: 5), ...[for (var i = 5; i < 10; i++) fakeNam('c${i.toString().padLeft(2, '0')}', 'Clean $i', tags: ['clean'])]];
    final x = rig(() => lib);
    await x.c.start('Pantera - Heresy');
    expect(x.runner.startedIds.toSet(), {'m00', 'm01', 'm02', 'm03', 'm04'}); // the description-best five
    expect(x.c.result!.checkedCount, 5);
    expect(x.c.result!.moreAvailable, 5);
    expect(x.runner.runCalls, 1);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(x.runner.runCalls, 1); // nothing continues on its own
    await x.c.checkMore();
    expect(x.runner.startedIds.length, 10);
    expect(x.runner.startedIds.toSet().length, 10); // nobody measured twice
    expect(x.c.result!.checkedCount, 10);
    expect(x.c.result!.moreAvailable, 0);
    expect(x.c.result!.hits.length, 3);
  });

  test('metadata pre-ranking looks at every library NAM and is deterministic', () async {
    final lib = [for (var i = 0; i < 12; i++) i == 9 ? fakeNam('best', 'Best', make: 'british', tags: ['high gain']) : fakeNam('n$i', 'Plain $i')];
    final x = rig(() => lib);
    await x.c.start('Pantera - Heresy');
    expect(x.runner.startedIds.first, 'best'); // found although it is the tenth in the list
    final again = rig(() => lib.reversed.toList());
    await again.c.start('Pantera - Heresy');
    expect(again.runner.startedIds, x.runner.startedIds);
  });

  test('cache hit: a repeated search measures nothing and creates no engine', () async {
    final x = rig(() => library(5));
    await x.c.start('Pantera - Heresy');
    final first = x.c.result!;
    expect((x.runner.runCalls, x.runner.enginesCreated), (1, 5));
    await x.c.start('Pantera - Heresy');
    expect((x.runner.runCalls, x.runner.enginesCreated), (1, 5)); // unchanged: no runner call, no engine
    expect(x.c.result!.hits.map((h) => h.candidate.capture.localId), first.hits.map((h) => h.candidate.capture.localId));
  });

  test('partial cache hit: only the new NAMs are measured', () async {
    var lib = library(3);
    final x = rig(() => lib);
    await x.c.start('Pantera - Heresy');
    expect(x.runner.startedIds.length, 3);
    lib = library(5);
    await x.c.start('Pantera - Heresy');
    expect(x.runner.startedIds.length, 5); // two more, not eight
    expect(x.runner.startedIds.toSet().length, 5);
    expect(x.c.result!.checkedCount, 5);
  });

  test('cancel after candidate 3: nothing further starts, the unfinished one is not cached, finished ones stay, and a new search works', () async {
    final lib = library(5);
    final cache = InMemoryToneMatchCache();
    late ToneMatchController ctl;
    final runner = FakeToneAnalysisRunner(duringCandidate: (i, id) async {
      if (i == 2) ctl.cancel();
    });
    final x = rig(() => lib, runner: runner, cache: cache);
    ctl = x.c;
    await ctl.start('Pantera - Heresy');
    expect(ctl.result, isNull);
    expect(ctl.phase, ToneMatchPhase.idle);
    expect(ctl.wasCancelled, isTrue);
    expect(ctl.cancelling, isFalse);
    expect(runner.startedIds.length, 3); // candidates 4 and 5 never started
    expect(runner.analyzedIds.length, 2);
    final signal = CanonicalSignal.forRole(EvaluationRole.rhythm);
    final cached = <bool>[for (final c in lib) await cache.read(signal.keyFor(c.sha256)) != null];
    expect(cached.where((e) => e).length, 2); // exactly the two completed ones
    runner.duringCandidate = null;
    await ctl.start('Pantera - Heresy');
    expect(ctl.result!.ok, isTrue);
    expect(runner.startedIds.length, 3 + 3); // the unfinished one and the two never started, finished ones reused
    expect(ctl.wasCancelled, isFalse);
  });

  test('cancel during "check more" keeps the results already shown', () async {
    final lib = [...library(5, matching: 5), ...[for (var i = 5; i < 8; i++) fakeNam('c$i', 'Clean $i', tags: ['clean'])]];
    late ToneMatchController ctl;
    final runner = FakeToneAnalysisRunner();
    final x = rig(() => lib, runner: runner);
    ctl = x.c;
    await ctl.start('Pantera - Heresy');
    final before = ctl.result!;
    runner.duringCandidate = (i, id) async => ctl.cancel();
    await ctl.checkMore();
    expect(ctl.phase, ToneMatchPhase.done);
    expect(ctl.result, same(before));
    expect(ctl.wasCancelled, isTrue);
    expect(runner.startedIds.length, 6); // one unfinished candidate of the second batch, then stop
  });

  test('same input and same library give the same ranking and the same reasons', () async {
    final features = {
      for (var i = 0; i < 5; i++) 'sha-m0$i': FakeFeatures(centroid: 900.0 + 150 * i, rolloff: 1800.0 + 250 * i, mid: 0.30 - 0.03 * i, highMid: 0.2 - 0.02 * i, crest: 16.0 - 2 * i),
    };
    List<String> run(ToneMatchResult r) => [for (final h in r.hits) '${h.candidate.capture.localId}|${h.rank}|${h.reasons.join('/')}'];
    final a = rig(() => library(5), runner: FakeToneAnalysisRunner(features: features));
    final b = rig(() => library(5), runner: FakeToneAnalysisRunner(features: features));
    await a.c.start('Pantera - Heresy');
    await b.c.start('Pantera - Heresy');
    expect(run(b.c.result!), run(a.c.result!));
    expect(a.c.result!.hits.first.candidate.capture.localId, 'm04'); // darkest, least mid, most compressed
  });

  test('The Loner and Heresy lead to different targets and different rankings on the same library', () async {
    final features = {
      'sha-m00': const FakeFeatures(mid: 0.16, highMid: 0.10, crest: 6), // scooped, compressed
      'sha-m01': const FakeFeatures(mid: 0.31, highMid: 0.22, crest: 16), // mid-forward, lively
      'sha-m02': const FakeFeatures(mid: 0.24, highMid: 0.16, crest: 11),
      'sha-m03': const FakeFeatures(mid: 0.27, highMid: 0.18, crest: 13),
    };
    final lib = library(4);
    final a = rig(() => lib, runner: FakeToneAnalysisRunner(features: features));
    final b = rig(() => lib, runner: FakeToneAnalysisRunner(features: features));
    await a.c.start('Pantera - Heresy');
    await b.c.start('Gary Moore - The Loner');
    expect(a.c.result!.target!.mids!.value, isNot(b.c.result!.target!.mids!.value));
    expect(a.c.result!.hits.first.candidate.capture.localId, 'm00');
    // The Loner wants strong mids and balanced dynamics, so the scooped, heavily compressed sound is not its choice.
    expect(b.c.result!.hits.first.candidate.capture.localId, isNot('m00'));
    expect(b.c.result!.hits.first.candidate.capture.localId, isNot(a.c.result!.hits.first.candidate.capture.localId));
    expect(b.c.result!.hits.map((h) => h.candidate.capture.localId).toList(), isNot(contains('m00')));
    // the role decides which fixed test recording is used
    expect(a.runner.runCalls, 1);
  });

  test('without the test recording: honest description-based result, no analysis attempted', () async {
    final x = rig(() => library(6), runner: FakeToneAnalysisRunner(available: false));
    await x.c.start('Pantera - Heresy');
    final r = x.c.result!;
    expect(r.analysisUnavailable, isTrue);
    expect(r.measured, isFalse);
    expect(r.hits.length, 3);
    expect(r.hits.every((h) => !h.measured), isTrue);
    expect(x.runner.startedIds, isEmpty);
    expect(r.moreAvailable, 0);
  });

  test('NAMs that cannot be measured are skipped; if none can, the result says so', () async {
    final lib = library(3);
    final some = rig(() => lib, runner: FakeToneAnalysisRunner(failIds: {'m00'}));
    await some.c.start('Pantera - Heresy');
    expect(some.c.result!.skippedCount, 1);
    expect(some.c.result!.hits.length, 2);
    final none = rig(() => lib, runner: FakeToneAnalysisRunner(failIds: {'m00', 'm01', 'm02'}));
    await none.c.start('Pantera - Heresy');
    expect(none.c.result!.failure, ToneMatchFailure.analysisFailed);
  });

  test('no target device: results are still produced', () async {
    final x = rig(() => library(3));
    await x.c.start('Pantera - Heresy');
    expect(x.c.result!.plan!.device, isNull);
    expect(x.c.result!.hits, isNotEmpty);
  });

  test('locally imported NAMs (fit unknown) take part; NAMs known not to work do not', () async {
    final lib = [
      fakeNam('imp', 'Imported.nam', compat: NamCompatibility.unknown),
      fakeNam('ok', 'Known fit', compat: NamCompatibility.compatible),
      fakeNam('bad1', 'Unsupported', compat: NamCompatibility.unsupported),
      fakeNam('bad2', 'Gone', compat: NamCompatibility.missingLocalFile),
      fakeNam('bad3', 'Broken', compat: NamCompatibility.invalid),
      fakeNam('bad4', 'Convert', compat: NamCompatibility.conversionRequired),
    ];
    final x = rig(() => lib);
    await x.c.start('Pantera - Heresy');
    expect(x.runner.startedIds.toSet(), {'imp', 'ok'});
  });
}
