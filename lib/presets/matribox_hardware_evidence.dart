/// HARDWARE evidence ledger: which live-edit operations have actually been
/// sent by WyrmTone to a real Matribox and verified (readback CERTIFIED).
/// CAPTURE_CONFIRMED (a real editor message exists) is deliberately NOT
/// enough for anything here.
///
/// Sources of hardware evidence:
/// 1. Baseline (historical, documented): Sol 100 OD Gain (first productive
///    write) and Sol 100 OD Presence (AMP certification), slot AMP.
/// 2. A Full Live Edit Certification of User P01 whose readback was
///    CERTIFIED (see [MatriboxFullLiveRecord]). What it proves is derived
///    from [MatriboxFullLivePlan] itself, not hard-coded.
///
/// Generalization rules (applied only after a CERTIFIED Full Live run):
/// - G1 MODEL SELECT: confirmed for a slot if a model select was certified
///   in that slot; valid for any algorithm whose PROTOCOL evidence for
///   select is capture-confirmed. The algorithm code is only payload, the
///   slot byte carries the risk.
/// - G2 PARAMETER WRITE: confirmed for (slot, value kind) if a parameter of
///   that kind was certified in that slot; valid for any capture-confirmed
///   parameter of that kind in that slot (payload = code, index, float).
///   Kinds/slots that were not certified stay unconfirmed.
/// - G3 BLOCK TOGGLE: the CC only differs in the controller number
///   (0x2F + slot). Confirmed for all nine slots if ON and OFF were both
///   certified, on at least two distinct slots; the capture showed 9/9
///   consistent controllers.
///
/// Nothing generalizes across value kinds or across slots for G1/G2.
library;

import 'matribox_certification_plan.dart';
import 'matribox_chain_catalog.dart';
import 'matribox_chain_slot.dart';
import 'matribox_full_live_plan.dart';
import 'matribox_full_live_session.dart';
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
    required this.modelSlots,
    required this.parameterKinds,
    required this.toggleConfirmed,
    required this.source,
    this.exactModels = const {},
    this.exactToggles = const {},
  });

  final Set<String> exact;
  final Set<MatriboxChainSlot> modelSlots;
  final Set<String> parameterKinds;
  final bool toggleConfirmed;
  final String source;

  /// `slot:algorithmId` of models whose exact MODEL SELECT was certified.
  final Set<String> exactModels;

  /// `slot:enabled` of exactly certified block toggles.
  final Set<String> exactToggles;

  static const generalizationRules = [
    'G1 MODEL SELECT: pro Slot nach zertifiziertem Full Live; gilt für jeden capture-bestätigten Algorithmus dieses Slots.',
    'G2 PARAMETER WRITE: pro (Slot, Werttyp) nach zertifiziertem Full Live; gilt für jeden capture-bestätigten Parameter dieses Typs im Slot.',
    'G3 BLOCK TOGGLE: alle neun Slots, wenn ON und OFF auf mindestens zwei Slots zertifiziert wurden (Controller = 0x2F + Slot, 9/9 im Capture).',
  ];

  /// Documented, NOT granted automatically: a catalog-only MODEL SELECT of
  /// another model would become eligible in slot S only after (a) a catalog-only
  /// select was certified in S, (b) the model's category matches S, and (c) an
  /// explicit product decision enables the rule. Until then only the exactly
  /// certified models are eligible.
  static const proposedCatalogSelectRule =
      'G4 (nicht aktiv): weitere Katalog-Modelle eines Slots erst nach ausdrücklicher Freigabe.';

  static String _key(MatriboxChainSlot slot, String algorithmId, String parameter) =>
      '${slot.name}:$algorithmId:$parameter';

  static String _kindKey(MatriboxChainSlot slot, MatriboxParameterKind kind) =>
      '${slot.name}:${kind.name}';

  /// Historical WyrmTone sends only (no Full Live evidence).
  static MatriboxHardwareLedger baseline() => MatriboxHardwareLedger._(
    exact: {
      _key(MatriboxChainSlot.amp, 'sol100Od', 'Gain'),
      _key(MatriboxChainSlot.amp, 'sol100Od', 'PRES'),
    },
    modelSlots: const {},
    parameterKinds: const {},
    toggleConfirmed: false,
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
    modelSlots: const {},
    parameterKinds: const {},
    toggleConfirmed: false,
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

  /// True only for a completed, fully CERTIFIED Full Live run of the current
  /// plan.
  static bool isCertified(MatriboxFullLiveRecord? record) =>
      record != null &&
      record.planId == MatriboxFullLivePlan.planId &&
      record.state == FullLiveRecordState.readbackDone &&
      record.readbackOutcome == 'certified' &&
      record.total == MatriboxFullLivePlan.operations.length &&
      record.completed == record.total;

  factory MatriboxHardwareLedger.fromFullLive(MatriboxFullLiveRecord? record) {
    final base = baseline();
    if (!isCertified(record)) return base;
    final slots = <MatriboxChainSlot>{};
    final kinds = <String>{};
    final onSlots = <MatriboxChainSlot>{};
    final offSlots = <MatriboxChainSlot>{};
    for (final op in MatriboxFullLivePlan.operations) {
      switch (op.kind) {
        case FullLiveOperationKind.modelSelect:
          slots.add(op.slot);
        case FullLiveOperationKind.parameter:
          kinds.add(_kindKey(op.slot, op.parameter!.kind));
        case FullLiveOperationKind.blockToggle:
          (op.enabled! ? onSlots : offSlots).add(op.slot);
      }
    }
    return MatriboxHardwareLedger._(
      exact: base.exact,
      modelSlots: slots,
      parameterKinds: kinds,
      toggleConfirmed:
          onSlots.isNotEmpty && offSlots.isNotEmpty && {...onSlots, ...offSlots}.length >= 2,
      source: 'Full Live Certification (${MatriboxFullLivePlan.planId}, Readback CERTIFIED)',
    );
  }

  /// True only for a completed, fully CERTIFIED run of exactly [plan].
  static bool isCertifiedFor(CertificationPlan plan, MatriboxFullLiveRecord? record) =>
      record != null &&
      record.planId == plan.planId &&
      record.state == FullLiveRecordState.readbackDone &&
      record.readbackOutcome == 'certified' &&
      record.total == plan.operations.length &&
      record.completed == record.total;

  /// Adds the EXACT operations of a certified [plan] (no generalization).
  MatriboxHardwareLedger withCertification(CertificationPlan plan, MatriboxFullLiveRecord? record) {
    if (!isCertifiedFor(plan, record)) return this;
    final exactParameters = {...exact};
    final models = {...exactModels};
    final toggles = {...exactToggles};
    for (final op in plan.operations) {
      switch (op.kind) {
        case FullLiveOperationKind.modelSelect:
          models.add('${op.slot.name}:${op.algorithm!.id}');
        case FullLiveOperationKind.parameter:
          exactParameters.add(_key(op.slot, op.algorithm!.id, op.parameter!.name));
        case FullLiveOperationKind.blockToggle:
          toggles.add('${op.slot.name}:${op.enabled}');
      }
    }
    return MatriboxHardwareLedger._(
      exact: exactParameters,
      modelSlots: modelSlots,
      parameterKinds: parameterKinds,
      toggleConfirmed: toggleConfirmed,
      source: '$source + ${plan.planId} (Readback CERTIFIED)',
      exactModels: models,
      exactToggles: toggles,
    );
  }

  HardwareEvidenceDecision model(MatriboxChainSlot slot, MatriboxTransferModel model) =>
      exactModels.contains('${slot.name}:${model.algorithm.id}')
      ? HardwareEvidenceDecision(
          true,
          'MODEL SELECT ${model.name} in ${slot.label} wurde von WyrmTone gesendet und verifiziert ($source).',
          exact: true,
        )
      : modelSlots.contains(slot)
      ? HardwareEvidenceDecision(true, 'G1: MODEL SELECT in ${slot.label} zertifiziert ($source).')
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
    if (parameterKinds.contains(_kindKey(slot, parameter.kind))) {
      return HardwareEvidenceDecision(
        true,
        'G2: ${parameter.kind.name}-Parameterwrite in ${slot.label} zertifiziert ($source).',
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
      : toggleConfirmed
      ? HardwareEvidenceDecision(true, 'G3: Block-CC ON/OFF zertifiziert ($source).')
      : const HardwareEvidenceDecision(false, 'BLOCK ON/OFF (CC) nicht hardware-bestätigt.');
}
