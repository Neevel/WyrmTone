/// CanonicalPreset (WyrmTone's device-agnostic recommendation/draft model,
/// see canonical_preset.dart) -> MatriboxSemanticPreset. This is the final
/// hop `DraftPresetAdapter` does not do: `DraftPresetAdapter` already
/// tags a `CanonicalPresetBlock`/`PresetParameter` with a Matribox
/// algorithm code and an [EvidenceLevel] from the local editor XML/
/// algorithm catalog (device_catalog.dart) -- but XML/catalog evidence is
/// a different evidence source than the QME2 wire-protocol confirmation
/// this project requires before treating a field as real. This translator
/// bridges that gap explicitly, never silently.
///
/// Never guesses: a field is only `translated` when its catalog algorithm
/// code matches [MatriboxPresetDecoder]'s confirmed Sol-100-OD mapping.
/// Everything else is reported as `unsupported`/`unknown`/
/// `evidenceMissing`, never invented.
library;

import 'canonical_preset.dart';
import 'matribox_amp_field_evidence.dart';
import 'matribox_semantic_preset.dart';
import 'protocol_evidence.dart';

enum MatriboxTranslationStatus {
  /// Field identified, mapped and carried into the semantic model.
  translated,

  /// The source has this field, but this project has no confirmed
  /// Matribox wire mapping for it (e.g. a different amp algorithm, or a
  /// block type this project doesn't model at all, such as CAB/FX).
  unsupported,

  /// The source preset has no value for this field at all.
  unknown,

  /// The field would be mappable in principle, but the source
  /// [PresetParameter] itself carries [EvidenceLevel.unknown] -- WyrmTone
  /// itself is not confident in the recommended value.
  evidenceMissing,
}

class MatriboxFieldTranslation {
  const MatriboxFieldTranslation({
    required this.field,
    required this.status,
    this.value,
    this.reason,
  });

  final String field;
  final MatriboxTranslationStatus status;
  final double? value;
  final String? reason;

  Map<String, Object?> toJson() => {
    'field': field,
    'status': status.name,
    'value': value,
    'reason': reason,
  };
}

/// [preset] carries only the fields that were actually `translated`;
/// [fields] is the full per-field audit trail, including every
/// unsupported/unknown/evidenceMissing field, so a caller never has to
/// guess why something is missing.
class MatriboxPresetTranslation {
  const MatriboxPresetTranslation({required this.preset, required this.fields});

  final MatriboxSemanticPreset preset;
  final List<MatriboxFieldTranslation> fields;

  bool get hasAnyTranslatedField => fields.any(
    (f) => f.status == MatriboxTranslationStatus.translated,
  );
}

const _solOneHundredOdCode = 0x07000047;
const _solOneHundredOdName = 'Sol 100 OD';

/// Maps our wire-protocol field name to the catalog's XML parameter name.
/// `PRES`/`Master` are the editor's own labels for the same knobs our
/// hardware read confirms as `presence`/`volume`; see
/// [MatriboxAmpBlock.presence] doc comment for why this correspondence is
/// treated as certain (same algorithm, same fixed knob order) but not
/// independently hardware-confirmed for anything beyond Gain.
const _catalogParameterNames = <String, String>{
  'gain': 'Gain',
  'presence': 'PRES',
  'volume': 'Master',
  'bass': 'Bass',
  'middle': 'Middle',
  'treble': 'Treble',
};

abstract final class MatriboxPresetTranslator {
  static MatriboxPresetTranslation translate(CanonicalPreset preset) {
    final ampBlocks = preset.blocks
        .where((b) => b.type == PresetBlockType.amp)
        .toList();
    final fields = <MatriboxFieldTranslation>[];

    if (ampBlocks.isEmpty) {
      for (final name in _catalogParameterNames.keys) {
        fields.add(
          MatriboxFieldTranslation(
            field: name,
            status: MatriboxTranslationStatus.unknown,
            reason: 'Kein AMP-Block im WyrmTone-Preset.',
          ),
        );
      }
      return MatriboxPresetTranslation(
        preset: MatriboxSemanticPreset(name: preset.name),
        fields: List.unmodifiable(fields),
      );
    }

    final ampBlock = ampBlocks.first;
    if (ampBlock.algorithmCode != _solOneHundredOdCode) {
      for (final name in _catalogParameterNames.keys) {
        fields.add(
          MatriboxFieldTranslation(
            field: name,
            status: MatriboxTranslationStatus.unsupported,
            reason:
                'Amp-Modell "${ampBlock.model ?? 'unbekannt'}" '
                '(Code ${ampBlock.algorithmCode}) hat keine bestätigte '
                'Matribox-Wire-Zuordnung; nur $_solOneHundredOdName ist '
                'QME2-wire-bestätigt.',
          ),
        );
      }
      return MatriboxPresetTranslation(
        preset: MatriboxSemanticPreset(name: preset.name),
        fields: List.unmodifiable(fields),
      );
    }

    MatriboxKnownField? translateField(String wireName) {
      final catalogName = _catalogParameterNames[wireName]!;
      final parameter = ampBlock.parameters
          .where((p) => p.name == catalogName)
          .firstOrNull;
      if (parameter == null) {
        fields.add(
          MatriboxFieldTranslation(
            field: wireName,
            status: MatriboxTranslationStatus.unknown,
            reason: 'Kein "$catalogName"-Parameter im WyrmTone-Preset.',
          ),
        );
        return null;
      }
      if (parameter.evidence == EvidenceLevel.unknown) {
        fields.add(
          MatriboxFieldTranslation(
            field: wireName,
            status: MatriboxTranslationStatus.evidenceMissing,
            reason:
                'WyrmTone-Empfehlung für "$catalogName" ist selbst nicht '
                'evidenzbasiert (EvidenceLevel.unknown).',
          ),
        );
        return null;
      }
      final value = parameter.value.toDouble();
      fields.add(
        MatriboxFieldTranslation(
          field: wireName,
          status: MatriboxTranslationStatus.translated,
          value: value,
        ),
      );
      // Write evidence and the canonical parameter index both come from
      // the central registry, not from the source parameter (which may
      // carry its own, unrelated recommendation-confidence evidence).
      final fieldEvidence = MatriboxAmpFieldEvidenceRegistry.forField(wireName)!;
      return MatriboxKnownField(
        value: value,
        identityEvidence: parameter.evidence,
        writeEvidence: fieldEvidence.writeEvidence,
        catalogIndex: fieldEvidence.catalogIndex,
      );
    }

    final gain = translateField('gain');
    final presence = translateField('presence');
    final volume = translateField('volume');
    final bass = translateField('bass');
    final middle = translateField('middle');
    final treble = translateField('treble');

    final amp = MatriboxAmpBlock(
      algorithmName: _solOneHundredOdName,
      algorithmCode: _solOneHundredOdCode,
      algorithmEvidence: ampBlock.evidence,
      gain: gain,
      presence: presence,
      volume: volume,
      bass: bass,
      middle: middle,
      treble: treble,
    );

    return MatriboxPresetTranslation(
      preset: MatriboxSemanticPreset(name: preset.name, amp: amp),
      fields: List.unmodifiable(fields),
    );
  }
}
