/// The complete, device-independent tone for all nine chain blocks.
///
/// Every block has exactly one [RecipeBlockState]; every decision carries an
/// origin. A recipe knows musical properties only (kinds, characters,
/// perceptual 0..100 levels, signed shaping) -- no Matribox model names,
/// codes, wire indices or bytes.
library;

import '../models/tone_target.dart';
import 'tone_intent.dart';

/// Central semantics of "is this block deterministic?".
///
/// - explicit UNCHANGED  -> unchanged (only ever set deliberately)
/// - wants OFF           -> off (needs no model)
/// - wants ON + kind     -> defined
/// - wants ON, no kind   -> incomplete (never "keep whatever is on the device")
/// - no statement at all -> incomplete
RecipeBlockState resolveBlockState({
  required bool? wantsOn,
  required bool kindKnown,
  bool explicitUnchanged = false,
}) {
  if (explicitUnchanged) return RecipeBlockState.unchanged;
  if (wantsOn == false) return RecipeBlockState.off;
  if (wantsOn == true) {
    return kindKnown ? RecipeBlockState.defined : RecipeBlockState.incomplete;
  }
  return RecipeBlockState.incomplete;
}

class RecipeBlock {
  const RecipeBlock({
    required this.role,
    required this.state,
    required this.stateOrigin,
    required this.stateReason,
    this.kind,
    this.params = const {},
    this.prefs = const {},
    this.incompleteReason,
  });

  final ToneBlockRole role;
  final RecipeBlockState state;
  final ToneOrigin stateOrigin;
  final String stateReason;

  /// The block's type intent (one of the enums in tone_intent.dart), if any.
  final ToneDecision<Enum>? kind;

  /// Semantic intents. Perceptual values are 0..100; EQ shaping is signed
  /// -100..+100; `sync`/`trail` are 0/1. The keys are musical, e.g. `gain`,
  /// `tightness`, `presence`, `amount`, `level`, `time`, `feedback`, `low`.
  final Map<String, ToneDecision<double>> params;

  /// Text preferences (cabinet speaker, microphone, amp family).
  final Map<String, ToneDecision<String>> prefs;
  final String? incompleteReason;

  bool get isEnabled => state == RecipeBlockState.defined;

  RecipeBlock copyWith({
    RecipeBlockState? state,
    ToneOrigin? stateOrigin,
    String? stateReason,
    ToneDecision<Enum>? kind,
    Map<String, ToneDecision<double>>? params,
    Map<String, ToneDecision<String>>? prefs,
    String? incompleteReason,
  }) => RecipeBlock(
    role: role,
    state: state ?? this.state,
    stateOrigin: stateOrigin ?? this.stateOrigin,
    stateReason: stateReason ?? this.stateReason,
    kind: kind ?? this.kind,
    params: params ?? this.params,
    prefs: prefs ?? this.prefs,
    incompleteReason: incompleteReason ?? this.incompleteReason,
  );
}

class CanonicalToneRecipe {
  CanonicalToneRecipe({
    required this.profileId,
    required this.artist,
    required this.song,
    required this.guitarName,
    required this.tuning,
    required this.soundRole,
    required Map<ToneBlockRole, RecipeBlock> blocks,
    Map<String, ToneDecision<double>> character = const {},
    this.templateId,
    this.notes = const [],
  }) : character = Map.unmodifiable(character),
       blocks = Map.unmodifiable(blocks);

  final String profileId, artist, song, guitarName, tuning;
  final SoundRole soundRole;
  final Map<ToneBlockRole, RecipeBlock> blocks;

  /// Original device-independent character intent. Derived parameter changes
  /// remain visible through their own origins; this map preserves the exact
  /// input for tracing and for device translators with future capabilities.
  final Map<String, ToneDecision<double>> character;
  final String? templateId;
  final List<String> notes;

  RecipeBlock operator [](ToneBlockRole role) => blocks[role]!;

  Iterable<RecipeBlock> get incomplete =>
      blocks.values.where((b) => b.state == RecipeBlockState.incomplete);

  CanonicalToneRecipe withBlock(RecipeBlock block) => CanonicalToneRecipe(
    profileId: profileId,
    artist: artist,
    song: song,
    guitarName: guitarName,
    tuning: tuning,
    soundRole: soundRole,
    blocks: {...blocks, block.role: block},
    character: character,
    templateId: templateId,
    notes: notes,
  );
}
