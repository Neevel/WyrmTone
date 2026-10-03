import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/controllers/usb_controller.dart';
import 'package:wyrmtone/devices/device_profile.dart';
import 'package:wyrmtone/models/usb_models.dart';
import 'package:wyrmtone/nam/local_nam_capture.dart';
import 'package:wyrmtone/screens/nam_detail_page.dart';
import 'package:wyrmtone/services/matribox_nam_payload.dart';
import 'package:wyrmtone/services/matribox_nam_transfer_service.dart';
import 'package:wyrmtone/services/nam_inference_engine.dart';
import 'package:wyrmtone/services/nam_preparation_service.dart';

import 'support/fake_usb_service.dart';

/// Product NAM → Matribox workflow V1: widget-level coverage of
/// [NamDetailPage]'s phase state machine, using injected
/// [NamPreparationRunner]/[MatriboxNamTransferRunner] plus the
/// `...ForTest` result constructors, so no test here touches real FFI,
/// native inference, or USB/MIDI -- matches the pattern already established
/// for the offline V5 preflight work (fake transport, no real device).
void main() {
  LocalNamCapture capture({NamCompatibility compatibility = NamCompatibility.compatible}) => LocalNamCapture(
    localId: 'nam-1',
    tone3000ToneId: null,
    tone3000ModelId: null,
    toneName: 'JVM410H',
    captureName: 'JVM410H Standard',
    creatorName: 'Marcel',
    description: null,
    make: 'Marshall',
    gearType: 'amp',
    tags: const [],
    license: '',
    source: 'local',
    architecture: NamArchitecture.a1,
    fileSize: 294105,
    // Realistic (matches File(path).uri.toString() in
    // nam_download_service.dart/nam_import_service.dart): percent-encoded
    // spaces/punctuation, exactly the shape that exposed the real "file
    // does not exist" bug in manual hardware-certification testing.
    localUri: Uri.file(
      '/data/user/0/de.neevel.wyrmtone/app_flutter/tone3000_nam/JVM410H Standard, Boosted.nam',
    ).toString(),
    sha256: 'test-sha',
    downloadedAt: DateTime.utc(2026),
    downloadStatus: NamDownloadStatus.imported,
    compatibility: compatibility,
    targetDevice: TargetDeviceId.matriboxOne,
    validationWarnings: const [],
    attribution: 'Marcel',
    cabinetContent: NamCabinetContent.withoutCabinet,
  );

  MatriboxNamPayload payload() => MatriboxNamPayload(
    cloData: Uint8List(8232),
    namName: 'JVM410H Standard',
    namSha256: 'test-sha',
    cloDataSha256: 'clodata-sha',
    preparationDuration: const Duration(seconds: 70),
  );

  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
  }

  testWidgets('idle: shows the transfer CTA for a compatible NAM', (tester) async {
    final usb = UsbController(FakeUsbService());
    addTearDown(usb.dispose);
    await pump(tester, NamDetailPage(capture: capture(), usbController: usb));
    expect(find.byKey(const Key('nam-detail-transfer')), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byKey(const Key('nam-detail-transfer')));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('idle: transfer CTA is disabled for an incompatible NAM, with an explanation', (tester) async {
    final usb = UsbController(FakeUsbService());
    addTearDown(usb.dispose);
    await pump(
      tester,
      NamDetailPage(capture: capture(compatibility: NamCompatibility.unsupported), usbController: usb),
    );
    final button = tester.widget<FilledButton>(find.byKey(const Key('nam-detail-transfer')));
    expect(button.onPressed, isNull);
    expect(find.textContaining('nicht verfügbar'), findsOneWidget);
  });

  testWidgets('the file:// localUri is decoded to a plain filesystem path before preparation', (tester) async {
    // Regression: a raw `file://...%20...` URI passed straight to the native
    // loader fails with "file does not exist" even though the file is
    // really there (found during manual hardware certification).
    final usb = UsbController(FakeUsbService());
    addTearDown(usb.dispose);
    String? receivedPath;
    await pump(
      tester,
      NamDetailPage(
        capture: capture(),
        usbController: usb,
        prepare: (namPath, {required namName, required namSha256, cancelToken, onProgress}) async {
          receivedPath = namPath;
          return const NamPreparationResult.cancelledForTest();
        },
      ),
    );
    await tester.tap(find.byKey(const Key('nam-detail-transfer')));
    await tester.pumpAndSettle();
    // Uri.toFilePath() is platform-aware (backslashes when this test itself
    // runs on Windows) -- the real target platform is Android/POSIX, so this
    // only asserts what must hold on every platform: no percent-encoding, no
    // URI scheme, and the real file name intact.
    expect(receivedPath, isNotNull);
    expect(receivedPath, isNot(contains('%20')));
    expect(receivedPath, isNot(startsWith('file:')));
    expect(receivedPath, contains('JVM410H Standard, Boosted.nam'));
  });

  testWidgets('expert metadata is collapsed under "Weitere Angaben"; the header shows plain-language facts only', (tester) async {
    final usb = UsbController(FakeUsbService());
    addTearDown(usb.dispose);
    await pump(tester, NamDetailPage(capture: capture(), usbController: usb));
    expect(find.text('Marcel · Lokaler Import'), findsOneWidget);
    expect(find.text('Kompatibel'), findsOneWidget);
    expect(find.textContaining('Lizenz'), findsNothing, reason: 'collapsed by default');
    await tester.tap(find.byKey(const Key('nam-metadata-details')));
    await tester.pumpAndSettle();
    expect(find.text('Lizenz: unbekannt'), findsOneWidget);
    expect(find.text('Architektur: A1'), findsOneWidget);
  });

  testWidgets('tapping transfer shows the indeterminate preparing card, no fake percentage', (tester) async {
    final usb = UsbController(FakeUsbService());
    addTearDown(usb.dispose);
    final completer = Completer<NamPreparationResult>();
    await pump(
      tester,
      NamDetailPage(
        capture: capture(),
        usbController: usb,
        prepare: (namPath, {required namName, required namSha256, cancelToken, onProgress}) => completer.future,
      ),
    );
    await tester.tap(find.byKey(const Key('nam-detail-transfer')));
    await tester.pump();
    expect(find.byKey(const Key('nam-preparing-card')), findsOneWidget);
    // No numeric/percentage progress text anywhere during preparation.
    expect(find.textContaining('%'), findsNothing);
    completer.complete(const NamPreparationResult.cancelledForTest());
    await tester.pumpAndSettle();
  });

  testWidgets('preparation cancelled shows the honest cancelled card, not a failure', (tester) async {
    final usb = UsbController(FakeUsbService());
    addTearDown(usb.dispose);
    await pump(
      tester,
      NamDetailPage(
        capture: capture(),
        usbController: usb,
        prepare: (namPath, {required namName, required namSha256, cancelToken, onProgress}) async =>
            const NamPreparationResult.cancelledForTest(),
      ),
    );
    await tester.tap(find.byKey(const Key('nam-detail-transfer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nam-preparation-cancelled')), findsOneWidget);
    expect(find.text('Vorbereitung abgebrochen'), findsOneWidget);
  });

  testWidgets('preparation failure shows the failed card with a German message', (tester) async {
    final usb = UsbController(FakeUsbService());
    addTearDown(usb.dispose);
    await pump(
      tester,
      NamDetailPage(
        capture: capture(),
        usbController: usb,
        prepare: (namPath, {required namName, required namSha256, cancelToken, onProgress}) async =>
            NamPreparationResult.failedForTest(
              const NamInferenceException(NamInferenceErrorKind.loadFailed, 0, 'native detail'),
            ),
      ),
    );
    await tester.tap(find.byKey(const Key('nam-detail-transfer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nam-preparation-failed')), findsOneWidget);
    expect(find.text('Das NAM-Modell konnte nicht für die Matribox vorbereitet werden.'), findsOneWidget);
    // Technical detail only under "Details", never shown expanded by default.
    expect(find.text('native detail'), findsNothing);
    expect(find.byKey(const Key('nam-failure-details')), findsOneWidget);
  });

  testWidgets('a successful preparation without a connected Matribox shows "Matribox verbinden"', (tester) async {
    final usb = UsbController(FakeUsbService());
    addTearDown(usb.dispose);
    await pump(
      tester,
      NamDetailPage(
        capture: capture(),
        usbController: usb,
        prepare: (namPath, {required namName, required namSha256, cancelToken, onProgress}) async =>
            NamPreparationResult.successForTest(payload()),
      ),
    );
    await tester.tap(find.byKey(const Key('nam-detail-transfer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nam-connect-card')), findsOneWidget);
    expect(find.text('Matribox verbinden'), findsOneWidget);
    final continueButton = tester.widget<FilledButton>(find.byKey(const Key('nam-connect-continue')));
    expect(continueButton.onPressed, isNull, reason: 'must not be selectable until actually connected');
  });

  testWidgets('full journey: connected -> pick Clone 5 -> confirm overwrite -> transfer -> success', (tester) async {
    final fakeUsb = FakeUsbService()
      ..devices = [matriboxDevice(hasPermission: true)]
      ..connection = const UsbConnectionStatus(isOpen: true, claimedInterfaceId: 3);
    final usb = UsbController(fakeUsb);
    addTearDown(usb.dispose);
    await usb.refresh();

    await pump(
      tester,
      NamDetailPage(
        capture: capture(),
        usbController: usb,
        prepare: (namPath, {required namName, required namSha256, cancelToken, onProgress}) async =>
            NamPreparationResult.successForTest(payload()),
        transfer: ({required payload, required slot, onProgress}) async {
          expect(slot.cloneNumber, 5);
          onProgress?.call(const MatriboxNamTransferProgress(confirmedCount: 590, totalFrames: 590));
          return const MatriboxNamTransferResult.successForTest(confirmedCount: 590, totalFrames: 590);
        },
      ),
    );

    await tester.tap(find.byKey(const Key('nam-detail-transfer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nam-connect-card')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nam-connect-continue')));
    await tester.pumpAndSettle();
    // Clone-slot picker sheet: Clone 1/5 selectable, Clone 2-4 not.
    expect(find.byKey(const Key('clone-slot-picker-1')), findsOneWidget);
    expect(find.byKey(const Key('clone-slot-picker-5')), findsOneWidget);
    final clone2 = tester.widget<ListTile>(find.byKey(const Key('clone-slot-picker-2')));
    expect(clone2.enabled, isFalse);

    await tester.tap(find.byKey(const Key('clone-slot-picker-5')));
    await tester.pumpAndSettle();

    // Overwrite confirmation dialog.
    expect(find.textContaining('wird überschrieben'), findsOneWidget);
    await tester.tap(find.byKey(const Key('nam-transfer-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nam-transfer-success')), findsOneWidget);
    expect(find.text('Übertragung abgeschlossen'), findsOneWidget);
  });

  group('explicit confirmation is mandatory; nothing writes or retries by itself', () {
    Future<(UsbController, List<int>)> connected(WidgetTester tester, {required MatriboxNamTransferRunner transfer}) async {
      final fakeUsb = FakeUsbService()
        ..devices = [matriboxDevice(hasPermission: true)]
        ..connection = const UsbConnectionStatus(isOpen: true, claimedInterfaceId: 3);
      final usb = UsbController(fakeUsb);
      addTearDown(usb.dispose);
      await usb.refresh();
      final calls = <int>[];
      await pump(
        tester,
        NamDetailPage(
          capture: capture(),
          usbController: usb,
          prepare: (namPath, {required namName, required namSha256, cancelToken, onProgress}) async =>
              NamPreparationResult.successForTest(payload()),
          transfer: ({required payload, required slot, onProgress}) {
            calls.add(slot.cloneNumber);
            return transfer(payload: payload, slot: slot, onProgress: onProgress);
          },
        ),
      );
      return (usb, calls);
    }

    const ok = MatriboxNamTransferResult.successForTest(confirmedCount: 590, totalFrames: 590);

    testWidgets('a finished preparation with a connected Matribox does not transfer anything', (tester) async {
      final (_, calls) = await connected(tester, transfer: ({required payload, required slot, onProgress}) async => ok);
      await tester.tap(find.byKey(const Key('nam-detail-transfer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nam-connect-card')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(calls, isEmpty, reason: 'ready is not consent: the user still has to continue, pick a slot and confirm');
    });

    testWidgets('dismissing the Clone-slot picker or the overwrite confirmation transfers nothing', (tester) async {
      final (_, calls) = await connected(tester, transfer: ({required payload, required slot, onProgress}) async => ok);
      await tester.tap(find.byKey(const Key('nam-detail-transfer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nam-connect-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Schließen'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.byKey(const Key('nam-connect-card')), findsOneWidget);

      await tester.tap(find.byKey(const Key('nam-connect-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('clone-slot-picker-5')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nam-transfer-confirm')), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty, reason: 'declining the overwrite warning must never reach the transfer');
      expect(find.byKey(const Key('nam-connect-card')), findsOneWidget);
    });

    testWidgets('a failed transfer is attempted exactly once -- no automatic retry', (tester) async {
      final (_, calls) = await connected(
        tester,
        transfer: ({required payload, required slot, onProgress}) async => const MatriboxNamTransferResult.failedForTest(
          MatriboxNamTransferFailureCategory.timeout,
          confirmedCount: 3,
          totalFrames: 590,
        ),
      );
      await tester.tap(find.byKey(const Key('nam-detail-transfer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nam-connect-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('clone-slot-picker-5')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nam-transfer-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nam-transfer-failed')), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      expect(calls, [5], reason: 'one confirmed attempt, one call; "Erneut versuchen" is a user action that starts over');
    });
  });

  testWidgets('a failed transfer never claims success, shows the German failure message', (tester) async {
    final fakeUsb = FakeUsbService()
      ..devices = [matriboxDevice(hasPermission: true)]
      ..connection = const UsbConnectionStatus(isOpen: true, claimedInterfaceId: 3);
    final usb = UsbController(fakeUsb);
    addTearDown(usb.dispose);
    await usb.refresh();

    await pump(
      tester,
      NamDetailPage(
        capture: capture(),
        usbController: usb,
        prepare: (namPath, {required namName, required namSha256, cancelToken, onProgress}) async =>
            NamPreparationResult.successForTest(payload()),
        transfer: ({required payload, required slot, onProgress}) async =>
            const MatriboxNamTransferResult.failedForTest(
              MatriboxNamTransferFailureCategory.timeout,
              confirmedCount: 3,
              totalFrames: 590,
            ),
      ),
    );

    await tester.tap(find.byKey(const Key('nam-detail-transfer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nam-connect-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clone-slot-picker-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nam-transfer-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nam-transfer-failed')), findsOneWidget);
    expect(find.text('Die Matribox hat nicht rechtzeitig geantwortet.'), findsOneWidget);
    expect(find.byKey(const Key('nam-transfer-success')), findsNothing);
  });

  testWidgets(
    'connection-lifecycle fix: a second NAM (same session) auto-reconnects a still-attached '
    'Matribox whose MIDI session went stale, without a push event or manual retry',
    (tester) async {
      final fakeUsb = FakeUsbService()
        ..devices = [matriboxDevice(hasPermission: true)]
        ..midiDevices = [matriboxMidiDevice()];
      final usb = UsbController(fakeUsb);
      addTearDown(usb.dispose);
      await usb.initialize();
      expect(usb.midiConnection.isOpen, isTrue, reason: 'auto-connect opened MIDI for the first NAM');

      // The real-hardware scenario this reproduces: after NAM A's transfer,
      // the MIDI session goes stale without Dart ever observing an
      // attach/detach/midiDevicesChanged event for it.
      fakeUsb.midiConnection = const MidiConnectionStatus(isOpen: false);

      await pump(
        tester,
        NamDetailPage(
          capture: capture(),
          usbController: usb,
          prepare: (namPath, {required namName, required namSha256, cancelToken, onProgress}) async =>
              NamPreparationResult.successForTest(payload()),
        ),
      );
      await tester.tap(find.byKey(const Key('nam-detail-transfer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nam-connect-card')), findsOneWidget);
      expect(find.text('Matribox verbunden'), findsOneWidget);
      final continueButton = tester.widget<FilledButton>(find.byKey(const Key('nam-connect-continue')));
      expect(continueButton.onPressed, isNotNull, reason: 'reconnected automatically, no manual retry needed');
    },
  );

  testWidgets('connection-lifecycle fix: "Erneut versuchen" on the connect card retries reconnection', (tester) async {
    final fakeUsb = FakeUsbService()..devices = [matriboxDevice()];
    final usb = UsbController(fakeUsb);
    addTearDown(usb.dispose);
    await usb.initialize();
    expect(usb.midiConnection.isOpen, isFalse);

    await pump(
      tester,
      NamDetailPage(
        capture: capture(),
        usbController: usb,
        prepare: (namPath, {required namName, required namSha256, cancelToken, onProgress}) async =>
            NamPreparationResult.successForTest(payload()),
      ),
    );
    await tester.tap(find.byKey(const Key('nam-detail-transfer')));
    await tester.pumpAndSettle();
    expect(find.text('Matribox verbinden'), findsOneWidget);

    // Now the device becomes available (permission granted, MIDI device
    // visible) -- but without any event WyrmTone reacts to on its own.
    fakeUsb.devices = [matriboxDevice(hasPermission: true)];
    fakeUsb.midiDevices = [matriboxMidiDevice()];

    await tester.tap(find.byKey(const Key('nam-connect-retry')));
    await tester.pumpAndSettle();

    expect(find.text('Matribox verbunden'), findsOneWidget);
    final continueButton = tester.widget<FilledButton>(find.byKey(const Key('nam-connect-continue')));
    expect(continueButton.onPressed, isNotNull);
  });

  testWidgets('cancelling during transfer calls the injected cancel hook, never claims success', (tester) async {
    final fakeUsb = FakeUsbService()
      ..devices = [matriboxDevice(hasPermission: true)]
      ..connection = const UsbConnectionStatus(isOpen: true, claimedInterfaceId: 3);
    final usb = UsbController(fakeUsb);
    addTearDown(usb.dispose);
    await usb.refresh();

    var cancelCalled = false;
    final transferCompleter = Completer<MatriboxNamTransferResult>();
    await pump(
      tester,
      NamDetailPage(
        capture: capture(),
        usbController: usb,
        prepare: (namPath, {required namName, required namSha256, cancelToken, onProgress}) async =>
            NamPreparationResult.successForTest(payload()),
        transfer: ({required payload, required slot, onProgress}) => transferCompleter.future,
        cancelTransfer: () async {
          cancelCalled = true;
          transferCompleter.complete(
            const MatriboxNamTransferResult.cancelledForTest(confirmedCount: 12, totalFrames: 590),
          );
        },
      ),
    );

    await tester.tap(find.byKey(const Key('nam-detail-transfer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nam-connect-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clone-slot-picker-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nam-transfer-confirm')));
    // Not pumpAndSettle: totalFrames is still 0 at this point, so the
    // progress indicator is indeterminate (a looping animation) -- exactly
    // the honest "no fake percentage" behaviour under test, but pumpAndSettle
    // never settles while it's animating.
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('nam-transferring-card')), findsOneWidget);
    await tester.tap(find.byKey(const Key('nam-transfer-cancel')));
    await tester.pumpAndSettle();

    expect(cancelCalled, isTrue);
    expect(find.byKey(const Key('nam-transfer-success')), findsNothing);
    expect(find.textContaining('unvollständig'), findsOneWidget);
  });
}
