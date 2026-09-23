import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_full_live_verifier.dart';
import 'package:wyrmtone/presets/matribox_preset_layout.dart';
import 'package:wyrmtone/presets/raw_preset_snapshot.dart';

import 'support/matribox_big_capture_snapshots.dart';
import 'support/matribox_full_live_helpers.dart';

/// Protocol evidence of the preset layout (real device reads) and the productive raw-change
/// classification of a readback (the same classifier the transfer readback uses).
RawPresetSnapshot _snapshot(List<List<int>> parts) => RawPresetSnapshot.capture(
  deviceLabel: 'Sonicake Matribox 1 84EF:0054',
  rawParts: parts,
);

void main() {
  final before = _snapshot(hexParts(bigBeforeRawPartsHex));
  final afterReal = _snapshot(hexParts(bigAfterRawPartsHex));

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

  group('raw-change classification of the real editor capture BEFORE -> AFTER', () {
    Map<FullLiveChangeClass, Set<String>> classify(Set<MatriboxChainSlot> planned) {
      final result = <FullLiveChangeClass, Set<String>>{};
      for (final c in MatriboxFullLiveVerifier.classifyRawChanges(
        before: before,
        after: afterReal,
        modelSlots: planned,
        parameterSlots: planned,
        toggleSlots: planned,
      )) {
        result.putIfAbsent(c.classification, () => {}).add(c.detail);
      }
      return result;
    }

    test('without a plan nothing is expected: every change is unexpected or unknown, Part 8 stays only CORRELATED', () {
      final c = classify({});
      expect(c.keys.toSet(), {
        FullLiveChangeClass.unexpectedKnownChange,
        FullLiveChangeClass.unknownRawChange,
        FullLiveChangeClass.correlatedPart8Change,
      });
      expect(c[FullLiveChangeClass.unexpectedKnownChange], containsAll(['Presetname nicht im Plan', 'Preset BPM nicht im Plan', 'Preset VOL nicht im Plan']));
      // the FX1 code copy only follows a planned FX1 model change
      expect(c[FullLiveChangeClass.unknownRawChange], {'Offset 652 ohne passende FX1-Änderung'});
    });

    test('with every block planned, name, BPM and VOL are still never expected; nothing is UNKNOWN', () {
      final c = classify(MatriboxChainSlot.values.toSet());
      expect(c.containsKey(FullLiveChangeClass.unknownRawChange), isFalse);
      expect(c[FullLiveChangeClass.unexpectedKnownChange], {'Presetname nicht im Plan', 'Preset BPM nicht im Plan', 'Preset VOL nicht im Plan'});
      expect(c[FullLiveChangeClass.expectedModelChange], contains('FX1-Code-Kopie folgt dem FX1-Modell'));
      expect(c[FullLiveChangeClass.correlatedPart8Change], hasLength(1));
    });
  });
}
