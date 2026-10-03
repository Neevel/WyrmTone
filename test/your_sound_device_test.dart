import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/controllers/recommendation_controller.dart';
import 'package:wyrmtone/controllers/usb_controller.dart';
import 'package:wyrmtone/devices/device_profile.dart';
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/screens/your_sound_page.dart';
import 'package:wyrmtone/sounds/sound_selection.dart';
import 'package:wyrmtone/tonevault/tone_vault_model.dart';
import 'package:wyrmtone/ui/wyrm_design.dart';

import 'support/fake_usb_service.dart';
import 'support/recommendation_fakes.dart';
import 'support/sound_flow_support.dart';

/// "Dein Sound" must describe the device the user actually has: every device sentence comes from
/// the chosen [ToneDeviceAdapter], nothing is hardcoded to one product, an unchosen device is a
/// neutral state, and a sound plan is only offered for transfer where a transfer really exists.
void main() {
  Future<({RecommendationController c, UsbController usb, FakeUsbService service})> pumpPage(
    WidgetTester tester, {
    TargetDeviceId? chosen,
    bool matriboxConnected = false,
    bool transferAvailable = false,
  }) async {
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeUsbService();
    if (matriboxConnected) service.devices = [matriboxDevice(hasPermission: true)];
    addTearDown(service.dispose);
    final usb = UsbController(service);
    addTearDown(usb.dispose);
    await usb.initialize();
    final store = MemoryStringStore();
    final c = await flowController(store: store);
    addTearDown(c.dispose);
    if (chosen != null) c.selectTargetDevice(chosen);
    final session = flowSession(c, store);
    addTearDown(session.dispose);
    await session.use(
      const SoundSelection(entryId: 'song.metallica.master_of_puppets', tuning: GuitarTuning.dropC, variant: ToneVariantKind.rhythm),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: WyrmTokens.theme(),
        home: YourSoundPage(controller: c, session: session, usbController: usb, presetTransferAvailable: transferAvailable),
      ),
    );
    await tester.pumpAndSettle();
    return (c: c, usb: usb, service: service);
  }

  Future<void> reveal(WidgetTester tester, Key key) async {
    await tester.scrollUntilVisible(find.byKey(key), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  test('a fresh controller has no chosen device; choosing one is explicit', () async {
    final c = await flowController();
    addTearDown(c.dispose);
    expect(c.hasTargetDevice, isFalse);
    c.selectTargetDevice(TargetDeviceId.matriboxOne);
    expect(c.hasTargetDevice, isTrue);
    expect(c.selectedTargetDevice, TargetDeviceId.matriboxOne);
  });

  test('every adapter has its own short name for use inside sentences', () {
    expect({for (final a in toneDeviceAdapters) a.id: a.shortName}, {
      TargetDeviceId.dnafxGitCore: 'DNAfx GiT Core',
      TargetDeviceId.matriboxOne: 'Matribox 1',
    });
  });

  testWidgets('no device chosen and none connected: neutral state, no device is claimed', (tester) async {
    await pumpPage(tester);
    expect(find.text('Dieser Sound ist nur vorbereitet und noch nicht übertragen.'), findsOneWidget);
    await reveal(tester, const Key('your-sound-device-neutral'));
    expect(find.text('Gerät wählen'), findsOneWidget);
    expect(find.textContaining('DNAfx'), findsNothing);
    expect(find.byKey(const Key('your-sound-device-status')), findsNothing);
    expect(find.byKey(const Key('open-tone-transfer')), findsNothing);
  });

  testWidgets('a chosen DNAfx is shown as DNAfx, and no sentence mentions the Matribox', (tester) async {
    await pumpPage(tester, chosen: TargetDeviceId.dnafxGitCore);
    expect(find.text('Dieser Sound ist für DNAfx GiT Core nur vorbereitet und noch nicht übertragen.'), findsOneWidget);
    await reveal(tester, const Key('your-sound-transfer-note'));
    expect(find.text('Für DNAfx GiT Core gibt es nur eine Vorschau mit manuellen Einstellungen.'), findsOneWidget);
    expect(find.textContaining('Harley Benton DNAfx GiT Core'), findsWidgets, reason: 'the dropdown shows the chosen adapter');
    expect(find.textContaining('Matribox'), findsNothing);
    expect(find.byKey(const Key('open-tone-transfer')), findsNothing);
  });

  testWidgets('a chosen Matribox in a normal build says honestly that plans are not sent yet and points to NAM transfer', (tester) async {
    await pumpPage(tester, chosen: TargetDeviceId.matriboxOne);
    expect(find.text('Dieser Sound ist für Matribox 1 nur vorbereitet und noch nicht übertragen.'), findsOneWidget);
    await reveal(tester, const Key('your-sound-transfer-note'));
    expect(find.textContaining('noch nicht direkt auf die Matribox 1 übertragen'), findsOneWidget);
    expect(find.textContaining('Bibliothek → NAM'), findsOneWidget);
    expect(find.byKey(const Key('open-tone-transfer')), findsNothing);
    expect(find.byKey(const Key('your-sound-slot-picker')), findsNothing);
    expect(find.text('Speichern, vergleichen & planen'), findsNothing, reason: 'the developer workshop is not part of the normal flow');
  });

  testWidgets('where a preset transfer really exists (developer build), the Matribox offers it, named after the adapter', (tester) async {
    await pumpPage(tester, chosen: TargetDeviceId.matriboxOne, transferAvailable: true);
    await reveal(tester, const Key('open-tone-transfer'));
    expect(find.text('Auf Matribox 1 übertragen'), findsOneWidget);
    expect(find.text('Zeigt dir zuerst, was auf Matribox 1 daraus wird. Dabei wird noch nichts gesendet.'), findsOneWidget);
    expect(find.textContaining('DNAfx'), findsNothing);
  });

  testWidgets('choosing a device after the neutral state shows the signal chain without any build error', (tester) async {
    await pumpPage(tester);
    await reveal(tester, const Key('your-sound-device-neutral'));
    expect(find.byKey(const Key('sound-chain')), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<TargetDeviceId>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sonicake Matribox 1 / QME-50').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await reveal(tester, const Key('sound-chain'));
    await tester.tap(find.byKey(const Key('sound-chain')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('your-sound-transfer-note')), findsOneWidget);
  });

  testWidgets('a connected supported device becomes the target when nothing was chosen', (tester) async {
    final rig = await pumpPage(tester, matriboxConnected: true);
    expect(rig.c.hasTargetDevice, isTrue);
    expect(rig.c.selectedTargetDevice, TargetDeviceId.matriboxOne);
    expect(find.text('Dieser Sound ist für Matribox 1 nur vorbereitet und noch nicht übertragen.'), findsOneWidget);
  });

  testWidgets('a connected device never overrides what the user chose', (tester) async {
    final rig = await pumpPage(tester, chosen: TargetDeviceId.dnafxGitCore, matriboxConnected: true);
    expect(rig.c.selectedTargetDevice, TargetDeviceId.dnafxGitCore);
    expect(find.text('Dieser Sound ist für DNAfx GiT Core nur vorbereitet und noch nicht übertragen.'), findsOneWidget);
  });
}
