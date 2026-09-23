import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../controllers/usb_controller.dart';
import '../models/guitar_profile.dart';
import '../models/recommendation.dart';
import '../presets/device_catalog.dart';
import '../presets/matribox_chain_slot.dart';
import '../presets/matribox_hardware_evidence.dart';
import '../presets/matribox_raw_backup_service.dart';
import '../presets/matribox_target_preset.dart';
import '../presets/matribox_tone_transfer_pipeline.dart';
import '../presets/matribox_tone_transfer_plan.dart';
import '../presets/matribox_tone_transfer_session.dart';
import '../presets/matribox_transfer_slots.dart';
import '../presets/tone_intent.dart';
import '../ui/transfer_pulse_animation.dart';
import '../ui/wyrm_design.dart';
import 'matribox_channel_clients.dart';
import 'matribox_raw_backup_panel.dart' show defaultMatriboxRawBackupDirectory;
import 'preset_workspace_page.dart' show loadDevicePresetCatalog;

/// What real, in-flight step is currently running -- a rendering hint only,
/// never itself a source of truth for the transfer's safety state.
enum _Activity { idle, preparing, sending, verifying }

const _preparingSubtexts = [
  'Speicherplatz wird vorbereitet …',
  'Sound wird angepasst …',
  'Fast fertig …',
];

const _friendlySlotName = {
  MatriboxChainSlot.fx1: 'Effekt 1',
  MatriboxChainSlot.fx2: 'Effekt 2',
  MatriboxChainSlot.amp: 'Amp',
  MatriboxChainSlot.nr: 'Noise Gate',
  MatriboxChainSlot.cab: 'Cab',
  MatriboxChainSlot.eq: 'EQ',
  MatriboxChainSlot.mod: 'Modulation',
  MatriboxChainSlot.dly: 'Delay',
  MatriboxChainSlot.rvb: 'Reverb',
};

class _ReadChannel implements MatriboxUserSlotReadChannel {
  const _ReadChannel();
  @override
  Future<Map<Object?, Object?>> readMatriboxUserP01() =>
      const MethodChannelPresetReadChannel().readMatriboxUserP01();
  @override
  Future<Map<Object?, Object?>> readMatriboxUserSlot(int presetNumber) =>
      const MethodChannelPresetReadChannel().readMatriboxUserSlot(presetNumber);
}

String _origin(ToneOrigin origin) => origin.label;

/// Product path "Sound auf die Matribox übertragen" for ONE chosen User slot P11..P99 (P01..P10 are
/// protected, see [MatriboxSlotPolicy]), presented as ONE tap. The page is bound to [targetSlot] for
/// its whole life; a different slot is a different page, a different store and a new preparation:
///
/// "An Matribox senden" runs READ -> BACKUP -> HASH -> TARGET -> DIFF -> EVIDENCE -> PLAN
/// automatically, then asks for a single understandable confirmation before the actual
/// LIVE WRITE. After that: a physical check on the device, MANUAL DEVICE SAVE (done by the
/// user; the checkpoint button sends nothing), an automatic fresh READBACK, then VERIFIED.
///
/// The read only sees the SAVED preset, so nothing is verified before the manual save.
/// WyrmTone sends no Store and offers no Restore. Every safety gate (fresh read, verified
/// backup, hash binding, evidence-gated plan, whole-plan native preflight, zero-MIDI manual
/// save, fresh readback) still runs on every single tap -- only the technical steps in
/// between are no longer separate buttons or dialogs.
class ToneTransferPage extends StatefulWidget {
  const ToneTransferPage({
    required this.recommendation,
    required this.targetSlot,
    this.transferChannel = matriboxToneTransferEnabled
        ? const MethodChannelToneTransferChannel()
        : const UnavailableToneTransferChannel(),
    this.backupDirectory = defaultMatriboxRawBackupDirectory,
    this.readChannel = const _ReadChannel(),
    this.nameCatalogLoader = loadDevicePresetCatalog,
    this.usbController,
    super.key,
  });

  final ToneTransferRecommendation recommendation;

  /// The chosen User preset number. Deliberately nullable and without a default: a missing or
  /// protected slot blocks the page before anything is read or sent.
  final int? targetSlot;
  final MatriboxToneTransferChannel transferChannel;
  final Future<Directory> Function() backupDirectory;
  final MatriboxUserSlotReadChannel readChannel;
  final Future<DevicePresetCatalog> Function() nameCatalogLoader;

  /// When given, an open session goes STALE the moment this app-wide connection state leaves
  /// `connected` -- not only the next time this page happens to load. Optional so every existing
  /// caller/test keeps working unchanged; the page-load check in [_loadRecord] still runs either way.
  final UsbController? usbController;

  @override
  State<ToneTransferPage> createState() => _ToneTransferPageState();
}

class _ToneTransferPageState extends State<ToneTransferPage> {
  bool _busy = false;
  PreparedToneTransfer? _prepared;
  ToneTransferRunResult? _run;
  MatriboxToneTransferRecord? _record;
  ToneReadbackResult? _readback;
  String? _message;

  /// A rendering hint only -- see [TransferPulseAnimation]. Never read by any of the transfer
  /// logic above; only ever written alongside the real `_busy` transitions below.
  _Activity _activity = _Activity.idle;

  /// Guards the whole "An Matribox senden" / "Ich habe gespeichert" flows against a rapid
  /// double tap: set synchronously as the very first statement of each handler, before any
  /// `await`, so a second tap in the same frame is a no-op instead of a second prepare/write.
  bool _actionInFlight = false;

  int _preparingSubtextIndex = 0;
  Timer? _preparingSubtextTimer;

  TransferVisualPhase get _visualPhase {
    switch (_activity) {
      case _Activity.preparing:
        return TransferVisualPhase.preparing;
      case _Activity.sending:
        return TransferVisualPhase.sending;
      case _Activity.verifying:
        return TransferVisualPhase.verifying;
      case _Activity.idle:
        break;
    }
    final record = _record;
    final state = record?.state;
    if (state == ToneTransferRecordState.verified) return TransferVisualPhase.success;
    if (state == ToneTransferRecordState.failed || state == ToneTransferRecordState.stale) return TransferVisualPhase.failed;
    if (state == ToneTransferRecordState.liveWriteComplete && record!.operations.any((o) => o.status != 'SENT')) {
      return TransferVisualPhase.failed; // stopped mid-run: not everything landed, nothing continues automatically
    }
    if (state == ToneTransferRecordState.liveWriteComplete ||
        state == ToneTransferRecordState.awaitingManualSave ||
        state == ToneTransferRecordState.verifying) {
      return TransferVisualPhase.awaitingSave;
    }
    if (_message != null) return TransferVisualPhase.failed;
    return TransferVisualPhase.idle;
  }

  @override
  void initState() {
    super.initState();
    _loadRecord();
    widget.usbController?.addListener(_onConnectionChanged);
  }

  /// A different slot (or sound) after a preparation invalidates everything prepared for the old
  /// one: a plan read and diffed against P11 is never executed as P12.
  @override
  void didUpdateWidget(ToneTransferPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.usbController != widget.usbController) {
      oldWidget.usbController?.removeListener(_onConnectionChanged);
      widget.usbController?.addListener(_onConnectionChanged);
    }
    if (oldWidget.targetSlot != widget.targetSlot || oldWidget.recommendation != widget.recommendation) {
      setState(() {
        _prepared = null;
        _run = null;
        _readback = null;
        _record = null;
        _message = null;
      });
      _loadRecord();
    }
  }

  /// The page's slot, only when it may be written (P11..P99). Null otherwise -- never a default.
  MatriboxUserSlot? get _slot {
    final slot = MatriboxUserSlot.tryPreset(widget.targetSlot);
    return slot != null && slot.isProductWritable ? slot : null;
  }

  String get _slotLabel => MatriboxUserSlot.tryPreset(widget.targetSlot)?.label ?? '—';

  @override
  void dispose() {
    widget.usbController?.removeListener(_onConnectionChanged);
    _preparingSubtextTimer?.cancel();
    super.dispose();
  }

  /// Reacts the instant the app's own connection state says the Matribox is no longer connected,
  /// instead of waiting for this page to be reloaded. Only ever moves a session TOWARDS stale/
  /// unresolved, never invents a save or a verification.
  bool _markingStale = false;

  void _onConnectionChanged() {
    final usb = widget.usbController;
    final record = _record;
    if (usb == null || record == null || _markingStale) return;
    if (usb.connectionState == DeviceConnectionState.connected) return;
    final open = record.state == ToneTransferRecordState.liveWriteComplete ||
        record.state == ToneTransferRecordState.awaitingManualSave ||
        record.state == ToneTransferRecordState.verifying;
    if (!open) return;
    _markingStale = true;
    unawaited(_markStaleNow(record).whenComplete(() => _markingStale = false));
  }

  Future<void> _markStaleNow(MatriboxToneTransferRecord record) async {
    final store = await _storeFor(record.targetSlot);
    if (store == null) return;
    final updated = await MatriboxToneTransferCheckpoint.markStaleOnDisconnect(record, store);
    if (mounted) setState(() => _record = updated);
  }

  /// The persisted session of exactly [presetNumber] (one file per slot); null for any slot that is
  /// not product-writable, so nothing is ever stored or loaded for P01..P10.
  Future<MatriboxToneTransferStore?> _storeFor(int? presetNumber) async {
    final slot = MatriboxUserSlot.tryPreset(presetNumber);
    if (slot == null || !slot.isProductWritable) return null;
    return MatriboxToneTransferStore(
      File('${(await widget.backupDirectory()).path}/${toneTransferStateFileName(slot)}'),
      slot: slot,
    );
  }

  /// Loads the stored workflow state and never assumes the live values still
  /// exist after a reconnect / power cycle.
  ///
  /// ROOT CAUSE of "first transfer works, the next one looks wrong": the persisted session file
  /// (`tone_transfer.state`) lives at ONE fixed path shared by every sound -- it carries no
  /// identity of WHICH sound it belongs to. Opening this page for a brand new sound therefore used
  /// to load the PREVIOUS sound's finished record (e.g. still VERIFIED) and show it immediately,
  /// even though nothing had happened yet for the new sound. [_belongsToCurrentSound] closes that
  /// gap: a stored record is only ever shown when its [MatriboxToneTransferRecord.target] matches
  /// this page's own [ToneTransferRecommendation.target]. A record for a different sound is treated
  /// as if nothing were stored -- it is not deleted (a later real save for the new sound overwrites
  /// the file anyway), just never surfaced here.
  ///
  /// The same holds per slot: the store is per slot and a record is only shown when it is bound to
  /// exactly this page's [ToneTransferPage.targetSlot] -- a VERIFIED P11 never appears for P12.
  Future<void> _loadRecord() async {
    final requestedSlot = widget.targetSlot;
    final store = await _storeFor(requestedSlot);
    var record = await store?.load(library: widget.recommendation.library);
    if (record != null && (!_belongsToCurrentSound(record) || record.targetSlot != requestedSlot)) record = null;
    if (record != null) {
      String? token;
      try {
        token = await widget.transferChannel.connectionToken();
      } catch (_) {}
      record = await MatriboxToneTransferCheckpoint.markStaleIfReconnected(record, token, store!);
    }
    // The slot may have changed while this was loading: never show another slot's record.
    if (mounted && widget.targetSlot == requestedSlot) setState(() => _record = record);
  }

  bool _belongsToCurrentSound(MatriboxToneTransferRecord record) =>
      jsonEncode(record.target.toJson()) == jsonEncode(widget.recommendation.target.toJson());

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

  Future<MatriboxRawBackupService> _backupService() async => MatriboxRawBackupService(
    channel: widget.readChannel,
    backupDirectory: await widget.backupDirectory(),
  );

  void _startPreparingSubtext() {
    _preparingSubtextIndex = 0;
    _preparingSubtextTimer?.cancel();
    _preparingSubtextTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted || _activity != _Activity.preparing) return;
      setState(() => _preparingSubtextIndex = (_preparingSubtextIndex + 1) % _preparingSubtexts.length);
    });
  }

  void _stopPreparingSubtext() {
    _preparingSubtextTimer?.cancel();
    _preparingSubtextTimer = null;
  }

  /// The ONE user-facing action: "An Matribox senden". Internally runs the whole prepare
  /// pipeline (connection check, slot check, fresh read, backup, hash bind, diff, evidence/
  /// preflight) silently, then -- only if there is something to send and nothing blocks it --
  /// asks for exactly one understandable confirmation before the actual live write. Nothing
  /// safety-relevant is skipped; it is just no longer a separate visible step.
  Future<void> _beginTransfer() async {
    if (_actionInFlight || _busy) return;
    // No slot, a protected slot or an invalid one: refused here, before any read or send.
    final slotRejection = MatriboxSlotPolicy.writeRejection(widget.targetSlot);
    if (slotRejection != null) {
      setState(() => _message = MatriboxTransferSlots.blockedExplanation(widget.targetSlot) ?? slotRejection);
      return;
    }
    final slot = _slot!;
    _actionInFlight = true;
    setState(() {
      _busy = true;
      _activity = _Activity.preparing;
      _prepared = null;
      _run = null;
      _readback = null;
      _message = null;
    });
    _startPreparingSubtext();
    try {
      DevicePresetCatalog? catalog;
      try {
        catalog = await widget.nameCatalogLoader();
      } catch (_) {
        // Only used to label unknown current models; the plan works without it.
      }
      final PreparedToneTransfer prepared;
      try {
        prepared = await MatriboxToneTransferSession(
          backupService: await _backupService(),
          // The productive evidence: exactly the real, CERTIFIED operations.
          ledger: MatriboxHardwareLedger.product(),
          channel: widget.transferChannel,
          nameCatalog: catalog,
          library: widget.recommendation.library,
        ).prepare(widget.recommendation.target, targetSlot: slot.presetNumber);
      } catch (error) {
        if (mounted) {
          setState(() {
            _message = 'Der aktuelle Speicherplatz konnte nicht sicher vorbereitet werden. Es wurde nichts übertragen.';
          });
        }
        return;
      }
      if (!mounted) return;
      if (widget.targetSlot != slot.presetNumber) return; // slot changed while reading: discard
      setState(() => _prepared = prepared);

      final plan = prepared.plan;
      if (plan != null && plan.overall == ToneTransferOverall.nothingToDo) {
        setState(() {
          _prepared = null;
          _message = 'Dieser Sound ist bereits auf ${slot.label} gespeichert.';
        });
        return;
      }
      if (!_canSend(prepared)) {
        setState(() {
          _message = prepared.blockedReason ?? _friendlyBlockedMessage(plan);
        });
        return;
      }

      setState(() {
        _busy = false;
        _activity = _Activity.idle;
      });
      _stopPreparingSubtext();

      final confirmed = await _confirm(
        title: '${widget.recommendation.recipe.song} auf ${slot.label} übertragen?',
        body: '${widget.recommendation.recipe.song} wird auf ${slot.label} übertragen.\n'
            'Der bisherige Sound auf ${slot.label} wird ersetzt. '
            'Die Matribox wechselt dafür auf ${slot.label}.',
        actionLabel: 'Jetzt übertragen',
        actionKey: const Key('tt-send-confirm'),
      );
      if (!mounted) return;
      if (!confirmed) {
        // Nothing was written; clear the prepared plan so "An Matribox senden" reappears for a
        // fresh attempt instead of leaving the user on a dead end with no visible action.
        setState(() => _prepared = null);
        return;
      }
      final ready = _prepared;
      // The prepared plan must still belong to exactly this page's slot; otherwise it is stale.
      if (ready == null || ready.targetSlot != widget.targetSlot || ready.targetSlot != slot.presetNumber) {
        setState(() => _prepared = null);
        return;
      }
      final store = await _storeFor(slot.presetNumber);
      if (store == null || !mounted) return;

      setState(() {
        _busy = true;
        _activity = _Activity.sending;
        _run = null;
      });
      final result = await MatriboxToneTransferExecutor(
        channel: widget.transferChannel,
        store: store,
      ).execute(ready);
      await _loadRecord();
      if (!mounted) return;
      setState(() {
        _run = result;
        _prepared = null;
        _message = result.isSuccess ? null : result.error;
      });
    } finally {
      _stopPreparingSubtext();
      if (mounted) setState(() { _busy = false; _activity = _Activity.idle; });
      _actionInFlight = false;
    }
  }

  String _friendlyBlockedMessage(MatriboxToneTransferPlan? plan) {
    if (plan == null) return 'Der Sound konnte nicht vorbereitet werden.';
    if (plan.summary.incomplete > 0) {
      return 'Ein Effekt konnte auf der Matribox nicht eindeutig zugeordnet werden und bleibt unverändert.';
    }
    return 'Senden gerade nicht möglich: ${plan.blockers.join(' ')}';
  }

  /// `plan.sendable` (== `overall == ready`) is already the authoritative safety gate: it hard-blocks
  /// on unsupported/unknown-current/evidence-blocked entries and on an INCOMPLETE **AMP** block (the
  /// sound cannot work at all without it), but deliberately does NOT block on any other incomplete
  /// block -- per the product rule that a block WyrmTone could not map stays exactly as it is on the
  /// device and does not stop an otherwise-safe transfer (see [MatriboxToneTransferPlan.build]'s
  /// `criticalIncompleteSlots`). Do not re-add a stricter `summary.incomplete == 0` check here: that
  /// would silently re-block every non-AMP incomplete block and leave the user on a dead end with no
  /// visible retry action once one is detected (confirmed on real hardware).
  bool _canSend(PreparedToneTransfer? prepared) {
    final plan = prepared?.plan;
    if (plan == null || !prepared!.hasVerifiedBackup) return false;
    if (_slot == null || prepared.targetSlot != widget.targetSlot || plan.presetNumber != widget.targetSlot) return false;
    return plan.sendable && widget.transferChannel.available;
  }

  /// "Ich habe am Gerät gespeichert": sends NOTHING itself, only advances the workflow, then
  /// immediately (no extra confirmation -- the tap itself IS the confirmation) runs a fresh
  /// readback to verify what was actually saved.
  Future<void> _confirmManualSave() async {
    if (_actionInFlight || _busy) return;
    final record = _record;
    if (record == null) return;
    _actionInFlight = true;
    try {
      final store = await _storeFor(record.targetSlot);
      if (store == null) return;
      final updated = await MatriboxToneTransferCheckpoint.confirmManualSave(record, store);
      if (mounted) setState(() => _record = updated);
      await _runReadback(updated);
    } finally {
      _actionInFlight = false;
    }
  }

  /// Reads back the slot the RECORD is bound to (never the page's current selection or P01).
  Future<void> _runReadback(MatriboxToneTransferRecord record) async {
    final store = await _storeFor(record.targetSlot);
    if (store == null || !mounted) return;
    setState(() {
      _busy = true;
      _activity = _Activity.verifying;
      _readback = null;
    });
    try {
      final result = await MatriboxToneTransferReadback.run(
        record: record,
        backupService: await _backupService(),
        store: store,
      );
      await _loadRecord();
      if (mounted) setState(() => _readback = result);
    } finally {
      if (mounted) setState(() { _busy = false; _activity = _Activity.idle; });
    }
  }

  /// The manual retry after STALE / FAILED: still an explicit confirmation, since here the app
  /// is asking permission to re-read without the user having just pressed "Ich habe gespeichert".
  Future<void> _retryReadback() async {
    if (_actionInFlight || _busy) return;
    final record = _record;
    if (record == null) return;
    _actionInFlight = true;
    try {
      final accepted = await _confirm(
        title: 'Gespeicherten Sound prüfen?',
        body: 'Liest ${MatriboxUserSlot.tryPreset(record.targetSlot)?.label ?? '—'} neu vom Gerät und vergleicht den gespeicherten Stand mit dem Ziel. '
            'Es wird nichts geschrieben.',
        actionLabel: 'Gespeicherten Sound prüfen',
        actionKey: const Key('tt-readback-confirm'),
      );
      if (!accepted || !mounted) return;
      await _runReadback(record);
    } finally {
      _actionInFlight = false;
    }
  }

  /// "Neuen Sound senden": ends this UI session only -- the device connection, any earlier
  /// backup file and the persisted record for THIS sound are left alone (a real new transfer
  /// for a different sound never reads this page's in-memory fields again after this call).
  void _restart() => setState(() {
    _record = null;
    _prepared = null;
    _run = null;
    _readback = null;
    _message = null;
    _activity = _Activity.idle;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rec = widget.recommendation;
    final prepared = _prepared;
    final plan = prepared?.plan;
    final record = _record;
    final state = record?.state;
    final active = state == ToneTransferRecordState.liveWriteComplete ||
        state == ToneTransferRecordState.awaitingManualSave ||
        state == ToneTransferRecordState.verifying;
    // The button stays available whenever there is nothing in flight and no plan is currently
    // sendable-and-pending-confirmation -- including a blocked plan, so a blocked attempt (e.g.
    // missing evidence, no transport) can be retried without leaving the page.
    final showPrimaryAction = record == null && !active && (plan == null || plan.overall != ToneTransferOverall.ready);

    return WyrmScaffold(
      title: 'Sound übertragen',
      background: true,
      backgroundIntensity: WyrmBackgroundIntensity.dim,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${rec.recipe.song} — ${rec.recipe.artist}',
            key: const Key('tt-title'),
            style: theme.textTheme.titleLarge,
          ),
          Text('Gitarre: ${rec.recipe.guitarName}'),
          Text('Stimmung: ${rec.draft.tuning.label}'),
          Text(
            _slot == null ? 'Ziel: Matribox 1 · kein Speicherplatz gewählt' : 'Ziel: Matribox 1 · Preset ${_slot!.label}',
            key: const Key('tt-target-slot'),
          ),
          const SizedBox(height: 12),
          WyrmCard(
            key: const Key('tt-hero'),
            accent: true,
            child: TransferPulseAnimation(phase: _visualPhase, presetLabel: _slotLabel),
          ),
          const SizedBox(height: 12),
          if (_slot == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                MatriboxTransferSlots.blockedExplanation(widget.targetSlot) ?? MatriboxTransferSlots.explanation,
                key: const Key('tt-slot-blocked'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (record != null) _phaseCard(context, record),
          if (showPrimaryAction && widget.usbController != null && widget.usbController!.connectionState != DeviceConnectionState.connected)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Matribox anschließen, um fortzufahren.', key: const Key('tt-connect-hint'), style: theme.textTheme.bodyMedium),
            ),
          if (_activity == _Activity.preparing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: WyrmCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Text('Sound wird vorbereitet …', style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(_preparingSubtexts[_preparingSubtextIndex], key: const Key('tt-preparing-subtext'), style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          if (showPrimaryAction && _activity != _Activity.preparing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.icon(
                key: const Key('tt-send'),
                onPressed: _busy || _slot == null ? null : _beginTransfer,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('An Matribox senden'),
              ),
            ),
          _changeSummary(context, plan),
          if (_message != null && _run == null && _activity != _Activity.preparing)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_message!, key: const Key('tt-message'), style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (_run != null) _runCard(context, _run!),
          if (_readback != null) _readbackCard(context, _readback!),
          const SizedBox(height: 16),
          if (prepared != null) _technicalDetails(context, prepared),
        ],
      ),
    );
  }

  /// The persisted workflow step: LIVE WRITE -> MANUAL SAVE -> VERIFY.
  Widget _phaseCard(BuildContext context, MatriboxToneTransferRecord record) {
    final theme = Theme.of(context);
    final error = TextStyle(color: theme.colorScheme.error);
    Widget card(String key, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        key: Key(key),
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ),
    );
    switch (record.state) {
      case ToneTransferRecordState.liveWriteComplete:
        final incomplete = record.operations.any((o) => o.status != 'SENT');
        return card('tt-phase-live', [
          if (incomplete) ...[
            Text('⚠ Übertragung gestoppt', style: theme.textTheme.titleMedium),
            Text('Nicht alle Änderungen wurden gesendet; es wird nicht automatisch fortgesetzt.', style: error),
          ] else ...[
            const Text('Teste deinen Sound kurz.'),
            Text(
              'Wenn alles passt, speichere ihn jetzt direkt an der Matribox. '
              'Achte darauf, dass am Gerät ${MatriboxUserSlot.tryPreset(record.targetSlot)?.label ?? '—'} angezeigt wird.',
              key: const Key('tt-save-slot-hint'),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('tt-manual-save-done'),
            onPressed: _busy ? null : _confirmManualSave,
            child: const Text('Ich habe gespeichert'),
          ),
        ]);
      case ToneTransferRecordState.awaitingManualSave:
      case ToneTransferRecordState.verifying:
        // The pulse animation above already carries the "Gespeicherter Sound wird geprüft …"
        // status; this card only ever needs to add the manual-retry affordance.
        return card('tt-phase-awaiting', [
          if (_busy)
            const LinearProgressIndicator()
          else
            FilledButton.icon(
              key: const Key('tt-readback'),
              onPressed: _retryReadback,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Gespeicherten Sound prüfen'),
            ),
        ]);
      case ToneTransferRecordState.stale:
        return card('tt-phase-stale', [
          Text('⚠ Verbindung wurde getrennt oder das Gerät neu gestartet', style: theme.textTheme.titleMedium),
          Text(
            'Ungespeicherte Live-Änderungen können verloren sein. Es wird nichts angenommen: '
            'ein frischer Read entscheidet, ob der gespeicherte Stand dem Ziel entspricht.',
            style: error,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('tt-readback'),
            onPressed: _busy ? null : _retryReadback,
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut lesen'),
          ),
        ]);
      case ToneTransferRecordState.failed:
        return card('tt-phase-failed', [
          Text('Transfer nicht verifiziert', style: theme.textTheme.titleMedium),
          Text('Letztes Ergebnis: ${record.readbackOutcome ?? 'unbekannt'}. Es wird nicht automatisch erneut geschrieben.', style: error),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('tt-readback'),
            onPressed: _busy ? null : _retryReadback,
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut lesen'),
          ),
        ]);
      case ToneTransferRecordState.verified:
        // The pulse animation above already says "Preset erfolgreich gespeichert"; this card
        // names the sound and where it landed.
        return card('tt-phase-verified', [
          const Icon(Icons.check_circle, color: WyrmTokens.success, size: 32),
          const SizedBox(height: 8),
          Text(
            '${widget.recommendation.recipe.song} · Matribox 1 · ${MatriboxUserSlot.tryPreset(record.targetSlot)?.label ?? '—'}',
            key: const Key('tt-success'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(key: const Key('tt-done'), onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig')),
              TextButton(key: const Key('tt-new-sound'), onPressed: _restart, child: const Text('Neuen Sound senden')),
            ],
          ),
        ]);
    }
  }

  /// Which blocks are touched -- from the real device diff once one exists (after a prepare),
  /// otherwise from the offline recommendation itself, so the summary is visible immediately,
  /// before the user has sent anything.
  List<MatriboxChainSlot> _changedSlots(MatriboxToneTransferPlan? plan) {
    final target = widget.recommendation.target;
    return [
      for (final slot in MatriboxChainSlot.values)
        if (plan != null
            ? plan.entries.any((e) => e.slot == slot && e.sendable && e.isChange)
            : target[slot].hasAnyTarget && target[slot].effectiveState != RecipeBlockState.incomplete)
          slot,
    ];
  }

  int _incompleteCount(MatriboxToneTransferPlan? plan) {
    if (plan != null) return plan.summary.incomplete;
    final target = widget.recommendation.target;
    return MatriboxChainSlot.values.where((s) => target[s].effectiveState == RecipeBlockState.incomplete).length;
  }

  bool _hasApproximation(MatriboxToneTransferPlan? plan) {
    if (plan != null) return plan.summary.unsupported > 0 || plan.summary.incomplete > 0;
    final target = widget.recommendation.target;
    return MatriboxChainSlot.values.any((s) {
      final quality = target[s].report?.quality;
      return quality == ApproximationQuality.goodApproximation || quality == ApproximationQuality.limitedApproximation;
    });
  }

  /// A compact, human-readable summary of what changes -- block names only, no raw
  /// MODEL/BLOCK/parameter/origin vocabulary. The full per-entry breakdown is one tap away.
  Widget _changeSummary(BuildContext context, MatriboxToneTransferPlan? plan) {
    final theme = Theme.of(context);
    final changed = _changedSlots(plan);
    final incomplete = _incompleteCount(plan);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            changed.isEmpty
                ? 'WyrmTone ändert an diesem Preset nichts weiter.'
                : 'WyrmTone passt an: ${changed.map((s) => _friendlySlotName[s] ?? s.label).join(', ')}.',
            key: const Key('tt-change-summary'),
            style: theme.textTheme.bodyMedium,
          ),
          if (incomplete > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Ein Effekt konnte auf der Matribox nicht eindeutig zugeordnet werden und bleibt unverändert.',
                key: const Key('tt-incomplete-note'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (_hasApproximation(plan))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Der Sound kann größtenteils übertragen werden. Einige Details werden angenähert oder bleiben unverändert.',
                key: const Key('tt-partial-note'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ExpansionTile(
            key: const Key('tt-change-details'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Änderungen anzeigen'),
            children: [for (final slot in MatriboxChainSlot.values) ..._slotDetail(context, slot, plan)],
          ),
        ],
      ),
    );
  }

  /// Friendly per-slot lines: value transitions only, no provenance enum names
  /// (SONG_PROFILE/TUNING_CORRECTION/...) and no internal eligibility codes.
  List<Widget> _slotDetail(BuildContext context, MatriboxChainSlot slot, MatriboxToneTransferPlan? plan) {
    final lines = plan != null ? _friendlyPlanLines(slot, plan) : _friendlyTargetLines(slot);
    if (lines.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(_friendlySlotName[slot] ?? slot.label, style: Theme.of(context).textTheme.titleSmall),
      ),
      for (final line in lines) Text(line),
    ];
  }

  List<String> _friendlyPlanLines(MatriboxChainSlot slot, MatriboxToneTransferPlan plan) => [
    for (final e in plan.entries.where((e) => e.slot == slot && e.sendable && e.isChange)) '${e.subject}: ${e.current} → ${e.target}',
  ];

  List<String> _friendlyTargetLines(MatriboxChainSlot slot) {
    final block = widget.recommendation.target[slot];
    if (block.effectiveState == RecipeBlockState.incomplete) return const ['Unvollständig: bleibt unverändert'];
    return [
      if (block.enabled.specified) 'Status → ${block.enabled.value! ? 'Ein' : 'Aus'}',
      if (block.model.specified) 'Modell → ${block.model.value!.name}',
      for (final e in block.parameters.entries)
        if (e.value.specified) '${e.key} → ${e.value.value!.toStringAsFixed(0)}',
    ];
  }

  String _entryText(ToneTransferEntry e) {
    final status = switch (e.eligibility) {
      ToneSendEligibility.blockedByEvidence => '⚠ gesperrt: ${e.blockReason}',
      ToneSendEligibility.unsupported => '✗ nicht unterstützt: ${e.blockReason}',
      ToneSendEligibility.unknownCurrent => '? unbekannt: ${e.blockReason}',
      ToneSendEligibility.incompleteTarget => '◌ bleibt unverändert',
      ToneSendEligibility.eligible => '→ wird geändert (${_origin(e.origin)})',
      ToneSendEligibility.notNeeded => e.specified ? '= unverändert' : '— nicht festgelegt',
    };
    return '${e.subject}: ${e.current} → ${e.target}  $status';
  }

  /// Everything internal (backup path/hash, plan fingerprint, raw origins, evidence
  /// vocabulary, catalog codes) lives here, collapsed by default. A normal user never needs
  /// to open it; nothing here is deleted or weakened, only moved out of the primary flow.
  Widget _technicalDetails(BuildContext context, PreparedToneTransfer prepared) {
    final plan = prepared.plan;
    final read = prepared.read;
    final ok = prepared.hasVerifiedBackup;
    return ExpansionTile(
      key: const Key('tt-technical'),
      title: const Text('Technische Details'),
      children: [
        if (plan != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                [for (final slot in MatriboxChainSlot.values) for (final e in plan.entries.where((e) => e.slot == slot)) _entryText(e)].join('\n'),
                key: const Key('tt-raw-diff'),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              [
                'Sicherung: ${ok ? '✓' : '✗'} Gerät gelesen ${ok ? '✓' : '✗'} gesichert ${ok ? '✓' : '✗'} geprüft',
                if (ok && read?.backup?.sha256 != null) 'Backup-SHA-256: ${read!.backup!.sha256}',
                if (ok && read?.backup?.filePath != null) 'Backup-Datei: ${read!.backup!.filePath}',
                if (plan != null) 'Plan: ${plan.fingerprint}',
                if (plan != null) 'Belege: ${plan.ledgerSource}',
                if (plan != null)
                  'Modelle: ${plan.summary.modelsChanged} · Werte: ${plan.summary.parametersChanged} · '
                      'Blöcke: ${plan.summary.blocksEnabled + plan.summary.blocksDisabled} · '
                      'Unverändert: ${plan.summary.unchanged} · Unvollständig: ${plan.summary.incomplete} · '
                      'Nicht unterstützt: ${plan.summary.unsupported} · Gesperrt: ${plan.summary.blocked}',
                if (plan != null)
                  for (final e in plan.operations.where((e) => e.model != null && e.intended == ToneOperationKind.selectModel))
                    '${e.slot.label} ${e.model!.name} (${_origin(e.origin)}): Katalog-Code 0x${e.model!.code.toRadixString(16).padLeft(8, '0')}',
              ].join('\n'),
              key: const Key('tt-status'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _runCard(BuildContext context, ToneTransferRunResult run) {
    final theme = Theme.of(context);
    final touched = run.completed.isNotEmpty || run.failed.isNotEmpty;
    if (!touched) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'Es wurde nichts an die Matribox gesendet: ${run.error ?? run.outcome.name}',
          key: const Key('tt-run-nothing'),
          style: TextStyle(color: theme.colorScheme.error),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        'Prüfprotokoll: completed: ${run.completed.length} · failed: ${run.failed.length} · notSent: ${run.notSent.length}'
        '${run.error == null ? '' : '\n${run.error}'}',
        key: Key(run.isSuccess ? 'tt-live-complete' : 'tt-run-stopped'),
      ),
    );
  }

  Widget _readbackCard(BuildContext context, ToneReadbackResult r) {
    final theme = Theme.of(context);
    final code = switch (r.outcome) {
      ToneReadbackOutcome.certified => 'CERTIFIED',
      ToneReadbackOutcome.targetMismatch => 'TARGET_MISMATCH',
      ToneReadbackOutcome.unexpectedKnownChange => 'UNEXPECTED_KNOWN_CHANGE',
      ToneReadbackOutcome.unknownRawChange => 'UNKNOWN_RAW_CHANGE',
      ToneReadbackOutcome.readFailed => 'READ_FAILED',
      ToneReadbackOutcome.notAwaitingSave => 'NOT_AWAITING_SAVE',
    };
    final label = switch (r.outcome) {
      ToneReadbackOutcome.certified => 'Sound erfolgreich übertragen und gespeichert verifiziert.',
      ToneReadbackOutcome.targetMismatch => 'Der gespeicherte Sound stimmt noch nicht vollständig mit dem Ziel überein.',
      ToneReadbackOutcome.unexpectedKnownChange => 'Am Gerät wurde zusätzlich etwas anderes geändert',
      ToneReadbackOutcome.unknownRawChange => 'Beim Prüfen wurde eine unerwartete Änderung erkannt.',
      ToneReadbackOutcome.readFailed => 'Das Preset konnte nicht erneut gelesen werden.',
      ToneReadbackOutcome.notAwaitingSave => 'Speichern am Gerät noch nicht bestätigt',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        key: Key(r.isCertified ? 'tt-readback-certified' : 'tt-readback-failed'),
        color: r.isCertified ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.titleSmall),
              if (r.isCertified)
                Text(
                  'Das Speichern erfolgte manuell an der Matribox. Status: ${_record?.persistence ?? 'MANUAL_SAVE_PERSISTENCE_VERIFIED'}',
                  style: theme.textTheme.bodySmall,
                ),
              Text('Prüfergebnis: $code', style: theme.textTheme.bodySmall),
              if (r.detail != null) Text(r.detail!),
              for (final c in r.checks)
                Text('${c.matched ? '✓' : '✗'} ${c.slot.label} ${c.subject}: ${c.expected} (Gerät: ${c.actual})'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Convenience for callers: builds the recommendation from a draft and opens
/// the page for the explicitly chosen [targetSlot] (no default slot).
Future<void> openToneTransfer(BuildContext context, PresetDraft draft, {required int? targetSlot}) async {
  final catalog = await loadDevicePresetCatalog();
  final recommendation = MatriboxToneTransferPipeline.fromDraft(draft, catalog: catalog);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ToneTransferPage(recommendation: recommendation, targetSlot: targetSlot)),
  );
}
