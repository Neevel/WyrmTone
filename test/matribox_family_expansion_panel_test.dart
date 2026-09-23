import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_family_expansion_certification.dart';
import 'package:wyrmtone/presets/matribox_model_library.dart';
import 'package:wyrmtone/screens/matribox_family_expansion_panel.dart';

import 'support/matribox_big_capture_snapshots.dart';
import 'support/matribox_family_expansion_support.dart';
import 'support/matribox_full_live_helpers.dart';
import 'support/matribox_tone_transfer_support.dart';

class _FamilyRun implements MatriboxFamilyExpansionChannel {
  _FamilyRun(this.plan, {this.failAt});
  final FamilyExpansionP01Plan plan;
  final int? failAt;
  final calls = <(String, String)>[];

  @override
  Future<Map<Object?, Object?>> runFamilyExpansionP01Certification({
    required String planId,
    required String backupSha256,
  }) async {
    calls.add((planId, backupSha256));
    final ops = plan.operations;
    final done = failAt ?? ops.length;
    return {
      'outcome': failAt == null ? 'SUCCESS' : 'SEND_FAILED',
      'error': failAt == null ? null : 'Transport-Fehler.',
      'total': ops.length,
      'completed': done,
      'failedIndex': failAt,
      'operations': [
        for (var i = 0; i < ops.length; i++)
          {'index': i, 'label': ops[i].label, 'status': i < done ? 'SENT' : (i == failAt ? 'FAILED' : 'NOT_SENT')},
      ],
    };
  }
}

void main() {
  late Directory tempDir;
  late ToneReadChannel read;
  late _FamilyRun run;
  final library = MatriboxModelLibrary.fromVendor(toneCatalog);
  final plan = FamilyExpansionP01Plan(library);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('family_panel');
    read = ToneReadChannel(suitableStartParts());
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> show(WidgetTester tester, {bool enabled = true, int? failAt}) async {
    run = _FamilyRun(plan, failAt: failAt);
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MatriboxFamilyExpansionPanel(
                enabled: enabled,
                connectionReady: true,
                monitoring: false,
                backupDirectory: () async => tempDir,
                libraryLoader: () async => library,
                readChannel: read,
                familyChannel: run,
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await tester.pump();
    });
  }

  Future<void> taps(WidgetTester tester, List<Key> keys) async {
    await tester.runAsync(() async {
      for (final key in keys) {
        await tester.tap(find.byKey(key));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  const prepare = Key('family-prepare');
  const prepareConfirm = Key('family-prepare-confirm');
  const start = Key('family-start');
  const startConfirm = Key('family-start-confirm');
  const confirmField = Key('family-confirm-field');
  const physical = Key('family-physical-check');
  const saved = Key('family-saved-confirm');
  const readback = Key('family-readback');
  const readbackConfirm = Key('family-readback-confirm');

  bool enabled(WidgetTester tester, Key key) {
    final widget = tester.widget(find.byKey(key));
    if (widget is FilledButton) return widget.onPressed != null;
    if (widget is CheckboxListTile) return widget.onChanged != null;
    throw StateError('unsupported');
  }

  testWidgets('disabled build renders nothing and never reads', (tester) async {
    await show(tester, enabled: false);
    expect(find.byKey(const Key('family-panel')), findsNothing);
    expect(read.reads, 0);
    expect(run.calls, isEmpty);
  });

  testWidgets('opening the page marked EXPERIMENTELL sends and reads nothing; the step list is shown', (tester) async {
    await show(tester);
    expect(find.text('FAMILY_EXPANSION_P01_V1'), findsWidgets);
    expect(find.textContaining('EXPERIMENTELL'), findsOneWidget);
    expect(find.text('Target: Matribox 1 · User P01'), findsOneWidget);
    expect(find.byKey(const Key('family-steps')), findsOneWidget);
    expect(read.reads, 0);
    expect(run.calls, isEmpty);
    expect(find.byKey(start), findsNothing);
    expect(find.byKey(readback), findsNothing);
  });

  testWidgets('a non-observable start state blocks: message shown, no start button, nothing sent', (tester) async {
    read.parts = hexParts(bigBeforeRawPartsHex); // the Angels source: NR/EQ/RVB ON, several models equal to the plan's
    await show(tester);
    await taps(tester, [prepare, prepareConfirm]);
    expect(find.byKey(start), findsNothing);
    expect(find.textContaining('SELECT_NOT_OBSERVABLE'), findsOneWidget);
    expect(run.calls, isEmpty);
  });

  testWidgets('prepare shows read/backup/hash and the 23 operations incl. Tier B; nothing is sent', (tester) async {
    await show(tester);
    await taps(tester, [prepare, prepareConfirm]);
    expect(read.reads, 1);
    for (final tick in ['✓ Device read', '✓ Backup', '✓ Reload', 'Backup: VERIFIED']) {
      expect(find.text(tick), findsOneWidget);
    }
    expect(find.byKey(const Key('family-hash')), findsOneWidget);
    expect(find.textContaining('23 Operationen: 9 MODEL SELECT · 11 PARAMETER · 3 BLOCK CC'), findsOneWidget);
    expect(find.textContaining('FX1: MODEL Boost'), findsOneWidget);
    expect(find.textContaining('AMP: MODEL Sol 100 OD'), findsOneWidget);
    expect(find.textContaining('CAB: PARAM VOL = 43 · Wire 1 (Hersteller-ID 2 − 1)'), findsOneWidget);
    expect(find.textContaining('FX2: PARAM Bright = 1 · Wire 2 (Hersteller-ID 3 − 1)'), findsOneWidget);
    expect(find.byKey(const Key('family-op-22')), findsOneWidget);
    expect(run.calls, isEmpty);
  });

  testWidgets('start needs the typed test name; cancel sends nothing; confirm = ONE call with plan id and hash', (tester) async {
    await show(tester);
    await taps(tester, [prepare, prepareConfirm]);
    final hash = (tester.widget<SelectableText>(find.byKey(const Key('family-hash'))).data!).substring('SHA-256: '.length);
    await taps(tester, [start]);
    expect(enabled(tester, startConfirm), isFalse);
    await tester.enterText(find.byKey(confirmField), 'FAMILY_EXPANSION');
    await tester.pump();
    expect(enabled(tester, startConfirm), isFalse);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(run.calls, isEmpty);

    await taps(tester, [start]);
    await tester.enterText(find.byKey(confirmField), 'FAMILY_EXPANSION_P01_V1');
    await tester.pump();
    expect(enabled(tester, startConfirm), isTrue);
    await taps(tester, [startConfirm]);
    expect(run.calls, [('FAMILY_EXPANSION_P01_V1', hash)]);
    expect(hash, hasLength(64));
    expect(find.text('LIVE WRITE COMPLETE – STOP'), findsOneWidget);
    expect(find.textContaining('completed: 23 · failed: 0 · notSent: 0'), findsOneWidget);
    expect(find.byKey(start), findsNothing); // one prepared session, one attempt
    expect(read.reads, 1); // STOP: no automatic readback
  });

  testWidgets('manual checkpoint: physical check, then "Ich habe am Gerät gespeichert" (zero MIDI), only then the readback', (tester) async {
    await show(tester);
    await taps(tester, [prepare, prepareConfirm]);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(start));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(confirmField), 'FAMILY_EXPANSION_P01_V1');
    await tester.pump();
    await taps(tester, [startConfirm]);

    // right after the write: neither the save confirmation nor the readback is possible
    expect(find.byKey(const Key('family-manual-instructions')), findsOneWidget);
    expect(find.textContaining('WyrmTone sendet keinen Store'), findsOneWidget);
    expect(enabled(tester, physical), isTrue);
    expect(enabled(tester, saved), isFalse);
    expect(enabled(tester, readback), isFalse);

    await tester.tap(find.byKey(physical));
    await tester.pump();
    expect(enabled(tester, saved), isTrue);
    expect(enabled(tester, readback), isFalse); // saving must be confirmed first

    await tester.tap(find.byKey(saved));
    await tester.pump();
    expect(enabled(tester, readback), isTrue);
    // the checkpoint sent nothing and read nothing
    expect(run.calls, hasLength(1));
    expect(read.reads, 1);

    read.parts = afterFromCertificationOps(plan.operations, from: suitableStartParts());
    await taps(tester, [readback, readbackConfirm]);
    expect(read.reads, 2);
    expect(find.byKey(const Key('family-readback-certified')), findsOneWidget);
    expect(find.text('CERTIFIED'), findsOneWidget);
    expect(find.text('MANUAL_SAVE_PERSISTENCE_VERIFIED'), findsOneWidget);
    expect(find.textContaining('WyrmTone hat keinen Store gesendet'), findsOneWidget);
    expect(find.textContaining('CORRELATED_PART8_CHANGE'), findsOneWidget);
    expect(find.textContaining('kein bestätigter Checksum'), findsOneWidget);
    expect(run.calls, hasLength(1)); // no retry, no second write
  });

  testWidgets('the live write is not visible to the read: TARGET_MISMATCH is reported, never success', (tester) async {
    await show(tester);
    await taps(tester, [prepare, prepareConfirm]);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(start));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(confirmField), 'FAMILY_EXPANSION_P01_V1');
    await tester.pump();
    await taps(tester, [startConfirm]);
    await tester.tap(find.byKey(physical));
    await tester.pump();
    await tester.tap(find.byKey(saved));
    await tester.pump();
    // the device did not persist anything: the read still shows the start state
    await taps(tester, [readback, readbackConfirm]);
    expect(find.text('TARGET_MISMATCH'), findsOneWidget);
    expect(find.text('MANUAL_SAVE_PERSISTENCE_VERIFIED'), findsNothing);
  });

  testWidgets('a mid-run failure stops: completed / failed / notSent; the state at the device is unclear, no retry', (tester) async {
    await show(tester, failAt: 3);
    await taps(tester, [prepare, prepareConfirm]);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(start));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(confirmField), 'FAMILY_EXPANSION_P01_V1');
    await tester.pump();
    await taps(tester, [startConfirm]);
    expect(find.text('⚠ Lauf gestoppt – STOP'), findsOneWidget);
    expect(find.textContaining('completed: 3 · failed: 1 · notSent: 19'), findsOneWidget);
    expect(find.textContaining('UNKNOWN'), findsWidgets);
    expect(run.calls, hasLength(1));
    expect(find.byKey(start), findsNothing);
  });
}
