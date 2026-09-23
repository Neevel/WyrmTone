/// Semantic diff CURRENT DEVICE PRESET vs [MatriboxTargetPreset] and the
/// deterministic, evidence-gated [MatriboxToneTransferPlan].
///
/// - Only real differences are planned; already correct values are
///   [ToneOperationKind.noChange] and never sent.
/// - Per chain slot (FX1 -> RVB) the order is: SELECT_MODEL -> SET_PARAMETER
///   ... -> ENABLE/DISABLE. A model change always precedes the parameter
///   writes of that model, and (because the device resets parameters on a
///   model change) every specified parameter of a newly selected model is
///   written.
/// - Every entry carries protocol evidence, hardware evidence and a send
///   eligibility. The plan is sendable only if EVERY planned operation is
///   eligible (no partial transfer of a real song preset).
///
/// Nothing here has a transport. Bytes are built only to validate the plan
/// ("Plan validated") through the closed [MatriboxChainEncoder].
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'device_catalog.dart';
import 'matribox_chain_catalog.dart';
import 'matribox_chain_encoder.dart';
import 'matribox_chain_slot.dart';
import 'matribox_evidence_v2.dart';
import 'matribox_hardware_evidence.dart';
import 'matribox_model_library.dart';
import 'matribox_preset_layout.dart';
import 'matribox_target_preset.dart';
import 'matribox_transfer_catalog.dart';
import 'matribox_transfer_slots.dart';
import 'tone_intent.dart';

enum ToneOperationKind {
  noChange,
  enableBlock,
  disableBlock,
  selectModel,
  setParameter,
  unsupported,
  blockedByEvidence,
  unknownCurrent,

  /// The block should be ON but has no model/kind: nothing deterministic.
  incompleteTarget,
}

enum ToneSendEligibility {
  /// No change needed (or nothing specified): never sent.
  notNeeded,
  eligible,
  blockedByEvidence,
  unsupported,
  unknownCurrent,
  incompleteTarget,
}

class ToneTransferEntry {
  const ToneTransferEntry({
    required this.slot,
    required this.intended,
    required this.subject,
    required this.current,
    required this.target,
    required this.origin,
    required this.reason,
    required this.eligibility,
    this.specified = true,
    this.protocolEvidence,
    this.hardwareEvidence,
    this.blockReason,
    this.model,
    this.parameter,
    this.value,
    this.enable,
    this.bytes,
  });

  final MatriboxChainSlot slot;

  /// What the entry wants to do if it were sendable.
  final ToneOperationKind intended;

  /// `BLOCK`, `MODEL` or the semantic parameter name.
  final String subject;
  final String current, target;
  final ToneOrigin origin;
  final String reason;
  final bool specified;
  final TransferProtocolEvidence? protocolEvidence;
  final HardwareEvidenceDecision? hardwareEvidence;
  final ToneSendEligibility eligibility;
  final String? blockReason;

  // Payload references for the transport (closed catalog objects, no ids).
  final MatriboxTransferModel? model;
  final MatriboxChainParameter? parameter;
  final double? value;
  final bool? enable;

  /// Only for plan validation / audit; never shown as a raw-SysEx UI.
  final List<int>? bytes;

  /// The spec's operation kind: blocked/unsupported/unknown entries are
  /// reported under their blocking kind.
  ToneOperationKind get resultKind => switch (eligibility) {
    ToneSendEligibility.blockedByEvidence => ToneOperationKind.blockedByEvidence,
    ToneSendEligibility.unsupported => ToneOperationKind.unsupported,
    ToneSendEligibility.unknownCurrent => ToneOperationKind.unknownCurrent,
    ToneSendEligibility.incompleteTarget => ToneOperationKind.incompleteTarget,
    _ => intended,
  };

  bool get sendable => eligibility == ToneSendEligibility.eligible;
  bool get isChange => intended != ToneOperationKind.noChange;
}

class ToneTransferSummary {
  const ToneTransferSummary({
    required this.modelsChanged,
    required this.parametersChanged,
    required this.blocksEnabled,
    required this.blocksDisabled,
    required this.unchanged,
    required this.notSpecified,
    required this.unsupported,
    required this.blocked,
    required this.unknownCurrent,
    this.incomplete = 0,
  });

  /// Eligible (sendable) changes only.
  final int modelsChanged, parametersChanged, blocksEnabled, blocksDisabled;
  final int unchanged, notSpecified, unsupported, blocked, unknownCurrent, incomplete;
}

enum ToneTransferOverall { ready, blocked, nothingToDo }

/// Blocks whose missing model makes a transfer pointless.
const criticalIncompleteSlots = {MatriboxChainSlot.amp};

class MatriboxToneTransferPlan {
  MatriboxToneTransferPlan._({
    required this.entries,
    required this.presetNumber,
    required this.isUserBank,
    required this.backupSha256,
    required this.blockers,
    required this.overall,
    required this.fingerprint,
    required this.ledgerSource,
  });

  final List<ToneTransferEntry> entries;

  /// The User slot this plan was diffed against and may only ever be sent to (P11..P99).
  final int presetNumber;
  final bool isUserBank;
  final String? backupSha256;
  final List<String> blockers;
  final ToneTransferOverall overall;
  final String fingerprint;
  final String ledgerSource;

  /// The exact list that would be sent, in order.
  List<ToneTransferEntry> get operations =>
      entries.where((e) => e.sendable && e.isChange).toList(growable: false);

  bool get sendable => overall == ToneTransferOverall.ready;

  /// The closed Dart -> Kotlin contract for the productive transport:
  /// slot names, catalog model/parameter names and values ONLY. No bytes, no
  /// algorithm ids, no parameter indices, no operation for Store/metadata.
  /// Kotlin validates every operation again against its own evidence table.
  /// There is no contract for a protected, invalid or Factory target (no fallback slot either).
  Map<String, Object?> toContractRequest() {
    final rejection = MatriboxSlotPolicy.writeRejection(presetNumber, isUserBank: isUserBank);
    if (rejection != null) throw StateError(rejection);
    return _contract();
  }

  Map<String, Object?> _contract() => {
    'planId': fingerprint,
    'targetBank': 'USER',
    'targetSlot': presetNumber,
    'backupHash': backupSha256,
    'operations': [
      for (final e in operations)
        switch (e.intended) {
          ToneOperationKind.selectModel => {
            'type': 'SELECT_MODEL',
            'slot': e.slot.label,
            'model': e.model!.name,
          },
          ToneOperationKind.setParameter => {
            'type': 'SET_PARAMETER',
            'slot': e.slot.label,
            'model': e.model!.name,
            'parameter': e.parameter!.name,
            'value': e.value,
          },
          ToneOperationKind.enableBlock => {'type': 'ENABLE_BLOCK', 'slot': e.slot.label},
          ToneOperationKind.disableBlock => {'type': 'DISABLE_BLOCK', 'slot': e.slot.label},
          _ => throw StateError('${e.intended.name} ist nicht sendbar.'),
        },
    ],
  };

  ToneTransferSummary get summary => ToneTransferSummary(
    modelsChanged: operations.where((e) => e.intended == ToneOperationKind.selectModel).length,
    parametersChanged: operations.where((e) => e.intended == ToneOperationKind.setParameter).length,
    blocksEnabled: operations.where((e) => e.intended == ToneOperationKind.enableBlock).length,
    blocksDisabled: operations.where((e) => e.intended == ToneOperationKind.disableBlock).length,
    unchanged: entries
        .where((e) => e.specified && e.eligibility == ToneSendEligibility.notNeeded)
        .length,
    notSpecified: entries.where((e) => !e.specified).length,
    unsupported: entries.where((e) => e.eligibility == ToneSendEligibility.unsupported).length,
    blocked: entries.where((e) => e.eligibility == ToneSendEligibility.blockedByEvidence).length,
    unknownCurrent: entries.where((e) => e.eligibility == ToneSendEligibility.unknownCurrent).length,
    incomplete: entries.where((e) => e.eligibility == ToneSendEligibility.incompleteTarget).length,
  );

  /// Builds the plan. [backupSha256] must be the verified backup of the
  /// current state; [transportAvailable] states whether a productive
  /// transport exists at all.
  static MatriboxToneTransferPlan build({
    required MatriboxPresetLayoutModel current,
    required MatriboxTargetPreset target,
    required MatriboxHardwareLedger ledger,
    required String? backupSha256,
    required int presetNumber,
    required bool isUserBank,
    required bool transportAvailable,
    DevicePresetCatalog? nameCatalog,
    MatriboxModelLibrary? library,
  }) {
    final models = library ?? MatriboxModelLibrary.base;
    // Family evidence over the hardware ledger's ACTIVE samples (Evidence V2).
    final evidence = MatriboxEvidenceV2(library: models, samples: ActiveSamples.fromLedger(ledger, models));
    final entries = <ToneTransferEntry>[];
    for (final slot in MatriboxChainSlot.values) {
      entries.addAll(_slotEntries(slot, current, target[slot], ledger, evidence, nameCatalog, models));
    }

    final blockers = <String>[];
    final blockedCount = entries.where((e) => e.isChange && !e.sendable && e.specified).length;
    final unknown = entries.where((e) => e.eligibility == ToneSendEligibility.unknownCurrent).length;
    final unsupported = entries.where((e) => e.eligibility == ToneSendEligibility.unsupported).length;
    final blockedEvidence = entries.where((e) => e.eligibility == ToneSendEligibility.blockedByEvidence).length;
    if (blockedEvidence > 0) {
      blockers.add('$blockedEvidence Operation(en) ohne ausreichende Protokoll-/Hardware-Evidenz.');
    }
    if (unsupported > 0) blockers.add('$unsupported Operation(en) nicht unterstützt.');
    // An incomplete block is only a blocker when the sound cannot work without it (the amp). Any other
    // incomplete block is left exactly as it is on the device (no operation, listed as "nicht gesetzt"), which
    // is what the preparation preview promised.
    final incomplete = entries
        .where((e) => e.eligibility == ToneSendEligibility.incompleteTarget && criticalIncompleteSlots.contains(e.slot))
        .length;
    if (incomplete > 0) blockers.add('$incomplete Block/Blöcke mit unvollständigem Ziel (INCOMPLETE_TARGET).');
    if (unknown > 0) blockers.add('$unknown Operation(en) mit unbekanntem aktuellem Zustand.');
    final slotRejection = MatriboxSlotPolicy.writeRejection(presetNumber, isUserBank: isUserBank);
    if (slotRejection != null) blockers.add(slotRejection);
    if (backupSha256 == null) blockers.add('Kein verifiziertes Backup.');
    final hasSendOps = entries.any((e) => e.sendable && e.isChange);
    if (!transportAvailable && (hasSendOps || blockedCount > 0)) {
      blockers.add('Kein produktiver Transport für Tone Transfer verfügbar.');
    }
    final ToneTransferOverall overall;
    if (blockers.isNotEmpty) {
      overall = ToneTransferOverall.blocked;
    } else if (!hasSendOps) {
      overall = ToneTransferOverall.nothingToDo;
    } else {
      overall = ToneTransferOverall.ready;
    }

    final fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              backupSha256,
              for (final e in entries.where((e) => e.sendable && e.isChange))
                [e.slot.label, e.intended.name, e.subject, e.target],
            ]),
          ),
        )
        .toString();

    return MatriboxToneTransferPlan._(
      entries: List.unmodifiable(entries),
      presetNumber: presetNumber,
      isUserBank: isUserBank,
      backupSha256: backupSha256,
      blockers: List.unmodifiable(blockers),
      overall: overall,
      fingerprint: fingerprint,
      ledgerSource: ledger.source,
    );
  }

  static String _hex(int code) => '0x${code.toRadixString(16).padLeft(8, '0')}';

  static String _format(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  static bool _same(MatriboxChainParameter p, double a, double b) {
    final tolerance = p.kind == MatriboxParameterKind.decimal ? 0.05 : 0.5;
    return (a - b).abs() < tolerance;
  }

  static String _currentModelName(
    MatriboxChainSlot slot,
    int code,
    MatriboxTransferModel? known,
    DevicePresetCatalog? catalog,
  ) {
    if (known != null) return known.name;
    final vendor = catalog?.algorithms
        .where((a) => a.code == code && a.category == slot.label)
        .firstOrNull;
    return vendor?.name ?? _hex(code);
  }

  /// The V2 decision as the plan's hardware-evidence record. V2 hard blocks and
  /// V2 family/exact confirmations decide; only when V2 has no opinion (it
  /// says "not enough samples") the legacy ledger rule is consulted.
  /// The same decision as the plan uses, for an advisory pre-check without a device read.
  static HardwareEvidenceDecision hardwareDecision(EvidenceDecision v2, HardwareEvidenceDecision legacy) => _asHardware(v2, legacy);

  static HardwareEvidenceDecision _asHardware(EvidenceDecision v2, HardwareEvidenceDecision legacy) {
    if (v2.sendable) {
      return HardwareEvidenceDecision(
        true,
        '${v2.level.name.toUpperCase()} · ${v2.family}: ${v2.basis}',
        exact: v2.level == EvidenceLevel.exactOperationConfirmed,
      );
    }
    if (v2.level == EvidenceLevel.blocked) return HardwareEvidenceDecision(false, '${v2.family}: ${v2.basis}');
    return legacy;
  }

  static List<ToneTransferEntry> _slotEntries(
    MatriboxChainSlot slot,
    MatriboxPresetLayoutModel current,
    MatriboxTargetBlock target,
    MatriboxHardwareLedger ledger,
    MatriboxEvidenceV2 evidence,
    DevicePresetCatalog? nameCatalog,
    MatriboxModelLibrary library,
  ) {
    final entries = <ToneTransferEntry>[];
    final currentCode = current.code(slot);
    final currentModel = library.byCode(slot, currentCode);
    final currentOnNow = current.isOn(slot);
    switch (target.effectiveState) {
      case RecipeBlockState.unchanged:
        return [
          ToneTransferEntry(
            slot: slot,
            intended: ToneOperationKind.noChange,
            subject: 'BLOCK',
            current: currentOnNow ? 'ON' : 'OFF',
            target: 'UNCHANGED',
            origin: ToneOrigin.unchanged,
            reason: target.report?.why.join(' ') ?? 'Ausdrücklich nicht Teil des Tone-Ziels.',
            eligibility: ToneSendEligibility.notNeeded,
            specified: false,
          ),
        ];
      case RecipeBlockState.incomplete:
        return [
          ToneTransferEntry(
            slot: slot,
            intended: ToneOperationKind.enableBlock,
            subject: 'BLOCK',
            current: currentOnNow ? 'ON' : 'OFF',
            target: 'INCOMPLETE_TARGET',
            origin: target.enabled.origin,
            reason: target.enabled.reason,
            eligibility: ToneSendEligibility.incompleteTarget,
            blockReason: target.incompleteReason ??
                'Block soll ON sein, aber es steht kein Modell fest; das aktuelle Gerätemodell wird nie übernommen.',
          ),
        ];
      case RecipeBlockState.off:
      case RecipeBlockState.defined:
        break;
    }
    final currentModelName = _currentModelName(slot, currentCode, currentModel, nameCatalog);

    // -- model -----------------------------------------------------------
    var modelChanged = false;
    var modelBlocked = false;
    var modelUnsupported = false;
    MatriboxTransferModel? effective = currentModel;
    final targetModel = target.model.value;
    if (targetModel == null) {
      entries.add(
        ToneTransferEntry(
          slot: slot,
          intended: ToneOperationKind.noChange,
          subject: 'MODEL',
          current: currentModelName,
          target: 'NOT_SPECIFIED',
          origin: ToneOrigin.unchanged,
          reason: target.model.reason,
          eligibility: ToneSendEligibility.notNeeded,
          specified: false,
        ),
      );
    } else if (targetModel.code == currentCode) {
      effective = targetModel;
      entries.add(
        ToneTransferEntry(
          slot: slot,
          intended: ToneOperationKind.noChange,
          subject: 'MODEL',
          current: currentModelName,
          target: targetModel.name,
          origin: target.model.origin,
          reason: target.model.reason,
          eligibility: ToneSendEligibility.notNeeded,
        ),
      );
    } else {
      modelChanged = true;
      effective = targetModel;
      List<int>? bytes;
      var eligibility = ToneSendEligibility.eligible;
      String? why;
      if (!targetModel.selectable || !targetModel.algorithm.slots.contains(slot)) {
        eligibility = ToneSendEligibility.unsupported;
        why = '${targetModel.name} ist für ${slot.label} nicht als Modellwahl unterstützt.';
      } else {
        bytes = MatriboxChainEncoder.modelSelect(slot, targetModel.algorithm);
      }
      final v2 = evidence.modelSelect(slot, targetModel);
      final legacy = ledger.model(slot, targetModel);
      final hardware = _asHardware(v2, legacy);
      if (eligibility == ToneSendEligibility.eligible) {
        if (v2.level == EvidenceLevel.blocked) {
          eligibility = ToneSendEligibility.blockedByEvidence;
          why = hardware.basis;
        } else if (!v2.sendable) {
          if (targetModel.selectEvidence != TransferProtocolEvidence.captureConfirmed && !legacy.exact) {
            eligibility = ToneSendEligibility.blockedByEvidence;
            why = 'MODEL SELECT für ${targetModel.name}: Protokoll nur ${targetModel.selectEvidence.name}, '
                'nicht capture-bestätigt.';
          } else if (!legacy.confirmed) {
            eligibility = ToneSendEligibility.blockedByEvidence;
            why = legacy.basis;
          }
        }
      }
      modelBlocked = eligibility == ToneSendEligibility.blockedByEvidence;
      modelUnsupported = eligibility == ToneSendEligibility.unsupported;
      entries.add(
        ToneTransferEntry(
          slot: slot,
          intended: ToneOperationKind.selectModel,
          subject: 'MODEL',
          current: currentModelName,
          target: targetModel.name,
          origin: target.model.origin,
          reason: target.model.reason,
          eligibility: eligibility,
          blockReason: why,
          protocolEvidence: targetModel.selectEvidence,
          hardwareEvidence: hardware,
          model: targetModel,
          bytes: bytes,
        ),
      );
    }

    // -- parameters ------------------------------------------------------
    final semantics = target.parameters.keys.toList();
    final ordering = effective;
    if (ordering != null) {
      semantics.sort(
        (a, b) => (ordering.parameter(a)?.wireIndex ?? 999).compareTo(
          ordering.parameter(b)?.wireIndex ?? 999,
        ),
      );
    }
    for (final semantic in semantics) {
      final wanted = target.parameters[semantic]!;
      if (!wanted.specified) {
        entries.add(
          ToneTransferEntry(
            slot: slot,
            intended: ToneOperationKind.noChange,
            subject: semantic,
            current: effective?.parameter(semantic) == null
                ? '?'
                : _format(current.parameter(slot, effective!.parameter(semantic)!.wireIndex)),
            target: 'NOT_SPECIFIED',
            origin: ToneOrigin.unchanged,
            reason: wanted.reason,
            eligibility: ToneSendEligibility.notNeeded,
            specified: false,
          ),
        );
        continue;
      }
      final value = wanted.value!;
      final parameter = effective?.parameter(semantic);
      if (effective == null) {
        entries.add(
          ToneTransferEntry(
            slot: slot,
            intended: ToneOperationKind.setParameter,
            subject: semantic,
            current: '?',
            target: _format(value),
            origin: wanted.origin,
            reason: wanted.reason,
            eligibility: ToneSendEligibility.unknownCurrent,
            blockReason: 'Aktuelles ${slot.label}-Modell $currentModelName ist im Transferkatalog unbekannt.',
          ),
        );
        continue;
      }
      if (parameter != null && parameter.blockedReason != null) {
        entries.add(
          ToneTransferEntry(
            slot: slot,
            intended: ToneOperationKind.setParameter,
            subject: semantic,
            current: '?',
            target: _format(value),
            origin: wanted.origin,
            reason: wanted.reason,
            eligibility: ToneSendEligibility.blockedByEvidence,
            blockReason: 'ADDRESS_BLOCKED: ${parameter.blockedReason}',
            model: effective,
          ),
        );
        continue;
      }
      if (parameter == null || !parameter.accepts(value)) {
        entries.add(
          ToneTransferEntry(
            slot: slot,
            intended: ToneOperationKind.setParameter,
            subject: semantic,
            current: '?',
            target: _format(value),
            origin: wanted.origin,
            reason: wanted.reason,
            eligibility: ToneSendEligibility.unsupported,
            blockReason: parameter == null
                ? '${effective.name} hat keinen Parameter "$semantic".'
                : 'Wert ${_format(value)} außerhalb ${parameter.minimum}..${parameter.maximum}.',
            model: effective,
          ),
        );
        continue;
      }
      final currentValue = current.parameter(slot, parameter.wireIndex);
      final currentText = modelChanged ? 'nach Modellwechsel zurückgesetzt' : _format(currentValue);
      if (!modelChanged && _same(parameter, currentValue, value)) {
        entries.add(
          ToneTransferEntry(
            slot: slot,
            intended: ToneOperationKind.noChange,
            subject: semantic,
            current: currentText,
            target: _format(value),
            origin: wanted.origin,
            reason: wanted.reason,
            eligibility: ToneSendEligibility.notNeeded,
            model: effective,
            parameter: parameter,
            value: value,
          ),
        );
        continue;
      }
      var eligibility = ToneSendEligibility.eligible;
      String? why;
      final v2 = evidence.parameter(slot, effective, parameter, value);
      final legacy = ledger.parameter(slot, effective, parameter);
      final hardware = _asHardware(v2, legacy);
      if (modelUnsupported) {
        eligibility = ToneSendEligibility.unsupported;
        why = 'Setzt einen nicht unterstützten Modellwechsel voraus.';
      } else if (modelBlocked) {
        eligibility = ToneSendEligibility.blockedByEvidence;
        why = 'Setzt den blockierten Modellwechsel voraus.';
      } else if (v2.level == EvidenceLevel.blocked) {
        eligibility = ToneSendEligibility.blockedByEvidence;
        why = hardware.basis;
      } else if (!v2.sendable) {
        if (effective.parameterEvidence != TransferProtocolEvidence.captureConfirmed) {
          eligibility = ToneSendEligibility.blockedByEvidence;
          why = 'PARAMETER ${effective.name}/${parameter.name}: Protokoll nur ${effective.parameterEvidence.name}.';
        } else if (!legacy.confirmed) {
          eligibility = ToneSendEligibility.blockedByEvidence;
          why = legacy.basis;
        }
      }
      entries.add(
        ToneTransferEntry(
          slot: slot,
          intended: ToneOperationKind.setParameter,
          subject: semantic,
          current: currentText,
          target: _format(value),
          origin: wanted.origin,
          reason: wanted.reason,
          eligibility: eligibility,
          blockReason: why,
          protocolEvidence: effective.parameterEvidence,
          hardwareEvidence: hardware,
          model: effective,
          parameter: parameter,
          value: value,
          bytes: MatriboxChainEncoder.parameterWrite(slot, effective.algorithm, parameter, value),
        ),
      );
    }

    // -- block state -----------------------------------------------------
    final wantedOn = target.enabled.value;
    final currentOn = current.isOn(slot);
    if (wantedOn == null) {
      entries.add(
        ToneTransferEntry(
          slot: slot,
          intended: ToneOperationKind.noChange,
          subject: 'BLOCK',
          current: currentOn ? 'ON' : 'OFF',
          target: 'NOT_SPECIFIED',
          origin: ToneOrigin.unchanged,
          reason: target.enabled.reason,
          eligibility: ToneSendEligibility.notNeeded,
          specified: false,
        ),
      );
    } else if (wantedOn == currentOn) {
      entries.add(
        ToneTransferEntry(
          slot: slot,
          intended: ToneOperationKind.noChange,
          subject: 'BLOCK',
          current: currentOn ? 'ON' : 'OFF',
          target: wantedOn ? 'ON' : 'OFF',
          origin: target.enabled.origin,
          reason: target.enabled.reason,
          eligibility: ToneSendEligibility.notNeeded,
        ),
      );
    } else {
      final hardware = _asHardware(evidence.blockToggle(slot, wantedOn), ledger.toggle(slot, wantedOn));
      entries.add(
        ToneTransferEntry(
          slot: slot,
          intended: wantedOn ? ToneOperationKind.enableBlock : ToneOperationKind.disableBlock,
          subject: 'BLOCK',
          current: currentOn ? 'ON' : 'OFF',
          target: wantedOn ? 'ON' : 'OFF',
          origin: target.enabled.origin,
          reason: target.enabled.reason,
          eligibility: hardware.confirmed
              ? ToneSendEligibility.eligible
              : ToneSendEligibility.blockedByEvidence,
          blockReason: hardware.confirmed ? null : hardware.basis,
          protocolEvidence: TransferProtocolEvidence.captureConfirmed,
          hardwareEvidence: hardware,
          enable: wantedOn,
          bytes: MatriboxChainEncoder.blockToggle(slot, enabled: wantedOn),
        ),
      );
    }
    return entries;
  }
}
