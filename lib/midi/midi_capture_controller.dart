import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'midi_parser.dart';
import 'midi_receive_source.dart';

enum MidiCaptureState {
  disconnected,
  deviceDetected,
  deviceOpened,
  monitoring,
  stopping,
  error,
}

class MidiCaptureEntry {
  MidiCaptureEntry({
    required this.sequence,
    required this.at,
    required this.kind,
    required this.type,
    required this.status,
    this.bytes = const [],
    this.androidTimestampNanos,
    this.marker,
  });
  final int sequence;
  final DateTime at;
  final String kind;
  final String type;
  final String status;
  final List<int> bytes;
  final int? androidTimestampNanos;
  final String? marker;
  String get hex => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');
  Map<String, Object?> toJson() => {
    'sequence': sequence,
    'localTimestamp': at.toLocal().toIso8601String(),
    'kind': kind,
    'type': type,
    'status': status,
    'length': bytes.length,
    'hex': hex,
    if (androidTimestampNanos != null)
      'androidTimestampNanos': androidTimestampNanos,
    if (marker != null) 'marker': marker,
  };
}

class MidiCaptureController extends ChangeNotifier {
  MidiCaptureController(
    this._source, {
    DateTime Function()? clock,
    this.maxEntries = 300,
    this.maxRetainedBytes = 262144,
    MidiParser? parser,
    void Function(String)? debugLogSink,
  }) : _clock = clock ?? DateTime.now,
       _debugLogSink = debugLogSink ?? debugPrintSynchronously,
       _parser = parser ?? MidiParser() {
    _chunks = _source.receivedChunks.listen(_receive);
    _interruptions = _source.interruptions.listen((_) {
      interrupt();
    });
  }
  final MidiReceiveSource _source;
  final DateTime Function() _clock;
  final MidiParser _parser;
  final void Function(String) _debugLogSink;
  bool debugLogging = false;
  int debugLogDropped = 0;
  int _debugWindow = -1;
  int _debugLines = 0;

  void setDebugLogging(bool enabled) {
    if (_disposed) return;
    debugLogging =
        kDebugMode && enabled && state == MidiCaptureState.monitoring;
    _debugWindow = -1;
    _debugLines = 0;
    debugLogDropped = 0;
    notifyListeners();
  }

  void _debugEntry(MidiCaptureEntry entry) {
    if (!kDebugMode || !debugLogging || entry.kind == 'chunk') return;
    final window = _elapsed.elapsedMilliseconds ~/ 1000;
    if (window != _debugWindow) {
      _debugWindow = window;
      _debugLines = 0;
    }
    if (_debugLines++ >= 20) {
      debugLogDropped++;
      return;
    }
    final hex = entry.bytes
        .take(256)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
    _debugLogSink(
      'WYRMTONE_RX ${jsonEncode({'receiveOnly': true, 'sequence': entry.sequence, 'at': entry.at.toLocal().toIso8601String(), 'kind': entry.kind, 'type': entry.type, 'status': entry.status, 'length': entry.bytes.length, 'hex': hex, 'truncated': entry.bytes.length > 256, 'suppressedTotal': debugLogDropped, if (entry.marker != null) 'marker': entry.marker})}',
    );
  }

  final int maxEntries;
  final int maxRetainedBytes;
  final _entries = ListQueue<MidiCaptureEntry>();
  final _elapsed = Stopwatch()..start();
  StreamSubscription<ReceivedMidiChunk>? _chunks;
  StreamSubscription<String>? _interruptions;
  Timer? _notifyTimer;
  Timer? _timeoutTimer;
  bool _disposed = false;
  bool _opened = false;
  int _generation = 0;
  int _sequence = 0;
  int retainedBytes = 0;
  int droppedEntries = 0;
  int droppedChunks = 0;
  int chunkCount = 0;
  int byteCount = 0;
  int messageCount = 0;
  int get pendingMessageCount => _parser.incompletePending ? 1 : 0;
  int completeSysExCount = 0;
  int incompleteCount = 0;
  int? outputPort;
  String? deviceName;
  String? error;
  String? _marker;
  DateTime? _markerAt;
  DateTime? startedAt;
  MidiCaptureState state = MidiCaptureState.disconnected;
  List<MidiCaptureEntry> get entries => List.unmodifiable(_entries);
  void updateConnection({
    required bool detected,
    required bool opened,
    String? name,
  }) {
    deviceName = name;
    _opened = opened;
    if (!opened &&
        (state == MidiCaptureState.monitoring ||
            state == MidiCaptureState.stopping)) {
      interrupt();
    } else if (state != MidiCaptureState.monitoring &&
        state != MidiCaptureState.stopping) {
      state = opened
          ? MidiCaptureState.deviceOpened
          : detected
          ? MidiCaptureState.deviceDetected
          : MidiCaptureState.disconnected;
    }
    _scheduleNotify();
  }

  Future<void> start() async {
    if (!_opened || state != MidiCaptureState.deviceOpened) return;
    final generation = ++_generation;
    state = MidiCaptureState.monitoring;
    error = null;
    startedAt ??= _clock();
    notifyListeners();
    try {
      final port = await _source.start();
      if (_disposed || generation != _generation || !_opened) {
        await _source.stop();
        return;
      }
      outputPort = port;
      _timeoutTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        for (final message in _parser.expire(_elapsed.elapsedMilliseconds)) {
          _message(message, _clock(), null);
        }
      });
    } catch (_) {
      if (!_disposed && generation == _generation) {
        state = MidiCaptureState.error;
        error = 'Passive Beobachtung konnte nicht gestartet werden.';
      }
    }
    _scheduleNotify();
  }

  Future<void> stop() async {
    if (state != MidiCaptureState.monitoring &&
        state != MidiCaptureState.error) {
      return;
    }
    ++_generation;
    state = MidiCaptureState.stopping;
    debugLogging = false;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    if (!_disposed) notifyListeners();
    for (final message in _parser.finish()) {
      _message(message, _clock(), null);
    }
    try {
      await _source.stop();
    } catch (_) {
      error = 'Empfang unterbrochen; native Ressourcen werden geschlossen.';
    }
    outputPort = null;
    state = _opened
        ? MidiCaptureState.deviceOpened
        : MidiCaptureState.disconnected;
    _scheduleNotify();
  }

  Future<void> interrupt() async {
    _opened = false;
    await stop();
    if (!_disposed) {
      state = MidiCaptureState.disconnected;
      outputPort = null;
      _scheduleNotify();
    }
  }

  void _receive(ReceivedMidiChunk chunk) {
    if (state != MidiCaptureState.monitoring || _disposed) return;
    droppedChunks += chunk.dropped;
    if (chunk.dropped > 0) {
      for (final message in _parser.finish()) {
        _message(message, _clock(), null);
      }
      _add(
        kind: 'loss',
        type: 'Empfangslücke',
        status: '${chunk.dropped} Chunks verworfen',
        at: _clock(),
      );
    }
    if (chunk.bytes.isEmpty) return;
    if (chunk.bytes.length > 16384) {
      droppedChunks++;
      _scheduleNotify();
      return;
    }
    final at = chunk.receivedAt ?? _clock();
    final hadSysEx = _parser.sysExPending || chunk.bytes.contains(0xF0);
    chunkCount++;
    byteCount += chunk.bytes.length;
    final messages = _parser.feed(chunk.bytes, _elapsed.elapsedMilliseconds);
    _add(
      kind: 'chunk',
      type: hadSysEx
          ? 'SysEx-Chunk'
          : messages.isEmpty
          ? 'unbekannt/unvollständig'
          : messages.map((m) => m.type).toSet().join(' / '),
      status: _parser.incompletePending ? 'unvollständig' : 'verarbeitet',
      at: at,
      bytes: List.of(chunk.bytes),
      timestamp: chunk.timestampNanos,
    );
    for (final message in messages) {
      _message(message, at, chunk.timestampNanos);
    }
  }

  void _message(ParsedMidiMessage message, DateTime at, int? timestamp) {
    messageCount++;
    if (message.type == 'SysEx' && message.status == 'vollständig') {
      completeSysExCount++;
    }
    if (message.status != 'vollständig') incompleteCount++;
    _add(
      kind: 'message',
      type: message.type,
      status: message.status,
      at: at,
      bytes: message.bytes,
      timestamp: timestamp,
    );
  }

  static String sanitizeMarker(String text) {
    final clean = text
        .replaceAll(
          RegExp(r'[\x00-\x1F\x7F-\x9F\u202A-\u202E\u2066-\u2069]'),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (RegExp(
      r'(/(?:dev|data|storage|sdcard|Users|home)/|(?:file|content)://|[a-zA-Z]:[\\/]|t3k_|bearer\s|oauth|access_token|refresh_token|client_secret)',
      caseSensitive: false,
    ).hasMatch(clean)) {
      return 'Sensible Markierung entfernt';
    }
    return String.fromCharCodes(clean.runes.take(120));
  }

  void addMarker(String text) {
    final clean = sanitizeMarker(text);
    if (clean.isEmpty) return;
    _marker = clean;
    _markerAt = _clock();
    _add(kind: 'marker', type: 'MARKER', status: 'lokal', at: _markerAt!);
  }

  void _add({
    required String kind,
    required String type,
    required String status,
    required DateTime at,
    List<int> bytes = const [],
    int? timestamp,
  }) {
    final entry = MidiCaptureEntry(
      sequence: ++_sequence,
      at: at,
      kind: kind,
      type: type,
      status: status,
      bytes: List.unmodifiable(bytes),
      androidTimestampNanos: timestamp,
      marker: _markerAt == null || !at.isBefore(_markerAt!)
          ? _marker
          : _entries
                .where((e) => e.kind == 'marker' && !e.at.isAfter(at))
                .lastOrNull
                ?.marker,
    );
    _entries.add(entry);
    _debugEntry(entry);
    retainedBytes += entry.bytes.length;
    while (_entries.length > maxEntries || retainedBytes > maxRetainedBytes) {
      retainedBytes -= _entries.removeFirst().bytes.length;
      droppedEntries++;
    }
    _scheduleNotify();
  }

  void clear() {
    _parser.finish();
    _entries.clear();
    retainedBytes = 0;
    droppedEntries = 0;
    droppedChunks = 0;
    chunkCount = 0;
    byteCount = 0;
    messageCount = 0;
    completeSysExCount = 0;
    incompleteCount = 0;
    _marker = null;
    _markerAt = null;
    // Sequence remains monotonic even after clearing.
    _scheduleNotify();
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'schemaVersion': 1,
    'app': 'WyrmTone',
    'device': {
      'type': 'sonicakeMatriboxOne',
      'vendorId': '0x84EF',
      'productId': '0x0054',
      'manufacturer': 'SONICAKE AUDIO',
      'product': 'SONICAKE MatriBox PRODUCT',
    },
    'session': {
      'startedAt': startedAt?.toLocal().toIso8601String(),
      'receiveOnly': true,
      'chunkCount': chunkCount,
      'byteCount': byteCount,
      'messageCount': messageCount,
      'pendingMessageCount': pendingMessageCount,
      'completeSysExCount': completeSysExCount,
      'incompleteCount': incompleteCount,
      'droppedEntries': droppedEntries,
      'droppedChunks': droppedChunks,
      'messages': _entries.map((e) => e.toJson()).toList(),
    },
  });
  void _scheduleNotify() {
    if (_disposed || _notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: 100), () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _notifyTimer?.cancel();
    _timeoutTimer?.cancel();
    _chunks?.cancel();
    _interruptions?.cancel();
    if (state == MidiCaptureState.monitoring ||
        state == MidiCaptureState.stopping) {
      _source.stop().catchError((Object _) {});
    }
    super.dispose();
  }
}
