import 'dart:convert';
import 'dart:io';

import 'package:wyrmtone/presets/canonical_preset.dart';
import 'package:wyrmtone/presets/confirmed_parameter_codec.dart';

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
      unsupported.add(
        '${File(path).uri.pathSegments.last}: PCAP decoding is not implemented by the existing analyzer.',
      );
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
