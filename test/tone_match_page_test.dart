import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/controllers/usb_controller.dart';
import 'package:wyrmtone/nam/local_nam_capture.dart';
import 'package:wyrmtone/screens/nam_detail_page.dart';
import 'package:wyrmtone/screens/tone_match_page.dart';
import 'package:wyrmtone/tonematch/tone_analysis_runner.dart';
import 'package:wyrmtone/tonematch/tone_knowledge_provider.dart';
import 'package:wyrmtone/tonematch/tone_match_cache.dart';
import 'package:wyrmtone/tonematch/tone_match_controller.dart';
import 'package:wyrmtone/tonematch/tone_match_models.dart';
import 'package:wyrmtone/ui/wyrm_design.dart';

import 'support/fake_usb_service.dart';
import 'support/sound_flow_support.dart';
import 'support/tone_match_fakes.dart';

/// Words a guitarist should never meet on this page.
const _forbidden = [
  'Inference', 'Feature', 'STFT', 'Embedding', 'Candidate', 'Kandidat', 'AnalysisVersion', 'Saturation', 'Spearman',
  'NAM Core', 'T15', 'Evaluation', 'Composite', 'Cache', 'CV ', '%',
];

String visibleText(WidgetTester tester) => tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? t.textSpan?.toPlainText() ?? '').join(' | ');

void main() {
  late LocalToneKnowledgeProvider provider;
  setUpAll(() async => provider = LocalToneKnowledgeProvider(await loadTestVault()));

  List<LocalNamCapture> library(int n) => [for (var i = 0; i < n; i++) fakeNam('m${i.toString().padLeft(2, '0')}', 'High Gain ${i.toString().padLeft(2, '0')}', make: 'british', tags: ['high gain'])];

  Future<({ToneMatchController c, FakeToneAnalysisRunner runner, FakeUsbService usb})> pump(
    WidgetTester tester, {
    required List<LocalNamCapture> lib,
    FakeToneAnalysisRunner? runner,
    ToneDeviceCapabilities? device,
    VoidCallback? openLibrary,
    double width = 360,
    double scale = 1.3,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final r = runner ?? FakeToneAnalysisRunner();
    final c = ToneMatchController(
      knowledge: () async => provider,
      captures: () => lib,
      coordinator: ToneAnalysisCoordinator(runner: r, cache: InMemoryToneMatchCache()),
      device: () => device,
    );
    addTearDown(c.dispose);
    final service = FakeUsbService();
    final usb = UsbController(service);
    addTearDown(usb.dispose);
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: MaterialApp(theme: WyrmTokens.theme(), home: Scaffold(body: ToneMatchPage(controller: c, usbController: usb, openLibrary: openLibrary))),
      ),
    );
    return (c: c, runner: r, usb: service);
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('tone-match-input')), text);
    await tapVisible(tester, find.byKey(const Key('tone-match-find')));
  }

  testWidgets('real progress while checking ("Sound 2 von 5"), no technical words, then the three best sounds', (tester) async {
    final gate = Completer<void>();
    late FakeToneAnalysisRunner runner;
    runner = FakeToneAnalysisRunner(duringCandidate: (i, id) async {
      if (i == 1) await gate.future;
    });
    await pump(tester, lib: library(8), runner: runner);
    await search(tester, 'Pantera - Heresy');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Passende Sounds werden geprüft'), findsOneWidget);
    expect(find.text('Sound 2 von 5'), findsOneWidget); // one finished, the second is being checked
    expect(find.byKey(const Key('tone-match-cancel')), findsOneWidget);
    for (final w in _forbidden) {
      expect(visibleText(tester), isNot(contains(w)), reason: 'progress shows "$w"');
    }
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Unsere passendsten Sounds'), findsOneWidget);
    for (var rank = 1; rank <= 3; rank++) {
      expect(find.byKey(Key('tone-match-hit-$rank')), findsOneWidget);
    }
    expect(find.byKey(const Key('tone-match-hit-4')), findsNothing); // never more than three
    expect(find.byKey(const Key('tone-match-more')), findsOneWidget); // three more sounds could be checked on request
    expect(runner.startedIds.length, 5); // not eight
  });

  testWidgets('no percentages, no quality labels, no technical words on any state (result, "Warum?", Details)', (tester) async {
    await pump(tester, lib: library(5));
    await search(tester, 'Gary Moore - The Loner');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Details'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('So wurde geprüft'), 300, scrollable: find.byType(Scrollable).first);
    final text = visibleText(tester);
    for (final w in _forbidden) {
      expect(text, isNot(contains(w)), reason: 'result shows "$w"');
    }
    for (final q in ['Sehr passend', 'Passt gut', 'Alternative']) {
      expect(text, isNot(contains(q)), reason: 'unvalidated quality label "$q"');
    }
    expect(text, contains('Warum dieser Sound?'));
    expect(text, contains('keine Prozentzahl'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('"NAM ansehen" opens the existing NAM detail page and transfers nothing', (tester) async {
    final x = await pump(tester, lib: library(5));
    await search(tester, 'Pantera - Heresy');
    await tester.pumpAndSettle();
    expect(x.usb.namCloneSessionInvocations, 0);
    await tapVisible(tester, find.byKey(const Key('tone-match-open-nam-1')));
    await tester.pumpAndSettle();
    expect(find.byType(NamDetailPage), findsOneWidget);
    expect(x.usb.namCloneSessionInvocations, 0);
    expect(x.usb.sentNamCloneFrames, isEmpty);
    expect(x.usb.namCloneSessionCalls, isEmpty);
  });

  testWidgets('Cancel during the check: calm notice, clean start state, a new search works', (tester) async {
    late ToneMatchController ctl;
    final gate = Completer<void>();
    final runner = FakeToneAnalysisRunner(duringCandidate: (i, id) async {
      if (i == 1) await gate.future;
    });
    final x = await pump(tester, lib: library(5), runner: runner);
    ctl = x.c;
    await search(tester, 'Pantera - Heresy');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('tone-match-cancel')));
    await tester.pump();
    expect(find.text('Suche wird abgebrochen …'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tone-match-cancelled')), findsOneWidget);
    expect(find.byKey(const Key('tone-match-results-title')), findsNothing);
    expect(ctl.phase, ToneMatchPhase.idle);
    expect(runner.startedIds.length, 2); // the third never started
    runner.duringCandidate = null;
    await search(tester, 'Pantera - Heresy');
    await tester.pumpAndSettle();
    expect(find.text('Unsere passendsten Sounds'), findsOneWidget);
  });

  testWidgets('0 NAMs: clear message and a way to the library', (tester) async {
    var opened = 0;
    await pump(tester, lib: const [], openLibrary: () => opened++);
    await search(tester, 'Pantera - Heresy');
    await tester.pumpAndSettle();
    expect(find.text('Du hast noch keine NAM-Modelle in deiner Bibliothek.'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('tone-match-open-library')));
    expect(opened, 1);
  });

  testWidgets('device handling: no device -> NAM can be viewed; Matribox -> viewable; DNAfx -> no NAM action and an honest note', (tester) async {
    await pump(tester, lib: library(3));
    await search(tester, 'Pantera - Heresy');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tone-match-open-nam-1')), findsOneWidget);
    expect(find.byKey(const Key('tone-match-device-note')), findsNothing);
  });

  testWidgets('Matribox selected: NAM view offered', (tester) async {
    await pump(tester, lib: library(3), device: const ToneDeviceCapabilities(name: 'Matribox 1', namTransfer: true, presetTransfer: false));
    await search(tester, 'Pantera - Heresy');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tone-match-open-nam-1')), findsOneWidget);
  });

  testWidgets('DNAfx selected: no pretended NAM use', (tester) async {
    await pump(tester, lib: library(3), device: const ToneDeviceCapabilities(name: 'DNAfx GiT Core', namTransfer: false, presetTransfer: false));
    await search(tester, 'Pantera - Heresy');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tone-match-open-nam-1')), findsNothing);
    expect(find.byKey(const Key('tone-match-device-note')), findsOneWidget);
    expect(find.textContaining('kann keine NAM-Modelle verwenden'), findsOneWidget);
    expect(find.byKey(const Key('tone-match-hit-1')), findsOneWidget); // results are still shown
  });

  testWidgets('without the test recording the page says so and labels the order as description-based', (tester) async {
    await pump(tester, lib: library(4), runner: FakeToneAnalysisRunner(available: false));
    await search(tester, 'Pantera - Heresy');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tone-match-no-analysis')), findsOneWidget);
    expect(find.text('Vorauswahl nach Beschreibung'), findsOneWidget);
    expect(find.text('Unsere passendsten Sounds'), findsNothing);
  });

  testWidgets('long song names and 320 dp with large fonts do not overflow', (tester) async {
    await pump(tester, lib: library(5), width: 320, scale: 1.6);
    await search(tester, 'Gary Moore - The Loner und noch ein sehr langer Zusatz im Songnamen zur Probe');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('an imported model with unknown fit says so honestly on its card', (tester) async {
    await pump(tester, lib: [fakeNam('imp', 'Imported.nam', compat: NamCompatibility.unknown)]);
    await search(tester, 'Pantera - Heresy');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tone-match-compat-1')), findsOneWidget);
    expect(find.textContaining('prüft die Detailansicht'), findsOneWidget);
  });
}
