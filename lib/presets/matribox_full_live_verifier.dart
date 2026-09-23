/// Readback verification for the Full Live plan: compares the BEFORE raw
/// snapshot (the verified backup) with a fresh AFTER read against the plan
/// and classifies EVERY changed raw byte.
///
/// Classes (per the plan's requirements):
/// EXPECTED_MODEL_CHANGE, EXPECTED_PARAMETER_CHANGE, EXPECTED_BLOCK_CHANGE,
/// CORRELATED_PART8_CHANGE (the one correlated window, never called a
/// checksum), UNEXPECTED_KNOWN_CHANGE, UNKNOWN_RAW_CHANGE.
///
/// A model change resets the block's parameters on the device (seen in the
/// capture), so parameter bytes of a slot that got a model select are
/// EXPECTED_PARAMETER_CHANGE even where the plan did not write them; their
/// values are not checked beyond the planned ones. Nothing is inferred
/// about unknown bytes: any other change stays UNKNOWN_RAW_CHANGE.
library;

import 'matribox_certification_plan.dart';
import 'matribox_chain_slot.dart';
import 'matribox_full_live_plan.dart';
import 'matribox_preset_layout.dart';
import 'raw_preset_snapshot.dart';

enum FullLiveChangeClass {
  expectedModelChange,
  expectedParameterChange,
  expectedBlockChange,
  correlatedPart8Change,
  unexpectedKnownChange,
  unknownRawChange,
}

class FullLiveRawChange {
  const FullLiveRawChange(this.part, this.rawOffset, this.classification, this.detail);
  final int part;
  final int rawOffset;
  final FullLiveChangeClass classification;
  final String detail;
}

enum FullLiveOperationCheck { matched, mismatch }

class FullLiveOperationResult {
  const FullLiveOperationResult({
    required this.operation,
    required this.check,
    required this.actual,
    this.note,
  });
  final FullLiveOperation operation;
  final FullLiveOperationCheck check;

  /// Human-readable actual value (code, float or ON/OFF).
  final String actual;
  final String? note;
}

enum FullLiveVerificationOutcome {
  certified,
  expectedChangeMissing,
  unexpectedKnownChange,
  unknownRawChange,
}

class FullLiveVerification {
  const FullLiveVerification({
    required this.outcome,
    required this.operations,
    required this.changes,
    this.untouchedSlots = const [],
    this.requiredModelViolations = const [],
  });

  final FullLiveVerificationOutcome outcome;
  final List<FullLiveOperationResult> operations;
  final List<FullLiveRawChange> changes;

  /// Slots the plan does not touch; the raw classifier proves they are unchanged.
  final List<MatriboxChainSlot> untouchedSlots;

  /// Slots whose model had to stay/end as required but did not.
  final List<String> requiredModelViolations;

  int count(FullLiveChangeClass c) => changes.where((e) => e.classification == c).length;
  bool get certified => outcome == FullLiveVerificationOutcome.certified;
}

abstract final class MatriboxFullLiveVerifier {
  static const _part8Window = (start: 37, end: 45);
  static const _tolerance = 1e-3;

  static FullLiveVerification verify({
    required RawPresetSnapshot before,
    required RawPresetSnapshot after,
    CertificationPlan plan = const FullLiveP01Plan(),
  }) {
    final afterModel = MatriboxPresetLayout.decode(after);

    final modelSlots = {
      for (final o in plan.operations)
        if (o.kind == FullLiveOperationKind.modelSelect) o.slot,
    };
    final parameterSlots = {
      for (final o in plan.operations)
        if (o.kind == FullLiveOperationKind.parameter) o.slot,
    };
    final toggleSlots = {
      for (final o in plan.operations)
        if (o.kind == FullLiveOperationKind.blockToggle) o.slot,
    };

    // slots that only receive parameter writes: narrow the raw check to those floats
    final parameterIndices = <MatriboxChainSlot, Set<int>>{};
    for (final o in plan.operations) {
      if (o.kind == FullLiveOperationKind.parameter && !modelSlots.contains(o.slot)) {
        parameterIndices.putIfAbsent(o.slot, () => <int>{}).add(o.parameter!.wireIndex);
      }
    }

    // 1. planned semantic results
    final results = <FullLiveOperationResult>[];
    for (final o in plan.operations) {
      switch (o.kind) {
        case FullLiveOperationKind.modelSelect:
          final actual = afterModel.code(o.slot);
          results.add(
            FullLiveOperationResult(
              operation: o,
              check: actual == o.algorithm!.code
                  ? FullLiveOperationCheck.matched
                  : FullLiveOperationCheck.mismatch,
              actual: '0x${actual.toRadixString(16).padLeft(8, '0')}',
            ),
          );
        case FullLiveOperationKind.parameter:
          final actual = afterModel.parameter(o.slot, o.parameter!.wireIndex);
          final accepted = o.acceptedValues.any((v) => (v - actual).abs() < _tolerance);
          results.add(
            FullLiveOperationResult(
              operation: o,
              check: accepted ? FullLiveOperationCheck.matched : FullLiveOperationCheck.mismatch,
              actual: actual.toStringAsFixed(2),
              note: accepted && (o.value! - actual).abs() >= _tolerance
                  ? 'Gerät hat den Wert selbst umgerechnet (Sync), wie im Capture.'
                  : null,
            ),
          );
        case FullLiveOperationKind.blockToggle:
          final actualOn = afterModel.isOn(o.slot);
          results.add(
            FullLiveOperationResult(
              operation: o,
              check: actualOn == o.enabled! ? FullLiveOperationCheck.matched : FullLiveOperationCheck.mismatch,
              actual: actualOn ? 'ON' : 'OFF',
            ),
          );
      }
    }

    // 2. classify every changed raw byte
    final changes = classifyRawChanges(
      before: before,
      after: after,
      modelSlots: modelSlots,
      parameterSlots: parameterSlots,
      toggleSlots: toggleSlots,
      parameterIndices: parameterIndices,
    );

    final violations = <String>[
      for (final e in plan.requiredModelsAfter.entries)
        if (afterModel.code(e.key) != e.value)
          '${e.key.label}: Modell 0x${afterModel.code(e.key).toRadixString(16).padLeft(8, '0')} statt 0x${e.value.toRadixString(16).padLeft(8, '0')}',
    ];
    final touched = {...modelSlots, ...parameterSlots, ...toggleSlots};

    // 3. outcome
    final FullLiveVerificationOutcome outcome;
    if (changes.any((c) => c.classification == FullLiveChangeClass.unknownRawChange)) {
      outcome = FullLiveVerificationOutcome.unknownRawChange;
    } else if (changes.any((c) => c.classification == FullLiveChangeClass.unexpectedKnownChange)) {
      outcome = FullLiveVerificationOutcome.unexpectedKnownChange;
    } else if (violations.isNotEmpty || results.any((r) => r.check == FullLiveOperationCheck.mismatch)) {
      outcome = FullLiveVerificationOutcome.expectedChangeMissing;
    } else {
      outcome = FullLiveVerificationOutcome.certified;
    }
    return FullLiveVerification(
      outcome: outcome,
      operations: List.unmodifiable(results),
      changes: List.unmodifiable(changes),
      untouchedSlots: [for (final s in MatriboxChainSlot.values) if (!touched.contains(s)) s],
      requiredModelViolations: violations,
    );
  }


  /// Classifies every changed raw byte between two snapshots. [parameterIndices]
  /// (optional) narrows the expected parameter bytes of a slot WITHOUT a model
  /// change to the listed wire parameter indices; other floats of that slot
  /// count as unexpected known changes.
  static List<FullLiveRawChange> classifyRawChanges({
    required RawPresetSnapshot before,
    required RawPresetSnapshot after,
    required Set<MatriboxChainSlot> modelSlots,
    required Set<MatriboxChainSlot> parameterSlots,
    required Set<MatriboxChainSlot> toggleSlots,
    Map<MatriboxChainSlot, Set<int>>? parameterIndices,
  }) {
    final beforeModel = MatriboxPresetLayout.decode(before);
    final afterModel = MatriboxPresetLayout.decode(after);
    final changes = <FullLiveRawChange>[];
    final fx1CopyChanged = afterModel.fx1CodeCopy != beforeModel.fx1CodeCopy;
    for (var part = 0; part < before.rawParts.length && part < after.rawParts.length; part++) {
      final b = before.rawParts[part];
      final a = after.rawParts[part];
      final length = b.length < a.length ? b.length : a.length;
      for (var i = 0; i < length; i++) {
        if (b[i] == a[i]) continue;
        changes.add(_classify(
          part, i, length,
          modelSlots: modelSlots,
          parameterSlots: parameterSlots,
          toggleSlots: toggleSlots,
          parameterIndices: parameterIndices,
          afterModel: afterModel,
          fx1CopyFollowsModel: fx1CopyChanged,
        ));
      }
      if (b.length != a.length) {
        changes.add(FullLiveRawChange(part, length, FullLiveChangeClass.unknownRawChange, 'Teilelänge geändert'));
      }
    }
    return changes;
  }

  static FullLiveRawChange _classify(
    int part,
    int rawOffset,
    int partLength, {
    required Set<MatriboxChainSlot> modelSlots,
    required Set<MatriboxChainSlot> parameterSlots,
    required Set<MatriboxChainSlot> toggleSlots,
    Map<MatriboxChainSlot, Set<int>>? parameterIndices,
    required MatriboxPresetLayoutModel afterModel,
    required bool fx1CopyFollowsModel,
  }) {
    if (part == 8 && rawOffset >= _part8Window.start && rawOffset < _part8Window.end) {
      return FullLiveRawChange(part, rawOffset, FullLiveChangeClass.correlatedPart8Change,
          'Part 8 Byte 37..44 (korreliert, nicht als Prüfsumme benannt)');
    }
    final offset = MatriboxPresetLayout.decodedOffset(part, rawOffset, partLength);
    if (offset == null) {
      return FullLiveRawChange(part, rawOffset, FullLiveChangeClass.unknownRawChange, 'kein Nutzdatenbyte');
    }
    for (final slot in MatriboxChainSlot.values) {
      final codeStart = MatriboxPresetLayout.codeOffset(slot);
      if (offset >= codeStart && offset < codeStart + 4) {
        return modelSlots.contains(slot)
            ? FullLiveRawChange(part, rawOffset, FullLiveChangeClass.expectedModelChange, '${slot.label} Modellcode')
            : FullLiveRawChange(part, rawOffset, FullLiveChangeClass.unexpectedKnownChange, '${slot.label} Modellcode ohne Plan');
      }
      final base = MatriboxPresetLayout.parametersBase(slot);
      if (offset >= base && offset < base + MatriboxPresetLayout.parametersStride) {
        if (modelSlots.contains(slot)) {
          return FullLiveRawChange(part, rawOffset, FullLiveChangeClass.expectedParameterChange, '${slot.label} Parameter');
        }
        final narrowed = parameterIndices?[slot];
        if (narrowed != null) {
          final index = (offset - base) ~/ 4;
          return narrowed.contains(index)
              ? FullLiveRawChange(part, rawOffset, FullLiveChangeClass.expectedParameterChange, '${slot.label} Parameter $index')
              : FullLiveRawChange(part, rawOffset, FullLiveChangeClass.unexpectedKnownChange, '${slot.label} Parameter $index ohne Plan');
        }
        return parameterSlots.contains(slot)
            ? FullLiveRawChange(part, rawOffset, FullLiveChangeClass.expectedParameterChange, '${slot.label} Parameter')
            : FullLiveRawChange(part, rawOffset, FullLiveChangeClass.unexpectedKnownChange, '${slot.label} Parameter ohne Plan');
      }
      final state = MatriboxPresetLayout.stateOffset(slot);
      if (offset >= state && offset < state + 2) {
        return toggleSlots.contains(slot)
            ? FullLiveRawChange(part, rawOffset, FullLiveChangeClass.expectedBlockChange, '${slot.label} Blockzustand')
            : FullLiveRawChange(part, rawOffset, FullLiveChangeClass.unexpectedKnownChange, '${slot.label} Blockzustand ohne Plan');
      }
    }
    if (offset >= MatriboxPresetLayout.fx1CodeCopyOffset &&
        offset < MatriboxPresetLayout.fx1CodeCopyOffset + 4) {
      // The copy changed together with the FX1 model in the capture.
      return fx1CopyFollowsModel &&
              modelSlots.contains(MatriboxChainSlot.fx1) &&
              afterModel.fx1CodeCopy == afterModel.code(MatriboxChainSlot.fx1)
          ? FullLiveRawChange(part, rawOffset, FullLiveChangeClass.expectedModelChange, 'FX1-Code-Kopie folgt dem FX1-Modell')
          : FullLiveRawChange(part, rawOffset, FullLiveChangeClass.unknownRawChange, 'Offset 652 ohne passende FX1-Änderung');
    }
    final known = offset >= MatriboxPresetLayout.nameOffset && offset < MatriboxPresetLayout.chainOrderOffset
        ? 'Presetname'
        : offset >= MatriboxPresetLayout.chainOrderOffset && offset < MatriboxPresetLayout.codeTableOffset
            ? 'Kettenreihenfolge'
            : offset == MatriboxPresetLayout.bpmOffset || offset == MatriboxPresetLayout.bpmOffset + 1
                ? 'Preset BPM'
                : offset == MatriboxPresetLayout.volumeOffset || offset == MatriboxPresetLayout.volumeOffset + 1
                    ? 'Preset VOL'
                    : null;
    return known != null
        ? FullLiveRawChange(part, rawOffset, FullLiveChangeClass.unexpectedKnownChange, '$known nicht im Plan')
        : FullLiveRawChange(part, rawOffset, FullLiveChangeClass.unknownRawChange, 'unbekannter Bereich');
  }
}
