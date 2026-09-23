/// Product-level Matribox catalog for tone transfer: semantic parameter
/// names, model lookup and the PROTOCOL evidence per model/parameter.
///
/// Product code never sees wire indices. It works with a chain slot, a
/// [MatriboxTransferModel] and a semantic parameter name (`gain`, `bass`,
/// `middle`, `treble`, `mix`, `rate`, `depth`, `threshold`, `trail`, ...);
/// this file (and only this layer) resolves them to the confirmed wire
/// parameter that [MatriboxChainEncoder] needs. The wire index is always
/// `manufacturer ID - 1` (matribox_parameter_addressing.dart); there is no
/// CAB special case any more.
///
/// Protocol evidence is separate from hardware evidence
/// (matribox_hardware_evidence.dart):
/// - [TransferProtocolEvidence.captureConfirmed]: a real editor message of
///   exactly this kind exists and the offline encoder reproduces it byte for
///   byte.
/// - [TransferProtocolEvidence.correlated]: the identity is known from
///   device reads / the local editor XML, but no such message was captured.
/// - [TransferProtocolEvidence.observed]: catalog (XML) only.
library;

import 'matribox_chain_catalog.dart';
import 'matribox_chain_slot.dart';

enum TransferProtocolEvidence { captureConfirmed, correlated, observed }

/// Editor labels that have a fixed semantic name. Everything else falls back
/// to the lower-cased label without spaces (`Swp Depth` -> `swpdepth`).
const _semanticOverrides = <String, String>{
  'Gain': 'gain',
  'PRES': 'presence',
  'Master': 'volume',
  'VOL': 'volume',
  'Bass': 'bass',
  'Middle': 'middle',
  'Treble': 'treble',
  'Tone': 'tone',
  'THRE': 'threshold',
  'ATK': 'attack',
  'Rel': 'release',
  'Mix': 'mix',
  'Rate': 'rate',
  'Depth': 'depth',
  'FdBk': 'feedback',
  'PreDly': 'predelay',
  'Pre Delay': 'predelay',
  'Decay': 'decay',
  'Time': 'time',
  'Trail': 'trail',
  'Sync': 'sync',
};

String matriboxSemanticName(String catalogName) =>
    _semanticOverrides[catalogName] ?? catalogName.toLowerCase().replaceAll(' ', '');

class MatriboxTransferModel {
  const MatriboxTransferModel({
    required this.algorithm,
    required this.selectEvidence,
    required this.parameterEvidence,
    this.selectable = true,
    this.note,
  });

  final MatriboxChainAlgorithm algorithm;
  final TransferProtocolEvidence selectEvidence;
  final TransferProtocolEvidence parameterEvidence;

  /// False for entries that exist only as documentation (User IR).
  final bool selectable;
  final String? note;

  String get name => algorithm.name;
  int get code => algorithm.code;

  /// Confirmed wire parameter for a semantic name, or null.
  MatriboxChainParameter? parameter(String semantic) => algorithm.parameters
      .where((p) => matriboxSemanticName(p.name) == semantic)
      .firstOrNull;
}

const _ampNames = ['Gain', 'PRES', 'Master', 'Bass', 'Middle', 'Treble'];

MatriboxChainAlgorithm _sol100(String id, String name, int code) => MatriboxChainAlgorithm(
  id: id,
  name: name,
  code: code,
  slots: {MatriboxChainSlot.amp},
  parameters: [
    for (var i = 0; i < _ampNames.length; i++)
      MatriboxChainParameter(
        name: _ampNames[i],
        wireIndex: i,
        catalogIndex: i,
        kind: MatriboxParameterKind.number,
      ),
  ],
);

/// Sol 100 OD: the code 0x07000047 is read from real P01 backups and the
/// six parameter messages are in the original store capture (Gain and
/// Presence were additionally sent by WyrmTone). No MODEL SELECT message for
/// this code was ever captured, so selecting it is only CORRELATED.
final matriboxSol100Od = _sol100('sol100Od', 'Sol 100 OD', 0x07000047);

/// Sol 100 LD: XML catalog only.
final matriboxSol100Ld = _sol100('sol100Ld', 'Sol 100 LD', 0x07000059);

abstract final class MatriboxTransferCatalog {
  static final models = List<MatriboxTransferModel>.unmodifiable([
    for (final a in matriboxCaptureConfirmedAlgorithms)
      MatriboxTransferModel(
        algorithm: a,
        selectEvidence: a.sendableInFullLive
            ? TransferProtocolEvidence.captureConfirmed
            : TransferProtocolEvidence.correlated,
        parameterEvidence: TransferProtocolEvidence.captureConfirmed,
        selectable: a.sendableInFullLive,
        note: a.note,
      ),
    MatriboxTransferModel(
      algorithm: matriboxSol100Od,
      selectEvidence: TransferProtocolEvidence.correlated,
      parameterEvidence: TransferProtocolEvidence.captureConfirmed,
      note: 'Code aus Geräte-Reads; kein MODEL-SELECT-Capture für diesen Code.',
    ),
    MatriboxTransferModel(
      algorithm: matriboxSol100Ld,
      selectEvidence: TransferProtocolEvidence.observed,
      parameterEvidence: TransferProtocolEvidence.observed,
      note: 'Nur lokaler Editor-Katalog; weder gelesen noch gecaptured.',
    ),
  ]);

  static MatriboxTransferModel? byName(String? name) =>
      models.where((m) => m.name == name).firstOrNull;

  static MatriboxTransferModel? byCode(MatriboxChainSlot slot, int code) => models
      .where((m) => m.code == code && m.algorithm.slots.contains(slot))
      .firstOrNull;
}
