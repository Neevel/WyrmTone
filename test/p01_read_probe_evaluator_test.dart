import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/midi/p01_read_probe_evaluator.dart';

import 'support/matribox_p01_readback_fixtures.dart';

/// Splits a full plain-MIDI byte stream into several chunks, simulating how
/// Android's MidiReceiver.onSend may deliver a device's response across
/// more than one callback.
List<List<int>> _fragment(List<int> bytes, List<int> chunkSizes) {
  final chunks = <List<int>>[];
  var offset = 0;
  for (final size in chunkSizes) {
    final end = (offset + size).clamp(0, bytes.length);
    if (offset < end) chunks.add(bytes.sublist(offset, end));
    offset = end;
  }
  if (offset < bytes.length) chunks.add(bytes.sublist(offset));
  return chunks;
}

List<int> _fullCycleBytes() => [
  for (final part in matriboxP01RealCycle) ...matriboxHex(part),
];

void main() {
  group('READBACK_TIMEOUT', () {
    test('native failure is reported as timeout, not parse error', () {
      final verdict = evaluateP01ReadProbeResponse(
        nativeSuccess: false,
        chunks: const [],
      );
      expect(verdict.outcome, P01ReadProbeOutcome.timeout);
    });

    test('native success but zero bytes received is also a timeout', () {
      final verdict = evaluateP01ReadProbeResponse(
        nativeSuccess: true,
        chunks: const [],
      );
      expect(verdict.outcome, P01ReadProbeOutcome.timeout);
    });
  });

  group('READBACK_CONFIRMED', () {
    test('full real cycle, delivered as one chunk, is confirmed', () {
      final verdict = evaluateP01ReadProbeResponse(
        nativeSuccess: true,
        chunks: [_fullCycleBytes()],
      );
      expect(verdict.outcome, P01ReadProbeOutcome.confirmed);
      expect(verdict.decoded?.name, 'CKY 96 STUD');
      expect(verdict.decoded?.gain, 17);
    });

    test('full real cycle, fragmented across many small chunks, is confirmed', () {
      final bytes = _fullCycleBytes();
      final chunks = _fragment(bytes, List.filled(bytes.length, 3));
      final verdict = evaluateP01ReadProbeResponse(
        nativeSuccess: true,
        chunks: chunks,
      );
      expect(verdict.outcome, P01ReadProbeOutcome.confirmed);
    });
  });

  group('READBACK_RECEIVED_BUT_MISMATCH', () {
    test('a changed marker is reported, not treated as an invalid request', () {
      final verdict = evaluateP01ReadProbeResponse(
        nativeSuccess: true,
        chunks: [_fullCycleBytes()],
        expected: {...expectedMarkers, 'gain': 99},
      );
      expect(verdict.outcome, P01ReadProbeOutcome.receivedButMismatch);
      // The actually decoded value is still reported, not suppressed.
      expect(verdict.decoded?.gain, 17);
    });
  });

  group('READBACK_INCOMPLETE', () {
    test('only part 0 arrived: name known, markers unreachable', () {
      final verdict = evaluateP01ReadProbeResponse(
        nativeSuccess: true,
        chunks: [matriboxHex(matriboxP01Part0)],
      );
      expect(verdict.outcome, P01ReadProbeOutcome.incomplete);
    });

    test('a complete but differently-named cycle is also incomplete', () {
      final renamed = matriboxHex(matriboxP01Part0);
      renamed[21] = 0x00; // corrupt the 'C' of "CKY 96 STUD"
      final bytes = [
        ...renamed,
        for (final part in matriboxP01RealCycle.skip(1)) ...matriboxHex(part),
      ];
      final verdict = evaluateP01ReadProbeResponse(
        nativeSuccess: true,
        chunks: [bytes],
      );
      expect(verdict.outcome, P01ReadProbeOutcome.incomplete);
    });
  });

  group('READBACK_PARSE_ERROR', () {
    test('a truncated SysEx without F7 is a parse error, not a false pass', () {
      final bytes = matriboxHex(matriboxP01Part0);
      final truncated = bytes.sublist(0, bytes.length - 5); // drop the tail, no F7
      final verdict = evaluateP01ReadProbeResponse(
        nativeSuccess: true,
        chunks: [truncated],
      );
      expect(verdict.outcome, P01ReadProbeOutcome.parseError);
    });
  });
}
