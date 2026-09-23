import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/tonevault/tone_nlu.dart';
import 'package:wyrmtone/tonevault/tone_vault.dart';
import 'package:wyrmtone/tonevault/tone_vault_search.dart';

/// Synthetic entries (load only, no music data) and the real catalog: index build and query times.
const _genres = ['thrash_metal', 'grunge', 'punk_rock', 'heavy_metal', 'blues_rock'];
const _syl = ['ka', 'lor', 'mi', 'zan', 'tor', 'vex', 'bru', 'fal', 'dun', 'sek'];
String _word(int n) => '${_syl[n % 10]}${_syl[(n ~/ 10) % 10]}${_syl[(n ~/ 100) % 10]}${_syl[(n ~/ 1000) % 10]}${_syl[(n ~/ 10000) % 10]}';

String _read(String p) => File(p).readAsStringSync();

ToneVault _synthetic(int n) {
  final entries = <Map<String, Object?>>[];
  for (var i = 0; i < n; i++) {
    final artist = 'Band ${_word(i)}';
    final isArtist = i % 2 == 0;
    entries.add({
      'id': isArtist ? 'artist.syn_$i' : 'song.syn_$i',
      'schemaVersion': 1,
      'type': isArtist ? 'ARTIST_SIGNATURE' : 'SONG',
      'title': isArtist ? artist : 'Song ${_word(i + 7)} $i',
      'source': {'classification': 'AI_GENERATED'},
      'confidence': 'LOW',
      'artist': artist,
      if (!isArtist) 'song': 'Song ${_word(i + 7)} $i',
      'genres': [_genres[i % _genres.length]],
      'eras': ['${1960 + (i % 6) * 10}s'],
      'roles': ['RHYTHM'],
      'tone': {
        'dimensions': {'gain': i % 100},
      },
    });
  }
  return ToneVault.fromTexts(
    taxonomy: _read('assets/tonevault/taxonomy.json'),
    vocabulary: _read('assets/tonevault/vocabulary.json'),
    nlu: _read('assets/tonevault/nlu.json'),
    packs: [
      jsonEncode({
        'pack': {
          'id': 'syn',
          'name': 'syn',
          'version': 1,
          'schemaVersion': 1,
          'license': {'name': 'synthetic'},
        },
        'entries': entries,
      }),
    ],
  );
}

int _ms(void Function() f) {
  final sw = Stopwatch()..start();
  f();
  return sw.elapsedMilliseconds;
}

void main() {
  for (final n in [5000, 10000]) {
    test('$n synthetische Einträge: Index, Suche, Fuzzy und NLU bleiben interaktiv', () {
      final build = Stopwatch()..start();
      final vault = _synthetic(n);
      final buildMs = build.elapsedMilliseconds;
      expect(vault.entries.length, n);
      // ignore: avoid_print
      print('$n import+index: $buildMs ms');
      expect(buildMs, lessThan(30000));

      final a = n ~/ 2 * 2 - 2; // last artist entry
      final s = a + 1; // its song entry
      String typo(String w) => w.replaceFirst(w.substring(4, 5), 'x');
      final queries = <String, String>{
        'exact artist': 'Band ${_word(a)}',
        'exact song': 'Song ${_word(s + 7)} $s',
        'fuzzy artist': 'Band ${typo(_word(a))}',
        'fuzzy song': 'Song ${typo(_word(s + 7))} $s',
        'artist+song+role': 'Band ${_word(a)} Song ${_word(s + 7)} $s rhythm',
        'genre': 'thrash metal',
        'era+genre': '80er thrash metal',
        'NLU combined': 'Band ${_word(a)} Rhythmus Drop C etwas weniger Gain ohne Reverb',
        'NLU typo+genre': 'moderner Thrash Metal Sound in Drop C mit viel Delay',
      };
      queries.forEach((label, text) {
        late ToneNluResult r;
        final ms = _ms(() => r = vault.nlu.understand(text));
        // ignore: avoid_print
        print('$n $label "$text": $ms ms, ${r.resolution.kind.name}, ${r.resolution.candidates.length}');
        expect(ms, lessThan(label.startsWith('NLU') ? 200 : 200), reason: label);
      });
      expect(vault.resolve('Band ${_word(a)}').primary?.entry.id, 'artist.syn_$a');
      expect(vault.resolve('Band ${typo(_word(a))}').primary?.entry.id, 'artist.syn_$a');
      expect(vault.resolve('Song ${_word(s + 7)} $s').kind, isNot(ResolutionKind.none));
    });
  }

  test('realer Massenkatalog: Import und typische Anfragen', () {
    final manifest = JsonManifest.parse(_read('assets/tonevault/manifest.json'));
    late ToneVault vault;
    final buildMs = _ms(
      () => vault = ToneVault.fromTexts(
        taxonomy: _read('assets/tonevault/taxonomy.json'),
        vocabulary: _read('assets/tonevault/vocabulary.json'),
        packs: [for (final p in manifest.packs) _read('assets/tonevault/$p')],
        nlu: _read('assets/tonevault/${manifest.nlu}'),
      ),
    );
    // ignore: avoid_print
    print('real catalog (${vault.entries.length} entries) import+index: $buildMs ms');
    expect(buildMs, lessThan(10000));
    const queries = {
      'exact artist': 'Metallica',
      'exact song': 'Enter Sandman',
      'fuzzy artist': 'metalica',
      'fuzzy song': 'master of pupets',
      'artist+song+role': 'Metallica Master of Puppets Rhythmus',
      'genre': 'thrash metal',
      'era+genre': '80er Hard Rock',
      'reimagined': 'Sandstorm auf Gitarre',
      'NLU combined': 'metallika master of pupets rhythm drop c# weniger gain ohne reverb',
      'NLU descriptive': 'fetter moderner Metal Sound in Drop A mit etwas Delay',
    };
    queries.forEach((label, text) {
      final ms = _ms(() => vault.nlu.understand(text));
      // ignore: avoid_print
      print('real $label "$text": $ms ms');
      expect(ms, lessThan(100), reason: label);
    });
  });
}
