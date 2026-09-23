import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../presets/matribox_raw_backup_service.dart';

const matriboxP01RawBackupEnabled =
    kDebugMode &&
    bool.fromEnvironment('ENABLE_MATRIBOX_P01_RAW_BACKUP', defaultValue: false);

Future<Directory> defaultMatriboxRawBackupDirectory() async => Directory(
  '${(await getApplicationDocumentsDirectory()).path}/matribox_raw_backups',
);

class _MethodChannelMatriboxPresetReadChannel
    implements MatriboxPresetReadChannel {
  const _MethodChannelMatriboxPresetReadChannel(this._channel);
  final MethodChannel _channel;
  @override
  Future<Map<Object?, Object?>> readMatriboxUserP01() async =>
      await _channel.invokeMapMethod<Object?, Object?>(
        'readMatriboxUserP01',
      ) ??
      {};
}

/// Production, non-diagnostic backup control: lives on the main device
/// page, not inside "Erweiterte Diagnose". Shows only plain-language
/// status (preset name, hash, file location) -- never a raw hex dump; the
/// diagnostic panels remain the only place for that.
class MatriboxRawBackupPanel extends StatefulWidget {
  const MatriboxRawBackupPanel({
    required this.connectionReady,
    required this.monitoring,
    this.enabled = matriboxP01RawBackupEnabled,
    this.backupDirectory = defaultMatriboxRawBackupDirectory,
    super.key,
  });

  final bool connectionReady;
  final bool monitoring;
  final bool enabled;
  final Future<Directory> Function() backupDirectory;

  @override
  State<MatriboxRawBackupPanel> createState() =>
      _MatriboxRawBackupPanelState();
}

class _MatriboxRawBackupPanelState extends State<MatriboxRawBackupPanel> {
  static const _channel = MethodChannel('de.neevel.wyrmtone/usb_methods');
  bool _busy = false;
  MatriboxRawBackupResult? _result;
  String? _errorMessage;

  Future<void> _confirmAndBackup() async {
    if (_busy || !widget.connectionReady || widget.monitoring) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Raw-Backup von User P01 erstellen?'),
        content: const Text(
          'Sonicake Matribox 1 · User-Preset P01\n\n'
          'Nur lesen: Es wird ausschließlich der aktuelle Inhalt von P01 '
          'vom Gerät gelesen. Keine Presetänderung, kein Speichern oder '
          'Schreiben auf dem Gerät. Das Backup wird ausschließlich lokal '
          'auf diesem Smartphone gespeichert.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('matribox-raw-backup-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Backup erstellen'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _busy = true;
      _result = null;
      _errorMessage = null;
    });
    try {
      final directory = await widget.backupDirectory();
      final service = MatriboxRawBackupService(
        channel: _MethodChannelMatriboxPresetReadChannel(_channel),
        backupDirectory: directory,
      );
      final result = await service.backupUserP01();
      if (!mounted) return;
      setState(() {
        _result = result;
        _errorMessage = result.isSuccess ? null : _describeFailure(result);
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _result = null;
          _errorMessage = 'Backup fehlgeschlagen: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describeFailure(MatriboxRawBackupResult result) {
    switch (result.outcome) {
      case MatriboxRawBackupOutcome.success:
        return '';
      case MatriboxRawBackupOutcome.phaseDTimeout:
      case MatriboxRawBackupOutcome.phaseDInvalid:
        return 'Backup fehlgeschlagen: Die Matribox hat nicht wie erwartet '
            'auf die Leseanfrage reagiert. Bitte Verbindung prüfen und '
            'erneut versuchen.';
      case MatriboxRawBackupOutcome.partTimeout:
      case MatriboxRawBackupOutcome.partInvalid:
      case MatriboxRawBackupOutcome.incomplete:
        return 'Backup fehlgeschlagen: Der Lesevorgang wurde unterbrochen, '
            'bevor alle Daten vollständig angekommen sind. Bitte erneut '
            'versuchen.';
      case MatriboxRawBackupOutcome.transportError:
        return 'Backup fehlgeschlagen: Verbindungsfehler. Bitte Verbindung '
            'prüfen und erneut versuchen.';
      case MatriboxRawBackupOutcome.channelError:
        return 'Backup fehlgeschlagen: ${result.errorMessage ?? 'Unbekannter Fehler.'}';
      case MatriboxRawBackupOutcome.validationFailed:
        return 'Backup fehlgeschlagen: Die Sicherung konnte nicht '
            'validiert werden. Es wurde keine gültige Sicherung '
            'gespeichert.';
    }
  }

  String _shortHash(String hash) =>
      hash.length <= 12 ? hash : '${hash.substring(0, 12)}…';

  String _formatDateTime(DateTime utc) {
    final local = utc.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    final available = widget.connectionReady && !widget.monitoring && !_busy;
    return Card(
      key: const Key('matribox-raw-backup-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Raw-Backup', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Sonicake Matribox 1 · User P01 · nur lesen. Keine '
              'Presetänderung, kein Speichern oder Schreiben auf dem Gerät.',
            ),
            const SizedBox(height: 8),
            if (!widget.connectionReady)
              const Text('Passende Matribox eindeutig als MIDI-Gerät öffnen.'),
            if (widget.monitoring)
              const Text('Passiven Monitor zuerst stoppen.'),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('matribox-raw-backup-button'),
              onPressed: available ? _confirmAndBackup : null,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Raw-Backup von P01 erstellen'),
            ),
            if (_result != null && _result!.isSuccess) ...[
              const SizedBox(height: 12),
              _BackupSuccessCard(
                result: _result!,
                shortHash: _shortHash(_result!.sha256 ?? ''),
                formattedDate: _result!.createdAt == null
                    ? null
                    : _formatDateTime(_result!.createdAt!),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                key: const Key('matribox-raw-backup-message'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BackupSuccessCard extends StatelessWidget {
  const _BackupSuccessCard({
    required this.result,
    required this.shortHash,
    required this.formattedDate,
  });

  final MatriboxRawBackupResult result;
  final String shortHash;
  final String? formattedDate;

  @override
  Widget build(BuildContext context) {
    final ampFields = result.ampFields;
    return Material(
      key: const Key('matribox-raw-backup-message'),
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preset Backup',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'User P01 · ${result.presetName ?? '?'}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          const _CheckLine('gelesen'),
          const _CheckLine('validiert'),
          const _CheckLine('lokal gesichert'),
          const SizedBox(height: 6),
          Text('Hash: $shortHash'),
          if (formattedDate != null) Text(formattedDate!),
          ExpansionTile(
            key: const Key('matribox-raw-backup-details'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Backupdetails'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Presetname: ${result.presetName ?? '?'}'),
                      Text('Bank: User · Slot: P01'),
                      if (ampFields != null)
                        for (final entry in ampFields.entries)
                          Text('${entry.key}: ${entry.value}'),
                      Text('Hash (vollständig): ${result.sha256 ?? '?'}'),
                      Text('Datei: ${result.filePath ?? '?'}'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          ],
        ),
      ),
    );
  }
}

class _CheckLine extends StatelessWidget {
  const _CheckLine(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 4),
      Text(label),
    ],
  );
}
