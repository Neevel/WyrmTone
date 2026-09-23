import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_full_live_verifier.dart';
import 'package:wyrmtone/presets/matribox_hardware_evidence.dart';
import 'package:wyrmtone/presets/matribox_model_library.dart';
import 'package:wyrmtone/presets/matribox_preset_layout.dart';
import 'package:wyrmtone/presets/matribox_raw_backup_service.dart';
import 'package:wyrmtone/presets/matribox_target_preset.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_plan.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_session.dart';
import 'package:wyrmtone/presets/matribox_transfer_catalog.dart';
import 'package:wyrmtone/presets/tone_intent.dart';

import 'support/matribox_big_capture_snapshots.dart';
import 'support/matribox_full_live_helpers.dart';
import 'support/matribox_tone_transfer_support.dart';

MatriboxToneTransferPlan planFor(
  MatriboxTargetPreset target, {
  MatriboxHardwareLedger? ledger,
  bool transport = true,
  MatriboxPresetLayoutModel? current,
  MatriboxModelLibrary? library,
}) => MatriboxToneTransferPlan.build(
  current: current ?? beforeLayout(),
  target: target,
  ledger: ledger ?? MatriboxHardwareLedger.product(),
  backupSha256: 'abc123',
  presetNumber: 11,
  isUserBank: true,
  transportAvailable: transport,
  nameCatalog: toneCatalog,
  library: library ?? productLibrary,
);

/// The library the product uses (vendor catalog); the productive ledger names its models.
final productLibrary = MatriboxModelLibrary.fromVendor(toneCatalog);

MatriboxTargetPreset targetOf(Map<MatriboxChainSlot, MatriboxTargetBlock> blocks) =>
    MatriboxTargetPreset(blocks: blocks);

TargetValue<double> tv(double v) => TargetValue(v, ToneOrigin.songProfile, 'test');
TargetValue<bool> on(bool v) => TargetValue(v, ToneOrigin.songProfile, 'test');

void main() {
  late Directory tempDir;
  late MatriboxToneTransferStore store;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('tone_transfer_test');
    store = MatriboxToneTransferStore(File('${tempDir.path}/tone_transfer.state'));
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  MatriboxRawBackupService service(ToneReadChannel c) =>
      MatriboxRawBackupService(channel: c, backupDirectory: tempDir);

  MatriboxToneTransferSession session(
    ToneReadChannel read, {
    MatriboxHardwareLedger? ledger,
    MatriboxToneTransferChannel? channel,
  }) => MatriboxToneTransferSession(
    backupService: service(read),
    ledger: ledger ?? MatriboxHardwareLedger.product(),
    channel: channel ?? RecordingTransfer(),
    nameCatalog: toneCatalog,
    library: productLibrary,
  );

  group('current device state', () {
    test('every prepare performs a NEW read; nothing is cached', () async {
      final read = ToneReadChannel(hexParts(bigBeforeRawPartsHex));
      final s = session(read);
      final target = readyTarget();
      final first = await s.prepare(target, targetSlot: 11);
      expect(read.reads, 1);
      expect(first.plan!.summary.parametersChanged, 5);
      read.parts = deviceAfter(first.plan!.operations); // the device changed meanwhile
      final second = await s.prepare(target, targetSlot: 11);
      expect(read.reads, 2);
      expect(second.plan!.operations, isEmpty);
      expect(second.plan!.overall, ToneTransferOverall.nothingToDo);
    });

    test('a failed read yields no plan; a Factory bank is refused', () async {
      final failing = ToneReadChannel(hexParts(bigBeforeRawPartsHex))..fail = true;
      final blocked = await session(failing).prepare(readyTarget(), targetSlot: 11);
      expect(blocked.plan, isNull);
      expect(blocked.blockedReason, contains('Kein gültiges Backup'));

      final factory = hexParts(bigBeforeRawPartsHex)..forEach((p) => p[13] = 0x01);
      final refused = await session(ToneReadChannel(factory)).prepare(readyTarget(), targetSlot: 11);
      expect(refused.plan, isNull);
    });

    test('backup and hash are mandatory: plan carries the verified hash, the executor re-checks it', () async {
      final prepared = await session(ToneReadChannel(hexParts(bigBeforeRawPartsHex)))
          .prepare(readyTarget(), targetSlot: 11);
      expect(prepared.plan!.backupSha256, prepared.read!.backup!.sha256);
      expect(File(prepared.read!.backup!.filePath!).existsSync(), isTrue);

      final noBackup = PreparedToneTransfer(target: prepared.target, plan: prepared.plan, targetSlot: 11);
      final channel = RecordingTransfer();
      final result = await MatriboxToneTransferExecutor(channel: channel, store: store).execute(noBackup);
      expect(result.outcome, ToneTransferRunOutcome.rejected);
      expect(channel.requests, isEmpty);

      final wrongHash = MatriboxToneTransferPlan.build(
        current: prepared.current!,
        target: prepared.target,
        ledger: MatriboxHardwareLedger.product(),
        backupSha256: 'deadbeef',
        presetNumber: 11,
        isUserBank: true,
        transportAvailable: true,
        library: productLibrary,
      );
      final mismatch = await MatriboxToneTransferExecutor(channel: channel, store: store).execute(
        PreparedToneTransfer(target: prepared.target, read: prepared.read, plan: wrongHash, targetSlot: 11),
      );
      expect(mismatch.outcome, ToneTransferRunOutcome.rejected);
      expect(channel.requests, isEmpty);
    });
  });

  group('semantic diff', () {
    test('every one of the nine slots is compared; model/parameter/block entries in chain order', () {
      final plan = planFor(readyTarget());
      expect({for (final e in plan.entries) e.slot}, MatriboxChainSlot.values.toSet());
      expect(plan.entries.map((e) => e.slot.index).toList(), everyElement(greaterThanOrEqualTo(0)));
      var last = -1;
      for (final e in plan.entries) {
        expect(e.slot.index, greaterThanOrEqualTo(last));
        last = e.slot.index;
      }
    });

    test('a model change precedes its parameters and resets them; block toggle comes last', () {
      final skreamerToBlues = MatriboxTransferCatalog.byName('Blues OD')!;
      final target = targetOf({
        MatriboxChainSlot.fx2: MatriboxTargetBlock(
          slot: MatriboxChainSlot.fx2,
          model: TargetValue(skreamerToBlues, ToneOrigin.deviceTranslation, 't'),
          parameters: {'gain': tv(23), 'tone': tv(61)},
          enabled: on(true),
        ),
      });
      final plan = planFor(target);
      final fx2 = plan.entries.where((e) => e.slot == MatriboxChainSlot.fx2 && e.isChange).toList();
      expect(fx2.map((e) => e.intended), [
        ToneOperationKind.selectModel,
        ToneOperationKind.setParameter,
        ToneOperationKind.setParameter,
        ToneOperationKind.enableBlock,
      ]);
      expect(fx2[1].current, 'nach Modellwechsel zurückgesetzt');
      expect(plan.overall, ToneTransferOverall.ready);
      expect(MatriboxToneTransferExecutor.orderIsValid(plan.operations), isTrue);
      expect(MatriboxToneTransferExecutor.orderIsValid(plan.operations.reversed.toList()), isFalse);
      // Without hardware evidence the dependent parameters are blocked too.
      final blocked = planFor(target, ledger: baselineLedger);
      expect(
        blocked.entries.where((e) => e.slot == MatriboxChainSlot.fx2 && e.isChange).map((e) => e.eligibility),
        everyElement(ToneSendEligibility.blockedByEvidence),
      );
    });

    test('already correct values are NO_CHANGE and never sent', () {
      final layout = beforeLayout();
      final amp = MatriboxTransferCatalog.byName('Sol 100 OD')!;
      final target = targetOf({
        MatriboxChainSlot.amp: MatriboxTargetBlock(
          slot: MatriboxChainSlot.amp,
          model: TargetValue(amp, ToneOrigin.deviceTranslation, 't'),
          parameters: {
            'gain': tv(layout.parameter(MatriboxChainSlot.amp, 0)),
            'bass': tv(layout.parameter(MatriboxChainSlot.amp, 3)),
          },
          enabled: on(layout.isOn(MatriboxChainSlot.amp)),
        ),
      });
      final plan = planFor(target);
      expect(plan.operations, isEmpty);
      expect(plan.overall, ToneTransferOverall.nothingToDo);
      expect(plan.summary.unchanged, 4); // model, gain, bass, block
    });

    test('UNKNOWN_CURRENT and UNSUPPORTED are reported, never guessed', () {
      final target = targetOf({
        MatriboxChainSlot.fx1: MatriboxTargetBlock(
          slot: MatriboxChainSlot.fx1,
          parameters: {'sustain': tv(30)}, // the current FX1 model is not in this (capture-only) library
        ),
        MatriboxChainSlot.amp: MatriboxTargetBlock(
          slot: MatriboxChainSlot.amp,
          parameters: {'gain': tv(120), 'nonexistent': tv(1)},
        ),
      });
      final plan = planFor(target, library: MatriboxModelLibrary.base);
      Iterable<ToneSendEligibility> of(MatriboxChainSlot s) =>
          plan.entries.where((e) => e.slot == s && e.specified && e.isChange).map((e) => e.eligibility);
      expect(of(MatriboxChainSlot.fx1), [ToneSendEligibility.unknownCurrent]);
      expect(of(MatriboxChainSlot.amp), [ToneSendEligibility.unsupported, ToneSendEligibility.unsupported]);
      expect(plan.overall, ToneTransferOverall.blocked);
      expect(plan.summary.unknownCurrent, 1);
      expect(plan.summary.unsupported, 2);
    });
  });

  group('evidence gate', () {
    test('capture-confirmed alone is not enough: the baseline samples (Sol 100 OD Gain/Presence) cover the AMP number family only', () {
      final plan = planFor(readyTarget(), ledger: baselineLedger);
      expect(plan.overall, ToneTransferOverall.blocked);
      final eligible = plan.operations.map((e) => '${e.slot.label}.${e.subject}').toList();
      expect(eligible, ['AMP.gain', 'AMP.presence', 'AMP.bass', 'AMP.middle', 'AMP.treble']); // Evidence V2: number family in AMP
      final blocked = plan.entries
          .where((e) => e.eligibility == ToneSendEligibility.blockedByEvidence)
          .map((e) => '${e.slot.label}.${e.subject}')
          .toList();
      expect(blocked, ['FX2.BLOCK', 'CAB.MODEL', 'CAB.BLOCK']); // no select/toggle samples in the baseline
      final bass = plan.entries.firstWhere((e) => e.subject == 'bass');
      expect(bass.protocolEvidence, TransferProtocolEvidence.captureConfirmed);
      expect(bass.hardwareEvidence!.confirmed, isTrue);
      expect(bass.hardwareEvidence!.exact, isFalse); // FAMILY, not exact
      expect(plan.summary.blocked, 3);
    });

    test('with the productive ledger the transfer mechanics plan is READY: 1 model, 5 parameter, 2 block operations', () {
      final plan = planFor(readyTarget());
      expect(plan.overall, ToneTransferOverall.ready);
      final s = plan.summary;
      expect((s.modelsChanged, s.parametersChanged, s.blocksEnabled, s.blocksDisabled), (1, 5, 2, 0));
      expect((s.blocked, s.unsupported), (0, 0));
      expect(plan.operations.map((e) => '${e.slot.label}.${e.subject}'), [
        'FX2.BLOCK',
        'AMP.gain',
        'AMP.presence',
        'AMP.bass',
        'AMP.middle',
        'AMP.treble',
        'CAB.MODEL',
        'CAB.BLOCK',
      ]);
      expect(plan.operations.every((e) => e.bytes != null), isTrue);
    });

    test('without a productive transport even a fully eligible plan is BLOCKED', () {
      final plan = planFor(readyTarget(), transport: false);
      expect(plan.overall, ToneTransferOverall.blocked);
      expect(plan.blockers.join(), contains('Transport'));
      expect(plan.sendable, isFalse);
    });

    test('a model select needs hardware samples, not only protocol evidence; User IR is never selectable', () {
      final brit = beforeLayoutWithAmp(0x07000035);
      MatriboxToneTransferPlan planWith(String name, {MatriboxHardwareLedger? ledger}) => planFor(
        targetOf({
          MatriboxChainSlot.amp: MatriboxTargetBlock(
            slot: MatriboxChainSlot.amp,
            model: TargetValue(MatriboxTransferCatalog.byName(name)!, ToneOrigin.deviceTranslation, 't'),
          ),
        }),
        current: brit,
        ledger: ledger,
      );
      ToneTransferEntry ampModel(MatriboxToneTransferPlan p) =>
          p.entries.firstWhere((e) => e.slot == MatriboxChainSlot.amp && e.subject == 'MODEL');
      // without select samples (baseline ledger) a select is blocked, whatever its protocol evidence
      final od = ampModel(planWith('Sol 100 OD', ledger: baselineLedger));
      expect(od.eligibility, ToneSendEligibility.blockedByEvidence);
      expect(od.protocolEvidence, TransferProtocolEvidence.correlated);
      expect(ampModel(planWith('Sol 100 LD', ledger: baselineLedger)).eligibility, ToneSendEligibility.blockedByEvidence);
      // the productive samples make AMP select a confirmed family (Sol 100 OD was selected in a certified run)
      expect(ampModel(planWith('Sol 100 OD')).eligibility, ToneSendEligibility.eligible);
      final ir = planFor(
        targetOf({
          MatriboxChainSlot.cab: MatriboxTargetBlock(
            slot: MatriboxChainSlot.cab,
            model: TargetValue(MatriboxTransferCatalog.byName('User IR 7')!, ToneOrigin.userOverride, 't'),
          ),
        }),
      ).entries.firstWhere((e) => e.slot == MatriboxChainSlot.cab && e.subject == 'MODEL');
      expect(ir.eligibility, ToneSendEligibility.unsupported);
    });
  });

  group('execution', () {
    Future<PreparedToneTransfer> prepared({MatriboxHardwareLedger? ledger}) => session(
      ToneReadChannel(hexParts(bigBeforeRawPartsHex)),
      ledger: ledger,
    ).prepare(readyTarget(), targetSlot: 11);

    test('a blocked plan (Blocked > 0) can never be sent', () async {
      final p = await prepared(ledger: baselineLedger);
      expect(p.plan!.summary.blocked, greaterThan(0));
      final channel = RecordingTransfer();
      final result = await MatriboxToneTransferExecutor(channel: channel, store: store).execute(p);
      expect(result.outcome, ToneTransferRunOutcome.rejected);
      expect(channel.requests, isEmpty);
      expect(await store.load(), isNull);
    });

    test('no productive transport: rejected, nothing sent', () async {
      final p = await session(
        ToneReadChannel(hexParts(bigBeforeRawPartsHex)),
        channel: const UnavailableToneTransferChannel(),
      ).prepare(readyTarget(), targetSlot: 11);
      expect(p.plan!.sendable, isFalse);
      final result = await MatriboxToneTransferExecutor(
        channel: const UnavailableToneTransferChannel(),
        store: store,
      ).execute(p);
      expect(result.isSuccess, isFalse);
      expect(result.completed, isEmpty);
    });

    test('the prepared plan is sent once, in order, without Store; the record keeps target and backup', () async {
      final p = await prepared();
      final channel = RecordingTransfer();
      final result = await MatriboxToneTransferExecutor(channel: channel, store: store).execute(p);
      expect(result.isSuccess, isTrue);
      expect(channel.requests, hasLength(8));
      expect(channel.executions, hasLength(1)); // the WHOLE plan in one call
      expect(channel.requests.map((r) => r['type']).toSet(), {'SELECT_MODEL', 'SET_PARAMETER', 'ENABLE_BLOCK'});
      expect(channel.requests.map((r) => r['slot']), ['FX2', 'AMP', 'AMP', 'AMP', 'AMP', 'AMP', 'CAB', 'CAB']);
      expect(channel.requests[1]['parameter'], 'Gain');
      expect(channel.requests[1]['value'], 67.0);
      expect(channel.requests[0]['type'], 'ENABLE_BLOCK');
      expect(channel.executions.single['targetBank'], 'USER');
      expect(channel.executions.single['targetSlot'], 11);
      expect(result.completed.length, 8);
      expect(result.recordSaved, isTrue);
      final record = (await store.load())!;
      expect(record.beforeBackupSha256, p.read!.backup!.sha256);
      expect(record.target.toJson()['blocks'], isNotEmpty);
      expect(jsonEncode(record.toJson()).toLowerCase(), isNot(contains('qme2')));
    });

    test('the first failure stops the run: completed / failed / notSent, no retry', () async {
      final p = await prepared();
      final channel = RecordingTransfer(failAt: 3);
      final result = await MatriboxToneTransferExecutor(channel: channel, store: store).execute(p);
      expect(result.outcome, ToneTransferRunOutcome.sendFailed);
      expect(channel.requests, hasLength(4)); // 3 sent + the failed one, never a 5th, never a repeat
      expect(result.completed.length, 3);
      expect(result.failed.length, 1);
      expect(result.notSent.length, 4);
      expect(result.error, contains('Transportfehler'));
      expect((await store.load())!.operations.map((o) => o.status), [
        'SENT', 'SENT', 'SENT', 'FAILED', 'NOT_SENT', 'NOT_SENT', 'NOT_SENT', 'NOT_SENT',
      ]);
    });

    test('a transport exception counts as failure', () async {
      final p = await prepared();
      final result = await MatriboxToneTransferExecutor(channel: _ThrowingTransfer(), store: store).execute(p);
      expect(result.outcome, ToneTransferRunOutcome.sendFailed);
      // how far the native run got is UNKNOWN: nothing is assumed, the record is kept
      expect(result.operations.every((o) => o.status == 'UNKNOWN'), isTrue);
      expect(result.recordSaved, isTrue);
    });
  });

  group('readback and manual-save follow-up', () {
    Future<(PreparedToneTransfer, MatriboxToneTransferRecord)> sent() async {
      final p = await session(ToneReadChannel(hexParts(bigBeforeRawPartsHex)))
          .prepare(readyTarget(), targetSlot: 11);
      await MatriboxToneTransferExecutor(channel: RecordingTransfer(), store: store).execute(p);
      // the user saves on the device and confirms: the checkpoint sends no MIDI
      final record = await MatriboxToneTransferCheckpoint.confirmManualSave((await store.load())!, store);
      return (p, record);
    }

    Future<ToneReadbackResult> readback(MatriboxToneTransferRecord r, List<List<int>> parts) =>
        MatriboxToneTransferReadback.run(record: r, backupService: service(ToneReadChannel(parts)), store: store);

    test('the state the plan produces is CERTIFIED (Part 8 only CORRELATED)', () async {
      final (p, record) = await sent();
      final result = await readback(record, deviceAfter(p.plan!.operations));
      expect(result.outcome, ToneReadbackOutcome.certified, reason: '${result.detail} ${result.checks.where((c) => !c.matched).map((c) => c.subject)}');
      expect(result.count(FullLiveChangeClass.correlatedPart8Change), greaterThan(0));
      expect(result.count(FullLiveChangeClass.unexpectedKnownChange), 0);
      expect((await store.load())!.readbackOutcome, 'certified');
    });

    test('an operation that did not land is a TARGET_MISMATCH', () async {
      final (p, record) = await sent();
      final result = await readback(record, deviceAfter(p.plan!.operations.take(7).toList()));
      expect(result.outcome, ToneReadbackOutcome.targetMismatch);
      expect(result.checks.where((c) => !c.matched).single.slot, MatriboxChainSlot.cab);
    });

    test('an unexpected model, parameter or block state is an UNEXPECTED_KNOWN_CHANGE', () async {
      final (p, record) = await sent();
      final model = deviceAfter(p.plan!.operations);
      setDecoded(model, MatriboxPresetLayout.codeOffset(MatriboxChainSlot.dly), u32(0x0b000006));
      expect((await readback(record, model)).outcome, ToneReadbackOutcome.unexpectedKnownChange);

      final parameter = deviceAfter(p.plan!.operations);
      // AMP volume (wire index 2) was not part of the plan.
      setDecoded(parameter, MatriboxPresetLayout.parametersBase(MatriboxChainSlot.amp) + 8, f32(99));
      final param = await readback(record, parameter);
      expect(param.outcome, ToneReadbackOutcome.unexpectedKnownChange);
      expect(param.changes.any((c) => c.detail.contains("AMP Parameter 2")), isTrue);

      final block = deviceAfter(p.plan!.operations);
      setDecoded(block, MatriboxPresetLayout.stateOffset(MatriboxChainSlot.mod), u16(1));
      expect((await readback(record, block)).outcome, ToneReadbackOutcome.unexpectedKnownChange);
    });

    test('an unknown raw change wins over everything and is never certified', () async {
      final (p, record) = await sent();
      final parts = deviceAfter(p.plan!.operations);
      setDecoded(parts, 700, [0x55]);
      expect((await readback(record, parts)).outcome, ToneReadbackOutcome.unknownRawChange);
    });

    test('a failed fresh read is READ_FAILED and the record stays SENT', () async {
      final (_, record) = await sent();
      final failing = ToneReadChannel(hexParts(bigBeforeRawPartsHex))..fail = true;
      final result = await MatriboxToneTransferReadback.run(
        record: record,
        backupService: service(failing),
        store: store,
      );
      expect(result.outcome, ToneReadbackOutcome.readFailed);
      expect((await store.load())!.state, ToneTransferRecordState.awaitingManualSave);
    });

    test('manual-save persistence is a separate claim and never a Store confirmation', () async {
      final (p, record) = await sent();
      final device = deviceAfter(p.plan!.operations);

      final early = await MatriboxToneTransferPersistence.check(
        record: record,
        backupService: service(ToneReadChannel(device)),
        store: store,
      );
      expect(early.outcome, TonePersistenceOutcome.notReady);

      await readback(record, device);
      final certified = (await store.load())!;
      final same = await MatriboxToneTransferPersistence.check(
        record: certified,
        backupService: service(ToneReadChannel(device)),
        store: store,
      );
      expect(same.outcome, TonePersistenceOutcome.manualSavePersistenceVerified);
      final saved = (await store.load())!;
      expect(saved.persistence, 'MANUAL_SAVE_PERSISTENCE_VERIFIED');
      expect(saved.readbackOutcome, 'certified');
      expect(saved.toJson().keys.any((k) => k.toLowerCase().contains('store')), isFalse);

      final reverted = await MatriboxToneTransferPersistence.check(
        record: certified,
        backupService: service(ToneReadChannel(hexParts(bigBeforeRawPartsHex))),
        store: store,
      );
      expect(reverted.outcome, TonePersistenceOutcome.persistenceMismatch);
    });
  });

  group('static safety', () {
    const files = [
      'lib/presets/matribox_tone_transfer_plan.dart',
      'lib/presets/matribox_tone_transfer_session.dart',
      'lib/presets/matribox_tone_transfer_pipeline.dart',
      'lib/presets/matribox_tone_translator.dart',
      'lib/presets/matribox_target_preset.dart',
      'lib/presets/matribox_transfer_catalog.dart',
      'lib/presets/matribox_hardware_evidence.dart',
      'lib/screens/tone_transfer_page.dart',
      'lib/screens/matribox_channel_clients.dart',
    ];
    String code(String path) => File(path)
        .readAsStringSync()
        .split('\n')
        .map((l) => l.split('//').first)
        .join('\n');

    test('no store/commit/restore path, no metadata send, no retry, no raw bytes across the transport', () {
      for (final f in files) {
        final source = code(f);
        expect(source, isNot(matches(RegExp(r'0x12,\s*0x1[12]'))), reason: f);
        expect(source, isNot(matches(RegExp(r'presetName\(|presetBpm\(|presetVolume\('))), reason: f);
        expect(source, isNot(matches(RegExp(r'fun\s+\w*(restore|retry|commit)', caseSensitive: false))), reason: f);
        expect(source, isNot(matches(RegExp(r'\b(restore|retry)\w*\s*\(', caseSensitive: false))), reason: f);
      }
      final session = code('lib/presets/matribox_tone_transfer_session.dart');
      final plan = code('lib/presets/matribox_tone_transfer_plan.dart');
      final contract = plan.substring(plan.indexOf('toContractRequest'), plan.indexOf('ToneTransferSummary get summary'));
      expect(contract, isNot(contains('bytes')));
      expect(contract, isNot(contains('wireIndex')));
      expect(contract, isNot(contains('.code')));
      // Exactly ONE transport call for the whole plan, without a retry construct.
      expect(RegExp(r'channel\.execute\(').allMatches(session).length, 1);
    });

    test('the page only reads from the device; the write path is the injected, unavailable transport', () {
      final page = code('lib/screens/tone_transfer_page.dart');
      expect(page, isNot(contains('invokeMethod')));
      expect(page, isNot(contains('invokeMapMethod')));
      final clients = code('lib/screens/matribox_channel_clients.dart');
      final invoked = RegExp(r"invokeMapMethod<[^>]*>\(\s*'([A-Za-z0-9]+)'").allMatches(clients).map((m) => m.group(1)).toSet();
      expect(invoked, containsAll({'readMatriboxUserP01', 'executeToneTransfer', 'getToneTransferStatus'}));
      expect(page, contains('UnavailableToneTransferChannel'));
    });
  });
}

class _ThrowingTransfer implements MatriboxToneTransferChannel {
  @override
  bool get available => true;
  @override
  Future<ToneTransferExecuteResult> execute(Map<String, Object?> request) async => throw StateError('USB getrennt.');
  @override
  Future<String?> connectionToken() async => null;
}
