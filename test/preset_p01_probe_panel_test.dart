import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/screens/verified_matribox_probe_panel.dart';

void main() {
  const channel = MethodChannel('de.neevel.wyrmtone/usb_methods');
  var calls = <String>[];
  var attempted = false;

  setUp(() {
    calls = <String>[];
    attempted = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.arguments, isNull);
          calls.add(call.method);
          switch (call.method) {
            case 'getVerifiedPresetP01ProbeStatus':
              return {
                'enabled': true,
                'ready': true,
                'attempted': attempted,
                'connection': 'usb/box',
                'sessionToken': 1,
                'logs': <String>[],
              };
            case 'sendVerifiedPresetP01SelectionProbe':
              attempted = true;
              return {
                'success': true,
                'sendCalls': 2,
                'logs': <String>['SEND_ATTEMPT', 'SEND_SUCCESS', 'PORT_CLOSED'],
              };
            default:
              fail('Unexpected method ${call.method}');
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VerifiedMatriboxProbePanel(
              enabled: false,
              p01Enabled: true,
              connectionReady: true,
              monitoring: false,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Verifizierter Matribox-Schreibtest'));
    await tester.pumpAndSettle();
  }

  testWidgets('P01 build exposes only fixed P01 controls and warning', (
    tester,
  ) async {
    await show(tester);
    expect(find.textContaining('Sonicake Matribox 1'), findsOneWidget);
    expect(find.text('Einmalig P01 auswählen'), findsOneWidget);
    expect(
      find.textContaining('Kein Speichern und kein Überschreiben'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Ungespeicherte Änderungen am aktuell aktiven Preset können verloren gehen.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Gain 41'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(DropdownButton<int>), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('probe-send')))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'checkbox and confirmation are required, then connection is locked',
    (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('probe-checkbox')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('probe-send')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        calls.where((call) => call == 'sendVerifiedPresetP01SelectionProbe'),
        isEmpty,
      );
      await tester.tap(find.byKey(const Key('probe-confirm')));
      await tester.pumpAndSettle();
      expect(
        calls.where((call) => call == 'sendVerifiedPresetP01SelectionProbe'),
        hasLength(1),
      );
      expect(
        find.text('Test in dieser Verbindung bereits ausgeführt'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('probe-send')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('both compile switches fail closed', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VerifiedMatriboxProbePanel(
          enabled: true,
          p01Enabled: true,
          connectionReady: true,
          monitoring: false,
        ),
      ),
    );
    expect(find.text('Verifizierter Matribox-Schreibtest'), findsNothing);
    expect(calls, isEmpty);
  });
}
