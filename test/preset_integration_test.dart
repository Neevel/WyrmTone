import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/devices/device_profile.dart';
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/models/recommendation.dart';
import 'package:wyrmtone/models/tone_target.dart';
import 'package:wyrmtone/presets/canonical_preset.dart';
import 'package:wyrmtone/presets/device_catalog.dart';
import 'package:wyrmtone/presets/draft_preset_adapter.dart';
import 'package:wyrmtone/presets/preset_diff.dart';
import 'package:wyrmtone/presets/preset_exchange.dart';
import 'package:wyrmtone/presets/preset_exchange_channel.dart';
import 'package:wyrmtone/presets/preset_validation.dart';
import 'package:wyrmtone/services/offline_sound_engine.dart';
import 'package:wyrmtone/services/offline_sound_profiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final catalog = DevicePresetCatalog(
    objectMap(
      jsonDecode(
        File('assets/catalog/matribox_preset_catalog.json').readAsStringSync(),
      ),
    ),
  );
  test('Angels reference traverses canonical, correction, diff and exchange unchanged', () {
    final profile = OfflineSoundProfiles.decode(
      File('assets/catalog/sound_profiles.json').readAsStringSync(),
    ).firstWhere((p) => p.id.contains('angels'));
    const guitar = GuitarProfile(
      id: 'hb-fusion-4',
      name: 'HB Fusion 4',
      guitarType: GuitarType.superstrat,
      pickupType: PickupType.passiveHumbucker,
      outputLevel: OutputLevel.medium,
      toneCharacter: ToneCharacter.neutral,
      tuning: GuitarTuning.dropC,
      playbackPath: PlaybackPath.headphones,
    );
    const engine = OfflineSoundEngine();
    final original = engine.create(
      device: TargetDeviceId.matriboxOne,
      profile: profile,
      guitar: guitar,
      tuning: GuitarTuning.dropC,
      role: SoundRole.rhythm,
      nams: const [],
      irs: const [],
      folderIrs: const [],
      availableUris: const {},
    );
    final correctedTone = engine.corrected(
      original.tone,
      original.tone,
      RecommendationFeedback.tooMuchGain,
    );
    final corrected = engine.create(
      device: TargetDeviceId.matriboxOne,
      profile: profile,
      guitar: guitar,
      tuning: GuitarTuning.dropC,
      role: SoundRole.rhythm,
      nams: const [],
      irs: const [],
      folderIrs: const [],
      availableUris: const {},
      toneOverride: correctedTone,
      history: [...original.history, 'Zu viel Gain'],
    );
    final adapter = DraftPresetAdapter(catalog), at = DateTime.utc(2026);
    final a = adapter.convert(original, createdAt: at);
    final b = adapter.convert(corrected, createdAt: at, modifiedAt: at);
    expect(a.artist, 'Children of Bodom');
    expect(a.song, contains('Angels'));
    expect(a.guitarName, 'HB Fusion 4');
    expect(a.tuning, GuitarTuning.dropC.name);
    final gain = const PresetDiffEngine()
        .compare(a, b)
        .firstWhere((change) => change.path.endsWith('/gain'));
    expect(
      gain.before,
      original.blocks.firstWhere((x) => x.slot == 'AMP').parameters['Gain'],
    );
    expect(
      gain.after,
      corrected.blocks.firstWhere((x) => x.slot == 'AMP').parameters['Gain'],
    );
    expect(gain.transferable, isFalse);
    final exchange = PresetExportService(PresetValidator(catalog));
    final json = exchange.export(b, exportedAt: at);
    expect(
      canonicalJson(exchange.import(json).toJson()),
      canonicalJson(b.toJson()),
    );
  });
  test(
    'SAF channel exposes only bounded import and export document calls',
    () async {
      const channel = MethodChannel('de.neevel.wyrmtone/preset_exchange');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'export' ? true : '{"schemaVersion":1}';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      const service = AndroidPresetDocumentService();
      expect(
        await service.export('{"schemaVersion":1}', 'safe.wyrmtone.json'),
        isTrue,
      );
      expect(await service.import(), '{"schemaVersion":1}');
      expect(calls.map((c) => c.method), ['export', 'import']);
      expect(
        calls.any(
          (c) => c.method.contains('send') || c.method.contains('midi'),
        ),
        isFalse,
      );
    },
  );
}
