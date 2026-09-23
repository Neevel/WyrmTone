import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_angels_product_plan.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_preset_layout.dart';
import 'package:wyrmtone/screens/matribox_angels_certification_panel.dart';

import 'support/matribox_big_capture_snapshots.dart';
import 'support/matribox_full_live_helpers.dart';
import 'support/matribox_tone_transfer_support.dart';

void main() {
  late Directory tempDir;
  late ToneReadChannel read;
  late PlanRunChannel run;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('angels_panel');
    read = ToneReadChannel(hexParts(bigBeforeRawPartsHex));
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> show(WidgetTester tester, {bool enabled = true, int? failAt}) async {
    final recommendation = angelsRecommendation();
    run = PlanRunChannel(AngelsProductPlan(library: recommendation.library), failAt: failAt);
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MatriboxAngelsCertificationPanel(
                enabled: enabled,
                connectionReady: true,
                monitoring: false,
                backupDirectory: () async => tempDir,
                recommendationLoader: () async => recommendation,
                readChannel: read,
                fullLiveChannel: run,
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await tester.pump();
    });
  }

  Future<void> taps(WidgetTester tester, List<Key> keys) async {
    await tester.runAsync(() async {
      for (final key in keys) {
        await tester.tap(find.byKey(key));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  const prepare = Key('angels-prepare');
  const prepareConfirm = Key('angels-prepare-confirm');
  const start = Key('angels-start');
  const startConfirm = Key('angels-start-confirm');
  const readback = Key('angels-readback');
  const readbackConfirm = Key('angels-readback-confirm');

  testWidgets('disabled build renders nothing and never reads', (tester) async {
    await show(tester, enabled: false);
    expect(find.byKey(const Key('angels-panel')), findsNothing);
    expect(read.reads, 0);
  });

  testWidgets('header, preparation ticks, 11 expected changes with the two uncertified model selects marked', (tester) async {
    await show(tester);
    expect(find.text("Angels Don't Kill – Product Unlock"), findsOneWidget);
    expect(find.text('Target: User P01'), findsOneWidget);
    expect(find.text('Guitar: HB Fusion 4'), findsOneWidget);
    expect(find.text('Tuning: Drop C'), findsOneWidget);
    expect(read.reads, 0);
    await taps(tester, [prepare, prepareConfirm]);
    expect(read.reads, 1);
    for (final tick in ['✓ Device read', '✓ Backup', '✓ Reload']) {
      expect(find.text(tick), findsOneWidget);
    }
    expect(find.byKey(const Key('angels-hash')), findsOneWidget);
    expect(find.textContaining('11 erwartete Änderungen: 2 MODEL SELECT · 5 PARAMETER · 4 BLOCK CC'), findsOneWidget);
    expect(find.textContaining('FX2: MODEL Boost · Katalog-Code 0x0000001a [NOT YET HARDWARE CERTIFIED]'), findsOneWidget);
    expect(find.textContaining('CAB: MODEL Sol 4x12 · Katalog-Code 0x0a000028 [NOT YET HARDWARE CERTIFIED]'), findsOneWidget);
    expect(find.text('Dieser Test verändert P01 live. Ein verifiziertes Backup existiert. Es wird nicht gespeichert.'), findsOneWidget);
    expect(find.text('ANGELS PRODUCT TEST STARTEN'), findsOneWidget);
    expect(run.planIds, isEmpty);
  });

  testWidgets('a wrong source blocks: message shown, no start button, nothing sent', (tester) async {
    read.parts = hexParts(bigBeforeRawPartsHex);
    setDecoded(read.parts, MatriboxPresetLayout.codeOffset(MatriboxChainSlot.dly), u32(0x0b000006));
    await show(tester);
    await taps(tester, [prepare, prepareConfirm]);
    expect(find.byKey(start), findsNothing);
    expect(find.textContaining('SOURCE_PRESET_MISMATCH'), findsOneWidget);
    expect(run.planIds, isEmpty);
  });

  testWidgets('cancel sends nothing; confirm = one call with the plan id; no automatic readback; readback CERTIFIED', (tester) async {
    await show(tester);
    await taps(tester, [prepare, prepareConfirm]);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(start));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(run.planIds, isEmpty);

    await taps(tester, [start, startConfirm]);
    expect(run.planIds, [AngelsProductPlan.planIdValue]);
    expect(find.text('LIVE WRITE COMPLETE – Gerät prüfen'), findsOneWidget);
    expect(find.textContaining('completed: 11 · failed: 0 · notSent: 0'), findsOneWidget);
    expect(find.text('ANGELS READBACK PRÜFEN'), findsOneWidget);
    expect(find.byKey(start), findsNothing);
    expect(read.reads, 1); // no automatic readback

    read.parts = afterFromCertificationOps(AngelsProductPlan(library: angelsRecommendation().library).operations);
    await taps(tester, [readback, readbackConfirm]);
    expect(read.reads, 2);
    expect(find.byKey(const Key('angels-readback-certified')), findsOneWidget);
    expect(find.text('CERTIFIED'), findsOneWidget);
    expect(find.text('Live-Sound erfolgreich verifiziert (nach manuellem Speichern am Gerät).'), findsOneWidget);
    expect(find.textContaining('Unberührt: NR, MOD, DLY, RVB'), findsOneWidget);
    expect(run.planIds, hasLength(1));
  });

  testWidgets('the live write is not visible to the read: TARGET_MISMATCH, then the same readback certifies after the manual save', (tester) async {
    await show(tester);
    await taps(tester, [prepare, prepareConfirm, start, startConfirm]);
    // device still returns the SAVED (old) preset: nothing saved yet
    await taps(tester, [readback, readbackConfirm]);
    expect(find.text('TARGET_MISMATCH'), findsOneWidget);
    expect(find.byKey(readback), findsOneWidget); // the readback can be repeated
    expect(find.byKey(start), findsNothing); // but never a second write
    // Marcel saves on the device -> the read now returns the target
    read.parts = afterFromCertificationOps(AngelsProductPlan(library: angelsRecommendation().library).operations);
    await taps(tester, [readback, readbackConfirm]);
    expect(find.text('CERTIFIED'), findsOneWidget);
    expect(run.planIds, hasLength(1));
  });

  testWidgets('after a TARGET_MISMATCH (device restarted, live values gone) a new run can be prepared and started', (tester) async {
    await show(tester);
    await taps(tester, [prepare, prepareConfirm, start, startConfirm]);
    await taps(tester, [readback, readbackConfirm]); // unsaved: old state
    expect(find.text('TARGET_MISMATCH'), findsOneWidget);
    expect(find.text('Neuen Lauf vorbereiten'), findsOneWidget);
    await taps(tester, [prepare, prepareConfirm]);
    expect(find.byKey(start), findsOneWidget); // P01 is still the known source
    await taps(tester, [start, startConfirm]);
    expect(run.planIds, hasLength(2)); // two separate, explicitly confirmed runs
  });

  testWidgets('a mid-run failure shows completed / failed / notSent; a partial readback is PARTIAL_EXECUTION', (tester) async {
    await show(tester, failAt: 3);
    await taps(tester, [prepare, prepareConfirm, start, startConfirm]);
    expect(run.planIds, hasLength(1));
    expect(find.byKey(const Key('angels-run-stopped')), findsOneWidget);
    expect(find.textContaining('completed: 3 · failed: 1 · notSent: 7'), findsOneWidget);
    read.parts = afterFromCertificationOps(AngelsProductPlan(library: angelsRecommendation().library).operations);
    await taps(tester, [readback, readbackConfirm]);
    expect(find.text('PARTIAL_EXECUTION'), findsOneWidget);
    expect(find.byKey(const Key('angels-success')), findsNothing);
  });
}
