import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_preset_layout.dart';
import 'package:wyrmtone/presets/raw_preset_snapshot.dart';

import 'matribox_big_capture_snapshots.dart';
import 'matribox_full_live_helpers.dart';
import 'matribox_p01_readback_fixtures.dart';

/// Preset raw parts that make every FAMILY_EXPANSION_P01_V1 family observable:
/// the models differ from the plan's and NR/EQ/RVB are OFF.
List<List<int>> suitableStartParts() {
  final parts = hexParts(bigBeforeRawPartsHex);
  void code(MatriboxChainSlot s, int c) => setDecoded(parts, MatriboxPresetLayout.codeOffset(s), u32(c));
  code(MatriboxChainSlot.fx1, 0x03000000);
  code(MatriboxChainSlot.amp, 0x07000035);
  code(MatriboxChainSlot.nr, 0x0000001b);
  code(MatriboxChainSlot.eq, 0x0100003a);
  code(MatriboxChainSlot.mod, 0x04000011);
  code(MatriboxChainSlot.dly, 0x0b000006);
  code(MatriboxChainSlot.rvb, 0x0c000008);
  for (final s in [MatriboxChainSlot.nr, MatriboxChainSlot.eq, MatriboxChainSlot.rvb]) {
    setDecoded(parts, MatriboxPresetLayout.stateOffset(s), u16(0));
  }
  return parts;
}

MatriboxPresetLayoutModel layoutOf(List<List<int>> parts) => MatriboxPresetLayout.decode(
  RawPresetSnapshot.capture(
    deviceLabel: 'Sonicake Matribox 1 84EF:0054',
    rawParts: parts,
    phaseDResponse: matriboxHex(matriboxPhaseDAcknowledgement),
  ),
);
