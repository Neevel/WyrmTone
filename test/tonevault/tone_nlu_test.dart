import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/models/tone_target.dart';
import 'package:wyrmtone/presets/canonical_tone_recipe.dart';
import 'package:wyrmtone/presets/tone_intent.dart' show RecipeBlockState, ToneBlockRole;
import 'package:wyrmtone/tonevault/tone_definition.dart';
import 'package:wyrmtone/presets/tone_recipe_builder.dart';
import 'package:wyrmtone/tonevault/tone_nlu.dart';
import 'package:wyrmtone/tonevault/tone_nlu_lexicon.dart';
import 'package:wyrmtone/tonevault/tone_vault.dart';
import 'package:wyrmtone/tonevault/tone_vault_query.dart';
import 'package:wyrmtone/tonevault/tone_vault_search.dart';

String read(String p) => File(p).readAsStringSync();

ToneVault loadVault({bool nlu = true}) {
  final manifest = JsonManifest.parse(read('assets/tonevault/manifest.json'));
  return ToneVault.fromTexts(
    taxonomy: read('assets/tonevault/taxonomy.json'),
    vocabulary: read('assets/tonevault/vocabulary.json'),
    packs: [for (final p in manifest.packs) read('assets/tonevault/$p')],
    nlu: nlu ? read('assets/tonevault/${manifest.nlu}') : null,
  );
}

const testGuitar = GuitarProfile(
  id: 'g',
  name: 'Test',
  guitarType: GuitarType.superstrat,
  pickupType: PickupType.activeHumbucker,
  outputLevel: OutputLevel.high,
  toneCharacter: ToneCharacter.bright,
  tuning: GuitarTuning.dropC,
  playbackPath: PlaybackPath.headphones,
);

CanonicalToneRecipe recipeOf(ToneDefinition def) => ToneRecipeBuilder.build(
  profile: def.toTargetSound(),
  guitar: testGuitar,
  tuning: GuitarTuning.dropC,
  role: def.role,
);

/// Compact, comparable view of a parse.
List<String> mods(ToneQuery q) => [for (final i in q.modifierIntents) '${i.modifier.wire}/${i.intensity.wire}'];
List<String> fx(ToneQuery q) => [for (final e in q.effects) '${e.off ? 'OFF' : 'ON'} ${e.kind.name}'];

void main() {
  late ToneVault vault;
  setUpAll(() => vault = loadVault());
  ToneNluResult parse(String q) => vault.nlu.understand(q);

  group('Vokabular', () {
    test('lädt datengetrieben und lehnt Fehler ab', () {
      final lex = ToneNluLexicon.parse(read('assets/tonevault/nlu.json'));
      expect(lex.phrases.length, greaterThan(500));
      expect(lex.adjectives.length, greaterThan(100));
      expect(lex.tunings.keys, containsAll(['dropC', 'dropCSharp', 'dropA', 'cSharpStandard']));
      expect(() => ToneNluLexicon.parse('{"schemaVersion":1}'), throwsA(anything));
      final broken = jsonDecode(read('assets/tonevault/nlu.json')) as Map<String, Object?>;
      (broken['modifierPhrases'] as Map)['NOT_A_MODIFIER'] = ['xyz'];
      expect(() => ToneNluLexicon.parse(jsonEncode(broken)), throwsA(anything));
    });

    test('ohne Lexikon verhält sich ToneVault wie V1', () {
      final v1 = loadVault(nlu: false);
      expect(v1.entries.length, vault.entries.length);
      expect(v1.resolve('Metallica Master of Puppets Rhythm').primary?.entry.id, 'song.metallica.master_of_puppets');
      expect(v1.index.lexicon.isEmpty, isTrue);
    });
  });

  group('Normalisierung', () {
    test('Deutsch: Komposita, Bindestriche, Zeitangaben', () {
      expect(parse('Metalsound Rhythmussound Drop-C-Sound').query.tuning, 'dropC');
      expect(parse('Metalsound Rhythmussound Drop-C-Sound').query.role?.wire, 'RHYTHM');
      expect(parse('Gitarrensound Metal').query.genre, 'metal');
      expect(parse('80er-Metal').query.era, '1980s');
      expect(parse('Lead-Sound Metal').query.role?.wire, 'LEAD');
      expect(parse('Clean-Sound').query.role?.wire, 'CLEAN');
    });

    test('Englisch und Notation der Stimmung', () {
      expect(parse('drop c# metal').query.tuning, 'dropCSharp');
      expect(parse('Metal drop c sharp').query.tuning, 'dropCSharp');
      expect(parse('c# standard blues').query.tuning, 'cSharpStandard');
      expect(parse('blues cis standard').query.tuning, 'cSharpStandard');
      expect(parse('metal dropc').query.tuning, 'dropC');
      expect(parse('METAL   DROP-C!!').query.normalizedText, contains('drop c'));
    });
  });

  group('Entities', () {
    test('Artist, Song, Album exakt, Alias und Fuzzy', () {
      final r = parse('metallika master of pupets');
      expect(r.query.artist, 'Metallica');
      expect(r.query.song, 'master of puppets');
      expect(r.baseEntryId, 'song.metallica.master_of_puppets');
      expect(r.matches.where((m) => m.method == 'fuzzy'), isNotEmpty);
      expect(parse('BFMV').query.artist, 'Bullet for My Valentine');
      expect(parse('BFMV').matches.first.method, 'alias');
      expect(parse('nirvanna in utero').query.album, 'in utero');
      expect(parse('Master of Puppets').matches.every((m) => m.method != 'fuzzy'), isTrue);
    });

    test('Artist + Song rankt vor losen Wörtern', () {
      final r = parse('Metallica Master of Puppets');
      expect(r.resolution.candidates.first.entry.id, 'song.metallica.master_of_puppets');
      final artistOnly = r.resolution.candidates.firstWhere((c) => c.entry.id == 'artist.metallica');
      expect(r.resolution.candidates.first.score, greaterThan(artistOnly.score));
    });

    test('Fuzzy verschluckt keine Modifier-Wörter', () {
      final r = parse('metallika master of pupets rhythm drop c weniger gain');
      expect(mods(r.query), ['LESS_GAIN/NORMAL']);
      expect(r.query.role?.wire, 'RHYTHM');
      expect(r.query.tuning, 'dropC');
    });

    test('Genre statt Artist, Ära beeinflusst nur die Kandidaten', () {
      final r = parse('80er Hard Rock Lead mit viel Delay');
      expect(r.query.genre, 'rock');
      expect(r.query.subgenre, 'hard_rock');
      expect(r.query.era, '1980s');
      expect(r.query.artist, isNull);
      expect(r.resolution.candidates, isNotEmpty);
    });
  });

  group('Modifier, Intensität, Negation', () {
    test('Intensität', () {
      expect(mods(parse('Master of Puppets etwas weniger Gain').query), ['LESS_GAIN/SLIGHT']);
      expect(mods(parse('Master of Puppets weniger Gain').query), ['LESS_GAIN/NORMAL']);
      expect(mods(parse('Master of Puppets viel weniger Gain').query), ['LESS_GAIN/STRONG']);
      expect(mods(parse('richtig viel Reverb').query), ['MORE_REVERB/STRONG']);
      expect(mods(parse('ein bisschen dunkler').query), ['DARKER/SLIGHT']);
      expect(mods(parse('a little brighter').query), ['BRIGHTER/SLIGHT']);
    });

    test('Widersprüche: der spätere Wunsch gewinnt, Wiederholung bleibt eine Absicht', () {
      expect(mods(parse('mehr Gain weniger Gain').query), ['LESS_GAIN/NORMAL']);
      expect(mods(parse('mehr Gain mehr Gain').query), ['MORE_GAIN/NORMAL']);
    });

    test('Negation ist kein LESS_*: explizit AUS', () {
      final r = parse('Clean mit Chorus aber ohne Reverb');
      expect(fx(r.query), ['ON chorus', 'OFF reverb']);
      expect(r.query.modifierIntents, isEmpty);
      expect(fx(parse('no reverb metalcore rhythm').query), ['OFF reverb']);
      expect(fx(parse('kein Gate').query), ['OFF gate']);
      expect(fx(parse('without modulation').query).isEmpty, isTrue, reason: 'Modulation allein ist kein Effekt-Wort');
    });

    test('Effekte: gewünscht, ohne Intensität kein Modifier', () {
      final r = parse('Cyberpunk Lead mit Delay');
      expect(fx(r.query), ['ON delay']);
      expect(r.query.modifierIntents, isEmpty);
      expect(mods(parse('Metal mit viel Delay').query), ['MORE_DELAY/STRONG']);
    });
  });

  group('Mehrdeutigkeit und Unbekanntes', () {
    test('Artist sicher, mehrere Kandidaten', () {
      final r = parse('Metallica');
      expect(r.query.artist, 'Metallica');
      expect(r.needsChoice, isTrue);
      expect(r.baseEntryId, isNull);
      expect(r.resolution.candidates.length, greaterThan(1));
      expect(parse('metal').query.artist, isNull);
      expect(parse('metal').query.genre, 'metal');
    });

    test('Unbekannte Wörter: kein Absturz, sinnvolle Restwörter, Stoppwörter nicht', () {
      final r = parse('mach mir einen ultra bösen galaktischen Metallica Sound');
      expect(r.query.artist, 'Metallica');
      expect(r.query.unresolvedTokens, ['galaktischen']);
      expect(mods(r.query), ['MORE_AGGRESSIVE/STRONG', 'MORE_GAIN/STRONG']);
      for (final q in ['', '   ', '!!!', 'ä ö ü', '1234567890', 'a' * 500]) {
        expect(() => parse(q), returnsNormally, reason: q);
      }
      expect(parse('').resolution.kind, ResolutionKind.none);
      expect(parse('').query.confidence, 0);
    });

    test('Confidence: sicherer Song > Artist > nichts', () {
      final song = parse('Metallica Master of Puppets').query.confidence;
      final artist = parse('Metallica').query.confidence;
      expect(song, greaterThan(artist));
      expect(artist, greaterThan(0));
      expect(parse('xqzvbnm').query.confidence, 0);
      expect(song, lessThanOrEqualTo(1));
    });

    test('Erklärbarkeit: strukturierte MatchReasons', () {
      final r = parse('Metallica Master of Puppets Rhythmus Drop C etwas weniger Gain');
      expect(r.explanation, containsAll(['artist: Metallica [exact]', 'song: Master of Puppets [exact]', 'role: RHYTHM [exact]', 'tuning: dropC [exact]', 'base: song.metallica.master_of_puppets']));
      expect(r.matches.map((m) => m.kind), containsAll(['artist', 'song', 'role', 'tuning', 'intensity', 'modifier']));
      expect(r.tuning?.guitarTuning, 'dropC');
      expect(parse('Metal Drop C#').tuning?.guitarTuning, 'dropCSharp');
      expect(parse('Blues C Standard').tuning?.guitarTuning, isNull, reason: 'C Standard kennt die App nicht: nichts erfinden');
    });
  });

  group('Deterministische Korrekturen', () {
    test('Nutzerwunsch gewinnt, begrenzt, geklemmt', () {
      final base = vault.definition('song.metallica.master_of_puppets');
      final q = parse('Master of Puppets weniger Gain').query;
      final less = vault.definitionFor('song.metallica.master_of_puppets', query: q);
      expect(less.dimensions[ToneDimension.gain]!, lessThan(base.dimensions[ToneDimension.gain]!));
      final slight = vault.definitionFor('song.metallica.master_of_puppets', query: parse('Master of Puppets etwas weniger Gain').query);
      final strong = vault.definitionFor('song.metallica.master_of_puppets', query: parse('Master of Puppets viel weniger Gain').query);
      final g = base.dimensions[ToneDimension.gain]!;
      expect(g - slight.dimensions[ToneDimension.gain]!, lessThan(g - less.dimensions[ToneDimension.gain]!));
      expect(g - less.dimensions[ToneDimension.gain]!, lessThan(g - strong.dimensions[ToneDimension.gain]!));
      // the vault entry itself is untouched
      expect(vault.definition('song.metallica.master_of_puppets').dimensions[ToneDimension.gain], g);
    });

    test('Clamping 0..100 und Gesamtgrenze', () {
      final high = applyToneModifierIntents({ToneDimension.gain: 98, ToneDimension.saturation: 2}, const [
        ToneModifierIntent(ToneModifier.moreGain, ToneIntensity.strong),
      ]);
      expect(high.dimensions[ToneDimension.gain], 100);
      final low = applyToneModifierIntents({ToneDimension.saturation: 3}, const [
        ToneModifierIntent(ToneModifier.lessGain, ToneIntensity.strong),
      ]);
      expect(low.dimensions[ToneDimension.saturation], 0);
      final stacked = applyToneModifierIntents({ToneDimension.gain: 50}, [
        for (var i = 0; i < 8; i++) const ToneModifierIntent(ToneModifier.moreGain, ToneIntensity.strong),
      ]);
      expect(stacked.dimensions[ToneDimension.gain], 50 + toneModifierMaxShift);
      final undefined = applyToneModifierIntents(const {}, const [ToneModifierIntent(ToneModifier.moreGain, ToneIntensity.normal)]);
      expect(undefined.dimensions, isEmpty);
      expect(undefined.skipped, contains(ToneDimension.gain));
    });

    test('Alle Modifier haben Deltas innerhalb der Grenzen', () {
      for (final m in ToneModifier.values) {
        final deltas = toneModifierDeltas[m];
        expect(deltas, isNotNull, reason: m.wire);
        for (final d in deltas!.values) {
          expect(d.abs() * ToneIntensity.strong.percent / 100, lessThanOrEqualTo(toneModifierMaxShift), reason: m.wire);
        }
      }
    });

    test('Effekte gehen in die kanonische Beschreibung und das Rezept', () {
      // Angels has reverb + a boost; "ohne Reverb" must switch reverb OFF, chorus must switch modulation ON
      final off = vault.definitionFor('song.children_of_bodom.angels_dont_kill', query: parse('Angels Dont Kill ohne Reverb').query);
      expect(off.dimensions[ToneDimension.reverb], 0);
      expect(recipeOf(off)[ToneBlockRole.reverb].state, RecipeBlockState.off);
      final chorus = vault.definitionFor('original.vhs_chorus_clean', query: parse('VHS Clean mit Chorus aber ohne Reverb').query);
      expect(chorus.dimensions[ToneDimension.reverb], 0);
      expect(chorus.dimensions[ToneDimension.modulation]!, greaterThan(0));
      final recipe = recipeOf(chorus);
      expect(recipe[ToneBlockRole.reverb].state, RecipeBlockState.off);
      expect(recipe[ToneBlockRole.modulation].state, isNot(RecipeBlockState.off));
    });

    test('Ohne Nutzerwünsche gleicht definitionFor der V1-Definition (Angels-Äquivalenz)', () {
      final a = vault.definition('song.children_of_bodom.angels_dont_kill');
      final b = vault.definitionFor('song.children_of_bodom.angels_dont_kill', query: parse("Angels Don't Kill").query);
      expect(b.dimensions, a.dimensions);
      final ra = recipeOf(a), rb = recipeOf(b);
      for (final role in ToneBlockRole.values) {
        expect(rb[role].state, ra[role].state, reason: role.name);
        expect(rb[role].kind?.value, ra[role].kind?.value, reason: role.name);
      }
    });

    test('Deterministisch', () {
      for (final q in ['Metallica Master of Puppets Rhythmus Drop C etwas weniger Gain', 'metal', 'warmer Blues Crunch mit etwas Reverb']) {
        final a = parse(q), b = loadVault().nlu.understand(q);
        expect(a.explanation, b.explanation);
        expect([for (final c in a.resolution.candidates) c.entry.id], [for (final c in b.resolution.candidates) c.entry.id]);
        expect(a.query.confidence, b.query.confidence);
      }
    });
  });

  group('Testkorpus', () {
    final corpus = jsonDecode(read('test/tonevault/nlu_corpus.json')) as Map<String, Object?>;
    final queries = (corpus['queries'] as List).cast<Map<String, Object?>>();

    test('umfasst mindestens 100 Anfragen in allen Kategorien und die 20 Pflichtanfragen', () {
      expect(queries.length, greaterThanOrEqualTo(100));
      final cats = {for (final q in queries) q['category']};
      expect(
        cats,
        containsAll(['artist', 'song', 'album', 'genre', 'role', 'tuning', 'modifier', 'intensity', 'negation', 'effects', 'era', 'typos', 'combined', 'electronic', 'unknown', 'ambiguous']),
      );
      final all = {for (final q in queries) q['q']};
      for (final must in const [
        'typischer Metallica Sound',
        'Metallica Master of Puppets Rhythmus',
        'Master of Puppets aber weniger Gain',
        'Metallica Rhythmus mit mehr Mitten und weniger Bass',
        'Children of Bodom Downfall Lead',
        "Angels Don't Kill etwas weniger scharf",
        'BFMV Scream Aim Fire',
        'moderner Metal Sound für Drop C',
        'fetter Metalcore Rhythm Sound',
        '80er Hard Rock Lead mit viel Delay',
        'warmer Blues Crunch',
        'Nirvana In Utero aber etwas dreckiger',
        'Clean Sound mit Chorus und viel Reverb',
        'dunkler Ambient Sound',
        'Sandstorm auf Gitarre',
        'Sandstorm aber aggressiver',
        'Cyberpunk Lead mit Delay',
        'mach mir einen richtig kaputten Industrial Sound',
        'metallika master of pupets rhythm drop c weniger gain',
        'no reverb metalcore rhythm',
      ]) {
        expect(all, contains(must));
      }
    });

    test('alle Erwartungen des Korpus treffen zu', () {
      final failures = <String>[];
      for (final item in queries) {
        final q = item['q'] as String;
        final expect_ = (item['expect'] as Map).cast<String, Object?>();
        final r = parse(q);
        final x = r.query;
        void check(String key, Object? actual) {
          if (!expect_.containsKey(key)) return;
          final want = expect_[key];
          final ok = want is List ? (key == 'unresolved' || key == 'styleTerms' ? want.every((w) => (actual as List).contains(w)) : _listEq(want, actual as List)) : want == actual;
          if (!ok) failures.add('"$q" $key: erwartet $want, war $actual');
        }

        check('artist', x.artist);
        check('song', x.song);
        check('album', x.album);
        check('genre', x.genre);
        check('subgenre', x.subgenre);
        check('era', x.era);
        check('role', x.role?.wire);
        check('tuning', x.tuning);
        check('kind', r.resolution.kind.name);
        check('base', r.baseEntryId);
        check('modifiers', mods(x));
        check('effects', fx(x));
        check('unresolved', x.unresolvedTokens);
        check('styleTerms', x.styleTerms);
      }
      final rate = 1 - failures.length / queries.length;
      // ignore: avoid_print
      print('NLU-Korpus: ${queries.length} Anfragen, Erfolgsquote ${(rate * 100).toStringAsFixed(1)} %, ${failures.length} Abweichungen');
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  });

  group('Offline und keine Gerätedaten', () {
    test('NLU-Code und -Daten: kein Netz, keine Geräte-/Protokollbegriffe', () {
      final files = [
        'lib/tonevault/tone_nlu.dart',
        'lib/tonevault/tone_nlu_lexicon.dart',
        'lib/tonevault/tone_vault_query.dart',
        'lib/tonevault/tone_vault_search.dart',
      ];
      for (final f in files) {
        final code = read(f);
        for (final banned in ['package:http', 'dart:io', 'dart:html', 'HttpClient', 'WebSocket', 'firebase', 'openai', 'anthropic', 'presets/matribox']) {
          expect(code.toLowerCase().contains(banned.toLowerCase()), isFalse, reason: '$f: $banned');
        }
      }
      final data = read('assets/tonevault/nlu.json').toLowerCase();
      for (final term in ['sysex', 'wireindex', 'algorithm', 'matribox', 'qme', 'midi']) {
        expect(data.contains(term), isFalse, reason: term);
      }
    });

    test('kein Artist-/Song-Sonderfall im Parser', () {
      final code = (read('lib/tonevault/tone_nlu.dart') + read('lib/tonevault/tone_nlu_lexicon.dart')).toLowerCase();
      for (final name in ['metallica', 'nirvana', 'slayer', 'bodom', 'sandstorm']) {
        expect(code.contains(name), isFalse, reason: name);
      }
    });
  });
}

bool _listEq(List a, List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
