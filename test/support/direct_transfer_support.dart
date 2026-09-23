import 'dart:io';

import 'package:wyrmtone/devices/device_profile.dart';
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/presets/matribox_hardware_evidence.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_pipeline.dart';
import 'package:wyrmtone/presets/matribox_translation_result.dart';
import 'package:wyrmtone/services/offline_sound_engine.dart';
import 'package:wyrmtone/sounds/sound_selection.dart';
import 'package:wyrmtone/tonevault/tone_vault.dart';

import 'matribox_tone_transfer_support.dart';

String _read(String p) => File(p).readAsStringSync();

ToneVault loadFullVault() {
  final manifest = JsonManifest.parse(_read('assets/tonevault/manifest.json'));
  return ToneVault.fromTexts(
    taxonomy: _read('assets/tonevault/taxonomy.json'),
    vocabulary: _read('assets/tonevault/vocabulary.json'),
    packs: [for (final p in manifest.packs) _read('assets/tonevault/$p')],
    nlu: _read('assets/tonevault/${manifest.nlu}'),
  );
}

/// A sound as the app creates it: request text -> understanding -> built-in sound -> the user's
/// wishes -> guitar/tuning corrections (local sound) -> the recipe -> the Matribox target.
class CreatedSound {
  CreatedSound(this.text, this.selection, this.recommendation);
  final String text;
  final SoundSelection selection;
  final ToneTransferRecommendation recommendation;

  MatriboxTranslationResult analyze([MatriboxHardwareLedger? ledger]) => MatriboxTranslationAnalyzer.analyze(
    target: recommendation.target,
    library: recommendation.library,
    ledger: ledger ?? MatriboxHardwareLedger.product(),
  );
}

/// [pick] chooses the entry when the request is ambiguous (default: best candidate).
CreatedSound createFromText(
  ToneVault vault,
  String text, {
  GuitarProfile guitar = hbFusion4,
  String? entryId,
  GuitarTuning? tuning,
}) {
  final nlu = vault.nlu.understand(text);
  final id = entryId ?? nlu.baseEntryId ?? nlu.resolution.candidates.first.entry.id;
  final fallback = vault.definition(id);
  final wanted = tuning ?? (nlu.tuning?.guitarTuning == null ? null : GuitarTuning.values.byName(nlu.tuning!.guitarTuning!)) ?? guitar.tuning;
  final entry = vault.entry(id)!;
  final variant = nlu.query.role ?? (entry.roles.isEmpty ? null : entry.roles.first);
  final selection = SoundSelection(
    entryId: id,
    tuning: wanted,
    variant: variant,
    modifiers: nlu.query.modifierIntents,
    effects: nlu.query.effects,
  );
  final definition = vault.definitionFor(id, variant: selection.variant, query: selection.toQuery());
  final draft = const OfflineSoundEngine().create(
    device: TargetDeviceId.matriboxOne,
    profile: definition.toTargetSound(),
    guitar: guitar,
    tuning: wanted,
    role: definition.role,
    nams: const [],
    irs: const [],
    folderIrs: const [],
    availableUris: const {},
  );
  assert(fallback.entry.id == id);
  return CreatedSound(
    text,
    selection,
    MatriboxToneTransferPipeline.fromDraft(draft, catalog: toneCatalog, createdAt: DateTime.utc(2026)),
  );
}
