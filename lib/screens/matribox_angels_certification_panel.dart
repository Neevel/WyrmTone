import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/guitar_profile.dart';
import '../models/tone_target.dart';
import '../presets/matribox_angels_product_plan.dart';
import '../presets/matribox_full_live_plan.dart';
import '../presets/matribox_full_live_session.dart';
import '../presets/matribox_full_live_verifier.dart';
import '../presets/matribox_hardware_evidence.dart';
import '../presets/matribox_raw_backup_service.dart';
import '../presets/matribox_tone_transfer_pipeline.dart';
import '../presets/matribox_tone_transfer_session.dart' show loadHardwareLedger;
import '../services/offline_sound_profiles.dart';
import 'matribox_channel_clients.dart';
import 'matribox_raw_backup_panel.dart' show defaultMatriboxRawBackupDirectory;
import 'preset_workspace_page.dart' show loadDevicePresetCatalog;

/// Debug-only, own compile gate (exclusive with every other hardware sender).
const matriboxAngelsCertificationEnabled =
    kDebugMode && bool.fromEnvironment('ENABLE_MATRIBOX_ANGELS_PRODUCT_CERTIFICATION', defaultValue: false);

const _referenceGuitar = GuitarProfile(
  id: 'hb-fusion-4',
  name: 'HB Fusion 4',
  guitarType: GuitarType.superstrat,
  pickupType: PickupType.passiveHumbucker,
  outputLevel: OutputLevel.medium,
  toneCharacter: ToneCharacter.neutral,
  tuning: GuitarTuning.dropC,
  playbackPath: PlaybackPath.headphones,
);

/// The Sound Engine V2 result for the certification reference request.
Future<ToneTransferRecommendation> loadAngelsReferenceRecommendation() async {
  final profiles = await OfflineSoundProfiles.load();
  final catalog = await loadDevicePresetCatalog();
  final profile = profiles.firstWhere((p) => p.id == 'cob-angels-dont-kill');
  return MatriboxToneTransferPipeline.recommend(
    profile: profile,
    guitar: _referenceGuitar,
    tuning: GuitarTuning.dropC,
    role: SoundRole.rhythm,
    catalog: catalog,
  );
}

String _hex(int code) => '0x${code.toRadixString(16).padLeft(8, '0')}';

String _readbackLabel(FullLiveReadbackOutcome o) => switch (o) {
  FullLiveReadbackOutcome.certified => 'CERTIFIED',
  FullLiveReadbackOutcome.expectedChangeMissing => 'TARGET_MISMATCH',
  FullLiveReadbackOutcome.unexpectedKnownChange => 'UNEXPECTED_KNOWN_CHANGE',
  FullLiveReadbackOutcome.unknownRawChange => 'UNKNOWN_RAW_CHANGE',
  FullLiveReadbackOutcome.readFailed => 'READ_FAILED',
  FullLiveReadbackOutcome.backupMismatch => 'BACKUP_MISMATCH',
  FullLiveReadbackOutcome.partialExecution => 'PARTIAL_EXECUTION',
};

/// Lab panel for the ONE product-unlock certification of User P01:
/// `ANGELS_DONT_KILL_P01_V1`. Every hardware step needs its own manual
/// confirmation; nothing retries, stores, restores or reads on its own.
class MatriboxAngelsCertificationPanel extends StatefulWidget {
  const MatriboxAngelsCertificationPanel({
    required this.connectionReady,
    required this.monitoring,
    this.enabled = matriboxAngelsCertificationEnabled,
    this.backupDirectory = defaultMatriboxRawBackupDirectory,
    this.recommendationLoader = loadAngelsReferenceRecommendation,
    this.readChannel = const MethodChannelPresetReadChannel(),
    this.fullLiveChannel = const MethodChannelFullLiveChannel(),
    super.key,
  });

  final bool connectionReady;
  final bool monitoring;
  final bool enabled;
  final Future<Directory> Function() backupDirectory;
  final Future<ToneTransferRecommendation> Function() recommendationLoader;
  final MatriboxPresetReadChannel readChannel;
  final MatriboxFullLiveChannel fullLiveChannel;

  @override
  State<MatriboxAngelsCertificationPanel> createState() => _MatriboxAngelsCertificationPanelState();
}

class _MatriboxAngelsCertificationPanelState extends State<MatriboxAngelsCertificationPanel> {
  bool _busy = false;
  ToneTransferRecommendation? _recommendation;
  AngelsProductPlan? _plan;
  MatriboxHardwareLedger? _ledger;
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
    File('${(await widget.backupDirectory()).path}/$matriboxAngelsStateFileName'),
  );

  Future<void> _init() async {
    try {
      final recommendation = await widget.recommendationLoader();
      final plan = AngelsProductPlan(library: recommendation.library, target: recommendation.target);
      final directory = await widget.backupDirectory();
      final ledger = await loadHardwareLedger(directory, library: recommendation.library);
      final record = await (await _store()).load();
      if (!mounted) return;
      setState(() {
        _recommendation = recommendation;
        _plan = plan;
        _ledger = ledger;
        _record = record;
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'Sound Engine konnte nicht geladen werden: $error');
    }
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
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
            FilledButton(
              key: actionKey,
              onPressed: () => Navigator.pop(context, true),
              child: Text(actionLabel),
            ),
          ],
        ),
      ) ==
      true;

  Future<MatriboxRawBackupService> _backupService() async => MatriboxRawBackupService(
    channel: widget.readChannel,
    backupDirectory: await widget.backupDirectory(),
  );

  Future<void> _prepare() async {
    final plan = _plan;
    if (_busy || plan == null || !widget.connectionReady || widget.monitoring) return;
    final accepted = await _confirm(
      title: 'Angels-Test vorbereiten?',
      body:
          'Sonicake Matribox 1 · User P01\n\nLiest P01 frisch, legt ein Backup an und '
          'prüft den Ausgangszustand. Es wird noch nichts geschrieben.',
      actionLabel: 'Vorbereiten',
      actionKey: const Key('angels-prepare-confirm'),
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

  Future<void> _start() async {
    final plan = _plan;
    final session = _session;
    if (_busy || plan == null || session == null || !session.readyForFullLiveTest) return;
    final confirmed = await _confirm(
      title: 'Angels Product Test starten?',
      body:
          'Sonicake Matribox 1 · User P01\nBackup: VERIFIED (${session.backup!.sha256!.substring(0, 12)}…)\n'
          '${plan.operations.length} Operationen: ${plan.modelCount} Modellwahlen, '
          '${plan.parameterCount} Parameter, ${plan.toggleCount} Blockschalter\n\n'
          'Dieser Test verändert P01 live. Ein verifiziertes Backup existiert. Es wird nicht gespeichert.',
      actionLabel: 'ANGELS PRODUCT TEST STARTEN',
      actionKey: const Key('angels-start-confirm'),
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _run = null;
      _session = null; // one prepared session, one attempt
    });
    final result = await MatriboxFullLiveExecutor(
      channel: widget.fullLiveChannel,
      store: await _store(),
      plan: plan,
    ).execute(session);
    final record = await (await _store()).load();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _run = result;
      _record = record;
    });
  }

  Future<void> _readbackRun() async {
    final plan = _plan;
    final record = _record;
    if (_busy || plan == null || record == null) return;
    final accepted = await _confirm(
      title: 'Angels Readback prüfen?',
      body:
          'Liest P01 neu vom Gerät und vergleicht Ausgang, Ziel und Ergebnis. Es wird nichts geschrieben.\n\n'
          'Wichtig: Der Read sieht nur den am Gerät GESPEICHERTEN Stand. Live-Änderungen davor manuell am Gerät speichern.',
      actionLabel: 'Readback prüfen',
      actionKey: const Key('angels-readback-confirm'),
    );
    if (!accepted || !mounted) return;
    setState(() {
      _busy = true;
      _readback = null;
    });
    try {
      final result = await MatriboxFullLiveReadback.run(
        record: record,
        backupService: await _backupService(),
        store: await _store(),
        plan: plan,
      );
      final updated = await (await _store()).load();
      final ledger = await loadHardwareLedger(await widget.backupDirectory(), library: _recommendation!.library);
      if (mounted) {
        setState(() {
          _readback = result;
          _record = updated;
          _ledger = ledger;
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
    // The read only sees the SAVED preset, so a readback can be repeated (e.g. after the manual save).
    final pendingReadback = record != null && record.readbackOutcome != 'certified';
    return Card(
      key: const Key('angels-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(child: Text("Angels Don't Kill – Product Unlock", style: theme.textTheme.titleMedium)),
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
            const Text('Target: User P01'),
            const Text("Song: Children of Bodom – Angels Don't Kill"),
            const Text('Guitar: HB Fusion 4'),
            const Text('Tuning: Drop C'),
            const SizedBox(height: 4),
            const Text(
              'Ein Test, der genau den aktuellen Sound-Engine-V2-Plan live auf P01 ausführt. '
              'Kein Store, kein Name/BPM/VOL, kein Restore.',
            ),
            if (!widget.connectionReady) const Text('Passende Matribox eindeutig als MIDI-Gerät öffnen.'),
            if (widget.monitoring) const Text('Passiven Monitor zuerst stoppen.'),
            const SizedBox(height: 8),
            if (pendingReadback)
              FilledButton.icon(
                key: const Key('angels-readback'),
                onPressed: available ? _readbackRun : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('ANGELS READBACK PRÜFEN'),
              ),
            // A new run stays available: the preparation re-checks the source
            // preset and refuses (SOURCE_PRESET_MISMATCH / ALREADY_AT_TARGET)
            // unless P01 is the known starting point.
            if (pendingReadback) const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('angels-prepare'),
              onPressed: available ? _prepare : null,
              icon: const Icon(Icons.science_outlined),
              label: Text(pendingReadback ? 'Neuen Lauf vorbereiten' : 'Angels-Test vorbereiten'),
            ),
            if (plan != null && session != null && session.readyForFullLiveTest) _preview(context, plan, session),
            if (_run != null) _runCard(context, _run!),
            if (_readback != null) _readbackCard(context, _readback!),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!, key: const Key('angels-message'), style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (record != null && record.readbackOutcome == 'certified' && _readback == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Zertifiziert (gespeicherter Record). Noch nicht dauerhaft gespeichert.'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _preview(BuildContext context, AngelsProductPlan plan, FullLiveSessionResult session) {
    final theme = Theme.of(context);
    final ledger = _ledger;
    final lines = <Widget>[];
    for (final o in plan.operations) {
      var text = '${o.slot.label}: ${o.label}';
      if (o.kind == FullLiveOperationKind.modelSelect) {
        final model = o.algorithm!;
        final certified = ledger?.model(o.slot, plan.library.byName(o.slot, model.name)!).exact ?? false;
        text += ' · Katalog-Code ${_hex(model.code)}${certified ? '' : ' [NOT YET HARDWARE CERTIFIED]'}';
      }
      lines.add(Text(text, key: Key('angels-op-${lines.length}')));
    }
    final hash = session.backup!.sha256!;
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
              Text('✓ Hash verified (${hash.substring(0, 12)}…)', key: const Key('angels-hash')),
              Text('Quelle: ${session.current!.name}'),
              const SizedBox(height: 6),
              Text(
                '${plan.operations.length} erwartete Änderungen: ${plan.modelCount} MODEL SELECT · '
                '${plan.parameterCount} PARAMETER · ${plan.toggleCount} BLOCK CC',
                key: const Key('angels-counts'),
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
                key: const Key('angels-start'),
                onPressed: _busy ? null : _start,
                child: const Text('ANGELS PRODUCT TEST STARTEN'),
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
          key: const Key('angels-run-nothing'),
          style: TextStyle(color: theme.colorScheme.error),
        ),
      );
    }
    final failed = run.operations.where((o) => o.status == 'FAILED').firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        key: Key(run.isSuccess ? 'angels-live-complete' : 'angels-run-stopped'),
        color: run.isSuccess ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                run.isSuccess ? 'LIVE WRITE COMPLETE – Gerät prüfen' : '⚠ Lauf gestoppt',
                style: theme.textTheme.titleMedium,
              ),
              Text('completed: ${run.completed} · failed: ${failed == null ? 0 : 1} · notSent: ${run.notSent.length}'),
              if (failed != null) Text('Fehlgeschlagen: #${failed.index} ${failed.label}'),
              if (run.error != null) Text(run.error!),
              const Text('Status: VOLATILE (kein Store)'),
              const SizedBox(height: 6),
              const Text(
                'Bitte am Gerät prüfen:\n'
                '• FX1 OFF\n• FX2 Boost ON\n• AMP Sol 100 OD: Gain 67, Presence 59, Bass 41, Middle 59, Treble 61\n'
                '• CAB Sol 4x12 ON\n• EQ OFF\n• Sternchen/Modified-Marker vorhanden\n'
                '• NR / MOD / DLY / RVB wie zuvor\n'
                '\nDann am Gerät MANUELL speichern (WyrmTone sendet keinen Store; der Read sieht nur den gespeicherten Stand). '
                'Danach „ANGELS READBACK PRÜFEN“.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _readbackCard(BuildContext context, FullLiveReadbackResult r) {
    final theme = Theme.of(context);
    final v = r.verification;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        key: Key(r.isCertified ? 'angels-readback-certified' : 'angels-readback-failed'),
        color: r.isCertified ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_readbackLabel(r.outcome), style: theme.textTheme.titleSmall),
              if (r.detail != null) Text(r.detail!),
              if (v != null) ...[
                for (final o in v.operations)
                  Text(
                    '${o.check == FullLiveOperationCheck.matched ? '✓' : '✗'} ${o.operation.slot.label} '
                    '${o.operation.label} → ${o.actual}',
                  ),
                for (final violation in v.requiredModelViolations) Text('✗ $violation'),
                Text('Unberührt: ${v.untouchedSlots.map((s) => s.label).join(', ')}'),
                Text('CORRELATED_PART8_CHANGE: ${v.count(FullLiveChangeClass.correlatedPart8Change)} Bytes'),
                Text(
                  'UNEXPECTED_KNOWN_CHANGE: ${v.count(FullLiveChangeClass.unexpectedKnownChange)} · '
                  'UNKNOWN_RAW_CHANGE: ${v.count(FullLiveChangeClass.unknownRawChange)}',
                ),
              ],
              if (r.isCertified) ...[
                const Text('Live-Sound erfolgreich verifiziert (nach manuellem Speichern am Gerät).', key: Key('angels-success')),
                const Text('Das manuelle Speichern ist kein QME2-Store; WyrmTone hat nichts gespeichert.'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
