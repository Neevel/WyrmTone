import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/target_sound.dart';
import '../presets/canonical_preset.dart' show objectMap;
import '../presets/device_catalog.dart';
import '../presets/matribox_amp_certification.dart';
import '../presets/matribox_amp_certification_session.dart';
import '../presets/matribox_raw_backup_service.dart';
import '../presets/matribox_song_target_preview.dart';
import '../services/offline_sound_profiles.dart';
import 'matribox_raw_backup_panel.dart' show defaultMatriboxRawBackupDirectory;

/// Certification writes exist only in a debug build with its own explicit
/// compile gate (see build.gradle.kts). Normal builds render nothing.
const matriboxAmpCertificationEnabled =
    kDebugMode &&
    bool.fromEnvironment(
      'ENABLE_MATRIBOX_SOL100OD_AMP_CERTIFICATION',
      defaultValue: false,
    );

const _certificationStateFileName = 'sol100od_amp_certification.state';

class _MethodChannelReadChannel implements MatriboxPresetReadChannel {
  const _MethodChannelReadChannel(this._channel);
  final MethodChannel _channel;
  @override
  Future<Map<Object?, Object?>> readMatriboxUserP01() async =>
      await _channel.invokeMapMethod<Object?, Object?>('readMatriboxUserP01') ?? {};
}

/// Only a whitelisted field name and the target value leave Dart.
class _MethodChannelCertificationWriteChannel
    implements MatriboxCertificationWriteChannel {
  const _MethodChannelCertificationWriteChannel(this._channel);
  final MethodChannel _channel;
  @override
  Future<Map<Object?, Object?>> writeCertificationAmpField(
    String field,
    double targetValue,
  ) async =>
      await _channel.invokeMapMethod<Object?, Object?>(
        'writeCertificationAmpField',
        {'field': field, 'targetValue': targetValue},
      ) ??
      {};
}

Future<({String? ampName, Map<String, double> targets})?>
_defaultSongTargets() async {
  try {
    final profiles = await OfflineSoundProfiles.load();
    final catalog = DevicePresetCatalog(
      objectMap(
        jsonDecode(
          await rootBundle.loadString('assets/catalog/matribox_preset_catalog.json'),
        ),
      ),
    );
    return MatriboxSongTargetPreview.compute(
      profiles: List<TargetSound>.from(profiles),
      catalog: catalog,
    );
  } catch (_) {
    return null;
  }
}

String _label(MatriboxSol100OdAmpField field) =>
    field.wireName[0].toUpperCase() + field.wireName.substring(1);

String _writeOutcomeMessage(MatriboxCertificationWriteOutcome outcome) =>
    switch (outcome) {
      MatriboxCertificationWriteOutcome.success => 'Erfolgreich gesendet.',
      MatriboxCertificationWriteOutcome.deviceNotConnected =>
        'Matribox nicht eindeutig als MIDI-Gerät verbunden.',
      MatriboxCertificationWriteOutcome.midiNotAvailable =>
        'MIDI-Verbindung aktuell nicht eindeutig verfügbar.',
      MatriboxCertificationWriteOutcome.invalidValue =>
        'Zielwert außerhalb des gültigen Bereichs.',
      MatriboxCertificationWriteOutcome.sendFailed => 'Senden ist fehlgeschlagen.',
      MatriboxCertificationWriteOutcome.safetyRejected =>
        'Von einer Sicherheitsprüfung abgelehnt.',
      MatriboxCertificationWriteOutcome.channelError => 'Plattformkanal-Fehler.',
    };

/// Lab/beta UI for the one-field-at-a-time Sol 100 OD AMP hardware
/// certification. Every hardware action needs its own manual confirmation;
/// nothing advances, retries, saves or reads on its own.
class MatriboxAmpCertificationPanel extends StatefulWidget {
  const MatriboxAmpCertificationPanel({
    required this.connectionReady,
    required this.monitoring,
    this.enabled = matriboxAmpCertificationEnabled,
    this.backupDirectory = defaultMatriboxRawBackupDirectory,
    this.songTargetsLoader = _defaultSongTargets,
    super.key,
  });

  final bool connectionReady;
  final bool monitoring;
  final bool enabled;
  final Future<Directory> Function() backupDirectory;
  final Future<({String? ampName, Map<String, double> targets})?> Function()
  songTargetsLoader;

  @override
  State<MatriboxAmpCertificationPanel> createState() =>
      _MatriboxAmpCertificationPanelState();
}

class _MatriboxAmpCertificationPanelState
    extends State<MatriboxAmpCertificationPanel> {
  static const _channel = MethodChannel('de.neevel.wyrmtone/usb_methods');

  bool _busy = false;
  List<MatriboxCertificationRecord> _records = const [];
  MatriboxCertificationSessionResult? _session;
  MatriboxCertificationWriteResult? _writeResult;
  MatriboxCertificationReadbackResult? _readbackResult;
  String? _message;
  ({String? ampName, Map<String, double> targets})? _songTargets;
  bool _songTargetsLoaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _loadRecords();
      _loadSongTargets();
    }
  }

  Future<MatriboxCertificationStore> _store() async => MatriboxCertificationStore(
    File('${(await widget.backupDirectory()).path}/$_certificationStateFileName'),
  );

  Future<void> _loadRecords() async {
    final records = await (await _store()).load();
    if (mounted) setState(() => _records = records);
  }

  Future<void> _loadSongTargets() async {
    final targets = await widget.songTargetsLoader();
    if (mounted) {
      setState(() {
        _songTargets = targets;
        _songTargetsLoaded = true;
      });
    }
  }

  MatriboxSol100OdAmpField? get _activeField {
    for (final field in matriboxCertificationOrder) {
      final status = MatriboxCertification.statusFor(field, _records);
      if (status != MatriboxCertificationStatus.certified) return field;
    }
    return null;
  }

  MatriboxCertificationRecord? _pendingRecord(MatriboxSol100OdAmpField field) =>
      _records
          .where(
            (r) =>
                r.field == field &&
                r.state == MatriboxCertificationRecordState.writeSent,
          )
          .firstOrNull;

  Future<bool> _confirm({
    required String title,
    required String body,
    required String actionLabel,
    required Key actionKey,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              key: actionKey,
              onPressed: () => Navigator.pop(context, true),
              child: Text(actionLabel),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _prepare(MatriboxSol100OdAmpField field) async {
    if (_busy || !widget.connectionReady || widget.monitoring) return;
    final accepted = await _confirm(
      title: '${_label(field)}-Certification vorbereiten?',
      body:
          'Sonicake Matribox 1 · User-Preset P01\n\n'
          'Liest zuerst P01 und legt ein Backup an. Danach wird nur ein '
          'Plan angezeigt -- es wird noch nichts geschrieben.',
      actionLabel: 'Vorbereiten',
      actionKey: const Key('matribox-cert-prepare-confirm'),
    );
    if (!accepted || !mounted) return;
    setState(() {
      _busy = true;
      _session = null;
      _writeResult = null;
      _readbackResult = null;
      _message = null;
    });
    try {
      final directory = await widget.backupDirectory();
      await _loadRecords();
      final result = await MatriboxCertificationSession(
        backupService: MatriboxRawBackupService(
          channel: const _MethodChannelReadChannel(_channel),
          backupDirectory: directory,
        ),
        records: _records,
      ).prepare(field);
      if (!mounted) return;
      setState(() {
        _session = result;
        _message = result.readyForCertificationWrite
            ? null
            : (result.blockedReason ?? 'Vorbereitung fehlgeschlagen.');
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'Vorbereitung fehlgeschlagen: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _write() async {
    final session = _session;
    if (_busy || session == null || !session.readyForCertificationWrite) return;
    final field = session.field;
    final label = _label(field);
    final confirmed = await _confirm(
      title: '$label-Test schreiben?',
      body:
          'Matribox 1\nUser P01\nSol 100 OD\n$label\n'
          '${session.currentValue!.toStringAsFixed(0)} → '
          '${session.targetValue!.toStringAsFixed(0)}\n\n'
          'Genau eine capture-bestätigte Parameter-Nachricht wird gesendet.\n'
          'Kein Store.\nKein weiterer Parameter.',
      actionLabel: '$label einmal schreiben',
      actionKey: const Key('matribox-cert-write-confirm'),
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _writeResult = null;
      // One write per prepared session: the plan is consumed by the attempt,
      // successful or not. A new attempt needs a fresh prepare.
      _session = null;
    });
    final store = await _store();
    final result = await MatriboxCertificationExecutor(
      channel: const _MethodChannelCertificationWriteChannel(_channel),
      store: store,
      records: _records,
    ).execute(session);
    await _loadRecords();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _writeResult = result;
    });
  }

  Future<void> _readback(MatriboxCertificationRecord record) async {
    if (_busy || !widget.connectionReady || widget.monitoring) return;
    final label = _label(record.field);
    final accepted = await _confirm(
      title: '$label Readback prüfen?',
      body:
          'Führt einen neuen Lesevorgang von User P01 aus und vergleicht '
          'ihn mit dem Backup vor dem Write. Es wird nichts geschrieben '
          'und nichts gespeichert.',
      actionLabel: 'Readback prüfen',
      actionKey: const Key('matribox-cert-readback-confirm'),
    );
    if (!accepted || !mounted) return;
    setState(() {
      _busy = true;
      _readbackResult = null;
    });
    try {
      final result = await MatriboxCertificationReadback.run(
        record: record,
        backupService: MatriboxRawBackupService(
          channel: const _MethodChannelReadChannel(_channel),
          backupDirectory: await widget.backupDirectory(),
        ),
        store: await _store(),
      );
      await _loadRecords();
      if (mounted) setState(() => _readbackResult = result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final available = widget.connectionReady && !widget.monitoring && !_busy;
    final active = _activeField;
    final pending = active == null ? null : _pendingRecord(active);
    final session = _session;
    return Card(
      key: const Key('matribox-cert-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Sol 100 OD · AMP Hardware Certification', style: theme.textTheme.titleMedium),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('LAB', style: theme.textTheme.labelSmall),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'User P01 · ein Feld nach dem anderen, je genau ein '
              '±1-Testwrite. Kein Store, kein Multi-Field-Write, keine '
              'Song-Zielwerte.',
            ),
            const SizedBox(height: 8),
            for (final field in MatriboxSol100OdAmpField.values)
              _FieldStatusLine(
                field: field,
                status: field == MatriboxSol100OdAmpField.gain
                    ? MatriboxCertificationStatus.certified
                    : MatriboxCertification.statusFor(field, _records),
              ),
            const SizedBox(height: 8),
            if (!widget.connectionReady)
              const Text('Passende Matribox eindeutig als MIDI-Gerät öffnen.'),
            if (widget.monitoring) const Text('Passiven Monitor zuerst stoppen.'),
            if (active == null)
              const Text('Alle Felder sind zertifiziert.')
            else ...[
              if (pending == null)
                FilledButton.icon(
                  key: const Key('matribox-cert-prepare'),
                  onPressed: available ? () => _prepare(active) : null,
                  icon: const Icon(Icons.science_outlined),
                  label: Text('${_label(active)}-Certification vorbereiten'),
                )
              else
                FilledButton.icon(
                  key: const Key('matribox-cert-readback'),
                  onPressed: available ? () => _readback(pending) : null,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text('${_label(active)} Readback prüfen'),
                ),
            ],
            if (session != null && session.readyForCertificationWrite)
              _PlanCard(
                session: session,
                onWrite: _busy ? null : _write,
              ),
            if (_writeResult != null) _WriteResultCard(result: _writeResult!),
            if (_readbackResult != null) _ReadbackResultCard(result: _readbackResult!),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(
                _message!,
                key: const Key('matribox-cert-message'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const Divider(height: 24),
            _SongTargetCard(
              loaded: _songTargetsLoaded,
              targets: _songTargets,
              statusOf: (field) => field == MatriboxSol100OdAmpField.gain
                  ? MatriboxCertificationStatus.certified
                  : MatriboxCertification.statusFor(field, _records),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldStatusLine extends StatelessWidget {
  const _FieldStatusLine({required this.field, required this.status});
  final MatriboxSol100OdAmpField field;
  final MatriboxCertificationStatus status;

  @override
  Widget build(BuildContext context) {
    final (symbol, text) = switch (status) {
      MatriboxCertificationStatus.certified => ('✓', 'CERTIFIED'),
      MatriboxCertificationStatus.readyForHardwareTest => ('●', 'READY FOR HARDWARE TEST'),
      MatriboxCertificationStatus.waiting => ('○', 'WAITING'),
      MatriboxCertificationStatus.writeSentAwaitingReadback => ('◐', 'WRITE_SENT · Readback offen'),
      MatriboxCertificationStatus.readbackFailed => ('✗', 'READBACK NICHT ZERTIFIZIERT'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '${_label(field)}\n$symbol $text',
        key: Key('matribox-cert-status-${field.wireName}'),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.session, required this.onWrite});
  final MatriboxCertificationSessionResult session;
  final VoidCallback? onWrite;

  @override
  Widget build(BuildContext context) {
    final field = session.field;
    final evidence = field.evidence;
    String mark(bool ok) => ok ? '✓' : '○';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_label(field)}-Test (Lab, ±1)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                'Current: ${session.currentValue!.toStringAsFixed(0)}\n'
                'Target: ${session.targetValue!.toStringAsFixed(0)}',
                key: const Key('matribox-cert-plan-values'),
              ),
              const SizedBox(height: 6),
              Text(
                'Evidence:\n'
                '${mark(evidence.readable)} Read confirmed\n'
                '${mark(evidence.indexEvidence.name == 'confirmed')} Index confirmed\n'
                '${mark(evidence.rawWriteCaptureEvidence.name == 'confirmed')} Capture confirmed\n'
                '${mark(evidence.encodable)} Encoder golden verified\n'
                '${mark(evidence.hardwareWritable)} Active hardware write '
                '${evidence.hardwareWritable ? 'confirmed' : 'not yet confirmed'}',
              ),
              const SizedBox(height: 6),
              const Text(
                'Backup:\n✓ Read\n✓ Saved\n✓ Reloaded\n✓ Hash verified',
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('matribox-cert-write'),
                onPressed: onWrite,
                child: Text('${_label(field)}-Test schreiben'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WriteResultCard extends StatelessWidget {
  const _WriteResultCard({required this.result});
  final MatriboxCertificationWriteResult result;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    if (!result.isSuccess) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Material(
          key: const Key('matribox-cert-write-failure'),
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Nicht zertifiziert: ${_writeOutcomeMessage(result.outcome)} '
              '(${result.outcome.name}). Kein Retry; für einen neuen '
              'Versuch neu verbinden und neu vorbereiten.',
            ),
          ),
        ),
      );
    }
    final field = result.field!;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        key: const Key('matribox-cert-write-success'),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_label(field)} → ${result.targetValue!.toStringAsFixed(0)}'),
              const Text('WRITE_SENT'),
              const Text('✓ Nachricht gesendet'),
              Text('⚠ Readback noch nicht verifiziert', style: TextStyle(color: errorColor)),
              Text('⚠ nicht dauerhaft gespeichert', style: TextStyle(color: errorColor)),
              if (!result.recordSaved)
                Text(
                  '⚠ Certification-Record konnte nicht gespeichert werden.',
                  style: TextStyle(color: errorColor),
                ),
              const SizedBox(height: 8),
              const Text(
                '1. Wert am Gerät prüfen\n'
                '2. Ergebnis festhalten\n'
                '3. manuell am Gerät speichern\n'
                '4. USB trennen\n'
                '5. neu verbinden\n'
                '6. Readback prüfen',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadbackResultCard extends StatelessWidget {
  const _ReadbackResultCard({required this.result});
  final MatriboxCertificationReadbackResult result;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Material(
      key: Key(
        result.isCertified
            ? 'matribox-cert-readback-certified'
            : 'matribox-cert-readback-failed',
      ),
      color: result.isCertified
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          '${switch (result.outcome) {
            MatriboxCertificationReadbackOutcome.certified => 'CERTIFIED',
            MatriboxCertificationReadbackOutcome.expectedChangeMissing => 'EXPECTED_CHANGE_MISSING',
            MatriboxCertificationReadbackOutcome.unexpectedKnownChange => 'UNEXPECTED_KNOWN_CHANGE',
            MatriboxCertificationReadbackOutcome.unknownRawChange => 'UNKNOWN_RAW_CHANGE',
            MatriboxCertificationReadbackOutcome.readFailed => 'READ_FAILED',
            MatriboxCertificationReadbackOutcome.backupMismatch => 'BACKUP_MISMATCH',
          }}'
          '${result.detail == null ? '' : '\n${result.detail}'}'
          '${result.isCertified ? '\nManuelles Save und QME2 Store sind separat und hier nicht bewertet.' : ''}',
        ),
      ),
    ),
  );
}

class _SongTargetCard extends StatelessWidget {
  const _SongTargetCard({
    required this.loaded,
    required this.targets,
    required this.statusOf,
  });
  final bool loaded;
  final ({String? ampName, Map<String, double> targets})? targets;
  final MatriboxCertificationStatus Function(MatriboxSol100OdAmpField) statusOf;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[];
    for (final field in MatriboxSol100OdAmpField.values) {
      final value = targets?.targets[field.wireName];
      final symbol = statusOf(field) == MatriboxCertificationStatus.certified ? '✓' : '○';
      lines.add(
        '${_label(field).padRight(9)} '
        '${value == null ? (loaded ? 'NOT PROVIDED' : '…') : value.toStringAsFixed(0).padRight(4)}'
        '  Certification $symbol',
      );
    }
    return Column(
      key: const Key('matribox-cert-song-info'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Warum testen wir das?', style: Theme.of(context).textTheme.titleSmall),
        const Text(matriboxSongPreviewLabel),
        Text('Amp: ${targets?.ampName ?? (loaded ? 'UNKNOWN' : '…')}'),
        Text(lines.join('\n')),
        Text(
          'Nur Information. Die Certification schreibt weiterhin ±1, nicht die Song-Zielwerte.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
