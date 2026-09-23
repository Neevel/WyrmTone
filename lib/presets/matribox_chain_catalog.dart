/// Capture-confirmed chain algorithms and parameters. This is the evidence
/// layer between the catalog (semantic names) and the wire (codes/indices):
/// the encoder only ever resolves codes and parameter indices from here, so
/// no UI or caller can supply a raw algorithm id or parameter index.
///
/// An entry exists only if the editor big capture
/// (matribox1_p01_big_capture_20260919.pcapng) contains real messages for
/// it; test/matribox_chain_encoder_test.dart proves each one byte-for-byte.
/// Everything here is CAPTURE_CONFIRMED. None of it is
/// ACTIVE_WYRMTONE_HARDWARE_CONFIRMED yet -- the only sends WyrmTone has
/// done are Sol 100 OD Gain/Presence (slot AMP, code 0x07000047).
library;

import 'matribox_chain_slot.dart';

enum MatriboxParameterKind {
  /// Non-negative numeric knob.
  number,

  /// Numeric value that may be negative (EQ gain, reverb Lo/Hi End).
  signedNumber,

  /// Numeric value with a decimal step (e.g. modulation Rate 3.7 Hz).
  decimal,

  /// Switch sent as float 0.0 / 1.0 (Sync, Trail).
  flag,
}

class MatriboxChainParameter {
  const MatriboxChainParameter({
    required this.name,
    required this.wireIndex,
    required this.catalogIndex,
    required this.kind,
    this.minimum = 0,
    this.maximum = 99,
    this.defaultValue,
    this.xmlId,
    this.controlType = 'Knob',
    this.bind,
    this.subType,
    this.menuIds = const [],
    this.step,
    this.blockedReason,
  });

  /// Catalog (algorithm.xml) parameter name.
  final String name;

  /// Wire parameter index (u16 in the 34-byte write) = manufacturer ID - 1
  /// (matribox_parameter_addressing.dart); -1 when [blockedReason] is set.
  final int wireIndex;

  /// The manufacturer's display index (algorithm.xml `idx`). NEVER an address:
  /// it differs from [wireIndex] wherever the XML skips an ID (CAB VOL, Boost Bright ...).
  final int catalogIndex;
  final MatriboxParameterKind kind;
  final double minimum;
  final double maximum;

  /// Editor catalog default, if the catalog states one.
  final double? defaultValue;

  /// Manufacturer parameter ID (algorithm.xml `ID`); wire = xmlId - 1
  /// (matribox_parameter_addressing.dart). Null for hand-written capture entries.
  final int? xmlId;

  /// `Knob`, `Switch` or `Combox` (manufacturer control type).
  final String controlType;

  /// Manufacturer `bind` (e.g. `Sync`): the meaning of this value depends on another parameter.
  final String? bind;

  /// Manufacturer `SubType` (e.g. `Power`).
  final String? subType;

  /// Manufacturer menu IDs of a Switch/Combox.
  final List<int> menuIds;

  /// Manufacturer `Step` (decimal knobs), if any.
  final double? step;

  /// Set when the address is invalid (missing/duplicate ID ...): the parameter is BLOCKED.
  final String? blockedReason;

  bool accepts(double value) {
    if (blockedReason != null) return false;
    if (!value.isFinite) return false;
    if (kind == MatriboxParameterKind.flag) return value == 0 || value == 1;
    return value >= minimum && value <= maximum;
  }
}

class MatriboxChainAlgorithm {
  const MatriboxChainAlgorithm({
    required this.id,
    required this.name,
    required this.code,
    required this.slots,
    required this.parameters,
    this.sendableInFullLive = true,
    this.note,
  });

  final String id;

  /// Catalog name (algorithm.xml).
  final String name;
  final int code;

  /// Slots this algorithm was actually seen in (capture evidence).
  final Set<MatriboxChainSlot> slots;
  final List<MatriboxChainParameter> parameters;

  /// False for entries that are only documented (User IR).
  final bool sendableInFullLive;
  final String? note;

  MatriboxChainParameter parameter(String parameterName) =>
      parameters.singleWhere((p) => p.name == parameterName);
}

const _knob = MatriboxParameterKind.number;
const _signed = MatriboxParameterKind.signedNumber;
const _flag = MatriboxParameterKind.flag;

MatriboxChainParameter _p(String name, int index, {MatriboxParameterKind kind = _knob, double min = 0, double max = 99, int? catalogIndex}) =>
    MatriboxChainParameter(
      name: name,
      wireIndex: index,
      catalogIndex: catalogIndex ?? index,
      kind: kind,
      minimum: min,
      maximum: max,
    );

const _drive3 = <MatriboxChainParameter>[
  MatriboxChainParameter(name: 'Gain', wireIndex: 0, catalogIndex: 0, kind: _knob),
  MatriboxChainParameter(name: 'Tone', wireIndex: 1, catalogIndex: 1, kind: _knob),
  MatriboxChainParameter(name: 'VOL', wireIndex: 2, catalogIndex: 2, kind: _knob),
];

final matriboxSkreamer = MatriboxChainAlgorithm(
  id: 'skreamer',
  name: 'Skreamer',
  code: 0x03000000,
  slots: {MatriboxChainSlot.fx1, MatriboxChainSlot.fx2},
  parameters: _drive3,
);

final matriboxBluesOd = MatriboxChainAlgorithm(
  id: 'bluesOd',
  name: 'Blues OD',
  code: 0x03000009,
  slots: {MatriboxChainSlot.fx2},
  parameters: _drive3,
);

final matriboxBrit800 = MatriboxChainAlgorithm(
  id: 'brit800',
  name: 'Brit 800',
  code: 0x07000035,
  slots: {MatriboxChainSlot.amp},
  parameters: [
    _p('Gain', 0),
    _p('PRES', 1),
    _p('Master', 2),
    _p('Bass', 3),
    _p('Middle', 4),
    _p('Treble', 5),
  ],
);

final matriboxGate1 = MatriboxChainAlgorithm(
  id: 'gate1',
  name: 'Gate 1',
  code: 0x0000001b,
  slots: {MatriboxChainSlot.nr},
  parameters: [_p('THRE', 0)],
);

final matriboxGate2 = MatriboxChainAlgorithm(
  id: 'gate2',
  name: 'Gate 2',
  code: 0x0000001d,
  slots: {MatriboxChainSlot.nr},
  parameters: [_p('THRE', 0), _p('ATK', 1), _p('Rel', 2)],
);

/// Normal cabinet chosen in the capture (catalog name "BritGN 4x12"; the
/// plan asked for "BritMD 4x12", see docs). VOL is wire index 1.
final matriboxCabBritGn = MatriboxChainAlgorithm(
  id: 'cabBritGn4x12',
  name: 'BritGN 4x12',
  code: 0x0a000022,
  slots: {MatriboxChainSlot.cab},
  parameters: [_p('VOL', 1, catalogIndex: 0)],
);

/// Observed only for User IR 7. The general "User IR n = 0x0a100000 + n - 1"
/// formula is CORRELATED/HYPOTHESIS; this entry is documentation, not sendable.
final matriboxUserIr7 = MatriboxChainAlgorithm(
  id: 'userIr7',
  name: 'User IR 7',
  code: 0x0a100006,
  slots: {MatriboxChainSlot.cab},
  parameters: [_p('VOL', 1, catalogIndex: 0)],
  sendableInFullLive: false,
  note: 'Only User IR 7 is capture-confirmed; other slots are hypothesis.',
);

final matriboxBassEq = MatriboxChainAlgorithm(
  id: 'bassEq',
  name: 'Bass EQ',
  code: 0x0100003a,
  slots: {MatriboxChainSlot.eq},
  parameters: [
    _p('50Hz', 0, kind: _signed, min: -50, max: 50),
    _p('120Hz', 1, kind: _signed, min: -50, max: 50),
    _p('400Hz', 2, kind: _signed, min: -50, max: 50),
    _p('800Hz', 3, kind: _signed, min: -50, max: 50),
    _p('2kHz', 4, kind: _signed, min: -50, max: 50),
    _p('VOL', 5),
  ],
);

final matriboxFlanger = MatriboxChainAlgorithm(
  id: 'flanger',
  name: 'Flanger',
  code: 0x04000011,
  slots: {MatriboxChainSlot.mod},
  parameters: [
    _p('Depth', 0),
    _p('Rate', 1, kind: MatriboxParameterKind.decimal, min: 0.1, max: 10),
    _p('PreDly', 2),
    _p('FdBk', 3),
    _p('Sync', 4, kind: _flag),
  ],
);

final matriboxSweep = MatriboxChainAlgorithm(
  id: 'sweep',
  name: 'Sweep',
  code: 0x0b000006,
  slots: {MatriboxChainSlot.dly},
  parameters: [
    _p('Mix', 0),
    _p('FdBk', 1),
    _p('Time', 2, min: 20, max: 4000),
    _p('Swp Depth', 3),
    _p('Swp Rate', 4),
    _p('Swp Sync', 5, kind: _flag),
    _p('Time Sync', 6, kind: _flag),
    _p('Trail', 7, kind: _flag),
  ],
);

final matriboxModRvb = MatriboxChainAlgorithm(
  id: 'modRvb',
  name: 'Mod RVB',
  code: 0x0c000008,
  slots: {MatriboxChainSlot.rvb},
  parameters: [
    _p('Mix', 0),
    _p('Pre Delay', 1, max: 100),
    _p('Decay', 2),
    _p('Lo End', 3, kind: _signed, min: -50, max: 50),
    _p('Hi End', 4, kind: _signed, min: -50, max: 50),
    _p('Trail', 5, kind: _flag),
  ],
);

final matriboxCaptureConfirmedAlgorithms = <MatriboxChainAlgorithm>[
  matriboxSkreamer,
  matriboxBluesOd,
  matriboxBrit800,
  matriboxGate1,
  matriboxGate2,
  matriboxCabBritGn,
  matriboxUserIr7,
  matriboxBassEq,
  matriboxFlanger,
  matriboxSweep,
  matriboxModRvb,
];
