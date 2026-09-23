/// Shared "fresh, verified read" used by every productive flow:
/// READ -> BACKUP (saved) -> RELOAD -> HASH VERIFY -> USER/SLOT CHECK ->
/// SEMANTIC DECODE. The result always comes from the device just now; there
/// is no cache and no fixture in this path.
///
/// [readVerifiedP01] is the historical User P01 read of the certification
/// flows; [readVerifiedUserSlot] is the productive transfer's read of exactly
/// one product-writable slot (P11..P99).
library;

import 'dart:io';

import 'matribox_preset_layout.dart';
import 'matribox_raw_backup_service.dart';
import 'matribox_transfer_slots.dart';
import 'preset_selection_codec.dart' show MatriboxPresetSlotAddress;
import 'raw_preset_backup_format.dart';
import 'raw_preset_snapshot.dart';

class VerifiedPresetRead {
  const VerifiedPresetRead({this.slot, this.backup, this.snapshot, this.layout, this.blockedReason});

  /// The slot that was REQUESTED (null for the historical P01 read).
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

typedef VerifiedP01Read = VerifiedPresetRead;

Future<VerifiedPresetRead> readVerifiedP01(MatriboxRawBackupService backupService) =>
    _readVerified(backupService.backupUserP01, expected: 1, slot: null);

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
  final label = MatriboxPresetSlotAddress.fromPresetNumber(expected).label;
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
          '(gelesen: ${snapshot.isUserBank ? MatriboxPresetSlotAddress.fromPresetNumber(snapshot.presetNumber).label : 'Factory'}).',
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
