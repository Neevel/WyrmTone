import 'package:wyrmtone/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_usb_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> renderApp(WidgetTester tester, FakeUsbService service) async {
    await tester.binding.setSurfaceSize(const Size(1200, 8000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(WyrmToneApp(usbService: service));
  }

  testWidgets('renders safely without an attached USB device', (tester) async {
    final service = FakeUsbService();
    addTearDown(service.dispose);

    await renderApp(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('Kein unterstütztes Gerät verbunden'), findsOneWidget);
    expect(find.byKey(const Key('no-devices')), findsOneWidget);
    expect(find.byKey(const Key('search-button')), findsOneWidget);
    expect(find.byKey(const Key('permission-button')), findsNothing);
  });

  testWidgets('highlights a DNAfx and offers permission', (tester) async {
    final service = FakeUsbService()..devices = [dnafxDevice()];
    addTearDown(service.dispose);

    await renderApp(tester, service);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('USB-Berechtigung erforderlich'),
      findsOneWidget,
    );
    expect(find.textContaining('DNAfx GiT Core erkannt'), findsWidgets);
    expect(find.byKey(const Key('permission-button')), findsOneWidget);
    expect(find.byKey(const Key('open-button')), findsNothing);
  });

  testWidgets('shows interfaces and endpoints after permission', (
    tester,
  ) async {
    final service = FakeUsbService()
      ..devices = [dnafxDevice(hasPermission: true)];
    addTearDown(service.dispose);

    await renderApp(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('DNAfx GiT Core erkannt'), findsOneWidget);
    expect(find.textContaining('Interface 0'), findsOneWidget);
    expect(find.textContaining('0x81 · IN · Interrupt'), findsOneWidget);
    expect(find.textContaining('0x02 · OUT · Interrupt'), findsOneWidget);
    expect(find.byKey(const Key('open-button')), findsOneWidget);
  });

  testWidgets('open and close actions update visible status', (tester) async {
    final service = FakeUsbService()
      ..devices = [dnafxDevice(hasPermission: true)];
    addTearDown(service.dispose);

    await renderApp(tester, service);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-button')));
    await tester.pumpAndSettle();

    expect(find.text('DNAfx GiT Core verbunden (read-only)'), findsOneWidget);
    expect(find.byKey(const Key('close-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('close-button')));
    await tester.pumpAndSettle();
    expect(find.text('DNAfx GiT Core erkannt'), findsOneWidget);
    expect(service.closeCalls, 1);
  });

  testWidgets('detach event returns UI to disconnected state', (tester) async {
    final service = FakeUsbService()
      ..devices = [dnafxDevice(hasPermission: true)];
    addTearDown(service.dispose);

    await renderApp(tester, service);
    await tester.pumpAndSettle();
    service.devices = [];
    await service.emit({'type': 'detached'});
    await tester.pumpAndSettle();

    expect(find.text('Kein unterstütztes Gerät verbunden'), findsOneWidget);
    expect(find.byKey(const Key('no-devices')), findsOneWidget);
  });

  testWidgets('shows Matribox candidate and allows permission request', (
    tester,
  ) async {
    final service = FakeUsbService()..devices = [matriboxDevice()];
    addTearDown(service.dispose);

    await renderApp(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('WyrmTone'), findsOneWidget);
    expect(find.textContaining('Sonicake Matribox 1 erkannt'), findsOneWidget);
    expect(find.textContaining('Kandidat erkannt'), findsOneWidget);
    expect(find.byKey(const Key('permission-button')), findsOneWidget);
    expect(find.byKey(const Key('open-button')), findsNothing);
  });

  testWidgets('shows Matribox relevant interface only after permission', (
    tester,
  ) async {
    final service = FakeUsbService()
      ..devices = [matriboxDevice(hasPermission: true)];
    addTearDown(service.dispose);

    await renderApp(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('Sonicake Matribox 1 erkannt'), findsOneWidget);
    expect(
      find.textContaining('Interface 3 (Alt 0) · relevante'),
      findsOneWidget,
    );
    expect(find.textContaining('0x83 · IN · Bulk'), findsOneWidget);
    expect(find.textContaining('0x03 · OUT · Bulk'), findsOneWidget);
    expect(find.byKey(const Key('open-button')), findsNothing);
    await tester.tap(find.byKey(const Key('advanced-diagnostics')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-button')), findsOneWidget);
  });

  testWidgets('shows MIDI ports and opens and closes only the MIDI device', (
    tester,
  ) async {
    final service = FakeUsbService()
      ..devices = [matriboxDevice(hasPermission: true)]
      ..midiDevices = [matriboxMidiDevice()];
    addTearDown(service.dispose);

    await renderApp(tester, service);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('midi-open-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('midi-open-button')));
    await tester.pumpAndSettle();
    expect(
      service.openCalls,
      0,
      reason: 'MIDI öffnen darf Raw USB nicht öffnen.',
    );

    await tester.dragUntilVisible(
      find.byKey(const Key('midi-device-7')),
      find.byType(Scrollable).first,
      const Offset(0, -500),
    );
    expect(find.text('Android MIDI-Geräte'), findsOneWidget);
    expect(find.text('Input-Port 0'), findsOneWidget);
    expect(find.text('Output-Port 0'), findsOneWidget);

    await tester.dragUntilVisible(
      find.byKey(const Key('midi-close-button')),
      find.byType(Scrollable).first,
      const Offset(0, 500),
    );
    await tester.tap(find.byKey(const Key('midi-close-button')));
    await tester.pumpAndSettle();
    expect(service.midiCloseCalls, 1);
  });
}
