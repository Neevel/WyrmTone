/// Orchestrates the controlled chain up to (but never including) an actual
/// write: READ CURRENT P01 -> CREATE/SAVE/RELOAD/VERIFY RAW BACKUP ->
/// DECODE CURRENT SEMANTIC PRESET -> BUILD TARGET -> DIFF -> BUILD WRITE
/// PLAN -> SAFETY VALIDATE. The result is meant to be shown to the user
/// for explicit manual confirmation; this class has no method that sends
/// anything to a device -- executing a confirmed write is out of scope
/// for this milestone (see docs/MATRIBOX_OFFLINE_ANALYSIS.md and
/// AGENTS.md's hardware-safety rule).
///
/// Restricted to User/P01 only in this milestone. The backup step reuses
/// [MatriboxRawBackupService] unchanged (already hardware-approved for
/// read+backup); this file adds no new native call.
library;

import 'dart:io';

import 'matribox_preset_decoder.dart';
import 'matribox_preset_diff.dart';
import 'matribox_preset_write_plan.dart';
import 'matribox_raw_backup_service.dart';
import 'matribox_semantic_preset.dart';
import 'matribox_write_lab_target.dart';
import 'preset_selection_codec.dart' show MatriboxPresetSlotAddress;
import 'raw_preset_backup_format.dart';
import 'raw_preset_snapshot.dart';

enum MatriboxSafeWriteSessionStage {
  /// A plan was built and safety-validated; whether it is actually
  /// [MatriboxPresetWritePlan.readyForHardwareTest] must still be checked
  /// -- reaching this stage only means preparation itself succeeded.
  readyForConfirmation,

  /// Preparation stopped before a plan could be built at all (no backup,
  /// backup invalid, wrong slot, no target possible, ...).
  blocked,
}

class MatriboxSafeWriteSessionResult {
  const MatriboxSafeWriteSessionResult({
    required this.stage,
    this.backup,
    this.currentPreset,
    this.targetPreset,
    this.diff,
    this.plan,
    this.blockedReason,
  });

  final MatriboxSafeWriteSessionStage stage;
  final MatriboxRawBackupResult? backup;
  final MatriboxSemanticPreset? currentPreset;
  final MatriboxSemanticPreset? targetPreset;
  final MatriboxPresetDiff? diff;
  final MatriboxPresetWritePlan? plan;
  final String? blockedReason;

  /// True only when a plan exists AND that plan itself says
  /// READY_FOR_HARDWARE_TEST. Never true just because preparation reached
  /// [MatriboxSafeWriteSessionStage.readyForConfirmation].
  bool get readyForHardwareTest =>
      stage == MatriboxSafeWriteSessionStage.readyForConfirmation &&
      plan?.readyForHardwareTest == true;
}

class MatriboxSafeWriteSession {
  const MatriboxSafeWriteSession({
    required this.backupService,
    required this.targetAddress,
  });

  final MatriboxRawBackupService backupService;

  /// Restricted to User/P01 for this milestone; [prepare] blocks
  /// immediately for any other address.
  final MatriboxPresetSlotAddress targetAddress;

  Future<MatriboxSafeWriteSessionResult> prepare() async {
    if (targetAddress.presetNumber != 1) {
      return const MatriboxSafeWriteSessionResult(
        stage: MatriboxSafeWriteSessionStage.blocked,
        blockedReason:
            'Safe Write Lab ist in dieser Phase ausschließlich für '
            'User/P01 freigegeben.',
      );
    }

    // Steps 1-5: READ CURRENT P01 -> CREATE -> SAVE -> RELOAD -> VERIFY
    // BACKUP HASH. Entirely delegated to the already hardware-approved
    // MatriboxRawBackupService -- no new native call here.
    final MatriboxRawBackupResult backupResult;
    try {
      backupResult = await backupService.backupUserP01();
    } catch (error) {
      return MatriboxSafeWriteSessionResult(
        stage: MatriboxSafeWriteSessionStage.blocked,
        blockedReason: 'Lesen/Sichern von P01 fehlgeschlagen: $error.',
      );
    }
    if (!backupResult.isSuccess || backupResult.filePath == null) {
      return MatriboxSafeWriteSessionResult(
        stage: MatriboxSafeWriteSessionStage.blocked,
        backup: backupResult,
        blockedReason:
            'Kein gültiges Backup: '
            '${backupResult.errorMessage ?? backupResult.outcome.name}.',
      );
    }

    // The just-verified backup FILE is the single source of truth for
    // "current state" -- re-read and re-validate it rather than trusting
    // any separately held live snapshot.
    final RawPresetSnapshot currentSnapshot;
    try {
      currentSnapshot = decodeRawPresetBackupJson(
        await File(backupResult.filePath!).readAsString(),
      );
    } catch (error) {
      return MatriboxSafeWriteSessionResult(
        stage: MatriboxSafeWriteSessionStage.blocked,
        backup: backupResult,
        blockedReason: 'Backup-Datei konnte nicht erneut gelesen werden: $error.',
      );
    }
    if (currentSnapshot.sha256 != backupResult.sha256) {
      return MatriboxSafeWriteSessionResult(
        stage: MatriboxSafeWriteSessionStage.blocked,
        backup: backupResult,
        blockedReason:
            'Hash der erneut gelesenen Backup-Datei stimmt nicht mit dem '
            'gemeldeten Hash überein.',
      );
    }
    if (currentSnapshot.presetNumber != targetAddress.presetNumber) {
      return MatriboxSafeWriteSessionResult(
        stage: MatriboxSafeWriteSessionStage.blocked,
        backup: backupResult,
        blockedReason:
            'Backup-Slot (${MatriboxPresetSlotAddress.fromPresetNumber(currentSnapshot.presetNumber).label}) '
            'stimmt nicht mit Zielslot (${targetAddress.label}) überein.',
      );
    }

    // Step 6: DECODE CURRENT SEMANTIC PRESET.
    final currentSemantic = MatriboxPresetDecoder.fromSnapshot(currentSnapshot);

    // Step 7: BUILD TARGET (lab-only in this milestone).
    final MatriboxSemanticPreset targetSemantic;
    try {
      targetSemantic = MatriboxWriteLabTarget.buildGainOnlyTarget(currentSemantic);
    } catch (error) {
      return MatriboxSafeWriteSessionResult(
        stage: MatriboxSafeWriteSessionStage.blocked,
        backup: backupResult,
        currentPreset: currentSemantic,
        blockedReason: 'Kein Lab-Target möglich: $error.',
      );
    }

    // Step 8: DIFF.
    final diff = MatriboxPresetDiffEngine.compare(
      current: currentSemantic,
      target: targetSemantic,
    );

    // Steps 9-10: BUILD WRITE PLAN + SAFETY VALIDATE (all gating logic
    // lives in MatriboxPresetWritePlanner, reused unchanged).
    final plan = MatriboxPresetWritePlanner.plan(
      targetAddress: targetAddress,
      currentBackup: currentSnapshot,
      verifiedBackupSha256: backupResult.sha256,
      diff: diff,
      target: targetSemantic,
    );

    // Steps 11-13 (SHOW PLAN, MANUAL CONFIRMATION, WRITE) are the caller's
    // responsibility -- this class stops here by design.
    return MatriboxSafeWriteSessionResult(
      stage: MatriboxSafeWriteSessionStage.readyForConfirmation,
      backup: backupResult,
      currentPreset: currentSemantic,
      targetPreset: targetSemantic,
      diff: diff,
      plan: plan,
    );
  }
}
