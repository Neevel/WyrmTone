/// The ONE product rule for which Matribox User slots WyrmTone's productive transfer may write.
///
///   P01..P99  = the User bank (device index = preset number - 1, 0..98)
///   P01..P10  = PROTECTED PLAY PRESETS: never a transfer target, not for tests, fallback, default,
///               retry, restore, certification or error handling
///   P11..P99  = PRODUCT WRITABLE: fresh read -> backup -> diff -> plan -> native preflight -> preset
///               select -> live write -> manual save -> readback of the SAME slot -> verify
///   Factory   = never writable
///
/// A missing or invalid slot is rejected, never replaced by a default (no fallback to P01, and no
/// fallback to P11 either). The native side enforces the same rule independently
/// (MatriboxSlotPolicy.kt); this file is the Dart half of that boundary, every Dart layer asks it
/// instead of repeating its own `>= 11` check.
///
/// Evidence status: P11 is HARDWARE_CERTIFIED (real multi-slot transfer 2026-09-23: fresh read,
/// preset select, live write, manual save, same-slot readback CERTIFIED). P12..P99 are
/// PRODUCT_WRITABLE / SOFTWARE_VALIDATED: the slot addressing is protocol evidence, but the P11
/// run is not generalized to them.
library;

import 'matribox_user_slot.dart';

export 'matribox_user_slot.dart';

abstract final class MatriboxSlotPolicy {
  static const firstUserPreset = MatriboxUserSlot.firstPresetNumber;
  static const lastUserPreset = MatriboxUserSlot.lastPresetNumber;
  static const lastProtectedPreset = 10;
  static const firstWritablePreset = 11;

  /// Status of every writable slot without its own hardware run.
  static const writableEvidenceStatus = 'PRODUCT_WRITABLE / SOFTWARE_VALIDATED';

  /// Writable slots with their own CERTIFIED hardware run (never generalized to other slots).
  static const hardwareCertifiedPresets = {11};

  static String evidenceStatus(int presetNumber) => hardwareCertifiedPresets.contains(presetNumber)
      ? 'PRODUCT_WRITABLE / HARDWARE_CERTIFIED'
      : isProductWritable(presetNumber)
      ? writableEvidenceStatus
      : 'PROTECTED';

  static const protectedExplanation = 'P01–P10 sind geschützt.';
  static const writableExplanation = 'Für Übertragungen stehen P11–P99 zur Verfügung.';

  static bool isUserPreset(int? presetNumber) => MatriboxUserSlot.tryPreset(presetNumber) != null;

  static bool isProtected(int? presetNumber) =>
      presetNumber != null && presetNumber >= firstUserPreset && presetNumber <= lastProtectedPreset;

  /// The only question every write-side layer asks: User bank AND P11..P99.
  static bool isProductWritable(int? presetNumber, {bool isUserBank = true}) =>
      isUserBank && presetNumber != null && presetNumber >= firstWritablePreset && presetNumber <= lastUserPreset;

  /// Null when [presetNumber] may be written; otherwise the plain-language reason it may not.
  static String? writeRejection(int? presetNumber, {bool isUserBank = true}) {
    if (!isUserBank) return 'Die Factory-Bank wird nie beschrieben.';
    if (presetNumber == null) return 'Kein Speicherplatz gewählt. $writableExplanation';
    if (isProtected(presetNumber)) return '$protectedExplanation $writableExplanation';
    if (!isUserPreset(presetNumber)) return 'Ungültiger Speicherplatz. $writableExplanation';
    return null;
  }
}

/// What is released for one slot, split by pipeline step. Derived from [MatriboxSlotPolicy] only.
class SlotCapability {
  const SlotCapability({
    required this.selectable,
    required this.readable,
    required this.backupSupported,
    required this.writeSupported,
    required this.verifySupported,
    required this.productiveTransferSupported,
    this.hardwareCertified = false,
  });

  /// The slot can be chosen as a transfer target in the UI.
  final bool selectable;

  /// A fresh device read of this slot is wired into the transfer.
  final bool readable;

  /// Reading includes a verified raw backup of this slot.
  final bool backupSupported;

  /// The native transport accepts writes targeting this slot.
  final bool writeSupported;

  /// A saved-state readback/verification of this slot is wired.
  final bool verifySupported;

  /// Every step above is released TOGETHER: the only flag the UI may use to enable a transfer.
  final bool productiveTransferSupported;

  /// A real, CERTIFIED hardware run exists for exactly this slot.
  final bool hardwareCertified;

  /// P01..P10: shown, but never a transfer target.
  static const protectedPlay = SlotCapability(
    selectable: false,
    readable: false,
    backupSupported: false,
    writeSupported: false,
    verifySupported: false,
    productiveTransferSupported: false,
  );

  /// P12..P99: PRODUCT_WRITABLE / SOFTWARE_VALIDATED.
  static const productWritable = SlotCapability(
    selectable: true,
    readable: true,
    backupSupported: true,
    writeSupported: true,
    verifySupported: true,
    productiveTransferSupported: true,
  );

  /// P11: PRODUCT_WRITABLE / HARDWARE_CERTIFIED.
  static const productWritableHardwareCertified = SlotCapability(
    selectable: true,
    readable: true,
    backupSupported: true,
    writeSupported: true,
    verifySupported: true,
    productiveTransferSupported: true,
    hardwareCertified: true,
  );
}

class MatriboxTransferSlot {
  const MatriboxTransferSlot(this.number, this.capability);

  /// 1..99 (User bank).
  final int number;

  final SlotCapability capability;

  /// Read, backup, write and verification are released for this slot.
  bool get approved => capability.productiveTransferSupported;

  bool get isProtected => MatriboxSlotPolicy.isProtected(number);

  String get label => 'P${number.toString().padLeft(2, '0')}';
}

abstract final class MatriboxTransferSlots {
  static final userSlots = List<MatriboxTransferSlot>.unmodifiable([
    for (var n = MatriboxSlotPolicy.firstUserPreset; n <= MatriboxSlotPolicy.lastUserPreset; n++)
      MatriboxTransferSlot(
        n,
        !MatriboxSlotPolicy.isProductWritable(n)
            ? SlotCapability.protectedPlay
            : MatriboxSlotPolicy.hardwareCertifiedPresets.contains(n)
            ? SlotCapability.productWritableHardwareCertified
            : SlotCapability.productWritable,
      ),
  ]);

  static bool isApproved(int? number) => MatriboxSlotPolicy.isProductWritable(number);

  /// Null for a missing or invalid number -- there is deliberately no default slot.
  static MatriboxTransferSlot? slot(int? number) =>
      MatriboxSlotPolicy.isUserPreset(number) ? userSlots[number! - 1] : null;

  static const explanation = '${MatriboxSlotPolicy.protectedExplanation} ${MatriboxSlotPolicy.writableExplanation}';

  static const protectedSlotExplanation =
      'Dieser Platz ist geschützt und wird von WyrmTone nie überschrieben. ${MatriboxSlotPolicy.writableExplanation}';

  static const noSlotExplanation = 'Wähle zuerst einen Speicherplatz. ${MatriboxSlotPolicy.writableExplanation}';

  /// The plain sentence for why [number] cannot be the target (null when it can).
  static String? blockedExplanation(int? number) {
    if (number == null) return noSlotExplanation;
    if (MatriboxSlotPolicy.isProtected(number)) return protectedSlotExplanation;
    if (!MatriboxSlotPolicy.isProductWritable(number)) return noSlotExplanation;
    return null;
  }
}
