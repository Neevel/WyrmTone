import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/canonical_preset.dart';
import 'package:wyrmtone/presets/device_catalog.dart';
import 'package:wyrmtone/presets/preset_diff.dart';
import 'package:wyrmtone/presets/preset_validation.dart';
import 'package:wyrmtone/presets/protocol_evidence.dart';

import '../tool/generate_preset_catalog.dart';

CanonicalPreset fixture() => CanonicalPreset(
  id: 'test',
  name: 'Local test',
  artist: '',
  song: '',
  genre: 'metal',
  role: 'rhythm',
  tuning: 'dropC',
  createdAt: DateTime.utc(2026),
  modifiedAt: DateTime.utc(2026),
  origin: PresetOrigin.manual,
  targetDevice: 'matriboxOne',
  guitarId: 'guitar',
  guitarName: 'Local guitar',
  blocks: [
    CanonicalPresetBlock(
      id: 'amp',
      type: PresetBlockType.amp,
      enabled: true,
      order: 0,
      model: 'Sol 100 OD',
      algorithmCode: 0x07000047,
      source: 'local test',
      parameters: [
        const PresetParameter(
          id: 'gain',
          name: 'Gain',
          value: 40,
          deviceIndex: 0,
          minimum: 0,
          maximum: 99,
          source: 'controlled reference',
          evidence: EvidenceLevel.confirmed,
        ),
      ],
    ),
  ],
);

void main() {
  final catalog = DevicePresetCatalog(
    objectMap(
      jsonDecode(
        File('assets/catalog/matribox_preset_catalog.json').readAsStringSync(),
      ),
    ),
  );
  final validator = PresetValidator(catalog);
  test('Semantic preset JSON roundtrip and immutable copies', () {
    final preset = fixture();
    final json = canonicalJson(preset.toJson());
    expect(
      canonicalJson(
        CanonicalPreset.fromJson(objectMap(jsonDecode(json))).toJson(),
      ),
      json,
    );
    final changed = preset.copyWith(
      blocks: [
        preset.blocks.first.copyWith(
          parameters: [
            preset.blocks.first.parameters.first.copyWith(value: 41),
          ],
        ),
      ],
    );
    expect(preset.blocks.first.parameters.first.value, 40);
    expect(changed.blocks.first.parameters.first.value, 41);
    expect(() => preset.blocks.clear(), throwsUnsupportedError);
    expect(
      () => preset.blocks.first.parameters.clear(),
      throwsUnsupportedError,
    );
    final future = preset.toJson()..['schemaVersion'] = 2;
    expect(() => CanonicalPreset.fromJson(future), throwsFormatException);
    final invalid = preset.blocks.first.parameters.first.toJson()
      ..['value'] = double.nan;
    expect(() => PresetParameter.fromJson(invalid), throwsFormatException);
  });
  test(
    'Factual catalogue finds only unambiguous algorithms and known indices',
    () {
      for (final entry in {
        'Sol 100 OD': 0x07000047,
        'Sol 100 LD': 0x07000059,
        'Calif Star CL': 0x07000019,
      }.entries) {
        expect(catalog.find(entry.key)!.code, entry.value);
      }
      expect(catalog.find('Sol 100 OD')!.parameter('Gain')!.index, 0);
      expect(catalog.find('Sol 100 LD')!.parameter('Bass')!.index, 3);
      expect(catalog.find('Sol 100 LD')!.parameter('Middle')!.index, 4);
      expect(catalog.find('not known'), isNull);
    },
  );
  test('Duplicate XML observations and conflicts retained', () {
    final data = normalizePresetCatalog(
      '<QME-50><Catalog Name="AMP">'
      '<Alg Name="Test" Code="1" Code="2"><Knob Name="Gain" idx="0" '
      'ID="1" ID="2" Dmin="0" Dmax="99"/></Alg></Catalog></QME-50>',
    );
    final algorithm = objectMap((data['algorithms'] as List).single);
    expect(algorithm['code'], isNull);
    expect(algorithm['conflict'], isTrue);
    final parameter = objectMap((algorithm['parameters'] as List).single);
    expect(parameter['conflict'], isTrue);
    expect(
      (objectMap(parameter['conflictingObservations'])['ID'] as List).length,
      2,
    );
  });
  test('Valid offline draft is never full-device approved', () {
    final result = validator.validate(fixture());
    expect(result.exportAllowed, isTrue);
    expect(result.transferAllowed, isFalse);
    expect(result.transferStatus, contains('nicht'));
    expect(result.blocks['amp'], BlockReadiness.manualOnly);
  });
  test(
    'Range, finite, member, index and duplicate failures are structured',
    () {
      final original = fixture(), amp = original.blocks.first;
      for (final value in [-1, 100, double.nan, double.infinity]) {
        final result = validator.validate(
          original.copyWith(
            blocks: [
              amp.copyWith(
                parameters: [amp.parameters.first.copyWith(value: value)],
              ),
            ],
          ),
        );
        expect(result.exportAllowed, isFalse);
      }
      expect(
        validator.validate(original.copyWith(blocks: [amp, amp])).exportAllowed,
        isFalse,
      );
      final missingModel = validator.validate(
        original.copyWith(blocks: [amp.copyWith(model: 'Unknown')]),
      );
      expect(missingModel.issues.any((i) => i.code == 'algorithm'), isTrue);
    },
  );
  test('Missing assets and incompatible NAM are warnings', () {
    final data = fixture().toJson();
    data['nam'] = {
      'fileName': 'local.nam',
      'format': 'NAM',
      'sha256': 'abc',
      'creator': 'Creator',
      'license': 't3k',
      'locallyAvailable': true,
      'architecture': 'a2',
      'cabinetContent': 'unknown',
    };
    data['blocks'] = [
      ...(data['blocks'] as List),
      {
        'id': 'nam',
        'type': 'nam',
        'enabled': true,
        'order': 1,
        'model': null,
        'algorithmCode': null,
        'parameters': [],
        'source': 'local',
        'evidenceLevel': 'unknown',
        'compatibility': 'unclear',
        'manual': true,
        'warnings': [],
      },
    ];
    final preset = CanonicalPreset.fromJson(data);
    final result = validator.validate(preset);
    expect(
      result.issues.map((i) => i.code),
      containsAll(['assetMissing', 'namArchitecture', 'cabinetUnknown']),
    );
    expect(result.blocks['nam'], BlockReadiness.missingLocalFile);
    final roundtrip = CanonicalPreset.fromJson(
      objectMap(jsonDecode(canonicalJson(preset.toJson()))),
    );
    expect(roundtrip.nam!.creator, 'Creator');
    expect(roundtrip.nam!.license, 't3k');
    expect(roundtrip.nam!.locallyAvailable, isTrue);
  });

  test('Stable parameter, algorithm, enabled, removed and unchanged diffs', () {
    const engine = PresetDiffEngine();
    final original = fixture(), amp = original.blocks.first;
    expect(
      engine.compare(original, original).single.type,
      PresetChangeType.unchanged,
    );
    final changed = original.copyWith(
      name: 'Changed',
      blocks: [
        amp.copyWith(
          enabled: false,
          parameters: [amp.parameters.first.copyWith(value: 41)],
        ),
      ],
    );
    final diff = engine.compare(original, changed);
    expect(
      diff.map((d) => d.type),
      containsAll([
        PresetChangeType.parameter,
        PresetChangeType.enabled,
        PresetChangeType.name,
      ]),
    );
    final gain = diff.firstWhere((d) => d.type == PresetChangeType.parameter);
    expect(gain.before, 40);
    expect(gain.after, 41);
    expect(gain.transferable, isFalse);
    expect(
      engine.compare(original, original.copyWith(blocks: [])).single.type,
      PresetChangeType.blockRemoved,
    );
    expect(
      engine
          .compare(
            original,
            original.copyWith(blocks: [amp.copyWith(model: 'Sol 100 LD')]),
          )
          .single
          .type,
      PresetChangeType.algorithm,
    );
    final paths = diff.map((d) => d.path).toList();
    expect(paths, [...paths]..sort());
  });
}
