/// Catalog statistics, genre coverage and duplicate/collision analysis of a ToneVault.
///
/// Pure analysis: nothing is changed or deleted. Legitimate similarity (two thrash acts that share a
/// template) is REPORTED, never removed automatically. The result is a JSON-friendly map.
library;

import '../models/tone_target.dart' show ToneDimension;
import 'tone_vault.dart';
import 'tone_vault_composer.dart';
import 'tone_vault_model.dart';
import 'tone_vault_text.dart';

abstract final class ToneVaultCatalogReport {
  /// Inheritance chains longer than this are reported as deep.
  static const deepChainLength = 6;

  /// Two artists whose resolved dimensions differ by at most this many points in total are "near identical".
  static const nearIdenticalDistance = 6;

  static Map<String, Object?> build(ToneVault vault) => {
    'stats': stats(vault),
    'coverage': coverage(vault),
    'duplicates': duplicates(vault),
  };

  static Map<String, int> _count<T>(Iterable<T> items, String Function(T) key) {
    final out = <String, int>{};
    for (final i in items) {
      out.update(key(i), (v) => v + 1, ifAbsent: () => 1);
    }
    return Map.fromEntries(out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  static Map<String, Object?> stats(ToneVault vault) {
    final entries = vault.entries;
    final index = vault.index;
    var declaredVariants = 0, explicitVariantLayers = 0, resolvedPairs = 0;
    final depth = <int, int>{};
    for (final e in entries) {
      final base = vault.composer.resolve(e.id);
      depth.update(base.chain.length, (v) => v + 1, ifAbsent: () => 1);
      declaredVariants += e.roles.length;
      for (final role in e.roles) {
        final r = vault.composer.resolve(e.id, variant: role);
        resolvedPairs++;
        if (r.variantLevels.isNotEmpty) explicitVariantLayers++;
      }
    }
    final genres = <String>{for (final e in entries) ...[...e.genres, ...e.subgenres]};
    return {
      'packs': [
        for (final p in vault.packs)
          {
            'id': p.id,
            'title': p.name,
            'version': p.version,
            'entries': p.entries.length,
            'declaredEntryCount': p.entryCount,
            'sourceClassification': p.sourceClassification?.wire,
            'license': p.license.name,
          },
      ],
      'entriesTotal': entries.length,
      'byType': _count(entries, (e) => e.type.wire),
      'artists': entries.where((e) => e.type == ToneEntryType.artistSignature).length,
      'songs': entries.where((e) => e.type == ToneEntryType.song).length,
      'albums': entries.where((e) => e.type == ToneEntryType.albumSignature).length,
      'eraSignatures': entries.where((e) => e.type == ToneEntryType.eraSignature).length,
      'templates': entries.where((e) => e.type.isTemplate).length,
      'guitarReimagined': entries.where((e) => e.type == ToneEntryType.guitarReimagined).length,
      'wyrmOriginals': entries.where((e) => e.type == ToneEntryType.originalWyrmtone).length,
      'explicitVariants': entries.fold<int>(0, (a, e) => a + e.variants.length),
      'declaredRoleVariants': declaredVariants,
      'resolvableVariants': resolvedPairs,
      'variantsWithOwnOverrideInChain': explicitVariantLayers,
      'genresUsed': genres.length,
      'sourceClassification': _count(entries, (e) => e.sourceClass.wire),
      'confidence': _count(entries, (e) => e.confidence.wire),
      'inheritanceDepth': {for (final k in (depth.keys.toList()..sort())) '$k': depth[k]},
      'aliases': {
        'artist': entries.fold<int>(0, (a, e) => a + e.artistAliases.length),
        'song': entries.fold<int>(0, (a, e) => a + e.songAliases.length),
        'album': entries.fold<int>(0, (a, e) => a + e.albumAliases.length),
        'search': entries.fold<int>(0, (a, e) => a + e.searchAliases.length),
      },
      'searchableTerms': {
        'phrases': {
          'artist': index.artists.exact.length + index.artists.alias.length,
          'song': index.songs.exact.length + index.songs.alias.length,
          'album': index.albums.exact.length + index.albums.alias.length,
          'title': index.titles.exact.length + index.titles.alias.length,
          'tag': index.tags.exact.length,
        },
        'distinctTokens': index.tokenFreq.length,
      },
    };
  }

  /// The genres an entry answers for: its own, else (songs/albums/eras) those of its nearest ancestor with genres.
  static Set<String> _effectiveGenres(ToneVault vault, ToneVaultEntry e) {
    if (e.genres.isNotEmpty || e.subgenres.isNotEmpty) return {...e.genres, ...e.subgenres};
    for (final id in vault.graph.ancestors(e.id).reversed) {
      final a = vault.graph.byId[id]!;
      if (a.id != e.id && (a.genres.isNotEmpty || a.subgenres.isNotEmpty)) return {...a.genres, ...a.subgenres};
    }
    return const {};
  }

  static Map<String, Object?> coverage(ToneVault vault) {
    final rows = <String, Object?>{};
    final weak = <String>[];
    for (final g in vault.taxonomy.genres.values) {
      final ids = {g.id, ...vault.taxonomy.withDescendants(g.id)};
      final of = [
        for (final e in vault.entries)
          if (_effectiveGenres(vault, e).any(ids.contains)) e,
      ];
      final direct = [
        for (final e in vault.entries)
          if (_effectiveGenres(vault, e).contains(g.id)) e,
      ];
      final template = vault.entries.any((e) => e.type.isTemplate && e.genres.any(ids.contains));
      final artists = of.where((e) => e.type == ToneEntryType.artistSignature).length;
      final songs = of.where((e) => e.type == ToneEntryType.song).length;
      final variants = of.fold<int>(0, (a, e) => a + e.roles.length);
      final eras = <String>{
        for (final e in of) ...{?e.era, ...e.eras},
      }.toList()..sort();
      final isRoot = g.parent == null;
      final problems = [
        if (!template && !isRoot) 'no-template',
        if (!isRoot && artists < 3 && !g.id.endsWith('_inspired')) 'few-artists',
        if (!isRoot && eras.length < 2 && artists >= 3) 'thin-era-coverage',
      ];
      if (problems.isNotEmpty && direct.isNotEmpty || (!isRoot && of.isEmpty)) weak.add('${g.id}: ${problems.isEmpty ? 'empty' : problems.join(', ')}');
      rows[g.id] = {
        'root': isRoot,
        'template': template,
        'entries': of.length,
        'artists': artists,
        'songs': songs,
        'variants': variants,
        'eras': eras,
        'weak': problems,
      };
    }
    weak.sort();
    return {'genres': rows, 'weakAreas': weak};
  }

  static String _definitionKey(ResolvedTone r) {
    final dims = r.dimensions.entries.toList()..sort((a, b) => a.key.index.compareTo(b.key.index));
    final kinds = r.kinds.entries.toList()..sort((a, b) => a.key.index.compareTo(b.key.index));
    final char = r.character.entries.toList()..sort((a, b) => a.key.index.compareTo(b.key.index));
    return [
      dims.map((e) => '${e.key.name}=${e.value}').join(','),
      kinds.map((e) => '${e.key.name}=${e.value}').join(','),
      char.map((e) => '${e.key.name}=${e.value}').join(','),
      (r.ampFamilies ?? const []).join('+'),
      r.cabinet ?? '',
    ].join('|');
  }

  static Map<String, Object?> duplicates(ToneVault vault) {
    final entries = vault.entries;
    final resolved = {for (final e in entries) e.id: vault.composer.resolve(e.id)};

    // identical complete definitions (per entry type: a template and an artist that inherit it entirely are normal)
    final byKey = <String, List<String>>{};
    for (final e in entries) {
      byKey.putIfAbsent('${e.type.wire}|${_definitionKey(resolved[e.id]!)}', () => []).add(e.id);
    }
    final identical = [
      for (final g in byKey.values)
        if (g.length > 1) g..sort(),
    ]..sort((a, b) => a.first.compareTo(b.first));

    // near identical artist signatures
    final artists = entries.where((e) => e.type == ToneEntryType.artistSignature).toList();
    final near = <List<Object>>[];
    for (var i = 0; i < artists.length; i++) {
      final a = resolved[artists[i].id]!.dimensions;
      for (var j = i + 1; j < artists.length; j++) {
        final b = resolved[artists[j].id]!.dimensions;
        var d = 0;
        for (final k in ToneDimension.values) {
          d += ((a[k] ?? 0) - (b[k] ?? 0)).abs();
          if (d > nearIdenticalDistance) break;
        }
        if (d <= nearIdenticalDistance) near.add([artists[i].id, artists[j].id, d]);
      }
    }

    // names / aliases
    final artistKeys = <String, Set<String>>{}; // normalized -> distinct artist names
    final songKeys = <String, Set<String>>{}; // normalized title -> "artist – song"
    final albumKeys = <String, Set<String>>{};
    void add(Map<String, Set<String>> m, String text, String owner) {
      final k = ToneText.normalize(text);
      if (k.isNotEmpty) m.putIfAbsent(k, () => {}).add(owner);
    }

    for (final e in entries) {
      if (e.artist != null) {
        add(artistKeys, e.artist!, e.artist!);
        for (final a in e.artistAliases) {
          add(artistKeys, a, e.artist!);
        }
      }
      if (e.song != null) {
        add(songKeys, e.song!, '${e.artist ?? '-'} – ${e.song}');
        for (final a in e.songAliases) {
          add(songKeys, a, '${e.artist ?? '-'} – ${e.song}');
        }
      }
      if (e.album != null) {
        add(albumKeys, e.album!, '${e.artist ?? '-'} – ${e.album}');
        for (final a in e.albumAliases) {
          add(albumKeys, a, '${e.artist ?? '-'} – ${e.album}');
        }
      }
    }
    Map<String, List<String>> collisions(Map<String, Set<String>> m) => {
      for (final k in (m.keys.where((k) => m[k]!.length > 1).toList()..sort())) k: (m[k]!.toList()..sort()),
    };
    final artistAliasCollisions = collisions(artistKeys);
    final songTitleCollisions = collisions(songKeys);
    final albumCollisions = collisions(albumKeys);
    final crossKind = <String, List<String>>{};
    for (final k in artistKeys.keys) {
      final kinds = [
        'artist',
        if (songKeys.containsKey(k)) 'song',
        if (albumKeys.containsKey(k)) 'album',
      ];
      if (kinds.length > 1) crossKind[k] = kinds;
    }

    // structure
    final childCount = <String, int>{};
    for (final e in entries) {
      for (final p in e.parents) {
        childCount.update(p, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    final parentsWithoutChildren = [
      for (final e in entries)
        // artists without songs are normal (an artist signature is a complete entry); templates/eras/albums nobody uses are not
        if ((e.type.isTemplate || e.type == ToneEntryType.eraSignature || e.type == ToneEntryType.albumSignature) && !childCount.containsKey(e.id))
          e.id,
    ]..sort();
    final deadTemplates = [
      for (final e in entries)
        if (e.type.isTemplate && !childCount.containsKey(e.id) && !entries.any((o) => o.type != ToneEntryType.genreTemplate && o.parents.contains(e.id)))
          e.id,
    ]..sort();
    final deep = [
      for (final e in entries)
        if (resolved[e.id]!.chain.length > deepChainLength) e.id,
    ]..sort();

    // redundant overrides: an explicitly defined value that already equals what the parent chain gives
    final redundant = <String, List<String>>{};
    for (final e in entries) {
      if (e.parents.isEmpty) continue;
      final inherited = vault.composer.resolve(e.id, includeSelf: false);
      final same = <String>[];
      e.tone.dimensions.forEach((d, field) {
        if (field.mode == FieldMode.defined && inherited.dimensions[d] == field.value) same.add(d.name);
      });
      if (same.isNotEmpty) redundant[e.id] = same..sort();
    }

    return {
      'identicalDefinitions': identical,
      'nearIdenticalArtists': [
        for (final n in near) {'a': n[0], 'b': n[1], 'distance': n[2]},
      ],
      'artistAliasCollisions': artistAliasCollisions,
      'songTitleCollisions': songTitleCollisions,
      'albumTitleCollisions': albumCollisions,
      'crossKindCollisions': crossKind,
      'parentsWithoutChildren': parentsWithoutChildren,
      'deadTemplates': deadTemplates,
      'deepInheritance': deep,
      'redundantOverrides': redundant,
    };
  }
}
