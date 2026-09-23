import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_evidence_v2.dart';
import 'package:wyrmtone/presets/matribox_hardware_evidence.dart';
import 'package:wyrmtone/presets/matribox_model_library.dart';
import 'package:wyrmtone/presets/matribox_raw_backup_service.dart';
import 'package:wyrmtone/presets/matribox_target_preset.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_plan.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_session.dart';
import 'package:wyrmtone/presets/matribox_tone_translator.dart';
import 'package:wyrmtone/presets/matribox_translation_result.dart';
import 'package:wyrmtone/presets/tone_intent.dart';
import 'package:wyrmtone/presets/tone_recipe_builder.dart';
import 'package:wyrmtone/tonevault/tone_vault.dart';

import 'support/direct_transfer_support.dart';
import 'support/matribox_big_capture_snapshots.dart';
import 'support/matribox_full_live_helpers.dart';
import 'support/matribox_tone_transfer_support.dart';

/// Workflow/integration tests (offline, no real Matribox): the real generic product path
/// ToneVault -> created sound -> recipe -> translator -> target -> plan -> contract, the gold
/// reference sounds, and the session workflow with fake channels. No hardware, no MIDI, no USB.
void main() {
  late ToneVault vault;
  late Directory tempDir;
  late MatriboxToneTransferStore store;
  final library = MatriboxModelLibrary.fromVendor(toneCatalog);

  setUpAll(() => vault = loadFullVault());
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hw_readiness');
    store = MatriboxToneTransferStore(File('${tempDir.path}/tone_transfer.state'));
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  MatriboxRawBackupService service(ToneReadChannel c) => MatriboxRawBackupService(channel: c, backupDirectory: tempDir);
  MatriboxToneTransferSession session(ToneReadChannel read, {MatriboxToneTransferChannel? channel}) => MatriboxToneTransferSession(
    backupService: service(read),
    ledger: MatriboxHardwareLedger.product(),
    channel: channel ?? RecordingTransfer(),
    nameCatalog: toneCatalog,
    library: library,
  );

  Map<String, String> describe(MatriboxTargetPreset t) => {
    for (final slot in MatriboxChainSlot.values)
      slot.label:
          '${t[slot].effectiveState}|on=${t[slot].enabled.value}|${t[slot].model.value?.name}|'
          '${t[slot].parameters.entries.where((e) => e.value.specified).map((e) => '${e.key}=${e.value.value}(${e.value.origin.name})').join(',')}',
  };

  const angelsOps = [
    'FX1 BLOCK OFF',
    'FX2 MODEL Boost',
    'FX2 BLOCK ON',
    'AMP gain 67',
    'AMP presence 59',
    'AMP bass 41',
    'AMP middle 59',
    'AMP treble 61',
    'CAB MODEL Sol 4x12',
    'CAB BLOCK ON',
    'EQ BLOCK OFF',
  ];
  List<String> opsOf(MatriboxToneTransferPlan p) => p.operations.map((e) => '${e.slot.label} ${e.subject} ${e.target}').toList();

  group('1 Angels Dont Kill: the real generic ToneVault path equals the certified golden', () {
    test('ToneVault entry -> created sound -> recipe -> translator -> target equals the fixed Angels recommendation', () {
      final fromVault = createFromText(vault, "Angels Don't Kill"); // NLU resolves the real entry
      expect(fromVault.selection.entryId, 'song.children_of_bodom.angels_dont_kill');
      final golden = angelsRecommendation();
      // same models, block states, values AND origins per block (reason texts may differ in wording)
      expect(describe(fromVault.recommendation.target), describe(golden.target));
      expect(fromVault.recommendation.recipe.tuning, golden.recipe.tuning);
    });

    test('and its plan against the known P01 is exactly the 11 certified operations', () {
      final target = createFromText(vault, "Angels Don't Kill").recommendation.target;
      final plan = MatriboxToneTransferPlan.build(
        current: beforeLayout(),
        target: target,
        ledger: MatriboxHardwareLedger.product(),
        backupSha256: 'ab' * 32,
        presetNumber: 11,
        isUserBank: true,
        transportAvailable: true,
        library: library,
      );
      expect(opsOf(plan), angelsOps);
      expect(plan.overall, ToneTransferOverall.ready);
      // the fixed golden recommendation gives the very same operations
      final goldenPlan = MatriboxToneTransferPlan.build(
        current: beforeLayout(),
        target: angelsRecommendation().target,
        ledger: MatriboxHardwareLedger.product(),
        backupSha256: 'ab' * 32,
        presetNumber: 11,
        isUserBank: true,
        transportAvailable: true,
        library: library,
      );
      expect(opsOf(goldenPlan), angelsOps);
    });

    test('the whole chain runs with fake devices: read -> backup -> plan -> live write -> manual save -> readback CERTIFIED', () async {
      final created = createFromText(vault, "Angels Don't Kill");
      final read = ToneReadChannel(hexParts(bigBeforeRawPartsHex));
      final transfer = RecordingTransfer();
      final s = session(read, channel: transfer);
      final prepared = await s.prepare(created.recommendation.target, targetSlot: 11);
      expect(prepared.plan!.overall, ToneTransferOverall.ready);
      expect(read.reads, 1);
      final run = await MatriboxToneTransferExecutor(channel: transfer, store: store).execute(prepared);
      expect(run.isSuccess, isTrue);
      expect(transfer.executions, hasLength(1));
      expect(transfer.requests, hasLength(11));
      final record = await MatriboxToneTransferCheckpoint.confirmManualSave((await store.load())!, store);
      expect(transfer.executions, hasLength(1), reason: 'the manual-save checkpoint sends nothing');
      final result = await MatriboxToneTransferReadback.run(
        record: record,
        backupService: service(ToneReadChannel(deviceAfter(prepared.plan!.operations))),
        store: store,
      );
      expect(result.outcome, ToneReadbackOutcome.certified);
      expect((await store.load())!.state, ToneTransferRecordState.verified);
    });

    test('documented difference: the golden is built from the legacy profile, the vault entry links it by legacyProfileId', () {
      final entry = vault.entry('song.children_of_bodom.angels_dont_kill')!;
      expect(entry.legacyProfileId, angelsProfile.id);
    });
  });

  group('7 the created sound is the source of truth (never a reloaded vault entry)', () {
    // The recipe is rebuilt from the FINAL local sound (draft.tone) and translated again: it must equal the target,
    // and it must differ from the translation of the unmodified vault entry.
    void checkSource(String modified, String baseline, {required bool lowerGain, bool moreMids = false, GuitarTuning? tuning}) {
      final s = createFromText(vault, modified);
      final base = createFromText(vault, baseline);
      expect(s.selection.modifiers, isNotEmpty, reason: 'the wishes were understood');
      final rec = s.recommendation;
      if (tuning != null) expect(rec.draft.tuning, tuning);
      final rebuilt = ToneRecipeBuilder.build(
        profile: rec.draft.profile,
        guitar: rec.draft.guitar,
        tuning: rec.draft.tuning,
        role: rec.draft.role,
        finalTone: rec.draft.tone,
        cabEnabled: rec.draft.blocks.where((b) => b.slot == 'CAB').firstOrNull?.enabled,
        internalAmp: rec.draft.selectedNamId == null,
      );
      // final recipe values == what the translator was given
      for (final role in ToneBlockRole.values) {
        expect({for (final e in rebuilt[role].params.entries) e.key: (e.value.value, e.value.origin)},
            {for (final e in rec.recipe[role].params.entries) e.key: (e.value.value, e.value.origin)},
            reason: role.name);
      }
      final again = MatriboxToneTranslator.translate(recipe: rebuilt, library: library);
      expect(describe(again), describe(rec.target), reason: 'target = translation of the final recipe');
      double? amp(CreatedSound c, String k) => c.recommendation.target[MatriboxChainSlot.amp].parameters[k]?.value;
      if (lowerGain) expect(amp(s, 'gain')!, lessThan(amp(base, 'gain')!));
      if (moreMids) expect(amp(s, 'middle')!, greaterThan(amp(base, 'middle')!));
      // provenance: the wish arrives as USER_OVERRIDE in the recipe and in the target
      final recipeOrigins = [for (final r in ToneBlockRole.values) ...rec.recipe[r].params.values.map((v) => v.origin)];
      expect(recipeOrigins, contains(ToneOrigin.userOverride));
      final targetOrigins = [
        for (final slot in MatriboxChainSlot.values) ...rec.target[slot].parameters.values.map((v) => v.origin),
      ];
      expect(targetOrigins, contains(ToneOrigin.userOverride));
      expect(describe(rec.target), isNot(describe(base.recommendation.target)));
    }

    test('"moderner Metalcore Rhythmus für Drop C, tight, aggressiv, weniger Gain"', () {
      checkSource(
        'moderner Metalcore Rhythmus für Drop C, tight, aggressiv, weniger Gain',
        'moderner Metalcore Rhythmus für Drop C, tight, aggressiv',
        lowerGain: true,
        tuning: GuitarTuning.dropC,
      );
    });

    test('"Master of Puppets weniger Gain mehr Mitten"', () {
      checkSource('Master of Puppets weniger Gain mehr Mitten', 'Master of Puppets', lowerGain: true, moreMids: true);
    });

    test('tuning and guitar corrections are part of the created sound and reach the target with their origin', () {
      final origins = <ToneOrigin>{};
      for (final t in [GuitarTuning.dropC, GuitarTuning.dropCSharp, GuitarTuning.dropA, GuitarTuning.cSharpStandard]) {
        final s = createFromText(vault, 'Master of Puppets Rhythmus', tuning: t);
        expect(s.recommendation.draft.tuning, t);
        for (final slot in MatriboxChainSlot.values) {
          origins.addAll(s.recommendation.target[slot].parameters.values.map((v) => v.origin));
        }
      }
      expect(origins, contains(ToneOrigin.tuningCorrection));
      var guitarSeen = false;
      for (final out in OutputLevel.values) {
        for (final tone in ToneCharacter.values) {
          final g = GuitarProfile(
            id: 'g', name: 'G', guitarType: GuitarType.values.first, pickupType: PickupType.values.last,
            outputLevel: out, toneCharacter: tone, tuning: GuitarTuning.dropC, playbackPath: PlaybackPath.headphones,
          );
          final s = createFromText(vault, 'Master of Puppets Rhythmus', guitar: g, tuning: GuitarTuning.dropC);
          for (final slot in MatriboxChainSlot.values) {
            if (s.recommendation.target[slot].parameters.values.any((v) => v.origin == ToneOrigin.guitarCorrection)) guitarSeen = true;
          }
        }
      }
      expect(guitarSeen, isTrue, reason: 'a guitar correction must reach the target');
    });
  });

  group('8 gold reference sounds A-J: verdict, plan and closed contract (no claim about musical quality)', () {
    const sounds = {
      'A Angels Dont Kill': "Angels Don't Kill",
      'B Master of Puppets Rhythm': 'Master of Puppets Rhythmus',
      'C Metalcore Drop C': 'moderner Metalcore Rhythm Drop C',
      'D Metalcore Drop A tighter': 'moderner Metalcore Rhythm Drop A straffer weniger Gain',
      'E Blues Crunch': 'warmer Blues Crunch',
      'F 80s Lead Delay': '80er Hard Rock Lead mit viel Delay',
      'G Grunge dirty': 'Nirvana aber dreckiger',
      'H Sandstorm': 'Sandstorm',
      'I Cyberpunk Lead': 'Cyberpunk Lead',
      'J Clean Chorus Reverb': 'Clean mit Chorus und viel Reverb',
    };
    test('nothing is BLOCKED, every plan is all-or-nothing and only sendable operations are planned', () {
      for (final e in sounds.entries) {
        final s = createFromText(vault, e.value);
        final r = s.analyze();
        final plan = MatriboxToneTransferPlan.build(
          current: beforeLayout(),
          target: s.recommendation.target,
          ledger: MatriboxHardwareLedger.product(),
          backupSha256: 'ab' * 32,
          presetNumber: 11,
          isUserBank: true,
          transportAvailable: true,
          library: library,
        );
        expect(r.overallCompatibility, isNot(MatriboxCompatibility.blocked), reason: e.key);
        expect(plan.overall, isNot(ToneTransferOverall.blocked), reason: '${e.key}: ${plan.blockers}');
        expect(plan.operations.every((o) => o.bytes != null), isTrue);
        // the typed contract carries only the closed field set
        final request = plan.toContractRequest();
        expect(request.keys.toSet(), {'planId', 'targetBank', 'targetSlot', 'backupHash', 'operations'});
        for (final op in (request['operations'] as List).cast<Map<String, Object?>>()) {
          expect(op.keys.toSet().difference({'type', 'slot', 'model', 'parameter', 'value'}), isEmpty, reason: '${e.key}: $op');
          expect(op['type'], anyOf('SELECT_MODEL', 'SET_PARAMETER', 'ENABLE_BLOCK', 'DISABLE_BLOCK'));
        }
      }
    });
  });

  group('incomplete blocks in the session workflow (fake channels)', () {
    List<List<int>> before() => hexParts(bigBeforeRawPartsHex);

    test('an incomplete NON-amp block (no model found) does not block the transfer; it is left as it is and never fails the verification', () async {
      final base = readyTarget();
      MatriboxTargetPreset withIncomplete(MatriboxChainSlot slot) => MatriboxTargetPreset(blocks: {
        ...base.blocks,
        slot: MatriboxTargetBlock(
          slot: slot,
          state: RecipeBlockState.incomplete,
          incompleteReason: 'kein Modell',
          enabled: TargetValue(true, ToneOrigin.songProfile, 't'),
        ),
      });
      final transfer = RecordingTransfer();
      final prepared = await session(ToneReadChannel(before()), channel: transfer).prepare(withIncomplete(MatriboxChainSlot.eq), targetSlot: 11);
      expect(prepared.plan!.overall, ToneTransferOverall.ready, reason: '${prepared.plan!.blockers}');
      expect(prepared.plan!.operations.where((o) => o.slot == MatriboxChainSlot.eq), isEmpty);
      expect((await MatriboxToneTransferExecutor(channel: transfer, store: store).execute(prepared)).isSuccess, isTrue);
      final record = await MatriboxToneTransferCheckpoint.confirmManualSave((await store.load())!, store);
      final result = await MatriboxToneTransferReadback.run(
        record: record,
        backupService: service(ToneReadChannel(deviceAfter(prepared.plan!.operations))),
        store: store,
      );
      expect(result.outcome, ToneReadbackOutcome.certified, reason: '${result.detail} ${result.checks.where((c) => !c.matched).map((c) => c.subject)}');

      // without an amp model the transfer stays blocked
      final noAmp = await session(ToneReadChannel(before())).prepare(withIncomplete(MatriboxChainSlot.amp), targetSlot: 11);
      expect(noAmp.plan!.sendable, isFalse);
    });

  });

  group('9 catalog numbers: manufacturer XML vs. productive transfer catalog (derived, not hard-coded)', () {
    test('every difference has a mechanical reason; addressable / sendable / semantic stay separate', () {
      final algorithms = toneCatalog.algorithms;
      final codes = {for (final a in algorithms) if (a.code != null) a.code!};
      // 1. FX1 and FX2 list the same algorithm codes: one model serves both slots
      final byCode = <int, Set<String?>>{};
      for (final a in algorithms) {
        byCode.putIfAbsent(a.code!, () => {}).add(a.category);
      }
      final sharedFx = byCode.values.where((c) => c.length > 1);
      expect(sharedFx.every((c) => c.difference({'FX1', 'FX2'}).isEmpty), isTrue);
      final duplicateEntries = algorithms.length - codes.length;
      expect(duplicateEntries, sharedFx.length);
      // 2. catalog entries without a name (unused cabinet slots) are not offered as models,
      //    unless the same code is a captured model of the transfer catalog
      final libCodes = {for (final m in library.models) m.code};
      final missing = codes.where((c) => !libCodes.contains(c)).toList();
      expect(library.models.length, codes.length - missing.length);
      expect(libCodes.difference(codes), isEmpty, reason: 'the library invents no code');
      for (final c in missing) {
        expect(algorithms.where((a) => a.code == c).every((a) => (a.name ?? '').isEmpty && a.category == 'CAB'), isTrue, reason: 'code $c');
      }
      final catalogParams = algorithms.fold<int>(0, (s, a) => s + a.parameters.length);
      final fxSharedParams = algorithms.where((a) => a.category == 'FX2').fold<int>(0, (s, a) => s + a.parameters.length);
      final missingParams = algorithms.where((a) => missing.contains(a.code)).fold<int>(0, (s, a) => s + a.parameters.length);
      final libraryParams = library.models.fold<int>(0, (s, m) => s + m.algorithm.parameters.length);
      // ignore: avoid_print
      print('CATALOG xml entries=${algorithms.length} params=$catalogParams | unique codes=${codes.length} (FX1/FX2 shared: $duplicateEntries, params $fxSharedParams) '
          '| unnamed-only codes=${missing.length} (params $missingParams) | library models=${library.models.length} params=$libraryParams');
      expect(libraryParams, catalogParams - fxSharedParams - missingParams);

      // 3. addressable / sendable per slot (A / B); C = a mapping rule exists
      final ev = MatriboxEvidenceV2(library: library, samples: ActiveSamples.fromLedger(MatriboxHardwareLedger.product(), library));
      final table = <String>[];
      var slotParams = 0, slotAddressable = 0, slotSendable = 0, slotModels = 0, slotSelectable = 0;
      for (final slot in MatriboxChainSlot.values) {
        final models = library.forSlot(slot).toList();
        var p = 0, a = 0, b = 0, sel = 0;
        for (final m in models) {
          if (m.selectable && ev.modelSelect(slot, m).sendable) sel++;
          for (final q in m.algorithm.parameters) {
            p++;
            if (q.blockedReason != null) continue;
            a++;
            if (ev.parameter(slot, m, q, q.defaultValue ?? q.minimum).sendable) b++;
          }
        }
        table.add('CATALOG ${slot.label}: models=${models.length} selectable+sendable=$sel params=$p A_addressable=$a B_sendable=$b');
        slotParams += p; slotAddressable += a; slotSendable += b; slotModels += models.length; slotSelectable += sel;
      }
      table.add('CATALOG SUM(slot view): model-slots=$slotModels select-sendable=$slotSelectable params=$slotParams A=$slotAddressable B=$slotSendable');
      // ignore: avoid_print
      table.forEach(print);
      expect(slotAddressable, lessThanOrEqualTo(slotParams));
      expect(slotSendable, lessThanOrEqualTo(slotAddressable));
      // a non-sendable parameter always has a stated reason (never silently dropped)
      for (final slot in MatriboxChainSlot.values) {
        for (final m in library.forSlot(slot)) {
          for (final q in m.algorithm.parameters) {
            final d = ev.parameter(slot, m, q, q.defaultValue ?? q.minimum);
            if (!d.sendable) expect(d.basis.isNotEmpty || q.blockedReason != null, isTrue, reason: '${slot.label} ${m.name}/${q.name}');
          }
        }
      }
    });
  });
}

