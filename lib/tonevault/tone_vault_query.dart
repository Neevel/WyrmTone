/// The structured query ToneVault understands, the modifier vocabulary and the
/// seam for a FUTURE local text parser (mini-NLU).
///
/// V1 ships a phrase-based interpreter ([ToneVaultResolver]) that fills a
/// [ToneQuery] from free text. A later parser only has to produce a
/// [ToneQuery] and call [ToneVaultResolver.resolveQuery]; nothing else changes.
library;

import '../models/tone_target.dart' show ToneDimension;
import 'tone_vault_model.dart';

enum ToneModifier {
  moreGain('MORE_GAIN'),
  lessGain('LESS_GAIN'),
  moreMids('MORE_MIDS'),
  lessMids('LESS_MIDS'),
  moreBass('MORE_BASS'),
  lessBass('LESS_BASS'),
  brighter('BRIGHTER'),
  darker('DARKER'),
  tighter('TIGHTER'),
  looser('LOOSER'),
  moreReverb('MORE_REVERB'),
  lessReverb('LESS_REVERB'),
  moreDelay('MORE_DELAY'),
  lessDelay('LESS_DELAY'),
  moreAggressive('MORE_AGGRESSIVE'),
  moreVintage('MORE_VINTAGE'),
  moreModern('MORE_MODERN'),
  moreClarity('MORE_CLARITY'),
  moreBody('MORE_BODY'),
  lessBody('LESS_BODY'),
  moreTreble('MORE_TREBLE'),
  lessTreble('LESS_TREBLE'),
  morePresence('MORE_PRESENCE'),
  lessPresence('LESS_PRESENCE'),
  lessClarity('LESS_CLARITY'),
  lessAggressive('LESS_AGGRESSIVE'),
  moreCompression('MORE_COMPRESSION'),
  lessCompression('LESS_COMPRESSION'),
  moreModulation('MORE_MODULATION'),
  lessModulation('LESS_MODULATION'),
  moreAmbient('MORE_AMBIENT'),
  lessAmbient('LESS_AMBIENT'),
  dirtier('DIRTIER'),
  cleaner('CLEANER'),
  warmer('WARMER'),
  colder('COLDER'),
  drier('DRIER'),
  wetter('WETTER');

  const ToneModifier(this.wire);
  final String wire;
  static ToneModifier? tryParse(String v) => ToneModifier.values.where((m) => m.wire == v).firstOrNull;
}

/// Device-independent deltas per modifier (perceptual 0..100 points).
/// HEURISTIC product decisions, applied only to dimensions the tone DEFINES
/// (an unspecified dimension is never invented) and clamped to 0..100.
const toneModifierDeltas = <ToneModifier, Map<ToneDimension, int>>{
  ToneModifier.moreGain: {ToneDimension.gain: 10, ToneDimension.saturation: 8},
  ToneModifier.lessGain: {ToneDimension.gain: -10, ToneDimension.saturation: -8},
  ToneModifier.moreMids: {ToneDimension.mids: 10, ToneDimension.upperMids: 5},
  ToneModifier.lessMids: {ToneDimension.mids: -10, ToneDimension.upperMids: -5},
  ToneModifier.moreBass: {ToneDimension.bass: 10},
  ToneModifier.lessBass: {ToneDimension.bass: -10},
  ToneModifier.brighter: {ToneDimension.treble: 10, ToneDimension.presence: 8, ToneDimension.irBrightness: 10},
  ToneModifier.darker: {ToneDimension.treble: -10, ToneDimension.presence: -8, ToneDimension.irBrightness: -10},
  ToneModifier.tighter: {ToneDimension.tightness: 12, ToneDimension.attack: 6, ToneDimension.bass: -4},
  ToneModifier.looser: {ToneDimension.tightness: -12, ToneDimension.attack: -6, ToneDimension.bass: 4},
  ToneModifier.moreReverb: {ToneDimension.reverb: 12, ToneDimension.space: 8},
  ToneModifier.lessReverb: {ToneDimension.reverb: -12, ToneDimension.space: -8},
  ToneModifier.moreDelay: {ToneDimension.delay: 12},
  ToneModifier.lessDelay: {ToneDimension.delay: -12},
  ToneModifier.moreAggressive: {ToneDimension.gain: 6, ToneDimension.presence: 6, ToneDimension.attack: 8},
  ToneModifier.moreVintage: {ToneDimension.tightness: -8, ToneDimension.compression: 6},
  ToneModifier.moreModern: {ToneDimension.tightness: 8, ToneDimension.compression: -6},
  ToneModifier.moreClarity: {ToneDimension.saturation: -6, ToneDimension.upperMids: 4, ToneDimension.lowMids: -4},
  ToneModifier.moreBody: {ToneDimension.bass: 6, ToneDimension.lowMids: 8},
  ToneModifier.lessBody: {ToneDimension.bass: -6, ToneDimension.lowMids: -8},
  ToneModifier.moreTreble: {ToneDimension.treble: 10, ToneDimension.presence: 4},
  ToneModifier.lessTreble: {ToneDimension.treble: -10, ToneDimension.presence: -4},
  ToneModifier.morePresence: {ToneDimension.presence: 10, ToneDimension.upperMids: 4},
  ToneModifier.lessPresence: {ToneDimension.presence: -10, ToneDimension.upperMids: -4, ToneDimension.treble: -4},
  ToneModifier.lessClarity: {ToneDimension.saturation: 6, ToneDimension.upperMids: -4, ToneDimension.lowMids: 4},
  ToneModifier.lessAggressive: {ToneDimension.gain: -6, ToneDimension.presence: -6, ToneDimension.attack: -8},
  ToneModifier.moreCompression: {ToneDimension.compression: 12, ToneDimension.sustain: 6},
  ToneModifier.lessCompression: {ToneDimension.compression: -12, ToneDimension.sustain: -6},
  ToneModifier.moreModulation: {ToneDimension.modulation: 12},
  ToneModifier.lessModulation: {ToneDimension.modulation: -12},
  ToneModifier.moreAmbient: {ToneDimension.space: 10, ToneDimension.reverb: 10, ToneDimension.delay: 6, ToneDimension.attack: -4},
  ToneModifier.lessAmbient: {ToneDimension.space: -10, ToneDimension.reverb: -10, ToneDimension.delay: -6, ToneDimension.attack: 4},
  ToneModifier.dirtier: {ToneDimension.gain: 6, ToneDimension.saturation: 12, ToneDimension.tightness: -4},
  ToneModifier.cleaner: {ToneDimension.gain: -6, ToneDimension.saturation: -12, ToneDimension.tightness: 4},
  ToneModifier.warmer: {ToneDimension.treble: -8, ToneDimension.presence: -6, ToneDimension.lowMids: 4, ToneDimension.irBrightness: -6},
  ToneModifier.colder: {ToneDimension.treble: 8, ToneDimension.presence: 6, ToneDimension.lowMids: -4, ToneDimension.irBrightness: 6},
  ToneModifier.drier: {ToneDimension.reverb: -12, ToneDimension.delay: -8, ToneDimension.space: -8},
  ToneModifier.wetter: {ToneDimension.reverb: 12, ToneDimension.delay: 8, ToneDimension.space: 8},
};

/// How strongly a relative wish is meant. Deliberately coarse: language cannot
/// express "-7.3", so an intensity only scales a modifier's central delta.
enum ToneIntensity {
  slight('SLIGHT', 50),
  normal('NORMAL', 100),
  strong('STRONG', 200);

  const ToneIntensity(this.wire, this.percent);
  final String wire;

  /// Share of the modifier's central delta.
  final int percent;
  static ToneIntensity? tryParse(String v) => ToneIntensity.values.where((i) => i.wire == v).firstOrNull;
  ToneIntensity max(ToneIntensity o) => percent >= o.percent ? this : o;
}

/// Upper bound (perceptual points) of the TOTAL shift modifiers may cause on one dimension.
const toneModifierMaxShift = 35;

/// The total shift per dimension of intensity-scaled modifiers, limited to +-[toneModifierMaxShift].
Map<ToneDimension, int> toneModifierShifts(Iterable<ToneModifierIntent> intents) {
  final shift = <ToneDimension, int>{};
  for (final i in intents) {
    (toneModifierDeltas[i.modifier] ?? const {}).forEach((d, delta) {
      shift[d] = (shift[d] ?? 0) + (delta * i.intensity.percent / 100).round();
    });
  }
  return {for (final e in shift.entries) e.key: e.value.clamp(-toneModifierMaxShift, toneModifierMaxShift)};
}

/// Applies intensity-scaled modifiers to already defined dimensions. Contributions
/// per dimension add up, the sum is limited to +-[toneModifierMaxShift], the result to 0..100.
/// Undefined dimensions stay undefined (reported in `skipped`).
({Map<ToneDimension, int> dimensions, Set<ToneDimension> skipped}) applyToneModifierIntents(
  Map<ToneDimension, int> dimensions,
  Iterable<ToneModifierIntent> intents,
) {
  final shift = toneModifierShifts(intents);
  final result = {...dimensions};
  final skipped = <ToneDimension>{};
  shift.forEach((d, total) {
    final current = result[d];
    if (current == null) {
      skipped.add(d);
    } else {
      result[d] = (current + total).clamp(0, 100);
    }
  });
  return (dimensions: Map.unmodifiable(result), skipped: Set.unmodifiable(skipped));
}

class ToneModifierIntent {
  const ToneModifierIntent(this.modifier, this.intensity, {this.phrase = ''});
  final ToneModifier modifier;
  final ToneIntensity intensity;

  /// The user's words that caused it (explainability).
  final String phrase;
  @override
  String toString() => '${modifier.wire}/${intensity.wire}';
}

/// Canonical effect ideas. They name a KIND OF EFFECT, never a device algorithm.
enum ToneEffectKind {
  boost,
  overdrive,
  distortion,
  fuzz,
  compressor,
  gate,
  chorus,
  flanger,
  phaser,
  tremolo,
  vibrato,
  delay,
  reverb,
  wah,
  octave,
  eq;

  static ToneEffectKind? tryParse(String v) => ToneEffectKind.values.where((k) => k.name == v).firstOrNull;
}

/// "with chorus" (desired) or "without reverb" (explicit OFF).
class ToneEffectIntent {
  const ToneEffectIntent(this.kind, {this.off = false, this.phrase = ''});
  final ToneEffectKind kind;
  final bool off;
  final String phrase;
  @override
  String toString() => '${off ? 'OFF' : 'ON'} ${kind.name}';
}

/// Why the parser understood something (structured, no prose).
class NluMatch {
  const NluMatch(this.kind, this.text, this.value, this.method, this.score);

  /// artist, song, album, title, genre, era, role, tuning, modifier, intensity, negation, effect, style
  final String kind;
  final String text;
  final String value;

  /// exact, alias, fuzzy or lexicon
  final String method;
  final double score;
  @override
  String toString() => '$kind:"$text"->$value [$method ${score.toStringAsFixed(2)}]';
}

/// Applies [modifiers] in order to already defined dimensions.
/// Returns the new values and the dimensions a modifier wanted to change but the tone leaves unspecified.
({Map<ToneDimension, int> dimensions, Set<ToneDimension> skipped}) applyToneModifiers(
  Map<ToneDimension, int> dimensions,
  Iterable<ToneModifier> modifiers,
) {
  final result = {...dimensions};
  final skipped = <ToneDimension>{};
  for (final m in modifiers) {
    (toneModifierDeltas[m] ?? const {}).forEach((d, delta) {
      final current = result[d];
      if (current == null) {
        skipped.add(d);
      } else {
        result[d] = (current + delta).clamp(0, 100);
      }
    });
  }
  return (dimensions: Map.unmodifiable(result), skipped: Set.unmodifiable(skipped));
}

/// A structured tone request. Every field is optional; free text is only
/// [rawText]. A future parser fills the rest.
class ToneQuery {
  const ToneQuery({
    this.rawText = '',
    this.artist,
    this.song,
    this.album,
    this.genre,
    this.era,
    this.role,
    this.tuning,
    this.modifiers = const [],
    this.tags = const [],
    this.title,
    this.normalizedText = '',
    this.subgenre,
    this.styleTerms = const [],
    this.modifierIntents = const [],
    this.effects = const [],
    this.confidence = 0,
    this.unresolvedTokens = const [],
    this.matchReasons = const [],
  });

  final String rawText;
  final String? artist, song, album;

  /// A free title/alias phrase of an entry (e.g. "neon outrun").
  final String? title;

  /// A taxonomy genre id.
  final String? genre;

  /// A taxonomy era id.
  final String? era;
  final ToneVariantKind? role;

  /// A GuitarTuning name (e.g. `dropC`).
  final String? tuning;
  final List<ToneModifier> modifiers;
  final List<String> tags;

  // --- filled by the Mini-NLU (defaults keep V1 callers unchanged)
  final String normalizedText;

  /// With [genre] = the top-level group ("metal"), the specific genre id ("thrash_metal").
  final String? subgenre;
  final List<String> styleTerms;
  final List<ToneModifierIntent> modifierIntents;
  final List<ToneEffectIntent> effects;

  /// 0..1, how much of the request was understood.
  final double confidence;
  final List<String> unresolvedTokens;
  final List<NluMatch> matchReasons;

  ToneQuery copyWith({
    String? normalizedText,
    String? genre,
    String? subgenre,
    List<String>? styleTerms,
    List<ToneModifier>? modifiers,
    List<ToneModifierIntent>? modifierIntents,
    List<ToneEffectIntent>? effects,
    double? confidence,
    List<String>? unresolvedTokens,
    List<NluMatch>? matchReasons,
  }) => ToneQuery(
    rawText: rawText,
    artist: artist,
    song: song,
    album: album,
    genre: genre ?? this.genre,
    era: era,
    role: role,
    tuning: tuning,
    modifiers: modifiers ?? this.modifiers,
    tags: tags,
    title: title,
    normalizedText: normalizedText ?? this.normalizedText,
    subgenre: subgenre ?? this.subgenre,
    styleTerms: styleTerms ?? this.styleTerms,
    modifierIntents: modifierIntents ?? this.modifierIntents,
    effects: effects ?? this.effects,
    confidence: confidence ?? this.confidence,
    unresolvedTokens: unresolvedTokens ?? this.unresolvedTokens,
    matchReasons: matchReasons ?? this.matchReasons,
  );

  bool get hasEntity =>
      artist != null || song != null || album != null || title != null || genre != null || subgenre != null || era != null || tags.isNotEmpty;
}

/// The seam for a later local text parser. It maps free text to a [ToneQuery]
/// (no cloud, no ML requirement). ToneVault V1 does not need one: the resolver
/// has a built-in phrase interpreter.
abstract interface class ToneQueryParser {
  ToneQuery parse(String text);
}
