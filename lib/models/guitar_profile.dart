enum GuitarType { strat, tele, lesPaul, superstrat, offset, other }

enum PickupType { singleCoil, p90, passiveHumbucker, activeHumbucker }

enum OutputLevel { low, medium, high }

enum ToneCharacter { dark, neutral, bright }

enum GuitarTuning {
  eStandard,
  ebStandard,
  dStandard,
  dropD,
  dropC,
  dropB,
  custom,
}

enum PlaybackPath {
  headphones,
  studioMonitors,
  frfr,
  audioInterface,
  powerAmpAndGuitarCab,
}

class GuitarProfile {
  const GuitarProfile({
    required this.id,
    required this.name,
    required this.guitarType,
    required this.pickupType,
    required this.outputLevel,
    required this.toneCharacter,
    required this.tuning,
    required this.playbackPath,
    this.stringGauge,
    this.customTuning,
  });

  factory GuitarProfile.fromJson(Map<String, Object?> json) => GuitarProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    guitarType: GuitarType.values.byName(json['guitarType'] as String),
    pickupType: PickupType.values.byName(json['pickupType'] as String),
    outputLevel: OutputLevel.values.byName(json['outputLevel'] as String),
    toneCharacter: ToneCharacter.values.byName(json['toneCharacter'] as String),
    tuning: GuitarTuning.values.byName(json['tuning'] as String),
    playbackPath: PlaybackPath.values.byName(json['playbackPath'] as String),
    stringGauge: json['stringGauge'] as String?,
    customTuning: json['customTuning'] as String?,
  );

  final String id;
  final String name;
  final GuitarType guitarType;
  final PickupType pickupType;
  final OutputLevel outputLevel;
  final ToneCharacter toneCharacter;
  final GuitarTuning tuning;
  final String? customTuning;
  final String? stringGauge;
  final PlaybackPath playbackPath;

  bool get usesRealGuitarCab =>
      playbackPath == PlaybackPath.powerAmpAndGuitarCab;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'guitarType': guitarType.name,
    'pickupType': pickupType.name,
    'outputLevel': outputLevel.name,
    'toneCharacter': toneCharacter.name,
    'tuning': tuning.name,
    'customTuning': customTuning,
    'stringGauge': stringGauge,
    'playbackPath': playbackPath.name,
  };
}

extension GuitarTypeLabel on GuitarType {
  String get label => switch (this) {
    GuitarType.strat => 'Strat',
    GuitarType.tele => 'Tele',
    GuitarType.lesPaul => 'Les Paul',
    GuitarType.superstrat => 'Superstrat',
    GuitarType.offset => 'Offset',
    GuitarType.other => 'Sonstige',
  };
}

extension PickupTypeLabel on PickupType {
  String get label => switch (this) {
    PickupType.singleCoil => 'Singlecoil',
    PickupType.p90 => 'P90',
    PickupType.passiveHumbucker => 'Passiver Humbucker',
    PickupType.activeHumbucker => 'Aktiver Humbucker',
  };
}

extension OutputLevelLabel on OutputLevel {
  String get label => switch (this) {
    OutputLevel.low => 'Niedrig',
    OutputLevel.medium => 'Mittel',
    OutputLevel.high => 'Hoch',
  };
}

extension ToneCharacterLabel on ToneCharacter {
  String get label => switch (this) {
    ToneCharacter.dark => 'Dunkel',
    ToneCharacter.neutral => 'Neutral',
    ToneCharacter.bright => 'Hell',
  };
}

extension GuitarTuningLabel on GuitarTuning {
  String get label => switch (this) {
    GuitarTuning.eStandard => 'E Standard',
    GuitarTuning.ebStandard => 'Eb Standard',
    GuitarTuning.dStandard => 'D Standard',
    GuitarTuning.dropD => 'Drop D',
    GuitarTuning.dropC => 'Drop C',
    GuitarTuning.dropB => 'Drop B',
    GuitarTuning.custom => 'Benutzerdefiniert',
  };

  int get depth => switch (this) {
    GuitarTuning.eStandard => 0,
    GuitarTuning.ebStandard || GuitarTuning.dropD => 1,
    GuitarTuning.dStandard => 2,
    GuitarTuning.dropC => 4,
    GuitarTuning.dropB => 6,
    GuitarTuning.custom => 2,
  };
}

extension PlaybackPathLabel on PlaybackPath {
  String get label => switch (this) {
    PlaybackPath.headphones => 'Kopfhörer',
    PlaybackPath.studioMonitors => 'Studiomonitore',
    PlaybackPath.frfr => 'FRFR',
    PlaybackPath.audioInterface => 'Audiointerface',
    PlaybackPath.powerAmpAndGuitarCab => 'Endstufe + Gitarrenbox',
  };
}
