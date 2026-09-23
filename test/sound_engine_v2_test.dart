import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/models/target_sound.dart';
import 'package:wyrmtone/models/tone_target.dart';
import 'package:wyrmtone/presets/canonical_tone_recipe.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_model_library.dart';
import 'package:wyrmtone/presets/matribox_model_matcher.dart';
import 'package:wyrmtone/presets/matribox_target_preset.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_plan.dart';
import 'package:wyrmtone/presets/matribox_tone_translator.dart';
import 'package:wyrmtone/presets/tone_intent.dart';
import 'package:wyrmtone/presets/tone_recipe_builder.dart';

import 'support/matribox_tone_transfer_support.dart';

TargetSound profileWith({
  SoundProfileKind kind = SoundProfileKind.genre,
  String style = 'Melodic Death Metal',
  Map<ToneDimension, int> tone = const {},
  List<String> families = const [],
  Map<String, int> character = const {},
  ToneUserAdjustments adjustments = const ToneUserAdjustments(),
  ToneKindHints kindHints = const ToneKindHints(),
}) => TargetSound(
  id: 't',
  artist: 'Artist',
  song: 'Song Title',
  style: style,
  referenceTuning: GuitarTuning.dStandard,
  gain: 50,
  tightness: 50,
  brightness: 50,
  bassAmount: 50,
  midCharacter: 'x',
  dynamics: 'x',
  ampStyle: 'x',
  cabinetStyle: 'x',
  effects: const [],
  ampModel: 'x',
  baseParameters: const {},
  confirmedFacts: const [],
  approximations: const [],
  profileKind: kind,
  toneTarget: ToneTarget(
    values: tone,
    profileId: 't',
    version: 1,
    source: 's',
    confidence: 50,
    reason: 'r',
    ampFamilies: families,
    character: character,
    kindHints: kindHints,
    userAdjustments: adjustments,
    cabinet: '4x12',
    speaker: 'V30',
    microphone: 'SM57',
  ),
);

CanonicalToneRecipe recipeFor(
  TargetSound profile, {
  GuitarProfile guitar = hbFusion4,
  GuitarTuning tuning = GuitarTuning.eStandard,
  SoundRole role = SoundRole.rhythm,
  ToneOverrides overrides = const ToneOverrides(),
  ToneTarget? finalTone,
}) => ToneRecipeBuilder.build(
  profile: profile,
  guitar: guitar,
  tuning: tuning,
  role: role,
  overrides: overrides,
  finalTone: finalTone,
);

String describe(CanonicalToneRecipe r) => jsonEncode([
  r.templateId,
  for (final role in ToneBlockRole.values)
    [
      role.name,
      r[role].state.name,
      r[role].stateOrigin.label,
      r[role].kind?.value.name,
      {
        for (final e in r[role].params.entries)
          e.key: [e.value.value, e.value.origin.label],
      },
      {for (final e in r[role].prefs.entries) e.key: e.value.value},
    ],
]);

String describeTarget(MatriboxTargetPreset t) => jsonEncode(t.toJson());

void main() {
  final library = MatriboxModelLibrary.fromVendor(toneCatalog);

  MatriboxTargetPreset translate(
    CanonicalToneRecipe r, {
    DeviceModelOverrides? models,
  }) => MatriboxToneTranslator.translate(
    recipe: r,
    library: library,
    modelOverrides: models ?? const DeviceModelOverrides(),
  );

  MatriboxToneTransferPlan planOf(MatriboxTargetPreset target, {current}) =>
      MatriboxToneTransferPlan.build(
        current: current ?? beforeLayout(),
        target: target,
        ledger: certifiedLedger,
        backupSha256: 'abc',
        presetNumber: 1,
        isUserBank: true,
        transportAvailable: true,
        library: library,
      );

  group('block state semantics (central)', () {
    test('OFF needs no model, ON needs a kind, UNCHANGED only when explicit, silence is not UNCHANGED', () {
      expect(
        resolveBlockState(wantsOn: false, kindKnown: false),
        RecipeBlockState.off,
      );
      expect(
        resolveBlockState(wantsOn: true, kindKnown: true),
        RecipeBlockState.defined,
      );
      expect(
        resolveBlockState(wantsOn: true, kindKnown: false),
        RecipeBlockState.incomplete,
      );
      expect(
        resolveBlockState(wantsOn: null, kindKnown: false),
        RecipeBlockState.incomplete,
      );
      expect(
        resolveBlockState(
          wantsOn: true,
          kindKnown: false,
          explicitUnchanged: true,
        ),
        RecipeBlockState.unchanged,
      );
    });

    test('a target block that should be ON without a model is INCOMPLETE, OFF without a model is complete', () {
      TargetValue<bool> b(bool v) =>
          TargetValue(v, ToneOrigin.songProfile, 't');
      expect(
        MatriboxTargetBlock(
          slot: MatriboxChainSlot.fx2,
          enabled: b(true),
        ).effectiveState,
        RecipeBlockState.incomplete,
      );
      expect(
        MatriboxTargetBlock(
          slot: MatriboxChainSlot.rvb,
          enabled: b(true),
        ).effectiveState,
        RecipeBlockState.incomplete,
      );
      expect(
        MatriboxTargetBlock(
          slot: MatriboxChainSlot.dly,
          enabled: b(false),
        ).effectiveState,
        RecipeBlockState.off,
      );
      expect(
        MatriboxTargetBlock(
          slot: MatriboxChainSlot.fx1,
          state: RecipeBlockState.unchanged,
        ).effectiveState,
        RecipeBlockState.unchanged,
      );
    });
  });

  group('fallback hierarchy and corrections', () {
    test('a specific profile beats the genre template', () {
      // template melodic_death_metal_rhythm says reverb 5; the song profile says 30
      final r = recipeFor(
        profileWith(
          kind: SoundProfileKind.song,
          tone: {ToneDimension.reverb: 30, ToneDimension.gain: 68},
        ),
      );
      expect(r.templateId, 'melodic_death_metal_rhythm');
      expect(
        r[ToneBlockRole.reverb].params['amount']!.value,
        26,
      ); // 30 -4 (rhythm), not 5
      expect(
        r[ToneBlockRole.reverb].params['amount']!.origin,
        ToneOrigin.roleProfile,
      );
      expect(
        r[ToneBlockRole.reverb].kind!.origin,
        ToneOrigin.genreProfile,
      ); // kind: profile silent -> template
    });

    test('the genre template fills what the profile leaves out, with GENRE_PROFILE as source', () {
      final r = recipeFor(profileWith(tone: {ToneDimension.gain: 70}));
      final gate = r[ToneBlockRole.gate];
      expect(gate.state, RecipeBlockState.defined);
      expect(
        (gate.kind!.value as GateLevel),
        GateLevel.medium,
      ); // template gateStrength 50
      expect(gate.kind!.origin, ToneOrigin.genreProfile);
      expect(
        r[ToneBlockRole.fx2].kind!.value,
        PreAmpKind.boost,
      ); // template drive kind
      expect(r[ToneBlockRole.fx2].stateOrigin, ToneOrigin.genreProfile);
    });

    test('without any statement a block is deterministically OFF (DEFAULT_SAFE), never UNCHANGED', () {
      final r = recipeFor(
        profileWith(style: 'Polka', tone: {ToneDimension.gain: 30}),
      );
      expect(r.templateId, isNull);
      for (final role in [
        ToneBlockRole.fx1,
        ToneBlockRole.fx2,
        ToneBlockRole.gate,
        ToneBlockRole.eq,
        ToneBlockRole.modulation,
        ToneBlockRole.delay,
        ToneBlockRole.reverb,
      ]) {
        expect(r[role].state, RecipeBlockState.off, reason: role.name);
        expect(r[role].stateOrigin, ToneOrigin.defaultSafe, reason: role.name);
      }
    });

    test('guitar and tuning corrections apply AFTER the base and keep their own source', () {
      final profile = profileWith(
        kind: SoundProfileKind.song,
        tone: {
          ToneDimension.gain: 68,
          ToneDimension.bass: 48,
          ToneDimension.tightness: 70,
        },
      );
      final plain = recipeFor(profile);
      expect(plain[ToneBlockRole.amp].params['bass']!.value, 48);
      expect(
        plain[ToneBlockRole.amp].params['bass']!.origin,
        ToneOrigin.songProfile,
      );
      final dropC = recipeFor(profile, tuning: GuitarTuning.dropC);
      expect(dropC[ToneBlockRole.amp].params['bass']!.value, 41);
      expect(
        dropC[ToneBlockRole.amp].params['bass']!.origin,
        ToneOrigin.tuningCorrection,
      );
      expect(dropC[ToneBlockRole.amp].params['tightness']!.value, 76);
      const active = GuitarProfile(
        id: 'a',
        name: 'Active',
        guitarType: GuitarType.superstrat,
        pickupType: PickupType.activeHumbucker,
        outputLevel: OutputLevel.high,
        toneCharacter: ToneCharacter.neutral,
        tuning: GuitarTuning.eStandard,
        playbackPath: PlaybackPath.headphones,
      );
      final hot = recipeFor(profile, guitar: active);
      expect(hot[ToneBlockRole.amp].params['gain']!.value, 63);
      expect(
        hot[ToneBlockRole.amp].params['gain']!.origin,
        ToneOrigin.guitarCorrection,
      );
    });

    test('user overrides win over profile, template and corrections', () {
      final profile = profileWith(
        kind: SoundProfileKind.song,
        tone: {ToneDimension.gain: 68, ToneDimension.delay: 0},
      );
      final r = recipeFor(
        profile,
        tuning: GuitarTuning.dropC,
        overrides: const ToneOverrides({
          ToneBlockRole.amp: BlockOverride(params: {'gain': 40}),
          ToneBlockRole.delay: BlockOverride(
            state: RecipeBlockState.defined,
            kind: DelayKind.tape,
          ),
          ToneBlockRole.reverb: BlockOverride(state: RecipeBlockState.off),
        }),
      );
      expect(r[ToneBlockRole.amp].params['gain']!.value, 40);
      expect(
        r[ToneBlockRole.amp].params['gain']!.origin,
        ToneOrigin.userOverride,
      );
      expect(r[ToneBlockRole.delay].state, RecipeBlockState.defined);
      expect(r[ToneBlockRole.delay].stateOrigin, ToneOrigin.userOverride);
      expect(r[ToneBlockRole.reverb].state, RecipeBlockState.off);
      expect(r[ToneBlockRole.reverb].stateOrigin, ToneOrigin.userOverride);
      // a confirmed session correction is a USER_OVERRIDE, too
      final corrected = ToneTarget(
        values: {...profile.toneTarget!.values, ToneDimension.gain: 60},
        profileId: 't',
        version: 1,
        source: 's',
        confidence: 50,
        reason: 'r',
      );
      final viaFeedback = recipeFor(profile, finalTone: corrected);
      expect(
        viaFeedback[ToneBlockRole.amp].params['gain']!.origin,
        ToneOrigin.userOverride,
      );
    });

    test(
      'ON without kind intent is INCOMPLETE; explicit UNCHANGED is allowed',
      () {
        final r = recipeFor(
          profileWith(
            kind: SoundProfileKind.song,
            tone: {ToneDimension.gain: 68, ToneDimension.delay: 0},
          ),
          overrides: const ToneOverrides({
            ToneBlockRole.eq: BlockOverride(state: RecipeBlockState.defined),
            ToneBlockRole.fx1: BlockOverride(state: RecipeBlockState.unchanged),
          }),
        );
        expect(r[ToneBlockRole.eq].state, RecipeBlockState.incomplete);
        expect(r.incomplete.map((b) => b.role), [ToneBlockRole.eq]);
        expect(r[ToneBlockRole.fx1].state, RecipeBlockState.unchanged);
      },
    );
  });

  group('character interpretation and precedence', () {
    const baseTone = {
      ToneDimension.gain: 50,
      ToneDimension.saturation: 50,
      ToneDimension.tightness: 50,
      ToneDimension.bass: 50,
      ToneDimension.lowMids: 50,
      ToneDimension.mids: 50,
      ToneDimension.upperMids: 50,
      ToneDimension.treble: 50,
      ToneDimension.presence: 50,
      ToneDimension.irBrightness: 50,
    };

    CanonicalToneRecipe characterRecipe({
      required int warmth,
      required int fuzziness,
      ToneUserAdjustments adjustments = const ToneUserAdjustments(),
    }) => recipeFor(
      profileWith(
        kind: SoundProfileKind.song,
        tone: baseTone,
        character: {'warmth': warmth, 'fuzziness': fuzziness},
        adjustments: adjustments,
      ),
    );

    double amp(CanonicalToneRecipe recipe, String key) =>
        recipe[ToneBlockRole.amp].params[key]!.value;

    test('warmth and fuzziness are deterministic, bounded and monotonic around neutral', () {
      final low = characterRecipe(warmth: 0, fuzziness: 0);
      final neutral = characterRecipe(warmth: 50, fuzziness: 50);
      final high = characterRecipe(warmth: 100, fuzziness: 100);

      expect([
        amp(low, 'treble'),
        amp(neutral, 'treble'),
        amp(high, 'treble'),
      ], orderedEquals([58, 50, 42]));
      expect([
        amp(low, 'presence'),
        amp(neutral, 'presence'),
        amp(high, 'presence'),
      ], orderedEquals([56, 50, 44]));
      expect([
        amp(low, 'gain'),
        amp(neutral, 'gain'),
        amp(high, 'gain'),
      ], orderedEquals([44, 50, 56]));
      expect([
        amp(low, 'tightness'),
        amp(neutral, 'tightness'),
        amp(high, 'tightness'),
      ], orderedEquals([54, 50, 46]));
      expect(
        high[ToneBlockRole.fx2].state,
        RecipeBlockState.off,
        reason: 'fuzziness is not an explicit fuzz/drive effect intent',
      );

      final a = translate(high);
      final b = translate(characterRecipe(warmth: 100, fuzziness: 100));
      expect(describeTarget(a), describeTarget(b));

      final bounded = characterRecipe(warmth: 100, fuzziness: 100);
      for (final value in bounded[ToneBlockRole.amp].params.values) {
        expect(value.value, inInclusiveRange(0, 100));
      }
    });

    test('small character changes do not oscillate models or effects', () {
      final outputs = [
        for (final value in [49, 50, 51])
          translate(characterRecipe(warmth: value, fuzziness: value)),
      ];
      expect(
        outputs.map((t) => t[MatriboxChainSlot.amp].model.value!.name).toSet(),
        hasLength(1),
      );
      expect(
        outputs.map((t) => t[MatriboxChainSlot.fx2].effectiveState).toSet(),
        {RecipeBlockState.off},
      );
    });

    test(
      'explicit gain and treble user values win over character interpretation',
      () {
        final recipe = characterRecipe(
          warmth: 100,
          fuzziness: 100,
          adjustments: const ToneUserAdjustments(
            absolute: {ToneDimension.gain: 42, ToneDimension.treble: 44},
          ),
        );
        expect(amp(recipe, 'gain'), 42);
        expect(amp(recipe, 'treble'), 44);
        expect(
          recipe[ToneBlockRole.amp].params['gain']!.origin,
          ToneOrigin.userOverride,
        );
        expect(
          recipe[ToneBlockRole.amp].params['treble']!.origin,
          ToneOrigin.userOverride,
        );
      },
    );

    test('tightness boost rule remains the existing hard threshold at 75 with gain at least 50', () {
      RecipeBlock fx2(int tightness, int gain) => recipeFor(
        profileWith(
          kind: SoundProfileKind.song,
          tone: {ToneDimension.gain: gain, ToneDimension.tightness: tightness},
        ),
      )[ToneBlockRole.fx2];

      expect(fx2(74, 60).state, RecipeBlockState.off);
      expect(fx2(75, 60).kind?.value, PreAmpKind.boost);
      expect(fx2(76, 60).kind?.value, PreAmpKind.boost);
      expect(fx2(75, 49).state, RecipeBlockState.off);
    });

    test('IR brightness low neutral high is preserved but honestly reported as unrepresented', () {
      MatriboxTargetPreset target(int brightness) => translate(
        recipeFor(
          profileWith(
            kind: SoundProfileKind.song,
            tone: {
              ToneDimension.gain: 50,
              ToneDimension.tightness: 50,
              ToneDimension.irBrightness: brightness,
            },
          ),
        ),
      );
      final outputs = [target(0), target(50), target(100)];
      expect(
        outputs.map((t) => t[MatriboxChainSlot.cab].model.value!.name).toSet(),
        hasLength(1),
      );
      for (final output in outputs) {
        expect(
          output[MatriboxChainSlot.cab].report!.notRepresented.join(' '),
          contains('brightness'),
        );
      }
    });
  });

  group('device translation V2', () {
    test('explicit generic octave intent uses the normal FX2 matcher; absence and user OFF stay off', () {
      final profile = profileWith(
        kind: SoundProfileKind.song,
        tone: const {ToneDimension.gain: 60, ToneDimension.tightness: 60},
        kindHints: const ToneKindHints(drive: PreAmpKind.octave),
      );
      final recipe = recipeFor(profile);
      expect(recipe[ToneBlockRole.fx1].state, RecipeBlockState.off);
      expect(recipe[ToneBlockRole.fx2].state, RecipeBlockState.defined);
      expect(recipe[ToneBlockRole.fx2].kind?.value, PreAmpKind.octave);
      expect(recipe[ToneBlockRole.fx2].kind?.origin, ToneOrigin.songProfile);

      final first = translate(recipe);
      final second = translate(recipe);
      final octave = first[MatriboxChainSlot.fx2];
      expect(octave.model.value?.name, 'Octaver');
      expect(octave.model.value?.code, 0x01000021);
      expect(octave.model.value?.selectEvidence.name, 'observed');
      expect(octave.model.value!.algorithm.parameters.map((p) => p.name), [
        'L-OCT',
        'H-OCT',
        'Dry',
      ]);
      expect(octave.model.value!.algorithm.parameters.map((p) => p.wireIndex), [
        0,
        1,
        2,
      ]);
      expect(
        octave.model.value!.algorithm.parameters.map((p) => p.defaultValue),
        [50, 50, 50],
      );
      expect(
        octave.parameters,
        isEmpty,
        reason: 'catalog labels alone do not justify invented musical values',
      );
      expect(describeTarget(first), describeTarget(second));

      final absent = translate(
        recipeFor(
          profileWith(
            kind: SoundProfileKind.song,
            tone: const {ToneDimension.gain: 60, ToneDimension.tightness: 60},
          ),
        ),
      );
      expect(
        absent[MatriboxChainSlot.fx2].effectiveState,
        RecipeBlockState.off,
      );
      expect(absent[MatriboxChainSlot.fx2].model.specified, isFalse);

      final disabled = recipeFor(
        profile,
        overrides: const ToneOverrides({
          ToneBlockRole.fx2: BlockOverride(state: RecipeBlockState.off),
        }),
      );
      expect(disabled[ToneBlockRole.fx2].state, RecipeBlockState.off);
      expect(disabled[ToneBlockRole.fx2].stateOrigin, ToneOrigin.userOverride);
    });

    test('Angels Dont Kill recipe and target are deterministic', () {
      final a = angelsRecommendation();
      final b = angelsRecommendation();
      expect(describe(a.recipe), describe(b.recipe));
      expect(describeTarget(a.target), describeTarget(b.target));
    });

    test('Angels recipe: all nine blocks with state, kind and source', () {
      final r = angelsRecommendation().recipe;
      expect(r.templateId, 'melodic_death_metal_rhythm');
      String s(ToneBlockRole role) =>
          '${r[role].state.name}/${r[role].stateOrigin.label}/${r[role].kind?.value.name}';
      expect(
        s(ToneBlockRole.fx1),
        'off/SONG_PROFILE/null',
      ); // compression 30 < 50
      expect(s(ToneBlockRole.fx2), 'defined/SONG_PROFILE/boost');
      expect(s(ToneBlockRole.gate), 'defined/SONG_PROFILE/medium');
      expect(s(ToneBlockRole.amp), 'defined/SONG_PROFILE/highGain');
      expect(s(ToneBlockRole.cab), 'defined/GUITAR_CORRECTION/c4x12');
      expect(s(ToneBlockRole.eq), 'off/DEFAULT_SAFE/null');
      expect(s(ToneBlockRole.modulation), 'off/SONG_PROFILE/null');
      expect(s(ToneBlockRole.delay), 'off/SONG_PROFILE/null');
      expect(s(ToneBlockRole.reverb), 'defined/SONG_PROFILE/room');
      expect(
        r[ToneBlockRole.amp].params['tightness']!.origin,
        ToneOrigin.tuningCorrection,
      );
      expect(
        r[ToneBlockRole.reverb].params['amount']!.value,
        4,
      ); // abstract amount, not a device value
      // the recipe carries no device knowledge
      final text = describe(r).toLowerCase();
      for (final banned in ['sol 100', 'boost', '0x', 'wire', 'gate 2']) {
        if (banned == 'boost') continue; // a musical kind (PreAmpKind.boost)
        expect(text, isNot(contains(banned)), reason: banned);
      }
    });

    test('Angels Matribox target: a model for every active block; OFF blocks need none', () {
      final rec = angelsRecommendation();
      String model(MatriboxChainSlot s) =>
          rec.target[s].model.value?.name ?? '-';
      expect(model(MatriboxChainSlot.fx2), 'Boost');
      expect(
        model(MatriboxChainSlot.amp),
        'Sol 100 OD',
      ); // same pick as the existing engine
      expect(model(MatriboxChainSlot.nr), 'Gate 2');
      expect(model(MatriboxChainSlot.cab), 'Sol 4x12');
      expect(model(MatriboxChainSlot.rvb), 'Room');
      for (final slot in [
        MatriboxChainSlot.fx1,
        MatriboxChainSlot.eq,
        MatriboxChainSlot.mod,
        MatriboxChainSlot.dly,
      ]) {
        expect(rec.target[slot].effectiveState, RecipeBlockState.off);
        expect(model(slot), '-');
      }
      final draftAmp = rec.draft.blocks
          .firstWhere((b) => b.slot == 'AMP')
          .model;
      expect(model(MatriboxChainSlot.amp), draftAmp);
      for (final slot in MatriboxChainSlot.values) {
        expect(
          rec.target[slot].effectiveState,
          isNot(RecipeBlockState.incomplete),
          reason: slot.label,
        );
      }
    });

    test('Angels approximation report per block; nothing is claimed that the catalog cannot show', () {
      final t = angelsRecommendation().target;
      ApproximationQuality q(MatriboxChainSlot s) => t[s].report!.quality;
      expect(
        q(MatriboxChainSlot.amp),
        ApproximationQuality.limitedApproximation,
      );
      expect(q(MatriboxChainSlot.fx2), ApproximationQuality.goodApproximation);
      expect(
        q(MatriboxChainSlot.nr),
        ApproximationQuality.limitedApproximation,
      );
      expect(
        q(MatriboxChainSlot.cab),
        ApproximationQuality.limitedApproximation,
      );
      expect(
        q(MatriboxChainSlot.rvb),
        ApproximationQuality.limitedApproximation,
      );
      expect(q(MatriboxChainSlot.eq), ApproximationQuality.direct);
      final cab = t[MatriboxChainSlot.cab].report!.notRepresented.join(' ');
      expect(
        cab,
        allOf(contains('V30'), contains('SM57')),
      ); // not claimed as matched
      final amp = t[MatriboxChainSlot.amp].report!.notRepresented.join(' ');
      expect(
        amp,
        allOf(
          contains('saturation'),
          contains('lowMids'),
          contains('upperMids'),
        ),
      );
      expect(
        t[MatriboxChainSlot.nr].report!.notRepresented.join(' '),
        contains('keine belegte Abbildungsregel'),
      );
      // abstract reverb amount is NOT Mix, gate strength is NOT THRE
      expect(t[MatriboxChainSlot.rvb].parameters, isEmpty);
      expect(t[MatriboxChainSlot.nr].parameters, isEmpty);
      expect(t[MatriboxChainSlot.amp].parameters.keys, [
        'gain',
        'presence',
        'bass',
        'middle',
        'treble',
      ]);
    });

    test('model selection is deterministic: repeated runs, ranked reasons, ties by catalog order', () {
      final a = MatriboxModelMatcher.amp(
        library,
        gain: 68,
        tightness: 90,
        mids: 60,
        families: 'british, high gain',
      );
      final b = MatriboxModelMatcher.amp(
        library,
        gain: 68,
        tightness: 90,
        mids: 60,
        families: 'british, high gain',
      );
      expect(
        a.ranked.map((c) => c.model.name),
        b.ranked.map((c) => c.model.name),
      );
      expect(a.selected!.model.name, 'Sol 100 OD');
      expect(a.selected!.reasons, isNotEmpty);
      // clean intent selects a clean amp, not the high-gain one
      final clean = MatriboxModelMatcher.amp(
        library,
        gain: 20,
        tightness: 40,
        mids: 50,
      );
      expect(clean.selected!.model.name, 'Calif Star CL');
      // equal scores: the model earlier in the catalog wins
      final tie = MatriboxModelMatcher.byTag(
        library,
        MatriboxChainSlot.mod,
        'chorus',
      );
      expect(tie.ranked.map((c) => c.model.name), ['Chorus A', 'Chorus B']);
    });

    test('an amp choice also drives the cabinet family; a user model override sits above scoring', () {
      final r = recipeFor(
        profileWith(
          kind: SoundProfileKind.song,
          tone: {ToneDimension.gain: 68, ToneDimension.tightness: 78},
        ),
      );
      expect(translate(r)[MatriboxChainSlot.cab].model.value!.name, 'Sol 4x12');
      final over = translate(
        r,
        models: const DeviceModelOverrides({
          ToneBlockRole.amp: 'Brit 800',
          ToneBlockRole.cab: 'BritGN 4x12',
        }),
      );
      expect(over[MatriboxChainSlot.amp].model.value!.name, 'Brit 800');
      expect(over[MatriboxChainSlot.amp].model.origin, ToneOrigin.userOverride);
      expect(over[MatriboxChainSlot.cab].model.value!.name, 'BritGN 4x12');
      final missing = translate(
        r,
        models: const DeviceModelOverrides({ToneBlockRole.amp: 'Not A Model'}),
      );
      expect(
        missing[MatriboxChainSlot.amp].effectiveState,
        RecipeBlockState.incomplete,
      );
    });

    test(
      'a block without a matching tagged model is INCOMPLETE, never a guess',
      () {
        final r = recipeFor(
          profileWith(
            kind: SoundProfileKind.song,
            tone: {ToneDimension.gain: 68, ToneDimension.modulation: 0},
          ),
          overrides: const ToneOverrides({
            ToneBlockRole.modulation: BlockOverride(
              state: RecipeBlockState.defined,
              kind: ModulationKind.rotary,
            ),
          }),
        );
        final t = translate(r)[MatriboxChainSlot.mod];
        expect(t.effectiveState, RecipeBlockState.incomplete);
        expect(t.report!.quality, ApproximationQuality.unsupported);
        final plan = planOf(translate(r));
        expect(plan.summary.incomplete, 1);
        // a non-amp gap is listed but no longer blocks the plan by itself; a missing AMP model does
        expect(plan.blockers.join(), isNot(contains('INCOMPLETE_TARGET')));
        final ampMissing = planOf(
          translate(
            r,
            models: const DeviceModelOverrides({
              ToneBlockRole.amp: 'Not A Model',
            }),
          ),
        );
        expect(ampMissing.overall, ToneTransferOverall.blocked);
        expect(ampMissing.blockers.join(), contains('INCOMPLETE_TARGET'));
      },
    );
  });

  group('parameter mapping (range, type, sign, flag)', () {
    CanonicalToneRecipe custom(Map<ToneBlockRole, RecipeBlock> blocks) {
      final base = recipeFor(
        profileWith(
          kind: SoundProfileKind.song,
          tone: {ToneDimension.gain: 68},
        ),
      );
      var r = base;
      for (final b in blocks.values) {
        r = r.withBlock(b);
      }
      return r;
    }

    RecipeBlock defined(
      ToneBlockRole role,
      Enum kind,
      Map<String, double> params,
    ) => RecipeBlock(
      role: role,
      state: RecipeBlockState.defined,
      stateOrigin: ToneOrigin.userOverride,
      stateReason: 'test',
      kind: ToneDecision(kind, ToneOrigin.userOverride, 'test'),
      params: {
        for (final e in params.entries)
          e.key: ToneDecision(e.value, ToneOrigin.userOverride, 'test'),
      },
    );

    test(
      'EQ shaping supports negative values and stays inside the catalog range',
      () {
        final t = translate(
          custom({
            ToneBlockRole.eq: defined(
              ToneBlockRole.eq,
              ToneOrigin.userOverride,
              {'low': -100, 'lowMid': -20, 'high': 60, 'level': 50},
            ),
          }),
        )[MatriboxChainSlot.eq];
        expect(t.model.value!.name, 'Guitar EQ');
        expect(t.parameters['125hz']!.value, -50);
        expect(t.parameters['400hz']!.value, -10);
        expect(t.parameters['4khz']!.value, 30);
        expect(t.parameters['volume']!.value, 50); // 0..99 linear, 49.5 -> 50
        final plan = planOf(MatriboxToneTransferPlan_targetOf(t));
        expect(
          plan.entries
              .where((e) => e.subject == '125hz' && e.isChange)
              .single
              .target,
          '-50',
        );
      },
    );

    test('flags and time targets honour catalog type and range (Sweep: Time 20..4000, switches 0/1)', () {
      final t = translate(
        custom({
          ToneBlockRole.delay: defined(
            ToneBlockRole.delay,
            DelayKind.modulated,
            {'mix': 100, 'time': 9000, 'sync': 1, 'trail': 0, 'feedback': 40},
          ),
        }),
      )[MatriboxChainSlot.dly];
      expect(t.model.value!.name, 'Sweep');
      expect(t.parameters['mix']!.value, 99);
      expect(
        t.parameters['time']!.value,
        4000,
      ); // clamped to the catalog maximum
      expect(t.parameters['timesync']!.value, 1);
      expect(t.parameters['trail']!.value, 0);
      expect(t.parameters['feedback']!.value, 40);
    });

    test('decimal parameters keep their step (Flanger rate 0.1..10)', () {
      final t = translate(
        custom({
          ToneBlockRole.modulation: defined(
            ToneBlockRole.modulation,
            ModulationKind.flanger,
            {'rate': 37, 'depth': 50},
          ),
        }),
      )[MatriboxChainSlot.mod];
      expect(t.parameters['rate']!.value, 3.8); // 0.1 + 0.37*9.9 = 3.763 -> 3.8
      expect(t.parameters['depth']!.value, 50);
    });

    test('a semantic parameter without a rule or without a model parameter stays visible', () {
      final t = translate(
        custom({
          ToneBlockRole.reverb: defined(
            ToneBlockRole.reverb,
            ReverbKind.plate,
            {'amount': 40, 'mix': 25, 'shimmer': 70},
          ),
        }),
      )[MatriboxChainSlot.rvb];
      expect(t.model.value!.name, 'Plate');
      expect(t.parameters.keys, [
        'mix',
      ]); // only the explicit device-oriented mix
      final gaps = t.report!.notRepresented.join(' ');
      expect(gaps, contains('amount 40/100'));
      expect(gaps, contains('shimmer 70/100'));
      expect(t.report!.quality, ApproximationQuality.limitedApproximation);
      // an amp override whose model lacks the knob: presence has no parameter there
      final amp = translate(
        custom({}),
        models: const DeviceModelOverrides({ToneBlockRole.amp: 'TWD Deluxe'}),
      )[MatriboxChainSlot.amp];
      expect(
        amp.report!.notRepresented.join(' '),
        contains('TWD Deluxe hat keinen Parameter'),
      );
    });
  });

  group('current preset never defines the target', () {
    test('the same request against different P01 states gives the SAME target and a different DIFF', () {
      final target = angelsRecommendation().target;
      final other = beforeLayoutWithAmp(0x07000035); // AMP currently Brit 800
      final a = planOf(target);
      final b = planOf(target, current: other);
      expect(
        describeTarget(target),
        describeTarget(angelsRecommendation().target),
      );
      String ampModel(MatriboxToneTransferPlan p) => p.entries
          .firstWhere(
            (e) => e.slot == MatriboxChainSlot.amp && e.subject == 'MODEL',
          )
          .intended
          .name;
      expect(ampModel(a), 'noChange');
      expect(ampModel(b), 'selectModel');
      expect(
        a.summary.modelsChanged + a.summary.blocked,
        isNot(b.summary.modelsChanged + b.summary.blocked),
      );
    });

    test('an UNCHANGED block leaves the device alone; the current model is never reused for an ON block', () {
      final r = recipeFor(
        profileWith(
          kind: SoundProfileKind.song,
          tone: {ToneDimension.gain: 68, ToneDimension.delay: 0},
        ),
        overrides: const ToneOverrides({
          ToneBlockRole.fx1: BlockOverride(state: RecipeBlockState.unchanged),
        }),
      );
      final target = translate(r);
      expect(
        target[MatriboxChainSlot.fx1].effectiveState,
        RecipeBlockState.unchanged,
      );
      final plan = planOf(target);
      expect(
        plan.entries
            .where((e) => e.slot == MatriboxChainSlot.fx1)
            .every((e) => !e.isChange),
        isTrue,
      );

      // an ON block that got no model never inherits the device's model
      final incomplete = MatriboxTargetPreset(
        blocks: {
          MatriboxChainSlot.fx2: MatriboxTargetBlock(
            slot: MatriboxChainSlot.fx2,
            enabled: TargetValue(true, ToneOrigin.songProfile, 't'),
          ),
        },
      );
      final p = planOf(incomplete);
      final fx2 = p.entries
          .where((e) => e.slot == MatriboxChainSlot.fx2)
          .single;
      expect(fx2.eligibility, ToneSendEligibility.incompleteTarget);
      expect(p.operations, isEmpty);
    });

    test(
      'the translator and the recipe layer cannot even see a device state',
      () {
        for (final f in [
          'lib/presets/matribox_tone_translator.dart',
          'lib/presets/tone_recipe_builder.dart',
          'lib/presets/canonical_tone_recipe.dart',
          'lib/presets/matribox_model_matcher.dart',
        ]) {
          final source = File(f).readAsStringSync();
          expect(source, isNot(contains('matribox_preset_layout')), reason: f);
          expect(source, isNot(contains('PresetLayoutModel')), reason: f);
          expect(source, isNot(contains('RawPresetSnapshot')), reason: f);
        }
        String code(String f) =>
            File(f)
                .readAsStringSync()
                .split(RegExp(r'\r?\n'))
                .map((l) => l.split('//').first)
                .join(' ')
                .toLowerCase();
        final recipe =
            code('lib/presets/canonical_tone_recipe.dart') +
            code('lib/presets/tone_recipe_builder.dart') +
            code('lib/presets/tone_templates.dart') +
            code('lib/presets/tone_intent.dart');
        for (final banned in [
          'matribox',
          'sol 100',
          'wireindex',
          '0x0',
          'algorithm',
        ]) {
          expect(recipe.contains(banned), isFalse, reason: banned);
        }
      },
    );
  });}

// ignore: non_constant_identifier_names
MatriboxTargetPreset MatriboxToneTransferPlan_targetOf(
  MatriboxTargetBlock block,
) => MatriboxTargetPreset(blocks: {block.slot: block});
