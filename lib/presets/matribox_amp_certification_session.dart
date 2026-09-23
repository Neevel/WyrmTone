/// Certification session, write executor and readback check for one
/// Sol 100 OD AMP field on User/P01:
///
/// SELECT FIELD -> READ P01 -> BACKUP -> SAVE -> RELOAD -> HASH VERIFY ->
/// DECODE CURRENT -> BUILD +/-1 TARGET -> ONE-FIELD DIFF -> SAFETY VALIDATE
/// -> (manual confirm, in the UI) -> EXACTLY ONE WRITE -> STOP.
///
/// Readback is a separate, manually started step after the user saved on
/// the device and reconnected. Nothing here stores, restores, retries or
/// advances to another field on its own. The normal song write plan is
/// untouched: a certification-eligible field stays BLOCKED there because
/// its static `hardwareWritable` evidence is unchanged.
library;

import 'dart:io';

import 'matribox_amp_certification.dart';
import 'matribox_preset_decoder.dart';
import 'matribox_preset_diff.dart';
import 'matribox_raw_backup_service.dart';
import 'matribox_semantic_preset.dart';
import 'matribox_write_verification.dart';
import 'preset_selection_codec.dart' show MatriboxPresetSlotAddress;
import 'raw_preset_backup_format.dart';
import 'raw_preset_snapshot.dart';

const _solOneHundredOdCode = 0x07000047;

enum MatriboxCertificationSessionStage { readyForConfirmation, blocked }

class MatriboxCertificationSessionResult {
  const MatriboxCertificationSessionResult({
    required this.stage,
    required this.field,
    this.backup,
    this.currentPreset,
    this.targetPreset,
    this.diff,
    this.currentValue,
    this.targetValue,
    this.blockedReason,
  });

  final MatriboxCertificationSessionStage stage;
  final MatriboxSol100OdAmpField field;
  final MatriboxRawBackupResult? backup;
  final MatriboxSemanticPreset? currentPreset;
  final MatriboxSemanticPreset? targetPreset;
  final MatriboxPresetDiff? diff;
  final double? currentValue;
  final double? targetValue;
  final String? blockedReason;

  /// True only if a backup is verified and the plan is exactly one change of
  /// [field] on User/P01 / Sol 100 OD. Not a product write approval.
  bool get readyForCertificationWrite =>
      stage == MatriboxCertificationSessionStage.readyForConfirmation &&
      backup?.isSuccess == true &&
      backup?.filePath != null &&
      backup?.sha256 != null &&
      currentValue != null &&
      targetValue != null;
}

class MatriboxCertificationSession {
  const MatriboxCertificationSession({
    required this.backupService,
    required this.records,
  });

  final MatriboxRawBackupService backupService;

  /// Records loaded from [MatriboxCertificationStore] before preparing.
  final List<MatriboxCertificationRecord> records;

  MatriboxCertificationSessionResult _blocked(
    MatriboxSol100OdAmpField field,
    String reason, {
    MatriboxRawBackupResult? backup,
    MatriboxSemanticPreset? current,
  }) => MatriboxCertificationSessionResult(
    stage: MatriboxCertificationSessionStage.blocked,
    field: field,
    backup: backup,
    currentPreset: current,
    blockedReason: reason,
  );

  Future<MatriboxCertificationSessionResult> prepare(
    MatriboxSol100OdAmpField field,
  ) async {
    final orderReason = MatriboxCertification.blockReason(field, records);
    if (orderReason != null) return _blocked(field, orderReason);

    final MatriboxRawBackupResult backupResult;
    try {
      backupResult = await backupService.backupUserP01();
    } catch (error) {
      return _blocked(field, 'Lesen/Sichern von P01 fehlgeschlagen: $error.');
    }
    if (!backupResult.isSuccess ||
        backupResult.filePath == null ||
        backupResult.sha256 == null) {
      return _blocked(
        field,
        'Kein gültiges Backup: '
        '${backupResult.errorMessage ?? backupResult.outcome.name}.',
        backup: backupResult,
      );
    }

    final RawPresetSnapshot snapshot;
    try {
      snapshot = decodeRawPresetBackupJson(
        await File(backupResult.filePath!).readAsString(),
      );
    } catch (error) {
      return _blocked(
        field,
        'Backup-Datei konnte nicht erneut gelesen werden: $error.',
        backup: backupResult,
      );
    }
    if (snapshot.sha256 != backupResult.sha256) {
      return _blocked(field, 'Backup-Hash stimmt nicht überein.', backup: backupResult);
    }
    if (snapshot.presetNumber != 1 || !snapshot.isUserBank) {
      return _blocked(
        field,
        'Certification ist ausschließlich für User/P01 freigegeben '
        '(gelesen: ${MatriboxPresetSlotAddress.fromPresetNumber(snapshot.presetNumber).label}).',
        backup: backupResult,
      );
    }

    final current = MatriboxPresetDecoder.fromSnapshot(snapshot);
    final amp = current.amp;
    if (amp == null || amp.algorithmCode != _solOneHundredOdCode) {
      return _blocked(
        field,
        'Aktueller Amp ist nicht Sol 100 OD; keine Certification.',
        backup: backupResult,
        current: current,
      );
    }
    final currentField = MatriboxCertificationTarget.currentField(current, field);
    if (currentField == null) {
      return _blocked(
        field,
        'Aktueller ${field.wireName}-Wert ist nicht lesbar.',
        backup: backupResult,
        current: current,
      );
    }

    final MatriboxSemanticPreset target;
    try {
      target = MatriboxCertificationTarget.build(current, field);
    } on UnsupportedCertificationTarget catch (error) {
      return _blocked(field, error.message, backup: backupResult, current: current);
    }
    final diff = MatriboxPresetDiffEngine.compare(current: current, target: target);
    if (diff.ampChanges.length != 1 || diff.ampChanges.single.field != field.wireName) {
      return _blocked(
        field,
        'Plan enthält nicht genau die eine Änderung von ${field.wireName}.',
        backup: backupResult,
        current: current,
      );
    }
    final change = diff.ampChanges.single;
    return MatriboxCertificationSessionResult(
      stage: MatriboxCertificationSessionStage.readyForConfirmation,
      field: field,
      backup: backupResult,
      currentPreset: current,
      targetPreset: target,
      diff: diff,
      currentValue: change.before,
      targetValue: change.after,
    );
  }
}

enum MatriboxCertificationWriteOutcome {
  success,
  deviceNotConnected,
  midiNotAvailable,
  invalidValue,
  sendFailed,
  safetyRejected,

  /// Dart-side only: the platform channel call itself failed.
  channelError,
}

class MatriboxCertificationWriteResult {
  const MatriboxCertificationWriteResult({
    required this.outcome,
    this.field,
    this.targetValue,
    this.errorMessage,
    this.recordSaved = false,
  });

  final MatriboxCertificationWriteOutcome outcome;
  final MatriboxSol100OdAmpField? field;
  final double? targetValue;
  final String? errorMessage;

  /// The WRITE_SENT record (BEFORE-backup reference) was persisted.
  final bool recordSaved;

  bool get isSuccess => outcome == MatriboxCertificationWriteOutcome.success;
}

MatriboxCertificationWriteOutcome _writeOutcomeFromNative(Object? name) =>
    switch (name) {
      'SUCCESS' => MatriboxCertificationWriteOutcome.success,
      'DEVICE_NOT_CONNECTED' => MatriboxCertificationWriteOutcome.deviceNotConnected,
      'MIDI_NOT_AVAILABLE' => MatriboxCertificationWriteOutcome.midiNotAvailable,
      'INVALID_VALUE' => MatriboxCertificationWriteOutcome.invalidValue,
      'SEND_FAILED' => MatriboxCertificationWriteOutcome.sendFailed,
      'SAFETY_REJECTED' => MatriboxCertificationWriteOutcome.safetyRejected,
      _ => MatriboxCertificationWriteOutcome.channelError,
    };

/// Abstracts the native call. Only a whitelisted field name and the target
/// value cross this boundary -- no algorithm, index, bytes, bank or slot.
abstract interface class MatriboxCertificationWriteChannel {
  Future<Map<Object?, Object?>> writeCertificationAmpField(
    String field,
    double targetValue,
  );
}

/// Re-derives every precondition from the session result itself (the UI's
/// enabled button is never trusted), makes at most ONE channel call and
/// never retries. A transport failure can only ever yield a non-success
/// outcome, never a record.
class MatriboxCertificationExecutor {
  const MatriboxCertificationExecutor({
    required this.channel,
    required this.store,
    required this.records,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final MatriboxCertificationWriteChannel channel;
  final MatriboxCertificationStore store;
  final List<MatriboxCertificationRecord> records;
  final DateTime Function() _clock;

  MatriboxCertificationWriteResult _rejected(String message) =>
      MatriboxCertificationWriteResult(
        outcome: MatriboxCertificationWriteOutcome.safetyRejected,
        errorMessage: message,
      );

  Future<MatriboxCertificationWriteResult> execute(
    MatriboxCertificationSessionResult session,
  ) async {
    if (!session.readyForCertificationWrite) {
      return _rejected('Certification-Plan ist nicht bereit.');
    }
    final field = session.field;
    final orderReason = MatriboxCertification.blockReason(field, records);
    if (orderReason != null) return _rejected(orderReason);
    final backup = session.backup!;
    if (backup.presetNumber != 1) return _rejected('Zielslot ist nicht User/P01.');
    final diff = session.diff;
    if (diff == null ||
        diff.ampChanges.length != 1 ||
        diff.ampChanges.single.field != field.wireName) {
      return _rejected('Plan enthält nicht genau die eine Änderung von ${field.wireName}.');
    }
    final target = session.targetValue!;
    final current = session.currentValue!;
    if (target != MatriboxCertificationTarget.targetFor(current) ||
        target < matriboxCertificationMinimum ||
        target > matriboxCertificationMaximum) {
      return _rejected('Zielwert ist nicht das kontrollierte ±1-Certification-Ziel.');
    }

    final Map<Object?, Object?> raw;
    try {
      raw = await channel.writeCertificationAmpField(field.wireName, target);
    } catch (error) {
      return MatriboxCertificationWriteResult(
        outcome: MatriboxCertificationWriteOutcome.channelError,
        field: field,
        errorMessage: '$error',
      );
    }
    final outcome = _writeOutcomeFromNative(raw['outcome']);
    if (outcome != MatriboxCertificationWriteOutcome.success) {
      return MatriboxCertificationWriteResult(
        outcome: outcome,
        field: field,
        targetValue: target,
        errorMessage: raw['error'] as String?,
      );
    }
    var saved = true;
    try {
      await store.save(
        MatriboxCertificationRecord(
          field: field,
          state: MatriboxCertificationRecordState.writeSent,
          beforeValue: current,
          targetValue: target,
          beforeBackupPath: backup.filePath!,
          beforeBackupSha256: backup.sha256!,
          writeSentAt: _clock(),
        ),
      );
    } catch (_) {
      saved = false;
    }
    return MatriboxCertificationWriteResult(
      outcome: outcome,
      field: field,
      targetValue: target,
      recordSaved: saved,
    );
  }
}

enum MatriboxCertificationReadbackOutcome {
  certified,
  expectedChangeMissing,
  unexpectedKnownChange,
  unknownRawChange,
  readFailed,
  backupMismatch,
}

class MatriboxCertificationReadbackResult {
  const MatriboxCertificationReadbackResult({
    required this.outcome,
    this.detail,
    this.afterSha256,
  });

  final MatriboxCertificationReadbackOutcome outcome;
  final String? detail;
  final String? afterSha256;

  bool get isCertified => outcome == MatriboxCertificationReadbackOutcome.certified;
}

/// Compares the stored BEFORE backup of a WRITE_SENT record with a NEW P01
/// read. The result only updates this lab store; it never edits the
/// evidence registry.
abstract final class MatriboxCertificationReadback {
  static Future<MatriboxCertificationReadbackResult> run({
    required MatriboxCertificationRecord record,
    required MatriboxRawBackupService backupService,
    required MatriboxCertificationStore store,
    DateTime Function()? clock,
  }) async {
    final now = clock ?? DateTime.now;
    if (record.state != MatriboxCertificationRecordState.writeSent) {
      return const MatriboxCertificationReadbackResult(
        outcome: MatriboxCertificationReadbackOutcome.readFailed,
        detail: 'Kein offener Write für diesen Readback.',
      );
    }
    final RawPresetSnapshot before;
    try {
      before = decodeRawPresetBackupJson(
        await File(record.beforeBackupPath).readAsString(),
      );
    } catch (error) {
      return MatriboxCertificationReadbackResult(
        outcome: MatriboxCertificationReadbackOutcome.backupMismatch,
        detail: 'BEFORE-Backup nicht lesbar: $error.',
      );
    }
    if (before.sha256 != record.beforeBackupSha256 ||
        before.presetNumber != 1 ||
        !before.isUserBank) {
      return const MatriboxCertificationReadbackResult(
        outcome: MatriboxCertificationReadbackOutcome.backupMismatch,
        detail: 'BEFORE-Backup passt nicht zum Certification-Record.',
      );
    }

    final MatriboxRawBackupResult read;
    try {
      read = await backupService.backupUserP01();
    } catch (error) {
      return MatriboxCertificationReadbackResult(
        outcome: MatriboxCertificationReadbackOutcome.readFailed,
        detail: '$error',
      );
    }
    if (!read.isSuccess || read.filePath == null) {
      return MatriboxCertificationReadbackResult(
        outcome: MatriboxCertificationReadbackOutcome.readFailed,
        detail: read.errorMessage ?? read.outcome.name,
      );
    }
    final RawPresetSnapshot after;
    try {
      after = decodeRawPresetBackupJson(await File(read.filePath!).readAsString());
    } catch (error) {
      return MatriboxCertificationReadbackResult(
        outcome: MatriboxCertificationReadbackOutcome.readFailed,
        detail: 'AFTER-Backup nicht lesbar: $error.',
      );
    }
    if (after.presetNumber != 1 || !after.isUserBank) {
      return const MatriboxCertificationReadbackResult(
        outcome: MatriboxCertificationReadbackOutcome.readFailed,
        detail: 'Neuer Read stammt nicht von User/P01.',
      );
    }

    final verification = MatriboxWriteVerifier.verify(
      before: before,
      after: after,
      expectedField: record.field.wireName,
    );
    final afterAmp = MatriboxPresetDecoder.fromSnapshot(after).amp;
    final afterValue = afterAmp?.fieldsByName[record.field.wireName]?.value;

    final MatriboxCertificationReadbackOutcome outcome;
    if (verification.outcome ==
            MatriboxWriteVerificationOutcome.expectedChangeMissing ||
        afterValue != record.targetValue) {
      outcome = MatriboxCertificationReadbackOutcome.expectedChangeMissing;
    } else if (verification.hasUnknownChange) {
      outcome = MatriboxCertificationReadbackOutcome.unknownRawChange;
    } else if (verification.outcome !=
        MatriboxWriteVerificationOutcome.verified) {
      outcome = MatriboxCertificationReadbackOutcome.unexpectedKnownChange;
    } else {
      outcome = MatriboxCertificationReadbackOutcome.certified;
    }

    final certified = outcome == MatriboxCertificationReadbackOutcome.certified;
    try {
      await store.save(
        record.withReadback(
          state: certified
              ? MatriboxCertificationRecordState.certified
              : MatriboxCertificationRecordState.readbackFailed,
          outcome: outcome.name,
          at: now(),
          afterSha256: after.sha256,
        ),
      );
    } catch (error) {
      return MatriboxCertificationReadbackResult(
        outcome: MatriboxCertificationReadbackOutcome.readFailed,
        detail: 'Ergebnis konnte nicht gespeichert werden: $error.',
        afterSha256: after.sha256,
      );
    }
    return MatriboxCertificationReadbackResult(
      outcome: outcome,
      afterSha256: after.sha256,
      detail: certified && verification.hasCorrelatedSideEffect
          ? 'Hinweis: zusätzlich änderte sich das bekannte Part-8-Fenster '
                '(Byte 37..44, vermutlich Prüfsumme; korreliert, nicht '
                'dekodiert -- gleiches Muster wie beim Gain-Write).'
          : null,
    );
  }
}
