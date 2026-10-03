import 'dart:typed_data';

import 'matribox_nam_clodata/clone_data.dart';

/// Android NAM Inference V1 (final on-device CloData gate): the product
/// result of a completed NAM preparation -- exactly what
/// `NamPreparationService.prepare()` returns on success, and the only thing
/// downstream code (a future Matribox transfer UI) needs to know about. No
/// FFI details, no native pointers, no estimator-stage internals.
class MatriboxNamPayload {
  const MatriboxNamPayload({
    required this.cloData,
    required this.namName,
    required this.namSha256,
    required this.cloDataSha256,
    required this.preparationDuration,
  });

  /// The 8,232-byte CloData block, ready to be split into transfer frames
  /// by the (separately defined) Matribox transfer wire codec for a chosen
  /// Clone slot. This class never opens a MIDI port or references any
  /// transport/transfer-session code -- it is pure data.
  final Uint8List cloData;

  /// The source NAM's display identity (e.g. `LocalNamCapture.toneName`),
  /// for UI display and diagnostics only.
  final String namName;

  /// SHA-256 of the source .nam file, for diagnostics/traceability.
  final String namSha256;

  /// SHA-256 of [cloData], for diagnostics/traceability (never shown to a
  /// normal user by default -- see the product NAM import milestone's UI
  /// rules).
  final String cloDataSha256;

  final Duration preparationDuration;

  /// Throws [FormatException] if [cloData] is not a structurally valid,
  /// exactly-8232-byte CloData block, or if any model-dependent float in it
  /// is NaN/Infinity. Never returns a partially-validated payload.
  static void validate(Uint8List cloData) {
    if (cloData.length != MatriboxCloneData.totalLength) {
      throw FormatException(
        'CloData must be ${MatriboxCloneData.totalLength} bytes, got ${cloData.length}.',
      );
    }
    final parsed = MatriboxCloneData.parse(cloData); // throws on structural mismatch
    void checkFinite(Uint8List floatBytes, String label) {
      final view = ByteData.sublistView(floatBytes);
      for (var i = 0; i < floatBytes.length; i += 4) {
        final v = view.getFloat32(i, Endian.little);
        if (!v.isFinite) {
          throw FormatException('CloData $label contains a non-finite float32 at byte offset $i.');
        }
      }
    }

    checkFinite(parsed.variableParams, 'variableParams');
    checkFinite(parsed.firTaps, 'firTaps');
  }
}
