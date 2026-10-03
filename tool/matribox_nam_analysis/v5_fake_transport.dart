/// V5A: a purely in-memory, simulated Matribox transport for dry-run
/// testing of [V5AckStateMachine] ONLY. Never opens a device, never
/// touches USB/MIDI. Not used anywhere in V5A outside tests, and not a
/// stand-in for a real transport (V5B, separately gated).
library;

import 'nam_transfer_codec.dart';
import 'v5_ack_state_machine.dart';

/// Scenario A: replies with the exact, correct ACK for every frame it is
/// sent -- the only scenario under which a full transfer should complete.
class V5FakeTransportAllOk implements V5Transport {
  @override
  Future<V5TransportResponse> sendFrame(List<int> frame) async {
    final req = NamTransferFrame.parse(frame);
    final ack = NamTransferAck(slot: req.slot, block: req.block, status: 0x01);
    return V5TransportResponse.received([ack.encode()]);
  }
}

/// Scenario B: never responds (simulated timeout) on the [failAtOrdinal]th
/// send (0-based); every prior frame gets a correct ACK.
class V5FakeTransportTimeout implements V5Transport {
  V5FakeTransportTimeout({required this.failAtOrdinal});
  final int failAtOrdinal;
  int _ordinal = 0;

  @override
  Future<V5TransportResponse> sendFrame(List<int> frame) async {
    final ordinal = _ordinal++;
    if (ordinal == failAtOrdinal) {
      return const V5TransportResponse.timeout();
    }
    final req = NamTransferFrame.parse(frame);
    final ack = NamTransferAck(slot: req.slot, block: req.block, status: 0x01);
    return V5TransportResponse.received([ack.encode()]);
  }
}

/// Scenario C: replies with a structurally broken (truncated) message on
/// the [failAtOrdinal]th send.
class V5FakeTransportMalformedAck implements V5Transport {
  V5FakeTransportMalformedAck({required this.failAtOrdinal});
  final int failAtOrdinal;
  int _ordinal = 0;

  @override
  Future<V5TransportResponse> sendFrame(List<int> frame) async {
    final ordinal = _ordinal++;
    if (ordinal == failAtOrdinal) {
      final req = NamTransferFrame.parse(frame);
      final ack = NamTransferAck(slot: req.slot, block: req.block, status: 0x01);
      final bytes = ack.encode();
      return V5TransportResponse.received([bytes.sublist(0, bytes.length - 3)]);
    }
    final req = NamTransferFrame.parse(frame);
    final ack = NamTransferAck(slot: req.slot, block: req.block, status: 0x01);
    return V5TransportResponse.received([ack.encode()]);
  }
}

/// Scenario D: ACKs a DIFFERENT clone slot (still well-formed otherwise)
/// on the [failAtOrdinal]th send.
class V5FakeTransportWrongSlot implements V5Transport {
  V5FakeTransportWrongSlot({required this.failAtOrdinal});
  final int failAtOrdinal;
  int _ordinal = 0;

  @override
  Future<V5TransportResponse> sendFrame(List<int> frame) async {
    final ordinal = _ordinal++;
    final req = NamTransferFrame.parse(frame);
    final wrongSlot = req.slot == 0x00 ? 0x01 : 0x00; // never 0x04 here
    final slot = ordinal == failAtOrdinal ? wrongSlot : req.slot;
    final ack = NamTransferAck(slot: slot, block: req.block, status: 0x01);
    return V5TransportResponse.received([ack.encode()]);
  }
}

/// Scenario E: ACKs the WRONG block number on the [failAtOrdinal]th send.
class V5FakeTransportWrongBlock implements V5Transport {
  V5FakeTransportWrongBlock({required this.failAtOrdinal});
  final int failAtOrdinal;
  int _ordinal = 0;

  @override
  Future<V5TransportResponse> sendFrame(List<int> frame) async {
    final ordinal = _ordinal++;
    final req = NamTransferFrame.parse(frame);
    final block = ordinal == failAtOrdinal ? (req.block + 1) % 588 : req.block;
    final ack = NamTransferAck(slot: req.slot, block: block, status: 0x01);
    return V5TransportResponse.received([ack.encode()]);
  }
}

/// Scenario F: ACKs with a non-success status byte on the
/// [failAtOrdinal]th send (only 0x01 was ever observed as success).
class V5FakeTransportNonSuccessStatus implements V5Transport {
  V5FakeTransportNonSuccessStatus({required this.failAtOrdinal, this.status = 0x00});
  final int failAtOrdinal;
  final int status;
  int _ordinal = 0;

  @override
  Future<V5TransportResponse> sendFrame(List<int> frame) async {
    final ordinal = _ordinal++;
    final req = NamTransferFrame.parse(frame);
    final s = ordinal == failAtOrdinal ? status : 0x01;
    final ack = NamTransferAck(slot: req.slot, block: req.block, status: s);
    return V5TransportResponse.received([ack.encode()]);
  }
}

/// Scenario G: sends the correct ACK plus one extra, unexpected message on
/// the [failAtOrdinal]th send.
class V5FakeTransportExtraMessage implements V5Transport {
  V5FakeTransportExtraMessage({required this.failAtOrdinal});
  final int failAtOrdinal;
  int _ordinal = 0;

  @override
  Future<V5TransportResponse> sendFrame(List<int> frame) async {
    final ordinal = _ordinal++;
    final req = NamTransferFrame.parse(frame);
    final ack = NamTransferAck(slot: req.slot, block: req.block, status: 0x01);
    if (ordinal == failAtOrdinal) {
      return V5TransportResponse.received([ack.encode(), ack.encode()]);
    }
    return V5TransportResponse.received([ack.encode()]);
  }
}
