import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_raw_backup_library.dart';
import 'package:wyrmtone/presets/raw_preset_backup_format.dart';
import 'package:wyrmtone/presets/raw_preset_snapshot.dart';

import 'support/matribox_p01_readback_fixtures.dart';

void main() {
  late Directory tempDir;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('matribox_backup_library_test');
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  RawPresetSnapshot snapshot() => RawPresetSnapshot.capture(
    deviceLabel: 'Sonicake Matribox 1 84EF:0054',
    rawParts: matriboxP01RealFullCycle.map(matriboxHex).toList(),
    clock: () => DateTime.utc(2026, 9, 17),
  );

  Future<File> writeBackup(RawPresetSnapshot snap) async {
    final file = File('${tempDir.path}/${snap.sha256}$rawPresetBackupFileSuffix');
    await file.writeAsString(encodeRawPresetBackupJson(snap));
    return file;
  }

  group('MatriboxRawBackupLibrary', () {
    test('an empty/missing directory lists no backups', () async {
      final library = MatriboxRawBackupLibrary(Directory('${tempDir.path}/missing'));
      expect(await library.list(), isEmpty);
    });

    test('lists a saved backup with its decoded snapshot', () async {
      final snap = snapshot();
      await writeBackup(snap);
      final library = MatriboxRawBackupLibrary(tempDir);

      final entries = await library.list();

      expect(entries, hasLength(1));
      expect(entries.single.snapshot.presetName, 'CKY 96 STUD');
      expect(entries.single.snapshot.sha256, snap.sha256);
    });

    test('lists newest first', () async {
      final older = RawPresetSnapshot.capture(
        deviceLabel: 'Sonicake Matribox 1 84EF:0054',
        rawParts: matriboxP01RealFullCycle.map(matriboxHex).toList(),
        clock: () => DateTime.utc(2026, 9, 15),
      );
      final newer = snapshot();
      await writeBackup(older);
      // Distinguish filenames despite identical content-derived hash by
      // writing to a differently-named file directly.
      await File('${tempDir.path}/older.wyrmtone-raw-preset.json')
          .writeAsString(encodeRawPresetBackupJson(older));
      await writeBackup(newer);

      final entries = await MatriboxRawBackupLibrary(tempDir).list();
      expect(entries.first.snapshot.createdAt, newer.createdAt);
    });

    test('a corrupted backup file is skipped, not deleted', () async {
      await writeBackup(snapshot());
      final corrupt = File('${tempDir.path}/broken$rawPresetBackupFileSuffix');
      await corrupt.writeAsString('not valid json');

      final entries = await MatriboxRawBackupLibrary(tempDir).list();

      expect(entries, hasLength(1)); // only the valid one is listed
      expect(corrupt.existsSync(), isTrue); // never auto-deleted
    });

    test('verify confirms an intact backup and rejects a tampered one', () async {
      final file = await writeBackup(snapshot());
      final library = MatriboxRawBackupLibrary(tempDir);
      expect(await library.verify(file.path), isTrue);

      await file.writeAsString(
        (await file.readAsString()).replaceFirst('"CKY 96 STUD"', '"TAMPERED"'),
      );
      expect(await library.verify(file.path), isFalse);
    });

    test('delete requires explicit confirmation and removes the file', () async {
      final file = await writeBackup(snapshot());
      final library = MatriboxRawBackupLibrary(tempDir);

      expect(
        () => library.delete(file.path, confirmed: false),
        throwsA(isA<StateError>()),
      );
      expect(file.existsSync(), isTrue);

      await library.delete(file.path, confirmed: true);
      expect(file.existsSync(), isFalse);
    });
  });
}
