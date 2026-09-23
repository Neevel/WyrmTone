import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/screens/verified_p01_full_read_probe_v3a_panel.dart';

import 'support/matribox_p01_readback_fixtures.dart';

void main() {
  const channel = MethodChannel('de.neevel.wyrmtone/usb_methods');
  var calls = <String>[];
  var attempted = false;
  Map<Object?, Object?> Function() sendResponse = () => {
    'success': true,
    'phaseDConfirmed': true,
    'completedParts': 10,
    'chunks': <Object?>[],
    'logs': <String>[],
  };

  setUp(() {
    calls = <String>[];
    attempted = false;
    sendResponse = () => {
      'success': true,
      'phaseDConfirmed': true,
      'completedParts': 10,
      'chunks': <Object?>[],
      'logs': <String>[],
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.arguments, isNull);
          calls.add(call.method);
          switch (call.method) {
            case 'getVerifiedPresetP01FullReadProbeV3AStatus':
              return {
                'enabled': true,
                'ready': true,
                'attempted': attempted,
                'connection': 'usb/box',
                'sessionToken': 1,
                'logs': <String>[],
              };
            case 'sendVerifiedPresetP01FullReadProbeV3A':
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
            child: VerifiedP01FullReadProbeV3APanel(
              enabled: true,
              connectionReady: true,
              monitoring: false,
            ),
          ),
        ),
      ),
    );
    await tester.tap(
      find.text('Experimenteller P01-Full-Read-Einmaltest (V3A)'),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirmSend(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('p01-full-read-probe-v3a-checkbox')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('p01-full-read-probe-v3a-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('p01-full-read-probe-v3a-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('disabled build renders nothing and calls nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VerifiedP01FullReadProbeV3APanel(
          enabled: false,
          connectionReady: true,
          monitoring: false,
        ),
      ),
    );
    expect(
      find.text('Experimenteller P01-Full-Read-Einmaltest (V3A)'),
      findsNothing,
    );
    expect(calls, isEmpty);
  });

  testWidgets('exposes only the fixed, parameterless V3A controls', (
    tester,
  ) async {
    await show(tester);
    expect(find.textContaining('Sonicake Matribox 1'), findsOneWidget);
    expect(
      find.text('Einmalig Phase D + P01-Full-Read (V3A) senden'),
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
        calls.where((call) => call == 'sendVerifiedPresetP01FullReadProbeV3A'),
        hasLength(1),
      );
      expect(
        find.text('Test in dieser Verbindung bereits ausgeführt'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Phase D not confirmed is reported distinctly', (tester) async {
    sendResponse = () => {
      'success': true,
      'phaseDConfirmed': false,
      'completedParts': 0,
      'stopReason': 'Phase D: Timeout nach 500 ms.',
      'chunks': <Object?>[],
      'logs': <String>[],
    };
    await show(tester);
    await confirmSend(tester);
    expect(find.textContaining('READBACK_INCOMPLETE_PHASE_D'), findsOneWidget);
    expect(find.textContaining('Phase D bestätigt: false'), findsOneWidget);
  });

  testWidgets('CONFIRMED: Phase D confirmed and all ten parts assembled', (
    tester,
  ) async {
    sendResponse = () => {
      'success': true,
      'phaseDConfirmed': true,
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
    expect(find.textContaining('Phase D bestätigt: true'), findsOneWidget);
    expect(find.textContaining('10/10'), findsOneWidget);
  });

  testWidgets('complete readback with changed marker is reported as mismatch', (
    tester,
  ) async {
    final changedPart1 = matriboxHex(matriboxP01Part1);
    // Gain is decoded at concatenated payload offset 188: byte 92 of
    // decoded part 1, represented here as eight nibbles from offset 201.
    changedPart1[205] = 0x09;
    changedPart1[206] = 0x00;
    sendResponse = () => {
      'success': true,
      'phaseDConfirmed': true,
      'completedParts': 10,
      'chunks': [
        {'bytes': matriboxHex(matriboxP01Part0), 'timestampNanos': 1},
        {'bytes': changedPart1, 'timestampNanos': 1},
        for (final part in matriboxP01RealCycle.skip(2))
          {'bytes': matriboxHex(part), 'timestampNanos': 1},
      ],
      'logs': <String>[],
    };

    await show(tester);
    await confirmSend(tester);

    expect(
      find.textContaining('READBACK_RECEIVED_BUT_MISMATCH'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Phase D confirmed but a part fails: distinct from Phase-D failure',
    (tester) async {
      sendResponse = () => {
        'success': true,
        'phaseDConfirmed': true,
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
      expect(find.textContaining('READBACK_INCOMPLETE_PART_N'), findsOneWidget);
      expect(find.textContaining('Phase D bestätigt: true'), findsOneWidget);
      expect(find.textContaining('3/10'), findsOneWidget);
    },
  );
}
