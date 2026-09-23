import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_preset_decoder.dart';
import 'package:wyrmtone/presets/matribox_semantic_preset.dart';
import 'package:wyrmtone/presets/matribox_write_lab_target.dart';
import 'package:wyrmtone/presets/protocol_evidence.dart';
import 'package:wyrmtone/presets/raw_preset_snapshot.dart';

import 'support/matribox_p01_readback_fixtures.dart';

void main() {
  MatriboxSemanticPreset realCurrent() => MatriboxPresetDecoder.fromSnapshot(
    RawPresetSnapshot.capture(
      deviceLabel: 'Sonicake Matribox 1 84EF:0054',
      rawParts: matriboxP01RealFullCycle.map(matriboxHex).toList(),
    ),
  );

  group('MatriboxWriteLabTarget.buildGainOnlyTarget', () {
    test('moves Gain from 17 to 18 (current + controlled delta), all else unchanged', () {
      final current = realCurrent();
      final target = MatriboxWriteLabTarget.buildGainOnlyTarget(current);

      expect(target.name, 'WyrmTone Sol100OD Write Lab');
      expect(target.amp!.gain!.value, 18.0);
      expect(target.amp!.gain!.writeEvidence, EvidenceLevel.confirmed);
      expect(target.amp!.presence!.value, current.amp!.presence!.value);
      expect(target.amp!.volume!.value, current.amp!.volume!.value);
      expect(target.amp!.bass!.value, current.amp!.bass!.value);
      expect(target.amp!.middle!.value, current.amp!.middle!.value);
      expect(target.amp!.treble!.value, current.amp!.treble!.value);
    });

    test('the target is never a hardcoded fixed value -- it tracks the current Gain', () {
      const highGain = MatriboxKnownField(
        value: 98,
        identityEvidence: EvidenceLevel.confirmed,
        writeEvidence: EvidenceLevel.confirmed,
        catalogIndex: 0,
      );
      const current = MatriboxSemanticPreset(
        name: 'CKY 96 STUD',
        amp: MatriboxAmpBlock(
          algorithmName: 'Sol 100 OD',
          algorithmCode: 0x07000047,
          algorithmEvidence: EvidenceLevel.confirmed,
          gain: highGain,
        ),
      );
      final target = MatriboxWriteLabTarget.buildGainOnlyTarget(current);
      expect(target.amp!.gain!.value, 99.0);
    });

    test(
      'at the validated maximum, the target steps down instead of a silent '
      'no-op -- the test must always be a real, observable change',
      () {
        const current = MatriboxSemanticPreset(
          name: 'CKY 96 STUD',
          amp: MatriboxAmpBlock(
            algorithmName: 'Sol 100 OD',
            algorithmCode: 0x07000047,
            algorithmEvidence: EvidenceLevel.confirmed,
            gain: MatriboxKnownField(
              value: 99,
              identityEvidence: EvidenceLevel.confirmed,
              writeEvidence: EvidenceLevel.confirmed,
              catalogIndex: 0,
            ),
          ),
        );
        final target = MatriboxWriteLabTarget.buildGainOnlyTarget(current);
        expect(target.amp!.gain!.value, 98.0);
      },
    );

    test('rejects a current preset without a known Gain value', () {
      const current = MatriboxSemanticPreset(name: 'Unbekannt');
      expect(
        () => MatriboxWriteLabTarget.buildGainOnlyTarget(current),
        throwsA(isA<UnsupportedWriteLabTarget>()),
      );
    });
  });
}
