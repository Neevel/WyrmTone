import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/models/target_sound.dart';
import 'package:wyrmtone/models/tone_target.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_target_preset.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_pipeline.dart';

import 'support/direct_transfer_support.dart';
import 'support/matribox_tone_transfer_support.dart';

ToneTarget _withoutCharacter(ToneTarget target) => ToneTarget(
  values: target.values,
  profileId: target.profileId,
  version: target.version,
  source: target.source,
  confidence: target.confidence,
  reason: target.reason,
  uncertainties: target.uncertainties,
  ampFamilies: target.ampFamilies,
  namTags: target.namTags,
  cabinet: target.cabinet,
  speaker: target.speaker,
  microphone: target.microphone,
  kindHints: target.kindHints.drive?.name == 'octave'
      ? ToneKindHints(
          modulation: target.kindHints.modulation,
          delay: target.kindHints.delay,
          reverb: target.kindHints.reverb,
          userSlots: {...target.kindHints.userSlots}..remove('drive'),
        )
      : target.kindHints,
  userAdjustments: target.userAdjustments,
);

TargetSound _withoutCharacterProfile(TargetSound profile) => TargetSound(
  id: profile.id,
  artist: profile.artist,
  song: profile.song,
  style: profile.style,
  referenceTuning: profile.referenceTuning,
  gain: profile.gain,
  tightness: profile.tightness,
  brightness: profile.brightness,
  bassAmount: profile.bassAmount,
  midCharacter: profile.midCharacter,
  dynamics: profile.dynamics,
  ampStyle: profile.ampStyle,
  cabinetStyle: profile.cabinetStyle,
  effects: profile.effects,
  ampModel: profile.ampModel,
  baseParameters: profile.baseParameters,
  confirmedFacts: profile.confirmedFacts,
  approximations: profile.approximations,
  profileKind: profile.profileKind,
  profileVersion: profile.profileVersion,
  aliases: profile.aliases,
  artistAliases: profile.artistAliases,
  roles: profile.roles,
  supportedTunings: profile.supportedTunings,
  toneTarget: _withoutCharacter(profile.toneTarget!),
  templateFallback: profile.templateFallback,
);

Map<String, Object?> _snapshot(MatriboxTargetPreset target) => {
  for (final slot in MatriboxChainSlot.values)
    slot.label: {
      'state': target[slot].effectiveState.name,
      'model': target[slot].model.value?.name,
      'parameters': {
        for (final entry in target[slot].parameters.entries)
          if (entry.value.specified) entry.key: entry.value.value,
      },
    },
};

void main() {
  final vault = loadFullVault();

  test('reference set compares V1 no-character translation with V2 character translation', () {
    const references = {
      'CKY': 'cky 96 quite bitter beings',
      'Angels': 'angels dont kill',
      'Master': 'master of puppets rhythmus',
      'Nirvana': 'come as you are',
      'Clean': 'clean mit chorus und viel reverb',
      'Metalcore': 'moderner metalcore rhythm drop c',
    };

    final changed = <String>[];
    for (final entry in references.entries) {
      final after = createFromText(
        vault,
        entry.value,
        tuning: entry.key == 'CKY' ? GuitarTuning.eStandard : null,
      );
      final draft = after.recommendation.draft;
      final before = MatriboxToneTransferPipeline.recommend(
        profile: _withoutCharacterProfile(draft.profile),
        guitar: draft.guitar,
        tuning: draft.tuning,
        role: draft.role,
        catalog: toneCatalog,
        createdAt: DateTime.utc(2026),
      );
      final beforeSnapshot = _snapshot(before.target);
      final afterSnapshot = _snapshot(after.recommendation.target);
      final octaverSlots = MatriboxChainSlot.values
          .where(
            (slot) =>
                after.recommendation.target[slot].model.value?.name ==
                'Octaver',
          )
          .toList();
      expect(
        octaverSlots,
        entry.key == 'CKY' ? [MatriboxChainSlot.fx2] : isEmpty,
        reason: entry.key,
      );
      if (jsonEncode(beforeSnapshot) != jsonEncode(afterSnapshot)) {
        changed.add(entry.key);
      }
      // ignore: avoid_print
      print('${entry.key} BEFORE ${jsonEncode(beforeSnapshot)}');
      // ignore: avoid_print
      print('${entry.key} AFTER  ${jsonEncode(afterSnapshot)}');

      for (final slot in MatriboxChainSlot.values) {
        for (final value
            in after.recommendation.target[slot].parameters.values) {
          if (value.specified) {
            expect(value.value!, inInclusiveRange(-1000, 1000));
          }
        }
      }
    }

    expect(changed, contains('CKY'));
    expect(changed, isNot(contains('Angels')));
  });
}
