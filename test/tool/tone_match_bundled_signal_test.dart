@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/tonematch/acoustic_target.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/isolate_tone_analysis_runner.dart';
import 'package:wyrmtone/tonematch/tone_analysis_runner.dart';
import 'package:wyrmtone/tonematch/tone_features.dart';
import 'package:wyrmtone/tonematch/tone_knowledge_provider.dart';
import 'package:wyrmtone/tonematch/tone_match_cache.dart';
import 'package:wyrmtone/tonematch/tone_match_models.dart';
import 'package:wyrmtone/tonematch/tone_match_runtime_signals.dart';
import 'package:wyrmtone/tonematch/tone_similarity.dart';

import '../support/sound_flow_support.dart';

/// Real worker isolate + real NAM engine (Windows development bridge, like the other tests in
/// test/tool): the bundled runtime signal must give the SAME analyses as the validated external path.
const _dll = 'native/nam_bridge/build/wyrmtone_nam.dll';

void main() {
  final nams = File('tool/tonematch_gate/ten_nam_set.json').existsSync()
      ? (jsonDecode(
          File('tool/tonematch_gate/ten_nam_set.json').readAsStringSync(),
        ) as List).cast<Map<String, Object?>>()
      : <Map<String, Object?>>[];
  final have =
      File(_dll).existsSync() &&
      nams.isNotEmpty &&
      nams.every((n) => File(n['path']! as String).existsSync());

  test(
    'bundled runtime signal == external validated path: key, analysis, similarity input and ranking',
    () async {
      final dir = Directory.systemTemp.createTempSync('tonematch_override');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (final r in EvaluationRole.values) {
        final id = EvaluationSignalRegistry.forRole(r)!.id;
        File('assets/tonematch/evaluation/$id.wav')
            .copySync('${dir.path}/$id.wav');
      }
      final provider = LocalToneKnowledgeProvider(await loadTestVault());
      final bundled = BundledToneMatchSignalProvider(
        load: (a) async => ByteData.sublistView(await File(a).readAsBytes()),
      );
      final external = IsolateToneAnalysisRunner(
        bundled: BundledToneMatchSignalProvider(
          load: (a) async => throw StateError('must not be used'),
        ),
        developmentOverrideDirectory: () async => dir.path,
      );
      final fromApp = IsolateToneAnalysisRunner(
        bundled: bundled,
      ); // no override: what a release build does

      List<AnalysisCandidate> candidates(List<String> ids) => [
        for (final n in nams.where((n) => ids.contains(n['id'])))
          AnalysisCandidate(
            id: n['id']! as String,
            name: 'NAM ${n['id']}',
            path: n['path']! as String,
            sha256: n['sha']! as String,
          ),
      ];

      for (final (role, text, ids) in [
        (EvaluationRole.rhythm, 'Pantera - Heresy', ['01', '06', '08']),
        (EvaluationRole.lead, 'Gary Moore - The Loner', ['01', '06', '08']),
        (EvaluationRole.clean, 'Nirvana - Come As You Are', ['01', '06']),
      ]) {
        final list = candidates(ids);
        final a = await ToneAnalysisCoordinator(
          runner: external,
          cache: InMemoryToneMatchCache(),
        ).analyze(role, list);
        final b = await ToneAnalysisCoordinator(
          runner: fromApp,
          cache: InMemoryToneMatchCache(),
        ).analyze(role, list);
        expect(a.analyses.keys.toSet(), ids.toSet(), reason: role.name);
        expect(b.analyses.keys.toSet(), ids.toSet(), reason: role.name);
        for (final id in ids) {
          String k(NamAnalysis x) =>
              '${x.key.namSha256}|${x.key.signalSha256}|${x.key.signalId}|${x.key.analysisVersion}';
          expect(
            k(b.analyses[id]!),
            k(a.analyses[id]!),
            reason: '${role.name} $id key',
          );
          expect(
            k(b.analyses[id]!),
            '${list.firstWhere((c) => c.id == id).sha256}|${EvaluationSignalRegistry.forRole(role)!.sha256}|${CanonicalSignal.forRole(role).keyId}|$toneAnalysisVersion',
            reason: '${role.name} $id key is the validated key',
          );
          // Everything except the wall-clock bookkeeping (timings, timestamp) must be identical.
          String content(NamAnalysis x) => jsonEncode(
            x.toJson()..removeWhere(
              (k, _) => const {
                'namLoadMs',
                'inferenceMs',
                'extractionMs',
                'analyzedAt',
              }.contains(k),
            ),
          );
          expect(
            content(b.analyses[id]!),
            content(a.analyses[id]!),
            reason: '${role.name} $id analysis',
          );
        }
        final intent = (await provider.resolve(ToneMatchRequest(text: text)))!;
        final target = const AcousticTargetMapper().map(intent);
        expect(target.signalRole, role);
        List<AnalyzedSound> sounds(AnalysisOutcome o) => [
          for (final id in ids)
            AnalyzedSound(id: id, name: 'NAM $id', analysis: o.analyses[id]!),
        ];
        expect(
          sounds(b).map((s) => s.analysis.features.tone).toList(),
          sounds(a).map((s) => s.analysis.features.tone).toList(),
          reason: '${role.name} similarity input',
        );
        expect(
          SimilarityV1.rank(
            sounds(b),
            target,
          ).map((e) => (e.sound.id, e.score)).toList(),
          SimilarityV1.rank(
            sounds(a),
            target,
          ).map((e) => (e.sound.id, e.score)).toList(),
          reason: '${role.name} ranking',
        );
      }
    },
    skip: have ? false : 'native DLL or local NAM files not available',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
