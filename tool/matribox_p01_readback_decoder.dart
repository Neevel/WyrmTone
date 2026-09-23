import 'dart:io';

import 'package:wyrmtone/presets/canonical_preset.dart' show canonicalJson;
import 'package:wyrmtone/presets/p01_readback_decoder.dart'
    show DecodedPresetReadback, decodeMatchingPresets;

import 'preset_compare.dart' show readPcapMidiObservations;

/// Thin offline CLI over the shared decoder in
/// `lib/presets/p01_readback_decoder.dart` (also used by the in-app
/// compile-gated read probe). Reads only already-captured PCAP/PCAPNG files
/// (TShark as a file decoder, same as `matribox_capture_inspector.dart`).
/// No MIDI port is opened, no SysEx is sent, no USB device is touched.

String _formatReport(
  String source,
  String expectedName,
  List<DecodedPresetReadback> matches,
) {
  final buffer = StringBuffer();
  buffer.writeln('Source: $source');
  if (matches.isEmpty) {
    buffer.writeln(
      'No readback cycle named "$expectedName" found in this capture. '
      'No fields are reported; nothing is guessed.',
    );
    return buffer.toString();
  }
  for (final match in matches) {
    buffer.writeln('User P${(match.slot + 1).toString().padLeft(2, '0')}');
    buffer.writeln('Name: ${match.name}');
    buffer.writeln();
    buffer.writeln('Amp:');
    buffer.writeln('  Gain:     ${match.gain}');
    buffer.writeln('  Presence: ${match.presence}');
    buffer.writeln('  Volume:   ${match.volume}');
    buffer.writeln('  Bass:     ${match.bass}');
    buffer.writeln('  Middle:   ${match.middle}');
    buffer.writeln('  Treble:   ${match.treble}');
    buffer.writeln();
  }
  return buffer.toString();
}

void main(List<String> args) {
  try {
    String? output;
    var expectedName = 'CKY 96 STUD';
    final captures = <String>[];
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--capture':
          if (++i >= args.length) {
            throw const FormatException('Missing --capture value.');
          }
          captures.add(args[i]);
        case '--name':
          if (++i >= args.length) {
            throw const FormatException('Missing --name value.');
          }
          expectedName = args[i];
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
    final jsonReport = <String, Object?>{
      'schemaVersion': 1,
      'offlineOnly': true,
      'expectedName': expectedName,
      'captures': [],
    };
    for (final path in captures) {
      final observations = readPcapMidiObservations(path);
      final matches = decodeMatchingPresets(
        observations,
        expectedName: expectedName,
      );
      final source = File(path).uri.pathSegments.last;
      stdout.write(_formatReport(source, expectedName, matches));
      (jsonReport['captures'] as List).add({
        'source': source,
        'matches': matches.map((m) => m.toJson()).toList(),
      });
    }
    if (output != null) {
      File(
        output,
      ).writeAsStringSync('${canonicalJson(jsonReport, pretty: true)}\n');
    }
  } catch (error) {
    stderr.writeln('Offline P01 readback decoding failed: $error');
    exitCode = 1;
  }
}
