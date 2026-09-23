import '../presets/tone_intent.dart'
    show DelayKind, ModulationKind, PreAmpKind, ReverbKind;

enum ToneDimension {
  gain,
  saturation,
  tightness,
  attack,
  sustain,
  bass,
  lowMids,
  mids,
  upperMids,
  treble,
  presence,
  compression,
  gateStrength,
  gateOpening,
  space,
  delay,
  reverb,
  modulation,
  irBrightness,
}

enum SoundProfileKind { song, artist, genre, fallback }

enum SoundRole { rhythm, lead, clean }

/// Optional, device-independent block-type hints of a profile (e.g. a fuzz in the
/// drive position, a flanger). Null = the profile says nothing; the generic
/// template/default then decides exactly as before.
class ToneKindHints {
  const ToneKindHints({
    this.drive,
    this.modulation,
    this.delay,
    this.reverb,
    this.userSlots = const {},
  });
  final PreAmpKind? drive;
  final ModulationKind? modulation;
  final DelayKind? delay;
  final ReverbKind? reverb;

  /// Slots (`drive`, `modulation`, `delay`, `reverb`) whose hint is an explicit USER wish, not the profile's.
  final Set<String> userSlots;
  bool get isEmpty =>
      drive == null && modulation == null && delay == null && reverb == null;
}

/// All dimensions: 0 = least amount/intensity, 100 = most. GateOpening is
/// opening speed (0 slow, 100 fast), space is wetness (0 dry, 100 spacious).
/// These are perceptual starting points, never device commands or wire IDs.
/// The user's explicit wishes on top of a tone ("less gain", "without reverb").
/// They are applied AFTER the tuning/guitar corrections and are reported as
/// USER_OVERRIDE in the recipe, so the user's decision always wins over the
/// profile's default and stays visible.
class ToneUserAdjustments {
  const ToneUserAdjustments({this.shifts = const {}, this.absolute = const {}});

  /// Relative changes (perceptual points) added to the corrected value.
  final Map<ToneDimension, int> shifts;

  /// Explicit values (0 = switched off) that replace the corrected value.
  final Map<ToneDimension, int> absolute;
  bool get isEmpty => shifts.isEmpty && absolute.isEmpty;

  /// [corrected] = the tone after tuning/guitar corrections. Dimensions nobody defined and
  /// the user did not set explicitly stay undefined. A switched-off dimension ignores shifts.
  Map<ToneDimension, int> apply(Map<ToneDimension, int> corrected) {
    final result = {...corrected};
    for (final d in {...shifts.keys, ...absolute.keys}) {
      final fixed = absolute[d];
      final start = fixed ?? corrected[d];
      if (start == null) continue;
      result[d] = fixed == 0 ? 0 : (start + (shifts[d] ?? 0)).clamp(0, 100);
    }
    return result;
  }
}

class ToneTarget {
  ToneTarget({
    required Map<ToneDimension, int> values,
    required this.profileId,
    required this.version,
    required this.source,
    required this.confidence,
    required this.reason,
    this.uncertainties = const [],
    this.ampFamilies = const [],
    this.namTags = const [],
    this.cabinet = '4x12',
    this.speaker = 'V30',
    this.microphone = 'SM57',
    this.kindHints = const ToneKindHints(),
    this.userAdjustments = const ToneUserAdjustments(),
    Map<String, int> character = const {},
  }) : character = Map.unmodifiable(character),
       values = Map.unmodifiable(values) {
    if (version < 1 ||
        confidence < 0 ||
        confidence > 100 ||
        values.values.any((v) => v < 0 || v > 100) ||
        character.values.any((v) => v < 0 || v > 100)) {
      throw ArgumentError('Ungültiges Klangziel.');
    }
  }
  final Map<ToneDimension, int> values;
  final String profileId, source, reason, cabinet, speaker, microphone;
  final int version, confidence;
  final List<String> uncertainties, ampFamilies, namTags;
  final ToneKindHints kindHints;
  final ToneUserAdjustments userAdjustments;

  /// Device-independent advisory character axes from ToneVault. Keys are the
  /// schema names (for example `warmth` and `fuzziness`), values are 0..100.
  /// Keeping this map here lets the canonical recipe layer interpret sound
  /// character without depending on ToneVault types or any device model.
  final Map<String, int> character;
  int operator [](ToneDimension dimension) => values[dimension] ?? 0;
  ToneTarget changed(Map<ToneDimension, int> changes) => ToneTarget(
    values: {...values, ...changes},
    profileId: profileId,
    version: version,
    source: source,
    confidence: confidence,
    reason: reason,
    uncertainties: uncertainties,
    ampFamilies: ampFamilies,
    namTags: namTags,
    cabinet: cabinet,
    speaker: speaker,
    microphone: microphone,
    kindHints: kindHints,
    userAdjustments: userAdjustments,
    character: character,
  );
}
