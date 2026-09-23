import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_chain_encoder.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_evidence_v2.dart';
import 'package:wyrmtone/presets/matribox_hardware_evidence.dart';
import 'package:wyrmtone/presets/matribox_model_library.dart';
import 'package:wyrmtone/presets/matribox_transfer_catalog.dart';

import 'support/matribox_certified_runs.dart';
import 'support/matribox_tone_transfer_support.dart';

/// The two CERTIFIED hardware runs are frozen evidence: the productive encoder must still produce
/// exactly their messages, and the productive ledger grants EXACT hardware evidence for exactly
/// their operations (plus the historical Sol 100 OD Gain/Presence sends) -- no more, no less.
void main() {
  final library = MatriboxModelLibrary.fromVendor(toneCatalog);
  final ledger = MatriboxHardwareLedger.product();
  final v2 = MatriboxEvidenceV2(library: library, samples: ActiveSamples.fromLedger(ledger, library));

  MatriboxTransferModel modelOf(CertifiedOperation o) =>
      library.byName(o.slot, o.model!) ?? (throw StateError('${o.slot.label} ${o.model} not in the library'));

  String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  List<String> kotlinGolden(String file) => [
    for (final m in RegExp(r'^\s*"([0-9a-f ]+)",', multiLine: true)
        .allMatches(File('android/app/src/test/kotlin/de/neevel/wyrmtone/$file').readAsStringSync()))
      m.group(1)!,
  ];

  test('the Dart evidence and the native goldens hold the same certified messages', () {
    expect(angelsDontKillP01V1.operations, hasLength(11));
    expect(familyExpansionP01V1.operations, hasLength(23));
    expect(angelsDontKillP01V1.operations.map((o) => o.hex), kotlinGolden('MatriboxAngelsGolden.kt'));
    expect(familyExpansionP01V1.operations.map((o) => o.hex), kotlinGolden('MatriboxFamilyExpansionGolden.kt'));
  });

  test('the productive encoder reproduces every certified message byte for byte', () {
    for (final run in certifiedRuns) {
      for (final o in run.operations) {
        final bytes = switch (o.kind) {
          CertifiedKind.modelSelect => MatriboxChainEncoder.modelSelect(o.slot, modelOf(o).algorithm),
          CertifiedKind.parameter => MatriboxChainEncoder.parameterWrite(
            o.slot,
            modelOf(o).algorithm,
            modelOf(o).algorithm.parameter(o.parameter!),
            o.value!,
          ),
          CertifiedKind.blockToggle => MatriboxChainEncoder.blockToggle(o.slot, enabled: o.enabled!),
        };
        expect(hex(bytes), o.hex, reason: '${run.planId} ${o.slot.label} ${o.kind.name} ${o.model ?? ''} ${o.parameter ?? ''}');
      }
    }
  });

  test('the productive ledger is exactly the certified operations plus the historical Gain/Presence sends', () {
    final all = [for (final r in certifiedRuns) ...r.operations];
    for (final o in all) {
      final decision = switch (o.kind) {
        CertifiedKind.modelSelect => ledger.model(o.slot, modelOf(o)),
        CertifiedKind.parameter => ledger.parameter(o.slot, modelOf(o), modelOf(o).algorithm.parameter(o.parameter!)),
        CertifiedKind.blockToggle => ledger.toggle(o.slot, o.enabled!),
      };
      expect((decision.confirmed, decision.exact), (true, true), reason: '${o.slot.label} ${o.kind.name} ${o.model} ${o.parameter}');
    }
    expect(ledger.exact, {
      for (final o in all.where((o) => o.kind == CertifiedKind.parameter)) '${o.slot.name}:${o.algorithmId}:${o.parameter}',
      'amp:sol100Od:Gain',
      'amp:sol100Od:PRES',
    });
    expect(ledger.exactModels, {for (final o in all.where((o) => o.kind == CertifiedKind.modelSelect)) '${o.slot.name}:${o.algorithmId}'});
    expect(ledger.exactToggles, {for (final o in all.where((o) => o.kind == CertifiedKind.blockToggle)) '${o.slot.name}:${o.enabled}'});
    // the baseline (nothing certified) holds only the historical Gain/Presence sends
    expect(MatriboxHardwareLedger.baseline().exact, {'amp:sol100Od:Gain', 'amp:sol100Od:PRES'});
    expect(MatriboxHardwareLedger.baseline().exactModels, isEmpty);
  });

  test('under Evidence V2 every certified operation is EXACT, except the Sync-bound Rate and Time which stay BLOCKED', () {
    for (final run in certifiedRuns) {
      for (final o in run.operations) {
        final level = switch (o.kind) {
          CertifiedKind.modelSelect => v2.modelSelect(o.slot, modelOf(o)).level,
          CertifiedKind.parameter => v2.parameter(o.slot, modelOf(o), modelOf(o).algorithm.parameter(o.parameter!), o.value!).level,
          CertifiedKind.blockToggle => v2.blockToggle(o.slot, o.enabled!).level,
        };
        final syncBound = (o.slot == MatriboxChainSlot.mod && o.parameter == 'Rate') || (o.slot == MatriboxChainSlot.dly && o.parameter == 'Time');
        expect(level, syncBound ? EvidenceLevel.blocked : EvidenceLevel.exactOperationConfirmed,
            reason: '${run.planId} ${o.slot.label} ${o.kind.name} ${o.model ?? ''} ${o.parameter ?? ''}');
      }
    }
  });
}
