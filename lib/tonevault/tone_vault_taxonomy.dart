/// Hierarchical genre/era taxonomy and the multilingual search vocabulary.
/// Both are DATA (assets/tonevault/taxonomy.json, vocabulary.json), so more
/// genres, eras or spellings never need a code change.
library;

import 'dart:convert';

import 'tone_vault_model.dart';
import 'tone_vault_text.dart';

class GenreNode {
  const GenreNode({required this.id, required this.name, this.parent, this.aliases = const []});
  final String id, name;
  final String? parent;
  final List<String> aliases;
}

class EraNode {
  const EraNode({required this.id, required this.name, required this.fromYear, required this.toYear, this.aliases = const []});
  final String id, name;
  final int fromYear, toYear;
  final List<String> aliases;
}

class ToneTaxonomy {
  ToneTaxonomy._(this.genres, this.eras)
    : _children = {},
      _phrases = {},
      _eraPhrases = {} {
    for (final g in genres.values) {
      if (g.parent != null) _children.putIfAbsent(g.parent!, () => []).add(g.id);
      for (final phrase in [g.name, g.id.replaceAll('_', ' '), ...g.aliases]) {
        final key = ToneText.normalize(phrase);
        if (key.isNotEmpty) _phrases.putIfAbsent(key, () => {}).add(g.id);
      }
    }
    for (final e in eras.values) {
      // decade ids ("1980s") are phrases too; the id "modern" is not: the bare word stays an adjective ("modern metal")
      for (final phrase in [e.name, if (e.id.contains(RegExp(r'\d'))) e.id.replaceAll('_', ' '), ...e.aliases]) {
        final key = ToneText.normalize(phrase);
        if (key.isNotEmpty) _eraPhrases[key] = e.id;
      }
    }
  }

  final Map<String, GenreNode> genres;
  final Map<String, EraNode> eras;
  final Map<String, List<String>> _children;
  final Map<String, Set<String>> _phrases;
  final Map<String, String> _eraPhrases;

  static ToneTaxonomy parse(String text) {
    final r = JsonObjectReader(jsonDecode(text), 'taxonomy');
    if (r.intValue('schemaVersion') != toneVaultSchemaVersion) {
      throw const ToneVaultFormatException('taxonomy.schemaVersion', 'Unbekannte Taxonomie-Version.');
    }
    final genres = <String, GenreNode>{};
    for (var i = 0; i < r.list('genres').length; i++) {
      final g = JsonObjectReader(r.list('genres')[i], 'taxonomy.genres[$i]');
      final node = GenreNode(id: g.string('id'), name: g.string('name'), parent: g.optString('parent'), aliases: g.strings('aliases'));
      g.done();
      if (genres.containsKey(node.id)) throw ToneVaultFormatException('taxonomy.genres[$i]', 'Doppelte Genre-ID ${node.id}.');
      genres[node.id] = node;
    }
    for (final g in genres.values) {
      if (g.parent != null && !genres.containsKey(g.parent)) {
        throw ToneVaultFormatException('taxonomy.genres.${g.id}', 'Unbekannter Parent ${g.parent}.');
      }
    }
    final eras = <String, EraNode>{};
    for (var i = 0; i < r.list('eras').length; i++) {
      final e = JsonObjectReader(r.list('eras')[i], 'taxonomy.eras[$i]');
      final node = EraNode(
        id: e.string('id'),
        name: e.string('name'),
        fromYear: e.intValue('fromYear'),
        toYear: e.intValue('toYear'),
        aliases: e.strings('aliases'),
      );
      e.done();
      eras[node.id] = node;
    }
    r.done();
    return ToneTaxonomy._(Map.unmodifiable(genres), Map.unmodifiable(eras));
  }

  bool hasGenre(String id) => genres.containsKey(id);
  bool hasEra(String id) => eras.containsKey(id);
  List<GenreNode> get roots => [for (final g in genres.values) if (g.parent == null) g];

  /// The genre itself plus every descendant.
  Set<String> withDescendants(String id) {
    final out = <String>{};
    void walk(String x) {
      if (!out.add(x)) return;
      for (final c in _children[x] ?? const <String>[]) {
        walk(c);
      }
    }

    walk(id);
    return out;
  }

  /// The root group (e.g. `metal`) of a genre.
  String groupOf(String id) {
    var current = genres[id];
    while (current?.parent != null) {
      current = genres[current!.parent];
    }
    return current?.id ?? id;
  }

  /// Genre ids for a normalized phrase (a name or alias), or empty.
  Set<String> genresForPhrase(String normalizedPhrase) => _phrases[normalizedPhrase] ?? const {};
  String? eraForPhrase(String normalizedPhrase) => _eraPhrases[normalizedPhrase];
  Iterable<String> get genrePhrases => _phrases.keys;
  Iterable<String> get eraPhrases => _eraPhrases.keys;

  String? eraForYear(int year) => eras.values.where((e) => year >= e.fromYear && year <= e.toYear).firstOrNull?.id;
}

/// Free-text vocabulary: role words, tuning-independent modifier phrases, stop words.
class ToneVocabulary {
  ToneVocabulary._(this.roleWords, this.modifierPhrases, this.stopwords, this.descriptorTags);

  /// normalized phrase -> variant
  final Map<String, ToneVariantKind> roleWords;

  /// normalized phrase -> modifier wire name (see ToneModifier)
  final Map<String, String> modifierPhrases;
  final Set<String> stopwords;

  /// normalized descriptor word -> tag (search only)
  final Map<String, String> descriptorTags;

  static ToneVocabulary parse(String text) {
    final r = JsonObjectReader(jsonDecode(text), 'vocabulary');
    if (r.intValue('schemaVersion') != toneVaultSchemaVersion) {
      throw const ToneVaultFormatException('vocabulary.schemaVersion', 'Unbekannte Vokabular-Version.');
    }
    final roles = <String, ToneVariantKind>{};
    final roleRaw = r.raw('roles');
    if (roleRaw is! Map) throw const ToneVaultFormatException('vocabulary.roles', 'Objekt erwartet.');
    for (final e in roleRaw.entries) {
      final kind = ToneVariantKind.parse('${e.key}', 'vocabulary.roles.${e.key}');
      for (final phrase in (e.value as List).cast<String>()) {
        roles[ToneText.normalize(phrase)] = kind;
      }
    }
    final modifiers = <String, String>{};
    final modRaw = r.raw('modifiers');
    if (modRaw is! Map) throw const ToneVaultFormatException('vocabulary.modifiers', 'Objekt erwartet.');
    for (final e in modRaw.entries) {
      for (final phrase in (e.value as List).cast<String>()) {
        modifiers[ToneText.normalize(phrase)] = '${e.key}';
      }
    }
    final descriptors = <String, String>{};
    final descRaw = r.raw('descriptors');
    if (descRaw is Map) {
      for (final e in descRaw.entries) {
        for (final phrase in (e.value as List).cast<String>()) {
          descriptors[ToneText.normalize(phrase)] = '${e.key}';
        }
      }
    }
    final stop = {for (final w in r.strings('stopwords')) ToneText.normalize(w)};
    r.done();
    return ToneVocabulary._(Map.unmodifiable(roles), Map.unmodifiable(modifiers), Set.unmodifiable(stop), Map.unmodifiable(descriptors));
  }
}
