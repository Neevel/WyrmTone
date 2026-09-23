import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/controllers/recommendation_controller.dart';
import 'package:wyrmtone/devices/device_profile.dart';
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/models/recommendation.dart';
import 'package:wyrmtone/models/tone_target.dart';
import 'package:wyrmtone/nam/local_nam_capture.dart';
import 'package:wyrmtone/services/local_persistence.dart';
import 'package:wyrmtone/services/offline_sound_engine.dart';
import 'package:wyrmtone/services/offline_sound_profiles.dart';
import 'package:wyrmtone/tone3000/local_ir_record.dart';

import 'support/recommendation_fakes.dart';

const guitar = GuitarProfile(
  id: 'g',
  name: 'Test',
  guitarType: GuitarType.superstrat,
  pickupType: PickupType.activeHumbucker,
  outputLevel: OutputLevel.high,
  toneCharacter: ToneCharacter.bright,
  tuning: GuitarTuning.dropC,
  playbackPath: PlaybackPath.headphones,
);

LocalNamCapture nam(
  String id, {
  NamArchitecture arch = NamArchitecture.a1,
  NamCabinetContent cab = NamCabinetContent.withoutCabinet,
}) => LocalNamCapture(
  localId: id,
  tone3000ToneId: null,
  tone3000ModelId: null,
  toneName: 'Marshall JCM900',
  captureName: id,
  creatorName: 'Creator',
  description: null,
  make: 'Marshall',
  gearType: 'amp',
  tags: const ['highgain', 'rhythm'],
  license: 't3k',
  source: 'local',
  architecture: arch,
  fileSize: 100,
  localUri: 'file:///$id.nam',
  sha256: '',
  downloadedAt: DateTime.utc(2026),
  downloadStatus: NamDownloadStatus.imported,
  compatibility: NamCompatibility.compatible,
  targetDevice: TargetDeviceId.matriboxOne,
  validationWarnings: const [],
  attribution: 'Creator',
  cabinetContent: cab,
);
LocalIrRecord ir(int id) => LocalIrRecord(
  localUri: 'file:///ir$id.wav',
  fileName: '4x12 V30 SM57 cap$id.wav',
  tone3000ToneId: id,
  tone3000ModelId: id,
  toneName: '4x12',
  modelName: 'IR',
  creatorName: 'Creator',
  license: 't3k',
  sourceUrl: '',
  downloadedAt: DateTime.utc(2026),
  fileSize: 100,
  channels: 1,
  sampleRateHz: 48000,
  bitsPerSample: 24,
  durationMs: 100,
  checksumSha256: '',
  availability: LocalIrAvailability.downloaded,
);

void main() {
  final profiles = OfflineSoundProfiles.decode(
    File('assets/catalog/sound_profiles.json').readAsStringSync(),
  );
  const engine = OfflineSoundEngine();
  PresetDraft draft({
    List<LocalNamCapture> nams = const [],
    List<LocalIrRecord> irs = const [],
    String? selected,
    TargetDeviceId device = TargetDeviceId.matriboxOne,
    GuitarTuning tuning = GuitarTuning.dropC,
  }) => engine.create(
    device: device,
    profile: profiles.first,
    guitar: guitar,
    tuning: tuning,
    role: SoundRole.rhythm,
    nams: nams,
    irs: irs,
    folderIrs: const [],
    availableUris: {
      ...nams.map((n) => n.localUri),
      ...irs.map((i) => i.localUri),
    },
    selectedNamId: selected,
  );
  String snapshot(PresetDraft d) => jsonEncode(d.toJson());
  RecommendationController controller() {
    final store = MemoryStringStore();
    return RecommendationController(
        profileRepository: ProfileRepository(store),
        irRepository: IrCatalogRepository(store),
        filePicker: FakeIrFilePicker(),
      )
      ..profiles = [guitar]
      ..selectedProfileId = 'g'
      ..selectedTargetDevice = TargetDeviceId.matriboxOne
      ..offlineProfiles = profiles;
  }

  test(
    'known aliases, apostrophes, Drop C; unknown never implies fallback',
    () {
      for (final query in [
        "Children of Bodom Angels Don't Kill",
        'children of bodom - angels dont kill',
        'COB Angels Don’t Kill Drop C',
      ]) {
        final result = OfflineSoundProfiles.resolve(query, profiles);
        expect(result.exactSong, isTrue);
        expect(result.matches.single.id, profiles.first.id);
      }
      expect(
        OfflineSoundProfiles.resolve(
          'COB Angels Don’t Kill Drop C',
          profiles,
        ).tuning,
        GuitarTuning.dropC,
      );
      expect(
        OfflineSoundProfiles.resolve('COB Unknown Song', profiles).matches,
        isEmpty,
      );
      expect(
        OfflineSoundProfiles.resolve(
          'Melodic Death Metal Tight Rhythm',
          profiles,
        ).exactSong,
        isFalse,
      );
      expect(profiles.last.profileKind, SoundProfileKind.genre);
      expect(
        OfflineSoundProfiles.resolve('COB Angels Dont Kill', [
          profiles.first,
          profiles.first,
        ]).exactSong,
        isFalse,
      );
    },
  );
  test('determinism, guitar/tuning adaptation, verified ranges and models', () {
    final d = draft();
    expect(snapshot(d), snapshot(draft()));
    expect(
      d.tone[ToneDimension.gain],
      profiles.first.toneTarget![ToneDimension.gain] - 5,
    );
    expect(
      d.tone[ToneDimension.bass],
      lessThan(draft(tuning: GuitarTuning.eStandard).tone[ToneDimension.bass]),
    );
    expect(d.reasons.join(' '), contains('Pickup'));
    final amp = d.blocks.firstWhere((b) => b.slot == 'AMP');
    expect(OfflineDeviceCatalog.amps(d.device).containsKey(amp.model), isTrue);
    expect(amp.parameters.values.every((v) => v >= 0 && v <= 99), isTrue);
    expect(
      () => OfflineDeviceCatalog.validate(
        PresetDraft(
          device: d.device,
          profile: d.profile,
          guitar: d.guitar,
          tuning: d.tuning,
          role: d.role,
          tone: d.tone,
          blocks: [
            const DraftBlock(
              slot: 'AMP',
              model: 'invented',
              enabled: true,
              parameters: {},
              provenance: {},
              note: '',
            ),
          ],
          candidates: {},
          reasons: [],
          warnings: [],
          history: [],
          searchRequirements: [],
        ),
      ),
      throwsArgumentError,
    );
  });
  test(
    'both bundled profiles resolve to Sol 100 OD (not LD) on Matribox -- '
    'so they DO translate today, unlike the DNAfx/J900 path',
    () {
      final angelsDontKill = draft(); // profiles.first, device: matriboxOne
      final genreFallback = engine.create(
        device: TargetDeviceId.matriboxOne,
        profile: profiles.last,
        guitar: guitar,
        tuning: GuitarTuning.dropC,
        role: SoundRole.rhythm,
        nams: const [],
        irs: const [],
        folderIrs: const [],
        availableUris: const {},
      );
      for (final d in [angelsDontKill, genreFallback]) {
        final amp = d.blocks.firstWhere((b) => b.slot == 'AMP');
        expect(amp.model, 'Sol 100 OD', reason: d.profile.id);
      }
    },
  );
  test('local/architecture exclusions, stable top3 and no double cabinet', () {
    final nams = [
      for (var i = 0; i < 5; i++) nam('n$i'),
      nam('bad', arch: NamArchitecture.a2),
    ];
    final irs = [for (var i = 0; i < 5; i++) ir(i)];
    final d = draft(nams: nams, irs: irs);
    expect(d.candidates['NAM'], hasLength(3));
    expect(d.candidates['IR'], hasLength(3));
    expect(d.candidates['NAM']!.every((n) => n.eligible), isTrue);
    expect(
      d.candidates['IR']!.every((i) => !i.eligible),
      isTrue,
      reason: 'Unverified importer limits must not imply compatibility',
    );
    expect(
      draft(nams: [nam('bad', arch: NamArchitecture.a2)])
          .candidates['NAM']!
          .single
          .eligible,
      isFalse,
    );
    expect(
      draft(
        nams: [nam('n')],
        device: TargetDeviceId.dnafxGitCore,
      ).candidates['NAM']!.single.eligible,
      isFalse,
    );
    expect(
      OfflineSoundEngine.local('https://example.com/x', {
        'https://example.com/x',
      }),
      isFalse,
    );
    for (final cab in [
      NamCabinetContent.withCabinet,
      NamCabinetContent.fullRig,
    ]) {
      final withCab = draft(
        nams: [nam('cab', cab: cab)],
        irs: irs,
        selected: 'cab',
      );
      expect(withCab.cabEnabled, isFalse);
      expect(withCab.candidates['IR'], isEmpty);
      expect(
        withCab.blocks.firstWhere((b) => b.slot == 'AMP').enabled,
        isFalse,
      );
    }
  });
  test('all semantic corrections bounded, gate uses device semantics', () {
    final base = draft().tone;
    var current = base;
    for (var n = 0; n < 20; n++) {
      for (final action in RecommendationFeedback.values) {
        current = engine.corrected(current, base, action);
        for (final dimension in ToneDimension.values) {
          expect(
            (current[dimension] - base[dimension]).abs(),
            lessThanOrEqualTo(15),
          );
          expect(current[dimension], inInclusiveRange(0, 100));
        }
      }
    }
    for (final action in [
      RecommendationFeedback.tooBright,
      RecommendationFeedback.tooMuddy,
      RecommendationFeedback.tooMuchGain,
      RecommendationFeedback.tooLittleGain,
      RecommendationFeedback.gateCutsNotes,
    ]) {
      expect(engine.corrected(base, base, action).values, isNot(base.values));
    }
    final dna = draft(device: TargetDeviceId.dnafxGitCore);
    expect(
      engine.corrected(
        dna.tone,
        dna.tone,
        RecommendationFeedback.gateCutsNotes,
      )[ToneDimension.gateOpening],
      greaterThan(dna.tone[ToneDimension.gateOpening]),
    );
    expect(
      draft().blocks.firstWhere((b) => b.slot == 'Gate').parameters,
      isEmpty,
    );
  });
  test(
    'preview cancel apply undo reset preserve exact session snapshots',
    () async {
      final c = controller();
      addTearDown(c.dispose);
      await c.createOfflineSound(
        sound: profiles.first,
        tuning: GuitarTuning.dropC,
        role: SoundRole.rhythm,
        nams: [],
        irs: [],
      );
      final original = snapshot(c.offlineDraft!);
      c.previewCorrection(RecommendationFeedback.tooBright);
      expect(snapshot(c.offlineDraft!), original);
      expect(snapshot(c.offlinePreview!), isNot(original));
      c.cancelCorrection();
      expect(c.offlinePreview, isNull);
      c.previewCorrection(RecommendationFeedback.tooBright);
      c.applyCorrection();
      expect(snapshot(c.offlineDraft!), isNot(original));
      c.undoCorrection();
      expect(snapshot(c.offlineDraft!), original);
      c.previewCorrection(RecommendationFeedback.tooMuddy);
      c.applyCorrection();
      c.resetCorrections();
      expect(snapshot(c.offlineDraft!), original);
    },
  );
  test('offline paths cannot access network, TONE3000 actions or probe', () {
    for (final path in [
      'lib/services/offline_sound_engine.dart',
      'lib/services/offline_sound_profiles.dart',
      'lib/sounds/sound_session.dart',
      'lib/sounds/sound_selection.dart',
      'lib/screens/sounds_page.dart',
      'lib/screens/sound_detail_page.dart',
      'lib/screens/your_sound_page.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final forbidden in [
        'MidiReceiver',
        'MethodChannel',
        'VerifiedMatribox',
        'sendVerified',
        'connectOrBrowse',
        'HttpClient',
        'package:http',
        '.download(',
        '.send(',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason: '$path: $forbidden',
        );
      }
    }
  });
}
