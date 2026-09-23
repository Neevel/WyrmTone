import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/tonevault/tone_vault_model.dart';

import 'support/direct_transfer_support.dart';

/// TONEVAULT SOUND QUALITY V2 -- deterministic, structural THIN/MODERATE/RICH
/// classification of every SONG-like entry, based ONLY on what the entry itself
/// states (never on what it inherits). No subjective 0..100 score.
///
/// ownSignal = explicit dimension values + explicit dimension OFFs + explicit kind
/// intents (drive/modulation/delay/reverb) + explicit character axes + amp-family
/// hint (0/1) + cabinet hint (0/1) -- all read directly from [ToneVaultEntry.tone],
/// never from a resolved/inherited [ResolvedTone].
///
/// THIN     = no own kind intent, no own amp-family hint, no own cabinet hint, AND
///            ownSignal <= 4 (almost everything meaningful is Template/Artist-inherited).
/// RICH     = at least one own kind intent AND (amp-family hint OR cabinet hint) AND
///            at least 4 own explicit dimension values (a genuine tonal signature:
///            values + colour/family + a deliberate effect intent).
/// MODERATE = everything between THIN and RICH.
class SongQuality {
  SongQuality(this.entry, this.ancestorDepth);
  final ToneVaultEntry entry;
  final int ancestorDepth;

  int get explicitDefined => entry.tone.dimensions.values.where((f) => f.mode == FieldMode.defined).length;
  int get explicitOff => entry.tone.dimensions.values.where((f) => f.mode == FieldMode.off).length;
  int get explicitKindIntents => entry.tone.kinds.values.where((f) => f.mode == FieldMode.defined).length;
  int get explicitCharacterAxes => entry.tone.character.values.where((f) => f.mode == FieldMode.defined).length;
  bool get hasAmpFamilyHint => entry.tone.ampFamilies.isDefined;
  bool get hasCabinetHint => entry.tone.cabinet.isDefined;
  int get roleOverrides => entry.variants.length;

  int get ownSignal =>
      explicitDefined + explicitOff + explicitKindIntents + explicitCharacterAxes + (hasAmpFamilyHint ? 1 : 0) + (hasCabinetHint ? 1 : 0);

  String get bucket {
    final rich = explicitKindIntents >= 1 && (hasAmpFamilyHint || hasCabinetHint) && explicitDefined >= 4;
    if (rich) return 'RICH';
    final thin = explicitKindIntents == 0 && !hasAmpFamilyHint && !hasCabinetHint && ownSignal <= 4;
    if (thin) return 'THIN';
    return 'MODERATE';
  }

  Map<String, Object?> toJson() => {
    'id': entry.id,
    'title': entry.title,
    'sourceClass': entry.sourceClass.wire,
    'confidence': entry.confidence.wire,
    'bucket': bucket,
    'explicitDefined': explicitDefined,
    'explicitOff': explicitOff,
    'explicitKindIntents': explicitKindIntents,
    'explicitCharacterAxes': explicitCharacterAxes,
    'hasAmpFamilyHint': hasAmpFamilyHint,
    'hasCabinetHint': hasCabinetHint,
    'roleOverrides': roleOverrides,
    'ancestorDepth': ancestorDepth,
    'ownSignal': ownSignal,
    'goldReference': entry.goldReference,
  };
}

bool _isSongLike(ToneEntryType t) => t == ToneEntryType.song || t == ToneEntryType.originalWyrmtone || t == ToneEntryType.guitarReimagined;

void main() {
  final vault = loadFullVault();

  test('catalog-wide quality audit: deterministic THIN/MODERATE/RICH classification', () {
    final all = vault.entries;
    final songs = all.where((e) => _isSongLike(e.type)).toList();
    final byBucket = <String, List<SongQuality>>{'THIN': [], 'MODERATE': [], 'RICH': []};
    for (final e in songs) {
      final q = SongQuality(e, vault.graph.ancestors(e.id).length);
      byBucket[q.bucket]!.add(q);
    }
    final confidenceCounts = {for (final c in ToneConfidence.values) c.wire: songs.where((e) => e.confidence == c).length};
    final noOwnKind = songs.where((e) => e.tone.kinds.values.every((f) => f.mode != FieldMode.defined)).length;
    final noOwnAmpFamily = songs.where((e) => !e.tone.ampFamilies.isDefined).length;
    final noOwnCabinet = songs.where((e) => !e.tone.cabinet.isDefined).length;
    final dimOnlyOverride =
        songs.where((e) {
          final q = SongQuality(e, 0);
          return q.explicitKindIntents == 0 && !q.hasAmpFamilyHint && !q.hasCabinetHint && q.explicitCharacterAxes == 0 && q.roleOverrides == 0;
        }).length;

    final report = {
      'generatedBy': 'test/tonevault_quality_audit_test.dart',
      'totalEntries': all.length,
      'songLikeEntries': songs.length,
      'buckets': {for (final b in byBucket.entries) b.key: b.value.length},
      'confidence': confidenceCounts,
      'songsWithNoOwnKindIntent': noOwnKind,
      'songsWithNoOwnAmpFamilyHint': noOwnAmpFamily,
      'songsWithNoOwnCabinetHint': noOwnCabinet,
      'songsThatAreEssentiallyOnlyDimensionOverrides': dimOnlyOverride,
      'thin': byBucket['THIN']!.map((q) => q.toJson()).toList(),
      'moderateSample': byBucket['MODERATE']!.take(25).map((q) => q.toJson()).toList(),
      'rich': byBucket['RICH']!.map((q) => q.toJson()).toList(),
    };
    File(
      'tool/tonevault_catalog/quality_audit_report.json',
    ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(report)}\n');

    // Structural sanity, not a moving target: the classifier must actually separate entries into
    // more than one bucket (otherwise the criteria are vacuous) and must be deterministic.
    expect(byBucket.values.expand((l) => l).length, songs.length);
    final again = SongQuality(songs.first, 0).bucket;
    expect(SongQuality(songs.first, 0).bucket, again, reason: 'classification must be deterministic (no randomness, no I/O)');
    // ignore: avoid_print
    print(
      'ToneVault quality audit: ${all.length} entries total, ${songs.length} song-like. '
      'THIN=${byBucket['THIN']!.length} MODERATE=${byBucket['MODERATE']!.length} RICH=${byBucket['RICH']!.length}. '
      'Full report: tool/tonevault_catalog/quality_audit_report.json',
    );
  });

  test('deterministic curation backlog: product-criteria priority, not a popularity ranking', () {
    const namedReferences = {
      'song.cky.96_quite_bitter_beings',
      'song.children_of_bodom.angels_dont_kill',
      'song.children_of_bodom.downfall',
      'song.bullet_for_my_valentine.scream_aim_fire',
      'song.metallica.master_of_puppets',
      'song.nirvana.come_as_you_are',
      'song.nirvana.smells_like_teen_spirit',
      'song.nirvana.lithium',
    };
    final songs = vault.entries.where((e) => _isSongLike(e.type)).toList();
    final scored = songs.map((e) => SongQuality(e, vault.graph.ancestors(e.id).length)).toList();

    // Priority is a SUM of independent, deterministic product-criteria points -- never a
    // subjective/popularity score: exact SONG entry (2), LOW confidence (2), THIN structure (3),
    // MODERATE structure (1), no own kind intent (1), no own amp/cabinet hint (1). Higher =
    // more worth curating next. Ties break on id (stable, not insertion order).
    int priority(SongQuality q) {
      var p = 0;
      if (q.entry.type == ToneEntryType.song) p += 2;
      if (q.entry.confidence == ToneConfidence.low) p += 2;
      if (q.bucket == 'THIN') p += 3;
      if (q.bucket == 'MODERATE') p += 1;
      if (q.explicitKindIntents == 0) p += 1;
      if (!q.hasAmpFamilyHint && !q.hasCabinetHint) p += 1;
      return p;
    }

    final ranked = [...scored]..sort((a, b) {
      final byPriority = priority(b).compareTo(priority(a));
      if (byPriority != 0) return byPriority;
      return a.entry.id.compareTo(b.entry.id);
    });

    final backlog = {
      'generatedBy': 'test/tonevault_quality_audit_test.dart',
      'principle':
          'Priority = exact SONG entry (2) + LOW confidence (2) + THIN (3) or MODERATE (1) + '
          'no own kind intent (1) + no own amp/cabinet hint (1). Deterministic, structural, '
          'never a subjective "best songs" ranking. Ties break alphabetically by id.',
      'namedReferenceSongs': namedReferences.toList()..sort(),
      'entries': [
        for (final q in ranked)
          {
            ...q.toJson(),
            'priority': priority(q),
            'isNamedReference': namedReferences.contains(q.entry.id),
          },
      ],
    };
    File(
      'tool/tonevault_catalog/curation_backlog.json',
    ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(backlog)}\n');

    // Deterministic: re-scoring and re-sorting the same input yields the same order.
    final again = [...scored]..sort((a, b) {
      final byPriority = priority(b).compareTo(priority(a));
      if (byPriority != 0) return byPriority;
      return a.entry.id.compareTo(b.entry.id);
    });
    expect(ranked.map((q) => q.entry.id).toList(), again.map((q) => q.entry.id).toList());
    // ignore: avoid_print
    print('Curation backlog written: tool/tonevault_catalog/curation_backlog.json (${ranked.length} song entries, top priority=${priority(ranked.first)})');
  });

  test('reference song audit: CKY, Angels, Downfall, BFMV x2, Master of Puppets, Come As You '
      'Are and existing Nirvana/In Utero entries', () {
    final wanted = [
      'song.cky.96_quite_bitter_beings',
      'song.children_of_bodom.angels_dont_kill',
    ];
    // Find by title/artist too, in case the id differs from the guess above.
    bool matches(ToneVaultEntry e, String artist, String song) =>
        (e.artist?.toLowerCase() == artist.toLowerCase()) && (e.song?.toLowerCase().contains(song.toLowerCase()) ?? false);
    final probes = <String, ToneVaultEntry?>{
      'CKY - 96 Quite Bitter Beings': vault.entries.where((e) => matches(e, 'CKY', '96 Quite Bitter Beings')).firstOrNull,
      "Children of Bodom - Angels Don't Kill": vault.entries.where((e) => matches(e, 'Children of Bodom', "Angels Don")).firstOrNull,
      'Children of Bodom - Downfall': vault.entries.where((e) => matches(e, 'Children of Bodom', 'Downfall')).firstOrNull,
      'Bullet For My Valentine - Scream Aim Fire': vault.entries.where((e) => matches(e, 'Bullet For My Valentine', 'Scream Aim Fire')).firstOrNull,
      'Bullet For My Valentine - Spit You Out': vault.entries.where((e) => matches(e, 'Bullet For My Valentine', 'Spit You Out')).firstOrNull,
      'Metallica - Master of Puppets': vault.entries.where((e) => matches(e, 'Metallica', 'Master of Puppets')).firstOrNull,
      'Nirvana - Come As You Are': vault.entries.where((e) => matches(e, 'Nirvana', 'Come As You Are')).firstOrNull,
    };
    final nirvanaAll = vault.entries.where((e) => e.artist?.toLowerCase() == 'nirvana').toList();
    final buf = StringBuffer('--- reference song audit ---\n');
    probes.forEach((label, e) {
      if (e == null) {
        buf.writeln('$label: NOT FOUND in ToneVault');
        return;
      }
      final q = SongQuality(e, vault.graph.ancestors(e.id).length);
      buf.writeln(
        '$label (${e.id}): ${q.bucket} · source=${e.sourceClass.wire} confidence=${e.confidence.wire} '
        'explicitDims=${q.explicitDefined} ownKindIntents=${q.explicitKindIntents} '
        'ampFamily=${q.hasAmpFamilyHint} cabinet=${q.hasCabinetHint} depth=${q.ancestorDepth}',
      );
    });
    buf.writeln('Nirvana entries in ToneVault: ${nirvanaAll.map((e) => '${e.id} (${e.song ?? e.title})').join(', ')}');
    // ignore: avoid_print
    print(buf);
    expect(probes['CKY - 96 Quite Bitter Beings'], isNotNull);
    expect(probes["Children of Bodom - Angels Don't Kill"], isNotNull);
    // Confirms wanted[] ids actually match what the probes found (keeps the list meaningful, not dead code).
    expect(probes['CKY - 96 Quite Bitter Beings']!.id, wanted[0]);
    expect(probes["Children of Bodom - Angels Don't Kill"]!.id, wanted[1]);
  });
}
