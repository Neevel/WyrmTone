/// Pack parsing and validation for ToneVault imports. Deterministic and total:
/// every problem becomes an issue; nothing is silently dropped or repaired.
library;

import 'dart:convert';

import '../models/guitar_profile.dart' show GuitarTuning;
import '../models/tone_target.dart' show ToneDimension;
import '../presets/tone_intent.dart' show DelayKind, ModulationKind, PreAmpKind, ReverbKind;
import 'tone_vault_composer.dart';
import 'tone_vault_model.dart';
import 'tone_vault_taxonomy.dart';
import 'tone_vault_text.dart';

enum IssueSeverity { error, warning }

class ToneVaultIssue {
  const ToneVaultIssue(this.code, this.severity, this.message, {this.entryId, this.pack});
  final String code;
  final IssueSeverity severity;
  final String message;
  final String? entryId, pack;
  bool get isError => severity == IssueSeverity.error;
  @override
  String toString() => '${severity.name.toUpperCase()} $code${entryId == null ? '' : ' [$entryId]'}: $message';
}

class ParsedPack {
  const ParsedPack(this.pack, this.issues);
  final ToneVaultPack? pack;
  final List<ToneVaultIssue> issues;
}

abstract final class ToneVaultPackParser {
  /// Parses a pack file. Entry-level format errors become issues and the entry
  /// is left out (the pack then fails validation as a whole).
  static ParsedPack parse(String text) {
    final issues = <ToneVaultIssue>[];
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      return ParsedPack(null, [ToneVaultIssue('JSON_INVALID', IssueSeverity.error, e.message)]);
    }
    try {
      final r = JsonObjectReader(decoded, 'pack');
      final meta = JsonObjectReader(r.raw('pack'), 'pack.pack');
      final licenseReader = JsonObjectReader(meta.raw('license'), 'pack.pack.license');
      final license = PackLicense(
        name: licenseReader.string('name'),
        note: licenseReader.optString('note'),
        attribution: licenseReader.optString('attribution'),
      );
      licenseReader.done();
      final packId = meta.string('id');
      final schema = meta.intValue('schemaVersion');
      final name = meta.string('name');
      final version = meta.intValue('version');
      final description = meta.optString('description');
      final declaredCount = meta.optInt('entryCount');
      final classification = meta.optString('sourceClassification');
      meta.done();
      final sourceClassification = classification == null ? null : SourceClass.parse(classification, 'pack.pack.sourceClassification');
      if (schema != toneVaultSchemaVersion) {
        return ParsedPack(null, [
          ToneVaultIssue('SCHEMA_VERSION', IssueSeverity.error, 'Pack $packId: Schema $schema wird nicht unterstützt.', pack: packId),
        ]);
      }
      final entries = <ToneVaultEntry>[];
      final list = r.list('entries');
      for (var i = 0; i < list.length; i++) {
        try {
          entries.add(parseEntry(list[i], 'entries[$i]').withPack(packId));
        } on ToneVaultFormatException catch (e) {
          final id = list[i] is Map ? (list[i] as Map)['id'] : null;
          issues.add(ToneVaultIssue('PARSE_ERROR', IssueSeverity.error, '${e.path}: ${e.message}', entryId: id is String ? id : null, pack: packId));
        }
      }
      r.done();
      if (declaredCount != null && declaredCount != list.length) {
        issues.add(ToneVaultIssue('PACK_COUNT', IssueSeverity.error, 'Pack $packId: entryCount $declaredCount, tatsächlich ${list.length} Einträge.', pack: packId));
      }
      return ParsedPack(
        ToneVaultPack(
          id: packId,
          name: name,
          version: version,
          schemaVersion: schema,
          license: license,
          entries: entries,
          description: description,
          entryCount: declaredCount,
          sourceClassification: sourceClassification,
        ),
        issues,
      );
    } on ToneVaultFormatException catch (e) {
      return ParsedPack(null, [ToneVaultIssue('PACK_FORMAT', IssueSeverity.error, '${e.path}: ${e.message}')]);
    }
  }
}

abstract final class ToneVaultValidator {
  static final _claim = RegExp(
    r'original\s*studio|studio\s*settings|exakt\w*\s*(equipment|ausr[uü]stung|amp|setup)|exact\s*(equipment|amp|setup|settings)|originalequipment|original\s*equipment|original\s*settings',
    caseSensitive: false,
  );
  static final _negation = RegExp(r'(^|[^a-z])(keine?|nicht|ohne|no|not|without|never)($|[^a-z])', caseSensitive: false);

  /// A CLAIM about original equipment/settings. A sentence that negates it
  /// ("keine Aussage über Originalequipment") is a disclaimer, not a claim.
  static bool _hasClaim(String text) {
    for (final sentence in text.split(RegExp(r'[.;!?\n]'))) {
      if (_claim.hasMatch(sentence) && !_negation.hasMatch(sentence)) return true;
    }
    return false;
  }

  static final _deviceTerm = RegExp(
    r'sysex|qme2|wire\s*index|algorithm\s*(id|code)|parameter\s*(id|index)|matribox|dnafx|midi\s*byte',
    caseSensitive: false,
  );

  static Set<String> _kindValues(ToneKindSlot slot) => switch (slot) {
    ToneKindSlot.drive => {for (final k in PreAmpKind.values) k.name},
    ToneKindSlot.modulation => {for (final k in ModulationKind.values) k.name},
    ToneKindSlot.delay => {for (final k in DelayKind.values) k.name},
    ToneKindSlot.reverb => {for (final k in ReverbKind.values) k.name},
  };

  /// Validates entries of ONE OR MORE packs together (ids, parents and aliases are global).
  static List<ToneVaultIssue> validate(
    List<ToneVaultEntry> entries,
    ToneTaxonomy taxonomy,
  ) {
    final issues = <ToneVaultIssue>[];
    void error(String code, String message, ToneVaultEntry e) =>
        issues.add(ToneVaultIssue(code, IssueSeverity.error, message, entryId: e.id, pack: e.pack));
    void warn(String code, String message, ToneVaultEntry e) =>
        issues.add(ToneVaultIssue(code, IssueSeverity.warning, message, entryId: e.id, pack: e.pack));

    // 1. ids
    final byId = <String, ToneVaultEntry>{};
    for (final e in entries) {
      if (e.id.isEmpty || !RegExp(r'^[a-z0-9][a-z0-9._-]*$').hasMatch(e.id)) {
        error('ID_INVALID', 'Stabile ID "${e.id}" ist ungültig (a-z, 0-9, . _ -).', e);
      }
      if (byId.containsKey(e.id)) {
        error('DUPLICATE_ID', 'ID ${e.id} kommt mehrfach vor (Pack ${byId[e.id]!.pack} und ${e.pack}).', e);
      } else {
        byId[e.id] = e;
      }
    }

    for (final e in entries) {
      if (e.schemaVersion != toneVaultSchemaVersion) error('SCHEMA_VERSION', 'Schema ${e.schemaVersion} nicht unterstützt.', e);
      if (e.title.trim().isEmpty) error('TITLE_MISSING', 'Titel fehlt.', e);

      // 2. required fields by type
      switch (e.type) {
        case ToneEntryType.genreTemplate || ToneEntryType.styleTemplate:
          if (e.genres.isEmpty) error('GENRE_MISSING', 'Ein Template braucht mindestens ein Genre.', e);
        case ToneEntryType.artistSignature:
          if ((e.artist ?? '').isEmpty) error('ARTIST_MISSING', 'Artist-Signatur ohne Artist.', e);
        case ToneEntryType.eraSignature:
          if ((e.artist ?? '').isEmpty && e.genres.isEmpty) error('ERA_SCOPE_MISSING', 'Era-Signatur braucht Artist oder Genre.', e);
          if ((e.era ?? '').isEmpty) error('ERA_MISSING', 'Era-Signatur ohne era.', e);
        case ToneEntryType.albumSignature:
          if ((e.artist ?? '').isEmpty || (e.album ?? '').isEmpty) error('ALBUM_FIELDS_MISSING', 'Album-Signatur braucht artist und album.', e);
        case ToneEntryType.song || ToneEntryType.guitarReimagined:
          if ((e.song ?? '').isEmpty) error('SONG_MISSING', 'Song-Eintrag ohne song.', e);
        case ToneEntryType.originalWyrmtone:
          break;
      }

      // 3. source classification and claims
      if (e.sourceClass == SourceClass.researched && !e.sources.any((s) => s.title.trim().isNotEmpty)) {
        error('SOURCE_MISSING', 'RESEARCHED verlangt mindestens eine Quelle mit Titel.', e);
      }
      if (e.type == ToneEntryType.guitarReimagined && e.sourceClass != SourceClass.guitarReimagined) {
        error('SOURCE_TYPE_MISMATCH', 'GUITAR_REIMAGINED-Einträge brauchen die Quellenklasse GUITAR_REIMAGINED.', e);
      }
      if (e.type == ToneEntryType.originalWyrmtone && e.sourceClass != SourceClass.wyrmOriginal) {
        error('SOURCE_TYPE_MISMATCH', 'ORIGINAL_WYRMTONE-Einträge brauchen die Quellenklasse WYRM_ORIGINAL.', e);
      }
      if (e.sourceClass == SourceClass.guitarReimagined && e.type != ToneEntryType.guitarReimagined) {
        error('SOURCE_TYPE_MISMATCH', 'Die Quellenklasse GUITAR_REIMAGINED gehört nur zum Typ GUITAR_REIMAGINED.', e);
      }
      final texts = [e.title, e.notes ?? '', ...e.tags, ...e.searchAliases, for (final v in e.variants) ...[v.notes ?? '', v.title ?? '']];
      if (e.sourceClass != SourceClass.researched && texts.any(_hasClaim)) {
        error('CLAIM_WITHOUT_SOURCE', 'Behauptung über Originalequipment/-settings ohne RESEARCHED-Quelle.', e);
      }
      if (texts.any(_deviceTerm.hasMatch)) error('DEVICE_TERM', 'ToneVault darf kein Gerätewissen enthalten.', e);

      // 4. taxonomy refs
      for (final g in [...e.genres, ...e.subgenres]) {
        if (!taxonomy.hasGenre(g)) error('GENRE_UNKNOWN', 'Unbekanntes Genre "$g".', e);
      }
      if (e.era != null && !taxonomy.hasEra(e.era!)) error('ERA_UNKNOWN', 'Unbekannte Era "${e.era}".', e);
      for (final era in e.eras) {
        if (!taxonomy.hasEra(era)) error('ERA_UNKNOWN', 'Unbekannte Era "$era" in eras.', e);
      }
      if (e.year != null && (e.year! < 1900 || e.year! > 2100)) error('RANGE_INVALID', 'Jahr ${e.year} unplausibel.', e);
      for (final t in e.tuningHints) {
        if (!GuitarTuning.values.any((x) => x.name == t)) error('TUNING_UNKNOWN', 'Unbekannte Stimmung "$t".', e);
      }

      // 5. variants / roles
      final kinds = <ToneVariantKind>{};
      for (final v in e.variants) {
        if (!kinds.add(v.kind)) error('VARIANT_DUPLICATE', 'Variante ${v.kind.wire} doppelt.', e);
        if (e.roles.isNotEmpty && !e.roles.contains(v.kind)) warn('VARIANT_NOT_IN_ROLES', 'Variante ${v.kind.wire} steht nicht in roles.', e);
      }

      // 6. specs: ranges, kinds, contradictions
      void spec(ToneSpec s, String where) {
        s.dimensions.forEach((d, f) {
          if (f.mode == FieldMode.defined && (f.value! < 0 || f.value! > 100)) {
            error('RANGE_INVALID', '$where: ${d.name}=${f.value} außerhalb 0..100.', e);
          }
          if (f.mode == FieldMode.off && !toneEffectDimensions.contains(d)) {
            error('STATE_CONTRADICTION', '$where: ${d.name} kann nicht "off" sein (nur Effekt-Dimensionen).', e);
          }
        });
        s.character.forEach((a, f) {
          if (f.mode == FieldMode.defined && (f.value! < 0 || f.value! > 100)) {
            error('RANGE_INVALID', '$where: ${a.name}=${f.value} außerhalb 0..100.', e);
          }
        });
        s.kinds.forEach((slot, f) {
          if (f.mode == FieldMode.defined && !_kindValues(slot).contains(f.value)) {
            error('KIND_UNKNOWN', '$where: "${f.value}" ist keine ${slot.name}-Art.', e);
          }
        });
        bool off(ToneDimension d) => s.dimensions[d]?.mode == FieldMode.off;
        bool defined(ToneDimension d) => s.dimensions[d]?.mode == FieldMode.defined;
        if (off(ToneDimension.gateStrength) && defined(ToneDimension.gateOpening)) {
          error('STATE_CONTRADICTION', '$where: Gate aus, aber gateOpening gesetzt.', e);
        }
        for (final pair in [
          (ToneDimension.delay, ToneKindSlot.delay),
          (ToneDimension.reverb, ToneKindSlot.reverb),
          (ToneDimension.modulation, ToneKindSlot.modulation),
        ]) {
          if (off(pair.$1) && s.kinds[pair.$2]?.mode == FieldMode.defined) {
            error('STATE_CONTRADICTION', '$where: ${pair.$1.name} aus, aber Art ${s.kinds[pair.$2]!.value} gesetzt.', e);
          }
          if (s.kinds[pair.$2]?.mode == FieldMode.off && defined(pair.$1) && s.dimensions[pair.$1]!.value! > 0) {
            error('STATE_CONTRADICTION', '$where: Art ${pair.$2.name} aus, aber ${pair.$1.name} > 0.', e);
          }
        }
      }

      spec(e.tone, 'tone');
      for (final v in e.variants) {
        spec(v.tone, 'variant ${v.kind.wire}');
      }

      // 7. aliases inside one entry
      final own = <String>{};
      void alias(String label, Iterable<String> values) {
        for (final v in values) {
          final n = ToneText.normalize(v);
          if (n.isEmpty) {
            error('ALIAS_EMPTY', '$label enthält einen leeren Alias.', e);
          } else if (!own.add('$label:$n')) {
            error('ALIAS_DUPLICATE', '$label "$v" ist doppelt.', e);
          }
        }
      }

      alias('artistAliases', e.artistAliases);
      alias('songAliases', e.songAliases);
      alias('albumAliases', e.albumAliases);
      alias('searchAliases', e.searchAliases);
      for (final v in e.variants) {
        alias('variant ${v.kind.wire} aliases', v.aliases);
      }
    }

    // 8. parents: existence, rank, cycles
    for (final e in entries) {
      for (final p in e.parents) {
        final parent = byId[p];
        if (p == e.id) {
          error('PARENT_CYCLE', 'Eintrag ist sein eigener Parent.', e);
        } else if (parent == null) {
          error('PARENT_MISSING', 'Parent "$p" existiert nicht (nicht aufgelöste Template-Referenz).', e);
        } else if (parent.type.rank >= e.type.rank) {
          error('PARENT_RANK_INVALID', 'Parent $p (${parent.type.wire}) steht nicht über ${e.type.wire}.', e);
        }
      }
    }
    final cyclic = _cyclic(byId);
    for (final id in cyclic) {
      error('PARENT_CYCLE', 'Vererbungszyklus über $id.', byId[id]!);
    }

    // 9. INHERIT needs a value in the parent chain (only for cycle-free, complete graphs)
    if (cyclic.isEmpty && !issues.any((i) => i.code == 'PARENT_MISSING')) {
      final graph = ToneVaultGraph(entries);
      final composer = ToneComposer(graph);
      for (final e in entries) {
        final parentTone = _parentsResolved(e, graph, composer);
        void check(ToneSpec s, String where, ResolvedTone? base, ToneSpec? own) {
          s.dimensions.forEach((d, f) {
            if (f.mode == FieldMode.inherit && !(base?.provenance.containsKey('dimension:${d.name}') ?? false) &&
                !(own?.dimensions[d]?.mode == FieldMode.defined || own?.dimensions[d]?.mode == FieldMode.off)) {
              error('INHERIT_WITHOUT_PARENT_VALUE', '$where: ${d.name} ist "inherit", aber kein Parent liefert einen Wert.', e);
            }
          });
          s.kinds.forEach((k, f) {
            if (f.mode == FieldMode.inherit && !(base?.provenance.containsKey('kind:${k.name}') ?? false) &&
                !(own?.kinds[k]?.mode == FieldMode.defined || own?.kinds[k]?.mode == FieldMode.off)) {
              error('INHERIT_WITHOUT_PARENT_VALUE', '$where: Art ${k.name} ist "inherit", aber kein Parent liefert einen Wert.', e);
            }
          });
        }

        check(e.tone, 'tone', parentTone, null);
        for (final v in e.variants) {
          // a variant may inherit from the entry's own base as well as from its parents
          check(v.tone, 'variant ${v.kind.wire}', parentTone, e.tone);
        }
      }
    }

    // 10. artist identity and duplicate songs
    final artistOf = <String, String>{}; // normalized name/alias -> normalized canonical artist
    final songs = <String, String>{}; // artist|song -> entry id
    for (final e in entries) {
      final artist = e.artist;
      if (artist != null && artist.isNotEmpty) {
        final canonical = ToneText.normalize(artist);
        for (final name in [artist, ...e.artistAliases]) {
          final n = ToneText.normalize(name);
          final existing = artistOf[n];
          if (existing != null && existing != canonical) {
            error('ARTIST_ALIAS_CONFLICT', 'Artist/Alias "$name" gehört zu zwei verschiedenen Artists ($existing, $canonical).', e);
          } else {
            artistOf[n] = canonical;
          }
        }
      }
      if (e.type == ToneEntryType.song && artist != null && (e.song ?? '').isNotEmpty) {
        final key = '${ToneText.normalize(artist)}|${ToneText.normalize(e.song!)}';
        final other = songs[key];
        if (other != null) {
          error('DUPLICATE_SONG', 'Song "${e.song}" von $artist existiert schon als $other.', e);
        } else {
          songs[key] = e.id;
        }
      }
    }
    // an alias of a song title must not name a different song of the same artist
    final songNames = <String, String>{};
    for (final e in entries.where((x) => x.type == ToneEntryType.song && x.artist != null)) {
      for (final name in [e.song!, ...e.songAliases]) {
        final key = '${ToneText.normalize(e.artist!)}|${ToneText.normalize(name)}';
        final other = songNames[key];
        if (other != null && other != e.id) {
          error('SONG_ALIAS_CONFLICT', 'Songname/Alias "$name" ist bei $other und ${e.id} vergeben.', e);
        } else {
          songNames[key] = e.id;
        }
      }
    }
    return issues;
  }

  static ResolvedTone? _parentsResolved(ToneVaultEntry e, ToneVaultGraph graph, ToneComposer composer) {
    if (e.parents.isEmpty) return null;
    // compose the parents' chain only (the entry itself excluded)
    final probe = ToneVaultEntry(
      id: '\u0000probe',
      schemaVersion: e.schemaVersion,
      type: ToneEntryType.song,
      title: 'probe',
      sourceClass: SourceClass.curated,
      confidence: ToneConfidence.low,
      parents: e.parents,
    );
    final g = ToneVaultGraph([...graph.byId.values, probe]);
    return ToneComposer(g).resolve(probe.id);
  }

  /// Ids that are part of a parent cycle.
  static Set<String> _cyclic(Map<String, ToneVaultEntry> byId) {
    final state = <String, int>{}; // 1 = visiting, 2 = done
    final cyclic = <String>{};
    void visit(String id, List<String> path) {
      final e = byId[id];
      if (e == null) return;
      final s = state[id];
      if (s == 2) return;
      if (s == 1) {
        cyclic.addAll(path.sublist(path.indexOf(id)));
        return;
      }
      state[id] = 1;
      for (final p in e.parents) {
        visit(p, [...path, id]);
      }
      state[id] = 2;
    }

    for (final id in byId.keys) {
      visit(id, const []);
    }
    return cyclic;
  }
}
