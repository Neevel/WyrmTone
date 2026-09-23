/// HARDWARE evidence ledger: which live-edit operations have actually been
/// sent by WyrmTone to a real Matribox and verified (readback CERTIFIED).
/// CAPTURE_CONFIRMED (a real editor message exists) is deliberately NOT
/// enough for anything here.
///
/// This is frozen, read-only evidence data. Sources:
/// 1. Baseline (historical, documented): Sol 100 OD Gain (first productive
///    write) and Sol 100 OD Presence (AMP certification), slot AMP.
/// 2. The CERTIFIED runs ANGELS_DONT_KILL_P01_V1 and FAMILY_EXPANSION_P01_V1
///    (their exact operations and messages are frozen in
///    test/support/matribox_certified_runs.dart and the native goldens).
/// The certification runners that produced them were removed; nothing here
/// can grant new evidence at runtime. The Full Live generalization rules
/// (G1-G3) were never part of the productive ledger and are gone with the
/// Full Live runner.
library;

import 'matribox_chain_catalog.dart';
import 'matribox_chain_slot.dart';
import 'matribox_transfer_catalog.dart';

class HardwareEvidenceDecision {
  const HardwareEvidenceDecision(this.confirmed, this.basis, {this.exact = false});
  final bool confirmed;
  final String basis;

  /// The exact operation (this model / this parameter / this toggle) was sent
  /// by WyrmTone and verified; needs no protocol generalization.
  final bool exact;
}

class MatriboxHardwareLedger {
  const MatriboxHardwareLedger._({
    required this.exact,
    required this.source,
    this.exactModels = const {},
    this.exactToggles = const {},
  });

  final Set<String> exact;
  final String source;

  /// `slot:algorithmId` of models whose exact MODEL SELECT was certified.
  final Set<String> exactModels;

  /// `slot:enabled` of exactly certified block toggles.
  final Set<String> exactToggles;

  static String _key(MatriboxChainSlot slot, String algorithmId, String parameter) =>
      '${slot.name}:$algorithmId:$parameter';

  /// Historical WyrmTone sends only (no Full Live evidence).
  static MatriboxHardwareLedger baseline() => MatriboxHardwareLedger._(
    exact: {
      _key(MatriboxChainSlot.amp, 'sol100Od', 'Gain'),
      _key(MatriboxChainSlot.amp, 'sol100Od', 'PRES'),
    },
    source: 'Baseline: Sol 100 OD Gain und Presence (AMP)',
  );

  /// The hardware evidence of the PRODUCTIVE transport: the older Sol 100 OD
  /// Gain/Presence sends, EXACTLY the operations of the CERTIFIED Angels Dont
  /// Kill product-unlock run (2026-09-20) and EXACTLY the 23 operations of the
  /// CERTIFIED FAMILY_EXPANSION_P01_V1 run (2026-09-21, wire = ID - 1,
  /// readback after manual device save). These are ACTIVE samples; the family
  /// rules of [MatriboxEvidenceV2] generalize them. The native table
  /// (MatriboxManufacturerCatalog.kt) is generated from the same decisions.
  static MatriboxHardwareLedger product() => MatriboxHardwareLedger._(
    exact: {
      _key(MatriboxChainSlot.amp, 'sol100Od', 'Gain'),
      _key(MatriboxChainSlot.amp, 'sol100Od', 'PRES'),
      _key(MatriboxChainSlot.amp, 'sol100Od', 'Bass'),
      _key(MatriboxChainSlot.amp, 'sol100Od', 'Middle'),
      _key(MatriboxChainSlot.amp, 'sol100Od', 'Treble'),
      // FAMILY_EXPANSION_P01_V1
      _key(MatriboxChainSlot.fx2, 'catalog:Boost', 'Gain'),
      _key(MatriboxChainSlot.fx2, 'catalog:Boost', 'Bright'),
      _key(MatriboxChainSlot.nr, 'gate2', 'THRE'),
      _key(MatriboxChainSlot.cab, 'catalog:Sol 4x12', 'VOL'),
      _key(MatriboxChainSlot.eq, 'catalog:Guitar EQ', '400Hz'),
      _key(MatriboxChainSlot.mod, 'catalog:Chorus A', 'Rate'),
      _key(MatriboxChainSlot.dly, 'catalog:Warm', 'Time'),
      _key(MatriboxChainSlot.dly, 'catalog:Warm', 'Trail'),
      _key(MatriboxChainSlot.rvb, 'catalog:Room', 'Mix'),
      _key(MatriboxChainSlot.rvb, 'catalog:Room', 'Decay'),
      _key(MatriboxChainSlot.rvb, 'catalog:Room', 'Trail'),
    },
    source: 'Hardware-CERTIFIED: ANGELS_DONT_KILL_P01_V1 + FAMILY_EXPANSION_P01_V1 (Readback nach manuellem Save) + Sol 100 OD Gain/Presence',
    exactModels: const {
      'fx2:catalog:Boost',
      'cab:catalog:Sol 4x12',
      // FAMILY_EXPANSION_P01_V1
      'fx1:catalog:Boost',
      'amp:sol100Od',
      'nr:gate2',
      'eq:catalog:Guitar EQ',
      'mod:catalog:Chorus A',
      'dly:catalog:Warm',
      'rvb:catalog:Room',
    },
    exactToggles: const {'fx1:false', 'fx2:true', 'cab:true', 'eq:false', 'nr:true', 'eq:true', 'rvb:true'},
  );

  HardwareEvidenceDecision model(MatriboxChainSlot slot, MatriboxTransferModel model) =>
      exactModels.contains('${slot.name}:${model.algorithm.id}')
      ? HardwareEvidenceDecision(
          true,
          'MODEL SELECT ${model.name} in ${slot.label} wurde von WyrmTone gesendet und verifiziert ($source).',
          exact: true,
        )
      : HardwareEvidenceDecision(false, 'MODEL SELECT in ${slot.label} nicht hardware-bestätigt.');

  HardwareEvidenceDecision parameter(
    MatriboxChainSlot slot,
    MatriboxTransferModel model,
    MatriboxChainParameter parameter,
  ) {
    if (exact.contains(_key(slot, model.algorithm.id, parameter.name))) {
      return HardwareEvidenceDecision(
        true,
        '${model.name}/${parameter.name} wurde von WyrmTone gesendet und verifiziert.',
        exact: true,
      );
    }
    return HardwareEvidenceDecision(
      false,
      'PARAMETER WRITE ${slot.label}/${parameter.kind.name} nicht hardware-bestätigt.',
    );
  }

  HardwareEvidenceDecision toggle(MatriboxChainSlot slot, bool enabled) =>
      exactToggles.contains('${slot.name}:$enabled')
      ? HardwareEvidenceDecision(true, 'Block ${slot.label} ${enabled ? 'ON' : 'OFF'} exakt zertifiziert ($source).', exact: true)
      : const HardwareEvidenceDecision(false, 'BLOCK ON/OFF (CC) nicht hardware-bestätigt.');
}
