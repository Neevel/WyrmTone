import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_angels_product_plan.dart';
import 'package:wyrmtone/presets/matribox_chain_catalog.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_evidence_v2.dart';
import 'package:wyrmtone/presets/matribox_family_expansion_certification.dart';
import 'package:wyrmtone/presets/matribox_full_live_plan.dart';
import 'package:wyrmtone/presets/matribox_full_live_session.dart';
import 'package:wyrmtone/presets/matribox_hardware_evidence.dart';
import 'package:wyrmtone/presets/matribox_model_library.dart';
import 'package:wyrmtone/presets/matribox_preset_layout.dart';
import 'package:wyrmtone/presets/matribox_raw_backup_service.dart';
import 'package:wyrmtone/screens/matribox_channel_clients.dart';

import 'support/matribox_big_capture_snapshots.dart';
import 'support/matribox_family_expansion_support.dart';
import 'support/matribox_full_live_helpers.dart';
import 'support/matribox_tone_transfer_support.dart';

const _base = 'android/app/src/main/kotlin/de/neevel/wyrmtone/';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = MatriboxModelLibrary.fromVendor(toneCatalog);
  final plan = FamilyExpansionP01Plan(library);

  MatriboxChainParameter parameterOf(MatriboxChainSlot slot, String name) =>
      plan.operations.singleWhere((o) => o.slot == slot && o.parameter?.name == name).parameter!;
  FullLiveOperation op(MatriboxChainSlot slot, String label) =>
      plan.operations.singleWhere((o) => o.slot == slot && o.label == label);
  ByteData payload(FullLiveOperation o) {
    final b = o.bytes;
    final raw = Uint8List.fromList([for (var i = 0; i < 10; i++) (b[13 + 2 * i] << 4) | b[14 + 2 * i]]);
    return ByteData.sublistView(raw);
  }

  group('exact semantic plan', () {
    test('23 operations, chain order, Tier B included (the fachlich described actions sum to 23, not 22)', () {
      expect([for (final o in plan.operations) '${o.slot.label} ${o.label}'], [
        'FX1 MODEL Boost',
        'FX2 MODEL Boost', 'FX2 PARAM Gain = 23', 'FX2 PARAM Bright = 1',
        'AMP MODEL Sol 100 OD',
        'NR MODEL Gate 2', 'NR PARAM THRE = 31', 'NR BLOCK ON',
        'CAB MODEL Sol 4x12', 'CAB PARAM VOL = 43',
        'EQ MODEL Guitar EQ', 'EQ PARAM 400Hz = -23', 'EQ BLOCK ON',
        'MOD MODEL Chorus A', 'MOD PARAM Rate = 3.7',
        'DLY MODEL Warm', 'DLY PARAM Time = 743', 'DLY PARAM Trail = 1',
        'RVB MODEL Room', 'RVB PARAM Mix = 23', 'RVB PARAM Decay = 41', 'RVB PARAM Trail = 1', 'RVB BLOCK ON',
      ]);
      expect((plan.modelCount, plan.parameterCount, plan.toggleCount), (9, 11, 3));
      // FX2 3 + NR 3 + CAB 2 + EQ 3 + MOD 2 + DLY 3 + RVB 5 = 21 Tier A, plus 2 Tier B = 23
      expect(plan.offline.operations().length, 21);
      expect(plan.offline.operations(includeOptional: true).length, 23);
    });

    test('deterministic: slots ascend, inside a slot select, parameters, block CC', () {
      expect(plan.operations.map((o) => o.slot.index).toList(), [for (final o in plan.operations) o.slot.index]..sort());
      for (final slot in MatriboxChainSlot.values) {
        final kinds = [for (final o in plan.operations.where((o) => o.slot == slot)) o.kind.index];
        expect(kinds, [...kinds]..sort(), reason: slot.label);
      }
      expect(FamilyExpansionP01Plan(library).operations.map((o) => o.label), plan.operations.map((o) => o.label));
    });

    test('Tier B, P01-only and USER-only are part of the contract', () {
      expect(plan.operations.first.slot, MatriboxChainSlot.fx1);
      expect(plan.operations.any((o) => o.slot == MatriboxChainSlot.amp && o.label == 'MODEL Sol 100 OD'), isTrue);
      expect(FamilyExpansionP01Plan.planIdValue, 'FAMILY_EXPANSION_P01_V1');
    });

    test('models and parameters resolve from the manufacturer catalog only', () {
      for (final o in plan.operations.where((o) => o.algorithm != null)) {
        final entries = toneCatalog.algorithms.where((a) => a.code == o.algorithm!.code && a.name == o.algorithm!.name).toList();
        // the slot's own category (FX1 and FX2 list the same algorithm twice)
        final entry = entries.singleWhere((a) => a.category == o.slot.label);
        if (o.parameter != null) {
          final p = entry.parameters.singleWhere((p) => p.name == o.parameter!.name);
          expect(p.index, o.parameter!.catalogIndex);
          expect(o.value! >= (p.minimum ?? 0) || o.parameter!.kind == MatriboxParameterKind.flag, isTrue, reason: o.label);
        }
      }
    });
  });

  group('encodings', () {
    test('wire index = editor ID - 1: CAB VOL (ID 2) is wire 1, Boost Bright (ID 3) is wire 2', () {
      final vol = parameterOf(MatriboxChainSlot.cab, 'VOL');
      expect((vol.catalogIndex, vol.wireIndex), (0, 1));
      expect(payload(op(MatriboxChainSlot.cab, 'PARAM VOL = 43')).getUint16(4, Endian.little), 1);
      final bright = parameterOf(MatriboxChainSlot.fx2, 'Bright');
      expect((bright.catalogIndex, bright.wireIndex), (1, 2));
      expect(payload(op(MatriboxChainSlot.fx2, 'PARAM Bright = 1')).getUint16(4, Endian.little), 2);
      // every other planned parameter has gapless IDs: wire == catalog index
      for (final o in plan.operations.where((o) => o.parameter != null)) {
        final p = o.parameter!;
        final expectedGap = (o.slot == MatriboxChainSlot.cab && p.name == 'VOL') || (o.slot == MatriboxChainSlot.fx2 && p.name == 'Bright');
        expect(p.wireIndex == p.catalogIndex, !expectedGap, reason: o.label);
      }
    });

    test('signed -23, decimal 3.7, Time 743 and flags encode as little-endian float32', () {
      double value(MatriboxChainSlot s, String label) => payload(op(s, label)).getFloat32(6, Endian.little);
      expect(value(MatriboxChainSlot.eq, 'PARAM 400Hz = -23'), -23);
      expect(payload(op(MatriboxChainSlot.mod, 'PARAM Rate = 3.7')).getUint32(6, Endian.little), ByteData(4).also((d) => d.setFloat32(0, 3.7, Endian.little)).getUint32(0, Endian.little));
      expect(value(MatriboxChainSlot.dly, 'PARAM Time = 743'), 743);
      for (final (slot, label) in [
        (MatriboxChainSlot.fx2, 'PARAM Bright = 1'),
        (MatriboxChainSlot.dly, 'PARAM Trail = 1'),
        (MatriboxChainSlot.rvb, 'PARAM Trail = 1'),
      ]) {
        expect(value(slot, label), 1, reason: '$slot $label');
        expect(parameterOf(slot, label.split(' ')[1]).kind, MatriboxParameterKind.flag);
      }
    });

    test('block CC ON is B1 controller 00 for NR, EQ and RVB', () {
      expect([for (final o in plan.operations.where((o) => o.kind == FullLiveOperationKind.blockToggle)) o.bytes], [
        [0xb1, 0x33, 0x00],
        [0xb1, 0x35, 0x00],
        [0xb1, 0x38, 0x00],
      ]);
    });

    test('no store, no 12 11 metadata, no 12 12 commit; every message is 3, 22 or 34 bytes', () {
      for (final o in plan.operations) {
        expect(o.bytes.length, anyOf(3, 22, 34));
        if (o.bytes.length > 3) expect(o.bytes.sublist(8, 10), [0x12, 0x10], reason: o.label);
      }
    });

    test('Flanger Sync / Time Sync / ATK / Rel are untouched', () {
      final names = [for (final o in plan.operations) o.parameter?.name].whereType<String>();
      expect(names.where((n) => n.contains('Sync') || n == 'ATK' || n == 'Rel'), isEmpty);
    });
  });

  group('start-state blockers (nothing is sent when a family would not be observable)', () {
    test('the Angels source / BEFORE preset blocks: five selects and three toggles are not observable', () {
      final blockers = plan.blockers(beforeLayout());
      expect(blockers.where((b) => b.startsWith('SELECT_NOT_OBSERVABLE')), isNotEmpty);
      expect(blockers.where((b) => b.startsWith('TOGGLE_NOT_OBSERVABLE')), isNotEmpty);
      expect(plan.blockCode(beforeLayout()), isNotNull);
    });

    test('a suitable start state passes', () {
      final layout = layoutOf(suitableStartParts());
      expect(plan.blockers(layout), isEmpty);
      expect(plan.blockCode(layout), isNull);
    });

    test('FX2 Boost and CAB Sol 4x12 may already be active (exactly confirmed, clean start)', () {
      final parts = suitableStartParts();
      setDecoded(parts, MatriboxPresetLayout.codeOffset(MatriboxChainSlot.fx2), u32(0x1a));
      setDecoded(parts, MatriboxPresetLayout.codeOffset(MatriboxChainSlot.cab), u32(0x0a000028));
      expect(plan.blockers(layoutOf(parts)), isEmpty);
    });
  });

  group('closed channel: plan id + verified backup hash only', () {
    test('the method channel sends exactly planId, targetBank USER, targetSlot 1 and backupHash', () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('de.neevel.wyrmtone/usb_methods');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return <Object?, Object?>{};
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      await const MethodChannelFamilyExpansionChannel().runFamilyExpansionP01Certification(
        planId: FamilyExpansionP01Plan.planIdValue,
        backupSha256: 'a' * 64,
      );
      expect(calls.single.method, 'runFamilyExpansionP01Certification');
      expect(calls.single.arguments, {
        'planId': 'FAMILY_EXPANSION_P01_V1',
        'targetBank': 'USER',
        'targetSlot': 1,
        'backupHash': 'a' * 64,
      });
    });

    test('no raw bytes, algorithm id, parameter index or operation crosses the channel (source)', () {
      final source = File('lib/screens/matribox_channel_clients.dart').readAsStringSync();
      final start = source.indexOf('class MethodChannelFamilyExpansionChannel');
      final body = source.substring(start, source.indexOf('/// The productive transport'));
      for (final forbidden in ['bytes', 'algorithm', 'parameterIndex', 'operations', 'sysex', 'code']) {
        expect(body.toLowerCase(), isNot(contains(forbidden.toLowerCase())), reason: forbidden);
      }
      final panel = File('lib/screens/matribox_family_expansion_panel.dart').readAsStringSync();
      expect(panel, isNot(contains('invokeMethod')));
      expect(panel, isNot(contains('invokeMapMethod')));
    });

    test('the run adapter refuses every other plan id', () async {
      final inner = _Recorder();
      final adapter = FamilyExpansionRunChannel(inner, 'b' * 64);
      expect(() => adapter.runFullLiveP01Certification(MatriboxFullLivePlan.planId), throwsStateError);
      expect(() => adapter.runFullLiveP01Certification(AngelsProductPlan.planIdValue), throwsStateError);
      expect(inner.calls, isEmpty);
      await adapter.runFullLiveP01Certification(FamilyExpansionP01Plan.planIdValue);
      expect(inner.calls, [('FAMILY_EXPANSION_P01_V1', 'b' * 64)]);
    });
  });

  group('manual-save checkpoint', () {
    test('order is enforced and confirming needs no channel (zero MIDI)', () {
      final cp = FamilyExpansionCheckpoint();
      expect(cp.mayVerify, isFalse);
      expect(cp.confirmPhysicalCheck, throwsStateError); // before the live write
      cp.liveWriteEnded();
      expect(cp.confirmManualSave, throwsStateError); // physical check first
      expect(cp.mayVerify, isFalse);
      cp.confirmPhysicalCheck();
      expect(cp.mayVerify, isFalse);
      cp.confirmManualSave();
      expect(cp.mayVerify, isTrue);
      cp.reset();
      expect(cp.mayVerify, isFalse);
    });

    test('verification cannot start (and reads nothing) before the manual-save confirmation', () async {
      final read = ToneReadChannel(hexParts(bigBeforeRawPartsHex));
      final dir = Directory.systemTemp.createTempSync('family_verify');
      addTearDown(() => dir.deleteSync(recursive: true));
      final cp = FamilyExpansionCheckpoint()
        ..liveWriteEnded()
        ..confirmPhysicalCheck();
      final record = MatriboxFullLiveRecord(
        planId: plan.planId,
        beforeBackupPath: 'x',
        beforeBackupSha256: 'x',
        runOutcome: 'success',
        completed: 23,
        total: 23,
        sentAt: DateTime.utc(2026),
      );
      expect(
        () => verifyFamilyExpansionAfterManualSave(
          checkpoint: cp,
          record: record,
          backupService: MatriboxRawBackupService(channel: read, backupDirectory: dir),
          store: MatriboxFullLiveStore(File('${dir.path}/s.state')),
          plan: plan,
        ),
        throwsStateError,
      );
      expect(read.reads, 0);
    });

    test('result labels; Part8 stays CORRELATED and is never a checksum', () {
      expect(familyExpansionResultLabel(FullLiveReadbackOutcome.certified), 'CERTIFIED');
      expect(familyExpansionResultLabel(FullLiveReadbackOutcome.expectedChangeMissing), 'TARGET_MISMATCH');
      expect(familyExpansionResultLabel(FullLiveReadbackOutcome.unexpectedKnownChange), 'UNEXPECTED_KNOWN_CHANGE');
      expect(familyExpansionResultLabel(FullLiveReadbackOutcome.unknownRawChange), 'UNKNOWN_RAW_CHANGE');
      expect(familyExpansionResultLabel(FullLiveReadbackOutcome.readFailed), 'READ_FAILED');
      expect(familyExpansionSuccessLabel, 'MANUAL_SAVE_PERSISTENCE_VERIFIED');
      final verifier = File('lib/presets/matribox_full_live_verifier.dart').readAsStringSync();
      expect(verifier, contains('korreliert, nicht als Prüfsumme benannt'));
      expect(verifier.toLowerCase(), isNot(contains('confirmed checksum')));
    });
  });

  group('promotion of the certified families', () {
    test('the family map is PROMOTED; only the decimal family has no productive parameter (bound to Sync)', () {
      expect(FamilyExpansionEvidenceUpgrades.active, isTrue);
      final upgrades = FamilyExpansionEvidenceUpgrades.forPlan(plan);
      expect(upgrades.map((u) => u.family), [
        'MODEL_SELECT_SLOT_FAMILY',
        'NUMBER_FAMILY',
        'SIGNED_FAMILY',
        'DECIMAL_FAMILY',
        'FLAG_FAMILY',
        'BLOCK_CC_FAMILY',
      ]);
      expect({for (final u in upgrades) u.family: u.status}, {
        'MODEL_SELECT_SLOT_FAMILY': 'PROMOTED',
        'NUMBER_FAMILY': 'PROMOTED',
        'SIGNED_FAMILY': 'PROMOTED',
        'DECIMAL_FAMILY': 'PROMOTED_BLOCKED_BY_BIND',
        'FLAG_FAMILY': 'PROMOTED',
        'BLOCK_CC_FAMILY': 'PROMOTED',
      });
      final byFamily = {for (final u in upgrades) u.family: u};
      expect(byFamily['MODEL_SELECT_SLOT_FAMILY']!.slots, MatriboxChainSlot.values);
      expect(byFamily['NUMBER_FAMILY']!.slots.map((s) => s.label), ['FX2', 'NR', 'CAB', 'DLY', 'RVB']);
      expect(byFamily['SIGNED_FAMILY']!.slots, [MatriboxChainSlot.eq]);
      expect(byFamily['DECIMAL_FAMILY']!.slots, [MatriboxChainSlot.mod]);
      expect(byFamily['FLAG_FAMILY']!.slots.map((s) => s.label), ['FX2', 'DLY', 'RVB']);
      expect(byFamily['BLOCK_CC_FAMILY']!.slots, MatriboxChainSlot.values);
    });

    test('with the productive ledger every plan operation is EXACT, except the bound Rate and Time which stay BLOCKED', () {
      final v2 = MatriboxEvidenceV2(
        library: library,
        samples: ActiveSamples.fromLedger(MatriboxHardwareLedger.product(), library),
      );
      for (final o in plan.operations) {
        final m = o.algorithm == null ? null : library.byCode(o.slot, o.algorithm!.code);
        final d = switch (o.kind) {
          FullLiveOperationKind.modelSelect => v2.modelSelect(o.slot, m!),
          FullLiveOperationKind.parameter => v2.parameter(o.slot, m!, o.parameter!, o.value!),
          FullLiveOperationKind.blockToggle => v2.blockToggle(o.slot, o.enabled!),
        };
        if (o.parameter?.bind != null) {
          expect(d.level, EvidenceLevel.blocked, reason: o.label);
          expect(d.basis, startsWith('BIND_UNRESOLVED'), reason: o.label);
        } else {
          expect(d.level, anyOf(EvidenceLevel.exactOperationConfirmed, EvidenceLevel.familyConfirmed), reason: o.label);
        }
      }
      final native = File('${_base}MatriboxToneTransferCatalog.kt').readAsStringSync();
      expect(native, isNot(contains('MatriboxFamilyExpansionPlan')));
    });

    test('heuristics stay off by default and are not used by this test', () {
      final translator = File('lib/presets/matribox_tone_translator.dart').readAsStringSync();
      expect(translator, contains('bool heuristics = false,'));
      expect(translator, contains("'HEURISTIC/DEVICE_APPROXIMATION: '"));
      for (final f in ['matribox_family_expansion_plan.dart', 'matribox_family_expansion_certification.dart']) {
        final source = File('lib/presets/$f').readAsStringSync();
        expect(source, isNot(contains('matribox_tone_translator')), reason: f);
        expect(source, isNot(contains('heuristics: true')), reason: f);
      }
    });
  });

  group('static safety', () {
    String code(String file) => File('$_base$file')
        .readAsStringSync()
        .split(RegExp(r'\r?\n'))
        .map((line) => line.split('//').first)
        .where((line) => !line.trimLeft().startsWith('*') && !line.trimLeft().startsWith('/*'))
        .join('\n');

    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    String line(String prefix) {
      final start = gradle.indexOf(prefix);
      expect(start, greaterThan(-1), reason: prefix);
      return gradle.substring(start, gradle.indexOf('\n', start));
    }

    test('own compile gate: default false, release false, exclusive with every other sender, not the productive gate', () {
      final family = line('val enableFamilyExpansion =');
      for (final other in [
        'requestedGain41Probe',
        'requestedPresetP01Probe',
        'requestedP01ReadProbe',
        'requestedP01FullReadProbe',
        'requestedP01FullReadProbeV3A',
        'requestedP01GainWrite',
        'requestedSol100OdCertification',
        'requestedFullLive',
        'requestedAngelsProduct',
        'requestedToneTransfer',
      ]) {
        expect(family, contains('!$other'), reason: other);
      }
      for (final flag in [
        'enableWriteProbe',
        'enablePresetP01Probe',
        'enableP01ReadProbe',
        'enableP01FullReadProbe',
        'enableP01FullReadProbeV3A',
        'enableP01GainWrite',
        'enableSol100OdCertification',
        'enableFullLive',
        'enableAngelsProduct',
        'enableToneTransfer',
      ]) {
        expect(line('val $flag ='), contains('!requestedFamilyExpansion'), reason: flag);
      }
      expect(gradle, contains('"ENABLE_MATRIBOX_FAMILY_EXPANSION_P01_V1", enableFamilyExpansion.toString()'));
      expect(gradle.substring(gradle.indexOf('release {')), contains('"ENABLE_MATRIBOX_FAMILY_EXPANSION_P01_V1", "false")'));
      final panel = File('lib/screens/matribox_family_expansion_panel.dart').readAsStringSync();
      expect(panel, contains("bool.fromEnvironment('ENABLE_MATRIBOX_FAMILY_EXPANSION_P01_V1', defaultValue: false)"));
      expect(panel, contains('kDebugMode'));
      expect(panel, isNot(contains('ENABLE_MATRIBOX_TONE_TRANSFER')));
      expect(code('MatriboxToneTransferSession.kt') + code('MatriboxToneTransferWriterPort.kt'), isNot(contains('FAMILY_EXPANSION')));
    });

    test('the channel case takes exactly four keys; no bytes, algorithm id or parameter index', () {
      final channels = File('${_base}UsbPlatformChannels.kt').readAsStringSync();
      final start = channels.indexOf('"runFamilyExpansionP01Certification" ->');
      expect(start, greaterThan(-1));
      final end = channels.indexOf('"getVerifiedMatriboxProbeStatus" ->', start);
      final block = channels.substring(start, end).split('\n').map((l) => l.split('//').first).join('\n');
      expect(block, contains('map.keys != setOf("planId", "targetBank", "targetSlot", "backupHash")'));
      for (final forbidden in ['algorithm', 'parameterIndex', 'ByteArray', 'sysex', 'operations']) {
        expect(block.toLowerCase(), isNot(contains(forbidden.toLowerCase())), reason: forbidden);
      }
      // still the same single send call site and no new input port
      final port = code('MatriboxFullLiveWriterPort.kt');
      expect(RegExp(r'\.send\s*\(').allMatches(port).length, 1);
      expect(port, contains('MatriboxCertificationPlans.permitted(fullLive, angels, familyExpansion)'));
      final manager = File('${_base}MidiDiagnosticsManager.kt').readAsStringSync();
      expect(RegExp(r'openInputPort\s*\(').allMatches(manager).length, 10);
    });

    test('the native plan has no store, metadata, send call, raw byte or retry API', () {
      final plan = code('MatriboxFamilyExpansionPlan.kt');
      expect(plan, isNot(matches(RegExp(r'0x12,\s*0x1[12]'))));
      expect(plan, isNot(matches(RegExp(r'\.send\s*\('))));
      expect(plan, isNot(matches(RegExp(r'ByteArray'))));
      expect(plan, isNot(matches(RegExp(r'fun\s+\w*([Ss]tore|[Rr]estore|[Rr]etry|[Cc]ommit)\w*\('))));
      expect(plan, contains('const val PLAN_ID = "FAMILY_EXPANSION_P01_V1"'));
      expect(plan, isNot(contains('forceClaim = true')));
    });

    test('nothing sends on open, connect, prepare or backup and nothing is started automatically', () {
      final panel = File('lib/screens/matribox_family_expansion_panel.dart').readAsStringSync();
      // the only call of the family channel is inside the confirmed start
      expect(RegExp(r'FamilyExpansionRunChannel\(').allMatches(panel).length, 1);
      expect(panel.indexOf('FamilyExpansionRunChannel('), greaterThan(panel.indexOf('Future<void> _start()')));
      expect(panel.substring(panel.indexOf('void initState()'), panel.indexOf('Future<MatriboxFullLiveStore> _store()')), isNot(contains('_start')));
      expect(File('lib/screens/home_page.dart').readAsStringSync(), contains('if (matriboxFamilyExpansionEnabled)'));
    });
  });
}

class _Recorder implements MatriboxFamilyExpansionChannel {
  final calls = <(String, String)>[];
  @override
  Future<Map<Object?, Object?>> runFamilyExpansionP01Certification({
    required String planId,
    required String backupSha256,
  }) async {
    calls.add((planId, backupSha256));
    return {};
  }
}

extension _Also<T> on T {
  T also(void Function(T) block) {
    block(this);
    return this;
  }
}
