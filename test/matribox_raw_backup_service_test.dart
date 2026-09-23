import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_raw_backup_service.dart';
import 'package:wyrmtone/presets/raw_preset_backup_format.dart';

import 'support/matribox_p01_readback_fixtures.dart';

class _FakeChannel implements MatriboxPresetReadChannel {
  _FakeChannel(this.response);
  Map<Object?, Object?> response;
  var calls = 0;
  @override
  Future<Map<Object?, Object?>> readMatriboxUserP01() async {
    ++calls;
    return response;
  }
}

class _ThrowingChannel implements MatriboxPresetReadChannel {
  @override
  Future<Map<Object?, Object?>> readMatriboxUserP01() async {
    throw StateError('Plugin nicht verfügbar.');
  }
}

Map<Object?, Object?> _successResponse() => {
  'outcome': 'SUCCESS',
  'phaseDResponse': matriboxHex(matriboxPhaseDAcknowledgement),
  'parts': matriboxP01RealFullCycle.map(matriboxHex).toList(),
  'error': null,
};

void main() {
  late Directory tempDir;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('matribox_raw_backup_test');
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('MatriboxRawBackupService end-to-end (offline)', () {
    test(
      'READ -> SNAPSHOT -> SERIALIZE -> SAVE -> READ FILE -> DESERIALIZE -> '
      'VALIDATE -> HASH COMPARE succeeds for a complete fixture cycle',
      () async {
        final channel = _FakeChannel(_successResponse());
        final service = MatriboxRawBackupService(
          channel: channel,
          backupDirectory: tempDir,
          clock: () => DateTime.utc(2026, 9, 17),
        );

        final result = await service.backupUserP01();

        expect(result.outcome, MatriboxRawBackupOutcome.success);
        expect(result.presetName, 'CKY 96 STUD');
        expect(result.presetNumber, 1);
        expect(result.sha256, hasLength(64));
        expect(result.filePath, isNotNull);
        expect(result.filePath, endsWith(rawPresetBackupFileSuffix));
        expect(File(result.filePath!).existsSync(), isTrue);
        expect(channel.calls, 1);
      },
    );

    test('the saved file round-trips to byte-identical raw parts', () async {
      final channel = _FakeChannel(_successResponse());
      final service = MatriboxRawBackupService(
        channel: channel,
        backupDirectory: tempDir,
      );

      final result = await service.backupUserP01();
      final reloaded = decodeRawPresetBackupJson(
        File(result.filePath!).readAsStringSync(),
      );
      final expectedParts = matriboxP01RealFullCycle.map(matriboxHex).toList();
      expect(reloaded.rawParts.length, expectedParts.length);
      for (var i = 0; i < expectedParts.length; i++) {
        expect(reloaded.rawParts[i], expectedParts[i]);
      }
      expect(reloaded.sha256, result.sha256);
    });

    test('an identical second backup reuses the same content-addressed file', () async {
      final service = MatriboxRawBackupService(
        channel: _FakeChannel(_successResponse()),
        backupDirectory: tempDir,
      );
      final first = await service.backupUserP01();
      final second = await service.backupUserP01();
      expect(second.outcome, MatriboxRawBackupOutcome.success);
      expect(second.filePath, first.filePath);
      expect(tempDir.listSync().whereType<File>().length, 1);
    });

    for (final entry in {
      'PHASE_D_TIMEOUT': MatriboxRawBackupOutcome.phaseDTimeout,
      'PHASE_D_INVALID': MatriboxRawBackupOutcome.phaseDInvalid,
      'PART_TIMEOUT': MatriboxRawBackupOutcome.partTimeout,
      'PART_INVALID': MatriboxRawBackupOutcome.partInvalid,
      'INCOMPLETE': MatriboxRawBackupOutcome.incomplete,
      'TRANSPORT_ERROR': MatriboxRawBackupOutcome.transportError,
    }.entries) {
      test('native outcome ${entry.key} maps to ${entry.value} and writes no file', () async {
        final channel = _FakeChannel({
          'outcome': entry.key,
          'phaseDResponse': null,
          'parts': <Object?>[],
          'error': 'native message',
        });
        final service = MatriboxRawBackupService(
          channel: channel,
          backupDirectory: tempDir,
        );

        final result = await service.backupUserP01();

        expect(result.outcome, entry.value);
        expect(result.errorMessage, 'native message');
        expect(tempDir.listSync(), isEmpty);
      });
    }

    test('a channel exception maps to channelError and writes no file', () async {
      final service = MatriboxRawBackupService(
        channel: _ThrowingChannel(),
        backupDirectory: tempDir,
      );

      final result = await service.backupUserP01();

      expect(result.outcome, MatriboxRawBackupOutcome.channelError);
      expect(result.errorMessage, contains('Plugin nicht verfügbar'));
      expect(tempDir.listSync(), isEmpty);
    });

    test(
      'SUCCESS with fewer than ten parts is never treated as a valid '
      'backup, even though native claimed success',
      () async {
        final incompleteParts = matriboxP01RealFullCycle
            .map(matriboxHex)
            .toList()
          ..removeLast();
        final channel = _FakeChannel({
          'outcome': 'SUCCESS',
          'phaseDResponse': matriboxHex(matriboxPhaseDAcknowledgement),
          'parts': incompleteParts,
          'error': null,
        });
        final service = MatriboxRawBackupService(
          channel: channel,
          backupDirectory: tempDir,
        );

        final result = await service.backupUserP01();

        expect(result.outcome, MatriboxRawBackupOutcome.validationFailed);
        expect(tempDir.listSync(), isEmpty);
      },
    );

    test('a malformed parts field maps to validationFailed and writes no file', () async {
      final channel = _FakeChannel({
        'outcome': 'SUCCESS',
        'phaseDResponse': null,
        'parts': 'not a list',
        'error': null,
      });
      final service = MatriboxRawBackupService(
        channel: channel,
        backupDirectory: tempDir,
      );

      final result = await service.backupUserP01();

      expect(result.outcome, MatriboxRawBackupOutcome.validationFailed);
      expect(tempDir.listSync(), isEmpty);
    });

    test('an unrecognised outcome string maps to channelError', () async {
      final channel = _FakeChannel({
        'outcome': 'SOMETHING_NEW',
        'error': null,
      });
      final service = MatriboxRawBackupService(
        channel: channel,
        backupDirectory: tempDir,
      );

      final result = await service.backupUserP01();

      expect(result.outcome, MatriboxRawBackupOutcome.channelError);
    });
  });
}
