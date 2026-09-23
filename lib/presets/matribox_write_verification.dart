/// BEFORE/AFTER verification for a (future) confirmed parameter write:
/// compares two [RawPresetSnapshot]s both at the semantic level (which
/// known fields changed) and at the raw-byte level (did anything change
/// outside the expected field's known byte window). This file performs no
/// I/O and sends nothing; it only compares data already read.
///
/// READ data is deliberately never treated as WRITE data here or
/// anywhere else: this module only ever compares two independently
/// captured snapshots, it never replays or re-sends bytes from either one.
library;

import 'matribox_preset_decoder.dart';
import 'matribox_preset_diff.dart';
import 'raw_preset_snapshot.dart';

enum MatriboxByteChangeClass {
  /// Inside the expected field's known byte window, and that field was
  /// the one this write intended to change.
  expectedChange,

  /// Inside a *different* known AMP field's byte window than the one
  /// intended -- a known field changed that should not have.
  unexpectedChange,

  /// Inside the one narrowly-scoped window that changed together with the
  /// intended field in every hardware write observed so far (Gain 17->18 and
  /// Presence 73->74: part 8, raw offsets 37..44, 4 decoded bytes that look
  /// like a content checksum/hash of the preset). CORRELATED, not decoded:
  /// it is only tolerated next to a genuine expected-field change and is
  /// always reported; it never masks any other unclassified byte.
  correlatedSideEffect,

  /// Outside every known AMP field window -- an unclassified byte
  /// changed. This is the case Schritt 9 explicitly calls out: it must
  /// block later product approval, since we cannot explain it.
  unknownChange,
}

class MatriboxRawByteDiffEntry {
  const MatriboxRawByteDiffEntry({
    required this.partIndex,
    required this.byteOffset,
    required this.before,
    required this.after,
    required this.classification,
    this.field,
  });

  final int partIndex;

  /// Offset within the raw part's own byte array (not a global offset).
  final int byteOffset;
  final int before;
  final int after;
  final MatriboxByteChangeClass classification;

  /// The known field this byte belongs to, if [classification] is not
  /// [MatriboxByteChangeClass.unknownChange].
  final String? field;

  Map<String, Object?> toJson() => {
    'part': partIndex,
    'byteOffset': byteOffset,
    'before': before,
    'after': after,
    'classification': classification.name,
    'field': field,
  };
}

/// Known AMP-field raw byte windows, derived from the confirmed
/// concatenated-decoded-buffer offsets (188/192/196/200/204/208, see
/// p01_readback_decoder.dart) mapped back to raw part+offset coordinates.
/// Each field occupies exactly 8 consecutive raw bytes (4 nibble-paired
/// decoded bytes) within a single part -- none of the six fields straddle
/// a part boundary, verified against the confirmed offsets.
class _FieldWindow {
  const _FieldWindow(this.field, this.partIndex, this.rawStart, this.rawEnd);
  final String field;
  final int partIndex;
  final int rawStart; // inclusive
  final int rawEnd; // exclusive
}

const _fieldWindows = <_FieldWindow>[
  _FieldWindow('gain', 1, 201, 209),
  _FieldWindow('presence', 2, 17, 25),
  _FieldWindow('volume', 2, 25, 33),
  _FieldWindow('bass', 2, 33, 41),
  _FieldWindow('middle', 2, 41, 49),
  _FieldWindow('treble', 2, 49, 57),
];

/// part 8, raw [37, 45): see [MatriboxByteChangeClass.correlatedSideEffect].
bool _isCorrelatedSideEffect(int partIndex, int byteOffset) =>
    partIndex == 8 && byteOffset >= 37 && byteOffset < 45;

String? _fieldForRawByte(int partIndex, int byteOffset) {
  for (final window in _fieldWindows) {
    if (window.partIndex == partIndex &&
        byteOffset >= window.rawStart &&
        byteOffset < window.rawEnd) {
      return window.field;
    }
  }
  return null;
}

enum MatriboxWriteVerificationOutcome {
  /// Exactly the expected field changed; nothing else did.
  verified,

  /// The expected field did not change at all.
  expectedChangeMissing,

  /// Something changed that was not the expected field (semantically
  /// and/or at the byte level).
  unexpectedChangesDetected,
}

class MatriboxWriteVerification {
  const MatriboxWriteVerification({
    required this.expectedField,
    required this.semanticDiff,
    required this.rawByteDiff,
    required this.outcome,
  });

  final String expectedField;
  final MatriboxPresetDiff semanticDiff;
  final List<MatriboxRawByteDiffEntry> rawByteDiff;
  final MatriboxWriteVerificationOutcome outcome;

  bool get hasUnknownChange => rawByteDiff.any(
    (e) => e.classification == MatriboxByteChangeClass.unknownChange,
  );

  /// The correlated part-8 side-effect window changed (reported, tolerated
  /// only together with the expected change).
  bool get hasCorrelatedSideEffect => rawByteDiff.any(
    (e) => e.classification == MatriboxByteChangeClass.correlatedSideEffect,
  );

  bool get isFullyExplained => outcome == MatriboxWriteVerificationOutcome.verified;

  Map<String, Object?> toJson() => {
    'expectedField': expectedField,
    'outcome': outcome.name,
    'hasUnknownChange': hasUnknownChange,
    'rawByteDiff': rawByteDiff.map((e) => e.toJson()).toList(),
  };
}

abstract final class MatriboxWriteVerifier {
  /// Compares [before] and [after] (independently captured, already
  /// validated `RawPresetSnapshot`s of the same slot) and classifies every
  /// difference. [expectedField] is the one field this write was supposed
  /// to change (e.g. `"gain"`).
  static MatriboxWriteVerification verify({
    required RawPresetSnapshot before,
    required RawPresetSnapshot after,
    required String expectedField,
  }) {
    final beforeSemantic = MatriboxPresetDecoder.fromSnapshot(before);
    final afterSemantic = MatriboxPresetDecoder.fromSnapshot(after);
    final semanticDiff = MatriboxPresetDiffEngine.compare(
      current: beforeSemantic,
      target: afterSemantic,
    );

    final rawByteDiff = <MatriboxRawByteDiffEntry>[];
    for (var partIndex = 0; partIndex < before.rawParts.length; partIndex++) {
      final beforePart = before.rawParts[partIndex];
      final afterPart = partIndex < after.rawParts.length
          ? after.rawParts[partIndex]
          : const <int>[];
      final length = beforePart.length < afterPart.length
          ? beforePart.length
          : afterPart.length;
      for (var offset = 0; offset < length; offset++) {
        final beforeByte = beforePart[offset];
        final afterByte = afterPart[offset];
        if (beforeByte == afterByte) continue;
        final field = _fieldForRawByte(partIndex, offset);
        final classification = field == null
            ? (_isCorrelatedSideEffect(partIndex, offset)
                  ? MatriboxByteChangeClass.correlatedSideEffect
                  : MatriboxByteChangeClass.unknownChange)
            : (field == expectedField
                  ? MatriboxByteChangeClass.expectedChange
                  : MatriboxByteChangeClass.unexpectedChange);
        rawByteDiff.add(
          MatriboxRawByteDiffEntry(
            partIndex: partIndex,
            byteOffset: offset,
            before: beforeByte,
            after: afterByte,
            classification: classification,
            field: field,
          ),
        );
      }
    }

    final expectedFieldChangedSemantically = semanticDiff.ampChanges.any(
      (c) => c.field == expectedField,
    );
    final onlyExpectedFieldChangedSemantically = semanticDiff.ampChanges.every(
      (c) => c.field == expectedField,
    );
    final onlyExpectedBytesChanged = rawByteDiff.every(
      (e) =>
          e.classification == MatriboxByteChangeClass.expectedChange ||
          e.classification == MatriboxByteChangeClass.correlatedSideEffect,
    );

    final MatriboxWriteVerificationOutcome outcome;
    if (!expectedFieldChangedSemantically) {
      outcome = MatriboxWriteVerificationOutcome.expectedChangeMissing;
    } else if (!onlyExpectedFieldChangedSemantically ||
        !onlyExpectedBytesChanged) {
      outcome = MatriboxWriteVerificationOutcome.unexpectedChangesDetected;
    } else {
      outcome = MatriboxWriteVerificationOutcome.verified;
    }

    return MatriboxWriteVerification(
      expectedField: expectedField,
      semanticDiff: semanticDiff,
      rawByteDiff: List.unmodifiable(rawByteDiff),
      outcome: outcome,
    );
  }
}
