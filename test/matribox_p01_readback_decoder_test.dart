import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/p01_readback_decoder.dart';
import 'package:wyrmtone/presets/preset_selection_codec.dart';

import 'support/matribox_p01_readback_fixtures.dart';

List<TimedMidiObservation> _cycle(List<String> parts) => [
  for (final part in parts)
    TimedMidiObservation(
      bytes: matriboxHex(part),
      direction: PresetSelectionDirection.deviceToHost,
    ),
];

void main() {
  const realCycle = matriboxP01RealCycle;

  test(
    'decodes the six confirmed AMP markers from the real User-P01 cycle',
    () {
      final decoded = decodeMatchingPresets(
        _cycle(realCycle),
        expectedName: 'CKY 96 STUD',
      );

      expect(decoded, hasLength(1));
      final preset = decoded.single;
      expect(preset.slot, 0);
      expect(preset.name, 'CKY 96 STUD');
      expect(preset.gain, 17);
      expect(preset.presence, 73);
      expect(preset.volume, 47);
      expect(preset.bass, 23);
      expect(preset.middle, 67);
      expect(preset.treble, 31);
    },
  );

  test('does not match a different expected preset name', () {
    final decoded = decodeMatchingPresets(
      _cycle(realCycle),
      expectedName: 'OLA SATAN V2',
    );

    expect(decoded, isEmpty);
  });

  test(
    'accepts the "currently active slot" response variant (offset 10 = 0x02)',
    () {
      // Real device behaviour: the single active-slot re-read seen once at
      // the end of both reference captures carries 0x02 instead of 0x01 at
      // offset 10 on its part-0 message; the remaining seven parts are
      // unaffected. See docs/MATRIBOX_OFFLINE_ANALYSIS.md.
      final activeSlotPart0 = matriboxHex(matriboxP01Part0);
      activeSlotPart0[10] = 0x02;
      final observations = [
        TimedMidiObservation(
          bytes: activeSlotPart0,
          direction: PresetSelectionDirection.deviceToHost,
        ),
        ..._cycle([
          matriboxP01Part1,
          matriboxP01Part2,
          matriboxP01Part3,
          matriboxP01Part4,
          matriboxP01Part5,
          matriboxP01Part6,
          matriboxP01Part7,
        ]),
      ];

      final decoded = decodeMatchingPresets(
        observations,
        expectedName: 'CKY 96 STUD',
      );

      expect(decoded, hasLength(1));
      expect(decoded.single.gain, 17);
    },
  );

  test('an incomplete cycle (missing a payload part) is not decoded', () {
    final incomplete = [
      matriboxP01Part0,
      matriboxP01Part1,
      matriboxP01Part2,
      matriboxP01Part3,
      matriboxP01Part4,
      matriboxP01Part5,
      matriboxP01Part6,
    ];

    final decoded = decodeMatchingPresets(
      _cycle(incomplete),
      expectedName: 'CKY 96 STUD',
    );

    expect(decoded, isEmpty);
  });

  test('host->device traffic and other-length messages are ignored', () {
    final observations = [
      const TimedMidiObservation(
        bytes: [
          0xf0,
          0x21,
          0x25,
          0x7f,
          0x51,
          0x4d,
          0x45,
          0x32,
          0x11,
          0x12,
          0xf7,
        ],
        direction: PresetSelectionDirection.hostToDevice,
      ),
      ..._cycle(realCycle),
    ];

    final cycles = reconstructReadbackCycles(observations);
    expect(cycles, hasLength(1));
    expect(cycles.single.slot, 0);
    expect(cycles.single.hasAllPayloadParts, isTrue);
  });
}
