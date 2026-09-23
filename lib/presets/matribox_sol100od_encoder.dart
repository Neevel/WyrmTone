/// Offline-only encoder for the six Sol 100 OD AMP parameter messages.
///
/// ENCODABLE is not HARDWARE_WRITABLE: this file builds bytes and sends
/// nothing (no transport, no platform channel). Which field may actually be
/// sent is decided elsewhere, by `MatriboxAmpFieldEvidence.hardwareWritable`,
/// which still only allows Gain.
///
/// The field is selected by wire name from the evidence registry, never by
/// a free algorithm/index, so this is not an arbitrary-parameter API.
library;

import 'confirmed_parameter_codec.dart';
import 'matribox_amp_field_evidence.dart';

const _solOneHundredOdCode = 0x07000047;
const _minimumValue = 0.0;
const _maximumValue = 99.0;

class UnencodableMatriboxField implements Exception {
  const UnencodableMatriboxField(this.message);
  final String message;
  @override
  String toString() => 'UnencodableMatriboxField: $message';
}

abstract final class MatriboxSol100OdEncoder {
  static bool isEncodable(String field) =>
      MatriboxAmpFieldEvidenceRegistry.forField(field)?.encodable ?? false;

  static List<int> encode(String field, double value) {
    final evidence = MatriboxAmpFieldEvidenceRegistry.forField(field);
    if (evidence == null || !evidence.encodable) {
      throw UnencodableMatriboxField(
        'Feld "$field" hat keine capture-bestätigte Encode-Evidenz.',
      );
    }
    if (!value.isFinite || value < _minimumValue || value > _maximumValue) {
      throw UnencodableMatriboxField(
        'Wert $value liegt außerhalb des validierten Bereichs '
        '[$_minimumValue, $_maximumValue].',
      );
    }
    return encodeMessageBytes(_solOneHundredOdCode, evidence.catalogIndex, value);
  }
}
