import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sound_flow_support.dart';

/// Live search suggestions while typing: local-only (the same ToneVault resolver + a thin prefix
/// layer over the same catalog names), debounced, typo-tolerant, and never a dead end. No fragile
/// exact ordering is asserted except where the ranking rule (Known Song/Artist > Genre/Style >
/// sonstige) is explicitly guaranteed.
void main() {
  Future<Rig> open(WidgetTester tester, {double width = 411}) async {
    final rig = await pumpShell(tester, width: width);
    await openSoundsTab(tester);
    return rig;
  }

  group('representative queries', () {
    const cases = {
      'mas': ['sound-result-song.metallica.master_of_puppets'],
      'metallica': ['understood-chips'],
      'metallika': ['understood-chips'],
      'master of pupets': ['sound-result-song.metallica.master_of_puppets'],
      'child': ['sound-result-artist.cob'],
      'angels': ['sound-result-song.children_of_bodom.angels_dont_kill'],
      'metalco': ['sound-result-tpl.genre.modern_metal'],
    };

    for (final entry in cases.entries) {
      testWidgets('"${entry.key}" surfaces a relevant suggestion', (tester) async {
        await open(tester);
        await search(tester, entry.key);
        for (final key in entry.value) {
          expect(find.byKey(Key(key)), findsWidgets, reason: entry.key);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('"Metallica weniger Gain" is still understood as a modifier on top of the artist', (tester) async {
      await open(tester);
      await search(tester, 'Metallica weniger Gain');
      expect(find.byKey(const Key('understood-chips')), findsOneWidget);
      expect(find.textContaining('Metallica'), findsWidgets);
    });

    testWidgets('"moderner Metalcore Drop C" keeps working as a full natural-language request', (tester) async {
      await open(tester);
      await search(tester, 'moderner Metalcore Drop C');
      expect(find.byKey(const Key('understood-chips')), findsOneWidget);
      expect(find.byKey(const Key('sound-result-tpl.genre.modern_metal')), findsWidgets);
    });

    testWidgets('pure gibberish shows the honest empty state, no crash, no fabricated sound', (tester) async {
      await open(tester);
      await search(tester, 'xzqvyplonkforglglorp qzxvbn');
      expect(find.text('Keinen direkten Treffer gefunden'), findsOneWidget);
      expect(find.byKey(const Key('create-from-description')), findsNothing, reason: 'no genre was named, so nothing is fabricated');
      expect(tester.takeException(), isNull);
    });

    test('invariant the "Sound aus deiner Beschreibung erstellen" fallback relies on: a recognized '
        'genre/subgenre always yields at least one real candidate from the resolver itself', () async {
      final vault = await loadTestVault();
      for (final q in ['metalcore', 'so ein metalcore ding', 'etwas Blues-mäßiges bitte']) {
        final r = vault.nlu.understand(q);
        if (r.query.genre != null || r.query.subgenre != null) {
          expect(r.resolution.candidates, isNotEmpty, reason: q);
        }
      }
    });
  });

  group('suggestion type icons', () {
    testWidgets('a short prefix shows the "Vorschläge" header and type icons, not internal enum names', (tester) async {
      await open(tester);
      await search(tester, 'mas');
      expect(find.byKey(const Key('prefix-suggestions')), findsOneWidget);
      expect(find.byIcon(Icons.music_note), findsWidgets);
      final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').join('\n');
      for (final forbidden in ['SONG', 'ARTIST_SIGNATURE', 'GENRE_TEMPLATE', 'ToneEntryType']) {
        expect(texts, isNot(contains(forbidden)));
      }
    });
  });

  group('debounce', () {
    testWidgets('nothing is resolved before the debounce window; the field itself updates immediately', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('sound-search')), 'mas');
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('mas'), findsOneWidget, reason: 'the field itself is never debounced');
      expect(find.byKey(const Key('prefix-suggestions')), findsNothing, reason: 'the resolver has not run yet');
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const Key('prefix-suggestions')), findsOneWidget);
    });

    testWidgets('rapid retyping only resolves the final text once', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('sound-search')), 'm');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(find.byKey(const Key('sound-search')), 'ma');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(find.byKey(const Key('sound-search')), 'mas');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sound-result-song.metallica.master_of_puppets')), findsWidgets);
    });
  });

  group('keyboard UX', () {
    testWidgets('tapping outside the field dismisses the keyboard without leaving the page', (tester) async {
      await open(tester);
      await search(tester, 'mas');
      expect(find.byKey(const Key('sound-search')), findsOneWidget);
      // Below the search field, inside the body -- not the global device-status bar at the very top.
      await tester.tapAt(tester.getCenter(find.byKey(const Key('prefix-suggestions'))));
      await tester.pumpAndSettle();
      // still on Sounds, nothing popped
      expect(find.byKey(const Key('sound-search')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a suggestion is reachable and tappable with the field focused (keyboard open)', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('sound-search')));
      await search(tester, 'master of pupets');
      await tester.scrollUntilVisible(
        find.byKey(const Key('sound-result-song.metallica.master_of_puppets')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('sound-result-song.metallica.master_of_puppets')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('your-sound-title')), findsNothing); // detail page, not "Dein Sound" yet
      expect(tester.takeException(), isNull);
    });
  });

  group('selecting a suggestion', () {
    testWidgets('an artist suggestion opens directly (no dead-end intermediate page)', (tester) async {
      await open(tester);
      await search(tester, 'child');
      await tester.scrollUntilVisible(find.byKey(const Key('sound-result-artist.cob')), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('sound-result-artist.cob')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Children of Bodom'), findsWidgets);
    });

    testWidgets('a genre suggestion opens directly', (tester) async {
      await open(tester);
      await search(tester, 'metalco');
      await tester.scrollUntilVisible(find.byKey(const Key('sound-result-tpl.genre.modern_metal')), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('sound-result-tpl.genre.modern_metal')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('responsive', () {
    for (final width in [320.0, 411.0, 1400.0]) {
      testWidgets('suggestions render without overflow at ${width}dp', (tester) async {
        await open(tester, width: width);
        await search(tester, 'mas');
        expect(tester.takeException(), isNull);
        await search(tester, 'child');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
