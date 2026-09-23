import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/raw_preset_backup_format.dart';
import 'package:wyrmtone/presets/raw_preset_snapshot.dart';

import 'support/matribox_p01_readback_fixtures.dart';

void main() {
  List<List<int>> realParts() =>
      matriboxP01RealFullCycle.map(matriboxHex).toList();

  RawPresetSnapshot realSnapshot() => RawPresetSnapshot.capture(
    deviceLabel: 'Sonicake Matribox 1 84EF:0054',
    rawParts: realParts(),
    phaseDResponse: matriboxHex(matriboxPhaseDAcknowledgement),
    clock: () => DateTime.utc(2026, 9, 15, 12, 0, 0),
  );

  group('raw preset backup JSON', () {
    test('round-trips losslessly', () {
      final original = realSnapshot();
      final json = encodeRawPresetBackupJson(original);
      final decoded = decodeRawPresetBackupJson(json);

      expect(decoded.deviceLabel, original.deviceLabel);
      expect(decoded.bank, original.bank);
      expect(decoded.slot, original.slot);
      expect(decoded.presetName, original.presetName);
      expect(decoded.createdAt, original.createdAt);
      expect(decoded.phaseDResponse, original.phaseDResponse);
      expect(decoded.rawParts.length, original.rawParts.length);
      for (var i = 0; i < original.rawParts.length; i++) {
        expect(decoded.rawParts[i], original.rawParts[i]);
      }
      expect(decoded.ampFields?.toJson(), original.ampFields?.toJson());
      expect(decoded.sha256, original.sha256);
    });

    test('encodes raw bytes as space-separated uppercase hex', () {
      final map = encodeRawPresetBackup(realSnapshot());
      final rawPartsHex = map['rawPartsHex'] as List<Object?>;
      expect(rawPartsHex.first, matches(RegExp(r'^[0-9A-F]{2}( [0-9A-F]{2})*$')));
      expect((rawPartsHex.first as String).startsWith('F0 21 25 7F'), isTrue);
    });

    test('contains formatVersion, decoderVersion and sha256 fields', () {
      final map = encodeRawPresetBackup(realSnapshot());
      expect(map['formatVersion'], rawPresetBackupSchemaVersion);
      expect(map['decoderVersion'], rawPresetDecoderVersion);
      expect(map['sha256'], hasLength(64));
    });

    test('rejects a file with a tampered sha256', () {
      final map = encodeRawPresetBackup(realSnapshot());
      map['sha256'] = '0' * 64;
      expect(
        () => decodeRawPresetBackup(map),
        throwsA(isA<RawPresetBackupFormatException>()),
      );
    });

    test('rejects a file whose raw bytes were edited without updating the hash', () {
      final map = encodeRawPresetBackup(realSnapshot());
      final rawPartsHex = List<Object?>.from(map['rawPartsHex'] as List);
      // Flip one payload byte (token index 100, well past the 17-byte
      // header of part 1) so the message stays structurally a valid QME2
      // readback part -- this must be caught by the sha256 check, not by
      // RawPresetSnapshot.capture's structural validation.
      final tokens = (rawPartsHex[1] as String).split(' ');
      final original = int.parse(tokens[100], radix: 16);
      tokens[100] = (original ^ 0x01).toRadixString(16).padLeft(2, '0').toUpperCase();
      rawPartsHex[1] = tokens.join(' ');
      map['rawPartsHex'] = rawPartsHex;
      expect(
        () => decodeRawPresetBackup(map),
        throwsA(isA<RawPresetBackupFormatException>()),
      );
    });

    test('rejects an unknown formatVersion', () {
      final map = encodeRawPresetBackup(realSnapshot());
      map['formatVersion'] = 999;
      expect(
        () => decodeRawPresetBackup(map),
        throwsA(isA<RawPresetBackupFormatException>()),
      );
    });

    test('rejects a file with a stored presetName not matching the raw bytes', () {
      final map = encodeRawPresetBackup(realSnapshot());
      map['presetName'] = 'SOMETHING ELSE';
      expect(
        () => decodeRawPresetBackup(map),
        throwsA(isA<RawPresetBackupFormatException>()),
      );
    });

    test('an incomplete read (fewer than ten parts) is never encodable as a valid backup', () {
      // The backup format has no path to construct a RawPresetSnapshot
      // except via RawPresetSnapshot.capture, so this is enforced once, at
      // the model level -- verified here for the specific case of a
      // truncated raw-parts list surviving into JSON round-tripping.
      final parts = realParts()..removeLast();
      expect(
        () => RawPresetSnapshot.capture(
          deviceLabel: 'Sonicake Matribox 1 84EF:0054',
          rawParts: parts,
        ),
        throwsA(isA<InvalidRawPresetSnapshotException>()),
      );
    });

    test('produced JSON is valid, parseable JSON text', () {
      final text = encodeRawPresetBackupJson(realSnapshot());
      expect(() => jsonDecode(text), returnsNormally);
    });
  });
}
