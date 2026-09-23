/// Precomputed, fully offline search index over [ToneVaultEntry] lists.
///
/// Everything a query needs is a hash lookup: phrase dictionaries per field
/// (artist, song, album, title/search alias, tag), genre and era posting lists,
/// and a token vocabulary for typo correction. Fuzzy work touches only the
/// vocabulary (a few thousand distinct tokens for 5,000+ entries), never every
/// entry, and only for query tokens that are not already known words.
library;

import '../models/guitar_profile.dart' show GuitarTuning, GuitarTuningLabel;
import 'tone_nlu_lexicon.dart';
import 'tone_vault_model.dart';
import 'tone_vault_taxonomy.dart';
import 'tone_vault_text.dart';

class PhraseDict {
  final Map<String, List<int>> exact = {};
  final Map<String, List<int>> alias = {};
  void addExact(String phrase, int idx) => _add(exact, phrase, idx);
  void addAlias(String phrase, int idx) => _add(alias, phrase, idx);
  static void _add(Map<String, List<int>> map, String phrase, int idx) {
    final key = ToneText.normalize(phrase);
    if (key.isEmpty) return;
    final list = map.putIfAbsent(key, () => []);
    if (list.isEmpty || list.last != idx) list.add(idx);
  }

  bool contains(String key) => exact.containsKey(key) || alias.containsKey(key);
  Iterable<String> get keys sync* {
    yield* exact.keys;
    yield* alias.keys;
  }
}

class ToneVaultIndex {
  ToneVaultIndex(List<ToneVaultEntry> input, this.taxonomy, this.vocabulary, {ToneNluLexicon? lexicon})
    : entries = List.unmodifiable(input),
      lexicon = lexicon ?? ToneNluLexicon.empty {
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.artist != null && e.artist!.isNotEmpty) {
        artists.addExact(e.artist!, i);
        for (final a in e.artistAliases) {
          artists.addAlias(a, i);
        }
        artistDisplay.putIfAbsent(ToneText.normalize(e.artist!), () => e.artist!);
      }
      if (e.song != null && e.song!.isNotEmpty) {
        songs.addExact(e.song!, i);
        for (final a in e.songAliases) {
          songs.addAlias(a, i);
        }
      }
      if (e.album != null && e.album!.isNotEmpty) {
        albums.addExact(e.album!, i);
        for (final a in e.albumAliases) {
          albums.addAlias(a, i);
        }
      }
      titles.addExact(e.title, i);
      for (final a in e.searchAliases) {
        titles.addAlias(a, i);
      }
      for (final v in e.variants) {
        for (final a in v.aliases) {
          titles.addAlias(a, i);
        }
      }
      for (final t in e.tags) {
        tags.addExact(t, i);
      }
      for (final g in {...e.genres, ...e.subgenres}) {
        byGenre.putIfAbsent(g, () => []).add(i);
      }
      final era = e.era ?? (e.year == null ? null : taxonomy.eraForYear(e.year!));
      for (final id in {?era, ...e.eras}) {
        byEra.putIfAbsent(id, () => []).add(i);
      }
    }
    for (final t in GuitarTuning.values.where((t) => t != GuitarTuning.custom)) {
      // '#' must survive normalization: "Drop C#" is not "Drop C"
      tunings[ToneText.normalize(t.label.replaceAll('#', 'sharp'))] = t.name;
    }
    tunings.addAll(this.lexicon.tuningPhrases);
    stopwords = {...vocabulary.stopwords, ...this.lexicon.stopwords};
    // vocabulary for typo correction: every word the index or the interpreter knows
    void learn(Iterable<String> phrases) {
      for (final phrase in phrases) {
        for (final token in phrase.split(' ')) {
          if (token.isEmpty) continue;
          tokenFreq[token] = (tokenFreq[token] ?? 0) + 1;
        }
      }
    }

    learn(artists.keys);
    learn(songs.keys);
    learn(albums.keys);
    learn(titles.keys);
    learn(tags.keys);
    learn(taxonomy.genrePhrases);
    learn(taxonomy.eraPhrases);
    learn(vocabulary.roleWords.keys);
    learn(vocabulary.modifierPhrases.keys);
    learn(vocabulary.stopwords);
    learn(vocabulary.descriptorTags.keys);
    learn(tunings.keys);
    learn(this.lexicon.words);
    for (final token in tokenFreq.keys) {
      tokensByLength.putIfAbsent(token.length, () => []).add(token);
      tokensByPhonetic.putIfAbsent(ToneText.phonetic(token), () => []).add(token);
    }
    for (final list in tokensByLength.values) {
      list.sort();
    }
    for (final list in tokensByPhonetic.values) {
      list.sort();
    }
    var maxTokens = 1;
    for (final key in [...artists.keys, ...songs.keys, ...albums.keys, ...titles.keys, ...tags.keys, ...taxonomy.genrePhrases, ...taxonomy.eraPhrases, ...vocabulary.roleWords.keys, ...vocabulary.modifierPhrases.keys]) {
      final n = ' '.allMatches(key).length + 1;
      if (n > maxTokens) maxTokens = n;
    }
    maxPhraseTokens = maxTokens > this.lexicon.maxPhraseTokens ? maxTokens : this.lexicon.maxPhraseTokens;
  }

  final List<ToneVaultEntry> entries;
  final ToneTaxonomy taxonomy;
  final ToneVocabulary vocabulary;
  final ToneNluLexicon lexicon;

  /// Stop words of the vocabulary and the NLU lexicon.
  late final Set<String> stopwords;

  final artists = PhraseDict();
  final songs = PhraseDict();
  final albums = PhraseDict();
  final titles = PhraseDict();
  final tags = PhraseDict();
  final Map<String, String> artistDisplay = {};
  final Map<String, List<int>> byGenre = {};
  final Map<String, List<int>> byEra = {};
  final Map<String, String> tunings = {};
  final Map<String, int> tokenFreq = {};
  final Map<int, List<String>> tokensByLength = {};
  final Map<String, List<String>> tokensByPhonetic = {};
  late final int maxPhraseTokens;

  final Map<String, String?> _corrections = {};

  /// A known word close to [token] (typo, missing/extra letter, swap, sound-alike), or null.
  /// Deterministic: best distance, then more frequent word, then alphabetical.
  String? correct(String token) {
    if (tokenFreq.containsKey(token) || token.length < 4 || RegExp(r'\d').hasMatch(token)) return null;
    if (_corrections.containsKey(token)) return _corrections[token];
    final limit = token.length <= 7 ? 1 : 2;
    String? best;
    var bestDistance = limit + 1;
    var bestFreq = -1;
    void consider(String candidate, int distance) {
      final freq = tokenFreq[candidate]!;
      if (distance < bestDistance ||
          (distance == bestDistance && (freq > bestFreq || (freq == bestFreq && candidate.compareTo(best!) < 0)))) {
        best = candidate;
        bestDistance = distance;
        bestFreq = freq;
      }
    }

    final sound = tokensByPhonetic[ToneText.phonetic(token)];
    if (sound != null) {
      for (final c in sound) {
        consider(c, ToneText.distance(token, c, limit + 1) > limit ? limit : ToneText.distance(token, c, limit));
      }
    }
    for (var len = token.length - limit; len <= token.length + limit; len++) {
      final bucket = tokensByLength[len];
      if (bucket == null) continue;
      for (final c in bucket) {
        if (c.codeUnitAt(0) != token.codeUnitAt(0)) continue; // a wrong first letter is too aggressive
        final d = ToneText.distance(token, c, limit);
        if (d <= limit) consider(c, d);
      }
    }
    return _corrections[token] = best;
  }
}
