import 'canonical_preset.dart';
import 'device_catalog.dart';
import 'protocol_evidence.dart';

enum IssueSeverity { error, warning, information }

enum BlockReadiness {
  ready,
  manualOnly,
  unsupported,
  unclear,
  missingLocalFile,
}

class PresetIssue {
  const PresetIssue(
    this.code,
    this.severity,
    this.message, {
    this.blockId,
    this.parameterId,
  });
  final String code, message;
  final String? blockId, parameterId;
  final IssueSeverity severity;
  Map<String, Object?> toJson() => {
    'code': code,
    'severity': severity.name,
    'message': message,
    'blockId': blockId,
    'parameterId': parameterId,
  };
}

class PresetValidation {
  PresetValidation(List<PresetIssue> issues, Map<String, BlockReadiness> blocks)
    : issues = List.unmodifiable(issues),
      blocks = Map.unmodifiable(blocks);
  final List<PresetIssue> issues;
  final Map<String, BlockReadiness> blocks;
  bool get exportAllowed =>
      !issues.any((i) => i.severity == IssueSeverity.error);
  bool get transferAllowed => false;
  String get status => !exportAllowed
      ? 'Nicht exportierbar'
      : issues.any((i) => i.severity == IssueSeverity.warning)
      ? 'Mit Warnungen'
      : 'Gültiger Offline-Entwurf';
  String get transferStatus => 'Noch nicht für Geräteübertragung freigegeben';
  Map<String, Object?> toJson() => {
    'status': status,
    'exportAllowed': exportAllowed,
    'transferAllowed': false,
    'transferStatus': transferStatus,
    'blocks': blocks.map((k, v) => MapEntry(k, v.name)),
    'issues': issues.map((i) => i.toJson()).toList(),
  };
}

class PresetValidator {
  const PresetValidator(this.catalog);
  final DevicePresetCatalog catalog;
  PresetValidation validate(
    CanonicalPreset preset, {
    Set<String> availableAssetHashes = const {},
  }) {
    final issues = <PresetIssue>[];
    final statuses = <String, BlockReadiness>{};
    void issue(
      String code,
      IssueSeverity severity,
      String text, [
      String? block,
      String? parameter,
    ]) {
      issues.add(
        PresetIssue(
          code,
          severity,
          text,
          blockId: block,
          parameterId: parameter,
        ),
      );
    }

    if (preset.schemaVersion != CanonicalPreset.currentSchemaVersion) {
      issue('schema', IssueSeverity.error, 'Unbekannte Preset-Version.');
    }
    if (preset.name.trim().isEmpty) {
      issue('name', IssueSeverity.error, 'Presetname fehlt.');
    }
    if (!['matriboxOne', 'dnafxGitCore'].contains(preset.targetDevice)) {
      issue('device', IssueSeverity.error, 'Nicht unterstütztes Zielgerät.');
    }
    if (!['rhythm', 'lead', 'clean'].contains(preset.role)) {
      issue('role', IssueSeverity.error, 'Unbekannte Rolle.');
    }
    if (preset.modifiedAt.isBefore(preset.createdAt)) {
      issue('time', IssueSeverity.error, 'Ungültige Zeitfolge.');
    }
    final ids = <String>{}, orders = <int>{};
    var lastOrder = -1;
    for (final block in preset.blocks) {
      var readiness = BlockReadiness.manualOnly;
      if (block.id.trim().isEmpty || !ids.add(block.id)) {
        issue(
          'blockId',
          IssueSeverity.error,
          'Leere/doppelte Block-ID.',
          block.id,
        );
      }
      if (block.order < 0 ||
          !orders.add(block.order) ||
          block.order <= lastOrder) {
        issue(
          'order',
          IssueSeverity.error,
          'Ungültige Blockreihenfolge.',
          block.id,
        );
      }
      lastOrder = block.order;
      final algorithm = preset.targetDevice == 'matriboxOne'
          ? catalog.find(block.model)
          : null;
      if (block.model != null &&
          algorithm == null &&
          preset.targetDevice == 'matriboxOne') {
        issue(
          'algorithm',
          IssueSeverity.warning,
          'Algorithmus nicht eindeutig im Gerätekatalog.',
          block.id,
        );
        readiness = BlockReadiness.unclear;
      }
      if (algorithm != null &&
          block.algorithmCode != null &&
          block.algorithmCode != algorithm.code) {
        issue(
          'algorithmCode',
          IssueSeverity.error,
          'Algorithmuscode widerspricht Katalog.',
          block.id,
        );
      }
      if (algorithm?.data['conflict'] == true) {
        issue(
          'catalogConflict',
          IssueSeverity.warning,
          'Widersprüchliche Algorithmus-Metadaten.',
          block.id,
        );
        readiness = BlockReadiness.unclear;
      }
      final parameterIds = <String>{};
      for (final parameter in block.parameters) {
        if (parameter.id.trim().isEmpty || !parameterIds.add(parameter.id)) {
          issue(
            'parameterId',
            IssueSeverity.error,
            'Leere/doppelte Parameter-ID.',
            block.id,
            parameter.id,
          );
        }
        final spec = algorithm?.parameter(parameter.name);
        if (algorithm != null && spec == null) {
          issue(
            'parameterMember',
            IssueSeverity.error,
            'Parameter gehört nicht zum Algorithmus.',
            block.id,
            parameter.id,
          );
        }
        if (spec != null &&
            parameter.deviceIndex != null &&
            parameter.deviceIndex != spec.index) {
          issue(
            'parameterIndex',
            IssueSeverity.error,
            'Parameterindex widerspricht Katalog.',
            block.id,
            parameter.id,
          );
        }
        if (parameter.deviceIndex == null ||
            parameter.evidence != EvidenceLevel.confirmed) {
          issue(
            'indexUnconfirmed',
            IssueSeverity.warning,
            'Parameterindex nicht für allgemeines Schreiben bestätigt.',
            block.id,
            parameter.id,
          );
        }
        final minimum = spec?.minimum ?? parameter.minimum,
            maximum = spec?.maximum ?? parameter.maximum;
        final step = spec?.step ?? parameter.step;
        if (!parameter.value.isFinite ||
            [
              parameter.minimum,
              parameter.maximum,
              parameter.step,
              parameter.originalValue,
            ].whereType<num>().any((v) => !v.isFinite)) {
          issue(
            'finite',
            IssueSeverity.error,
            'Nicht endlicher Parameterwert.',
            block.id,
            parameter.id,
          );
        } else {
          if ((minimum != null && parameter.value < minimum) ||
              (maximum != null && parameter.value > maximum) ||
              (minimum != null && maximum != null && minimum > maximum)) {
            issue(
              'range',
              IssueSeverity.error,
              'Parameter außerhalb des Wertebereichs.',
              block.id,
              parameter.id,
            );
          }
          if (step != null &&
              (step <= 0 ||
                  (((parameter.value - (minimum ?? 0)) / step) -
                              ((parameter.value - (minimum ?? 0)) / step)
                                  .round())
                          .abs() >
                      0.000001)) {
            issue(
              'step',
              IssueSeverity.error,
              'Ungültige Schrittweite.',
              block.id,
              parameter.id,
            );
          }
          if (parameter.dataType == ParameterDataType.integer &&
                  parameter.value != parameter.value.round() ||
              parameter.dataType == ParameterDataType.boolean &&
                  parameter.value != 0 &&
                  parameter.value != 1) {
            issue(
              'dataType',
              IssueSeverity.error,
              'Wert passt nicht zum Datentyp.',
              block.id,
              parameter.id,
            );
          }
        }
        if (spec?.data['conflict'] == true) {
          issue(
            'parameterConflict',
            IssueSeverity.warning,
            'Widersprüchliche Parameter-Metadaten; keine Schreibfreigabe.',
            block.id,
            parameter.id,
          );
        }
      }
      if (block.type == PresetBlockType.nam &&
          preset.targetDevice == 'dnafxGitCore') {
        readiness = BlockReadiness.unsupported;
        issue(
          'namUnsupported',
          IssueSeverity.warning,
          'DNAfx unterstützt kein NAM.',
          block.id,
        );
      }
      if (block.enabled &&
          [PresetBlockType.nam, PresetBlockType.cab].contains(block.type)) {
        final asset = block.type == PresetBlockType.nam
            ? preset.nam
            : preset.ir;
        if (asset == null) {
          readiness = BlockReadiness.unclear;
          issue(
            'assetUnassigned',
            IssueSeverity.warning,
            'NAM/Cab/IR-Zuordnung ungeklärt.',
            block.id,
          );
        } else if (asset.sha256 == null ||
            !availableAssetHashes.contains(asset.sha256)) {
          readiness = BlockReadiness.missingLocalFile;
          issue(
            'assetMissing',
            IssueSeverity.warning,
            'Lokale Datei nicht nachgewiesen.',
            block.id,
          );
        }
      }
      statuses[block.id] = readiness;
    }
    if (preset.nam != null && preset.nam!.architecture != 'a1') {
      issue(
        'namArchitecture',
        IssueSeverity.warning,
        'NAM-Architektur nicht kompatibel bestätigt.',
      );
    }
    if (preset.nam?.cabinetContent == 'unknown') {
      issue(
        'cabinetUnknown',
        IssueSeverity.warning,
        'Cabinet-Inhalt des NAM ungeklärt.',
      );
    }
    issue(
      'transferBlocked',
      IssueSeverity.information,
      ProtocolEvidenceRegistry.decide('preset.transfer').reason,
    );
    return PresetValidation(issues, statuses);
  }
}
