import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_amp_certification.dart';
import 'package:wyrmtone/presets/matribox_amp_certification_session.dart';
import 'package:wyrmtone/presets/matribox_raw_backup_service.dart';

import 'support/matribox_p01_readback_fixtures.dart';
import 'support/matribox_tone_transfer_support.dart';

class _WriteChannel implements MatriboxCertificationWriteChannel {
  _WriteChannel([this.response = const {'outcome': 'SUCCESS', 'error': null}]);
  Map<Object?, Object?> response;
  bool throws = false;
  final calls = <(String, double)>[];
  @override
  Future<Map<Object?, Object?>> writeCertificationAmpField(String field, double targetValue) async {
    calls.add((field, targetValue));
    if (throws) throw StateError('GAIN_WRITE_FAILED');
    return response;
  }
}

List<List<int>> _realParts() => matriboxP01RealFullCycle.map(matriboxHex).toList();

void _setFloatAt(List<int> part, int rawStart, double value) {
  final data = ByteData(4)..setFloat32(0, value, Endian.little);
  for (var i = 0; i < 4; i++) {
    final byte = data.getUint8(i);
    part[rawStart + i * 2] = byte >> 4;
    part[rawStart + i * 2 + 1] = byte & 0x0f;
  }
}

// Raw windows of the confirmed AMP fields (see matribox_write_verification.dart).
const _windows = {
  MatriboxSol100OdAmpField.gain: (1, 201),
  MatriboxSol100OdAmpField.presence: (2, 17),
  MatriboxSol100OdAmpField.volume: (2, 25),
  MatriboxSol100OdAmpField.bass: (2, 33),
  MatriboxSol100OdAmpField.middle: (2, 41),
  MatriboxSol100OdAmpField.treble: (2, 49),
};

void main() {
  late Directory tempDir;
  late MatriboxCertificationStore store;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('matribox_certification_test');
    store = MatriboxCertificationStore(File('${tempDir.path}/state.json'));
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  MatriboxRawBackupService service(MatriboxPresetReadChannel channel) =>
      MatriboxRawBackupService(channel: channel, backupDirectory: tempDir);

  MatriboxCertificationRecord record(
    MatriboxSol100OdAmpField field,
    MatriboxCertificationRecordState state,
  ) => MatriboxCertificationRecord(
    field: field,
    state: state,
    beforeValue: 1,
    targetValue: 2,
    beforeBackupPath: 'x',
    beforeBackupSha256: 'y',
    writeSentAt: DateTime.utc(2026),
  );

  group('eligibility and order', () {
    test('Gain is certified and never re-tested; Presence is the first eligible field', () {
      expect(MatriboxCertification.statusFor(MatriboxSol100OdAmpField.gain, const []),
          MatriboxCertificationStatus.certified);
      expect(MatriboxCertification.blockReason(MatriboxSol100OdAmpField.gain, const []), isNotNull);
      expect(MatriboxCertification.blockReason(MatriboxSol100OdAmpField.presence, const []), isNull);
      expect(MatriboxCertification.statusFor(MatriboxSol100OdAmpField.presence, const []),
          MatriboxCertificationStatus.readyForHardwareTest);
    });

    test('wrong order is blocked until the previous field is CERTIFIED', () {
      for (final field in matriboxCertificationOrder.skip(1)) {
        expect(MatriboxCertification.blockReason(field, const []), contains('Reihenfolge'), reason: field.wireName);
      }
      final records = [record(MatriboxSol100OdAmpField.presence, MatriboxCertificationRecordState.certified)];
      expect(MatriboxCertification.blockReason(MatriboxSol100OdAmpField.volume, records), isNull);
      expect(MatriboxCertification.blockReason(MatriboxSol100OdAmpField.bass, records), isNotNull);
    });

    test('WRITE_SENT is not certified and blocks both retry and the next field', () {
      final records = [record(MatriboxSol100OdAmpField.presence, MatriboxCertificationRecordState.writeSent)];
      expect(MatriboxCertification.statusFor(MatriboxSol100OdAmpField.presence, records),
          MatriboxCertificationStatus.writeSentAwaitingReadback);
      expect(MatriboxCertification.blockReason(MatriboxSol100OdAmpField.presence, records), isNotNull);
      expect(MatriboxCertification.blockReason(MatriboxSol100OdAmpField.volume, records), isNotNull);
    });

    test('a failed readback stays uncertified and blocks the next field', () {
      final records = [record(MatriboxSol100OdAmpField.presence, MatriboxCertificationRecordState.readbackFailed)];
      expect(MatriboxCertification.statusFor(MatriboxSol100OdAmpField.presence, records),
          MatriboxCertificationStatus.readbackFailed);
      expect(MatriboxCertification.blockReason(MatriboxSol100OdAmpField.volume, records), isNotNull);
    });

    test('certification never changes the static evidence registry', () {
      for (final field in matriboxCertificationOrder) {
        expect(field.evidence.hardwareWritable, isFalse, reason: field.wireName);
        expect(field.evidence.encodable, isTrue, reason: field.wireName);
      }
    });

    test('the closed field type maps wire names to confirmed indices and nothing else', () {
      expect(MatriboxSol100OdAmpField.values.map((f) => f.parameterIndex), [0, 1, 2, 3, 4, 5]);
      expect(MatriboxSol100OdAmpField.fromWireName('reverb'), isNull);
      expect(MatriboxSol100OdAmpField.fromWireName('Presence'), isNull);
    });
  });

  test('target is current+1, or current-1 at 99, always within 0..99', () {
    expect(MatriboxCertificationTarget.targetFor(73), 74);
    expect(MatriboxCertificationTarget.targetFor(0), 1);
    expect(MatriboxCertificationTarget.targetFor(98), 99);
    expect(MatriboxCertificationTarget.targetFor(99), 98);
  });

  test('store round-trips records and ignores corrupt files', () async {
    expect(await store.load(), isEmpty);
    await store.save(record(MatriboxSol100OdAmpField.presence, MatriboxCertificationRecordState.writeSent));
    await store.save(record(MatriboxSol100OdAmpField.presence, MatriboxCertificationRecordState.certified));
    final loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.state, MatriboxCertificationRecordState.certified);
    await store.file.writeAsString('{not json');
    expect(await store.load(), isEmpty);
  });

  group('session.prepare', () {
    test('Presence: backup verified, exactly one 73 -> 74 change on User/P01 / Sol 100 OD', () async {
      final channel = ToneReadChannel(_realParts());
      final result = await MatriboxCertificationSession(
        backupService: service(channel),
        records: const [],
      ).prepare(MatriboxSol100OdAmpField.presence);
      expect(result.readyForCertificationWrite, isTrue, reason: '${result.blockedReason}');
      expect(result.currentValue, 73);
      expect(result.targetValue, 74);
      expect(result.diff!.ampChanges.map((c) => c.field), ['presence']);
      expect(result.currentPreset!.amp!.algorithmName, 'Sol 100 OD');
    });

    test('wrong order / Gain are blocked BEFORE any read', () async {
      final channel = ToneReadChannel(_realParts());
      final session = MatriboxCertificationSession(backupService: service(channel), records: const []);
      for (final field in [MatriboxSol100OdAmpField.volume, MatriboxSol100OdAmpField.gain]) {
        final result = await session.prepare(field);
        expect(result.readyForCertificationWrite, isFalse);
        expect(result.blockedReason, isNotNull);
      }
      expect(channel.reads, 0);
    });

    test('Factory bank, wrong slot and an unknown/non-Sol100OD preset are blocked', () async {
      final factory = _realParts();
      for (final part in factory) {
        part[13] = 0x01;
      }
      final otherSlot = _realParts();
      for (final part in otherSlot) {
        part[14] = 0x09; // P10
      }
      for (final parts in [factory, otherSlot]) {
        final result = await MatriboxCertificationSession(
          backupService: service(ToneReadChannel(parts)),
          records: const [],
        ).prepare(MatriboxSol100OdAmpField.presence);
        expect(result.readyForCertificationWrite, isFalse);
        expect(result.blockedReason, contains('User/P01'));
      }
    });

    test('a failed read blocks; nothing is ready', () async {
      final channel = ToneReadChannel(_realParts())..fail = true;
      final result = await MatriboxCertificationSession(backupService: service(channel), records: const [])
          .prepare(MatriboxSol100OdAmpField.presence);
      expect(result.readyForCertificationWrite, isFalse);
      expect(result.blockedReason, contains('Kein gültiges Backup'));
    });
  });

  group('executor', () {
    Future<MatriboxCertificationSessionResult> ready() =>
        MatriboxCertificationSession(backupService: service(ToneReadChannel(_realParts())), records: const [])
            .prepare(MatriboxSol100OdAmpField.presence);

    test('sends exactly one write with field + target only and persists WRITE_SENT', () async {
      final write = _WriteChannel();
      final result = await MatriboxCertificationExecutor(channel: write, store: store, records: const [])
          .execute(await ready());
      expect(result.isSuccess, isTrue);
      expect(result.recordSaved, isTrue);
      expect(write.calls, [('presence', 74.0)]);
      final saved = (await store.load()).single;
      expect(saved.state, MatriboxCertificationRecordState.writeSent);
      expect(MatriboxCertification.statusFor(MatriboxSol100OdAmpField.presence, [saved]),
          MatriboxCertificationStatus.writeSentAwaitingReadback);
    });

    test('a blocked session never reaches the channel', () async {
      final write = _WriteChannel();
      final blocked = await MatriboxCertificationSession(
        backupService: service(ToneReadChannel(_realParts())..fail = true),
        records: const [],
      ).prepare(MatriboxSol100OdAmpField.presence);
      final result = await MatriboxCertificationExecutor(channel: write, store: store, records: const [])
          .execute(blocked);
      expect(result.outcome, MatriboxCertificationWriteOutcome.safetyRejected);
      expect(write.calls, isEmpty);
    });

    test('wrong order at execution time is rejected without a send', () async {
      final write = _WriteChannel();
      final session = await ready();
      final result = await MatriboxCertificationExecutor(
        channel: write,
        store: store,
        records: [record(MatriboxSol100OdAmpField.presence, MatriboxCertificationRecordState.writeSent)],
      ).execute(session);
      expect(result.outcome, MatriboxCertificationWriteOutcome.safetyRejected);
      expect(write.calls, isEmpty);
    });

    test('an invalid (non +/-1 or out-of-range) target is rejected without a send', () async {
      final write = _WriteChannel();
      final good = await ready();
      for (final target in [80.0, 100.0, -1.0]) {
        final result = await MatriboxCertificationExecutor(channel: write, store: store, records: const [])
            .execute(MatriboxCertificationSessionResult(
              stage: MatriboxCertificationSessionStage.readyForConfirmation,
              field: MatriboxSol100OdAmpField.presence,
              backup: good.backup,
              diff: good.diff,
              currentValue: 73,
              targetValue: target,
            ));
        expect(result.outcome, MatriboxCertificationWriteOutcome.safetyRejected, reason: '$target');
      }
      expect(write.calls, isEmpty);
    });

    test('native failure or channel exception never yields success or a record', () async {
      for (final channel in [
        _WriteChannel({'outcome': 'SEND_FAILED', 'error': 'x'}),
        _WriteChannel({'outcome': 'SAFETY_REJECTED', 'error': 'x'}),
        _WriteChannel()..throws = true,
      ]) {
        final result = await MatriboxCertificationExecutor(channel: channel, store: store, records: const [])
            .execute(await ready());
        expect(result.isSuccess, isFalse);
        expect(channel.calls, hasLength(1)); // no retry
        expect(await store.load(), isEmpty);
      }
    });
  });

  group('readback certification', () {
    // Writes a BEFORE backup + WRITE_SENT record for [field], then returns
    // the record. The BEFORE state is the real P01 fixture.
    Future<MatriboxCertificationRecord> sentRecord(MatriboxSol100OdAmpField field) async {
      final session = await MatriboxCertificationSession(
        backupService: service(ToneReadChannel(_realParts())),
        records: [
          for (final earlier in matriboxCertificationOrder.takeWhile((f) => f != field))
            record(earlier, MatriboxCertificationRecordState.certified),
        ],
      ).prepare(field);
      expect(session.readyForCertificationWrite, isTrue, reason: '${session.blockedReason}');
      await MatriboxCertificationExecutor(
        channel: _WriteChannel(),
        store: store,
        records: [
          for (final earlier in matriboxCertificationOrder.takeWhile((f) => f != field))
            record(earlier, MatriboxCertificationRecordState.certified),
        ],
      ).execute(session);
      return (await store.load()).singleWhere((r) => r.field == field);
    }

    Future<MatriboxCertificationReadbackResult> readback(
      MatriboxCertificationRecord record,
      List<List<int>> afterParts,
    ) => MatriboxCertificationReadback.run(record: record, backupService: service(ToneReadChannel(afterParts)), store: store);

    for (final field in matriboxCertificationOrder) {
      test('${field.wireName}: expected change only -> CERTIFIED', () async {
        final sent = await sentRecord(field);
        final after = _realParts();
        final window = _windows[field]!;
        _setFloatAt(after[window.$1], window.$2, sent.targetValue);
        final result = await readback(sent, after);
        expect(result.outcome, MatriboxCertificationReadbackOutcome.certified, reason: '${result.detail}');
        final stored = (await store.load()).singleWhere((r) => r.field == field);
        expect(stored.state, MatriboxCertificationRecordState.certified);
      });
    }

    test('expected change plus the known part-8 side effect -> CERTIFIED with a note', () async {
      final sent = await sentRecord(MatriboxSol100OdAmpField.presence);
      final after = _realParts();
      _setFloatAt(after[2], 17, sent.targetValue);
      for (var i = 37; i < 45; i++) {
        after[8][i] = (after[8][i] + 1) & 0x0f;
      }
      final result = await readback(sent, after);
      expect(result.outcome, MatriboxCertificationReadbackOutcome.certified);
      expect(result.detail, contains('Part-8'));
    });

    test('missing change -> EXPECTED_CHANGE_MISSING, stays uncertified', () async {
      final sent = await sentRecord(MatriboxSol100OdAmpField.presence);
      final result = await readback(sent, _realParts());
      expect(result.outcome, MatriboxCertificationReadbackOutcome.expectedChangeMissing);
      expect((await store.load()).single.state, MatriboxCertificationRecordState.readbackFailed);
    });

    test('a different value than the target -> EXPECTED_CHANGE_MISSING', () async {
      final sent = await sentRecord(MatriboxSol100OdAmpField.presence);
      final after = _realParts();
      _setFloatAt(after[2], 17, sent.targetValue + 5);
      final result = await readback(sent, after);
      expect(result.outcome, MatriboxCertificationReadbackOutcome.expectedChangeMissing);
    });

    test('another known field changed too -> UNEXPECTED_KNOWN_CHANGE', () async {
      final sent = await sentRecord(MatriboxSol100OdAmpField.presence);
      final after = _realParts();
      _setFloatAt(after[2], 17, sent.targetValue);
      _setFloatAt(after[1], 201, 60); // gain
      final result = await readback(sent, after);
      expect(result.outcome, MatriboxCertificationReadbackOutcome.unexpectedKnownChange);
    });

    test('an unknown raw byte changed -> UNKNOWN_RAW_CHANGE', () async {
      final sent = await sentRecord(MatriboxSol100OdAmpField.presence);
      final after = _realParts();
      _setFloatAt(after[2], 17, sent.targetValue);
      after[3][100] = after[3][100] == 0 ? 1 : 0;
      final result = await readback(sent, after);
      expect(result.outcome, MatriboxCertificationReadbackOutcome.unknownRawChange);
      expect((await store.load()).single.state, MatriboxCertificationRecordState.readbackFailed);
    });

    test('transport failure -> READ_FAILED and the record stays WRITE_SENT', () async {
      final sent = await sentRecord(MatriboxSol100OdAmpField.presence);
      final channel = ToneReadChannel(_realParts())..fail = true;
      final result = await MatriboxCertificationReadback.run(record: sent, backupService: service(channel), store: store);
      expect(result.outcome, MatriboxCertificationReadbackOutcome.readFailed);
      expect((await store.load()).single.state, MatriboxCertificationRecordState.writeSent);
    });

    test('a BEFORE backup that no longer matches its hash -> BACKUP_MISMATCH', () async {
      final sent = await sentRecord(MatriboxSol100OdAmpField.presence);
      await File(sent.beforeBackupPath).writeAsString('{"tampered": true}');
      final result = await readback(sent, _realParts());
      expect(result.outcome, MatriboxCertificationReadbackOutcome.backupMismatch);
    });
  });
}
