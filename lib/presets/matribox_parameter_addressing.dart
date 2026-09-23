/// The ONE place where a parameter's WIRE index is derived.
///
///   wireParameterIndex = manufacturerParameterId - 1
///
/// `manufacturerParameterId` is the `ID` attribute of the parameter in the
/// manufacturer's algorithm.xml (Sonicake Matribox 1 / QME-50 editor), kept in
/// the normalized catalog as `xmlId`. The XML `idx` is the display order only:
/// it equals `ID - 1` unless the XML skips an ID (a hidden parameter), which
/// happens for Boost `Bright` (idx 1, ID 3 -> wire 2), every CAB `VOL`
/// (idx 0, ID 2 -> wire 1) and a few more (see docs).
///
/// Hardware evidence: all 46 parameter groups of the editor big capture, plus
/// the CERTIFIED FAMILY_EXPANSION_P01_V1 run (Boost Bright on wire 2, CAB VOL
/// on wire 1) on a real Matribox 1. There is NO fallback to `idx`: a missing,
/// non-positive, duplicated or out-of-range ID blocks the parameter.
library;

/// A P01 stores 15 float parameters per block (payload layout).
const matriboxParametersPerBlock = 15;

const matriboxWireIndexRule = 'wireParameterIndex = manufacturerParameterId - 1';

/// The rule itself. Callers must validate the ID first ([ParameterAddress.resolve]).
int matriboxWireParameterIndex(int manufacturerParameterId) => manufacturerParameterId - 1;

class ParameterAddress {
  const ParameterAddress._(this.wireIndex, this.blockedReason);

  /// The wire index, or null when the parameter is BLOCKED.
  final int? wireIndex;

  /// Why the parameter is blocked (machine code first), or null.
  final String? blockedReason;

  bool get blocked => wireIndex == null;

  /// [id] is the manufacturer ID of this parameter, [allIds] the IDs of every
  /// parameter of the same algorithm (to detect duplicates).
  static ParameterAddress resolve(int? id, Iterable<int?> allIds) {
    if (id == null) return const ParameterAddress._(null, 'ID_MISSING: keine gültige Hersteller-ID');
    if (id <= 0) return ParameterAddress._(null, 'ID_INVALID: Hersteller-ID $id ist nicht positiv');
    if (allIds.where((other) => other == id).length > 1) {
      return ParameterAddress._(null, 'ID_DUPLICATE: Hersteller-ID $id kommt im Algorithmus mehrfach vor');
    }
    final wire = matriboxWireParameterIndex(id);
    if (wire >= matriboxParametersPerBlock) {
      return ParameterAddress._(null, 'ID_OUT_OF_RANGE: Wire-Index $wire passt nicht in einen Block');
    }
    return ParameterAddress._(wire, null);
  }
}
