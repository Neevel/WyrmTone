import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/screens/matribox_safe_write_lab_panel.dart';

import 'support/matribox_p01_readback_fixtures.dart';

void main() {
  const channel = MethodChannel('de.neevel.wyrmtone/usb_methods');
  var calls = <String>[];
  var writeArguments = <Map<Object?, Object?>>[];
  var nextWriteResponse = {'outcome': 'SUCCESS', 'error': null};
  late Directory tempDir;

  setUp(() {
    calls = <String>[];
    writeArguments = <Map<Object?, Object?>>[];
    nextWriteResponse = {'outcome': 'SUCCESS', 'error': null};
    tempDir = Directory.systemTemp.createTempSync('matribox_safe_write_lab_panel');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'readMatriboxUserP01':
              expect(call.arguments, isNull);
              return {
                'outcome': 'SUCCESS',
                'phaseDResponse': matriboxHex(matriboxPhaseDAcknowledgement),
                'parts': matriboxP01RealFullCycle.map(matriboxHex).toList(),
                'error': null,
              };
            case 'writeConfirmedSol100OdGain':
              writeArguments.add(call.arguments as Map<Object?, Object?>);
              return nextWriteResponse;
            default:
              fail('Unexpected method ${call.method}');
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MatriboxSafeWriteLabPanel(
              enabled: true,
              connectionReady: true,
              monitoring: false,
              backupDirectory: () async => tempDir,
            ),
          ),
        ),
      ),
    );
  }

  // Real File/Directory I/O (via MatriboxRawBackupService) must run inside
  // a single runAsync block together with every tap/pump that depends on
  // it -- see matribox_raw_backup_panel_test.dart for why.
  Future<void> prepareAndConfirm(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('matribox-safe-write-lab-prepare')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('matribox-safe-write-lab-confirm')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await tester.pumpAndSettle();
  }

  testWidgets('disabled build renders nothing and calls nothing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MatriboxSafeWriteLabPanel(
          enabled: false,
          connectionReady: true,
          monitoring: false,
          backupDirectory: () async => tempDir,
        ),
      ),
    );
    expect(find.byKey(const Key('matribox-safe-write-lab-panel')), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('shows the accurate LAB description before any action', (tester) async {
    await show(tester);
    expect(find.text('Matribox Safe Write'), findsOneWidget);
    expect(find.text('LAB'), findsOneWidget);
    expect(find.textContaining('gelesen, gesichert und der Schreibplan geprüft'), findsOneWidget);
    // The description must no longer claim writes are impossible -- the
    // write button can genuinely send once a plan is ready.
    expect(find.textContaining('Es wird noch keine Änderung an das Gerät gesendet'), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('requires explicit confirmation before reading anything', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const Key('matribox-safe-write-lab-prepare')));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  testWidgets(
    'a prepared plan shows Gain 17 -> 18, WRITE CONFIRMED, all else unchanged',
    (tester) async {
      await show(tester);
      await prepareAndConfirm(tester);

      expect(calls, ['readMatriboxUserP01']);
      expect(find.textContaining('CKY 96 STUD'), findsOneWidget);
      expect(find.textContaining('gain: 17 → 18'), findsOneWidget);
      expect(find.textContaining('WRITE CONFIRMED'), findsOneWidget);
      expect(find.text('Alle anderen Felder: UNCHANGED'), findsOneWidget);
      final writeButton = tester.widget<FilledButton>(
        find.byKey(const Key('matribox-safe-write-lab-write')),
      );
      expect(writeButton.onPressed, isNotNull);
    },
  );

  testWidgets(
    'the first click on the write button only opens the confirmation dialog -- nothing is sent',
    (tester) async {
      await show(tester);
      await prepareAndConfirm(tester);

      await tester.tap(find.byKey(const Key('matribox-safe-write-lab-write')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Diese Änderung wird jetzt an die Matribox gesendet'), findsOneWidget);
      expect(find.textContaining('Kein Store wird gesendet'), findsOneWidget);
      expect(find.textContaining('Sol 100 OD · Gain 17 → 18'), findsOneWidget);
      expect(calls, ['readMatriboxUserP01']);
      expect(writeArguments, isEmpty);
    },
  );

  testWidgets('cancelling the confirmation dialog sends nothing', (tester) async {
    await show(tester);
    await prepareAndConfirm(tester);

    await tester.tap(find.byKey(const Key('matribox-safe-write-lab-write')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    expect(calls, ['readMatriboxUserP01']);
    expect(writeArguments, isEmpty);
  });

  testWidgets(
    'confirming sends exactly one write call with the derived target value, no Store, no second Read',
    (tester) async {
      await show(tester);
      await prepareAndConfirm(tester);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('matribox-safe-write-lab-write')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('matribox-safe-write-lab-write-confirm')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      });
      await tester.pumpAndSettle();

      expect(calls, ['readMatriboxUserP01', 'writeConfirmedSol100OdGain']);
      expect(writeArguments, [{'targetGain': 18.0}]);
      expect(find.text('✓ Gain-Write gesendet'), findsOneWidget);
      expect(find.text('Status: VOLATILE_WRITE_SENT'), findsOneWidget);
      expect(find.text('Readback noch nicht verifiziert'), findsOneWidget);
      expect(find.text('Preset noch nicht dauerhaft gespeichert'), findsOneWidget);

      // No Store call exists on this channel/session at all, and no
      // second read is ever triggered automatically after a send.
      expect(calls.where((c) => c == 'readMatriboxUserP01'), hasLength(1));
      expect(calls.any((c) => c.toLowerCase().contains('store')), isFalse);
    },
  );

  testWidgets('a rejected write shows the outcome, not a silent success', (tester) async {
    nextWriteResponse = {'outcome': 'SEND_FAILED', 'error': 'Transport-Fehler.'};
    await show(tester);
    await prepareAndConfirm(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('matribox-safe-write-lab-write')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('matribox-safe-write-lab-write-confirm')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    expect(writeArguments, [{'targetGain': 18.0}]);
    expect(find.textContaining('Senden ist fehlgeschlagen'), findsOneWidget);
    expect(find.text('✓ Gain-Write gesendet'), findsNothing);
  });

  testWidgets('disabled when connection is not ready', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MatriboxSafeWriteLabPanel(
          enabled: true,
          connectionReady: false,
          monitoring: false,
          backupDirectory: () async => tempDir,
        ),
      ),
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('matribox-safe-write-lab-prepare')),
    );
    expect(button.onPressed, isNull);
  });
}
