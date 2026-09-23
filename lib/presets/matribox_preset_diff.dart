/// Diff between two [MatriboxSemanticPreset]s (e.g. the currently decoded
/// device state vs. a translated target). Deliberately not
/// `PresetDiffEngine` (preset_diff.dart): that engine compares
/// `CanonicalPreset`s at the WyrmTone-recommendation layer; this compares
/// the Matribox wire-semantic layer, so a difference here is meaningful
/// for an actual device write, not just for a recommendation change.
///
/// A field absent on the target (unknown/unsupported during translation)
/// never produces a change -- unknown fields are never touched.
library;

import 'matribox_semantic_preset.dart';
import 'protocol_evidence.dart';

class MatriboxPresetFieldChange {
  const MatriboxPresetFieldChange({
    required this.field,
    required this.before,
    required this.after,
    required this.evidence,
  });

  final String field;
  final double? before;
  final double after;
  final EvidenceLevel evidence;

  Map<String, Object?> toJson() => {
    'field': field,
    'before': before,
    'after': after,
    'evidenceLevel': evidence.name,
  };
}

class MatriboxPresetDiff {
  const MatriboxPresetDiff({
    required this.nameBefore,
    required this.nameAfter,
    required this.ampChanges,
  });

  final String nameBefore;
  final String nameAfter;
  final List<MatriboxPresetFieldChange> ampChanges;

  bool get nameChanged => nameBefore != nameAfter;
  bool get hasChanges => nameChanged || ampChanges.isNotEmpty;
}

abstract final class MatriboxPresetDiffEngine {
  static MatriboxPresetDiff compare({
    required MatriboxSemanticPreset current,
    required MatriboxSemanticPreset target,
  }) {
    final changes = <MatriboxPresetFieldChange>[];
    final currentFields = current.amp?.fieldsByName ?? const {};
    final targetFields = target.amp?.fieldsByName ?? const {};
    for (final entry in targetFields.entries) {
      final after = entry.value;
      if (after == null) continue; // never targeted -> never a change
      final before = currentFields[entry.key];
      if (before != null && before.value == after.value) continue;
      changes.add(
        MatriboxPresetFieldChange(
          field: entry.key,
          before: before?.value,
          after: after.value,
          evidence: after.identityEvidence,
        ),
      );
    }
    return MatriboxPresetDiff(
      nameBefore: current.name,
      nameAfter: target.name,
      ampChanges: List.unmodifiable(changes),
    );
  }
}
