/// Builds the explicitly LAB-labelled "WyrmTone Sol100OD Write Lab"
/// target: identical to the current device preset except Gain, which
/// moves by a small, controlled amount from whatever the *current* value
/// actually is -- never a hardcoded "magic" target value. This is
/// deliberately not the real "Angels Don't Kill" recommendation, which
/// today uses amp model J900 and correctly stays `unsupported` via
/// [MatriboxPresetTranslator] (no Matribox wire mapping exists for it).
///
/// This file performs no I/O and sends nothing; it only builds a
/// [MatriboxSemanticPreset] value.
///
/// This is a hardware-lab test fixture, not product logic, and must never
/// be treated as one: the real, long-term source of a write target is
/// Tone Recommendation -> [MatriboxPresetTranslator] ->
/// [MatriboxSemanticPreset] -> [MatriboxPresetDiffEngine] ->
/// [MatriboxPresetWritePlanner], never `currentGain + 1`. Do not call
/// [MatriboxWriteLabTarget.buildGainOnlyTarget] from any non-lab code
/// path (e.g. a real song/tone write flow).
library;

import 'matribox_amp_field_evidence.dart';
import 'matribox_semantic_preset.dart';

const matriboxWriteLabPresetName = 'WyrmTone Sol100OD Write Lab';

/// Small, controlled step applied to the current Gain value -- not a
/// hardcoded target like "43"; see the module doc comment.
const matriboxWriteLabGainDelta = 1.0;

const matriboxGainMinimum = 0.0;
const matriboxGainMaximum = 99.0;

class UnsupportedWriteLabTarget implements Exception {
  const UnsupportedWriteLabTarget(this.message);
  final String message;
  @override
  String toString() => 'UnsupportedWriteLabTarget: $message';
}

abstract final class MatriboxWriteLabTarget {
  /// [current] must already carry a known Sol-100-OD AMP block with a
  /// known Gain value (i.e. decoded from a snapshot whose preset name is
  /// in `knownAmpFieldPresetNames`). Every other known field is carried
  /// over completely unchanged -- the lab target only ever touches Gain.
  static MatriboxSemanticPreset buildGainOnlyTarget(
    MatriboxSemanticPreset current,
  ) {
    final amp = current.amp;
    final currentGain = amp?.gain;
    if (amp == null || currentGain == null) {
      throw const UnsupportedWriteLabTarget(
        'Aktuelles Preset hat keinen bekannten Gain-Wert; kein Lab-Target '
        'möglich.',
      );
    }
    // currentGain + 1, except at the top of the validated range: clamping
    // 99 to 99 would silently produce a no-op write plan, so the boundary
    // case steps down by one instead -- the test stays deterministic and
    // always a real, observable change.
    final targetGainValue = currentGain.value >= matriboxGainMaximum
        ? matriboxGainMaximum - matriboxWriteLabGainDelta
        : (currentGain.value + matriboxWriteLabGainDelta).clamp(
            matriboxGainMinimum,
            matriboxGainMaximum,
          ).toDouble();
    final gainEvidence = MatriboxAmpFieldEvidenceRegistry.gain;
    return MatriboxSemanticPreset(
      name: matriboxWriteLabPresetName,
      amp: MatriboxAmpBlock(
        algorithmName: amp.algorithmName,
        algorithmCode: amp.algorithmCode,
        algorithmEvidence: amp.algorithmEvidence,
        gain: MatriboxKnownField(
          value: targetGainValue,
          identityEvidence: gainEvidence.readEvidence,
          writeEvidence: gainEvidence.writeEvidence,
          catalogIndex: gainEvidence.catalogIndex,
        ),
        presence: amp.presence,
        volume: amp.volume,
        bass: amp.bass,
        middle: amp.middle,
        treble: amp.treble,
      ),
    );
  }
}
