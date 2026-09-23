/// Debug/certification wrapper of `FAMILY_EXPANSION_P01_V1` for the existing
/// Full Live infrastructure (session prepare -> executor -> manual save ->
/// readback/verifier). It adds ONLY: the certification plan, the manual-save
/// checkpoint, the closed channel adapter (plan id + backup hash) and the
/// PROMOTED evidence-family map. It has no transport of its own, sends
/// nothing by itself and never releases a productive family.
library;

import 'matribox_certification_plan.dart';
import 'matribox_chain_catalog.dart';
import 'matribox_chain_slot.dart';
import 'matribox_family_expansion_plan.dart';
import 'matribox_full_live_plan.dart';
import 'matribox_full_live_session.dart';
import 'matribox_model_library.dart';
import 'matribox_preset_layout.dart';
import 'matribox_raw_backup_service.dart';

/// File name of the family-expansion record inside the raw-backup directory.
const matriboxFamilyExpansionStateFileName = 'family_expansion_p01_v1.state';

/// The plan for the Full Live infrastructure. The operation list is
/// [FamilyExpansionPlan] INCLUDING Tier B (FX1 Boost, AMP Sol 100 OD select),
/// sorted into deterministic chain order: slots ascend FX1..RVB; inside a slot
/// MODEL SELECT, then PARAMETERs, then the block CC. That is the order the
/// productive plan validator and the native preflight enforce too: a select
/// resets the block's parameters, so parameters follow it, and a block is
/// switched ON only once it is configured.
class FamilyExpansionP01Plan implements CertificationPlan {
  FamilyExpansionP01Plan(MatriboxModelLibrary library)
    : offline = FamilyExpansionPlan(library),
      operations = List.unmodifiable([
        for (final slot in MatriboxChainSlot.values)
          for (final step in FamilyExpansionPlan(library).steps)
            if (step.operation.slot == slot) step.operation,
      ]);

  static const planIdValue = FamilyExpansionPlan.planId;

  /// Slots whose model select is already exactly hardware-confirmed; the
  /// target model may already be active there (a clean start for their parameters).
  static const selectAlreadyConfirmedSlots = {MatriboxChainSlot.fx2, MatriboxChainSlot.cab};

  final FamilyExpansionPlan offline;

  @override
  String get planId => planIdValue;
  @override
  String get title => 'FAMILY_EXPANSION_P01_V1';
  @override
  final List<FullLiveOperation> operations;

  int get modelCount => operations.where((o) => o.kind == FullLiveOperationKind.modelSelect).length;
  int get parameterCount => operations.where((o) => o.kind == FullLiveOperationKind.parameter).length;
  int get toggleCount => operations.where((o) => o.kind == FullLiveOperationKind.blockToggle).length;

  @override
  Map<MatriboxChainSlot, int> get requiredModelsAfter => const {};

  /// A select of the model that is already active, or an ON of a block that
  /// is already ON, proves nothing about that message family: the run could
  /// report CERTIFIED without testing it. Such a start state blocks (nothing
  /// is sent). FX2 Boost and CAB Sol 4x12 are already exactly confirmed and
  /// only serve as a clean start of their parameters.
  @override
  List<String> blockers(MatriboxPresetLayoutModel current) {
    final reasons = <String>[];
    for (final o in operations) {
      if (o.kind == FullLiveOperationKind.modelSelect &&
          !selectAlreadyConfirmedSlots.contains(o.slot) &&
          current.code(o.slot) == o.algorithm!.code) {
        reasons.add(
          'SELECT_NOT_OBSERVABLE: ${o.slot.label} hat bereits ${o.algorithm!.name}; die Modellwahl '
          'wäre nicht beobachtbar. Vorher im Editor ein Preset mit anderem Modell importieren.',
        );
      }
      if (o.kind == FullLiveOperationKind.blockToggle && o.enabled! && current.isOn(o.slot)) {
        reasons.add(
          'TOGGLE_NOT_OBSERVABLE: ${o.slot.label} ist bereits ON; das Einschalten wäre nicht '
          'beobachtbar. Vorher im Editor ausschalten.',
        );
      }
    }
    return reasons;
  }

  @override
  String? blockCode(MatriboxPresetLayoutModel current) {
    final reasons = blockers(current);
    return reasons.isEmpty ? null : reasons.first.split(':').first;
  }
}

/// The closed native call of this test: plan id + the verified backup hash.
/// Never bytes, algorithm ids, parameter indices or operations.
abstract interface class MatriboxFamilyExpansionChannel {
  Future<Map<Object?, Object?>> runFamilyExpansionP01Certification({
    required String planId,
    required String backupSha256,
  });
}

/// Lets the unchanged [MatriboxFullLiveExecutor] run this plan: it binds the
/// verified backup hash to the one call and refuses any other plan id.
class FamilyExpansionRunChannel implements MatriboxFullLiveChannel {
  const FamilyExpansionRunChannel(this.inner, this.backupSha256);
  final MatriboxFamilyExpansionChannel inner;
  final String backupSha256;

  @override
  Future<Map<Object?, Object?>> runFullLiveP01Certification(String planId) {
    if (planId != FamilyExpansionP01Plan.planIdValue) {
      throw StateError('Nur ${FamilyExpansionP01Plan.planIdValue} darf über diesen Kanal laufen.');
    }
    return inner.runFamilyExpansionP01Certification(planId: planId, backupSha256: backupSha256);
  }
}

enum FamilyExpansionStage {
  /// Nothing sent yet.
  beforeRun,

  /// The live write ended (completed or stopped): the device is VOLATILE. STOP.
  liveWriteDone,

  /// The user confirmed the physical check on the device.
  physicallyChecked,

  /// The user confirmed "Ich habe am Gerät gespeichert". WyrmTone sent nothing for it.
  manualSaveConfirmed,
}

/// The manual checkpoint between live write and verification. It holds only
/// in-memory state and has no channel: confirming sends ZERO MIDI. Neither a
/// restart nor a reconnect carries a confirmation over.
class FamilyExpansionCheckpoint {
  FamilyExpansionStage _stage = FamilyExpansionStage.beforeRun;
  FamilyExpansionStage get stage => _stage;

  void liveWriteEnded() => _stage = FamilyExpansionStage.liveWriteDone;

  void confirmPhysicalCheck() {
    if (_stage != FamilyExpansionStage.liveWriteDone) {
      throw StateError('Physische Prüfung erst nach dem Live-Write.');
    }
    _stage = FamilyExpansionStage.physicallyChecked;
  }

  void confirmManualSave() {
    if (_stage != FamilyExpansionStage.physicallyChecked) {
      throw StateError('Manuelles Speichern erst nach der physischen Prüfung bestätigen.');
    }
    _stage = FamilyExpansionStage.manualSaveConfirmed;
  }

  bool get manualSaveConfirmed => _stage == FamilyExpansionStage.manualSaveConfirmed;

  /// Verification (fresh full readback) may only start after the confirmation.
  bool get mayVerify => manualSaveConfirmed;

  void reset() => _stage = FamilyExpansionStage.beforeRun;
}

/// The final result labels of the test.
String familyExpansionResultLabel(FullLiveReadbackOutcome o) => switch (o) {
  FullLiveReadbackOutcome.certified => 'CERTIFIED',
  FullLiveReadbackOutcome.expectedChangeMissing => 'TARGET_MISMATCH',
  FullLiveReadbackOutcome.unexpectedKnownChange => 'UNEXPECTED_KNOWN_CHANGE',
  FullLiveReadbackOutcome.unknownRawChange => 'UNKNOWN_RAW_CHANGE',
  FullLiveReadbackOutcome.readFailed => 'READ_FAILED',
  FullLiveReadbackOutcome.backupMismatch => 'BACKUP_MISMATCH',
  FullLiveReadbackOutcome.partialExecution => 'PARTIAL_EXECUTION',
};

/// Only a CERTIFIED readback after the confirmed manual save is a
/// MANUAL_SAVE_PERSISTENCE_VERIFIED. It never means WyrmTone sent a Store.
const familyExpansionSuccessLabel = 'MANUAL_SAVE_PERSISTENCE_VERIFIED';

/// The fresh full readback + comparison, refused (StateError, no read) until
/// the manual save was confirmed.
Future<FullLiveReadbackResult> verifyFamilyExpansionAfterManualSave({
  required FamilyExpansionCheckpoint checkpoint,
  required MatriboxFullLiveRecord record,
  required MatriboxRawBackupService backupService,
  required MatriboxFullLiveStore store,
  required FamilyExpansionP01Plan plan,
  DateTime Function()? clock,
}) {
  if (!checkpoint.mayVerify) {
    throw StateError('Verification erst nach „Ich habe am Gerät gespeichert“.');
  }
  return MatriboxFullLiveReadback.run(
    record: record,
    backupService: backupService,
    store: store,
    plan: plan,
    clock: clock,
  );
}

class PromotedEvidenceFamily {
  const PromotedEvidenceFamily({
    required this.family,
    required this.slots,
    required this.requiredOperations,
    required this.upgradeTo,
    required this.note,
  });

  final String family;
  final List<MatriboxChainSlot> slots;

  /// The operations that must be verified after the manual save.
  final List<String> requiredOperations;
  final String upgradeTo;
  final String note;

  /// PROMOTED: the certified hardware run (2026-09-21) was followed by the separate promotion order;
  /// the families are productive through [MatriboxHardwareLedger.product] (Evidence V2). The decimal
  /// family has no productive parameter yet: every decimal parameter is bound to Sync (BIND_UNRESOLVED).
  String get status => family == 'DECIMAL_FAMILY' ? 'PROMOTED_BLOCKED_BY_BIND' : 'PROMOTED';

  Map<String, Object?> toJson() => {
    'family': family,
    'slots': [for (final s in slots) s.label],
    'requiredOperations': requiredOperations,
    'upgradeTo': upgradeTo,
    'status': status,
    'note': note,
  };
}

/// Machine-readable map of the evidence families that the CERTIFIED
/// FAMILY_EXPANSION_P01_V1 run promoted (technical writeability only, nothing musical).
/// The decision itself lives in [MatriboxEvidenceV2] over [MatriboxHardwareLedger.product].
abstract final class FamilyExpansionEvidenceUpgrades {
  /// True since the promotion order: the certified samples are part of the productive ledger.
  static const bool active = true;

  static const _familyLevel = 'FAMILY_CONFIRMED';

  static String _label(FullLiveOperation o) => '${o.slot.label} ${o.label}';

  static List<PromotedEvidenceFamily> forPlan(FamilyExpansionP01Plan plan) {
    final ops = plan.operations;
    final selects = [
      for (final o in ops)
        if (o.kind == FullLiveOperationKind.modelSelect) o,
    ];
    final upgrades = <PromotedEvidenceFamily>[
      PromotedEvidenceFamily(
        family: 'MODEL_SELECT_SLOT_FAMILY',
        slots: [for (final o in selects) o.slot],
        requiredOperations: [for (final o in selects) _label(o)],
        upgradeTo: _familyLevel,
        note: 'Alle 9 Slots; FX1 und AMP durch Tier B. Keine musikalische Eignung. User IR bleibt gesperrt.',
      ),
    ];
    void byKind(String family, Set<MatriboxParameterKind> kinds, String note) {
      final selected = [
        for (final o in ops)
          if (o.kind == FullLiveOperationKind.parameter && kinds.contains(o.parameter!.kind)) o,
      ];
      if (selected.isEmpty) return;
      upgrades.add(
        PromotedEvidenceFamily(
          family: family,
          slots: {for (final o in selected) o.slot}.toList(),
          requiredOperations: [for (final o in selected) _label(o)],
          upgradeTo: _familyLevel,
          note: note,
        ),
      );
    }

    byKind(
      'NUMBER_FAMILY',
      {MatriboxParameterKind.number},
      'Nur die tatsächlich getesteten Parameterfamilien je Slot; Wire-Index = Hersteller-ID − 1 (z. B. CAB VOL: ID 2 → Wire 1, Boost Bright: ID 3 → Wire 2).',
    );
    byKind('SIGNED_FAMILY', {MatriboxParameterKind.signedNumber}, 'Vorzeichenbehafteter Float32; nur EQ getestet.');
    byKind('DECIMAL_FAMILY', {MatriboxParameterKind.decimal}, 'Dezimaler Float32; nur MOD Rate getestet. Alle dezimalen Parameter sind an Sync gebunden und daher produktiv gesperrt.');
    byKind(
      'FLAG_FAMILY',
      {MatriboxParameterKind.flag},
      'Flag-Transport 0/1; bestätigt nicht die musikalische Bedeutung (Bright-Semantik UNKNOWN).',
    );
    upgrades.add(
      PromotedEvidenceFamily(
        family: 'BLOCK_CC_FAMILY',
        slots: MatriboxChainSlot.values,
        requiredOperations: [
          for (final o in ops)
            if (o.kind == FullLiveOperationKind.blockToggle) _label(o),
        ],
        upgradeTo: _familyLevel,
        note:
            'Alle 9 Slots, beide Richtungen; der Controller wird nativ aus dem Slot abgeleitet.',
      ),
    );
    return List.unmodifiable(upgrades);
  }

  static List<Map<String, Object?>> toJson(FamilyExpansionP01Plan plan) => [
    for (final u in forPlan(plan)) u.toJson(),
  ];
}
