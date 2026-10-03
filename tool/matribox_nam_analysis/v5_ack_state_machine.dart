/// V5A: the stop-and-wait sender state machine, and a write-budget guard.
/// In V5A this is ONLY ever exercised against [V5FakeTransport]
/// (`v5_fake_transport.dart`) in tests -- nothing here opens a USB/MIDI
/// device, and [V5Transport] is an abstract interface with no real
/// implementation anywhere in this milestone. A real transport is future
/// work for V5B, gated on explicit user approval, and is not written here.
library;

import 'nam_transfer_codec.dart';
import 'v5_transfer_plan.dart';

/// One raw response to a single sent frame. `null` [messages] means a
/// timeout (no response arrived within whatever deadline the transport
/// enforces). A non-null but multi-element list represents an unexpected
/// extra message on top of the real ACK (scenario G).
class V5TransportResponse {
  const V5TransportResponse.timeout() : messages = null;
  const V5TransportResponse.received(this.messages);
  final List<List<int>>? messages;
}

/// Abstract transport. [V5AckStateMachine] never assumes anything about
/// what is behind this beyond "sends one frame, returns one response" --
/// it never retries a send and never reaches past this interface.
abstract class V5Transport {
  Future<V5TransportResponse> sendFrame(List<int> frame);
}

/// Enforces the V5 hardware-test write budget: exactly one full-transfer
/// attempt, ever, per instance. A second call to [consumeAttempt] throws,
/// regardless of whether the first attempt succeeded, aborted, or is still
/// in progress -- there is no reset method.
class V5WriteBudget {
  bool _consumed = false;

  void consumeAttempt() {
    if (_consumed) {
      throw StateError(
        'V5 write budget exhausted: exactly one transfer attempt is allowed per V5WriteBudget instance.',
      );
    }
    _consumed = true;
  }

  bool get isConsumed => _consumed;
}

enum V5AbortReason {
  none,
  timeout,
  malformedAck,
  wrongSlot,
  wrongBlock,
  unexpectedStatus,
  unexpectedExtraMessage,
  writeBudgetExhausted,
}

enum V5TransferOutcome { success, transportFail }

class V5LogEntry {
  V5LogEntry({
    required this.timestamp,
    required this.ordinal,
    required this.block,
    required this.targetSlot,
    required this.outboundHex,
    required this.ackArrivalDuration,
    this.ackBlock,
    this.ackStatus,
    this.abortReason,
  });

  final DateTime timestamp;
  final int ordinal;
  final int block;
  final int targetSlot;

  /// Safe hex representation of the outbound frame (never a hash of
  /// anything else, never any unrelated device/personal data).
  final String outboundHex;
  final Duration ackArrivalDuration;
  final int? ackBlock;
  final int? ackStatus;
  final V5AbortReason? abortReason;
}

class V5TransferSummary {
  V5TransferSummary({
    required this.framesPlanned,
    required this.framesSent,
    required this.acksReceived,
    required this.lastConfirmedBlock,
    required this.outcome,
    required this.abortReason,
  });

  final int framesPlanned;
  final int framesSent;
  final int acksReceived;
  final int? lastConfirmedBlock;
  final V5TransferOutcome outcome;
  final V5AbortReason abortReason;

  @override
  String toString() =>
      'V5TransferSummary(planned=$framesPlanned sent=$framesSent acks=$acksReceived '
      'lastConfirmedBlock=$lastConfirmedBlock outcome=$outcome reason=$abortReason)';
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Runs [plan] against [transport] under [budget], stopping IMMEDIATELY
/// (before sending the next frame) on the first anomaly. The only allowed
/// repeats are the ones already baked into [plan] (the confirmed
/// last-block repetition) -- this function never retries a send on its
/// own initiative.
class V5AckStateMachine {
  V5AckStateMachine({required this.plan, required this.transport, required this.budget});

  final V5TransferPlan plan;
  final V5Transport transport;
  final V5WriteBudget budget;

  final List<V5LogEntry> log = [];

  Future<V5TransferSummary> run() async {
    budget.consumeAttempt(); // throws if already used -- before any send.

    var acksReceived = 0;
    int? lastConfirmedBlock;

    for (final planned in plan.frames) {
      final started = DateTime.now();
      final response = await transport.sendFrame(planned.outbound);
      final elapsed = DateTime.now().difference(started);

      if (response.messages == null) {
        log.add(
          V5LogEntry(
            timestamp: started,
            ordinal: planned.ordinal,
            block: planned.block,
            targetSlot: planned.expectedAckSlot,
            outboundHex: _hex(planned.outbound),
            ackArrivalDuration: elapsed,
            abortReason: V5AbortReason.timeout,
          ),
        );
        return _summary(acksReceived, lastConfirmedBlock, V5AbortReason.timeout);
      }
      final messages = response.messages!;
      if (messages.length != 1) {
        log.add(
          V5LogEntry(
            timestamp: started,
            ordinal: planned.ordinal,
            block: planned.block,
            targetSlot: planned.expectedAckSlot,
            outboundHex: _hex(planned.outbound),
            ackArrivalDuration: elapsed,
            abortReason: V5AbortReason.unexpectedExtraMessage,
          ),
        );
        return _summary(acksReceived, lastConfirmedBlock, V5AbortReason.unexpectedExtraMessage);
      }

      NamTransferAck ack;
      try {
        ack = NamTransferAck.parse(messages.single);
      } on FormatException {
        log.add(
          V5LogEntry(
            timestamp: started,
            ordinal: planned.ordinal,
            block: planned.block,
            targetSlot: planned.expectedAckSlot,
            outboundHex: _hex(planned.outbound),
            ackArrivalDuration: elapsed,
            abortReason: V5AbortReason.malformedAck,
          ),
        );
        return _summary(acksReceived, lastConfirmedBlock, V5AbortReason.malformedAck);
      }

      if (ack.slot != planned.expectedAckSlot) {
        log.add(
          V5LogEntry(
            timestamp: started,
            ordinal: planned.ordinal,
            block: planned.block,
            targetSlot: planned.expectedAckSlot,
            outboundHex: _hex(planned.outbound),
            ackArrivalDuration: elapsed,
            ackBlock: ack.block,
            ackStatus: ack.status,
            abortReason: V5AbortReason.wrongSlot,
          ),
        );
        return _summary(acksReceived, lastConfirmedBlock, V5AbortReason.wrongSlot);
      }
      if (ack.block != planned.expectedAckBlock) {
        log.add(
          V5LogEntry(
            timestamp: started,
            ordinal: planned.ordinal,
            block: planned.block,
            targetSlot: planned.expectedAckSlot,
            outboundHex: _hex(planned.outbound),
            ackArrivalDuration: elapsed,
            ackBlock: ack.block,
            ackStatus: ack.status,
            abortReason: V5AbortReason.wrongBlock,
          ),
        );
        return _summary(acksReceived, lastConfirmedBlock, V5AbortReason.wrongBlock);
      }
      if (!ack.isObservedOk || ack.status != planned.expectedAckStatus) {
        log.add(
          V5LogEntry(
            timestamp: started,
            ordinal: planned.ordinal,
            block: planned.block,
            targetSlot: planned.expectedAckSlot,
            outboundHex: _hex(planned.outbound),
            ackArrivalDuration: elapsed,
            ackBlock: ack.block,
            ackStatus: ack.status,
            abortReason: V5AbortReason.unexpectedStatus,
          ),
        );
        return _summary(acksReceived, lastConfirmedBlock, V5AbortReason.unexpectedStatus);
      }

      acksReceived++;
      lastConfirmedBlock = ack.block;
      log.add(
        V5LogEntry(
          timestamp: started,
          ordinal: planned.ordinal,
          block: planned.block,
          targetSlot: planned.expectedAckSlot,
          outboundHex: _hex(planned.outbound),
          ackArrivalDuration: elapsed,
          ackBlock: ack.block,
          ackStatus: ack.status,
        ),
      );
    }

    return V5TransferSummary(
      framesPlanned: plan.frameCount,
      framesSent: log.length,
      acksReceived: acksReceived,
      lastConfirmedBlock: lastConfirmedBlock,
      outcome: V5TransferOutcome.success,
      abortReason: V5AbortReason.none,
    );
  }

  V5TransferSummary _summary(int acksReceived, int? lastConfirmedBlock, V5AbortReason reason) {
    return V5TransferSummary(
      framesPlanned: plan.frameCount,
      framesSent: log.length,
      acksReceived: acksReceived,
      lastConfirmedBlock: lastConfirmedBlock,
      outcome: V5TransferOutcome.transportFail,
      abortReason: reason,
    );
  }
}
