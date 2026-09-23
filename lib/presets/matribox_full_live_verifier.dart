/// Raw-change classification of a fresh readback against the verified BEFORE
/// snapshot, used by the productive transfer readback (originally built for
/// the Full Live certification, whose runner is gone). Every changed raw byte
/// is classified:
///
/// EXPECTED_MODEL_CHANGE, EXPECTED_PARAMETER_CHANGE, EXPECTED_BLOCK_CHANGE,
/// CORRELATED_PART8_CHANGE (the one correlated window, never called a
/// checksum), UNEXPECTED_KNOWN_CHANGE, UNKNOWN_RAW_CHANGE.
///
/// A model change resets the block's parameters on the device (seen in the
/// capture), so parameter bytes of a slot that got a model select are
/// EXPECTED_PARAMETER_CHANGE. Nothing is inferred about unknown bytes: any
/// other change stays UNKNOWN_RAW_CHANGE.
library;

import 'matribox_chain_slot.dart';
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

abstract final class MatriboxFullLiveVerifier {
  static const _part8Window = (start: 37, end: 45);

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
