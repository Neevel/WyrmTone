import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/matribox_nam_analysis/v5_ack_state_machine.dart';
import '../../tool/matribox_nam_analysis/v5_fake_transport.dart';
import '../../tool/matribox_nam_analysis/v5_transfer_plan.dart';

/// V5A: dry-run of the ACK state machine against a purely in-memory fake
/// transport (`v5_fake_transport.dart`) -- never a real device. Covers the
/// seven required failure-injection scenarios (A-G) plus the write
/// budget.
void main() {
  Uint8List validCloData() => Uint8List(v5RequiredCloDataLength)
    ..setRange(0, 16, 'V5 Test Clone Xy'.codeUnits);

  V5TransferPlan plan() => V5TransferPlan.build(
    cloData: validCloData(),
    modelLabel: 'Test Model',
    cloDataSha256Hex: 'deadbeef',
  );

  group('scenario A: all ACKs valid', () {
    test('the intended transfer completes exactly', () async {
      final sm = V5AckStateMachine(
        plan: plan(),
        transport: V5FakeTransportAllOk(),
        budget: V5WriteBudget(),
      );
      final summary = await sm.run();
      expect(summary.outcome, V5TransferOutcome.success);
      expect(summary.framesSent, v5ExpectedFrameCount);
      expect(summary.acksReceived, v5ExpectedFrameCount);
      expect(summary.lastConfirmedBlock, v5ExpectedBlockCount - 1);
      expect(summary.abortReason, V5AbortReason.none);
    });
  });

  group('scenarios B-G: must abort before the next frame', () {
    Future<void> expectAbort(V5Transport transport, V5AbortReason reason, {int? atOrdinal}) async {
      final sm = V5AckStateMachine(plan: plan(), transport: transport, budget: V5WriteBudget());
      final summary = await sm.run();
      expect(summary.outcome, V5TransferOutcome.transportFail);
      expect(summary.abortReason, reason);
      if (atOrdinal != null) {
        // Sent up to and including the failing frame, never beyond it.
        expect(summary.framesSent, atOrdinal + 1);
      }
      expect(summary.framesSent, lessThan(v5ExpectedFrameCount));
    }

    test('B: timeout aborts immediately', () async {
      await expectAbort(V5FakeTransportTimeout(failAtOrdinal: 5), V5AbortReason.timeout, atOrdinal: 5);
    });

    test('C: malformed ACK aborts immediately', () async {
      await expectAbort(
        V5FakeTransportMalformedAck(failAtOrdinal: 3),
        V5AbortReason.malformedAck,
        atOrdinal: 3,
      );
    });

    test('D: wrong-slot ACK aborts immediately', () async {
      await expectAbort(
        V5FakeTransportWrongSlot(failAtOrdinal: 7),
        V5AbortReason.wrongSlot,
        atOrdinal: 7,
      );
    });

    test('E: wrong-block ACK aborts immediately', () async {
      await expectAbort(
        V5FakeTransportWrongBlock(failAtOrdinal: 2),
        V5AbortReason.wrongBlock,
        atOrdinal: 2,
      );
    });

    test('F: non-success status aborts immediately', () async {
      await expectAbort(
        V5FakeTransportNonSuccessStatus(failAtOrdinal: 10),
        V5AbortReason.unexpectedStatus,
        atOrdinal: 10,
      );
    });

    test('G: unexpected extra message aborts immediately', () async {
      await expectAbort(
        V5FakeTransportExtraMessage(failAtOrdinal: 1),
        V5AbortReason.unexpectedExtraMessage,
        atOrdinal: 1,
      );
    });

    test('a late-transfer failure (near the repeated final block) still aborts, no partial-completion success', () async {
      await expectAbort(
        V5FakeTransportWrongBlock(failAtOrdinal: v5ExpectedFrameCount - 2),
        V5AbortReason.wrongBlock,
        atOrdinal: v5ExpectedFrameCount - 2,
      );
    });
  });

  group('write budget', () {
    test('a second run attempt on the same budget throws and never sends', () async {
      final budget = V5WriteBudget();
      final sm1 = V5AckStateMachine(plan: plan(), transport: V5FakeTransportAllOk(), budget: budget);
      final summary1 = await sm1.run();
      expect(summary1.outcome, V5TransferOutcome.success);
      expect(budget.isConsumed, isTrue);

      final sm2 = V5AckStateMachine(plan: plan(), transport: V5FakeTransportAllOk(), budget: budget);
      expect(() => sm2.run(), throwsA(isA<StateError>()));
    });

    test('a failed attempt still consumes the budget (no automatic retry)', () async {
      final budget = V5WriteBudget();
      final sm1 = V5AckStateMachine(
        plan: plan(),
        transport: V5FakeTransportTimeout(failAtOrdinal: 0),
        budget: budget,
      );
      await sm1.run();
      expect(budget.isConsumed, isTrue);
      final sm2 = V5AckStateMachine(plan: plan(), transport: V5FakeTransportAllOk(), budget: budget);
      expect(() => sm2.run(), throwsA(isA<StateError>()));
    });
  });

  test('logging captures one entry per attempted frame, never more', () async {
    final sm = V5AckStateMachine(
      plan: plan(),
      transport: V5FakeTransportWrongBlock(failAtOrdinal: 4),
      budget: V5WriteBudget(),
    );
    final summary = await sm.run();
    expect(sm.log.length, summary.framesSent);
    expect(sm.log.last.abortReason, V5AbortReason.wrongBlock);
  });
}
