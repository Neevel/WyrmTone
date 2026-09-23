import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/raw_preset_snapshot.dart';

import 'support/matribox_p01_readback_fixtures.dart';

void main() {
  List<List<int>> realParts() =>
      matriboxP01RealFullCycle.map(matriboxHex).toList();

  group('RawPresetSnapshot.capture', () {
    test('decodes a complete real ten-part User-P01 cycle', () {
      final snapshot = RawPresetSnapshot.capture(
        deviceLabel: 'Sonicake Matribox 1 84EF:0054',
        rawParts: realParts(),
        phaseDResponse: matriboxHex(matriboxPhaseDAcknowledgement),
        clock: () => DateTime.utc(2026, 9, 15),
      );

      expect(snapshot.presetName, 'CKY 96 STUD');
      expect(snapshot.bank, 0);
      expect(snapshot.slot, 0);
      expect(snapshot.presetNumber, 1);
      expect(snapshot.isUserBank, isTrue);
      expect(snapshot.formatVersion, rawPresetSnapshotFormatVersion);
      expect(snapshot.decoderVersion, rawPresetDecoderVersion);
    });

    test('decodes the confirmed AMP markers matching the CKY-96-STUD fixture', () {
      final snapshot = RawPresetSnapshot.capture(
        deviceLabel: 'Sonicake Matribox 1 84EF:0054',
        rawParts: realParts(),
      );
      final amp = snapshot.ampFields;
      expect(amp, isNotNull);
      expect(amp!.gain, 17.0);
      expect(amp.presence, 73.0);
      expect(amp.volume, 47.0);
      expect(amp.bass, 23.0);
      expect(amp.middle, 67.0);
      expect(amp.treble, 31.0);
    });

    test('raw parts are preserved byte-identical, including unclassified bytes', () {
      final input = realParts();
      final snapshot = RawPresetSnapshot.capture(
        deviceLabel: 'Sonicake Matribox 1 84EF:0054',
        rawParts: input,
      );
      expect(snapshot.rawParts.length, 10);
      for (var i = 0; i < 10; i++) {
        expect(snapshot.rawParts[i], input[i], reason: 'part $i must be byte-identical');
      }
    });

    test('phaseDResponse is preserved byte-identical when supplied', () {
      final phaseD = matriboxHex(matriboxPhaseDAcknowledgement);
      final snapshot = RawPresetSnapshot.capture(
        deviceLabel: 'Sonicake Matribox 1 84EF:0054',
        rawParts: realParts(),
        phaseDResponse: phaseD,
      );
      expect(snapshot.phaseDResponse, phaseD);
    });

    test('phaseDResponse is optional and null when not supplied', () {
      final snapshot = RawPresetSnapshot.capture(
        deviceLabel: 'Sonicake Matribox 1 84EF:0054',
        rawParts: realParts(),
      );
      expect(snapshot.phaseDResponse, isNull);
    });

    test('hash is deterministic for identical input', () {
      final a = RawPresetSnapshot.capture(
        deviceLabel: 'Sonicake Matribox 1 84EF:0054',
        rawParts: realParts(),
      );
      final b = RawPresetSnapshot.capture(
        deviceLabel: 'Sonicake Matribox 1 84EF:0054',
        rawParts: realParts(),
      );
      expect(a.sha256, b.sha256);
      expect(a.sha256, hasLength(64));
    });

    test('a single manipulated byte changes the hash', () {
      final baseline = RawPresetSnapshot.capture(
        deviceLabel: 'Sonicake Matribox 1 84EF:0054',
        rawParts: realParts(),
      );
      final manipulated = realParts();
      // Flip one unclassified byte deep inside part 1's payload (not part of
      // any confirmed field), still leaving every structural check intact.
      manipulated[1][100] = manipulated[1][100] == 0x00 ? 0x01 : 0x00;
      final changed = RawPresetSnapshot.capture(
        deviceLabel: 'Sonicake Matribox 1 84EF:0054',
        rawParts: manipulated,
      );
      expect(changed.sha256, isNot(baseline.sha256));
    });

    test('rejects a read with fewer than ten parts', () {
      final parts = realParts()..removeLast();
      expect(
        () => RawPresetSnapshot.capture(
          deviceLabel: 'Sonicake Matribox 1 84EF:0054',
          rawParts: parts,
        ),
        throwsA(isA<InvalidRawPresetSnapshotException>()),
      );
    });

    test('rejects a part with the wrong length', () {
      final parts = realParts();
      parts[0] = parts[0].sublist(0, parts[0].length - 2)..add(0xf7);
      expect(
        () => RawPresetSnapshot.capture(
          deviceLabel: 'Sonicake Matribox 1 84EF:0054',
          rawParts: parts,
        ),
        throwsA(isA<InvalidRawPresetSnapshotException>()),
      );
    });

    test('rejects parts supplied out of order', () {
      final parts = realParts();
      final tmp = parts[1];
      parts[1] = parts[2];
      parts[2] = tmp;
      expect(
        () => RawPresetSnapshot.capture(
          deviceLabel: 'Sonicake Matribox 1 84EF:0054',
          rawParts: parts,
        ),
        throwsA(isA<InvalidRawPresetSnapshotException>()),
      );
    });

    test('rejects a duplicated part standing in for a different index', () {
      final parts = realParts();
      parts[1] = List<int>.from(parts[0]); // part 0's bytes, twice
      expect(
        () => RawPresetSnapshot.capture(
          deviceLabel: 'Sonicake Matribox 1 84EF:0054',
          rawParts: parts,
        ),
        throwsA(isA<InvalidRawPresetSnapshotException>()),
      );
    });

    test('rejects an empty device label', () {
      expect(
        () => RawPresetSnapshot.capture(
          deviceLabel: '  ',
          rawParts: realParts(),
        ),
        throwsA(isA<InvalidRawPresetSnapshotException>()),
      );
    });

    test('rejects a malformed phaseDResponse', () {
      expect(
        () => RawPresetSnapshot.capture(
          deviceLabel: 'Sonicake Matribox 1 84EF:0054',
          rawParts: realParts(),
          phaseDResponse: [0x00, 0x01],
        ),
        throwsA(isA<InvalidRawPresetSnapshotException>()),
      );
    });

    test('does not populate AMP fields for an unrecognised preset name', () {
      final parts = realParts();
      // Overwrite the name bytes (decoded offset 2..) in part 0's payload
      // with an unrecognised name, keeping the header and framing intact.
      // Part 0 payload starts at raw offset 17; each decoded byte is two
      // raw nibble bytes, so decoded offset 2 is raw offset 17 + 2*2 = 21.
      for (var i = 0; i < 4; i++) {
        final decodedValue = 'ZZ'.codeUnitAt(i.isEven ? 0 : 1);
        parts[0][21 + i * 2] = (decodedValue >> 4) & 0x0f;
        parts[0][21 + i * 2 + 1] = decodedValue & 0x0f;
      }
      final snapshot = RawPresetSnapshot.capture(
        deviceLabel: 'Sonicake Matribox 1 84EF:0054',
        rawParts: parts,
      );
      expect(snapshot.presetName, isNot('CKY 96 STUD'));
      expect(snapshot.ampFields, isNull);
    });
  });
}
