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
/// Evidence status of P11..P99: PRODUCT_WRITABLE / SOFTWARE_VALIDATED. The slot addressing
/// (read Bank/Slot bytes, preset-select index = preset number - 1) is protocol evidence; a hardware
/// run per slot range is still outstanding, so no slot is claimed as HARDWARE_CERTIFIED here.
library;

abstract final class MatriboxSlotPolicy {
  static const firstUserPreset = 1;
  static const lastUserPreset = 99;
  static const lastProtectedPreset = 10;
  static const firstWritablePreset = 11;

  /// Honest status of every writable slot after the software milestone.
  static const writableEvidenceStatus = 'PRODUCT_WRITABLE / SOFTWARE_VALIDATED';

  static const protectedExplanation = 'P01–P10 sind geschützt.';
  static const writableExplanation = 'Für Übertragungen stehen P11–P99 zur Verfügung.';

  static bool isUserPreset(int? presetNumber) =>
      presetNumber != null && presetNumber >= firstUserPreset && presetNumber <= lastUserPreset;

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

/// A User-bank preset P01..P99. Only ever built from a valid number; never a default.
final class MatriboxUserSlot {
  const MatriboxUserSlot._(this.presetNumber);

  /// Null for anything outside P01..P99 (including a missing number).
  static MatriboxUserSlot? tryPreset(int? presetNumber) =>
      MatriboxSlotPolicy.isUserPreset(presetNumber) ? MatriboxUserSlot._(presetNumber!) : null;

  factory MatriboxUserSlot.preset(int presetNumber) =>
      tryPreset(presetNumber) ?? (throw ArgumentError.value(presetNumber, 'presetNumber', 'kein User-Preset P01–P99'));

  /// Inverse of [deviceIndex]: 0..98.
  factory MatriboxUserSlot.fromDeviceIndex(int deviceIndex) => MatriboxUserSlot.preset(deviceIndex + 1);

  /// 1..99.
  final int presetNumber;

  /// 0..98: the Bank/Slot byte of the read and the preset-select index.
  int get deviceIndex => presetNumber - 1;

  bool get isProtected => MatriboxSlotPolicy.isProtected(presetNumber);
  bool get isProductWritable => MatriboxSlotPolicy.isProductWritable(presetNumber);

  String get label => 'P${presetNumber.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) => other is MatriboxUserSlot && other.presetNumber == presetNumber;

  @override
  int get hashCode => presetNumber.hashCode;

  @override
  String toString() => label;
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

  /// A real hardware run for this slot exists. False for every slot after the software milestone.
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

  /// P11..P99: PRODUCT_WRITABLE / SOFTWARE_VALIDATED.
  static const productWritable = SlotCapability(
    selectable: true,
    readable: true,
    backupSupported: true,
    writeSupported: true,
    verifySupported: true,
    productiveTransferSupported: true,
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
        MatriboxSlotPolicy.isProductWritable(n) ? SlotCapability.productWritable : SlotCapability.protectedPlay,
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
