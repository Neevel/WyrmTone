/// Builds the device-independent [CanonicalToneRecipe] from the existing
/// recommendation inputs.
///
/// Fallback hierarchy (a lower level only speaks where every higher level
/// is silent, and the source is preserved):
///
/// 1. USER_OVERRIDE (block overrides and session feedback corrections)
/// 2. SONG_PROFILE / ARTIST_PROFILE (the curated profile's stated values)
/// 3. GENRE_PROFILE (a small template, matched by genre + role)
/// 4. Generic CHARACTER interpretation of explicitly stated axes
/// 5. ROLE / TUNING / GUITAR corrections, applied AFTER the base values by
///    the existing [OfflineSoundEngine.adapt] rules
/// 6. DEFAULT_SAFE (a block nothing speaks about is deterministically OFF)
///
/// Device translation is NOT part of this file.
library;

import '../models/guitar_profile.dart';
import '../models/target_sound.dart';
import '../models/tone_target.dart';
import '../services/offline_sound_engine.dart';
import 'canonical_tone_recipe.dart';
import 'tone_intent.dart';
import 'tone_templates.dart';

/// Per-block user choice. It sits above every profile/template value and
/// below nothing except the device's own limits (applied by the translator).
class BlockOverride {
  const BlockOverride({this.state, this.kind, this.params = const {}});

  /// [RecipeBlockState.off], [RecipeBlockState.unchanged] or
  /// [RecipeBlockState.defined] (block ON).
  final RecipeBlockState? state;
  final Enum? kind;
  final Map<String, double> params;
}

class ToneOverrides {
  const ToneOverrides([this.blocks = const {}]);
  final Map<ToneBlockRole, BlockOverride> blocks;
}

abstract final class ToneRecipeBuilder {
  static const _neutralGuitarId = 'neutral';

  /// Character axes are absolute 0..100 descriptors. Fifty is the neutral
  /// point; influence grows linearly and is bounded by the existing ToneVault
  /// modifier semantics. Undefined dimensions are never invented.
  static ({Map<ToneDimension, int> values, Set<ToneDimension> changed})
  _interpretCharacter(
    Map<ToneDimension, int> input,
    Map<String, int> character,
  ) {
    final result = {...input};
    final changed = <ToneDimension>{};

    void apply(String axis, Map<ToneDimension, int> maximumDeltas) {
      final value = character[axis];
      if (value == null) return;
      final factor = (value.clamp(0, 100) - 50) / 50;
      for (final entry in maximumDeltas.entries) {
        final current = result[entry.key];
        if (current == null) continue;
        final delta = (entry.value * factor).round();
        if (delta == 0) continue;
        final next = (current + delta).clamp(0, 100);
        if (next != current) {
          result[entry.key] = next;
          changed.add(entry.key);
        }
      }
    }

    // Same relationships already used by ToneVault's warmer/colder modifier.
    apply('warmth', const {
      ToneDimension.treble: -8,
      ToneDimension.presence: -6,
      ToneDimension.lowMids: 4,
      ToneDimension.irBrightness: -6,
    });
    // Same relationships already used by ToneVault's dirtier/cleaner modifier.
    // This shapes the amp intent only; it never implies an explicit fuzz pedal.
    apply('fuzziness', const {
      ToneDimension.gain: 6,
      ToneDimension.saturation: 12,
      ToneDimension.tightness: -4,
    });
    return (
      values: Map.unmodifiable(result),
      changed: Set.unmodifiable(changed),
    );
  }

  static CanonicalToneRecipe build({
    required TargetSound profile,
    required GuitarProfile guitar,
    required GuitarTuning tuning,
    required SoundRole role,
    ToneTarget? finalTone,
    bool? cabEnabled,
    bool internalAmp = true,
    ToneOverrides overrides = const ToneOverrides(),
  }) {
    final base = profile.toneTarget!;
    const engine = OfflineSoundEngine();
    final profileOrigin = switch (profile.profileKind) {
      SoundProfileKind.song => ToneOrigin.songProfile,
      SoundProfileKind.artist => ToneOrigin.artistProfile,
      _ => ToneOrigin.genreProfile,
    };
    final template = profile.templateFallback
        ? ToneTemplates.match(profile.style, role)
        : null;
    final hints = base.kindHints;
    ToneOrigin hintOrigin(String slot) => hints.userSlots.contains(slot)
        ? ToneOrigin.userOverride
        : profileOrigin;

    // 1. base values: profile first, template only where the profile is silent
    final baseOrigin = <ToneDimension, ToneOrigin>{};
    final merged = <ToneDimension, int>{};
    for (final d in ToneDimension.values) {
      if (base.values.containsKey(d)) {
        merged[d] = base.values[d]!;
        baseOrigin[d] = profileOrigin;
      } else if (template?.dimensions.containsKey(d) ?? false) {
        merged[d] = template!.dimensions[d]!;
        baseOrigin[d] = ToneOrigin.genreProfile;
      }
    }
    final characterResult = _interpretCharacter(merged, base.character);
    for (final d in characterResult.changed) {
      baseOrigin[d] = ToneOrigin.characterInterpretation;
    }
    final mergedTarget = base.changed(characterResult.values);

    // 2. corrections after the base, attributed to the layer that changed a value
    final neutral = GuitarProfile(
      id: _neutralGuitarId,
      name: _neutralGuitarId,
      guitarType: guitar.guitarType,
      pickupType: PickupType.passiveHumbucker,
      outputLevel: OutputLevel.medium,
      toneCharacter: ToneCharacter.neutral,
      tuning: GuitarTuning.eStandard,
      playbackPath: guitar.playbackPath,
    );
    final roleOnly = engine
        .adapt(mergedTarget, neutral, GuitarTuning.eStandard, role)
        .$1;
    final roleTuning = engine.adapt(mergedTarget, neutral, tuning, role).$1;
    final full = engine.adapt(mergedTarget, guitar, tuning, role).$1;
    final engineOnly = engine.adapt(base, guitar, tuning, role).$1;

    final value = <ToneDimension, int>{};
    final origin = <ToneDimension, ToneOrigin>{};
    // explicit user wishes (modifiers/effects) come after the corrections and win
    final wishes = base.userAdjustments;
    final adjusted = wishes.isEmpty
        ? const <ToneDimension, int>{}
        : wishes.apply({
            for (final d in characterResult.values.keys) d: full[d],
          });
    final uncharacteredAdjusted = wishes.isEmpty
        ? const <ToneDimension, int>{}
        : wishes.apply({for (final d in merged.keys) d: engineOnly[d]});
    for (final d in wishes.absolute.keys) {
      baseOrigin.putIfAbsent(d, () => profileOrigin);
    }
    for (final d in {...characterResult.values.keys, ...wishes.absolute.keys}) {
      var v = adjusted[d] ?? full[d];
      ToneOrigin o;
      final expectedDraftValue = uncharacteredAdjusted[d] ?? engineOnly[d];
      if (finalTone != null && finalTone[d] != expectedDraftValue) {
        v = finalTone[d];
        o = ToneOrigin.userOverride; // confirmed session correction
      } else if (wishes.absolute.containsKey(d) ||
          (adjusted[d] != null && adjusted[d] != full[d])) {
        o = ToneOrigin.userOverride; // explicit user wish
      } else if (full[d] != roleTuning[d]) {
        o = ToneOrigin.guitarCorrection;
      } else if (roleTuning[d] != roleOnly[d]) {
        o = ToneOrigin.tuningCorrection;
      } else if (roleOnly[d] != mergedTarget[d]) {
        o = ToneOrigin.roleProfile;
      } else {
        o = baseOrigin[d]!;
      }
      value[d] = v;
      origin[d] = o;
    }
    bool has(ToneDimension d) => value.containsKey(d);

    /// Origin of a rule decision: the base origin if the base value already
    /// yields the same decision, otherwise the correction that flipped it.
    ToneOrigin decisionOrigin(ToneDimension d, bool Function(int) rule) =>
        rule(mergedTarget[d]) == rule(value[d]!) ? baseOrigin[d]! : origin[d]!;

    ToneDecision<double> level(ToneDimension d, String why) =>
        ToneDecision(value[d]!.toDouble(), origin[d]!, why);

    RecipeBlock off(ToneBlockRole r, ToneOrigin o, String why) => RecipeBlock(
      role: r,
      state: RecipeBlockState.off,
      stateOrigin: o,
      stateReason: why,
    );

    RecipeBlock silentOff(ToneBlockRole r, String what) => off(
      r,
      ToneOrigin.defaultSafe,
      'Weder Profil noch Template sagen etwas zu $what: deterministisch aus.',
    );

    final blocks = <ToneBlockRole, RecipeBlock>{};

    // FX1 = compressor position
    if (has(ToneDimension.compression)) {
      final v = value[ToneDimension.compression]!;
      final o = decisionOrigin(ToneDimension.compression, (x) => x >= 50);
      blocks[ToneBlockRole.fx1] = v >= 50
          ? RecipeBlock(
              role: ToneBlockRole.fx1,
              state: RecipeBlockState.defined,
              stateOrigin: o,
              stateReason:
                  'Kompression $v/100 >= 50: eigener Kompressor im Ziel.',
              kind: ToneDecision(
                PreAmpKind.compressor,
                o,
                'Kompression $v/100',
              ),
              params: {
                'amount': level(ToneDimension.compression, 'Kompression'),
              },
            )
          : off(
              ToneBlockRole.fx1,
              o,
              'Kompression $v/100 < 50: kein Kompressor-Pedal im Ziel '
              '(Verdichtung kommt vom Amp).',
            );
    } else {
      blocks[ToneBlockRole.fx1] = silentOff(ToneBlockRole.fx1, 'Kompression');
    }

    // FX2 = drive/boost position
    final driveKind = hints.drive ?? template?.driveKind;
    if (has(ToneDimension.tightness) || driveKind != null) {
      final tight = value[ToneDimension.tightness] ?? 0;
      final gainValue = value[ToneDimension.gain] ?? 0;
      final wantsBoost = tight >= 75 && gainValue >= 50;
      final kind =
          driveKind ?? (wantsBoost ? PreAmpKind.boost : PreAmpKind.none);
      final kindOrigin = hints.drive != null
          ? hintOrigin('drive')
          : ToneOrigin.genreProfile;
      final o = driveKind != null && driveKind != PreAmpKind.boost
          ? kindOrigin
          : has(ToneDimension.tightness)
          ? decisionOrigin(ToneDimension.tightness, (x) => x >= 75)
          : kindOrigin;
      if (kind == PreAmpKind.none ||
          (driveKind == PreAmpKind.boost &&
              !wantsBoost &&
              has(ToneDimension.tightness))) {
        blocks[ToneBlockRole.fx2] = off(
          ToneBlockRole.fx2,
          o,
          'Straffheit $tight/100 oder Gain $gainValue/100 unter der Boost-Schwelle: kein Drive-Pedal.',
        );
      } else {
        final why = driveKind != null && !wantsBoost
            ? (hints.drive != null
                  ? 'Profil: ${kind.name}.'
                  : 'Template ${template!.id}: ${kind.name}.')
            : 'Straffheit $tight/100 >= 75 und Gain $gainValue/100 >= 50: Boost vor dem Amp.';
        blocks[ToneBlockRole.fx2] = RecipeBlock(
          role: ToneBlockRole.fx2,
          state: RecipeBlockState.defined,
          stateOrigin: o,
          stateReason: why,
          kind: ToneDecision(kind, driveKind != null ? kindOrigin : o, why),
        );
      }
    } else {
      blocks[ToneBlockRole.fx2] = silentOff(
        ToneBlockRole.fx2,
        'Straffheit/Drive',
      );
    }

    // Gate
    if (has(ToneDimension.gateStrength)) {
      final s = value[ToneDimension.gateStrength]!;
      GateLevel band(int x) => x <= 0
          ? GateLevel.off
          : x <= 33
          ? GateLevel.light
          : x <= 66
          ? GateLevel.medium
          : GateLevel.strong;
      final o = decisionOrigin(
        ToneDimension.gateStrength,
        (x) => band(x) == band(s),
      );
      final gateLevel = band(s);
      if (gateLevel == GateLevel.off) {
        blocks[ToneBlockRole.gate] = off(
          ToneBlockRole.gate,
          o,
          'Gate-Stärke 0: kein Gate.',
        );
      } else {
        final params = <String, ToneDecision<double>>{
          'strength': level(ToneDimension.gateStrength, 'Gate-Stärke'),
          if (has(ToneDimension.gateOpening))
            'opening': level(ToneDimension.gateOpening, 'Gate-Öffnung'),
        };
        final prefs = <String, ToneDecision<String>>{};
        if (has(ToneDimension.gateOpening)) {
          final open = value[ToneDimension.gateOpening]!;
          final c = open >= 70
              ? GateCharacter.fast
              : (open <= 30 ? GateCharacter.slow : GateCharacter.natural);
          prefs['character'] = ToneDecision(
            c.name,
            origin[ToneDimension.gateOpening]!,
            'Öffnungsgeschwindigkeit $open/100',
          );
        }
        blocks[ToneBlockRole.gate] = RecipeBlock(
          role: ToneBlockRole.gate,
          state: RecipeBlockState.defined,
          stateOrigin: o,
          stateReason: 'Gate-Stärke $s/100 (${gateLevel.name}).',
          kind: ToneDecision(gateLevel, o, 'Gate-Stärke $s/100'),
          params: params,
          prefs: prefs,
        );
      }
    } else {
      blocks[ToneBlockRole.gate] = silentOff(ToneBlockRole.gate, 'Noise Gate');
    }

    // Amp
    if (!internalAmp) {
      blocks[ToneBlockRole.amp] = off(
        ToneBlockRole.amp,
        ToneOrigin.userOverride,
        'NAM ersetzt den internen Amp.',
      );
    } else if (has(ToneDimension.gain)) {
      final g = value[ToneDimension.gain]!;
      AmpCharacter bucket(int x) => x >= 60
          ? AmpCharacter.highGain
          : (x >= 35 ? AmpCharacter.crunch : AmpCharacter.clean);
      final o = decisionOrigin(
        ToneDimension.gain,
        (x) => bucket(x) == bucket(g),
      );
      const ampDims = {
        ToneDimension.gain: 'gain',
        ToneDimension.tightness: 'tightness',
        ToneDimension.saturation: 'saturation',
        ToneDimension.presence: 'presence',
        ToneDimension.bass: 'bass',
        ToneDimension.lowMids: 'lowMids',
        ToneDimension.mids: 'mids',
        ToneDimension.upperMids: 'upperMids',
        ToneDimension.treble: 'treble',
      };
      blocks[ToneBlockRole.amp] = RecipeBlock(
        role: ToneBlockRole.amp,
        state: RecipeBlockState.defined,
        stateOrigin: profileOrigin,
        stateReason: 'Interner Amp.',
        kind: ToneDecision(bucket(g), o, 'Gain $g/100 -> ${bucket(g).name}'),
        params: {
          for (final e in ampDims.entries)
            if (has(e.key)) e.value: level(e.key, e.value),
        },
        prefs: {
          if (base.ampFamilies.isNotEmpty)
            'ampFamilies': ToneDecision(
              base.ampFamilies.join(', '),
              profileOrigin,
              'Profil-Ampfamilie',
            ),
        },
      );
    } else {
      blocks[ToneBlockRole.amp] = RecipeBlock(
        role: ToneBlockRole.amp,
        state: RecipeBlockState.incomplete,
        stateOrigin: ToneOrigin.defaultSafe,
        stateReason: 'Kein Gain-Ziel: Amp-Charakter nicht bestimmbar.',
        incompleteReason: 'Weder Profil noch Template nennen den Gain.',
      );
    }

    // Cabinet
    final usesInternalCab = cabEnabled ?? !guitar.usesRealGuitarCab;
    if (!usesInternalCab) {
      blocks[ToneBlockRole.cab] = off(
        ToneBlockRole.cab,
        ToneOrigin.guitarCorrection,
        'Reale Gitarrenbox oder NAM mit Cabinet: keine zusätzliche CAB.',
      );
    } else {
      final config = switch (base.cabinet.toLowerCase()) {
        '1x12' => CabConfig.c1x12,
        '2x12' => CabConfig.c2x12,
        '4x12' => CabConfig.c4x12,
        _ => CabConfig.other,
      };
      blocks[ToneBlockRole.cab] = RecipeBlock(
        role: ToneBlockRole.cab,
        state: RecipeBlockState.defined,
        stateOrigin: ToneOrigin.guitarCorrection,
        stateReason: 'Interne CAB nötig (keine reale Gitarrenbox).',
        kind: ToneDecision(
          config,
          profileOrigin,
          'Profil: Cabinet ${base.cabinet}',
        ),
        prefs: {
          'speaker': ToneDecision(
            base.speaker,
            profileOrigin,
            'Profil: Speaker ${base.speaker}',
          ),
          'microphone': ToneDecision(
            base.microphone,
            profileOrigin,
            'Profil: Mikrofon ${base.microphone}',
          ),
        },
        params: {
          if (has(ToneDimension.irBrightness))
            'brightness': level(ToneDimension.irBrightness, 'IR-Helligkeit'),
        },
      );
    }

    // EQ: no dimension exists for it; nothing states an EQ target
    blocks[ToneBlockRole.eq] = silentOff(ToneBlockRole.eq, 'EQ');

    // Modulation
    if (has(ToneDimension.modulation)) {
      final v = value[ToneDimension.modulation]!;
      final o = decisionOrigin(ToneDimension.modulation, (x) => x > 0);
      blocks[ToneBlockRole.modulation] = v > 0
          ? RecipeBlock(
              role: ToneBlockRole.modulation,
              state: RecipeBlockState.defined,
              stateOrigin: o,
              stateReason: 'Modulation $v/100.',
              kind: hints.modulation != null
                  ? ToneDecision(
                      hints.modulation!,
                      hintOrigin('modulation'),
                      'Profil: ${hints.modulation!.name}',
                    )
                  : template?.modulationKind != null
                  ? ToneDecision(
                      template!.modulationKind!,
                      ToneOrigin.genreProfile,
                      'Template ${template.id}',
                    )
                  : const ToneDecision(
                      ModulationKind.chorus,
                      ToneOrigin.defaultSafe,
                      'Standardart Chorus',
                    ),
              params: {'amount': level(ToneDimension.modulation, 'Modulation')},
            )
          : off(ToneBlockRole.modulation, o, 'Modulation 0: keine Modulation.');
    } else {
      blocks[ToneBlockRole.modulation] = silentOff(
        ToneBlockRole.modulation,
        'Modulation',
      );
    }

    // Delay
    if (has(ToneDimension.delay)) {
      final v = value[ToneDimension.delay]!;
      final o = decisionOrigin(ToneDimension.delay, (x) => x > 0);
      blocks[ToneBlockRole.delay] = v > 0
          ? RecipeBlock(
              role: ToneBlockRole.delay,
              state: RecipeBlockState.defined,
              stateOrigin: o,
              stateReason: 'Delay $v/100.',
              kind: hints.delay != null
                  ? ToneDecision(
                      hints.delay!,
                      hintOrigin('delay'),
                      'Profil: ${hints.delay!.name}',
                    )
                  : template?.delayKind != null
                  ? ToneDecision(
                      template!.delayKind!,
                      ToneOrigin.genreProfile,
                      'Template ${template.id}',
                    )
                  : const ToneDecision(
                      DelayKind.digital,
                      ToneOrigin.defaultSafe,
                      'Standardart Digital',
                    ),
              params: {'amount': level(ToneDimension.delay, 'Delay')},
            )
          : off(ToneBlockRole.delay, o, 'Delay 0/100: trocken.');
    } else {
      blocks[ToneBlockRole.delay] = silentOff(ToneBlockRole.delay, 'Delay');
    }

    // Reverb: `amount` is an abstract room amount, never a device Mix
    if (has(ToneDimension.reverb)) {
      final v = value[ToneDimension.reverb]!;
      final o = decisionOrigin(ToneDimension.reverb, (x) => x > 0);
      blocks[ToneBlockRole.reverb] = v > 0
          ? RecipeBlock(
              role: ToneBlockRole.reverb,
              state: RecipeBlockState.defined,
              stateOrigin: o,
              stateReason: 'Hall $v/100.',
              kind: hints.reverb != null
                  ? ToneDecision(
                      hints.reverb!,
                      hintOrigin('reverb'),
                      'Profil: ${hints.reverb!.name}',
                    )
                  : template?.reverbKind != null
                  ? ToneDecision(
                      template!.reverbKind!,
                      ToneOrigin.genreProfile,
                      'Template ${template.id}',
                    )
                  : ToneDecision(
                      v <= 25 ? ReverbKind.room : ReverbKind.hall,
                      ToneOrigin.defaultSafe,
                      v <= 25 ? 'Wenig Hall: Raum' : 'Mehr Hall: Hall',
                    ),
              params: {'amount': level(ToneDimension.reverb, 'Hall')},
            )
          : off(ToneBlockRole.reverb, o, 'Hall 0/100: kein Hall.');
    } else {
      blocks[ToneBlockRole.reverb] = silentOff(ToneBlockRole.reverb, 'Hall');
    }

    // 3. user overrides on top
    for (final entry in overrides.blocks.entries) {
      blocks[entry.key] = _override(blocks[entry.key]!, entry.value);
    }

    return CanonicalToneRecipe(
      profileId: profile.id,
      artist: profile.artist,
      song: profile.song,
      guitarName: guitar.name,
      tuning: tuning.name,
      soundRole: role,
      blocks: blocks,
      character: {
        for (final entry in base.character.entries)
          entry.key: ToneDecision(
            entry.value.toDouble(),
            profileOrigin,
            'Klangcharakter ${entry.key} ${entry.value}/100',
          ),
      },
      templateId: template?.id,
    );
  }

  static RecipeBlock _override(RecipeBlock block, BlockOverride o) {
    const why = 'Nutzer-Override.';
    var result = block;
    if (o.kind != null) {
      result = result.copyWith(
        kind: ToneDecision(o.kind!, ToneOrigin.userOverride, why),
      );
    }
    if (o.params.isNotEmpty) {
      result = result.copyWith(
        params: {
          ...result.params,
          for (final e in o.params.entries)
            e.key: ToneDecision(e.value, ToneOrigin.userOverride, why),
        },
      );
    }
    if (o.state != null) {
      final wantsOn = o.state == RecipeBlockState.defined
          ? true
          : (o.state == RecipeBlockState.off ? false : null);
      final resolved = resolveBlockState(
        wantsOn: wantsOn,
        kindKnown: result.kind != null,
        explicitUnchanged: o.state == RecipeBlockState.unchanged,
      );
      result = result.copyWith(
        state: resolved,
        stateOrigin: ToneOrigin.userOverride,
        stateReason: resolved == RecipeBlockState.incomplete
            ? 'Nutzer schaltet den Block ein, aber es gibt keine Art/Modell-Angabe.'
            : why,
        incompleteReason: resolved == RecipeBlockState.incomplete
            ? 'Block ON ohne Art.'
            : null,
      );
    }
    return result;
  }
}
