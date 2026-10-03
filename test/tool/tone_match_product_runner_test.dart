@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/evaluation_signal_loader.dart';
import 'package:wyrmtone/tonematch/evaluation_signal_t15.dart';
import 'package:wyrmtone/tonematch/isolate_tone_analysis_runner.dart';
import 'package:wyrmtone/tonematch/tone_analysis_runner.dart';
import 'package:wyrmtone/tonematch/tone_features.dart';
import 'package:wyrmtone/tonematch/tone_match_cache.dart';
import 'package:wyrmtone/tonematch/tone_match_runtime_signals.dart';

import '../../tool/tonematch_gate/gate_dsp.dart';

/// The PRODUCT runner (worker isolate, real NAM engine, real evaluation WAVs) on the Windows
/// development bridge, like the other tests in test/tool. Skipped without the native DLL / local NAMs.
const _dll = 'native/nam_bridge/build/wyrmtone_nam.dll';

class _CountingRunner implements ToneAnalysisRunner {
  _CountingRunner(this.inner);
  final ToneAnalysisRunner inner;
  int runCalls = 0, started = 0;
  @override
  Future<bool> isAvailableFor(EvaluationRole role) => inner.isAvailableFor(role);
  @override
  void cancel() => inner.cancel();
  @override
  Stream<AnalysisEvent> run(EvaluationRole role, List<AnalysisCandidate> candidates) async* {
    runCalls++;
    await for (final e in inner.run(role, candidates)) {
      if (e is CandidateStarted) started++;
      yield e;
    }
  }
}

void main() {
  final nams = File('tool/tonematch_gate/ten_nam_set.json').existsSync()
      ? (jsonDecode(File('tool/tonematch_gate/ten_nam_set.json').readAsStringSync()) as List).cast<Map<String, Object?>>()
      : <Map<String, Object?>>[];
  final have = File(_dll).existsSync() && nams.isNotEmpty && nams.every((n) => File(n['path']! as String).existsSync());
  final skip = have ? false : 'native DLL or local NAM files not available';

  test('product T15 derivation is byte-identical to the validated gate derivation', () async {
    const loader = FileEvaluationSignalLoader(_read);
    for (final role in [EvaluationRole.rhythm, EvaluationRole.lead]) {
      final prepared = await loader.prepare(EvaluationSignalRegistry.forRole(role)!);
      final product = EvaluationSignalT15.derive(prepared.samples);
      final gate = buildVariants(prepared.samples, contentSeconds: [15]).firstWhere((v) => v.id == 'T15').samples;
      expect(product.length, gate.length, reason: role.name);
      expect(product.buffer.asUint8List(product.offsetInBytes, product.lengthInBytes), gate.buffer.asUint8List(gate.offsetInBytes, gate.lengthInBytes), reason: role.name);
    }
  });

  test('worker isolate: cold run equals the benchmarked analysis, second run is served from the cache without any engine, cancel leaves a usable state', () async {
    final dir = Directory.systemTemp.createTempSync('tonematch_signals');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final role in ['rhythm', 'lead']) {
      File('assets/tonematch/evaluation/wyrmtone-$role-v1.wav').copySync('${dir.path}/wyrmtone-$role-v1.wav');
    }
    final runner = _CountingRunner(IsolateToneAnalysisRunner(bundled: BundledToneMatchSignalProvider(), developmentOverrideDirectory: () async => dir.path));
    final cache = InMemoryToneMatchCache();
    final coordinator = ToneAnalysisCoordinator(runner: runner, cache: cache);
    List<AnalysisCandidate> candidates(List<String> ids) => [
      for (final n in nams.where((n) => ids.contains(n['id'])))
        AnalysisCandidate(id: n['id']! as String, name: 'NAM ${n['id']}', path: n['path']! as String, sha256: n['sha']! as String),
    ];
    final three = candidates(['01', '06', '08']);

    final progress = <int>[];
    final cold = await coordinator.analyze(EvaluationRole.rhythm, three, onProgress: (p) => progress.add(p.done));
    expect(cold.cancelled, isFalse);
    expect(cold.analyses.keys.toSet(), {'01', '06', '08'});
    expect(cold.fromCache, isEmpty);
    expect(progress.last, 3);
    expect(runner.runCalls, 1);
    expect(runner.started, 3);

    // The same numbers as the desktop reference of the Android benchmark (same signal, same NAM, same analysis).
    final ref = (jsonDecode(File('tool/tonematch_android_bench/results/desktop_t15_summary.json').readAsStringSync()) as Map)['rhythm'] as Map;
    for (final id in ['01', '06', '08']) {
      final tone = cold.analyses[id]!.features.tone;
      for (final k in [ToneFeatureIds.centroidHz, ToneFeatureIds.crestDb, ToneFeatureIds.saturationComposite]) {
        expect(tone[k]!, closeTo((ref[id] as Map)[k] as num, 1e-9 * (tone[k]!.abs() + 1)), reason: '$id $k');
      }
      expect(cold.analyses[id]!.key.signalId, 'wyrmtone-rhythm-v1#T15');
    }

    final warm = await coordinator.analyze(EvaluationRole.rhythm, three);
    expect(warm.fromCache, {'01', '06', '08'});
    expect((runner.runCalls, runner.started), (1, 3)); // no runner call, no engine
    for (final id in ['01', '06', '08']) {
      expect(warm.analyses[id]!.features.tone, cold.analyses[id]!.features.tone);
    }

    // Cancel right after the first measurement started: the running chunk ends, nothing else starts.
    final freshCache = InMemoryToneMatchCache();
    final cancelling = ToneAnalysisCoordinator(runner: runner, cache: freshCache);
    final startedBefore = runner.started;
    final future = cancelling.analyze(EvaluationRole.lead, three, onProgress: (p) {
      if (p.currentName != null) cancelling.cancel();
    });
    final out = await future;
    expect(out.cancelled, isTrue);
    expect(runner.started - startedBefore, 1);
    expect(out.analyses, isEmpty); // the unfinished measurement is not kept and not cached
    final leadSignal = CanonicalSignal.forRole(EvaluationRole.lead);
    for (final c in three) {
      expect(await freshCache.read(leadSignal.keyFor(c.sha256)), isNull);
    }

    // A new run on a clean state works.
    final again = await ToneAnalysisCoordinator(runner: runner, cache: freshCache).analyze(EvaluationRole.lead, candidates(['06']));
    expect(again.cancelled, isFalse);
    expect(again.analyses.keys, ['06']);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 10)));
}

Future<Uint8List> _read(String p) => File(p).readAsBytes();
