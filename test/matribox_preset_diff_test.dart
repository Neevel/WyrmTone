import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_preset_diff.dart';
import 'package:wyrmtone/presets/matribox_semantic_preset.dart';
import 'package:wyrmtone/presets/protocol_evidence.dart';

MatriboxKnownField _field(double value, {EvidenceLevel writeEvidence = EvidenceLevel.unknown}) =>
    MatriboxKnownField(
      value: value,
      identityEvidence: EvidenceLevel.confirmed,
      writeEvidence: writeEvidence,
    );

MatriboxAmpBlock _amp({
  double? gain,
  double? presence,
  double? volume,
  double? bass,
  double? middle,
  double? treble,
}) => MatriboxAmpBlock(
  algorithmName: 'Sol 100 OD',
  algorithmCode: 0x07000047,
  algorithmEvidence: EvidenceLevel.confirmed,
  gain: gain == null ? null : _field(gain, writeEvidence: EvidenceLevel.confirmed),
  presence: presence == null ? null : _field(presence),
  volume: volume == null ? null : _field(volume),
  bass: bass == null ? null : _field(bass),
  middle: middle == null ? null : _field(middle),
  treble: treble == null ? null : _field(treble),
);

void main() {
  group('MatriboxPresetDiffEngine.compare', () {
    test('identical values produce no changes', () {
      final current = MatriboxSemanticPreset(
        name: 'CKY 96 STUD',
        amp: _amp(gain: 17, presence: 73, volume: 47, bass: 23, middle: 67, treble: 31),
      );
      final target = MatriboxSemanticPreset(
        name: 'CKY 96 STUD',
        amp: _amp(gain: 17, presence: 73, volume: 47, bass: 23, middle: 67, treble: 31),
      );
      final diff = MatriboxPresetDiffEngine.compare(current: current, target: target);
      expect(diff.hasChanges, isFalse);
      expect(diff.ampChanges, isEmpty);
    });

    test('changed known values produce a diff entry each', () {
      final current = MatriboxSemanticPreset(
        name: 'CKY 96 STUD',
        amp: _amp(gain: 17, presence: 73, volume: 47, bass: 23, middle: 67, treble: 31),
      );
      final target = MatriboxSemanticPreset(
        name: 'Angels Don’t Kill',
        amp: _amp(gain: 43, presence: 73, volume: 60, bass: 48, middle: 35, treble: 62),
      );
      final diff = MatriboxPresetDiffEngine.compare(current: current, target: target);

      expect(diff.nameChanged, isTrue);
      final byField = {for (final c in diff.ampChanges) c.field: c};
      expect(byField.keys, {'gain', 'volume', 'bass', 'middle', 'treble'});
      expect(byField['presence'], isNull); // unchanged, no entry
      expect(byField['gain']!.before, 17.0);
      expect(byField['gain']!.after, 43.0);
    });

    test('a field unknown on the target is never a change, even if current has a value', () {
      final current = MatriboxSemanticPreset(name: 'CKY 96 STUD', amp: _amp(gain: 17, bass: 23));
      final target = MatriboxSemanticPreset(name: 'CKY 96 STUD', amp: _amp(gain: 17));
      final diff = MatriboxPresetDiffEngine.compare(current: current, target: target);
      expect(diff.ampChanges, isEmpty);
    });

    test('no known amp block on either side yields no amp changes', () {
      final current = const MatriboxSemanticPreset(name: 'A');
      final target = const MatriboxSemanticPreset(name: 'B');
      final diff = MatriboxPresetDiffEngine.compare(current: current, target: target);
      expect(diff.ampChanges, isEmpty);
      expect(diff.nameChanged, isTrue);
    });
  });
}
