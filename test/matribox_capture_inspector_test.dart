import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/preset_selection_codec.dart';

import '../tool/matribox_capture_inspector.dart';
import '../tool/preset_compare.dart' show parseTsharkMidiFields;

void main() {
  test('inspection preserves order, unknown messages, and repeat groups', () {
    const unknownLarge = <int>[
      0xf0,
      0x21,
      0x25,
      0x7f,
      0x51,
      0x4d,
      0x45,
      0x32,
      0x7e,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0xf7,
    ];
    final p01 = ConfirmedPresetSelectionCodec.encodeReference(
      KnownMatriboxPresetSelectionTarget.p01,
    );
    final inspected = inspectMidiObservations([
      TimedMidiObservation(
        bytes: p01,
        direction: PresetSelectionDirection.hostToDevice,
        timestampMs: 10,
      ),
      const TimedMidiObservation(
        bytes: unknownLarge,
        direction: PresetSelectionDirection.deviceToHost,
        timestampMs: 20,
      ),
      TimedMidiObservation(
        bytes: p01,
        direction: PresetSelectionDirection.hostToDevice,
        timestampMs: 30,
      ),
    ]);

    expect(inspected.map((item) => item['sequence']), [1, 2, 3]);
    expect(inspected.first['family'], 'QME2 preset selection');
    expect(inspected.first['presetIndex'], 0);
    expect(inspected.first['identicalCount'], 2);
    expect(inspected.last['identicalGroup'], inspected.first['identicalGroup']);
    expect(inspected[1]['length'], 40);
    expect(inspected[1]['family'], contains('40-byte unclassified'));
    expect(inspected[1]['hex'], isNotEmpty);
    expect(inspected[1]['direction'], 'deviceToHost');
    expect(inspected[1]['deviceWriteApproved'], isFalse);
  });

  test(
    'raw usb.capdata fallback is deframed when MIDI dissection is absent',
    () {
      const p01 =
          '04f02125047f514d044532120400020004000000040000000400000005f70000';
      final observations = parseTsharkMidiFields('1.000\t0x03\t32\t\t$p01\n');

      expect(observations, hasLength(1));
      expect(observations.single.bytes, hasLength(22));
      expect(observations.single.bytes.first, 0xf0);
      expect(observations.single.bytes.last, 0xf7);
    },
  );

  test(
    'algorithm selection and control change remain offline observations',
    () {
      const algorithmSelection = <int>[
        0xf0,
        0x21,
        0x25,
        0x7f,
        0x51,
        0x4d,
        0x45,
        0x32,
        0x12,
        0x10,
        0x03,
        0x00,
        0x01,
        0x05,
        0x09,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x07,
        0xf7,
      ];
      final inspected = inspectMidiObservations(const [
        TimedMidiObservation(
          bytes: algorithmSelection,
          direction: PresetSelectionDirection.hostToDevice,
        ),
        TimedMidiObservation(
          bytes: [0xb1, 0x31, 0x7f],
          direction: PresetSelectionDirection.hostToDevice,
          state: MidiObservationState.otherMidi,
        ),
      ]);

      expect(inspected.first['family'], 'QME2 algorithm selection');
      expect(inspected.first['algorithmCode'], 0x07000059);
      expect(inspected.first['deviceWriteApproved'], isFalse);
      expect(inspected.last['family'], 'MIDI control change');
      expect(inspected.last['midiChannel'], 2);
      expect(inspected.last['controller'], 49);
      expect(inspected.last['value'], 127);
      expect(inspected.last['deviceWriteApproved'], isFalse);
    },
  );
}
