/// FROZEN HARDWARE EVIDENCE (read-only test data, do not edit).
///
/// The exact operations and messages of the two CERTIFIED WyrmTone hardware runs on User P01
/// (readback after manual device save):
///   ANGELS_DONT_KILL_P01_V1  (2026-09-20, 11 operations)
///   FAMILY_EXPANSION_P01_V1  (2026-09-21, 23 operations)
/// Extracted from the removed certification plans before their runners were deleted; the same
/// bytes are frozen natively in MatriboxAngelsGolden.kt / MatriboxFamilyExpansionGolden.kt.
/// The productive ledger (MatriboxHardwareLedger.product) is checked against this data.
library;

import 'package:wyrmtone/presets/matribox_chain_slot.dart';

enum CertifiedKind { modelSelect, parameter, blockToggle }

class CertifiedOperation {
  const CertifiedOperation(
    this.slot,
    this.kind, {
    required this.model,
    required this.algorithmId,
    required this.parameter,
    required this.value,
    required this.enabled,
    required this.hex,
  });

  final MatriboxChainSlot slot;
  final CertifiedKind kind;
  final String? model, algorithmId, parameter;
  final double? value;
  final bool? enabled;

  /// The message as sent (space separated lowercase hex).
  final String hex;
}

class CertifiedRun {
  const CertifiedRun({required this.planId, required this.operations});
  final String planId;
  final List<CertifiedOperation> operations;
}

const certifiedRuns = [angelsDontKillP01V1, familyExpansionP01V1];

const angelsDontKillP01V1 = CertifiedRun(
  planId: 'ANGELS_DONT_KILL_P01_V1',
  operations: [
    CertifiedOperation(MatriboxChainSlot.fx1, CertifiedKind.blockToggle, model: null, algorithmId: null, parameter: null, value: null, enabled: false, hex: 'b1 30 7f'),
    CertifiedOperation(MatriboxChainSlot.fx2, CertifiedKind.modelSelect, model: 'Boost', algorithmId: 'catalog:Boost', parameter: null, value: null, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 02 00 01 01 0a 00 00 00 00 00 00 f7'),
    CertifiedOperation(MatriboxChainSlot.fx2, CertifiedKind.blockToggle, model: null, algorithmId: null, parameter: null, value: null, enabled: true, hex: 'b1 31 00'),
    CertifiedOperation(MatriboxChainSlot.amp, CertifiedKind.parameter, model: 'Sol 100 OD', algorithmId: 'sol100Od', parameter: 'Gain', value: 67.0, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 03 00 02 04 07 00 00 00 00 00 07 00 00 00 00 00 00 00 00 08 06 04 02 f7'),
    CertifiedOperation(MatriboxChainSlot.amp, CertifiedKind.parameter, model: 'Sol 100 OD', algorithmId: 'sol100Od', parameter: 'PRES', value: 59.0, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 03 00 02 04 07 00 00 00 00 00 07 00 01 00 00 00 00 00 00 06 0c 04 02 f7'),
    CertifiedOperation(MatriboxChainSlot.amp, CertifiedKind.parameter, model: 'Sol 100 OD', algorithmId: 'sol100Od', parameter: 'Bass', value: 41.0, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 03 00 02 04 07 00 00 00 00 00 07 00 03 00 00 00 00 00 00 02 04 04 02 f7'),
    CertifiedOperation(MatriboxChainSlot.amp, CertifiedKind.parameter, model: 'Sol 100 OD', algorithmId: 'sol100Od', parameter: 'Middle', value: 59.0, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 03 00 02 04 07 00 00 00 00 00 07 00 04 00 00 00 00 00 00 06 0c 04 02 f7'),
    CertifiedOperation(MatriboxChainSlot.amp, CertifiedKind.parameter, model: 'Sol 100 OD', algorithmId: 'sol100Od', parameter: 'Treble', value: 61.0, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 03 00 02 04 07 00 00 00 00 00 07 00 05 00 00 00 00 00 00 07 04 04 02 f7'),
    CertifiedOperation(MatriboxChainSlot.cab, CertifiedKind.modelSelect, model: 'Sol 4x12', algorithmId: 'catalog:Sol 4x12', parameter: null, value: null, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 05 00 01 02 08 00 00 00 00 00 0a f7'),
    CertifiedOperation(MatriboxChainSlot.cab, CertifiedKind.blockToggle, model: null, algorithmId: null, parameter: null, value: null, enabled: true, hex: 'b1 34 00'),
    CertifiedOperation(MatriboxChainSlot.eq, CertifiedKind.blockToggle, model: null, algorithmId: null, parameter: null, value: null, enabled: false, hex: 'b1 35 7f'),
  ],
);
const familyExpansionP01V1 = CertifiedRun(
  planId: 'FAMILY_EXPANSION_P01_V1',
  operations: [
    CertifiedOperation(MatriboxChainSlot.fx1, CertifiedKind.modelSelect, model: 'Boost', algorithmId: 'catalog:Boost', parameter: null, value: null, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 01 00 01 01 0a 00 00 00 00 00 00 f7'),
    CertifiedOperation(MatriboxChainSlot.fx2, CertifiedKind.modelSelect, model: 'Boost', algorithmId: 'catalog:Boost', parameter: null, value: null, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 02 00 01 01 0a 00 00 00 00 00 00 f7'),
    CertifiedOperation(MatriboxChainSlot.fx2, CertifiedKind.parameter, model: 'Boost', algorithmId: 'catalog:Boost', parameter: 'Gain', value: 23.0, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 02 00 02 01 0a 00 00 00 00 00 00 00 00 00 00 00 00 00 00 0b 08 04 01 f7'),
    CertifiedOperation(MatriboxChainSlot.fx2, CertifiedKind.parameter, model: 'Boost', algorithmId: 'catalog:Boost', parameter: 'Bright', value: 1.0, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 02 00 02 01 0a 00 00 00 00 00 00 00 02 00 00 00 00 00 00 08 00 03 0f f7'),
    CertifiedOperation(MatriboxChainSlot.amp, CertifiedKind.modelSelect, model: 'Sol 100 OD', algorithmId: 'sol100Od', parameter: null, value: null, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 03 00 01 04 07 00 00 00 00 00 07 f7'),
    CertifiedOperation(MatriboxChainSlot.nr, CertifiedKind.modelSelect, model: 'Gate 2', algorithmId: 'gate2', parameter: null, value: null, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 04 00 01 01 0d 00 00 00 00 00 00 f7'),
    CertifiedOperation(MatriboxChainSlot.nr, CertifiedKind.parameter, model: 'Gate 2', algorithmId: 'gate2', parameter: 'THRE', value: 31.0, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 04 00 02 01 0d 00 00 00 00 00 00 00 00 00 00 00 00 00 00 0f 08 04 01 f7'),
    CertifiedOperation(MatriboxChainSlot.nr, CertifiedKind.blockToggle, model: null, algorithmId: null, parameter: null, value: null, enabled: true, hex: 'b1 33 00'),
    CertifiedOperation(MatriboxChainSlot.cab, CertifiedKind.modelSelect, model: 'Sol 4x12', algorithmId: 'catalog:Sol 4x12', parameter: null, value: null, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 05 00 01 02 08 00 00 00 00 00 0a f7'),
    CertifiedOperation(MatriboxChainSlot.cab, CertifiedKind.parameter, model: 'Sol 4x12', algorithmId: 'catalog:Sol 4x12', parameter: 'VOL', value: 43.0, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 05 00 02 02 08 00 00 00 00 00 0a 00 01 00 00 00 00 00 00 02 0c 04 02 f7'),
    CertifiedOperation(MatriboxChainSlot.eq, CertifiedKind.modelSelect, model: 'Guitar EQ', algorithmId: 'catalog:Guitar EQ', parameter: null, value: null, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 06 00 01 03 05 00 00 00 00 00 01 f7'),
    CertifiedOperation(MatriboxChainSlot.eq, CertifiedKind.parameter, model: 'Guitar EQ', algorithmId: 'catalog:Guitar EQ', parameter: '400Hz', value: -23.0, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 06 00 02 03 05 00 00 00 00 00 01 00 01 00 00 00 00 00 00 0b 08 0c 01 f7'),
    CertifiedOperation(MatriboxChainSlot.eq, CertifiedKind.blockToggle, model: null, algorithmId: null, parameter: null, value: null, enabled: true, hex: 'b1 35 00'),
    CertifiedOperation(MatriboxChainSlot.mod, CertifiedKind.modelSelect, model: 'Chorus A', algorithmId: 'catalog:Chorus A', parameter: null, value: null, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 07 00 01 00 00 00 00 00 00 00 04 f7'),
    CertifiedOperation(MatriboxChainSlot.mod, CertifiedKind.parameter, model: 'Chorus A', algorithmId: 'catalog:Chorus A', parameter: 'Rate', value: 3.7, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 07 00 02 00 00 00 00 00 00 00 04 00 01 00 00 0c 0d 0c 0c 06 0c 04 00 f7'),
    CertifiedOperation(MatriboxChainSlot.dly, CertifiedKind.modelSelect, model: 'Warm', algorithmId: 'catalog:Warm', parameter: null, value: null, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 08 00 01 00 0d 00 00 00 00 00 0b f7'),
    CertifiedOperation(MatriboxChainSlot.dly, CertifiedKind.parameter, model: 'Warm', algorithmId: 'catalog:Warm', parameter: 'Time', value: 743.0, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 08 00 02 00 0d 00 00 00 00 00 0b 00 01 00 00 00 00 0c 00 03 09 04 04 f7'),
    CertifiedOperation(MatriboxChainSlot.dly, CertifiedKind.parameter, model: 'Warm', algorithmId: 'catalog:Warm', parameter: 'Trail', value: 1.0, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 08 00 02 00 0d 00 00 00 00 00 0b 00 04 00 00 00 00 00 00 08 00 03 0f f7'),
    CertifiedOperation(MatriboxChainSlot.rvb, CertifiedKind.modelSelect, model: 'Room', algorithmId: 'catalog:Room', parameter: null, value: null, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 09 00 01 00 00 00 00 00 00 00 0c f7'),
    CertifiedOperation(MatriboxChainSlot.rvb, CertifiedKind.parameter, model: 'Room', algorithmId: 'catalog:Room', parameter: 'Mix', value: 23.0, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 09 00 02 00 00 00 00 00 00 00 0c 00 00 00 00 00 00 00 00 0b 08 04 01 f7'),
    CertifiedOperation(MatriboxChainSlot.rvb, CertifiedKind.parameter, model: 'Room', algorithmId: 'catalog:Room', parameter: 'Decay', value: 41.0, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 09 00 02 00 00 00 00 00 00 00 0c 00 02 00 00 00 00 00 00 02 04 04 02 f7'),
    CertifiedOperation(MatriboxChainSlot.rvb, CertifiedKind.parameter, model: 'Room', algorithmId: 'catalog:Room', parameter: 'Trail', value: 1.0, enabled: null, hex: 'f0 21 25 7f 51 4d 45 32 12 10 09 00 02 00 00 00 00 00 00 00 0c 00 03 00 00 00 00 00 00 08 00 03 0f f7'),
    CertifiedOperation(MatriboxChainSlot.rvb, CertifiedKind.blockToggle, model: null, algorithmId: null, parameter: null, value: null, enabled: true, hex: 'b1 38 00'),
  ],
);
