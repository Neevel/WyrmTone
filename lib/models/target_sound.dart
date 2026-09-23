import 'guitar_profile.dart';
import 'tone_target.dart';

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
    this.profileKind = SoundProfileKind.song,
    this.profileVersion = 1,
    this.aliases = const [],
    this.artistAliases = const [],
    this.roles = const [SoundRole.rhythm],
    this.supportedTunings = const [],
    this.toneTarget,
    this.templateFallback = true,
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
  final SoundProfileKind profileKind;
  final int profileVersion;
  final List<String> aliases, artistAliases;
  final List<SoundRole> roles;
  final List<GuitarTuning> supportedTunings;
  final ToneTarget? toneTarget;

  /// True (default): the legacy genre templates may fill dimensions this profile
  /// is silent about. ToneVault profiles set false: an unspecified dimension
  /// stays unspecified and the recipe builder switches its block off.
  final bool templateFallback;

  String get displayName => '$artist – $song';
}
