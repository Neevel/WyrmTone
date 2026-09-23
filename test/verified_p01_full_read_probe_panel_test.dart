import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/screens/verified_p01_full_read_probe_panel.dart';

import 'support/matribox_p01_readback_fixtures.dart';

void main() {
  const channel = MethodChannel('de.neevel.wyrmtone/usb_methods');
  var calls = <String>[];
  var attempted = false;
  Map<Object?, Object?> Function() sendResponse = () => {
    'success': true,
    'completedParts': 10,
    'chunks': <Object?>[],
    'logs': <String>[],
  };

  setUp(() {
    calls = <String>[];
    attempted = false;
    sendResponse = () => {
      'success': true,
      'completedParts': 10,
      'chunks': <Object?>[],
      'logs': <String>[],
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.arguments, isNull);
          calls.add(call.method);
          switch (call.method) {
            case 'getVerifiedPresetP01FullReadProbeStatus':
              return {
                'enabled': true,
                'ready': true,
                'attempted': attempted,
                'connection': 'usb/box',
                'sessionToken': 1,
                'logs': <String>[],
              };
            case 'sendVerifiedPresetP01FullReadProbe':
              attempted = true;
              return sendResponse();
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
            child: VerifiedP01FullReadProbePanel(
              enabled: true,
              connectionReady: true,
              monitoring: false,
            ),
          ),
        ),
      ),
    );
    await tester.tap(
      find.text('Experimenteller P01-Full-Read-Einmaltest (V2)'),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirmSend(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('p01-full-read-probe-checkbox')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('p01-full-read-probe-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('p01-full-read-probe-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('disabled build renders nothing and calls nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VerifiedP01FullReadProbePanel(
          enabled: false,
          connectionReady: true,
          monitoring: false,
        ),
      ),
    );
    expect(
      find.text('Experimenteller P01-Full-Read-Einmaltest (V2)'),
      findsNothing,
    );
    expect(calls, isEmpty);
  });

  testWidgets('exposes only the fixed, parameterless full-read controls', (
    tester,
  ) async {
    await show(tester);
    expect(find.textContaining('Sonicake Matribox 1'), findsOneWidget);
    expect(
      find.text('Einmalig P01-Full-Read (10 Teile) senden'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(DropdownButton<int>), findsNothing);
  });

  testWidgets(
    'checkbox and confirmation are required, then the connection is locked',
    (tester) async {
      await show(tester);
      await confirmSend(tester);
      expect(
        calls.where((call) => call == 'sendVerifiedPresetP01FullReadProbe'),
        hasLength(1),
      );
      expect(
        find.text('Test in dieser Verbindung bereits ausgeführt'),
        findsOneWidget,
      );
    },
  );

  testWidgets('CONFIRMED: all ten parts assembled into a matching cycle', (
    tester,
  ) async {
    sendResponse = () => {
      'success': true,
      'completedParts': 10,
      'chunks': [
        for (final part in matriboxP01RealCycle)
          {'bytes': matriboxHex(part), 'timestampNanos': 1},
      ],
      'logs': <String>[],
    };
    await show(tester);
    await confirmSend(tester);
    expect(find.textContaining('READBACK_CONFIRMED'), findsOneWidget);
    expect(find.textContaining('10/10'), findsOneWidget);
  });

  testWidgets('stopped early: reports completed part count and stop reason', (
    tester,
  ) async {
    sendResponse = () => {
      'success': true,
      'completedParts': 3,
      'stopReason': 'Teil 3: Timeout nach 500 ms.',
      'chunks': [
        for (final part in matriboxP01RealCycle.take(3))
          {'bytes': matriboxHex(part), 'timestampNanos': 1},
      ],
      'logs': <String>[],
    };
    await show(tester);
    await confirmSend(tester);
    expect(find.textContaining('READBACK_INCOMPLETE'), findsOneWidget);
    expect(find.textContaining('3/10'), findsOneWidget);
    expect(
      find.textContaining('Teil 3: Timeout nach 500 ms.'),
      findsOneWidget,
    );
  });
}
