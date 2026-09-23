import 'dart:io';

import 'package:wyrmtone/presets/canonical_preset.dart';
import 'package:wyrmtone/presets/confirmed_parameter_codec.dart';
import 'package:wyrmtone/presets/preset_selection_codec.dart';

import 'preset_compare.dart' show readPcapMidiObservations;

List<Map<String, Object?>> inspectMidiObservations(
  List<TimedMidiObservation> observations,
) {
  final groupByHex = <String, int>{};
  final countByHex = <String, int>{};
  for (final observation in observations) {
    final hex = _hex(observation.bytes);
    countByHex[hex] = (countByHex[hex] ?? 0) + 1;
    groupByHex.putIfAbsent(hex, () => groupByHex.length + 1);
  }
  return List.unmodifiable([
    for (var sequence = 0; sequence < observations.length; sequence++)
      _inspectObservation(
        observations[sequence],
        sequence + 1,
        groupByHex,
        countByHex,
      ),
  ]);
}

Map<String, Object?> _inspectObservation(
  TimedMidiObservation observation,
  int sequence,
  Map<String, int> groupByHex,
  Map<String, int> countByHex,
) {
  final bytes = observation.bytes;
  final hex = _hex(bytes);
  final result = <String, Object?>{
    'sequence': sequence,
    'direction': observation.direction.name,
    'timestampMs': observation.timestampMs,
    'state': observation.state.name,
    'length': bytes.length,
    'hex': hex,
    'qme2': _hasQme2(bytes),
    'identicalGroup': groupByHex[hex],
    'identicalCount': countByHex[hex],
    'deviceWriteApproved': false,
  };
  if (observation.state == MidiObservationState.incompleteSysEx) {
    return {
      ...result,
      'family': 'incompleteSysEx',
      'possibleMeaning': 'truncated capture or incomplete transfer',
      'evidenceLevel': 'observed',
    };
  }
  if (observation.state == MidiObservationState.otherMidi) {
    final controlChange = bytes.length == 3 && (bytes[0] & 0xf0) == 0xb0;
    return {
      ...result,
      'family': controlChange ? 'MIDI control change' : 'otherMidi',
      if (controlChange) 'midiChannel': (bytes[0] & 0x0f) + 1,
      if (controlChange) 'controller': bytes[1],
      if (controlChange) 'value': bytes[2],
      'possibleMeaning': controlChange
          ? 'control change; target mapping unconfirmed'
          : 'non-SysEx MIDI traffic',
      'evidenceLevel': 'observed',
    };
  }
  if (bytes.length == 34) {
    try {
      final decoded = ConfirmedParameterCodec.decode(bytes);
      return {
        ...result,
        'family': 'QME2 parameter',
        'algorithmCode': decoded.algorithmCode,
        'algorithmCodeHex':
            '0x${decoded.algorithmCode.toRadixString(16).padLeft(8, '0')}',
        'parameterIndex': decoded.parameterIndex,
        'value': decoded.value,
        'possibleMeaning': 'single live parameter value',
        'evidenceLevel': 'confirmedWireLayoutLimitedReferences',
      };
    } on FormatException {
      // Keep the complete message below as explicitly unclassified traffic.
    }
  }
  final algorithmCode = _decodeAlgorithmSelectionCode(bytes);
  if (algorithmCode != null) {
    return {
      ...result,
      'family': 'QME2 algorithm selection',
      'algorithmCode': algorithmCode,
      'algorithmCodeHex':
          '0x${algorithmCode.toRadixString(16).padLeft(8, '0')}',
      'possibleMeaning': 'select algorithm; block mapping unconfirmed',
      'evidenceLevel': 'correlatedWithLocalAlgorithmCatalog',
    };
  }
  if (ConfirmedPresetSelectionCodec.looksLikeCandidate(bytes)) {
    final rejection = ConfirmedPresetSelectionCodec.rejectionFor(bytes);
    if (rejection == null) {
      final decoded = ConfirmedPresetSelectionCodec.decode(bytes);
      return {
        ...result,
        'family': 'QME2 preset selection',
        'presetIndex': decoded.targetIndex,
        'preset': decoded.presetLabel,
        'possibleMeaning': 'select confirmed captured preset target',
        'evidenceLevel': 'confirmedControlledCapture',
      };
    }
    return {
      ...result,
      'family': 'rejected preset-selection candidate',
      'rejectionReason': rejection.reason,
      'invalidOffset': rejection.offset,
      'possibleMeaning': '22-byte QME2/envelope variant; semantics unknown',
      'evidenceLevel': 'unknown',
    };
  }
  return {
    ...result,
    'family': _hasQme2(bytes)
        ? 'QME2 0x${_hexByte(bytes[8])}/0x${_hexByte(bytes[9])} '
              '${bytes.length}-byte unclassified'
        : 'unknown',
    'possibleMeaning': 'unclassified; preserved for comparison',
    'evidenceLevel': 'observed',
  };
}

int? _decodeAlgorithmSelectionCode(List<int> bytes) {
  const prefix = <int>[
    0xf0,
    0x21,
    0x25,
    0x7f,
    0x51,
    0x4d,
    0x45,
    0x32,
    0x12,
    0x10,
    0x03,
    0x00,
    0x01,
  ];
  if (bytes.length != 22 || bytes.last != 0xf7) return null;
  for (var index = 0; index < prefix.length; index++) {
    if (bytes[index] != prefix[index]) return null;
  }
  final decoded = <int>[];
  for (var index = 13; index <= 19; index += 2) {
    final high = bytes[index], low = bytes[index + 1];
    if (high > 0x0f || low > 0x0f) return null;
    decoded.add(high * 16 + low);
  }
  return decoded[0] |
      (decoded[1] << 8) |
      (decoded[2] << 16) |
      (decoded[3] << 24);
}

bool _hasQme2(List<int> bytes) =>
    bytes.length >= 8 &&
    bytes[4] == 0x51 &&
    bytes[5] == 0x4d &&
    bytes[6] == 0x45 &&
    bytes[7] == 0x32;

String _hexByte(int byte) =>
    byte.toRadixString(16).padLeft(2, '0').toUpperCase();

String _hex(List<int> bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');

Map<String, Object?> inspectPcap(String path) {
  final messages = inspectMidiObservations(readPcapMidiObservations(path));
  final lengths = {for (final item in messages) item['length'] as int};
  return {
    'source': File(path).uri.pathSegments.last,
    'messages': messages,
    'messageCount': messages.length,
    'lengthCounts': {
      for (final length in lengths)
        '$length': messages.where((item) => item['length'] == length).length,
    },
    'directionCounts': {
      for (final direction in PresetSelectionDirection.values)
        direction.name: messages
            .where((item) => item['direction'] == direction.name)
            .length,
    },
  };
}

void main(List<String> args) {
  try {
    String? output;
    final captures = <String>[];
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--capture':
          if (++i >= args.length) {
            throw const FormatException('Missing --capture value.');
          }
          captures.add(args[i]);
        case '--output':
          if (++i >= args.length) {
            throw const FormatException('Missing --output value.');
          }
          output = args[i];
        default:
          throw FormatException('Unknown option ${args[i]}');
      }
    }
    if (captures.isEmpty) {
      throw const FormatException('At least one --capture is required.');
    }
    final report = {
      'schemaVersion': 1,
      'offlineOnly': true,
      'captures': captures.map(inspectPcap).toList(),
    };
    final encoded = '${canonicalJson(report, pretty: true)}\n';
    if (output == null) {
      stdout.write(encoded);
    } else {
      File(output).writeAsStringSync(encoded);
    }
  } catch (error) {
    stderr.writeln('Offline capture inspection failed: $error');
    exitCode = 1;
  }
}
