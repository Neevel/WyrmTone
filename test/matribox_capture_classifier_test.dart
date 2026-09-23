import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/confirmed_parameter_codec.dart';
import 'package:wyrmtone/presets/matribox_capture_classifier.dart';

import 'support/matribox_big_capture_fixtures.dart';
import 'support/matribox_sol100od_write_fixtures.dart';

List<int> _bytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

CaptureMessage _msg(double t, List<int> bytes) =>
    CaptureMessage(direction: 'hostToDevice', timestampMs: t, bytes: bytes);

const _catalog = [
  CatalogModel(category: 'AMP', name: 'Sol 100 OD', code: 0x07000047),
  CatalogModel(category: 'AMP', name: 'Brit 800', code: 0x07000035),
];

// Synthetic, clearly non-capture messages: only to test classification logic.
List<int> _qme2(List<int> tail) => [
  0xf0, 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32, ...tail, 0xf7,
];

void main() {
  final real = [
    for (final f in sol100OdCaptureFixtures) _msg(f.timestampMs, _bytes(f.hex)),
  ];

  test('real captured parameter writes: one cluster, runs decoded and mapped to the catalog', () {
    final report = classifyCapture(real, catalog: _catalog);
    final param = report.clusters
        .where((c) => c.family == CaptureFamily.parameterWrite)
        .toList();
    expect(param, hasLength(1));
    expect(param.single.key, 'param slot=3 class=07');
    expect(param.single.messages, hasLength(real.length));
    // Only the index nibble (22) and the value nibbles vary in the real capture.
    expect(
      param.single.variablePositions.every((p) => p == 22 || (p >= 25 && p <= 32)),
      isTrue,
    );
    expect(report.runs.map((r) => r.parameterIndex).toSet(), {0, 1, 2, 3, 4, 5});
    expect(report.runs.every((r) => r.models.single.name == 'Sol 100 OD'), isTrue);
    expect(report.codeChanges, isEmpty);
  });

  test('decodeParameterWrite matches the confirmed codec and rejects other families', () {
    for (final f in sol100OdCaptureFixtures) {
      final decoded = decodeParameterWrite(_bytes(f.hex))!;
      final codec = ConfirmedParameterCodec.decode(_bytes(f.hex));
      expect(
        (decoded.code, decoded.index, decoded.value),
        (codec.algorithmCode, codec.parameterIndex, codec.value),
      );
    }
    expect(decodeParameterWrite(_qme2([0x12, 0x11, 0, 0, 0])), isNull);
  });

  test('an algorithm-code change is reported with the messages between (model-selection candidate)', () {
    final other = encodeMessageBytes(0x07000035, 1, 50);
    final selectorGuess = _qme2([0x12, 0x10, 0x03, 0x00, 0x01, 0x05, 0x07, 0x00]);
    final report = classifyCapture([
      _msg(1, _bytes(sol100OdCaptureFixtures.first.hex)),
      _msg(2, selectorGuess),
      _msg(3, other),
    ], catalog: _catalog);
    expect(report.codeChanges, hasLength(1));
    expect(report.codeChanges.single.fromCode, 0x07000047);
    expect(report.codeChanges.single.toCode, 0x07000035);
    expect(report.codeChanges.single.betweenClusters.single, startsWith('qme2 len='));
    expect(report.runs.last.models.single.name, 'Brit 800');
  });

  test('names, store-burst headers and non-QME2 data land in their own clusters', () {
    final name = _qme2([0x12, 0x11, 0, 0, 0, 0, 0, 0, 0, 0, 0, ...'CKY TEST'.codeUnits, 0]);
    final report = classifyCapture([
      _msg(1, name),
      _msg(2, _qme2([0x12, 0x12, 0x00, 0x00, 0x02, 0, 0, 0, 0])),
      _msg(3, [0xf0, 0x7e, 0x7f, 0x06, 0x01, 0xf7]),
      CaptureMessage(direction: 'deviceToHost', timestampMs: 4, bytes: name),
    ]);
    expect(report.messageCount, 3); // device->host is ignored
    expect(
      report.clusters.map((c) => c.family),
      containsAll([
        CaptureFamily.presetMetadata,
        CaptureFamily.commitCandidate,
        CaptureFamily.nonQme2,
      ]),
    );
    expect(report.nameCandidates.single.text, 'CKY TEST');
  });

  test('II-Pro cross-correlation is a hint only: exact / structural / no match', () {
    final cluster = classifyCapture(real).clusters.single;
    const exact = ReferenceFamily(
      id: 'x',
      source: 'test',
      length: 34,
      headerHex: 'f0 21 25 7f 51 4d 45 32 12 10 03 00 02',
    );
    const lengthOnly = ReferenceFamily(id: 'y', source: 'test', length: 34, headerHex: 'aa bb');
    const different = ReferenceFamily(id: 'z', source: 'test', length: 20, headerHex: 'aa bb');
    expect(crossCorrelate(cluster, [different, exact]).match, ReferenceMatch.exactMatch);
    expect(crossCorrelate(cluster, [lengthOnly]).match, ReferenceMatch.structuralMatch);
    expect(crossCorrelate(cluster, [different]).match, ReferenceMatch.noMatch);
    expect(ReferenceMatch.values.map((m) => m.name), isNot(contains('confirmed')));
  });

  test('raw BEFORE/AFTER change ranges are contiguous and per part', () {
    final before = [List.filled(20, 0), List.filled(10, 0)];
    final after = [List<int>.from(before[0]), List<int>.from(before[1])];
    after[0][3] = 1;
    after[0][4] = 1;
    after[0][9] = 2;
    after[1][0] = 5;
    expect(
      rawChangeRanges(before, after).map((r) => r.toString()),
      ['part 0 [3, 5)', 'part 0 [9, 10)', 'part 1 [0, 1)'],
    );
    expect(rawChangeRanges(before, before), isEmpty);
  });

  group('big capture (2026-09-19), CORRELATED families from real editor traffic', () {
    final catalog = [
      for (final a in ((jsonDecode(File('assets/catalog/matribox_preset_catalog.json').readAsStringSync())
              as Map)['algorithms'] as List).cast<Map>())
        CatalogModel(category: a['category'] as String, name: a['name'] as String, code: a['code'] as int),
    ];
    final fixtures = [
      for (final f in bigCaptureFixtures) (f, _bytes(f.hex)),
    ];

    test('every fixture is classified; nothing is left as an unknown QME2 family', () {
      final report = classifyCapture([for (final f in fixtures) _msg(f.$1.timestampMs, f.$2)], catalog: catalog);
      expect(report.clusters.where((c) => c.family == CaptureFamily.unknownQme2), isEmpty);
      expect(
        report.clusters.map((c) => c.family).toSet(),
        containsAll([
          CaptureFamily.parameterWrite,
          CaptureFamily.modelSelection,
          CaptureFamily.presetMetadata,
          CaptureFamily.commitCandidate,
          CaptureFamily.midiControlChange,
        ]),
      );
    });

    test('model selection = slot + algorithm code, matching the AFTER editor export', () {
      final selections = [
        for (final f in fixtures)
          ?decodeModelSelection(f.$2),
      ];
      expect(selections, hasLength(11));
      // slot -> code as also stored in the AFTER preset export.
      expect({for (final s in selections) s.slot: s.code}, {
        1: 0x03000000, // FX1 Skreamer
        2: 0x03000009, // FX2 Blues OD
        3: 0x07000035, // AMP Brit 800
        4: 0x0000001d, // NR Gate 2 (last selection)
        5: 0x0a100006, // CAB User IR 7 (last selection)
        6: 0x0100003a, // EQ Bass EQ
        7: 0x04000011, // MOD Flanger
        8: 0x0b000006, // DLY Sweep
        9: 0x0c000008, // RVB Mod RVB
      });
    });

    test('FX1 and FX2 write the same algorithm code; only the slot header byte tells them apart', () {
      final fx1 = fixtures.map((f) => decodeParameterWrite(f.$2)).whereType<({int slot, int code, int index, double value})>()
          .where((d) => d.slot == 1 && d.code == 0x03000000).toList();
      final fx2 = fixtures.map((f) => decodeParameterWrite(f.$2)).whereType<({int slot, int code, int index, double value})>()
          .where((d) => d.slot == 2 && d.code == 0x03000000).toList();
      expect(fx1, isNotEmpty);
      expect(fx2, isNotEmpty);
      // Header byte 10 is the only structural difference between the two slots.
      final a = fixtures.firstWhere((f) => f.$1.label == 'param-first slot:code 1:50331648').$2;
      final b = fixtures.firstWhere((f) => f.$1.label == 'param-first slot:code 2:50331648').$2;
      expect([a[10], b[10]], [1, 2]);
      expect(a.sublist(13, 25), b.sublist(13, 25)); // same code + index nibbles
    });

    test('preset metadata scalars: 12 11 00 00 03 = Preset VOL 37, ...02 = BPM 137, ...05 = type 4', () {
      final scalars = {
        for (final f in fixtures)
          if (decodePresetMetadataScalar(f.$2) case final m?) m.selector: m.value,
      };
      expect(scalars, {3: 37, 2: 137, 5: 4});
    });

    test('block ON/OFF are MIDI CCs b1 30..38 with 0x7f = block OFF, 0x00 = block ON', () {
      final ccs = [for (final f in fixtures) if (f.$2.length == 3) f.$2];
      expect(ccs, isNotEmpty);
      expect(ccs.every((b) => b[0] == 0xb1 && b[1] >= 0x30 && b[1] <= 0x38 && (b[2] == 0 || b[2] == 0x7f)), isTrue);
    });

    test('bursts split at idle gaps', () {
      final bursts = groupBursts([_msg(0, [0xb1, 0x30, 0]), _msg(500, [0xb1, 0x30, 0x7f]), _msg(9000, [0xb1, 0x31, 0])]);
      expect(bursts.map((b) => b.count), [2, 1]);
    });
  });
}
