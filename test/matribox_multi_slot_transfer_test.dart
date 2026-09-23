import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_hardware_evidence.dart';
import 'package:wyrmtone/presets/matribox_raw_backup_service.dart';
import 'package:wyrmtone/presets/matribox_target_preset.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_plan.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_session.dart';
import 'package:wyrmtone/presets/matribox_transfer_catalog.dart';
import 'package:wyrmtone/presets/matribox_transfer_slots.dart';
import 'package:wyrmtone/presets/matribox_verified_p01_read.dart';
import 'package:wyrmtone/presets/raw_preset_backup_format.dart';
import 'package:wyrmtone/presets/tone_intent.dart';
import 'package:wyrmtone/screens/matribox_channel_clients.dart';
import 'package:wyrmtone/screens/tone_transfer_page.dart';

import 'support/matribox_big_capture_snapshots.dart';
import 'support/matribox_full_live_helpers.dart';
import 'support/matribox_tone_transfer_support.dart';

/// Multi-slot transfer: P01..P10 are protected play presets (zero reads, zero sends), P11..P99 are
/// product writable, and the chosen slot is bound through read -> backup -> diff -> plan -> native
/// contract -> record -> readback -> verification. No hardware: every device is a fake.
void main() {
  late Directory tempDir;
  final angels = angelsRecommendation();

  setUp(() => tempDir = Directory.systemTemp.createTempSync('multi_slot'));
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  List<List<int>> copy(List<List<int>> parts) => [for (final p in parts) [...p]];
  List<List<int>> before() => hexParts(bigBeforeRawPartsHex);

  MatriboxRawBackupService service(ToneReadChannel c) => MatriboxRawBackupService(channel: c, backupDirectory: tempDir);
  MatriboxToneTransferSession session(ToneReadChannel read, MatriboxToneTransferChannel channel) => MatriboxToneTransferSession(
    backupService: service(read),
    ledger: MatriboxHardwareLedger.product(),
    channel: channel,
    library: angels.library,
  );
  MatriboxToneTransferStore storeFor(int n) {
    final slot = MatriboxUserSlot.preset(n);
    return MatriboxToneTransferStore(File('${tempDir.path}/${toneTransferStateFileName(slot)}'), slot: slot);
  }

  /// A small, fully eligible sound whose only difference is the AMP gain (and so its plan).
  MatriboxTargetPreset gainTarget(double gain) {
    TargetValue<double> v(double x) => TargetValue(x, ToneOrigin.songProfile, 'test');
    return MatriboxTargetPreset(
      blocks: {
        MatriboxChainSlot.amp: MatriboxTargetBlock(
          slot: MatriboxChainSlot.amp,
          enabled: TargetValue(true, ToneOrigin.songProfile, 'test'),
          model: TargetValue(MatriboxTransferCatalog.byName('Sol 100 OD')!, ToneOrigin.deviceTranslation, 'test'),
          parameters: {'gain': v(gain)},
        ),
      },
    );
  }

  MatriboxToneTransferPlan planFor(int presetNumber, {bool userBank = true, MatriboxTargetPreset? target}) =>
      MatriboxToneTransferPlan.build(
        current: beforeLayout(),
        target: target ?? angels.target,
        ledger: MatriboxHardwareLedger.product(),
        backupSha256: 'ab' * 32,
        presetNumber: presetNumber,
        isUserBank: userBank,
        transportAvailable: true,
        library: angels.library,
      );

  /// Full product chain against a fake device holding per-slot content; returns the final record.
  Future<MatriboxToneTransferRecord> transferAndVerify({
    required ToneReadChannel device,
    required RecordingTransfer channel,
    required MatriboxTargetPreset target,
    required int slot,
  }) async {
    final prepared = await session(device, channel).prepare(target, targetSlot: slot);
    expect(prepared.plan!.sendable, isTrue, reason: 'P$slot ${prepared.plan!.blockers}');
    final store = storeFor(slot);
    final run = await MatriboxToneTransferExecutor(channel: channel, store: store).execute(prepared);
    expect(run.isSuccess, isTrue, reason: run.error);
    // loaded like the page does (with the library), so the saved record keeps its full target
    final record = await MatriboxToneTransferCheckpoint.confirmManualSave((await store.load(library: angels.library))!, store);
    // the "user" saves on the device: the slot now holds the written sound
    device.bySlot[slot] = deviceAfter(prepared.plan!.operations, from: copy(device.bySlot[slot] ?? before()));
    final result = await MatriboxToneTransferReadback.run(record: record, backupService: service(device), store: store);
    expect(result.outcome, ToneReadbackOutcome.certified, reason: 'P$slot ${result.detail}');
    return (await store.load(library: angels.library))!;
  }

  group('central slot policy and addressing', () {
    test('P01..P10 protected, P11..P99 writable, everything else invalid; no default', () {
      for (var n = 1; n <= 10; n++) {
        expect(MatriboxSlotPolicy.isProtected(n), isTrue);
        expect(MatriboxSlotPolicy.isProductWritable(n), isFalse);
        expect(MatriboxSlotPolicy.writeRejection(n), contains('P01–P10 sind geschützt.'));
      }
      for (var n = 11; n <= 99; n++) {
        expect(MatriboxSlotPolicy.isProductWritable(n), isTrue);
        expect(MatriboxSlotPolicy.writeRejection(n), isNull);
      }
      for (final n in [null, 0, -1, 100, 255]) {
        expect(MatriboxSlotPolicy.isProductWritable(n), isFalse, reason: '$n');
        expect(MatriboxSlotPolicy.writeRejection(n), isNotNull, reason: '$n');
        expect(MatriboxUserSlot.tryPreset(n), isNull, reason: '$n');
      }
      expect(MatriboxSlotPolicy.isProductWritable(11, isUserBank: false), isFalse);
      expect(MatriboxSlotPolicy.writeRejection(50, isUserBank: false), 'Die Factory-Bank wird nie beschrieben.');
      // the UI capability table is derived from the same policy
      expect(MatriboxTransferSlots.userSlots, hasLength(99));
      for (final slot in MatriboxTransferSlots.userSlots) {
        final writable = slot.number >= 11;
        expect(slot.label, 'P${slot.number.toString().padLeft(2, '0')}');
        expect((slot.approved, slot.isProtected, slot.capability.selectable), (writable, !writable, writable), reason: slot.label);
        expect(
          [slot.capability.readable, slot.capability.backupSupported, slot.capability.writeSupported, slot.capability.verifySupported],
          everyElement(writable),
          reason: slot.label,
        );
        // only P11 has its own CERTIFIED hardware run; it is never generalized to other slots
        expect(slot.capability.hardwareCertified, slot.number == 11, reason: slot.label);
      }
      for (final n in [null, 0, 100]) {
        expect(MatriboxTransferSlots.slot(n), isNull);
      }
      expect(MatriboxSlotPolicy.evidenceStatus(11), 'PRODUCT_WRITABLE / HARDWARE_CERTIFIED');
      for (final n in [12, 50, 99]) {
        expect(MatriboxSlotPolicy.evidenceStatus(n), 'PRODUCT_WRITABLE / SOFTWARE_VALIDATED');
      }
      for (final n in [1, 5, 10]) {
        expect(MatriboxSlotPolicy.evidenceStatus(n), 'PROTECTED');
      }
    });

    test('off-by-one: P11 -> 10, P12 -> 11, P20 -> 19, P50 -> 49, P99 -> 98 and back', () {
      const expected = {1: 0, 10: 9, 11: 10, 12: 11, 20: 19, 50: 49, 99: 98};
      expected.forEach((preset, index) {
        final slot = MatriboxUserSlot.preset(preset);
        expect(slot.deviceIndex, index);
        expect(MatriboxUserSlot.fromDeviceIndex(index), slot);
        expect(MatriboxUserSlot.fromDeviceIndex(index).presetNumber, preset);
      });
      expect(MatriboxUserSlot.preset(11).label, 'P11');
      expect(MatriboxUserSlot.preset(99).label, 'P99');
      expect(() => MatriboxUserSlot.fromDeviceIndex(99), throwsArgumentError);
      expect(() => MatriboxUserSlot.preset(0), throwsArgumentError);
    });

    test('a fake slot read answers exactly the requested Bank/Slot bytes (P50 -> 0x31)', () async {
      final device = ToneReadChannel(before());
      final read = await readVerifiedUserSlot(service(device), MatriboxUserSlot.preset(50));
      expect(read.isVerified, isTrue, reason: read.blockedReason);
      expect(read.snapshot!.slot, 0x31);
      expect(read.snapshot!.presetNumber, 50);
      expect(read.snapshot!.isUserBank, isTrue);
      expect(device.slotReads, [50]);
    });
  });

  group('P01, P02, P05, P10: product layer rejects, zero reads, zero sends', () {
    for (final protected in [1, 2, 5, 10]) {
      test('P${protected.toString().padLeft(2, '0')}', () async {
        final device = ToneReadChannel(before());
        final channel = RecordingTransfer();
        // session: rejected before the device is even read
        final prepared = await session(device, channel).prepare(angels.target, targetSlot: protected);
        expect(prepared.plan, isNull);
        expect(prepared.blockedReason, contains('P01–P10 sind geschützt.'));
        expect(device.reads, 0);
        // backup / read helpers refuse as well, without reading
        expect((await service(device).backupUserSlot(MatriboxUserSlot.preset(protected))).isSuccess, isFalse);
        expect((await readVerifiedUserSlot(service(device), MatriboxUserSlot.preset(protected))).isVerified, isFalse);
        expect(device.reads, 0);
        // plan: blocked, and there is no contract to send
        final plan = planFor(protected);
        expect(plan.sendable, isFalse);
        expect(() => plan.toContractRequest(), throwsStateError);
        // executor: even a hand-built "prepared" transfer with a plan is rejected
        final okRead = await session(ToneReadChannel(before()), channel).prepare(angels.target, targetSlot: 11);
        final forged = PreparedToneTransfer(target: angels.target, targetSlot: protected, read: okRead.read, plan: plan);
        final run = await MatriboxToneTransferExecutor(channel: channel, store: storeFor(11)).execute(forged);
        expect(run.outcome, ToneTransferRunOutcome.rejected);
        expect(channel.executions, isEmpty);
        expect(channel.requests, isEmpty);
      });
    }

    test('missing slot, P00, P100 and the Factory bank are rejected the same way (no fallback to P01 or P11)', () async {
      final device = ToneReadChannel(before());
      final channel = RecordingTransfer();
      for (final slot in [null, 0, -3, 100]) {
        final prepared = await session(device, channel).prepare(angels.target, targetSlot: slot);
        expect(prepared.plan, isNull, reason: '$slot');
        expect(prepared.blockedReason, isNotNull, reason: '$slot');
      }
      expect(device.reads, 0);
      final factory = planFor(11, userBank: false);
      expect(factory.sendable, isFalse);
      expect(factory.blockers, contains('Die Factory-Bank wird nie beschrieben.'));
      expect(() => factory.toContractRequest(), throwsStateError);
      expect(channel.executions, isEmpty);
    });

    test('the Dart MethodChannel client never invokes the native read for a protected slot', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const methods = MethodChannel('de.neevel.wyrmtone/usb_methods');
      final calls = <MethodCall>[];
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        return {'outcome': 'PHASE_D_TIMEOUT'};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(methods, null));
      const client = MethodChannelPresetReadChannel();
      for (final protected in [1, 2, 5, 10, 0, 100]) {
        await expectLater(client.readMatriboxUserSlot(protected), throwsStateError);
      }
      expect(calls, isEmpty);
      await client.readMatriboxUserSlot(37);
      expect(calls.single.method, 'readMatriboxUserSlot');
      expect(calls.single.arguments, {'targetBank': 'USER', 'targetSlot': 37});
    });
  });

  group('P11, P12, P50, P99: the whole productive pipeline keeps the slot', () {
    for (final slot in [11, 12, 50, 99]) {
      test('P$slot: read, backup, plan, contract, record, readback and verification all name P$slot', () async {
        final device = ToneReadChannel(before());
        final channel = RecordingTransfer();
        final prepared = await session(device, channel).prepare(angels.target, targetSlot: slot);
        expect(device.slotReads, [slot]);
        expect(prepared.targetSlot, slot);
        expect(prepared.read!.slot!.presetNumber, slot);
        expect(prepared.read!.snapshot!.presetNumber, slot);
        expect(prepared.plan!.presetNumber, slot);
        final contract = prepared.plan!.toContractRequest();
        expect(contract['targetBank'], 'USER');
        expect(contract['targetSlot'], slot);

        final store = storeFor(slot);
        final run = await MatriboxToneTransferExecutor(channel: channel, store: store).execute(prepared);
        expect(run.isSuccess, isTrue);
        expect(channel.executions.single['targetSlot'], slot);
        var record = (await store.load())!;
        expect((record.targetSlot, record.writtenSlot), (slot, slot));
        final beforeBackup = decodeRawPresetBackupJson(await File(record.beforeBackupPath).readAsString());
        expect(beforeBackup.presetNumber, slot);
        expect(beforeBackup.sha256, record.beforeBackupSha256);

        record = await MatriboxToneTransferCheckpoint.confirmManualSave(record, store);
        device.bySlot[slot] = deviceAfter(prepared.plan!.operations);
        final result = await MatriboxToneTransferReadback.run(record: record, backupService: service(device), store: store);
        expect(device.slotReads, [slot, slot]);
        expect(result.outcome, ToneReadbackOutcome.certified);
        final verified = (await store.load())!;
        expect(verified.state, ToneTransferRecordState.verified);
        expect(verified.targetSlot, slot);
      });
    }
  });

  group('slot binding: any mismatch is never sent and never VERIFIED', () {
    test('a plan prepared for P11 cannot be executed as P12 (slot changed after prepare)', () async {
      final channel = RecordingTransfer();
      final p11 = await session(ToneReadChannel(before()), channel).prepare(angels.target, targetSlot: 11);
      final asP12 = PreparedToneTransfer(target: p11.target, targetSlot: 12, read: p11.read, plan: p11.plan);
      final run = await MatriboxToneTransferExecutor(channel: channel, store: storeFor(12)).execute(asP12);
      expect(run.outcome, ToneTransferRunOutcome.rejected);
      expect(channel.executions, isEmpty);
    });

    test('a P12 plan on a P11 backup, or a historical P01 read, is rejected before sending', () async {
      final channel = RecordingTransfer();
      final p11 = await session(ToneReadChannel(before()), channel).prepare(angels.target, targetSlot: 11);
      final p12Plan = MatriboxToneTransferPlan.build(
        current: p11.current!,
        target: p11.target,
        ledger: MatriboxHardwareLedger.product(),
        backupSha256: p11.read!.backup!.sha256,
        presetNumber: 12,
        isUserBank: true,
        transportAvailable: true,
        library: angels.library,
      );
      final mixed = PreparedToneTransfer(target: p11.target, targetSlot: 12, read: p11.read, plan: p12Plan);
      expect((await MatriboxToneTransferExecutor(channel: channel, store: storeFor(12)).execute(mixed)).outcome,
          ToneTransferRunOutcome.rejected);
      // a read without slot identity (e.g. a plain P01 backup read) is never a transfer read
      final r = p11.read!;
      final legacyRead = VerifiedPresetRead(backup: r.backup, snapshot: r.snapshot, layout: r.layout);
      final legacy = PreparedToneTransfer(target: p11.target, targetSlot: 11, read: legacyRead, plan: p11.plan);
      expect((await MatriboxToneTransferExecutor(channel: channel, store: storeFor(11)).execute(legacy)).outcome,
          ToneTransferRunOutcome.rejected);
      expect(channel.executions, isEmpty);
    });

    test('the device answering P12 to a P11 read: no plan at prepare, READ_FAILED at readback', () async {
      final channel = RecordingTransfer();
      final wrongAtPrepare = ToneReadChannel(before())..answerSlot = 12;
      final blocked = await session(wrongAtPrepare, channel).prepare(angels.target, targetSlot: 11);
      expect(wrongAtPrepare.slotReads, [11]);
      expect(blocked.blockedReason, contains('P12'));
      expect(blocked.plan, isNull);
      expect((await MatriboxToneTransferExecutor(channel: channel, store: storeFor(11)).execute(blocked)).outcome,
          ToneTransferRunOutcome.rejected);
      expect(channel.executions, isEmpty);

      final prepared = await session(ToneReadChannel(before()), channel).prepare(angels.target, targetSlot: 11);
      final store = storeFor(11);
      await MatriboxToneTransferExecutor(channel: channel, store: store).execute(prepared);
      final record = await MatriboxToneTransferCheckpoint.confirmManualSave((await store.load(library: angels.library))!, store);
      final wrongAtReadback = ToneReadChannel(deviceAfter(prepared.plan!.operations))..answerSlot = 12;
      final result = await MatriboxToneTransferReadback.run(record: record, backupService: service(wrongAtReadback), store: store);
      expect(wrongAtReadback.slotReads, [11]);
      expect(result.outcome, ToneReadbackOutcome.readFailed);
      expect((await store.load())!.state, isNot(ToneTransferRecordState.verified));
    });

    test('the native side reporting another written slot is no success and can never be verified', () async {
      final device = ToneReadChannel(before());
      final channel = RecordingTransfer(reportedSlot: 12);
      final prepared = await session(device, channel).prepare(angels.target, targetSlot: 11);
      final store = storeFor(11);
      final run = await MatriboxToneTransferExecutor(channel: channel, store: store).execute(prepared);
      expect(run.isSuccess, isFalse);
      expect(run.error, contains('SLOT_MISMATCH'));
      final record = await MatriboxToneTransferCheckpoint.confirmManualSave((await store.load())!, store);
      expect(record.writtenSlot, 12);
      device.bySlot[11] = deviceAfter(prepared.plan!.operations);
      final result = await MatriboxToneTransferReadback.run(record: record, backupService: service(device), store: store);
      expect(result.outcome, ToneReadbackOutcome.readFailed);
      expect((await store.load())!.state, isNot(ToneTransferRecordState.verified));
    });

    test('the store of one slot never hands out another slot record', () async {
      final record = await transferAndVerify(
        device: ToneReadChannel(before()),
        channel: RecordingTransfer(),
        target: angels.target,
        slot: 11,
      );
      // a P11 record copied into the P12 file is still refused by the P12 store
      await File('${tempDir.path}/${toneTransferStateFileName(MatriboxUserSlot.preset(11))}')
          .copy('${tempDir.path}/${toneTransferStateFileName(MatriboxUserSlot.preset(12))}');
      expect(record.state, ToneTransferRecordState.verified);
      expect(await storeFor(12).load(), isNull);
      expect((await storeFor(11).load())!.targetSlot, 11);
    });
  });

  group('consecutive transfers without state leak', () {
    test('Sound A -> P11, Sound B -> P12, Sound C -> P11: right backups, plans, native calls and verifications', () async {
      final device = ToneReadChannel(before());
      final channel = RecordingTransfer();
      final soundA = angels.target;
      final soundB = gainTarget(30);
      final soundC = gainTarget(80);

      final a = await transferAndVerify(device: device, channel: channel, target: soundA, slot: 11);
      final b = await transferAndVerify(device: device, channel: channel, target: soundB, slot: 12);
      final afterA = device.bySlot[11]!;
      final c = await transferAndVerify(device: device, channel: channel, target: soundC, slot: 11);

      // native calls: one per transfer, each naming its own slot
      expect(channel.executions.map((e) => e['targetSlot']), [11, 12, 11]);
      // each plan was diffed against the fresh state of ITS slot: C's P11 plan starts from A's saved sound
      expect(channel.executions[0]['operations'], hasLength(11));
      expect(channel.executions[2]['operations'], [
        {'type': 'SET_PARAMETER', 'slot': 'AMP', 'model': 'Sol 100 OD', 'parameter': 'Gain', 'value': 80.0},
      ]);
      // backups: every BEFORE backup is of its own slot, C's backup is A's saved P11 state
      Future<int> backupSlot(MatriboxToneTransferRecord r) async =>
          decodeRawPresetBackupJson(await File(r.beforeBackupPath).readAsString()).presetNumber;
      expect([await backupSlot(a), await backupSlot(b), await backupSlot(c)], [11, 12, 11]);
      final cBefore = decodeRawPresetBackupJson(await File(c.beforeBackupPath).readAsString());
      expect(cBefore.rawParts, retargetParts(afterA, 10));
      // the stores: P11 ends with C, P12 still with B; nothing leaked across
      final p11 = (await storeFor(11).load())!;
      final p12 = (await storeFor(12).load())!;
      expect(p11.planFingerprint, c.planFingerprint);
      expect(p12.planFingerprint, b.planFingerprint);
      expect(p11.target.toJson().toString(), soundC.toJson().toString());
      expect(p12.target.toJson().toString(), soundB.toJson().toString());
      expect((p11.state, p12.state), (ToneTransferRecordState.verified, ToneTransferRecordState.verified));
      // the device: P12 still holds B, P11 holds C
      expect(device.slotReads.where((s) => s != 11 && s != 12), isEmpty);
    });

    test('same sound -> P11 then -> P20: the verified P11 state never satisfies P20', () async {
      final device = ToneReadChannel(before());
      final channel = RecordingTransfer();
      final p11 = await transferAndVerify(device: device, channel: channel, target: angels.target, slot: 11);
      expect(p11.state, ToneTransferRecordState.verified);
      // nothing is known about P20 yet
      expect(await storeFor(20).load(), isNull);
      // P20 is freshly read and planned against ITS OWN state: the whole plan again, not "already done"
      final p20 = await session(device, channel).prepare(angels.target, targetSlot: 20);
      expect(p20.plan!.overall, ToneTransferOverall.ready);
      expect(p20.plan!.operations, hasLength(11));
      expect(p20.read!.snapshot!.presetNumber, 20);
      // a P20 record that is not yet saved is never VERIFIED because P11 is
      final store20 = storeFor(20);
      await MatriboxToneTransferExecutor(channel: channel, store: store20).execute(p20);
      final record20 = await MatriboxToneTransferCheckpoint.confirmManualSave((await store20.load())!, store20);
      final unsaved = await MatriboxToneTransferReadback.run(record: record20, backupService: service(device), store: store20);
      expect(unsaved.outcome, ToneReadbackOutcome.targetMismatch);
      expect((await store20.load())!.state, ToneTransferRecordState.failed);
      expect((await storeFor(11).load())!.state, ToneTransferRecordState.verified);
      expect(device.slotReads, [11, 11, 20, 20]);
    });
  });

  group('Angels regression: exactly the 11 certified operations, only the slot varies', () {
    test('P11, P50 and P99 give the identical 11-operation contract', () {
      final reference = planFor(11).toContractRequest();
      expect(reference['operations'], hasLength(11));
      for (final slot in [11, 12, 50, 99]) {
        final contract = planFor(slot).toContractRequest();
        expect(contract['operations'], reference['operations'], reason: 'P$slot');
        expect(contract['planId'], reference['planId'], reason: 'the golden plan id does not depend on the slot');
        expect(contract['targetSlot'], slot);
      }
    });
  });

  group('ToneTransferPage: slot bound UI', () {
    Future<void> show(WidgetTester tester, {required int? slot, ToneReadChannel? read, RecordingTransfer? transfer}) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: ToneTransferPage(
              recommendation: angels,
              targetSlot: slot,
              readChannel: read ?? ToneReadChannel(before()),
              transferChannel: transfer ?? RecordingTransfer(),
              backupDirectory: () async => tempDir,
              nameCatalogLoader: () async => toneCatalog,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.pump();
      });
    }

    for (final slot in [null, 1, 10]) {
      testWidgets('slot $slot: explained, send disabled, nothing read or sent', (tester) async {
        final read = ToneReadChannel(before());
        final transfer = RecordingTransfer();
        await show(tester, slot: slot, read: read, transfer: transfer);
        expect(find.byKey(const Key('tt-slot-blocked')), findsOneWidget);
        expect(tester.widget<FilledButton>(find.byKey(const Key('tt-send'))).onPressed, isNull);
        expect(read.reads, 0);
        expect(transfer.executions, isEmpty);
      });
    }

    testWidgets('a VERIFIED P11 session is shown for P11 and never for P12, also after switching the slot', (tester) async {
      await tester.runAsync(() => transferAndVerify(
        device: ToneReadChannel(before()),
        channel: RecordingTransfer(),
        target: angels.target,
        slot: 11,
      ));
      await show(tester, slot: 11);
      expect(find.byKey(const Key('tt-phase-verified')), findsOneWidget);
      expect(find.text('${angels.recipe.song} · Matribox 1 · P11'), findsOneWidget);
      await show(tester, slot: 12);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tt-phase-verified')), findsNothing);
      expect(find.text('Ziel: Matribox 1 · Preset P12'), findsOneWidget);
      expect(find.byKey(const Key('tt-send')), findsOneWidget);
    });
  });
}
