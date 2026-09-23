/// Sol 100 OD AMP hardware certification model: a closed field type, the
/// fixed certification order, persisted per-field results and the +/-1
/// certification target.
///
/// This is Lab logic, not product logic. A certification result shown or
/// stored here NEVER changes [MatriboxAmpFieldEvidenceRegistry] -- raising a
/// field's `writeEvidence` is a separate, manual development step after
/// the hardware test has been evaluated (no self-certification). Nothing
/// in this file sends anything.
library;

import 'dart:convert';
import 'dart:io';

import 'matribox_amp_field_evidence.dart';
import 'matribox_semantic_preset.dart';

/// The closed set of Sol 100 OD AMP knobs. The parameter index is derived
/// from [MatriboxAmpFieldEvidenceRegistry], never supplied by a caller.
enum MatriboxSol100OdAmpField {
  gain('gain'),
  presence('presence'),
  volume('volume'),
  bass('bass'),
  middle('middle'),
  treble('treble');

  const MatriboxSol100OdAmpField(this.wireName);

  final String wireName;

  MatriboxAmpFieldEvidence get evidence =>
      MatriboxAmpFieldEvidenceRegistry.forField(wireName)!;

  int get parameterIndex => evidence.catalogIndex;

  static MatriboxSol100OdAmpField? fromWireName(String? name) {
    for (final field in values) {
      if (field.wireName == name) return field;
    }
    return null;
  }
}

/// Fixed certification order. Gain is not in the list: it is certified.
const matriboxCertificationOrder = <MatriboxSol100OdAmpField>[
  MatriboxSol100OdAmpField.presence,
  MatriboxSol100OdAmpField.volume,
  MatriboxSol100OdAmpField.bass,
  MatriboxSol100OdAmpField.middle,
  MatriboxSol100OdAmpField.treble,
];

enum MatriboxCertificationRecordState {
  /// One write was sent. Not certified: readback still outstanding.
  writeSent,

  /// Readback verified the expected change and nothing else.
  certified,

  /// Readback ran but did not certify (see [MatriboxCertificationRecord.readbackOutcome]).
  readbackFailed,
}

class MatriboxCertificationRecord {
  const MatriboxCertificationRecord({
    required this.field,
    required this.state,
    required this.beforeValue,
    required this.targetValue,
    required this.beforeBackupPath,
    required this.beforeBackupSha256,
    required this.writeSentAt,
    this.readbackOutcome,
    this.readbackAt,
    this.afterBackupSha256,
  });

  final MatriboxSol100OdAmpField field;
  final MatriboxCertificationRecordState state;
  final double beforeValue;
  final double targetValue;
  final String beforeBackupPath;
  final String beforeBackupSha256;
  final DateTime writeSentAt;
  final String? readbackOutcome;
  final DateTime? readbackAt;
  final String? afterBackupSha256;

  MatriboxCertificationRecord withReadback({
    required MatriboxCertificationRecordState state,
    required String outcome,
    required DateTime at,
    String? afterSha256,
  }) => MatriboxCertificationRecord(
    field: field,
    state: state,
    beforeValue: beforeValue,
    targetValue: targetValue,
    beforeBackupPath: beforeBackupPath,
    beforeBackupSha256: beforeBackupSha256,
    writeSentAt: writeSentAt,
    readbackOutcome: outcome,
    readbackAt: at,
    afterBackupSha256: afterSha256,
  );

  Map<String, Object?> toJson() => {
    'field': field.wireName,
    'state': state.name,
    'beforeValue': beforeValue,
    'targetValue': targetValue,
    'beforeBackupPath': beforeBackupPath,
    'beforeBackupSha256': beforeBackupSha256,
    'writeSentAt': writeSentAt.toUtc().toIso8601String(),
    'readbackOutcome': readbackOutcome,
    'readbackAt': readbackAt?.toUtc().toIso8601String(),
    'afterBackupSha256': afterBackupSha256,
  };

  static MatriboxCertificationRecord? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final field = MatriboxSol100OdAmpField.fromWireName(json['field'] as String?);
    final state = MatriboxCertificationRecordState.values
        .where((s) => s.name == json['state'])
        .firstOrNull;
    final before = json['beforeValue'];
    final target = json['targetValue'];
    final path = json['beforeBackupPath'];
    final sha = json['beforeBackupSha256'];
    final sent = DateTime.tryParse('${json['writeSentAt']}');
    if (field == null ||
        state == null ||
        before is! num ||
        target is! num ||
        path is! String ||
        sha is! String ||
        sent == null) {
      return null;
    }
    return MatriboxCertificationRecord(
      field: field,
      state: state,
      beforeValue: before.toDouble(),
      targetValue: target.toDouble(),
      beforeBackupPath: path,
      beforeBackupSha256: sha,
      writeSentAt: sent,
      readbackOutcome: json['readbackOutcome'] as String?,
      readbackAt: DateTime.tryParse('${json['readbackAt']}'),
      afterBackupSha256: json['afterBackupSha256'] as String?,
    );
  }
}

/// Small local JSON file holding one record per field (latest wins). It
/// keeps the BEFORE-backup reference across app restarts and USB
/// reconnects, which the manual save/reconnect/readback steps require.
class MatriboxCertificationStore {
  const MatriboxCertificationStore(this.file);

  final File file;

  Future<List<MatriboxCertificationRecord>> load() async {
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['records'] is! List) return const [];
      return [
        for (final item in decoded['records'] as List)
          ?MatriboxCertificationRecord.tryFromJson(item),
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> save(MatriboxCertificationRecord record) async {
    final records = [
      for (final r in await load())
        if (r.field != record.field) r,
      record,
    ];
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'records': [for (final r in records) r.toJson()],
      }),
      flush: true,
    );
  }
}

enum MatriboxCertificationStatus {
  /// Hardware-certified (Gain via static evidence, others via a stored
  /// CERTIFIED readback result in this lab session store).
  certified,

  /// Next field in the fixed order; may be prepared and tested now.
  readyForHardwareTest,

  /// Earlier field in the order is not certified yet.
  waiting,

  /// One write was sent; the readback check is outstanding.
  writeSentAwaitingReadback,

  /// Readback ran and did not certify. Needs analysis before retrying.
  readbackFailed,
}

abstract final class MatriboxCertification {
  static MatriboxCertificationRecord? _recordFor(
    MatriboxSol100OdAmpField field,
    List<MatriboxCertificationRecord> records,
  ) {
    for (final record in records) {
      if (record.field == field) return record;
    }
    return null;
  }

  /// Gain (static evidence) and any field whose stored readback result is
  /// CERTIFIED count as certified for ordering purposes.
  static bool isCertified(
    MatriboxSol100OdAmpField field,
    List<MatriboxCertificationRecord> records,
  ) {
    if (field.evidence.hardwareWritable &&
        field.evidence.readbackAfterWriteEvidence.name == 'confirmed') {
      return true;
    }
    return _recordFor(field, records)?.state ==
        MatriboxCertificationRecordState.certified;
  }

  static MatriboxCertificationStatus statusFor(
    MatriboxSol100OdAmpField field,
    List<MatriboxCertificationRecord> records,
  ) {
    if (isCertified(field, records)) return MatriboxCertificationStatus.certified;
    final record = _recordFor(field, records);
    if (record?.state == MatriboxCertificationRecordState.writeSent) {
      return MatriboxCertificationStatus.writeSentAwaitingReadback;
    }
    if (!matriboxCertificationOrder.contains(field)) {
      return MatriboxCertificationStatus.waiting;
    }
    final earlier = matriboxCertificationOrder.takeWhile((f) => f != field);
    if (earlier.any((f) => !isCertified(f, records))) {
      return MatriboxCertificationStatus.waiting;
    }
    return record?.state == MatriboxCertificationRecordState.readbackFailed
        ? MatriboxCertificationStatus.readbackFailed
        : MatriboxCertificationStatus.readyForHardwareTest;
  }

  /// Why [field] may not be prepared/written now, or null if it may.
  /// A field whose earlier readback failed is deliberately not eligible
  /// again until the failure was analysed and the store entry reset.
  static String? blockReason(
    MatriboxSol100OdAmpField field,
    List<MatriboxCertificationRecord> records,
  ) {
    if (!matriboxCertificationOrder.contains(field)) {
      return 'Gain ist bereits zertifiziert und wird nicht erneut getestet.';
    }
    final evidence = field.evidence;
    if (!evidence.encodable ||
        evidence.rawWriteCaptureEvidence.name != 'confirmed' ||
        evidence.indexEvidence.name != 'confirmed') {
      return 'Feld ist nicht capture-bestätigt.';
    }
    return switch (statusFor(field, records)) {
      MatriboxCertificationStatus.readyForHardwareTest => null,
      MatriboxCertificationStatus.certified =>
        'Feld ist bereits zertifiziert.',
      MatriboxCertificationStatus.waiting =>
        'Falsche Reihenfolge: vorherige Felder sind noch nicht zertifiziert.',
      MatriboxCertificationStatus.writeSentAwaitingReadback =>
        'Ein Write wurde gesendet; zuerst den Readback prüfen.',
      MatriboxCertificationStatus.readbackFailed =>
        'Der letzte Readback hat nicht zertifiziert; erst analysieren.',
    };
  }
}

const matriboxCertificationMinimum = 0.0;
const matriboxCertificationMaximum = 99.0;

class UnsupportedCertificationTarget implements Exception {
  const UnsupportedCertificationTarget(this.message);
  final String message;
  @override
  String toString() => 'UnsupportedCertificationTarget: $message';
}

/// Certification/Lab target: current + 1, or current - 1 at the maximum.
/// NOT recommendation logic; never use this for a real song write.
abstract final class MatriboxCertificationTarget {
  static double targetFor(double current) => current >= matriboxCertificationMaximum
      ? current - 1
      : (current + 1).clamp(matriboxCertificationMinimum, matriboxCertificationMaximum);

  static MatriboxKnownField? currentField(
    MatriboxSemanticPreset preset,
    MatriboxSol100OdAmpField field,
  ) => preset.amp?.fieldsByName[field.wireName];

  /// [current] carrying the one-field target; every other field unchanged.
  static MatriboxSemanticPreset build(
    MatriboxSemanticPreset current,
    MatriboxSol100OdAmpField field,
  ) {
    final amp = current.amp;
    final knownField = currentField(current, field);
    if (amp == null || knownField == null) {
      throw UnsupportedCertificationTarget(
        'Aktuelles Preset hat keinen bekannten ${field.wireName}-Wert.',
      );
    }
    final evidence = field.evidence;
    final target = MatriboxKnownField(
      value: targetFor(knownField.value),
      identityEvidence: evidence.readEvidence,
      writeEvidence: evidence.writeEvidence,
      catalogIndex: evidence.catalogIndex,
    );
    return MatriboxSemanticPreset(
      name: current.name,
      amp: MatriboxAmpBlock(
        algorithmName: amp.algorithmName,
        algorithmCode: amp.algorithmCode,
        algorithmEvidence: amp.algorithmEvidence,
        gain: field == MatriboxSol100OdAmpField.gain ? target : amp.gain,
        presence: field == MatriboxSol100OdAmpField.presence ? target : amp.presence,
        volume: field == MatriboxSol100OdAmpField.volume ? target : amp.volume,
        bass: field == MatriboxSol100OdAmpField.bass ? target : amp.bass,
        middle: field == MatriboxSol100OdAmpField.middle ? target : amp.middle,
        treble: field == MatriboxSol100OdAmpField.treble ? target : amp.treble,
      ),
    );
  }
}
