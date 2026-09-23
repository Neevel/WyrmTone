import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_preset_decoder.dart';
import 'package:wyrmtone/presets/protocol_evidence.dart';
import 'package:wyrmtone/presets/raw_preset_snapshot.dart';

import 'support/matribox_p01_readback_fixtures.dart';

void main() {
  RawPresetSnapshot ckySnapshot() => RawPresetSnapshot.capture(
    deviceLabel: 'Sonicake Matribox 1 84EF:0054',
    rawParts: matriboxP01RealFullCycle.map(matriboxHex).toList(),
    phaseDResponse: matriboxHex(matriboxPhaseDAcknowledgement),
  );

  group('MatriboxPresetDecoder.fromSnapshot', () {
    test('decodes the six confirmed AMP fields for the CKY fixture', () {
      final preset = MatriboxPresetDecoder.fromSnapshot(ckySnapshot());

      expect(preset.name, 'CKY 96 STUD');
      expect(preset.address!.presetNumber, 1);
      expect(preset.hasKnownAmpBlock, isTrue);
      expect(preset.amp!.algorithmName, 'Sol 100 OD');
      expect(preset.amp!.algorithmCode, 0x07000047);
      expect(preset.amp!.gain!.value, 17.0);
      expect(preset.amp!.presence!.value, 73.0);
      expect(preset.amp!.volume!.value, 47.0);
      expect(preset.amp!.bass!.value, 23.0);
      expect(preset.amp!.middle!.value, 67.0);
      expect(preset.amp!.treble!.value, 31.0);
    });

    test('only Gain carries confirmed write evidence; the rest is read-only', () {
      final amp = MatriboxPresetDecoder.fromSnapshot(ckySnapshot()).amp!;
      expect(amp.gain!.writeEvidence, EvidenceLevel.confirmed);
      for (final field in [
        amp.presence,
        amp.volume,
        amp.bass,
        amp.middle,
        amp.treble,
      ]) {
        expect(field!.writeEvidence, EvidenceLevel.unknown);
        expect(field.identityEvidence, EvidenceLevel.confirmed);
      }
    });

    test('raw parts are preserved unchanged on the semantic preset', () {
      final input = matriboxP01RealFullCycle.map(matriboxHex).toList();
      final preset = MatriboxPresetDecoder.fromSnapshot(
        RawPresetSnapshot.capture(
          deviceLabel: 'Sonicake Matribox 1 84EF:0054',
          rawParts: input,
        ),
      );
      expect(preset.rawParts, isNotNull);
      expect(preset.rawParts!.length, 10);
      for (var i = 0; i < 10; i++) {
        expect(preset.rawParts![i], input[i]);
      }
    });

    test('an unrecognised preset name yields no known AMP block', () {
      final parts = matriboxP01RealFullCycle.map(matriboxHex).toList();
      // Overwrite the decoded name bytes (see raw_preset_snapshot_test.dart
      // for why offset 21 is the first decoded name byte of part 0).
      for (var i = 0; i < 4; i++) {
        parts[0][21 + i * 2] = 0x05;
        parts[0][21 + i * 2 + 1] = 0x0a;
      }
      final snapshot = RawPresetSnapshot.capture(
        deviceLabel: 'Sonicake Matribox 1 84EF:0054',
        rawParts: parts,
      );
      final preset = MatriboxPresetDecoder.fromSnapshot(snapshot);
      expect(preset.hasKnownAmpBlock, isFalse);
      expect(preset.amp, isNull);
      // The name itself is still structural, not evidence-gated, and the
      // raw bytes remain fully available even without a known AMP block.
      expect(preset.name, isNot('CKY 96 STUD'));
      expect(preset.rawParts, isNotNull);
    });
  });
}
