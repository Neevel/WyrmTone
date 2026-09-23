/// The single source of truth for what is actually known about each of the
/// six confirmed Sol-100-OD AMP fields -- kept strictly separate per
/// dimension so evidence for one question is never silently reused to
/// answer a different one:
///
/// - READ:  is the field's value confirmed decodable from a full-preset
///   readback ([RawPresetSnapshot]/`p01_readback_decoder.dart`)?
/// - INDEX: is the field's `ConfirmedParameterCodec` parameter index
///   (the address used by the *single-parameter write* message family)
///   confirmed or only correlated (known from catalog/capture, but not
///   independently write-tested)?
/// - WRITE: has an actual device write via that index been hardware-
///   confirmed to change the device (currently only Sol-100-OD Gain,
///   40->41, via `ConfirmedParameterCodec`/the historical Gain-41 probe)?
/// - STORE: is persistence via a QME2 *protocol* store command confirmed?
///   See docs/MATRIBOX_OFFLINE_ANALYSIS.md, "STORE-Wiederauswertung" --
///   currently BLOCKED/unknown for every field; no store command is
///   isolated with sufficient confidence, and WyrmTone has never sent one.
/// - MANUAL SAVE PERSISTENCE: is persistence confirmed after the *user*
///   saved the change via the device's own physical Save function (not a
///   WyrmTone/QME2 command), followed by a USB reconnect and a fresh
///   productive read? This is a strictly weaker, separate claim from
///   STORE -- it says nothing about whether a QME2 store message exists or
///   works, only that a value WyrmTone wrote plus a manual physical save
///   was observed to survive a reconnect.
///
/// `MatriboxPresetDecoder`, `MatriboxPresetTranslator` and
/// `MatriboxPresetWritePlanner` all consult this registry instead of
/// hardcoding per-field evidence themselves, so raising a field's evidence
/// (e.g. once Presence write is hardware-confirmed) happens in exactly one
/// place.
library;

import 'protocol_evidence.dart';

class MatriboxAmpFieldEvidence {
  const MatriboxAmpFieldEvidence({
    required this.field,
    required this.catalogIndex,
    required this.readEvidence,
    required this.indexEvidence,
    required this.writeEvidence,
    required this.storeEvidence,
    this.manualSavePersistenceEvidence = EvidenceLevel.unknown,
    this.rawWriteCaptureEvidence = EvidenceLevel.unknown,
    this.encodeEvidence = EvidenceLevel.unknown,
    this.readbackAfterWriteEvidence = EvidenceLevel.unknown,
  });

  /// Wire-protocol field name (`gain`, `presence`, `volume`, `bass`,
  /// `middle`, `treble`).
  final String field;

  /// The Sol-100-OD parameter index addressed by
  /// `ConfirmedParameterCodec`/`encodeMessageBytes`.
  final int catalogIndex;

  /// Confirmed via the full-preset-readback wire family (parts 0-9).
  final EvidenceLevel readEvidence;

  /// Confirmed/correlated that [catalogIndex] is this field's address in
  /// the single-parameter write/read message family.
  final EvidenceLevel indexEvidence;

  /// Hardware-confirmed that writing this field via [catalogIndex] changes
  /// the device (independent of the read side).
  final EvidenceLevel writeEvidence;

  /// Hardware-confirmed that a write to this field, once stored, survives
  /// a reconnect. See docs/MATRIBOX_OFFLINE_ANALYSIS.md,
  /// "STORE-Wiederauswertung" -- currently unknown for every field, since
  /// no store command is isolated with sufficient confidence, regardless
  /// of whether the field itself is writable.
  final EvidenceLevel storeEvidence;

  /// Hardware-confirmed that a WyrmTone write to this field survived a
  /// reconnect after the user manually saved via the device's own physical
  /// Save function -- NOT via any WyrmTone/QME2 store message. Independent
  /// of [storeEvidence]; confirming this never upgrades [storeEvidence].
  final EvidenceLevel manualSavePersistenceEvidence;

  /// A real host->device message for this field exists in an original
  /// editor capture (matribox1_p01_store.pcapng, extracted programmatically)
  /// -- says nothing about whether WyrmTone ever sent it.
  final EvidenceLevel rawWriteCaptureEvidence;

  /// WyrmTone's offline encoder reproduces real captured messages of this
  /// field byte-for-byte (see test/matribox_sol100od_encoder_test.dart).
  /// Independent of [writeEvidence].
  final EvidenceLevel encodeEvidence;

  /// After a WyrmTone-sent write, a fresh production read confirmed the new
  /// value. Only Gain has been hardware-tested.
  final EvidenceLevel readbackAfterWriteEvidence;

  /// The offline encoder may build this field's message. NOT permission to
  /// send it: see [hardwareWritable].
  bool get encodable => encodeEvidence == EvidenceLevel.confirmed;

  /// The value can be decoded and displayed at all.
  bool get readable => readEvidence != EvidenceLevel.unknown;

  /// The value can appear in a [MatriboxSemanticPreset] built from a
  /// translated `CanonicalPreset` (requires knowing where it would go, not
  /// that it is writable).
  bool get translatable => indexEvidence != EvidenceLevel.unknown;

  /// The field may appear in a [MatriboxPresetWritePlan] as a considered
  /// operation at all (still possibly `blocked` there for other reasons).
  bool get writePlannable => translatable;

  /// The field may actually be marked `writable` in a write plan.
  bool get hardwareWritable => writeEvidence == EvidenceLevel.confirmed;

  /// A write to this field, even if [hardwareWritable], is not yet known
  /// to persist across a reconnect via the QME2 protocol itself (no store
  /// message sent by WyrmTone).
  bool get persistenceConfirmed => storeEvidence == EvidenceLevel.confirmed;

  /// A write to this field has been observed to survive a reconnect after
  /// the user manually saved it on the device itself.
  bool get manualSavePersistenceConfirmed =>
      manualSavePersistenceEvidence == EvidenceLevel.confirmed;

  Map<String, Object?> toJson() => {
    'field': field,
    'catalogIndex': catalogIndex,
    'readEvidence': readEvidence.name,
    'indexEvidence': indexEvidence.name,
    'writeEvidence': writeEvidence.name,
    'storeEvidence': storeEvidence.name,
    'manualSavePersistenceEvidence': manualSavePersistenceEvidence.name,
    'rawWriteCaptureEvidence': rawWriteCaptureEvidence.name,
    'encodeEvidence': encodeEvidence.name,
    'readbackAfterWriteEvidence': readbackAfterWriteEvidence.name,
    'encodable': encodable,
    'readable': readable,
    'translatable': translatable,
    'writePlannable': writePlannable,
    'hardwareWritable': hardwareWritable,
    'persistenceConfirmed': persistenceConfirmed,
    'manualSavePersistenceConfirmed': manualSavePersistenceConfirmed,
  };
}

abstract final class MatriboxAmpFieldEvidenceRegistry {
  static const gain = MatriboxAmpFieldEvidence(
    field: 'gain',
    catalogIndex: 0,
    readEvidence: EvidenceLevel.confirmed,
    indexEvidence: EvidenceLevel.confirmed,
    // Sol-100-OD Gain 40->41 via ConfirmedParameterCodec, the historical
    // Gain-41 probe; and, in the first productive hardware write (17->18
    // via MatriboxConfirmedGainWriter through the Safe Write Lab), a
    // hardware-confirmed device value change plus a confirmed readback via
    // the production read path. See docs/MATRIBOX_OFFLINE_ANALYSIS.md,
    // "Erster produktiver WyrmTone-Hardware-Write".
    writeEvidence: EvidenceLevel.confirmed,
    // QME2 STORE remains unknown/blocked -- WyrmTone has never sent a
    // store message. Do not confuse with manualSavePersistenceEvidence
    // below.
    storeEvidence: EvidenceLevel.unknown,
    // The user saved the 17->18 change via the device's own physical Save
    // function, then reconnected; a fresh productive WyrmTone read
    // afterwards confirmed Gain=18 persisted. This says nothing about a
    // QME2 store command.
    manualSavePersistenceEvidence: EvidenceLevel.confirmed,
    rawWriteCaptureEvidence: EvidenceLevel.confirmed,
    encodeEvidence: EvidenceLevel.confirmed,
    readbackAfterWriteEvidence: EvidenceLevel.confirmed,
  );
  static const presence = MatriboxAmpFieldEvidence(
    field: 'presence',
    catalogIndex: 1,
    readEvidence: EvidenceLevel.confirmed,
    // Index confirmed by the original store capture: each index group's
    // final value equals the named marker value AND the full-preset
    // readback shows the same value at the same knob position
    // (docs, "Sol 100 OD: vollständige AMP-Write-Evidenz").
    indexEvidence: EvidenceLevel.confirmed,
    writeEvidence: EvidenceLevel.unknown,
    storeEvidence: EvidenceLevel.unknown,
    rawWriteCaptureEvidence: EvidenceLevel.confirmed,
    encodeEvidence: EvidenceLevel.confirmed,
  );
  static const volume = MatriboxAmpFieldEvidence(
    field: 'volume',
    catalogIndex: 2,
    readEvidence: EvidenceLevel.confirmed,
    indexEvidence: EvidenceLevel.confirmed,
    writeEvidence: EvidenceLevel.unknown,
    storeEvidence: EvidenceLevel.unknown,
    rawWriteCaptureEvidence: EvidenceLevel.confirmed,
    encodeEvidence: EvidenceLevel.confirmed,
  );
  static const bass = MatriboxAmpFieldEvidence(
    field: 'bass',
    catalogIndex: 3,
    readEvidence: EvidenceLevel.confirmed,
    indexEvidence: EvidenceLevel.confirmed,
    writeEvidence: EvidenceLevel.unknown,
    storeEvidence: EvidenceLevel.unknown,
    rawWriteCaptureEvidence: EvidenceLevel.confirmed,
    encodeEvidence: EvidenceLevel.confirmed,
  );
  static const middle = MatriboxAmpFieldEvidence(
    field: 'middle',
    catalogIndex: 4,
    readEvidence: EvidenceLevel.confirmed,
    indexEvidence: EvidenceLevel.confirmed,
    writeEvidence: EvidenceLevel.unknown,
    storeEvidence: EvidenceLevel.unknown,
    rawWriteCaptureEvidence: EvidenceLevel.confirmed,
    encodeEvidence: EvidenceLevel.confirmed,
  );
  static const treble = MatriboxAmpFieldEvidence(
    field: 'treble',
    catalogIndex: 5,
    readEvidence: EvidenceLevel.confirmed,
    indexEvidence: EvidenceLevel.confirmed,
    writeEvidence: EvidenceLevel.unknown,
    storeEvidence: EvidenceLevel.unknown,
    rawWriteCaptureEvidence: EvidenceLevel.confirmed,
    encodeEvidence: EvidenceLevel.confirmed,
  );

  static const all = <MatriboxAmpFieldEvidence>[
    gain,
    presence,
    volume,
    bass,
    middle,
    treble,
  ];

  static MatriboxAmpFieldEvidence? forField(String field) =>
      all.where((f) => f.field == field).firstOrNull;
}
