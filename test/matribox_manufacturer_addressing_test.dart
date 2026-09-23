import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/device_catalog.dart';
import 'package:wyrmtone/presets/matribox_chain_catalog.dart';
import 'package:wyrmtone/presets/matribox_chain_encoder.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_evidence_v2.dart';
import 'package:wyrmtone/presets/matribox_hardware_evidence.dart';
import 'package:wyrmtone/presets/matribox_model_library.dart';
import 'package:wyrmtone/presets/matribox_parameter_addressing.dart';
import 'package:wyrmtone/presets/matribox_target_preset.dart';
import 'package:wyrmtone/presets/matribox_tone_transfer_plan.dart';
import 'package:wyrmtone/presets/matribox_transfer_catalog.dart';
import 'package:wyrmtone/presets/tone_intent.dart';

import '../tool/matribox_analyzer.dart' show readResource, ResourceNode;
import 'support/matribox_big_capture_groups.dart';
import 'support/matribox_tone_transfer_support.dart';

const _manufacturerXml = r'C:\Program Files\Sonicake\Matribox\Resource\Matribox\File\algorithm.xml';

Map<String, Object?> _param(
  String name,
  int? id, {
  int index = 0,
  String control = 'Knob',
  num? min = 0,
  num? max = 99,
  num? step,
  String? bind,
  String? subType,
  List<int> menus = const [],
}) => {
  'name': name,
  'index': index,
  'xmlId': ?id,
  'minimum': control == 'Knob' ? min : null,
  'maximum': control == 'Knob' ? max : null,
  'step': step,
  'xmlControlType': control,
  'bind': bind,
  'subType': subType,
  'menus': [for (final m in menus) {'id': m, 'name': 'm$m'}],
};

Map<String, Object?> _alg(String category, String name, int code, List<Map<String, Object?>> parameters) => {
  'category': category,
  'name': name,
  'code': code,
  'parameters': parameters,
};

void main() {
  final library = MatriboxModelLibrary.fromVendor(toneCatalog);
  final product = MatriboxEvidenceV2(
    library: library,
    samples: ActiveSamples.fromLedger(MatriboxHardwareLedger.product(), library),
  );
  MatriboxTransferModel m(MatriboxChainSlot s, String n) => library.byName(s, n)!;

  group('the central wire rule: wire = manufacturer ID - 1', () {
    test('the rule itself and its named constant', () {
      expect(matriboxWireParameterIndex(1), 0);
      expect(matriboxWireParameterIndex(3), 2);
      expect(matriboxWireIndexRule, 'wireParameterIndex = manufacturerParameterId - 1');
    });

    test('Boost Bright: idx 1, ID 3 -> wire 2 (idx must not be used); Gain idx 0, ID 1 -> wire 0', () {
      final boost = m(MatriboxChainSlot.fx2, 'Boost').algorithm;
      final bright = boost.parameter('Bright');
      expect((bright.catalogIndex, bright.xmlId, bright.wireIndex), (1, 3, 2));
      expect((boost.parameter('Gain').catalogIndex, boost.parameter('Gain').xmlId, boost.parameter('Gain').wireIndex), (0, 1, 0));
      // the encoder writes the WIRE index into the 34-byte message, never idx
      final bytes = MatriboxChainEncoder.parameterWrite(MatriboxChainSlot.fx2, boost, bright, 1);
      expect((bytes[13 + 8] << 4) | bytes[14 + 8], 2);
      expect((bytes[13 + 10] << 4) | bytes[14 + 10], 0);
    });

    test('CAB VOL (ID 2) -> wire 1 through the same generic rule, no CAB special case in the library', () {
      final vol = m(MatriboxChainSlot.cab, 'Sol 4x12').algorithm.parameter('VOL');
      expect((vol.catalogIndex, vol.xmlId, vol.wireIndex), (0, 2, 1));
      final source = File('lib/presets/matribox_model_library.dart').readAsStringSync();
      expect(source, isNot(contains('isCab')));
      expect(source, isNot(matches(RegExp(r'wireIndex:\s*\(?p\.index'))));
      expect(File('lib/presets/matribox_parameter_addressing.dart').readAsStringSync(), contains('manufacturerParameterId - 1'));
    });

    test('every ID gap of the manufacturer catalog is addressed by ID - 1: 65 parameters in 59 algorithm entries', () {
      var params = 0;
      final algorithms = <String>{};
      for (final a in toneCatalog.algorithms) {
        for (final p in a.parameters) {
          if (p.xmlId! - 1 != p.index) {
            params++;
            algorithms.add('${a.category}|${a.name}|${a.code}');
          }
        }
      }
      expect((params, algorithms.length), (65, 59));
      // in the library the wire index of every such parameter is ID - 1 (or blocked by an FX1/FX2 conflict)
      for (final slot in MatriboxChainSlot.values) {
        for (final model in library.forSlot(slot)) {
          for (final p in model.algorithm.parameters.where((p) => p.xmlId != null)) {
            expect(p.wireIndex, p.blockedReason != null ? -1 : p.xmlId! - 1, reason: '${slot.label} ${model.name}/${p.name}');
          }
        }
      }
    });

    test('all 46 parameter groups of the big capture agree with the rule', () {
      var checked = 0;
      for (final g in bigCaptureGroups) {
        final slot = MatriboxChainSlot.values[g.slot - 1];
        final model = library.byCode(slot, g.code);
        if (model == null || !model.algorithm.sendableInFullLive) continue;
        final hit = model.algorithm.parameters.where((p) => p.wireIndex == g.index && p.xmlId == g.index + 1);
        expect(hit, isNotEmpty, reason: '${slot.label} ${model.name} wire ${g.index}');
        checked++;
      }
      expect(checked, greaterThanOrEqualTo(44));
    });

    test('the normalized catalog agrees with the manufacturer XML on every ID (skipped when the XML is not installed)', () {
      final file = File(_manufacturerXml);
      if (!file.existsSync()) {
        markTestSkipped('algorithm.xml nicht vorhanden');
        return;
      }
      final root = readResource(file.readAsStringSync(), 'manufacturer').root;
      String attr(ResourceNode n, String key) => n.attributes[key]?.first.raw.trim() ?? '';
      final fromXml = <String>[];
      for (final catalog in root.all('Catalog')) {
        for (final alg in catalog.children.where((n) => n.name == 'Alg')) {
          for (final ResourceNode p in alg.children.where((n) => const ['Knob', 'Switch', 'Combox'].contains(n.name))) {
            fromXml.add('${attr(catalog, 'Name')}|${attr(alg, 'Code')}|${attr(p, 'Name')}|${attr(p, 'idx')}|${attr(p, 'ID')}|${attr(p, 'bind')}');
          }
        }
      }
      final fromCatalog = [
        for (final a in toneCatalog.algorithms)
          for (final p in a.parameters) '${a.category}|${a.code}|${p.name}|${p.index}|${p.xmlId}|${p.bind ?? ''}',
      ];
      expect(fromCatalog, fromXml);
    });
  });

  group('no idx fallback: a missing, invalid or duplicated ID BLOCKS the parameter', () {
    final synthetic = DevicePresetCatalog({
      'algorithms': [
        _alg('FX1', 'NoId', 900001, [_param('A', null)]),
        _alg('FX1', 'ZeroId', 900002, [_param('A', 0)]),
        _alg('FX1', 'NegativeId', 900003, [_param('A', -2)]),
        _alg('FX1', 'DuplicateId', 900004, [_param('A', 1), _param('B', 1, index: 1)]),
        _alg('FX1', 'TooLarge', 900005, [_param('A', 16)]),
        _alg('FX1', 'Fine', 900006, [_param('A', 1), _param('B', 2, index: 1)]),
      ],
    });
    final lib = MatriboxModelLibrary.fromVendor(synthetic);
    final samples = ActiveSamples(
      selects: [SelectSample(MatriboxChainSlot.fx1, 'x', SampleSource.catalogOnly)],
      parameters: [
        for (final s in [MatriboxChainSlot.fx1, MatriboxChainSlot.amp, MatriboxChainSlot.nr])
          ParameterSample(s, 'x', 'p', MatriboxParameterKind.number, SampleSource.catalogOnly),
      ],
    );
    final evidence = MatriboxEvidenceV2(library: lib, samples: samples);

    test('ParameterAddress.resolve', () {
      expect(ParameterAddress.resolve(null, [null]).blocked, isTrue);
      expect(ParameterAddress.resolve(0, [0]).blockedReason, startsWith('ID_INVALID'));
      expect(ParameterAddress.resolve(-2, [-2]).blockedReason, startsWith('ID_INVALID'));
      expect(ParameterAddress.resolve(1, [1, 1]).blockedReason, startsWith('ID_DUPLICATE'));
      expect(ParameterAddress.resolve(16, [16]).blockedReason, startsWith('ID_OUT_OF_RANGE'));
      expect(ParameterAddress.resolve(3, [1, 2, 3]).wireIndex, 2);
    });

    test('the library never falls back to idx; V2 says BLOCKED; the encoder refuses to encode it', () {
      for (final name in ['NoId', 'ZeroId', 'NegativeId', 'DuplicateId', 'TooLarge']) {
        final model = lib.byName(MatriboxChainSlot.fx1, name)!;
        for (final p in model.algorithm.parameters) {
          expect(p.blockedReason, isNotNull, reason: '$name/${p.name}');
          expect(p.wireIndex, -1, reason: '$name/${p.name}');
          expect(evidence.parameter(MatriboxChainSlot.fx1, model, p, 10).level, EvidenceLevel.blocked, reason: '$name/${p.name}');
          expect(() => MatriboxChainEncoder.parameterWrite(MatriboxChainSlot.fx1, model.algorithm, p, 10), throwsA(anything));
        }
      }
      final fine = lib.byName(MatriboxChainSlot.fx1, 'Fine')!;
      expect(fine.algorithm.parameter('B').wireIndex, 1);
      expect(evidence.parameter(MatriboxChainSlot.fx1, fine, fine.algorithm.parameter('B'), 10).sendable, isTrue);
    });
  });

  group('value types, enumerations and bind rules of the productive evidence', () {
    final synthetic = DevicePresetCatalog({
      'algorithms': [
        _alg('FX1', 'Types', 910001, [
          _param('Knob', 1),
          _param('Rate', 2, index: 1, min: 0.1, max: 10, step: 0.1),
          _param('Flag', 3, index: 2, control: 'Switch', menus: [0, 1]),
          _param('OddSwitch', 4, index: 3, control: 'Switch', menus: [0, 2]),
          _param('Mode', 5, index: 4, control: 'Combox', menus: [0, 1, 2]),
          _param('Bound', 6, index: 5, bind: 'Link'),
          _param('Link', 7, index: 6, control: 'Switch', subType: 'Power', menus: [0, 1]),
          _param('Signed', 8, index: 7, min: -50, max: 50),
        ]),
      ],
    });
    final lib = MatriboxModelLibrary.fromVendor(synthetic);
    final samples = ActiveSamples(
      selects: [SelectSample(MatriboxChainSlot.fx1, 'x', SampleSource.catalogOnly)],
      parameters: [
        for (final s in [MatriboxChainSlot.fx1, MatriboxChainSlot.amp, MatriboxChainSlot.nr])
          for (final k in MatriboxParameterKind.values) ParameterSample(s, 'x', 'p', k, SampleSource.catalogOnly),
      ],
    );
    final e = MatriboxEvidenceV2(library: lib, samples: samples);
    final model = lib.byName(MatriboxChainSlot.fx1, 'Types')!;
    EvidenceDecision d(String p, double v) => e.parameter(MatriboxChainSlot.fx1, model, model.algorithm.parameter(p), v);

    test('numeric range, negative, decimal (manufacturer step) and flag values', () {
      expect(d('Knob', 50).sendable, isTrue);
      expect(d('Knob', 100).level, EvidenceLevel.blocked);
      expect(d('Knob', -1).level, EvidenceLevel.blocked);
      expect(d('Signed', -23).sendable, isTrue);
      expect(d('Signed', -51).level, EvidenceLevel.blocked);
      expect(d('Rate', 3.7).sendable, isTrue);
      expect(d('Rate', 3.75).level, EvidenceLevel.blocked); // not on the 0.1 grid
      expect(d('Rate', 0.05).level, EvidenceLevel.blocked);
      expect(d('Flag', 1).sendable, isTrue);
      expect(d('Flag', 0).sendable, isTrue);
      expect(d('Flag', 0.5).level, EvidenceLevel.blocked);
      expect(d('Knob', double.nan).level, EvidenceLevel.blocked);
    });

    test('enumerations, odd switch menus, bind and the bind target are BLOCKED with a machine reason', () {
      expect(d('Mode', 1).basis, startsWith('ENUM_UNCONFIRMED'));
      expect(d('OddSwitch', 1).basis, startsWith('SWITCH_MENU_UNCONFIRMED'));
      expect(d('Bound', 10).basis, startsWith('BIND_UNRESOLVED'));
      expect(d('Link', 1).basis, startsWith('SYNC_SEMANTICS_UNKNOWN'));
    });
  });

  group('the productive families over the real manufacturer catalog', () {
    test('model select: every slot, any manufacturer algorithm of that slot is FAMILY/EXACT', () {
      for (final slot in MatriboxChainSlot.values) {
        final models = library.forSlot(slot).where((x) => !x.name.startsWith('User IR')).toList();
        expect(models, isNotEmpty, reason: slot.label);
        for (final model in models) {
          expect(product.modelSelect(slot, model).sendable, isTrue, reason: '${slot.label} ${model.name}');
        }
      }
    });

    test('an algorithm of another category, an unknown algorithm and User IR are blocked', () {
      expect(product.modelSelect(MatriboxChainSlot.amp, m(MatriboxChainSlot.rvb, 'Room')).level, EvidenceLevel.blocked);
      expect(product.modelSelect(MatriboxChainSlot.rvb, m(MatriboxChainSlot.cab, 'Sol 4x12')).level, EvidenceLevel.blocked);
      final fake = MatriboxTransferModel(
        algorithm: MatriboxChainAlgorithm(
          id: 'fake', name: 'Fake', code: 0x0700ffff, slots: {for (final s in MatriboxChainSlot.values) s}, parameters: const [],
        ),
        selectEvidence: TransferProtocolEvidence.observed,
        parameterEvidence: TransferProtocolEvidence.observed,
      );
      for (final slot in MatriboxChainSlot.values) {
        expect(product.modelSelect(slot, fake).level, EvidenceLevel.blocked, reason: slot.label);
      }
      final ir = m(MatriboxChainSlot.cab, 'User IR 7');
      expect(product.modelSelect(MatriboxChainSlot.cab, ir).basis, startsWith('USER_IR_BLOCKED'));
      expect(product.parameter(MatriboxChainSlot.cab, ir, ir.algorithm.parameter('VOL'), 43).basis, startsWith('USER_IR_BLOCKED'));
      // the 15 User IR entries have blank names and are not in the library at all
      expect(toneCatalog.algorithms.where((a) => (a.name ?? '').isEmpty).length, 15);
      expect(library.models.where((x) => x.name.isEmpty), isEmpty);
    });

    test('a parameter must belong to the model; hand-captured models carry the manufacturer metadata too', () {
      final sol = m(MatriboxChainSlot.amp, 'Sol 100 OD');
      final foreign = m(MatriboxChainSlot.rvb, 'Room').algorithm.parameter('Mix');
      expect(product.parameter(MatriboxChainSlot.amp, sol, foreign, 10).level, EvidenceLevel.blocked);
      final flanger = m(MatriboxChainSlot.mod, 'Flanger').algorithm;
      expect(flanger.parameter('Rate').bind, 'Sync'); // hand entry enriched from the manufacturer XML
      expect(product.parameter(MatriboxChainSlot.mod, m(MatriboxChainSlot.mod, 'Flanger'), flanger.parameter('Rate'), 3.7).basis, startsWith('BIND_UNRESOLVED'));
      // a hand-captured wire index that disagrees with the manufacturer ID would be blocked, not trusted
      for (final model in library.models) {
        for (final p in model.algorithm.parameters.where((p) => p.xmlId != null && p.blockedReason == null)) {
          expect(p.wireIndex, p.xmlId! - 1, reason: '${model.name}/${p.name}');
        }
      }
    });

    test('bind / Sync: every bound parameter and every Sync target of the manufacturer catalog is blocked', () {
      var bound = 0, targets = 0;
      for (final slot in MatriboxChainSlot.values) {
        for (final model in library.forSlot(slot)) {
          for (final p in model.algorithm.parameters) {
            if (p.bind != null) {
              bound++;
              expect(product.parameter(slot, model, p, p.kind == MatriboxParameterKind.flag ? 0 : p.minimum).level, EvidenceLevel.blocked, reason: '${model.name}/${p.name}');
            }
            if (model.algorithm.parameters.any((q) => q.bind == p.name)) {
              targets++;
              expect(product.parameter(slot, model, p, 0).level, EvidenceLevel.blocked, reason: '${model.name}/${p.name}');
            }
          }
        }
      }
      expect(bound, greaterThan(0));
      expect(targets, greaterThan(0));
    });

    test('block CC: all nine slots, both directions', () {
      for (final slot in MatriboxChainSlot.values) {
        expect(product.blockToggle(slot, true).sendable, isTrue, reason: slot.label);
        expect(product.blockToggle(slot, false).sendable, isTrue, reason: slot.label);
        expect(slot.blockToggleController, 0x2f + slot.wireSlot); // 0x30..0x38
      }
    });

    test('Store, metadata and restore stay blocked message families', () {
      for (final f in ['STORE (12 12)', 'METADATA (12 11)', 'RESTORE_RETRY', 'RAW_SYSEX']) {
        expect(MatriboxMessageFamilies.decide(f).level, EvidenceLevel.blocked, reason: f);
      }
    });
  });

  group('the productive Dart plan over the promoted families', () {
    TargetValue<T> tv<T>(T v) => TargetValue(v, ToneOrigin.songProfile, 'test');
    MatriboxToneTransferPlan plan(Map<MatriboxChainSlot, MatriboxTargetBlock> blocks) => MatriboxToneTransferPlan.build(
      current: beforeLayout(),
      target: MatriboxTargetPreset(blocks: blocks),
      ledger: MatriboxHardwareLedger.product(),
      backupSha256: 'a' * 64,
      presetNumber: 11,
      isUserBank: true,
      transportAvailable: true,
      library: library,
    );

    test('a generalized plan (FX1 select + write, EQ select + signed write, DLY block) is READY and contract-only', () {
      final p = plan({
        MatriboxChainSlot.fx1: MatriboxTargetBlock(
          slot: MatriboxChainSlot.fx1,
          enabled: tv(true),
          model: tv(m(MatriboxChainSlot.fx1, 'Skreamer')),
          parameters: {'gain': tv(30.0)},
        ),
        MatriboxChainSlot.eq: MatriboxTargetBlock(
          slot: MatriboxChainSlot.eq,
          enabled: tv(true),
          model: tv(m(MatriboxChainSlot.eq, 'Guitar EQ')),
          parameters: {'400hz': tv(-12.0)},
        ),
      });
      expect(p.summary.blocked, 0);
      expect(p.overall, ToneTransferOverall.ready);
      final request = p.toContractRequest();
      final ops = (request['operations'] as List).cast<Map<String, Object?>>();
      expect(ops.any((o) => o['type'] == 'SELECT_MODEL' && o['slot'] == 'FX1' && o['model'] == 'Skreamer'), isTrue);
      for (final o in ops) {
        expect(o.keys.toSet().difference({'type', 'slot', 'model', 'parameter', 'value'}), isEmpty, reason: '$o'); // no bytes, ids or indices
      }
    });

    test('a bound parameter (Flanger Rate) blocks the WHOLE plan: no partial transfer', () {
      final p = plan({
        MatriboxChainSlot.mod: MatriboxTargetBlock(
          slot: MatriboxChainSlot.mod,
          enabled: tv(true),
          model: tv(m(MatriboxChainSlot.mod, 'Flanger')),
          parameters: {'rate': tv(3.7)},
        ),
      });
      final rate = p.entries.firstWhere((e) => e.subject == 'rate');
      expect(rate.eligibility, ToneSendEligibility.blockedByEvidence);
      expect(rate.blockReason, contains('BIND_UNRESOLVED'));
      expect(p.overall, ToneTransferOverall.blocked);
    });

    test('User IR as the target model is refused before any send', () {
      final p = plan({
        MatriboxChainSlot.cab: MatriboxTargetBlock(
          slot: MatriboxChainSlot.cab,
          enabled: tv(true),
          model: tv(m(MatriboxChainSlot.cab, 'User IR 7')),
        ),
      });
      expect(p.overall, ToneTransferOverall.blocked);
      expect(p.entries.any((e) => e.intended == ToneOperationKind.selectModel && !e.sendable), isTrue);
    });
  });
}
