import 'dart:async';
import 'dart:typed_data';

import 'package:wyrmtone/midi/midi_receive_source.dart';

class FakeMidiReceiveSource implements MidiReceiveSource {
  final chunks = StreamController<ReceivedMidiChunk>.broadcast(sync: true);
  final interrupted = StreamController<String>.broadcast(sync: true);
  int starts = 0;
  int stops = 0;
  bool active = false;
  @override
  Stream<ReceivedMidiChunk> get receivedChunks => chunks.stream;
  @override
  Stream<String> get interruptions => interrupted.stream;
  @override
  Future<int> start() async {
    starts++;
    active = true;
    return 0;
  }

  @override
  Future<void> stop() async {
    stops++;
    active = false;
  }

  void receive(List<int> bytes) => chunks.add(
    ReceivedMidiChunk(Uint8List.fromList(bytes), timestampNanos: 1234),
  );
  Future<void> dispose() async {
    await chunks.close();
    await interrupted.close();
  }
}
