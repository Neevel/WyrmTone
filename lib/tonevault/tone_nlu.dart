/// Mini-NLU V1: a small, domain-specific, fully offline, deterministic reader of
/// German/English guitar-sound requests. It is NOT a chatbot and generates no text.
///
/// raw text -> [ToneVaultResolver.interpret] (normalization, entities via the
/// ToneVault index itself, exact > alias > fuzzy) -> composition of intensity,
/// negation, modifier, adjective and effect words (all from the lexicon data) ->
/// a fully populated [ToneQuery] -> ONE resolver pass -> [ToneNluResult].
///
/// It never produces device data. Turning the result into a sound is the job of
/// `ToneVault.definitionFor` + the existing recipe pipeline.
library;

import 'tone_nlu_lexicon.dart';
import 'tone_vault_index.dart' show PhraseDict;
import 'tone_vault_model.dart';
import 'tone_vault_query.dart';
import 'tone_vault_search.dart';
import 'tone_vault_text.dart';
import 'tone_vault.dart';

class ToneNluResult {
  const ToneNluResult({required this.query, required this.resolution, required this.tuning});

  /// Everything that was understood (never null, may be empty).
  final ToneQuery query;

  /// Base tone candidates; several -> the user (or UI) must choose.
  final ToneVaultResolution resolution;

  /// The requested tuning, if any (the app may not support it: see [TuningSpec.guitarTuning]).
  final TuningSpec? tuning;

  String get rawText => query.rawText;
  List<NluMatch> get matches => query.matchReasons;
  bool get needsChoice => resolution.requiresChoice;
  bool get understood => resolution.kind != ResolutionKind.none || query.modifierIntents.isNotEmpty || query.effects.isNotEmpty;

  /// The unambiguous base entry, if the request has one.
  String? get baseEntryId => resolution.primary?.entry.id;

  /// Structured, prose-free explanation lines ("artist: NAME [fuzzy 0.94]").
  List<String> get explanation => [
    for (final m in matches) '${m.kind}: ${m.value} [${m.method}${m.method == 'exact' || m.method == 'lexicon' ? '' : ' ${m.score.toStringAsFixed(2)}'}]',
    if (baseEntryId != null) 'base: $baseEntryId',
  ];
}

class ToneNlu implements ToneQueryParser {
  ToneNlu(this.vault);
  final ToneVault vault;

  @override
  ToneQuery parse(String text) => understand(text).query;

  static const _opposites = <ToneModifier, ToneModifier>{
    ToneModifier.moreGain: ToneModifier.lessGain,
    ToneModifier.moreMids: ToneModifier.lessMids,
    ToneModifier.moreBass: ToneModifier.lessBass,
    ToneModifier.brighter: ToneModifier.darker,
    ToneModifier.tighter: ToneModifier.looser,
    ToneModifier.moreReverb: ToneModifier.lessReverb,
    ToneModifier.moreDelay: ToneModifier.lessDelay,
    ToneModifier.moreAggressive: ToneModifier.lessAggressive,
    ToneModifier.moreVintage: ToneModifier.moreModern,
    ToneModifier.moreClarity: ToneModifier.lessClarity,
    ToneModifier.moreBody: ToneModifier.lessBody,
    ToneModifier.moreTreble: ToneModifier.lessTreble,
    ToneModifier.morePresence: ToneModifier.lessPresence,
    ToneModifier.moreCompression: ToneModifier.lessCompression,
    ToneModifier.moreModulation: ToneModifier.lessModulation,
    ToneModifier.moreAmbient: ToneModifier.lessAmbient,
    ToneModifier.dirtier: ToneModifier.cleaner,
    ToneModifier.warmer: ToneModifier.colder,
    ToneModifier.drier: ToneModifier.wetter,
  };
  static final _opposite = {
    for (final e in _opposites.entries) ...{e.key: e.value, e.value: e.key},
  };

  ToneNluResult understand(String text) {
    final resolver = vault.resolver;
    final index = vault.index;
    final lex = index.lexicon;
    final interp = resolver.interpret(text);
    final tokens = interp.tokens;

    // words the user typed, for explanations
    String typed(ToneSpan s) => [
      for (var k = s.start; k < s.end; k++) interp.corrections[k] ?? tokens[k],
    ].join(' ');
    bool adjacent(int end, int start) {
      for (var k = end; k < start; k++) {
        if (!index.stopwords.contains(tokens[k])) return false;
      }
      return true;
    }

    final intents = <ToneModifierIntent>[];
    final effects = <ToneEffectIntent>[];
    final styleTerms = <String>[];
    final matches = <NluMatch>[];
    String? canonicalSong, canonicalAlbum;
    final effectTags = <String>{}; // words that are tags in the index but were meant as effects ("with chorus")
    ToneSpan? pendingIntensity, pendingNegation;
    ToneIntensity pendingLevel = ToneIntensity.normal;
    var pendingEnd = 0;

    void addIntent(ToneModifier m, ToneIntensity level, String phrase) {
      final opposite = _opposite[m];
      intents.removeWhere((i) => i.modifier == m || i.modifier == opposite);
      intents.add(ToneModifierIntent(m, level, phrase: phrase));
    }

    void addEffect(ToneEffectKind kind, bool off, String phrase) {
      effects.removeWhere((e) => e.kind == kind);
      effects.add(ToneEffectIntent(kind, off: off, phrase: phrase));
    }

    // "with chorus" = present, "without reverb" = OFF, "lots of delay" = present AND stronger
    void effectIntent(ToneEffectKind kind, bool negated, ToneIntensity? intensity, String phrase) {
      addEffect(kind, negated, phrase);
      final more = lex.effectParams[kind]?.more;
      if (!negated && intensity != null && more != null) addIntent(more, intensity, phrase);
    }

    NluMatch match(ToneSpan s, String kind, String value, {String? method}) {
      var score = 1.0;
      final m = method ?? (s.fuzzy ? 'fuzzy' : (s.alias ? 'alias' : 'exact'));
      if (s.fuzzy) {
        var best = 1.0;
        for (var k = s.start; k < s.end; k++) {
          final original = interp.corrections[k];
          if (original == null) continue;
          final len = original.length > tokens[k].length ? original.length : tokens[k].length;
          final sim = 1 - ToneText.distance(original, tokens[k], len) / len;
          if (sim < best) best = sim;
        }
        score = double.parse(best.toStringAsFixed(2));
      } else if (s.alias) {
        score = 0.95;
      }
      return NluMatch(kind, typed(s), value, m, score);
    }

    String entryOf(PhraseDict d, ToneSpan s, String Function(ToneVaultEntry) pick) {
      final list = (s.alias ? d.alias : d.exact)[s.phrase] ?? d.exact[s.phrase] ?? d.alias[s.phrase];
      return list == null || list.isEmpty ? s.phrase : pick(index.entries[list.first]);
    }

    for (final s in interp.spans) {
      switch (s.kind) {
        case MatchKind.intensity:
          final level = s.payload as ToneIntensity;
          if (pendingIntensity != null && adjacent(pendingEnd, s.start)) {
            pendingLevel = pendingLevel.max(level);
          } else {
            pendingLevel = level;
          }
          pendingIntensity = s;
          pendingEnd = s.end;
          matches.add(match(s, 'intensity', level.wire, method: 'lexicon'));
          continue;
        case MatchKind.negation:
          pendingNegation = s;
          pendingEnd = s.end;
          matches.add(match(s, 'negation', 'NOT', method: 'lexicon'));
          continue;
        default:
      }
      final intensity = pendingIntensity != null && adjacent(pendingEnd, s.start) ? pendingLevel : null;
      final negated = pendingNegation != null && adjacent(pendingEnd, s.start);
      pendingIntensity = pendingNegation = null;
      final phrase = typed(s);
      switch (s.kind) {
        case MatchKind.modifier:
          final wires = (s.payload as String).split(',');
          for (final wire in wires) {
            final m = ToneModifier.tryParse(wire);
            if (m != null) addIntent(m, intensity ?? ToneIntensity.normal, phrase);
          }
          matches.add(match(s, 'modifier', '${wires.join('+')}/${(intensity ?? ToneIntensity.normal).wire}', method: 'lexicon'));
        case MatchKind.adjective:
          final spec = s.payload as AdjectiveSpec;
          final level = intensity ?? spec.intensity;
          for (final m in spec.modifiers) {
            addIntent(m, level, phrase);
          }
          matches.add(match(s, 'modifier', '${spec.modifiers.map((m) => m.wire).join('+')}/${level.wire}', method: 'lexicon'));
        case MatchKind.tag:
          // the index knows the word as a tag; the lexicon may know it as an effect ("chorus")
          if (lex.phrases[s.phrase] case final LexEntry effect when effect.kind == LexKind.effect) {
            final kind = effect.payload as ToneEffectKind;
            effectTags.add((s.payload as String?) ?? s.phrase);
            effectIntent(kind, negated, intensity, phrase);
            matches.add(match(s, 'effect', '${negated ? 'OFF ' : ''}${kind.name}', method: 'lexicon'));
            break;
          }
          styleTerms.add((s.payload as String?) ?? s.phrase);
          matches.add(match(s, 'style', (s.payload as String?) ?? s.phrase));
          final spec = lex.adjectives[s.phrase];
          if (spec != null) {
            final level = intensity ?? spec.intensity;
            for (final m in spec.modifiers) {
              addIntent(m, level, phrase);
            }
          }
        case MatchKind.effect:
          final kind = s.payload as ToneEffectKind;
          effectIntent(kind, negated, intensity, phrase);
          matches.add(match(s, 'effect', '${negated ? 'OFF ' : ''}${kind.name}', method: 'lexicon'));
        case MatchKind.param:
          final spec = s.payload as ParamSpec;
          final wanted = negated ? spec.less : (intensity != null ? spec.more : null);
          if (wanted != null) {
            addIntent(wanted, negated ? ToneIntensity.strong : intensity!, phrase);
            matches.add(match(s, 'modifier', '${wanted.wire}/${(negated ? ToneIntensity.strong : intensity!).wire}', method: 'lexicon'));
          }
        case MatchKind.artist:
          matches.add(match(s, 'artist', entryOf(index.artists, s, (e) => e.artist ?? s.phrase)));
        case MatchKind.song:
          final title = entryOf(index.songs, s, (e) => e.song ?? s.phrase);
          canonicalSong ??= ToneText.normalize(title);
          matches.add(match(s, 'song', title));
        case MatchKind.album:
          final title = entryOf(index.albums, s, (e) => e.album ?? s.phrase);
          canonicalAlbum ??= ToneText.normalize(title);
          matches.add(match(s, 'album', title));
        case MatchKind.title:
          matches.add(match(s, 'title', entryOf(index.titles, s, (e) => e.title)));
        case MatchKind.genre:
          matches.add(match(s, 'genre', (s.payload as Set<String>).first));
        case MatchKind.era:
          matches.add(match(s, 'era', s.payload as String));
        case MatchKind.role:
          matches.add(match(s, 'role', (s.payload as ToneVariantKind).wire));
        case MatchKind.tuning:
          matches.add(match(s, 'tuning', s.payload as String));
        case MatchKind.intensity || MatchKind.negation:
          break;
      }
    }

    // genre -> group + specific genre
    final q0 = interp.query;
    String? genre = q0.genre, subgenre;
    if (genre != null && vault.taxonomy.genres[genre]?.parent != null) {
      subgenre = genre;
      genre = vault.taxonomy.groupOf(genre);
    }
    // "Clean-Sound", "Ambient Clean": a role word the taxonomy also knows as a genre is the
    // requested role too (the last one is the head of the phrase)
    var role = q0.role;
    if (role == null) {
      for (final s in interp.spans) {
        if (s.kind != MatchKind.genre) continue;
        final id = (s.payload as Set<String>).first;
        role = index.vocabulary.roleWords[s.phrase] ??
            ToneVariantKind.values.where((k) => k.wire.toLowerCase() == id).firstOrNull ??
            role;
      }
    }
    // ranking hints of comparative wishes; they never make a request an entity request on their own
    final hasEntity = q0.artist != null || q0.song != null || q0.album != null || q0.title != null || genre != null || q0.era != null;
    final rankingTags = <String>[
      if (hasEntity)
        for (final i in intents)
          if (lex.modifierTags[i.modifier] case final tag? when index.tags.exact.containsKey(tag) && !q0.tags.contains(tag)) tag,
    ];
    final tuningSpec = q0.tuning == null ? null : (lex.tunings[q0.tuning] ?? _builtInTuning(q0.tuning!));
    final composed = ToneQuery(
      rawText: q0.rawText,
      artist: q0.artist,
      song: canonicalSong ?? q0.song,
      album: canonicalAlbum ?? q0.album,
      genre: genre,
      subgenre: subgenre,
      era: q0.era,
      role: role,
      tuning: q0.tuning,
      tags: [
        for (final t in q0.tags)
          if (!effectTags.contains(t)) t,
        ...rankingTags,
      ],
      title: q0.title,
      normalizedText: tokens.join(' '),
      modifiers: [for (final i in intents) i.modifier],
      modifierIntents: List.unmodifiable(intents),
      effects: List.unmodifiable(effects),
      styleTerms: List.unmodifiable(styleTerms),
      unresolvedTokens: List.unmodifiable(interp.unmatched),
      matchReasons: List.unmodifiable(matches),
    );
    final resolution = resolver.resolveInterpretation(interp, query: composed);
    final scored = composed.copyWith(confidence: _confidence(composed, resolution, matches));
    return ToneNluResult(
      query: scored,
      resolution: ToneVaultResolution(
        query: scored,
        kind: resolution.kind,
        candidates: resolution.candidates,
        primary: resolution.primary,
        unmatched: resolution.unmatched,
        fuzzyUsed: resolution.fuzzyUsed,
      ),
      tuning: tuningSpec,
    );
  }

  TuningSpec? _builtInTuning(String id) {
    // V1 tunings the app knows even without lexicon data
    const labels = {
      'eStandard': 'E Standard',
      'ebStandard': 'Eb Standard',
      'dStandard': 'D Standard',
      'dropD': 'Drop D',
      'dropC': 'Drop C',
      'dropB': 'Drop B',
    };
    final label = labels[id];
    return label == null ? null : TuningSpec(id, label, id);
  }

  /// 0..1 how much of the request was understood. Deterministic and explainable:
  /// entity strength x match quality, small bonus per further facet, penalty per
  /// unknown content word, discount for a real choice.
  double _confidence(ToneQuery q, ToneVaultResolution r, List<NluMatch> matches) {
    if (r.kind == ResolutionKind.none) {
      // no base tone, but wishes that can refine any tone ("a bit darker")
      return q.modifierIntents.isNotEmpty || q.effects.isNotEmpty ? 0.3 : 0;
    }
    var base = q.song != null
        ? 0.95
        : (q.album != null || q.title != null)
        ? 0.85
        : q.artist != null
        ? 0.75
        : 0.6;
    final entityKinds = {'song', 'album', 'title', 'artist', 'genre', 'era', 'style'};
    var quality = 1.0;
    for (final m in matches) {
      if (entityKinds.contains(m.kind) && m.score < quality) quality = m.score;
    }
    base *= quality;
    final facets = [q.role != null, q.tuning != null, q.modifierIntents.isNotEmpty, q.effects.isNotEmpty].where((b) => b).length;
    base += 0.03 * facets;
    base -= 0.04 * (q.unresolvedTokens.length > 5 ? 5 : q.unresolvedTokens.length);
    if (r.requiresChoice) base *= 0.85;
    return double.parse(base.clamp(0.0, 1.0).toStringAsFixed(2));
  }
}
