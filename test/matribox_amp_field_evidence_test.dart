import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_amp_field_evidence.dart';
import 'package:wyrmtone/presets/protocol_evidence.dart';

void main() {
  group('MatriboxAmpFieldEvidenceRegistry', () {
    test('exactly the six confirmed AMP fields, in wire order', () {
      expect(
        MatriboxAmpFieldEvidenceRegistry.all.map((f) => f.field).toList(),
        ['gain', 'presence', 'volume', 'bass', 'middle', 'treble'],
      );
      expect(
        MatriboxAmpFieldEvidenceRegistry.all.map((f) => f.catalogIndex).toList(),
        [0, 1, 2, 3, 4, 5],
      );
    });

    test('only Gain is hardwareWritable; all six are readable and translatable', () {
      for (final field in MatriboxAmpFieldEvidenceRegistry.all) {
        expect(field.readable, isTrue, reason: field.field);
        expect(field.translatable, isTrue, reason: field.field);
        expect(field.writePlannable, isTrue, reason: field.field);
        expect(
          field.hardwareWritable,
          field.field == 'gain',
          reason: field.field,
        );
      }
    });

    test('no field has confirmed QME2 store evidence (STORE remains blocked)', () {
      for (final field in MatriboxAmpFieldEvidenceRegistry.all) {
        expect(field.storeEvidence, EvidenceLevel.unknown, reason: field.field);
        expect(field.persistenceConfirmed, isFalse, reason: field.field);
      }
    });

    test(
      'only Gain has confirmed manual-save persistence, which never implies '
      'QME2 store evidence',
      () {
        expect(
          MatriboxAmpFieldEvidenceRegistry.gain.manualSavePersistenceEvidence,
          EvidenceLevel.confirmed,
        );
        expect(MatriboxAmpFieldEvidenceRegistry.gain.manualSavePersistenceConfirmed, isTrue);
        // Confirming a manual save must never upgrade the separate QME2
        // store claim.
        expect(MatriboxAmpFieldEvidenceRegistry.gain.storeEvidence, EvidenceLevel.unknown);
        expect(MatriboxAmpFieldEvidenceRegistry.gain.persistenceConfirmed, isFalse);
        for (final field in [
          MatriboxAmpFieldEvidenceRegistry.presence,
          MatriboxAmpFieldEvidenceRegistry.volume,
          MatriboxAmpFieldEvidenceRegistry.bass,
          MatriboxAmpFieldEvidenceRegistry.middle,
          MatriboxAmpFieldEvidenceRegistry.treble,
        ]) {
          expect(
            field.manualSavePersistenceEvidence,
            EvidenceLevel.unknown,
            reason: field.field,
          );
          expect(field.manualSavePersistenceConfirmed, isFalse, reason: field.field);
        }
      },
    );

    test('read/index evidence is confirmed for all six; write evidence only for Gain', () {
      expect(MatriboxAmpFieldEvidenceRegistry.gain.readEvidence, EvidenceLevel.confirmed);
      expect(MatriboxAmpFieldEvidenceRegistry.gain.indexEvidence, EvidenceLevel.confirmed);
      for (final field in [
        MatriboxAmpFieldEvidenceRegistry.presence,
        MatriboxAmpFieldEvidenceRegistry.volume,
        MatriboxAmpFieldEvidenceRegistry.bass,
        MatriboxAmpFieldEvidenceRegistry.middle,
        MatriboxAmpFieldEvidenceRegistry.treble,
      ]) {
        expect(field.readEvidence, EvidenceLevel.confirmed, reason: field.field);
        expect(field.indexEvidence, EvidenceLevel.confirmed, reason: field.field);
        expect(field.rawWriteCaptureEvidence, EvidenceLevel.confirmed, reason: field.field);
        expect(field.encodeEvidence, EvidenceLevel.confirmed, reason: field.field);
        expect(field.readbackAfterWriteEvidence, EvidenceLevel.unknown, reason: field.field);
        expect(field.writeEvidence, EvidenceLevel.unknown, reason: field.field);
      }
    });

    test('forField returns null for an unknown name, never guesses', () {
      expect(MatriboxAmpFieldEvidenceRegistry.forField('reverb'), isNull);
    });
  });
}
