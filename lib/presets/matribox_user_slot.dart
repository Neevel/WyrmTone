/// The ONE canonical Matribox User-bank slot address: P01..P99 <-> device index 0..98
/// (confirmed: read Bank/Slot byte, preset-select index, Program Change = preset number - 1).
///
/// Pure addressing. Whether a slot may be WRITTEN is a separate product rule
/// ([MatriboxSlotPolicy] in matribox_transfer_slots.dart); this class never decides it.
library;

final class MatriboxUserSlot {
  const MatriboxUserSlot._(this.presetNumber);

  static const firstPresetNumber = 1;
  static const lastPresetNumber = 99;

  /// Null for anything outside P01..P99 (including a missing number).
  static MatriboxUserSlot? tryPreset(int? presetNumber) =>
      presetNumber != null && presetNumber >= firstPresetNumber && presetNumber <= lastPresetNumber
      ? MatriboxUserSlot._(presetNumber)
      : null;

  factory MatriboxUserSlot.preset(int presetNumber) =>
      tryPreset(presetNumber) ?? (throw ArgumentError.value(presetNumber, 'presetNumber', 'kein User-Preset P01–P99'));

  /// Inverse of [deviceIndex]: 0..98.
  factory MatriboxUserSlot.fromDeviceIndex(int deviceIndex) => MatriboxUserSlot.preset(deviceIndex + 1);

  /// 1..99.
  final int presetNumber;

  /// 0..98: the Bank/Slot byte of the read and the preset-select index.
  int get deviceIndex => presetNumber - 1;

  String get label => 'P${presetNumber.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) => other is MatriboxUserSlot && other.presetNumber == presetNumber;

  @override
  int get hashCode => presetNumber.hashCode;

  @override
  String toString() => label;
}
