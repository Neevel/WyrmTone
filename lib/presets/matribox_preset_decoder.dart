/// Raw -> Semantic decoding: turns a [RawPresetSnapshot] into a
/// [MatriboxSemanticPreset]. Purely offline; never opens a MIDI port.
///
/// Evidence-aware by construction: [MatriboxSemanticPreset.amp] is only
/// populated when the snapshot's preset name is in
/// [knownAmpFieldPresetNames] (currently only "CKY 96 STUD"), matching
/// exactly what [RawPresetSnapshot] itself already decodes -- this file
/// adds no new field guesses, it only reshapes already-confirmed values
/// into the semantic model and attaches write-evidence per field.
library;

import 'matribox_amp_field_evidence.dart';
import 'matribox_semantic_preset.dart';
import 'preset_selection_codec.dart' show MatriboxPresetSlotAddress;
import 'protocol_evidence.dart';
import 'raw_preset_snapshot.dart';

/// The only algorithm with confirmed wire-level AMP field offsets. If
/// [knownAmpFieldPresetNames] ever grows to include a preset using a
/// different algorithm, this decoder must be revisited -- it currently
/// assumes every snapshot with populated `ampFields` uses Sol-100-OD.
const _solOneHundredOdCode = 0x07000047;
const _solOneHundredOdName = 'Sol 100 OD';

abstract final class MatriboxPresetDecoder {
  static MatriboxSemanticPreset fromSnapshot(RawPresetSnapshot snapshot) {
    final ampFields = snapshot.ampFields;
    MatriboxAmpBlock? amp;
    if (ampFields != null) {
      // Per-field read/write evidence comes from the single central
      // registry (matribox_amp_field_evidence.dart), never hardcoded here.
      MatriboxKnownField field(String name, double value) {
        final evidence = MatriboxAmpFieldEvidenceRegistry.forField(name)!;
        return MatriboxKnownField(
          value: value,
          identityEvidence: evidence.readEvidence,
          writeEvidence: evidence.writeEvidence,
          catalogIndex: evidence.catalogIndex,
        );
      }

      amp = MatriboxAmpBlock(
        algorithmName: _solOneHundredOdName,
        algorithmCode: _solOneHundredOdCode,
        algorithmEvidence: EvidenceLevel.confirmed,
        gain: field('gain', ampFields.gain),
        presence: field('presence', ampFields.presence),
        volume: field('volume', ampFields.volume),
        bass: field('bass', ampFields.bass),
        middle: field('middle', ampFields.middle),
        treble: field('treble', ampFields.treble),
      );
    }
    return MatriboxSemanticPreset(
      address: MatriboxPresetSlotAddress.fromPresetNumber(
        snapshot.presetNumber,
      ),
      name: snapshot.presetName,
      amp: amp,
      rawParts: snapshot.rawParts,
    );
  }
}
