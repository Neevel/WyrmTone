import 'package:wyrmtone/controllers/recommendation_controller.dart';
import 'package:wyrmtone/controllers/tone3000_controller.dart';
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/screens/ir_library_page.dart';
import 'package:wyrmtone/screens/recommendation_page.dart';
import 'package:wyrmtone/services/local_persistence.dart';
import 'package:wyrmtone/tone3000/local_ir_repository.dart';
import 'package:wyrmtone/tone3000/tone3000_config.dart';
import 'package:wyrmtone/tone3000/tone3000_download_service.dart';
import 'package:wyrmtone/tone3000/tone3000_http.dart';
import 'package:wyrmtone/tone3000/tone3000_models.dart';
import 'package:wyrmtone/tone3000/tone3000_oauth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recommendation_fakes.dart';
import 'support/tone3000_fakes.dart';

void main() {
  testWidgets('missing client key has a visible configuration state', (
    tester,
  ) async {
    final recommendation = _recommendationController();
    final tone3000 = _toneController(clientId: '');
    addTearDown(recommendation.dispose);
    addTearDown(tone3000.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: IrLibraryPage(controller: recommendation, tone3000: tone3000),
      ),
    );

    expect(find.text('TONE3000'), findsOneWidget);
    expect(find.byKey(const Key('tone3000-missing-config')), findsOneWidget);
    expect(find.textContaining('TONE3000_CLIENT_ID'), findsOneWidget);
  });

  testWidgets('selected IR models render with attribution and one download', (
    tester,
  ) async {
    final recommendation = _recommendationController();
    final tone3000 = _toneController(clientId: 'publishable-test')
      ..user = const Tone3000User(id: 1, username: 'Marcel')
      ..selection = Tone3000Selection(tone: _tone, models: [_model]);
    addTearDown(recommendation.dispose);
    addTearDown(tone3000.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: IrLibraryPage(controller: recommendation, tone3000: tone3000),
      ),
    );

    expect(find.text('Angemeldet als Marcel'), findsOneWidget);
    expect(find.text('IR Collection'), findsOneWidget);
    expect(find.textContaining('Creator: Creator Name'), findsOneWidget);
    expect(find.byKey(const Key('tone3000-download-10')), findsOneWidget);
    expect(find.byKey(const Key('tone3000-close-selection')), findsOneWidget);
    expect(find.textContaining('Alle herunterladen'), findsNothing);

    await tester.tap(find.byKey(const Key('tone3000-close-selection')));
    await tester.pump();
    expect(find.text('IR Collection'), findsNothing);
  });

  testWidgets('recommendation without a local IR opens TONE3000 selection', (
    tester,
  ) async {
    final recommendation = _recommendationController();
    await recommendation.saveProfile(_profile);
    final browser = FakeTone3000Browser();
    final tone3000 = _toneController(
      clientId: 'publishable-test',
      browser: browser,
    );
    addTearDown(recommendation.dispose);
    addTearDown(tone3000.dispose);
    addTearDown(browser.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RecommendationPage(
          controller: recommendation,
          tone3000: tone3000,
        ),
      ),
    );
    final browse = find.byKey(const Key('recommendation-tone3000-browse'));
    await tester.scrollUntilVisible(browse, 300);
    await tester.tap(browse);
    await tester.pump();

    expect(browser.opened, hasLength(1));
    expect(browser.opened.single.queryParameters['prompt'], 'select_tone');
    expect(browser.opened.single.queryParameters['format'], 'ir');
  });
}

RecommendationController _recommendationController() {
  final store = MemoryStringStore();
  return RecommendationController(
    profileRepository: ProfileRepository(store),
    irRepository: IrCatalogRepository(store),
    filePicker: FakeIrFilePicker(),
  );
}

Tone3000Controller _toneController({
  required String clientId,
  FakeTone3000Browser? browser,
}) {
  final config = Tone3000Config(clientId: clientId);
  final secureStore = MemoryTone3000SecureStore();
  final selectedBrowser = browser ?? FakeTone3000Browser();
  final http = FakeTone3000HttpTransport();
  DateTime clock() => DateTime.utc(2026, 9, 8, 12);
  final tokens = Tone3000TokenClient(
    config: config,
    transport: http,
    clock: clock,
  );
  final session = Tone3000SessionManager(
    store: secureStore,
    tokenClient: tokens,
    clock: clock,
  );
  return Tone3000Controller(
    config: config,
    browser: selectedBrowser,
    oauth: Tone3000OAuthService(
      config: config,
      store: secureStore,
      browser: selectedBrowser,
      tokenClient: tokens,
      clock: clock,
    ),
    sessionManager: session,
    api: FakeTone3000Api(),
    downloader: const _UnusedDownloader(),
    localRepository: LocalIrRepository(MemoryStringStore()),
  );
}

class _UnusedDownloader implements Tone3000Downloader {
  const _UnusedDownloader();

  @override
  Future<Tone3000DownloadResult> download({
    required Tone3000Tone tone,
    required Tone3000Model model,
    required String accessToken,
    required bool replaceExisting,
    required Tone3000CancellationToken cancellationToken,
    required void Function(int received, int? total) onProgress,
  }) => throw UnsupportedError('Not used by this widget test.');
}

final _tone = Tone3000Tone(
  id: 83759,
  title: 'IR Collection',
  creatorName: 'Creator Name',
  license: 'cc-by',
  format: 'ir',
  url: Uri.parse('https://www.tone3000.com/tones/83759'),
);

final _model = Tone3000Model(
  id: 10,
  toneId: 83759,
  name: 'Cab Model',
  sizeClass: 'custom',
  modelUrl: Uri.parse('https://files.tone3000.com/models/10.wav'),
);

const _profile = GuitarProfile(
  id: 'guitar-1',
  name: 'Testgitarre',
  guitarType: GuitarType.superstrat,
  pickupType: PickupType.passiveHumbucker,
  outputLevel: OutputLevel.medium,
  toneCharacter: ToneCharacter.neutral,
  tuning: GuitarTuning.dStandard,
  playbackPath: PlaybackPath.headphones,
);
