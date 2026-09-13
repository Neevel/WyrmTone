import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/matribox_analyzer.dart';

String capture({
  bool receiveOnly = true,
  String hex = 'F0 01 F7',
  int length = 3,
}) => jsonEncode({
  'schemaVersion': 1,
  'session': {
    'receiveOnly': receiveOnly,
    'startedAt': '2026-09-12T10:00:00',
    'droppedEntries': 0,
    'droppedChunks': 0,
    'incompleteCount': 0,
    'messages': [
      {
        'sequence': 1,
        'localTimestamp': '2026-09-12T10:00:01',
        'kind': 'chunk',
        'hex': hex,
        'length': length,
      },
      {
        'sequence': 2,
        'localTimestamp': '2026-09-12T10:00:01',
        'kind': 'message',
        'type': 'SysEx',
        'status': 'vollständig',
        'hex': hex,
        'length': length,
      },
    ],
  },
});

void main() {
  test('offline tool has no device, network or process dependencies', () {
    final source = File('tool/matribox_analyzer.dart').readAsStringSync();
    expect(
      RegExp(
        r'\b(HttpClient|Socket|Process|MethodChannel|MidiManager|openInputPort|bulkTransfer|controlTransfer)\b',
      ).hasMatch(source),
      false,
    );
    expect(source, isNot(contains('package:flutter/')));
  });
  test('fragmented chunks and multiple SysEx stay distinct from markers', () {
    final doc = jsonDecode(capture()) as Map<String, dynamic>;
    final session = doc['session'] as Map<String, dynamic>;
    final base = {'localTimestamp': '2026-09-12T10:00:01'};
    session['messages'] = [
      {
        ...base,
        'sequence': 1,
        'kind': 'marker',
        'marker': 'action',
        'hex': '',
        'length': 0,
      },
      {...base, 'sequence': 2, 'kind': 'chunk', 'hex': 'F0 01', 'length': 2},
      {
        ...base,
        'sequence': 3,
        'kind': 'chunk',
        'hex': 'F7 F0 02 F7',
        'length': 4,
      },
      {
        ...base,
        'sequence': 4,
        'kind': 'message',
        'type': 'SysEx',
        'status': 'vollständig',
        'hex': 'F0 01 F7',
        'length': 3,
      },
      {
        ...base,
        'sequence': 5,
        'kind': 'message',
        'type': 'SysEx',
        'status': 'vollständig',
        'hex': 'F0 02 F7',
        'length': 3,
      },
    ];
    final result = readCapture(jsonEncode(doc), 'synthetic');
    expect(result.messages, hasLength(2));
    expect(result.markers, hasLength(1));
    expect(result.warnings, isEmpty);
  });
  test('duplicates retain positions and values, unknown fields survive', () {
    final import = readResource(
      '<R>\n<P ID="1" ID="2" mystery="abc"/></R>',
      'synthetic.xml',
    );
    final p = import.root.all('P').single;
    expect(p.attributes['ID']!.map((v) => v.raw), ['1', '2']);
    expect(p.value('ID'), isNull);
    expect(p.value('mystery'), 'abc');
    expect(import.warnings.single, contains('synthetic.xml:2:'));
    expect(
      p.attributes['ID']!.first.position,
      lessThan(p.attributes['ID']!.last.position),
    );
    expect(p.attributes['ID']!.first.confidence, 'observed');
  });
  test('raw numbers and bases stay separate, missing stays unknown', () {
    expect(Evidence('0x2A', 'x', 0).normalized, 42);
    expect(Evidence('42', 'x', 0).representation, 'decimal');
    expect(Evidence('0x2A', 'x', 0).representation, 'hex');
    expect(Evidence('-0.5', 'x', 0).normalized, -0.5);
    expect(Evidence('abc', 'x', 0).normalized, isNull);
  });
  test('rejects unsafe captures and invalid complete SysEx or length', () {
    expect(
      () => readCapture(capture(receiveOnly: false), 'x'),
      throwsFormatException,
    );
    expect(
      () => readCapture(capture(hex: '01 02 F7'), 'x'),
      throwsFormatException,
    );
    expect(
      () => readCapture(capture(hex: 'F0 01 02'), 'x'),
      throwsFormatException,
    );
    expect(() => readCapture(capture(length: 4), 'x'), throwsFormatException);
    expect(readCapture(capture(), 'x').warnings, isEmpty);
  });
  test('positions compare exactly and preserve ASCII observations', () {
    final diff = differences([
      [0xF0, 0x51, 1, 0xF7],
      [0xF0, 0x51, 2, 0xF7],
    ]);
    expect(diff[1]['ascii'], 'Q');
    expect(diff[2]['constant'], false);
    expect(diff[2]['decimal'], [1, 2]);
    expect(diff[2]['meaning'], 'unknown');
  });
  test(
    'nibble float hypothesis reconstructs endpoints without semantic claim',
    () {
      expect(nibbleFloat([0, 0, 0, 0, 12, 6, 4, 2], 0), 99);
      expect(nibbleFloat(List.filled(8, 0), 0), 0);
      expect(nibbleFloat([16, 0, 0, 0, 0, 0, 0, 0], 0), isNull);
    },
  );
  test('file reading preserves originals and report is deterministic', () async {
    final dir = await Directory.systemTemp.createTemp('wyrmtone_offline_test_');
    try {
      final file = File('${dir.path}/synthetic.xml');
      const original =
          '<R><Catalog Name="FX"><Alg Name="Test" Code="0"><Knob ID="1" ID="1"/></Alg></Catalog></R>';
      await file.writeAsString(original);
      final imported = readResource(await file.readAsString(), 'synthetic.xml');
      final captures = [readCapture(capture(), 'synthetic.json')];
      final a = report(
        imported,
        readResource('<R/>', 'preset.xml'),
        captures,
        [],
      );
      expect(
        a,
        report(imported, readResource('<R/>', 'preset.xml'), captures, []),
      );
      expect(a, contains('Hypothesis:'));
      expect(await file.readAsString(), original);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
