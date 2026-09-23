/// Offline classifier for a Matribox 1 editor capture (host->device SysEx).
///
/// Prepared for the planned "big capture" (several blocks changed in one
/// editor session). It clusters EVERY host->device message by
/// length + command-header bytes (not only 34-byte parameter writes),
/// decodes the known parameter-write family, maps algorithm codes to the
/// local catalog and reports what varies inside each cluster -- so model
/// selections, enable/disable, name and store messages can be found without
/// assuming their format in advance.
///
/// Nothing here sends anything or touches a device. Labels are working
/// hypotheses except for the one family already confirmed by hardware
/// (the 34-byte single-parameter write). MATRIBOX_II_PRO_REFERENCE
/// evidence is only ever attached as a comparison hint by
/// [crossCorrelate]; it never upgrades a Matribox 1 label.
library;

import 'dart:typed_data';

const _qme2Prefix = [0xf0, 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32];

class CaptureMessage {
  const CaptureMessage({
    required this.direction,
    required this.timestampMs,
    required this.bytes,
  });

  final String direction;
  final double timestampMs;
  final List<int> bytes;

  factory CaptureMessage.fromReport(Map<String, Object?> json) => CaptureMessage(
    direction: json['direction'] as String,
    timestampMs: (json['timestampMs'] as num).toDouble(),
    bytes: [
      for (final token in (json['hex'] as String).trim().split(RegExp(r'\s+')))
        int.parse(token, radix: 16),
    ],
  );
}

class CatalogModel {
  const CatalogModel({required this.category, required this.name, required this.code});
  final String category;
  final String name;
  final int code;
}

/// Working label for a cluster. Only [parameterWrite] is hardware-confirmed
/// for Matribox 1; everything else is a hypothesis to be checked against the
/// BEFORE/AFTER raw presets.
enum CaptureFamily {
  /// `12 10 SS 00 02`, 34 bytes: algorithm/index/float parameter write for
  /// chain slot SS. Slot 3 (AMP) is hardware-confirmed; the other slots are
  /// CORRELATED from the big capture (known action order + BEFORE/AFTER).
  parameterWrite,

  /// `12 10 SS 00 01`, 22 bytes: model (algorithm code) selection for slot SS.
  modelSelection,

  /// `12 11 00 00 NN`: preset-level metadata (name, BPM, VOL, type, ...),
  /// also re-sent as part of the Save burst.
  presetMetadata,

  /// `12 12 00 00 02`, 22 bytes: last message of the Save burst.
  commitCandidate,

  /// 3-byte MIDI control change (block ON/OFF in the big capture).
  midiControlChange,

  /// Other 22-byte QME2 messages.
  presetSelectionCandidate,
  nameCandidate,
  unknownQme2,
  nonQme2,
}

/// Chain slot (header byte 10) -> block name. CORRELATED by the big capture
/// of 2026-09-19 (slot = chain position + 1); never derived from II Pro data.
const matriboxSlotBlocks = <int, String>{
  1: 'FX1',
  2: 'FX2',
  3: 'AMP',
  4: 'NR',
  5: 'CAB',
  6: 'EQ',
  7: 'MOD',
  8: 'DLY',
  9: 'RVB',
};

class CaptureCluster {
  CaptureCluster({required this.key, required this.family});

  final String key;
  CaptureFamily family;
  final List<CaptureMessage> messages = [];

  int get length => messages.first.bytes.length;

  /// Byte positions whose value differs between messages of this cluster:
  /// where model/slot/enable/value information can live.
  List<int> get variablePositions => [
    for (var i = 0; i < length; i++)
      if (messages.map((m) => m.bytes[i]).toSet().length > 1) i,
  ];

  double get firstMs => messages.first.timestampMs;
  double get lastMs => messages.last.timestampMs;
}

class ParameterWriteRun {
  ParameterWriteRun({
    required this.slot,
    required this.algorithmCode,
    required this.parameterIndex,
    required this.models,
  });

  final int slot;
  final int algorithmCode;
  final int parameterIndex;
  final List<CatalogModel> models;
  final List<double> values = [];
  double firstMs = 0;
  double lastMs = 0;
}

class CaptureReport {
  CaptureReport({
    required this.clusters,
    required this.runs,
    required this.codeChanges,
    required this.nameCandidates,
    required this.messageCount,
    this.modelSelections = const [],
    this.metadata = const [],
    this.controlChanges = const [],
    this.bursts = const [],
  });

  final List<CaptureCluster> clusters;
  final List<ParameterWriteRun> runs;

  /// A parameter write whose algorithm code differs from the previous
  /// parameter write, with every non-parameter message in between: the
  /// prime candidates for a model-selection message.
  final List<CodeChange> codeChanges;
  final List<NameCandidate> nameCandidates;
  final int messageCount;

  /// Explicit model-selection messages (`12 10 SS 00 01`) in time order.
  final List<ModelSelectionEvent> modelSelections;

  /// Preset-level scalar metadata messages (`12 11 00 00 NN`, 18 bytes).
  final List<MetadataEvent> metadata;

  /// 3-byte MIDI control changes in time order.
  final List<ControlChangeEvent> controlChanges;

  /// Messages grouped into bursts separated by idle gaps.
  final List<CaptureBurst> bursts;
}

class ModelSelectionEvent {
  const ModelSelectionEvent(this.timestampMs, this.slot, this.code, this.models);
  final double timestampMs;
  final int slot;
  final int code;
  final List<CatalogModel> models;
}

class MetadataEvent {
  const MetadataEvent(this.timestampMs, this.selector, this.value);
  final double timestampMs;
  final int selector;
  final int value;
}

class ControlChangeEvent {
  const ControlChangeEvent(this.timestampMs, this.status, this.controller, this.value);
  final double timestampMs;
  final int status;
  final int controller;
  final int value;
}

class CaptureBurst {
  const CaptureBurst({
    required this.startMs,
    required this.endMs,
    required this.count,
    required this.summary,
  });
  final double startMs;
  final double endMs;
  final int count;

  /// e.g. `select slot=1; param slot=1 x83`.
  final String summary;
}

class CodeChange {
  const CodeChange({
    required this.slot,
    required this.fromCode,
    required this.toCode,
    required this.atMs,
    required this.betweenClusters,
  });
  final int slot;
  final int fromCode;
  final int toCode;
  final double atMs;
  final List<String> betweenClusters;
}

class NameCandidate {
  const NameCandidate(this.clusterKey, this.text, this.timestampMs);
  final String clusterKey;
  final String text;
  final double timestampMs;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

bool _isQme2(List<int> bytes) =>
    bytes.length > 13 &&
    [for (var i = 0; i < _qme2Prefix.length; i++) bytes[i] == _qme2Prefix[i]]
        .every((ok) => ok);

bool _isSlotMessage(List<int> b, int length, int kind) =>
    b.length == length &&
    _isQme2(b) &&
    b.last == 0xf7 &&
    b[8] == 0x12 &&
    b[9] == 0x10 &&
    b[10] >= 1 &&
    b[10] <= 9 &&
    b[11] == 0x00 &&
    b[12] == kind;

bool _isParameterWrite(List<int> b) => _isSlotMessage(b, 34, 2);

bool _isModelSelection(List<int> b) => _isSlotMessage(b, 22, 1);

int? _nibbleUint32(List<int> b, int offset) {
  final raw = Uint8List(4);
  for (var i = 0; i < 4; i++) {
    final high = b[offset + i * 2];
    final low = b[offset + i * 2 + 1];
    if (high > 15 || low > 15) return null;
    raw[i] = (high << 4) | low;
  }
  return ByteData.sublistView(raw).getUint32(0, Endian.little);
}

/// Model selection: chain slot plus the algorithm code (nibble-paired u32 LE
/// at offset 13).
({int slot, int code})? decodeModelSelection(List<int> b) {
  if (!_isModelSelection(b)) return null;
  final code = _nibbleUint32(b, 13);
  return code == null ? null : (slot: b[10], code: code);
}

/// Preset metadata scalar (`12 11 00 00 NN`, 18 bytes): selector NN plus a
/// nibble-paired u16 LE (e.g. Preset VOL, BPM, type).
({int selector, int value})? decodePresetMetadataScalar(List<int> b) {
  if (b.length != 18 || !_isQme2(b) || b.last != 0xf7 || b[8] != 0x12 || b[9] != 0x11) {
    return null;
  }
  final values = [for (var i = 0; i < 2; i++) (b[13 + i * 2] << 4) | b[14 + i * 2]];
  if (b.sublist(13, 17).any((n) => n > 15)) return null;
  return (selector: b[12], value: values[0] | (values[1] << 8));
}

/// Printable-ASCII run of at least [minimum] characters (name detection).
String? _asciiRun(List<int> bytes, {int minimum = 4}) {
  final buffer = StringBuffer();
  String? best;
  for (final byte in bytes.skip(8)) {
    if (byte >= 0x20 && byte < 0x7f) {
      buffer.writeCharCode(byte);
    } else {
      if (buffer.length >= minimum && (best == null || buffer.length > best.length)) {
        best = buffer.toString();
      }
      buffer.clear();
    }
  }
  if (buffer.length >= minimum && (best == null || buffer.length > best.length)) {
    best = buffer.toString();
  }
  return best;
}

/// The known 34-byte parameter payload: algorithm u32 LE, index u16 LE,
/// float32 LE, all nibble-paired from offset 13.
({int slot, int code, int index, double value})? decodeParameterWrite(List<int> b) {
  if (!_isParameterWrite(b)) return null;
  final raw = Uint8List(10);
  for (var i = 0; i < 10; i++) {
    final high = b[13 + i * 2];
    final low = b[14 + i * 2];
    if (high > 15 || low > 15) return null;
    raw[i] = (high << 4) | low;
  }
  final data = ByteData.sublistView(raw);
  final value = data.getFloat32(6, Endian.little);
  if (!value.isFinite) return null;
  return (
    slot: b[10],
    code: data.getUint32(0, Endian.little),
    index: data.getUint16(4, Endian.little),
    value: value,
  );
}

bool _isControlChange(List<int> b) =>
    b.length == 3 && b[0] >= 0xb0 && b[0] <= 0xbf && b[1] < 0x80 && b[2] < 0x80;

CaptureFamily _familyFor(List<int> b) {
  if (_isControlChange(b)) return CaptureFamily.midiControlChange;
  if (!_isQme2(b)) return CaptureFamily.nonQme2;
  if (_isParameterWrite(b)) return CaptureFamily.parameterWrite;
  if (_isModelSelection(b)) return CaptureFamily.modelSelection;
  final header = _hex(b.sublist(8, 10));
  if (header == '12 11') return CaptureFamily.presetMetadata;
  if (header == '12 12') return CaptureFamily.commitCandidate;
  if (b.length == 22) return CaptureFamily.presetSelectionCandidate;
  if (_asciiRun(b) != null) return CaptureFamily.nameCandidate;
  return CaptureFamily.unknownQme2;
}

String _clusterKey(List<int> b) {
  if (_isControlChange(b)) {
    return 'cc status=${b[0].toRadixString(16)} controller=${b[1].toRadixString(16)}';
  }
  if (!_isQme2(b)) return 'RAW len=${b.length} first=${_hex(b.take(4).toList())}';
  // Slot-addressed families cluster per chain slot; parameter writes also by
  // algorithm class byte (high byte of the code).
  if (_isParameterWrite(b)) {
    final decoded = decodeParameterWrite(b);
    final cls = decoded == null ? '??' : (decoded.code >>> 24).toRadixString(16).padLeft(2, '0');
    return 'param slot=${b[10]} class=$cls';
  }
  if (_isModelSelection(b)) return 'select slot=${b[10]}';
  return 'qme2 len=${b.length} hdr=${_hex(b.sublist(8, 13))}';
}

CaptureReport classifyCapture(
  List<CaptureMessage> all, {
  List<CatalogModel> catalog = const [],
}) {
  final messages = all.where((m) => m.direction == 'hostToDevice').toList()
    ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
  final clusters = <String, CaptureCluster>{};
  for (final m in messages) {
    final key = _clusterKey(m.bytes);
    clusters.putIfAbsent(key, () => CaptureCluster(key: key, family: _familyFor(m.bytes))).messages.add(m);
  }

  final runs = <ParameterWriteRun>[];
  final changes = <CodeChange>[];
  final names = <NameCandidate>[];
  final selections = <ModelSelectionEvent>[];
  final metadata = <MetadataEvent>[];
  final controls = <ControlChangeEvent>[];
  final lastCodeBySlot = <int, int>{};
  final sinceBySlot = <int, List<String>>{};
  for (final m in messages) {
    final key = _clusterKey(m.bytes);
    final selection = decodeModelSelection(m.bytes);
    if (selection != null) {
      selections.add(
        ModelSelectionEvent(
          m.timestampMs,
          selection.slot,
          selection.code,
          [for (final c in catalog) if (c.code == selection.code) c],
        ),
      );
    }
    final scalar = decodePresetMetadataScalar(m.bytes);
    if (scalar != null) {
      metadata.add(MetadataEvent(m.timestampMs, scalar.selector, scalar.value));
    }
    if (_isControlChange(m.bytes)) {
      controls.add(ControlChangeEvent(m.timestampMs, m.bytes[0], m.bytes[1], m.bytes[2]));
    }
    final decoded = decodeParameterWrite(m.bytes);
    if (decoded == null) {
      for (final list in sinceBySlot.values) {
        list.add(key);
      }
      final name = _asciiRun(m.bytes);
      if (name != null && _isQme2(m.bytes)) {
        names.add(NameCandidate(key, name, m.timestampMs));
      }
      continue;
    }
    final lastCode = lastCodeBySlot[decoded.slot];
    if (lastCode != null && decoded.code != lastCode) {
      changes.add(
        CodeChange(
          slot: decoded.slot,
          fromCode: lastCode,
          toCode: decoded.code,
          atMs: m.timestampMs,
          betweenClusters: List.of(sinceBySlot[decoded.slot] ?? const []),
        ),
      );
    }
    lastCodeBySlot[decoded.slot] = decoded.code;
    sinceBySlot[decoded.slot] = <String>[];
    if (runs.isEmpty ||
        runs.last.slot != decoded.slot ||
        runs.last.algorithmCode != decoded.code ||
        runs.last.parameterIndex != decoded.index) {
      runs.add(
        ParameterWriteRun(
          slot: decoded.slot,
          algorithmCode: decoded.code,
          parameterIndex: decoded.index,
          models: [for (final c in catalog) if (c.code == decoded.code) c],
        )..firstMs = m.timestampMs,
      );
    }
    runs.last
      ..values.add(decoded.value)
      ..lastMs = m.timestampMs;
  }

  return CaptureReport(
    clusters: clusters.values.toList(),
    runs: runs,
    codeChanges: changes,
    nameCandidates: names,
    messageCount: messages.length,
    modelSelections: selections,
    metadata: metadata,
    controlChanges: controls,
    bursts: groupBursts(messages),
  );
}

/// Groups time-ordered messages into bursts separated by idle gaps longer
/// than [gapMs] (the pauses between editor actions).
List<CaptureBurst> groupBursts(List<CaptureMessage> messages, {double gapMs = 2000}) {
  final bursts = <CaptureBurst>[];
  var current = <CaptureMessage>[];
  void flush() {
    if (current.isEmpty) return;
    final counts = <String, int>{};
    for (final m in current) {
      counts.update(_clusterKey(m.bytes), (n) => n + 1, ifAbsent: () => 1);
    }
    bursts.add(
      CaptureBurst(
        startMs: current.first.timestampMs,
        endMs: current.last.timestampMs,
        count: current.length,
        summary: [
          for (final e in counts.entries) e.value == 1 ? e.key : '${e.key} x${e.value}',
        ].join('; '),
      ),
    );
    current = <CaptureMessage>[];
  }

  for (final m in messages) {
    if (current.isNotEmpty && m.timestampMs - current.last.timestampMs > gapMs) flush();
    current.add(m);
  }
  flush();
  return bursts;
}

enum ReferenceMatch { exactMatch, structuralMatch, noMatch }

class ReferenceFamily {
  const ReferenceFamily({
    required this.id,
    required this.source,
    required this.length,
    required this.headerHex,
  });

  factory ReferenceFamily.fromJson(Map<String, Object?> json) => ReferenceFamily(
    id: json['id'] as String,
    source: json['source'] as String,
    length: json['length'] as int,
    headerHex: json['headerHex'] as String,
  );

  final String id;
  final String source;
  final int length;

  /// Space-separated lowercase hex of the leading bytes that define the family.
  final String headerHex;
}

/// MATRIBOX_II_PRO_REFERENCE comparison hint for one cluster: EXACT when
/// length and the reference header prefix are identical, STRUCTURAL when
/// only the length matches or the header shares its first bytes, else NO
/// MATCH. Never a Matribox 1 confirmation.
({ReferenceMatch match, ReferenceFamily? reference}) crossCorrelate(
  CaptureCluster cluster,
  List<ReferenceFamily> references,
) {
  final sample = cluster.messages.first.bytes;
  ReferenceFamily? structural;
  for (final ref in references) {
    final refBytes = [
      for (final t in ref.headerHex.split(' ')) if (t.isNotEmpty) int.parse(t, radix: 16),
    ];
    final prefixEqual = refBytes.length <= sample.length &&
        [for (var i = 0; i < refBytes.length; i++) sample[i] == refBytes[i]].every((ok) => ok);
    if (prefixEqual && ref.length == sample.length) {
      return (match: ReferenceMatch.exactMatch, reference: ref);
    }
    final sharedPrefix = () {
      var n = 0;
      while (n < refBytes.length && n < sample.length && sample[n] == refBytes[n]) {
        n++;
      }
      return n;
    }();
    if (ref.length == sample.length || sharedPrefix >= 8) structural ??= ref;
  }
  return structural == null
      ? (match: ReferenceMatch.noMatch, reference: null)
      : (match: ReferenceMatch.structuralMatch, reference: structural);
}

/// Contiguous changed raw-byte range between two independently read raw
/// presets (BEFORE / AFTER of the ground-truth triple). Purely descriptive:
/// no classification beyond position.
class RawChangeRange {
  const RawChangeRange(this.partIndex, this.start, this.endExclusive);
  final int partIndex;
  final int start;
  final int endExclusive;
  int get length => endExclusive - start;
  @override
  String toString() => 'part $partIndex [$start, $endExclusive)';
}

List<RawChangeRange> rawChangeRanges(
  List<List<int>> before,
  List<List<int>> after,
) {
  final ranges = <RawChangeRange>[];
  for (var part = 0; part < before.length && part < after.length; part++) {
    final b = before[part];
    final a = after[part];
    final length = b.length < a.length ? b.length : a.length;
    int? start;
    for (var i = 0; i <= length; i++) {
      final changed = i < length && b[i] != a[i];
      if (changed) {
        start ??= i;
      } else if (start != null) {
        ranges.add(RawChangeRange(part, start, i));
        start = null;
      }
    }
    if (b.length != a.length) {
      ranges.add(RawChangeRange(part, length, b.length > a.length ? b.length : a.length));
    }
  }
  return ranges;
}
