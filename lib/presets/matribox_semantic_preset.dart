/// The semantic layer for a Matribox preset: a small set of named,
/// evidence-tagged fields (currently only the Sol-100-OD AMP block's six
/// confirmed knobs), as opposed to the raw byte layer ([RawPresetSnapshot])
/// or the device-agnostic WyrmTone layer ([CanonicalPreset]). These three
/// layers are deliberately kept separate:
///
/// - `RawPresetSnapshot` (raw_preset_snapshot.dart): exact device bytes.
/// - `MatriboxSemanticPreset` (this file): named Matribox fields with
///   per-field evidence, decoded from a snapshot or produced as a
///   translation target. Still Matribox-specific.
/// - `CanonicalPreset` (canonical_preset.dart): WyrmTone's own
///   device-agnostic recommendation/draft model.
///
/// Reuses [EvidenceLevel] from protocol_evidence.dart rather than a new
/// evidence enum, and [MatriboxPresetSlotAddress] from
/// preset_selection_codec.dart rather than a new address type.
///
/// Only the AMP block is modelled. The preset payload also contains CAB,
/// FX, Gate, Modulation, Delay, Reverb, EQ etc. blocks -- none of their
/// wire-protocol offsets are confirmed, so they are deliberately not
/// modelled here at all (not even as empty placeholders) rather than
/// guessing a structure. [RawPresetSnapshot.rawParts], when available,
/// still contains every byte of those blocks unchanged.
library;

import 'preset_selection_codec.dart' show MatriboxPresetSlotAddress;
import 'protocol_evidence.dart';

/// One named Matribox field with independent evidence for whether its
/// *identity/position* is confirmed (e.g. via the QME2 full-read wire
/// protocol, or via editor/XML catalog correlation for a translation
/// target) and whether *writing* this specific field is hardware-confirmed
/// (currently true only for Sol-100-OD Gain via
/// `ConfirmedParameterCodec`). These are different questions: a field can
/// be confidently read and displayed while still being unwritable.
class MatriboxKnownField {
  const MatriboxKnownField({
    required this.value,
    required this.identityEvidence,
    this.writeEvidence = EvidenceLevel.unknown,
    this.catalogIndex,
  });

  final double value;
  final EvidenceLevel identityEvidence;
  final EvidenceLevel writeEvidence;

  /// The Sol-100-OD parameter index used by the confirmed single-parameter
  /// write message family (`ConfirmedParameterCodec`), if known. Null does
  /// not mean unwritable by itself -- [writeEvidence] is authoritative.
  final int? catalogIndex;

  Map<String, Object?> toJson() => {
    'value': value,
    'identityEvidence': identityEvidence.name,
    'writeEvidence': writeEvidence.name,
    'catalogIndex': catalogIndex,
  };
}

/// The Sol-100-OD AMP block, the only algorithm with confirmed wire-level
/// field offsets (docs/MATRIBOX_OFFLINE_ANALYSIS.md, "Vollständiger
/// Device→Host-Readback und Persistenzbeweis"). `algorithmCode` is the
/// catalog code `0x07000047`.
class MatriboxAmpBlock {
  const MatriboxAmpBlock({
    required this.algorithmName,
    required this.algorithmCode,
    required this.algorithmEvidence,
    this.gain,
    this.presence,
    this.volume,
    this.bass,
    this.middle,
    this.treble,
  });

  final String algorithmName;
  final int algorithmCode;
  final EvidenceLevel algorithmEvidence;

  /// Wire-protocol field name `presence` corresponds to the catalog's
  /// `PRES` parameter (index 1); `volume` corresponds to the catalog's
  /// `Master` (index 2) -- same physical knob, different naming source
  /// (hardware capture vs. editor XML). This correspondence is by
  /// construction (same algorithm, same knob order) but only Gain has
  /// independent read+write hardware confirmation; the others are
  /// read-confirmed only.
  final MatriboxKnownField? gain, presence, volume, bass, middle, treble;

  Map<String, Object?> toJson() => {
    'algorithmName': algorithmName,
    'algorithmCode': algorithmCode,
    'algorithmEvidence': algorithmEvidence.name,
    'gain': gain?.toJson(),
    'presence': presence?.toJson(),
    'volume': volume?.toJson(),
    'bass': bass?.toJson(),
    'middle': middle?.toJson(),
    'treble': treble?.toJson(),
  };

  /// All six fields keyed by their wire-protocol name, in a fixed order,
  /// including absent (null) ones -- the canonical iteration order used by
  /// the diff engine and the write planner.
  Map<String, MatriboxKnownField?> get fieldsByName => {
    'gain': gain,
    'presence': presence,
    'volume': volume,
    'bass': bass,
    'middle': middle,
    'treble': treble,
  };
}

/// A Matribox preset at the semantic layer. [address] and [rawParts] are
/// only present when this was decoded from an actual device read
/// ([RawPresetSnapshot]); a pure translation target (not yet read from any
/// device) has both null. [amp] is null when the preset's AMP algorithm
/// is not one this project has confirmed field offsets for.
class MatriboxSemanticPreset {
  const MatriboxSemanticPreset({
    this.address,
    required this.name,
    this.amp,
    this.rawParts,
  });

  final MatriboxPresetSlotAddress? address;
  final String name;
  final MatriboxAmpBlock? amp;
  final List<List<int>>? rawParts;

  bool get hasKnownAmpBlock => amp != null;
}
