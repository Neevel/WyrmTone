import 'guitar_profile.dart';

class TargetSound {
  const TargetSound({
    required this.id,
    required this.artist,
    required this.song,
    required this.style,
    required this.referenceTuning,
    required this.gain,
    required this.tightness,
    required this.brightness,
    required this.bassAmount,
    required this.midCharacter,
    required this.dynamics,
    required this.ampStyle,
    required this.cabinetStyle,
    required this.effects,
    required this.ampModel,
    required this.baseParameters,
    required this.confirmedFacts,
    required this.approximations,
  });

  final String id;
  final String artist;
  final String song;
  final String style;
  final GuitarTuning referenceTuning;
  final int gain;
  final int tightness;
  final int brightness;
  final int bassAmount;
  final String midCharacter;
  final String dynamics;
  final String ampStyle;
  final String cabinetStyle;
  final List<String> effects;
  final String ampModel;
  final Map<String, int> baseParameters;
  final List<String> confirmedFacts;
  final List<String> approximations;

  String get displayName => '$artist – $song';
}
