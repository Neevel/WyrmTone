import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_preset_diff.dart';
import 'package:wyrmtone/presets/matribox_preset_write_plan.dart';
import 'package:wyrmtone/presets/matribox_semantic_preset.dart';
import 'package:wyrmtone/presets/preset_selection_codec.dart';
import 'package:wyrmtone/presets/protocol_evidence.dart';
import 'package:wyrmtone/presets/raw_preset_snapshot.dart';

import 'support/matribox_p01_readback_fixtures.dart';

MatriboxKnownField _field(double value, {EvidenceLevel writeEvidence = EvidenceLevel.unknown, int? catalogIndex}) =>
    MatriboxKnownField(
      value: value,
      identityEvidence: EvidenceLevel.confirmed,
      writeEvidence: writeEvidence,
      catalogIndex: catalogIndex,
    );

MatriboxSemanticPreset _targetWithGainOnly(double gain) => MatriboxSemanticPreset(
  name: 'Angels Don’t Kill',
  amp: MatriboxAmpBlock(
    algorithmName: 'Sol 100 OD',
    algorithmCode: 0x07000047,
    algorithmEvidence: EvidenceLevel.confirmed,
    gain: _field(gain, writeEvidence: EvidenceLevel.confirmed, catalogIndex: 0),
  ),
);

MatriboxSemanticPreset _targetWithGainAndBass(double gain, double bass) => MatriboxSemanticPreset(
  name: 'Angels Don’t Kill',
  amp: MatriboxAmpBlock(
    algorithmName: 'Sol 100 OD',
    algorithmCode: 0x07000047,
    algorithmEvidence: EvidenceLevel.confirmed,
    gain: _field(gain, writeEvidence: EvidenceLevel.confirmed, catalogIndex: 0),
    bass: _field(bass, catalogIndex: 3), // no write evidence
  ),
);

RawPresetSnapshot _p01Backup() => RawPresetSnapshot.capture(
  deviceLabel: 'Sonicake Matribox 1 84EF:0054',
  rawParts: matriboxP01RealFullCycle.map(matriboxHex).toList(),
);

void main() {
  final address = MatriboxPresetSlotAddress.fromPresetNumber(1);

  group('MatriboxPresetWritePlanner.plan', () {
    test('a single confirmed-writable Gain change is READY_FOR_HARDWARE_TEST', () {
      final backup = _p01Backup();
      final target = _targetWithGainOnly(43);
      final diff = MatriboxPresetDiff(
        nameBefore: 'CKY 96 STUD',
        nameAfter: target.name,
        ampChanges: const [
          MatriboxPresetFieldChange(field: 'gain', before: 17, after: 43, evidence: EvidenceLevel.confirmed),
        ],
      );

      final plan = MatriboxPresetWritePlanner.plan(
        targetAddress: address,
        currentBackup: backup,
        verifiedBackupSha256: backup.sha256,
        diff: diff,
        target: target,
      );

      expect(plan.gate, MatriboxWritePlanGate.readyForHardwareTest);
      expect(plan.blockers, isEmpty);
      expect(plan.operations, hasLength(1));
      expect(plan.operations.single.writable, isTrue);
      expect(plan.operations.single.catalogIndex, 0);
    });

    test('any non-writable field blocks the whole plan, not just that field', () {
      final backup = _p01Backup();
      final target = _targetWithGainAndBass(43, 48);
      final diff = MatriboxPresetDiff(
        nameBefore: 'CKY 96 STUD',
        nameAfter: target.name,
        ampChanges: const [
          MatriboxPresetFieldChange(field: 'gain', before: 17, after: 43, evidence: EvidenceLevel.confirmed),
          MatriboxPresetFieldChange(field: 'bass', before: 23, after: 48, evidence: EvidenceLevel.observed),
        ],
      );

      final plan = MatriboxPresetWritePlanner.plan(
        targetAddress: address,
        currentBackup: backup,
        verifiedBackupSha256: backup.sha256,
        diff: diff,
        target: target,
      );

      expect(plan.gate, MatriboxWritePlanGate.blocked);
      expect(
        plan.blockers,
        contains('Mindestens eine geplante Änderung ist nicht schreib-bestätigt.'),
      );
      final byField = {for (final op in plan.operations) op.field: op};
      expect(byField['gain']!.writable, isTrue);
      expect(byField['bass']!.writable, isFalse);
    });

    test('no backup at all blocks the plan', () {
      final target = _targetWithGainOnly(43);
      final plan = MatriboxPresetWritePlanner.plan(
        targetAddress: address,
        currentBackup: null,
        verifiedBackupSha256: null,
        diff: MatriboxPresetDiff(
          nameBefore: 'CKY 96 STUD',
          nameAfter: target.name,
          ampChanges: const [
            MatriboxPresetFieldChange(field: 'gain', before: 17, after: 43, evidence: EvidenceLevel.confirmed),
          ],
        ),
        target: target,
      );
      expect(plan.gate, MatriboxWritePlanGate.blocked);
      expect(
        plan.blockers,
        contains('Kein gültiges Raw-Backup des Zielslots vorhanden.'),
      );
    });

    test('an unverified backup hash blocks the plan even if a backup object is passed', () {
      final backup = _p01Backup();
      final target = _targetWithGainOnly(43);
      final plan = MatriboxPresetWritePlanner.plan(
        targetAddress: address,
        currentBackup: backup,
        verifiedBackupSha256: 'not-the-real-hash',
        diff: MatriboxPresetDiff(
          nameBefore: 'CKY 96 STUD',
          nameAfter: target.name,
          ampChanges: const [
            MatriboxPresetFieldChange(field: 'gain', before: 17, after: 43, evidence: EvidenceLevel.confirmed),
          ],
        ),
        target: target,
      );
      expect(plan.gate, MatriboxWritePlanGate.blocked);
      expect(
        plan.blockers,
        contains('Backup-Hash ist nicht unabhängig verifiziert.'),
      );
    });

    test('a Factory-bank backup blocks the plan, even with an otherwise valid change', () {
      final factoryParts = matriboxP01RealFullCycle.map(matriboxHex).toList();
      for (final part in factoryParts) {
        part[13] = 0x01; // Factory bank, consistent across all ten parts.
      }
      final backup = RawPresetSnapshot.capture(
        deviceLabel: 'Sonicake Matribox 1 84EF:0054',
        rawParts: factoryParts,
      );
      final target = _targetWithGainOnly(43);
      final plan = MatriboxPresetWritePlanner.plan(
        targetAddress: address,
        currentBackup: backup,
        verifiedBackupSha256: backup.sha256,
        diff: MatriboxPresetDiff(
          nameBefore: backup.presetName,
          nameAfter: target.name,
          ampChanges: const [
            MatriboxPresetFieldChange(field: 'gain', before: 17, after: 43, evidence: EvidenceLevel.confirmed),
          ],
        ),
        target: target,
      );
      expect(plan.gate, MatriboxWritePlanGate.blocked);
      expect(
        plan.blockers,
        contains('Factory-Bank ist außerhalb des Scopes.'),
      );
    });

    test('a target slot mismatched with the backup slot blocks the plan', () {
      final backup = _p01Backup(); // preset P01
      final target = _targetWithGainOnly(43);
      final plan = MatriboxPresetWritePlanner.plan(
        targetAddress: MatriboxPresetSlotAddress.fromPresetNumber(10), // P10
        currentBackup: backup,
        verifiedBackupSha256: backup.sha256,
        diff: MatriboxPresetDiff(
          nameBefore: 'CKY 96 STUD',
          nameAfter: target.name,
          ampChanges: const [
            MatriboxPresetFieldChange(field: 'gain', before: 17, after: 43, evidence: EvidenceLevel.confirmed),
          ],
        ),
        target: target,
      );
      expect(plan.gate, MatriboxWritePlanGate.blocked);
      expect(plan.blockers.any((b) => b.contains('Zielslot')), isTrue);
    });

    test('no planned changes at all blocks the plan', () {
      final backup = _p01Backup();
      const target = MatriboxSemanticPreset(name: 'CKY 96 STUD');
      final plan = MatriboxPresetWritePlanner.plan(
        targetAddress: address,
        currentBackup: backup,
        verifiedBackupSha256: backup.sha256,
        diff: const MatriboxPresetDiff(
          nameBefore: 'CKY 96 STUD',
          nameAfter: 'CKY 96 STUD',
          ampChanges: [],
        ),
        target: target,
      );
      expect(plan.gate, MatriboxWritePlanGate.blocked);
      expect(plan.blockers, contains('Keine geplanten Änderungen.'));
    });
  });
}
