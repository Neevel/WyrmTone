/// Production, read-only backup pipeline for the Matribox User/P01 preset:
/// READ (native) -> SNAPSHOT -> SERIALIZE -> SAVE -> READ FILE ->
/// DESERIALIZE -> VALIDATE -> HASH COMPARE. A backup counts as successful
/// only once the file has been written, reloaded from disk and
/// re-validated -- never merely because a snapshot was captured or a file
/// was written. There is no restore/write path here: this pipeline only
/// ever produces a local, read-only backup file.
library;

import 'dart:io';

import 'matribox_transfer_slots.dart';
import 'raw_preset_backup_format.dart';
import 'raw_preset_snapshot.dart';

/// Mirrors the native `MatriboxPresetReadOutcome` enum
/// (android/app/src/main/kotlin/de/neevel/wyrmtone/MatriboxPresetReader.kt),
/// plus two Dart-side-only outcomes for failures that happen after the
/// native read itself succeeded (or couldn't be reached at all).
enum MatriboxRawBackupOutcome {
  success,
  phaseDTimeout,
  phaseDInvalid,
  partTimeout,
  partInvalid,
  incomplete,
  transportError,

  /// The platform channel call itself failed or returned an unrecognised
  /// shape (e.g. the plugin is unavailable).
  channelError,

  /// The native side reported SUCCESS, but the returned raw data failed
  /// [RawPresetSnapshot.capture]'s validation, or the just-written backup
  /// file failed to reload/re-validate. Never trusted at face value.
  validationFailed,
}

class MatriboxRawBackupResult {
  const MatriboxRawBackupResult({
    required this.outcome,
    this.presetName,
    this.presetNumber,
    this.sha256,
    this.filePath,
    this.createdAt,
    this.ampFields,
    this.errorMessage,
  });

  final MatriboxRawBackupOutcome outcome;
  final String? presetName;
  final int? presetNumber;
  final String? sha256;
  final String? filePath;
  final DateTime? createdAt;

  /// Only the known, evidence-backed AMP fields (gain/presence/volume/
  /// bass/middle/treble) for plain-language display -- never raw bytes.
  final Map<String, double>? ampFields;
  final String? errorMessage;

  bool get isSuccess => outcome == MatriboxRawBackupOutcome.success;
}

/// Abstracts the native platform-channel call so the pipeline below is
/// fully testable offline, without a MethodChannel or Flutter binding.
abstract interface class MatriboxPresetReadChannel {
  /// Returns the raw native result map: `outcome` (String), `phaseDResponse`
  /// (`List<int>?`), `parts` (`List<List<int>>`, only meaningful on
  /// SUCCESS), `error` (`String?`).
  Future<Map<Object?, Object?>> readMatriboxUserP01();
}

/// The productive transfer's read: the same native reader, addressed at ONE product-writable User
/// slot (P11..P99; the native side rejects anything else before sending). Same result map as
/// [MatriboxPresetReadChannel.readMatriboxUserP01].
abstract interface class MatriboxUserSlotReadChannel implements MatriboxPresetReadChannel {
  Future<Map<Object?, Object?>> readMatriboxUserSlot(int presetNumber);
}

MatriboxRawBackupOutcome _outcomeFromNative(Object? name) => switch (name) {
  'SUCCESS' => MatriboxRawBackupOutcome.success,
  'PHASE_D_TIMEOUT' => MatriboxRawBackupOutcome.phaseDTimeout,
  'PHASE_D_INVALID' => MatriboxRawBackupOutcome.phaseDInvalid,
  'PART_TIMEOUT' => MatriboxRawBackupOutcome.partTimeout,
  'PART_INVALID' => MatriboxRawBackupOutcome.partInvalid,
  'INCOMPLETE' => MatriboxRawBackupOutcome.incomplete,
  'TRANSPORT_ERROR' => MatriboxRawBackupOutcome.transportError,
  _ => MatriboxRawBackupOutcome.channelError,
};

class MatriboxRawBackupService {
  MatriboxRawBackupService({
    required this.channel,
    required this.backupDirectory,
    this.deviceLabel = 'Sonicake Matribox 1 84EF:0054',
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final MatriboxPresetReadChannel channel;
  final Directory backupDirectory;
  final String deviceLabel;
  final DateTime Function() clock;

  /// Runs the full READ -> SNAPSHOT -> SERIALIZE -> SAVE -> READ FILE ->
  /// DESERIALIZE -> VALIDATE -> HASH COMPARE pipeline for User/P01. Never
  /// throws: every failure mode is reported via [MatriboxRawBackupResult].
  Future<MatriboxRawBackupResult> backupUserP01() => _backup(channel.readMatriboxUserP01, null);

  /// The same pipeline for exactly [slot] (P11..P99 only). Fails closed -- without any read --
  /// for a protected slot or a channel without slot addressing, and rejects a snapshot whose own
  /// Bank/Slot bytes are not User/[slot]: a P11 backup can never contain another slot's data.
  Future<MatriboxRawBackupResult> backupUserSlot(MatriboxUserSlot slot) async {
    final rejection = MatriboxSlotPolicy.writeRejection(slot.presetNumber);
    if (rejection != null) {
      return MatriboxRawBackupResult(outcome: MatriboxRawBackupOutcome.channelError, errorMessage: rejection);
    }
    final slotChannel = channel;
    if (slotChannel is! MatriboxUserSlotReadChannel) {
      return const MatriboxRawBackupResult(
        outcome: MatriboxRawBackupOutcome.channelError,
        errorMessage: 'Dieser Lesekanal kann keinen Speicherplatz adressieren.',
      );
    }
    return _backup(() => slotChannel.readMatriboxUserSlot(slot.presetNumber), slot);
  }

  Future<MatriboxRawBackupResult> _backup(
    Future<Map<Object?, Object?>> Function() read,
    MatriboxUserSlot? expectedSlot,
  ) async {
    final Map<Object?, Object?> raw;
    try {
      raw = await read();
    } catch (error) {
      return MatriboxRawBackupResult(
        outcome: MatriboxRawBackupOutcome.channelError,
        errorMessage: '$error',
      );
    }

    final outcome = _outcomeFromNative(raw['outcome']);
    if (outcome != MatriboxRawBackupOutcome.success) {
      return MatriboxRawBackupResult(
        outcome: outcome,
        errorMessage:
            raw['error'] as String? ?? 'Lesevorgang fehlgeschlagen.',
      );
    }

    final RawPresetSnapshot snapshot;
    try {
      final partsField = raw['parts'];
      if (partsField is! List) {
        throw const InvalidRawPresetSnapshotException(
          'Native Antwort enthält keine Parts-Liste.',
        );
      }
      final rawParts = partsField.map((part) {
        if (part is! List) {
          throw const InvalidRawPresetSnapshotException(
            'Ein Part in der nativen Antwort ist keine Byteliste.',
          );
        }
        return part.cast<int>();
      }).toList();
      final phaseDField = raw['phaseDResponse'];
      final phaseDResponse = phaseDField == null
          ? null
          : (phaseDField as List).cast<int>();
      snapshot = RawPresetSnapshot.capture(
        deviceLabel: deviceLabel,
        rawParts: rawParts,
        phaseDResponse: phaseDResponse,
        clock: clock,
      );
      if (expectedSlot != null && (!snapshot.isUserBank || snapshot.presetNumber != expectedSlot.presetNumber)) {
        throw InvalidRawPresetSnapshotException(
          'Gerät lieferte ${snapshot.isUserBank ? 'P${snapshot.presetNumber.toString().padLeft(2, '0')}' : 'Factory'} '
          'statt ${expectedSlot.label}.',
        );
      }
    } catch (error) {
      // The native side reported SUCCESS but the payload does not hold up
      // to the same validation every other snapshot must pass. Never
      // written as a backup.
      return MatriboxRawBackupResult(
        outcome: MatriboxRawBackupOutcome.validationFailed,
        errorMessage: '$error',
      );
    }

    try {
      final file = await _saveIfAbsent(snapshot);
      final reloaded = decodeRawPresetBackupJson(await file.readAsString());
      if (reloaded.sha256 != snapshot.sha256) {
        return const MatriboxRawBackupResult(
          outcome: MatriboxRawBackupOutcome.validationFailed,
          errorMessage:
              'Hash der gespeicherten Sicherung stimmt nicht mit dem '
              'gelesenen Preset überein.',
        );
      }
      return MatriboxRawBackupResult(
        outcome: MatriboxRawBackupOutcome.success,
        presetName: reloaded.presetName,
        presetNumber: reloaded.presetNumber,
        sha256: reloaded.sha256,
        filePath: file.path,
        createdAt: reloaded.createdAt,
        ampFields: reloaded.ampFields?.toJson().map(
          (key, value) => MapEntry(key, (value as num).toDouble()),
        ),
      );
    } catch (error) {
      return MatriboxRawBackupResult(
        outcome: MatriboxRawBackupOutcome.validationFailed,
        errorMessage:
            'Sicherung konnte nicht gespeichert oder erneut gelesen/'
            'validiert werden: $error',
      );
    }
  }

  /// Content-addressed by [RawPresetSnapshot.sha256], mirroring
  /// `PresetBackupRepository`'s hash-derived filename and
  /// "never overwrite, an existing file wins" behaviour. Writes via a
  /// temporary file + rename so a crash mid-write never leaves a partial
  /// backup file behind.
  Future<File> _saveIfAbsent(RawPresetSnapshot snapshot) async {
    await backupDirectory.create(recursive: true);
    final file = File(
      '${backupDirectory.path}/${snapshot.sha256}$rawPresetBackupFileSuffix',
    );
    if (await file.exists()) return file;
    final temporary = File(
      '${file.path}.${clock().microsecondsSinceEpoch}.tmp',
    );
    await temporary.create(exclusive: true);
    await temporary.writeAsString(
      encodeRawPresetBackupJson(snapshot),
      flush: true,
    );
    if (await file.exists()) {
      await temporary.delete();
      return file;
    }
    await temporary.rename(file.path);
    return file;
  }
}
