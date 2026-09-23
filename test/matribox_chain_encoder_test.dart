import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/matribox_chain_catalog.dart';
import 'package:wyrmtone/presets/matribox_chain_encoder.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';

import 'support/matribox_big_capture_fixtures.dart';
import 'support/matribox_big_capture_groups.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

MatriboxChainAlgorithm _algorithmFor(int code) =>
    matriboxCaptureConfirmedAlgorithms.singleWhere((a) => a.code == code);

MatriboxChainParameter _parameterFor(MatriboxChainAlgorithm a, int wireIndex) =>
    a.parameters.singleWhere((p) => p.wireIndex == wireIndex);

MatriboxChainSlot _slot(int wire) =>
    MatriboxChainSlot.values.singleWhere((s) => s.wireSlot == wire);

void main() {
  test('slot enum is closed: wire slots 1..9 and block controllers 0x30..0x38', () {
    expect(MatriboxChainSlot.values.map((s) => s.wireSlot), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(MatriboxChainSlot.values.map((s) => s.blockToggleController),
        [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38]);
    expect(MatriboxChainSlot.values.map((s) => s.label),
        ['FX1', 'FX2', 'AMP', 'NR', 'CAB', 'EQ', 'MOD', 'DLY', 'RVB']);
  });

  test('MODEL SELECT reproduces every captured message byte-for-byte (all slots)', () {
    expect(bigCaptureSelects.map((s) => s.slot).toSet(), {1, 2, 3, 4, 5, 6, 7, 8, 9});
    for (final s in bigCaptureSelects) {
      final algorithm = _algorithmFor(s.code);
      expect(
        _hex(MatriboxChainEncoder.modelSelect(_slot(s.slot), algorithm)),
        s.hex,
        reason: 'slot ${s.slot} ${algorithm.name}',
      );
    }
  });

  test('PARAMETER write reproduces first and last captured message of all 46 groups', () {
    expect(bigCaptureGroups, hasLength(46));
    for (final g in bigCaptureGroups) {
      final algorithm = _algorithmFor(g.code);
      final parameter = _parameterFor(algorithm, g.index);
      final slot = _slot(g.slot);
      expect(_hex(MatriboxChainEncoder.parameterWrite(slot, algorithm, parameter, g.firstValue)), g.firstHex,
          reason: '${slot.label} ${algorithm.name}/${parameter.name} first ${g.firstValue}');
      expect(_hex(MatriboxChainEncoder.parameterWrite(slot, algorithm, parameter, g.lastValue)), g.lastHex,
          reason: '${slot.label} ${algorithm.name}/${parameter.name} last ${g.lastValue}');
    }
  });

  test('every slot has parameter goldens, and all four value types are covered', () {
    expect({for (final g in bigCaptureGroups) g.slot}, {1, 2, 3, 4, 5, 6, 7, 8, 9});
    final kinds = <MatriboxParameterKind>{
      for (final g in bigCaptureGroups)
        _parameterFor(_algorithmFor(g.code), g.index).kind,
    };
    expect(kinds, MatriboxParameterKind.values.toSet());
    expect(bigCaptureGroups.any((g) => g.lastValue < 0), isTrue); // negative
    expect(bigCaptureGroups.any((g) => g.lastValue != g.lastValue.roundToDouble()), isTrue); // decimal
  });

  test('BLOCK TOGGLE: all nine slots, both directions, equal captured control changes', () {
    for (final slot in MatriboxChainSlot.values) {
      for (final enabled in [true, false]) {
        expect(bigCaptureControlChanges, contains(_hex(MatriboxChainEncoder.blockToggle(slot, enabled: enabled))),
            reason: '${slot.label} enabled=$enabled');
      }
    }
    // 0x00 = ON, 0x7F = OFF
    expect(MatriboxChainEncoder.blockToggle(MatriboxChainSlot.cab, enabled: true), [0xb1, 0x34, 0x00]);
    expect(MatriboxChainEncoder.blockToggle(MatriboxChainSlot.fx1, enabled: false), [0xb1, 0x30, 0x7f]);
  });

  test('FX1 and FX2 Skreamer differ only by the slot byte', () {
    final a = MatriboxChainEncoder.parameterWrite(MatriboxChainSlot.fx1, matriboxSkreamer, matriboxSkreamer.parameter('Gain'), 23);
    final b = MatriboxChainEncoder.parameterWrite(MatriboxChainSlot.fx2, matriboxSkreamer, matriboxSkreamer.parameter('Gain'), 23);
    expect([for (var i = 0; i < a.length; i++) if (a[i] != b[i]) i], [10]);
  });

  test('catalog entries match the local XML-derived catalog (code, names, ranges)', () {
    final catalog = (jsonDecode(File('assets/catalog/matribox_preset_catalog.json').readAsStringSync())
        as Map)['algorithms'] as List;
    for (final a in matriboxCaptureConfirmedAlgorithms.where((a) => a.id != 'userIr7')) {
      final entries = catalog.cast<Map>().where((c) => c['code'] == a.code && c['name'] == a.name).toList();
      expect(entries, isNotEmpty, reason: a.name);
      final params = (entries.first['parameters'] as List).cast<Map>();
      for (final p in a.parameters) {
        final match = params.singleWhere((c) => c['name'] == p.name, orElse: () => {});
        expect(match, isNotEmpty, reason: '${a.name}/${p.name}');
        expect(match['index'], p.catalogIndex, reason: '${a.name}/${p.name}');
        if (p.kind != MatriboxParameterKind.flag) {
          expect(match['minimum'], p.minimum, reason: '${a.name}/${p.name}');
          expect(match['maximum'], p.maximum, reason: '${a.name}/${p.name}');
        }
      }
    }
  });

  test('User IR: only User IR 7 is documented, encodes offline, and is not sendable', () {
    expect(matriboxUserIr7.code, 0x0a100006);
    expect(matriboxUserIr7.sendableInFullLive, isFalse);
    final captured = bigCaptureSelects.singleWhere((s) => s.code == 0x0a100006);
    expect(_hex(MatriboxChainEncoder.modelSelect(MatriboxChainSlot.cab, matriboxUserIr7)), captured.hex);
    expect(matriboxCaptureConfirmedAlgorithms.where((a) => a.code >> 20 == 0x0a1).length, 1);
  });

  test('encoder refuses unconfirmed combinations and out-of-range values', () {
    expect(() => MatriboxChainEncoder.modelSelect(MatriboxChainSlot.amp, matriboxBluesOd),
        throwsA(isA<MatriboxChainEncodingError>()));
    expect(() => MatriboxChainEncoder.parameterWrite(MatriboxChainSlot.mod, matriboxSweep, matriboxSweep.parameter('Mix'), 1),
        throwsA(isA<MatriboxChainEncodingError>()));
    // a parameter object from another algorithm is refused
    expect(() => MatriboxChainEncoder.parameterWrite(MatriboxChainSlot.fx1, matriboxSkreamer, matriboxBrit800.parameter('Bass'), 1),
        throwsA(isA<MatriboxChainEncodingError>()));
    final rate = matriboxFlanger.parameter('Rate');
    for (final bad in [0.0, 10.5, double.nan]) {
      expect(() => MatriboxChainEncoder.parameterWrite(MatriboxChainSlot.mod, matriboxFlanger, rate, bad),
          throwsA(isA<MatriboxChainEncodingError>()), reason: '$bad');
    }
    final sync = matriboxFlanger.parameter('Sync');
    expect(() => MatriboxChainEncoder.parameterWrite(MatriboxChainSlot.mod, matriboxFlanger, sync, 0.5),
        throwsA(isA<MatriboxChainEncodingError>()));
    final eq = matriboxBassEq.parameter('50Hz');
    expect(() => MatriboxChainEncoder.parameterWrite(MatriboxChainSlot.eq, matriboxBassEq, eq, -51),
        throwsA(isA<MatriboxChainEncodingError>()));
  });

  test('preset metadata encoders (offline) reproduce the captured messages', () {
    final captured = {for (final f in bigCaptureFixtures) f.hex};
    expect(captured, contains(_hex(MatriboxChainEncoder.presetVolume(37))));
    expect(captured, contains(_hex(MatriboxChainEncoder.presetBpm(137))));
    expect(captured, contains(_hex(MatriboxChainEncoder.presetName('CAP TEST 01'))));
    expect(() => MatriboxChainEncoder.presetName('THIS NAME IS TOO LONG'), throwsA(isA<MatriboxChainEncodingError>()));
  });
}
