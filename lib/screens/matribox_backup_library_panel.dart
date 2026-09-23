import 'dart:io';

import 'package:flutter/material.dart';

import '../presets/matribox_raw_backup_library.dart';
import 'matribox_raw_backup_panel.dart' show defaultMatriboxRawBackupDirectory;

/// Local backup management only: list, details, integrity check, delete.
/// Deliberately no restore -- that stays out of scope until write itself
/// is hardware-approved.
class MatriboxBackupLibraryPanel extends StatefulWidget {
  const MatriboxBackupLibraryPanel({
    this.backupDirectory = defaultMatriboxRawBackupDirectory,
    super.key,
  });

  final Future<Directory> Function() backupDirectory;

  @override
  State<MatriboxBackupLibraryPanel> createState() =>
      _MatriboxBackupLibraryPanelState();
}

class _MatriboxBackupLibraryPanelState
    extends State<MatriboxBackupLibraryPanel> {
  Future<List<MatriboxRawBackupEntry>>? _future;
  final Map<String, bool?> _verified = {};

  Future<List<MatriboxRawBackupEntry>> _load() async {
    final directory = await widget.backupDirectory();
    return MatriboxRawBackupLibrary(directory).list();
  }

  void _refresh() {
    setState(() {
      _verified.clear();
      _future = _load();
    });
  }

  Future<void> _verify(String filePath) async {
    final directory = await widget.backupDirectory();
    final ok = await MatriboxRawBackupLibrary(directory).verify(filePath);
    if (mounted) setState(() => _verified[filePath] = ok);
  }

  Future<void> _delete(String filePath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup löschen?'),
        content: const Text(
          'Diese lokale Sicherung wird endgültig gelöscht. Die Matribox '
          'selbst ist davon nicht betroffen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('matribox-backup-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final directory = await widget.backupDirectory();
    await MatriboxRawBackupLibrary(
      directory,
    ).delete(filePath, confirmed: true);
    _refresh();
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('matribox-backup-library-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Matribox Backups',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const Key('matribox-backup-library-refresh'),
                  icon: const Icon(Icons.refresh),
                  onPressed: _refresh,
                ),
              ],
            ),
            FutureBuilder<List<MatriboxRawBackupEntry>>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Lade lokale Sicherungen…'),
                  );
                }
                final entries = snapshot.data!;
                if (entries.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Noch keine lokale Sicherung vorhanden.'),
                  );
                }
                return Column(
                  children: [
                    for (final entry in entries)
                      _BackupTile(
                        key: Key('matribox-backup-tile-${entry.filePath}'),
                        entry: entry,
                        verified: _verified[entry.filePath],
                        onVerify: () => _verify(entry.filePath),
                        onDelete: () => _delete(entry.filePath),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupTile extends StatelessWidget {
  const _BackupTile({
    required super.key,
    required this.entry,
    required this.verified,
    required this.onVerify,
    required this.onDelete,
  });

  final MatriboxRawBackupEntry entry;
  final bool? verified;
  final VoidCallback onVerify;
  final VoidCallback onDelete;

  String _formatDateTime(DateTime utc) {
    final local = utc.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = entry.snapshot;
    return ExpansionTile(
      title: Text(
        '${snapshot.presetName} (P${snapshot.presetNumber.toString().padLeft(2, '0')})',
      ),
      subtitle: Text(_formatDateTime(snapshot.createdAt)),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bank: ${snapshot.isUserBank ? 'User' : 'Factory'}'),
                Text('Hash: ${snapshot.sha256}'),
                if (snapshot.ampFields != null)
                  for (final entryField in snapshot.ampFields!.toJson().entries)
                    Text('${entryField.key}: ${entryField.value}'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      key: Key('matribox-backup-verify-${entry.filePath}'),
                      onPressed: onVerify,
                      child: const Text('Integrität prüfen'),
                    ),
                    if (verified != null)
                      Text(
                        verified! ? 'Gültig' : 'Ungültig/beschädigt',
                        style: TextStyle(
                          color: verified!
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const Spacer(),
                    TextButton(
                      key: Key('matribox-backup-delete-${entry.filePath}'),
                      onPressed: onDelete,
                      child: const Text('Löschen'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
