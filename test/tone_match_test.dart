import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/devices/device_profile.dart';
import 'package:wyrmtone/models/tone_target.dart' show SoundRole, ToneDimension;
import 'package:wyrmtone/nam/local_nam_capture.dart';
import 'package:wyrmtone/tonematch/nam_candidate_provider.dart';
import 'package:wyrmtone/tonematch/tone_knowledge_provider.dart';
import 'package:wyrmtone/tonematch/tone_match_models.dart';
import 'package:wyrmtone/tonematch/tone_plan_builder.dart';

import 'support/sound_flow_support.dart';

LocalNamCapture nam(String id, String name, {String? make, List<String> tags = const [], String? desc, NamCompatibility compat = NamCompatibility.compatible}) =>
    LocalNamCapture(
      localId: id,
      tone3000ToneId: null,
      tone3000ModelId: null,
      toneName: name,
      captureName: name,
      creatorName: 'tester',
      description: desc,
      make: make,
      gearType: 'amp',
      tags: tags,
      license: 'cc',
      source: 'test',
      architecture: NamArchitecture.a1,
      fileSize: 1,
      localUri: 'x',
      sha256: id,
      downloadedAt: DateTime.utc(2026),
      downloadStatus: NamDownloadStatus.imported,
      compatibility: compat,
      targetDevice: TargetDeviceId.matriboxOne,
      validationWarnings: const [],
      attribution: '',
      cabinetContent: NamCabinetContent.unknown,
    );

void main() {
  late LocalToneKnowledgeProvider provider;
  setUpAll(() async => provider = LocalToneKnowledgeProvider(await loadTestVault()));

  Future<ToneIntent> intent(String text) async => (await provider.resolve(ToneMatchRequest(text: text)))!;

  test('Gary Moore and Pantera produce clearly different intents', () async {
    final moore = await intent('Gary Moore - The Loner');
    final pantera = await intent('Pantera - Heresy');
    expect(moore.role, SoundRole.lead);
    expect(pantera.role, SoundRole.rhythm);
    expect(moore.artist, 'Gary Moore');
    expect(pantera.artist, 'Pantera');
    expect(moore.dim(ToneDimension.sustain)!, greaterThan(pantera.dim(ToneDimension.sustain) ?? 0));
    expect(pantera.dim(ToneDimension.tightness)!, greaterThan(moore.dim(ToneDimension.tightness) ?? 0));
    expect(pantera.dim(ToneDimension.gain)!, greaterThan(moore.dim(ToneDimension.gain)!));
  });

  test('a song without own entry is marked UNKNOWN, never invented', () async {
    final i = await intent('Gary Moore - The Loner');
    expect(i.songKnown, isFalse);
    expect(i.evidence['song']!.kind, EvidenceKind.unknown);
    expect(i.evidence['role']!.kind, EvidenceKind.heuristic);
    final known = await intent('Nirvana - Come As You Are');
    expect(known.songKnown, isTrue);
    expect(known.evidence['song']!.kind, EvidenceKind.known);
  });

  test('same request is deterministic; unknown text and empty text yield null', () async {
    final a = await intent('Pantera - Heresy'), b = await intent('Pantera - Heresy');
    expect(a.dimensions, b.dimensions);
    expect(a.ampFamilies, b.ampFamilies);
    expect(await provider.resolve(const ToneMatchRequest(text: 'qzxv wlpk')), isNull);
    expect(await provider.resolve(const ToneMatchRequest(text: '  ')), isNull);
  });

  test('candidate ranking: only compatible NAMs, fitting metadata first, deterministic', () async {
    final i = await intent('Pantera - Heresy');
    final hay = i.ampFamilies.isEmpty ? 'metal' : i.ampFamilies.first;
    final captures = [
      nam('clean', 'Sparkly Clean', tags: ['clean']),
      nam('fit', 'Fit', make: hay, tags: ['high gain', 'metal']),
      nam('bad', 'Broken', make: hay, compat: NamCompatibility.unsupported),
    ];
    final r = const NamCandidateProvider().rank(i, captures);
    expect(r.excluded, 1);
    expect(r.ranked.map((c) => c.capture.localId), ['fit', 'clean']);
    expect(r.ranked.first.score, greaterThan(r.ranked.last.score));
    expect(const NamCandidateProvider().rank(i, captures).ranked.map((c) => c.capture.localId), ['fit', 'clean']);
  });

  test('device adaptation never claims preset transfer it does not have', () async {
    final i = await intent('Pantera - Heresy');
    const b = TonePlanBuilder();
    final cand = const NamCandidateProvider().rank(i, [nam('a', 'A', tags: ['metal'])]).ranked.first;
    final plan = b.build(i, cand);
    final d = b.adapt(plan, const ToneDeviceCapabilities(name: 'Matribox', namTransfer: true, presetTransfer: false));
    expect(d.canTransferNam, isTrue);
    expect(d.canTransferPreset, isFalse);
    expect(d.limitations.join(' '), contains('nicht automatisch'));
    expect(b.adapt(plan, null).canTransferNam, isFalse);
  });
}
