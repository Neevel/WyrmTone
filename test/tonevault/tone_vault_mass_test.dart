import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/devices/device_profile.dart';
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/models/target_sound.dart';
import 'package:wyrmtone/models/tone_target.dart';
import 'package:wyrmtone/presets/canonical_tone_recipe.dart';
import 'package:wyrmtone/presets/tone_intent.dart' show RecipeBlockState, ToneBlockRole, ToneOrigin;
import 'package:wyrmtone/presets/tone_recipe_builder.dart';
import 'package:wyrmtone/services/offline_sound_engine.dart';
import 'package:wyrmtone/tonevault/tone_nlu.dart';
import 'package:wyrmtone/tonevault/tone_vault.dart';
import 'package:wyrmtone/tonevault/tone_vault_model.dart';
import 'package:wyrmtone/tonevault/tone_vault_report.dart';
import 'package:wyrmtone/tonevault/tone_vault_taxonomy.dart';
import 'package:wyrmtone/tonevault/tone_vault_text.dart';
import 'package:wyrmtone/tonevault/tone_vault_validator.dart';

String read(String p) => File(p).readAsStringSync();

const seedPackFiles = [
  'packs/core_genres.json',
  'packs/metal_essentials.json',
  'packs/modern_metal.json',
  'packs/extreme_metal.json',
  'packs/rock_essentials.json',
  'packs/alternative_grunge.json',
  'packs/punk_pop_punk.json',
  'packs/electronic_reimagined.json',
];

List<String> packTexts({bool reversed = false}) {
  final manifest = JsonManifest.parse(read('assets/tonevault/manifest.json'));
  final list = [for (final p in manifest.packs) read('assets/tonevault/$p')];
  return reversed ? list.reversed.toList() : list;
}

ToneVault loadMass({bool reversed = false}) {
  final manifest = JsonManifest.parse(read('assets/tonevault/manifest.json'));
  return ToneVault.fromTexts(
    taxonomy: read('assets/tonevault/taxonomy.json'),
    vocabulary: read('assets/tonevault/vocabulary.json'),
    packs: packTexts(reversed: reversed),
    nlu: read('assets/tonevault/${manifest.nlu}'),
  );
}

const guitar = GuitarProfile(
  id: 'g',
  name: 'Test',
  guitarType: GuitarType.superstrat,
  pickupType: PickupType.activeHumbucker,
  outputLevel: OutputLevel.high,
  toneCharacter: ToneCharacter.bright,
  tuning: GuitarTuning.dropC,
  playbackPath: PlaybackPath.headphones,
);

CanonicalToneRecipe recipe(TargetSound s, SoundRole role, {GuitarTuning tuning = GuitarTuning.dropC, ToneTarget? finalTone}) =>
    ToneRecipeBuilder.build(profile: s, guitar: guitar, tuning: tuning, role: role, finalTone: finalTone);

double ampParam(CanonicalToneRecipe r, String name) => r[ToneBlockRole.amp].params[name]!.value;
ToneOrigin ampOrigin(CanonicalToneRecipe r, String name) => r[ToneBlockRole.amp].params[name]!.origin;

String norm(String s) => ToneText.normalize(s);

void main() {
  late ToneVault vault;
  setUpAll(() => vault = loadMass());
  ToneNluResult ask(String q) => vault.nlu.understand(q);

  group('Import und Pack-Metadaten', () {
    test('kompletter Katalog: null Fehler, keine Warnungen', () {
      final parsed = [for (final t in packTexts()) ToneVaultPackParser.parse(t)];
      final issues = [
        for (final p in parsed) ...p.issues,
        ...ToneVaultValidator.validate(
          [for (final p in parsed) ...p.pack!.entries],
          ToneTaxonomy.parse(read('assets/tonevault/taxonomy.json')),
        ),
      ];
      expect(issues.where((i) => i.isError), isEmpty, reason: issues.take(5).join('\n'));
      expect(issues, isEmpty, reason: 'Warnungen: ${issues.take(5).join('\n')}');
    });

    test('jedes Pack hat stabile Metadaten und eine korrekte Eintragszahl', () {
      final ids = <String>{};
      for (final p in vault.packs) {
        expect(ids.add(p.id), isTrue, reason: 'doppelte Pack-ID ${p.id}');
        expect(p.id, matches(RegExp(r'^[a-z0-9_]+$')));
        expect(p.schemaVersion, toneVaultSchemaVersion);
        expect(p.version, greaterThanOrEqualTo(1));
        expect(p.name.trim(), isNotEmpty);
        expect((p.description ?? '').trim(), isNotEmpty, reason: p.id);
        expect(p.license.name, isNotEmpty);
        if (!seedPackFiles.contains('packs/${p.id}.json')) {
          expect(p.entryCount, p.entries.length, reason: p.id);
          expect(p.sourceClassification, isNotNull, reason: p.id);
        }
      }
      expect(vault.packs.length, greaterThanOrEqualTo(30));
    });

    test('Pack-Eintragszahl wird validiert', () {
      final broken = jsonDecode(read('assets/tonevault/packs/blues.json')) as Map<String, Object?>;
      (broken['pack'] as Map)['entryCount'] = 3;
      final parsed = ToneVaultPackParser.parse(jsonEncode(broken));
      expect(parsed.issues.map((i) => i.code), contains('PACK_COUNT'));
    });

    test('Import ist deterministisch und unabhängig von der Pack-Reihenfolge', () {
      final a = vault, b = loadMass(reversed: true);
      expect(b.entries.length, a.entries.length);
      for (final q in ['typischer Metallica Sound', '80er metal', 'blues crunch', 'metal', 'Metallica Master of Puppets Rhythmus', 'punk']) {
        expect([for (final c in b.resolve(q).candidates) c.entry.id], [for (final c in a.resolve(q).candidates) c.entry.id], reason: q);
      }
      expect(jsonEncode(ToneVaultCatalogReport.stats(b)['byType']), jsonEncode(ToneVaultCatalogReport.stats(a)['byType']));
    });

    test('Generator ohne Zufall, Hashes oder Uhrzeit', () {
      for (final f in Directory('tool/tonevault_catalog').listSync().whereType<File>().where((f) => f.path.endsWith('.py'))) {
        final code = f.readAsStringSync();
        for (final banned in ['import random', 'from random', 'hashlib', 'secrets', 'uuid', 'import time', 'datetime']) {
          expect(code.contains(banned), isFalse, reason: '${f.path}: $banned');
        }
      }
    });
  });

  group('Umfang und Abdeckung', () {
    test('Zielzahlen', () {
      final s = ToneVaultCatalogReport.stats(vault);
      expect(s['entriesTotal'] as int, greaterThanOrEqualTo(1000));
      expect(s['artists'] as int, greaterThanOrEqualTo(300));
      expect(s['songs'] as int, inInclusiveRange(100, 300), reason: 'kuratierter Song-Layer, keine Massenerzeugung');
      expect(s['albums'] as int, greaterThanOrEqualTo(30));
      expect(s['eraSignatures'] as int, greaterThanOrEqualTo(40));
      expect(s['templates'] as int, greaterThanOrEqualTo(60));
      expect(s['resolvableVariants'] as int, greaterThanOrEqualTo(1000));
      expect((s['guitarReimagined'] as int) + (s['wyrmOriginals'] as int), greaterThanOrEqualTo(50));
      expect((s['artists'] as int), greaterThan(s['songs'] as int), reason: 'nicht jeder Artist braucht Songs');
    });

    test('Source-Klassen: nichts wird als RESEARCHED/AI/COMMUNITY ausgegeben', () {
      final dist = ToneVaultCatalogReport.stats(vault)['sourceClassification'] as Map;
      expect(dist.keys.toSet().difference({'CURATED', 'STYLE_INSPIRED', 'GUITAR_REIMAGINED', 'WYRM_ORIGINAL'}), isEmpty);
      for (final e in vault.entries.where((e) => e.type == ToneEntryType.artistSignature)) {
        expect(e.sourceClass, SourceClass.styleInspired, reason: e.id);
        expect(e.notes ?? '', contains('keine Aussage über Originalequipment'), reason: e.id);
      }
    });

    test('alle geforderten Artists sind vorhanden', () {
      const required = [
        // Metal
        'Metallica', 'Megadeth', 'Slayer', 'Anthrax', 'Testament', 'Exodus', 'Kreator', 'Sodom', 'Sepultura', 'Pantera', 'Machine Head',
        'Lamb of God', 'Gojira', 'Meshuggah', 'Tool', 'Dream Theater', 'Opeth', 'Mastodon', 'Black Sabbath', 'Ozzy Osbourne', 'Dio',
        'Iron Maiden', 'Judas Priest', 'Accept', 'Motörhead', 'Manowar', 'Helloween', 'Blind Guardian', 'HammerFall', 'Sabaton', 'Nightwish',
        'Within Temptation', 'Children of Bodom', 'In Flames', 'Dark Tranquillity', 'At the Gates', 'Arch Enemy', 'Amon Amarth', 'Soilwork',
        'Death', 'Cannibal Corpse', 'Morbid Angel', 'Obituary', 'Carcass', 'Behemoth', 'Mayhem', 'Emperor', 'Immortal', 'Dimmu Borgir',
        'Electric Wizard', 'Sleep', 'Kyuss', 'Down', 'Slipknot', 'Korn', 'System of a Down', 'Deftones', 'Linkin Park', 'Rammstein',
        'Fear Factory', 'Static-X', 'Disturbed', 'Avenged Sevenfold', 'Trivium', 'Killswitch Engage', 'Bullet for My Valentine',
        'As I Lay Dying', 'Parkway Drive', 'Architects', 'Bring Me the Horizon', 'August Burns Red', 'Periphery', 'TesseracT', 'Spiritbox',
        'Lorna Shore',
        // Rock
        'AC/DC', 'Led Zeppelin', 'Deep Purple', 'Queen', 'Pink Floyd', 'The Who', 'The Rolling Stones', 'Jimi Hendrix', 'Cream', 'Eric Clapton',
        'Dire Straits', 'ZZ Top', 'Aerosmith', "Guns N' Roses", 'Van Halen', 'Bon Jovi', 'Def Leppard', 'Mötley Crüe', 'Whitesnake', 'Scorpions',
        'Europe', 'Journey', 'Boston', 'Rush', 'Yes', 'King Crimson', 'Porcupine Tree', 'Nirvana', 'Alice in Chains', 'Soundgarden',
        'Pearl Jam', 'Stone Temple Pilots', 'Foo Fighters', 'Queens of the Stone Age', 'Muse', 'Radiohead', 'Arctic Monkeys', 'The Strokes',
        'The White Stripes', 'Smashing Pumpkins', 'Red Hot Chili Peppers', 'Rage Against the Machine', 'Audioslave', 'Green Day', 'Blink-182',
        'Sum 41', 'The Offspring', 'Bad Religion', 'Rise Against', 'My Chemical Romance', 'Paramore',
        // Other guitar
        'B.B. King', 'Stevie Ray Vaughan', 'Gary Moore', 'John Mayer', 'Joe Bonamassa', 'Albert King', 'Buddy Guy', 'Nile Rodgers', 'Cory Wong',
        'Prince', 'Mark Knopfler', 'Brad Paisley', 'Johnny Cash', 'Chet Atkins', 'Wes Montgomery', 'George Benson', 'Pat Metheny',
        'John Scofield', 'Joe Satriani', 'Steve Vai', 'Eric Johnson',
      ];
      final have = {for (final e in vault.entries.where((e) => e.type == ToneEntryType.artistSignature)) norm(e.artist!)};
      expect([for (final n in required) if (!have.contains(norm(n))) n], isEmpty);
    });

    test('Genre-Abdeckung: jedes geforderte Genre hat ein Template und Artists', () {
      final cov = (ToneVaultCatalogReport.coverage(vault)['genres'] as Map).cast<String, Map>();
      const genres = [
        // metal
        'heavy_metal', 'nwobhm', 'thrash_metal', 'speed_metal', 'power_metal', 'progressive_metal', 'groove_metal', 'nu_metal', 'alternative_metal',
        'industrial_metal', 'melodic_death_metal', 'death_metal', 'technical_death_metal', 'black_metal', 'symphonic_metal', 'doom_metal',
        'stoner_metal', 'sludge_metal', 'metalcore', 'melodic_metalcore', 'deathcore', 'djent', 'post_metal', 'folk_metal', 'viking_metal',
        'gothic_metal',
        // rock
        'classic_rock', 'hard_rock', 'blues_rock', 'progressive_rock', 'alternative_rock', 'grunge', 'post_grunge', 'indie_rock', 'garage_rock',
        'psychedelic_rock', 'southern_rock', 'glam_metal', 'punk_rock', 'pop_punk', 'post_punk', 'emo', 'post_hardcore', 'shoegaze', 'post_rock',
        // other guitar
        'blues', 'texas_blues', 'chicago_blues', 'funk', 'soul', 'country', 'jazz', 'fusion', 'surf', 'rockabilly', 'clean_pop', 'ambient', 'lo_fi',
      ];
      final missing = <String>[];
      for (final g in genres) {
        final c = cov[g];
        if (c == null || c['template'] != true || (c['artists'] as int) < 2) missing.add('$g ${c ?? 'fehlt'}');
      }
      expect(missing, isEmpty);
    });

    test('Templates sind musikalisch unterscheidbar (keine identischen Definitionen)', () {
      final dup = ToneVaultCatalogReport.duplicates(vault);
      final identicalTemplates = [
        for (final g in dup['identicalDefinitions'] as List)
          if ((g as List).any((id) => (id as String).startsWith('tpl.'))) g,
      ];
      expect(identicalTemplates, isEmpty);
    });

    test('Era-Metadaten: alle Dekaden und modern sind vorhanden und tragen Einträge', () {
      final tax = vault.taxonomy;
      for (final id in ['1960s', '1970s', '1980s', '1990s', '2000s', '2010s', '2020s', 'modern']) {
        expect(tax.hasEra(id), isTrue, reason: id);
      }
      for (final id in ['1960s', '1970s', '1980s', '1990s', '2000s', '2010s', 'modern']) {
        expect(vault.index.byEra[id] ?? const [], isNotEmpty, reason: id);
      }
      // "modern" as a bare word stays an adjective (modern metal); the era is reachable explicitly
      expect(ask('modern era metal').query.era, 'modern');
      expect(ask('modern metal').query.era, isNull);
    });
  });

  group('Duplikate und Kollisionen', () {
    test('keine Alias-, Artist- oder Titelkollisionen; keine überflüssigen Overrides im neuen Katalog', () {
      final d = ToneVaultCatalogReport.duplicates(vault);
      expect(d['artistAliasCollisions'], isEmpty);
      expect(d['songTitleCollisions'], isEmpty);
      expect(d['albumTitleCollisions'], isEmpty);
      expect(d['deepInheritance'], isEmpty);
      final seedIds = {
        for (final f in seedPackFiles) for (final e in (jsonDecode(read('assets/tonevault/$f'))['entries'] as List)) (e as Map)['id'] as String,
      };
      final redundant = (d['redundantOverrides'] as Map).keys.where((id) => !seedIds.contains(id)).toList();
      expect(redundant, isEmpty, reason: 'überflüssige Overrides im generierten Katalog');
      // documented legitimate cross-kind names (an artist that is also an album/song title)
      expect((d['crossKindCollisions'] as Map).keys.toSet(), containsAll(['korn', 'overkill']));
    });

    test('Erkennung funktioniert: künstliche Kollisionen und redundante Overrides werden gefunden', () {
      Map<String, Object?> entry(String id, {String type = 'ARTIST_SIGNATURE', Map<String, Object?>? extra, Object? gain = 50, String? parent}) => {
        'id': id,
        'schemaVersion': 1,
        'type': type,
        'title': id,
        'source': {'classification': 'CURATED'},
        'confidence': 'MEDIUM',
        'genres': ['thrash_metal'],
        'roles': ['RHYTHM'],
        if (parent != null) 'parents': [parent],
        'tone': {'dimensions': {'gain': gain}},
        ...?extra,
      };
      final pack = jsonEncode({
        'pack': {'id': 't', 'name': 't', 'version': 1, 'schemaVersion': 1, 'license': {'name': 't'}},
        'entries': [
          entry('tpl.genre.t', type: 'GENRE_TEMPLATE'),
          entry('artist.a', extra: {'artist': 'Alpha'}, parent: 'tpl.genre.t'),
          entry('artist.b', extra: {'artist': 'Beta', 'artistAliases': ['Alfa']}, parent: 'tpl.genre.t'),
          entry('song.a.x', type: 'SONG', extra: {'artist': 'Alpha', 'song': 'Same Title'}, parent: 'artist.a'),
          entry('song.b.x', type: 'SONG', extra: {'artist': 'Beta', 'song': 'Same Title'}, parent: 'artist.b'),
          entry('tpl.genre.dead', type: 'GENRE_TEMPLATE', gain: 33),
        ],
      });
      final v = ToneVault.fromTexts(
        taxonomy: read('assets/tonevault/taxonomy.json'),
        vocabulary: read('assets/tonevault/vocabulary.json'),
        packs: [pack],
      );
      final d = ToneVaultCatalogReport.duplicates(v);
      expect((d['songTitleCollisions'] as Map).keys, contains('same title'));
      expect((d['redundantOverrides'] as Map).keys, containsAll(['artist.a', 'artist.b']));
      expect(d['deadTemplates'], contains('tpl.genre.dead'));
      expect(
        (d['identicalDefinitions'] as List).any((g) => (g as List).contains('artist.a') && g.contains('artist.b')),
        isTrue,
      );
    });

    test('Bericht ist aktuell (tool/tonevault_catalog/catalog_report.json)', () {
      final report = ToneVaultCatalogReport.build(vault);
      final file = File('tool/tonevault_catalog/catalog_report.json');
      if (Platform.environment['WRITE_TONEVAULT_REPORT'] == '1') {
        file.writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(report)}\n');
      }
      final committed = jsonDecode(file.readAsStringSync()) as Map;
      expect(jsonEncode(committed['stats']), jsonEncode(jsonDecode(jsonEncode(report['stats']))), reason: 'Bericht neu erzeugen: WRITE_TONEVAULT_REPORT=1');
      expect(committed.keys, containsAll(['stats', 'coverage', 'duplicates']));
    });
  });

  group('Suche im Massenkatalog', () {
    test('jeder Artist ist über seinen Namen auffindbar, jeder Song über Artist + Titel exakt', () {
      final wrongSongs = <String>[], wrongArtists = <String>[];
      for (final e in vault.entries) {
        if (e.type == ToneEntryType.song) {
          if (ask('${e.artist} ${e.song}').baseEntryId != e.id) wrongSongs.add(e.id);
        } else if (e.type == ToneEntryType.artistSignature) {
          final r = ask(e.artist!);
          if (r.query.artist != e.artist || !r.resolution.candidates.any((c) => c.entry.id == e.id)) wrongArtists.add(e.id);
        }
      }
      expect(wrongSongs, isEmpty);
      expect(wrongArtists, isEmpty);
    });

    test('exakte Artist+Song-Treffer werden durch neue Einträge nicht verdrängt', () {
      expect(ask('Metallica Master of Puppets Rhythmus').baseEntryId, 'song.metallica.master_of_puppets');
      expect(ask('metallika master of pupets').baseEntryId, 'song.metallica.master_of_puppets');
      expect(ask('Children of Bodom Downfall Lead').baseEntryId, 'song.children_of_bodom.downfall');
      expect(ask('BFMV Scream Aim Fire').baseEntryId, 'song.bullet_for_my_valentine.scream_aim_fire');
      expect(ask('Nirvana In Utero').baseEntryId, 'album.nirvana.in_utero');
      expect(ask('sandstorm').baseEntryId, 'reimagined.darude_sandstorm');
      final metallica = ask('typischer Metallica Sound');
      expect(metallica.needsChoice, isTrue);
      expect(metallica.query.artist, 'Metallica');
      expect(metallica.resolution.candidates.map((c) => c.entry.id), containsAll(['artist.metallica', 'era.metallica.1980s', 'era.metallica.modern']));
    });

    test('Genre-Anfragen liefern das Template zuerst', () {
      String top(String q) => ask(q).resolution.candidates.first.entry.id;
      expect(top('thrash'), 'tpl.genre.thrash_metal');
      expect(top('synthwave'), 'tpl.genre.synthwave');
      expect(top('cyberpunk'), 'tpl.genre.cyberpunk_synth');
      expect(top('blues crunch'), 'tpl.genre.blues_clean');
      expect(top('death metal'), 'tpl.genre.death_metal');
      expect(top('funk'), 'tpl.genre.funk');
      expect(top('shoegaze'), 'tpl.genre.shoegaze');
    });

    test('Era-Anfragen liefern Kandidaten der Era', () {
      bool hasEra(ToneVaultEntry e, String era) => e.era == era || e.eras.contains(era);
      final cases = {
        '60s rock': '1960s',
        '70s rock': '1970s',
        '80s metal': '1980s',
        '80er hard rock': '1980s',
        '90s grunge': '1990s',
        '2000s metalcore': '2000s',
        '2010s modern metal': '2010s',
        '80s clean': '1980s',
        '90s alternative': '1990s',
      };
      cases.forEach((q, era) {
        final r = ask(q);
        expect(r.query.era, era, reason: q);
        expect(r.resolution.candidates, isNotEmpty, reason: q);
        final top = r.resolution.candidates.take(5).map((c) => c.entry);
        expect(top.where((e) => hasEra(e, era)).length, greaterThanOrEqualTo(3), reason: '$q -> ${top.map((e) => e.id).toList()}');
      });
      final modern = ask('modern metal');
      expect(modern.resolution.candidates.take(4).map((c) => c.entry.tags).every((t) => t.contains('modern')), isTrue);
      expect(ask('80s metal').query.genre, 'metal');
    });

    test('Reimagined und Originals sind auffindbar und richtig klassifiziert', () {
      const reimagined = [
        'Sandstorm', 'Children', 'Better Off Alone', 'Kernkraft 400', 'Insomnia', 'Firestarter', 'Breathe', 'Around the World',
        'Blue', "L'Amour Toujours", '9 PM', 'Hyper Hyper', 'Played-A-Live',
      ];
      for (final t in reimagined) {
        final r = ask(t);
        expect(r.resolution.candidates.any((c) => c.entry.type == ToneEntryType.guitarReimagined && c.entry.sourceClass == SourceClass.guitarReimagined), isTrue, reason: t);
      }
      const originals = [
        'Neon Outrun Lead', 'VHS Chorus Clean', 'Cyberpunk Lead', 'Dark Cyber Lead', 'Arcade Lead', 'Synth Bass Guitar', 'Industrial Machine Rhythm',
        'Trance Gate Guitar', 'Acid-Inspired Lead', 'Dreamwave Clean', 'Night Drive Lead', 'Blade Runner Inspired Ambient', '80s Movie Lead',
        'Space Chorus Clean', 'Darkwave Rhythm', 'Telephone Guitar', 'Radio Guitar', 'Underwater Clean', 'Broken Speaker', '8-Bit Inspired',
        'Horror Ambience', 'Space Ambience', 'Huge Arena Lead', 'Tiny Practice Amp', 'Garage Fuzz', 'Doom Wall', 'Chainsaw Metal',
        'Dream Clean', 'Cathedral Clean', 'Western Tremolo', 'Surf Spring', 'Lo-Fi Cassette', 'VHS Wobble',
      ];
      for (final t in originals) {
        final r = ask(t);
        expect(r.baseEntryId, isNotNull, reason: t);
        final e = vault.entry(r.baseEntryId!)!;
        expect(e.type, ToneEntryType.originalWyrmtone, reason: t);
        expect(e.sourceClass, SourceClass.wyrmOriginal, reason: t);
        expect(e.notes ?? '', contains('keine'), reason: t);
      }
      final s = ToneVaultCatalogReport.stats(vault);
      expect((s['guitarReimagined'] as int) + (s['wyrmOriginals'] as int), greaterThanOrEqualTo(50));
    });

    test('Special-Sounds sind klanglich eigenständig (nicht nur Umbenennungen)', () {
      final tel = vault.definition('original.telephone_guitar').dimensions;
      final clean = vault.definition('original.dream_clean').dimensions;
      expect(tel[ToneDimension.mids]!, greaterThan(70));
      expect(tel[ToneDimension.bass]!, lessThan(15));
      expect(clean[ToneDimension.gain]!, lessThan(15));
      expect(vault.definition('original.chainsaw_metal').dimensions[ToneDimension.gain]!, greaterThan(80));
      expect(vault.definition('original.cathedral_clean').dimensions[ToneDimension.reverb]!, greaterThan(85));
    });

    test('Vererbung: Artist -> Era -> Album -> Song -> Rolle', () {
      final r = vault.composer.resolve('song.metallica.battery', variant: ToneVariantKind.rhythm);
      expect(r.chain, containsAllInOrder(['tpl.genre.thrash_metal', 'artist.metallica', 'era.metallica.1980s', 'album.metallica.master_of_puppets', 'song.metallica.battery']));
      final lead = vault.composer.resolve('song.metallica.battery', variant: ToneVariantKind.lead);
      expect(lead.dimensions[ToneDimension.sustain]!, isNot(r.dimensions[ToneDimension.sustain]), reason: 'die LEAD-Variante des Templates greift');
      expect(vault.composer.resolve('era.in_flames.modern').chain, contains('artist.in_flames'));
    });
  });

  group('Stimmungen', () {
    test('Aliase werden erkannt und auf die neue Engine-Stimmung abgebildet', () {
      const cases = {
        'Drop C#': 'dropCSharp',
        'drop c#': 'dropCSharp',
        'drop db': 'dropCSharp',
        'C# Standard': 'cSharpStandard',
        'C sharp standard': 'cSharpStandard',
        'Cis Standard': 'cSharpStandard',
        'Drop A': 'dropA',
        'drop-a': 'dropA',
      };
      cases.forEach((text, id) {
        final r = ask('Metal $text');
        expect(r.query.tuning, id, reason: text);
        expect(r.tuning?.guitarTuning, id, reason: text);
        expect(GuitarTuning.values.where((t) => t.name == r.tuning!.guitarTuning), isNotEmpty, reason: text);
      });
      expect(ask('Metal Drop C').query.tuning, 'dropC', reason: 'Drop C bleibt Drop C');
      expect(ask('Metal Drop B').tuning?.guitarTuning, 'dropB');
    });

    test('die bestehende Tuning-Korrektur akzeptiert und wendet die neuen Stimmungen an', () {
      const engine = OfflineSoundEngine();
      final sound = vault.definition('song.metallica.master_of_puppets').toTargetSound();
      final target = sound.toneTarget!;
      final e = engine.adapt(target, guitar, GuitarTuning.eStandard, SoundRole.rhythm).$1;
      for (final t in [GuitarTuning.dropCSharp, GuitarTuning.dropA, GuitarTuning.cSharpStandard]) {
        final adapted = engine.adapt(target, guitar, t, SoundRole.rhythm).$1;
        expect(adapted[ToneDimension.bass], lessThan(e[ToneDimension.bass]), reason: '${t.name}: Tiefbass begrenzen');
        expect(adapted[ToneDimension.tightness], greaterThan(e[ToneDimension.tightness]), reason: '${t.name}: straffer');
        final r = recipe(sound, SoundRole.rhythm, tuning: t);
        expect(r.tuning, t.name);
        expect(r[ToneBlockRole.amp].state, RecipeBlockState.defined);
        final draft = engine.create(
          device: TargetDeviceId.matriboxOne,
          profile: sound,
          guitar: guitar,
          tuning: t,
          role: SoundRole.rhythm,
          nams: const [],
          irs: const [],
          folderIrs: const [],
          availableUris: const {},
        );
        expect(draft.tuning, t);
      }
      // deeper tunings correct at least as much as shallower ones; existing tunings are unchanged
      expect(GuitarTuning.dropA.depth, greaterThan(GuitarTuning.dropB.depth));
      expect(GuitarTuning.dropCSharp.depth, inInclusiveRange(GuitarTuning.dStandard.depth, GuitarTuning.dropC.depth));
      expect([for (final t in [GuitarTuning.eStandard, GuitarTuning.ebStandard, GuitarTuning.dStandard, GuitarTuning.dropD, GuitarTuning.dropC, GuitarTuning.dropB]) t.depth], [0, 1, 2, 1, 4, 6]);
      expect([for (final t in GuitarTuning.values) t.label], containsAll(['Drop C#', 'Drop A', 'C# Standard', 'Drop C', 'E Standard']));
    });
  });

  group('User-Override-Provenance', () {
    test('Master of Puppets weniger Gain: Gain ist USER_OVERRIDE, Korrekturen bleiben nachvollziehbar', () {
      final id = 'song.metallica.master_of_puppets';
      final baseline = recipe(vault.definition(id).toTargetSound(), SoundRole.rhythm);
      final q = ask('Master of Puppets weniger Gain');
      final def = vault.definitionFor(id, query: q.query);
      final wished = recipe(def.toTargetSound(), SoundRole.rhythm);
      expect(ampOrigin(wished, 'gain'), ToneOrigin.userOverride);
      expect(ampOrigin(baseline, 'gain'), isNot(ToneOrigin.userOverride));
      expect(ampParam(wished, 'gain'), ampParam(baseline, 'gain') - 10, reason: 'der Wunsch wirkt auf den korrigierten Wert (NORMAL = -10)');
      // untouched dimensions keep their tuning/guitar origin
      expect(ampOrigin(wished, 'bass'), ampOrigin(baseline, 'bass'));
      expect([ToneOrigin.tuningCorrection, ToneOrigin.guitarCorrection], contains(ampOrigin(wished, 'bass')));
      expect(ampParam(wished, 'bass'), ampParam(baseline, 'bass'));
      // the vault entry itself is unchanged
      expect(vault.definition(id).dimensions[ToneDimension.gain], def.baseDimensions![ToneDimension.gain]);
    });

    test('Metallica Rhythmus mehr Mitten: Mitten sind USER_OVERRIDE', () {
      const id = 'artist.metallica';
      final q = ask('Metallica Rhythmus mehr Mitten').query;
      expect(q.role, ToneVariantKind.rhythm);
      final baseline = recipe(vault.definition(id, variant: ToneVariantKind.rhythm).toTargetSound(), SoundRole.rhythm);
      final wished = recipe(vault.definitionFor(id, query: q).toTargetSound(), SoundRole.rhythm);
      expect(ampOrigin(wished, 'mids'), ToneOrigin.userOverride);
      expect(ampParam(wished, 'mids'), ampParam(baseline, 'mids') + 10);
      expect(ampOrigin(wished, 'upperMids'), ToneOrigin.userOverride);
      expect(ampOrigin(wished, 'treble'), isNot(ToneOrigin.userOverride));
    });

    test('Sandstorm aggressiver: Aggression (Gain/Präsenz) ist USER_OVERRIDE', () {
      const id = 'reimagined.darude_sandstorm';
      final q = ask('Sandstorm aggressiver').query;
      final baseline = recipe(vault.definition(id).toTargetSound(), SoundRole.lead);
      final def = vault.definitionFor(id, query: q);
      final wished = recipe(def.toTargetSound(), SoundRole.lead);
      expect(ampOrigin(wished, 'gain'), ToneOrigin.userOverride);
      expect(ampParam(wished, 'gain'), greaterThan(ampParam(baseline, 'gain')));
      expect(def.adjustments.shifts[ToneDimension.gain], 6);
    });

    test('Intensität und Begrenzung gelten auch im Rezept (0..100)', () {
      const id = 'song.metallica.master_of_puppets';
      final strong = recipe(vault.definitionFor(id, query: ask('Master of Puppets viel weniger Gain').query).toTargetSound(), SoundRole.rhythm);
      final slight = recipe(vault.definitionFor(id, query: ask('Master of Puppets etwas weniger Gain').query).toTargetSound(), SoundRole.rhythm);
      expect(ampParam(strong, 'gain'), lessThan(ampParam(slight, 'gain')));
      for (final r in [strong, slight]) {
        for (final p in r[ToneBlockRole.amp].params.values) {
          expect(p.value, inInclusiveRange(0, 100));
        }
      }
    });

    test('OFF-Wunsch: explizit AUS mit USER_OVERRIDE, auch für nicht definierte Dimensionen', () {
      const id = 'song.children_of_bodom.angels_dont_kill';
      final r = recipe(vault.definitionFor(id, query: ask("Angels Dont Kill ohne Reverb").query).toTargetSound(), SoundRole.rhythm);
      expect(r[ToneBlockRole.reverb].state, RecipeBlockState.off);
      expect(r[ToneBlockRole.reverb].stateOrigin, ToneOrigin.userOverride);
      final chorus = recipe(vault.definitionFor('original.dark_cyber_lead', query: ask('Dark Cyber Lead mit Chorus').query).toTargetSound(), SoundRole.lead);
      expect(chorus[ToneBlockRole.modulation].state, RecipeBlockState.defined);
      expect(chorus[ToneBlockRole.modulation].kind!.origin, ToneOrigin.userOverride, reason: 'die Chorus-Art ist ein Nutzerwunsch');
    });

    test('Pipeline: PresetDraft-Ton und Rezept stimmen überein (keine Doppelanwendung)', () {
      const id = 'song.metallica.master_of_puppets';
      const engine = OfflineSoundEngine();
      final base = vault.definition(id).toTargetSound();
      final sound = vault.definitionFor(id, query: ask('Master of Puppets weniger Gain').query).toTargetSound();
      final baseDraft = engine.create(
        device: TargetDeviceId.matriboxOne, profile: base, guitar: guitar, tuning: GuitarTuning.dropC, role: SoundRole.rhythm,
        nams: const [], irs: const [], folderIrs: const [], availableUris: const {},
      );
      final draft = engine.create(
        device: TargetDeviceId.matriboxOne, profile: sound, guitar: guitar, tuning: GuitarTuning.dropC, role: SoundRole.rhythm,
        nams: const [], irs: const [], folderIrs: const [], availableUris: const {},
      );
      expect(draft.tone[ToneDimension.gain], baseDraft.tone[ToneDimension.gain] - 10);
      final r = recipe(sound, SoundRole.rhythm, finalTone: draft.tone);
      expect(ampOrigin(r, 'gain'), ToneOrigin.userOverride);
      expect(ampParam(r, 'gain'), draft.tone[ToneDimension.gain].toDouble());
      expect(ampParam(r, 'gain'), ampParam(recipe(sound, SoundRole.rhythm), 'gain'));
    });
  });

  group('Offline und keine Gerätedaten', () {
    test('Katalog, Bericht und Generator enthalten keine Geräte-/Protokollbegriffe und keine fremden Inhalte', () {
      final files = [
        for (final f in Directory('assets/tonevault').listSync(recursive: true).whereType<File>()) f,
        for (final f in Directory('tool/tonevault_catalog').listSync().whereType<File>()) f,
        File('lib/tonevault/tone_vault_report.dart'),
      ];
      for (final f in files) {
        final text = f.readAsStringSync().toLowerCase();
        for (final term in ['sysex', 'wireindex', 'wire index', 'algorithmcode', 'algorithm code', 'qme', 'nativeparam', 'midi byte', 'matribox', 'lyrics:', 'tabs:']) {
          expect(text.contains(term), isFalse, reason: '${f.path}: $term');
        }
      }
      final code = File('lib/tonevault/tone_vault_report.dart').readAsStringSync();
      expect(code.contains('dart:io'), isFalse);
      expect(code.contains('package:http'), isFalse);
    });
  });
}
