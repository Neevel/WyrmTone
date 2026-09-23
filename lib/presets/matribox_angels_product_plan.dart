/// `ANGELS_DONT_KILL_P01_V1`: the product-near hardware certification. It
/// executes exactly the current Sound Engine V2 write plan for Children of
/// Bodom -- Angels Don't Kill (HB Fusion 4, Drop C) against a known User P01
/// state, through the existing Full Live infrastructure:
///
///   FX1 OFF | FX2 Boost, ON | AMP Sol 100 OD Gain 67, PRES 59, Bass 41,
///   Middle 59, Treble 61 | CAB Sol 4x12, ON | EQ OFF
///
/// Models come from the editor catalog only (no free-form id): Boost
/// `0x0000001a` (FX), Sol 4x12 `0x0a000028` (CAB). The known source state
/// (P01 "CKY 96 STUD") is a CERTIFICATION PRECONDITION only -- the normal
/// Sound Engine never sees it. No Store, no `12 11`, no name/BPM/VOL, no
/// NR/RVB parameter write. Both sides hold the same fixed list; native
/// addresses it only by [planIdValue].
library;

import 'matribox_certification_plan.dart';
import 'matribox_chain_slot.dart';
import 'matribox_full_live_plan.dart';
import 'matribox_hardware_evidence.dart';
import 'matribox_model_library.dart';
import 'matribox_preset_layout.dart';
import 'matribox_target_preset.dart';
import 'matribox_tone_transfer_plan.dart';
import 'matribox_transfer_catalog.dart';

/// File name of the Angels certification record inside the raw-backup directory.
const matriboxAngelsStateFileName = 'angels_product_certification.state';

/// The certification's expected starting point (the real P01 read of the big
/// capture session, decoded programmatically in the tests).
abstract final class AngelsCertificationSource {
  static const presetName = 'CKY 96 STUD';
  static const codes = <MatriboxChainSlot, int>{
    MatriboxChainSlot.fx1: 0x01000021,
    MatriboxChainSlot.fx2: 0x03000000,
    MatriboxChainSlot.amp: 0x07000047,
    MatriboxChainSlot.nr: 0x0000001d,
    MatriboxChainSlot.cab: 0x0a000006,
    MatriboxChainSlot.eq: 0x01000035,
    MatriboxChainSlot.mod: 0x04000000,
    MatriboxChainSlot.dly: 0x0b00000d,
    MatriboxChainSlot.rvb: 0x0c000000,
  };
  static const blockStates = <MatriboxChainSlot, bool>{
    MatriboxChainSlot.fx1: true,
    MatriboxChainSlot.fx2: false,
    MatriboxChainSlot.amp: true,
    MatriboxChainSlot.nr: true,
    MatriboxChainSlot.cab: false,
    MatriboxChainSlot.eq: true,
    MatriboxChainSlot.mod: false,
    MatriboxChainSlot.dly: false,
    MatriboxChainSlot.rvb: true,
  };

  /// AMP wire index -> value (Gain, PRES, Bass, Middle, Treble).
  static const ampParameters = <int, double>{0: 18, 1: 74, 3: 23, 4: 67, 5: 31};
}

class AngelsProductPlan implements CertificationPlan {
  AngelsProductPlan({required this.library, this.target});

  static const planIdValue = 'ANGELS_DONT_KILL_P01_V1';

  final MatriboxModelLibrary library;

  /// The Sound Engine V2 target; when given, the production diff must equal
  /// this plan's operations for the plan to run.
  final MatriboxTargetPreset? target;

  @override
  String get planId => planIdValue;
  @override
  String get title => "Angels Don't Kill – Product Unlock";

  /// Resolved from the catalog by name and slot only.
  MatriboxTransferModel get boost => library.byName(MatriboxChainSlot.fx2, 'Boost')!;
  MatriboxTransferModel get sol4x12 => library.byName(MatriboxChainSlot.cab, 'Sol 4x12')!;
  MatriboxTransferModel get sol100Od => MatriboxTransferCatalog.byName('Sol 100 OD')!;

  @override
  late final List<FullLiveOperation> operations = List.unmodifiable([
    FullLiveOperation.toggle(MatriboxChainSlot.fx1, enabled: false),
    FullLiveOperation.model(MatriboxChainSlot.fx2, boost.algorithm),
    FullLiveOperation.toggle(MatriboxChainSlot.fx2, enabled: true),
    FullLiveOperation.parameter(MatriboxChainSlot.amp, sol100Od.algorithm, 'Gain', 67),
    FullLiveOperation.parameter(MatriboxChainSlot.amp, sol100Od.algorithm, 'PRES', 59),
    FullLiveOperation.parameter(MatriboxChainSlot.amp, sol100Od.algorithm, 'Bass', 41),
    FullLiveOperation.parameter(MatriboxChainSlot.amp, sol100Od.algorithm, 'Middle', 59),
    FullLiveOperation.parameter(MatriboxChainSlot.amp, sol100Od.algorithm, 'Treble', 61),
    FullLiveOperation.model(MatriboxChainSlot.cab, sol4x12.algorithm),
    FullLiveOperation.toggle(MatriboxChainSlot.cab, enabled: true),
    FullLiveOperation.toggle(MatriboxChainSlot.eq, enabled: false),
  ]);

  int get modelCount => operations.where((o) => o.kind == FullLiveOperationKind.modelSelect).length;
  int get parameterCount => operations.where((o) => o.kind == FullLiveOperationKind.parameter).length;
  int get toggleCount => operations.where((o) => o.kind == FullLiveOperationKind.blockToggle).length;

  /// The AMP model is not selected (already Sol 100 OD) but must still be it afterwards.
  @override
  Map<MatriboxChainSlot, int> get requiredModelsAfter => {MatriboxChainSlot.amp: sol100Od.code};

  bool _matchesSource(MatriboxPresetLayoutModel c) {
    if (c.name != AngelsCertificationSource.presetName) return false;
    for (final slot in MatriboxChainSlot.values) {
      if (c.code(slot) != AngelsCertificationSource.codes[slot]) return false;
      if (c.isOn(slot) != AngelsCertificationSource.blockStates[slot]) return false;
    }
    return AngelsCertificationSource.ampParameters.entries.every(
      (e) => (c.parameter(MatriboxChainSlot.amp, e.key) - e.value).abs() < 0.5,
    );
  }

  bool _isAlreadyTarget(MatriboxPresetLayoutModel c) {
    if (c.isOn(MatriboxChainSlot.fx1) ||
        !c.isOn(MatriboxChainSlot.fx2) ||
        c.code(MatriboxChainSlot.fx2) != boost.code ||
        !c.isOn(MatriboxChainSlot.cab) ||
        c.code(MatriboxChainSlot.cab) != sol4x12.code ||
        c.isOn(MatriboxChainSlot.eq) ||
        c.code(MatriboxChainSlot.amp) != sol100Od.code) {
      return false;
    }
    for (final o in operations) {
      if (o.kind == FullLiveOperationKind.parameter &&
          (c.parameter(o.slot, o.parameter!.wireIndex) - o.value!).abs() >= 0.5) {
        return false;
      }
    }
    return true;
  }

  String _key(FullLiveOperation o) => switch (o.kind) {
    FullLiveOperationKind.modelSelect => '${o.slot.label}|MODEL|${o.algorithm!.name}',
    FullLiveOperationKind.parameter =>
      '${o.slot.label}|${matriboxSemanticName(o.parameter!.name)}|${o.value!.toStringAsFixed(0)}',
    FullLiveOperationKind.blockToggle => '${o.slot.label}|BLOCK|${o.enabled! ? 'ON' : 'OFF'}',
  };

  String _entryKey(ToneTransferEntry e) => '${e.slot.label}|${e.subject}|${e.target}';

  @override
  String? blockCode(MatriboxPresetLayoutModel current) {
    if (_isAlreadyTarget(current)) return 'ALREADY_AT_TARGET';
    if (!_matchesSource(current)) return 'SOURCE_PRESET_MISMATCH';
    if (_productionMismatch(current).isNotEmpty) return 'PLAN_MISMATCH';
    return null;
  }

  List<String> _productionMismatch(MatriboxPresetLayoutModel current) {
    final production = target;
    if (production == null) return const [];
    final plan = MatriboxToneTransferPlan.build(
      current: current,
      target: production,
      ledger: MatriboxHardwareLedger.baseline(),
      backupSha256: 'certification-diff',
      presetNumber: 1,
      isUserBank: true,
      transportAvailable: true,
      library: library,
    );
    final wanted = operations.map(_key).toList();
    final actual = [for (final e in plan.entries.where((e) => e.isChange)) _entryKey(e)];
    if (wanted.length == actual.length && [for (var i = 0; i < wanted.length; i++) wanted[i] == actual[i]].every((x) => x)) {
      return const [];
    }
    return ['Produktionsdiff (${actual.join(', ')}) entspricht nicht dem Certification-Plan (${wanted.join(', ')}).'];
  }

  @override
  List<String> blockers(MatriboxPresetLayoutModel current) {
    if (_isAlreadyTarget(current)) {
      return [
        'ALREADY_AT_TARGET: P01 hat bereits den Angels-Zielzustand. Vorher im Editor das '
            'Ausgangs-Preset "${AngelsCertificationSource.presetName}" wieder importieren; es wird nichts gesendet.',
      ];
    }
    if (!_matchesSource(current)) {
      return [
        'SOURCE_PRESET_MISMATCH: P01 ist nicht der erwartete Certification-Ausgangspunkt '
            '"${AngelsCertificationSource.presetName}" (gelesen: "${current.name}"). '
            'Vorher im Editor das Ausgangs-Preset importieren; es wird nichts gesendet.',
      ];
    }
    return [for (final m in _productionMismatch(current)) 'PLAN_MISMATCH: $m'];
  }
}
