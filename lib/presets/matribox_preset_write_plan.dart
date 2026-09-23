/// A concrete, per-field plan for writing to a Matribox preset slot.
/// Deliberately separate from `PresetWritePlan`/`PresetWritePlanner`
/// (preset_write_plan.dart), which plans at the `CanonicalPreset` layer
/// and is unconditionally blocked pending full protocol confirmation. This
/// plan operates at the wire-semantic layer and can genuinely mark an
/// individual field WRITABLE when hardware write evidence exists for it
/// (currently only Sol-100-OD Gain, via `ConfirmedParameterCodec`).
///
/// This file only plans; it never sends anything and has no transport
/// dependency. Nothing produced here is executed automatically.
library;

import 'matribox_preset_diff.dart';
import 'matribox_semantic_preset.dart';
import 'preset_selection_codec.dart' show MatriboxPresetSlotAddress;
import 'protocol_evidence.dart';
import 'raw_preset_snapshot.dart';

enum MatriboxWriteOperationStatus { writable, blocked }

class MatriboxPresetWriteOperation {
  const MatriboxPresetWriteOperation({
    required this.field,
    required this.currentValue,
    required this.targetValue,
    required this.evidence,
    required this.status,
    required this.reason,
    this.catalogIndex,
    this.algorithmCode,
  });

  final String field;
  final double? currentValue;
  final double targetValue;
  final EvidenceLevel evidence;
  final MatriboxWriteOperationStatus status;
  final String reason;
  final int? catalogIndex;
  final int? algorithmCode;

  bool get writable => status == MatriboxWriteOperationStatus.writable;

  Map<String, Object?> toJson() => {
    'field': field,
    'currentValue': currentValue,
    'targetValue': targetValue,
    'evidenceLevel': evidence.name,
    'status': status.name,
    'reason': reason,
    'catalogIndex': catalogIndex,
    'algorithmCode': algorithmCode,
  };
}

enum MatriboxWritePlanGate { readyForHardwareTest, blocked }

class MatriboxPresetWritePlan {
  const MatriboxPresetWritePlan({
    required this.targetAddress,
    required this.backupSha256,
    required this.operations,
    required this.gate,
    required this.blockers,
  });

  final MatriboxPresetSlotAddress targetAddress;
  final String? backupSha256;
  final List<MatriboxPresetWriteOperation> operations;
  final MatriboxWritePlanGate gate;
  final List<String> blockers;

  bool get readyForHardwareTest =>
      gate == MatriboxWritePlanGate.readyForHardwareTest;

  Map<String, Object?> toJson() => {
    'targetAddress': targetAddress.label,
    'backupSha256': backupSha256,
    'operations': operations.map((o) => o.toJson()).toList(),
    'gate': gate.name,
    'blockers': blockers,
  };
}

abstract final class MatriboxPresetWritePlanner {
  /// [verifiedBackupSha256] must be the hash independently re-verified
  /// after saving the backup (e.g. `MatriboxRawBackupResult.sha256` from a
  /// completed `MatriboxRawBackupService.backupUserP01()` call) -- passing
  /// [currentBackup]'s own hash back at face value would defeat the
  /// "backup hash verified" requirement.
  static MatriboxPresetWritePlan plan({
    required MatriboxPresetSlotAddress targetAddress,
    required RawPresetSnapshot? currentBackup,
    required String? verifiedBackupSha256,
    required MatriboxPresetDiff diff,
    required MatriboxSemanticPreset target,
  }) {
    final blockers = <String>[];

    if (currentBackup == null) {
      blockers.add('Kein gültiges Raw-Backup des Zielslots vorhanden.');
    } else if (verifiedBackupSha256 == null ||
        verifiedBackupSha256 != currentBackup.sha256) {
      blockers.add('Backup-Hash ist nicht unabhängig verifiziert.');
    } else if (currentBackup.presetNumber != targetAddress.presetNumber) {
      blockers.add(
        'Zielslot (${targetAddress.label}) stimmt nicht mit dem '
        'gesicherten Slot (${MatriboxPresetSlotAddress.fromPresetNumber(currentBackup.presetNumber).label}) überein.',
      );
    } else if (!currentBackup.isUserBank) {
      blockers.add('Factory-Bank ist außerhalb des Scopes.');
    }

    final operations = <MatriboxPresetWriteOperation>[];
    final targetFields = target.amp?.fieldsByName ?? const {};
    for (final change in diff.ampChanges) {
      final targetField = targetFields[change.field];
      final writable = targetField?.writeEvidence == EvidenceLevel.confirmed;
      operations.add(
        MatriboxPresetWriteOperation(
          field: change.field,
          currentValue: change.before,
          targetValue: change.after,
          evidence: change.evidence,
          status: writable
              ? MatriboxWriteOperationStatus.writable
              : MatriboxWriteOperationStatus.blocked,
          reason: writable
              ? 'WRITABLE: ConfirmedParameterCodec, Sol 100 OD Gain (einzige '
                    'schreib-bestätigte Feldadresse).'
              : 'Keine bestätigte Schreib-Evidenz für dieses Feld '
                    '(nur Lese-Evidenz, falls überhaupt vorhanden).',
          catalogIndex: targetField?.catalogIndex,
          algorithmCode: target.amp?.algorithmCode,
        ),
      );
    }

    if (operations.isEmpty) {
      blockers.add('Keine geplanten Änderungen.');
    } else if (operations.any((op) => !op.writable)) {
      blockers.add(
        'Mindestens eine geplante Änderung ist nicht schreib-bestätigt.',
      );
    }

    final gate = blockers.isEmpty
        ? MatriboxWritePlanGate.readyForHardwareTest
        : MatriboxWritePlanGate.blocked;

    return MatriboxPresetWritePlan(
      targetAddress: targetAddress,
      backupSha256: currentBackup?.sha256,
      operations: List.unmodifiable(operations),
      gate: gate,
      blockers: List.unmodifiable(blockers),
    );
  }
}
