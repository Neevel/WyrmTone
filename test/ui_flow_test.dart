import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/controllers/recommendation_controller.dart';
import 'package:wyrmtone/controllers/usb_controller.dart';
import 'package:wyrmtone/devices/device_profile.dart';
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/models/usb_models.dart';
import 'package:wyrmtone/midi/midi_capture_controller.dart';
import 'package:wyrmtone/screens/app_shell.dart';
import 'package:wyrmtone/services/local_persistence.dart';
import 'package:wyrmtone/services/offline_sound_profiles.dart';
import 'package:wyrmtone/ui/wyrm_design.dart';

import 'support/recommendation_fakes.dart';
import 'support/fake_usb_service.dart';

void main() {
  test(
    'central device and diagnostic labels preserve actual states in German',
    () {
      final service = FakeUsbService();
      final usb = UsbController(service);
      addTearDown(usb.dispose);
      addTearDown(service.dispose);
      expect(deviceStatusLabel(usb), 'Kein unterstütztes Gerät erkannt');
      usb.devices = [matriboxDevice(hasPermission: true)];
      expect(deviceStatusLabel(usb), contains('erkannt'));
      usb.midiConnection = const MidiConnectionStatus(
        isOpen: true,
        deviceId: 7,
      );
      expect(deviceStatusLabel(usb), 'MIDI-Verbindung geöffnet');
      usb.midiConnection = const MidiConnectionStatus(isOpen: false);
      usb.connection = const UsbConnectionStatus(isOpen: true);
      expect(deviceStatusLabel(usb), 'USB-Verbindung geöffnet');
      usb.connection = const UsbConnectionStatus(isOpen: false);
      usb.devices = [];
      expect(deviceStatusLabel(usb), 'Kein unterstütztes Gerät erkannt');
      expect(midiCaptureStatusLabel(MidiCaptureState.disconnected), 'getrennt');
      for (final state in MidiCaptureState.values) {
        expect(midiCaptureStatusLabel(state), isNot(state.name));
      }
    },
  );
  for (final width in [320.0, 900.0]) {
    testWidgets('navigation and confirmed correction at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FakeUsbService();
      addTearDown(service.dispose);
      final usb = UsbController(service);
      addTearDown(usb.dispose);
      await usb.initialize();
      final store = MemoryStringStore();
      final c = RecommendationController(
        profileRepository: ProfileRepository(store),
        irRepository: IrCatalogRepository(store),
        filePicker: FakeIrFilePicker(),
      );
      addTearDown(c.dispose);
      await c.saveProfile(
        const GuitarProfile(
          id: 'g',
          name: 'Marshall Testgitarre',
          guitarType: GuitarType.superstrat,
          pickupType: PickupType.passiveHumbucker,
          outputLevel: OutputLevel.high,
          toneCharacter: ToneCharacter.neutral,
          tuning: GuitarTuning.dropC,
          playbackPath: PlaybackPath.headphones,
        ),
      );
      c.offlineProfiles = OfflineSoundProfiles.decode(
        File('assets/catalog/sound_profiles.json').readAsStringSync(),
      );
      c.selectTargetDevice(TargetDeviceId.matriboxOne);
      await tester.pumpWidget(
        MaterialApp(
          theme: WyrmTokens.theme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.4 : 1)),
            child: child!,
          ),
          home: AppShell(usbController: usb, recommendationController: c),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> reveal(Finder finder) async {
        if (finder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            finder,
            200,
            scrollable: find
                .descendant(
                  of: find.byKey(const Key('recommendation-view')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
        }
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        final rect = tester.getRect(finder);
        final navigation = tester.getRect(find.byType(NavigationBar));
        expect(
          rect.bottom,
          lessThanOrEqualTo(navigation.top),
          reason: 'Action must stay above bottom navigation',
        );
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(finder.hitTestable(), findsOneWidget);
      }

      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Gerät'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('diagnostic-log')), findsNothing);
      expect(find.text('Verifizierter Matribox-Schreibtest'), findsNothing);
      await tester.tap(find.text('Bibliothek'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NAM'));
      await tester.pumpAndSettle();
      expect(find.text('NAM-Bibliothek nicht eingerichtet'), findsOneWidget);
      await tester.tap(find.text('Profil'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Aktuell ausgewählt'), findsOneWidget);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dashboard-create')));
      await tester.pumpAndSettle();
      expect(find.text('Schritt 1 von 7'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byKey(const Key('wizard-step-menu')), findsOneWidget);
      final summary = tester.widget<Text>(
        find.byKey(const Key('wizard-summary')),
      );
      expect(summary.maxLines, isNull);
      expect(summary.overflow, isNull);
      if (width == 320) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        await tester.pumpAndSettle();
        await reveal(find.byKey(const Key('offline-request')));
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
      }
      for (var step = 0; step < 3; step++) {
        await reveal(find.byKey(const Key('wizard-next')));
        await tester.tap(find.byKey(const Key('wizard-next')));
        await tester.pumpAndSettle();
        expect(find.text('Schritt ${step + 2} von 7'), findsOneWidget);
      }
      await reveal(find.byKey(const Key('offline-create')));
      await tester.tap(find.byKey(const Key('offline-create')));
      await tester.pumpAndSettle();
      expect(c.offlineDraft, isNotNull);
      expect(
        find.text('Offline erstellt · Keine KI verwendet'),
        findsOneWidget,
      );
      expect(find.textContaining('Rhythmus'), findsWidgets);
      final original = c.offlineDraft;
      for (var step = 0; step < 1; step++) {
        await reveal(find.byKey(const Key('wizard-next')));
        await tester.tap(find.byKey(const Key('wizard-next')));
        await tester.pumpAndSettle();
      }
      if (width == 320) {
        await reveal(find.byKey(const Key('open-preset-workspace')));
        await tester.tap(find.byKey(const Key('open-preset-workspace')));
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Preset planen'), findsOneWidget);
        final workspaceScroll = find.byType(Scrollable).last;
        for (final key in const [
          Key('preset-export'),
          Key('preset-import'),
          Key('preset-transfer-disabled'),
        ]) {
          await tester.scrollUntilVisible(
            find.byKey(key),
            300,
            scrollable: workspaceScroll,
          );
          expect(find.byKey(key), findsOneWidget);
        }
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('preset-transfer-disabled')),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.textContaining('vollständige Matribox-Presetübertragung'),
          findsOneWidget,
        );
        await tester.tap(find.text('Wählen').first);
        await tester.pumpAndSettle();
        expect(find.text('Nur Planung – noch keine Übertragung'), findsWidgets);
        expect(service.openCalls, 0);
        expect(service.midiOpenCalls, 0);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      await reveal(find.byKey(const Key('wizard-next')));
      await tester.tap(find.byKey(const Key('wizard-next')));
      await tester.pumpAndSettle();
      await reveal(find.text('Zu schrill'));
      await tester.tap(find.text('Zu schrill'));
      await tester.pumpAndSettle();
      expect(c.offlineDraft, same(original));
      await reveal(find.byKey(const Key('offline-apply')));
      await tester.tap(find.byKey(const Key('offline-apply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offline-apply')), findsNothing);
      await reveal(find.byKey(const Key('offline-undo')));
      await tester.tap(find.byKey(const Key('offline-undo')));
      await tester.pumpAndSettle();
      expect(c.offlineDraft, same(original));
      expect(service.openCalls, 0);
      expect(service.midiOpenCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
