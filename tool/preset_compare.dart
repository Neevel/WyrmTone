import 'dart:convert';
import 'dart:io';

import 'package:wyrmtone/presets/canonical_preset.dart';
import 'package:wyrmtone/presets/confirmed_parameter_codec.dart';
import 'package:wyrmtone/presets/preset_selection_codec.dart';

import 'matribox_analyzer.dart' show readCapture, readResource;

Map<String, Object?> compareOffline(
  CanonicalPreset preset,
  List<String> capturePaths, {
  String? presetXmlPath,
}) {
  final expected = <String, num>{};
  for (final block in preset.blocks) {
    if (block.algorithmCode != null) {
      for (final parameter in block.parameters) {
        if (parameter.deviceIndex != null) {
          expected['${block.algorithmCode}:${parameter.deviceIndex}'] =
              parameter.value;
        }
      }
    }
  }
  final messages = <Map<String, Object?>>[], unsupported = <String>[];
  for (final path in capturePaths) {
    if (path.toLowerCase().endsWith('.pcap') ||
        path.toLowerCase().endsWith('.pcapng')) {
      try {
        final observations = readPcapMidiObservations(path);
        messages.addAll(
          analyzePresetSelections(observations).map(
            (analysis) => <String, Object?>{
              'source': File(path).uri.pathSegments.last,
              ...analysis.toJson(),
            },
          ),
        );
      } on Object catch (error) {
        unsupported.add('${File(path).uri.pathSegments.last}: $error');
      }
      continue;
    }
    final capture = readCapture(
      File(path).readAsStringSync(),
      File(path).uri.pathSegments.last,
    );
    for (final raw in capture.messages) {
      final bytes = (raw['bytes'] as List<int>);
      if (bytes.length != 34) {
        messages.add({
          'source': capture.source,
          'direction': 'deviceToApp',
          'length': bytes.length,
          'family': 'unknown',
          'evidenceLevel': 'observed',
          'unknownBytes': 'all; unsupported message length',
        });
        continue;
      }
      try {
        final decoded = ConfirmedParameterCodec.decode(bytes);
        final key = '${decoded.algorithmCode}:${decoded.parameterIndex}';
        messages.add({
          'source': capture.source,
          'direction': 'deviceToApp',
          'length': 34,
          'family': 'QME2 parameter',
          'algorithmCode': decoded.algorithmCode,
          'parameterIndex': decoded.parameterIndex,
          'value': decoded.value,
          'catalogMatch': key == '117440583:0'
              ? 'Sol 100 OD / Gain'
              : 'unknown',
          'expectedValue': expected[key],
          'matchesPreset': expected[key] == decoded.value,
          'evidenceLevel': key == '117440583:0'
              ? 'confirmedLimitedReference'
              : 'observedStructure',
          'unknownBytes': 'offsets 8-12 remain observed constants',
        });
      } on FormatException {
        messages.add({
          'source': capture.source,
          'direction': 'deviceToApp',
          'length': 34,
          'family': 'unknown34',
          'evidenceLevel': 'unknown',
          'unknownBytes': 'message does not match confirmed header',
        });
      }
    }
  }
  Map<String, Object?>? xml;
  if (presetXmlPath != null) {
    final resource = readResource(
      File(presetXmlPath).readAsStringSync(),
      File(presetXmlPath).uri.pathSegments.last,
    );
    xml = {
      'recognizedPresetElements': resource.root.all('Preset').length,
      'scannerWarnings': resource.warnings,
      'interpretation':
          'local reference only; no device state or known export-format claim',
    };
  }
  final observedKeys = {
    for (final message in messages)
      if (message['algorithmCode'] != null && message['parameterIndex'] != null)
        '${message['algorithmCode']}:${message['parameterIndex']}',
  };
  return {
    'schemaVersion': 1,
    'offlineOnly': true,
    'presetId': preset.id,
    'messages': messages,
    'missingExpected':
        expected.keys.where((k) => !observedKeys.contains(k)).toList()..sort(),
    'additionalObserved':
        observedKeys.where((k) => !expected.containsKey(k)).toList()..sort(),
    'unsupportedInputs': unsupported,
    'presetXml': ?xml,
  };
}

/// Uses TShark only as a file decoder. No capture adapter or device is opened.
List<TimedMidiObservation> readPcapMidiObservations(String path) {
  final bundled = File(r'C:\Program Files\Wireshark\tshark.exe');
  final executable = bundled.existsSync() ? bundled.path : 'tshark';
  final result = Process.runSync(executable, [
    '-r',
    path,
    '-Y',
    'usb.endpoint_address == 0x03 || usb.endpoint_address == 0x83',
    '-T',
    'fields',
    '-E',
    'occurrence=a',
    '-E',
    'aggregator=,',
    '-e',
    'frame.time_relative',
    '-e',
    'usb.endpoint_address',
    '-e',
    'usb.data_len',
    '-e',
    'usbaudio.midi.event',
    '-e',
    'usb.capdata',
  ]);
  if (result.exitCode != 0) {
    throw FormatException('TShark failed: ${result.stderr}'.trim());
  }
  return parseTsharkMidiFields(result.stdout as String);
}

List<TimedMidiObservation> parseTsharkMidiFields(String output) {
  final observations = <TimedMidiObservation>[];
  final partial = <PresetSelectionDirection, List<int>>{};
  final partialStartedAt = <PresetSelectionDirection, double?>{};

  void consume(
    List<int> payload,
    PresetSelectionDirection direction,
    double? timestampMs,
  ) {
    var other = <int>[];
    void flushOther() {
      if (other.isEmpty) return;
      observations.add(
        TimedMidiObservation(
          bytes: List.unmodifiable(other),
          direction: direction,
          timestampMs: timestampMs,
          state: MidiObservationState.otherMidi,
        ),
      );
      other = <int>[];
    }

    for (final byte in payload) {
      final active = partial[direction];
      if (byte == 0xf0) {
        flushOther();
        if (active != null && active.isNotEmpty) {
          observations.add(
            TimedMidiObservation(
              bytes: List.unmodifiable(active),
              direction: direction,
              timestampMs: partialStartedAt[direction],
              state: MidiObservationState.incompleteSysEx,
            ),
          );
        }
        partial[direction] = <int>[0xf0];
        partialStartedAt[direction] = timestampMs;
      } else if (active != null) {
        active.add(byte);
        if (byte == 0xf7) {
          observations.add(
            TimedMidiObservation(
              bytes: List.unmodifiable(active),
              direction: direction,
              timestampMs: partialStartedAt[direction],
            ),
          );
          partial.remove(direction);
          partialStartedAt.remove(direction);
        }
      } else {
        other.add(byte);
      }
    }
    flushOther();
  }

  for (final line in const LineSplitter().convert(output)) {
    final fields = line.split('\t');
    if (fields.length < 4) continue;
    final timestampSeconds = double.tryParse(fields[0]);
    final endpoint = fields[1].toLowerCase();
    final dataLength = int.tryParse(fields[2]);
    final dissectedEvent = fields[3].trim();
    final rawCapture = fields.length >= 5
        ? fields.sublist(4).join(',').trim()
        : '';
    final eventField = dissectedEvent.isNotEmpty ? dissectedEvent : rawCapture;
    // Empty completion URBs carry no MIDI bytes and are not device responses.
    if (dataLength == 0 || eventField.isEmpty) continue;
    final direction = endpoint == '0x03'
        ? PresetSelectionDirection.hostToDevice
        : PresetSelectionDirection.deviceToHost;
    consume(
      decodeTsharkMidiEventField(eventField),
      direction,
      timestampSeconds == null ? null : timestampSeconds * 1000,
    );
  }
  for (final entry in partial.entries) {
    observations.add(
      TimedMidiObservation(
        bytes: List.unmodifiable(entry.value),
        direction: entry.key,
        timestampMs: partialStartedAt[entry.key],
        state: MidiObservationState.incompleteSysEx,
      ),
    );
  }
  return List.unmodifiable(observations);
}

List<int> decodeTsharkMidiEventField(String field) {
  final tokens = field
      .split(',')
      .map((token) => token.replaceAll(':', '').trim())
      .where((token) => token.isNotEmpty)
      .toList();
  if (tokens.isEmpty || tokens.any((token) => token.length.isOdd)) {
    throw const FormatException('Invalid TShark MIDI event field.');
  }
  final hex = RegExp(r'^[0-9a-f]+$', caseSensitive: false);
  if (tokens.any((token) => !hex.hasMatch(token))) {
    throw const FormatException('Invalid TShark MIDI event field.');
  }

  final rawPackets = tokens.every((token) => token.length == 8)
      ? tokens
      : tokens.length == 1 &&
            tokens.single.length > 6 &&
            tokens.single.length % 8 == 0
      ? <String>[
          for (var i = 0; i < tokens.single.length; i += 8)
            tokens.single.substring(i, i + 8),
        ]
      : null;
  if (rawPackets == null) {
    if (tokens.any((token) => token.length > 6)) {
      throw const FormatException('Ambiguous TShark MIDI event grouping.');
    }
    return List.unmodifiable(_hexBytes(tokens.join()));
  }

  final midi = <int>[];
  for (final packetHex in rawPackets) {
    final packet = _hexBytes(packetHex);
    final cin = packet[0] & 0x0f;
    final validBytes = switch (cin) {
      0x2 || 0x6 || 0xc || 0xd => 2,
      0x3 || 0x4 || 0x7 || 0x8 || 0x9 || 0xa || 0xb || 0xe => 3,
      0x5 || 0xf => 1,
      _ => 0,
    };
    if (validBytes == 0) {
      throw FormatException(
        'Unsupported USB-MIDI CIN 0x${cin.toRadixString(16)}.',
      );
    }
    midi.addAll(packet.skip(1).take(validBytes));
  }
  return List.unmodifiable(midi);
}

List<int> _hexBytes(String packed) => <int>[
  for (var i = 0; i < packed.length; i += 2)
    int.parse(packed.substring(i, i + 2), radix: 16),
];
void main(List<String> args) {
  try {
    String? preset, output, presetXml;
    final captures = <String>[];
    for (var i = 0; i < args.length; i += 2) {
      if (i + 1 >= args.length) {
        throw const FormatException('Missing argument value.');
      }
      switch (args[i]) {
        case '--preset':
          preset = args[i + 1];
        case '--capture':
          captures.add(args[i + 1]);
        case '--preset-xml':
          presetXml = args[i + 1];
        case '--json-output':
          output = args[i + 1];
        default:
          throw FormatException('Unknown option ${args[i]}');
      }
    }
    if (preset == null) throw const FormatException('--preset is required');
    final document = objectMap(jsonDecode(File(preset).readAsStringSync()));
    final canonical = CanonicalPreset.fromJson(
      objectMap(document['preset'] ?? document),
    );
    final report = compareOffline(
      canonical,
      captures,
      presetXmlPath: presetXml,
    );
    stdout.writeln(
      'Offline preset comparison: ${(report['messages'] as List).length} messages',
    );
    for (final item in report['messages'] as List) {
      final message = objectMap(item);
      stdout.writeln(
        '${message['direction']} · ${message['family']} · '
        'algorithm=${message['algorithmCode'] ?? '?'} index=${message['parameterIndex'] ?? '?'} '
        'value=${message['value'] ?? '?'} match=${message['matchesPreset'] ?? '?'}',
      );
    }
    for (final note in report['unsupportedInputs'] as List) {
      stdout.writeln('Unsupported: $note');
    }
    if (output != null) {
      File(output)
          .writeAsStringSync('${canonicalJson(report, pretty: true)}\n');
    }
  } catch (error) {
    stderr.writeln('Offline comparison failed: $error');
    exitCode = 1;
  }
}
