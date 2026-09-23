/// The one productive path from a recommendation to a Matribox target:
///
/// Song/Genre profile + guitar + tuning + role -> ToneRecipeBuilder
/// (fallback hierarchy, corrections) -> CanonicalToneRecipe (device
/// independent, all nine blocks) -> MatriboxToneTranslator (model matching +
/// explicit parameter rules against the editor catalog) -> MatriboxTargetPreset.
///
/// The existing OfflineSoundEngine/DraftPresetAdapter still produce the
/// draft and the CanonicalPreset (storage/exchange); the recipe reuses the
/// engine's own correction rules and the draft's final tone (session
/// corrections). The current device state is NOT an input of this file.
library;

import '../devices/device_profile.dart';
import '../models/guitar_profile.dart';
import '../models/recommendation.dart';
import '../models/target_sound.dart';
import '../models/tone_target.dart';
import '../services/offline_sound_engine.dart';
import 'canonical_preset.dart';
import 'canonical_tone_recipe.dart';
import 'device_catalog.dart';
import 'draft_preset_adapter.dart';
import 'matribox_model_library.dart';
import 'matribox_target_preset.dart';
import 'matribox_tone_translator.dart';
import 'tone_recipe_builder.dart';

class ToneTransferRecommendation {
  const ToneTransferRecommendation({
    required this.draft,
    required this.canonical,
    required this.recipe,
    required this.target,
    required this.library,
  });

  final PresetDraft draft;
  final CanonicalPreset canonical;
  final CanonicalToneRecipe recipe;
  final MatriboxTargetPreset target;
  final MatriboxModelLibrary library;

  ToneTransferRecommendation withTarget(MatriboxTargetPreset replacement) => ToneTransferRecommendation(
    draft: draft,
    canonical: canonical,
    recipe: recipe,
    target: replacement,
    library: library,
  );
}

abstract final class MatriboxToneTransferPipeline {
  /// Uses an already created draft (the UI's recommendation result).
  static ToneTransferRecommendation fromDraft(
    PresetDraft draft, {
    required DevicePresetCatalog catalog,
    DateTime? createdAt,
    ToneOverrides overrides = const ToneOverrides(),
    DeviceModelOverrides modelOverrides = const DeviceModelOverrides(),
  }) {
    if (draft.device != TargetDeviceId.matriboxOne) {
      throw ArgumentError('Tone Transfer gilt nur für die Matribox 1.');
    }
    final canonical = DraftPresetAdapter(catalog).convert(
      draft,
      createdAt: createdAt ?? DateTime.now().toUtc(),
    );
    final cab = draft.blocks.where((b) => b.slot == 'CAB').firstOrNull;
    final recipe = ToneRecipeBuilder.build(
      profile: draft.profile,
      guitar: draft.guitar,
      tuning: draft.tuning,
      role: draft.role,
      finalTone: draft.tone,
      cabEnabled: cab?.enabled,
      internalAmp: draft.selectedNamId == null,
      overrides: overrides,
    );
    final library = MatriboxModelLibrary.fromVendor(catalog);
    final target = MatriboxToneTranslator.translate(
      recipe: recipe,
      library: library,
      modelOverrides: modelOverrides,
    );
    return ToneTransferRecommendation(
      draft: draft,
      canonical: canonical,
      recipe: recipe,
      target: target,
      library: library,
    );
  }

  /// Runs the real recommendation for a profile.
  static ToneTransferRecommendation recommend({
    required TargetSound profile,
    required GuitarProfile guitar,
    required GuitarTuning tuning,
    required SoundRole role,
    required DevicePresetCatalog catalog,
    DateTime? createdAt,
    ToneOverrides overrides = const ToneOverrides(),
    DeviceModelOverrides modelOverrides = const DeviceModelOverrides(),
  }) {
    final draft = const OfflineSoundEngine().create(
      device: TargetDeviceId.matriboxOne,
      profile: profile,
      guitar: guitar,
      tuning: tuning,
      role: role,
      nams: const [],
      irs: const [],
      folderIrs: const [],
      availableUris: const {},
    );
    return fromDraft(
      draft,
      catalog: catalog,
      createdAt: createdAt,
      overrides: overrides,
      modelOverrides: modelOverrides,
    );
  }
}
