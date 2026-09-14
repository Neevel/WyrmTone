import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/canonical_preset.dart';

import '../tool/preset_compare.dart';
import 'preset_domain_test.dart' show fixture;

void main() {
  test(
    'Offline capture comparison recognizes confirmed Gain reference',
    () async {
      final dir = await Directory.systemTemp.createTemp('wyrmtone-compare-');
      addTearDown(() => dir.delete(recursive: true));
      final capture = File('${dir.path}/capture.json');
      await capture.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'session': {
            'startedAt': DateTime.utc(2026).toIso8601String(),
            'receiveOnly': true,
            'droppedEntries': 0,
            'droppedChunks': 0,
            'incompleteCount': 0,
            'messages': [
              {
                'sequence': 1,
                'localTimestamp': DateTime.utc(2026).toIso8601String(),
                'kind': 'message',
                'type': 'SysEx',
                'status': 'vollständig',
                'length': 34,
                'hex': 'F0 21 25 7F 51 4D 45 32 12 10 03 00 02 04 07 00 00 00 00 00 07 00 00 00 00 00 00 00 00 02 00 04 02 F7',
              },
            ],
          },
        }),
      );
      final result = compareOffline(fixture(), [capture.path]);
      final message = objectMap((result['messages'] as List).single);
      expect(message['direction'], 'deviceToApp');
      expect(message['catalogMatch'], 'Sol 100 OD / Gain');
      expect(message['parameterIndex'], 0);
      expect(message['value'], 40.0);
      expect(message['matchesPreset'], isTrue);
      expect(result['missingExpected'], isEmpty);
    },
  );
  test('PCAP support is reported honestly when unavailable', () {
    final result = compareOffline(fixture(), ['reference.pcapng']);
    expect(result['unsupportedInputs'], isNotEmpty);
    expect(result['messages'], isEmpty);
  });
}
