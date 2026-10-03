/// The ONE product rule for which Matribox Clone slot WyrmTone's NAM transfer may
/// write, mirroring `lib/presets/matribox_transfer_slots.dart`'s evidence-tiered
/// shape for the User preset bank.
///
/// Evidence status (see `matribox_nam_transfer_codec.dart`'s `CloneSlotEvidence`):
/// Clone 1 (wire 0x00) and Clone 5 (wire 0x04) are CONFIRMED by real hardware
/// captures/transfers. Clone 2-4 (wire 0x01-0x03) are protocol-derived / strongly
/// inferred only -- no capture, no hardware transfer. V1 product policy: ship
/// only the hardware-confirmed slots as writable; Clone 2-4 are visible (so users
/// understand the device has 5 Clone slots) but disabled, never silently presented
/// as equally certified. This file is the ONE place that decision is made --
/// nothing else re-derives "which Clone slots may be written".
library;

import 'matribox_nam_transfer_codec.dart';

/// What is released for one Clone slot in the product transfer flow.
class CloneSlotCapability {
  const CloneSlotCapability({required this.writeSupported, required this.evidenceLabel, required this.userLabel});

  /// The only flag the UI may use to enable the final transfer action for
  /// this slot.
  final bool writeSupported;

  /// Short, honest German label for the evidence level -- never claims
  /// "bestätigt" for an inferred slot.
  final String evidenceLabel;

  /// What a guitarist reads in the slot picker: availability, not research status.
  final String userLabel;

  static const confirmed =
      CloneSlotCapability(writeSupported: true, evidenceLabel: 'Hardware-bestätigt', userLabel: 'Verfügbar');
  static const unverified =
      CloneSlotCapability(writeSupported: false, evidenceLabel: 'Noch nicht verifiziert', userLabel: 'In dieser Version noch gesperrt');
}

abstract final class MatriboxCloneSlotPolicy {
  /// Clone numbers (1-5) that are real, hardware-confirmed transfer targets
  /// in this product version.
  static const productWritable = {1, 5};

  static CloneSlotCapability capabilityFor(int cloneNumber) =>
      productWritable.contains(cloneNumber) ? CloneSlotCapability.confirmed : CloneSlotCapability.unverified;

  static bool isProductWritable(int cloneNumber) => productWritable.contains(cloneNumber);

  static const explanation =
      'Wähle den Speicherplatz auf deiner Matribox, auf den das NAM geladen wird. '
      'Zurzeit stehen Clone 1 und Clone 5 zur Verfügung, Clone 2–4 sind noch gesperrt.';
}

/// One selectable row in the Clone-slot picker: a typed [MatriboxCloneSlot]
/// (never a raw 0x00-0x04 wire value) plus its product-policy capability.
class MatriboxTransferCloneSlot {
  MatriboxTransferCloneSlot(int cloneNumber)
    : slot = MatriboxCloneSlot(cloneNumber),
      capability = MatriboxCloneSlotPolicy.capabilityFor(cloneNumber);

  final MatriboxCloneSlot slot;
  final CloneSlotCapability capability;

  int get cloneNumber => slot.cloneNumber;
  bool get approved => capability.writeSupported;
  String get label => 'Clone $cloneNumber';
}

abstract final class MatriboxTransferCloneSlots {
  static final all = List<MatriboxTransferCloneSlot>.unmodifiable([
    for (var n = 1; n <= 5; n++) MatriboxTransferCloneSlot(n),
  ]);
}
