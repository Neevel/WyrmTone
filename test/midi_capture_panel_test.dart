import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/midi/midi_capture_controller.dart';
import 'package:wyrmtone/midi/midi_receive_source.dart';
import 'package:wyrmtone/screens/midi_capture_panel.dart';
import 'package:wyrmtone/app.dart';
import 'package:wyrmtone/models/usb_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_midi_receive_source.dart';
import 'support/fake_usb_service.dart';

class FakeExporter implements MidiCaptureExporter {
  String? json;
  @override
  Future<bool> exportJson(String json) async {
    this.json = json;
    return true;
  }
}

void main() {
  testWidgets('explicit start stop marker clear and JSON export', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final source = FakeMidiReceiveSource();
    final c = MidiCaptureController(source);
    final exporter = FakeExporter();
    addTearDown(() async {
      c.dispose();
      await source.dispose();
    });
    c.updateConnection(detected: true, opened: true, name: 'Matribox');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MidiCapturePanel(controller: c, exporter: exporter),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(source.starts, 0);
    await tester.tap(find.byKey(const Key('capture-start')));
    await tester.pump();
    source.receive([0xB0, 7, 41]);
    await tester.pump(const Duration(milliseconds: 110));
    expect(find.textContaining('Empfangene Chunks: 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('capture-marker')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Gain 40 → 41');
    await tester.tap(find.text('Setzen'));
    await tester.pumpAndSettle();
    expect(c.entries.last.marker, 'Gain 40 → 41');
    await tester.tap(find.byKey(const Key('capture-export')));
    await tester.pumpAndSettle();
    expect(source.active, isFalse);
    expect(exporter.json, contains('"receiveOnly": true'));
    await tester.tap(find.byKey(const Key('capture-clear')));
    await tester.pumpAndSettle();
    expect(c.entries, isEmpty);
  });
  testWidgets(
    'Matribox advanced Raw USB disabled during MIDI; app pause closes capture',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1200, 8000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = FakeUsbService()
        ..devices = [matriboxDevice(hasPermission: true)]
        ..midiDevices = [matriboxMidiDevice()]
        ..midiConnection = const MidiConnectionStatus(
          isOpen: true,
          deviceId: 7,
        );
      addTearDown(service.dispose);
      await tester.pumpWidget(WyrmToneApp(usbService: service));
      await tester.pumpAndSettle();
      // Reach the diagnostics the same way a person does: Profil -> Geräte -> Erweiterte Diagnose
      // (the "Gerät" bottom-navigation tab was retired; see docs of the V2 navigation restructure).
      await tester.tap(find.text('Profil'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('open-device-settings')), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('open-device-settings')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('open-advanced-diagnostics')), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('open-advanced-diagnostics')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-button')), findsNothing);
      await tester.tap(find.byKey(const Key('advanced-diagnostics')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('raw-usb-diagnostics')), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('raw-usb-diagnostics')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('open-button')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('capture-start')));
      await tester.pump();
      expect(service.midiReceiveSource.active, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(service.midiReceiveSource.active, isFalse);
      expect(service.midiCloseCalls, greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(service.midiReceiveSource.starts, 1);
    },
  );
}
