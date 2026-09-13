import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/midi/midi_capture_controller.dart';
import 'package:wyrmtone/midi/midi_parser.dart';
import 'package:wyrmtone/midi/midi_receive_source.dart';

import 'support/fake_midi_receive_source.dart';

void main() {
  test(
    'debug RX logging is opt-in, bounded and disabled by interruption',
    () async {
      final source = FakeMidiReceiveSource();
      final lines = <String>[];
      final c = MidiCaptureController(source, debugLogSink: lines.add);
      c.updateConnection(detected: true, opened: true);
      await c.start();
      source.receive([0xF0, 1, 0xF7]);
      expect(lines, isEmpty);
      c.setDebugLogging(true);
      c.addMarker('Gain\n40 → 41');
      source.receive([0xF0, ...List.filled(300, 1), 0xF7]);
      final payload =
          jsonDecode(lines.last.substring('WYRMTONE_RX '.length)) as Map;
      expect(payload['receiveOnly'], true);
      expect(payload['truncated'], true);
      expect((payload['hex'] as String).split(' '), hasLength(256));
      expect(payload['marker'], 'Gain 40 → 41');
      for (var i = 0; i < 30; i++) {
        source.receive([0xF0, 1, 0xF7]);
      }
      expect(lines, hasLength(20));
      expect(c.debugLogDropped, 12);
      expect(c.completeSysExCount, 32);
      await c.interrupt();
      expect(c.debugLogging, false);
      final count = lines.length;
      source.receive([0xF0, 1, 0xF7]);
      expect(lines.length, count);
      c.dispose();
      await source.dispose();
    },
  );
  group('receive-only MIDI parser', () {
    final cases = <int, String>{
      0x80: 'Note Off',
      0x90: 'Note On',
      0xA0: 'Polyphonic Aftertouch',
      0xB0: 'Control Change',
      0xC0: 'Program Change',
      0xD0: 'Channel Pressure',
      0xE0: 'Pitch Bend',
    };
    for (final entry in cases.entries) {
      test('classifies ${entry.value}', () {
        final bytes = [
          entry.key,
          1,
          if (entry.key != 0xC0 && entry.key != 0xD0) 2,
        ];
        expect(MidiParser().feed(bytes, 0).single.type, entry.value);
      });
    }
    test('System Common and Real-Time', () {
      final result = MidiParser().feed([0xF2, 1, 2, 0xF8], 0);
      expect(result.map((m) => m.type), ['System Common', 'System Real-Time']);
    });
    test('normal message fragmented across callbacks and running status', () {
      final p = MidiParser();
      expect(p.feed([0xB0, 7], 0), isEmpty);
      expect(p.feed([20, 7, 21], 1).map((m) => m.bytes), [
        [0xB0, 7, 20],
        [0xB0, 7, 21],
      ]);
    });
    test('complete SysEx in one chunk', () {
      final message = MidiParser().feed([0xF0, 1, 2, 0xF7], 0).single;
      expect(message.type, 'SysEx');
      expect(message.status, 'vollständig');
    });
    test('SysEx fragments in order', () {
      final p = MidiParser();
      expect(p.feed([0xF0, 1], 0), isEmpty);
      expect(p.sysExPending, isTrue);
      expect(p.feed([2], 10), isEmpty);
      expect(p.feed([3, 0xF7], 20).single.bytes, [0xF0, 1, 2, 3, 0xF7]);
    });
    test('multiple SysEx in one chunk', () {
      expect(MidiParser().feed([0xF0, 1, 0xF7, 0xF0, 2, 0xF7], 0).length, 2);
    });
    test('Real-Time interleaved with SysEx is not assembled into SysEx', () {
      final messages = MidiParser().feed([0xF0, 1, 0xF8, 2, 0xFA, 0xF7], 0);
      expect(messages.map((m) => m.type), [
        'System Real-Time',
        'System Real-Time',
        'SysEx',
      ]);
      expect(messages.last.bytes, [0xF0, 1, 2, 0xF7]);
    });
    test('incomplete SysEx visible on stop', () {
      final p = MidiParser()..feed([0xF0, 1], 0);
      expect(p.finish().single.status, contains('unvollständig'));
      expect(p.bufferedBytes, 0);
    });
    test('SysEx timeout ignores abandoned tail', () {
      final p = MidiParser(timeoutMillis: 10)..feed([0xF0, 1], 0);
      expect(p.expire(9), isEmpty);
      expect(p.expire(10).single.status, contains('Timeout'));
      expect(p.feed([2, 0xF7], 11), isEmpty);
      expect(p.feed([0xF0, 3, 0xF7], 12).single.status, 'vollständig');
    });
    test('maximum SysEx buffer size', () {
      final p = MidiParser(maxSysExBytes: 4);
      final result = p.feed([0xF0, 1, 2, 3, 4, 5, 0xF7], 0);
      expect(result.single.status, contains('Größenlimit'));
      expect(result.single.bytes.length, 4);
      expect(p.bufferedBytes, 0);
    });
    test('new status aborts SysEx without inventing semantics', () {
      final result = MidiParser().feed([0xF0, 1, 0xB0, 7, 3], 0);
      expect(result.first.status, contains('neuer Status'));
      expect(result.last.type, 'Control Change');
    });
    test('orphan bytes and pending MIDI classified incomplete', () {
      final p = MidiParser();
      expect(p.feed([1], 0).single.type, 'unbekannt/unvollständig');
      p.feed([0x90, 1], 1);
      expect(p.finish().single.status, contains('unvollständig'));
    });
  });
  group('passive capture domain', () {
    late FakeMidiReceiveSource source;
    late MidiCaptureController capture;
    setUp(() {
      source = FakeMidiReceiveSource();
      capture = MidiCaptureController(
        source,
        clock: () => DateTime.utc(2026, 9, 12),
      );
    });
    tearDown(() async {
      capture.dispose();
      await source.dispose();
    });
    void opened() => capture.updateConnection(
      detected: true,
      opened: true,
      name: 'Matribox',
    );
    test('no automatic start, start needs opened device', () async {
      capture.updateConnection(detected: true, opened: false);
      await capture.start();
      expect(source.starts, 0);
      opened();
      expect(source.starts, 0);
      await capture.start();
      expect(source.starts, 1);
      expect(capture.outputPort, 0);
    });
    test('duplicate start prevented, start stop and late RX ignored', () async {
      opened();
      await Future.wait([capture.start(), capture.start()]);
      expect(source.starts, 1);
      source.receive([0xB0, 7, 1]);
      expect(capture.chunkCount, 1);
      await capture.stop();
      expect(source.stops, 1);
      expect(capture.state, MidiCaptureState.deviceOpened);
      source.receive([0xB0, 7, 2]);
      expect(capture.chunkCount, 1);
    });
    test('stop without start and repeated stop safe', () async {
      await capture.stop();
      await capture.stop();
      expect(source.stops, 0);
    });
    test('detach or removed MIDI device interrupts reception', () async {
      opened();
      await capture.start();
      capture.updateConnection(detected: false, opened: false);
      await Future<void>.microtask(() {});
      expect(source.active, isFalse);
      expect(capture.state, MidiCaptureState.disconnected);
      source.receive([0xF8]);
      expect(capture.chunkCount, 0);
    });
    test('native lifecycle interruption stops source', () async {
      opened();
      await capture.start();
      source.interrupted.add('appPause');
      await Future<void>.microtask(() {});
      expect(source.active, isFalse);
      expect(capture.state, MidiCaptureState.disconnected);
    });
    test('chunks and assembled SysEx separated and timestamped', () async {
      opened();
      await capture.start();
      source.receive([0xF0, 1]);
      source.receive([2, 0xF7]);
      expect(capture.entries.where((e) => e.kind == 'chunk').length, 2);
      expect(capture.entries.last.bytes, [0xF0, 1, 2, 0xF7]);
      expect(capture.completeSysExCount, 1);
      expect(capture.byteCount, 4);
      expect(capture.entries.last.androidTimestampNanos, 1234);
    });
    test('ring buffer count and byte limits preserve order', () async {
      capture.dispose();
      capture = MidiCaptureController(
        source,
        maxEntries: 4,
        maxRetainedBytes: 9,
      );
      opened();
      await capture.start();
      for (var i = 0; i < 10; i++) {
        source.receive([0xB0, 7, i]);
      }
      expect(capture.entries.length, lessThanOrEqualTo(4));
      expect(capture.retainedBytes, lessThanOrEqualTo(9));
      expect(capture.droppedEntries, greaterThan(0));
      final seq = capture.entries.map((e) => e.sequence).toList();
      expect(seq, orderedEquals([...seq]..sort()));
      expect(capture.entries.last.bytes.last, 9);
    });
    test('gap invalidates SysEx assembler', () async {
      opened();
      await capture.start();
      source.receive([0xF0, 1]);
      source.chunks.add(ReceivedMidiChunk(Uint8List(0), dropped: 3));
      source.receive([2, 0xF7]);
      expect(capture.completeSysExCount, 0);
      expect(capture.droppedChunks, 3);
    });
    test('markers sanitize controls and attach to later RX', () async {
      opened();
      await capture.start();
      capture.addMarker(' Gain\n40\r→\u000041 ');
      source.receive([0xF8]);
      expect(capture.entries.last.marker, 'Gain 40 → 41');
      expect(MidiCaptureController.sanitizeMarker('x' * 300).length, 120);
      expect(
        MidiCaptureController.sanitizeMarker('t3k_secret'),
        'Sensible Markierung entfernt',
      );
    });
    test(
      'JSON export allowlist and receiveOnly flag, no device paths or serial',
      () async {
        capture.updateConnection(
          detected: true,
          opened: true,
          name: '/dev/bus/usb/private-serial',
        );
        await capture.start();
        capture.addMarker('Gain 40 → 41');
        source.receive([0xF8]);
        final text = capture.exportJson();
        final json = jsonDecode(text) as Map;
        expect(json['session']['receiveOnly'], true);
        expect(json['schemaVersion'], 1);
        for (final value in [
          '/dev/',
          'private-serial',
          'serialNumber',
          'token',
          'clientId',
          'uri',
        ]) {
          expect(text, isNot(contains(value)));
        }
      },
    );
    test(
      'clear releases retained payload but sequence remains monotonic',
      () async {
        opened();
        await capture.start();
        source.receive([0xF8]);
        final seq = capture.entries.last.sequence;
        capture.clear();
        expect(capture.retainedBytes, 0);
        expect(capture.entries, isEmpty);
        source.receive([0xF8]);
        expect(capture.entries.first.sequence, greaterThan(seq));
      },
    );
  });
}
