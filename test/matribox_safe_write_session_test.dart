import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_preset_write_plan.dart';
import 'package:wyrmtone/presets/matribox_raw_backup_service.dart';
import 'package:wyrmtone/presets/matribox_safe_write_session.dart';
import 'package:wyrmtone/presets/preset_selection_codec.dart';

import 'support/matribox_p01_readback_fixtures.dart';

class _FakeChannel implements MatriboxPresetReadChannel {
  _FakeChannel(this.response);
  Map<Object?, Object?> response;
  @override
  Future<Map<Object?, Object?>> readMatriboxUserP01() async => response;
}

class _ThrowingChannel implements MatriboxPresetReadChannel {
  @override
  Future<Map<Object?, Object?>> readMatriboxUserP01() async {
    throw StateError('Kein Gerät verbunden.');
  }
}

Map<Object?, Object?> _successResponse(List<List<int>> parts) => {
  'outcome': 'SUCCESS',
  'phaseDResponse': matriboxHex(matriboxPhaseDAcknowledgement),
  'parts': parts,
  'error': null,
};

List<List<int>> _realParts() => matriboxP01RealFullCycle.map(matriboxHex).toList();

void _setFloatAt(List<int> part, int rawStart, double value) {
  final data = ByteData(4)..setFloat32(0, value, Endian.little);
  for (var i = 0; i < 4; i++) {
    final byte = data.getUint8(i);
    part[rawStart + i * 2] = byte >> 4;
    part[rawStart + i * 2 + 1] = byte & 0x0f;
  }
}

void main() {
  late Directory tempDir;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('matribox_safe_write_session_test');
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  MatriboxSafeWriteSession sessionWith(MatriboxPresetReadChannel channel, {int presetNumber = 1}) =>
      MatriboxSafeWriteSession(
        backupService: MatriboxRawBackupService(
          channel: channel,
          backupDirectory: tempDir,
        ),
        targetAddress: MatriboxPresetSlotAddress.fromPresetNumber(presetNumber),
      );

  group('MatriboxSafeWriteSession.prepare', () {
    test('no backup at all (transport error) blocks preparation', () async {
      final result = await sessionWith(_ThrowingChannel()).prepare();
      expect(result.stage, MatriboxSafeWriteSessionStage.blocked);
      expect(result.plan, isNull);
      expect(result.blockedReason, contains('Kein gültiges Backup'));
    });

    test('an invalid/incomplete native read blocks preparation', () async {
      final incomplete = _realParts()..removeLast();
      final result = await sessionWith(_FakeChannel(_successResponse(incomplete))).prepare();
      expect(result.stage, MatriboxSafeWriteSessionStage.blocked);
      expect(result.plan, isNull);
    });

    test('a wrong target slot is rejected immediately, before any read', () async {
      final session = sessionWith(
        _FakeChannel(_successResponse(_realParts())),
        presetNumber: 10,
      );
      final result = await session.prepare();
      expect(result.stage, MatriboxSafeWriteSessionStage.blocked);
      expect(result.blockedReason, contains('User/P01'));
      expect(result.backup, isNull);
    });

    test('a preset already at the maximum Gain still plans a real change (steps down to 98)', () async {
      // MatriboxWriteLabTarget never produces a silent no-op: at the top
      // of the range it steps down instead of clamping to the same value
      // (see matribox_write_lab_target_test.dart). The no-op safety path
      // itself (empty diff -> plan blocked) is covered directly at
      // matribox_preset_write_plan_test.dart's "no planned changes" test.
      final parts = _realParts();
      _setFloatAt(parts[1], 201, 99.0); // Gain already at the validated maximum.
      final result = await sessionWith(_FakeChannel(_successResponse(parts))).prepare();

      expect(result.stage, MatriboxSafeWriteSessionStage.readyForConfirmation);
      expect(result.diff!.ampChanges, hasLength(1));
      expect(result.diff!.ampChanges.single.before, 99.0);
      expect(result.diff!.ampChanges.single.after, 98.0);
      expect(result.plan!.gate, MatriboxWritePlanGate.readyForHardwareTest);
      expect(result.readyForHardwareTest, isTrue);
    });

    test('a Gain-only confirmed plan for the real P01 fixture is eligible for hardware test', () async {
      final result = await sessionWith(_FakeChannel(_successResponse(_realParts()))).prepare();

      expect(result.stage, MatriboxSafeWriteSessionStage.readyForConfirmation);
      expect(result.currentPreset!.name, 'CKY 96 STUD');
      expect(result.targetPreset!.name, 'WyrmTone Sol100OD Write Lab');
      expect(result.diff!.ampChanges, hasLength(1));
      expect(result.diff!.ampChanges.single.field, 'gain');
      expect(result.diff!.ampChanges.single.before, 17.0);
      expect(result.diff!.ampChanges.single.after, 18.0);
      expect(result.plan!.operations, hasLength(1));
      expect(result.plan!.operations.single.writable, isTrue);
      expect(result.plan!.gate, MatriboxWritePlanGate.readyForHardwareTest);
      expect(result.readyForHardwareTest, isTrue);
      expect(result.backup!.isSuccess, isTrue);
    });
  });
}
