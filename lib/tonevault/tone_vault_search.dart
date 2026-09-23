/// ToneVault search and resolution (V1): free text or a structured [ToneQuery]
/// -> ranked, explained candidates. No cloud, no ML, deterministic.
///
/// Order of trust: exact phrase > alias > sound-alike/typo correction. A typo
/// correction only counts when the corrected words form a COMPLETE known phrase.
/// The resolver never picks an arbitrary single tone for an ambiguous request
/// ("Metallica"): it returns the structured options and says a choice is needed.
library;

import '../models/tone_target.dart' show ToneDimension;
import 'tone_nlu_lexicon.dart';
import 'tone_vault_index.dart';
import 'tone_vault_model.dart';
import 'tone_vault_query.dart';
import 'tone_vault_text.dart';

enum MatchKind { song, artist, album, title, tag, genre, era, role, modifier, tuning, intensity, negation, effect, adjective, param }

class ToneMatchReason {
  const ToneMatchReason(this.kind, this.phrase, this.weight, {this.alias = false, this.fuzzy = false});
  final MatchKind kind;
  final String phrase;
  final double weight;

  /// Matched an alias/alternative spelling instead of the canonical name.
  final bool alias;

  /// A typo/sound-alike correction was needed.
  final bool fuzzy;
  @override
  String toString() => '${kind.name}${alias ? '(alias)' : ''}${fuzzy ? '(fuzzy)' : ''}:"$phrase"=$weight';
}

class ToneCandidate {
  const ToneCandidate({required this.entry, required this.score, required this.reasons, this.variant, this.variantSupported = true});
  final ToneVaultEntry entry;
  final double score;
  final List<ToneMatchReason> reasons;
  final ToneVariantKind? variant;

  /// False when a variant was requested that neither the entry nor a template supplies.
  final bool variantSupported;
  bool get fuzzy => reasons.any((r) => r.fuzzy);
}

enum ResolutionKind {
  /// Nothing recognized.
  none,

  /// Exactly one entry is clearly meant.
  exact,

  /// Several legitimate options: the user (or a later step) must choose.
  choose,
}

class ToneVaultResolution {
  const ToneVaultResolution({
    required this.query,
    required this.kind,
    required this.candidates,
    required this.unmatched,
    required this.fuzzyUsed,
    this.primary,
  });
  final ToneQuery query;
  final ResolutionKind kind;

  /// Ranked candidates (best first); deterministic.
  final List<ToneCandidate> candidates;
  final ToneCandidate? primary;

  /// Significant query words that matched nothing.
  final List<String> unmatched;
  final bool fuzzyUsed;
  bool get requiresChoice => kind == ResolutionKind.choose;
}

/// One recognized piece of the request (token range [start], [end]) and what it is.
class ToneSpan {
  ToneSpan(this.kind, this.start, this.end, this.phrase, {this.alias = false, this.fuzzy = false, this.payload});
  final MatchKind kind;
  final int start, end;
  final String phrase;
  final bool alias, fuzzy;
  final Object? payload;
}

class ToneInterpretation {
  const ToneInterpretation({
    required this.query,
    required this.spans,
    required this.tokens,
    required this.unmatched,
    required this.fuzzy,
    required this.corrections,
  });
  final ToneQuery query;
  final List<ToneSpan> spans;

  /// The (typo-corrected, normalized) tokens the spans refer to.
  final List<String> tokens;
  final List<String> unmatched;
  final bool fuzzy;

  /// token index -> the word the user typed, for corrected words.
  final Map<int, String> corrections;
}

class ToneVaultResolver {
  ToneVaultResolver(this.index);
  final ToneVaultIndex index;

  static const _wSong = 100.0, _wSongAlias = 90.0;
  static const _wArtist = 40.0, _wArtistAlias = 36.0;
  static const _wAlbum = 60.0, _wAlbumAlias = 54.0;
  static const _wTitle = 70.0, _wTitleAlias = 62.0;
  static const _wGenre = 30.0, _wEra = 30.0, _wTag = 15.0, _wRole = 10.0;
  static const _fuzzFactor = 0.85;

  // ------------------------------------------------------------------ interpretation

  List<ToneSpan> _spans(List<String> tokens, {required Set<int> fuzzyTokens}) {
    final spans = <ToneSpan>[];
    var i = 0;
    while (i < tokens.length) {
      ToneSpan? best;
      final maxN = index.maxPhraseTokens < tokens.length - i ? index.maxPhraseTokens : tokens.length - i;
      for (var n = maxN; n >= 1 && best == null; n--) {
        final phrase = tokens.sublist(i, i + n).join(' ');
        final fuzzy = List.generate(n, (k) => i + k).any(fuzzyTokens.contains);
        ToneSpan? hit;
        // priority at equal length: song, artist, album, title, genre, era, tuning, modifier, role, descriptor, tag
        if (index.songs.exact.containsKey(phrase)) {
          hit = ToneSpan(MatchKind.song, i, i + n, phrase, fuzzy: fuzzy);
        } else if (index.artists.exact.containsKey(phrase)) {
          hit = ToneSpan(MatchKind.artist, i, i + n, phrase, fuzzy: fuzzy);
        } else if (index.albums.exact.containsKey(phrase)) {
          hit = ToneSpan(MatchKind.album, i, i + n, phrase, fuzzy: fuzzy);
        } else if (index.songs.alias.containsKey(phrase)) {
          hit = ToneSpan(MatchKind.song, i, i + n, phrase, alias: true, fuzzy: fuzzy);
        } else if (index.artists.alias.containsKey(phrase)) {
          hit = ToneSpan(MatchKind.artist, i, i + n, phrase, alias: true, fuzzy: fuzzy);
        } else if (index.albums.alias.containsKey(phrase)) {
          hit = ToneSpan(MatchKind.album, i, i + n, phrase, alias: true, fuzzy: fuzzy);
        } else if (index.titles.contains(phrase)) {
          hit = ToneSpan(MatchKind.title, i, i + n, phrase, alias: !index.titles.exact.containsKey(phrase), fuzzy: fuzzy);
        } else if (index.taxonomy.genresForPhrase(phrase).isNotEmpty) {
          hit = ToneSpan(MatchKind.genre, i, i + n, phrase, fuzzy: fuzzy, payload: index.taxonomy.genresForPhrase(phrase));
        } else if (index.taxonomy.eraForPhrase(phrase) != null) {
          hit = ToneSpan(MatchKind.era, i, i + n, phrase, fuzzy: fuzzy, payload: index.taxonomy.eraForPhrase(phrase));
        } else if (index.tunings.containsKey(phrase)) {
          hit = ToneSpan(MatchKind.tuning, i, i + n, phrase, payload: index.tunings[phrase]);
        } else if (index.vocabulary.modifierPhrases.containsKey(phrase)) {
          hit = ToneSpan(MatchKind.modifier, i, i + n, phrase, payload: index.vocabulary.modifierPhrases[phrase]);
        } else if (index.vocabulary.roleWords.containsKey(phrase)) {
          hit = ToneSpan(MatchKind.role, i, i + n, phrase, payload: index.vocabulary.roleWords[phrase]);
        } else if (index.vocabulary.descriptorTags.containsKey(phrase) && index.tags.exact.containsKey(index.vocabulary.descriptorTags[phrase]!)) {
          hit = ToneSpan(MatchKind.tag, i, i + n, phrase, payload: index.vocabulary.descriptorTags[phrase]);
        } else if (index.tags.exact.containsKey(phrase)) {
          hit = ToneSpan(MatchKind.tag, i, i + n, phrase, fuzzy: fuzzy);
        } else if (index.lexicon.phrases[phrase] case final e?) {
          hit = ToneSpan(
            switch (e.kind) {
              LexKind.modifier => MatchKind.modifier,
              LexKind.intensity => MatchKind.intensity,
              LexKind.negation => MatchKind.negation,
              LexKind.effect => MatchKind.effect,
              LexKind.adjective => MatchKind.adjective,
              LexKind.param => MatchKind.param,
            },
            i,
            i + n,
            phrase,
            fuzzy: fuzzy,
            payload: e.payload,
          );
        }
        best = hit;
      }
      if (best == null) {
        i++;
      } else {
        spans.add(best);
        i = best.end;
      }
    }
    return spans;
  }

  /// Free text -> structured query (+ the spans that explain it).
  ToneInterpretation interpret(String text) {
    final tokens = index.lexicon.isEmpty ? ToneText.tokens(text) : index.lexicon.tokens(text, index.tokenFreq.containsKey);
    var spans = _spans(tokens, fuzzyTokens: const {});
    var fuzzy = false;
    var current = tokens;
    // typo correction for words that stayed unmatched
    final unmatchedIdx = _unmatchedIndexes(current.length, spans);
    final corrected = [...current];
    final fuzzyTokens = <int>{};
    final corrections = <int, String>{};
    for (final k in unmatchedIdx) {
      if (index.stopwords.contains(current[k])) continue;
      final fix = index.correct(current[k]);
      if (fix != null) {
        corrections[k] = current[k];
        corrected[k] = fix;
        fuzzyTokens.add(k);
      }
    }
    if (fuzzyTokens.isNotEmpty) {
      final retry = _spans(corrected, fuzzyTokens: fuzzyTokens);
      // a correction only counts if the corrected word ended up inside a matched span
      final used = {for (final s in retry) for (var k = s.start; k < s.end; k++) k};
      if (fuzzyTokens.any(used.contains)) {
        spans = retry;
        current = corrected;
        fuzzy = true;
      } else {
        corrections.clear();
      }
    }
    // a phrase that is a song title AND an artist name ("Overkill"): with no other artist in the request the
    // act is meant; next to another artist ("Motörhead Overkill") it is the song
    if (!spans.any((x) => x.kind == MatchKind.artist)) {
      spans = [
        for (final x in spans)
          (x.kind == MatchKind.song && !x.alias && index.artists.exact.containsKey(x.phrase))
              ? ToneSpan(MatchKind.artist, x.start, x.end, x.phrase, fuzzy: x.fuzzy)
              : x,
      ];
    }
    // "clean", "crunch", "ambient" are variants AND genres of the taxonomy: next to another
    // entity they are the requested variant, on their own they may still be the genre
    bool isEntity(ToneSpan s) => const {MatchKind.artist, MatchKind.song, MatchKind.album, MatchKind.title, MatchKind.genre, MatchKind.era, MatchKind.tag}.contains(s.kind);
    spans = [
      for (final s in spans)
        (s.kind == MatchKind.genre && index.vocabulary.roleWords.containsKey(s.phrase) && spans.any((o) => !identical(o, s) && isEntity(o) && !(o.kind == MatchKind.genre && index.vocabulary.roleWords.containsKey(o.phrase))))
            ? ToneSpan(MatchKind.role, s.start, s.end, s.phrase, payload: index.vocabulary.roleWords[s.phrase])
            : s,
    ];
    final covered = {for (final s in spans) for (var k = s.start; k < s.end; k++) k};
    final unmatched = [
      for (var k = 0; k < current.length; k++)
        if (!covered.contains(k) && !index.stopwords.contains(current[k])) current[k],
    ];

    String? artist, song, album, genre, era, tuning, title;
    ToneVariantKind? role;
    final modifiers = <ToneModifier>[];
    final tagList = <String>[];
    for (final s in spans) {
      switch (s.kind) {
        case MatchKind.artist:
          if (artist == null) {
            final idx = (s.alias ? index.artists.alias : index.artists.exact)[s.phrase]!;
            artist = index.entries[idx.first].artist;
          }
        case MatchKind.song:
          song ??= s.phrase;
        case MatchKind.album:
          album ??= s.phrase;
        case MatchKind.genre:
          genre ??= (s.payload as Set<String>).first;
        case MatchKind.era:
          era ??= s.payload as String;
        case MatchKind.tuning:
          tuning ??= s.payload as String;
        case MatchKind.role:
          role ??= s.payload as ToneVariantKind;
        case MatchKind.modifier:
          for (final wire in (s.payload as String).split(',')) {
            final m = ToneModifier.tryParse(wire);
            if (m != null) modifiers.add(m);
          }
        case MatchKind.intensity || MatchKind.negation || MatchKind.effect || MatchKind.adjective || MatchKind.param:
          break; // composed by the Mini-NLU (tone_nlu.dart)
        case MatchKind.tag:
          // a word the lexicon knows as an EFFECT ("with chorus") is a wish, not a search tag
          if (index.lexicon.phrases[s.phrase]?.kind == LexKind.effect) break;
          tagList.add((s.payload as String?) ?? s.phrase);
        case MatchKind.title:
          title ??= s.phrase;
      }
    }
    // "clean", "crunch", "ambient" are variants AND genres of the taxonomy: a role word
    // only acts as a genre when nothing else identified the request
    if (artist == null && song == null && album == null && title == null && genre == null && era == null && tagList.isEmpty && role != null) {
      final phrase = spans.firstWhere((s) => s.kind == MatchKind.role).phrase;
      final g = index.taxonomy.genresForPhrase(phrase);
      if (g.isNotEmpty) genre = g.first;
    }
    return ToneInterpretation(
      query: ToneQuery(
        rawText: text,
        artist: artist,
        song: song,
        album: album,
        genre: genre,
        era: era,
        role: role,
        tuning: tuning,
        modifiers: modifiers,
        tags: tagList,
        title: title,
      ),
      spans: spans,
      tokens: current,
      unmatched: unmatched,
      fuzzy: fuzzy,
      corrections: corrections,
    );
  }

  Set<int> _unmatchedIndexes(int length, List<ToneSpan> spans) {
    final covered = {for (final s in spans) for (var k = s.start; k < s.end; k++) k};
    return {for (var k = 0; k < length; k++) if (!covered.contains(k)) k};
  }

  // ------------------------------------------------------------------ resolution

  ToneVaultResolution resolve(String text) => resolveInterpretation(interpret(text));

  /// Resolves an already interpreted request ([query] may replace the interpreter's
  /// query, e.g. with the modifiers/effects the Mini-NLU composed). No second parse.
  ToneVaultResolution resolveInterpretation(ToneInterpretation r, {ToneQuery? query}) =>
      _resolve(query ?? r.query, r.spans, r.unmatched, r.fuzzy);

  /// For a structured query (e.g. from a future text parser).
  ToneVaultResolution resolveQuery(ToneQuery query) {
    final spans = <ToneSpan>[];
    String norm(String? s) => ToneText.normalize(s ?? '');
    if (query.artist != null) spans.add(ToneSpan(MatchKind.artist, 0, 0, norm(query.artist)));
    if (query.song != null) spans.add(ToneSpan(MatchKind.song, 0, 0, norm(query.song)));
    if (query.album != null) spans.add(ToneSpan(MatchKind.album, 0, 0, norm(query.album)));
    if (query.title != null) spans.add(ToneSpan(MatchKind.title, 0, 0, norm(query.title)));
    return _resolve(query, spans, const [], false);
  }

  ToneVaultResolution _resolve(ToneQuery q, List<ToneSpan> spans, List<String> unmatched, bool fuzzyUsed) {
    if (!q.hasEntity) {
      return ToneVaultResolution(query: q, kind: ResolutionKind.none, candidates: const [], unmatched: unmatched, fuzzyUsed: fuzzyUsed);
    }
    final scores = <int, double>{};
    final reasons = <int, List<ToneMatchReason>>{};
    void add(int idx, ToneMatchReason r) {
      scores[idx] = (scores[idx] ?? 0) + r.weight;
      (reasons[idx] ??= []).add(r);
    }

    double f(double w, bool fuzzy) => fuzzy ? w * _fuzzFactor : w;
    bool spanFuzzy(MatchKind kind) => spans.any((s) => s.kind == kind && s.fuzzy);

    final artistKey = q.artist == null ? null : ToneText.normalize(q.artist!);
    bool artistMatches(ToneVaultEntry e) {
      if (artistKey == null) return true;
      if (e.artist == null) return false;
      return ToneText.normalize(e.artist!) == artistKey;
    }

    // song
    if (q.song != null) {
      final fz = spanFuzzy(MatchKind.song);
      for (final idx in index.songs.exact[q.song!] ?? const <int>[]) {
        final e = index.entries[idx];
        if (artistMatches(e)) add(idx, ToneMatchReason(MatchKind.song, q.song!, f(_wSong, fz), fuzzy: fz));
      }
      for (final idx in index.songs.alias[q.song!] ?? const <int>[]) {
        final e = index.entries[idx];
        if (artistMatches(e) && !(reasons[idx]?.any((r) => r.kind == MatchKind.song) ?? false)) {
          add(idx, ToneMatchReason(MatchKind.song, q.song!, f(_wSongAlias, fz), alias: true, fuzzy: fz));
        }
      }
    }
    // album
    if (q.album != null) {
      final fz = spanFuzzy(MatchKind.album);
      final all = [
        for (final i in index.albums.exact[q.album!] ?? const <int>[]) (i, false),
        for (final i in index.albums.alias[q.album!] ?? const <int>[]) (i, true),
      ];
      for (final (idx, alias) in all) {
        if (artistMatches(index.entries[idx])) {
          add(idx, ToneMatchReason(MatchKind.album, q.album!, f(alias ? _wAlbumAlias : _wAlbum, fz), alias: alias, fuzzy: fz));
        }
      }
    }
    // artist
    if (artistKey != null) {
      final fz = spanFuzzy(MatchKind.artist);
      final aliasHit = spans.any((s) => s.kind == MatchKind.artist && s.alias);
      for (final idx in index.artists.exact[artistKey] ?? const <int>[]) {
        add(idx, ToneMatchReason(MatchKind.artist, q.artist!, f(aliasHit ? _wArtistAlias : _wArtist, fz), alias: aliasHit, fuzzy: fz));
      }
    }
    // free title / alias phrase (only when no structured entity explains the phrase)
    for (final s in spans.where((s) => s.kind == MatchKind.title)) {
      final list = index.titles.exact[s.phrase] ?? index.titles.alias[s.phrase] ?? const <int>[];
      for (final idx in list) {
        add(idx, ToneMatchReason(MatchKind.title, s.phrase, f(s.alias ? _wTitleAlias : _wTitle, s.fuzzy), alias: s.alias, fuzzy: s.fuzzy));
      }
    }
    // genre (with all descendants), era, tags
    final entityScoped = q.artist != null || q.song != null || q.album != null;
    final genreId = q.subgenre ?? q.genre;
    if (genreId != null) {
      final ids = index.taxonomy.withDescendants(genreId);
      final fz = spanFuzzy(MatchKind.genre);
      final direct = <int, bool>{};
      for (final g in ids) {
        for (final idx in index.byGenre[g] ?? const <int>[]) {
          direct[idx] = (direct[idx] ?? false) || g == genreId;
        }
      }
      for (final entry in direct.entries) {
        final idx = entry.key;
        if (entityScoped && scores[idx] == null) continue; // entity + genre: genre only refines
        add(idx, ToneMatchReason(MatchKind.genre, genreId, f(entry.value ? _wGenre : _wGenre * 0.7, fz), fuzzy: fz));
        if (entry.value && index.entries[idx].type.isTemplate) add(idx, const ToneMatchReason(MatchKind.genre, 'template', 8));
        // the entry's PRIMARY genre is the asked genre (a shoegaze template beats an ambient template that lists shoegaze second)
        if (entry.value && index.entries[idx].genres.firstOrNull == genreId) add(idx, const ToneMatchReason(MatchKind.genre, 'primary', 4));
      }
    }
    if (q.era != null) {
      for (final idx in index.byEra[q.era!] ?? const <int>[]) {
        if (entityScoped && scores[idx] == null) continue;
        add(idx, ToneMatchReason(MatchKind.era, q.era!, _wEra));
      }
    }
    for (final t in q.tags) {
      for (final idx in index.tags.exact[t] ?? const <int>[]) {
        if (entityScoped && scores[idx] == null) continue;
        add(idx, ToneMatchReason(MatchKind.tag, t, _wTag));
      }
    }
    // an entity-less request that only names genre/era needs BOTH to match when both were given
    if (!entityScoped && genreId != null && q.era != null) {
      final both = {for (final idx in scores.keys) if ((reasons[idx] ?? []).any((r) => r.kind == MatchKind.genre) && (reasons[idx] ?? []).any((r) => r.kind == MatchKind.era)) idx};
      if (both.isNotEmpty) scores.removeWhere((idx, _) => !both.contains(idx));
    }

    // type preference: which kind of entry answers this kind of request best
    final artistOnly = q.artist != null && q.song == null && q.album == null;
    for (final idx in scores.keys.toList()) {
      final e = index.entries[idx];
      final bonus = artistOnly
          ? switch (e.type) {
              ToneEntryType.artistSignature => 6.0,
              ToneEntryType.eraSignature => 4.0,
              ToneEntryType.albumSignature => 3.0,
              _ => 0.0,
            }
          : (q.song == null && q.album == null)
          ? switch (e.type) {
              ToneEntryType.genreTemplate => 6.0,
              ToneEntryType.styleTemplate => 4.0,
              ToneEntryType.artistSignature => 1.0,
              _ => 0.0,
            }
          : 0.0;
      scores[idx] = scores[idx]! + bonus;
    }

    // variant support
    final candidates = <ToneCandidate>[];
    for (final idx in scores.keys) {
      final e = index.entries[idx];
      var supported = true;
      var s = scores[idx]!;
      if (q.role != null) {
        supported = e.variant(q.role!) != null || e.roles.contains(q.role);
        if (supported) {
          s += _wRole;
          (reasons[idx] ??= []).add(const ToneMatchReason(MatchKind.role, 'variant', _wRole));
        }
      }
      candidates.add(ToneCandidate(entry: e, score: s, reasons: List.unmodifiable(reasons[idx]!), variant: q.role, variantSupported: supported));
    }
    candidates.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : a.entry.id.compareTo(b.entry.id);
    });

    if (candidates.isEmpty) {
      return ToneVaultResolution(query: q, kind: ResolutionKind.none, candidates: const [], unmatched: unmatched, fuzzyUsed: fuzzyUsed);
    }
    // exact: a specific song/album requested and one entry clearly leads; or only one option exists
    final top = candidates.first;
    final second = candidates.length > 1 ? candidates[1] : null;
    final specific = q.song != null || q.album != null;
    final clear = second == null || top.score - second.score >= 8;
    // a single hit for a mere genre/era wish is offered, not silently decided (unless it is a template)
    final named = q.artist != null || q.song != null || q.album != null || q.title != null;
    final unique = candidates.length == 1 && (named || top.entry.type.isTemplate);
    final ResolutionKind kind;
    if (unique || (specific && clear)) {
      kind = ResolutionKind.exact;
    } else {
      kind = ResolutionKind.choose;
    }
    return ToneVaultResolution(
      query: q,
      kind: kind,
      candidates: List.unmodifiable(candidates),
      primary: kind == ResolutionKind.exact ? top : null,
      unmatched: unmatched,
      fuzzyUsed: fuzzyUsed || candidates.any((c) => c.fuzzy),
    );
  }

  /// Convenience for a "search as you type" UI: the resolution's candidates, at most [limit].
  List<ToneCandidate> search(String text, {int limit = 20}) {
    final r = resolve(text);
    return r.candidates.length <= limit ? r.candidates : r.candidates.sublist(0, limit);
  }

  /// Applies the request's modifiers (if any) to already resolved dimensions.
  static Map<ToneDimension, int> withModifiers(Map<ToneDimension, int> dims, ToneQuery q) =>
      applyToneModifiers(dims, q.modifiers).dimensions;
}
