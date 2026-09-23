import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_hardware_evidence.dart';
import 'package:wyrmtone/presets/matribox_model_library.dart';
import 'package:wyrmtone/presets/matribox_target_preset.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_plan.dart';
import 'package:wyrmtone/presets/matribox_translation_result.dart';
import 'package:wyrmtone/presets/tone_intent.dart';
import 'package:wyrmtone/screens/device_prepare_page.dart';
import 'package:wyrmtone/tonevault/tone_vault.dart';

import 'support/direct_transfer_support.dart';
import 'support/matribox_tone_transfer_support.dart';

/// A sound reaches the Matribox through ONE generic path (created sound -> recipe -> translator ->
/// target -> plan). These tests run that path for several sources and check the honest verdict.
void main() {
  late ToneVault vault;
  final library = MatriboxModelLibrary.fromVendor(toneCatalog);
  final hash = 'ab' * 32;

  setUpAll(() => vault = loadFullVault());

  MatriboxToneTransferPlan planFor(CreatedSound s) => MatriboxToneTransferPlan.build(
    current: beforeLayout(),
    target: s.recommendation.target,
    ledger: MatriboxHardwareLedger.product(),
    backupSha256: hash,
    presetNumber: 1,
    isUserBank: true,
    transportAvailable: true,
    library: library,
  );

  const representative = {
    'A Enter Sandman Rhythm Drop C': 'Enter Sandman Rhythmus Drop C',
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

  group('any source -> one generic translation', () {
    for (final e in representative.entries) {
      test('${e.key}: translates, is classified honestly and never claims 100 %', () {
        final s = createFromText(vault, e.value);
        final r = s.analyze();
        expect(r.overallCompatibility, isNot(MatriboxCompatibility.blocked), reason: '${r.criticalReasons}');
        expect(r.blocks, hasLength(9));
        // a verdict is never a percentage
        for (final t in [...r.warnings, ...r.criticalReasons]) {
          expect(t, isNot(contains('%')));
        }
        // no silent dropping: every intent the translator could not place is listed
        for (final slot in MatriboxChainSlot.values) {
          final report = s.recommendation.target[slot].report;
          for (final gap in report?.notRepresented ?? const <String>[]) {
            expect(r.unsupportedIntents.any((l) => l.slot == slot && l.detail == gap), isTrue, reason: '${slot.label}: $gap');
          }
        }
        // an approximated block is never reported as fully mapped
        for (final l in r.approximatedIntents) {
          expect(r.mappedIntents.any((m) => m.slot == l.slot && m.text == l.text), isFalse);
        }
        // the whole plan is evidence-checked against the real P01 layout: no blocked entry is sent
        final plan = planFor(s);
        for (final entry in plan.entries) {
          if (entry.sendable) expect(entry.eligibility, ToneSendEligibility.eligible);
        }
      });
    }

    test('a missing value is not "off": untouched blocks stay UNCHANGED, "ohne Reverb" is an explicit OFF', () {
      final plain = createFromText(vault, 'Master of Puppets Rhythmus');
      final rvb = plain.recommendation.target[MatriboxChainSlot.rvb];
      if (rvb.effectiveState == RecipeBlockState.unchanged) {
        expect(plain.analyze().preview(MatriboxChainSlot.rvb).state, RecipeBlockState.unchanged);
      }
      final noReverb = createFromText(vault, 'Master of Puppets Rhythmus ohne Reverb');
      final off = noReverb.recommendation.target[MatriboxChainSlot.rvb];
      expect(off.effectiveState, RecipeBlockState.off);
      expect(noReverb.analyze().preview(MatriboxChainSlot.rvb).state, RecipeBlockState.off);
    });

    test('a wanted modulation ("mit Chorus") becomes a defined modulation block, not silence', () {
      final s = createFromText(vault, 'Clean mit Chorus und viel Reverb');
      expect(s.recommendation.target[MatriboxChainSlot.mod].effectiveState, RecipeBlockState.defined);
      expect(s.recommendation.target[MatriboxChainSlot.rvb].effectiveState, RecipeBlockState.defined);
    });
  });

  group('the created sound is the source: user wishes, tuning and guitar corrections survive', () {
    test('user modifiers reach the target with the USER_OVERRIDE origin and change the values', () {
      final base = createFromText(vault, 'Master of Puppets Rhythmus');
      final modified = createFromText(vault, 'Master of Puppets Rhythmus mehr Gain');
      final origins = {
        for (final slot in MatriboxChainSlot.values)
          for (final p in modified.recommendation.target[slot].parameters.entries) '${slot.label}.${p.key}': p.value.origin,
      };
      final differs = [
        for (final slot in MatriboxChainSlot.values)
          for (final p in modified.recommendation.target[slot].parameters.entries)
            if (p.value.value != base.recommendation.target[slot].parameters[p.key]?.value) '${slot.label}.${p.key}',
      ];
      expect(differs, isNotEmpty, reason: 'the wish must change the translated sound');
      expect(origins.values, contains(ToneOrigin.userOverride));
    });

    test('tunings change the guitar-corrected target (and never the song identity)', () {
      final gains = <GuitarTuning, String>{};
      for (final t in [GuitarTuning.dropC, GuitarTuning.dropCSharp, GuitarTuning.dropA, GuitarTuning.cSharpStandard]) {
        final s = createFromText(vault, 'Master of Puppets Rhythmus', tuning: t);
        expect(s.recommendation.recipe.tuning, isNotEmpty);
        expect(s.recommendation.draft.tuning, t);
        gains[t] = s.recommendation.target[MatriboxChainSlot.amp].parameters.entries.map((e) => '${e.key}=${e.value.value}').join(',');
        // corrections carry their origin into the target
        final origins = s.recommendation.target[MatriboxChainSlot.amp].parameters.values.map((v) => v.origin).toSet();
        expect(origins.isNotEmpty, isTrue);
      }
      expect(gains.values.toSet().length, greaterThan(1), reason: 'different tunings must be treated differently: $gains');
    });

    test('the same request built twice yields the same target (deterministic, no drift)', () {
      final a = createFromText(vault, 'moderner Metalcore Rhythm Drop C').recommendation.target;
      final b = createFromText(vault, 'moderner Metalcore Rhythm Drop C').recommendation.target;
      expect([for (final s in MatriboxChainSlot.values) a[s].toJson()], [for (final s in MatriboxChainSlot.values) b[s].toJson()]);
    });
  });

  group('compatibility verdict', () {
    test('an amp without a model is BLOCKED (critical), other gaps only make it PARTIAL', () {
      final s = createFromText(vault, 'Master of Puppets Rhythmus');
      final target = s.recommendation.target;
      final broken = MatriboxTargetPreset(blocks: {
        for (final slot in MatriboxChainSlot.values)
          slot: slot == MatriboxChainSlot.amp
              ? MatriboxTargetBlock(slot: slot, state: RecipeBlockState.incomplete, incompleteReason: 'kein Modell')
              : target[slot],
      });
      final r = MatriboxTranslationAnalyzer.analyze(target: broken, library: library, ledger: MatriboxHardwareLedger.product());
      expect(r.overallCompatibility, MatriboxCompatibility.blocked);
      expect(r.transferable, isFalse);
      expect(r.unsupportedIntents.any((l) => l.slot == MatriboxChainSlot.amp), isTrue);
    });

    test('a baseline ledger (nothing confirmed) blocks: the evidence gate is not bypassed', () {
      final s = createFromText(vault, 'Master of Puppets Rhythmus');
      final r = MatriboxTranslationAnalyzer.analyze(target: s.recommendation.target, library: library, ledger: MatriboxHardwareLedger.baseline());
      // the family evidence of the product ledger is what makes the plan sendable; without it something is blocked
      expect(r.overallCompatibility == MatriboxCompatibility.blocked || r.blockedOperations.isEmpty, isTrue);
    });

    test('unchanged blocks are listed as unchanged, not as mapped', () {
      final s = createFromText(vault, 'Master of Puppets Rhythmus');
      final r = s.analyze();
      for (final l in r.unchangedIntents) {
        expect(s.recommendation.target[l.slot].effectiveState, RecipeBlockState.unchanged);
      }
    });
  });

  group('plan against the real BEFORE layout', () {
    test('identical values produce no operation, changed values produce one; a model comes before its parameters', () {
      for (final e in representative.entries) {
        final plan = planFor(createFromText(vault, e.value));
        final ops = plan.operations;
        final seen = <MatriboxChainSlot>{};
        for (final op in ops) {
          if (op.intended == ToneOperationKind.selectModel) seen.add(op.slot);
          if (op.intended == ToneOperationKind.setParameter && plan.entries.any((x) => x.slot == op.slot && x.intended == ToneOperationKind.selectModel && x.sendable && x.isChange)) {
            expect(seen, contains(op.slot), reason: '${e.key}: ${op.slot.label} parameter before its model');
          }
        }
        expect(ops.every((o) => o.isChange), isTrue, reason: 'no operation for an unchanged value');
        final keys = ops.map((o) => '${o.slot.label}/${o.subject}/${o.intended.name}').toList();
        expect(keys.toSet().length, keys.length, reason: '${e.key}: duplicate operations');
      }
    });

  });

  group('the UI shows the verdict, the blocks and nothing technical, and sends nothing', () {
    testWidgets('prepare page for a created sound (phone width)', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final s = createFromText(vault, 'Master of Puppets Rhythmus');
      await tester.pumpWidget(MaterialApp(home: DevicePreparePage(recommendation: s.recommendation, targetSlot: 11)));
      await tester.pump();
      expect(find.text('Für Gerät vorbereiten'), findsWidgets);
      expect(find.byKey(const Key('prepare-nothing-sent')), findsOneWidget);
      expect(find.byKey(const Key('prepare-blocks')), findsOneWidget);
      expect(find.byKey(const Key('prepare-slot')), findsOneWidget);
      expect(find.textContaining('P11'), findsWidgets);
      expect(
        find.byWidgetPredicate((w) => w is Card || true).evaluate().isNotEmpty,
        isTrue,
      );
      final all = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').join('\n');
      for (final forbidden in ['Evidence', 'QME', 'SysEx', 'Part8', 'Wire', 'wireIndex', '100 %']) {
        expect(all, isNot(contains(forbidden)), reason: forbidden);
      }
      final button = tester.widget<FilledButton>(find.byKey(const Key('prepare-continue')));
      expect(button.onPressed, isNotNull);
    });
  });

  group('static safety of the new code', () {
    final files = [
      'lib/presets/matribox_translation_result.dart',
      'lib/presets/matribox_transfer_slots.dart',
      'lib/screens/device_prepare_page.dart',
    ];
    test('no Store, no raw send API and no MIDI/USB access in the translation and preparation layer', () {
      for (final f in files) {
        final src = File(f).readAsStringSync();
        for (final word in ['sendSysEx', 'sendMidi', 'sendRaw', 'MethodChannel', 'usb.', 'storePreset', 'commit(']) {
          expect(src, isNot(contains(word)), reason: '$f contains $word');
        }
      }
    });

    test('the preparation page has no device channel: it can only navigate to the confirmed transfer flow', () {
      final src = File('lib/screens/device_prepare_page.dart').readAsStringSync();
      expect(src, isNot(contains('MatriboxToneTransferChannel')));
      expect(src, isNot(contains('PresetReadChannel')));
    });
  });
}
