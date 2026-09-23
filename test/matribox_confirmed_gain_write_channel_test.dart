import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_confirmed_gain_write_channel.dart';
import 'package:wyrmtone/presets/matribox_preset_diff.dart';
import 'package:wyrmtone/presets/matribox_preset_write_plan.dart';
import 'package:wyrmtone/presets/matribox_safe_write_session.dart';
import 'package:wyrmtone/presets/preset_selection_codec.dart';
import 'package:wyrmtone/presets/protocol_evidence.dart';

class _FakeChannel implements MatriboxConfirmedGainWriteChannel {
  _FakeChannel(this.response);
  Map<Object?, Object?> response;
  var calls = <double>[];
  @override
  Future<Map<Object?, Object?>> writeConfirmedSol100OdGain(double targetGain) async {
    calls.add(targetGain);
    return response;
  }
}

class _ThrowingChannel implements MatriboxConfirmedGainWriteChannel {
  @override
  Future<Map<Object?, Object?>> writeConfirmedSol100OdGain(double targetGain) async {
    throw StateError('Kanal nicht verfügbar.');
  }
}

MatriboxPresetWritePlan _planWith({
  List<MatriboxPresetWriteOperation> operations = const [],
  int presetNumber = 1,
}) => MatriboxPresetWritePlan(
  targetAddress: MatriboxPresetSlotAddress.fromPresetNumber(presetNumber),
  backupSha256: 'abc',
  operations: operations,
  gate: operations.length == 1 && operations.single.writable
      ? MatriboxWritePlanGate.readyForHardwareTest
      : MatriboxWritePlanGate.blocked,
  blockers: const [],
);

const _writableGainOp = MatriboxPresetWriteOperation(
  field: 'gain',
  currentValue: 17,
  targetValue: 18,
  evidence: EvidenceLevel.confirmed,
  status: MatriboxWriteOperationStatus.writable,
  reason: 'WRITABLE',
  catalogIndex: 0,
  algorithmCode: 0x07000047,
);

MatriboxSafeWriteSessionResult _resultWith(MatriboxPresetWritePlan plan) =>
    MatriboxSafeWriteSessionResult(
      stage: MatriboxSafeWriteSessionStage.readyForConfirmation,
      plan: plan,
      diff: const MatriboxPresetDiff(nameBefore: 'CKY 96 STUD', nameAfter: 'Lab', ampChanges: []),
    );

void main() {
  group('MatriboxSafeWriteExecutor.executeGainWrite', () {
    test('a ready, single Gain-writable plan sends exactly once with the target value', () async {
      final channel = _FakeChannel({'outcome': 'SUCCESS', 'error': null});
      final executor = MatriboxSafeWriteExecutor(channel);

      final result = await executor.executeGainWrite(
        _resultWith(_planWith(operations: const [_writableGainOp])),
      );

      expect(result.isSuccess, isTrue);
      expect(result.targetValue, 18.0);
      expect(channel.calls, [18.0]);
    });

    test('a blocked session never calls the channel', () async {
      final channel = _FakeChannel({'outcome': 'SUCCESS', 'error': null});
      final executor = MatriboxSafeWriteExecutor(channel);

      final result = await executor.executeGainWrite(
        const MatriboxSafeWriteSessionResult(stage: MatriboxSafeWriteSessionStage.blocked),
      );

      expect(result.outcome, MatriboxGainWriteOutcome.safetyRejected);
      expect(channel.calls, isEmpty);
    });

    test('a plan targeting a slot other than P01 never calls the channel', () async {
      final channel = _FakeChannel({'outcome': 'SUCCESS', 'error': null});
      final executor = MatriboxSafeWriteExecutor(channel);

      final result = await executor.executeGainWrite(
        _resultWith(_planWith(operations: const [_writableGainOp], presetNumber: 10)),
      );

      expect(result.outcome, MatriboxGainWriteOutcome.safetyRejected);
      expect(channel.calls, isEmpty);
    });

    test('a plan with more than one operation never calls the channel', () async {
      final channel = _FakeChannel({'outcome': 'SUCCESS', 'error': null});
      final executor = MatriboxSafeWriteExecutor(channel);
      const secondOp = MatriboxPresetWriteOperation(
        field: 'presence',
        currentValue: 73,
        targetValue: 60,
        evidence: EvidenceLevel.observed,
        status: MatriboxWriteOperationStatus.blocked,
        reason: 'no write evidence',
      );

      final result = await executor.executeGainWrite(
        _resultWith(_planWith(operations: const [_writableGainOp, secondOp])),
      );

      expect(result.outcome, MatriboxGainWriteOutcome.safetyRejected);
      expect(channel.calls, isEmpty);
    });

    test('a non-gain or non-writable single operation never calls the channel', () async {
      final channel = _FakeChannel({'outcome': 'SUCCESS', 'error': null});
      final executor = MatriboxSafeWriteExecutor(channel);
      const blockedPresence = MatriboxPresetWriteOperation(
        field: 'presence',
        currentValue: 73,
        targetValue: 60,
        evidence: EvidenceLevel.observed,
        status: MatriboxWriteOperationStatus.blocked,
        reason: 'no write evidence',
      );

      final result = await executor.executeGainWrite(
        MatriboxSafeWriteSessionResult(
          stage: MatriboxSafeWriteSessionStage.readyForConfirmation,
          plan: MatriboxPresetWritePlan(
            targetAddress: MatriboxPresetSlotAddress.fromPresetNumber(1),
            backupSha256: 'abc',
            operations: const [blockedPresence],
            gate: MatriboxWritePlanGate.blocked,
            blockers: const ['x'],
          ),
        ),
      );

      expect(result.outcome, MatriboxGainWriteOutcome.safetyRejected);
      expect(channel.calls, isEmpty);
    });

    test('maps every native outcome correctly', () async {
      for (final entry in {
        'SUCCESS': MatriboxGainWriteOutcome.success,
        'DEVICE_NOT_CONNECTED': MatriboxGainWriteOutcome.deviceNotConnected,
        'MIDI_NOT_AVAILABLE': MatriboxGainWriteOutcome.midiNotAvailable,
        'INVALID_VALUE': MatriboxGainWriteOutcome.invalidValue,
        'SEND_FAILED': MatriboxGainWriteOutcome.sendFailed,
        'SAFETY_REJECTED': MatriboxGainWriteOutcome.safetyRejected,
      }.entries) {
        final channel = _FakeChannel({'outcome': entry.key, 'error': 'x'});
        final executor = MatriboxSafeWriteExecutor(channel);
        final result = await executor.executeGainWrite(
          _resultWith(_planWith(operations: const [_writableGainOp])),
        );
        expect(result.outcome, entry.value, reason: entry.key);
      }
    });

    test('a channel exception maps to channelError, not a crash', () async {
      final executor = MatriboxSafeWriteExecutor(_ThrowingChannel());
      final result = await executor.executeGainWrite(
        _resultWith(_planWith(operations: const [_writableGainOp])),
      );
      expect(result.outcome, MatriboxGainWriteOutcome.channelError);
    });
  });
}
