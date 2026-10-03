import 'dart:math' as math;
import 'dart:typed_data';

import 'nam_file_profile.dart';
import 'usb_capture_reader.dart';

/// Pure functions over already-parsed captures. Nothing here talks to a device.
class AnalysisOptions {
  const AnalysisOptions({
    this.includeIsochronous = false,
    this.largePayloadBytes = 256,
    this.burstGapUs = 100000,
    this.timelineLimit = 200,
    this.hitLimit = 20,
  });

  /// USB audio is isochronous and irrelevant for a file transfer; off by default.
  final bool includeIsochronous;
  final int largePayloadBytes;
  final int burstGapUs;
  final int timelineLimit;
  final int hitLimit;
}

/// One logical unit: a reassembled SysEx / MIDI event run on a USB-MIDI-like
/// endpoint, or a raw URB payload on any other endpoint.
class CaptureMessage {
  const CaptureMessage({
    required this.index,
    required this.timestampUs,
    required this.direction,
    required this.endpoint,
    required this.kind,
    required this.bytes,
  });
  final int index;
  final int? timestampUs;
  final UsbDirection direction;
  final String endpoint;
  final String kind; // sysex | sysex-incomplete | midi | urb
  final Uint8List bytes;
}

List<CaptureMessage> extractMessages(
  UsbCapture capture,
  AnalysisOptions options,
) {
  final transfers = [
    for (final t in capture.transfers)
      if (options.includeIsochronous || !t.isIsochronous) t,
  ];
  final midiEndpoints = <String>{};
  final byEndpoint = <String, List<UsbTransfer>>{};
  for (final t in transfers) {
    byEndpoint.putIfAbsent('${t.endpoint}:${t.transferType}', () => []).add(t);
  }
  for (final entry in byEndpoint.entries) {
    final type = entry.value.first.transferType;
    if (type != 1 && type != 3) continue;
    final decoded = [for (final t in entry.value) _decodeUsbMidi(t.payload)];
    if (decoded.every((d) => d != null) &&
        decoded.any((d) => d!.contains(0xf0))) {
      midiEndpoints.add(entry.key);
    }
  }
  final messages = <CaptureMessage>[];
  final partial = <String, ({List<int> bytes, int? at})>{};

  void emit(UsbTransfer t, String kind, List<int> bytes, int? at) =>
      messages.add(
        CaptureMessage(
          index: messages.length,
          timestampUs: at,
          direction: t.direction,
          endpoint: t.endpointLabel,
          kind: kind,
          bytes: Uint8List.fromList(bytes),
        ),
      );

  for (final t in transfers) {
    if (!midiEndpoints.contains('${t.endpoint}:${t.transferType}')) {
      emit(t, 'urb', t.payload, t.timestampUs);
      continue;
    }
    final key = t.endpointLabel;
    var other = <int>[];
    for (final byte in _decodeUsbMidi(t.payload)!) {
      final active = partial[key];
      if (byte == 0xf0) {
        if (other.isNotEmpty) emit(t, 'midi', other, t.timestampUs);
        other = [];
        if (active != null) {
          emit(t, 'sysex-incomplete', active.bytes, active.at);
        }
        partial[key] = (bytes: [0xf0], at: t.timestampUs);
      } else if (active != null) {
        active.bytes.add(byte);
        if (byte == 0xf7) {
          emit(t, 'sysex', active.bytes, active.at);
          partial.remove(key);
        }
      } else {
        other.add(byte);
      }
    }
    if (other.isNotEmpty) emit(t, 'midi', other, t.timestampUs);
  }
  return messages;
}

/// USB-MIDI 1.0 event packets (4 bytes, CIN in the low nibble of byte 0).
List<int>? _decodeUsbMidi(Uint8List payload) {
  if (payload.isEmpty || payload.length % 4 != 0) return null;
  final midi = <int>[];
  for (var i = 0; i < payload.length; i += 4) {
    final count = switch (payload[i] & 0x0f) {
      0x2 || 0x6 || 0xc || 0xd => 2,
      0x3 || 0x4 || 0x7 || 0x8 || 0x9 || 0xa || 0xb || 0xe => 3,
      0x5 || 0xf => 1,
      _ => 0,
    };
    if (count == 0) return null;
    midi.addAll(payload.sublist(i + 1, i + 1 + count));
  }
  return midi;
}

Map<String, Object?> inspectCapture(
  UsbCapture capture, {
  List<NamNeedle> needles = const [],
  AnalysisOptions options = const AnalysisOptions(),
}) {
  final messages = extractMessages(capture, options);
  final first = messages.isEmpty ? null : messages.first.timestampUs;
  return {
    'capture': {
      'frames': capture.frameCount,
      'transfersWithPayload': capture.transfers.length,
      'emptyTransfers': capture.emptyTransfers,
      'ignoredFrames': capture.ignoredFrames,
      'isochronousTransfersExcluded': options.includeIsochronous
          ? 0
          : capture.transfers.where((t) => t.isIsochronous).length,
      'messages': messages.length,
    },
    'endpoints': _endpointSummary(capture, messages, options),
    'bursts': _bursts(messages, options),
    'timeline': _timeline(messages, first, options.timelineLimit),
    'needleHits': [
      for (final n in needles) _searchNeedle(n, capture, messages, options),
    ],
  };
}

List<Map<String, Object?>> _endpointSummary(
  UsbCapture capture,
  List<CaptureMessage> messages,
  AnalysisOptions options,
) {
  final groups = <String, List<CaptureMessage>>{};
  for (final m in messages) {
    groups
        .putIfAbsent('${m.endpoint} ${m.direction.name} ${m.kind}', () => [])
        .add(m);
  }
  final keys = groups.keys.toList()..sort();
  return [
    for (final key in keys)
      () {
        final group = groups[key]!;
        final lengths = <int, int>{};
        final headers = <String, int>{};
        final histogram = List.filled(256, 0);
        var total = 0;
        for (final m in group) {
          lengths[m.bytes.length] = (lengths[m.bytes.length] ?? 0) + 1;
          if (m.bytes.length >= 8) {
            final head = _hex(m.bytes.sublist(0, 8));
            headers[head] = (headers[head] ?? 0) + 1;
          }
          for (final b in m.bytes.take(1 << 20)) {
            histogram[b]++;
            total++;
          }
        }
        final topLengths = lengths.entries.toList()
          ..sort(
            (a, b) => b.value != a.value
                ? b.value.compareTo(a.value)
                : a.key.compareTo(b.key),
          );
        final topHeaders = headers.entries.where((e) => e.value >= 2).toList()
          ..sort(
            (a, b) => b.value != a.value
                ? b.value.compareTo(a.value)
                : a.key.compareTo(b.key),
          );
        return <String, Object?>{
          'group': key,
          'messages': group.length,
          'totalBytes': group.fold<int>(0, (s, m) => s + m.bytes.length),
          'minLength': lengths.keys.reduce(math.min),
          'maxLength': lengths.keys.reduce(math.max),
          'largePayloads': group
              .where((m) => m.bytes.length >= options.largePayloadBytes)
              .length,
          'entropyBitsPerByte': double.parse(
            _entropy(histogram, total).toStringAsFixed(3),
          ),
          'topLengths': [
            for (final e in topLengths.take(12))
              {'length': e.key, 'count': e.value},
          ],
          'repeatedHeaders8': [
            for (final e in topHeaders.take(5))
              {'hex': e.key, 'count': e.value},
          ],
        };
      }(),
  ];
}

double _entropy(List<int> histogram, int total) {
  if (total == 0) return 0;
  var bits = 0.0;
  for (final count in histogram) {
    if (count == 0) continue;
    final p = count / total;
    bits -= p * (math.log(p) / math.ln2);
  }
  return bits;
}

/// Consecutive same-endpoint/same-direction messages closer than the gap.
List<Map<String, Object?>> _bursts(
  List<CaptureMessage> messages,
  AnalysisOptions options,
) {
  final bursts = <Map<String, Object?>>[];
  var start = 0;
  bool continues(CaptureMessage a, CaptureMessage b) =>
      a.direction == b.direction &&
      a.endpoint == b.endpoint &&
      a.kind == b.kind &&
      (a.timestampUs == null ||
          b.timestampUs == null ||
          b.timestampUs! - a.timestampUs! <= options.burstGapUs);
  for (var i = 1; i <= messages.length; i++) {
    if (i < messages.length && continues(messages[i - 1], messages[i])) {
      continue;
    }
    final run = messages.sublist(start, i);
    final total = run.fold<int>(0, (s, m) => s + m.bytes.length);
    if (run.isNotEmpty &&
        (run.length >= 4 || total >= options.largePayloadBytes)) {
      bursts.add({
        'firstMessage': run.first.index,
        'direction': run.first.direction.name,
        'endpoint': run.first.endpoint,
        'kind': run.first.kind,
        'messages': run.length,
        'totalBytes': total,
        'lengthPattern': _runLengths([for (final m in run) m.bytes.length]),
      });
    }
    start = i;
  }
  bursts.sort(
    (a, b) => (b['totalBytes'] as int).compareTo(a['totalBytes'] as int),
  );
  return bursts.take(20).toList();
}

String _runLengths(List<int> lengths) {
  final parts = <String>[];
  for (var i = 0; i < lengths.length;) {
    var j = i;
    while (j < lengths.length && lengths[j] == lengths[i]) {
      j++;
    }
    parts.add(j - i == 1 ? '${lengths[i]}' : '${lengths[i]}x${j - i}');
    i = j;
    if (parts.length >= 24) {
      parts.add('...');
      break;
    }
  }
  return parts.join(',');
}

List<Map<String, Object?>> _timeline(
  List<CaptureMessage> messages,
  int? origin,
  int limit,
) {
  Map<String, Object?> row(CaptureMessage m) => {
    'message': m.index,
    'tMs': m.timestampUs == null || origin == null
        ? null
        : (m.timestampUs! - origin) / 1000,
    'direction': m.direction.name,
    'endpoint': m.endpoint,
    'kind': m.kind,
    'length': m.bytes.length,
    'head16': _hex(m.bytes.take(16).toList()),
  };
  if (messages.length <= limit) return [for (final m in messages) row(m)];
  final half = limit ~/ 2;
  return [
    for (final m in messages.take(half)) row(m),
    {'omitted': messages.length - 2 * half},
    for (final m in messages.skip(messages.length - half)) row(m),
  ];
}

Map<String, Object?> _searchNeedle(
  NamNeedle needle,
  UsbCapture capture,
  List<CaptureMessage> messages,
  AnalysisOptions options,
) {
  final hits = <Map<String, Object?>>[];
  var total = 0;
  void record(String view, CaptureMessage? m, int offset) {
    total++;
    if (hits.length < options.hitLimit) {
      hits.add({
        'view': view,
        'message': m?.index,
        'direction': m?.direction.name,
        'endpoint': m?.endpoint,
        'offset': offset,
      });
    }
  }

  for (final m in messages) {
    for (final o in _findAll(m.bytes, needle.bytes)) {
      record('raw', m, o);
    }
    if (m.kind == 'sysex') {
      for (final parity in [0, 1]) {
        for (final highFirst in [true, false]) {
          final view = 'sysex-nibbles-${highFirst ? 'hi-lo' : 'lo-hi'}@$parity';
          for (final o in _findAll(
            _nibbles(m.bytes, parity, highFirst),
            needle.bytes,
          )) {
            record(view, m, o);
          }
        }
      }
    }
  }
  // Raw URB stream per endpoint/direction, so a needle split across chunks is found.
  final streams = <String, BytesBuilder>{};
  for (final m in messages.where((m) => m.kind == 'urb')) {
    streams
        .putIfAbsent('${m.endpoint} ${m.direction.name}', BytesBuilder.new)
        .add(m.bytes);
  }
  for (final entry in streams.entries) {
    for (final o in _findAll(entry.value.toBytes(), needle.bytes)) {
      record('urb-stream ${entry.key}', null, o);
    }
  }
  return {
    'needle': needle.label,
    'length': needle.bytes.length,
    'totalHits': total,
    'hits': hits,
  };
}

Uint8List _nibbles(Uint8List bytes, int parity, bool highFirst) {
  final out = BytesBuilder();
  for (var i = parity; i + 1 < bytes.length; i += 2) {
    final a = bytes[i] & 0x0f, b = bytes[i + 1] & 0x0f;
    out.addByte(highFirst ? (a << 4) | b : (b << 4) | a);
  }
  return out.toBytes();
}

List<int> _findAll(Uint8List hay, Uint8List needle) {
  final found = <int>[];
  if (needle.isEmpty || hay.length < needle.length) return found;
  final last = hay.length - needle.length;
  for (var i = 0; i <= last; i++) {
    if (hay[i] != needle[0]) continue;
    var j = 1;
    while (j < needle.length && hay[i + j] == needle[j]) {
      j++;
    }
    if (j == needle.length) found.add(i);
  }
  return found;
}

/// Compares the first capture (reference) against every other one, message by
/// message in capture order, per direction. Answers "which byte positions are
/// constant / variable" for A/B (slot), A/C (payload) and A/D (dynamic fields).
Map<String, Object?> compareCaptures(
  Map<String, UsbCapture> captures, {
  AnalysisOptions options = const AnalysisOptions(),
}) {
  if (captures.length < 2) {
    throw const FormatException('At least two captures are required.');
  }
  final messages = {
    for (final e in captures.entries) e.key: extractMessages(e.value, options),
  };
  final labels = captures.keys.toList();
  final reference = labels.first;
  return {
    'reference': reference,
    'comparisons': [
      for (final other in labels.skip(1))
        {
          'pair': '$reference vs $other',
          for (final direction in UsbDirection.values)
            direction.name: _comparePair(
              [
                for (final m in messages[reference]!)
                  if (m.direction == direction) m,
              ],
              [
                for (final m in messages[other]!)
                  if (m.direction == direction) m,
              ],
            ),
        },
    ],
  };
}

Map<String, Object?> _comparePair(
  List<CaptureMessage> a,
  List<CaptureMessage> b,
) {
  var identical = 0, different = 0, lengthMismatch = 0;
  int? firstDivergence;
  final diffs = <Map<String, Object?>>[];
  for (var i = 0; i < math.min(a.length, b.length); i++) {
    final x = a[i].bytes, y = b[i].bytes;
    if (x.length != y.length) {
      lengthMismatch++;
      firstDivergence ??= i;
      if (diffs.length < 50) {
        diffs.add({'index': i, 'lengthA': x.length, 'lengthB': y.length});
      }
      continue;
    }
    final ranges = <List<int>>[];
    for (var p = 0; p < x.length; p++) {
      if (x[p] == y[p]) continue;
      if (ranges.isNotEmpty && ranges.last[1] == p - 1) {
        ranges.last[1] = p;
      } else {
        ranges.add([p, p]);
      }
    }
    if (ranges.isEmpty) {
      identical++;
      continue;
    }
    different++;
    firstDivergence ??= i;
    if (diffs.length < 50) {
      diffs.add({
        'index': i,
        'length': x.length,
        'variableRanges': ranges,
        'variableBytes': ranges.fold<int>(0, (s, r) => s + r[1] - r[0] + 1),
        'constantBytes':
            x.length - ranges.fold<int>(0, (s, r) => s + r[1] - r[0] + 1),
        'referenceHead16': _hex(x.take(16).toList()),
        'otherHead16': _hex(y.take(16).toList()),
      });
    }
  }
  return {
    'messagesReference': a.length,
    'messagesOther': b.length,
    'identical': identical,
    'differentSameLength': different,
    'lengthMismatch': lengthMismatch,
    'firstDivergence': firstDivergence,
    'differences': diffs,
  };
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
