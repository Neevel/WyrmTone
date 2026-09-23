import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_chain_catalog.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_full_live_plan.dart';
import 'package:wyrmtone/presets/matribox_full_live_verifier.dart';
import 'package:wyrmtone/presets/matribox_preset_layout.dart';
import 'package:wyrmtone/presets/raw_preset_backup_format.dart';
import 'package:wyrmtone/presets/raw_preset_snapshot.dart';

import 'support/matribox_big_capture_groups.dart';
import 'support/matribox_big_capture_snapshots.dart';
import 'support/matribox_full_live_helpers.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<List<int>> _parts(List<String> hexParts) => [for (final h in hexParts) hexToBytes(h)];

RawPresetSnapshot _snapshot(List<List<int>> parts) => RawPresetSnapshot.capture(
  deviceLabel: 'Sonicake Matribox 1 84EF:0054',
  rawParts: parts,
);

void main() {
  final before = _snapshot(_parts(bigBeforeRawPartsHex));
  final afterReal = _snapshot(_parts(bigAfterRawPartsHex));

  group('layout decoder (confirmed portions, real device reads)', () {
    test('BEFORE: CKY 96 STUD, code table, AMP knobs, block states, BPM/VOL', () {
      final m = MatriboxPresetLayout.decode(before);
      expect(m.name, 'CKY 96 STUD');
      expect(m.codes, [0x01000021, 0x03000000, 0x07000047, 0x1d, 0x0a000006, 0x01000035, 0x04000000, 0x0b00000d, 0x0c000000]);
      expect(m.blockStates, [1, 0, 1, 1, 0, 1, 0, 0, 1]);
      expect((m.bpm, m.volume), (120, 50));
      expect([for (var i = 0; i < 6; i++) m.parameter(MatriboxChainSlot.amp, i)], [18, 74, 47, 23, 67, 31]);
      expect(m.fx1CodeCopy, 0x01000021);
    });

    test('AFTER: CAP TEST 01 with every block of the capture', () {
      final m = MatriboxPresetLayout.decode(afterReal);
      expect(m.name, 'CAP TEST 01');
      expect(m.codes, [0x03000000, 0x03000009, 0x07000035, 0x1d, 0x0a100006, 0x0100003a, 0x04000011, 0x0b000006, 0x0c000008]);
      expect((m.bpm, m.volume), (137, 37));
      expect([for (var i = 0; i < 6; i++) m.parameter(MatriboxChainSlot.amp, i)], [17, 67, 31, 41, 47, 59]);
      expect(m.parameter(MatriboxChainSlot.cab, 1), 37); // CAB VOL is wire index 1
      expect(m.parameter(MatriboxChainSlot.eq, 1), -23);
      expect(m.parameter(MatriboxChainSlot.mod, 4), 1); // Sync
      expect(m.blockStates, [1, 0, 1, 1, 0, 1, 0, 0, 1]);
    });
  });

  group('plan', () {
    test('25 fixed operations: 9 model selects, 14 parameter writes, 2 block toggles', () {
      expect(MatriboxFullLivePlan.operations, hasLength(25));
      expect((MatriboxFullLivePlan.modelCount, MatriboxFullLivePlan.parameterCount, MatriboxFullLivePlan.toggleCount), (9, 14, 2));
      expect(MatriboxFullLivePlan.slotsWithModelSelect.toSet(), MatriboxChainSlot.values.toSet());
    });

    test('every planned message is EXACTLY a captured Big-Capture message (Dart == capture)', () {
      expect(
        [for (final o in MatriboxFullLivePlan.operations) _hex(o.bytes)],
        bigCapturePlannedMessages,
      );
    });

    test('covers positive, negative, decimal and flag values; no User IR, no metadata, no store', () {
      final params = MatriboxFullLivePlan.operations.where((o) => o.kind == FullLiveOperationKind.parameter);
      expect(params.any((o) => o.value! > 0 && o.parameter!.kind == MatriboxParameterKind.number), isTrue);
      expect(params.any((o) => o.value! < 0), isTrue);
      expect(params.any((o) => o.parameter!.kind == MatriboxParameterKind.decimal), isTrue);
      expect(params.any((o) => o.parameter!.kind == MatriboxParameterKind.flag), isTrue);
      expect(MatriboxFullLivePlan.operations.every((o) => o.algorithm == null || o.algorithm!.sendableInFullLive), isTrue);
      for (final o in MatriboxFullLivePlan.operations) {
        expect(o.bytes.length, anyOf(22, 34, 3));
        // 12 12 (commit) and 12 11 (metadata) never appear
        if (o.bytes.length > 3) expect(o.bytes[9], 0x10, reason: o.label);
      }
    });

    test('toggles prove both directions: FX1 ON->OFF (0x7f) and FX2 OFF->ON (0x00)', () {
      final toggles = MatriboxFullLivePlan.operations.where((o) => o.kind == FullLiveOperationKind.blockToggle).toList();
      expect([for (final t in toggles) t.bytes], [[0xb1, 0x30, 0x7f], [0xb1, 0x31, 0x00]]);
    });

    test('the original P01 suits the plan; the post-capture state is refused with a restore hint', () {
      expect(MatriboxFullLivePlan.blockers(MatriboxPresetLayout.decode(before)), isEmpty);
      final blockers = MatriboxFullLivePlan.blockers(MatriboxPresetLayout.decode(afterReal));
      expect(blockers, isNotEmpty);
      expect(blockers.join(' '), contains('P01_BEFORE_BIG_CAPTURE.prst'));
    });
  });

  group('verifier', () {
    test('the state the plan produces is CERTIFIED; Part 8 window and FX1 copy are tolerated', () {
      final result = MatriboxFullLiveVerifier.verify(before: before, after: _snapshot(afterFromPlan()));
      expect(result.outcome, FullLiveVerificationOutcome.certified,
          reason: result.changes.where((c) => c.classification.name.startsWith('un')).map((c) => c.detail).join('; '));
      expect(result.operations.every((r) => r.check == FullLiveOperationCheck.matched), isTrue);
      expect(result.count(FullLiveChangeClass.correlatedPart8Change), 8);
      expect(result.count(FullLiveChangeClass.expectedModelChange), greaterThan(0));
      expect(result.count(FullLiveChangeClass.expectedParameterChange), greaterThan(0));
      expect(result.count(FullLiveChangeClass.expectedBlockChange), greaterThan(0));
      expect(result.count(FullLiveChangeClass.unexpectedKnownChange) + result.count(FullLiveChangeClass.unknownRawChange), 0);
    });

    test('Rate 4.0 (device conversion with Sync) passes with a note; another value does not', () {
      final ok = MatriboxFullLiveVerifier.verify(before: before, after: _snapshot(afterFromPlan(rate: 4.0)));
      expect(ok.certified, isTrue);
      expect(ok.operations.firstWhere((r) => r.operation.parameter?.name == 'Rate').note, isNotNull);
      final exact = MatriboxFullLiveVerifier.verify(before: before, after: _snapshot(afterFromPlan(rate: 3.7)));
      expect(exact.certified, isTrue);
      final wrong = MatriboxFullLiveVerifier.verify(before: before, after: _snapshot(afterFromPlan(rate: 6.0)));
      expect(wrong.outcome, FullLiveVerificationOutcome.expectedChangeMissing);
    });

    test('no change at all is expectedChangeMissing', () {
      final result = MatriboxFullLiveVerifier.verify(before: before, after: before);
      expect(result.outcome, FullLiveVerificationOutcome.expectedChangeMissing);
    });

    test('a missing model change is expectedChangeMissing', () {
      final parts = afterFromPlan();
      setDecoded(parts, MatriboxPresetLayout.codeOffset(MatriboxChainSlot.rvb), u32(0x0c000000));
      final result = MatriboxFullLiveVerifier.verify(before: before, after: _snapshot(parts));
      expect(result.outcome, FullLiveVerificationOutcome.expectedChangeMissing);
      expect(result.operations.where((r) => r.check == FullLiveOperationCheck.mismatch).map((r) => r.operation.slot), [MatriboxChainSlot.rvb]);
    });

    test('unplanned known fields (BPM, name, other block state) are UNEXPECTED_KNOWN_CHANGE', () {
      for (final mutate in <void Function(List<List<int>>)>[
        (p) => setDecoded(p, MatriboxPresetLayout.bpmOffset, u16(99)),
        (p) => setDecoded(p, MatriboxPresetLayout.nameOffset, 'XY'.codeUnits),
        (p) => setDecoded(p, MatriboxPresetLayout.stateOffset(MatriboxChainSlot.amp), u16(0)),
      ]) {
        final parts = afterFromPlan();
        mutate(parts);
        expect(MatriboxFullLiveVerifier.verify(before: before, after: _snapshot(parts)).outcome,
            FullLiveVerificationOutcome.unexpectedKnownChange);
      }
    });

    test('an unknown raw byte anywhere else stays visible as UNKNOWN_RAW_CHANGE and blocks certification', () {
      for (final mutate in <void Function(List<List<int>>)>[
        (p) => setDecoded(p, 700, [0x55]),
        (p) => p[8][30] = (p[8][30] + 1) & 15, // part 8 outside the correlated window
      ]) {
        final parts = afterFromPlan();
        mutate(parts);
        final result = MatriboxFullLiveVerifier.verify(before: before, after: _snapshot(parts));
        expect(result.outcome, FullLiveVerificationOutcome.unknownRawChange);
      }
    });

    test('the real post-capture state (name, BPM, VOL, other params) is NOT certified', () {
      final result = MatriboxFullLiveVerifier.verify(before: before, after: afterReal);
      expect(result.certified, isFalse);
    });
  });
}
