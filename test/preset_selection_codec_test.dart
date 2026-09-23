import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_user_slot.dart';
import 'package:wyrmtone/presets/preset_selection_codec.dart';

void main() {
  const references = {
    KnownMatriboxPresetSelectionTarget.p01: 'P01',
    KnownMatriboxPresetSelectionTarget.p10: 'P10',
    KnownMatriboxPresetSelectionTarget.p11: 'P11',
  };

  test('the confirmed selection indices map to the canonical user slot address and back', () {
    for (final entry in references.entries) {
      final slot = MatriboxUserSlot.fromDeviceIndex(entry.key.deviceIndex);
      expect(slot.label, entry.value);
      expect(slot.presetNumber, entry.key.presetNumber);
      expect(MatriboxUserSlot.preset(slot.presetNumber).deviceIndex, entry.key.deviceIndex);
      expect(OfflinePresetSelectionMessage(entry.key).slot, slot);
    }
    expect(() => MatriboxUserSlot.fromDeviceIndex(-1), throwsArgumentError);
    expect(() => MatriboxUserSlot.preset(0), throwsArgumentError);
  });

  test('P01 P10 and P11 golden bytes round-trip offline', () {
    for (final entry in references.entries) {
      final bytes = ConfirmedPresetSelectionCodec.encodeReference(entry.key);
      final decoded = ConfirmedPresetSelectionCodec.decode(bytes);
      expect(decoded.targetIndex, entry.key.deviceIndex);
      expect(decoded.presetLabel, entry.value);
      expect(decoded.deviceWriteApproved, isFalse);
    }
    expect(KnownMatriboxPresetSelectionTarget.fromDeviceIndex(1), isNull);
  });

  test('each golden reference has complete controlled evidence', () {
    for (final entry in ConfirmedPresetSelectionCodec.references.entries) {
      final evidence = entry.value;
      expect(evidence.target, entry.key);
      expect(evidence.editorToMatriboxCapturePresent, isTrue);
      expect(evidence.targetIndexConfirmed, isTrue);
      expect(evidence.twoIdenticalTransmissionsObserved, isTrue);
      expect(evidence.displayChangeConfirmed, isTrue);
      expect(evidence.deviceWriteApproved, isFalse);
    }
  });

  test('invalid 22-byte preset candidate remains visible with offset', () {
    final invalid = ConfirmedPresetSelectionCodec.encodeReference(
      KnownMatriboxPresetSelectionTarget.p01,
    ).toList()..[12] = 1;
    final finding = analyzePresetSelections([
      TimedMidiObservation(
        bytes: invalid,
        direction: PresetSelectionDirection.hostToDevice,
      ),
    ]).single;
    expect(finding, isA<RejectedPresetSelectionCandidate>());
    expect(finding.toJson(), containsPair('invalidOffset', 12));
    expect(finding.toJson(), containsPair('observedValue', 1));
    expect(finding.toJson(), containsPair('deviceWriteApproved', false));
  });

  test('unconfirmed target index is rejected', () {
    final unknown = ConfirmedPresetSelectionCodec.encodeReference(
      KnownMatriboxPresetSelectionTarget.p01,
    ).toList()..[18] = 1;
    final finding = analyzePresetSelections([
      TimedMidiObservation(
        bytes: unknown,
        direction: PresetSelectionDirection.hostToDevice,
      ),
    ]).single;
    expect(
      finding.toJson(),
      containsPair('rejectionReason', 'unconfirmedTargetIndex'),
    );
    expect(finding.toJson(), containsPair('invalidOffset', 18));
  });

  test(
    'two repeats are grouped; unrelated device traffic stays unclassified',
    () {
      final bytes = ConfirmedPresetSelectionCodec.encodeReference(
        KnownMatriboxPresetSelectionTarget.p01,
      );
      final findings = analyzePresetSelections([
        TimedMidiObservation(
          bytes: bytes,
          direction: PresetSelectionDirection.hostToDevice,
          timestampMs: 1000,
        ),
        const TimedMidiObservation(
          bytes: [0xf0, 0x7e, 0x00, 0xf7],
          direction: PresetSelectionDirection.deviceToHost,
          timestampMs: 1001,
        ),
        TimedMidiObservation(
          bytes: bytes,
          direction: PresetSelectionDirection.hostToDevice,
          timestampMs: 1002.9,
        ),
      ]);
      final analysis = findings.whereType<PresetSelectionAnalysis>().single;
      expect(analysis.message.presetLabel, 'P01');
      expect(analysis.repeatCount, 2);
      expect(analysis.repeatIntervalsMs.single, closeTo(2.9, 0.0001));
      expect(analysis.possibleDeviceResponses, 0);
      expect(findings.whereType<UnclassifiedDeviceTraffic>().single.count, 1);
    },
  );

  test('only same-family timely device data can be a possible response', () {
    final bytes = ConfirmedPresetSelectionCodec.encodeReference(
      KnownMatriboxPresetSelectionTarget.p10,
    );
    final findings = analyzePresetSelections([
      TimedMidiObservation(
        bytes: bytes,
        direction: PresetSelectionDirection.hostToDevice,
        timestampMs: 10,
      ),
      TimedMidiObservation(
        bytes: bytes,
        direction: PresetSelectionDirection.deviceToHost,
        timestampMs: 11,
      ),
    ]);
    final analysis = findings.whereType<PresetSelectionAnalysis>().single;
    expect(analysis.possibleDeviceResponses, 1);
    expect(analysis.toJson(), containsPair('confirmedMidiResponse', false));
    expect(findings.whereType<UnclassifiedDeviceTraffic>(), isEmpty);
  });
}
