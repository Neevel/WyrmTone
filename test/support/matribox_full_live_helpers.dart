import 'dart:typed_data';

import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_full_live_plan.dart';
import 'package:wyrmtone/presets/matribox_preset_layout.dart';
import 'package:wyrmtone/presets/raw_preset_backup_format.dart';

import 'matribox_big_capture_snapshots.dart';

List<List<int>> hexParts(List<String> hex) => [for (final h in hex) hexToBytes(h)];

/// Writes [bytes] at decoded payload [offset] into nibble-paired raw parts.
void setDecoded(List<List<int>> parts, int offset, List<int> bytes) {
  for (var i = 0; i < bytes.length; i++) {
    final o = offset + i;
    final part = o ~/ MatriboxPresetLayout.bytesPerPart;
    final raw = MatriboxPresetLayout.rawPayloadStart + (o % MatriboxPresetLayout.bytesPerPart) * 2;
    parts[part][raw] = bytes[i] >> 4;
    parts[part][raw + 1] = bytes[i] & 15;
  }
}

List<int> u32(int v) => (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();
List<int> u16(int v) => (ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List();
List<int> f32(double v) => (ByteData(4)..setFloat32(0, v, Endian.little)).buffer.asUint8List();

/// The device state the plan is expected to produce, applied to a copy of
/// the real BEFORE raw parts (part-8 window touched like the real device).
List<List<int>> afterFromPlan({double? rate}) {
  final parts = hexParts(bigBeforeRawPartsHex);
  final touched = <MatriboxChainSlot>{};
  for (final o in MatriboxFullLivePlan.operations) {
    switch (o.kind) {
      case FullLiveOperationKind.modelSelect:
        setDecoded(parts, MatriboxPresetLayout.codeOffset(o.slot), u32(o.algorithm!.code));
        // a model change resets the block's parameters to defaults
        setDecoded(parts, MatriboxPresetLayout.parametersBase(o.slot), List.filled(60, 0));
        touched.add(o.slot);
        if (o.slot == MatriboxChainSlot.fx1) {
          setDecoded(parts, MatriboxPresetLayout.fx1CodeCopyOffset, u32(o.algorithm!.code));
        }
      case FullLiveOperationKind.parameter:
        final value = o.parameter!.name == 'Rate' ? (rate ?? 4.0) : o.value!;
        setDecoded(
          parts,
          MatriboxPresetLayout.parametersBase(o.slot) + 4 * o.parameter!.wireIndex,
          f32(value),
        );
      case FullLiveOperationKind.blockToggle:
        setDecoded(parts, MatriboxPresetLayout.stateOffset(o.slot), u16(o.enabled! ? 1 : 0));
    }
  }
  for (var i = 37; i < 45; i++) {
    parts[8][i] = (parts[8][i] + 1) & 15;
  }
  return parts;
}

