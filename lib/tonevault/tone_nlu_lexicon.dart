/// The data-driven language layer of the Mini-NLU: intensity words, negations,
/// direction x parameter phrases, effect words, adjectives, tunings and the two
/// pragmatic text normalizations (raw rewrites, German compound splitting).
///
/// Everything comes from `assets/tonevault/nlu.json`; the parser code contains
/// structure, not words. An empty lexicon ([ToneNluLexicon.empty]) disables all
/// of it, which is how ToneVault V1 behaves.
library;

import 'dart:convert';

import 'tone_vault_model.dart' show JsonObjectReader, ToneVaultFormatException, toneVaultSchemaVersion;
import 'tone_vault_query.dart';
import 'tone_vault_text.dart';

enum LexKind { modifier, intensity, negation, effect, adjective, param }

class LexEntry {
  const LexEntry(this.kind, this.payload);
  final LexKind kind;

  /// modifier: wire names joined by ","; intensity: [ToneIntensity]; effect: [ToneEffectKind];
  /// adjective: [AdjectiveSpec]; param: [ParamSpec]; negation: null.
  final Object? payload;
}

class AdjectiveSpec {
  const AdjectiveSpec(this.modifiers, this.intensity);
  final List<ToneModifier> modifiers;
  final ToneIntensity intensity;
}

class ParamSpec {
  const ParamSpec(this.more, this.less);
  final ToneModifier? more, less;
}

/// A tuning the user may name. [guitarTuning] is the app's GuitarTuning enum name,
/// or null when the app has no such tuning (the request is reported, never faked).
class TuningSpec {
  const TuningSpec(this.id, this.label, this.guitarTuning);
  final String id, label;
  final String? guitarTuning;
}

class ToneNluLexicon {
  ToneNluLexicon._({
    required this.rawRewrites,
    required this.tokenRewrites,
    required this.compoundSuffixes,
    required this.stopwords,
    required this.phrases,
    required this.adjectives,
    required this.effectParams,
    required this.tunings,
    required this.tuningPhrases,
    required this.modifierTags,
    required this.words,
    required this.maxPhraseTokens,
  });

  static final ToneNluLexicon empty = ToneNluLexicon._(
    rawRewrites: const [],
    tokenRewrites: const {},
    compoundSuffixes: const [],
    stopwords: const {},
    phrases: const {},
    adjectives: const {},
    effectParams: const {},
    tunings: const {},
    tuningPhrases: const {},
    modifierTags: const {},
    words: const {},
    maxPhraseTokens: 1,
  );

  final List<(RegExp, String)> rawRewrites;
  final Map<String, String> tokenRewrites;
  final List<String> compoundSuffixes;
  final Set<String> stopwords;

  /// normalized phrase -> entry (priority on collisions: modifier, effect, adjective, param).
  final Map<String, LexEntry> phrases;

  /// normalized adjective phrase -> spec (also consulted for words the index knows as tags).
  final Map<String, AdjectiveSpec> adjectives;
  final Map<ToneEffectKind, ParamSpec> effectParams;
  final Map<String, TuningSpec> tunings;
  final Map<String, String> tuningPhrases;

  /// Ranking hints: a comparative wish ("more modern") also prefers entries with this style tag.
  final Map<ToneModifier, String> modifierTags;

  /// Every single word of the lexicon (typo-correction vocabulary, compound stems).
  final Set<String> words;
  final int maxPhraseTokens;

  bool get isEmpty => phrases.isEmpty && tuningPhrases.isEmpty && rawRewrites.isEmpty;

  /// Text -> tokens with the lexicon's normalizations. [isKnown] tells which words the
  /// index already knows (a compound is only split when its stem is a known word).
  List<String> tokens(String text, bool Function(String) isKnown) {
    var t = text.toLowerCase();
    for (final (pattern, replacement) in rawRewrites) {
      t = t.replaceAllMapped(pattern, (m) {
        var out = replacement;
        for (var g = 1; g <= m.groupCount; g++) {
          out = out.replaceAll('\\$g', m.group(g) ?? '');
        }
        return out;
      });
    }
    final out = <String>[];
    for (final token in ToneText.tokens(t)) {
      final rewritten = tokenRewrites[token];
      if (rewritten != null) {
        out.add(rewritten);
        continue;
      }
      var split = false;
      if (!isKnown(token) && !words.contains(token)) {
        for (final suffix in compoundSuffixes) {
          if (token.length >= suffix.length + 3 && token.endsWith(suffix)) {
            final stem = token.substring(0, token.length - suffix.length);
            if (isKnown(stem) || words.contains(stem)) {
              out
                ..add(stem)
                ..add(suffix);
              split = true;
              break;
            }
          }
        }
      }
      if (!split) out.add(token);
    }
    return out;
  }

  static ToneNluLexicon parse(String text) {
    final r = JsonObjectReader(jsonDecode(text), 'nlu');
    if (r.intValue('schemaVersion') != toneVaultSchemaVersion) {
      throw const ToneVaultFormatException('nlu.schemaVersion', 'Unbekannte NLU-Version.');
    }
    Map<String, Object?> obj(String key) {
      final v = r.raw(key);
      if (v is! Map) throw ToneVaultFormatException('nlu.$key', 'Objekt erwartet.');
      return v.cast<String, Object?>();
    }

    List<String> list(Object? v, String path) {
      if (v is! List || v.any((e) => e is! String)) throw ToneVaultFormatException(path, 'Liste von Texten erwartet.');
      return v.cast<String>();
    }

    String norm(String s) => ToneText.normalize(s);
    ToneModifier modifier(String wire, String path) =>
        ToneModifier.tryParse(wire) ?? (throw ToneVaultFormatException(path, 'Unbekannter Modifier $wire.'));

    final rawRewrites = <(RegExp, String)>[];
    for (final item in r.list('rawRewrites')) {
      final pair = list(item, 'nlu.rawRewrites');
      if (pair.length != 2) throw const ToneVaultFormatException('nlu.rawRewrites', 'Paare [Muster, Ersatz] erwartet.');
      rawRewrites.add((RegExp(pair[0]), pair[1]));
    }
    final tokenRewrites = {for (final e in obj('tokenRewrites').entries) norm(e.key): norm('${e.value}')};
    final suffixes = [for (final s in r.strings('compoundSuffixes')) norm(s)]..sort((a, b) => b.length.compareTo(a.length));
    final stop = {for (final w in r.strings('stopwords')) norm(w)};

    final phrases = <String, LexEntry>{};
    void put(String phrase, LexEntry entry) {
      final key = norm(phrase);
      if (key.isNotEmpty) phrases.putIfAbsent(key, () => entry);
    }

    // 1. explicit modifier phrases
    for (final e in obj('modifierPhrases').entries) {
      modifier(e.key, 'nlu.modifierPhrases.${e.key}');
      for (final p in list(e.value, 'nlu.modifierPhrases.${e.key}')) {
        put(p, LexEntry(LexKind.modifier, e.key));
      }
    }
    // 2. direction x parameter (and effect) words
    final directions = obj('directions');
    final more = list(directions['more'], 'nlu.directions.more');
    final less = list(directions['less'], 'nlu.directions.less');
    final params = <String, ParamSpec>{};
    final paramWords = <String, List<String>>{};
    for (final e in obj('params').entries) {
      final p = JsonObjectReader(e.value, 'nlu.params.${e.key}');
      final spec = ParamSpec(
        p.optString('more') == null ? null : modifier(p.optString('more')!, 'nlu.params.${e.key}.more'),
        p.optString('less') == null ? null : modifier(p.optString('less')!, 'nlu.params.${e.key}.less'),
      );
      params[e.key] = spec;
      paramWords[e.key] = p.strings('words');
      p.done();
    }
    void directionPhrases(Iterable<String> words, ParamSpec spec) {
      for (final w in words) {
        if (spec.more != null) {
          for (final d in more) {
            put('$d $w', LexEntry(LexKind.modifier, spec.more!.wire));
          }
        }
        if (spec.less != null) {
          for (final d in less) {
            put('$d $w', LexEntry(LexKind.modifier, spec.less!.wire));
          }
        }
      }
    }

    for (final e in params.entries) {
      directionPhrases(paramWords[e.key]!, e.value);
    }
    // 3. effects (a bare effect word is an effect; "more <effect>" strengthens its parameter)
    final effectParams = <ToneEffectKind, ParamSpec>{};
    for (final e in obj('effects').entries) {
      final kind = ToneEffectKind.tryParse(e.key) ?? (throw ToneVaultFormatException('nlu.effects.${e.key}', 'Unbekannter Effekt.'));
      final p = JsonObjectReader(e.value, 'nlu.effects.${e.key}');
      final paramName = p.optString('param');
      final words = p.strings('words');
      p.done();
      if (paramName != null) {
        final spec = params[paramName] ?? (throw ToneVaultFormatException('nlu.effects.${e.key}.param', 'Unbekannter Parameter $paramName.'));
        effectParams[kind] = spec;
        directionPhrases(words, spec);
      }
      for (final w in words) {
        put(w, LexEntry(LexKind.effect, kind));
      }
    }
    // 4. adjectives
    final adjectives = <String, AdjectiveSpec>{};
    for (final e in obj('adjectives').entries) {
      final p = JsonObjectReader(e.value, 'nlu.adjectives.${e.key}');
      final mods = [for (final m in p.strings('modifiers')) modifier(m, 'nlu.adjectives.${e.key}')];
      final inten = ToneIntensity.tryParse(p.string('intensity')) ?? (throw ToneVaultFormatException('nlu.adjectives.${e.key}', 'Unbekannte Intensität.'));
      p.done();
      final key = norm(e.key);
      adjectives.putIfAbsent(key, () => AdjectiveSpec(mods, inten));
      put(key, LexEntry(LexKind.adjective, adjectives[key]));
    }
    // 5. bare parameter words ("lots of bass")
    for (final e in params.entries) {
      for (final w in paramWords[e.key]!) {
        put(w, LexEntry(LexKind.param, e.value));
      }
    }
    // 6. intensity and negation
    final intensity = obj('intensity');
    for (final e in intensity.entries) {
      final level = ToneIntensity.tryParse(e.key) ?? (throw ToneVaultFormatException('nlu.intensity.${e.key}', 'Unbekannte Intensität.'));
      for (final w in list(e.value, 'nlu.intensity.${e.key}')) {
        phrases[norm(w)] = LexEntry(LexKind.intensity, level);
      }
    }
    for (final w in r.strings('negation')) {
      phrases[norm(w)] = const LexEntry(LexKind.negation, null);
    }
    // 7. tunings
    final tunings = <String, TuningSpec>{};
    final tuningPhrases = <String, String>{};
    for (final e in obj('tunings').entries) {
      final p = JsonObjectReader(e.value, 'nlu.tunings.${e.key}');
      final spec = TuningSpec(e.key, p.string('label'), p.optString('guitarTuning'));
      tunings[e.key] = spec;
      for (final phrase in p.strings('phrases')) {
        tuningPhrases[norm(phrase)] = e.key;
      }
      p.done();
    }
    final modifierTags = <ToneModifier, String>{};
    for (final e in obj('modifierTags').entries) {
      modifierTags[modifier(e.key, 'nlu.modifierTags.${e.key}')] = norm('${e.value}');
    }
    r.done();

    final words = <String>{};
    var maxTokens = 1;
    for (final key in [...phrases.keys, ...tuningPhrases.keys, ...stop]) {
      final parts = key.split(' ');
      words.addAll(parts);
      if (parts.length > maxTokens) maxTokens = parts.length;
    }
    return ToneNluLexicon._(
      rawRewrites: List.unmodifiable(rawRewrites),
      tokenRewrites: Map.unmodifiable(tokenRewrites),
      compoundSuffixes: List.unmodifiable(suffixes),
      stopwords: Set.unmodifiable(stop),
      phrases: Map.unmodifiable(phrases),
      adjectives: Map.unmodifiable(adjectives),
      effectParams: Map.unmodifiable(effectParams),
      tunings: Map.unmodifiable(tunings),
      tuningPhrases: Map.unmodifiable(tuningPhrases),
      modifierTags: Map.unmodifiable(modifierTags),
      words: Set.unmodifiable(words),
      maxPhraseTokens: maxTokens,
    );
  }
}
