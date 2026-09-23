/// A local, in-memory audit record for one confirmed parameter write.
/// Deliberately not persisted to disk -- no existing audit-log
/// infrastructure exists to build on, and the backup's SHA-256 is already
/// the durable reference to the before-state (see
/// raw_preset_backup_format.dart). Contains no raw bytes and no secrets.
///
/// [outcome] reflects ONLY the result of the native send attempt (the
/// platform channel's/native session's outcome, e.g. "success" or
/// "sendFailed") -- it is a WRITE_SENT-level fact. It must never be read
/// as also confirming that the device's value actually changed, that a
/// readback verified the change, or that the change survived a save or
/// reconnect. Those are separate, currently manual/human-observed
/// concerns (see docs/MATRIBOX_OFFLINE_ANALYSIS.md, "Erster produktiver
/// WyrmTone-Hardware-Write") and are deliberately not modeled as
/// additional fields here yet, since nothing in this codebase computes
/// them automatically -- adding unused state would be premature. When a
/// generalized [package:wyrmtone/presets/matribox_write_verification.dart]
/// BEFORE/AFTER check is actually wired into a write flow, its result
/// belongs in a follow-up field, not folded into [outcome].
library;

class MatriboxWriteAuditEntry {
  const MatriboxWriteAuditEntry({
    required this.timestamp,
    required this.device,
    required this.presetName,
    required this.backupSha256,
    required this.field,
    required this.beforeValue,
    required this.targetValue,
    required this.evidence,
    required this.outcome,
  });

  final DateTime timestamp;
  final String device;
  final String presetName;
  final String backupSha256;
  final String field;
  final double? beforeValue;
  final double targetValue;
  final String evidence;
  final String outcome;

  Map<String, Object?> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'device': device,
    'target': 'User/P01',
    'presetName': presetName,
    'backupSha256': backupSha256,
    'field': field,
    'beforeValue': beforeValue,
    'targetValue': targetValue,
    'evidence': evidence,
    'outcome': outcome,
  };
}
