/// The one predetermined "Full Live Edit Certification" operation list for
/// User P01. It is a fixed list of capture-confirmed model selections,
/// parameter writes and block toggles (the exact values/models of the big
/// capture); nothing is composed dynamically, nothing is stored.
///
/// Dart builds and verifies the plan; the native side holds its own
/// identical constant list (MatriboxFullLivePlan.kt) and is addressed only
/// by [planId] -- Dart never sends bytes. NO Store / commit (`12 12`),
/// no Save, no preset name/BPM/VOL, no User IR in this test.
library;

import 'matribox_chain_catalog.dart';
import 'matribox_chain_encoder.dart';
import 'matribox_chain_slot.dart';
import 'matribox_preset_layout.dart';

enum FullLiveOperationKind { modelSelect, parameter, blockToggle }

class FullLiveOperation {
  const FullLiveOperation._({
    required this.kind,
    required this.slot,
    required this.bytes,
    required this.label,
    this.algorithm,
    this.parameter,
    this.value,
    this.acceptedValues = const [],
    this.enabled,
  });

  factory FullLiveOperation.model(MatriboxChainSlot slot, MatriboxChainAlgorithm algorithm) =>
      FullLiveOperation._(
        kind: FullLiveOperationKind.modelSelect,
        slot: slot,
        algorithm: algorithm,
        bytes: MatriboxChainEncoder.modelSelect(slot, algorithm),
        label: 'MODEL ${algorithm.name}',
      );

  factory FullLiveOperation.parameter(
    MatriboxChainSlot slot,
    MatriboxChainAlgorithm algorithm,
    String parameterName,
    double value, {
    List<double> alsoAccepted = const [],
  }) {
    final parameter = algorithm.parameter(parameterName);
    return FullLiveOperation._(
      kind: FullLiveOperationKind.parameter,
      slot: slot,
      algorithm: algorithm,
      parameter: parameter,
      value: value,
      acceptedValues: [value, ...alsoAccepted],
      bytes: MatriboxChainEncoder.parameterWrite(slot, algorithm, parameter, value),
      label: 'PARAM $parameterName = ${_format(value)}',
    );
  }

  factory FullLiveOperation.toggle(MatriboxChainSlot slot, {required bool enabled}) =>
      FullLiveOperation._(
        kind: FullLiveOperationKind.blockToggle,
        slot: slot,
        enabled: enabled,
        bytes: MatriboxChainEncoder.blockToggle(slot, enabled: enabled),
        label: 'BLOCK ${enabled ? 'ON' : 'OFF'}',
      );

  final FullLiveOperationKind kind;
  final MatriboxChainSlot slot;
  final MatriboxChainAlgorithm? algorithm;
  final MatriboxChainParameter? parameter;
  final double? value;

  /// Values the readback may show for this parameter. Usually just [value];
  /// see [MatriboxFullLivePlan] for the one documented device conversion.
  final List<double> acceptedValues;
  final bool? enabled;
  final List<int> bytes;
  final String label;

  static String _format(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
}

abstract final class MatriboxFullLivePlan {
  static const planId = 'FULL_LIVE_P01_V1';

  /// Sent in this order, one message each; a fixed pause between messages
  /// (longer after a model select) is applied natively.
  static final List<FullLiveOperation> operations = List.unmodifiable([
    FullLiveOperation.model(MatriboxChainSlot.fx1, matriboxSkreamer),
    FullLiveOperation.parameter(MatriboxChainSlot.fx1, matriboxSkreamer, 'Gain', 23),
    FullLiveOperation.model(MatriboxChainSlot.fx2, matriboxBluesOd),
    FullLiveOperation.parameter(MatriboxChainSlot.fx2, matriboxBluesOd, 'Tone', 61),
    FullLiveOperation.model(MatriboxChainSlot.amp, matriboxBrit800),
    FullLiveOperation.parameter(MatriboxChainSlot.amp, matriboxBrit800, 'Gain', 17),
    FullLiveOperation.parameter(MatriboxChainSlot.amp, matriboxBrit800, 'PRES', 67),
    FullLiveOperation.model(MatriboxChainSlot.nr, matriboxGate2),
    FullLiveOperation.parameter(MatriboxChainSlot.nr, matriboxGate2, 'THRE', 31),
    FullLiveOperation.model(MatriboxChainSlot.cab, matriboxCabBritGn),
    FullLiveOperation.parameter(MatriboxChainSlot.cab, matriboxCabBritGn, 'VOL', 43),
    FullLiveOperation.model(MatriboxChainSlot.eq, matriboxBassEq),
    FullLiveOperation.parameter(MatriboxChainSlot.eq, matriboxBassEq, '50Hz', 17),
    FullLiveOperation.parameter(MatriboxChainSlot.eq, matriboxBassEq, '120Hz', -23),
    FullLiveOperation.model(MatriboxChainSlot.mod, matriboxFlanger),
    // Rate is written first, then Sync. In the capture the device itself
    // turned Rate into the note value 4 once Sync was on (AFTER export:
    // Rate 4, Sync 1), so 4.0 is also accepted for Rate at readback.
    FullLiveOperation.parameter(MatriboxChainSlot.mod, matriboxFlanger, 'Rate', 3.7, alsoAccepted: [4]),
    FullLiveOperation.parameter(MatriboxChainSlot.mod, matriboxFlanger, 'Sync', 1),
    FullLiveOperation.model(MatriboxChainSlot.dly, matriboxSweep),
    FullLiveOperation.parameter(MatriboxChainSlot.dly, matriboxSweep, 'Mix', 17),
    FullLiveOperation.parameter(MatriboxChainSlot.dly, matriboxSweep, 'Trail', 1),
    FullLiveOperation.model(MatriboxChainSlot.rvb, matriboxModRvb),
    FullLiveOperation.parameter(MatriboxChainSlot.rvb, matriboxModRvb, 'Mix', 23),
    FullLiveOperation.parameter(MatriboxChainSlot.rvb, matriboxModRvb, 'Trail', 1),
    // One currently ON block -> OFF, one currently OFF block -> ON. Not
    // toggled back: the changed state must stay visible on the device.
    FullLiveOperation.toggle(MatriboxChainSlot.fx1, enabled: false),
    FullLiveOperation.toggle(MatriboxChainSlot.fx2, enabled: true),
  ]);

  static int get modelCount =>
      operations.where((o) => o.kind == FullLiveOperationKind.modelSelect).length;
  static int get parameterCount =>
      operations.where((o) => o.kind == FullLiveOperationKind.parameter).length;
  static int get toggleCount =>
      operations.where((o) => o.kind == FullLiveOperationKind.blockToggle).length;

  static Iterable<MatriboxChainSlot> get slotsWithModelSelect => [
    for (final o in operations)
      if (o.kind == FullLiveOperationKind.modelSelect) o.slot,
  ];

  /// Minimum number of model selections that must actually change the
  /// current model; otherwise the test proves nothing observable.
  static const minimumObservableModelChanges = 6;

  /// Why P01's current state does not suit this plan, or an empty list.
  static List<String> blockers(MatriboxPresetLayoutModel current) {
    final reasons = <String>[];
    var changing = 0;
    for (final o in operations) {
      if (o.kind == FullLiveOperationKind.modelSelect &&
          current.code(o.slot) != o.algorithm!.code) {
        changing++;
      }
    }
    if (changing < minimumObservableModelChanges) {
      reasons.add(
        'Nur $changing von $modelCount Modellwahlen würden das aktuelle Modell '
        'ändern (mindestens $minimumObservableModelChanges nötig). P01 steht '
        'schon fast im Zielzustand -- vorher im Editor das Original-Preset '
        '(P01_BEFORE_BIG_CAPTURE.prst) wieder importieren.',
      );
    }
    if (!current.isOn(MatriboxChainSlot.fx1)) {
      reasons.add('FX1 ist bereits aus; der ON→OFF-Test wäre nicht beobachtbar.');
    }
    if (current.isOn(MatriboxChainSlot.fx2)) {
      reasons.add('FX2 ist bereits an; der OFF→ON-Test wäre nicht beobachtbar.');
    }
    return reasons;
  }
}
