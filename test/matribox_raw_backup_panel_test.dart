import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/screens/matribox_raw_backup_panel.dart';

import 'support/matribox_p01_readback_fixtures.dart';

void main() {
  const channel = MethodChannel('de.neevel.wyrmtone/usb_methods');
  var calls = <String>[];
  Map<Object?, Object?> Function() readResponse = () => {
    'outcome': 'SUCCESS',
    'phaseDResponse': matriboxHex(matriboxPhaseDAcknowledgement),
    'parts': matriboxP01RealFullCycle.map(matriboxHex).toList(),
    'error': null,
  };
  late Directory tempDir;

  setUp(() {
    calls = <String>[];
    tempDir = Directory.systemTemp.createTempSync('matribox_raw_backup_panel');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'readMatriboxUserP01':
              expect(call.arguments, isNull);
              return readResponse();
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
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MatriboxRawBackupPanel(
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

  Future<void> tapBackupAndConfirm(WidgetTester tester) async {
    // _confirmAndBackup (which performs real File/Directory I/O) is
    // invoked synchronously by the first tap below; a Dart async
    // function's zone is fixed at the point it is first called, so the
    // whole interaction -- both taps and every pump in between -- must run
    // inside a single runAsync callback for the real I/O futures it later
    // awaits to ever resolve under TestWidgetsFlutterBinding's fake clock.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('matribox-raw-backup-button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('matribox-raw-backup-confirm')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await tester.pumpAndSettle();
  }

  testWidgets('disabled build renders nothing and calls nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MatriboxRawBackupPanel(
          enabled: false,
          connectionReady: true,
          monitoring: false,
          backupDirectory: () async => tempDir,
        ),
      ),
    );
    expect(find.byKey(const Key('matribox-raw-backup-panel')), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('shows the plain-language, read-only description before any action', (
    tester,
  ) async {
    await show(tester);
    expect(find.textContaining('Sonicake Matribox 1'), findsOneWidget);
    expect(find.textContaining('User P01'), findsOneWidget);
    expect(find.textContaining('nur lesen'), findsOneWidget);
    expect(
      find.text('Raw-Backup von P01 erstellen'),
      findsOneWidget,
    );
    expect(calls, isEmpty);
  });

  testWidgets('requires explicit confirmation before sending anything', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byKey(const Key('matribox-raw-backup-button')));
    await tester.pumpAndSettle();
    expect(calls, isEmpty); // dialog shown, nothing sent yet
    expect(find.text('Abbrechen'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  testWidgets(
    'success shows a status card with checkmarks, short hash, date and '
    'preset name -- no hex dump',
    (tester) async {
      await show(tester);
      await tapBackupAndConfirm(tester);

      expect(calls, ['readMatriboxUserP01']);
      expect(find.byKey(const Key('matribox-raw-backup-message')), findsOneWidget);
      expect(find.text('gelesen'), findsOneWidget);
      expect(find.text('validiert'), findsOneWidget);
      expect(find.text('lokal gesichert'), findsOneWidget);
      expect(find.textContaining('CKY 96 STUD'), findsWidgets);
      expect(find.textContaining('P01'), findsWidgets);
      expect(find.textContaining('Hash:'), findsOneWidget);
      // The full hash/file path are inside the collapsed "Backupdetails"
      // section until expanded.
      expect(find.textContaining(tempDir.path), findsNothing);
      await tester.tap(find.byKey(const Key('matribox-raw-backup-details')));
      await tester.pumpAndSettle();
      expect(find.textContaining(tempDir.path), findsOneWidget);
      expect(tempDir.listSync().whereType<File>(), isNotEmpty);

      // No raw hex dump anywhere in the rendered text.
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
      expect(texts, isNot(matches(RegExp(r'F0 21 25 7F'))));
    },
  );

  testWidgets('a native timeout is reported in plain language, no hex', (
    tester,
  ) async {
    readResponse = () => {
      'outcome': 'PHASE_D_TIMEOUT',
      'phaseDResponse': null,
      'parts': <Object?>[],
      'error': 'Phase D wurde nicht bestätigt.',
    };
    await show(tester);
    await tapBackupAndConfirm(tester);

    expect(find.textContaining('fehlgeschlagen'), findsOneWidget);
    expect(find.textContaining('Leseanfrage'), findsOneWidget);
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    expect(texts, isNot(contains('PHASE_D_TIMEOUT')));
  });

  testWidgets('disabled when connection is not ready', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MatriboxRawBackupPanel(
          enabled: true,
          connectionReady: false,
          monitoring: false,
          backupDirectory: () async => tempDir,
        ),
      ),
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('matribox-raw-backup-button')),
    );
    expect(button.onPressed, isNull);
    expect(
      find.text('Passende Matribox eindeutig als MIDI-Gerät öffnen.'),
      findsOneWidget,
    );
  });

  testWidgets('disabled while the passive monitor is running', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MatriboxRawBackupPanel(
          enabled: true,
          connectionReady: true,
          monitoring: true,
          backupDirectory: () async => tempDir,
        ),
      ),
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('matribox-raw-backup-button')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Passiven Monitor zuerst stoppen.'), findsOneWidget);
  });
}
