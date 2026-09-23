import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_hardware_evidence.dart';
import 'package:wyrmtone/presets/matribox_target_preset.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_pipeline.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_plan.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_session.dart';
import 'package:wyrmtone/presets/tone_intent.dart';
import 'package:wyrmtone/screens/tone_transfer_page.dart';

import 'support/matribox_big_capture_snapshots.dart';
import 'support/matribox_full_live_helpers.dart';
import 'support/matribox_tone_transfer_support.dart';

/// The One-Tap flow: "An Matribox senden" runs the whole prepare pipeline (fresh read, backup,
/// hash, diff, evidence/preflight) automatically and silently, then asks for exactly ONE
/// understandable confirmation before the actual live write. Everything safety-relevant from the
/// old two-button flow (fresh read + verified backup + evidence-gated plan + native whole-plan
/// preflight before the first send) still runs on every tap; it is just no longer a second
/// visible step.
void main() {
  late Directory tempDir;
  late ToneReadChannel read;
  late RecordingTransfer transfer;
  final angels = angelsRecommendation();

  List<List<int>> savedAfterTransfer() {
    final plan = MatriboxToneTransferPlan.build(
      current: beforeLayout(),
      target: angels.target,
      ledger: MatriboxHardwareLedger.product(),
      backupSha256: 'x',
      presetNumber: 11,
      isUserBank: true,
      transportAvailable: true,
      library: angels.library,
    );
    return deviceAfter(plan.operations);
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('tone_transfer_page');
    read = ToneReadChannel(hexParts(bigBeforeRawPartsHex));
    transfer = RecordingTransfer();
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> show(
    WidgetTester tester, {
    MatriboxToneTransferChannel? channel,
    ToneTransferRecommendation? recommendation,
  }) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: ToneTransferPage(
            key: UniqueKey(),
            recommendation: recommendation ?? angels,
            readChannel: read,
            transferChannel: channel ?? transfer,
            backupDirectory: () async => tempDir,
            nameCatalogLoader: () async => toneCatalog, targetSlot: 11,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await tester.pump();
    });
  }

  // Real File I/O: every tap that leads to it runs inside one runAsync block.
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

  const send = Key('tt-send');
  const sendConfirm = Key('tt-send-confirm');
  const manualSave = Key('tt-manual-save-done');
  const readback = Key('tt-readback');
  const readbackConfirm = Key('tt-readback-confirm');

  testWidgets('offline preview shows the real recommendation, reads nothing, one primary CTA', (tester) async {
    await show(tester);
    expect(find.textContaining('Angels Don'), findsOneWidget);
    expect(find.textContaining('Gitarre: HB Fusion 4'), findsOneWidget);
    expect(find.textContaining('Stimmung: Drop C'), findsOneWidget);
    expect(find.text('Ziel: Matribox 1 · Preset P11'), findsOneWidget);
    expect(find.text('An Matribox senden'), findsOneWidget);
    expect(find.text('Gerät lesen & Sicherung anlegen'), findsNothing);
    // The compact, friendly summary is visible immediately -- no raw MODEL/BLOCK/origin words.
    final summary = tester.widget<Text>(find.byKey(const Key('tt-change-summary'))).data!;
    expect(summary, contains('WyrmTone passt an:'));
    expect(summary, isNot(contains('MODEL')));
    expect(summary, isNot(contains('SONG_PROFILE')));
    expect(find.byKey(sendConfirm), findsNothing);
    expect(read.reads, 0);
    expect(transfer.executions, isEmpty);
  });

  testWidgets('one tap prepares AND asks for exactly one confirmation before the live write', (tester) async {
    await show(tester);
    await taps(tester, [send]);
    expect(read.reads, 1); // the fresh read already happened, silently
    expect(
      find.textContaining('wird auf P11 übertragen.\nDer bisherige Sound auf P11 wird ersetzt.'),
      findsOneWidget,
    );
    expect(transfer.executions, isEmpty); // confirmation not yet given: nothing sent
    // The cancel tap must run inside runAsync too: _beginTransfer's async chain started inside a
    // real-file-IO runAsync zone (the prepare step) and its later continuations only flush there.
    await tester.runAsync(() async {
      await tester.tap(find.text('Abbrechen'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    expect(transfer.executions, isEmpty);
    // cancelling clears the prepared plan so the primary action is available again
    expect(find.byKey(send), findsOneWidget);

    await taps(tester, [send, sendConfirm]);
    expect(transfer.executions, hasLength(1));
    expect(transfer.requests, hasLength(11));
  });

  testWidgets('without a productive transport nothing is sendable; the button stays for a retry', (tester) async {
    await show(tester, channel: const UnavailableToneTransferChannel());
    await taps(tester, [send]);
    expect(transfer.executions, isEmpty);
    expect(find.byKey(sendConfirm), findsNothing);
    expect(find.textContaining('Transport'), findsWidgets);
    expect(find.byKey(send), findsOneWidget, reason: 'a blocked attempt can be retried without leaving the page');
  });

  testWidgets(
    'REGRESSION (real hardware): a non-AMP incomplete block never blocks the send button -- it is '
    'shown as an informational note, and the transfer proceeds after the single confirmation',
    (tester) async {
      final base = readyTarget();
      final withIncompleteEq = angels.withTarget(
        MatriboxTargetPreset(
          blocks: {
            ...base.blocks,
            MatriboxChainSlot.eq: MatriboxTargetBlock(
              slot: MatriboxChainSlot.eq,
              state: RecipeBlockState.incomplete,
              incompleteReason: 'kein Modell',
              enabled: TargetValue(true, ToneOrigin.songProfile, 't'),
            ),
          },
        ),
      );
      await show(tester, recommendation: withIncompleteEq);
      await taps(tester, [send]);
      // Informational only: visible, but the send button must still be reachable.
      expect(find.byKey(const Key('tt-incomplete-note')), findsOneWidget);
      expect(find.byKey(sendConfirm), findsOneWidget, reason: 'a non-critical incomplete block must not block the confirmation dialog');
      await taps(tester, [sendConfirm]);
      expect(transfer.executions, hasLength(1));
      expect(find.text('Sound ist live auf der Matribox aktiv'), findsOneWidget);
    },
  );

  testWidgets('LIVE WRITE -> physical check -> MANUAL SAVE checkpoint (no MIDI) -> automatic readback -> VERIFIED', (tester) async {
    await show(tester);
    await taps(tester, [send, sendConfirm]);
    expect(transfer.executions, hasLength(1));
    expect(transfer.requests, hasLength(11));
    expect(find.text('Sound ist live auf der Matribox aktiv'), findsOneWidget);
    expect(find.textContaining('speichere ihn jetzt direkt an der Matribox'), findsOneWidget);
    expect(find.byKey(readback), findsNothing); // no manual readback button before the checkpoint
    expect(find.byKey(send), findsNothing);
    expect(read.reads, 1);

    // "Ich habe gespeichert" itself is the confirmation -- the readback that follows is automatic.
    read.parts = savedAfterTransfer(); // the device now holds the saved sound
    await taps(tester, [manualSave]);
    expect(transfer.executions, hasLength(1));
    expect(read.reads, 2);
    expect(find.byKey(readbackConfirm), findsNothing);
    expect(find.byKey(const Key('tt-readback-certified')), findsOneWidget);
    expect(find.text('Preset erfolgreich gespeichert'), findsOneWidget);
    expect(find.textContaining('Das Speichern erfolgte manuell an der Matribox'), findsOneWidget);
    expect(find.textContaining('MANUAL_SAVE_PERSISTENCE_VERIFIED'), findsOneWidget);
    expect(transfer.executions, hasLength(1)); // verification never writes
  });

  testWidgets(
    'REGRESSION: after Sound A is VERIFIED, opening the page for a DIFFERENT sound never shows '
    'a leftover VERIFIED card -- it is a fresh, unprepared session',
    (tester) async {
      // Sound A: full success, exactly as above.
      await show(tester);
      await taps(tester, [send, sendConfirm]);
      read.parts = savedAfterTransfer();
      await taps(tester, [manualSave]);
      expect(find.byKey(const Key('tt-success')), findsOneWidget);

      // Sound B: a genuinely different target (never a re-run of the exact same request), opened
      // the way a person would -- Dein Sound -> Auf Matribox übertragen -- WITHOUT tapping
      // "Neuen Sound senden" first.
      final soundB = angels.withTarget(readyTarget());
      await show(tester, recommendation: soundB);

      expect(find.byKey(const Key('tt-phase-verified')), findsNothing, reason: "Sound A's leftover VERIFIED card must not leak into Sound B's page");
      expect(find.byKey(const Key('tt-success')), findsNothing);
      expect(find.byKey(send), findsOneWidget, reason: 'Sound B starts from a clean, unprepared state');
      expect(find.text('Ziel: Matribox 1 · Preset P11'), findsOneWidget);

      // Sound B goes through its OWN full, independent lifecycle -- a brand new plan, a brand new
      // live write, nothing carried over from Sound A.
      await taps(tester, [send, sendConfirm]);
      // `transfer` is the shared channel from setUp() -- Sound A already contributed one execution,
      // so exactly one MORE (a brand new plan) is the correct total for Sound B's own write.
      expect(transfer.executions, hasLength(2), reason: 'exactly one NEW execution for Sound B, on top of Sound A\'s earlier one');
      // `read` is the shared channel too: its fresh read for Sound B's own prepare/plan sees the
      // device the way Sound A's transfer actually left it, not the original BEFORE snapshot.
      final afterSoundA = savedAfterTransfer();
      final plan = MatriboxToneTransferPlan.build(
        current: layoutFrom(afterSoundA),
        target: soundB.target,
        ledger: MatriboxHardwareLedger.product(),
        backupSha256: 'x',
        presetNumber: 11,
        isUserBank: true,
        transportAvailable: true,
        library: soundB.library,
      );
      read.parts = deviceAfter(plan.operations, from: afterSoundA);
      await taps(tester, [manualSave]);
      expect(find.byKey(const Key('tt-success')), findsOneWidget);
    },
  );

  testWidgets('"Neuen Sound senden" then the identical sound again: no unnecessary write, friendly "already saved" message', (tester) async {
    final soundB = angels.withTarget(readyTarget());
    await show(tester, recommendation: soundB);
    await taps(tester, [send, sendConfirm]);
    read.parts = deviceAfter(
      MatriboxToneTransferPlan.build(
        current: beforeLayout(),
        target: soundB.target,
        ledger: MatriboxHardwareLedger.product(),
        backupSha256: 'x',
        presetNumber: 11,
        isUserBank: true,
        transportAvailable: true,
        library: soundB.library,
      ).operations,
    );
    await taps(tester, [manualSave]);
    expect(find.byKey(const Key('tt-success')), findsOneWidget);
    expect(transfer.executions, hasLength(1));

    // "Neuen Sound senden" only ends this UI session -- the device is left exactly as it is
    // (already matching soundB's target). Sending the SAME sound again in the SAME page instance
    // must recognise nothing needs to change.
    await taps(tester, [const Key('tt-new-sound')]);
    await taps(tester, [send]);
    expect(find.text('Dieser Sound ist bereits auf P11 gespeichert.'), findsOneWidget);
    expect(find.byKey(sendConfirm), findsNothing);
    expect(transfer.executions, hasLength(1), reason: 'no unnecessary rewrite of an already-matching preset');
  });

  testWidgets('TARGET_MISMATCH: reread or re-prepare, never an automatic resend', (tester) async {
    await show(tester);
    await taps(tester, [send, sendConfirm]);
    // forgot to save: the read still returns the old saved preset
    await taps(tester, [manualSave]);
    expect(find.textContaining('TARGET_MISMATCH'), findsOneWidget);
    expect(find.text('Transfer nicht verifiziert'), findsOneWidget);
    expect(find.text('Erneut lesen'), findsOneWidget);
    expect(find.byKey(send), findsNothing);
    expect(transfer.executions, hasLength(1));

    read.parts = savedAfterTransfer();
    await taps(tester, [readback, readbackConfirm]);
    expect(find.byKey(const Key('tt-success')), findsOneWidget);
    expect(transfer.executions, hasLength(1));
  });

  testWidgets('disconnect / power-off after the live write makes the session STALE; a fresh read decides', (tester) async {
    await show(tester);
    await taps(tester, [send, sendConfirm]);
    expect(find.text('Sound ist live auf der Matribox aktiv'), findsOneWidget);

    transfer.token = 'gen-2'; // the device was switched off / reconnected
    await show(tester); // app restart: the stored session is reloaded
    expect(find.byKey(const Key('tt-phase-stale')), findsOneWidget);
    expect(find.text('Erneut lesen'), findsOneWidget);
    expect(find.text('Sound ist live auf der Matribox aktiv'), findsNothing);
    expect(find.byKey(manualSave), findsNothing);

    // the stored state is still the OLD preset: not verified
    await taps(tester, [readback, readbackConfirm]);
    expect(find.textContaining('TARGET_MISMATCH'), findsOneWidget);
    expect(find.byKey(const Key('tt-success')), findsNothing);
    expect(transfer.executions, hasLength(1));
  });

  testWidgets('a mid-run failure shows completed / failed / notSent, no automatic continuation', (tester) async {
    final failing = RecordingTransfer(failAt: 2);
    await show(tester, channel: failing);
    await taps(tester, [send, sendConfirm]);
    expect(failing.executions, hasLength(1));
    expect(failing.requests, hasLength(3));
    expect(find.text('⚠ Übertragung gestoppt'), findsOneWidget);
    expect(find.textContaining('Prüfprotokoll: completed: 2 · failed: 1 · notSent: 8'), findsOneWidget);
    expect(find.byKey(send), findsNothing);
  });

  testWidgets('a wrong bank read is refused and no plan is shown', (tester) async {
    read.parts = hexParts(bigBeforeRawPartsHex)..forEach((p) => p[13] = 0x01);
    await show(tester);
    await taps(tester, [send]);
    expect(find.byKey(sendConfirm), findsNothing);
    expect(find.byKey(const Key('tt-message')), findsOneWidget);
  });

  testWidgets('double tap on "An Matribox senden" triggers at most one prepare and one live write', (tester) async {
    await show(tester);
    await tester.runAsync(() async {
      // Two taps in the same frame, before either prepare has had a chance to disable the button.
      await tester.tap(find.byKey(send));
      await tester.tap(find.byKey(send));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    expect(read.reads, 1, reason: 'only one prepare ran despite two taps');
    expect(find.byKey(sendConfirm), findsOneWidget);

    await taps(tester, [sendConfirm]);
    expect(transfer.executions, hasLength(1));
  });

  testWidgets('leaving the page while PREPARING (back navigation) writes nothing and does not crash', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ToneTransferPage(
                      recommendation: angels,
                      readChannel: read,
                      transferChannel: transfer,
                      backupDirectory: () async => tempDir,
                      nameCatalogLoader: () async => toneCatalog, targetSlot: 11,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Tap "An Matribox senden" and leave immediately, while the real read+backup (PREPARING) is
      // still in flight -- before the confirm dialog has even had a chance to appear.
      await tester.tap(find.byKey(send));
      await tester.pump();
      navigatorKey.currentState!.pop();
      await tester.pump();
      // Let the in-flight prepare() actually finish so its late setState calls run against a
      // disposed State -- this is exactly the scenario that must not crash or write.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'a late setState after the page was popped must be a no-op, not a crash');
    expect(transfer.executions, isEmpty, reason: 'leaving during PREPARING must never reach a live write');
    expect(find.byType(ToneTransferPage), findsNothing);
  });
}
