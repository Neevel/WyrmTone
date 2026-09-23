import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_angels_product_plan.dart';
import 'package:wyrmtone/presets/matribox_chain_catalog.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_full_live_plan.dart';
import 'package:wyrmtone/presets/matribox_full_live_session.dart';
import 'package:wyrmtone/presets/matribox_full_live_verifier.dart';
import 'package:wyrmtone/presets/matribox_hardware_evidence.dart';
import 'package:wyrmtone/presets/matribox_model_library.dart';
import 'package:wyrmtone/presets/matribox_preset_layout.dart';
import 'package:wyrmtone/presets/matribox_raw_backup_service.dart';
import 'package:wyrmtone/presets/matribox_sol100od_encoder.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_plan.dart';
import 'package:wyrmtone/presets/matribox_transfer_catalog.dart';

import 'support/matribox_big_capture_snapshots.dart';
import 'support/matribox_full_live_helpers.dart';
import 'support/matribox_tone_transfer_support.dart';

String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

void main() {
  final library = MatriboxModelLibrary.fromVendor(toneCatalog);
  final target = angelsRecommendation().target;
  late Directory tempDir;
  late MatriboxFullLiveStore store;

  AngelsProductPlan newPlan({bool withTarget = true}) =>
      AngelsProductPlan(library: library, target: withTarget ? target : null);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('angels_product');
    store = MatriboxFullLiveStore(File('${tempDir.path}/angels.state'));
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  MatriboxRawBackupService service(ToneReadChannel c) =>
      MatriboxRawBackupService(channel: c, backupDirectory: tempDir);

  Future<FullLiveSessionResult> prepare(ToneReadChannel c, {AngelsProductPlan? plan}) =>
      MatriboxFullLiveSession(backupService: service(c), plan: plan ?? newPlan()).prepare();

  MatriboxFullLiveRecord certifiedAngelsRecord() => MatriboxFullLiveRecord(
    planId: AngelsProductPlan.planIdValue,
    beforeBackupPath: 'x',
    beforeBackupSha256: 'x',
    runOutcome: 'success',
    completed: 11,
    total: 11,
    sentAt: DateTime.utc(2026),
  ).withReadback('certified', DateTime.utc(2026), 'y');

  group('catalog resolution', () {
    test('Boost and Sol 4x12 come only from the catalog, exactly as the V2 translator selected them', () {
      final plan = newPlan();
      expect(plan.boost.name, 'Boost');
      expect(plan.boost.code, 0x0000001a);
      expect(plan.sol4x12.name, 'Sol 4x12');
      expect(plan.sol4x12.code, 0x0a000028);
      expect(identical(plan.boost, library.byName(MatriboxChainSlot.fx2, 'Boost')), isTrue);
      final catalogJson = jsonDecode(File('assets/catalog/matribox_preset_catalog.json').readAsStringSync()) as Map;
      int code(String category, String name) => ((catalogJson['algorithms'] as List)
          .cast<Map>()
          .firstWhere((a) => a['category'] == category && a['name'] == name))['code'] as int;
      expect(code('FX2', 'Boost'), 0x1a);
      expect(code('CAB', 'Sol 4x12'), 0x0a000028);
      // the V2 translator picked exactly these models
      expect(target[MatriboxChainSlot.fx2].model.value!.code, plan.boost.code);
      expect(target[MatriboxChainSlot.cab].model.value!.code, plan.sol4x12.code);
      // neither is capture-confirmed and neither is BritGN/BritMD of the big capture
      expect(matriboxCaptureConfirmedAlgorithms.any((a) => a.code == 0x1a || a.code == 0x0a000028), isFalse);
      expect(plan.sol4x12.code, isNot(matriboxCabBritGn.code));
      expect(plan.boost.selectEvidence, TransferProtocolEvidence.observed);
      expect(plan.sol4x12.selectEvidence, TransferProtocolEvidence.observed);
    });

    test('no arbitrary algorithm id or slot: the plan API takes a library and a target, nothing else', () {
      final source = File('lib/presets/matribox_angels_product_plan.dart')
          .readAsStringSync()
          .split(RegExp(r'\r?\n'))
          .map((l) => l.split('//').first)
          .join('\n');
      expect(source, contains('AngelsProductPlan({required this.library, this.target})'));
      expect(source, isNot(matches(RegExp(r'FullLiveOperation\.model\([^)]*0x'))));
      final channels = File('lib/screens/matribox_channel_clients.dart').readAsStringSync();
      expect(channels, contains("{'planId': planId}"));
      expect(channels.toLowerCase(), isNot(contains('algorithm')));
    });
  });

  group('exact plan', () {
    test('11 operations in the exact order: 2 MODEL, 5 PARAMETER, 4 BLOCK CC', () {
      final plan = newPlan();
      expect(plan.operations.map((o) => '${o.slot.label} ${o.label}'), [
        'FX1 BLOCK OFF',
        'FX2 MODEL Boost',
        'FX2 BLOCK ON',
        'AMP PARAM Gain = 67',
        'AMP PARAM PRES = 59',
        'AMP PARAM Bass = 41',
        'AMP PARAM Middle = 59',
        'AMP PARAM Treble = 61',
        'CAB MODEL Sol 4x12',
        'CAB BLOCK ON',
        'EQ BLOCK OFF',
      ]);
      expect((plan.modelCount, plan.parameterCount, plan.toggleCount), (2, 5, 4));
      expect(hex(newPlan().operations.expand((o) => o.bytes).toList()), hex(plan.operations.expand((o) => o.bytes).toList()));
    });

    test('model select comes before the dependent operations of its block', () {
      final ops = newPlan().operations;
      for (final slot in [MatriboxChainSlot.fx2, MatriboxChainSlot.cab]) {
        final model = ops.indexWhere((o) => o.slot == slot && o.kind == FullLiveOperationKind.modelSelect);
        final toggle = ops.indexWhere((o) => o.slot == slot && o.kind == FullLiveOperationKind.blockToggle);
        expect(model, lessThan(toggle), reason: slot.label);
      }
      // slots ascend along the chain
      final slots = ops.map((o) => o.slot.index).toList();
      expect(slots, [...slots]..sort());
    });

    test('no NR / MOD / DLY / RVB write, no AMP model select, no no-op against the known source', () {
      final plan = newPlan();
      final touched = plan.operations.map((o) => o.slot).toSet();
      expect(touched.intersection({MatriboxChainSlot.nr, MatriboxChainSlot.mod, MatriboxChainSlot.dly, MatriboxChainSlot.rvb}), isEmpty);
      expect(plan.operations.any((o) => o.slot == MatriboxChainSlot.amp && o.kind == FullLiveOperationKind.modelSelect), isFalse);
      final before = beforeLayout();
      for (final o in plan.operations) {
        switch (o.kind) {
          case FullLiveOperationKind.modelSelect:
            expect(before.code(o.slot), isNot(o.algorithm!.code), reason: o.label);
          case FullLiveOperationKind.parameter:
            expect((before.parameter(o.slot, o.parameter!.wireIndex) - o.value!).abs(), greaterThan(0.5), reason: o.label);
          case FullLiveOperationKind.blockToggle:
            expect(before.isOn(o.slot), isNot(o.enabled), reason: o.label);
        }
      }
    });

    test('messages: 12 10 family only (model select 22 B, parameter 34 B, CC 3 B); never 12 11 / 12 12', () {
      for (final o in newPlan().operations) {
        final b = o.bytes;
        switch (o.kind) {
          case FullLiveOperationKind.modelSelect:
            expect(b.length, 22);
            expect(b.sublist(8, 13), [0x12, 0x10, o.slot.wireSlot, 0x00, 0x01]);
          case FullLiveOperationKind.parameter:
            expect(b.length, 34);
            expect(b.sublist(8, 13), [0x12, 0x10, o.slot.wireSlot, 0x00, 0x02]);
          case FullLiveOperationKind.blockToggle:
            expect(b, [0xb1, 0x2f + o.slot.wireSlot, o.enabled! ? 0x00 : 0x7f]);
        }
      }
    });

    test('AMP parameter messages equal the confirmed Sol 100 OD encoder; Kotlin golden hex is up to date', () {
      final ops = newPlan().operations.where((o) => o.kind == FullLiveOperationKind.parameter).toList();
      const fields = ['gain', 'presence', 'bass', 'middle', 'treble'];
      for (var i = 0; i < 5; i++) {
        final reference = MatriboxSol100OdEncoder.encode(fields[i], ops[i].value!);
        expect(hex(ops[i].bytes.sublist(13)), hex(reference.sublist(13)), reason: fields[i]);
      }
      final golden = RegExp(r'"([0-9a-f ]+)",')
          .allMatches(File('android/app/src/test/kotlin/de/neevel/wyrmtone/MatriboxAngelsGolden.kt').readAsStringSync())
          .map((m) => m.group(1)!)
          .toList();
      expect(golden, newPlan().operations.map((o) => hex(o.bytes)).toList());
    });
  });

  group('preparation and source precondition', () {
    test('a fresh read is mandatory, the backup and its hash too', () async {
      final read = ToneReadChannel(hexParts(bigBeforeRawPartsHex));
      final result = await prepare(read);
      expect(read.reads, 1);
      expect(result.readyForFullLiveTest, isTrue, reason: '${result.blockedReason}');
      expect(result.backup!.sha256, isNotNull);
      expect(File(result.backup!.filePath!).existsSync(), isTrue);
      expect(result.current!.name, AngelsCertificationSource.presetName);

      final failing = ToneReadChannel(hexParts(bigBeforeRawPartsHex))..fail = true;
      final blocked = await prepare(failing);
      expect(blocked.readyForFullLiveTest, isFalse);
      expect(blocked.blockedReason, contains('Kein gültiges Backup'));
    });

    test('the certification source constants are exactly the decoded real BEFORE state', () {
      final l = beforeLayout();
      expect(l.name, AngelsCertificationSource.presetName);
      for (final s in MatriboxChainSlot.values) {
        expect(l.code(s), AngelsCertificationSource.codes[s], reason: s.label);
        expect(l.isOn(s), AngelsCertificationSource.blockStates[s], reason: s.label);
      }
      for (final e in AngelsCertificationSource.ampParameters.entries) {
        expect(l.parameter(MatriboxChainSlot.amp, e.key), e.value);
      }
    });

    test('the production Sound Engine V2 diff against the known source equals the certification plan', () async {
      final plan = newPlan();
      expect(plan.blockers(beforeLayout()), isEmpty);
      expect(plan.blockCode(beforeLayout()), isNull);
      final production = MatriboxToneTransferPlan.build(
        current: beforeLayout(), target: target, ledger: baselineLedger, backupSha256: 'x',
        presetNumber: 11, isUserBank: true, transportAvailable: true, library: library,
      );
      final changes = production.entries.where((e) => e.isChange).toList();
      expect(changes.length, 11);
      expect(changes.map((e) => e.intended.name).where((n) => n == 'selectModel').length, 2);
      // a different production target is a PLAN_MISMATCH, never silently another plan
      final other = AngelsProductPlan(library: library, target: readyTarget());
      expect(other.blockCode(beforeLayout()), 'PLAN_MISMATCH');
    });

    test('a wrong source preset blocks execution (SOURCE_PRESET_MISMATCH), nothing is sent', () async {
      for (final mutate in <void Function(List<List<int>>)>[
        (p) => setDecoded(p, MatriboxPresetLayout.codeOffset(MatriboxChainSlot.dly), u32(0x0b000006)),
        (p) => setDecoded(p, MatriboxPresetLayout.stateOffset(MatriboxChainSlot.nr), u16(0)),
        (p) => setDecoded(p, MatriboxPresetLayout.parametersBase(MatriboxChainSlot.amp), f32(40)),
        (p) => setDecoded(p, MatriboxPresetLayout.nameOffset, [0x41, 0x41]),
      ]) {
        final parts = hexParts(bigBeforeRawPartsHex);
        mutate(parts);
        final result = await prepare(ToneReadChannel(parts));
        expect(result.readyForFullLiveTest, isFalse);
        expect(result.blockCode, 'SOURCE_PRESET_MISMATCH');
        expect(result.blockedReason, contains('SOURCE_PRESET_MISMATCH'));
        final channel = PlanRunChannel(newPlan());
        final run = await MatriboxFullLiveExecutor(channel: channel, store: store, plan: newPlan()).execute(result);
        expect(run.outcome, FullLiveRunOutcome.safetyRejected);
        expect(channel.planIds, isEmpty);
      }
    });

    test('a P01 that already holds the target is refused (ALREADY_AT_TARGET) instead of sending', () async {
      final parts = afterFromCertificationOps(newPlan().operations);
      final result = await prepare(ToneReadChannel(parts));
      expect(result.readyForFullLiveTest, isFalse);
      expect(result.blockCode, 'ALREADY_AT_TARGET');
      final channel = PlanRunChannel(newPlan());
      await MatriboxFullLiveExecutor(channel: channel, store: store, plan: newPlan()).execute(result);
      expect(channel.planIds, isEmpty);
    });

    test('a Factory bank read is refused', () async {
      final parts = hexParts(bigBeforeRawPartsHex)..forEach((p) => p[13] = 0x01);
      expect((await prepare(ToneReadChannel(parts))).readyForFullLiveTest, isFalse);
    });
  });

  group('execution', () {
    test('one channel call with the plan id only; record keeps the BEFORE backup; volatile', () async {
      final ready = await prepare(ToneReadChannel(hexParts(bigBeforeRawPartsHex)));
      final channel = PlanRunChannel(newPlan());
      final result = await MatriboxFullLiveExecutor(channel: channel, store: store, plan: newPlan()).execute(ready);
      expect(result.isSuccess, isTrue);
      expect(channel.planIds, [AngelsProductPlan.planIdValue]);
      expect((result.completed, result.total), (11, 11));
      final record = (await store.load())!;
      expect(record.planId, AngelsProductPlan.planIdValue);
      expect(record.beforeBackupSha256, ready.backup!.sha256);
      expect(record.state, FullLiveRecordState.sent);
    });

    test('the first failure stops the run and reports completed / failed / notSent, without retry', () async {
      final ready = await prepare(ToneReadChannel(hexParts(bigBeforeRawPartsHex)));
      final channel = PlanRunChannel(newPlan(), failAt: 4);
      final result = await MatriboxFullLiveExecutor(channel: channel, store: store, plan: newPlan()).execute(ready);
      expect(result.isSuccess, isFalse);
      expect(channel.planIds, hasLength(1)); // no retry
      expect((result.completed, result.failedIndex), (4, 4));
      expect(result.notSent, hasLength(6));
      expect((await store.load())!.completed, 4);
    });

    test('no Store, no metadata: no Store/12 11/12 12 in the plan, panel or transport code', () {
      for (final f in [
        'lib/presets/matribox_angels_product_plan.dart',
        'lib/presets/matribox_certification_plan.dart',
        'lib/screens/matribox_angels_certification_panel.dart',
        'lib/screens/matribox_channel_clients.dart',
      ]) {
        final source = File(f).readAsStringSync().split(RegExp(r'\r?\n')).map((l) => l.split('//').first).join('\n');
        expect(source, isNot(matches(RegExp(r'0x12,\s*0x12|0x12,\s*0x11'))), reason: f);
        expect(source, isNot(matches(RegExp(r'presetName\(|presetBpm\(|presetVolume\(|restore\w*\(|retry\w*\(', caseSensitive: false))), reason: f);
      }
    });
  });

  group('readback', () {
    Future<(MatriboxFullLiveRecord, FullLiveSessionResult)> sent() async {
      final ready = await prepare(ToneReadChannel(hexParts(bigBeforeRawPartsHex)));
      await MatriboxFullLiveExecutor(channel: PlanRunChannel(newPlan()), store: store, plan: newPlan()).execute(ready);
      return ((await store.load())!, ready);
    }

    Future<FullLiveReadbackResult> readback(MatriboxFullLiveRecord r, List<List<int>> parts) =>
        MatriboxFullLiveReadback.run(record: r, backupService: service(ToneReadChannel(parts)), store: store, plan: newPlan());

    test('the exact expected state is CERTIFIED: models, five AMP parameters, block states, untouched blocks, Part 8 correlated', () async {
      final (record, _) = await sent();
      final result = await readback(record, afterFromCertificationOps(newPlan().operations));
      expect(result.outcome, FullLiveReadbackOutcome.certified, reason: '${result.detail}');
      final v = result.verification!;
      expect(v.operations, hasLength(11));
      expect(v.operations.every((o) => o.check == FullLiveOperationCheck.matched), isTrue);
      expect(v.untouchedSlots, [MatriboxChainSlot.nr, MatriboxChainSlot.mod, MatriboxChainSlot.dly, MatriboxChainSlot.rvb]);
      expect(v.count(FullLiveChangeClass.correlatedPart8Change), greaterThan(0));
      expect(v.count(FullLiveChangeClass.unexpectedKnownChange), 0);
      expect(v.count(FullLiveChangeClass.unknownRawChange), 0);
      expect((await store.load())!.readbackOutcome, 'certified');
    });

    test('a missing model select, AMP parameter or block state is a TARGET_MISMATCH', () async {
      final (record, _) = await sent();
      final ops = newPlan().operations;
      for (final skipLabel in ['FX2 MODEL Boost', 'AMP PARAM Bass = 41', 'CAB BLOCK ON', 'EQ BLOCK OFF', 'CAB MODEL Sol 4x12']) {
        final partial = ops.where((o) => '${o.slot.label} ${o.label}' != skipLabel).toList();
        final result = await readback(record, afterFromCertificationOps(partial));
        expect(result.outcome, FullLiveReadbackOutcome.expectedChangeMissing, reason: skipLabel);
        expect(result.verification!.operations.where((o) => o.check == FullLiveOperationCheck.mismatch), hasLength(1), reason: skipLabel);
      }
    });

    test('the AMP model must still be Sol 100 OD afterwards', () async {
      final (record, _) = await sent();
      final parts = afterFromCertificationOps(newPlan().operations);
      setDecoded(parts, MatriboxPresetLayout.codeOffset(MatriboxChainSlot.amp), u32(0x07000035));
      final result = await readback(record, parts);
      expect(result.outcome, isNot(FullLiveReadbackOutcome.certified));
      expect(result.verification!.requiredModelViolations, isNotEmpty);
    });

    test('untouched blocks: a changed NR/RVB model, MOD parameter or DLY state is an UNEXPECTED_KNOWN_CHANGE', () async {
      final (record, _) = await sent();
      final cases = <void Function(List<List<int>>)>[
        (p) => setDecoded(p, MatriboxPresetLayout.codeOffset(MatriboxChainSlot.nr), u32(0x1b)),
        (p) => setDecoded(p, MatriboxPresetLayout.parametersBase(MatriboxChainSlot.mod), f32(77)),
        (p) => setDecoded(p, MatriboxPresetLayout.stateOffset(MatriboxChainSlot.dly), u16(1)),
        (p) => setDecoded(p, MatriboxPresetLayout.stateOffset(MatriboxChainSlot.rvb), u16(0)),
      ];
      for (final mutate in cases) {
        final parts = afterFromCertificationOps(newPlan().operations);
        mutate(parts);
        expect((await readback(record, parts)).outcome, FullLiveReadbackOutcome.unexpectedKnownChange);
      }
    });

    test('an unwritten AMP parameter (Master) that changed is unexpected; an unknown raw byte fails the certification', () async {
      final (record, _) = await sent();
      final master = afterFromCertificationOps(newPlan().operations);
      setDecoded(master, MatriboxPresetLayout.parametersBase(MatriboxChainSlot.amp) + 8, f32(99));
      expect((await readback(record, master)).outcome, FullLiveReadbackOutcome.unexpectedKnownChange);
      final raw = afterFromCertificationOps(newPlan().operations);
      setDecoded(raw, 700, [0x55]);
      final result = await readback(record, raw);
      expect(result.outcome, FullLiveReadbackOutcome.unknownRawChange);
      expect(result.isCertified, isFalse);
    });

    test('an incomplete run can never be CERTIFIED (PARTIAL_EXECUTION); a failed read is READ_FAILED', () async {
      final ready = await prepare(ToneReadChannel(hexParts(bigBeforeRawPartsHex)));
      await MatriboxFullLiveExecutor(channel: PlanRunChannel(newPlan(), failAt: 6), store: store, plan: newPlan()).execute(ready);
      final record = (await store.load())!;
      final result = await readback(record, afterFromCertificationOps(newPlan().operations));
      expect(result.outcome, FullLiveReadbackOutcome.partialExecution);
      expect((await store.load())!.readbackOutcome, 'partialExecution');

      final (sentRecord, _) = await sent();
      final failing = ToneReadChannel(hexParts(bigBeforeRawPartsHex))..fail = true;
      final failed = await MatriboxFullLiveReadback.run(record: sentRecord, backupService: service(failing), store: store, plan: newPlan());
      expect(failed.outcome, FullLiveReadbackOutcome.readFailed);
    });
  });

  group('evidence upgrade', () {
    test('before the test nothing of the plan is hardware-eligible except Gain and Presence', () {
      final plan = MatriboxToneTransferPlan.build(
        current: beforeLayout(), target: target, ledger: certifiedLedger, backupSha256: 'x',
        presetNumber: 11, isUserBank: true, transportAvailable: true, library: library,
      );
      // even with a certified Full Live the two catalog model selects stay blocked
      final blocked = plan.entries.where((e) => e.eligibility == ToneSendEligibility.blockedByEvidence).map((e) => '${e.slot.label}.${e.subject}');
      expect(blocked, ['FX2.MODEL', 'CAB.MODEL']);
      expect(plan.overall, ToneTransferOverall.blocked);
    });

    test('CERTIFIED upgrades exactly the tested operations and the Angels plan becomes eligible; only the transport blocks', () {
      final angelsLedger = baselineLedger.withCertification(newPlan(), certifiedAngelsRecord());
      MatriboxToneTransferPlan planWith(MatriboxHardwareLedger l, {bool transport = false}) => MatriboxToneTransferPlan.build(
        current: beforeLayout(), target: target, ledger: l, backupSha256: 'x',
        presetNumber: 11, isUserBank: true, transportAvailable: transport, library: library,
      );
      final plan = planWith(angelsLedger);
      final s = plan.summary;
      expect((s.modelsChanged, s.parametersChanged, s.blocksEnabled + s.blocksDisabled), (2, 5, 4));
      expect((s.blocked, s.unsupported, s.incomplete, s.unknownCurrent), (0, 0, 0, 0));
      expect(plan.operations, hasLength(11));
      // the ONLY remaining blocker is the missing productive transport
      expect(plan.blockers, hasLength(1));
      expect(plan.blockers.single, contains('Transport'));
      expect(planWith(angelsLedger, transport: true).overall, ToneTransferOverall.ready);
      expect(angelsLedger.source, contains('ANGELS_DONT_KILL_P01_V1'));
    });

    test('nothing beyond the exact operations is released: other models, parameters and toggles stay blocked', () {
      final ledger = baselineLedger.withCertification(newPlan(), certifiedAngelsRecord());
      final boost = library.byName(MatriboxChainSlot.fx2, 'Boost')!;
      final octaver = library.byName(MatriboxChainSlot.fx2, 'Octaver')!;
      final brit75 = library.byName(MatriboxChainSlot.cab, 'Brit75 4x12')!;
      final sol = MatriboxTransferCatalog.byName('Sol 100 OD')!;
      expect(ledger.model(MatriboxChainSlot.fx2, boost).exact, isTrue);
      expect(ledger.model(MatriboxChainSlot.fx2, octaver).confirmed, isFalse); // no automatic catalog generalization
      expect(ledger.model(MatriboxChainSlot.fx1, boost).confirmed, isFalse); // exact slot only
      expect(ledger.model(MatriboxChainSlot.cab, brit75).confirmed, isFalse);
      expect(ledger.parameter(MatriboxChainSlot.amp, sol, sol.algorithm.parameter('Bass')).exact, isTrue);
      expect(ledger.parameter(MatriboxChainSlot.amp, sol, sol.algorithm.parameter('Master')).confirmed, isFalse);
      expect(ledger.toggle(MatriboxChainSlot.fx1, false).exact, isTrue);
      expect(ledger.toggle(MatriboxChainSlot.fx2, true).exact, isTrue);
      expect(ledger.toggle(MatriboxChainSlot.cab, true).exact, isTrue);
      expect(ledger.toggle(MatriboxChainSlot.eq, false).exact, isTrue);
      expect(ledger.toggle(MatriboxChainSlot.dly, true).confirmed, isFalse);
      expect(ledger.toggle(MatriboxChainSlot.fx2, false).confirmed, isFalse);
      expect(MatriboxHardwareLedger.proposedCatalogSelectRule, contains('nicht aktiv'));
    });

    test('a failed, partial or wrong-plan record upgrades nothing', () {
      MatriboxFullLiveRecord rec({String? outcome, int completed = 11, String? planId}) => MatriboxFullLiveRecord(
        planId: planId ?? AngelsProductPlan.planIdValue, beforeBackupPath: 'x', beforeBackupSha256: 'x', runOutcome: 'success',
        completed: completed, total: 11, sentAt: DateTime.utc(2026),
      ).withReadback(outcome ?? 'certified', DateTime.utc(2026), 'y');
      final boost = library.byName(MatriboxChainSlot.fx2, 'Boost')!;
      for (final r in [
        null,
        rec(outcome: 'expectedChangeMissing'),
        rec(outcome: 'unknownRawChange'),
        rec(outcome: 'partialExecution'),
        rec(completed: 6),
        rec(planId: MatriboxFullLivePlan.planId),
      ]) {
        final ledger = baselineLedger.withCertification(newPlan(), r);
        expect(ledger.model(MatriboxChainSlot.fx2, boost).confirmed, isFalse);
        expect(ledger.exactModels, isEmpty);
      }
      // the Full Live record is a different plan and keeps its own evidence
      expect(certifiedLedger.modelSlots, hasLength(9));
    });
  });
}
