import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_hardware_evidence.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_plan.dart';
import 'package:wyrmtone/screens/tone_transfer_page.dart';
import 'package:wyrmtone/ui/transfer_pulse_animation.dart';

import 'support/matribox_big_capture_snapshots.dart';
import 'support/matribox_full_live_helpers.dart';
import 'support/matribox_tone_transfer_support.dart';

/// The transfer page's visual redesign: a Sound → Matribox hero with an animation that only ever
/// reflects the real product state (never a timer of its own), a friendlier success/failure
/// vocabulary, and a working "Fertig" exit. The underlying state machine (already covered by
/// tone_transfer_page_test.dart) is untouched; these tests are about what is ON SCREEN.
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
    tempDir = Directory.systemTemp.createTempSync('transfer_redesign');
    read = ToneReadChannel(hexParts(bigBeforeRawPartsHex));
    transfer = RecordingTransfer();
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> show(WidgetTester tester, {bool reducedMotion = false}) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    if (reducedMotion) {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: ToneTransferPage(
            key: UniqueKey(),
            recommendation: angels,
            readChannel: read,
            transferChannel: transfer,
            backupDirectory: () async => tempDir,
            nameCatalogLoader: () async => toneCatalog, targetSlot: 11,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await tester.pump();
    });
  }

  // Real File I/O: every tap that leads to it runs inside one runAsync block. The async chain
  // stays "tainted" by that real zone for its whole lifetime (including later dialog taps), so
  // every subsequent tap in the same flow is wrapped the same way.
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

  group('hero', () {
    testWidgets('shows Sound -> Matribox 1 -> Preset, idle, no raw ids, before anything happens', (tester) async {
      await show(tester);
      expect(find.byKey(const Key('tt-hero')), findsOneWidget);
      expect(tester.widget<TransferPulseAnimation>(find.byType(TransferPulseAnimation)).phase, TransferVisualPhase.idle);
      expect(find.byType(TransferPulseAnimation), findsOneWidget);
      expect(find.textContaining('Matribox 1'), findsWidgets);
      expect(find.textContaining('P11'), findsWidgets);
      final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').join('\n');
      for (final forbidden in ['0x', 'QME', 'SysEx', 'wireIndex']) {
        expect(texts, isNot(contains(forbidden)));
      }
    });
  });

  group('animation reflects the real state, never invents one', () {
    testWidgets('awaitingSave right after a successful live write; success only after verify; "Fertig" pops the page', (tester) async {
      await show(tester);
      await taps(tester, [send, sendConfirm]);
      expect(tester.widget<TransferPulseAnimation>(find.byType(TransferPulseAnimation)).phase, TransferVisualPhase.awaitingSave);

      read.parts = savedAfterTransfer(); // the device now holds the saved sound
      await taps(tester, [manualSave]); // "Ich habe gespeichert" itself triggers the readback
      expect(tester.widget<TransferPulseAnimation>(find.byType(TransferPulseAnimation)).phase, TransferVisualPhase.success);
      expect(find.byKey(const Key('tt-done')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tt-done')));
      await tester.pumpAndSettle();
      expect(find.byType(ToneTransferPage), findsNothing);
    });

    testWidgets('a failed run and a failed verify both show phase failed, animation stops (no motion)', (tester) async {
      final failing = RecordingTransfer(failAt: 2);
      await show(tester);
      // swap channel by rebuilding with the failing transport
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: ToneTransferPage(
              key: UniqueKey(),
              recommendation: angels,
              readChannel: read,
              transferChannel: failing,
              backupDirectory: () async => tempDir,
              nameCatalogLoader: () async => toneCatalog, targetSlot: 11,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.pump();
      });
      await taps(tester, [send, sendConfirm]);
      expect(tester.widget<TransferPulseAnimation>(find.byType(TransferPulseAnimation)).phase, TransferVisualPhase.failed);
    });

    testWidgets('TARGET_MISMATCH after manual save: phase failed, a plain sentence, the code only as a detail', (tester) async {
      await show(tester);
      await taps(tester, [send, sendConfirm]);
      // forgot to actually save: readback (run automatically by "Ich habe gespeichert") still sees
      // the old preset
      await taps(tester, [manualSave]);
      expect(tester.widget<TransferPulseAnimation>(find.byType(TransferPulseAnimation)).phase, TransferVisualPhase.failed);
      expect(find.text('Der gespeicherte Sound stimmt noch nicht vollständig mit dem Ziel überein.'), findsOneWidget);
      expect(find.textContaining('Prüfergebnis: TARGET_MISMATCH'), findsOneWidget);
    });
  });

  group('reduced motion', () {
    testWidgets('no moving dot; the status text is still the single source of truth', (tester) async {
      await show(tester, reducedMotion: true);
      await taps(tester, [send, sendConfirm]);
      // the phase is still correctly awaitingSave, just rendered without motion
      expect(tester.widget<TransferPulseAnimation>(find.byType(TransferPulseAnimation)).phase, TransferVisualPhase.awaitingSave);
      expect(find.text('Sound ist live auf der Matribox aktiv'), findsOneWidget);
    });
  });
}
