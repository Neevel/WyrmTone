/// `FAMILY_EXPANSION_P01_V1`: the single, most informative next hardware
/// test. [FamilyExpansionPlan] is the OFFLINE data of the plan (steps with
/// their evidence purpose; validated against the evidence model in
/// test/matribox_evidence_v2_test.dart). [FamilyExpansionP01Plan] is the
/// debug/certification wrapper that runs those very operations through the
/// existing Full Live session/executor/verifier (see
/// matribox_family_expansion_certification.dart; own compile gate, only the
/// plan id and the backup hash cross the channel, the native side holds its
/// own constant operation list). This file stays pure data.
///
/// Rules of the plan: User P01 only; fresh read + backup + hash first; every
/// operation is catalog/capture-resolved (no free ids/indices); values are
/// values the editor itself wrote in the big capture (no extremes, no random
/// values); no Store, no metadata, no name/BPM/VOL. After the live run:
/// physical check -> manual device save -> fresh readback.
///
/// Nothing here releases a productive family.
library;

import 'matribox_chain_slot.dart';
import 'matribox_full_live_plan.dart';
import 'matribox_model_library.dart';

class FamilyExpansionStep {
  const FamilyExpansionStep(this.operation, this.purpose, {this.optional = false});
  final FullLiveOperation operation;

  /// The evidence question this operation answers.
  final String purpose;

  /// Tier B: closes a family gap that is not needed for song no. 2 itself.
  final bool optional;
}

class FamilyExpansionPlan {
  FamilyExpansionPlan(MatriboxModelLibrary library) : steps = _build(library);

  static const planId = 'FAMILY_EXPANSION_P01_V1';
  final List<FamilyExpansionStep> steps;

  List<FullLiveOperation> operations({bool includeOptional = false}) => [
    for (final s in steps)
      if (includeOptional || !s.optional) s.operation,
  ];

  static List<FamilyExpansionStep> _build(MatriboxModelLibrary library) {
    FullLiveOperation select(MatriboxChainSlot slot, String name) =>
        FullLiveOperation.model(slot, library.byName(slot, name)!.algorithm);
    FullLiveOperation param(MatriboxChainSlot slot, String model, String parameter, double value) =>
        FullLiveOperation.parameter(slot, library.byName(slot, model)!.algorithm, parameter, value);
    FullLiveOperation on(MatriboxChainSlot slot) => FullLiveOperation.toggle(slot, enabled: true);
    const fx2 = MatriboxChainSlot.fx2, nr = MatriboxChainSlot.nr, cab = MatriboxChainSlot.cab;
    const eq = MatriboxChainSlot.eq, mod = MatriboxChainSlot.mod, dly = MatriboxChainSlot.dly;
    const rvb = MatriboxChainSlot.rvb;
    return List.unmodifiable([
      FamilyExpansionStep(select(fx2, 'Boost'), 'Boost-Auswahl als sauberer Ausgangspunkt für den Drive-Parameter (exakt bereits bestätigt).'),
      FamilyExpansionStep(param(fx2, 'Boost', 'Gain', 23), 'Drive: erster Parameterwrite auf einem nur-Katalog-Modell in FX2 (Zahl, Index 0 wie Skreamer/Blues OD).'),
      FamilyExpansionStep(param(fx2, 'Boost', 'Bright', 1), 'Boolescher Switch 0/1 in FX2 (dritter Slot mit Flag-Sample neben DLY und RVB: gibt der Flag-Familie slotübergreifende Breite).'),
      FamilyExpansionStep(select(nr, 'Gate 2'), 'MODEL SELECT in NR (neue Kategorie, capture-bestätigter Code).'),
      FamilyExpansionStep(param(nr, 'Gate 2', 'THRE', 31), 'Gate2 THRE (Zahl in NR; Wert aus dem Capture) für die Gate-Heuristik.'),
      FamilyExpansionStep(on(nr), 'Block-CC ON auf NR (bisher nie aktiv gesendet).'),
      FamilyExpansionStep(select(cab, 'Sol 4x12'), 'Sol 4x12 als Ausgangspunkt für CAB VOL (exakt bereits bestätigt).'),
      FamilyExpansionStep(param(cab, 'Sol 4x12', 'VOL', 43), 'CAB VOL: Wire-Index 1 (Hersteller-ID 2 − 1) auf einem nur-Katalog-CAB (bisher nur BritGN im Capture).'),
      FamilyExpansionStep(select(eq, 'Guitar EQ'), 'MODEL SELECT nur-Katalog-Modell in EQ (neue Kategorie; Guitar EQ ist der Recipe-Standard).'),
      FamilyExpansionStep(param(eq, 'Guitar EQ', '400Hz', -23), 'Negativer Float32 (-23 stammt aus dem Capture) auf einem nur-Katalog-Parameter in EQ.'),
      FamilyExpansionStep(on(eq), 'Block-CC ON auf EQ (bisher nur OFF bestätigt).'),
      FamilyExpansionStep(select(mod, 'Chorus A'), 'MODEL SELECT nur-Katalog-Modell in MOD.'),
      FamilyExpansionStep(param(mod, 'Chorus A', 'Rate', 3.7), 'Dezimaler Float32 (3.7 aus dem Capture, Katalog-Step 0.1); Sync bleibt unberührt.'),
      FamilyExpansionStep(select(dly, 'Warm'), 'MODEL SELECT nur-Katalog-Modell in DLY.'),
      FamilyExpansionStep(param(dly, 'Warm', 'Time', 743), 'Zeitparameter 20..4000 ms (Wert aus dem Sweep-Capture).'),
      FamilyExpansionStep(param(dly, 'Warm', 'Trail', 1), 'Boolescher Switch 0/1 in DLY auf einem nur-Katalog-Parameter.'),
      FamilyExpansionStep(select(rvb, 'Room'), 'MODEL SELECT nur-Katalog-Modell in RVB (Recipe-Standard für wenig Hall).'),
      FamilyExpansionStep(param(rvb, 'Room', 'Mix', 23), 'Reverb Mix (Zahl, Wert aus Mod RVB) für die Reverb-Normalisierung.'),
      FamilyExpansionStep(param(rvb, 'Room', 'Decay', 41), 'Reverb Decay (Zahl, Wert aus Mod RVB).'),
      FamilyExpansionStep(param(rvb, 'Room', 'Trail', 1), 'Boolescher Switch 0/1 in RVB.'),
      FamilyExpansionStep(on(rvb), 'Block-CC ON auf RVB (Controller 0x38, äußerster Slot; bisher nie aktiv).'),
      FamilyExpansionStep(select(MatriboxChainSlot.fx1, 'Boost'), 'Tier B: MODEL SELECT nur-Katalog-Modell in FX1 (Zwilling von FX2).', optional: true),
      FamilyExpansionStep(select(MatriboxChainSlot.amp, 'Sol 100 OD'), 'Tier B: MODEL SELECT in AMP (Code aus Geräte-Reads); schließt die AMP-Familie.', optional: true),
    ]);
  }
}
