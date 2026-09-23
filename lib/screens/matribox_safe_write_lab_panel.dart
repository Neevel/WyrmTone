import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../presets/matribox_confirmed_gain_write_channel.dart';
import '../presets/matribox_preset_write_plan.dart';
import '../presets/matribox_raw_backup_service.dart';
import '../presets/matribox_safe_write_session.dart';
import '../presets/matribox_write_audit.dart';
import '../presets/preset_selection_codec.dart';
import 'matribox_raw_backup_panel.dart' show defaultMatriboxRawBackupDirectory;

// A gain-write build (see build.gradle.kts) always enables the raw-backup
// read/backup capability alongside the write capability -- the Safe Write
// Lab's prepare step needs it -- so this panel must also show up when only
// ENABLE_MATRIBOX_P01_GAIN_WRITE was requested, not only when
// ENABLE_MATRIBOX_P01_RAW_BACKUP itself was.
const matriboxSafeWriteLabEnabled =
    kDebugMode &&
    (bool.fromEnvironment('ENABLE_MATRIBOX_P01_RAW_BACKUP', defaultValue: false) ||
        bool.fromEnvironment('ENABLE_MATRIBOX_P01_GAIN_WRITE', defaultValue: false));

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

/// The one native production write call. No algorithm, index, bank, slot
/// or raw bytes ever cross this boundary -- only the already-derived
/// target gain value.
class _MethodChannelMatriboxConfirmedGainWriteChannel
    implements MatriboxConfirmedGainWriteChannel {
  const _MethodChannelMatriboxConfirmedGainWriteChannel(this._channel);
  final MethodChannel _channel;
  @override
  Future<Map<Object?, Object?>> writeConfirmedSol100OdGain(
    double targetGain,
  ) async =>
      await _channel.invokeMapMethod<Object?, Object?>(
        'writeConfirmedSol100OdGain',
        {'targetGain': targetGain},
      ) ??
      {};
}

String _gainWriteOutcomeMessage(MatriboxGainWriteOutcome outcome) =>
    switch (outcome) {
      MatriboxGainWriteOutcome.success => 'Erfolgreich gesendet.',
      MatriboxGainWriteOutcome.deviceNotConnected =>
        'Matribox nicht eindeutig als MIDI-Gerät verbunden.',
      MatriboxGainWriteOutcome.midiNotAvailable =>
        'MIDI-Verbindung aktuell nicht eindeutig verfügbar (z.B. Monitor aktiv).',
      MatriboxGainWriteOutcome.invalidValue => 'Zielwert außerhalb des gültigen Bereichs.',
      MatriboxGainWriteOutcome.sendFailed => 'Senden ist fehlgeschlagen.',
      MatriboxGainWriteOutcome.safetyRejected =>
        'Von einer Sicherheitsprüfung abgelehnt.',
      MatriboxGainWriteOutcome.channelError => 'Plattformkanal-Fehler.',
    };

/// UI for the Matribox Safe Write pipeline for User/P01: reads and backs
/// up the current preset, builds and safety-validates a write plan, and --
/// only after explicit manual confirmation -- can actually send a single
/// hardware-confirmed Gain write (see [MatriboxSafeWriteExecutor]). Marked
/// LAB/BETA because the only target this milestone can plan is the fixed
/// Gain lab-test delta ([MatriboxWriteLabTarget]), not a real Tone
/// Recommendation; every other AMP field remains BLOCKED. See
/// docs/MATRIBOX_OFFLINE_ANALYSIS.md, "Erster produktiver WyrmTone-
/// Hardware-Write".
class MatriboxSafeWriteLabPanel extends StatefulWidget {
  const MatriboxSafeWriteLabPanel({
    required this.connectionReady,
    required this.monitoring,
    this.enabled = matriboxSafeWriteLabEnabled,
    this.backupDirectory = defaultMatriboxRawBackupDirectory,
    super.key,
  });

  final bool connectionReady;
  final bool monitoring;
  final bool enabled;
  final Future<Directory> Function() backupDirectory;

  @override
  State<MatriboxSafeWriteLabPanel> createState() =>
      _MatriboxSafeWriteLabPanelState();
}

class _MatriboxSafeWriteLabPanelState
    extends State<MatriboxSafeWriteLabPanel> {
  static const _channel = MethodChannel('de.neevel.wyrmtone/usb_methods');
  bool _busy = false;
  bool _writeBusy = false;
  MatriboxSafeWriteSessionResult? _result;
  String? _errorMessage;
  MatriboxGainWriteResult? _writeResult;
  MatriboxWriteAuditEntry? _lastAudit;

  Future<void> _confirmAndPrepare() async {
    if (_busy || !widget.connectionReady || widget.monitoring) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Safe Write Lab für User P01 vorbereiten?'),
        content: const Text(
          'Sonicake Matribox 1 · User-Preset P01\n\n'
          'Liest zuerst den aktuellen Inhalt von P01 und legt ein Backup '
          'an (wie beim normalen Raw-Backup). Danach wird nur ein '
          'Schreibplan berechnet und angezeigt -- es wird dabei noch '
          'nichts auf das Gerät geschrieben.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('matribox-safe-write-lab-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Vorbereiten'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _busy = true;
      _result = null;
      _errorMessage = null;
      _writeResult = null;
      _lastAudit = null;
    });
    try {
      final directory = await widget.backupDirectory();
      final session = MatriboxSafeWriteSession(
        backupService: MatriboxRawBackupService(
          channel: _MethodChannelMatriboxPresetReadChannel(_channel),
          backupDirectory: directory,
        ),
        targetAddress: MatriboxPresetSlotAddress.fromPresetNumber(1),
      );
      final result = await session.prepare();
      if (!mounted) return;
      setState(() {
        _result = result;
        _errorMessage = result.stage == MatriboxSafeWriteSessionStage.blocked
            ? (result.blockedReason ?? 'Vorbereitung fehlgeschlagen.')
            : null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _result = null;
          _errorMessage = 'Vorbereitung fehlgeschlagen: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // The Safe Write Session remains authoritative: this method never calls
  // the native writer directly. It only opens the confirmation dialog for
  // an already-prepared, already-safety-validated result; the actual
  // decision to send is made exactly once, inside MatriboxSafeWriteExecutor,
  // which independently re-derives and re-checks every precondition again.
  Future<void> _confirmAndWrite() async {
    final result = _result;
    if (_writeBusy || result == null || !result.readyForHardwareTest) return;
    final plan = result.plan!;
    final operation = plan.operations.single;
    final presetName = result.currentPreset?.name ?? '?';
    final before = operation.currentValue?.toStringAsFixed(0) ?? '?';
    final target = operation.targetValue.toStringAsFixed(0);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Änderung auf P01 schreiben?'),
        content: Text(
          'Sonicake Matribox 1\n'
          'User P01 · $presetName\n'
          'Backup: VERIFIED\n'
          'Operation: Sol 100 OD · Gain $before → $target\n\n'
          'Diese Änderung wird jetzt an die Matribox gesendet. Sie wird in '
          'diesem Schritt NICHT dauerhaft gespeichert. Kein Store wird '
          'gesendet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('matribox-safe-write-lab-write-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gain auf P01 schreiben'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _writeBusy = true;
      _writeResult = null;
      _lastAudit = null;
    });
    final executor = MatriboxSafeWriteExecutor(
      _MethodChannelMatriboxConfirmedGainWriteChannel(_channel),
    );
    final writeResult = await executor.executeGainWrite(result);
    final audit = MatriboxWriteAuditEntry(
      timestamp: DateTime.now(),
      device: 'Sonicake Matribox 1',
      presetName: presetName,
      backupSha256: result.backup?.sha256 ?? '?',
      field: operation.field,
      beforeValue: operation.currentValue,
      targetValue: operation.targetValue,
      evidence: operation.evidence.name,
      outcome: writeResult.outcome.name,
    );
    if (!mounted) return;
    setState(() {
      _writeBusy = false;
      _writeResult = writeResult;
      _lastAudit = audit;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    final available = widget.connectionReady && !widget.monitoring && !_busy;
    final result = _result;
    return Card(
      key: const Key('matribox-safe-write-lab-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Matribox Safe Write',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'LAB',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'User P01 · Vor jeder Änderung wird das aktuelle Preset '
              'gelesen, gesichert und der Schreibplan geprüft. Aktuell nur '
              'als kontrollierter Gain-Hardwaretest verfügbar, nicht als '
              'allgemeine Preset-Bearbeitung.',
            ),
            const SizedBox(height: 8),
            if (!widget.connectionReady)
              const Text('Passende Matribox eindeutig als MIDI-Gerät öffnen.'),
            if (widget.monitoring)
              const Text('Passiven Monitor zuerst stoppen.'),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('matribox-safe-write-lab-prepare'),
              onPressed: available ? _confirmAndPrepare : null,
              icon: const Icon(Icons.science_outlined),
              label: const Text('Safe Write Lab vorbereiten'),
            ),
            if (result != null &&
                result.stage == MatriboxSafeWriteSessionStage.readyForConfirmation) ...[
              const SizedBox(height: 12),
              _SafeWriteLabPreview(
                result: result,
                onWritePressed: _writeBusy ? null : _confirmAndWrite,
              ),
            ],
            if (_writeResult != null) ...[
              const SizedBox(height: 12),
              _SafeWriteResultView(result: _writeResult!, audit: _lastAudit),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                key: const Key('matribox-safe-write-lab-message'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SafeWriteLabPreview extends StatelessWidget {
  const _SafeWriteLabPreview({required this.result, required this.onWritePressed});

  final MatriboxSafeWriteSessionResult result;
  final VoidCallback? onWritePressed;

  @override
  Widget build(BuildContext context) {
    final plan = result.plan;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Target: User P01'),
            Text('Aktuelles Preset: ${result.currentPreset?.name ?? '?'}'),
            const SizedBox(height: 6),
            const _CheckLine('gelesen'),
            const _CheckLine('gespeichert'),
            const _CheckLine('erneut geladen'),
            const _CheckLine('Hash validiert'),
            const SizedBox(height: 8),
            Text(
              'Geplante Änderung (Hardware-Lab-Test)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              'Fester Test-Delta (aktueller Wert + 1), kein Tone-'
              'Recommendation-Ziel.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            if (plan == null || plan.operations.isEmpty)
              const Text('Keine Änderung geplant (Zielwert entspricht bereits dem aktuellen Wert).')
            else
              for (final op in plan.operations)
                Text(
                  'AMP / ${result.targetPreset?.amp?.algorithmName ?? 'Sol 100 OD'} · '
                  '${op.field}: ${op.currentValue?.toStringAsFixed(0) ?? '?'} → '
                  '${op.targetValue.toStringAsFixed(0)}\n'
                  'Evidence: ${op.writable ? 'WRITE CONFIRMED' : 'BLOCKED'}',
                  key: Key('matribox-safe-write-lab-operation-${op.field}'),
                ),
            const SizedBox(height: 4),
            const Text('Alle anderen Felder: UNCHANGED'),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('matribox-safe-write-lab-write'),
              onPressed: result.readyForHardwareTest ? onWritePressed : null,
              child: const Text('Änderung auf P01 schreiben'),
            ),
            if (plan != null && plan.gate == MatriboxWritePlanGate.blocked) ...[
              const SizedBox(height: 4),
              Text(
                'Nicht bereit: ${plan.blockers.join(' ')}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows the outcome of exactly one send attempt. On success this is
/// deliberately NOT a "done" state: it must make clear that nothing has
/// been read back or persisted yet, and it must never trigger either of
/// those steps by itself.
class _SafeWriteResultView extends StatelessWidget {
  const _SafeWriteResultView({required this.result, required this.audit});

  final MatriboxGainWriteResult result;
  final MatriboxWriteAuditEntry? audit;

  @override
  Widget build(BuildContext context) {
    final auditLine = audit == null
        ? null
        : 'Audit: ${audit!.presetName} · Backup ${audit!.backupSha256.substring(0, audit!.backupSha256.length.clamp(0, 12))}… · '
              '${audit!.outcome} · ${audit!.timestamp.toIso8601String()}';
    if (result.isSuccess) {
      return Material(
        key: const Key('matribox-safe-write-lab-write-success'),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('✓ Gain-Write gesendet'),
              const Text('Sol 100 OD'),
              Text('Gain → ${result.targetValue?.toStringAsFixed(0) ?? '?'}'),
              const Text('Status: VOLATILE_WRITE_SENT'),
              const SizedBox(height: 8),
              Text(
                'Readback noch nicht verifiziert',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              Text(
                'Preset noch nicht dauerhaft gespeichert',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
              const Text(
                'Nächster Schritt: Matribox physisch neu verbinden und P01 '
                'erneut lesen.',
              ),
              if (auditLine != null) ...[
                const SizedBox(height: 8),
                Text(auditLine, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      );
    }
    return Material(
      key: const Key('matribox-safe-write-lab-write-failure'),
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gain-Write nicht erfolgreich: ${result.outcome.name} -- '
              '${_gainWriteOutcomeMessage(result.outcome)}',
            ),
            if (auditLine != null) ...[
              const SizedBox(height: 8),
              Text(auditLine, style: Theme.of(context).textTheme.bodySmall),
            ],
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
