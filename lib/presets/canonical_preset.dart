import 'dart:convert';

import 'protocol_evidence.dart';

enum PresetBlockType {
  gate,
  compressor,
  drive,
  amp,
  nam,
  cab,
  eq,
  modulation,
  delay,
  reverb,
}

enum ParameterDataType { integer, floating, boolean }

enum PresetOrigin { exactProfile, genreFallback, manual, imported }

Map<String, Object?> objectMap(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected JSON object.');
  }
  return value;
}

String requiredText(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing or invalid $key.');
  }
  return value;
}

T enumValue<T extends Enum>(List<T> values, Object? name) =>
    values.where((v) => v.name == name).firstOrNull ??
    (throw FormatException('Unknown enum value: $name'));
num finiteNumber(Object? value) {
  if (value is! num || !value.isFinite) {
    throw const FormatException('Expected finite number.');
  }
  return value;
}

List<String> textList(Object? value) {
  if (value is! List || value.any((v) => v is! String)) {
    throw const FormatException('Expected text list.');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

/// Stable key ordering for hashing and semantic comparisons.
String canonicalJson(Object? value, {bool pretty = false}) {
  Object? sorted(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sorted(item[key])};
    }
    if (item is List) return item.map(sorted).toList();
    if (item is num && !item.isFinite) {
      throw const FormatException('Non-finite JSON number.');
    }
    return item;
  }

  return (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
      .convert(sorted(value));
}

class PresetParameter {
  const PresetParameter({
    required this.id,
    required this.name,
    required this.value,
    this.deviceIndex,
    this.unit,
    this.minimum,
    this.maximum,
    this.step,
    this.dataType = ParameterDataType.integer,
    required this.source,
    this.evidence = EvidenceLevel.unknown,
    this.originalValue,
  });
  final String id, name, source;
  final String? unit;
  final int? deviceIndex;
  final num value;
  final num? minimum, maximum, step, originalValue;
  final ParameterDataType dataType;
  final EvidenceLevel evidence;
  // Index evidence is not a generalized permission to write.
  bool get transferable => false;
  PresetParameter copyWith({num? value, num? originalValue}) => PresetParameter(
    id: id,
    name: name,
    value: value ?? this.value,
    deviceIndex: deviceIndex,
    unit: unit,
    minimum: minimum,
    maximum: maximum,
    step: step,
    dataType: dataType,
    source: source,
    evidence: evidence,
    originalValue: originalValue ?? this.originalValue,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'deviceIndex': deviceIndex,
    'value': value,
    'unit': unit,
    'minimum': minimum,
    'maximum': maximum,
    'step': step,
    'dataType': dataType.name,
    'source': source,
    'evidenceLevel': evidence.name,
    'manual': true,
    'originalValue': originalValue,
  };
  factory PresetParameter.fromJson(Map<String, Object?> map) {
    num? optional(String key) =>
        map[key] == null ? null : finiteNumber(map[key]);
    if (map['deviceIndex'] != null && map['deviceIndex'] is! int) {
      throw const FormatException('Invalid device index.');
    }
    return PresetParameter(
      id: requiredText(map, 'id'),
      name: requiredText(map, 'name'),
      value: finiteNumber(map['value']),
      deviceIndex: map['deviceIndex'] as int?,
      unit: map['unit'] as String?,
      minimum: optional('minimum'),
      maximum: optional('maximum'),
      step: optional('step'),
      originalValue: optional('originalValue'),
      dataType: enumValue(ParameterDataType.values, map['dataType']),
      source: requiredText(map, 'source'),
      evidence: enumValue(EvidenceLevel.values, map['evidenceLevel']),
    );
  }
}

class PresetAssetReference {
  const PresetAssetReference({
    required this.fileName,
    required this.format,
    this.sha256,
    this.creator,
    this.license,
    this.locallyAvailable = false,
    this.architecture,
    this.cabinetContent = 'unknown',
  });
  final String fileName, format, cabinetContent;
  final String? sha256, creator, license, architecture;
  final bool locallyAvailable;
  Map<String, Object?> toJson() => {
    'fileName': fileName,
    'format': format,
    'sha256': sha256,
    'creator': creator,
    'license': license,
    'locallyAvailable': locallyAvailable,
    'architecture': architecture,
    'cabinetContent': cabinetContent,
  };
  factory PresetAssetReference.fromJson(Map<String, Object?> map) =>
      PresetAssetReference(
        fileName: requiredText(map, 'fileName'),
        format: requiredText(map, 'format'),
        sha256: map['sha256'] as String?,
        creator: map['creator'] as String?,
        license: map['license'] as String?,
        architecture: map['architecture'] as String?,
        // Availability is only exported metadata; validation still requires a
        // separately supplied local hash before it treats the file as present.
        locallyAvailable: map['locallyAvailable'] == true,
        cabinetContent: map['cabinetContent'] as String? ?? 'unknown',
      );
}

class CanonicalPresetBlock {
  CanonicalPresetBlock({
    required this.id,
    required this.type,
    required this.enabled,
    required this.order,
    this.model,
    this.algorithmCode,
    required List<PresetParameter> parameters,
    required this.source,
    this.evidence = EvidenceLevel.unknown,
    this.compatibility = 'unclear',
    List<String> warnings = const [],
  }) : parameters = List.unmodifiable(parameters),
       warnings = List.unmodifiable(warnings);
  final String id, source, compatibility;
  final String? model;
  final int? algorithmCode;
  final PresetBlockType type;
  final bool enabled;
  final int order;
  final List<PresetParameter> parameters;
  final EvidenceLevel evidence;
  final List<String> warnings;
  bool get transferable => false;
  CanonicalPresetBlock copyWith({
    bool? enabled,
    String? model,
    List<PresetParameter>? parameters,
  }) => CanonicalPresetBlock(
    id: id,
    type: type,
    enabled: enabled ?? this.enabled,
    order: order,
    model: model ?? this.model,
    algorithmCode: algorithmCode,
    parameters: parameters ?? this.parameters,
    source: source,
    evidence: evidence,
    compatibility: compatibility,
    warnings: warnings,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'enabled': enabled,
    'order': order,
    'model': model,
    'algorithmCode': algorithmCode,
    'parameters': parameters.map((p) => p.toJson()).toList(),
    'source': source,
    'evidenceLevel': evidence.name,
    'compatibility': compatibility,
    'manual': true,
    'warnings': warnings,
  };
  factory CanonicalPresetBlock.fromJson(Map<String, Object?> map) {
    if (map['enabled'] is! bool ||
        map['order'] is! int ||
        (map['algorithmCode'] != null && map['algorithmCode'] is! int) ||
        map['parameters'] is! List) {
      throw const FormatException('Invalid preset block.');
    }
    return CanonicalPresetBlock(
      id: requiredText(map, 'id'),
      type: enumValue(PresetBlockType.values, map['type']),
      enabled: map['enabled'] as bool,
      order: map['order'] as int,
      model: map['model'] as String?,
      algorithmCode: map['algorithmCode'] as int?,
      parameters: (map['parameters'] as List)
          .map((p) => PresetParameter.fromJson(objectMap(p)))
          .toList(),
      source: requiredText(map, 'source'),
      evidence: enumValue(EvidenceLevel.values, map['evidenceLevel']),
      compatibility: requiredText(map, 'compatibility'),
      warnings: textList(map['warnings']),
    );
  }
}

class CanonicalPreset {
  CanonicalPreset({
    this.schemaVersion = currentSchemaVersion,
    required this.id,
    required this.name,
    required this.artist,
    required this.song,
    required this.genre,
    required this.role,
    required this.tuning,
    required this.createdAt,
    required this.modifiedAt,
    required this.origin,
    required this.targetDevice,
    required this.guitarId,
    required this.guitarName,
    required List<CanonicalPresetBlock> blocks,
    this.ir,
    this.nam,
    List<String> warnings = const [],
    List<String> notes = const [],
  }) : blocks = List.unmodifiable(blocks),
       warnings = List.unmodifiable(warnings),
       notes = List.unmodifiable(notes);
  static const currentSchemaVersion = 1;
  final int schemaVersion;
  final String id,
      name,
      artist,
      song,
      genre,
      role,
      tuning,
      targetDevice,
      guitarId,
      guitarName;
  final DateTime createdAt, modifiedAt;
  final PresetOrigin origin;
  final List<CanonicalPresetBlock> blocks;
  final List<String> warnings, notes;
  final PresetAssetReference? ir, nam;
  CanonicalPreset copyWith({
    String? name,
    List<CanonicalPresetBlock>? blocks,
    DateTime? modifiedAt,
  }) => CanonicalPreset(
    schemaVersion: schemaVersion,
    id: id,
    name: name ?? this.name,
    artist: artist,
    song: song,
    genre: genre,
    role: role,
    tuning: tuning,
    createdAt: createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    origin: origin,
    targetDevice: targetDevice,
    guitarId: guitarId,
    guitarName: guitarName,
    blocks: blocks ?? this.blocks,
    ir: ir,
    nam: nam,
    warnings: warnings,
    notes: notes,
  );
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'name': name,
    'artist': artist,
    'song': song,
    'genre': genre,
    'role': role,
    'tuning': tuning,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'modifiedAt': modifiedAt.toUtc().toIso8601String(),
    'origin': origin.name,
    'targetDevice': targetDevice,
    'guitar': {'id': guitarId, 'name': guitarName},
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'ir': ir?.toJson(),
    'nam': nam?.toJson(),
    'warnings': warnings,
    'notes': notes,
  };
  factory CanonicalPreset.fromJson(Map<String, Object?> map) {
    if (map['schemaVersion'] != currentSchemaVersion) {
      throw const FormatException(
        'Unsupported WyrmTone preset schema version; no migration available.',
      );
    }
    if (map['blocks'] is! List) {
      throw const FormatException('Missing preset blocks.');
    }
    final guitar = objectMap(map['guitar']);
    return CanonicalPreset(
      id: requiredText(map, 'id'),
      name: requiredText(map, 'name'),
      artist: map['artist'] as String,
      song: map['song'] as String,
      genre: map['genre'] as String,
      role: requiredText(map, 'role'),
      tuning: requiredText(map, 'tuning'),
      createdAt: DateTime.parse(requiredText(map, 'createdAt')),
      modifiedAt: DateTime.parse(requiredText(map, 'modifiedAt')),
      origin: enumValue(PresetOrigin.values, map['origin']),
      targetDevice: requiredText(map, 'targetDevice'),
      guitarId: requiredText(guitar, 'id'),
      guitarName: requiredText(guitar, 'name'),
      blocks: (map['blocks'] as List)
          .map((b) => CanonicalPresetBlock.fromJson(objectMap(b)))
          .toList(),
      ir: map['ir'] == null
          ? null
          : PresetAssetReference.fromJson(objectMap(map['ir'])),
      nam: map['nam'] == null
          ? null
          : PresetAssetReference.fromJson(objectMap(map['nam'])),
      warnings: textList(map['warnings']),
      notes: textList(map['notes']),
    );
  }
}
