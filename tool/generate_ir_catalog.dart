import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:wyrmtone/services/ir_filename_parser.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/generate_ir_catalog.dart <wav-dir> <output-json>',
    );
    exitCode = 64;
    return;
  }
  final source = Directory(arguments[0]);
  final output = File(arguments[1]);
  final files = await source
      .list(recursive: true, followLinks: false)
      .where(
        (entry) => entry is File && entry.path.toLowerCase().endsWith('.wav'),
      )
      .cast<File>()
      .toList();
  files.sort(
    (left, right) =>
        _name(left).toLowerCase().compareTo(_name(right).toLowerCase()),
  );

  final duplicateGroups = await _findDuplicateGroups(files);
  const parser = IrFilenameParser();
  final entries = <Map<String, Object?>>[];
  for (final file in files) {
    final name = _name(file);
    final metadata = parser.parse(name);
    entries.add({
      'fileName': name,
      'normalizedFileName': parser.normalizeFileName(name),
      'format': await _readWavFormat(file),
      'metadata': metadata.toJson(),
      'suitabilityHints': _suitabilityHints(metadata.detectedTags, name),
      'duplicateGroup': duplicateGroups[file.path],
    });
  }

  await output.parent.create(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  await output.writeAsString(
    '${encoder.convert({'schemaVersion': 1, 'entries': entries})}\n',
    encoding: utf8,
  );
  stdout.writeln('Generated ${entries.length} metadata entries.');
}

Future<Map<String, String>> _findDuplicateGroups(List<File> files) async {
  final byLength = <int, List<File>>{};
  for (final file in files) {
    byLength.putIfAbsent(await file.length(), () => []).add(file);
  }
  final result = <String, String>{};
  var groupNumber = 0;
  for (final candidates in byLength.values.where((group) => group.length > 1)) {
    final unmatched = [...candidates];
    while (unmatched.isNotEmpty) {
      final representative = unmatched.removeAt(0);
      final representativeBytes = await representative.readAsBytes();
      final identical = <File>[representative];
      for (var index = unmatched.length - 1; index >= 0; index--) {
        final bytes = await unmatched[index].readAsBytes();
        if (_bytesEqual(representativeBytes, bytes)) {
          identical.add(unmatched.removeAt(index));
        }
      }
      if (identical.length > 1) {
        groupNumber++;
        final id = 'duplicate-${groupNumber.toString().padLeft(2, '0')}';
        for (final file in identical) {
          result[file.path] = id;
        }
      }
    }
  }
  return result;
}

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Future<Map<String, Object?>> _readWavFormat(File file) async {
  final bytes = await file.readAsBytes();
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 12 ||
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) != 'WAVE') {
    return {
      'container': 'WAV',
      'encoding': 'unbekannt',
      'sampleRateHz': null,
      'channels': null,
      'bitsPerSample': null,
      'durationMs': null,
    };
  }
  int? encodingCode;
  int? channels;
  int? sampleRate;
  int? byteRate;
  int? bitsPerSample;
  int? dataLength;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = ascii.decode(
      bytes.sublist(offset, offset + 4),
      allowInvalid: true,
    );
    final length = data.getUint32(offset + 4, Endian.little);
    final content = offset + 8;
    if (content + length > bytes.length) break;
    if (id == 'fmt ' && length >= 16) {
      encodingCode = data.getUint16(content, Endian.little);
      channels = data.getUint16(content + 2, Endian.little);
      sampleRate = data.getUint32(content + 4, Endian.little);
      byteRate = data.getUint32(content + 8, Endian.little);
      bitsPerSample = data.getUint16(content + 14, Endian.little);
    } else if (id == 'data') {
      dataLength = length;
    }
    offset = content + length + (length.isOdd ? 1 : 0);
  }
  final encoding = switch (encodingCode) {
    1 => 'PCM',
    3 => 'IEEE Float',
    0xfffe => 'WAVE_FORMAT_EXTENSIBLE',
    final value? => 'Format $value',
    null => 'unbekannt',
  };
  return {
    'container': 'WAV',
    'encoding': encoding,
    'sampleRateHz': sampleRate,
    'channels': channels,
    'bitsPerSample': bitsPerSample,
    'durationMs': byteRate == null || byteRate == 0 || dataLength == null
        ? null
        : (dataLength * 1000 / byteRate).round(),
  };
}

List<String> _suitabilityHints(List<String> tags, String fileName) {
  final normalized = fileName.toLowerCase();
  final hints = <String>[];
  if (tags.contains('V30')) {
    hints.add('V30-Hinweis: geeigneter Kandidat für straffe High-Gain-Sounds');
  }
  if (tags.contains('Greenback')) {
    hints.add(
      'Greenback-Hinweis: geeigneter Kandidat für Classic Rock und mittige Sounds',
    );
  }
  if (tags.contains('G12T-75')) {
    hints.add(
      'G12T-75-Hinweis: geeigneter Kandidat für moderne Marshall-artige Sounds',
    );
  }
  if (normalized.contains('archenemy') ||
      normalized.contains('children') ||
      normalized.contains('bodom') ||
      normalized.contains('metallica')) {
    hints.add(
      'Dateiname deutet auf Metal/High Gain; technische Eignung durch Vorhören prüfen',
    );
  } else if (normalized.contains('nirvana') || normalized.contains('utero')) {
    hints.add(
      'Dateiname deutet auf Grunge/Alternative; technische Eignung durch Vorhören prüfen',
    );
  } else if (normalized.contains('acdc') || normalized.contains('ac dc')) {
    hints.add(
      'Dateiname deutet auf Classic Rock; technische Eignung durch Vorhören prüfen',
    );
  }
  if (hints.isEmpty) {
    hints.add(
      'Künstler-/Songreferenz; technische Eignung durch Vorhören prüfen',
    );
  }
  return hints;
}

String _name(File file) => file.uri.pathSegments.last;
