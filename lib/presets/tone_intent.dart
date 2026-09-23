/// Vocabulary of the device-independent tone layer (Sound Engine V2).
///
/// Nothing in this file (or in the recipe built from it) knows a Matribox
/// model name, algorithm code, parameter index or byte. A recipe says what
/// the sound should DO; a device translator decides how a device can do it.
library;

/// Where a decision comes from, most specific first:
/// USER_OVERRIDE > SONG_PROFILE > ARTIST_PROFILE > GENRE_PROFILE (template)
/// > ROLE/TUNING/GUITAR corrections (applied after the base) >
/// DEFAULT_SAFE (neutral/off when nothing states anything) >
/// DEVICE_TRANSLATION (only set by a device translator).
enum ToneOrigin {
  songProfile,
  artistProfile,
  genreProfile,
  roleProfile,
  guitarCorrection,
  tuningCorrection,
  characterInterpretation,
  userOverride,
  defaultSafe,
  deviceTranslation,
  unchanged,
}

/// How firmly a decision is grounded, never a numeric confidence.
enum ToneBasis {
  profileDerived,
  genreFallback,
  correction,
  userChoice,
  defaultSafe,
  deviceApproximation,
  none,
}

extension ToneOriginBasis on ToneOrigin {
  ToneBasis get basis => switch (this) {
    ToneOrigin.songProfile ||
    ToneOrigin.artistProfile => ToneBasis.profileDerived,
    ToneOrigin.genreProfile ||
    ToneOrigin.roleProfile => ToneBasis.genreFallback,
    ToneOrigin.guitarCorrection ||
    ToneOrigin.tuningCorrection ||
    ToneOrigin.characterInterpretation => ToneBasis.correction,
    ToneOrigin.userOverride => ToneBasis.userChoice,
    ToneOrigin.defaultSafe => ToneBasis.defaultSafe,
    ToneOrigin.deviceTranslation => ToneBasis.deviceApproximation,
    ToneOrigin.unchanged => ToneBasis.none,
  };

  String get label => switch (this) {
    ToneOrigin.songProfile => 'SONG_PROFILE',
    ToneOrigin.artistProfile => 'ARTIST_PROFILE',
    ToneOrigin.genreProfile => 'GENRE_PROFILE',
    ToneOrigin.roleProfile => 'ROLE_PROFILE',
    ToneOrigin.guitarCorrection => 'GUITAR_CORRECTION',
    ToneOrigin.tuningCorrection => 'TUNING_CORRECTION',
    ToneOrigin.characterInterpretation => 'CHARACTER_INTERPRETATION',
    ToneOrigin.userOverride => 'USER_OVERRIDE',
    ToneOrigin.defaultSafe => 'DEFAULT_SAFE',
    ToneOrigin.deviceTranslation => 'DEVICE_TRANSLATION',
    ToneOrigin.unchanged => 'UNCHANGED',
  };
}

extension ToneBasisLabel on ToneBasis {
  String get label => switch (this) {
    ToneBasis.profileDerived => 'PROFILE_DERIVED',
    ToneBasis.genreFallback => 'GENRE_FALLBACK',
    ToneBasis.correction => 'CORRECTION',
    ToneBasis.userChoice => 'USER_CHOICE',
    ToneBasis.defaultSafe => 'DEFAULT_SAFE',
    ToneBasis.deviceApproximation => 'DEVICE_APPROXIMATION',
    ToneBasis.none => 'NONE',
  };
}

class ToneDecision<T> {
  const ToneDecision(this.value, this.origin, this.reason);
  final T value;
  final ToneOrigin origin;
  final String reason;
}

/// The nine blocks of the signal chain. FX1/FX2 are two independent
/// pre-amp positions; the recipe describes each on its own.
enum ToneBlockRole { fx1, fx2, gate, amp, cab, eq, modulation, delay, reverb }

enum PreAmpKind {
  none,
  boost,
  overdrive,
  distortion,
  fuzz,
  compressor,
  octave,
  wah,
  other,
}

enum AmpCharacter { clean, crunch, highGain }

/// Noise-gate need. Mapping to a device threshold needs an explicit rule.
enum GateLevel { off, light, medium, strong }

enum GateCharacter { fast, natural, slow }

enum CabConfig { c1x12, c2x12, c4x12, other }

enum ModulationKind { none, chorus, flanger, phaser, tremolo, rotary, other }

enum DelayKind { none, digital, analogWarm, tape, pingPong, modulated, other }

enum ReverbKind { none, room, plate, hall, spring, modulated, other }

/// Block state in a recipe.
/// - [defined]: enabled with enough kind/model intent for a deterministic
///   translation,
/// - [off]: deterministically off (needs no model),
/// - [unchanged]: EXPLICITLY not part of the tone target (only a user
///   override or a template may say so; absence of data never does),
/// - [incomplete]: the block should be part of the sound but the
///   information does not suffice.
enum RecipeBlockState { defined, off, unchanged, incomplete }
