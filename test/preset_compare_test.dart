import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/canonical_preset.dart';
import 'package:wyrmtone/presets/preset_selection_codec.dart';

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

  test('missing PCAP input is reported honestly', () {
    final result = compareOffline(fixture(), ['reference.pcapng']);
    expect(result['unsupportedInputs'], isNotEmpty);
    expect(result['messages'], isEmpty);
  });

  test('real TShark field shape preserves P01 timing and empty completion', () {
    const p01 = 'f02125,7f514d,453212,000200,000000,000000,000000,f7';
    final observations = parseTsharkMidiFields(
      '4.399426\t0x03\t32\t$p01\n'
      '4.399700\t0x83\t0\t\n'
      '4.402307\t0x03\t32\t$p01\n',
    );
    final analysis = analyzePresetSelections(observations)
        .whereType<PresetSelectionAnalysis>()
        .single;
    expect(analysis.message.presetLabel, 'P01');
    expect(analysis.repeatCount, 2);
    expect(analysis.repeatIntervalsMs.single, closeTo(2.881, 0.0001));
    expect(analysis.possibleDeviceResponses, 0);
  });

  test('USB-MIDI CIN bytes and F7 padding are removed', () {
    final decoded = decodeTsharkMidiEventField(
      '04f02125,047f514d,04453212,04000200,04000000,04000000,04000000,05f70000',
    );
    expect(
      decoded,
      ConfirmedPresetSelectionCodec.encodeReference(
        KnownMatriboxPresetSelectionTarget.p01,
      ),
    );
    expect(decoded, hasLength(22));
  });

  test('fragmented and multiple SysEx are assembled and split', () {
    final observations = parseTsharkMidiFields(
      '1.000\t0x03\t4\t04f02125\n'
      '1.001\t0x03\t28\t047f514d,04453212,04000200,04000000,04000000,04000000,05f70000\n'
      '1.002\t0x03\t8\t04f07e00,05f70000,04f07d00,05f70000\n',
    );
    expect(
      observations.where(
        (item) => item.state == MidiObservationState.completeSysEx,
      ),
      hasLength(3),
    );
    expect(observations.first.bytes, hasLength(22));
  });

  test('unfinished SysEx is reported without repair', () {
    final observations = parseTsharkMidiFields(
      '1.000\t0x03\t8\t04f02125,047f514d\n',
    );
    expect(observations.single.state, MidiObservationState.incompleteSysEx);
    expect(
      analyzePresetSelections(observations).single,
      isA<IncompleteSysExFinding>(),
    );
  });
}
