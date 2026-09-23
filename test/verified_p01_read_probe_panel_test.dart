import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/screens/verified_p01_read_probe_panel.dart';

import 'support/matribox_p01_readback_fixtures.dart';

void main() {
  const channel = MethodChannel('de.neevel.wyrmtone/usb_methods');
  var calls = <String>[];
  var attempted = false;
  Map<Object?, Object?> Function() sendResponse = () => {
    'success': true,
    'chunks': <Object?>[],
    'logs': <String>['SEND_ATTEMPT', 'SEND_SUCCESS'],
  };

  setUp(() {
    calls = <String>[];
    attempted = false;
    sendResponse = () => {
      'success': true,
      'chunks': <Object?>[],
      'logs': <String>['SEND_ATTEMPT', 'SEND_SUCCESS'],
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.arguments, isNull);
          calls.add(call.method);
          switch (call.method) {
            case 'getVerifiedPresetP01ReadProbeStatus':
              return {
                'enabled': true,
                'ready': true,
                'attempted': attempted,
                'connection': 'usb/box',
                'sessionToken': 1,
                'logs': <String>[],
              };
            case 'sendVerifiedPresetP01ReadProbe':
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
            child: VerifiedP01ReadProbePanel(
              enabled: true,
              connectionReady: true,
              monitoring: false,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Experimenteller P01-Read-Einmaltest'));
    await tester.pumpAndSettle();
  }

  Future<void> confirmSend(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('p01-read-probe-checkbox')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('p01-read-probe-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('p01-read-probe-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('disabled build renders nothing and calls nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VerifiedP01ReadProbePanel(
          enabled: false,
          connectionReady: true,
          monitoring: false,
        ),
      ),
    );
    expect(find.text('Experimenteller P01-Read-Einmaltest'), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('exposes only the fixed, parameterless read-probe controls', (
    tester,
  ) async {
    await show(tester);
    expect(find.textContaining('Sonicake Matribox 1'), findsOneWidget);
    expect(
      find.text('Einmalig P01-Read-Request senden'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(DropdownButton<int>), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('p01-read-probe-send')))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'checkbox and confirmation are required, then the connection is locked',
    (tester) async {
      await show(tester);
      await confirmSend(tester);
      expect(
        calls.where((call) => call == 'sendVerifiedPresetP01ReadProbe'),
        hasLength(1),
      );
      expect(
        find.text('Test in dieser Verbindung bereits ausgeführt'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('p01-read-probe-send')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('CONFIRMED: matching full cycle is reported as confirmed', (
    tester,
  ) async {
    sendResponse = () => {
      'success': true,
      'chunks': [
        {
          'bytes': [
            for (final part in matriboxP01RealCycle) ...matriboxHex(part),
          ],
          'timestampNanos': 1,
        },
      ],
      'logs': <String>[],
    };
    await show(tester);
    await confirmSend(tester);
    expect(find.textContaining('READBACK_CONFIRMED'), findsOneWidget);
  });

  testWidgets('TIMEOUT: no bytes at all', (tester) async {
    sendResponse = () => {'success': true, 'chunks': <Object?>[], 'logs': <String>[]};
    await show(tester);
    await confirmSend(tester);
    expect(find.textContaining('READBACK_TIMEOUT'), findsOneWidget);
  });

  testWidgets('INCOMPLETE: only part 0 received', (tester) async {
    sendResponse = () => {
      'success': true,
      'chunks': [
        {'bytes': matriboxHex(matriboxP01Part0), 'timestampNanos': 1},
      ],
      'logs': <String>[],
    };
    await show(tester);
    await confirmSend(tester);
    expect(find.textContaining('READBACK_INCOMPLETE'), findsOneWidget);
  });

  testWidgets(
    'MISMATCH: a decoded value differing from the reference is reported, not hidden',
    (tester) async {
      final part1 = matriboxHex(matriboxP01Part1);
      // Flip the Gain float bytes (last 4 decoded bytes of part 1) so the
      // decoded value no longer matches the confirmed reference of 17.0.
      part1[part1.length - 5] = 0x00;
      part1[part1.length - 4] = 0x00;
      part1[part1.length - 3] = 0x00;
      part1[part1.length - 2] = 0x00;
      sendResponse = () => {
        'success': true,
        'chunks': [
          {
            'bytes': [
              ...matriboxHex(matriboxP01Part0),
              ...part1,
              for (final part in matriboxP01RealCycle.skip(2))
                ...matriboxHex(part),
            ],
            'timestampNanos': 1,
          },
        ],
        'logs': <String>[],
      };
      await show(tester);
      await confirmSend(tester);
      expect(
        find.textContaining('READBACK_RECEIVED_BUT_MISMATCH'),
        findsOneWidget,
      );
    },
  );
}
