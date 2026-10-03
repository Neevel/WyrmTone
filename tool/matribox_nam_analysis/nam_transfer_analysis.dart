import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'capture_analysis.dart';
import 'clone_data.dart';
import 'nam_transfer_codec.dart';
import 'usb_capture_reader.dart';

/// Offline evidence report for Clone (NAM) transfers. Inputs are parsed
/// captures and NAM files; outputs are a JSON-friendly report plus artifacts
/// (reconstructed CloData, CSV tables) the caller may write outside the repo.
class NamTransferAnalysis {
  NamTransferAnalysis(this.report, this.artifacts);
  final Map<String, Object?> report;
  final Map<String, Uint8List> artifacts;
}

NamTransferAnalysis analyzeCloneTransfers(
  Map<String, UsbCapture> captures, {
  Map<String, Uint8List> namFiles = const {},
  Map<String, String> namFileNames = const {},
}) {
  if (captures.isEmpty) throw const FormatException('No captures.');
  final artifacts = <String, Uint8List>{};
  final perCapture = <String, Map<String, Object?>>{};
  final clo = <String, Uint8List?>{};
  final frames = <String, List<_Timed>>{};
  final labels = captures.keys.toList();

  for (final label in labels) {
    final messages = extractMessages(captures[label]!, const AnalysisOptions());
    final host = [
      for (final m in messages)
        if (m.direction == UsbDirection.hostToDevice) m,
    ];
    final device = [
      for (final m in messages)
        if (m.direction == UsbDirection.deviceToHost) m,
    ];
    final blocks = [
      for (final m in host)
        if (m.kind == 'sysex' && m.bytes.length == namBlockMessageLength) m,
    ];
    final reconstruction = reconstructCloneTransfer([
      for (final m in blocks) m.bytes,
    ]);
    clo[label] = reconstruction.cloData;
    if (reconstruction.cloData != null) {
      artifacts['${_slug(label)}_clodata.bin'] = reconstruction.cloData!;
    }
    final parsedBlocks = <_Timed>[];
    for (final m in blocks) {
      try {
        parsedBlocks.add(
          _Timed(NamTransferFrame.parse(m.bytes), m.timestampUs, m.bytes),
        );
      } on FormatException {
        // counted by the reconstruction
      }
    }
    frames[label] = parsedBlocks;
    final acks = <({NamTransferAck ack, int? t, Uint8List raw})>[];
    var otherDevice = 0;
    for (final m in device) {
      try {
        acks.add((
          ack: NamTransferAck.parse(m.bytes),
          t: m.timestampUs,
          raw: m.bytes,
        ));
      } on FormatException {
        otherDevice++;
      }
    }
    final firstBlockT = parsedBlocks.isEmpty ? null : parsedBlocks.first.t;
    perCapture[label] = {
      'logicalMessages': messages.length,
      'hostMessages': host.length,
      'deviceMessages': device.length,
      'blockMessages': blocks.length,
      'ackMessages': acks.length,
      'deviceMessagesNotAck': otherDevice,
      'hostMessagesNotBlock': [
        for (final m in host)
          if (!blocks.contains(m))
            {
              'kind': m.kind,
              'length': m.bytes.length,
              'msBeforeFirstBlock': m.timestampUs == null || firstBlockT == null
                  ? null
                  : (firstBlockT - m.timestampUs!) / 1000,
              'hex': _hex(m.bytes),
            },
      ],
      'endpointsUsed': [
        for (final e in {...messages.map((m) => m.endpoint)}) e,
      ]..sort(),
      'reconstruction': {
        'complete': reconstruction.isComplete,
        'distinctBlocks': reconstruction.blockCount,
        'missingBlocks': reconstruction.missingBlocks,
        'repeatedBlocks': {
          for (final e in reconstruction.duplicateBlocks.entries)
            '${e.key}': e.value,
        },
        'conflictingBlocks': reconstruction.conflictingBlocks,
        'slotBytesSeen': reconstruction.slots.toList()..sort(),
        'checksumFailures': reconstruction.checksumFailures,
        'malformed': reconstruction.malformed,
        'cloDataBytes': reconstruction.cloData?.length,
        'cloDataSha256': reconstruction.cloData == null
            ? null
            : sha256.convert(reconstruction.cloData!).toString(),
      },
      'ack': _ackAnalysis(parsedBlocks, acks, artifacts, label),
      'checksumCandidates': _checksumCandidates(
        blocks.map((m) => m.bytes).toList(),
      ),
    };
  }

  final reference = labels.first;
  final comparisons = <Map<String, Object?>>[];
  for (final other in labels.skip(1)) {
    comparisons.add(
      _compare(
        reference,
        other,
        clo,
        frames,
        captures,
        artifacts,
        namFiles,
        namFileNames,
      ),
    );
  }
  return NamTransferAnalysis({
    'schemaVersion': 1,
    'offlineOnly': true,
    'captures': perCapture,
    'reference': reference,
    'comparisons': comparisons,
    'regionMap': _regionMap(labels, clo),
    'name': _nameAnalysis(labels, clo, namFiles, namFileNames),
    'namWeightsVsCloData': _weightSearch(labels, clo, namFiles),
  }, artifacts);
}

class _Timed {
  const _Timed(this.frame, this.t, this.raw);
  final NamTransferFrame frame;
  final int? t;
  final Uint8List raw;
}

String _slug(String label) =>
    label.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');

Map<String, Object?> _ackAnalysis(
  List<_Timed> blocks,
  List<({NamTransferAck ack, int? t, Uint8List raw})> acks,
  Map<String, Uint8List> artifacts,
  String label,
) {
  final sameSequence =
      blocks.length == acks.length &&
      [
        for (var i = 0; i < blocks.length; i++)
          blocks[i].frame.slot == acks[i].ack.slot &&
              blocks[i].frame.block == acks[i].ack.block,
      ].every((e) => e);
  final origin = blocks.isEmpty ? null : blocks.first.t;
  final rows = StringBuffer('index,block,slot,sendMs,ackMs,latencyMs,status\n');
  final latencies = <double>[];
  final gaps = <double>[];
  final pipelined = <int>[];
  for (var i = 0; i < math.min(blocks.length, acks.length); i++) {
    final s = blocks[i].t, a = acks[i].t;
    final latency = s == null || a == null ? null : (a - s) / 1000;
    if (latency != null) latencies.add(latency);
    if (i + 1 < blocks.length && a != null && blocks[i + 1].t != null) {
      final gap = (blocks[i + 1].t! - a) / 1000;
      if (gap >= 0) {
        gaps.add(gap);
      } else {
        pipelined.add(blocks[i].frame.block);
      }
    }
    rows.writeln(
      '$i,${blocks[i].frame.block},${blocks[i].frame.slot},'
      '${s == null || origin == null ? '' : (s - origin) / 1000},'
      '${a == null || origin == null ? '' : (a - origin) / 1000},'
      '${latency ?? ''},${acks[i].ack.status}',
    );
  }
  artifacts['${_slug(label)}_acks.csv'] = Uint8List.fromList(
    utf8.encode(rows.toString()),
  );
  final lastTimes = [
    for (final b in blocks.where(
      (b) => b.frame.block == (blocks.isEmpty ? -1 : blocks.last.frame.block),
    ))
      b.t,
  ];
  return {
    'ackSequenceEqualsBlockSequence': sameSequence,
    'statusValues': {
      for (final s in {...acks.map((a) => a.ack.status)})
        '$s': acks.where((a) => a.ack.status == s).length,
    },
    'blocksSentBeforePreviousAckArrived': pipelined,
    'latencyMs': _stats(latencies),
    'ackToNextBlockMs': _stats(gaps),
    'slowestLatencies': (() {
      final indexed = [
        for (var i = 0; i < latencies.length; i++)
          (latencies[i], blocks[i].frame.block),
      ]..sort((a, b) => b.$1.compareTo(a.$1));
      return [
        for (final e in indexed.take(4))
          {'block': e.$2, 'ms': double.parse(e.$1.toStringAsFixed(3))},
      ];
    })(),
    'lastBlockSendIntervalsMs': [
      for (var i = 1; i < lastTimes.length; i++)
        if (lastTimes[i] != null && lastTimes[i - 1] != null)
          (lastTimes[i]! - lastTimes[i - 1]!) / 1000,
    ],
    'transferMs':
        blocks.isEmpty || acks.isEmpty || origin == null || acks.last.t == null
        ? null
        : (acks.last.t! - origin) / 1000,
  };
}

Map<String, Object?> _stats(List<double> values) {
  if (values.isEmpty) return const {};
  final sorted = [...values]..sort();
  double r(double v) => double.parse(v.toStringAsFixed(3));
  return {
    'count': sorted.length,
    'min': r(sorted.first),
    'median': r(sorted[sorted.length ~/ 2]),
    'max': r(sorted.last),
  };
}

/// Candidate per-block check values; compared with the 2 wire nibbles before
/// F7 over every block message of the capture. Only an algorithm matching all
/// blocks (and both slots/NAMs) counts as confirmed.
Map<String, Object?> _checksumCandidates(List<Uint8List> blockMessages) {
  final valid = [
    for (final m in blockMessages)
      if (m.length == namBlockMessageLength) m,
  ];
  int crc8(List<int> data, int poly) {
    var crc = 0;
    for (final b in data) {
      crc ^= b;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x80) != 0
            ? ((crc << 1) ^ poly) & 0xff
            : (crc << 1) & 0xff;
      }
    }
    return crc;
  }

  int xor(List<int> d) => d.fold(0, (a, b) => a ^ b);
  int sum(List<int> d) => d.fold(0, (a, b) => a + b);
  final algorithms = <String, int Function(Uint8List)>{
    'sum8 of 28 wire nibbles': (m) => sum(m.sublist(16, 44)) & 0xff,
    'sum7 of 28 wire nibbles': (m) => sum(m.sublist(16, 44)) & 0x7f,
    'xor of 28 wire nibbles': (m) => xor(m.sublist(16, 44)),
    'sum8 of 14 decoded bytes': (m) =>
        sum(decodeTransferPayload(m.sublist(16, 44))) & 0xff,
    'xor of 14 decoded bytes': (m) =>
        xor(decodeTransferPayload(m.sublist(16, 44))),
    'two-complement sum8 of nibbles': (m) => (-sum(m.sublist(16, 44))) & 0xff,
    'crc8 0x07 of nibbles': (m) => crc8(m.sublist(16, 44), 0x07),
    'crc8 0x31 of nibbles': (m) => crc8(m.sublist(16, 44), 0x31),
    'crc8 0x07 of decoded bytes': (m) =>
        crc8(decodeTransferPayload(m.sublist(16, 44)), 0x07),
    'sum8 of nibbles + slot + block bytes': (m) =>
        (sum(m.sublist(16, 44)) + m[13] + m[14] + m[15]) & 0xff,
    'sum8 of bytes 13..43 (slot, block, nibbles)': (m) =>
        sum(m.sublist(13, 44)) & 0xff,
  };
  return {
    'blocks': valid.length,
    'matches': {
      for (final e in algorithms.entries)
        e.key: valid.where((m) => e.value(m) == ((m[44] << 4) | m[45])).length,
    },
  };
}

Map<String, Object?> _compare(
  String a,
  String b,
  Map<String, Uint8List?> clo,
  Map<String, List<_Timed>> frames,
  Map<String, UsbCapture> captures,
  Map<String, Uint8List> artifacts,
  Map<String, Uint8List> namFiles,
  Map<String, String> namFileNames,
) {
  final fa = frames[a]!, fb = frames[b]!;
  final positions = <int>{};
  var pairs = 0;
  for (var i = 0; i < math.min(fa.length, fb.length); i++) {
    pairs++;
    for (var p = 0; p < fa[i].raw.length; p++) {
      if (fa[i].raw[p] != fb[i].raw[p]) positions.add(p);
    }
  }
  final ca = clo[a], cb = clo[b];
  final result = <String, Object?>{
    'pair': '$a vs $b',
    'blockMessagePairsCompared': pairs,
    'blockMessageBytePositionsThatDiffer': positions.toList()..sort(),
    'blockNumbersEqualPairwise':
        fa.length == fb.length &&
        [
          for (var i = 0; i < fa.length; i++)
            fa[i].frame.block == fb[i].frame.block,
        ].every((e) => e),
    'slotWireValues': {
      a: fa.map((f) => f.frame.slot).toSet().toList(),
      b: fb.map((f) => f.frame.slot).toSet().toList(),
    },
    'cloDataIdentical': ca != null && cb != null && _equal(ca, cb),
    'sameNamFile': namFiles.containsKey(a) && namFiles.containsKey(b)
        ? _equal(namFiles[a]!, namFiles[b]!)
        : null,
  };
  if (ca != null && cb != null) {
    final ranges = <List<int>>[];
    for (var i = 0; i < ca.length; i++) {
      if (ca[i] == cb[i]) continue;
      if (ranges.isNotEmpty && ranges.last[1] == i - 1) {
        ranges.last[1] = i;
      } else {
        ranges.add([i, i]);
      }
    }
    result['differingBytes'] = ranges.fold<int>(
      0,
      (s, r) => s + r[1] - r[0] + 1,
    );
    result['differingRangeCount'] = ranges.length;
    result['differingEnvelope'] = ranges.isEmpty
        ? null
        : [ranges.first[0], ranges.last[1]];
    final csv = StringBuffer(
      'block,sameBytes,differentBytes,percentDifferent,entropyA,entropyB\n',
    );
    for (var block = 0; block * namBlockPayloadBytes < ca.length; block++) {
      final from = block * namBlockPayloadBytes,
          to = from + namBlockPayloadBytes;
      var diff = 0;
      for (var i = from; i < to; i++) {
        if (ca[i] != cb[i]) diff++;
      }
      csv.writeln(
        '$block,${namBlockPayloadBytes - diff},$diff,${(100 * diff / namBlockPayloadBytes).toStringAsFixed(1)},'
        '${_entropy(ca.sublist(from, to)).toStringAsFixed(3)},${_entropy(cb.sublist(from, to)).toStringAsFixed(3)}',
      );
    }
    artifacts['${_slug(a)}_vs_${_slug(b)}_blocks.csv'] = Uint8List.fromList(
      utf8.encode(csv.toString()),
    );
  }
  return result;
}

/// Regions defined by the confirmed layout (see [MatriboxCloneData]); the
/// evidence column says why a boundary is believed, never what it "means".
Map<String, Object?> _regionMap(
  List<String> labels,
  Map<String, Uint8List?> clo,
) {
  const regions = <(int, int, String, String)>[
    (
      0x0000,
      0x0010,
      'NAME',
      'CONFIRMED: equals file name (A/B/C); max 16 bytes by editor code',
    ),
    (
      0x0010,
      0x0020,
      'UNKNOWN_REGION_1 (zero)',
      'CORRELATED: zero in all captures',
    ),
    (
      0x0020,
      0x0028,
      'VTSI header (magic, size 0x1288)',
      'CONFIRMED: editor code writes both constants',
    ),
    (
      0x0028,
      0x0034,
      'UNKNOWN_REGION_2 (zero; CRC field)',
      'CORRELATED: editor computes CRC only for size 0x2288',
    ),
    (0x0034, 0x0038, 'data length 0x1200', 'CONFIRMED: editor code and bytes'),
    (
      0x0038,
      0x0088,
      'CONSTANT_REGION (doubles)',
      'CORRELATED: identical in all captures',
    ),
    (
      0x0088,
      0x0098,
      'VARIABLE_REGION_1 (4 x float32)',
      'CORRELATED: differs between NAMs',
    ),
    (
      0x0098,
      0x00a8,
      'PARTITION_FIELDS (0,128,128,1024)',
      'CONFIRMED: editor reads 0x80/0x84 fields as counts',
    ),
    (
      0x00a8,
      0x12a8,
      'VARIABLE_REGION_2 (1152 x float32)',
      'CONFIRMED: length = data length; values differ between NAMs',
    ),
    (
      0x12a8,
      0x2028,
      'TAIL (zeros, last 8 bytes 0xFF)',
      'CORRELATED: identical in all captures',
    ),
  ];
  final present = [
    for (final l in labels)
      if (clo[l] != null) l,
  ];
  return {
    'labels': present,
    'regions': [
      for (final r in regions)
        {
          'offset': r.$1,
          'length': r.$2 - r.$1,
          'name': r.$3,
          'evidence': r.$4,
          'identicalInAllCaptures': present.every(
            (l) => _equal(
              clo[l]!.sublist(r.$1, r.$2),
              clo[present.first]!.sublist(r.$1, r.$2),
            ),
          ),
          'entropyBitsPerByte': {
            for (final l in present)
              l: double.parse(
                _entropy(clo[l]!.sublist(r.$1, r.$2)).toStringAsFixed(3),
              ),
          },
        },
    ],
    'layoutParsesAndRoundTrips': {
      for (final l in present) l: _roundTrips(clo[l]!),
    },
  };
}

bool _roundTrips(Uint8List data) {
  try {
    return _equal(MatriboxCloneData.parse(data).serialize(), data);
  } on FormatException {
    return false;
  }
}

Map<String, Object?> _nameAnalysis(
  List<String> labels,
  Map<String, Uint8List?> clo,
  Map<String, Uint8List> namFiles,
  Map<String, String> namFileNames,
) => {
  for (final l in labels)
    if (clo[l] != null)
      l: () {
        final data = clo[l]!;
        final field = data.sublist(0, 16);
        final end = field.indexOf(0);
        final text = String.fromCharCodes(
          end < 0 ? field : field.sublist(0, end),
        );
        final fileName = namFileNames[l];
        final stem = fileName == null
            ? null
            : (fileName.toLowerCase().endsWith('.nam')
                  ? fileName.substring(0, fileName.length - 4)
                  : fileName);
        String? metadataName;
        if (namFiles[l] != null) {
          try {
            final meta =
                (jsonDecode(utf8.decode(namFiles[l]!)) as Map)['metadata'];
            metadataName = meta is Map ? meta['name'] as String? : null;
          } on Object {
            metadataName = null;
          }
        }
        return {
          'transferred': text,
          'fieldBytesHex': _hex(field),
          'nulTerminatedInField': end >= 0,
          'zeroBytesAfterName0x10to0x1f': data
              .sublist(16, 32)
              .every((b) => b == 0),
          'fileNameStem': stem,
          'stemLength': stem?.length,
          'equalsStemTruncatedTo16': stem == null
              ? null
              : text == (stem.length > 16 ? stem.substring(0, 16) : stem),
          'metadataName': metadataName,
          'equalsMetadataNameTruncatedTo16': metadataName == null
              ? null
              : text ==
                    (metadataName.length > 16
                        ? metadataName.substring(0, 16)
                        : metadataName),
        };
      }(),
};

/// Searches NAM weights as float32 LE/BE and float64 LE inside CloData:
/// 1) any single hit (chance level shown), 2) runs of >= 3 consecutive weights.
Map<String, Object?> _weightSearch(
  List<String> labels,
  Map<String, Uint8List?> clo,
  Map<String, Uint8List> namFiles,
) {
  final out = <String, Object?>{};
  for (final l in labels) {
    final data = clo[l], nam = namFiles[l];
    if (data == null || nam == null) continue;
    final weights = <double>[];
    try {
      void collect(Object? node) {
        if (node is! Map) return;
        final w = node['weights'];
        if (w is List) {
          weights.addAll(w.whereType<num>().map((n) => n.toDouble()));
        }
        final config = node['config'];
        if (config is Map && config['submodels'] is List) {
          for (final s in (config['submodels'] as List).whereType<Map>()) {
            collect(s['model']);
          }
        }
      }

      collect(jsonDecode(utf8.decode(nam)));
    } on Object {
      continue;
    }
    final result = <String, Object?>{'weights': weights.length};
    for (final (name, width, little, double64) in [
      ('float32-le', 4, true, false),
      ('float32-be', 4, false, false),
      ('float64-le', 8, true, true),
    ]) {
      Uint8List enc(double v) {
        final d = ByteData(width);
        double64
            ? d.setFloat64(0, v, little ? Endian.little : Endian.big)
            : d.setFloat32(0, v, little ? Endian.little : Endian.big);
        return d.buffer.asUint8List();
      }

      final index = <String, List<int>>{};
      for (var k = 0; k < weights.length; k++) {
        (index[_hex(enc(weights[k]))] ??= []).add(k);
      }
      var single = 0, runs = 0;
      for (var off = 0; off + width * 3 <= data.length; off++) {
        final hit = index[_hex(data.sublist(off, off + width))];
        if (hit == null) continue;
        single++;
        final next = index[_hex(data.sublist(off + width, off + 2 * width))];
        final third =
            index[_hex(data.sublist(off + 2 * width, off + 3 * width))];
        if (next != null &&
            third != null &&
            hit.any((k) => next.contains(k + 1) && third.contains(k + 2))) {
          runs++;
        }
      }
      result[name] = {
        'singleHits': single,
        'runsOf3': runs,
        'expectedSingleHitsByChance': double.parse(
          (weights.length * data.length / math.pow(2.0, width * 8))
              .toStringAsFixed(4),
        ),
      };
    }
    out[l] = result;
  }
  return out;
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

double _entropy(List<int> bytes) {
  if (bytes.isEmpty) return 0;
  final h = List.filled(256, 0);
  for (final b in bytes) {
    h[b]++;
  }
  var bits = 0.0;
  for (final c in h) {
    if (c == 0) continue;
    final p = c / bytes.length;
    bits -= p * (math.log(p) / math.ln2);
  }
  return bits;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
