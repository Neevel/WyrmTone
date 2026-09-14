import 'canonical_preset.dart';
import 'preset_backup.dart';
import 'preset_exchange.dart';
import 'preset_diff.dart';
import 'preset_validation.dart';
import 'protocol_evidence.dart';

enum PresetSlotSource { manual, officialReference, unknown }

class PresetSlot {
  const PresetSlot({
    required this.id,
    required this.bank,
    required this.position,
    required this.label,
    required this.currentName,
    required this.source,
    this.readAt,
    this.currentPreset,
    this.backupId,
    this.protected = true,
  });
  final String id, bank, position, label, currentName;
  final PresetSlotSource source;
  final DateTime? readAt;
  final CanonicalPreset? currentPreset;
  final String? backupId;
  final bool protected;
  bool get fullContentKnown => currentPreset != null;
  bool get localBackupPresent => backupId != null;
}

class PresetWritePlan {
  PresetWritePlan({
    required this.targetDevice,
    required this.slot,
    required this.expectedStart,
    required this.backup,
    required List<PresetChange> changes,
    required List<CapabilityDecision> requiredCapabilities,
    required List<String> blockers,
    required List<String> warnings,
  }) : changes = List.unmodifiable(changes),
       requiredCapabilities = List.unmodifiable(requiredCapabilities),
       blockers = List.unmodifiable(blockers),
       warnings = List.unmodifiable(warnings);
  final String targetDevice;
  final PresetSlot? slot;
  final CanonicalPreset? expectedStart;
  final PresetBackup? backup;
  final List<PresetChange> changes;
  final List<CapabilityDecision> requiredCapabilities;
  final List<String> blockers, warnings;
  bool get confirmationRequired => true;
  bool get transferAllowed => false;
  String get verificationPlan =>
      'Device readback unconfirmed; future exact canonical comparison required.';
  String get restorationPlan =>
      'Only local draft restoration available; no device restoration.';
}

class PresetWritePlanner {
  const PresetWritePlanner(this.validator);
  final PresetValidator validator;
  PresetWritePlan plan(
    CanonicalPreset preset, {
    PresetSlot? slot,
    PresetBackup? backup,
    bool explicitlySelected = false,
    bool uniqueConnectedTarget = false,
    Set<String> availableAssetHashes = const {},
  }) {
    final blockers = <String>[];
    if (slot == null || !explicitlySelected) {
      blockers.add('Kein ausdrücklich gewählter Zielslot.');
    }
    if (slot?.protected != false) {
      blockers.add('Zielslot geschützt oder Schutzstatus unbekannt.');
    }
    if (slot?.currentPreset == null) {
      blockers.add('Ausgangsinhalt des Zielslots unbekannt.');
    }
    if (backup == null ||
        backup.slotId != slot?.id ||
        slot?.currentPreset == null ||
        backup.hash != presetHashForPlan(slot!.currentPreset!)) {
      blockers.add('Keine passende lokale Sicherung des Ausgangsstands.');
    }
    if (!uniqueConnectedTarget) {
      blockers.add('Zielgerät nicht eindeutig verbunden.');
    }
    final validation = validator.validate(
      preset,
      availableAssetHashes: availableAssetHashes,
    );
    for (final issue in validation.issues.where(
      (i) =>
          i.severity == IssueSeverity.error ||
          [
            'indexUnconfirmed',
            'assetMissing',
            'assetUnassigned',
            'namArchitecture',
          ].contains(i.code),
    )) {
      blockers.add(issue.message);
    }
    final decisions = [
      for (final capability in [
        'preset.select',
        'preset.read',
        'preset.save',
        'algorithm.write',
        'parameter.write',
        'preset.transfer',
        'preset.verify',
        'preset.restore',
      ])
        ProtocolEvidenceRegistry.decide(capability),
    ];
    for (final decision in decisions.where((d) => !d.allowed)) {
      blockers.add('Capability nicht freigegeben: ${decision.capability!.id}');
    }
    blockers.add(
      'Die vollständige Matribox-Presetübertragung ist noch nicht protokollseitig bestätigt.',
    );
    return PresetWritePlan(
      targetDevice: preset.targetDevice,
      slot: slot,
      expectedStart: slot?.currentPreset,
      backup: backup,
      changes: slot?.currentPreset == null
          ? const []
          : const PresetDiffEngine().compare(slot!.currentPreset!, preset),
      requiredCapabilities: decisions,
      blockers: blockers.toSet().toList()..sort(),
      warnings: [
        'Nur Planung – noch keine Übertragung',
        'Eine lokale Sicherung ist kein Hardware-Backup.',
      ],
    );
  }
}

// Keep hashing independent of transports.
String presetHashForPlan(CanonicalPreset preset) => presetHash(preset);

enum AdapterResultStatus { unsupported, notConfirmed }

class DevicePresetResult {
  const DevicePresetResult(this.operation, this.status, this.reason);
  final String operation, reason;
  final AdapterResultStatus status;
}

abstract interface class DevicePresetAdapter {
  DevicePresetResult capabilityFor(String operation);
}

class OfflineMatriboxPresetAdapter implements DevicePresetAdapter {
  const OfflineMatriboxPresetAdapter();
  @override
  DevicePresetResult capabilityFor(String operation) {
    const known = [
      'listSlots',
      'readPreset',
      'deviceBackup',
      'transfer',
      'verify',
      'restore',
      'select',
      'save',
    ];
    return DevicePresetResult(
      operation,
      known.contains(operation)
          ? AdapterResultStatus.notConfirmed
          : AdapterResultStatus.unsupported,
      'Noch nicht für Geräteübertragung freigegeben',
    );
  }
}
