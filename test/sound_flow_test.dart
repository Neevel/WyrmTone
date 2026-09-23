import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/models/tone_target.dart' show SoundRole;
import 'package:wyrmtone/presets/tone_intent.dart' show ToneBlockRole, ToneOrigin;
import 'package:wyrmtone/presets/tone_recipe_builder.dart';
import 'package:wyrmtone/sounds/sound_labels.dart';
import 'package:wyrmtone/sounds/sound_selection.dart';
import 'package:wyrmtone/tonevault/tone_vault_model.dart';
import 'package:wyrmtone/tonevault/tone_vault_query.dart';

import 'support/recommendation_fakes.dart';
import 'support/sound_flow_support.dart';

void main() {
  group('Sounds-Einstieg', () {
    testWidgets('Startansicht: Suche, Vorschläge, Genres, Entdecken; keine internen Begriffe und kein alter Wizard', (tester) async {
      await pumpShell(tester);
      await openSoundsTab(tester);
      expect(find.text('Was möchtest du spielen?'), findsOneWidget);
      expect(find.byKey(const Key('sound-search')), findsOneWidget);
      expect(find.text('Master of Puppets Rhythmus'), findsOneWidget);
      expect(find.text('Genres'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Entdecken'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Entdecken'), findsOneWidget);
      for (final banned in ['ToneVault', 'Referenz-Sounds', 'Schritt 1 von 7', 'Sound erstellen', 'Wizard', 'Canonical', 'NLU', 'STYLE_INSPIRED']) {
        expect(find.textContaining(banned), findsNothing, reason: banned);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('Vorschlag füllt das Suchfeld und zeigt, was verstanden wurde', (tester) async {
      await pumpShell(tester);
      await openSoundsTab(tester);
      await tester.tap(find.text('80er Hard Rock Lead'));
      await tester.pumpAndSettle();
      final chips = find.descendant(of: find.byKey(const Key('understood-chips')), matching: find.byType(Chip));
      final labels = [for (final c in tester.widgetList<Chip>(chips)) (c.label as Text).data];
      expect(labels, containsAll(['Hard Rock', 'Lead']));
      expect(labels.any((l) => l!.contains('80')), isTrue);
      expect(find.textContaining('confidence', findRichText: true), findsNothing);
      expect(find.textContaining('0.'), findsNothing, reason: 'keine Konfidenzzahlen im normalen UI');
    });

    testWidgets('natürliche Anfrage: erkannte Chips inkl. Wunsch und Stimmung', (tester) async {
      await pumpShell(tester);
      await openSoundsTab(tester);
      await search(tester, 'metallika master of pupets rhythm drop c# etwas weniger gain');
      final chips = find.descendant(of: find.byKey(const Key('understood-chips')), matching: find.byType(Chip));
      final labels = [for (final c in tester.widgetList<Chip>(chips)) (c.label as Text).data];
      expect(labels, containsAll(['Metallica', 'Master of Puppets', 'Rhythmus', 'Drop C#', 'Weniger Gain (etwas)']));
      expect(find.byKey(const Key('sound-result-song.metallica.master_of_puppets')), findsOneWidget);
      expect(find.textContaining('song.metallica'), findsNothing, reason: 'keine technischen IDs');
    });

    testWidgets('mehrdeutig, kein Treffer und unbekannter Artist geben klare Zustände statt Fehler', (tester) async {
      await pumpShell(tester);
      await openSoundsTab(tester);
      await search(tester, 'Metallica');
      expect(find.text('Mehrere Sounds passen. Such dir einen aus:'), findsOneWidget);
      expect(find.byKey(const Key('sound-result-artist.metallica')), findsOneWidget);
      await search(tester, 'xqzvbnm wtfplk');
      expect(find.text('Keinen direkten Treffer gefunden'), findsOneWidget);
      await search(tester, 'Zzyzx Unbekannte Band');
      expect(tester.takeException(), isNull);
      await search(tester, 'richtig viel Reverb');
      expect(find.textContaining('fehlt ein Ausgangssound'), findsOneWidget);
      await search(tester, '');
      expect(find.text('Was möchtest du spielen?'), findsOneWidget);
    });

    testWidgets('Filter engt die Trefferliste ein', (tester) async {
      await pumpShell(tester);
      await openSoundsTab(tester);
      await search(tester, 'thrash');
      expect(find.byKey(const Key('sound-result-artist.anthrax')), findsOneWidget);
      await tapVisible(tester, find.textContaining('Genres & Stile ('));
      expect(find.byKey(const Key('sound-result-tpl.genre.thrash_metal')), findsOneWidget);
      expect(find.byKey(const Key('sound-result-artist.anthrax')), findsNothing);
    });
  });

  group('Sound-Flow ohne alten Wizard (Metallica-Absturz)', () {
    Future<Rig> useSound(WidgetTester tester, String query, String resultId, {double width = 411}) async {
      final rig = await pumpShell(tester, width: width);
      await openSoundsTab(tester);
      await search(tester, query);
      await tapVisible(tester, find.byKey(Key('sound-result-$resultId')));
      expect(find.byKey(const Key('sound-title')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('use-sound')));
      return rig;
    }

    testWidgets('Metallica → verwenden → Entwurf → Dein Sound öffnet ohne Dropdown-Assertion', (tester) async {
      final rig = await useSound(tester, 'Metallica', 'artist.metallica');
      expect(tester.takeException(), isNull);
      expect(rig.controller.offlineDraft, isNotNull);
      expect(rig.controller.offlineDraft!.profile.artist, 'Metallica');
      expect(find.byKey(const Key('your-sound-title')), findsOneWidget);
      expect(find.text('Metallica'), findsWidgets);
      expect(find.byKey(const Key('your-sound-metrics')), findsOneWidget);
      // back on the start page: the sound is offered again and opens the same screen
      await tester.pageBack();
      await tester.pumpAndSettle();
      await search(tester, '');
      expect(find.byKey(const Key('current-sound-card')), findsOneWidget);
      await tester.tap(find.byKey(const Key('current-sound-card')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('your-sound-title')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ein Künstler, den es nur im großen Katalog gibt, durchläuft denselben Flow', (tester) async {
      final rig = await useSound(tester, 'Lorna Shore', 'artist.lorna_shore');
      expect(tester.takeException(), isNull);
      expect(rig.controller.offlineDraft!.profile.artist, 'Lorna Shore');
      expect(find.byKey(const Key('your-sound-title')), findsOneWidget);
    });

    testWidgets('Song aus dem Massenkatalog mit Wunsch und Rolle', (tester) async {
      final rig = await useSound(tester, 'Enter Sandman Rhythmus weniger Gain', 'song.metallica.enter_sandman');
      expect(rig.controller.offlineDraft!.role, SoundRole.rhythm);
      expect(rig.session.current!.modifiers.map((m) => m.modifier), contains(ToneModifier.lessGain));
      expect(find.text('Weniger Gain'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ohne Gitarrenprofil: verständlicher Hinweis, kein Absturz, kein Entwurf', (tester) async {
      final rig = await pumpShell(tester, withGuitar: false);
      await openSoundsTab(tester);
      await search(tester, 'Master of Puppets');
      await tapVisible(tester, find.byKey(const Key('sound-result-song.metallica.master_of_puppets')));
      expect(find.text('Noch keine Gitarre angelegt. Damit der Sound zu deiner Gitarre passt, lege zuerst ein Profil an.'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('use-sound')));
      expect(find.byKey(const Key('sound-notice')), findsOneWidget);
      expect(rig.controller.offlineDraft, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('Anpassen und Herkunft der Wünsche', () {
    testWidgets('Personalisierung: Gitarre, Stimmung inkl. neuer Stimmungen, Variante', (tester) async {
      await pumpShell(tester);
      await openSoundsTab(tester);
      await search(tester, 'Master of Puppets');
      await tapVisible(tester, find.byKey(const Key('sound-result-song.metallica.master_of_puppets')));
      expect(find.text('Testgitarre'), findsWidgets);
      await tapVisible(tester, find.byKey(const ValueKey('tuning-dropC')));
      for (final label in ['C# Standard', 'Drop C#', 'Drop A']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      await tester.tap(find.text('Drop A').last);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('use-sound')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Stimmung und Rolle aus der Anfrage werden übernommen und wirken in der Vorschau', (tester) async {
      final rig = await pumpShell(tester);
      await openSoundsTab(tester);
      await search(tester, 'Master of Puppets Lead Drop A');
      await tapVisible(tester, find.byKey(const Key('sound-result-song.metallica.master_of_puppets')));
      await tapVisible(tester, find.byKey(const Key('use-sound')));
      expect(rig.controller.offlineDraft!.tuning, GuitarTuning.dropA);
      expect(rig.controller.offlineDraft!.role, SoundRole.lead);
      expect(find.text('Drop A'), findsWidgets);
    });

    testWidgets('Schnellanpassung: Stufen, Grenzen und USER_OVERRIDE im Rezept', (tester) async {
      final rig = await pumpShell(tester);
      await openSoundsTab(tester);
      await search(tester, 'Master of Puppets');
      await tapVisible(tester, find.byKey(const Key('sound-result-song.metallica.master_of_puppets')));
      expect(find.text('unverändert'), findsWidgets);
      final less = find.byKey(const Key('adjust-gain-less'));
      await tapVisible(tester, less);
      expect(tester.widget<Text>(find.byKey(const Key('adjust-gain-value'))).data, 'Weniger Gain (etwas)');
      await tester.tap(less);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('adjust-gain-value'))).data, 'Weniger Gain');
      await tester.tap(less);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('adjust-gain-value'))).data, 'Weniger Gain (deutlich)');
      expect(tester.widget<IconButton>(less).onPressed, isNull, reason: 'Stufen sind begrenzt');
      await tapVisible(tester, find.byKey(const Key('adjust-bright-more')));
      await tapVisible(tester, find.byKey(const Key('use-sound')));

      final sel = rig.session.current!;
      expect([for (final m in sel.modifiers) '${m.modifier.wire}/${m.intensity.wire}'], ['LESS_GAIN/STRONG', 'BRIGHTER/SLIGHT']);
      final draft = rig.controller.offlineDraft!;
      final recipe = ToneRecipeBuilder.build(profile: draft.profile, guitar: draft.guitar, tuning: draft.tuning, role: draft.role, finalTone: draft.tone);
      expect(recipe[ToneBlockRole.amp].params['gain']!.origin, ToneOrigin.userOverride);
      expect(recipe[ToneBlockRole.amp].params['gain']!.value, lessThan(60));
      expect(find.byKey(const Key('your-adjustments')), findsOneWidget);
      expect(find.text('Weniger Gain (deutlich)'), findsOneWidget);
      expect(find.text('Heller (etwas)'), findsOneWidget);
    });

    testWidgets('Hinweis, wenn ein Wunsch bei diesem Sound nichts festlegen kann', (tester) async {
      await pumpShell(tester);
      await openSoundsTab(tester);
      await search(tester, 'Sandstorm');
      await tapVisible(tester, find.byKey(const Key('sound-result-reimagined.darude_sandstorm')));
      // an axis whose properties the sound does not define at all is reported, not silently ignored
      final notes = find.byKey(const Key('wish-ignored-note'));
      final before = notes.evaluate().length;
      for (final id in ['bass', 'mids', 'body', 'tight', 'aggression', 'delay', 'reverb', 'era']) {
        await tapVisible(tester, find.byKey(Key('adjust-$id-more')));
      }
      expect(notes.evaluate().length >= before, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Dein Sound: Nachschärfen mit Vorschau, Anwenden und Rückgängig', (tester) async {
      final rig = await pumpShell(tester);
      await openSoundsTab(tester);
      await search(tester, 'Master of Puppets');
      await tapVisible(tester, find.byKey(const Key('sound-result-song.metallica.master_of_puppets')));
      await tapVisible(tester, find.byKey(const Key('use-sound')));
      final original = rig.controller.offlineDraft;
      await tapVisible(tester, find.byKey(const Key('fine-tune')));
      await tapVisible(tester, find.text('Zu schrill'));
      expect(rig.controller.offlinePreview, isNotNull);
      expect(rig.controller.offlineDraft, same(original), reason: 'die Vorschau verändert noch nichts');
      await tapVisible(tester, find.byKey(const Key('offline-apply')));
      expect(rig.controller.canUndoCorrection, isTrue);
      await tapVisible(tester, find.byKey(const Key('offline-undo')));
      expect(rig.controller.offlineDraft, same(original));
      expect(tester.takeException(), isNull);
    });
  });

  group('Speichern, Wiederherstellen, defekte Daten', () {
    test('Auswahl ist strikt serialisierbar; Defektes wird abgelehnt statt zu crashen', () {
      const sel = SoundSelection(
        entryId: 'song.metallica.master_of_puppets',
        tuning: GuitarTuning.dropCSharp,
        variant: ToneVariantKind.lead,
        modifiers: [ToneModifierIntent(ToneModifier.lessGain, ToneIntensity.slight)],
        effects: [ToneEffectIntent(ToneEffectKind.reverb, off: true)],
      );
      final back = SoundSelection.tryDecode(sel.signature)!;
      expect(back.signature, sel.signature);
      for (final bad in [null, '', 'nope', '[]', '{}', '{"version":1}', '{"version":2,"entry":"a","tuning":"dropC"}', '{"version":1,"entry":"a","tuning":"nonsense"}',
        '{"version":1,"entry":"a","tuning":"dropC","modifiers":[{"modifier":"X","intensity":"NORMAL"}]}',
        '{"version":1,"entry":"a","tuning":"dropC","variant":"BOGUS"}']) {
        expect(SoundSelection.tryDecode(bad), isNull, reason: '$bad');
      }
    });

    testWidgets('gespeicherter Sound überlebt einen App-Neustart und lässt sich öffnen', (tester) async {
      final store = MemoryStringStore();
      final first = await pumpShell(tester, store: store);
      await openSoundsTab(tester);
      await search(tester, 'Master of Puppets');
      await tapVisible(tester, find.byKey(const Key('sound-result-song.metallica.master_of_puppets')));
      await tapVisible(tester, find.byKey(const Key('adjust-mids-more')));
      await tapVisible(tester, find.byKey(const Key('use-sound')));
      final saved = first.session.current!.signature;
      expect(await SoundSelectionRepository(store).loadCurrent().then((s) => s!.signature), saved);

      // "restart": a new controller (no draft) and a new session on the same store
      await tester.pumpWidget(const SizedBox());
      final controller = await flowController(store: store);
      final session = flowSession(controller, store);
      await pumpShell(tester, store: store, session: session, controller: controller);
      expect(controller.offlineDraft, isNull);
      expect(session.current!.signature, saved);
      await openSoundsTab(tester);
      expect(find.byKey(const Key('current-sound-card')), findsOneWidget);
      await tester.tap(find.byKey(const Key('current-sound-card')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('your-sound-title')), findsOneWidget);
      expect(controller.offlineDraft, isNotNull);
      expect(find.text('Mehr Mitten (etwas)', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('beschädigter gespeicherter Sound wird ignoriert; unbekannter Sound bietet sicheres Verwerfen', (tester) async {
      final damaged = MemoryStringStore();
      await damaged.write(SoundSelectionRepository.currentKey, '{"version":1,"entry":');
      await damaged.write(SoundSelectionRepository.recentKey, 'kaputt');
      final rig = await pumpShell(tester, store: damaged);
      await openSoundsTab(tester);
      expect(rig.session.current, isNull);
      expect(find.byKey(const Key('current-sound-card')), findsNothing);
      expect(find.text('Was möchtest du spielen?'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      final unknown = MemoryStringStore();
      await unknown.write(
        SoundSelectionRepository.currentKey,
        const SoundSelection(entryId: 'song.gibt_es.nicht', tuning: GuitarTuning.dropC).signature,
      );
      final rig2 = await pumpShell(tester, store: unknown);
      await openSoundsTab(tester);
      expect(find.byKey(const Key('restore-failed')), findsOneWidget);
      expect(find.text('Dein gespeicherter Sound ist nicht mehr verfügbar'), findsOneWidget);
      await tester.tap(find.text('Verwerfen'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('restore-failed')), findsNothing);
      expect(rig2.session.current, isNull);
      expect(await SoundSelectionRepository(unknown).loadCurrent(), isNull);
    });

    testWidgets('Zuletzt verwendet erscheint auf der Startansicht', (tester) async {
      final store = MemoryStringStore();
      await pumpShell(tester, store: store);
      await openSoundsTab(tester);
      await search(tester, 'Enter Sandman');
      await tapVisible(tester, find.byKey(const Key('sound-result-song.metallica.enter_sandman')));
      await tapVisible(tester, find.byKey(const Key('use-sound')));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await search(tester, 'Smells Like Teen Spirit');
      await tapVisible(tester, find.byKey(const Key('sound-result-song.nirvana.smells_like_teen_spirit')));
      await tapVisible(tester, find.byKey(const Key('use-sound')));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await search(tester, '');
      expect(find.text('Zuletzt verwendet'), findsOneWidget);
      expect(find.byKey(const Key('recent-song.metallica.enter_sandman')), findsOneWidget);
    });
  });

  group('Navigation, Startseite, Gerät bleibt getrennt', () {
    testWidgets('fünf Ziele, Sound finden führt zur Suche, kein toter Eintrag', (tester) async {
      await pumpShell(tester);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(find.byKey(const Key('dashboard-create')), findsOneWidget);
      expect(find.text('Sound finden'), findsWidgets);
      await tester.tap(find.byKey(const Key('dashboard-create')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sound-search')), findsOneWidget);
      for (final tab in ['Bibliothek', 'Profil', 'Start']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
    });

    testWidgets('Startseite zeigt den aktuellen Sound und öffnet ihn', (tester) async {
      final rig = await pumpShell(tester);
      await rig.session.use(const SoundSelection(entryId: 'song.metallica.master_of_puppets', tuning: GuitarTuning.dropC, variant: ToneVariantKind.rhythm));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('dashboard-current-sound')), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('dashboard-current-sound')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('your-sound-title')), findsOneWidget);
    });

    testWidgets('Geräteaktion bleibt getrennt und sendet nichts von selbst', (tester) async {
      final rig = await pumpShell(tester);
      await rig.session.use(const SoundSelection(entryId: 'song.metallica.master_of_puppets', tuning: GuitarTuning.dropC, variant: ToneVariantKind.rhythm));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('dashboard-current-sound')), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('dashboard-current-sound')));
      await tester.pumpAndSettle();
      expect(find.text('Dieser Sound ist auf deinem Gerät nur vorbereitet und noch nicht übertragen.'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Gerät').last, 300, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('Sound erstellen ist nicht dasselbe wie senden'), findsOneWidget);
      expect(rig.usbService.openCalls, 0);
      expect(rig.usbService.midiOpenCalls, 0);
    });
  });

  group('Responsive und Barrierefreiheit', () {
    for (final size in const [Size(320, 640), Size(411, 900), Size(1000, 900), Size(1400, 900)]) {
      for (final scale in const [1.0, 1.6]) {
        testWidgets('Flow ohne Überlauf bei ${size.width.toInt()} dp, Textskalierung $scale', (tester) async {
          final rig = await pumpShell(tester, width: size.width, height: size.height, textScale: scale);
          await openSoundsTab(tester);
          expect(tester.takeException(), isNull);
          await search(tester, 'Metallica Master of Puppets Rhythmus drop c# etwas weniger gain mit chorus');
          expect(tester.takeException(), isNull);
          if (size.width >= 1000) {
            final card = tester.getSize(find.byKey(const Key('sound-result-song.metallica.master_of_puppets')));
            expect(card.width, lessThanOrEqualTo(720), reason: 'Karten werden auf Faltgeräten nicht endlos breit');
          }
          await tapVisible(tester, find.byKey(const Key('sound-result-song.metallica.master_of_puppets')));
          expect(tester.takeException(), isNull);
          await tapVisible(tester, find.byKey(const Key('use-sound')));
          expect(tester.takeException(), isNull);
          expect(rig.controller.offlineDraft, isNotNull);
          await tester.scrollUntilVisible(find.byKey(const Key('sound-origin')), 400, scrollable: find.byType(Scrollable).first);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('Touch-Ziele, Beschriftungen und Text neben Farbe', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpShell(tester);
      await openSoundsTab(tester);
      await search(tester, 'Master of Puppets');
      await tapVisible(tester, find.byKey(const Key('sound-result-song.metallica.master_of_puppets')));
      for (final key in ['adjust-gain-less', 'adjust-gain-more', 'use-sound']) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(size.width, greaterThanOrEqualTo(48), reason: key);
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
      }
      expect(tester.getSemantics(find.byKey(const Key('adjust-gain-less'))).tooltip, 'Weniger Gain', reason: 'Anpassungsknöpfe sind beschriftet');
      expect(tester.getSemantics(find.byKey(const Key('adjust-gain-more'))).tooltip, 'Mehr Gain');
      expect(find.bySemanticsLabel(RegExp(r'Gain: (niedrig|mittel|hoch|sehr hoch|sehr niedrig)')), findsOneWidget, reason: 'Pegel steht als Text, nicht nur als Balken');
      expect(tester.getSemantics(find.byKey(const Key('use-sound'))).label, contains('Sound verwenden'));
      handle.dispose();
    });
  });

  group('Texte und Labels der Sound-Oberfläche', () {
    test('Texte der Sound-Oberfläche enthalten keine internen Begriffe', () {
      final literal = RegExp(r"'((?:[^'\\]|\\.)*)'");
      for (final path in [
        'lib/screens/sounds_page.dart',
        'lib/screens/sound_detail_page.dart',
        'lib/screens/your_sound_page.dart',
        'lib/screens/dashboard_page.dart',
        'lib/sounds/sound_labels.dart',
        'lib/sounds/sound_session.dart',
      ]) {
        for (final m in literal.allMatches(File(path).readAsStringSync())) {
          final text = m.group(1)!;
          for (final banned in ['ToneVault', 'Canonical', 'NLU', 'Resolver', 'TargetPreset', 'Evidence', 'STYLE_INSPIRED', 'Wizard', 'Legacy']) {
            expect(text.contains(banned), isFalse, reason: '$path: "$text"');
          }
        }
      }
    });

    test('Quellenlabels sind nutzerfreundlich', () {
      for (final c in SourceClass.values) {
        final label = sourceLabel(c);
        expect(label, isNot(c.wire));
        expect(label, isNot(equals(label.toUpperCase())));
        expect(label.contains('_'), isFalse);
      }
      expect(sourceLabel(SourceClass.styleInspired), 'Inspiriert');
      expect(sourceLabel(SourceClass.wyrmOriginal), 'Wyrm Original');
    });
  });
}
