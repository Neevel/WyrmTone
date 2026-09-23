/// Read-only information for the certification UI: what the real
/// recommendation pipeline would want on the Matribox for the bundled
/// "Angels Don't Kill" profile. Never used to write anything; the
/// certification itself only ever writes a +/-1 lab delta.
library;

import '../devices/device_profile.dart';
import '../models/guitar_profile.dart';
import '../models/tone_target.dart';
import '../models/target_sound.dart';
import '../services/offline_sound_engine.dart';
import 'device_catalog.dart';
import 'draft_preset_adapter.dart';
import 'matribox_preset_translator.dart';

/// Fixed reference setup for the preview (not the user's guitar).
const matriboxSongPreviewLabel = 'Angels Don\'t Kill · HB Fusion 4 · Drop C · Matribox 1';

const _referenceGuitar = GuitarProfile(
  id: 'hb-fusion-4',
  name: 'HB Fusion 4',
  guitarType: GuitarType.superstrat,
  pickupType: PickupType.passiveHumbucker,
  outputLevel: OutputLevel.medium,
  toneCharacter: ToneCharacter.neutral,
  tuning: GuitarTuning.dropC,
  playbackPath: PlaybackPath.headphones,
);

abstract final class MatriboxSongTargetPreview {
  /// Amp name plus one target per field name; a field the engine did not
  /// provide is simply absent (shown as NOT PROVIDED by the UI).
  static ({String? ampName, Map<String, double> targets})? compute({
    required List<TargetSound> profiles,
    required DevicePresetCatalog catalog,
  }) {
    final profile = profiles.where((p) => p.id == 'cob-angels-dont-kill').firstOrNull;
    if (profile == null) return null;
    final draft = const OfflineSoundEngine().create(
      device: TargetDeviceId.matriboxOne,
      profile: profile,
      guitar: _referenceGuitar,
      tuning: GuitarTuning.dropC,
      role: SoundRole.rhythm,
      nams: const [],
      irs: const [],
      folderIrs: const [],
      availableUris: const {},
    );
    final canonical = DraftPresetAdapter(catalog).convert(
      draft,
      createdAt: DateTime.utc(2026),
    );
    final translation = MatriboxPresetTranslator.translate(canonical);
    return (
      ampName: translation.preset.amp?.algorithmName,
      targets: {
        for (final f in translation.fields)
          if (f.value != null) f.field: f.value!,
      },
    );
  }
}
