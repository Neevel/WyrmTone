import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/target_sounds.dart';
import '../models/target_sound.dart';
import '../models/tone_target.dart';
import '../models/guitar_profile.dart';

class SoundRequestMatch {
  const SoundRequestMatch(this.matches, this.tuning, this.role);
  final List<TargetSound> matches;
  final GuitarTuning? tuning;
  final SoundRole? role;
  bool get exactSong =>
      matches.length == 1 &&
      matches.single.profileKind == SoundProfileKind.song;
}

class OfflineSoundProfiles {
  static String normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp("['’‘`]"), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  static bool _contains(String text, String alias) =>
      ' $text '.contains(' ${normalize(alias)} ');

  static Future<List<TargetSound>> load() async =>
      decode(await rootBundle.loadString('assets/catalog/sound_profiles.json'));
  static List<TargetSound> decode(String text) {
    final root = jsonDecode(text) as Map<String, dynamic>;
    if (root['schemaVersion'] != 1) {
      throw FormatException('Unbekannte Profilversion.');
    }
    final result = <TargetSound>[];
    for (final raw in root['profiles'] as List<dynamic>) {
      final j = raw as Map<String, dynamic>;
      final base = targetSounds.firstWhere((s) => s.id == j['baseId']);
      final target = ToneTarget(
        values: (j['tone'] as Map<String, dynamic>).map(
          (key, value) =>
              MapEntry(ToneDimension.values.byName(key), value as int),
        ),
        profileId: j['id'] as String,
        version: j['version'] as int,
        source: j['source'] as String,
        confidence: j['confidence'] as int,
        reason: j['reason'] as String,
        uncertainties: (j['uncertainties'] as List<dynamic>).cast<String>(),
        ampFamilies: (j['ampFamilies'] as List<dynamic>).cast<String>(),
        namTags: (j['namTags'] as List<dynamic>).cast<String>(),
        cabinet: j['cabinet'] as String,
        speaker: j['speaker'] as String,
        microphone: j['microphone'] as String,
      );
      result.add(
        TargetSound(
          id: target.profileId,
          artist: j['artist'] as String,
          song: j['song'] as String,
          style: j['genre'] as String,
          referenceTuning: base.referenceTuning,
          gain: target[ToneDimension.gain],
          tightness: target[ToneDimension.tightness],
          brightness: target[ToneDimension.irBrightness],
          bassAmount: target[ToneDimension.bass],
          midCharacter: base.midCharacter,
          dynamics: base.dynamics,
          ampStyle: base.ampStyle,
          cabinetStyle: base.cabinetStyle,
          effects: base.effects,
          ampModel: base.ampModel,
          baseParameters: base.baseParameters,
          confirmedFacts: const [],
          approximations: target.uncertainties,
          profileKind: SoundProfileKind.values.byName(j['kind'] as String),
          profileVersion: target.version,
          aliases: (j['aliases'] as List<dynamic>).cast<String>(),
          artistAliases: (j['artistAliases'] as List<dynamic>).cast<String>(),
          roles: (j['roles'] as List<dynamic>)
              .map((v) => SoundRole.values.byName(v as String))
              .toList(),
          supportedTunings: (j['tunings'] as List<dynamic>)
              .map((v) => GuitarTuning.values.byName(v as String))
              .toList(),
          toneTarget: target,
        ),
      );
    }
    if (result.map((s) => s.id).toSet().length != result.length) {
      throw FormatException('Doppelte Profil-ID.');
    }
    return List.unmodifiable(result);
  }

  static SoundRequestMatch resolve(String input, List<TargetSound> profiles) {
    final text = normalize(input);
    GuitarTuning? tuning;
    for (final item in GuitarTuning.values.where(
      (t) => t != GuitarTuning.custom,
    )) {
      if (_contains(text, item.label)) tuning = item;
    }
    SoundRole? role;
    if (_contains(text, 'rhythmus') || _contains(text, 'rhythm')) {
      role = SoundRole.rhythm;
    }
    if (_contains(text, 'lead')) role = SoundRole.lead;
    if (_contains(text, 'clean')) role = SoundRole.clean;
    final matches = profiles
        .where(
          (p) =>
              p.profileKind == SoundProfileKind.song &&
              [p.artist, ...p.artistAliases].any((a) => _contains(text, a)) &&
              [p.song, ...p.aliases].any((a) => _contains(text, a)),
        )
        .toList();
    return SoundRequestMatch(matches, tuning, role);
  }
}
