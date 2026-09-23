/// Tone Transfer flow for ONE product-writable User slot (P11..P99, see
/// [MatriboxSlotPolicy]; P01..P10 are protected and never a target):
///
/// PREPARE (fresh read of THAT slot -> backup -> reload -> hash -> decode -> diff
/// -> evidence-gated plan) -> explicit confirmation (UI) -> EXECUTE (the
/// whole prepared plan goes to the native transport in ONE closed contract
/// call; the native side validates the WHOLE plan before the first send,
/// stops at the first failure, never retries, never stores) -> LIVE WRITE
/// COMPLETE -> physical check on the device -> MANUAL DEVICE SAVE (done by
/// the user; the checkpoint button sends nothing) -> fresh READBACK (target
/// vs saved device state + raw-change safety) -> VERIFIED.
///
/// The read only sees the SAVED preset, so a readback before the manual save
/// is never a product verification. No Store is ever sent by WyrmTone.
///
/// The target slot is fixed when the transfer is prepared and travels
/// unchanged through plan, native call, record, readback and verification:
/// requested == prepared == backup == written == verified slot, otherwise
/// nothing is sent or nothing is verified. There is no default slot.
///
/// Dart never passes bytes, algorithm ids or wire indices across the
/// transport: only slot names, catalog model/parameter names and values.
library;

import 'dart:convert';
import 'dart:io';

import 'device_catalog.dart';
import 'matribox_angels_product_plan.dart';
import 'matribox_chain_slot.dart';
import 'matribox_full_live_session.dart';
import 'matribox_full_live_verifier.dart';
import 'matribox_hardware_evidence.dart';
import 'matribox_model_library.dart';
import 'matribox_preset_layout.dart';
import 'matribox_raw_backup_service.dart';
import 'matribox_target_preset.dart';
import 'matribox_tone_transfer_plan.dart';
import 'matribox_transfer_catalog.dart';
import 'matribox_transfer_slots.dart';
import 'matribox_verified_p01_read.dart';
import 'tone_intent.dart' show RecipeBlockState;
import 'raw_preset_backup_format.dart';
import 'raw_preset_snapshot.dart';

// ---------------------------------------------------------------------------
// Transport
// ---------------------------------------------------------------------------

/// Result of the ONE native execute call (the whole plan).
class ToneTransferExecuteResult {
  const ToneTransferExecuteResult({
    required this.outcome,
    this.error,
    this.errorCode,
    this.completed = 0,
    this.failedIndex,
    this.statuses = const [],
    this.sessionToken,
    this.targetSlot,
    this.presetSelect,
  });

  /// SUCCESS, VALIDATION_REJECTED, DEVICE_NOT_CONNECTED, MIDI_NOT_AVAILABLE,
  /// SAFETY_REJECTED or SEND_FAILED (native names).
  final String outcome;
  final String? error, errorCode;
  final int completed;
  final int? failedIndex;

  /// SENT / FAILED / NOT_SENT per operation, in plan order.
  final List<String> statuses;

  /// Native connection generation at the time of the write.
  final String? sessionToken;

  /// The User slot the native side selected and wrote (echo of the validated plan).
  final int? targetSlot;

  /// SENT / FAILED / NOT_SENT of the preset select that precedes the first operation.
  final String? presetSelect;

  factory ToneTransferExecuteResult.fromNative(Map<Object?, Object?> raw) => ToneTransferExecuteResult(
    outcome: '${raw['outcome']}',
    error: raw['error'] as String?,
    errorCode: raw['errorCode'] as String?,
    completed: (raw['completed'] as num?)?.toInt() ?? 0,
    failedIndex: (raw['failedIndex'] as num?)?.toInt(),
    statuses: [
      for (final item in (raw['operations'] as List? ?? const []))
        if (item is Map) '${item['status']}',
    ],
    sessionToken: raw['sessionToken']?.toString(),
    targetSlot: (raw['targetSlot'] as num?)?.toInt(),
    presetSelect: raw['presetSelect'] as String?,
  );
}

/// The productive transport. [execute] takes ONLY the closed contract map
/// built by [MatriboxToneTransferPlan.toContractRequest].
abstract interface class MatriboxToneTransferChannel {
  /// False while no productive native transport is enabled.
  bool get available;
  Future<ToneTransferExecuteResult> execute(Map<String, Object?> request);

  /// Current native connection generation (changes on every reconnect).
  Future<String?> connectionToken();
}

class UnavailableToneTransferChannel implements MatriboxToneTransferChannel {
  const UnavailableToneTransferChannel();
  @override
  bool get available => false;
  @override
  Future<ToneTransferExecuteResult> execute(Map<String, Object?> request) async =>
      const ToneTransferExecuteResult(
        outcome: 'SAFETY_REJECTED',
        error: 'Kein produktiver Tone-Transfer-Transport verfügbar.',
      );
  @override
  Future<String?> connectionToken() async => null;
}

/// Hardware evidence from the Full Live record in [backupDirectory] (if any).
Future<MatriboxHardwareLedger> loadHardwareLedger(
  Directory backupDirectory, {
  MatriboxModelLibrary? library,
}) async {
  final record = await MatriboxFullLiveStore(
    File('${backupDirectory.path}/$matriboxFullLiveStateFileName'),
  ).load();
  var ledger = MatriboxHardwareLedger.fromFullLive(record);
  if (library != null) {
    final angels = await MatriboxFullLiveStore(
      File('${backupDirectory.path}/$matriboxAngelsStateFileName'),
    ).load();
    ledger = ledger.withCertification(AngelsProductPlan(library: library), angels);
  }
  return ledger;
}

/// One persisted session per target slot: a VERIFIED P11 record lives in a
/// different file than anything for P12 and can never be shown for it.
String toneTransferStateFileName(MatriboxUserSlot slot) => 'tone_transfer_${slot.label}.state';

// ---------------------------------------------------------------------------
// Prepare
// ---------------------------------------------------------------------------

class PreparedToneTransfer {
  const PreparedToneTransfer({
    required this.target,
    required this.targetSlot,
    this.read,
    this.plan,
    this.blockedReason,
  });

  final MatriboxTargetPreset target;

  /// The slot that was REQUESTED for this preparation (never defaulted).
  final int? targetSlot;
  final VerifiedPresetRead? read;
  final MatriboxToneTransferPlan? plan;
  final String? blockedReason;

  bool get hasVerifiedBackup => read?.isVerified == true;
  MatriboxPresetLayoutModel? get current => read?.layout;
}

class MatriboxToneTransferSession {
  const MatriboxToneTransferSession({
    required this.backupService,
    required this.ledger,
    required this.channel,
    this.nameCatalog,
    this.library,
  });

  final MatriboxRawBackupService backupService;
  final MatriboxHardwareLedger ledger;
  final MatriboxToneTransferChannel channel;
  final DevicePresetCatalog? nameCatalog;
  final MatriboxModelLibrary? library;

  /// Always performs a NEW read of exactly [targetSlot]; there is no cached
  /// state. A missing, protected (P01..P10), invalid or Factory slot is
  /// rejected BEFORE anything is read or sent.
  Future<PreparedToneTransfer> prepare(MatriboxTargetPreset target, {required int? targetSlot}) async {
    final rejection = MatriboxSlotPolicy.writeRejection(targetSlot);
    if (rejection != null) {
      return PreparedToneTransfer(target: target, targetSlot: targetSlot, blockedReason: rejection);
    }
    final slot = MatriboxUserSlot.preset(targetSlot!);
    final read = await readVerifiedUserSlot(backupService, slot);
    if (!read.isVerified) {
      return PreparedToneTransfer(
        target: target,
        targetSlot: targetSlot,
        read: read,
        blockedReason: read.blockedReason ?? 'Lesen von ${slot.label} fehlgeschlagen.',
      );
    }
    final plan = MatriboxToneTransferPlan.build(
      current: read.layout!,
      target: target,
      ledger: ledger,
      backupSha256: read.backup!.sha256,
      presetNumber: read.snapshot!.presetNumber,
      isUserBank: read.snapshot!.isUserBank,
      transportAvailable: channel.available,
      nameCatalog: nameCatalog,
      library: library,
    );
    return PreparedToneTransfer(target: target, targetSlot: targetSlot, read: read, plan: plan);
  }
}

// ---------------------------------------------------------------------------
// Record + store
// ---------------------------------------------------------------------------

/// Persisted workflow state. PREPARED lives only in memory.
/// - liveWriteComplete: sent, the user has not confirmed the manual save yet
/// - awaitingManualSave: the user confirmed the device save (no MIDI involved)
/// - verifying: a fresh saved-state readback is running
/// - verified: fresh saved-state readback matches the target
/// - failed: the readback did not verify (no automatic resend)
/// - stale: the device connection changed after the live write; live values
///   may be lost, nothing is assumed
enum ToneTransferRecordState { liveWriteComplete, awaitingManualSave, verifying, verified, failed, stale }

class ToneTransferOpRecord {
  const ToneTransferOpRecord({
    required this.slot,
    required this.kind,
    required this.subject,
    required this.status,
    this.wireIndex,
  });

  final MatriboxChainSlot slot;
  final ToneOperationKind kind;
  final String subject;

  /// SENT, FAILED or NOT_SENT.
  final String status;
  final int? wireIndex;

  Map<String, Object?> toJson() => {
    'slot': slot.label,
    'kind': kind.name,
    'subject': subject,
    'status': status,
    'wireIndex': wireIndex,
  };

  static ToneTransferOpRecord? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final slot = MatriboxChainSlot.values.where((s) => s.label == json['slot']).firstOrNull;
    final kind = ToneOperationKind.values.where((k) => k.name == json['kind']).firstOrNull;
    if (slot == null || kind == null || json['subject'] is! String || json['status'] is! String) {
      return null;
    }
    return ToneTransferOpRecord(
      slot: slot,
      kind: kind,
      subject: json['subject'] as String,
      status: json['status'] as String,
      wireIndex: json['wireIndex'] as int?,
    );
  }
}

class MatriboxToneTransferRecord {
  const MatriboxToneTransferRecord({
    required this.targetSlot,
    required this.planFingerprint,
    required this.beforeBackupPath,
    required this.beforeBackupSha256,
    required this.target,
    required this.operations,
    required this.sentAt,
    this.state = ToneTransferRecordState.liveWriteComplete,
    this.readbackOutcome,
    this.afterBackupSha256,
    this.persistence,
    this.sessionToken,
    this.writtenSlot,
  });

  /// The User slot (P11..P99) this transfer is bound to for its whole life:
  /// the readback reads THIS slot, never the page's current selection.
  final int targetSlot;

  /// The slot the native side reported as selected and written.
  final int? writtenSlot;

  final String planFingerprint;
  final String beforeBackupPath;
  final String beforeBackupSha256;
  final MatriboxTargetPreset target;
  final List<ToneTransferOpRecord> operations;
  final DateTime sentAt;
  final ToneTransferRecordState state;
  final String? readbackOutcome;
  final String? afterBackupSha256;

  /// `MANUAL_SAVE_PERSISTENCE_VERIFIED` or `PERSISTENCE_MISMATCH`. NEVER a
  /// QME2 store claim.
  final String? persistence;

  /// Native connection generation of the live write.
  final String? sessionToken;

  MatriboxToneTransferRecord copyWith({
    ToneTransferRecordState? state,
    String? readbackOutcome,
    String? afterBackupSha256,
    String? persistence,
  }) => MatriboxToneTransferRecord(
    targetSlot: targetSlot,
    writtenSlot: writtenSlot,
    planFingerprint: planFingerprint,
    beforeBackupPath: beforeBackupPath,
    beforeBackupSha256: beforeBackupSha256,
    target: target,
    operations: operations,
    sentAt: sentAt,
    state: state ?? this.state,
    readbackOutcome: readbackOutcome ?? this.readbackOutcome,
    afterBackupSha256: afterBackupSha256 ?? this.afterBackupSha256,
    persistence: persistence ?? this.persistence,
    sessionToken: sessionToken,
  );

  Map<String, Object?> toJson() => {
    'targetBank': 'USER',
    'targetSlot': targetSlot,
    'writtenSlot': writtenSlot,
    'planFingerprint': planFingerprint,
    'beforeBackupPath': beforeBackupPath,
    'beforeBackupSha256': beforeBackupSha256,
    'target': target.toJson(),
    'operations': [for (final o in operations) o.toJson()],
    'sentAt': sentAt.toUtc().toIso8601String(),
    'state': state.name,
    'readbackOutcome': readbackOutcome,
    'afterBackupSha256': afterBackupSha256,
    'persistence': persistence,
    'sessionToken': sessionToken,
  };

  static MatriboxToneTransferRecord? tryFromJson(Object? json, {MatriboxModelLibrary? library}) {
    if (json is! Map) return null;
    try {
      final sentAt = DateTime.tryParse('${json['sentAt']}');
      final state = _stateFromJson(json['state'], json['readbackOutcome']);
      final operations = [
        for (final o in (json['operations'] as List? ?? const [])) ToneTransferOpRecord.tryFromJson(o),
      ];
      // A record without a product-writable User slot (e.g. a legacy P01 record) is never loaded.
      final targetSlot = json['targetSlot'];
      if (json['targetBank'] != 'USER' || targetSlot is! int || !MatriboxSlotPolicy.isProductWritable(targetSlot)) {
        return null;
      }
      final writtenSlot = json['writtenSlot'];
      if (writtenSlot != null && writtenSlot is! int) return null;
      if (json['planFingerprint'] is! String ||
          json['beforeBackupPath'] is! String ||
          json['beforeBackupSha256'] is! String ||
          json['target'] is! Map ||
          sentAt == null ||
          state == null ||
          operations.any((o) => o == null)) {
        return null;
      }
      return MatriboxToneTransferRecord(
        targetSlot: targetSlot,
        writtenSlot: writtenSlot as int?,
        planFingerprint: json['planFingerprint'] as String,
        beforeBackupPath: json['beforeBackupPath'] as String,
        beforeBackupSha256: json['beforeBackupSha256'] as String,
        target: MatriboxTargetPreset.fromJson(json['target'] as Map, library: library),
        operations: operations.cast<ToneTransferOpRecord>(),
        sentAt: sentAt,
        state: state,
        readbackOutcome: json['readbackOutcome'] as String?,
        afterBackupSha256: json['afterBackupSha256'] as String?,
        persistence: json['persistence'] as String?,
        sessionToken: json['sessionToken']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Accepts the earlier state names (sent / readbackDone) of stored records.
ToneTransferRecordState? _stateFromJson(Object? name, Object? readbackOutcome) {
  if (name == 'sent') return ToneTransferRecordState.liveWriteComplete;
  if (name == 'readbackDone') {
    return readbackOutcome == 'certified' ? ToneTransferRecordState.verified : ToneTransferRecordState.failed;
  }
  return ToneTransferRecordState.values.where((s) => s.name == name).firstOrNull;
}

class MatriboxToneTransferStore {
  const MatriboxToneTransferStore(this.file, {this.slot});
  final File file;

  /// When set, only a record bound to exactly this slot is ever loaded.
  final MatriboxUserSlot? slot;

  Future<MatriboxToneTransferRecord?> load({MatriboxModelLibrary? library}) async {
    if (!await file.exists()) return null;
    try {
      final record = MatriboxToneTransferRecord.tryFromJson(jsonDecode(await file.readAsString()), library: library);
      if (record != null && slot != null && record.targetSlot != slot!.presetNumber) return null;
      return record;
    } on FormatException {
      return null;
    }
  }

  Future<void> save(MatriboxToneTransferRecord record) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(record.toJson()), flush: true);
  }
}

// ---------------------------------------------------------------------------
// Execute
// ---------------------------------------------------------------------------

enum ToneTransferRunOutcome {
  success,
  rejected,
  transportUnavailable,
  sendFailed,
}

class ToneTransferOpStatus {
  const ToneTransferOpStatus(this.entry, this.status);
  final ToneTransferEntry entry;

  /// SENT, FAILED or NOT_SENT.
  final String status;
}

class ToneTransferRunResult {
  const ToneTransferRunResult({
    required this.outcome,
    this.operations = const [],
    this.error,
    this.recordSaved = false,
  });

  final ToneTransferRunOutcome outcome;
  final List<ToneTransferOpStatus> operations;
  final String? error;
  final bool recordSaved;

  bool get isSuccess => outcome == ToneTransferRunOutcome.success;
  Iterable<ToneTransferOpStatus> get completed => operations.where((o) => o.status == 'SENT');
  Iterable<ToneTransferOpStatus> get failed => operations.where((o) => o.status == 'FAILED');
  Iterable<ToneTransferOpStatus> get notSent => operations.where((o) => o.status == 'NOT_SENT');
}

class MatriboxToneTransferExecutor {
  const MatriboxToneTransferExecutor({
    required this.channel,
    required this.store,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final MatriboxToneTransferChannel channel;
  final MatriboxToneTransferStore store;
  final DateTime Function() _clock;

  static bool orderIsValid(List<ToneTransferEntry> operations) {
    // Slots ascend, and inside a slot MODEL < PARAMETER < BLOCK.
    var lastSlot = -1;
    var lastRank = -1;
    for (final e in operations) {
      final rank = switch (e.intended) {
        ToneOperationKind.selectModel => 0,
        ToneOperationKind.setParameter => 1,
        _ => 2,
      };
      if (e.slot.index < lastSlot) return false;
      if (e.slot.index == lastSlot && rank < lastRank) return false;
      if (e.slot.index != lastSlot) lastRank = -1;
      lastSlot = e.slot.index;
      lastRank = rank;
    }
    return true;
  }

  ToneTransferRunResult _rejected(String reason) =>
      ToneTransferRunResult(outcome: ToneTransferRunOutcome.rejected, error: reason);

  /// Re-derives every precondition from the prepared plan (the UI's enabled
  /// button is never trusted), hands the WHOLE plan to the native transport
  /// in one call and records the audit. Nothing is recomputed, retried or
  /// rolled back; the native side validates every operation again.
  Future<ToneTransferRunResult> execute(PreparedToneTransfer prepared) async {
    final plan = prepared.plan;
    final read = prepared.read;
    if (plan == null || read == null || !read.isVerified) {
      return _rejected('Kein verifiziertes Backup / kein Plan.');
    }
    if (!plan.sendable) return _rejected('Plan ist nicht sendbar (${plan.overall.name}).');
    // requested == prepared == backup == plan slot, and that slot is product-writable.
    final requested = prepared.targetSlot;
    final slotRejection = MatriboxSlotPolicy.writeRejection(requested) ??
        MatriboxSlotPolicy.writeRejection(plan.presetNumber, isUserBank: plan.isUserBank) ??
        MatriboxSlotPolicy.writeRejection(read.snapshot!.presetNumber, isUserBank: read.snapshot!.isUserBank);
    if (slotRejection != null) return _rejected(slotRejection);
    if (plan.presetNumber != requested ||
        read.snapshot!.presetNumber != requested ||
        read.slot?.presetNumber != requested) {
      return _rejected('Plan, Sicherung und gewählter Speicherplatz gehören nicht zusammen.');
    }
    if (plan.backupSha256 == null || plan.backupSha256 != read.backup!.sha256) {
      return _rejected('Plan gehört nicht zum verifizierten Backup.');
    }
    final operations = plan.operations;
    if (operations.isEmpty || operations.any((e) => e.bytes == null)) {
      return _rejected('Plan enthält keine validierten Operationen.');
    }
    if (!orderIsValid(operations)) return _rejected('Operationsreihenfolge ungültig.');
    if (!channel.available) {
      return const ToneTransferRunResult(
        outcome: ToneTransferRunOutcome.transportUnavailable,
        error: 'Kein produktiver Tone-Transfer-Transport verfügbar.',
      );
    }

    ToneTransferExecuteResult native;
    try {
      native = await channel.execute(plan.toContractRequest());
    } catch (thrown) {
      // The channel itself failed: how far the native run got is UNKNOWN. The
      // live state of the device must not be assumed either way.
      native = ToneTransferExecuteResult(
        outcome: 'SEND_FAILED',
        error: '$thrown',
        statuses: List<String>.filled(operations.length, 'UNKNOWN'),
      );
    }
    final statuses = native.statuses.length == operations.length
        ? native.statuses
        : List<String>.filled(operations.length, 'NOT_SENT');
    // The native side must have selected and written exactly the prepared slot; anything else is
    // never a success (and the record below can then never be verified either).
    final slotConfirmed = native.targetSlot == plan.presetNumber;
    final outcome = switch (native.outcome) {
      'SUCCESS' when slotConfirmed && statuses.every((s) => s == 'SENT') => ToneTransferRunOutcome.success,
      'SEND_FAILED' => ToneTransferRunOutcome.sendFailed,
      _ => ToneTransferRunOutcome.rejected,
    };
    final error = native.error != null
        ? '${native.errorCode == null ? '' : '${native.errorCode}: '}${native.error}'
        : native.outcome == 'SUCCESS' && !slotConfirmed
        ? 'SLOT_MISMATCH: Gerät meldet Speicherplatz ${native.targetSlot} statt ${plan.presetNumber}.'
        : null;

    final attempted = statuses.any((s) => s != 'NOT_SENT');
    var saved = false;
    if (attempted) {
      try {
        await store.save(
          MatriboxToneTransferRecord(
            targetSlot: plan.presetNumber,
            writtenSlot: native.targetSlot,
            planFingerprint: plan.fingerprint,
            beforeBackupPath: read.backup!.filePath!,
            beforeBackupSha256: read.backup!.sha256!,
            target: prepared.target,
            operations: [
              for (var i = 0; i < operations.length; i++)
                ToneTransferOpRecord(
                  slot: operations[i].slot,
                  kind: operations[i].intended,
                  subject: operations[i].subject,
                  status: statuses[i],
                  wireIndex: operations[i].parameter?.wireIndex,
                ),
            ],
            sentAt: _clock(),
            sessionToken: native.sessionToken,
          ),
        );
        saved = true;
      } catch (_) {}
    }
    return ToneTransferRunResult(
      outcome: outcome,
      operations: [
        for (var i = 0; i < operations.length; i++) ToneTransferOpStatus(operations[i], statuses[i]),
      ],
      error: error,
      recordSaved: saved,
    );
  }
}

/// Workflow steps around the manual device save. None of them touches MIDI:
/// they take a store, not a transport.
abstract final class MatriboxToneTransferCheckpoint {
  /// "Ich habe am Gerät gespeichert": only records the workflow step. It does
  /// not claim anything was saved; only the readback can show that.
  static Future<MatriboxToneTransferRecord> confirmManualSave(
    MatriboxToneTransferRecord record,
    MatriboxToneTransferStore store,
  ) async {
    if (record.state != ToneTransferRecordState.liveWriteComplete && record.state != ToneTransferRecordState.stale) {
      return record;
    }
    final updated = record.copyWith(state: ToneTransferRecordState.awaitingManualSave);
    await store.save(updated);
    return updated;
  }

  /// The app's own connection state (Auto-Connect's central [DeviceConnectionState]) noticed the
  /// Matribox connection is gone RIGHT NOW while a live-write session was open. Unlike
  /// [markStaleIfReconnected] this needs no session-token round trip through the native side -- the
  /// disconnect is already known -- so the page can react the moment it happens instead of only on
  /// its next load. Never assumes anything is saved; a fresh read still decides.
  static Future<MatriboxToneTransferRecord> markStaleOnDisconnect(
    MatriboxToneTransferRecord record,
    MatriboxToneTransferStore store,
  ) async {
    final open = record.state == ToneTransferRecordState.liveWriteComplete ||
        record.state == ToneTransferRecordState.awaitingManualSave ||
        record.state == ToneTransferRecordState.verifying;
    if (!open) return record;
    final updated = record.copyWith(state: ToneTransferRecordState.stale);
    await store.save(updated);
    return updated;
  }

  /// The device connection changed after the live write (disconnect,
  /// power-off): the live values may be gone. Nothing is assumed; a fresh
  /// read decides.
  static Future<MatriboxToneTransferRecord> markStaleIfReconnected(
    MatriboxToneTransferRecord record,
    String? currentToken,
    MatriboxToneTransferStore store,
  ) async {
    final open = record.state == ToneTransferRecordState.liveWriteComplete ||
        record.state == ToneTransferRecordState.awaitingManualSave;
    if (!open || record.sessionToken == null || currentToken == null || currentToken == record.sessionToken) {
      return record;
    }
    final updated = record.copyWith(state: ToneTransferRecordState.stale);
    await store.save(updated);
    return updated;
  }
}

// ---------------------------------------------------------------------------
// Target-vs-device semantic verification
// ---------------------------------------------------------------------------

class ToneTargetCheck {
  const ToneTargetCheck({
    required this.slot,
    required this.subject,
    required this.expected,
    required this.actual,
    required this.matched,
  });
  final MatriboxChainSlot slot;
  final String subject, expected, actual;
  final bool matched;
}

abstract final class MatriboxToneTargetVerifier {
  static String _hex(int code) => '0x${code.toRadixString(16).padLeft(8, '0')}';
  static String _format(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// Compares every SPECIFIED target field with the device state.
  static List<ToneTargetCheck> compare(MatriboxTargetPreset target, MatriboxPresetLayoutModel device) {
    final checks = <ToneTargetCheck>[];
    for (final slot in MatriboxChainSlot.values) {
      final block = target[slot];
      // an incomplete block was never part of the transfer: the device keeps its own state there
      if (block.effectiveState == RecipeBlockState.incomplete) continue;
      final deviceModel = MatriboxTransferCatalog.byCode(slot, device.code(slot));
      final targetModel = block.model.value;
      if (targetModel != null) {
        checks.add(
          ToneTargetCheck(
            slot: slot,
            subject: 'MODEL',
            expected: targetModel.name,
            actual: deviceModel?.name ?? _hex(device.code(slot)),
            matched: targetModel.code == device.code(slot),
          ),
        );
      }
      final effective = targetModel ?? deviceModel;
      for (final entry in block.parameters.entries) {
        final wanted = entry.value.value;
        if (wanted == null) continue;
        final parameter = effective?.parameter(entry.key);
        if (parameter == null) {
          checks.add(
            ToneTargetCheck(
              slot: slot,
              subject: entry.key,
              expected: _format(wanted),
              actual: 'Modell unbekannt',
              matched: false,
            ),
          );
          continue;
        }
        final actual = device.parameter(slot, parameter.wireIndex);
        final tolerance = parameter.kind.name == 'decimal' ? 0.05 : 0.5;
        checks.add(
          ToneTargetCheck(
            slot: slot,
            subject: entry.key,
            expected: _format(wanted),
            actual: _format(actual),
            matched: (actual - wanted).abs() < tolerance,
          ),
        );
      }
      final wantedOn = block.enabled.value;
      if (wantedOn != null) {
        checks.add(
          ToneTargetCheck(
            slot: slot,
            subject: 'BLOCK',
            expected: wantedOn ? 'ON' : 'OFF',
            actual: device.isOn(slot) ? 'ON' : 'OFF',
            matched: device.isOn(slot) == wantedOn,
          ),
        );
      }
    }
    return checks;
  }
}

// ---------------------------------------------------------------------------
// Readback + persistence
// ---------------------------------------------------------------------------

enum ToneReadbackOutcome {
  certified,
  targetMismatch,
  unexpectedKnownChange,
  unknownRawChange,
  readFailed,

  /// A readback before the manual-save checkpoint is never a verification.
  notAwaitingSave,
}

class ToneReadbackResult {
  const ToneReadbackResult({
    required this.outcome,
    this.checks = const [],
    this.changes = const [],
    this.detail,
  });

  final ToneReadbackOutcome outcome;
  final List<ToneTargetCheck> checks;
  final List<FullLiveRawChange> changes;
  final String? detail;

  bool get isCertified => outcome == ToneReadbackOutcome.certified;
  int count(FullLiveChangeClass c) => changes.where((e) => e.classification == c).length;
}

abstract final class MatriboxToneTransferReadback {
  /// Fresh device read; BEFORE backup from the record; semantic TARGET vs
  /// DEVICE AFTER plus raw-change safety. Part 8 stays CORRELATED.
  static Future<ToneReadbackResult> run({
    required MatriboxToneTransferRecord record,
    required MatriboxRawBackupService backupService,
    required MatriboxToneTransferStore store,
  }) async {
    const allowed = {
      ToneTransferRecordState.awaitingManualSave,
      ToneTransferRecordState.failed,
      ToneTransferRecordState.stale,
      ToneTransferRecordState.verifying,
    };
    if (!allowed.contains(record.state)) {
      return const ToneReadbackResult(
        outcome: ToneReadbackOutcome.notAwaitingSave,
        detail: 'Erst nach dem manuellen Speichern am Gerät und der Bestätigung „Ich habe am Gerät gespeichert“ prüfen.',
      );
    }
    // The readback reads the slot the transfer is BOUND to -- never P01, never the UI's selection.
    final slot = MatriboxUserSlot.tryPreset(record.targetSlot);
    if (slot == null || !slot.isProductWritable || record.writtenSlot != record.targetSlot) {
      return const ToneReadbackResult(
        outcome: ToneReadbackOutcome.readFailed,
        detail: 'Der Transfer ist an keinen bestätigt beschriebenen Speicherplatz P11–P99 gebunden.',
      );
    }
    final RawPresetSnapshot before;
    try {
      before = decodeRawPresetBackupJson(await File(record.beforeBackupPath).readAsString());
    } catch (error) {
      return ToneReadbackResult(
        outcome: ToneReadbackOutcome.readFailed,
        detail: 'BEFORE-Backup nicht lesbar: $error.',
      );
    }
    if (before.sha256 != record.beforeBackupSha256 || before.presetNumber != slot.presetNumber || !before.isUserBank) {
      return const ToneReadbackResult(
        outcome: ToneReadbackOutcome.readFailed,
        detail: 'BEFORE-Backup passt nicht zum Transfer-Record.',
      );
    }
    final read = await readVerifiedUserSlot(backupService, slot);
    if (!read.isVerified || read.snapshot!.presetNumber != slot.presetNumber || !read.snapshot!.isUserBank) {
      return ToneReadbackResult(
        outcome: ToneReadbackOutcome.readFailed,
        detail: read.blockedReason ?? 'Der Readback lieferte nicht ${slot.label}.',
      );
    }
    final after = read.snapshot!;
    final checks = MatriboxToneTargetVerifier.compare(record.target, read.layout!);

    // Expected raw changes: every operation that was sent or attempted.
    final attempted = record.operations.where((o) => o.status != 'NOT_SENT');
    final modelSlots = {
      for (final o in attempted)
        if (o.kind == ToneOperationKind.selectModel) o.slot,
    };
    final toggleSlots = {
      for (final o in attempted)
        if (o.kind == ToneOperationKind.enableBlock || o.kind == ToneOperationKind.disableBlock) o.slot,
    };
    final indices = <MatriboxChainSlot, Set<int>>{};
    for (final o in attempted) {
      if (o.kind == ToneOperationKind.setParameter && o.wireIndex != null) {
        indices.putIfAbsent(o.slot, () => <int>{}).add(o.wireIndex!);
      }
    }
    final changes = MatriboxFullLiveVerifier.classifyRawChanges(
      before: before,
      after: after,
      modelSlots: modelSlots,
      parameterSlots: const {},
      toggleSlots: toggleSlots,
      parameterIndices: indices,
    );

    final ToneReadbackOutcome outcome;
    if (changes.any((c) => c.classification == FullLiveChangeClass.unknownRawChange)) {
      outcome = ToneReadbackOutcome.unknownRawChange;
    } else if (changes.any((c) => c.classification == FullLiveChangeClass.unexpectedKnownChange)) {
      outcome = ToneReadbackOutcome.unexpectedKnownChange;
    } else if (checks.any((c) => !c.matched)) {
      outcome = ToneReadbackOutcome.targetMismatch;
    } else {
      outcome = ToneReadbackOutcome.certified;
    }
    try {
      await store.save(
        record.copyWith(
          state: outcome == ToneReadbackOutcome.certified
              ? ToneTransferRecordState.verified
              : ToneTransferRecordState.failed,
          readbackOutcome: outcome.name,
          afterBackupSha256: after.sha256,
          // Verified AFTER a manual device save: not a QME2 store confirmation.
          persistence: outcome == ToneReadbackOutcome.certified ? 'MANUAL_SAVE_PERSISTENCE_VERIFIED' : null,
        ),
      );
    } catch (error) {
      return ToneReadbackResult(
        outcome: ToneReadbackOutcome.readFailed,
        checks: checks,
        changes: changes,
        detail: 'Ergebnis konnte nicht gespeichert werden: $error.',
      );
    }
    return ToneReadbackResult(outcome: outcome, checks: checks, changes: changes);
  }
}

enum TonePersistenceOutcome { manualSavePersistenceVerified, persistenceMismatch, notReady, readFailed }

class TonePersistenceResult {
  const TonePersistenceResult(this.outcome, {this.checks = const [], this.detail});
  final TonePersistenceOutcome outcome;
  final List<ToneTargetCheck> checks;
  final String? detail;

  bool get verified => outcome == TonePersistenceOutcome.manualSavePersistenceVerified;
}

abstract final class MatriboxToneTransferPersistence {
  /// After a manual device save (and reconnect): fresh read, target still
  /// identical -> MANUAL_SAVE_PERSISTENCE_VERIFIED. This is NOT a QME2 store
  /// confirmation; WyrmTone never sends a store command.
  static Future<TonePersistenceResult> check({
    required MatriboxToneTransferRecord record,
    required MatriboxRawBackupService backupService,
    required MatriboxToneTransferStore store,
  }) async {
    if (record.readbackOutcome != ToneReadbackOutcome.certified.name) {
      return const TonePersistenceResult(
        TonePersistenceOutcome.notReady,
        detail: 'Zuerst muss der Live-Readback CERTIFIED sein.',
      );
    }
    final slot = MatriboxUserSlot.tryPreset(record.targetSlot);
    if (slot == null || !slot.isProductWritable) {
      return const TonePersistenceResult(TonePersistenceOutcome.readFailed, detail: 'Kein Speicherplatz P11–P99.');
    }
    final read = await readVerifiedUserSlot(backupService, slot);
    if (!read.isVerified) {
      return TonePersistenceResult(TonePersistenceOutcome.readFailed, detail: read.blockedReason);
    }
    final checks = MatriboxToneTargetVerifier.compare(record.target, read.layout!);
    final ok = checks.every((c) => c.matched);
    final outcome = ok
        ? TonePersistenceOutcome.manualSavePersistenceVerified
        : TonePersistenceOutcome.persistenceMismatch;
    try {
      await store.save(
        record.copyWith(
          persistence: ok ? 'MANUAL_SAVE_PERSISTENCE_VERIFIED' : 'PERSISTENCE_MISMATCH',
        ),
      );
    } catch (_) {}
    return TonePersistenceResult(outcome, checks: checks);
  }
}
