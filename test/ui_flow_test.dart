import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/controllers/usb_controller.dart';
import 'package:wyrmtone/devices/device_profile.dart';
import 'package:wyrmtone/models/usb_models.dart';
import 'package:wyrmtone/midi/midi_capture_controller.dart';
import 'package:wyrmtone/ui/wyrm_design.dart';

import 'support/fake_usb_service.dart';
import 'support/sound_flow_support.dart';

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
    testWidgets('navigation, sound flow and confirmed correction at width $width', (tester) async {
      final rig = await pumpShell(tester, width: width, height: 900, textScale: width == 320 ? 1.4 : 1);
      final service = rig.usbService;
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Profil'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('open-device-settings')), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('open-device-settings')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('open-advanced-diagnostics')), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('open-advanced-diagnostics')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('diagnostic-log')), findsNothing);
      expect(find.text('Verifizierter Matribox-Schreibtest'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
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
      expect(find.byKey(const Key('sound-search')), findsOneWidget);
      expect(find.text('Schritt 1 von 7'), findsNothing);

      rig.controller.selectTargetDevice(TargetDeviceId.matriboxOne);
      await search(tester, 'Master of Puppets Rhythmus');
      await tapVisible(tester, find.byKey(const Key('sound-result-song.metallica.master_of_puppets')));
      await tapVisible(tester, find.byKey(const Key('use-sound')));
      final original = rig.controller.offlineDraft;
      expect(original, isNotNull);
      expect(find.byKey(const Key('your-sound-title')), findsOneWidget);
      // the action stays above the bottom navigation and reachable
      await tester.scrollUntilVisible(find.byKey(const Key('open-tone-transfer')), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Auf Matribox übertragen'), findsOneWidget);

      if (width == 320) {
        await tapVisible(tester, find.byKey(const Key('open-preset-workspace')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
        await tester.pumpAndSettle();
        expect(find.text('Preset planen'), findsOneWidget);
        final workspaceScroll = find.byType(Scrollable).last;
        for (final key in const [Key('preset-export'), Key('preset-import'), Key('preset-transfer-disabled')]) {
          await tester.scrollUntilVisible(find.byKey(key), 300, scrollable: workspaceScroll);
          expect(find.byKey(key), findsOneWidget);
        }
        expect(tester.widget<FilledButton>(find.byKey(const Key('preset-transfer-disabled'))).onPressed, isNull);
        expect(find.textContaining('vollständige Matribox-Presetübertragung'), findsOneWidget);
        await tester.tap(find.text('Wählen').first);
        await tester.pumpAndSettle();
        expect(find.text('Nur Planung – noch keine Übertragung'), findsWidgets);
        expect(service.openCalls, 0);
        expect(service.midiOpenCalls, 0);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      await tapVisible(tester, find.byKey(const Key('fine-tune')));
      await tapVisible(tester, find.text('Zu schrill'));
      expect(rig.controller.offlineDraft, same(original));
      await tapVisible(tester, find.byKey(const Key('offline-apply')));
      expect(find.byKey(const Key('offline-apply')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('offline-undo')));
      expect(rig.controller.offlineDraft, same(original));
      expect(service.openCalls, 0);
      expect(service.midiOpenCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
