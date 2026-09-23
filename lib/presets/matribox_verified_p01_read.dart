/// The productive transfer's "fresh, verified read" of exactly one
/// product-writable slot (P11..P99): READ -> BACKUP (saved) -> RELOAD -> HASH
/// VERIFY -> USER/SLOT CHECK -> SEMANTIC DECODE. The result always comes from
/// the device just now; there is no cache and no fixture in this path.
library;

import 'dart:io';

import 'matribox_preset_layout.dart';
import 'matribox_raw_backup_service.dart';
import 'matribox_transfer_slots.dart';
import 'raw_preset_backup_format.dart';
import 'raw_preset_snapshot.dart';

class VerifiedPresetRead {
  const VerifiedPresetRead({this.slot, this.backup, this.snapshot, this.layout, this.blockedReason});

  /// The slot that was REQUESTED (null only for a read without slot identity, never a transfer read).
  final MatriboxUserSlot? slot;
  final MatriboxRawBackupResult? backup;
  final RawPresetSnapshot? snapshot;
  final MatriboxPresetLayoutModel? layout;
  final String? blockedReason;

  bool get isVerified =>
      blockedReason == null &&
      backup?.isSuccess == true &&
      backup?.filePath != null &&
      backup?.sha256 != null &&
      snapshot != null &&
      layout != null;
}

/// Fresh verified read of exactly [slot]. A protected or invalid slot is refused WITHOUT reading;
/// a snapshot that is not User/[slot] is never verified.
Future<VerifiedPresetRead> readVerifiedUserSlot(MatriboxRawBackupService backupService, MatriboxUserSlot slot) {
  final rejection = MatriboxSlotPolicy.writeRejection(slot.presetNumber);
  if (rejection != null) return Future.value(VerifiedPresetRead(slot: slot, blockedReason: rejection));
  return _readVerified(() => backupService.backupUserSlot(slot), expected: slot.presetNumber, slot: slot);
}

Future<VerifiedPresetRead> _readVerified(
  Future<MatriboxRawBackupResult> Function() backupRead, {
  required int expected,
  required MatriboxUserSlot? slot,
}) async {
  final label = MatriboxUserSlot.preset(expected).label;
  final MatriboxRawBackupResult backup;
  try {
    backup = await backupRead();
  } catch (error) {
    return VerifiedPresetRead(slot: slot, blockedReason: 'Lesen/Sichern von $label fehlgeschlagen: $error.');
  }
  if (!backup.isSuccess || backup.filePath == null || backup.sha256 == null) {
    return VerifiedPresetRead(
      slot: slot,
      backup: backup,
      blockedReason: 'Kein gültiges Backup: ${backup.errorMessage ?? backup.outcome.name}.',
    );
  }
  final RawPresetSnapshot snapshot;
  try {
    snapshot = decodeRawPresetBackupJson(await File(backup.filePath!).readAsString());
  } catch (error) {
    return VerifiedPresetRead(
      slot: slot,
      backup: backup,
      blockedReason: 'Backup-Datei konnte nicht erneut gelesen werden: $error.',
    );
  }
  if (snapshot.sha256 != backup.sha256) {
    return VerifiedPresetRead(slot: slot, backup: backup, blockedReason: 'Backup-Hash stimmt nicht überein.');
  }
  if (snapshot.presetNumber != expected || !snapshot.isUserBank) {
    return VerifiedPresetRead(
      slot: slot,
      backup: backup,
      snapshot: snapshot,
      blockedReason:
          'Nur User/$label ist angefordert '
          '(gelesen: ${!snapshot.isUserBank ? 'Factory' : MatriboxUserSlot.tryPreset(snapshot.presetNumber)?.label ?? 'Slot-Byte ${snapshot.slot}'}).',
    );
  }
  final MatriboxPresetLayoutModel layout;
  try {
    layout = MatriboxPresetLayout.decode(snapshot);
  } catch (error) {
    return VerifiedPresetRead(
      slot: slot,
      backup: backup,
      snapshot: snapshot,
      blockedReason: 'Preset-Layout nicht dekodierbar: $error.',
    );
  }
  return VerifiedPresetRead(slot: slot, backup: backup, snapshot: snapshot, layout: layout);
}
