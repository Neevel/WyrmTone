import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/services/matribox_clone_slot_policy.dart';
import 'package:wyrmtone/services/matribox_nam_payload.dart';
import 'package:wyrmtone/services/matribox_nam_transfer_codec.dart';
import 'package:wyrmtone/services/matribox_nam_transfer_service.dart';

import 'support/fake_usb_service.dart';

/// Product NAM → Matribox workflow V1: the Dart orchestration layer over the
/// hardware-validated V5 transport, using a fake transport (no real device) --
/// same testing pattern the earlier V5 offline preflight work established.
void main() {
  MatriboxNamPayload payload({int fill = 0x11}) {
    final cloData = Uint8List(8232);
    // Build a structurally valid CloData via the real encode/parse round trip
    // is overkill here; MatriboxNamTransferService only requires
    // MatriboxNamPayload.validate() to pass, so build one directly from the
    // converter's own known-good shape isn't necessary -- reuse the frozen
    // constant header/constants by relying on the converter elsewhere is
    // out of scope for this service-layer test. Instead: construct bytes
    // that satisfy MatriboxCloneData.parse's structural checks directly.
    for (var i = 0x88; i < 0x1ea8; i++) {
      cloData[i] = fill;
    }
    final view = ByteData.sublistView(cloData);
    view.setUint32(0x20, 0x49535456, Endian.little); // 'VTSI'
    view.setUint32(0x24, 0x1288, Endian.little);
    view.setUint32(0x34, 0x1200, Endian.little);
    view.setUint32(0xa0, 128, Endian.little); // must be set AFTER the fill loop above (it overlaps this offset)
    view.setUint32(0xa4, 1024, Endian.little); // same
    return MatriboxNamPayload(
      cloData: cloData,
      namName: 'Test NAM',
      namSha256: 'test-sha',
      cloDataSha256: 'test-clodata-sha',
      preparationDuration: const Duration(seconds: 42),
    );
  }

  group('MatriboxCloneSlotPolicy', () {
    test('Clone 1 and Clone 5 are product-writable (hardware-confirmed)', () {
      expect(MatriboxCloneSlotPolicy.isProductWritable(1), isTrue);
      expect(MatriboxCloneSlotPolicy.isProductWritable(5), isTrue);
      expect(MatriboxCloneSlotPolicy.capabilityFor(1).evidenceLabel, 'Hardware-bestätigt');
    });

    test('Clone 2-4 are visible but not product-writable (inferred only)', () {
      for (final n in [2, 3, 4]) {
        expect(MatriboxCloneSlotPolicy.isProductWritable(n), isFalse, reason: 'Clone $n');
        expect(MatriboxCloneSlotPolicy.capabilityFor(n).evidenceLabel, 'Noch nicht verifiziert');
      }
    });

    test('MatriboxTransferCloneSlots.all has exactly 5 entries, Clone1/5 approved, Clone2-4 not', () {
      final all = MatriboxTransferCloneSlots.all;
      expect(all.length, 5);
      expect(all.map((s) => s.cloneNumber), [1, 2, 3, 4, 5]);
      expect(all.where((s) => s.approved).map((s) => s.cloneNumber), [1, 5]);
    });

    test('an out-of-range Clone number is structurally impossible', () {
      expect(() => MatriboxTransferCloneSlot(0), throwsFormatException);
      expect(() => MatriboxTransferCloneSlot(6), throwsFormatException);
    });
  });

  group('MatriboxNamTransferService', () {
    test('590/590 success: outcome success, progress reaches 590/590, no automatic retry', () async {
      final usb = FakeUsbService();
      usb.namCloneSessionResult = {'outcome': 'SUCCESS', 'framesSent': 590, 'lastConfirmedBlock': 587};
      final progressEvents = <MatriboxNamTransferProgress>[];
      final service = MatriboxNamTransferService(usb);

      final result = await service.transfer(
        payload: payload(),
        slot: MatriboxCloneSlot(5),
        onProgress: progressEvents.add,
      );

      expect(result.isSuccess, isTrue);
      expect(result.outcome, MatriboxNamTransferOutcome.success);
      expect(usb.namCloneSessionCalls, hasLength(1));
      expect(progressEvents, isNotEmpty);
      expect(progressEvents.last.confirmedCount, usb.namCloneSessionCalls.single.length);
      expect(progressEvents.last.totalFrames, usb.namCloneSessionCalls.single.length);
      // Exactly one session call: no automatic retry anywhere in this service.
      await service.transfer(payload: payload(), slot: MatriboxCloneSlot(5));
      expect(usb.namCloneSessionCalls, hasLength(2), reason: 'a second EXPLICIT call is allowed; nothing retries on its own');
    });

    test('progress derives from confirmed ACKs, not merely-sent frames', () async {
      final usb = FakeUsbService()..autoEmitNamTransferProgress = false;
      usb.namCloneSessionResult = {'outcome': 'SUCCESS', 'framesSent': 3, 'lastConfirmedBlock': 2};
      final progressEvents = <MatriboxNamTransferProgress>[];
      final service = MatriboxNamTransferService(usb);

      final future = service.transfer(payload: payload(), slot: MatriboxCloneSlot(1), onProgress: progressEvents.add);
      // Manually emit only a PARTIAL confirmed count before the call resolves.
      usb.namTransferProgressController.add({'confirmedCount': 1, 'lastConfirmedBlock': 0, 'totalFrames': 3});
      await Future<void>.delayed(Duration.zero);
      await future;

      expect(progressEvents, hasLength(1));
      expect(progressEvents.single.confirmedCount, 1);
      expect(progressEvents.single.totalFrames, 3);
    });

    for (final entry in {
      'TIMEOUT': MatriboxNamTransferFailureCategory.timeout,
      'UNEXPECTED_MESSAGE': MatriboxNamTransferFailureCategory.invalidResponse,
      'MALFORMED_ACK': MatriboxNamTransferFailureCategory.malformedAck,
      'WRONG_SLOT': MatriboxNamTransferFailureCategory.wrongSlot,
      'WRONG_BLOCK': MatriboxNamTransferFailureCategory.wrongBlock,
      'UNEXPECTED_STATUS': MatriboxNamTransferFailureCategory.unexpectedStatus,
      'SEND_FAILED': MatriboxNamTransferFailureCategory.sendFailure,
      'OPEN_FAILED': MatriboxNamTransferFailureCategory.openFailed,
    }.entries) {
      test('native outcome ${entry.key} maps to ${entry.value}, never PASS', () async {
        final usb = FakeUsbService()..autoEmitNamTransferProgress = false;
        usb.namCloneSessionResult = {
          'outcome': entry.key,
          'error': 'technical detail',
          'framesSent': 2,
          'lastConfirmedBlock': 1,
        };
        final service = MatriboxNamTransferService(usb);
        final result = await service.transfer(payload: payload(), slot: MatriboxCloneSlot(1));
        expect(result.outcome, MatriboxNamTransferOutcome.failed);
        expect(result.failureCategory, entry.value);
        expect(result.technicalMessage, 'technical detail');
        expect(result.userMessage, isNot(contains('technical detail')), reason: 'raw native text must never leak into the default user message');
      });
    }

    test('an invalid (structurally wrong) payload is refused before any frame is built, no session call', () async {
      final usb = FakeUsbService();
      final service = MatriboxNamTransferService(usb);
      final badPayload = MatriboxNamPayload(
        cloData: Uint8List(100),
        namName: 'bad',
        namSha256: 'x',
        cloDataSha256: 'x',
        preparationDuration: Duration.zero,
      );
      final result = await service.transfer(payload: badPayload, slot: MatriboxCloneSlot(1));
      expect(result.outcome, MatriboxNamTransferOutcome.failed);
      expect(result.failureCategory, MatriboxNamTransferFailureCategory.invalidPayload);
      expect(usb.namCloneSessionCalls, isEmpty);
    });

    test('cancel() before transfer() starts refuses without calling the session', () async {
      final usb = FakeUsbService();
      final service = MatriboxNamTransferService(usb);
      await service.cancel();
      final result = await service.transfer(payload: payload(), slot: MatriboxCloneSlot(1));
      expect(result.outcome, MatriboxNamTransferOutcome.cancelled);
      expect(usb.namCloneSessionCalls, isEmpty);
      expect(usb.cancelNamCloneTransferSessionCalls, 1);
      expect(usb.closeCalls, 0, reason: 'cancel must never tear down the USB connection itself');
    });

    test('building the service and calling cancel() never sends anything on their own', () async {
      final usb = FakeUsbService();
      // ignore: unused_local_variable
      final service = MatriboxNamTransferService(usb);
      expect(usb.namCloneSessionCalls, isEmpty);
    });

    // Session-lifecycle fix: this is the EXACT bug found during real-device
    // repeated-transfer testing. executeNamCloneTransferSession can throw a
    // PlatformException (the platform channel's own watchdog timeout, the
    // native "a session is already active" guard, or any other native-side
    // failure) WITHOUT ever returning a result map -- before this fix,
    // transfer() had no catch for that, so the exception propagated
    // uncaught and the caller's UI never left the "transferring" phase,
    // even though the native side had already finished (with an error) in
    // well under a second. "PlatformException" here is exactly what a real
    // MethodChannel.invokeMethod throws when native code calls
    // `result.error(...)` -- not a made-up test-only type.
    test(
      'a PlatformException from executeNamCloneTransferSession becomes a terminal failed result, never propagates',
      () async {
        final usb = FakeUsbService()
          ..namCloneSessionError = PlatformException(
            code: 'NAM_CLONE_SESSION_TIMEOUT',
            message: 'Die Matribox hat nicht innerhalb der erwarteten Zeit geantwortet.',
          );
        final service = MatriboxNamTransferService(usb);
        final result = await service.transfer(payload: payload(), slot: MatriboxCloneSlot(5));
        expect(result.outcome, MatriboxNamTransferOutcome.failed);
        expect(result.failureCategory, MatriboxNamTransferFailureCategory.timeout);
      },
    );

    test('an "already active" PlatformException also becomes a terminal failed result', () async {
      final usb = FakeUsbService()
        ..namCloneSessionError = PlatformException(
          code: 'NAM_CLONE_SESSION_FAILED',
          message: 'Eine NAM-Clone-Transfer-Sitzung läuft bereits; kein zweiter gleichzeitiger Versuch.',
        );
      final service = MatriboxNamTransferService(usb);
      final result = await service.transfer(payload: payload(), slot: MatriboxCloneSlot(5));
      expect(result.outcome, MatriboxNamTransferOutcome.failed);
      expect(result.technicalMessage, contains('läuft bereits'));
    });

    group('sequential transfers (the real-device bug this milestone fixes)', () {
      test('SUCCESS -> SUCCESS: two independent transfer sessions, no app restart, no state leakage', () async {
        final usb = FakeUsbService();
        usb.namCloneSessionResult = {'outcome': 'SUCCESS', 'framesSent': 588, 'lastConfirmedBlock': 587};

        final serviceA = MatriboxNamTransferService(usb);
        final resultA = await serviceA.transfer(payload: payload(fill: 0x11), slot: MatriboxCloneSlot(5));
        expect(resultA.outcome, MatriboxNamTransferOutcome.success);

        // A fresh service instance, exactly as NamDetailPage creates one per attempt
        // (a brand new widget/page visit for NAM B) -- same underlying transport.
        final serviceB = MatriboxNamTransferService(usb);
        final resultB = await serviceB.transfer(payload: payload(fill: 0x22), slot: MatriboxCloneSlot(5));
        expect(resultB.outcome, MatriboxNamTransferOutcome.success);

        expect(usb.namCloneSessionCalls, hasLength(2));
        expect(usb.namCloneSessionCalls[0], isNot(equals(usb.namCloneSessionCalls[1])), reason: 'different payloads must produce different frames');
      });

      test('SUCCESS -> CANCEL -> SUCCESS', () async {
        final usb = FakeUsbService();
        usb.namCloneSessionResult = {'outcome': 'SUCCESS', 'framesSent': 588, 'lastConfirmedBlock': 587};
        final serviceA = MatriboxNamTransferService(usb);
        expect((await serviceA.transfer(payload: payload(), slot: MatriboxCloneSlot(5))).outcome, MatriboxNamTransferOutcome.success);

        final serviceB = MatriboxNamTransferService(usb);
        await serviceB.cancel();
        expect((await serviceB.transfer(payload: payload(), slot: MatriboxCloneSlot(5))).outcome, MatriboxNamTransferOutcome.cancelled);

        final serviceC = MatriboxNamTransferService(usb);
        expect((await serviceC.transfer(payload: payload(), slot: MatriboxCloneSlot(5))).outcome, MatriboxNamTransferOutcome.success);
      });

      test('SUCCESS -> FAILURE -> SUCCESS', () async {
        final usb = FakeUsbService();
        usb.namCloneSessionResult = {'outcome': 'SUCCESS', 'framesSent': 588, 'lastConfirmedBlock': 587};
        final serviceA = MatriboxNamTransferService(usb);
        expect((await serviceA.transfer(payload: payload(), slot: MatriboxCloneSlot(5))).outcome, MatriboxNamTransferOutcome.success);

        usb.namCloneSessionError = PlatformException(code: 'NAM_CLONE_SESSION_TIMEOUT', message: 'timeout');
        final serviceB = MatriboxNamTransferService(usb);
        expect((await serviceB.transfer(payload: payload(), slot: MatriboxCloneSlot(5))).outcome, MatriboxNamTransferOutcome.failed);

        usb.namCloneSessionError = null;
        usb.namCloneSessionResult = {'outcome': 'SUCCESS', 'framesSent': 588, 'lastConfirmedBlock': 587};
        final serviceC = MatriboxNamTransferService(usb);
        expect((await serviceC.transfer(payload: payload(), slot: MatriboxCloneSlot(5))).outcome, MatriboxNamTransferOutcome.success);
      });

      test('CANCEL -> SUCCESS', () async {
        final usb = FakeUsbService();
        final serviceA = MatriboxNamTransferService(usb);
        await serviceA.cancel();
        expect((await serviceA.transfer(payload: payload(), slot: MatriboxCloneSlot(5))).outcome, MatriboxNamTransferOutcome.cancelled);

        usb.namCloneSessionResult = {'outcome': 'SUCCESS', 'framesSent': 588, 'lastConfirmedBlock': 587};
        final serviceB = MatriboxNamTransferService(usb);
        expect((await serviceB.transfer(payload: payload(), slot: MatriboxCloneSlot(5))).outcome, MatriboxNamTransferOutcome.success);
      });

      test('FAILURE -> SUCCESS', () async {
        final usb = FakeUsbService()
          ..namCloneSessionError = PlatformException(code: 'NAM_CLONE_SESSION_TIMEOUT', message: 'timeout');
        final serviceA = MatriboxNamTransferService(usb);
        expect((await serviceA.transfer(payload: payload(), slot: MatriboxCloneSlot(5))).outcome, MatriboxNamTransferOutcome.failed);

        usb.namCloneSessionError = null;
        usb.namCloneSessionResult = {'outcome': 'SUCCESS', 'framesSent': 588, 'lastConfirmedBlock': 587};
        final serviceB = MatriboxNamTransferService(usb);
        expect((await serviceB.transfer(payload: payload(), slot: MatriboxCloneSlot(5))).outcome, MatriboxNamTransferOutcome.success);
      });

      test('no automatic retry: a failed attempt is never silently retried by the service itself', () async {
        final usb = FakeUsbService()
          ..namCloneSessionError = PlatformException(code: 'NAM_CLONE_SESSION_TIMEOUT', message: 'timeout');
        final service = MatriboxNamTransferService(usb);
        final result = await service.transfer(payload: payload(), slot: MatriboxCloneSlot(5));
        expect(result.outcome, MatriboxNamTransferOutcome.failed);
        expect(usb.namCloneSessionInvocations, 1, reason: 'exactly one native call, no silent retry');
      });
    });
  });
}
