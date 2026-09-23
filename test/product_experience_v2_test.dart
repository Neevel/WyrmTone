import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/controllers/usb_controller.dart';
import 'package:wyrmtone/devices/device_profile.dart';
import 'package:wyrmtone/presets/matribox_hardware_evidence.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_plan.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_session.dart';
import 'package:wyrmtone/presets/matribox_transfer_slots.dart';
import 'package:wyrmtone/screens/device_prepare_page.dart';
import 'package:wyrmtone/screens/device_settings_page.dart';
import 'package:wyrmtone/screens/tone_transfer_page.dart';
import 'package:wyrmtone/tone3000/tone3000_config.dart';
import 'package:wyrmtone/ui/preset_slot_picker.dart';

import 'support/fake_usb_service.dart';
import 'support/matribox_tone_transfer_support.dart';

void main() {
  group('PresetSlotPicker (bottom sheet, not a 99-button grid)', () {
    testWidgets('shows every slot, P01-P10 protected and not pickable, P11-P99 pickable', (tester) async {
      int? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => picked = await PresetSlotPicker.pick(context, selected: null),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('P01–P10 sind geschützt. Für Übertragungen stehen P11–P99 zur Verfügung.'), findsOneWidget);
      expect(find.byKey(const Key('slot-picker-P01')), findsOneWidget);
      expect(tester.widget<ListTile>(find.byKey(const Key('slot-picker-P01'))).enabled, isFalse);
      expect(find.text('Geschützt – wird nicht überschrieben'), findsWidgets);
      // a protected slot cannot be picked: tapping it keeps the sheet open and returns nothing
      await tester.tap(find.byKey(const Key('slot-picker-P01')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('slot-picker-list')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('slot-picker-search')), '10');
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(find.byKey(const Key('slot-picker-P10'))).enabled, isFalse);
      await tester.enterText(find.byKey(const Key('slot-picker-search')), '50');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('slot-picker-P50')), findsOneWidget);
      expect(find.byKey(const Key('slot-picker-P01')), findsNothing);
      expect(tester.widget<ListTile>(find.byKey(const Key('slot-picker-P50'))).enabled, isTrue);
      await tester.tap(find.byKey(const Key('slot-picker-P50')));
      await tester.pumpAndSettle();
      expect(picked, 50);
    });
  });

  group('DevicePreparePage: no default slot, protected slots never continue', () {
    testWidgets('P11 target: continue is enabled', (tester) async {
      final rec = angelsRecommendation();
      await tester.pumpWidget(MaterialApp(home: DevicePreparePage(recommendation: rec, targetSlot: 11)));
      await tester.pump();
      expect(find.textContaining('P11'), findsWidgets);
      expect(tester.widget<FilledButton>(find.byKey(const Key('prepare-continue'))).onPressed, isNotNull);
    });

    for (final protected in [1, 5, 10]) {
      testWidgets('P${protected.toString().padLeft(2, '0')} target: shown as protected, continue stays blocked', (tester) async {
        final rec = angelsRecommendation();
        await tester.pumpWidget(MaterialApp(home: DevicePreparePage(recommendation: rec, targetSlot: protected)));
        await tester.pump();
        expect(find.textContaining('P${protected.toString().padLeft(2, '0')}'), findsWidgets);
        expect(tester.widget<FilledButton>(find.byKey(const Key('prepare-continue'))).onPressed, isNull);
        expect(find.textContaining(MatriboxTransferSlots.protectedSlotExplanation), findsWidgets);
      });
    }

    testWidgets('no slot chosen: nothing defaults to P01 or P11, continue stays blocked', (tester) async {
      final rec = angelsRecommendation();
      await tester.pumpWidget(MaterialApp(home: DevicePreparePage(recommendation: rec)));
      await tester.pump();
      expect(find.text('Kein Speicherplatz gewählt'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('prepare-continue'))).onPressed, isNull);
      expect(find.textContaining(MatriboxTransferSlots.noSlotExplanation), findsWidgets);
    });

    testWidgets('the slot chosen on the page is the slot the transfer step is bound to', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rec = angelsRecommendation();
      int? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: DevicePreparePage(
            recommendation: rec,
            transferPage: (context, slot) {
              opened = slot;
              return const Scaffold(body: Text('transfer'));
            },
          ),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('prepare-slot-picker')));
      await tester.tap(find.byKey(const Key('prepare-slot-picker')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('slot-picker-search')), '37');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('slot-picker-P37')));
      await tester.pumpAndSettle();
      expect(find.text('Preset P37'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('prepare-continue')));
      await tester.tap(find.byKey(const Key('prepare-continue')));
      await tester.pumpAndSettle();
      expect(opened, 37);
    });
  });

  group('ToneTransferPage: an app-noticed disconnect goes STALE immediately, not only on next load', () {
    late Directory tempDir;
    setUp(() => tempDir = Directory.systemTemp.createTempSync('t3k_stale'));
    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    testWidgets('a liveWriteComplete session flips to stale the instant the central connection state leaves connected', (tester) async {
      final rec = angelsRecommendation();
      final store = MatriboxToneTransferStore(File('${tempDir.path}/tone_transfer_P11.state'));
      final service = FakeUsbService()..devices = [matriboxDevice(hasPermission: true)];
      addTearDown(service.dispose);
      final usb = UsbController(service);
      addTearDown(usb.dispose);

      await tester.runAsync(() async {
        final plan = MatriboxToneTransferPlan.build(
          current: beforeLayout(),
          target: rec.target,
          ledger: MatriboxHardwareLedger.product(),
          backupSha256: 'x',
          presetNumber: 11,
          isUserBank: true,
          transportAvailable: true,
          library: rec.library,
        );
        await store.save(
          MatriboxToneTransferRecord(
            targetSlot: 11,
            writtenSlot: 11,
            planFingerprint: plan.fingerprint,
            beforeBackupPath: 'x',
            beforeBackupSha256: 'x',
            target: rec.target,
            operations: const [],
            sentAt: DateTime.utc(2026),
            state: ToneTransferRecordState.liveWriteComplete,
            sessionToken: 'gen-1',
          ),
        );
        await usb.initialize();
      });

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: ToneTransferPage(
              recommendation: rec,
              backupDirectory: () async => tempDir,
              usbController: usb,
              transferChannel: RecordingTransfer(), targetSlot: 11,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tt-phase-stale')), findsNothing, reason: 'still connected');

      await tester.runAsync(() async {
        service.devices = [];
        await service.emit({'type': 'detached'});
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tt-phase-stale')), findsOneWidget);

      final saved = await tester.runAsync(() => store.load());
      expect(saved!.state, ToneTransferRecordState.stale);
    });
  });

  group('DeviceSettingsPage: Auto-Connect toggle, status, Erweiterte Diagnose link', () {
    testWidgets('shows status and lets the user turn Auto-Connect off', (tester) async {
      final service = FakeUsbService();
      addTearDown(service.dispose);
      final usb = UsbController(service);
      addTearDown(usb.dispose);
      await usb.initialize();
      expect(usb.autoConnect, isTrue);

      await tester.pumpWidget(MaterialApp(home: DeviceSettingsPage(controller: usb)));
      await tester.pumpAndSettle();
      expect(find.text('Keine Matribox verbunden'), findsOneWidget);
      await tester.tap(find.byKey(const Key('device-settings-autoconnect')));
      await tester.pumpAndSettle();
      expect(usb.autoConnect, isFalse);
      expect(find.byKey(const Key('open-advanced-diagnostics')), findsOneWidget);
    });
  });

  group('TONE3000 client id default (public, never a secret)', () {
    test('ships non-empty by default and is not misclassified as unconfigured', () {
      final config = Tone3000Config.fromEnvironment();
      expect(config.isConfigured, isTrue);
      expect(config.validationMessage, isNull);
    });
  });

  group('DeviceCapabilities reflects reality: preset transfer confirmed, IR/NAM upload not', () {
    test('Matribox 1: supportsPresetTransfer confirmed, supportsIrTransfer/supportsNamTransfer not implemented', () {
      const caps = MatriboxOneAdapter();
      final capabilities = caps.capabilities;
      expect(capabilities.supportsPresetTransfer, CapabilityVerification.confirmed);
      expect(capabilities.supportsIrTransfer, CapabilityVerification.notImplemented);
      expect(capabilities.supportsNamTransfer, CapabilityVerification.notImplemented);
    });
  });
}
