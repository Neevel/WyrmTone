import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;

import 'matribox_nam_payload.dart';
import 'matribox_nam_transfer_codec.dart';
import 'usb_service.dart';

/// Product NAM transfer V1: the Dart-side orchestration layer over the
/// already hardware-validated V5 transport (`MatriboxNamCloneTransferReference`/
/// `MatriboxNamTransferSession`/`NamAckStreamAssembler`, native side). This
/// file NEVER constructs raw SysEx bytes itself for anything other than the
/// one confirmed NAM Clone-transfer frame family (via [encodeCloneTransfer]):
/// no Store, no preset command, no arbitrary bytes from UI code. The wire
/// protocol is unchanged -- this only adds typed inputs
/// ([MatriboxNamPayload]/[MatriboxCloneSlot]) and real ACK-based progress on
/// top of the existing [UsbService.executeNamCloneTransferSession].
enum MatriboxNamTransferOutcome { success, failed, cancelled }

/// Product-facing failure categories (mirrors the native
/// `NamTransferOutcome` enum, but this is the boundary UI code depends on --
/// never the raw native string).
enum MatriboxNamTransferFailureCategory {
  timeout,
  disconnected,
  invalidResponse,
  malformedAck,
  wrongSlot,
  wrongBlock,
  unexpectedStatus,
  sendFailure,
  openFailed,
  alreadyUsed,
  notEligible,
  invalidPayload,
  unknown,
}

/// German, user-facing text for a failure category (section 21). The
/// technical native message stays available separately for a "Details" view
/// -- never shown by default.
String matriboxNamTransferFailureMessage(MatriboxNamTransferFailureCategory category) => switch (category) {
  MatriboxNamTransferFailureCategory.timeout => 'Die Matribox hat nicht rechtzeitig geantwortet.',
  MatriboxNamTransferFailureCategory.disconnected => 'Die Verbindung zur Matribox wurde unterbrochen.',
  MatriboxNamTransferFailureCategory.invalidResponse => 'Die Matribox hat unerwartet geantwortet.',
  MatriboxNamTransferFailureCategory.malformedAck => 'Die Matribox hat unerwartet geantwortet.',
  MatriboxNamTransferFailureCategory.wrongSlot => 'Die Matribox hat einen anderen Clone-Slot bestätigt als erwartet.',
  MatriboxNamTransferFailureCategory.wrongBlock => 'Die Matribox hat einen anderen Block bestätigt als erwartet.',
  MatriboxNamTransferFailureCategory.unexpectedStatus => 'Die Matribox hat die Übertragung nicht bestätigt.',
  MatriboxNamTransferFailureCategory.sendFailure => 'Die Übertragung konnte nicht fortgesetzt werden.',
  MatriboxNamTransferFailureCategory.openFailed => 'Die Matribox konnte nicht geöffnet werden.',
  MatriboxNamTransferFailureCategory.alreadyUsed =>
    'Diese Sitzung wurde bereits verwendet. Bitte starte eine neue Übertragung.',
  MatriboxNamTransferFailureCategory.notEligible => 'Die Matribox ist gerade nicht bereit für eine Übertragung.',
  MatriboxNamTransferFailureCategory.invalidPayload => 'Das vorbereitete NAM-Modell konnte nicht übertragen werden.',
  MatriboxNamTransferFailureCategory.unknown => 'Die Übertragung ist fehlgeschlagen.',
};

/// Real, ACK-confirmed progress (section 17) -- never derived from frames
/// merely sent.
class MatriboxNamTransferProgress {
  const MatriboxNamTransferProgress({required this.confirmedCount, required this.totalFrames});
  final int confirmedCount;
  final int totalFrames;
  double get fraction => totalFrames == 0 ? 0.0 : confirmedCount / totalFrames;
}

class MatriboxNamTransferResult {
  const MatriboxNamTransferResult._({
    required this.outcome,
    this.failureCategory,
    this.technicalMessage,
    required this.confirmedCount,
    required this.totalFrames,
  });

  /// Test-only construction helpers -- production code only ever gets
  /// instances back from [MatriboxNamTransferService.transfer] itself.
  const MatriboxNamTransferResult.successForTest({required this.confirmedCount, required this.totalFrames})
    : outcome = MatriboxNamTransferOutcome.success,
      failureCategory = null,
      technicalMessage = null;
  const MatriboxNamTransferResult.failedForTest(
    this.failureCategory, {
    required this.confirmedCount,
    required this.totalFrames,
    this.technicalMessage,
  }) : outcome = MatriboxNamTransferOutcome.failed;
  const MatriboxNamTransferResult.cancelledForTest({required this.confirmedCount, required this.totalFrames})
    : outcome = MatriboxNamTransferOutcome.cancelled,
      failureCategory = null,
      technicalMessage = null;

  final MatriboxNamTransferOutcome outcome;
  final MatriboxNamTransferFailureCategory? failureCategory;

  /// The raw native error string, for a "Details" view only -- never shown
  /// to the user by default.
  final String? technicalMessage;
  final int confirmedCount;
  final int totalFrames;

  bool get isSuccess => outcome == MatriboxNamTransferOutcome.success;

  /// German, user-facing summary for [outcome]/[failureCategory]. Callers
  /// needing the cancelled-state copy should use the dedicated cancelled
  /// text in the UI (section 19) rather than this getter, since the exact
  /// wording there also depends on [confirmedCount]/[totalFrames].
  String get userMessage => switch (outcome) {
    MatriboxNamTransferOutcome.success => 'Übertragung abgeschlossen.',
    MatriboxNamTransferOutcome.cancelled => 'Die Übertragung wurde abgebrochen.',
    MatriboxNamTransferOutcome.failed => matriboxNamTransferFailureMessage(
      failureCategory ?? MatriboxNamTransferFailureCategory.unknown,
    ),
  };
}

/// Product-facing Matribox NAM transfer. One instance is good for exactly
/// one [transfer] call, matching the native session's own one-shot,
/// no-retry design (see `MatriboxNamTransferSession`/the process-lifetime
/// write budget in `MidiDiagnosticsManager`) -- never call [transfer] twice
/// on the same instance.
class MatriboxNamTransferService {
  MatriboxNamTransferService(this._usbService);

  final UsbService _usbService;
  bool _cancelled = false;

  /// Requests cancellation (section 19). Safe to call before, during, or
  /// after [transfer].
  ///
  /// Hardware-certification fix: this used to call [UsbService.closeDevice],
  /// which only tears down [UsbConnectionManager] and never reaches the
  /// native NAM transfer session at all -- confirmed during real-device
  /// testing to make "Abbrechen" a no-op while a transfer was stuck. Now
  /// calls the narrow, dedicated [UsbService.cancelNamCloneTransferSession],
  /// which reaches `MatriboxNamTransferSession.cancel()` directly and
  /// touches nothing else (not the USB connection, not the passive
  /// monitor). See that native method's own docs for what it does and does
  /// not interrupt (a blocked Android system/Binder call, e.g. from a
  /// mid-transfer USB disconnect, may not respond to this -- the platform
  /// channel's own watchdog timeout is the backstop for that case, see
  /// `UsbPlatformChannels.kt`).
  Future<void> cancel() async {
    _cancelled = true;
    await _usbService.cancelNamCloneTransferSession();
  }

  /// Builds the confirmed NAM Clone-transfer frames from [payload]/[slot]
  /// and runs the hardware-validated session. [onProgress] is called with
  /// real, ACK-confirmed counts as they arrive (never derived from frames
  /// merely sent). Never sends anything before this call is made and
  /// explicitly awaited by the caller -- building this object and calling
  /// [cancel] never causes a write.
  Future<MatriboxNamTransferResult> transfer({
    required MatriboxNamPayload payload,
    required MatriboxCloneSlot slot,
    void Function(MatriboxNamTransferProgress progress)? onProgress,
  }) async {
    if (_cancelled) {
      return const MatriboxNamTransferResult._(outcome: MatriboxNamTransferOutcome.cancelled, confirmedCount: 0, totalFrames: 0);
    }
    try {
      MatriboxNamPayload.validate(payload.cloData);
    } on FormatException catch (e) {
      return MatriboxNamTransferResult._(
        outcome: MatriboxNamTransferOutcome.failed,
        failureCategory: MatriboxNamTransferFailureCategory.invalidPayload,
        technicalMessage: e.message,
        confirmedCount: 0,
        totalFrames: 0,
      );
    }

    final messages = encodeCloneTransfer(payload.cloData, slot.wireValue);
    final frames = [for (final m in messages) m.toList()];

    StreamSubscription<Map<Object?, Object?>>? subscription;
    if (onProgress != null) {
      subscription = _usbService.namTransferProgress.listen((event) {
        final confirmedCount = (event['confirmedCount'] as num?)?.toInt();
        final totalFrames = (event['totalFrames'] as num?)?.toInt();
        if (confirmedCount != null && totalFrames != null) {
          onProgress(MatriboxNamTransferProgress(confirmedCount: confirmedCount, totalFrames: totalFrames));
        }
      });
    }
    try {
      final raw = await _usbService.executeNamCloneTransferSession(frames);
      if (_cancelled) {
        return MatriboxNamTransferResult._(
          outcome: MatriboxNamTransferOutcome.cancelled,
          confirmedCount: _confirmedCountOf(raw),
          totalFrames: frames.length,
        );
      }
      return _mapResult(raw, frames.length);
    } on PlatformException catch (e) {
      // Lifecycle fix: a native-side failure that never returns a result
      // map at all (the watchdog timeout, the "a session is already
      // active" guard, or any other runtime exception the platform
      // channel converts to result.error(...)) used to propagate as an
      // UNCAUGHT exception here -- the caller's await never completed with
      // a value, so its UI state machine never left the "transferring"
      // phase, even though the native side had already finished (with an
      // error) in well under a second. This is the actual fix for that:
      // every PlatformException becomes a normal, terminal
      // MatriboxNamTransferResult, same as any other failure.
      return MatriboxNamTransferResult._(
        outcome: MatriboxNamTransferOutcome.failed,
        failureCategory: _categoryOfPlatformException(e),
        technicalMessage: e.message,
        confirmedCount: 0,
        totalFrames: frames.length,
      );
    } finally {
      await subscription?.cancel();
    }
  }

  static MatriboxNamTransferFailureCategory _categoryOfPlatformException(PlatformException e) => switch (e.code) {
    'NAM_CLONE_SESSION_TIMEOUT' => MatriboxNamTransferFailureCategory.timeout,
    'INVALID_ARGUMENT' => MatriboxNamTransferFailureCategory.invalidPayload,
    _ => MatriboxNamTransferFailureCategory.unknown,
  };

  static int _confirmedCountOf(Map<Object?, Object?> raw) {
    final lastConfirmedBlock = (raw['lastConfirmedBlock'] as num?)?.toInt();
    return lastConfirmedBlock == null ? 0 : lastConfirmedBlock + 1;
  }

  static MatriboxNamTransferResult _mapResult(Map<Object?, Object?> raw, int totalFrames) {
    final outcomeStr = raw['outcome'] as String?;
    final confirmedCount = _confirmedCountOf(raw);
    if (outcomeStr == 'SUCCESS') {
      return MatriboxNamTransferResult._(
        outcome: MatriboxNamTransferOutcome.success,
        confirmedCount: confirmedCount,
        totalFrames: totalFrames,
      );
    }
    return MatriboxNamTransferResult._(
      outcome: MatriboxNamTransferOutcome.failed,
      failureCategory: _categoryOf(outcomeStr),
      technicalMessage: raw['error'] as String?,
      confirmedCount: confirmedCount,
      totalFrames: totalFrames,
    );
  }

  static MatriboxNamTransferFailureCategory _categoryOf(String? nativeOutcome) => switch (nativeOutcome) {
    'TIMEOUT' => MatriboxNamTransferFailureCategory.timeout,
    'UNEXPECTED_MESSAGE' => MatriboxNamTransferFailureCategory.invalidResponse,
    'MALFORMED_ACK' => MatriboxNamTransferFailureCategory.malformedAck,
    'WRONG_SLOT' => MatriboxNamTransferFailureCategory.wrongSlot,
    'WRONG_BLOCK' => MatriboxNamTransferFailureCategory.wrongBlock,
    'UNEXPECTED_STATUS' => MatriboxNamTransferFailureCategory.unexpectedStatus,
    'SEND_FAILED' => MatriboxNamTransferFailureCategory.sendFailure,
    'OPEN_FAILED' => MatriboxNamTransferFailureCategory.openFailed,
    'ALREADY_USED' => MatriboxNamTransferFailureCategory.alreadyUsed,
    'NOT_ELIGIBLE' => MatriboxNamTransferFailureCategory.notEligible,
    _ => MatriboxNamTransferFailureCategory.unknown,
  };
}
