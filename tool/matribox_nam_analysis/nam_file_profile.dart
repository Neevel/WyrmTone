import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// A byte sequence that a later capture analysis looks for in USB payloads.
///
/// Needles only say "these bytes come from the source file"; a hit is
/// evidence of an unmodified transfer, a miss is NOT evidence of anything.
class NamNeedle {
  const NamNeedle(this.label, this.bytes);
  final String label;
  final Uint8List bytes;
}

/// Reproducible, offline description of one `.nam` file (no device access).
class NamFileProfile {
  NamFileProfile._(this.report, this.needles);

  final Map<String, Object?> report;
  final List<NamNeedle> needles;

  /// Throws [FormatException] for empty input. Non-JSON input is described
  /// (size, hash, `isJsonObject: false`) instead of rejected.
  factory NamFileProfile.describe(Uint8List bytes, {String? fileName}) {
    if (bytes.isEmpty) throw const FormatException('Empty NAM file.');
    final report = <String, Object?>{
      'fileName': ?fileName,
      'sizeBytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      'startsWithUtf8Bom':
          bytes.length >= 3 &&
          bytes[0] == 0xef &&
          bytes[1] == 0xbb &&
          bytes[2] == 0xbf,
      'endsWithNewline': bytes.last == 0x0a,
    };
    final needles = <NamNeedle>[];
    String? text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      report['isUtf8'] = false;
    }
    if (text != null) {
      report['isUtf8'] = true;
      report['containsLineBreaks'] = text.contains('\n');
      Object? decoded;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
      report['isJsonObject'] = decoded is Map<String, Object?>;
      if (decoded is Map<String, Object?>) {
        _describeJson(decoded, report);
        needles.addAll(_needles(bytes, text, decoded));
      }
    } else {
      report['isJsonObject'] = false;
    }
    return NamFileProfile._(report, List.unmodifiable(needles));
  }
}

void _describeJson(Map<String, Object?> json, Map<String, Object?> report) {
  report['topLevelKeys'] = json.keys.toList();
  report['version'] = json['version'];
  report['architecture'] = json['architecture'];
  report['sampleRate'] = json['sample_rate'];
  report['metadata'] = _scalars(json['metadata']);
  final weights = json['weights'];
  final submodels = <Map<String, Object?>>[];
  final config = json['config'];
  if (config is Map<String, Object?> && config['submodels'] is List) {
    for (final entry in (config['submodels'] as List).whereType<Map>()) {
      final model = entry['model'];
      final m = model is Map ? model : const {};
      submodels.add({
        'maxValue': entry['max_value'],
        'version': m['version'],
        'architecture': m['architecture'],
        'sampleRate': m['sample_rate'],
        'weightCount': m['weights'] is List
            ? (m['weights'] as List).length
            : null,
        'metadata': _scalars(m['metadata']),
      });
    }
  }
  report['submodels'] = submodels;
  report['weightCountTopLevel'] = weights is List ? weights.length : null;
  report['weightCountTotal'] =
      (weights is List ? weights.length : 0) +
      submodels.fold<int>(
        0,
        (sum, s) => sum + ((s['weightCount'] as int?) ?? 0),
      );
  report['isSlimmableContainer'] = json['architecture'] == 'SlimmableContainer';
  // The file cannot tell A1/A2/A2-Lite; that tag comes from TONE3000 metadata.
  report['tone3000ArchitectureTag'] = 'not present in file';
}

Map<String, Object?> _scalars(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final e in value.entries)
      if (e.value is String ||
          e.value is num ||
          e.value is bool ||
          e.value == null)
        '${e.key}': e.value is String && (e.value as String).length > 120
            ? (e.value as String).substring(0, 120)
            : e.value,
  };
}

List<NamNeedle> _needles(
  Uint8List bytes,
  String text,
  Map<String, Object?> json,
) {
  final needles = <NamNeedle>[];
  void add(String label, List<int> data) {
    if (data.length >= 4) {
      needles.add(NamNeedle(label, Uint8List.fromList(data)));
    }
  }

  int clampEnd(int i) => i > bytes.length ? bytes.length : i;
  add('file-head-24', bytes.sublist(0, clampEnd(24)));
  add(
    'file-tail-24',
    bytes.sublist(bytes.length - 24 < 0 ? 0 : bytes.length - 24),
  );
  final mid = bytes.length ~/ 2;
  add('file-mid-32', bytes.sublist(mid, clampEnd(mid + 32)));
  final marker = text.indexOf('"weights":[');
  if (marker >= 0) {
    final start = marker + '"weights":['.length;
    add(
      'weights-text-32',
      utf8.encode(
        text.substring(
          start,
          start + 32 > text.length ? text.length : start + 32,
        ),
      ),
    );
  }
  for (final key in const ['name', 'modeled_by', 'gear_make', 'gear_model']) {
    final value = (json['metadata'] is Map
        ? (json['metadata'] as Map)[key]
        : null);
    if (value is String && value.length >= 4) {
      add('metadata-$key', utf8.encode(value));
    }
  }
  final firstWeights = _firstWeights(json, 4);
  if (firstWeights.length == 4) {
    for (final little in [true, false]) {
      final data = ByteData(16);
      for (var i = 0; i < 4; i++) {
        data.setFloat32(
          i * 4,
          firstWeights[i],
          little ? Endian.little : Endian.big,
        );
      }
      add(
        'weights-float32-${little ? 'le' : 'be'}-first4',
        data.buffer.asUint8List(),
      );
    }
  }
  needles.addAll(_checksumCandidates(bytes));
  return needles;
}

List<double> _firstWeights(Map<String, Object?> json, int count) {
  List? find(Map<String, Object?> node) {
    final w = node['weights'];
    if (w is List && w.length >= count) return w;
    final config = node['config'];
    if (config is Map && config['submodels'] is List) {
      for (final entry in (config['submodels'] as List).whereType<Map>()) {
        final model = entry['model'];
        if (model is Map<String, Object?>) {
          final found = find(model);
          if (found != null) return found;
        }
      }
    }
    return null;
  }

  final weights = find(json);
  if (weights == null || weights.take(count).any((w) => w is! num)) {
    return const [];
  }
  return [for (final w in weights.take(count)) (w as num).toDouble()];
}

/// Checksums the official editor MAY compute (its log strings mention
/// "checksum"). Candidates only: a hit is a correlation, never proof. Only
/// 32-bit values are searched; shorter ones would match by chance.
List<NamNeedle> _checksumCandidates(Uint8List bytes) {
  var sum = 0;
  var a = 1;
  var b = 0;
  var crc = 0xffffffff;
  for (final byte in bytes) {
    sum = (sum + byte) & 0xffffffff;
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  final values = <String, int>{
    'crc32': (crc ^ 0xffffffff) & 0xffffffff,
    'adler32': ((b << 16) | a) & 0xffffffff,
    'sum32': sum,
  };
  return [
    for (final entry in values.entries)
      for (final little in [true, false])
        NamNeedle(
          'checksum-candidate:${entry.key}-${little ? 'le' : 'be'}='
          '0x${entry.value.toRadixString(16).padLeft(8, '0')}',
          (ByteData(
                4,
              )..setUint32(0, entry.value, little ? Endian.little : Endian.big))
              .buffer
              .asUint8List(),
        ),
  ];
}
