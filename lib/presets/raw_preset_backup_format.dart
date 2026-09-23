/// JSON serialisation for [RawPresetSnapshot]. Deliberately a separate file
/// suffix (`.wyrmtone-raw-preset.json`) from `preset_backup.dart`'s
/// `.wyrmtone-backup.json`: the two are unrelated formats for unrelated
/// models (curated `CanonicalPreset` recommendations vs. a raw device
/// dump). Never route a raw snapshot through `PresetExportService`/
/// `PresetPrivacy` -- that filter explicitly rejects `bytes`/`rawMidi`/
/// `binary`-named fields, which is exactly what this format stores.
///
/// This file only encodes/decodes already-captured data; it never opens a
/// MIDI port, sends anything or touches a USB device. Decoding always
/// re-derives the snapshot from the raw bytes via
/// [RawPresetSnapshot.capture] and cross-checks the stored metadata against
/// that re-derivation -- stored values are never trusted blindly.
library;

import 'dart:convert';

import 'canonical_preset.dart' show canonicalJson, objectMap, requiredText;
import 'raw_preset_snapshot.dart';

const rawPresetBackupSchemaVersion = 1;
const rawPresetBackupFileSuffix = '.wyrmtone-raw-preset.json';

class RawPresetBackupFormatException implements Exception {
  const RawPresetBackupFormatException(this.message);
  final String message;
  @override
  String toString() => 'RawPresetBackupFormatException: $message';
}

String bytesToHex(List<int> bytes) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');

List<int> hexToBytes(String hex) {
  final tokens = hex.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
  final bytes = <int>[];
  for (final token in tokens) {
    if (!RegExp(r'^[0-9a-fA-F]{1,2}$').hasMatch(token)) {
      throw RawPresetBackupFormatException('Ungültiges Hex-Byte: "$token".');
    }
    bytes.add(int.parse(token, radix: 16));
  }
  return bytes;
}

/// Encodes [snapshot] as a plain JSON-compatible map. Raw bytes are encoded
/// as space-separated uppercase hex (never base64, matching the hex
/// convention already used throughout the protocol documentation/fixtures
/// for direct human diffability).
Map<String, Object?> encodeRawPresetBackup(RawPresetSnapshot snapshot) => {
  'formatVersion': rawPresetBackupSchemaVersion,
  'createdAt': snapshot.createdAt.toUtc().toIso8601String(),
  'device': snapshot.deviceLabel,
  'protocol': matriboxProtocolId,
  'bank': snapshot.bank,
  'slot': snapshot.slot,
  'presetNumber': snapshot.presetNumber,
  'presetName': snapshot.presetName,
  'decoderVersion': snapshot.decoderVersion,
  'phaseDResponseHex': snapshot.phaseDResponse == null
      ? null
      : bytesToHex(snapshot.phaseDResponse!),
  'rawPartsHex': snapshot.rawParts.map(bytesToHex).toList(),
  'decodedFields': snapshot.ampFields?.toJson(),
  'sha256': snapshot.sha256,
};

/// Pretty-printed, key-sorted JSON text for [snapshot] (reuses
/// canonical_preset.dart's `canonicalJson` for stable key ordering, exactly
/// as `PresetExportService`/`PresetBackupRepository` already do for the
/// unrelated `CanonicalPreset` format).
String encodeRawPresetBackupJson(RawPresetSnapshot snapshot) =>
    canonicalJson(encodeRawPresetBackup(snapshot), pretty: true);

/// Decodes and re-validates a raw preset backup. Never trusts the stored
/// `bank`/`slot`/`presetName`/`sha256` fields: it reconstructs a
/// [RawPresetSnapshot] from the embedded raw hex via
/// [RawPresetSnapshot.capture] (which re-runs every structural/order/
/// consistency check) and then requires every stored value to match the
/// re-derived one, so a hand-edited or corrupted file is rejected rather
/// than silently accepted.
RawPresetSnapshot decodeRawPresetBackup(Map<String, Object?> json) {
  if (json['formatVersion'] != rawPresetBackupSchemaVersion) {
    throw const RawPresetBackupFormatException(
      'Unbekannte oder fehlende formatVersion.',
    );
  }
  final deviceLabel = requiredText(json, 'device');
  final createdAt = DateTime.parse(requiredText(json, 'createdAt'));

  final rawPartsField = json['rawPartsHex'];
  if (rawPartsField is! List) {
    throw const RawPresetBackupFormatException('Fehlendes rawPartsHex-Feld.');
  }
  final rawParts = rawPartsField.map((entry) {
    if (entry is! String) {
      throw const RawPresetBackupFormatException(
        'rawPartsHex enthält kein Hex-String-Element.',
      );
    }
    return hexToBytes(entry);
  }).toList();

  final phaseDHex = json['phaseDResponseHex'];
  final List<int>? phaseDResponse;
  if (phaseDHex == null) {
    phaseDResponse = null;
  } else if (phaseDHex is String) {
    phaseDResponse = hexToBytes(phaseDHex);
  } else {
    throw const RawPresetBackupFormatException(
      'phaseDResponseHex ist kein Hex-String.',
    );
  }

  final snapshot = RawPresetSnapshot.capture(
    deviceLabel: deviceLabel,
    rawParts: rawParts,
    phaseDResponse: phaseDResponse,
    clock: () => createdAt,
  );

  if (json['bank'] != snapshot.bank || json['slot'] != snapshot.slot) {
    throw const RawPresetBackupFormatException(
      'Gespeicherte bank/slot stimmen nicht mit den Rohdaten überein.',
    );
  }
  if (json['presetName'] != snapshot.presetName) {
    throw const RawPresetBackupFormatException(
      'Gespeicherter presetName stimmt nicht mit den Rohdaten überein.',
    );
  }
  if (json['sha256'] != snapshot.sha256) {
    throw const RawPresetBackupFormatException(
      'Gespeicherter Hash stimmt nicht mit den Rohdaten überein '
      '(Manipulation oder Beschädigung).',
    );
  }
  return snapshot;
}

RawPresetSnapshot decodeRawPresetBackupJson(String text) =>
    decodeRawPresetBackup(objectMap(jsonDecode(text)));
