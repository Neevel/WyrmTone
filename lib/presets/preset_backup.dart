import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import 'canonical_preset.dart';
import 'preset_exchange.dart';

enum BackupOrigin { wyrmToneDraft, manualImport, officialEditorReference }

class PresetBackup {
  const PresetBackup({
    required this.id,
    required this.at,
    required this.preset,
    required this.hash,
    required this.origin,
    this.slotId,
  });
  final String id, hash;
  final String? slotId;
  final DateTime at;
  final CanonicalPreset preset;
  final BackupOrigin origin;
  String get restoration => 'Local only; device restoration unavailable';
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'at': at.toUtc().toIso8601String(),
    'targetDevice': preset.targetDevice,
    'slotId': slotId,
    'name': preset.name,
    'origin': origin.name,
    'hash': hash,
    'restoration': restoration,
    'preset': preset.toJson(),
  };
}

class BackupListing {
  const BackupListing(this.backups, this.errors);
  final List<PresetBackup> backups;
  final List<String> errors;
}

abstract interface class PresetRepository {
  Future<BackupListing> list();
  Future<PresetBackup> save(
    CanonicalPreset preset, {
    BackupOrigin origin,
    String? slotId,
  });
  Future<CanonicalPreset> restoreLocally(String id);
  Future<void> delete(String id, {required bool confirmed});
}

class PresetBackupRepository implements PresetRepository {
  PresetBackupRepository(this.directory, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final Directory directory;
  final DateTime Function() clock;
  static final _id = RegExp(r'^[0-9a-f]{64}$');
  static String _backupId(String hash, String? slotId, BackupOrigin origin) =>
      sha256
          .convert(utf8.encode('$hash|${slotId ?? ''}|${origin.name}'))
          .toString();
  File _file(String id) {
    if (!_id.hasMatch(id)) throw const FormatException('Invalid backup ID.');
    return File('${directory.path}/$id.wyrmtone-backup.json');
  }

  PresetBackup _read(File file) {
    final data = objectMap(jsonDecode(file.readAsStringSync()));
    PresetPrivacy.check(data);
    if (data['schemaVersion'] != 1) {
      throw const FormatException('Unknown backup version.');
    }
    final preset = CanonicalPreset.fromJson(objectMap(data['preset']));
    final hash = presetHash(preset);
    final origin = enumValue(BackupOrigin.values, data['origin']);
    final slotId = data['slotId'] as String?;
    if (data['hash'] != hash ||
        data['id'] != _backupId(hash, slotId, origin) ||
        data['targetDevice'] != preset.targetDevice) {
      throw const FormatException('Backup checksum or metadata mismatch.');
    }
    return PresetBackup(
      id: data['id'] as String,
      at: DateTime.parse(requiredText(data, 'at')),
      preset: preset,
      hash: hash,
      origin: origin,
      slotId: slotId,
    );
  }

  @override
  Future<BackupListing> list() async {
    if (!await directory.exists()) return const BackupListing([], []);
    final backups = <PresetBackup>[], errors = <String>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File && entry.path.endsWith('.wyrmtone-backup.json')) {
        try {
          backups.add(_read(entry));
        } catch (_) {
          errors.add(
            'Beschädigte Sicherung: ${entry.uri.pathSegments.last}; nicht gelöscht.',
          );
        }
      } else if (entry.path.endsWith('.tmp')) {
        errors.add('Unvollständige Sicherung vorhanden; nicht gelöscht.');
      }
    }
    backups.sort((a, b) => b.at.compareTo(a.at));
    errors.sort();
    return BackupListing(List.unmodifiable(backups), List.unmodifiable(errors));
  }

  @override
  Future<PresetBackup> save(
    CanonicalPreset preset, {
    BackupOrigin origin = BackupOrigin.wyrmToneDraft,
    String? slotId,
  }) async {
    PresetPrivacy.check(preset.toJson());
    final hash = presetHash(preset);
    final id = _backupId(hash, slotId, origin);
    final file = _file(id);
    if (await file.exists()) {
      return _read(file); // Exact normalized-content duplicate.
    }
    await directory.create(recursive: true);
    final backup = PresetBackup(
      id: id,
      at: clock(),
      preset: preset,
      hash: hash,
      origin: origin,
      slotId: slotId,
    );
    final temporary = File(
      '${file.path}.${clock().microsecondsSinceEpoch}.tmp',
    );
    await temporary.create(exclusive: true);
    await temporary.writeAsString(
      canonicalJson(backup.toJson(), pretty: true),
      flush: true,
    );
    if (await file.exists()) {
      // Never overwrite an existing backup, including a corrupt one.
      return _read(file);
    }
    await temporary.rename(file.path);
    return backup;
  }

  @override
  Future<CanonicalPreset> restoreLocally(String id) async =>
      _read(_file(id)).preset;
  @override
  Future<void> delete(String id, {required bool confirmed}) async {
    if (!confirmed) {
      throw StateError('Explicit deletion confirmation required.');
    }
    await _file(id).delete();
  }
}
