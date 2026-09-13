import 'dart:async';

import 'package:flutter/services.dart';

class ReceivedMidiChunk {
  ReceivedMidiChunk(
    this.bytes, {
    this.timestampNanos,
    this.receivedAt,
    this.dropped = 0,
  });
  final Uint8List bytes;
  final int? timestampNanos;
  final DateTime? receivedAt;
  final int dropped;
}

/// The domain monitor knows reception only, never a device-write interface.
abstract interface class MidiReceiveSource {
  Stream<ReceivedMidiChunk> get receivedChunks;
  Stream<String> get interruptions;
  Future<int> start();
  Future<void> stop();
}

class MethodChannelMidiReceiveSource implements MidiReceiveSource {
  final _methods = const MethodChannel('de.neevel.wyrmtone/usb_methods');
  final _events = const EventChannel('de.neevel.wyrmtone/midi_capture_events');
  final _chunks = StreamController<ReceivedMidiChunk>.broadcast();
  final _interruptions = StreamController<String>.broadcast();
  StreamSubscription<Object?>? _subscription;
  @override
  Stream<ReceivedMidiChunk> get receivedChunks => _chunks.stream;
  @override
  Stream<String> get interruptions => _interruptions.stream;
  @override
  Future<int> start() async {
    _subscription ??= _events.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      if (event['type'] == 'stopped') {
        _interruptions.add('Native Beobachtung beendet');
        return;
      }
      final lost = event['dropped'] as int? ?? 0;
      if (lost > 0) _chunks.add(ReceivedMidiChunk(Uint8List(0), dropped: lost));
      for (final chunk in event['chunks'] as List? ?? const []) {
        if (chunk is! Map || chunk['bytes'] is! Uint8List) continue;
        _chunks.add(
          ReceivedMidiChunk(
            chunk['bytes'] as Uint8List,
            timestampNanos: chunk['timestampNanos'] as int?,
            receivedAt: DateTime.fromMillisecondsSinceEpoch(
              chunk['receivedAtMillis'] as int,
            ),
          ),
        );
      }
    }, onError: (Object _) => _interruptions.add('Empfangskanal unterbrochen'));
    try {
      return await _methods.invokeMethod<int>('startMidiCapture') ?? 0;
    } catch (_) {
      await _subscription?.cancel();
      _subscription = null;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _methods.invokeMethod<void>('stopMidiCapture');
    } finally {
      await _subscription?.cancel();
      _subscription = null;
    }
  }
}

abstract interface class MidiCaptureExporter {
  Future<bool> exportJson(String json);
}

class AndroidMidiCaptureExporter implements MidiCaptureExporter {
  @override
  Future<bool> exportJson(String json) async =>
      await const MethodChannel('de.neevel.wyrmtone/midi_capture_export')
          .invokeMethod<bool>('exportJson', {'json': json}) ??
      false;
}
