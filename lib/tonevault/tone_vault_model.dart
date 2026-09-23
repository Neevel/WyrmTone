/// ToneVault V1 data model: device-INDEPENDENT musical tone knowledge.
///
/// Nothing in this library (or in any ToneVault pack) may know a device model,
/// algorithm code, parameter index, MIDI/SysEx byte or QME2 command. The
/// parser is strict: an unknown key is a format error, so device-specific
/// fields cannot be smuggled into a pack. Device values only arise in a device
/// translator, after a [ToneDefinition] became a CanonicalToneRecipe.
///
/// Field semantics (also for kind hints and character axes):
/// - absent (UNSPECIFIED): this layer says nothing; the value comes from the parent chain
/// - `"inherit"` (INHERIT): explicitly "take the parent's value" (the validator
///   requires that a parent chain provides one)
/// - `"off"` (OFF): explicit deactivation; overrides the parent (only for effect dimensions)
/// - a number/name (DEFINED): the layer defines the value
library;

import '../models/tone_target.dart' show ToneDimension;

const toneVaultSchemaVersion = 1;

class ToneVaultFormatException implements Exception {
  const ToneVaultFormatException(this.path, this.message);
  final String path;
  final String message;
  @override
  String toString() => 'ToneVaultFormatException($path): $message';
}

enum ToneEntryType {
  genreTemplate('GENRE_TEMPLATE', 0),
  styleTemplate('STYLE_TEMPLATE', 1),
  artistSignature('ARTIST_SIGNATURE', 2),
  eraSignature('ERA_SIGNATURE', 3),
  albumSignature('ALBUM_SIGNATURE', 4),
  song('SONG', 5),
  originalWyrmtone('ORIGINAL_WYRMTONE', 5),
  guitarReimagined('GUITAR_REIMAGINED', 5);

  const ToneEntryType(this.wire, this.rank);
  final String wire;

  /// A parent must have a strictly lower rank than its child
  /// (genre < style < artist < era < album < song/original/reimagined).
  final int rank;

  bool get isTemplate => this == genreTemplate || this == styleTemplate;
  static ToneEntryType parse(String v, String path) => ToneEntryType.values.firstWhere(
    (e) => e.wire == v,
    orElse: () => throw ToneVaultFormatException(path, 'Unbekannter Eintragstyp "$v".'),
  );
}

enum ToneVariantKind {
  rhythm('RHYTHM'),
  lead('LEAD'),
  solo('SOLO'),
  clean('CLEAN'),
  crunch('CRUNCH'),
  ambient('AMBIENT'),
  special('SPECIAL');

  const ToneVariantKind(this.wire);
  final String wire;
  static ToneVariantKind parse(String v, String path) => ToneVariantKind.values.firstWhere(
    (e) => e.wire == v,
    orElse: () => throw ToneVaultFormatException(path, 'Unbekannte Variante/Rolle "$v".'),
  );
}

/// Where a tone comes from. Independent of [ToneConfidence].
enum SourceClass {
  researched('RESEARCHED'),
  curated('CURATED'),
  styleInspired('STYLE_INSPIRED'),
  wyrmOriginal('WYRM_ORIGINAL'),
  guitarReimagined('GUITAR_REIMAGINED'),
  community('COMMUNITY'),
  aiGenerated('AI_GENERATED');

  const SourceClass(this.wire);
  final String wire;
  static SourceClass parse(String v, String path) => SourceClass.values.firstWhere(
    (e) => e.wire == v,
    orElse: () => throw ToneVaultFormatException(path, 'Unbekannte Quellenklasse "$v".'),
  );
}

/// How sure WyrmTone is that the recipe is the INTENDED interpretation. It says
/// nothing about historical equipment (that needs [SourceClass.researched]).
enum ToneConfidence {
  high('HIGH'),
  medium('MEDIUM'),
  low('LOW');

  const ToneConfidence(this.wire);
  final String wire;
  static ToneConfidence parse(String v, String path) => ToneConfidence.values.firstWhere(
    (e) => e.wire == v,
    orElse: () => throw ToneVaultFormatException(path, 'Unbekannte Confidence "$v".'),
  );
}

/// Block-type hints a tone can carry (kinds of the canonical vocabulary in tone_intent.dart).
enum ToneKindSlot { drive, modulation, delay, reverb }

/// Advisory character axes (0..100). They describe and search; they are NOT
/// consumed by a device translator in V1.
enum CharacterAxis { body, warmth, darkness, clarity, aggression, vintage, fuzziness, loFi, width }

enum FieldMode { unspecified, inherit, off, defined }

class ToneField<T> {
  const ToneField._(this.mode, this.value);
  const ToneField.unspecified() : this._(FieldMode.unspecified, null);
  const ToneField.inherit() : this._(FieldMode.inherit, null);
  const ToneField.off() : this._(FieldMode.off, null);
  const ToneField.defined(T value) : this._(FieldMode.defined, value);

  final FieldMode mode;
  final T? value;
  bool get isUnspecified => mode == FieldMode.unspecified;
  bool get isDefined => mode == FieldMode.defined;

  @override
  bool operator ==(Object other) => other is ToneField<T> && other.mode == mode && other.value == value;
  @override
  int get hashCode => Object.hash(mode, value);
  @override
  String toString() => mode == FieldMode.defined ? '$value' : mode.name;
}

/// Dimensions that describe an optional effect and may therefore be explicitly OFF.
const toneEffectDimensions = {
  ToneDimension.compression,
  ToneDimension.gateStrength,
  ToneDimension.space,
  ToneDimension.delay,
  ToneDimension.reverb,
  ToneDimension.modulation,
};

/// The overridable tone content of one layer (an entry's base or one variant).
class ToneSpec {
  const ToneSpec({
    this.dimensions = const {},
    this.character = const {},
    this.kinds = const {},
    this.ampFamilies = const ToneField.unspecified(),
    this.cabinet = const ToneField.unspecified(),
    this.speaker = const ToneField.unspecified(),
    this.microphone = const ToneField.unspecified(),
    this.namTags = const ToneField.unspecified(),
  });

  static const empty = ToneSpec();

  final Map<ToneDimension, ToneField<int>> dimensions;
  final Map<CharacterAxis, ToneField<int>> character;
  final Map<ToneKindSlot, ToneField<String>> kinds;
  final ToneField<List<String>> ampFamilies;
  final ToneField<String> cabinet, speaker, microphone;
  final ToneField<List<String>> namTags;

  bool get isEmpty =>
      dimensions.isEmpty &&
      character.isEmpty &&
      kinds.isEmpty &&
      ampFamilies.isUnspecified &&
      cabinet.isUnspecified &&
      speaker.isUnspecified &&
      microphone.isUnspecified &&
      namTags.isUnspecified;
}

class SourceRef {
  const SourceRef({required this.title, this.url, this.note});
  final String title;
  final String? url;
  final String? note;
}

class ToneVariant {
  const ToneVariant({
    required this.kind,
    this.title,
    this.aliases = const [],
    this.tone = ToneSpec.empty,
    this.notes,
    this.confidence,
  });
  final ToneVariantKind kind;
  final String? title;
  final List<String> aliases;
  final ToneSpec tone;
  final String? notes;
  final ToneConfidence? confidence;
}

class ToneVaultEntry {
  const ToneVaultEntry({
    required this.id,
    required this.schemaVersion,
    required this.type,
    required this.title,
    required this.sourceClass,
    required this.confidence,
    this.artist,
    this.artistAliases = const [],
    this.song,
    this.songAliases = const [],
    this.album,
    this.albumAliases = const [],
    this.era,
    this.year,
    this.eras = const [],
    this.genres = const [],
    this.subgenres = const [],
    this.tags = const [],
    this.roles = const [],
    this.tuningHints = const [],
    this.searchAliases = const [],
    this.parents = const [],
    this.sources = const [],
    this.notes,
    this.tone = ToneSpec.empty,
    this.variants = const [],
    this.legacyProfileId,
    this.goldReference = false,
    this.pack = '',
  });

  final String id;
  final int schemaVersion;
  final ToneEntryType type;
  final String title;
  final SourceClass sourceClass;
  final ToneConfidence confidence;
  final String? artist, song, album, era, notes, legacyProfileId;
  final List<String> artistAliases, songAliases, albumAliases;
  final int? year;

  /// Eras (taxonomy ids) the entry is characteristic for, in addition to [era]/[year] (search context only).
  final List<String> eras;
  final List<String> genres, subgenres, tags, tuningHints, searchAliases, parents;
  final List<ToneVariantKind> roles;
  final List<SourceRef> sources;
  final ToneSpec tone;
  final List<ToneVariant> variants;

  /// Marks a hand-curated, research-backed reference entry (e.g. Angels Don't Kill, CKY 96 Quite
  /// Bitter Beings) whose CanonicalToneRecipe was deliberately reviewed end to end, not just
  /// auto-inherited from a template. Purely an internal curation signal for prioritising future
  /// work -- never a user-facing ranking or ToneVault quality gate.
  final bool goldReference;

  /// Set by the pack loader (not part of an entry's JSON).
  final String pack;

  ToneVariant? variant(ToneVariantKind kind) => variants.where((v) => v.kind == kind).firstOrNull;

  ToneVaultEntry withPack(String packId) => ToneVaultEntry(
    id: id,
    schemaVersion: schemaVersion,
    type: type,
    title: title,
    sourceClass: sourceClass,
    confidence: confidence,
    artist: artist,
    artistAliases: artistAliases,
    song: song,
    songAliases: songAliases,
    album: album,
    albumAliases: albumAliases,
    era: era,
    year: year,
    eras: eras,
    genres: genres,
    subgenres: subgenres,
    tags: tags,
    roles: roles,
    tuningHints: tuningHints,
    searchAliases: searchAliases,
    parents: parents,
    sources: sources,
    notes: notes,
    tone: tone,
    variants: variants,
    legacyProfileId: legacyProfileId,
    goldReference: goldReference,
    pack: packId,
  );
}

class PackLicense {
  const PackLicense({required this.name, this.note, this.attribution});
  final String name;
  final String? note, attribution;
}

class ToneVaultPack {
  const ToneVaultPack({
    required this.id,
    required this.name,
    required this.version,
    required this.schemaVersion,
    required this.license,
    required this.entries,
    this.description,
    this.entryCount,
    this.sourceClassification,
  });
  final String id, name;
  final int version, schemaVersion;
  final String? description;

  /// Declared number of entries (validated against the actual list) and the pack's dominant source class.
  final int? entryCount;
  final SourceClass? sourceClassification;
  final PackLicense license;
  final List<ToneVaultEntry> entries;
}

// -------------------------------------------------------------------- strict JSON reading

/// Reads a JSON object and rejects keys nobody asked for.
class JsonObjectReader {
  JsonObjectReader(Object? raw, this.path) {
    if (raw is! Map) throw ToneVaultFormatException(path, 'Objekt erwartet.');
    _map = {for (final e in raw.entries) '${e.key}': e.value};
  }
  final String path;
  late final Map<String, Object?> _map;
  final _used = <String>{};

  String child(String key) => '$path.$key';

  Object? raw(String key) {
    _used.add(key);
    return _map[key];
  }

  bool has(String key) => _map.containsKey(key);

  String string(String key, {bool required = true}) {
    final v = raw(key);
    if (v == null) {
      if (required) throw ToneVaultFormatException(child(key), 'Pflichtfeld fehlt.');
      return '';
    }
    if (v is! String) throw ToneVaultFormatException(child(key), 'Text erwartet.');
    return v;
  }

  String? optString(String key) {
    final v = raw(key);
    if (v == null) return null;
    if (v is! String) throw ToneVaultFormatException(child(key), 'Text erwartet.');
    return v;
  }

  int? optInt(String key) {
    final v = raw(key);
    if (v == null) return null;
    if (v is! int) throw ToneVaultFormatException(child(key), 'Ganzzahl erwartet.');
    return v;
  }

  bool? optBool(String key) {
    final v = raw(key);
    if (v == null) return null;
    if (v is! bool) throw ToneVaultFormatException(child(key), 'Wahrheitswert erwartet.');
    return v;
  }

  int intValue(String key) => optInt(key) ?? (throw ToneVaultFormatException(child(key), 'Pflichtfeld fehlt.'));

  List<String> strings(String key) {
    final v = raw(key);
    if (v == null) return const [];
    if (v is! List || v.any((e) => e is! String)) {
      throw ToneVaultFormatException(child(key), 'Textliste erwartet.');
    }
    return List.unmodifiable(v.cast<String>());
  }

  List<Object?> list(String key) {
    final v = raw(key);
    if (v == null) return const [];
    if (v is! List) throw ToneVaultFormatException(child(key), 'Liste erwartet.');
    return v;
  }

  /// Fails if the object has keys that were never read.
  void done() {
    final extra = _map.keys.where((k) => !_used.contains(k)).toList()..sort();
    if (extra.isNotEmpty) {
      throw ToneVaultFormatException(path, 'Unbekannte Felder: ${extra.join(', ')} (keine Geräte-/Wire-Felder erlaubt).');
    }
  }
}

ToneField<int> _intField(Object? v, String path) {
  if (v == 'inherit') return const ToneField.inherit();
  if (v == 'off') return const ToneField.off();
  if (v is int) return ToneField.defined(v);
  throw ToneVaultFormatException(path, 'Ganzzahl, "off" oder "inherit" erwartet.');
}

ToneField<String> _textField(Object? v, String path) {
  if (v == 'inherit') return const ToneField.inherit();
  if (v == 'off') return const ToneField.off();
  if (v is String) return ToneField.defined(v);
  throw ToneVaultFormatException(path, 'Text, "off" oder "inherit" erwartet.');
}

ToneField<List<String>> _listField(Object? v, String path) {
  if (v == 'inherit') return const ToneField.inherit();
  if (v is List && v.every((e) => e is String)) return ToneField.defined(List.unmodifiable(v.cast<String>()));
  throw ToneVaultFormatException(path, 'Textliste oder "inherit" erwartet.');
}

ToneSpec parseToneSpec(Object? raw, String path) {
  if (raw == null) return ToneSpec.empty;
  final r = JsonObjectReader(raw, path);
  final dims = <ToneDimension, ToneField<int>>{};
  final dimRaw = r.raw('dimensions');
  if (dimRaw != null) {
    if (dimRaw is! Map) throw ToneVaultFormatException(r.child('dimensions'), 'Objekt erwartet.');
    for (final e in dimRaw.entries) {
      final d = ToneDimension.values.where((x) => x.name == e.key).firstOrNull;
      if (d == null) throw ToneVaultFormatException('$path.dimensions.${e.key}', 'Unbekannte Dimension.');
      dims[d] = _intField(e.value, '$path.dimensions.${e.key}');
    }
  }
  final axes = <CharacterAxis, ToneField<int>>{};
  final axRaw = r.raw('character');
  if (axRaw != null) {
    if (axRaw is! Map) throw ToneVaultFormatException(r.child('character'), 'Objekt erwartet.');
    for (final e in axRaw.entries) {
      final a = CharacterAxis.values.where((x) => x.name == e.key).firstOrNull;
      if (a == null) throw ToneVaultFormatException('$path.character.${e.key}', 'Unbekannte Charakter-Achse.');
      axes[a] = _intField(e.value, '$path.character.${e.key}');
    }
  }
  final kinds = <ToneKindSlot, ToneField<String>>{};
  final kindRaw = r.raw('kinds');
  if (kindRaw != null) {
    if (kindRaw is! Map) throw ToneVaultFormatException(r.child('kinds'), 'Objekt erwartet.');
    for (final e in kindRaw.entries) {
      final s = ToneKindSlot.values.where((x) => x.name == e.key).firstOrNull;
      if (s == null) throw ToneVaultFormatException('$path.kinds.${e.key}', 'Unbekannter Block-Typ-Hinweis.');
      kinds[s] = _textField(e.value, '$path.kinds.${e.key}');
    }
  }
  ToneField<List<String>> listField(String key) => r.has(key) ? _listField(r.raw(key), r.child(key)) : const ToneField.unspecified();
  ToneField<String> textField(String key) => r.has(key) ? _textField(r.raw(key), r.child(key)) : const ToneField.unspecified();
  final spec = ToneSpec(
    dimensions: Map.unmodifiable(dims),
    character: Map.unmodifiable(axes),
    kinds: Map.unmodifiable(kinds),
    ampFamilies: listField('ampFamilies'),
    cabinet: textField('cabinet'),
    speaker: textField('speaker'),
    microphone: textField('microphone'),
    namTags: listField('namTags'),
  );
  r.done();
  return spec;
}

ToneVariant _parseVariant(Object? raw, String path) {
  final r = JsonObjectReader(raw, path);
  final v = ToneVariant(
    kind: ToneVariantKind.parse(r.string('kind'), r.child('kind')),
    title: r.optString('title'),
    aliases: r.strings('aliases'),
    tone: parseToneSpec(r.raw('tone'), r.child('tone')),
    notes: r.optString('notes'),
    confidence: r.has('confidence') ? ToneConfidence.parse(r.string('confidence'), r.child('confidence')) : null,
  );
  r.done();
  return v;
}

ToneVaultEntry parseEntry(Object? raw, String path) {
  final r = JsonObjectReader(raw, path);
  final sourceRaw = r.raw('source');
  final s = JsonObjectReader(sourceRaw, r.child('source'));
  final sourceClass = SourceClass.parse(s.string('classification'), s.child('classification'));
  final refs = [
    for (var i = 0; i < s.list('references').length; i++)
      () {
        final rr = JsonObjectReader(s.list('references')[i], '${s.child('references')}[$i]');
        final ref = SourceRef(title: rr.string('title'), url: rr.optString('url'), note: rr.optString('note'));
        rr.done();
        return ref;
      }(),
  ];
  s.done();
  final entry = ToneVaultEntry(
    id: r.string('id'),
    schemaVersion: r.intValue('schemaVersion'),
    type: ToneEntryType.parse(r.string('type'), r.child('type')),
    title: r.string('title'),
    artist: r.optString('artist'),
    artistAliases: r.strings('artistAliases'),
    song: r.optString('song'),
    songAliases: r.strings('songAliases'),
    album: r.optString('album'),
    albumAliases: r.strings('albumAliases'),
    era: r.optString('era'),
    year: r.optInt('year'),
    eras: r.strings('eras'),
    genres: r.strings('genres'),
    subgenres: r.strings('subgenres'),
    tags: r.strings('tags'),
    roles: [for (final v in r.strings('roles')) ToneVariantKind.parse(v, r.child('roles'))],
    tuningHints: r.strings('tuningHints'),
    searchAliases: r.strings('searchAliases'),
    parents: r.strings('parents'),
    sourceClass: sourceClass,
    sources: refs,
    confidence: ToneConfidence.parse(r.string('confidence'), r.child('confidence')),
    notes: r.optString('notes'),
    tone: parseToneSpec(r.raw('tone'), r.child('tone')),
    variants: [
      for (var i = 0; i < r.list('variants').length; i++) _parseVariant(r.list('variants')[i], '${r.child('variants')}[$i]'),
    ],
    legacyProfileId: r.optString('legacyProfileId'),
    goldReference: r.optBool('goldReference') ?? false,
  );
  r.done();
  return entry;
}
