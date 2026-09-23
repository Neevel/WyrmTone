import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../presets/matribox_chain_catalog.dart';
import '../presets/matribox_chain_slot.dart';
import '../presets/matribox_full_live_plan.dart';
import '../presets/matribox_full_live_session.dart';
import '../presets/matribox_full_live_verifier.dart';
import '../presets/matribox_raw_backup_service.dart';
import 'matribox_channel_clients.dart';
import 'matribox_raw_backup_panel.dart' show defaultMatriboxRawBackupDirectory;

/// The Full Live certification exists only in a debug build with its own
/// explicit compile gate (see build.gradle.kts). Normal builds render nothing.
const matriboxFullLiveEnabled =
    kDebugMode &&
    bool.fromEnvironment('ENABLE_MATRIBOX_FULL_LIVE_CERTIFICATION', defaultValue: false);

String _algorithmName(int code) {
  for (final a in matriboxCaptureConfirmedAlgorithms) {
    if (a.code == code) return a.name;
  }
  return '0x${code.toRadixString(16).padLeft(8, '0')}';
}

String _runOutcomeMessage(FullLiveRunOutcome outcome) => switch (outcome) {
  FullLiveRunOutcome.success => 'Alle Operationen gesendet.',
  FullLiveRunOutcome.deviceNotConnected => 'Matribox nicht eindeutig als MIDI-Gerät verbunden.',
  FullLiveRunOutcome.midiNotAvailable => 'MIDI-Verbindung aktuell nicht eindeutig verfügbar.',
  FullLiveRunOutcome.safetyRejected => 'Von einer Sicherheitsprüfung abgelehnt.',
  FullLiveRunOutcome.sendFailed => 'Senden ist fehlgeschlagen; Lauf sofort gestoppt.',
  FullLiveRunOutcome.channelError => 'Plattformkanal-Fehler.',
};

String _readbackLabel(FullLiveReadbackOutcome outcome) => switch (outcome) {
  FullLiveReadbackOutcome.certified => 'CERTIFIED',
  FullLiveReadbackOutcome.expectedChangeMissing => 'EXPECTED_CHANGE_MISSING',
  FullLiveReadbackOutcome.unexpectedKnownChange => 'UNEXPECTED_KNOWN_CHANGE',
  FullLiveReadbackOutcome.unknownRawChange => 'UNKNOWN_RAW_CHANGE',
  FullLiveReadbackOutcome.readFailed => 'READ_FAILED',
  FullLiveReadbackOutcome.backupMismatch => 'BACKUP_MISMATCH',
  FullLiveReadbackOutcome.partialExecution => 'PARTIAL_EXECUTION',
};

const _classLabels = {
  FullLiveChangeClass.expectedModelChange: 'EXPECTED_MODEL_CHANGE',
  FullLiveChangeClass.expectedParameterChange: 'EXPECTED_PARAMETER_CHANGE',
  FullLiveChangeClass.expectedBlockChange: 'EXPECTED_BLOCK_CHANGE',
  FullLiveChangeClass.correlatedPart8Change: 'CORRELATED_PART8_CHANGE',
  FullLiveChangeClass.unexpectedKnownChange: 'UNEXPECTED_KNOWN_CHANGE',
  FullLiveChangeClass.unknownRawChange: 'UNKNOWN_RAW_CHANGE',
};

/// Lab/beta UI for the single Full Live Edit Certification of User P01.
/// Every hardware action needs its own manual confirmation; nothing
/// retries, stores, advances or reads on its own.
class MatriboxFullLivePanel extends StatefulWidget {
  const MatriboxFullLivePanel({
    required this.connectionReady,
    required this.monitoring,
    this.enabled = matriboxFullLiveEnabled,
    this.backupDirectory = defaultMatriboxRawBackupDirectory,
    super.key,
  });

  final bool connectionReady;
  final bool monitoring;
  final bool enabled;
  final Future<Directory> Function() backupDirectory;

  @override
  State<MatriboxFullLivePanel> createState() => _MatriboxFullLivePanelState();
}

class _MatriboxFullLivePanelState extends State<MatriboxFullLivePanel> {

  bool _busy = false;
  MatriboxFullLiveRecord? _record;
  FullLiveSessionResult? _session;
  FullLiveRunResult? _runResult;
  FullLiveReadbackResult? _readbackResult;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _loadRecord();
  }

  Future<MatriboxFullLiveStore> _store() async => MatriboxFullLiveStore(
    File('${(await widget.backupDirectory()).path}/$matriboxFullLiveStateFileName'),
  );

  Future<void> _loadRecord() async {
    final record = await (await _store()).load();
    if (mounted) setState(() => _record = record);
  }

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

  Future<void> _prepare() async {
    if (_busy || !widget.connectionReady || widget.monitoring) return;
    final accepted = await _confirm(
      title: 'Full Live Test vorbereiten?',
      body:
          'Sonicake Matribox 1 · User-Preset P01\n\n'
          'Liest zuerst P01 und legt ein Backup an. Danach wird nur der '
          'Plan angezeigt -- es wird noch nichts geschrieben.',
      actionLabel: 'Vorbereiten',
      actionKey: const Key('matribox-fl-prepare-confirm'),
    );
    if (!accepted || !mounted) return;
    setState(() {
      _busy = true;
      _session = null;
      _runResult = null;
      _readbackResult = null;
      _message = null;
    });
    try {
      final result = await MatriboxFullLiveSession(
        backupService: MatriboxRawBackupService(
          channel: const MethodChannelPresetReadChannel(),
          backupDirectory: await widget.backupDirectory(),
        ),
      ).prepare();
      if (!mounted) return;
      setState(() {
        _session = result;
        _message = result.readyForFullLiveTest
            ? null
            : (result.blockedReason ?? 'Vorbereitung fehlgeschlagen.');
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'Vorbereitung fehlgeschlagen: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final session = _session;
    if (_busy || session == null || !session.readyForFullLiveTest) return;
    final hash = session.backup!.sha256!;
    final confirmed = await _confirm(
      title: 'Full Live Test starten?',
      body:
          'Sonicake Matribox 1 · User P01\n'
          'Backup: VERIFIED (${hash.substring(0, 12)}…)\n'
          '${MatriboxFullLivePlan.operations.length} Operationen: '
          '${MatriboxFullLivePlan.modelCount} Modellwahlen, '
          '${MatriboxFullLivePlan.parameterCount} Parameter, '
          '${MatriboxFullLivePlan.toggleCount} Blockschalter\n\n'
          'Dieser Test verändert mehrere Live-Blöcke von P01. Ein '
          'verifiziertes Backup existiert. Es wird kein Store-Befehl '
          'gesendet.',
      actionLabel: 'FULL LIVE TEST STARTEN',
      actionKey: const Key('matribox-fl-start-confirm'),
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _runResult = null;
      // One run per prepared session: consumed by the attempt, successful
      // or not. A new attempt needs a fresh prepare.
      _session = null;
    });
    final result = await MatriboxFullLiveExecutor(
      channel: const MethodChannelFullLiveChannel(),
      store: await _store(),
    ).execute(session);
    await _loadRecord();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _runResult = result;
    });
  }

  Future<void> _readback(MatriboxFullLiveRecord record) async {
    if (_busy || !widget.connectionReady || widget.monitoring) return;
    final accepted = await _confirm(
      title: 'Full Live Readback prüfen?',
      body:
          'Führt einen neuen Lesevorgang von User P01 aus und vergleicht '
          'ihn mit dem Backup vor dem Test und dem Plan. Es wird nichts '
          'geschrieben und nichts gespeichert.',
      actionLabel: 'Readback prüfen',
      actionKey: const Key('matribox-fl-readback-confirm'),
    );
    if (!accepted || !mounted) return;
    setState(() {
      _busy = true;
      _readbackResult = null;
    });
    try {
      final result = await MatriboxFullLiveReadback.run(
        record: record,
        backupService: MatriboxRawBackupService(
          channel: const MethodChannelPresetReadChannel(),
          backupDirectory: await widget.backupDirectory(),
        ),
        store: await _store(),
      );
      await _loadRecord();
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
    final record = _record;
    final pending = record != null && record.state == FullLiveRecordState.sent;
    final session = _session;
    return Card(
      key: const Key('matribox-fl-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    'Matribox Full Live Edit Certification',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
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
              'User P01 · ein Test, der Modelle, Parameter und Blockzustände '
              'in mehreren Chain-Slots live ändert. Kein Store, kein Restore.',
            ),
            const SizedBox(height: 8),
            if (!widget.connectionReady)
              const Text('Passende Matribox eindeutig als MIDI-Gerät öffnen.'),
            if (widget.monitoring) const Text('Passiven Monitor zuerst stoppen.'),
            if (pending)
              FilledButton.icon(
                key: const Key('matribox-fl-readback'),
                onPressed: available ? () => _readback(record) : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Full Live Readback prüfen'),
              )
            else
              FilledButton.icon(
                key: const Key('matribox-fl-prepare'),
                onPressed: available ? _prepare : null,
                icon: const Icon(Icons.science_outlined),
                label: const Text('Full Live Test vorbereiten'),
              ),
            if (session != null && session.readyForFullLiveTest)
              _PlanCard(session: session, onStart: _busy ? null : _start),
            if (_runResult != null) _RunResultCard(result: _runResult!),
            if (_readbackResult != null) _ReadbackCard(result: _readbackResult!),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(
                _message!,
                key: const Key('matribox-fl-message'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.session, required this.onStart});
  final FullLiveSessionResult session;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = session.current!;
    final lines = <Widget>[];
    for (final slot in MatriboxChainSlot.values) {
      final ops = MatriboxFullLivePlan.operations.where((o) => o.slot == slot);
      lines.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(slot.label, style: theme.textTheme.titleSmall),
      ));
      for (final o in ops) {
        final detail = switch (o.kind) {
          FullLiveOperationKind.modelSelect =>
            'MODEL ${o.algorithm!.name} (aktuell ${_algorithmName(current.code(slot))})',
          FullLiveOperationKind.parameter => o.label,
          FullLiveOperationKind.blockToggle =>
            'BLOCK ${o.enabled! ? 'ON' : 'OFF'} (aktuell ${current.isOn(slot) ? 'ON' : 'OFF'})',
        };
        lines.add(Text(detail, key: Key('matribox-fl-op-${slot.label}-${o.kind.name}-${o.label}')));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('User P01'),
              Text('Backup: VERIFIED · Hash ${session.backup!.sha256!.substring(0, 12)}…'),
              Text('Aktuelles Preset: ${current.name}'),
              const SizedBox(height: 4),
              Text(
                '${MatriboxFullLivePlan.operations.length} Operationen: '
                '${MatriboxFullLivePlan.modelCount} Modellwahlen · '
                '${MatriboxFullLivePlan.parameterCount} Parameter · '
                '${MatriboxFullLivePlan.toggleCount} Blockschalter',
                key: const Key('matribox-fl-counts'),
              ),
              ...lines,
              const SizedBox(height: 8),
              Text(
                'Dieser Test verändert mehrere Live-Blöcke von P01. Ein '
                'verifiziertes Backup existiert. Es wird kein Store-Befehl '
                'gesendet.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('matribox-fl-start'),
                onPressed: onStart,
                child: const Text('FULL LIVE TEST STARTEN'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunResultCard extends StatelessWidget {
  const _RunResultCard({required this.result});
  final FullLiveRunResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (result.completed == 0 && !result.isSuccess) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Material(
          key: const Key('matribox-fl-run-failure'),
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Nichts gesendet: ${_runOutcomeMessage(result.outcome)} '
              '(${result.outcome.name}). ${result.error ?? ''}',
            ),
          ),
        ),
      );
    }
    final failed = result.operations.where((o) => o.status == 'FAILED').firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        key: Key(result.isSuccess ? 'matribox-fl-run-success' : 'matribox-fl-run-stopped'),
        color: result.isSuccess
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.isSuccess ? '✓ Full Live Test gesendet' : '⚠ Lauf gestoppt'),
              Text('Abgeschlossen: ${result.completed} von ${result.total}'),
              if (failed != null) Text('Fehlgeschlagen: #${failed.index} ${failed.label}'),
              if (!result.isSuccess)
                Text('Nicht gesendet: ${result.notSent.length} Operationen (kein Retry, kein Rollback)'),
              if (result.error != null) Text(result.error!),
              const SizedBox(height: 6),
              Text('Status: VOLATILE (kein Store)', style: theme.textTheme.titleSmall),
              Text('⚠ Readback noch nicht verifiziert', style: TextStyle(color: theme.colorScheme.error)),
              Text('⚠ nicht dauerhaft gespeichert', style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 6),
              const Text(
                '1. Gerät prüfen: Modelle, Werte, Blockzustände, Sternchen\n'
                '2. Ergebnis festhalten\n'
                '3. Am Gerät MANUELL speichern (der Read sieht nur den gespeicherten Stand; kein Store von WyrmTone)\n'
                '4. Dann "Full Live Readback prüfen"',
              ),
              if (!result.recordSaved && result.completed > 0)
                Text('⚠ Full-Live-Record konnte nicht gespeichert werden.', style: TextStyle(color: theme.colorScheme.error)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadbackCard extends StatelessWidget {
  const _ReadbackCard({required this.result});
  final FullLiveReadbackResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = result.verification;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        key: Key(result.isCertified ? 'matribox-fl-readback-certified' : 'matribox-fl-readback-failed'),
        color: result.isCertified
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_readbackLabel(result.outcome), style: theme.textTheme.titleSmall),
              if (result.detail != null) Text(result.detail!),
              if (v != null) ...[
                const SizedBox(height: 6),
                for (final r in v.operations)
                  Text(
                    '${r.check == FullLiveOperationCheck.matched ? '✓' : '✗'} '
                    '${r.operation.slot.label} ${r.operation.label} → ${r.actual}'
                    '${r.note == null ? '' : ' (${r.note})'}',
                  ),
                const SizedBox(height: 6),
                for (final c in FullLiveChangeClass.values)
                  if (v.count(c) > 0) Text('${_classLabels[c]}: ${v.count(c)} Bytes'),
                if (result.isCertified)
                  const Text(
                    'Volatil bestätigt. Manuelles Save und QME2 Store sind '
                    'separat und hier nicht bewertet.',
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
