import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/models/target_sound.dart';
import 'package:wyrmtone/models/tone_target.dart';
import 'package:wyrmtone/presets/canonical_tone_recipe.dart';
import 'package:wyrmtone/presets/tone_intent.dart' show ToneBlockRole;
import 'package:wyrmtone/presets/tone_recipe_builder.dart';
import 'package:wyrmtone/services/offline_sound_profiles.dart';
import 'package:wyrmtone/tonevault/tone_vault.dart';
import 'package:wyrmtone/tonevault/tone_vault_model.dart';
import 'package:wyrmtone/tonevault/tone_vault_query.dart';
import 'package:wyrmtone/tonevault/tone_vault_search.dart';
import 'package:wyrmtone/tonevault/tone_vault_taxonomy.dart';

String read(String p) => File(p).readAsStringSync();

ToneVault loadSeed() {
  final manifest = JsonManifest.parse(read('assets/tonevault/manifest.json'));
  return ToneVault.fromTexts(
    taxonomy: read('assets/tonevault/taxonomy.json'),
    vocabulary: read('assets/tonevault/vocabulary.json'),
    packs: [for (final p in manifest.packs) read('assets/tonevault/$p')],
  );
}

Map<String, Object?> entryJson(
  String id, {
  String type = 'GENRE_TEMPLATE',
  String source = 'CURATED',
  String confidence = 'MEDIUM',
  List<String> parents = const [],
  List<String> genres = const ['thrash_metal'],
  Map<String, Object?>? tone,
  List<Object?> variants = const [],
  List<String> roles = const ['RHYTHM', 'LEAD'],
  Map<String, Object?> extra = const {},
}) => {
  'id': id,
  'schemaVersion': 1,
  'type': type,
  'title': id,
  'source': {'classification': source},
  'confidence': confidence,
  'genres': genres,
  'parents': parents,
  'roles': roles,
  'tone': tone ?? {'dimensions': {'gain': 50}},
  'variants': variants,
  ...extra,
};

String packJson(List<Map<String, Object?>> entries) => jsonEncode({
  'pack': {
    'id': 't',
    'name': 't',
    'version': 1,
    'schemaVersion': 1,
    'license': {'name': 'test'},
  },
  'entries': entries,
});

ToneVault vaultOf(List<Map<String, Object?>> entries) => ToneVault.fromTexts(
  taxonomy: read('assets/tonevault/taxonomy.json'),
  vocabulary: read('assets/tonevault/vocabulary.json'),
  packs: [packJson(entries)],
);

List<String> errorCodes(List<Map<String, Object?>> entries) {
  try {
    vaultOf(entries);
    return [];
  } on ToneVaultLoadException catch (e) {
    return [for (final i in e.issues.where((i) => i.isError)) i.code];
  }
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

CanonicalToneRecipe buildRecipe(TargetSound s, SoundRole role) =>
    ToneRecipeBuilder.build(profile: s, guitar: testGuitar, tuning: GuitarTuning.dropC, role: role);

void main() {
  late ToneVault vault;
  setUpAll(() => vault = loadSeed());

  group('Schema und IDs', () {
    test('Seed lädt, IDs stabil und eindeutig, Schema-Version 1', () {
      final ids = vault.entries.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(vault.entries.every((e) => e.schemaVersion == toneVaultSchemaVersion), isTrue);
      expect(vault.entries.every((e) => RegExp(r'^[a-z0-9_.]+$').hasMatch(e.id)), isTrue);
      expect(vault.entry('song.children_of_bodom.angels_dont_kill'), isNotNull);
      expect(vault.warnings.where((w) => w.isError), isEmpty);
    });

    test('Seed-Umfang und geforderte Artists', () {
      final artists = vault.entries.where((e) => e.type == ToneEntryType.artistSignature).toList();
      expect(vault.entries.length, greaterThanOrEqualTo(87), reason: 'die 87 Seed-Einträge bleiben erhalten');
      expect(artists.length, greaterThanOrEqualTo(45));
      for (final name in const ['Metallica', 'Slayer', 'Megadeth', 'Iron Maiden', 'Children of Bodom', 'Nirvana']) {
        expect(artists.any((a) => a.artist == name), isTrue, reason: name);
      }
      expect(vault.entries.where((e) => e.type == ToneEntryType.guitarReimagined), isNotEmpty);
      expect(vault.entries.where((e) => e.type.isTemplate), isNotEmpty);
    });

    test('Format-Fehler: unbekanntes Feld und falsche Schema-Version werden abgelehnt', () {
      expect(errorCodes([entryJson('a.b', extra: {'sysex': 'F0'})]), isNotEmpty);
      final bad = entryJson('a.b')..['schemaVersion'] = 99;
      expect(errorCodes([bad]), isNotEmpty);
    });

    test('Keine Gerätefelder in Schema/Seed, keine Netz-/Geräteabhängigkeit im Code', () {
      final texts = [
        for (final f in Directory('assets/tonevault').listSync(recursive: true).whereType<File>()) f.readAsStringSync(),
        for (final l in read('lib/tonevault/tone_vault_model.dart').split(RegExp(r'\r?\n')))
          if (!l.trimLeft().startsWith('//')) l,
      ].join('\n').toLowerCase();
      for (final term in const ['sysex', 'wireindex', 'algorithmcode', 'qme', 'nativeparam']) {
        expect(texts.contains(term), isFalse, reason: term);
      }
      final code = Directory('lib/tonevault').listSync().whereType<File>().map((f) => f.readAsStringSync()).join('\n');
      expect(code.contains('presets/matribox'), isFalse);
      expect(code.contains('dart:io'), isFalse);
      expect(code.contains('package:http'), isFalse);
    });
  });

  group('Vererbung', () {
    test('OFF vs INHERIT vs UNSPECIFIED, mehrstufig', () {
      final v = vaultOf([
        entryJson('tpl.genre.g', tone: {
          'dimensions': {'gain': 60, 'reverb': 30, 'delay': 20, 'bass': 50},
        }),
        entryJson('tpl.style.s', type: 'STYLE_TEMPLATE', parents: ['tpl.genre.g'], tone: {
          'dimensions': {'reverb': 'off', 'delay': 'inherit', 'gain': 70},
        }),
        entryJson('artist.a', type: 'ARTIST_SIGNATURE', extra: {'artist': 'A'}, parents: ['tpl.style.s'], tone: {
          'dimensions': {'bass': 40},
        }),
      ]);
      final t = v.composer.resolve('artist.a');
      expect(t.chain, ['tpl.genre.g', 'tpl.style.s', 'artist.a']);
      expect(t.dimensions[ToneDimension.gain], 70);
      expect(t.dimensions[ToneDimension.reverb], 0);
      expect(t.explicitOff, contains(ToneDimension.reverb));
      expect(t.dimensions[ToneDimension.delay], 20, reason: 'INHERIT behält den Elternwert');
      expect(t.dimensions[ToneDimension.bass], 40);
      expect(t.dimensions.containsKey(ToneDimension.presence), isFalse, reason: 'UNSPECIFIED bleibt offen');
      expect(t.provenance['dimension:gain'], 'tpl.style.s');
    });

    test('Seed-Song erbt mehrstufig', () {
      expect(vault.composer.resolve('song.metallica.master_of_puppets').chain.length, greaterThan(2));
    });

    test('Varianten überschreiben nur ihre Ebene; unbekannte Variante meldet Basisklang', () {
      final v = vaultOf([
        entryJson('tpl.genre.g', tone: {
          'dimensions': {'gain': 60, 'sustain': 40},
        }, variants: [
          {
            'kind': 'LEAD',
            'tone': {
              'dimensions': {'sustain': 70},
            },
          },
        ]),
        entryJson('artist.a', type: 'ARTIST_SIGNATURE', extra: {'artist': 'A'}, parents: ['tpl.genre.g'], tone: {
          'dimensions': {'gain': 80},
        }),
      ]);
      final lead = v.composer.resolve('artist.a', variant: ToneVariantKind.lead);
      expect(lead.dimensions[ToneDimension.gain], 80);
      expect(lead.dimensions[ToneDimension.sustain], 70);
      final solo = v.composer.resolve('artist.a', variant: ToneVariantKind.solo);
      expect(solo.variantMatched, isFalse);
      expect(solo.dimensions[ToneDimension.sustain], 40);
    });

    test('Zyklen, fehlende Parents und Rang werden abgelehnt', () {
      expect(
        errorCodes([entryJson('tpl.genre.a', parents: ['tpl.genre.b']), entryJson('tpl.genre.b', parents: ['tpl.genre.a'])]),
        isNotEmpty,
      );
      expect(errorCodes([entryJson('tpl.genre.a', parents: ['tpl.genre.nope'])]), contains('PARENT_MISSING'));
      expect(
        errorCodes([
          entryJson('artist.a', type: 'ARTIST_SIGNATURE', extra: {'artist': 'A'}),
          entryJson('tpl.genre.g', parents: ['artist.a']),
        ]),
        contains('PARENT_RANK_INVALID'),
      );
    });

    test('Angels: Vault-Song ist äquivalent zum JSON-Profil', () {
      final json = OfflineSoundProfiles.decode(
        read('assets/catalog/sound_profiles.json'),
      ).firstWhere((p) => p.id == 'cob-angels-dont-kill');
      final sound = vault.definition('song.children_of_bodom.angels_dont_kill').toTargetSound();
      for (final d in ToneDimension.values) {
        expect(sound.toneTarget!.values[d] ?? 0, json.toneTarget!.values[d] ?? 0, reason: d.name);
      }
      final a = buildRecipe(json, SoundRole.rhythm), b = buildRecipe(sound, SoundRole.rhythm);
      for (final role in ToneBlockRole.values) {
        expect(b[role].state, a[role].state, reason: role.name);
        expect(b[role].kind?.value, a[role].kind?.value, reason: role.name);
        expect({for (final e in b[role].params.entries) e.key: e.value.value}, {for (final e in a[role].params.entries) e.key: e.value.value}, reason: role.name);
      }
    });
  });

  group('Source und Confidence', () {
    test('getrennt; RESEARCHED braucht Quelle', () {
      expect(errorCodes([entryJson('a.b', source: 'RESEARCHED')]), contains('SOURCE_MISSING'));
      final ok = entryJson('a.b', extra: {
        'source': {
          'classification': 'RESEARCHED',
          'references': [
            {'title': 'Interview'},
          ],
        },
      });
      expect(errorCodes([ok]), isEmpty);
      expect(errorCodes([entryJson('a.b', confidence: 'HIGH', source: 'STYLE_INSPIRED')]), isEmpty);
    });

    test('Reimagined-Einträge tragen GUITAR_REIMAGINED und einen Disclaimer', () {
      final e = vault.entry('reimagined.darude_sandstorm')!;
      expect(e.sourceClass, SourceClass.guitarReimagined);
      expect(vault.definition(e.id).disclaimers.join(' '), contains('kein Nachbau'));
    });

    test('Validator: Ranges, Genre, Duplikate, Aliase, Varianten', () {
      expect(errorCodes([entryJson('a.b', tone: {'dimensions': {'gain': 140}})]), contains('RANGE_INVALID'));
      expect(errorCodes([entryJson('a.b', genres: ['no_such_genre'])]), contains('GENRE_UNKNOWN'));
      expect(errorCodes([entryJson('a.b'), entryJson('a.b')]), contains('DUPLICATE_ID'));
      expect(
        errorCodes([
          entryJson('artist.x', type: 'ARTIST_SIGNATURE', extra: {'artist': 'X', 'artistAliases': ['Zed']}),
          entryJson('artist.y', type: 'ARTIST_SIGNATURE', extra: {'artist': 'Y', 'artistAliases': ['zed']}),
        ]),
        isNotEmpty,
      );
      expect(
        errorCodes([
          entryJson('a.b', variants: [
            {'kind': 'LEAD'},
            {'kind': 'LEAD'},
          ]),
        ]),
        contains('VARIANT_DUPLICATE'),
      );
    });
  });

  group('Suche', () {
    ToneVaultResolution q(String text) => vault.resolve(text);

    test('exact, alias, Normalisierung', () {
      expect(q('Master of Puppets').primary?.entry.id, 'song.metallica.master_of_puppets');
      expect(q('  MASTER-OF-PUPPETS ').primary?.entry.id, 'song.metallica.master_of_puppets');
      expect(q('Sandstorm').primary?.entry.id, 'reimagined.darude_sandstorm');
      expect(q('BFMV Scream Aim Fire').primary?.entry.id, 'song.bullet_for_my_valentine.scream_aim_fire');
    });

    test('Fuzzy: Tippfehler, Exact ohne Fuzzy', () {
      final r = q('metallika master of pupets');
      expect(r.fuzzyUsed, isTrue);
      expect(r.primary?.entry.id, 'song.metallica.master_of_puppets');
      expect(q('Master of Puppets').fuzzyUsed, isFalse);
    });

    test('Artist + Song + Rolle', () {
      final r = q('Metallica Master of Puppets Rhythm');
      expect(r.kind, ResolutionKind.exact);
      expect(r.primary?.entry.id, 'song.metallica.master_of_puppets');
      expect(r.query.role, ToneVariantKind.rhythm);
      final lead = q('Children of Bodom Downfall Lead');
      expect(lead.primary?.entry.id, 'song.children_of_bodom.downfall');
      expect(lead.query.role, ToneVariantKind.lead);
    });

    test('Mehrdeutig: Metallica ergibt eine Auswahl', () {
      final r = q('typischer Metallica Sound');
      expect(r.kind, ResolutionKind.choose);
      expect(r.candidates.length, greaterThan(1));
      expect(q('metallica').requiresChoice, isTrue);
    });

    test('Genre-Suche, Tuning, Modifier, Rolle neben Genre', () {
      expect(q('melodic death metal').candidates, isNotEmpty);
      final m = q('fetter moderner Metal Sound in Drop C');
      expect(m.query.tuning, 'dropC');
      expect(m.query.modifiers, containsAll([ToneModifier.moreBody, ToneModifier.moreModern]));
      expect(q('BFMV Scream Aim Fire aber weniger Gain').query.modifiers, [ToneModifier.lessGain]);
      expect(q('blues crunch').query.role, ToneVariantKind.crunch);
    });

    test('Deutsch/Englisch, Determinismus, nichts erkannt', () {
      expect(q('dunkler Cyberpunk Lead').primary?.entry.id, 'original.cyberpunk_lead');
      final a = q('metal').candidates.map((c) => c.entry.id).toList();
      final b = loadSeed().resolve('metal').candidates.map((c) => c.entry.id).toList();
      expect(a, b);
      expect(q('xqzvbnm wtfplk').kind, ResolutionKind.none);
    });

    test('Modifier ändern nur definierte Dimensionen, geclampt', () {
      final base = vault.definition('song.metallica.master_of_puppets');
      final more = vault.definition('song.metallica.master_of_puppets', modifiers: [ToneModifier.moreGain]);
      expect(more.dimensions[ToneDimension.gain]!, greaterThan(base.dimensions[ToneDimension.gain]!));
      final applied = applyToneModifiers({ToneDimension.gain: 98}, [ToneModifier.moreGain]);
      expect(applied.dimensions[ToneDimension.gain], 100);
      expect(applied.skipped, contains(ToneDimension.saturation));
    });
  });

  test('Taxonomie: Nachfahren', () {
    final tax = ToneTaxonomy.parse(read('assets/tonevault/taxonomy.json'));
    expect(tax.withDescendants('metal'), contains('thrash_metal'));
  });

  group('Hand-over an die bestehende Pipeline', () {
    test('toTargetSound: kein Template-Fallback, Rolle, Herkunft', () {
      final s = vault.definition('song.metallica.master_of_puppets', variant: ToneVariantKind.lead).toTargetSound();
      expect(s.templateFallback, isFalse);
      expect(s.roles, [SoundRole.lead]);
      expect(s.toneTarget!.source, contains('ToneVault'));
      expect(s.id, startsWith('vault:'));
    });

    test('Jeder Vault-Eintrag baut ein CanonicalToneRecipe', () {
      for (final e in vault.entries) {
        final def = vault.definition(e.id);
        final recipe = buildRecipe(def.toTargetSound(), def.role);
        expect(recipe.blocks.length, ToneBlockRole.values.length, reason: e.id);
      }
    });
  });
}
