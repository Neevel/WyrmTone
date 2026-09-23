import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/raw_preset_backup_format.dart';
import 'package:wyrmtone/presets/raw_preset_snapshot.dart';
import 'package:wyrmtone/screens/matribox_backup_library_panel.dart';

import 'support/matribox_p01_readback_fixtures.dart';

// Verify/delete interaction (tapping into the per-entry ExpansionTile) is
// deliberately not covered at the widget level here: the underlying
// MatriboxRawBackupLibrary.verify/delete methods that the buttons call are
// already fully tested in matribox_raw_backup_library_test.dart, and the
// confirmation-dialog wiring itself mirrors the already-tested pattern in
// matribox_raw_backup_panel_test.dart. Only the list rendering is covered
// here.
void main() {
  late Directory tempDir;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('matribox_backup_library_panel');
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // All real Directory/File I/O -- including writing the fixture backup
  // file -- must happen inside a single runAsync callback. Awaiting real
  // I/O anywhere outside runAsync never resolves under
  // TestWidgetsFlutterBinding's fake clock.
  Future<File> writeBackup() async {
    final snapshot = RawPresetSnapshot.capture(
      deviceLabel: 'Sonicake Matribox 1 84EF:0054',
      rawParts: matriboxP01RealFullCycle.map(matriboxHex).toList(),
      clock: () => DateTime.utc(2026, 9, 17),
    );
    final file = File('${tempDir.path}/${snapshot.sha256}$rawPresetBackupFileSuffix');
    await file.writeAsString(encodeRawPresetBackupJson(snapshot));
    return file;
  }

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatriboxBackupLibraryPanel(
            backupDirectory: () async => tempDir,
          ),
        ),
      ),
    );
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
  }

  Future<void> run(WidgetTester tester, Future<void> Function() body) async {
    await tester.runAsync(body);
    await tester.pumpAndSettle();
  }

  testWidgets('shows empty state when no backup exists', (tester) async {
    await run(tester, () async {
      await pumpPanel(tester);
    });
    expect(find.text('Noch keine lokale Sicherung vorhanden.'), findsOneWidget);
  });

  testWidgets('lists an existing backup with preset name and date', (tester) async {
    await run(tester, () async {
      await writeBackup();
      await pumpPanel(tester);
    });
    expect(find.textContaining('CKY 96 STUD'), findsOneWidget);
    expect(find.textContaining('P01'), findsOneWidget);
    expect(find.textContaining('17.09.2026'), findsOneWidget);
  });
}
