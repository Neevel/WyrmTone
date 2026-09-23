import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_full_live_plan.dart';
import 'package:wyrmtone/presets/matribox_full_live_session.dart';
import 'package:wyrmtone/presets/matribox_raw_backup_service.dart';

import 'support/matribox_big_capture_snapshots.dart';
import 'support/matribox_full_live_helpers.dart';
import 'support/matribox_tone_transfer_support.dart';

class _RunChannel implements MatriboxFullLiveChannel {
  _RunChannel({this.completed, this.failAt, this.outcome = 'SUCCESS'});
  final int? completed;
  final int? failAt;
  final String outcome;
  bool throws = false;
  final planIds = <String>[];
  @override
  Future<Map<Object?, Object?>> runFullLiveP01Certification(String planId) async {
    planIds.add(planId);
    if (throws) throw StateError('FULL_LIVE_FAILED');
    final ops = MatriboxFullLivePlan.operations;
    final done = completed ?? (failAt ?? ops.length);
    return {
      'outcome': outcome,
      'error': failAt == null ? null : 'Transport-Fehler.',
      'total': ops.length,
      'completed': done,
      'failedIndex': failAt,
      'operations': [
        for (var i = 0; i < ops.length; i++)
          {
            'index': i,
            'label': ops[i].label,
            'status': i < done ? 'SENT' : (i == failAt ? 'FAILED' : 'NOT_SENT'),
          },
      ],
    };
  }
}

void main() {
  late Directory tempDir;
  late MatriboxFullLiveStore store;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('matribox_full_live_test');
    store = MatriboxFullLiveStore(File('${tempDir.path}/full_live.state'));
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  MatriboxRawBackupService service(ToneReadChannel channel) =>
      MatriboxRawBackupService(channel: channel, backupDirectory: tempDir);

  Future<FullLiveSessionResult> ready() =>
      MatriboxFullLiveSession(backupService: service(ToneReadChannel(hexParts(bigBeforeRawPartsHex)))).prepare();

  group('prepare', () {
    test('real P01 read: backup verified, hash checked, plan suits the original preset', () async {
      final result = await ready();
      expect(result.readyForFullLiveTest, isTrue, reason: '${result.blockedReason}');
      expect(result.current!.name, 'CKY 96 STUD');
      expect(result.backup!.sha256, isNotNull);
    });

    test('a P01 that already holds the target state is refused with the restore hint', () async {
      final result = await MatriboxFullLiveSession(
        backupService: service(ToneReadChannel(hexParts(bigAfterRawPartsHex))),
      ).prepare();
      expect(result.readyForFullLiveTest, isFalse);
      expect(result.blockedReason, contains('P01_BEFORE_BIG_CAPTURE.prst'));
    });

    test('a failed read blocks (no backup, nothing ready)', () async {
      final channel = ToneReadChannel(hexParts(bigBeforeRawPartsHex))..fail = true;
      final result = await MatriboxFullLiveSession(backupService: service(channel)).prepare();
      expect(result.readyForFullLiveTest, isFalse);
      expect(result.blockedReason, contains('Kein gültiges Backup'));
    });

    test('Factory bank or another slot is blocked', () async {
      for (final mutate in <void Function(List<int>)>[(p) => p[13] = 0x01, (p) => p[14] = 0x09]) {
        final parts = hexParts(bigBeforeRawPartsHex);
        parts.forEach(mutate);
        final result = await MatriboxFullLiveSession(backupService: service(ToneReadChannel(parts))).prepare();
        expect(result.readyForFullLiveTest, isFalse);
      }
    });
  });

  group('executor', () {
    test('one channel call with the plan id only; the record keeps the BEFORE backup', () async {
      final channel = _RunChannel();
      final result = await MatriboxFullLiveExecutor(channel: channel, store: store).execute(await ready());
      expect(result.isSuccess, isTrue);
      expect(channel.planIds, [MatriboxFullLivePlan.planId]);
      expect((result.completed, result.total), (25, 25));
      expect(result.recordSaved, isTrue);
      final record = (await store.load())!;
      expect(record.planId, MatriboxFullLivePlan.planId);
      expect(record.state, FullLiveRecordState.sent);
      expect(File(record.beforeBackupPath).existsSync(), isTrue);
    });

    test('a blocked session never reaches the channel', () async {
      final blocked = await MatriboxFullLiveSession(
        backupService: service(ToneReadChannel(hexParts(bigAfterRawPartsHex))),
      ).prepare();
      final channel = _RunChannel();
      final result = await MatriboxFullLiveExecutor(channel: channel, store: store).execute(blocked);
      expect(result.outcome, FullLiveRunOutcome.safetyRejected);
      expect(channel.planIds, isEmpty);
    });

    test('a ready-looking session whose current state does not suit the plan is rejected anyway', () async {
      final good = await ready();
      final afterLayout = (await MatriboxFullLiveSession(
        backupService: service(ToneReadChannel(hexParts(bigAfterRawPartsHex))),
      ).prepare()).current!;
      final tampered = FullLiveSessionResult(
        stage: FullLiveSessionStage.readyForConfirmation,
        backup: good.backup,
        current: afterLayout,
      );
      final channel = _RunChannel();
      final result = await MatriboxFullLiveExecutor(channel: channel, store: store).execute(tampered);
      expect(result.outcome, FullLiveRunOutcome.safetyRejected);
      expect(channel.planIds, isEmpty);
    });

    test('first failure: reports completed / failed / NOT sent and still keeps the record, no retry', () async {
      final channel = _RunChannel(failAt: 7, outcome: 'SEND_FAILED');
      final result = await MatriboxFullLiveExecutor(channel: channel, store: store).execute(await ready());
      expect(result.isSuccess, isFalse);
      expect(channel.planIds, hasLength(1)); // no retry
      expect((result.completed, result.failedIndex), (7, 7));
      expect(result.notSent, hasLength(17));
      expect(result.operations[7].status, 'FAILED');
      expect(result.recordSaved, isTrue);
      expect((await store.load())!.completed, 7);
    });

    test('nothing sent -> no record; channel exception -> channelError, no record', () async {
      for (final channel in [
        _RunChannel(completed: 0, outcome: 'SAFETY_REJECTED'),
        _RunChannel()..throws = true,
      ]) {
        final result = await MatriboxFullLiveExecutor(channel: channel, store: store).execute(await ready());
        expect(result.isSuccess, isFalse);
        expect(result.recordSaved, isFalse);
        expect(await store.load(), isNull);
        expect(channel.planIds, hasLength(1));
      }
    });
  });

  group('readback', () {
    Future<MatriboxFullLiveRecord> sent() async {
      await MatriboxFullLiveExecutor(channel: _RunChannel(), store: store).execute(await ready());
      return (await store.load())!;
    }

    Future<FullLiveReadbackResult> readback(MatriboxFullLiveRecord record, List<List<int>> parts) =>
        MatriboxFullLiveReadback.run(record: record, backupService: service(ToneReadChannel(parts)), store: store);

    test('the state the plan produces is CERTIFIED and stored', () async {
      final result = await readback(await sent(), afterFromPlan());
      expect(result.outcome, FullLiveReadbackOutcome.certified, reason: '${result.detail}');
      expect((await store.load())!.state, FullLiveRecordState.readbackDone);
      expect((await store.load())!.readbackOutcome, 'certified');
    });

    test('unchanged device -> EXPECTED_CHANGE_MISSING; extra known/unknown changes are reported', () async {
      final record = await sent();
      expect((await readback(record, hexParts(bigBeforeRawPartsHex))).outcome, FullLiveReadbackOutcome.expectedChangeMissing);

      final known = afterFromPlan();
      setDecoded(known, 626, u16(99)); // BPM
      expect((await readback(record, known)).outcome, FullLiveReadbackOutcome.unexpectedKnownChange);

      final unknown = afterFromPlan();
      setDecoded(unknown, 700, [0x55]);
      expect((await readback(record, unknown)).outcome, FullLiveReadbackOutcome.unknownRawChange);
    });

    test('transport failure -> READ_FAILED, record stays SENT; tampered BEFORE backup -> BACKUP_MISMATCH', () async {
      final record = await sent();
      final failing = ToneReadChannel(afterFromPlan())..fail = true;
      final failed = await MatriboxFullLiveReadback.run(record: record, backupService: service(failing), store: store);
      expect(failed.outcome, FullLiveReadbackOutcome.readFailed);
      expect((await store.load())!.state, FullLiveRecordState.sent);

      await File(record.beforeBackupPath).writeAsString('{"tampered": true}');
      expect((await readback(record, afterFromPlan())).outcome, FullLiveReadbackOutcome.backupMismatch);
    });
  });
}
