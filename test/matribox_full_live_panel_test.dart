import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_full_live_plan.dart';
import 'package:wyrmtone/screens/matribox_full_live_panel.dart';

import 'support/matribox_big_capture_snapshots.dart';
import 'support/matribox_full_live_helpers.dart';
import 'support/matribox_p01_readback_fixtures.dart';

void main() {
  const channel = MethodChannel('de.neevel.wyrmtone/usb_methods');
  var calls = <String>[];
  var runArguments = <Object?>[];
  var runFails = false;
  var readParts = <List<int>>[];
  late Directory tempDir;

  Map<Object?, Object?> runResponse() {
    final ops = MatriboxFullLivePlan.operations;
    final done = runFails ? 7 : ops.length;
    return {
      'outcome': runFails ? 'SEND_FAILED' : 'SUCCESS',
      'error': runFails ? 'Transport-Fehler.' : null,
      'total': ops.length,
      'completed': done,
      'failedIndex': runFails ? 7 : null,
      'operations': [
        for (var i = 0; i < ops.length; i++)
          {
            'index': i,
            'label': ops[i].label,
            'status': i < done ? 'SENT' : (runFails && i == 7 ? 'FAILED' : 'NOT_SENT'),
          },
      ],
    };
  }

  setUp(() {
    calls = <String>[];
    runArguments = <Object?>[];
    runFails = false;
    readParts = hexParts(bigBeforeRawPartsHex);
    tempDir = Directory.systemTemp.createTempSync('matribox_fl_panel');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'readMatriboxUserP01':
            return {
              'outcome': 'SUCCESS',
              'phaseDResponse': matriboxHex(matriboxPhaseDAcknowledgement),
              'parts': readParts,
              'error': null,
            };
          case 'runFullLiveP01Certification':
            runArguments.add(call.arguments);
            return runResponse();
          default:
            fail('Unexpected method ${call.method}');
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> show(WidgetTester tester, {bool enabled = true}) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MatriboxFullLivePanel(
                enabled: enabled,
                connectionReady: true,
                monitoring: false,
                backupDirectory: () async => tempDir,
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
  }

  // Real File I/O: every tap that leads to it runs inside one runAsync block.
  Future<void> taps(WidgetTester tester, List<Key> keys) async {
    await tester.runAsync(() async {
      for (final key in keys) {
        await tester.tap(find.byKey(key));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  const prepare = Key('matribox-fl-prepare');
  const prepareConfirm = Key('matribox-fl-prepare-confirm');
  const start = Key('matribox-fl-start');
  const startConfirm = Key('matribox-fl-start-confirm');
  const readback = Key('matribox-fl-readback');
  const readbackConfirm = Key('matribox-fl-readback-confirm');

  testWidgets('disabled build renders nothing and calls nothing', (tester) async {
    await show(tester, enabled: false);
    expect(find.byKey(const Key('matribox-fl-panel')), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('prepare reads only; cancelling sends nothing; plan card shows counts and warning', (tester) async {
    await show(tester);
    expect(find.text('Matribox Full Live Edit Certification'), findsOneWidget);
    expect(find.text('LAB'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(prepare));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);

    await taps(tester, [prepare, prepareConfirm]);
    expect(calls, ['readMatriboxUserP01']);
    expect(find.byKey(const Key('matribox-fl-counts')), findsOneWidget);
    expect(find.textContaining('9 Modellwahlen'), findsOneWidget);
    expect(find.textContaining('14 Parameter'), findsOneWidget);
    expect(find.textContaining('2 Blockschalter'), findsOneWidget);
    expect(find.textContaining('kein Store-Befehl'), findsOneWidget);
    expect(find.byKey(start), findsOneWidget);
    expect(runArguments, isEmpty);
  });

  testWidgets('start needs its own confirmation; cancel sends nothing; confirm = exactly one call with the plan id only', (tester) async {
    await show(tester);
    await taps(tester, [prepare, prepareConfirm]);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(start));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('kein Store-Befehl'), findsWidgets);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(runArguments, isEmpty);

    await taps(tester, [start, startConfirm]);
    expect(runArguments, [
      {'planId': MatriboxFullLivePlan.planId},
    ]);
    expect(calls.where((c) => c == 'runFullLiveP01Certification'), hasLength(1));
    expect(calls.where((c) => c == 'readMatriboxUserP01'), hasLength(1)); // no auto readback
    expect(find.byKey(const Key('matribox-fl-run-success')), findsOneWidget);
    expect(find.textContaining('25 von 25'), findsOneWidget);
    expect(find.textContaining('VOLATILE'), findsOneWidget);
    expect(find.byKey(start), findsNothing); // consumed: a new attempt needs a new prepare
    expect(find.byKey(readback), findsOneWidget);
  });

  testWidgets('failure shows completed / failed / not sent, no retry', (tester) async {
    runFails = true;
    await show(tester);
    await taps(tester, [prepare, prepareConfirm, start, startConfirm]);
    expect(runArguments, hasLength(1));
    expect(find.byKey(const Key('matribox-fl-run-stopped')), findsOneWidget);
    expect(find.textContaining('Abgeschlossen: 7 von 25'), findsOneWidget);
    expect(find.textContaining('Fehlgeschlagen: #7'), findsOneWidget);
    expect(find.textContaining('Nicht gesendet: 17'), findsOneWidget);
    expect(find.byKey(start), findsNothing);
  });

  testWidgets('a P01 already holding the target state blocks the plan', (tester) async {
    readParts = afterFromPlan();
    await show(tester);
    await taps(tester, [prepare, prepareConfirm]);
    expect(find.byKey(start), findsNothing);
    expect(find.byKey(const Key('matribox-fl-message')), findsOneWidget);
    expect(find.textContaining('P01_BEFORE_BIG_CAPTURE.prst'), findsOneWidget);
    expect(runArguments, isEmpty);
  });

  testWidgets('manual readback certifies the state the plan produces; no write, no store', (tester) async {
    await show(tester);
    await taps(tester, [prepare, prepareConfirm, start, startConfirm]);
    readParts = afterFromPlan();
    await taps(tester, [readback, readbackConfirm]);
    expect(find.byKey(const Key('matribox-fl-readback-certified')), findsOneWidget);
    expect(find.text('CERTIFIED'), findsOneWidget);
    expect(calls.where((c) => c == 'runFullLiveP01Certification'), hasLength(1));
    expect(calls.every((c) => c == 'readMatriboxUserP01' || c == 'runFullLiveP01Certification'), isTrue);
  });
}
