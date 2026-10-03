import '../models/tone_target.dart' show ToneDimension;
import '../nam/local_nam_capture.dart';
import 'tone_match_models.dart';

/// Builds the abstract [TonePlan] and adapts it to a device. Knows no concrete device: only
/// what [ToneDeviceCapabilities] states.
class TonePlanBuilder {
  const TonePlanBuilder();

  TonePlan build(ToneIntent intent, ToneMatchCandidate? candidate) {
    final c = candidate?.capture;
    final needsIr = c == null
        ? null
        : switch (c.cabinetContent) {
            NamCabinetContent.withoutCabinet => true,
            NamCabinetContent.withCabinet || NamCabinetContent.fullRig => false,
            NamCabinetContent.unknown => null,
          };
    final notes = <String>[
      if (intent.cabinet.isNotEmpty) 'Cabinet-Charakter laut Wissensbasis: ${intent.cabinet}.',
      if ((intent.dim(ToneDimension.sustain) ?? 0) >= 70) 'Langer Sustain gewünscht: Delay/Reverb sparsam einplanen.',
    ];
    return TonePlan(
      intent: intent,
      candidate: candidate,
      needsIr: needsIr,
      delayKind: intent.delayKind,
      reverbKind: intent.reverbKind,
      notes: notes,
    );
  }

  DeviceTonePlan adapt(TonePlan plan, ToneDeviceCapabilities? device) {
    final limits = <String>[];
    if (device == null) {
      limits.add('Kein Zielgerät gewählt: Der Plan ist nur eine Empfehlung.');
    } else {
      if (plan.delayKind != null && !device.supportsDelay) limits.add('${device.name} unterstützt kein passendes Delay.');
      if (plan.reverbKind != null && !device.supportsReverb) limits.add('${device.name} unterstützt keinen passenden Reverb.');
      if (!device.presetTransfer) {
        limits.add('Den Sound-Plan (Gain, EQ, Effekte) kann WyrmTone aktuell nicht automatisch auf ${device.name} übertragen. Nur das NAM wird übertragen.');
      }
    }
    return DeviceTonePlan(
      plan: plan,
      device: device,
      canTransferNam: device?.namTransfer == true && plan.candidate != null,
      canTransferPreset: device?.presetTransfer == true,
      limitations: limits,
    );
  }
}
