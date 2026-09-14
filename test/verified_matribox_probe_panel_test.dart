import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/screens/verified_matribox_probe_panel.dart';

void main() {
  const channel = MethodChannel('de.neevel.wyrmtone/usb_methods');
  var sends = 0;
  var attempted = false;
  var success = true;
  setUp(() {
    sends = 0;
    attempted = false;
    success = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.arguments, isNull);
          switch (call.method) {
            case 'getVerifiedMatriboxProbeStatus':
              return {
                'enabled': true,
                'ready': true,
                'attempted': attempted,
                'connection': 'usb/box',
                'sessionToken': 1,
                'logs': <String>[],
              };
            case 'sendVerifiedSol100OdGain41Probe':
              ++sends;
              attempted = true;
              return {
                'success': success,
                'error': success ? null : 'Portfehler.',
                'logs': [
                  'SEND_ATTEMPT',
                  success ? 'SEND_SUCCESS' : 'SEND_FAILED',
                  'PORT_CLOSED',
                ],
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
  Future<void> show(
    WidgetTester tester, {
    bool enabled = true,
    bool ready = true,
    bool monitoring = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VerifiedMatriboxProbePanel(
              enabled: enabled,
              connectionReady: ready,
              monitoring: monitoring,
            ),
          ),
        ),
      ),
    );
    if (enabled) {
      await tester.tap(find.text('Verifizierter Matribox-Schreibtest'));
      await tester.pumpAndSettle();
    }
  }

  FilledButton button(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('probe-send')));
  Future<void> checkAndRequest(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('probe-checkbox')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('probe-send')));
    await tester.pumpAndSettle();
  }

  testWidgets('normal flag hides developer area', (tester) async {
    expect(matriboxWriteProbeEnabled, isFalse);
    await show(tester, enabled: false);
    expect(find.text('Verifizierter Matribox-Schreibtest'), findsNothing);
    expect(sends, 0);
  });
  testWidgets('warnings and checkbox required; no free values', (tester) async {
    await show(tester);
    expect(
      find.textContaining('Der aktuelle Gerätezustand kann'),
      findsOneWidget,
    );
    expect(find.textContaining('speichert kein Preset'), findsOneWidget);
    expect(button(tester).onPressed, isNull);
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(sends, 0);
  });
  testWidgets('wrong device unavailable', (tester) async {
    await show(tester, ready: false);
    expect(button(tester).onPressed, isNull);
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('probe-checkbox')))
          .onChanged,
      isNull,
    );
  });
  testWidgets('monitor must stop', (tester) async {
    await show(tester, monitoring: true);
    expect(find.text('Passiven Monitor zuerst stoppen.'), findsOneWidget);
    expect(button(tester).onPressed, isNull);
  });
  testWidgets('dialog mandatory; cancellation sends nothing', (tester) async {
    await show(tester);
    await checkAndRequest(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(sends, 0);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(sends, 0);
  });
  testWidgets('confirmed fixed call once then button disabled', (tester) async {
    await show(tester);
    await checkAndRequest(tester);
    await tester.tap(find.byKey(const Key('probe-confirm')));
    await tester.pumpAndSettle();
    expect(sends, 1);
    expect(button(tester).onPressed, isNull);
    expect(
      find.text('Test in dieser Verbindung bereits ausgeführt'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Android hat die Bytes angenommen'),
      findsOneWidget,
    );
  });
  testWidgets('failure understandable and consumed', (tester) async {
    success = false;
    await show(tester);
    await checkAndRequest(tester);
    await tester.tap(find.byKey(const Key('probe-confirm')));
    await tester.pumpAndSettle();
    expect(sends, 1);
    expect(button(tester).onPressed, isNull);
    expect(
      find.textContaining('Es wurde kein weiterer Sendeversuch durchgeführt.'),
      findsOneWidget,
    );
  });
  testWidgets('pause during confirmation never sends', (tester) async {
    await show(tester);
    await checkAndRequest(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await tester.tap(find.byKey(const Key('probe-confirm')));
    await tester.pumpAndSettle();
    expect(sends, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
