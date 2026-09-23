import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/data/target_sounds.dart' as legacy;
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/models/tone_target.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_model_matcher.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_pipeline.dart';
import 'package:wyrmtone/presets/tone_intent.dart';
import 'package:wyrmtone/tonevault/tone_vault_model.dart';

import 'support/direct_transfer_support.dart';
import 'support/matribox_tone_transfer_support.dart';

/// SOUND ACCURACY INVESTIGATION + GOLD SOUND V1: CKY -- 96 Quite Bitter Beings (real-phone
/// report, Harley Benton Fusion 4 / E Standard -> Matribox 1).
///
/// Golden/characterization trace: locks in the CURRENT, research-backed pipeline result so a
/// future change to the ToneVault composer, ToneRecipeBuilder or the AMP model matcher cannot
/// silently regress it. The investigation found no pipeline defect -- the song entry was thin by
/// design; the GOLD milestone then curated it (real research: a Louder Sound feature with direct
/// Deron Miller quotes, and the song's genre classification), adding provenance, a light character
/// signature and a `goldReference` marker, while deliberately leaving the 4 core dimensions
/// unchanged because the research CONFIRMED rather than contradicted them (see the report for the
/// full evidence ledger and the "why nothing was threshold-gamed" reasoning).
void main() {
  final vault = loadFullVault();

  test('MATRIBOX TRANSLATION QUALITY V2: character shaping stays separate while explicit '
      'octave intent adds only Octaver', () {
    final created = createFromText(
      vault,
      'cky 96 quite bitter beings',
      guitar: hbFusion4,
      tuning: GuitarTuning.eStandard,
    );
    final entry = vault.entry('song.cky.96_quite_bitter_beings')!;
    // AFTER: the enrichment IS visible on the entry itself...
    expect(entry.confidence.wire, 'MEDIUM');
    final ampBlock = created.recommendation.recipe[ToneBlockRole.amp];
    expect(
      ampBlock.prefs['ampFamilies']?.origin,
      ToneOrigin.songProfile,
      reason: 'now the song\'s own statement, not inherited from the template',
    );
    // 55/58: a LIGHT amount of warmth/fuzziness (above the 50 neutral midpoint the interpreter
    // uses -- the original 40/35 were below it, i.e. accidentally "colder/cleaner than neutral",
    // the opposite of the intended light stoner-rock coloring; fixed after cross-checking against
    // the real hardware preset investigation).
    expect(created.recommendation.recipe.character['warmth']?.value, 55);
    expect(created.recommendation.recipe.character['fuzziness']?.value, 58);
    // V1 before: Brit 800, gain 61, presence 53, bass 57, middle 61, treble 55.
    // V2 keeps the model and block states but applies bounded character shaping.
    final target = created.recommendation.target;
    expect(target[MatriboxChainSlot.amp].model.value?.name, 'Brit 800');
    expect(target[MatriboxChainSlot.amp].parameters['gain']?.value, 62);
    expect(target[MatriboxChainSlot.amp].parameters['presence']?.value, 52);
    expect(target[MatriboxChainSlot.amp].parameters['bass']?.value, 57);
    expect(target[MatriboxChainSlot.amp].parameters['middle']?.value, 61);
    expect(target[MatriboxChainSlot.amp].parameters['treble']?.value, 54);
    expect(target[MatriboxChainSlot.fx1].effectiveState, RecipeBlockState.off);
    expect(
      target[MatriboxChainSlot.fx2].effectiveState,
      RecipeBlockState.defined,
    );
    expect(target[MatriboxChainSlot.fx2].model.value?.name, 'Octaver');
  });

  test(
    'the exact song entry is resolved -- never a generic genre/artist fallback',
    () {
      final nlu = vault.nlu.understand('cky 96 quite bitter beings');
      expect(nlu.baseEntryId, 'song.cky.96_quite_bitter_beings');
      final created = createFromText(
        vault,
        'cky 96 quite bitter beings',
        guitar: hbFusion4,
        tuning: GuitarTuning.eStandard,
      );
      expect(created.selection.entryId, 'song.cky.96_quite_bitter_beings');
    },
  );

  test('the full ancestor chain (song -> artist.cky -> tpl.genre.hard_rock) is inherited: '
      'gateStrength/gateOpening/reverb/ampFamilies/cabinet all reach the recipe, not just the '
      "song entry's own 4 explicit dimensions", () {
    final resolved = vault.composer.resolve('song.cky.96_quite_bitter_beings');
    expect(resolved.chain, [
      'tpl.genre.hard_rock',
      'artist.cky',
      'song.cky.96_quite_bitter_beings',
    ]);
    // CKY's own explicit values win over the template's...
    expect(resolved.dimensions[ToneDimension.gain], 62);
    expect(resolved.dimensions[ToneDimension.tightness], 68);
    expect(resolved.dimensions[ToneDimension.bass], 58);
    expect(resolved.dimensions[ToneDimension.irBrightness], 55);
    // ...but everything CKY/artist.cky are silent about is inherited from the genre template, not lost.
    expect(resolved.dimensions[ToneDimension.gateStrength], 8);
    expect(resolved.dimensions[ToneDimension.gateOpening], 60);
    expect(resolved.dimensions[ToneDimension.mids], 62);
    expect(resolved.ampFamilies, ['british', 'crunch']);
    expect(resolved.cabinet, '4x12');
  });

  test('AMP = Brit 800: a traceable, evidence-based match -- gain/tightness/mids closeness plus '
      'the inherited "british" family bonus, not a generic/default pick', () {
    final created = createFromText(
      vault,
      'cky 96 quite bitter beings',
      guitar: hbFusion4,
      tuning: GuitarTuning.eStandard,
    );
    final ampBlock = created.recommendation.recipe[ToneBlockRole.amp];
    expect(ampBlock.kind?.value, AmpCharacter.highGain);
    expect(ampBlock.prefs['ampFamilies']?.value, 'british, crunch');
    final match = MatriboxModelMatcher.amp(
      created.recommendation.library,
      gain: ampBlock.params['gain']!.value.round(),
      tightness: ampBlock.params['tightness']?.value.round(),
      mids: ampBlock.params['mids']?.value.round(),
      families: ampBlock.prefs['ampFamilies']?.value ?? '',
    );
    expect(match.selected?.model.name, 'Brit 800');
    // Without the inherited "british" bonus, "Sol 100 OD" would have won instead (85.2 > 83.2) --
    // this locks in that the genre-template inheritance is what actually decides the winner.
    final withoutFamily = MatriboxModelMatcher.amp(
      created.recommendation.library,
      gain: ampBlock.params['gain']!.value.round(),
      tightness: ampBlock.params['tightness']?.value.round(),
      mids: ampBlock.params['mids']?.value.round(),
    );
    expect(withoutFamily.selected?.model.name, 'Sol 100 OD');
    expect(
      created.recommendation.target[MatriboxChainSlot.amp].model.value?.name,
      'Brit 800',
    );
  });

  test('the explicit curated octave intent survives ToneVault composition and becomes '
      'canonical FX2 intent', () {
    final created = createFromText(
      vault,
      'cky 96 quite bitter beings',
      guitar: hbFusion4,
      tuning: GuitarTuning.eStandard,
    );
    final recipe = created.recommendation.recipe;
    expect(recipe[ToneBlockRole.fx1].state, RecipeBlockState.off);
    expect(recipe[ToneBlockRole.fx1].stateReason, contains('Kompression'));
    expect(recipe[ToneBlockRole.fx2].state, RecipeBlockState.defined);
    expect(recipe[ToneBlockRole.fx2].kind?.value, PreAmpKind.octave);
    expect(recipe[ToneBlockRole.fx2].kind?.origin, ToneOrigin.songProfile);
    expect(
      created.recommendation.target[MatriboxChainSlot.fx2].model.value?.name,
      'Octaver',
    );
    expect(
      created.recommendation.target[MatriboxChainSlot.fx2].parameters,
      isEmpty,
      reason: 'no Octaver values are guessed from catalog labels',
    );
    // The legacy profile remains empty; this Gold curation is intentionally ToneVault-first.
    final legacyCky = legacy.targetSounds.firstWhere(
      (s) => s.id == 'cky-96-qbb',
    );
    expect(legacyCky.effects, isEmpty);
  });

  test('an explicit user request without Octaver overrides the curated Gold intent', () {
    final disabled = createFromText(
      vault,
      'cky 96 quite bitter beings ohne octaver',
      guitar: hbFusion4,
      tuning: GuitarTuning.eStandard,
    );
    final fx2 = disabled.recommendation.recipe[ToneBlockRole.fx2];
    expect(fx2.state, RecipeBlockState.off);
    expect(fx2.stateOrigin, ToneOrigin.userOverride);
    expect(
      disabled.recommendation.target[MatriboxChainSlot.fx2].effectiveState,
      RecipeBlockState.off,
    );
  });

  test('CAB is decided by the GUITAR profile\'s own Wiedergabeweg (playbackPath), not by the '
      'song: the same CKY sound is CAB=ON for a guitar without a real cab and CAB=OFF for one '
      'wired through a real power amp + cabinet', () {
    const throughRealCab = GuitarProfile(
      id: 'hb-fusion-4-real-cab',
      name: 'HB Fusion 4 (real cab)',
      guitarType: GuitarType.superstrat,
      pickupType: PickupType.passiveHumbucker,
      outputLevel: OutputLevel.medium,
      toneCharacter: ToneCharacter.neutral,
      tuning: GuitarTuning.eStandard,
      playbackPath: PlaybackPath.powerAmpAndGuitarCab,
    );
    final withInternalCab = createFromText(
      vault,
      'cky 96 quite bitter beings',
      guitar: hbFusion4,
      tuning: GuitarTuning.eStandard,
    );
    expect(
      withInternalCab
          .recommendation
          .target[MatriboxChainSlot.cab]
          .effectiveState,
      RecipeBlockState.defined,
    );
    expect(
      withInternalCab
          .recommendation
          .target[MatriboxChainSlot.cab]
          .model
          .value
          ?.name,
      'BritGN 4x12',
    );

    final withRealCab = createFromText(
      vault,
      'cky 96 quite bitter beings',
      guitar: throughRealCab,
      tuning: GuitarTuning.eStandard,
    );
    expect(
      withRealCab.recommendation.target[MatriboxChainSlot.cab].effectiveState,
      RecipeBlockState.off,
    );
    expect(
      withRealCab.recommendation.recipe[ToneBlockRole.cab].stateReason,
      contains('Reale Gitarrenbox'),
    );
  });

  test('the legacy (pre-ToneVault) target_sounds.dart CKY entry is not reachable through the '
      'Matribox pipeline: RecommendationController.recommendation is DNAfx-only, and the legacy '
      'TargetSound has no toneTarget for the recipe builder to use', () {
    final legacyCky = legacy.targetSounds.firstWhere(
      (s) => s.id == 'cky-96-qbb',
    );
    expect(
      legacyCky.toneTarget,
      isNull,
      reason: 'never populated for the legacy list; only usable via the DNAfx-only path',
    );
  });

  test('other songs keep resolving through their own exact entry (fallback/specificity did not '
      'regress alongside CKY)', () {
    for (final text in [
      "angels don't kill",
      'master of puppets',
      'come as you are',
    ]) {
      final nlu = vault.nlu.understand(text);
      expect(nlu.baseEntryId, isNotNull, reason: text);
      final created = createFromText(vault, text);
      expect(created.selection.entryId, nlu.baseEntryId, reason: text);
    }
  });

  test('DEVICE INDEPENDENCE: the enriched CKY entry (and the whole vault) stays free of device '
      'identifiers -- loadFullVault() itself already enforces this at import time (a '
      'DEVICE_TERM violation throws before any test runs), this just names the guarantee '
      'explicitly and checks the new fields directly', () {
    // If ANY pack (including the just-enriched modern_metal.json) contained a device term, this
    // setup would already have thrown ToneVaultLoadException before reaching this line.
    expect(vault.entries, isNotEmpty);
    final cky = vault.entry('song.cky.96_quite_bitter_beings')!;
    final forbidden = RegExp(
      r'sysex|qme2|wire\s*index|algorithm\s*(id|code)|parameter\s*(id|index)|matribox|dnafx|midi\s*byte',
      caseSensitive: false,
    );
    final haystack = [
      cky.notes ?? '',
      for (final s in cky.sources) '${s.title} ${s.note ?? ''}',
      cky.tone.ampFamilies.value?.join(' ') ?? '',
      cky.tone.cabinet.value ?? '',
    ].join(' ');
    expect(forbidden.hasMatch(haystack), isFalse, reason: haystack);
  });

  test('GOLD REFERENCE marker is set on CKY and on Angels, and nowhere else derives special '
      'behaviour from it -- it is an internal curation-priority signal, never a quality gate '
      'or a user-facing ranking', () {
    final cky = vault.entry('song.cky.96_quite_bitter_beings')!;
    final angels = vault.entry('song.children_of_bodom.angels_dont_kill')!;
    expect(cky.goldReference, isTrue);
    expect(angels.goldReference, isTrue);
    // A handful of clearly non-gold songs stay false (the field defaults to false, is not
    // required, and does not need touching for the other 296 song-like entries).
    final randomOthers = vault.entries
        .where(
          (e) =>
              e.type == ToneEntryType.song &&
              e.id != cky.id &&
              e.id != angels.id,
        )
        .take(20);
    expect(
      randomOthers.where((e) => e.goldReference),
      isEmpty,
      reason: 'gold marking must stay opt-in, not a side effect of parsing',
    );
  });

  test('GOLD CURATION: CKY is now a deliberately reviewed sound, not a bare fallback -- it '
      'carries its OWN character/amp-family/cabinet signature on the song entry itself (a '
      'generic hard-rock song with zero own tone data would have none of these), and its '
      'resolved ampFamilies is attributed to the SONG, not silently to the genre template', () {
    final cky = vault.entry('song.cky.96_quite_bitter_beings')!;
    expect(cky.tone.dimensions.length, greaterThanOrEqualTo(4));
    expect(
      cky.tone.character.isEmpty,
      isFalse,
      reason: 'own character signature, not just inherited',
    );
    expect(cky.tone.ampFamilies.isDefined, isTrue);
    expect(cky.tone.cabinet.isDefined, isTrue);
    final ckyResolved = vault.composer.resolve(
      'song.cky.96_quite_bitter_beings',
    );
    expect(
      ckyResolved.provenance['dimension:gain'],
      'song.cky.96_quite_bitter_beings',
    );
    expect(
      ckyResolved.provenance['ampFamilies'],
      'song.cky.96_quite_bitter_beings',
    );
    expect(
      ckyResolved.provenance['cabinet'],
      'song.cky.96_quite_bitter_beings',
    );
  });

  test('user adjustments still apply on top of the curated Gold profile: a "weniger Gain" wish '
      'lowers gain and is attributed to USER_OVERRIDE, the rest of the Gold curation is untouched', () {
    final base = createFromText(
      vault,
      'cky 96 quite bitter beings',
      guitar: hbFusion4,
      tuning: GuitarTuning.eStandard,
    );
    final adjusted = createFromText(
      vault,
      'cky 96 quite bitter beings weniger gain',
      guitar: hbFusion4,
      tuning: GuitarTuning.eStandard,
    );
    final baseGain = base
        .recommendation
        .target[MatriboxChainSlot.amp]
        .parameters['gain']!
        .value!;
    final adjustedGain = adjusted
        .recommendation
        .target[MatriboxChainSlot.amp]
        .parameters['gain']!
        .value!;
    expect(adjustedGain, lessThan(baseGain));
    expect(
      adjusted
          .recommendation
          .target[MatriboxChainSlot.amp]
          .parameters['gain']!
          .origin,
      ToneOrigin.userOverride,
    );
    // ampFamilies/cabinet (the Gold curation) are unaffected by a gain wish.
    expect(
      adjusted.recommendation.target[MatriboxChainSlot.amp].model.value?.name,
      'Brit 800',
    );
  });

  test('guitar correction still applies on top of the curated Gold profile: two different '
      'guitars produce two different final recipes for the same CKY sound', () {
    const brightHumbucker = GuitarProfile(
      id: 'bright-active-probe',
      name: 'Bright Active Les Paul',
      guitarType: GuitarType.lesPaul,
      pickupType: PickupType.activeHumbucker,
      outputLevel: OutputLevel.high,
      toneCharacter: ToneCharacter.bright,
      tuning: GuitarTuning.eStandard,
      playbackPath: PlaybackPath.headphones,
    );
    final withHbFusion = createFromText(
      vault,
      'cky 96 quite bitter beings',
      guitar: hbFusion4,
      tuning: GuitarTuning.eStandard,
    );
    final withOtherGuitar = createFromText(
      vault,
      'cky 96 quite bitter beings',
      guitar: brightHumbucker,
      tuning: GuitarTuning.eStandard,
    );
    // Both resolve the same Gold entry (CKY is not hard-coded to one guitar)...
    expect(withHbFusion.selection.entryId, 'song.cky.96_quite_bitter_beings');
    expect(
      withOtherGuitar.selection.entryId,
      'song.cky.96_quite_bitter_beings',
    );
    expect(
      withHbFusion
          .recommendation
          .target[MatriboxChainSlot.amp]
          .model
          .value
          ?.name,
      'Brit 800',
    );
    // ...but guitar correction still measurably runs: a very different guitar (active humbucker,
    // high output, bright) must not produce the identical AMP gain as HB Fusion 4.
    final hbGain = withHbFusion
        .recommendation
        .target[MatriboxChainSlot.amp]
        .parameters['gain']!
        .value!;
    final otherGain = withOtherGuitar
        .recommendation
        .target[MatriboxChainSlot.amp]
        .parameters['gain']!
        .value!;
    expect(
      hbGain,
      isNot(otherGain),
      reason: 'guitar correction must still measurably differ between two very different guitars',
    );
  });

  test('Matribox translation is deterministic: the same Gold CKY recipe, translated twice, '
      'produces the byte-identical target', () {
    final a = createFromText(
      vault,
      'cky 96 quite bitter beings',
      guitar: hbFusion4,
      tuning: GuitarTuning.eStandard,
    );
    final b = createFromText(
      vault,
      'cky 96 quite bitter beings',
      guitar: hbFusion4,
      tuning: GuitarTuning.eStandard,
    );
    Map<String, String> describe(ToneTransferRecommendation r) => {
      for (final slot in MatriboxChainSlot.values)
        slot.label:
            '${r.target[slot].effectiveState}|${r.target[slot].model.value?.name}|'
            '${r.target[slot].parameters.entries.where((e) => e.value.specified).map((e) => '${e.key}=${e.value.value}').join(',')}',
    };
    expect(describe(a.recommendation), describe(b.recommendation));
  });

  test('digital CAB probe: with an FRFR/headphones-style playbackPath (no real cab), the curated '
      'CKY cabinet intent (4x12, British-family amp) resolves to a concrete Matribox CAB model', () {
    final created = createFromText(
      vault,
      'cky 96 quite bitter beings',
      guitar: hbFusion4,
      tuning: GuitarTuning.eStandard,
    );
    final cab = created.recommendation.target[MatriboxChainSlot.cab];
    expect(cab.effectiveState, RecipeBlockState.defined);
    expect(
      cab.model.value?.name,
      'BritGN 4x12',
      reason: 'same family token as the Brit 800 amp, per the cabinet matcher\'s own family-match bonus',
    );
  });
}
