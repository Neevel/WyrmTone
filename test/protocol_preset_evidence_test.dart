import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/preset_selection_codec.dart';
import 'package:wyrmtone/presets/protocol_evidence.dart';

void main() {
  test('PC editor evidence remains separate for P01 P10 and P11', () {
    final references = ProtocolEvidenceRegistry.controlledPresetSelections;
    expect(references.map((entry) => entry.target).toList(), [
      KnownMatriboxPresetSelectionTarget.p01,
      KnownMatriboxPresetSelectionTarget.p10,
      KnownMatriboxPresetSelectionTarget.p11,
    ]);
    expect(references.map((entry) => entry.deviceIndex).toList(), [0, 9, 10]);
    expect(
      references
          .map((entry) => entry.pcEditor.observedRepeatIntervalMs)
          .toList(),
      [2.881, 2.417, 1.867],
    );
    for (final reference in references) {
      expect(reference.pcEditor.editorToMatriboxCapturePresent, isTrue);
      expect(reference.pcEditor.targetIndexConfirmed, isTrue);
      expect(reference.pcEditor.twoIdenticalTransmissionsObserved, isTrue);
      expect(reference.pcEditor.displayChangeConfirmed, isTrue);
      expect(reference.pcEditor.deviceResponseConfirmed, isFalse);
      expect(reference.deviceWriteApproved, isFalse);
    }
  });

  test('only P01 has WyrmTone hardware evidence', () {
    final references = ProtocolEvidenceRegistry.controlledPresetSelections;
    final p01 = references.singleWhere(
      (entry) => entry.target == KnownMatriboxPresetSelectionTarget.p01,
    );
    final p10 = references.singleWhere(
      (entry) => entry.target == KnownMatriboxPresetSelectionTarget.p10,
    );
    final p11 = references.singleWhere(
      (entry) => entry.target == KnownMatriboxPresetSelectionTarget.p11,
    );

    expect(p01.hasWyrmToneHardwareEvidence, isTrue);
    final hardware = p01.wyrmToneHardware!;
    expect(hardware.transport, 'Android MIDI');
    expect(hardware.transmittedMessageCount, 2);
    expect(hardware.identicalKnownMessages, isTrue);
    expect(hardware.observedRepeatIntervalMs, 3.0);
    expect(hardware.androidSendCallsSuccessful, isTrue);
    expect(hardware.displayChangeConfirmed, isTrue);
    expect(hardware.saveOrStorePerformed, isFalse);
    expect(hardware.deviceResponseConfirmed, isFalse);
    expect(p10.hasWyrmToneHardwareEvidence, isFalse);
    expect(p11.hasWyrmToneHardwareEvidence, isFalse);
  });

  test('preset selection remains unapproved for general device writes', () {
    final general = ProtocolEvidenceRegistry.capabilities.singleWhere(
      (capability) => capability.id == 'preset.select',
    );
    expect(general.productionApproved, isFalse);
    expect(ProtocolEvidenceRegistry.decide('preset.select').allowed, isFalse);
  });
}
