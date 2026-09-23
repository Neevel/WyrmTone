import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_write_verification.dart';
import 'package:wyrmtone/presets/raw_preset_snapshot.dart';

import 'support/matribox_p01_readback_fixtures.dart';

/// Writes [value] as a nibble-paired float32 LE at raw part offset
/// [rawStart] (8 raw bytes = 4 decoded bytes), mirroring the device's own
/// nibble-pair encoding (see p01_readback_decoder.dart's `nibbleDecode`).
void _setFloatAt(List<int> part, int rawStart, double value) {
  final data = ByteData(4)..setFloat32(0, value, Endian.little);
  for (var i = 0; i < 4; i++) {
    final byte = data.getUint8(i);
    part[rawStart + i * 2] = byte >> 4;
    part[rawStart + i * 2 + 1] = byte & 0x0f;
  }
}

void main() {
  List<List<int>> realParts() => matriboxP01RealFullCycle.map(matriboxHex).toList();

  RawPresetSnapshot snapshotFrom(List<List<int>> parts) => RawPresetSnapshot.capture(
    deviceLabel: 'Sonicake Matribox 1 84EF:0054',
    rawParts: parts,
  );

  group('MatriboxWriteVerifier.verify', () {
    test('an isolated Gain change is fully verified -- expected only', () {
      final before = snapshotFrom(realParts());
      final afterParts = realParts();
      _setFloatAt(afterParts[1], 201, 18.0); // gain's known raw window
      final after = snapshotFrom(afterParts);

      final result = MatriboxWriteVerifier.verify(
        before: before,
        after: after,
        expectedField: 'gain',
      );

      expect(result.outcome, MatriboxWriteVerificationOutcome.verified);
      expect(result.isFullyExplained, isTrue);
      expect(result.hasUnknownChange, isFalse);
      expect(result.semanticDiff.ampChanges, hasLength(1));
      expect(result.semanticDiff.ampChanges.single.field, 'gain');
      expect(result.semanticDiff.ampChanges.single.after, 18.0);
      expect(
        result.rawByteDiff.every(
          (e) => e.classification == MatriboxByteChangeClass.expectedChange,
        ),
        isTrue,
      );
    });

    test('no change at all is expectedChangeMissing, not silently accepted', () {
      final snapshot = snapshotFrom(realParts());
      final result = MatriboxWriteVerifier.verify(
        before: snapshot,
        after: snapshotFrom(realParts()),
        expectedField: 'gain',
      );
      expect(result.outcome, MatriboxWriteVerificationOutcome.expectedChangeMissing);
      expect(result.rawByteDiff, isEmpty);
    });

    test('a change in a different known field is unexpectedChangesDetected', () {
      final before = snapshotFrom(realParts());
      final afterParts = realParts();
      _setFloatAt(afterParts[1], 201, 18.0); // expected: gain
      _setFloatAt(afterParts[2], 25, 55.0); // unexpected: volume window
      final after = snapshotFrom(afterParts);

      final result = MatriboxWriteVerifier.verify(
        before: before,
        after: after,
        expectedField: 'gain',
      );

      expect(result.outcome, MatriboxWriteVerificationOutcome.unexpectedChangesDetected);
      expect(result.hasUnknownChange, isFalse);
      final volumeEntries = result.rawByteDiff.where((e) => e.field == 'volume');
      expect(
        volumeEntries.every((e) => e.classification == MatriboxByteChangeClass.unexpectedChange),
        isTrue,
      );
      expect(volumeEntries, isNotEmpty);
    });

    test('a change outside every known field window is unknownChange and blocks approval', () {
      final before = snapshotFrom(realParts());
      final afterParts = realParts();
      _setFloatAt(afterParts[1], 201, 18.0); // expected: gain
      // Flip a byte deep inside part 3, which has no known field windows at all.
      afterParts[3][100] = afterParts[3][100] == 0 ? 1 : 0;
      final after = snapshotFrom(afterParts);

      final result = MatriboxWriteVerifier.verify(
        before: before,
        after: after,
        expectedField: 'gain',
      );

      expect(result.outcome, MatriboxWriteVerificationOutcome.unexpectedChangesDetected);
      expect(result.hasUnknownChange, isTrue);
      final unknown = result.rawByteDiff.where(
        (e) => e.classification == MatriboxByteChangeClass.unknownChange,
      );
      expect(unknown, isNotEmpty);
      expect(unknown.single.field, isNull);
      expect(unknown.single.partIndex, 3);
    });

    test(
      'an isolated Presence change is fully verified -- the Verifier '
      'supports more known fields than the Writer can currently send',
      () {
        final before = snapshotFrom(realParts());
        final afterParts = realParts();
        _setFloatAt(afterParts[2], 17, 74.0); // presence's known raw window
        final after = snapshotFrom(afterParts);

        final result = MatriboxWriteVerifier.verify(
          before: before,
          after: after,
          expectedField: 'presence',
        );

        expect(result.outcome, MatriboxWriteVerificationOutcome.verified);
        expect(result.isFullyExplained, isTrue);
        expect(result.hasUnknownChange, isFalse);
        expect(result.semanticDiff.ampChanges, hasLength(1));
        expect(result.semanticDiff.ampChanges.single.field, 'presence');
        expect(result.semanticDiff.ampChanges.single.after, 74.0);
        expect(
          result.rawByteDiff.every(
            (e) => e.classification == MatriboxByteChangeClass.expectedChange,
          ),
          isTrue,
        );
      },
    );

    test(
      'expecting Presence but Gain changed instead is expectedChangeMissing, '
      'and the Gain bytes are still classified as unexpectedChange',
      () {
        final before = snapshotFrom(realParts());
        final afterParts = realParts();
        _setFloatAt(afterParts[1], 201, 18.0); // gain changed, not presence
        final after = snapshotFrom(afterParts);

        final result = MatriboxWriteVerifier.verify(
          before: before,
          after: after,
          expectedField: 'presence',
        );

        expect(result.outcome, MatriboxWriteVerificationOutcome.expectedChangeMissing);
        final gainEntries = result.rawByteDiff.where((e) => e.field == 'gain');
        expect(
          gainEntries.every((e) => e.classification == MatriboxByteChangeClass.unexpectedChange),
          isTrue,
        );
      },
    );

    test('every one of the six known fields verifies in isolation; all others stay unchanged', () {
      const windows = {
        'gain': (1, 201),
        'presence': (2, 17),
        'volume': (2, 25),
        'bass': (2, 33),
        'middle': (2, 41),
        'treble': (2, 49),
      };
      for (final entry in windows.entries) {
        final before = snapshotFrom(realParts());
        final afterParts = realParts();
        _setFloatAt(afterParts[entry.value.$1], entry.value.$2, 58.0);
        final result = MatriboxWriteVerifier.verify(
          before: before,
          after: snapshotFrom(afterParts),
          expectedField: entry.key,
        );
        expect(result.outcome, MatriboxWriteVerificationOutcome.verified, reason: entry.key);
        expect(result.hasUnknownChange, isFalse, reason: entry.key);
        expect(result.semanticDiff.ampChanges.map((c) => c.field), [entry.key]);
        expect(result.rawByteDiff.every((e) => e.field == entry.key), isTrue, reason: entry.key);
      }
    });

    group('correlated part-8 side-effect window (seen in the Gain and Presence hardware writes)', () {
      void touchWindow(List<List<int>> parts) {
        for (var i = 37; i < 45; i++) {
          parts[8][i] = (parts[8][i] + 1) & 0x0f;
        }
      }

      test('expected change + window change is verified, and the side effect is reported', () {
        final afterParts = realParts();
        _setFloatAt(afterParts[2], 17, 74.0);
        touchWindow(afterParts);
        final result = MatriboxWriteVerifier.verify(
          before: snapshotFrom(realParts()),
          after: snapshotFrom(afterParts),
          expectedField: 'presence',
        );
        expect(result.outcome, MatriboxWriteVerificationOutcome.verified);
        expect(result.hasUnknownChange, isFalse);
        expect(result.hasCorrelatedSideEffect, isTrue);
      });

      test('the window alone never counts as the expected change', () {
        final afterParts = realParts();
        touchWindow(afterParts);
        final result = MatriboxWriteVerifier.verify(
          before: snapshotFrom(realParts()),
          after: snapshotFrom(afterParts),
          expectedField: 'presence',
        );
        expect(result.outcome, MatriboxWriteVerificationOutcome.expectedChangeMissing);
      });

      test('it never masks any other unclassified byte, even in part 8', () {
        final afterParts = realParts();
        _setFloatAt(afterParts[2], 17, 74.0);
        touchWindow(afterParts);
        afterParts[8][36] = (afterParts[8][36] + 1) & 0x0f; // just outside the window
        final result = MatriboxWriteVerifier.verify(
          before: snapshotFrom(realParts()),
          after: snapshotFrom(afterParts),
          expectedField: 'presence',
        );
        expect(result.outcome, MatriboxWriteVerificationOutcome.unexpectedChangesDetected);
        expect(result.hasUnknownChange, isTrue);
      });
    });

    test('byte-identical parts elsewhere never appear in the diff at all', () {
      final before = snapshotFrom(realParts());
      final afterParts = realParts();
      _setFloatAt(afterParts[1], 201, 18.0);
      final after = snapshotFrom(afterParts);

      final result = MatriboxWriteVerifier.verify(
        before: before,
        after: after,
        expectedField: 'gain',
      );

      // Parts 0 and 4-9 are untouched; none of their bytes should surface.
      expect(result.rawByteDiff.any((e) => e.partIndex == 0), isFalse);
      for (var i = 4; i <= 9; i++) {
        expect(result.rawByteDiff.any((e) => e.partIndex == i), isFalse);
      }
    });
  });
}
