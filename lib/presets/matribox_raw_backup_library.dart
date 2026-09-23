/// Local management of existing Matribox raw backups: list, read details,
/// verify integrity, delete. Deliberately no restore -- that stays out of
/// scope until write itself is hardware-approved. Mirrors
/// `PresetBackupRepository` (preset_backup.dart)'s list/delete pattern,
/// but is a genuinely separate implementation: raw device backups and
/// WyrmTone's own `CanonicalPreset` drafts are different domains and must
/// not share a repository.
library;

import 'dart:io';

import 'raw_preset_backup_format.dart';
import 'raw_preset_snapshot.dart';

class MatriboxRawBackupEntry {
  const MatriboxRawBackupEntry({required this.filePath, required this.snapshot});

  final String filePath;
  final RawPresetSnapshot snapshot;
}

class MatriboxRawBackupLibrary {
  const MatriboxRawBackupLibrary(this.directory);

  final Directory directory;

  /// Newest first. A file that fails to decode/validate is skipped, never
  /// deleted automatically -- a corrupted backup is still evidence that
  /// something needs a human's attention.
  Future<List<MatriboxRawBackupEntry>> list() async {
    if (!await directory.exists()) return const [];
    final entries = <MatriboxRawBackupEntry>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith(rawPresetBackupFileSuffix)) {
        continue;
      }
      try {
        final snapshot = decodeRawPresetBackupJson(
          await entity.readAsString(),
        );
        entries.add(
          MatriboxRawBackupEntry(filePath: entity.path, snapshot: snapshot),
        );
      } catch (_) {
        // Corrupted or foreign file: skip, leave it in place for inspection.
      }
    }
    entries.sort(
      (a, b) => b.snapshot.createdAt.compareTo(a.snapshot.createdAt),
    );
    return List.unmodifiable(entries);
  }

  /// Re-decodes and re-validates the file from disk (never trusts a
  /// cached [MatriboxRawBackupEntry]).
  Future<bool> verify(String filePath) async {
    try {
      decodeRawPresetBackupJson(await File(filePath).readAsString());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> delete(String filePath, {required bool confirmed}) async {
    if (!confirmed) {
      throw StateError('Löschen erfordert ausdrückliche Bestätigung.');
    }
    await File(filePath).delete();
  }
}
