import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../presets/matribox_family_expansion_certification.dart';
import '../presets/matribox_full_live_plan.dart';
import '../presets/matribox_full_live_session.dart';
import '../presets/matribox_full_live_verifier.dart';
import '../presets/matribox_model_library.dart';
import '../presets/matribox_raw_backup_service.dart';
import 'matribox_channel_clients.dart';
import 'matribox_raw_backup_panel.dart' show defaultMatriboxRawBackupDirectory;
import 'preset_workspace_page.dart' show loadDevicePresetCatalog;

/// Debug-only, own compile gate (exclusive with every other hardware sender,
/// including the productive Tone Transfer gate). Default false; release false.
const matriboxFamilyExpansionEnabled =
    kDebugMode && bool.fromEnvironment('ENABLE_MATRIBOX_FAMILY_EXPANSION_P01_V1', defaultValue: false);

Future<MatriboxModelLibrary> loadFamilyExpansionLibrary() async =>
    MatriboxModelLibrary.fromVendor(await loadDevicePresetCatalog());

String _hex(int code) => '0x${code.toRadixString(16).padLeft(8, '0')}';

/// EXPERIMENTAL lab panel for the ONE certification test
/// `FAMILY_EXPANSION_P01_V1` on User P01. Nothing here sends on open,
/// connect, prepare or backup; the live write needs the typed test name, the
/// verification needs the physical check AND the manual-save confirmation.
/// WyrmTone sends no Store; the user saves on the Matribox itself.
class MatriboxFamilyExpansionPanel extends StatefulWidget {
  const MatriboxFamilyExpansionPanel({
    required this.connectionReady,
    required this.monitoring,
    this.enabled = matriboxFamilyExpansionEnabled,
    this.backupDirectory = defaultMatriboxRawBackupDirectory,
    this.libraryLoader = loadFamilyExpansionLibrary,
    this.readChannel = const MethodChannelPresetReadChannel(),
    this.familyChannel = const MethodChannelFamilyExpansionChannel(),
    super.key,
  });

  final bool connectionReady;
  final bool monitoring;
  final bool enabled;
  final Future<Directory> Function() backupDirectory;
  final Future<MatriboxModelLibrary> Function() libraryLoader;
  final MatriboxPresetReadChannel readChannel;
  final MatriboxFamilyExpansionChannel familyChannel;

  @override
  State<MatriboxFamilyExpansionPanel> createState() => _MatriboxFamilyExpansionPanelState();
}

class _MatriboxFamilyExpansionPanelState extends State<MatriboxFamilyExpansionPanel> {
  final _checkpoint = FamilyExpansionCheckpoint();
  bool _busy = false;
  FamilyExpansionP01Plan? _plan;
  MatriboxFullLiveRecord? _record;
  FullLiveSessionResult? _session;
  FullLiveRunResult? _run;
  FullLiveReadbackResult? _readback;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _init();
  }

  Future<MatriboxFullLiveStore> _store() async => MatriboxFullLiveStore(
    File('${(await widget.backupDirectory()).path}/$matriboxFamilyExpansionStateFileName'),
  );

  Future<void> _init() async {
    try {
      final plan = FamilyExpansionP01Plan(await widget.libraryLoader());
      final record = await (await _store()).load();
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _record = record;
        // A stored record never carries a confirmation: physical check and
        // manual save must be confirmed again in this app session.
        if (record != null && record.readbackOutcome != 'certified') _checkpoint.liveWriteEnded();
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'Plan konnte nicht geladen werden: $error');
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String actionLabel,
    required Key actionKey,
    bool typeTestName = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) {
          final controller = TextEditingController();
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(body),
                  if (typeTestName) ...[
                    const SizedBox(height: 12),
                    Text('Zur Bestätigung „${FamilyExpansionP01Plan.planIdValue}“ eintippen:'),
                    TextField(
                      key: const Key('family-confirm-field'),
                      controller: controller,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
                FilledButton(
                  key: actionKey,
                  onPressed: !typeTestName || controller.text.trim() == FamilyExpansionP01Plan.planIdValue
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: Text(actionLabel),
                ),
              ],
            ),
          );
        },
      ) ==
      true;

  Future<MatriboxRawBackupService> _backupService() async => MatriboxRawBackupService(
    channel: widget.readChannel,
    backupDirectory: await widget.backupDirectory(),
  );

  /// A. connected, B. User P01, C. fresh full read, D. raw backup + hash. Sends nothing.
  Future<void> _prepare() async {
    final plan = _plan;
    if (_busy || plan == null || !widget.connectionReady || widget.monitoring) return;
    final accepted = await _confirm(
      title: 'FAMILY_EXPANSION_P01_V1 vorbereiten?',
      body:
          'Sonicake Matribox 1 · User P01\n\nLiest P01 frisch (vollständig), legt ein Roh-Backup an, '
          'verifiziert es und zeigt den Hash. Es wird noch nichts geschrieben.',
      actionLabel: 'Vorbereiten',
      actionKey: const Key('family-prepare-confirm'),
    );
    if (!accepted || !mounted) return;
    setState(() {
      _busy = true;
      _session = null;
      _run = null;
      _readback = null;
      _message = null;
    });
    try {
      final result = await MatriboxFullLiveSession(backupService: await _backupService(), plan: plan).prepare();
      if (!mounted) return;
      setState(() {
        _session = result;
        _message = result.readyForFullLiveTest ? null : (result.blockedReason ?? 'Vorbereitung fehlgeschlagen.');
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'Vorbereitung fehlgeschlagen: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// F/G. explicit confirmation, then ONE native call. Never retried.
  Future<void> _start() async {
    final plan = _plan;
    final session = _session;
    if (_busy || plan == null || session == null || !session.readyForFullLiveTest) return;
    final hash = session.backup!.sha256!;
    final confirmed = await _confirm(
      title: 'FAMILY_EXPANSION_P01_V1 starten?',
      body:
          'Sonicake Matribox 1 · User P01\nBackup: VERIFIED\nSHA-256: $hash\n'
          '${plan.operations.length} Operationen: ${plan.modelCount} Modellwahlen, '
          '${plan.parameterCount} Parameter, ${plan.toggleCount} Blockschalter\n\n'
          'Experimenteller Test. Er verändert P01 live und wird NICHT gespeichert. '
          'Kein Retry, kein Rollback, kein Store.',
      actionLabel: 'FAMILY_EXPANSION_P01_V1 STARTEN',
      actionKey: const Key('family-start-confirm'),
      typeTestName: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _run = null;
      _session = null; // one prepared session, one attempt
    });
    final result = await MatriboxFullLiveExecutor(
      channel: FamilyExpansionRunChannel(widget.familyChannel, hash),
      store: await _store(),
      plan: plan,
    ).execute(session);
    final record = await (await _store()).load();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _run = result;
      _record = record;
      if (result.completed > 0 || result.isSuccess) _checkpoint.liveWriteEnded();
    });
  }

  /// H-L. STOP after the write; the next step is the user's, not a read.
  Future<void> _verify() async {
    final plan = _plan;
    final record = _record;
    if (_busy || plan == null || record == null || !_checkpoint.mayVerify) return;
    final accepted = await _confirm(
      title: 'Fresh Readback und Verification?',
      body:
          'Liest P01 neu vom Gerät und vergleicht Ausgang, Ziel und Ergebnis. Es wird nichts geschrieben.\n\n'
          'Der Read sieht nur den am Gerät GESPEICHERTEN Stand.',
      actionLabel: 'Readback prüfen',
      actionKey: const Key('family-readback-confirm'),
    );
    if (!accepted || !mounted) return;
    setState(() {
      _busy = true;
      _readback = null;
    });
    try {
      final result = await verifyFamilyExpansionAfterManualSave(
        checkpoint: _checkpoint,
        record: record,
        backupService: await _backupService(),
        store: await _store(),
        plan: plan,
      );
      final updated = await (await _store()).load();
      if (mounted) {
        setState(() {
          _readback = result;
          _record = updated;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final plan = _plan;
    final session = _session;
    final record = _record;
    final available = widget.connectionReady && !widget.monitoring && !_busy && plan != null;
    final awaitingManualSteps = record != null &&
        record.readbackOutcome != 'certified' &&
        _checkpoint.stage != FamilyExpansionStage.beforeRun;
    return Card(
      key: const Key('family-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(child: Text(FamilyExpansionP01Plan.planIdValue, style: theme.textTheme.titleMedium)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('EXPERIMENTELL · DEBUG/CERTIFICATION', style: theme.textTheme.labelSmall),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Target: Matribox 1 · User P01'),
            const Text(
              'Ein kontrollierter Lauf, der technische Schreib- und Persistenzfähigkeit mehrerer Protokollfamilien '
              'prüft. Er bestätigt KEINE musikalische Eignung. Kein Store durch WyrmTone, kein Name/BPM/VOL, kein Retry.',
            ),
            const SizedBox(height: 4),
            const Text(
              'Ablauf: 1 Verbinden · 2 User P01 · 3 Full Read · 4 Backup+Hash · 5 Plan · 6 Bestätigung · '
              '7 Live-Write · 8 STOP · 9 am Gerät prüfen · 10 am Gerät speichern · 11 „Ich habe am Gerät gespeichert“ · '
              '12 frischer Readback · 13 Vergleich.',
              key: Key('family-steps'),
            ),
            if (!widget.connectionReady) const Text('Passende Matribox eindeutig als MIDI-Gerät öffnen.'),
            if (widget.monitoring) const Text('Passiven Monitor zuerst stoppen.'),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('family-prepare'),
              onPressed: available ? _prepare : null,
              icon: const Icon(Icons.science_outlined),
              label: Text(awaitingManualSteps ? 'Neuen Lauf vorbereiten' : 'FAMILY_EXPANSION_P01_V1 vorbereiten'),
            ),
            if (plan != null && session != null && session.readyForFullLiveTest) _preview(context, plan, session),
            if (_run != null) _runCard(context, _run!),
            if (awaitingManualSteps) _manualSteps(context, available),
            if (_readback != null) _readbackCard(context, _readback!),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!, key: const Key('family-message'), style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _preview(BuildContext context, FamilyExpansionP01Plan plan, FullLiveSessionResult session) {
    final theme = Theme.of(context);
    final hash = session.backup!.sha256!;
    final lines = <Widget>[];
    for (final o in plan.operations) {
      var text = '${o.slot.label}: ${o.label}';
      if (o.kind == FullLiveOperationKind.modelSelect) text += ' · Katalog-Code ${_hex(o.algorithm!.code)}';
      if (o.kind == FullLiveOperationKind.parameter && o.parameter!.xmlId != null) {
        text += ' · Wire ${o.parameter!.wireIndex} (Hersteller-ID ${o.parameter!.xmlId} − 1)';
      }
      lines.add(Text(text, key: Key('family-op-${lines.length}')));
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
              const Text('✓ Device read'),
              const Text('✓ Backup'),
              const Text('✓ Reload'),
              const Text('Backup: VERIFIED'),
              SelectableText('SHA-256: $hash', key: const Key('family-hash')),
              Text('Quelle: ${session.current!.name}'),
              const SizedBox(height: 6),
              Text(
                '${plan.operations.length} Operationen: ${plan.modelCount} MODEL SELECT · '
                '${plan.parameterCount} PARAMETER · ${plan.toggleCount} BLOCK CC (inkl. Tier B: FX1 Boost, AMP Sol 100 OD)',
                key: const Key('family-counts'),
                style: theme.textTheme.titleSmall,
              ),
              ...lines,
              const SizedBox(height: 8),
              Text(
                'Dieser Test verändert P01 live. Ein verifiziertes Backup existiert. Es wird nicht gespeichert.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('family-start'),
                onPressed: _busy ? null : _start,
                child: const Text('FAMILY_EXPANSION_P01_V1 STARTEN'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _runCard(BuildContext context, FullLiveRunResult run) {
    final theme = Theme.of(context);
    if (run.completed == 0 && !run.isSuccess) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'Nichts gesendet: ${run.error ?? run.outcome.name}',
          key: const Key('family-run-nothing'),
          style: TextStyle(color: theme.colorScheme.error),
        ),
      );
    }
    final failed = run.operations.where((o) => o.status == 'FAILED').firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        key: Key(run.isSuccess ? 'family-live-complete' : 'family-run-stopped'),
        color: run.isSuccess ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                run.isSuccess ? 'LIVE WRITE COMPLETE – STOP' : '⚠ Lauf gestoppt – STOP',
                style: theme.textTheme.titleMedium,
              ),
              Text('completed: ${run.completed} · failed: ${failed == null ? 0 : 1} · notSent: ${run.notSent.length}'),
              if (failed != null)
                Text(
                  'Fehlgeschlagen: #${failed.index} ${failed.label} · '
                  'Gerätezustand dieser Operation: UNKNOWN (kein Erfolg behauptet)',
                ),
              if (run.error != null) Text(run.error!),
              const Text('Status: VOLATILE (kein Store). Kein Readback als Persistenzprüfung.'),
            ],
          ),
        ),
      ),
    );
  }

  /// I. physical check -> J/K. manual save on the device + explicit confirmation -> L. readback.
  Widget _manualSteps(BuildContext context, bool available) {
    final stage = _checkpoint.stage;
    final checked = stage == FamilyExpansionStage.physicallyChecked || stage == FamilyExpansionStage.manualSaveConfirmed;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Am Gerät prüfen: FX1 Boost · FX2 Boost (Gain 23, Bright an) · AMP Sol 100 OD · NR Gate 2 (THRE 31, ON) · '
            'CAB Sol 4x12 (VOL 43) · EQ Guitar EQ (400Hz −23, ON) · MOD Chorus A (Rate 3.7) · DLY Warm (Time 743, Trail an) · '
            'RVB Room (Mix 23, Decay 41, Trail an, ON) · Sternchen/Modified-Marker.\n'
            'Das prüft nur die technische Übertragung, nicht den Klang.\n\n'
            'Dann am Gerät MANUELL speichern. WyrmTone sendet keinen Store (QME2 Store bleibt UNKNOWN/BLOCKED).',
            key: Key('family-manual-instructions'),
          ),
          CheckboxListTile(
            key: const Key('family-physical-check'),
            contentPadding: EdgeInsets.zero,
            value: checked,
            onChanged: stage == FamilyExpansionStage.liveWriteDone
                ? (v) => setState(() {
                    if (v == true) _checkpoint.confirmPhysicalCheck();
                  })
                : null,
            title: const Text('Ich habe die Werte am Gerät geprüft'),
          ),
          FilledButton(
            key: const Key('family-saved-confirm'),
            onPressed: stage == FamilyExpansionStage.physicallyChecked
                ? () => setState(_checkpoint.confirmManualSave) // sends nothing
                : null,
            child: const Text('Ich habe am Gerät gespeichert'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('family-readback'),
            onPressed: available && _checkpoint.mayVerify ? _verify : null,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('FRISCHER READBACK + VERGLEICH'),
          ),
        ],
      ),
    );
  }

  Widget _readbackCard(BuildContext context, FullLiveReadbackResult r) {
    final theme = Theme.of(context);
    final v = r.verification;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        key: Key(r.isCertified ? 'family-readback-certified' : 'family-readback-failed'),
        color: r.isCertified ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(familyExpansionResultLabel(r.outcome), style: theme.textTheme.titleSmall),
              if (r.detail != null) Text(r.detail!),
              if (v != null) ...[
                for (final o in v.operations)
                  Text(
                    '${o.check == FullLiveOperationCheck.matched ? '✓' : '✗'} ${o.operation.slot.label} '
                    '${o.operation.label} → ${o.actual}',
                  ),
                for (final violation in v.requiredModelViolations) Text('✗ $violation'),
                Text('Unberührt: ${v.untouchedSlots.map((s) => s.label).join(', ')}'),
                Text(
                  'CORRELATED_PART8_CHANGE: ${v.count(FullLiveChangeClass.correlatedPart8Change)} Bytes '
                  '(nur korreliert, kein bestätigter Checksum)',
                  key: const Key('family-part8'),
                ),
                Text(
                  'UNEXPECTED_KNOWN_CHANGE: ${v.count(FullLiveChangeClass.unexpectedKnownChange)} · '
                  'UNKNOWN_RAW_CHANGE: ${v.count(FullLiveChangeClass.unknownRawChange)}',
                ),
              ],
              if (r.isCertified) ...[
                const Text(familyExpansionSuccessLabel, key: Key('family-success')),
                const Text(
                  'Nach manuellem Speichern am Gerät verifiziert. WyrmTone hat keinen Store gesendet. '
                  'Das ist keine Aussage über musikalische Eignung; produktive Freigaben brauchen einen separaten Auftrag.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
