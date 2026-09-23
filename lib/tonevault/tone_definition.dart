/// A fully resolved, device-independent tone (the output of ToneVault) and its
/// hand-over to the EXISTING sound pipeline.
///
/// ToneVault does not have a second sound engine: [ToneDefinition.toTargetSound]
/// produces the same [TargetSound]/[ToneTarget] the curated profiles use, so
/// ToneRecipeBuilder (guitar/tuning/role corrections, fallback origins) and the
/// device translators run unchanged. Nothing here knows a device.
library;

import '../models/guitar_profile.dart' show GuitarTuning;
import '../models/target_sound.dart';
import '../models/tone_target.dart';
import '../presets/tone_intent.dart'
    show DelayKind, ModulationKind, PreAmpKind, ReverbKind;
import 'tone_vault_composer.dart';
import 'tone_vault_model.dart';
import 'tone_vault_query.dart';

/// Perceptual role of a variant in the existing pipeline.
SoundRole soundRoleFor(ToneVariantKind? kind) => switch (kind) {
  ToneVariantKind.lead || ToneVariantKind.solo => SoundRole.lead,
  ToneVariantKind.clean || ToneVariantKind.ambient => SoundRole.clean,
  ToneVariantKind.rhythm ||
  ToneVariantKind.crunch ||
  ToneVariantKind.special ||
  null => SoundRole.rhythm,
};

/// ToneConfidence -> the existing 0..100 [ToneTarget.confidence].
int confidenceScore(ToneConfidence c) => switch (c) {
  ToneConfidence.high => 80,
  ToneConfidence.medium => 60,
  ToneConfidence.low => 40,
};

String sourceDisclaimer(SourceClass c) => switch (c) {
  SourceClass.researched => 'Aus Quellen abgeleitet (siehe Quellenangaben).',
  SourceClass.curated => 'Von WyrmTone bewusst gebaute Klangannäherung; keine Aussage über Originalequipment.',
  SourceClass.styleInspired => 'Stilorientierte Klangannäherung; keine Aussage über Originalequipment oder Studioeinstellungen.',
  SourceClass.wyrmOriginal => 'Eigene WyrmTone-Kreation.',
  SourceClass.guitarReimagined => 'WyrmTone-Gitarreninterpretation; kein Nachbau des Originalklangs oder -synthesizers.',
  SourceClass.community => 'Nutzerinhalt; nicht von WyrmTone geprüft.',
  SourceClass.aiGenerated => 'Automatisch erzeugt; nicht von WyrmTone geprüft.',
};

class ToneDefinition {
  ToneDefinition({
    required this.entry,
    required this.resolved,
    required this.variant,
    required this.dimensions,
    required this.appliedModifiers,
    required this.skippedModifierDimensions,
    required this.chainTitles,
    this.baseDimensions,
    this.adjustments = const ToneUserAdjustments(),
    this.kindOverrides = const {},
    this.effects = const [],
    this.appliedEffects = const [],
    this.requestedTuning,
  });

  final ToneVaultEntry entry;
  final ResolvedTone resolved;
  final ToneVariantKind? variant;

  /// Resolved dimensions AFTER the user's wishes (what the user asked for, before tuning/guitar corrections).
  final Map<ToneDimension, int> dimensions;

  /// The vault's own resolved dimensions (null = same as [dimensions], no user wishes).
  final Map<ToneDimension, int>? baseDimensions;

  /// The user's wishes; the recipe applies them last and marks them USER_OVERRIDE.
  final ToneUserAdjustments adjustments;
  final List<String> appliedModifiers;
  final Set<ToneDimension> skippedModifierDimensions;
  final List<String> chainTitles;

  /// Block-type hints the user's effect wishes changed (null = explicitly off).
  final Map<ToneKindSlot, String?> kindOverrides;

  /// The user's effect wishes and the ones that changed this definition
  /// (an EQ wish has no perceptual dimension and is reported, not applied).
  final List<ToneEffectIntent> effects, appliedEffects;

  /// The tuning the user asked for (a GuitarTuning name or an NLU tuning id), if any.
  final String? requestedTuning;

  String get id => 'vault:${entry.id}:${variant?.wire.toLowerCase() ?? 'base'}';
  SourceClass get sourceClass => entry.sourceClass;
  ToneConfidence get confidence => entry.confidence;
  SoundRole get role => soundRoleFor(variant);
  bool get variantMatched => resolved.variantMatched;

  List<String> get disclaimers => [
    sourceDisclaimer(entry.sourceClass),
    if (entry.sources.isNotEmpty)
      'Quellen: ${entry.sources.map((s) => s.title).join('; ')}',
    if (!variantMatched && variant != null)
      'Für die Variante ${variant!.wire} gibt es keine eigene Ausprägung: Basisklang.',
    for (final e in effects.where((e) => !appliedEffects.contains(e)))
      'Effektwunsch ${e.kind.name} wird von der Klangbeschreibung nicht abgebildet.',
    if (appliedModifiers.isNotEmpty && skippedModifierDimensions.isNotEmpty)
      'Modifier ${appliedModifiers.join(', ')}: ${skippedModifierDimensions.map((d) => d.name).join(', ')} ist unspezifiziert und blieb unverändert.',
  ];

  String get summary =>
      '${entry.title}${variant == null ? '' : ' · ${variant!.wire}'} · ${entry.sourceClass.wire} · ${entry.confidence.wire}'
      ' · erbt: ${chainTitles.length <= 1 ? 'nichts' : chainTitles.take(chainTitles.length - 1).join(' > ')}';

  GuitarTuning? get referenceTuning => entry.tuningHints
      .map((n) => GuitarTuning.values.where((t) => t.name == n).firstOrNull)
      .whereType<GuitarTuning>()
      .firstOrNull;

  ToneKindHints get kindHints {
    PreAmpKind? drive;
    ModulationKind? modulation;
    DelayKind? delay;
    ReverbKind? reverb;
    final mergedKinds = <ToneKindSlot, String?>{
      ...resolved.kinds,
      ...kindOverrides,
    };
    mergedKinds.forEach((slot, name) {
      switch (slot) {
        case ToneKindSlot.drive:
          drive = name == null
              ? PreAmpKind.none
              : PreAmpKind.values.byName(name);
        case ToneKindSlot.modulation:
          modulation = name == null
              ? ModulationKind.none
              : ModulationKind.values.byName(name);
        case ToneKindSlot.delay:
          delay = name == null ? DelayKind.none : DelayKind.values.byName(name);
        case ToneKindSlot.reverb:
          reverb = name == null
              ? ReverbKind.none
              : ReverbKind.values.byName(name);
      }
    });
    return ToneKindHints(
      drive: drive,
      modulation: modulation,
      delay: delay,
      reverb: reverb,
      userSlots: {for (final slot in kindOverrides.keys) slot.name},
    );
  }

  /// Hand-over to the existing pipeline. Legacy genre templates are switched OFF
  /// (`templateFallback: false`): a dimension ToneVault leaves unspecified stays
  /// unspecified and the recipe builder switches its block off deterministically.
  TargetSound toTargetSound() {
    int dim(ToneDimension d) => dimensions[d] ?? 0;
    final isTemplate = entry.type.isTemplate;
    final kind = switch (entry.type) {
      ToneEntryType.song ||
      ToneEntryType.originalWyrmtone ||
      ToneEntryType.guitarReimagined => SoundProfileKind.song,
      ToneEntryType.genreTemplate ||
      ToneEntryType.styleTemplate => SoundProfileKind.genre,
      _ => SoundProfileKind.artist,
    };
    final target = ToneTarget(
      values: baseDimensions ?? dimensions,
      userAdjustments: adjustments,
      profileId: id,
      version: 1,
      source: '${entry.sourceClass.wire} · ToneVault ${entry.pack}',
      confidence: confidenceScore(entry.confidence),
      reason: summary,
      uncertainties: disclaimers,
      ampFamilies: resolved.ampFamilies ?? const [],
      namTags: resolved.namTags ?? const [],
      cabinet: resolved.cabinet ?? '',
      speaker: resolved.speaker ?? '',
      microphone: resolved.microphone ?? '',
      kindHints: kindHints,
      character: {
        for (final entry in resolved.character.entries)
          entry.key.name: entry.value,
      },
    );
    final roleLabel = variant == null
        ? ''
        : variant!.wire[0] + variant!.wire.substring(1).toLowerCase();
    return TargetSound(
      id: id,
      artist: isTemplate ? entry.title : (entry.artist ?? entry.title),
      song: entry.song ?? (roleLabel.isEmpty ? entry.title : roleLabel),
      style: entry.genres.isEmpty
          ? entry.title
          : entry.genres.first.replaceAll('_', ' '),
      referenceTuning: referenceTuning ?? GuitarTuning.eStandard,
      gain: dim(ToneDimension.gain),
      tightness: dim(ToneDimension.tightness),
      brightness: dim(ToneDimension.irBrightness),
      bassAmount: dim(ToneDimension.bass),
      midCharacter: '',
      dynamics: '',
      ampStyle: (resolved.ampFamilies ?? const []).join(', '),
      cabinetStyle: resolved.cabinet ?? '',
      effects: const [],
      ampModel: '',
      baseParameters: const {},
      confirmedFacts: const [],
      approximations: disclaimers,
      profileKind: kind,
      aliases: entry.songAliases,
      artistAliases: entry.artistAliases,
      roles: [role],
      supportedTunings: [
        for (final n in entry.tuningHints)
          ...GuitarTuning.values.where((t) => t.name == n),
      ],
      toneTarget: target,
      templateFallback: false,
    );
  }
}
