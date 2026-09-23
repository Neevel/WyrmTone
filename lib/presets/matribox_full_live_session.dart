/// Full Live Edit Certification flow for User P01:
///
/// PREPARE (READ -> BACKUP -> SAVE -> RELOAD -> HASH VERIFY -> DECODE -> plan
/// check) -> one manual confirmation -> RUN (native, fixed plan, first
/// failure stops, no retry, no rollback) -> STOP. The device is inspected by
/// the user; only then a separate manual READBACK verifies the result
/// against the BEFORE backup and the plan.
///
/// NO Store / commit / Save, no preset name/BPM/VOL, no User IR. Changes stay
/// volatile. Dart never sends bytes: the native side runs its own constant
/// plan, addressed only by [MatriboxFullLivePlan.planId].
library;

import 'dart:convert';
import 'dart:io';

import 'matribox_certification_plan.dart';
import 'matribox_full_live_plan.dart';
import 'matribox_full_live_verifier.dart';
import 'matribox_preset_layout.dart';
import 'matribox_raw_backup_service.dart';
import 'matribox_verified_p01_read.dart';
import 'raw_preset_backup_format.dart';
import 'raw_preset_snapshot.dart';

/// File name of the single Full Live record inside the raw-backup directory.
const matriboxFullLiveStateFileName = 'full_live_certification.state';

enum FullLiveSessionStage { readyForConfirmation, blocked }

class FullLiveSessionResult {
  const FullLiveSessionResult({
    required this.stage,
    this.backup,
    this.current,
    this.blockedReason,
    this.blockCode,
  });

  final FullLiveSessionStage stage;
  final MatriboxRawBackupResult? backup;

  /// Confirmed layout of the verified BEFORE backup.
  final MatriboxPresetLayoutModel? current;
  final String? blockedReason;

  /// Machine readable blocker (`SOURCE_PRESET_MISMATCH`, `ALREADY_AT_TARGET`, ...).
  final String? blockCode;

  bool get readyForFullLiveTest =>
      stage == FullLiveSessionStage.readyForConfirmation &&
      backup?.isSuccess == true &&
      backup?.filePath != null &&
      backup?.sha256 != null &&
      current != null;
}

class MatriboxFullLiveSession {
  const MatriboxFullLiveSession({
    required this.backupService,
    this.plan = const FullLiveP01Plan(),
  });

  final MatriboxRawBackupService backupService;
  final CertificationPlan plan;

  FullLiveSessionResult _blocked(String reason, {MatriboxRawBackupResult? backup}) =>
      FullLiveSessionResult(stage: FullLiveSessionStage.blocked, backup: backup, blockedReason: reason);

  Future<FullLiveSessionResult> prepare() async {
    final read = await readVerifiedP01(backupService);
    if (!read.isVerified) {
      return _blocked(read.blockedReason ?? 'Lesen von P01 fehlgeschlagen.', backup: read.backup);
    }
    final layout = read.layout!;
    final blockers = plan.blockers(layout);
    if (blockers.isNotEmpty) {
      return FullLiveSessionResult(
        stage: FullLiveSessionStage.blocked,
        backup: read.backup,
        current: layout,
        blockedReason: blockers.join(' '),
        blockCode: plan.blockCode(layout),
      );
    }
    return FullLiveSessionResult(
      stage: FullLiveSessionStage.readyForConfirmation,
      backup: read.backup,
      current: layout,
    );
  }
}

enum FullLiveRunOutcome {
  success,
  deviceNotConnected,
  midiNotAvailable,
  safetyRejected,
  sendFailed,

  /// Dart-side only: the platform channel call itself failed.
  channelError,
}

FullLiveRunOutcome _runOutcomeFromNative(Object? name) => switch (name) {
  'SUCCESS' => FullLiveRunOutcome.success,
  'DEVICE_NOT_CONNECTED' => FullLiveRunOutcome.deviceNotConnected,
  'MIDI_NOT_AVAILABLE' => FullLiveRunOutcome.midiNotAvailable,
  'SAFETY_REJECTED' => FullLiveRunOutcome.safetyRejected,
  'SEND_FAILED' => FullLiveRunOutcome.sendFailed,
  _ => FullLiveRunOutcome.channelError,
};

class FullLiveOperationStatus {
  const FullLiveOperationStatus(this.index, this.label, this.status);
  final int index;
  final String label;

  /// SENT, FAILED or NOT_SENT.
  final String status;
}

class FullLiveRunResult {
  const FullLiveRunResult({
    required this.outcome,
    this.completed = 0,
    this.total = 0,
    this.failedIndex,
    this.error,
    this.operations = const [],
    this.recordSaved = false,
  });

  final FullLiveRunOutcome outcome;
  final int completed;
  final int total;
  final int? failedIndex;
  final String? error;
  final List<FullLiveOperationStatus> operations;
  final bool recordSaved;

  bool get isSuccess => outcome == FullLiveRunOutcome.success;
  Iterable<FullLiveOperationStatus> get notSent => operations.where((o) => o.status == 'NOT_SENT');
}

/// Abstracts the native call. Only the plan id crosses this boundary.
abstract interface class MatriboxFullLiveChannel {
  Future<Map<Object?, Object?>> runFullLiveP01Certification(String planId);
}

enum FullLiveRecordState { sent, readbackDone }

class MatriboxFullLiveRecord {
  const MatriboxFullLiveRecord({
    required this.planId,
    required this.beforeBackupPath,
    required this.beforeBackupSha256,
    required this.runOutcome,
    required this.completed,
    required this.total,
    required this.sentAt,
    this.state = FullLiveRecordState.sent,
    this.readbackOutcome,
    this.readbackAt,
    this.afterBackupSha256,
  });

  final String planId;
  final String beforeBackupPath;
  final String beforeBackupSha256;
  final String runOutcome;
  final int completed;
  final int total;
  final DateTime sentAt;
  final FullLiveRecordState state;
  final String? readbackOutcome;
  final DateTime? readbackAt;
  final String? afterBackupSha256;

  MatriboxFullLiveRecord withReadback(String outcome, DateTime at, String? afterSha) =>
      MatriboxFullLiveRecord(
        planId: planId,
        beforeBackupPath: beforeBackupPath,
        beforeBackupSha256: beforeBackupSha256,
        runOutcome: runOutcome,
        completed: completed,
        total: total,
        sentAt: sentAt,
        state: FullLiveRecordState.readbackDone,
        readbackOutcome: outcome,
        readbackAt: at,
        afterBackupSha256: afterSha,
      );

  Map<String, Object?> toJson() => {
    'planId': planId,
    'beforeBackupPath': beforeBackupPath,
    'beforeBackupSha256': beforeBackupSha256,
    'runOutcome': runOutcome,
    'completed': completed,
    'total': total,
    'sentAt': sentAt.toUtc().toIso8601String(),
    'state': state.name,
    'readbackOutcome': readbackOutcome,
    'readbackAt': readbackAt?.toUtc().toIso8601String(),
    'afterBackupSha256': afterBackupSha256,
  };

  static MatriboxFullLiveRecord? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final sentAt = DateTime.tryParse('${json['sentAt']}');
    final state = FullLiveRecordState.values.where((s) => s.name == json['state']).firstOrNull;
    if (json['planId'] is! String ||
        json['beforeBackupPath'] is! String ||
        json['beforeBackupSha256'] is! String ||
        json['runOutcome'] is! String ||
        json['completed'] is! int ||
        json['total'] is! int ||
        sentAt == null ||
        state == null) {
      return null;
    }
    return MatriboxFullLiveRecord(
      planId: json['planId'] as String,
      beforeBackupPath: json['beforeBackupPath'] as String,
      beforeBackupSha256: json['beforeBackupSha256'] as String,
      runOutcome: json['runOutcome'] as String,
      completed: json['completed'] as int,
      total: json['total'] as int,
      sentAt: sentAt,
      state: state,
      readbackOutcome: json['readbackOutcome'] as String?,
      readbackAt: DateTime.tryParse('${json['readbackAt']}'),
      afterBackupSha256: json['afterBackupSha256'] as String?,
    );
  }
}

/// Single-record local JSON file; keeps the BEFORE-backup reference across
/// app restarts and reconnects.
class MatriboxFullLiveStore {
  const MatriboxFullLiveStore(this.file);
  final File file;

  Future<MatriboxFullLiveRecord?> load() async {
    if (!await file.exists()) return null;
    try {
      return MatriboxFullLiveRecord.tryFromJson(jsonDecode(await file.readAsString()));
    } on FormatException {
      return null;
    }
  }

  Future<void> save(MatriboxFullLiveRecord record) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(record.toJson()), flush: true);
  }
}

/// Re-derives every precondition from the session result (the UI's enabled
/// button is never trusted), makes at most ONE channel call and never
/// retries.
class MatriboxFullLiveExecutor {
  const MatriboxFullLiveExecutor({
    required this.channel,
    required this.store,
    this.plan = const FullLiveP01Plan(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final MatriboxFullLiveChannel channel;
  final MatriboxFullLiveStore store;
  final CertificationPlan plan;
  final DateTime Function() _clock;

  Future<FullLiveRunResult> execute(FullLiveSessionResult session) async {
    if (!session.readyForFullLiveTest) {
      return const FullLiveRunResult(
        outcome: FullLiveRunOutcome.safetyRejected,
        error: 'Full-Live-Plan ist nicht bereit.',
      );
    }
    final backup = session.backup!;
    if (backup.presetNumber != 1) {
      return const FullLiveRunResult(
        outcome: FullLiveRunOutcome.safetyRejected,
        error: 'Zielslot ist nicht User/P01.',
      );
    }
    if (plan.blockers(session.current!).isNotEmpty) {
      return const FullLiveRunResult(
        outcome: FullLiveRunOutcome.safetyRejected,
        error: 'Aktueller P01-Zustand passt nicht zum Plan.',
      );
    }

    final Map<Object?, Object?> raw;
    try {
      raw = await channel.runFullLiveP01Certification(plan.planId);
    } catch (error) {
      return FullLiveRunResult(outcome: FullLiveRunOutcome.channelError, error: '$error');
    }
    final operations = [
      for (final item in (raw['operations'] as List? ?? const []))
        if (item is Map)
          FullLiveOperationStatus(
            (item['index'] as num?)?.toInt() ?? -1,
            '${item['label']}',
            '${item['status']}',
          ),
    ];
    final completed = (raw['completed'] as num?)?.toInt() ?? 0;
    final total = (raw['total'] as num?)?.toInt() ?? plan.operations.length;
    final outcome = _runOutcomeFromNative(raw['outcome']);

    var saved = false;
    if (completed > 0) {
      try {
        await store.save(
          MatriboxFullLiveRecord(
            planId: plan.planId,
            beforeBackupPath: backup.filePath!,
            beforeBackupSha256: backup.sha256!,
            runOutcome: outcome.name,
            completed: completed,
            total: total,
            sentAt: _clock(),
          ),
        );
        saved = true;
      } catch (_) {}
    }
    return FullLiveRunResult(
      outcome: outcome,
      completed: completed,
      total: total,
      failedIndex: (raw['failedIndex'] as num?)?.toInt(),
      error: raw['error'] as String?,
      operations: operations,
      recordSaved: saved,
    );
  }
}

enum FullLiveReadbackOutcome {
  certified,
  expectedChangeMissing,
  unexpectedKnownChange,
  unknownRawChange,
  readFailed,
  backupMismatch,

  /// Not every operation of the plan was sent (first failure stopped the run).
  partialExecution,
}

class FullLiveReadbackResult {
  const FullLiveReadbackResult({required this.outcome, this.verification, this.detail});
  final FullLiveReadbackOutcome outcome;
  final FullLiveVerification? verification;
  final String? detail;
  bool get isCertified => outcome == FullLiveReadbackOutcome.certified;
}

/// Compares the stored BEFORE backup with a NEW P01 read against the plan.
abstract final class MatriboxFullLiveReadback {
  static Future<FullLiveReadbackResult> run({
    required MatriboxFullLiveRecord record,
    required MatriboxRawBackupService backupService,
    required MatriboxFullLiveStore store,
    DateTime Function()? clock,
    CertificationPlan plan = const FullLiveP01Plan(),
  }) async {
    final RawPresetSnapshot before;
    try {
      before = decodeRawPresetBackupJson(await File(record.beforeBackupPath).readAsString());
    } catch (error) {
      return FullLiveReadbackResult(
        outcome: FullLiveReadbackOutcome.backupMismatch,
        detail: 'BEFORE-Backup nicht lesbar: $error.',
      );
    }
    if (before.sha256 != record.beforeBackupSha256 || before.presetNumber != 1 || !before.isUserBank) {
      return const FullLiveReadbackResult(
        outcome: FullLiveReadbackOutcome.backupMismatch,
        detail: 'BEFORE-Backup passt nicht zum Full-Live-Record.',
      );
    }
    final MatriboxRawBackupResult read;
    try {
      read = await backupService.backupUserP01();
    } catch (error) {
      return FullLiveReadbackResult(outcome: FullLiveReadbackOutcome.readFailed, detail: '$error');
    }
    if (!read.isSuccess || read.filePath == null) {
      return FullLiveReadbackResult(
        outcome: FullLiveReadbackOutcome.readFailed,
        detail: read.errorMessage ?? read.outcome.name,
      );
    }
    final RawPresetSnapshot after;
    try {
      after = decodeRawPresetBackupJson(await File(read.filePath!).readAsString());
    } catch (error) {
      return FullLiveReadbackResult(
        outcome: FullLiveReadbackOutcome.readFailed,
        detail: 'AFTER-Backup nicht lesbar: $error.',
      );
    }
    if (after.presetNumber != 1 || !after.isUserBank) {
      return const FullLiveReadbackResult(
        outcome: FullLiveReadbackOutcome.readFailed,
        detail: 'Neuer Read stammt nicht von User/P01.',
      );
    }
    final verification = MatriboxFullLiveVerifier.verify(before: before, after: after, plan: plan);
    final partial = record.completed < record.total || record.planId != plan.planId;
    final outcome = partial
        ? FullLiveReadbackOutcome.partialExecution
        : switch (verification.outcome) {
      FullLiveVerificationOutcome.certified => FullLiveReadbackOutcome.certified,
      FullLiveVerificationOutcome.expectedChangeMissing => FullLiveReadbackOutcome.expectedChangeMissing,
      FullLiveVerificationOutcome.unexpectedKnownChange => FullLiveReadbackOutcome.unexpectedKnownChange,
      FullLiveVerificationOutcome.unknownRawChange => FullLiveReadbackOutcome.unknownRawChange,
    };
    try {
      await store.save(record.withReadback(outcome.name, (clock ?? DateTime.now)(), after.sha256));
    } catch (error) {
      return FullLiveReadbackResult(
        outcome: FullLiveReadbackOutcome.readFailed,
        verification: verification,
        detail: 'Ergebnis konnte nicht gespeichert werden: $error.',
      );
    }
    return FullLiveReadbackResult(outcome: outcome, verification: verification);
  }
}
