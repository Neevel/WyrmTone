import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/canonical_tone_recipe.dart';
import 'package:wyrmtone/presets/matribox_chain_catalog.dart';
import 'package:wyrmtone/presets/matribox_chain_encoder.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_evidence_v2.dart';
import 'package:wyrmtone/presets/matribox_hardware_evidence.dart';
import 'package:wyrmtone/presets/matribox_model_library.dart';
import 'package:wyrmtone/presets/matribox_target_preset.dart';
import 'package:wyrmtone/presets/matribox_tone_translator.dart';
import 'package:wyrmtone/presets/matribox_transfer_catalog.dart';
import 'package:wyrmtone/presets/tone_intent.dart';

import 'support/matribox_big_capture_groups.dart';
import 'support/matribox_certified_runs.dart';
import 'support/matribox_tone_transfer_support.dart';

String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

// Pinned after the manufacturer-ID rule and the bind/enum/User IR blocks (Angels-only state).
const nowNumbers = (63, 12, 0);

void main() {
  final library = MatriboxModelLibrary.fromVendor(toneCatalog);
  MatriboxTransferModel certifiedModel(CertifiedOperation o) => library.byName(o.slot, o.model!)!;
  SampleSource sourceOf(TransferProtocolEvidence e) =>
      e == TransferProtocolEvidence.captureConfirmed ? SampleSource.capture : SampleSource.catalogOnly;
  // The historical state BEFORE FAMILY_EXPANSION_P01_V1: only the certified Angels run (frozen evidence,
  // its Gain/Presence include the older baseline sends). The family rules are pinned at this state.
  final angels = angelsDontKillP01V1.operations;
  final angelsToggles = {for (final o in angels.where((o) => o.kind == CertifiedKind.blockToggle)) '${o.slot.name}:${o.enabled}'};
  final samples = ActiveSamples(
    selects: [
      for (final o in angels.where((o) => o.kind == CertifiedKind.modelSelect))
        SelectSample(o.slot, o.algorithmId!, sourceOf(certifiedModel(o).selectEvidence)),
    ],
    parameters: [
      for (final o in angels.where((o) => o.kind == CertifiedKind.parameter))
        ParameterSample(o.slot, o.algorithmId!, o.parameter!, certifiedModel(o).algorithm.parameter(o.parameter!).kind,
            sourceOf(certifiedModel(o).parameterEvidence)),
    ],
    toggles: [for (final o in angels.where((o) => o.kind == CertifiedKind.blockToggle)) ToggleSample(o.slot, o.enabled!)],
  );
  final v2 = MatriboxEvidenceV2(library: library, samples: samples);
  // The productive state: Angels + FAMILY_EXPANSION_P01_V1 (MatriboxHardwareLedger.product).
  final projected = MatriboxEvidenceV2(library: library, samples: ActiveSamples.fromLedger(MatriboxHardwareLedger.product(), library));
  final catalogEntries = [
    for (final a in toneCatalog.algorithms)
      (
        category: a.category!,
        code: a.code!,
        name: a.name!,
        parameterIndices: [for (final p in a.parameters) p.index!],
      ),
  ];

  MatriboxTransferModel model(MatriboxChainSlot slot, String name) => library.byName(slot, name)!;

  group('message families', () {
    test('structure is confirmed; metadata, store, factory, P02+, restore/retry and raw SysEx are BLOCKED', () {
      for (final f in MatriboxMessageFamilies.structureConfirmed) {
        expect(MatriboxMessageFamilies.decide(f).level, EvidenceLevel.structureConfirmed);
        expect(MatriboxMessageFamilies.decide(f).sendable, isFalse, reason: 'structure alone never sends');
      }
      for (final f in MatriboxMessageFamilies.blocked.keys) {
        expect(MatriboxMessageFamilies.decide(f).level, EvidenceLevel.blocked, reason: f);
      }
      expect(MatriboxMessageFamilies.decide('SOMETHING_ELSE').level, EvidenceLevel.blocked);
    });

    test('only family and exact evidence may send', () {
      expect([for (final l in EvidenceLevel.values) if (l.sendable) l.name], ['familyConfirmed', 'exactOperationConfirmed']);
    });
  });

  group('model select family', () {
    test('an arbitrary algorithm outside the vendor catalog is rejected in every slot', () {
      final fake = MatriboxTransferModel(
        algorithm: MatriboxChainAlgorithm(
          id: 'fake',
          name: 'Fake',
          code: 0x0700ffff,
          slots: {for (final s in MatriboxChainSlot.values) s},
          parameters: const [],
        ),
        selectEvidence: TransferProtocolEvidence.observed,
        parameterEvidence: TransferProtocolEvidence.observed,
      );
      for (final slot in MatriboxChainSlot.values) {
        expect(projected.modelSelect(slot, fake).level, EvidenceLevel.blocked, reason: slot.label);
      }
    });

    test('a catalog algorithm in the wrong category is rejected', () {
      expect(projected.modelSelect(MatriboxChainSlot.amp, model(MatriboxChainSlot.rvb, 'Room')).level, EvidenceLevel.blocked);
      expect(projected.modelSelect(MatriboxChainSlot.cab, model(MatriboxChainSlot.dly, 'Warm')).level, EvidenceLevel.blocked);
      expect(projected.modelSelect(MatriboxChainSlot.rvb, model(MatriboxChainSlot.cab, 'Sol 4x12')).level, EvidenceLevel.blocked);
    });

    test('User IR (documentation only) is never selectable', () {
      final ir = library.byName(MatriboxChainSlot.cab, 'User IR 7')!;
      expect(projected.modelSelect(MatriboxChainSlot.cab, ir).level, EvidenceLevel.blocked);
    });

    test('today: FX2 and CAB catalog models pass by family, everything else does not', () {
      final otherFx = library.forSlot(MatriboxChainSlot.fx2).firstWhere(
        (m) => m.selectEvidence == TransferProtocolEvidence.observed && m.name != 'Boost',
      );
      final fx = v2.modelSelect(MatriboxChainSlot.fx2, otherFx);
      expect(fx.level, EvidenceLevel.familyConfirmed);
      expect(fx.basis, contains('Katalog-Code'));
      final otherCab = library.forSlot(MatriboxChainSlot.cab).firstWhere(
        (m) => m.selectEvidence == TransferProtocolEvidence.observed && m.name != 'Sol 4x12',
      );
      expect(v2.modelSelect(MatriboxChainSlot.cab, otherCab).level, EvidenceLevel.familyConfirmed);
      // exactly certified
      expect(v2.modelSelect(MatriboxChainSlot.fx2, model(MatriboxChainSlot.fx2, 'Boost')).level, EvidenceLevel.exactOperationConfirmed);
      // no active sample in these slots
      for (final (slot, name) in [
        (MatriboxChainSlot.rvb, 'Room'),
        (MatriboxChainSlot.eq, 'Guitar EQ'),
        (MatriboxChainSlot.dly, 'Warm'),
        (MatriboxChainSlot.mod, 'Chorus A'),
        (MatriboxChainSlot.amp, 'Sol 100 LD'),
        (MatriboxChainSlot.fx1, 'Boost'),
      ]) {
        final d = v2.modelSelect(slot, model(slot, name));
        expect(d.sendable, isFalse, reason: '$name in ${slot.label}');
        expect(d.missing, isNotNull);
      }
      // capture-confirmed identities without an active sample stay CAPTURE_CONFIRMED
      expect(v2.modelSelect(MatriboxChainSlot.nr, model(MatriboxChainSlot.nr, 'Gate 2')).level, EvidenceLevel.captureConfirmed);
      expect(v2.modelSelect(MatriboxChainSlot.rvb, model(MatriboxChainSlot.rvb, 'Room')).level, EvidenceLevel.catalogConfirmed);
    });

    test('the FX2 family does not leak to FX1 (twin slot, different slot byte)', () {
      expect(v2.modelSelect(MatriboxChainSlot.fx1, model(MatriboxChainSlot.fx1, 'Boost')).sendable, isFalse);
    });
  });

  group('parameter family', () {
    test('unknown parameter and out-of-range values are rejected; range comes from the catalog', () {
      final sol = model(MatriboxChainSlot.amp, 'Sol 100 OD');
      final gain = sol.algorithm.parameter('Gain');
      expect(v2.parameter(MatriboxChainSlot.amp, sol, gain, 100).level, EvidenceLevel.blocked);
      expect(v2.parameter(MatriboxChainSlot.amp, sol, gain, -1).level, EvidenceLevel.blocked);
      expect(v2.parameter(MatriboxChainSlot.amp, sol, gain, double.nan).level, EvidenceLevel.blocked);
      final foreign = model(MatriboxChainSlot.rvb, 'Room').algorithm.parameter('Mix');
      expect(v2.parameter(MatriboxChainSlot.amp, sol, foreign, 10).level, EvidenceLevel.blocked);
      final invented = const MatriboxChainParameter(name: 'Invented', wireIndex: 9, catalogIndex: 9, kind: MatriboxParameterKind.number);
      expect(v2.parameter(MatriboxChainSlot.amp, sol, invented, 10).level, EvidenceLevel.blocked);
      final flag = model(MatriboxChainSlot.rvb, 'Room').algorithm.parameter('Trail');
      expect(projected.parameter(MatriboxChainSlot.rvb, model(MatriboxChainSlot.rvb, 'Room'), flag, 0.5).level, EvidenceLevel.blocked);
      final eq = model(MatriboxChainSlot.eq, 'Guitar EQ');
      expect(projected.parameter(MatriboxChainSlot.eq, eq, eq.algorithm.parameter('400Hz'), -51).level, EvidenceLevel.blocked);
      expect(projected.parameter(MatriboxChainSlot.eq, eq, eq.algorithm.parameter('400Hz'), -50).sendable, isTrue);
    });

    test('per value certification is not needed: a certified Gain 67 covers Gain 68 (same parameter, range checked)', () {
      final sol = model(MatriboxChainSlot.amp, 'Sol 100 OD');
      final gain = sol.algorithm.parameter('Gain');
      final a = v2.parameter(MatriboxChainSlot.amp, sol, gain, 67);
      final b = v2.parameter(MatriboxChainSlot.amp, sol, gain, 68);
      expect(a.level, EvidenceLevel.exactOperationConfirmed);
      expect(b.level, EvidenceLevel.exactOperationConfirmed);
      expect(a.basis, contains('Wert nur per Katalogbereich'));
    });

    test('today: capture-confirmed AMP numbers pass by family; catalog-only identities do not', () {
      final brit = model(MatriboxChainSlot.amp, 'Brit 800');
      expect(v2.parameter(MatriboxChainSlot.amp, brit, brit.algorithm.parameter('Master'), 30).level, EvidenceLevel.familyConfirmed);
      final ld = model(MatriboxChainSlot.amp, 'Sol 100 LD');
      final d = v2.parameter(MatriboxChainSlot.amp, ld, ld.algorithm.parameter('Gain'), 30);
      expect(d.sendable, isFalse);
      expect(d.missing, contains('nur-Katalog'));
      // other slots have no sample of their kind at all
      final gate = model(MatriboxChainSlot.nr, 'Gate 2');
      expect(v2.parameter(MatriboxChainSlot.nr, gate, gate.algorithm.parameter('THRE'), 40).level, EvidenceLevel.captureConfirmed);
      final boost = model(MatriboxChainSlot.fx2, 'Boost');
      expect(v2.parameter(MatriboxChainSlot.fx2, boost, boost.algorithm.parameter('Gain'), 23).level, EvidenceLevel.catalogConfirmed);
    });

    test('CAB is no special slot any more: wire = ID - 1 (VOL: ID 2 -> wire 1) and the cross-slot kind rule covers it', () {
      final sol = model(MatriboxChainSlot.cab, 'Sol 4x12');
      final vol = sol.algorithm.parameter('VOL');
      expect((vol.xmlId, vol.wireIndex, vol.catalogIndex), (2, 1, 0));
      final otherSlots = ActiveSamples(
        parameters: [
          for (final s in [MatriboxChainSlot.amp, MatriboxChainSlot.rvb, MatriboxChainSlot.dly, MatriboxChainSlot.fx2])
            ParameterSample(s, 'x', 'p', MatriboxParameterKind.number, SampleSource.catalogOnly),
        ],
      );
      final e = MatriboxEvidenceV2(library: library, samples: otherSlots);
      expect(e.parameter(MatriboxChainSlot.cab, sol, vol, 43).sendable, isTrue); // cross-slot (4 distinct slots)
      expect(e.parameter(MatriboxChainSlot.nr, model(MatriboxChainSlot.nr, 'Gate 2'), model(MatriboxChainSlot.nr, 'Gate 2').algorithm.parameter('THRE'), 31).level,
          EvidenceLevel.familyConfirmed);
      // fewer than three slots do not cover a further slot
      final two = MatriboxEvidenceV2(
        library: library,
        samples: ActiveSamples(parameters: [
          ParameterSample(MatriboxChainSlot.amp, 'x', 'p', MatriboxParameterKind.number, SampleSource.catalogOnly),
          ParameterSample(MatriboxChainSlot.rvb, 'x', 'p', MatriboxParameterKind.number, SampleSource.catalogOnly),
        ]),
      );
      expect(two.parameter(MatriboxChainSlot.cab, sol, vol, 43).sendable, isFalse);
    });

    test('wire index is the editor ID - 1: hand-captured algorithms and every catalog model (index rule evidence)', () {
      for (final a in matriboxCaptureConfirmedAlgorithms) {
        for (final p in a.parameters) {
          if (a.slots.contains(MatriboxChainSlot.cab)) {
            expect(p.wireIndex, p.catalogIndex + 1, reason: '${a.name}/${p.name}');
          } else {
            expect(p.wireIndex, p.catalogIndex, reason: '${a.name}/${p.name}');
          }
        }
      }
      // catalog-only models: wire = algorithm.xml ID - 1 (equals the catalog index unless the XML skips an ID)
      for (final m in library.models) {
        if (m.selectEvidence != TransferProtocolEvidence.observed) continue;
        final entry = toneCatalog.algorithms.firstWhere((a) => a.code == m.code && a.name == m.name);
        for (final p in m.algorithm.parameters) {
          if (p.blockedReason != null) {
            expect(p.wireIndex, -1, reason: '${m.name}/${p.name}'); // e.g. FX1/FX2 definition conflict: no address
            continue;
          }
          expect(p.wireIndex, entry.parameter(p.name)!.xmlId! - 1, reason: '${m.name}/${p.name}');
        }
      }
    });
  });

  group('float32 encoding: negative, decimal, boolean and positive are byte-exact against the big capture', () {
    test('the last host write of every captured group is reproduced by the encoder', () {
      var kinds = <MatriboxParameterKind>{};
      for (final g in bigCaptureGroups) {
        final slot = MatriboxChainSlot.values[g.slot - 1];
        final algorithm = matriboxCaptureConfirmedAlgorithms.where((a) => a.code == g.code && a.slots.contains(slot)).firstOrNull;
        expect(algorithm, isNotNull, reason: 'slot ${g.slot} code ${g.code}');
        final parameter = algorithm!.parameters.singleWhere((p) => p.wireIndex == g.index);
        expect(hex(MatriboxChainEncoder.parameterWrite(slot, algorithm, parameter, g.lastValue)), g.lastHex,
            reason: '${algorithm.name}/${parameter.name}');
        kinds = {...kinds, parameter.kind};
      }
      expect(kinds, MatriboxParameterKind.values.toSet());
    });

    test('named samples: negative EQ, decimal Flanger rate, boolean Sync', () {
      final bass = matriboxBassEq.parameter('120Hz');
      expect(bass.kind, MatriboxParameterKind.signedNumber);
      final rate = matriboxFlanger.parameter('Rate');
      expect(rate.kind, MatriboxParameterKind.decimal);
      final sync = matriboxFlanger.parameter('Sync');
      expect(sync.kind, MatriboxParameterKind.flag);
      final by = {for (final g in bigCaptureGroups) '${g.slot}:${g.code}:${g.index}': g};
      expect(hex(MatriboxChainEncoder.parameterWrite(MatriboxChainSlot.eq, matriboxBassEq, bass, -23)), by['6:16777274:1']!.lastHex);
      expect(hex(MatriboxChainEncoder.parameterWrite(MatriboxChainSlot.mod, matriboxFlanger, rate, 3.7)), by['7:67108881:1']!.lastHex);
      expect(hex(MatriboxChainEncoder.parameterWrite(MatriboxChainSlot.mod, matriboxFlanger, sync, 1)), by['7:67108881:4']!.lastHex);
    });
  });

  group('block CC family', () {
    test('all nine controllers, both polarities: 0x30..0x38, 0x00 = ON, 0x7F = OFF', () {
      for (final slot in MatriboxChainSlot.values) {
        expect(MatriboxChainEncoder.blockToggle(slot, enabled: true), [0xb1, 0x30 + slot.index, 0x00], reason: slot.label);
        expect(MatriboxChainEncoder.blockToggle(slot, enabled: false), [0xb1, 0x30 + slot.index, 0x7f], reason: slot.label);
      }
    });

    test('with the four certified toggles (FX1 off, FX2 on, CAB on, EQ off) the family is confirmed for all slots', () {
      for (final slot in MatriboxChainSlot.values) {
        for (final enabled in [true, false]) {
          final d = v2.blockToggle(slot, enabled);
          final exact = angelsToggles.contains('${slot.name}:$enabled');
          expect(d.level, exact ? EvidenceLevel.exactOperationConfirmed : EvidenceLevel.familyConfirmed, reason: '${slot.label} $enabled');
        }
      }
    });

    test('without enough samples the family is only CAPTURE_CONFIRMED and names the missing sample', () {
      final few = MatriboxEvidenceV2(
        library: library,
        samples: const ActiveSamples(toggles: [ToggleSample(MatriboxChainSlot.fx1, false), ToggleSample(MatriboxChainSlot.fx2, true)]),
      );
      final d = few.blockToggle(MatriboxChainSlot.rvb, true);
      expect(d.level, EvidenceLevel.captureConfirmed);
      expect(d.missing, contains('drei'));
      final baseline = MatriboxEvidenceV2(library: library, samples: ActiveSamples.fromLedger(MatriboxHardwareLedger.baseline(), library));
      expect(baseline.blockToggle(MatriboxChainSlot.amp, true).sendable, isFalse);
    });
  });

  group('Angels golden path regression', () {
    test('the 11 certified operations are all EXACT under evidence V2', () {
      expect(angels, hasLength(11));
      for (final o in angels) {
        final d = switch (o.kind) {
          CertifiedKind.modelSelect => v2.modelSelect(o.slot, certifiedModel(o)),
          CertifiedKind.parameter => v2.parameter(o.slot, certifiedModel(o), certifiedModel(o).algorithm.parameter(o.parameter!), o.value!),
          CertifiedKind.blockToggle => v2.blockToggle(o.slot, o.enabled!),
        };
        expect(d.level, EvidenceLevel.exactOperationConfirmed, reason: '${o.slot.label} ${o.kind.name} ${o.parameter ?? ''}');
      }
    });
  });

  group('sound heuristics are separate from protocol evidence', () {
    MatriboxTargetPreset translate(Map<ToneBlockRole, RecipeBlock> blocks, {required bool heuristics}) {
      final base = angelsRecommendation().recipe;
      var recipe = base;
      for (final b in blocks.values) {
        recipe = recipe.withBlock(b);
      }
      return MatriboxToneTranslator.translate(
        recipe: recipe,
        library: library,
        heuristics: heuristics,
      );
    }

    RecipeBlock gate(int strength) => RecipeBlock(
      role: ToneBlockRole.gate,
      state: RecipeBlockState.defined,
      stateOrigin: ToneOrigin.genreProfile,
      stateReason: 't',
      kind: ToneDecision(GateLevel.medium, ToneOrigin.genreProfile, 't'),
      params: {'strength': ToneDecision(strength.toDouble(), ToneOrigin.genreProfile, 't')},
      prefs: {'character': ToneDecision('natural', ToneOrigin.genreProfile, 't')},
    );

    RecipeBlock reverb(int amount) => RecipeBlock(
      role: ToneBlockRole.reverb,
      state: RecipeBlockState.defined,
      stateOrigin: ToneOrigin.genreProfile,
      stateReason: 't',
      kind: ToneDecision(ReverbKind.room, ToneOrigin.genreProfile, 't'),
      params: {'amount': ToneDecision(amount.toDouble(), ToneOrigin.genreProfile, 't')},
    );

    test('default translation is unchanged: no THRE, no Mix from the abstract values', () {
      final t = translate({ToneBlockRole.gate: gate(50), ToneBlockRole.reverb: reverb(4)}, heuristics: false);
      expect(t[MatriboxChainSlot.nr].parameters, isEmpty);
      expect(t[MatriboxChainSlot.rvb].parameters, isEmpty);
    });

    test('gate strength maps deterministically onto the safe THRE range 20..60 of Gate 2 only', () {
      double thre(int s) => translate({ToneBlockRole.gate: gate(s)}, heuristics: true)[MatriboxChainSlot.nr].parameters['threshold']!.value!;
      expect(thre(0), 20); // catalog default = LIGHT floor
      expect(thre(50), 40); // MEDIUM = centre of the safe range
      expect(thre(100), 60); // STRONG ceiling (editor reached 59)
      expect(thre(50), thre(50));
      final t = translate({ToneBlockRole.gate: gate(50)}, heuristics: true)[MatriboxChainSlot.nr];
      expect(t.model.value!.name, 'Gate 2');
      expect(t.parameters['threshold']!.reason, contains('HEURISTIC/DEVICE_APPROXIMATION'));
      expect(t.report!.mapped.join(' '), contains('[HEURISTIC]'));
      // ATK/Rel semantics stay UNKNOWN: character is still not set
      expect(t.parameters.keys, ['threshold']);
      expect(t.report!.notRepresented.join(' '), contains('ATK/Rel nicht gesetzt'));
    });

    test('reverb amount is NOT Mix: amount 4 does not become Mix 4, the range is 0..50 of Mix', () {
      double mix(int a) => translate({ToneBlockRole.reverb: reverb(a)}, heuristics: true)[MatriboxChainSlot.rvb].parameters['mix']!.value!;
      expect(mix(4), 2);
      expect(mix(4), isNot(4));
      expect(mix(26), 13);
      expect(mix(100), 50);
      expect(mix(0), 0);
      final t = translate({ToneBlockRole.reverb: reverb(40)}, heuristics: true)[MatriboxChainSlot.rvb];
      expect(t.parameters.keys, ['mix']); // Decay / Pre Delay are not derivable from the amount
      expect(t.parameters['mix']!.reason, contains('HEURISTIC'));
    });

    test('a heuristic never changes protocol evidence: the model keeps its protocol evidence', () {
      final t = translate({ToneBlockRole.reverb: reverb(40)}, heuristics: true)[MatriboxChainSlot.rvb];
      expect(t.model.value!.parameterEvidence, TransferProtocolEvidence.observed);
      expect(projected.parameter(MatriboxChainSlot.rvb, t.model.value!, t.model.value!.algorithm.parameter('Mix'), 20).sendable, isTrue);
      expect(v2.parameter(MatriboxChainSlot.rvb, t.model.value!, t.model.value!.algorithm.parameter('Mix'), 20).sendable, isFalse);
    });

    test('an explicit device mix wins over the heuristic amount', () {
      final block = RecipeBlock(
        role: ToneBlockRole.reverb,
        state: RecipeBlockState.defined,
        stateOrigin: ToneOrigin.genreProfile,
        stateReason: 't',
        kind: ToneDecision(ReverbKind.room, ToneOrigin.genreProfile, 't'),
        params: {
          'amount': ToneDecision(40, ToneOrigin.genreProfile, 't'),
          'mix': ToneDecision(25, ToneOrigin.userOverride, 't'),
        },
      );
      final t = translate({ToneBlockRole.reverb: block}, heuristics: true)[MatriboxChainSlot.rvb];
      expect(t.parameters['mix']!.value, 25);
    });
  });

  group('the productive samples (Angels + FAMILY_EXPANSION_P01_V1)', () {
    test('model select is a family in every slot; number, signed and flag families reach other models; Sync stays BLOCKED', () {
      // model select becomes a family in every slot (one sample per slot)
      for (final slot in MatriboxChainSlot.values) {
        expect(evidenceCoverage(catalogEntries, projected).perSlotSelectable[slot], isTrue, reason: slot.label);
      }
      // catalog-only drive: a different FX2 catalog model's Gain is then covered by the FX2 number family
      final ts = library.forSlot(MatriboxChainSlot.fx2).firstWhere(
        (m) => m.name != 'Boost' && m.selectEvidence == TransferProtocolEvidence.observed && m.algorithm.parameters.any((p) => p.name == 'Gain'),
      );
      expect(projected.parameter(MatriboxChainSlot.fx2, ts, ts.algorithm.parameter('Gain'), 40).sendable, isTrue);
      // negative and decimal float32 on other models of the same slots
      final bass = library.forSlot(MatriboxChainSlot.eq).firstWhere((m) => m.name == 'Bass EQ');
      expect(projected.parameter(MatriboxChainSlot.eq, bass, bass.algorithm.parameter('50Hz'), -10).sendable, isTrue);
      // decimal Rate is bound to Sync: stays BLOCKED even though the certification run wrote it
      final flanger = library.forSlot(MatriboxChainSlot.mod).firstWhere((m) => m.name == 'Flanger');
      expect(projected.parameter(MatriboxChainSlot.mod, flanger, flanger.algorithm.parameter('Rate'), 1.5).level, EvidenceLevel.blocked);
    });

    test('coverage over the 181 algorithms / 631 parameters grows and never claims musical suitability', () {
      final now = evidenceCoverage(catalogEntries, v2);
      final after = evidenceCoverage(catalogEntries, projected);
      // ignore: avoid_print
      print('COVERAGE now: ${now.algorithmsSendable}/${now.algorithms} algorithms, ${now.parametersSendable}/${now.parameters} parameters (${now.parametersEndToEnd} end-to-end)');
      // ignore: avoid_print
      print('COVERAGE after: ${after.algorithmsSendable}/${after.algorithms} algorithms, ${after.parametersSendable}/${after.parameters} parameters (${after.parametersEndToEnd} end-to-end)');
      expect(now.algorithms, 181);
      expect(now.parameters, 631);
      expect((now.algorithmsSendable, now.parametersSendable, now.parametersEndToEnd), nowNumbers);
      expect((after.algorithmsSendable, after.parametersSendable, after.parametersEndToEnd), (166, 548, 548));
      // remaining blockers: the 15 User IR entries (blank names, documentation only)
      expect(after.algorithms - after.algorithmsSendable, 15);
      expect(after.algorithmsSendable, greaterThan(now.algorithmsSendable));
      expect(after.parametersSendable, greaterThan(now.parametersSendable));
    });
  });

  group('Evidence V2 is an offline model, not a transport', () {
    test('no send, no channel, not imported by the product transport or the native table', () {
      final source = File('lib/presets/matribox_evidence_v2.dart').readAsStringSync();
      expect(source, isNot(contains('invokeMethod')));
      expect(source, isNot(contains('.send(')));
      // The productive PLAN uses it as its decision model; the transport layers never import it.
      for (final f in ['matribox_tone_transfer_session.dart', 'matribox_channel_clients.dart']) {
        final path = f.startsWith('matribox_channel') ? 'lib/screens/$f' : 'lib/presets/$f';
        expect(File(path).readAsStringSync(), isNot(contains('matribox_evidence_v2')), reason: f);
      }
      expect(File('lib/presets/matribox_tone_transfer_plan.dart').readAsStringSync(), isNot(contains('invokeMethod')));
      // The native table is generated data; the productive native files carry no certification plan.
      for (final f in [
        'MatriboxToneTransferCatalog.kt',
        'MatriboxToneTransferPlanValidator.kt',
        'MatriboxToneTransferSession.kt',
        'MatriboxToneTransferWriterPort.kt',
        'MatriboxManufacturerCatalog.kt',
      ]) {
        expect(File('android/app/src/main/kotlin/de/neevel/wyrmtone/$f').readAsStringSync(), isNot(contains('MatriboxFamilyExpansionPlan')), reason: f);
      }
    });
  });
}
