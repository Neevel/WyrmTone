/// Dart-side client for the one native production write operation:
/// `writeConfirmedSol100OdGain`. This file sends nothing by itself; it
/// only wraps a [MatriboxConfirmedGainWriteChannel] call with
/// [MatriboxSafeWriteExecutor], which independently re-validates every
/// precondition from a [MatriboxSafeWriteSessionResult] before ever
/// invoking the channel -- the UI's "write" button being enabled is never
/// trusted on its own (defense in depth, matching the native side's own
/// independent re-validation).
library;

import 'matribox_preset_write_plan.dart';
import 'matribox_safe_write_session.dart';

enum MatriboxGainWriteOutcome {
  success,
  deviceNotConnected,
  midiNotAvailable,
  invalidValue,
  sendFailed,
  safetyRejected,

  /// The platform channel call itself failed or returned an unrecognised
  /// shape (Dart-side only; has no native counterpart).
  channelError,
}

class MatriboxGainWriteResult {
  const MatriboxGainWriteResult({
    required this.outcome,
    this.targetValue,
    this.errorMessage,
  });

  final MatriboxGainWriteOutcome outcome;
  final double? targetValue;
  final String? errorMessage;

  bool get isSuccess => outcome == MatriboxGainWriteOutcome.success;
}

MatriboxGainWriteOutcome _outcomeFromNative(Object? name) => switch (name) {
  'SUCCESS' => MatriboxGainWriteOutcome.success,
  'DEVICE_NOT_CONNECTED' => MatriboxGainWriteOutcome.deviceNotConnected,
  'MIDI_NOT_AVAILABLE' => MatriboxGainWriteOutcome.midiNotAvailable,
  'INVALID_VALUE' => MatriboxGainWriteOutcome.invalidValue,
  'SEND_FAILED' => MatriboxGainWriteOutcome.sendFailed,
  'SAFETY_REJECTED' => MatriboxGainWriteOutcome.safetyRejected,
  _ => MatriboxGainWriteOutcome.channelError,
};

/// Abstracts the native platform-channel call so [MatriboxSafeWriteExecutor]
/// is fully testable offline, without a MethodChannel or Flutter binding.
abstract interface class MatriboxConfirmedGainWriteChannel {
  /// [targetGain] is the only value ever sent -- no algorithm, index, bank,
  /// slot or raw bytes leave this boundary.
  Future<Map<Object?, Object?>> writeConfirmedSol100OdGain(double targetGain);
}

/// The Safe Write Session remains authoritative: this executor re-derives
/// and re-checks every precondition from the session result itself,
/// independently of whatever a caller (e.g. a UI button's enabled state)
/// already believes. It makes at most one channel call, and only if every
/// check passes.
class MatriboxSafeWriteExecutor {
  const MatriboxSafeWriteExecutor(this.channel);

  final MatriboxConfirmedGainWriteChannel channel;

  Future<MatriboxGainWriteResult> executeGainWrite(
    MatriboxSafeWriteSessionResult session,
  ) async {
    if (!session.readyForHardwareTest) {
      return const MatriboxGainWriteResult(
        outcome: MatriboxGainWriteOutcome.safetyRejected,
        errorMessage: 'Plan ist nicht READY_FOR_HARDWARE_TEST.',
      );
    }
    final plan = session.plan;
    if (plan == null) {
      return const MatriboxGainWriteResult(
        outcome: MatriboxGainWriteOutcome.safetyRejected,
        errorMessage: 'Kein Schreibplan vorhanden.',
      );
    }
    if (plan.targetAddress.presetNumber != 1) {
      return const MatriboxGainWriteResult(
        outcome: MatriboxGainWriteOutcome.safetyRejected,
        errorMessage: 'Zielslot ist nicht User/P01.',
      );
    }
    if (plan.operations.length != 1) {
      return const MatriboxGainWriteResult(
        outcome: MatriboxGainWriteOutcome.safetyRejected,
        errorMessage: 'Plan enthält nicht genau eine Operation.',
      );
    }
    final operation = plan.operations.single;
    if (operation.field != 'gain' ||
        operation.status != MatriboxWriteOperationStatus.writable) {
      return const MatriboxGainWriteResult(
        outcome: MatriboxGainWriteOutcome.safetyRejected,
        errorMessage:
            'Einzige Operation ist nicht die bestätigte Gain-Schreiboperation.',
      );
    }

    final Map<Object?, Object?> raw;
    try {
      raw = await channel.writeConfirmedSol100OdGain(operation.targetValue);
    } catch (error) {
      return MatriboxGainWriteResult(
        outcome: MatriboxGainWriteOutcome.channelError,
        errorMessage: '$error',
      );
    }
    return MatriboxGainWriteResult(
      outcome: _outcomeFromNative(raw['outcome']),
      targetValue: operation.targetValue,
      errorMessage: raw['error'] as String?,
    );
  }
}
