/// A fixed, closed hardware certification plan for User P01. The Full Live
/// session/executor/verifier/readback infrastructure runs any
/// [CertificationPlan]; the plan is identified natively only by [planId], and
/// the native side holds its own identical constant operation list. No plan
/// ever contains Store (`12 12`), metadata (`12 11`), name, BPM or VOL.
library;

import 'matribox_chain_slot.dart';
import 'matribox_full_live_plan.dart';
import 'matribox_preset_layout.dart';

abstract interface class CertificationPlan {
  String get planId;
  String get title;

  /// Sent in exactly this order (one message each).
  List<FullLiveOperation> get operations;

  /// Models that must be present after the run in slots the plan does not
  /// change (checked at readback).
  Map<MatriboxChainSlot, int> get requiredModelsAfter;

  /// Why P01's current state does not suit this plan, or an empty list.
  List<String> blockers(MatriboxPresetLayoutModel current);

  /// Machine readable reason of the first blocker (`SOURCE_PRESET_MISMATCH`,
  /// `ALREADY_AT_TARGET`, ...), or null.
  String? blockCode(MatriboxPresetLayoutModel current);
}

/// The original Full Live Edit Certification (`FULL_LIVE_P01_V1`).
class FullLiveP01Plan implements CertificationPlan {
  const FullLiveP01Plan();

  @override
  String get planId => MatriboxFullLivePlan.planId;
  @override
  String get title => 'Full Live Edit Certification';
  @override
  List<FullLiveOperation> get operations => MatriboxFullLivePlan.operations;
  @override
  Map<MatriboxChainSlot, int> get requiredModelsAfter => const {};
  @override
  List<String> blockers(MatriboxPresetLayoutModel current) => MatriboxFullLivePlan.blockers(current);
  @override
  String? blockCode(MatriboxPresetLayoutModel current) =>
      blockers(current).isEmpty ? null : 'SOURCE_PRESET_MISMATCH';
}
