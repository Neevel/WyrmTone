import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/screens/matribox_amp_certification_panel.dart';

import 'support/matribox_p01_readback_fixtures.dart';

void _setFloatAt(List<int> part, int rawStart, double value) {
  final data = ByteData(4)..setFloat32(0, value, Endian.little);
  for (var i = 0; i < 4; i++) {
    final byte = data.getUint8(i);
    part[rawStart + i * 2] = byte >> 4;
    part[rawStart + i * 2 + 1] = byte & 0x0f;
  }
}

void main() {
  const channel = MethodChannel('de.neevel.wyrmtone/usb_methods');
  var calls = <String>[];
  var writeArguments = <Map<Object?, Object?>>[];
  var writeResponse = <String, Object?>{'outcome': 'SUCCESS', 'error': null};
  var readParts = <List<int>>[];
  late Directory tempDir;

  setUp(() {
    calls = <String>[];
    writeArguments = <Map<Object?, Object?>>[];
    writeResponse = {'outcome': 'SUCCESS', 'error': null};
    readParts = matriboxP01RealFullCycle.map(matriboxHex).toList();
    tempDir = Directory.systemTemp.createTempSync('matribox_cert_panel');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'readMatriboxUserP01':
              expect(call.arguments, isNull);
              return {
                'outcome': 'SUCCESS',
                'phaseDResponse': matriboxHex(matriboxPhaseDAcknowledgement),
                'parts': readParts,
                'error': null,
              };
            case 'writeCertificationAmpField':
              writeArguments.add(call.arguments as Map<Object?, Object?>);
              return writeResponse;
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
              child: MatriboxAmpCertificationPanel(
                enabled: enabled,
                connectionReady: true,
                monitoring: false,
                backupDirectory: () async => tempDir,
                songTargetsLoader: () async => (
                  ampName: 'Sol 100 OD',
                  targets: {
                    'gain': 67.0,
                    'presence': 59.0,
                    'volume': 50.0,
                    'bass': 41.0,
                    'middle': 59.0,
                    'treble': 61.0,
                  },
                ),
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
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  const prepare = Key('matribox-cert-prepare');
  const prepareConfirm = Key('matribox-cert-prepare-confirm');
  const write = Key('matribox-cert-write');
  const writeConfirm = Key('matribox-cert-write-confirm');
  const readback = Key('matribox-cert-readback');
  const readbackConfirm = Key('matribox-cert-readback-confirm');

  testWidgets('disabled build renders nothing and calls nothing', (tester) async {
    await show(tester, enabled: false);
    expect(find.byKey(const Key('matribox-cert-panel')), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('initial state: Gain certified, Presence ready, others waiting, song info read-only', (tester) async {
    await show(tester);
    expect(find.text('Gain\n✓ CERTIFIED'), findsOneWidget);
    expect(find.text('Presence\n● READY FOR HARDWARE TEST'), findsOneWidget);
    for (final f in ['Volume', 'Bass', 'Middle', 'Treble']) {
      expect(find.text('$f\n○ WAITING'), findsOneWidget);
    }
    expect(find.textContaining('Presence  59'), findsOneWidget);
    expect(find.textContaining('nicht die Song-Zielwerte'), findsOneWidget);
    expect(find.text('Presence-Certification vorbereiten'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('prepare: cancel sends nothing; confirm reads only and shows 73 -> 74', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(prepare));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);

    await taps(tester, [prepare, prepareConfirm]);
    expect(calls, ['readMatriboxUserP01']);
    expect(find.text('Current: 73\nTarget: 74'), findsOneWidget);
    expect(find.textContaining('○ Active hardware write not yet confirmed'), findsOneWidget);
    expect(find.textContaining('✓ Hash verified'), findsOneWidget);
    expect(writeArguments, isEmpty);
  });

  testWidgets('write: first click sends nothing, cancel sends nothing, confirm sends exactly one', (tester) async {
    await show(tester);
    await taps(tester, [prepare, prepareConfirm]);
    calls.clear();

    await tester.tap(find.byKey(write));
    await tester.pumpAndSettle();
    expect(find.textContaining('Genau eine capture-bestätigte Parameter-Nachricht'), findsOneWidget);
    expect(find.textContaining('Kein Store.'), findsOneWidget);
    expect(find.textContaining('73 → 74'), findsOneWidget);
    expect(writeArguments, isEmpty);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(writeArguments, isEmpty);

    await taps(tester, [write, writeConfirm]);
    expect(writeArguments, [
      {'field': 'presence', 'targetValue': 74.0},
    ]);
    expect(calls, ['writeCertificationAmpField']); // no readback, no store, no read
    expect(find.text('WRITE_SENT'), findsOneWidget);
    expect(find.text('⚠ Readback noch nicht verifiziert'), findsOneWidget);
    expect(find.text('⚠ nicht dauerhaft gespeichert'), findsOneWidget);
    // Not certified, and the consumed plan cannot be sent a second time.
    expect(find.text('Presence\n◐ WRITE_SENT · Readback offen'), findsOneWidget);
    expect(find.byKey(write), findsNothing);
    expect(find.byKey(readback), findsOneWidget);
  });

  testWidgets('a failed write stays uncertified and is never retried', (tester) async {
    writeResponse = {'outcome': 'SEND_FAILED', 'error': 'USB'};
    await show(tester);
    await taps(tester, [prepare, prepareConfirm, write, writeConfirm]);
    expect(writeArguments, hasLength(1));
    expect(find.byKey(const Key('matribox-cert-write-failure')), findsOneWidget);
    expect(find.text('WRITE_SENT'), findsNothing);
    expect(find.text('Presence\n● READY FOR HARDWARE TEST'), findsOneWidget);
    expect(find.byKey(write), findsNothing);
  });

  testWidgets('readback: manual, uses a NEW read, certifies and unlocks the next field', (tester) async {
    await show(tester);
    await taps(tester, [prepare, prepareConfirm, write, writeConfirm]);
    calls.clear();
    // The device now reports the written value (user saved + reconnected).
    _setFloatAt(readParts[2], 17, 74);
    await taps(tester, [readback, readbackConfirm]);
    expect(calls, ['readMatriboxUserP01']);
    expect(find.byKey(const Key('matribox-cert-readback-certified')), findsOneWidget);
    expect(find.textContaining('CERTIFIED'), findsWidgets);
    expect(find.text('Presence\n✓ CERTIFIED'), findsOneWidget);
    expect(find.text('Volume\n● READY FOR HARDWARE TEST'), findsOneWidget);
    expect(writeArguments, hasLength(1)); // still exactly the one write
  });

  testWidgets('readback without the change does not certify', (tester) async {
    await show(tester);
    await taps(tester, [prepare, prepareConfirm, write, writeConfirm]);
    await taps(tester, [readback, readbackConfirm]); // device still at 73
    expect(find.byKey(const Key('matribox-cert-readback-failed')), findsOneWidget);
    expect(find.textContaining('EXPECTED_CHANGE_MISSING'), findsOneWidget);
    expect(find.text('Presence\n✗ READBACK NICHT ZERTIFIZIERT'), findsOneWidget);
    expect(find.text('Volume\n○ WAITING'), findsOneWidget);
  });

  testWidgets('disabled when the connection is not ready', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MatriboxAmpCertificationPanel(
              enabled: true,
              connectionReady: false,
              monitoring: false,
              backupDirectory: () async => tempDir,
              songTargetsLoader: () async => null,
            ),
          ),
        ),
      ),
    );
    final button = tester.widget<FilledButton>(find.byKey(prepare));
    expect(button.onPressed, isNull);
  });
}
