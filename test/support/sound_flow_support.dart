import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/controllers/recommendation_controller.dart';
import 'package:wyrmtone/controllers/usb_controller.dart';
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/screens/app_shell.dart';
import 'package:wyrmtone/services/local_persistence.dart';
import 'package:wyrmtone/sounds/sound_selection.dart';
import 'package:wyrmtone/sounds/sound_session.dart';
import 'package:wyrmtone/tonevault/tone_vault.dart';
import 'package:wyrmtone/ui/wyrm_design.dart';

import 'fake_usb_service.dart';
import 'recommendation_fakes.dart';

String _read(String p) => File(p).readAsStringSync();

/// The complete built-in sound library, loaded from the asset files (no platform channel).
Future<ToneVault> loadTestVault() async {
  final manifest = JsonManifest.parse(_read('assets/tonevault/manifest.json'));
  return ToneVault.fromTexts(
    taxonomy: _read('assets/tonevault/taxonomy.json'),
    vocabulary: _read('assets/tonevault/vocabulary.json'),
    packs: [for (final p in manifest.packs) _read('assets/tonevault/$p')],
    nlu: _read('assets/tonevault/${manifest.nlu}'),
  );
}

const testGuitar = GuitarProfile(
  id: 'g1',
  name: 'Testgitarre',
  guitarType: GuitarType.superstrat,
  pickupType: PickupType.activeHumbucker,
  outputLevel: OutputLevel.high,
  toneCharacter: ToneCharacter.neutral,
  tuning: GuitarTuning.dropC,
  playbackPath: PlaybackPath.headphones,
);

Future<RecommendationController> flowController({bool withGuitar = true, MemoryStringStore? store}) async {
  final s = store ?? MemoryStringStore();
  final c = RecommendationController(
    profileRepository: ProfileRepository(s),
    irRepository: IrCatalogRepository(s),
    filePicker: FakeIrFilePicker(),
  );
  if (withGuitar) await c.saveProfile(testGuitar);
  return c;
}

SoundSession flowSession(RecommendationController c, MemoryStringStore store) =>
    SoundSession(controller: c, repository: SoundSelectionRepository(store), vaultLoader: loadTestVault);

class Rig {
  Rig(this.controller, this.session, this.store, this.usbService);
  final RecommendationController controller;
  final SoundSession session;
  final MemoryStringStore store;
  final FakeUsbService usbService;
}

/// Pumps the whole app shell at a given logical size and text scale.
Future<Rig> pumpShell(
  WidgetTester tester, {
  double width = 411,
  double height = 900,
  double textScale = 1,
  bool withGuitar = true,
  MemoryStringStore? store,
  SoundSession? session,
  RecommendationController? controller,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final service = FakeUsbService();
  addTearDown(service.dispose);
  final usb = UsbController(service);
  addTearDown(usb.dispose);
  await usb.initialize();
  final s = store ?? MemoryStringStore();
  final c = controller ?? await flowController(withGuitar: withGuitar, store: s);
  addTearDown(c.dispose);
  final sess = session ?? flowSession(c, s);
  await tester.pumpWidget(
    MaterialApp(
      theme: WyrmTokens.theme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AppShell(usbController: usb, recommendationController: c, soundSession: sess),
    ),
  );
  await tester.pumpAndSettle();
  return Rig(c, sess, s, service);
}

Future<void> openSoundsTab(WidgetTester tester) async {
  await tester.tap(find.text('Sounds').last);
  await tester.pumpAndSettle();
}

Future<void> search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('sound-search')), text);
  // The field's own onChanged is debounced (SoundsPage._suggestDebounce); pump past it explicitly
  // before settling, instead of relying on pumpAndSettle to notice a timer-scheduled frame.
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
