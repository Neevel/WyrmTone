import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/models/tone_target.dart' show SoundRole;
import 'package:wyrmtone/tonematch/acoustic_target.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/tone_features.dart';
import 'package:wyrmtone/tonematch/tone_knowledge_provider.dart';
import 'package:wyrmtone/tonematch/tone_match_models.dart';
import 'package:wyrmtone/tonematch/tone_similarity.dart';

import 'support/sound_flow_support.dart';
import 'support/tone_match_fakes.dart';

AnalyzedSound sound(String id, FakeFeatures f, {double meta = 0}) =>
    AnalyzedSound(id: id, name: 'Sound $id', analysis: fakeAnalysis(EvaluationRole.lead, 'sha-$id', f), metadataScore: meta);

void main() {
  late LocalToneKnowledgeProvider provider;
  const mapper = AcousticTargetMapper();
  setUpAll(() async => provider = LocalToneKnowledgeProvider(await loadTestVault()));
  Future<AcousticTargetProfile> target(String text) async => mapper.map((await provider.resolve(ToneMatchRequest(text: text)))!);

  group('acoustic target profile', () {
    test('The Loner and Heresy get clearly different, evidence-based targets', () async {
      final loner = await target('Gary Moore - The Loner');
      final heresy = await target('Pantera - Heresy');
      expect(loner.role, SoundRole.lead);
      expect(heresy.role, SoundRole.rhythm);
      expect(loner.signalRole, EvaluationRole.lead);
      expect(heresy.signalRole, EvaluationRole.rhythm);
      expect(loner.mids!.value, MidTarget.forward);
      expect(heresy.mids!.value, MidTarget.scooped);
      expect(loner.dynamics!.value, DynamicsTarget.neutral);
      expect(heresy.dynamics!.value, DynamicsTarget.compressed);
      expect(loner.mids!.value, isNot(heresy.mids!.value));
      expect(loner.dynamics!.value, isNot(heresy.dynamics!.value));
    });

    test('every direction carries its origin; heuristic links are labelled as such', () async {
      final heresy = await target('Pantera - Heresy');
      expect(heresy.mids!.evidence.kind, EvidenceKind.curated); // stated by WyrmTone's curated description
      expect(heresy.dynamics!.evidence.kind, EvidenceKind.heuristic); // gain -> dynamics is a heuristic link
      expect(heresy.dynamics!.basis, contains('Gain'));
      expect(heresy.mids!.evidence.source, contains('Pantera'));
    });

    test('aspects without a defensible measure stay unmapped instead of being forced onto a feature', () async {
      final heresy = await target('Pantera - Heresy');
      final names = heresy.unmapped.map((u) => u.aspect);
      expect(names, containsAll(['Straffheit', 'Anschlag', 'Sustain']));
      // The profile has no field through which "tightness" could steer a measurement.
      expect(heresy.hasAcousticTargets, isTrue);
      expect(heresy.unmapped.every((u) => u.reason.isNotEmpty), isTrue);
    });

    test('targets are relative directions, never absolute Hz/dB values', () async {
      final t = await target('Gary Moore - The Loner');
      expect(t.brightness!.value, isA<BrightnessTarget>());
      expect(t.mids!.value, isA<MidTarget>());
      expect(t.dynamics!.value, isA<DynamicsTarget>());
    });
  });

  group('Similarity V1', () {
    final scooped = const AcousticTargetProfile(
      role: SoundRole.rhythm,
      signalRole: EvaluationRole.rhythm,
      mids: TargetDimension(MidTarget.scooped, ToneEvidence(EvidenceKind.curated, 't'), 't'),
      dynamics: TargetDimension(DynamicsTarget.compressed, ToneEvidence(EvidenceKind.heuristic, 't'), 't'),
    );
    final forward = const AcousticTargetProfile(
      role: SoundRole.lead,
      signalRole: EvaluationRole.lead,
      mids: TargetDimension(MidTarget.forward, ToneEvidence(EvidenceKind.curated, 't'), 't'),
      dynamics: TargetDimension(DynamicsTarget.dynamic, ToneEvidence(EvidenceKind.heuristic, 't'), 't'),
    );
    final set = [
      sound('a', const FakeFeatures(mid: 0.18, highMid: 0.10, crest: 6, centroid: 1000, rolloff: 1800)), // scooped, compressed, dark
      sound('b', const FakeFeatures(mid: 0.30, highMid: 0.22, crest: 17, centroid: 1700, rolloff: 3000)), // mid-forward, dynamic, bright
      sound('c', const FakeFeatures(mid: 0.24, highMid: 0.16, crest: 11, centroid: 1300, rolloff: 2400)),
      sound('d', const FakeFeatures(mid: 0.26, highMid: 0.18, crest: 13, centroid: 1400, rolloff: 2600)),
    ];

    test('the ranking follows the relative targets', () {
      expect(SimilarityV1.rank(set, scooped).first.sound.id, 'a');
      expect(SimilarityV1.rank(set, forward).first.sound.id, 'b');
      expect(SimilarityV1.rank(set, scooped).last.sound.id, 'b');
    });

    test('only stable features count: attack, decay, transient and the saturation composite are ignored', () {
      final noisy = [
        for (final s in set)
          sound(
            s.id,
            FakeFeatures(
              mid: s.analysis.features.tone['tone.band.MID']!,
              highMid: s.analysis.features.tone['tone.band.HIGH_MID']!,
              crest: s.analysis.features.tone[ToneFeatureIds.crestDb]!,
              centroid: s.analysis.features.tone[ToneFeatureIds.centroidHz]!,
              rolloff: s.analysis.features.tone[ToneFeatureIds.rolloff85Hz]!,
              attack: (999 - s.id.codeUnitAt(0)).toDouble(), // wildly different excluded values
              decay: 50.0 * s.id.codeUnitAt(0),
              transient: -40.0 * s.id.codeUnitAt(0),
              composite: 1 - 0.1 * (s.id.codeUnitAt(0) - 96),
            ),
          ),
      ];
      final base = SimilarityV1.rank(set, scooped), changed = SimilarityV1.rank(noisy, scooped);
      expect(changed.map((e) => e.sound.id), base.map((e) => e.sound.id));
      expect(changed.map((e) => e.score), base.map((e) => e.score)); // exactly equal
      for (final id in SimilarityV1.excludedFeatureIds) {
        expect(SimilarityV1.usedFeatureIds, isNot(contains(id)), reason: id);
      }
      expect(SimilarityV1.excludedFeatureIds, containsAll([ToneFeatureIds.attackMs, ToneFeatureIds.decayDbPerSec, ToneFeatureIds.transientPeakToBodyDb]));
    });

    test('a used feature does change the result', () {
      final tweaked = [for (final s in set) s.id == 'c' ? sound('c', const FakeFeatures(mid: 0.05, highMid: 0.02, crest: 3)) : s];
      expect(SimilarityV1.rank(tweaked, scooped).first.sound.id, 'c');
    });

    test('deterministic: the same input gives the same order, independent of input order; ties break by description score then name', () {
      final a = SimilarityV1.rank(set, scooped).map((e) => e.sound.id).toList();
      expect(SimilarityV1.rank(set.reversed.toList(), scooped).map((e) => e.sound.id), a);
      expect(SimilarityV1.rank(set, scooped).map((e) => e.sound.id), a);
      final twins = [sound('x', const FakeFeatures(), meta: 1), sound('y', const FakeFeatures(), meta: 5), sound('z', const FakeFeatures(), meta: 5)];
      expect(SimilarityV1.rank(twins, scooped).map((e) => e.sound.id), ['y', 'z', 'x']);
    });

    test('a single sound carries no relative information; there is no percentage and no quality class', () {
      final one = SimilarityV1.rank([set.first], scooped);
      expect(one.single.position.brightness, 0.5);
      for (final e in SimilarityV1.rank(set, scooped)) {
        final text = SimilarityV1.explain(e, scooped, set.length).join(' ');
        expect(text, isNot(contains('%')));
        expect(text.toLowerCase(), isNot(contains('sehr passend')));
        expect(text.toLowerCase(), isNot(contains('passt gut')));
      }
    });

    test('explanations only make relative statements with at least three sounds and never claim equipment', () {
      final top = SimilarityV1.rank(set, scooped).first;
      final few = SimilarityV1.explain(top, scooped, 2).join(' ');
      final many = SimilarityV1.explain(top, scooped, 4).join(' ');
      expect(few, isNot(contains('als die meisten')));
      expect(many, contains('als die meisten geprüften Sounds'));
      expect(many, contains('Gesucht:'));
      expect(few, contains('Gesucht:'));
      for (final banned in ['benutzte', 'Amp von', 'Original']) {
        expect(many, isNot(contains(banned)));
      }
    });
  });
}
