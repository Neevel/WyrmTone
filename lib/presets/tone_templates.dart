/// A few generic genre/role templates. They supply MUSICAL intents (perceptual
/// levels and block kinds) for dimensions a song/artist profile stays silent
/// about. They contain no device parameters and no song knowledge, and they
/// are only ever a fallback: a more specific profile always wins.
library;

import '../models/tone_target.dart';
import 'tone_intent.dart';

class ToneTemplate {
  const ToneTemplate({
    required this.id,
    required this.genreKeys,
    required this.role,
    required this.dimensions,
    this.driveKind,
    this.modulationKind,
    this.delayKind,
    this.reverbKind,
  });

  final String id;

  /// Lower-case fragments matched against the profile's genre text.
  final List<String> genreKeys;
  final SoundRole role;

  /// Perceptual 0..100 fallback levels, used only where the profile is silent.
  final Map<ToneDimension, int> dimensions;
  final PreAmpKind? driveKind;
  final ModulationKind? modulationKind;
  final DelayKind? delayKind;
  final ReverbKind? reverbKind;
}

abstract final class ToneTemplates {
  static const all = <ToneTemplate>[
    ToneTemplate(
      id: 'melodic_death_metal_rhythm',
      genreKeys: ['melodic death'],
      role: SoundRole.rhythm,
      dimensions: {
        ToneDimension.gain: 70,
        ToneDimension.tightness: 80,
        ToneDimension.gateStrength: 50,
        ToneDimension.gateOpening: 80,
        ToneDimension.delay: 0,
        ToneDimension.reverb: 5,
        ToneDimension.modulation: 0,
        ToneDimension.compression: 20,
      },
      driveKind: PreAmpKind.boost,
      reverbKind: ReverbKind.room,
    ),
    ToneTemplate(
      id: 'melodic_death_metal_lead',
      genreKeys: ['melodic death'],
      role: SoundRole.lead,
      dimensions: {
        ToneDimension.gain: 72,
        ToneDimension.tightness: 65,
        ToneDimension.sustain: 70,
        ToneDimension.gateStrength: 35,
        ToneDimension.delay: 25,
        ToneDimension.reverb: 20,
        ToneDimension.modulation: 0,
      },
      driveKind: PreAmpKind.overdrive,
      delayKind: DelayKind.digital,
      reverbKind: ReverbKind.hall,
    ),
    ToneTemplate(
      id: 'modern_metal_rhythm',
      genreKeys: ['metal', 'thrash', 'death'],
      role: SoundRole.rhythm,
      dimensions: {
        ToneDimension.gain: 75,
        ToneDimension.tightness: 85,
        ToneDimension.gateStrength: 60,
        ToneDimension.gateOpening: 80,
        ToneDimension.delay: 0,
        ToneDimension.reverb: 5,
        ToneDimension.modulation: 0,
        ToneDimension.compression: 20,
      },
      driveKind: PreAmpKind.boost,
      reverbKind: ReverbKind.room,
    ),
    ToneTemplate(
      id: 'hard_rock_rhythm',
      genreKeys: ['hard rock'],
      role: SoundRole.rhythm,
      dimensions: {
        ToneDimension.gain: 55,
        ToneDimension.tightness: 55,
        ToneDimension.gateStrength: 15,
        ToneDimension.delay: 0,
        ToneDimension.reverb: 10,
        ToneDimension.modulation: 0,
      },
      reverbKind: ReverbKind.room,
    ),
    ToneTemplate(
      id: 'classic_rock_crunch',
      genreKeys: ['classic rock', 'blues rock'],
      role: SoundRole.rhythm,
      dimensions: {
        ToneDimension.gain: 45,
        ToneDimension.tightness: 45,
        ToneDimension.gateStrength: 0,
        ToneDimension.delay: 0,
        ToneDimension.reverb: 15,
        ToneDimension.modulation: 0,
      },
      reverbKind: ReverbKind.spring,
    ),
    ToneTemplate(
      id: 'clean_ambient',
      genreKeys: ['ambient', 'clean', 'post rock'],
      role: SoundRole.clean,
      dimensions: {
        ToneDimension.gain: 15,
        ToneDimension.tightness: 30,
        ToneDimension.gateStrength: 0,
        ToneDimension.delay: 35,
        ToneDimension.reverb: 45,
        ToneDimension.modulation: 20,
      },
      modulationKind: ModulationKind.chorus,
      delayKind: DelayKind.analogWarm,
      reverbKind: ReverbKind.hall,
    ),
  ];

  /// First template (in the order above: most specific first) whose genre
  /// key occurs in [genre] and whose role equals [role]. Null when none fits.
  static ToneTemplate? match(String genre, SoundRole role) {
    final text = genre.toLowerCase();
    for (final template in all) {
      if (template.role == role && template.genreKeys.any(text.contains)) return template;
    }
    return null;
  }
}
