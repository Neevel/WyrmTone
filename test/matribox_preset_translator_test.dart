import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/canonical_preset.dart';
import 'package:wyrmtone/presets/matribox_preset_translator.dart';
import 'package:wyrmtone/presets/protocol_evidence.dart';

CanonicalPresetBlock _ampBlock({
  required int algorithmCode,
  String? model,
  List<PresetParameter> parameters = const [],
}) => CanonicalPresetBlock(
  id: 'amp',
  type: PresetBlockType.amp,
  enabled: true,
  order: 0,
  model: model,
  algorithmCode: algorithmCode,
  source: 'test',
  evidence: EvidenceLevel.observed,
  parameters: parameters,
);

CanonicalPreset _preset(List<CanonicalPresetBlock> blocks) => CanonicalPreset(
  id: 'test',
  name: 'Angels Don’t Kill',
  artist: 'Children of Bodom',
  song: 'Angels Don’t Kill',
  genre: 'metal',
  role: 'rhythm',
  tuning: 'dropC',
  createdAt: DateTime.utc(2026),
  modifiedAt: DateTime.utc(2026),
  origin: PresetOrigin.manual,
  targetDevice: 'matriboxOne',
  guitarId: 'guitar',
  guitarName: 'Test guitar',
  blocks: blocks,
);

PresetParameter _param(String name, num value, {EvidenceLevel evidence = EvidenceLevel.observed, int? deviceIndex}) =>
    PresetParameter(
      id: name.toLowerCase(),
      name: name,
      value: value,
      deviceIndex: deviceIndex,
      source: 'test',
      evidence: evidence,
    );

void main() {
  group('MatriboxPresetTranslator.translate', () {
    test('translates all six fields for a Sol 100 OD amp block', () {
      final result = MatriboxPresetTranslator.translate(
        _preset([
          _ampBlock(
            algorithmCode: 0x07000047,
            model: 'Sol 100 OD',
            parameters: [
              _param('Gain', 43, evidence: EvidenceLevel.confirmed, deviceIndex: 0),
              _param('PRES', 60, deviceIndex: 1),
              _param('Master', 55, deviceIndex: 2),
              _param('Bass', 48, deviceIndex: 3),
              _param('Middle', 35, deviceIndex: 4),
              _param('Treble', 62, deviceIndex: 5),
            ],
          ),
        ]),
      );

      expect(result.hasAnyTranslatedField, isTrue);
      expect(result.preset.hasKnownAmpBlock, isTrue);
      expect(result.preset.amp!.gain!.value, 43.0);
      expect(result.preset.amp!.gain!.writeEvidence, EvidenceLevel.confirmed);
      expect(result.preset.amp!.presence!.value, 60.0);
      expect(result.preset.amp!.presence!.writeEvidence, EvidenceLevel.unknown);
      expect(result.preset.amp!.volume!.value, 55.0);
      expect(result.preset.amp!.bass!.value, 48.0);
      expect(result.preset.amp!.middle!.value, 35.0);
      expect(result.preset.amp!.treble!.value, 62.0);
      expect(
        result.fields.every((f) => f.status == MatriboxTranslationStatus.translated),
        isTrue,
      );
    });

    test('an unmapped amp algorithm is unsupported, not guessed', () {
      final result = MatriboxPresetTranslator.translate(
        _preset([
          _ampBlock(
            algorithmCode: 0x1234, // not Sol 100 OD
            model: 'J900',
            parameters: [_param('Gain', 68, deviceIndex: 0)],
          ),
        ]),
      );

      expect(result.hasAnyTranslatedField, isFalse);
      expect(result.preset.hasKnownAmpBlock, isFalse);
      expect(
        result.fields.every((f) => f.status == MatriboxTranslationStatus.unsupported),
        isTrue,
      );
      expect(result.fields.first.reason, contains('J900'));
    });

    test('missing amp block yields unknown for every field', () {
      final result = MatriboxPresetTranslator.translate(_preset([]));
      expect(result.hasAnyTranslatedField, isFalse);
      expect(
        result.fields.every((f) => f.status == MatriboxTranslationStatus.unknown),
        isTrue,
      );
    });

    test('a parameter with EvidenceLevel.unknown is evidenceMissing, not guessed', () {
      final result = MatriboxPresetTranslator.translate(
        _preset([
          _ampBlock(
            algorithmCode: 0x07000047,
            model: 'Sol 100 OD',
            parameters: [
              _param('Gain', 43, evidence: EvidenceLevel.confirmed, deviceIndex: 0),
              _param('PRES', 60, evidence: EvidenceLevel.unknown, deviceIndex: 1),
            ],
          ),
        ]),
      );

      final presenceField = result.fields.firstWhere((f) => f.field == 'presence');
      expect(presenceField.status, MatriboxTranslationStatus.evidenceMissing);
      expect(result.preset.amp!.presence, isNull);
      expect(result.preset.amp!.gain!.value, 43.0);
    });

    test('a missing catalog parameter for a mapped algorithm is unknown', () {
      final result = MatriboxPresetTranslator.translate(
        _preset([
          _ampBlock(
            algorithmCode: 0x07000047,
            model: 'Sol 100 OD',
            parameters: [_param('Gain', 43, evidence: EvidenceLevel.confirmed, deviceIndex: 0)],
          ),
        ]),
      );

      final bassField = result.fields.firstWhere((f) => f.field == 'bass');
      expect(bassField.status, MatriboxTranslationStatus.unknown);
      expect(result.preset.amp!.bass, isNull);
    });
  });
}
