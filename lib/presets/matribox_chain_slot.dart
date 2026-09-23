/// The closed set of Matribox 1 chain slots. There is deliberately no way to
/// build a slot from an arbitrary integer: the wire slot number and the
/// block-toggle MIDI controller both derive from this enum.
///
/// Evidence: CONFIRMED (editor capture matribox1_p01_big_capture_20260919,
/// slot = chain position + 1). Not derived from any Matribox II Pro data.
library;

enum MatriboxChainSlot {
  fx1('FX1'),
  fx2('FX2'),
  amp('AMP'),
  nr('NR'),
  cab('CAB'),
  eq('EQ'),
  mod('MOD'),
  dly('DLY'),
  rvb('RVB');

  const MatriboxChainSlot(this.label);

  final String label;

  /// Header byte 10 of `12 10 SS 00 01|02`: 1..9.
  int get wireSlot => index + 1;

  /// MIDI control change (channel 2, status 0xB1) that switches the block:
  /// controller 0x30 + slot - 1; value 0x00 = ON, 0x7F = OFF.
  int get blockToggleController => 0x2f + wireSlot;
}

const matriboxBlockToggleStatus = 0xb1;
const matriboxBlockOnValue = 0x00;
const matriboxBlockOffValue = 0x7f;
