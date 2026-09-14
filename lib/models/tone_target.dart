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

/// All dimensions: 0 = least amount/intensity, 100 = most. GateOpening is
/// opening speed (0 slow, 100 fast), space is wetness (0 dry, 100 spacious).
/// These are perceptual starting points, never device commands or wire IDs.
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
  }) : values = Map.unmodifiable(values) {
    if (version < 1 ||
        confidence < 0 ||
        confidence > 100 ||
        values.values.any((v) => v < 0 || v > 100)) {
      throw ArgumentError('Ungültiges Klangziel.');
    }
  }
  final Map<ToneDimension, int> values;
  final String profileId, source, reason, cabinet, speaker, microphone;
  final int version, confidence;
  final List<String> uncertainties, ampFamilies, namTags;
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
  );
}
