/// Confirmed portions of the decoded 768-byte P01 payload, established by the
/// big capture (BEFORE/AFTER raw reads + editor .prst exports):
///
/// - name: ASCII from decoded offset 2
/// - chain order table u16 0..8 from offset 14 (not interpreted further)
/// - algorithm code table: u32 LE at 32 + 4*(slot-1)
/// - parameter blocks: 15 float32 LE at 68 + 60*(slot-1)
/// - block state table: u16 LE at 608 + 2*(slot-1) (1 = ON, 0 = OFF)
/// - BPM u16 at 626, Preset VOL u16 at 628
/// - offset 652: copy of the FX1 code (follows the FX1 model; meaning open)
///
/// Nothing else is interpreted. The 4 bytes at part 8 raw offsets 37..44 are
/// CORRELATED with edits (not a decoded checksum); see the verifier.
library;

import 'dart:typed_data';

import 'matribox_chain_slot.dart';
import 'raw_preset_snapshot.dart';

class MatriboxPresetLayoutModel {
  const MatriboxPresetLayoutModel({
    required this.name,
    required this.codes,
    required this.parameters,
    required this.blockStates,
    required this.bpm,
    required this.volume,
    required this.fx1CodeCopy,
  });

  final String name;

  /// Indexed by [MatriboxChainSlot.index].
  final List<int> codes;
  final List<List<double>> parameters;
  final List<int> blockStates;
  final int bpm;
  final int volume;
  final int fx1CodeCopy;

  int code(MatriboxChainSlot slot) => codes[slot.index];
  bool isOn(MatriboxChainSlot slot) => blockStates[slot.index] == 1;
  double parameter(MatriboxChainSlot slot, int wireIndex) =>
      parameters[slot.index][wireIndex];
}

abstract final class MatriboxPresetLayout {
  static const payloadLength = 768;
  static const nameOffset = 2;
  static const chainOrderOffset = 14;
  static const codeTableOffset = 32;
  static const parametersOffset = 68;
  static const parametersStride = 60;
  static const parametersPerSlot = 15;
  static const blockStateOffset = 608;
  static const bpmOffset = 626;
  static const volumeOffset = 628;
  static const fx1CodeCopyOffset = 652;

  /// Raw part offset where the nibble-paired payload starts, and the part's
  /// payload capacity (96 decoded bytes per 210-byte part 0..7).
  static const rawPayloadStart = 17;
  static const bytesPerPart = 96;

  static int codeOffset(MatriboxChainSlot s) => codeTableOffset + 4 * s.index;
  static int parametersBase(MatriboxChainSlot s) =>
      parametersOffset + parametersStride * s.index;
  static int stateOffset(MatriboxChainSlot s) => blockStateOffset + 2 * s.index;

  /// Decoded payload offset of raw byte [rawOffset] in part [part], or null
  /// if it is not a payload byte (header, F7, parts 8/9).
  static int? decodedOffset(int part, int rawOffset, int partLength) {
    if (part < 0 || part > 7) return null;
    if (rawOffset < rawPayloadStart || rawOffset >= partLength - 1) return null;
    return part * bytesPerPart + (rawOffset - rawPayloadStart) ~/ 2;
  }

  static Uint8List decodePayload(RawPresetSnapshot snapshot) {
    final out = <int>[];
    for (var part = 0; part < 8; part++) {
      final raw = snapshot.rawParts[part];
      for (var i = rawPayloadStart; i + 1 < raw.length - 1; i += 2) {
        out.add((raw[i] << 4) | raw[i + 1]);
      }
    }
    if (out.length != payloadLength) {
      throw FormatException('Payload hat ${out.length} statt $payloadLength Bytes.');
    }
    return Uint8List.fromList(out);
  }

  static MatriboxPresetLayoutModel decode(RawPresetSnapshot snapshot) {
    final payload = decodePayload(snapshot);
    final data = ByteData.sublistView(payload);
    final nameBytes = <int>[];
    for (var i = nameOffset; i < chainOrderOffset && payload[i] != 0; i++) {
      nameBytes.add(payload[i]);
    }
    return MatriboxPresetLayoutModel(
      name: String.fromCharCodes(nameBytes),
      codes: [
        for (final s in MatriboxChainSlot.values) data.getUint32(codeOffset(s), Endian.little),
      ],
      parameters: [
        for (final s in MatriboxChainSlot.values)
          [
            for (var i = 0; i < parametersPerSlot; i++)
              data.getFloat32(parametersBase(s) + 4 * i, Endian.little),
          ],
      ],
      blockStates: [
        for (final s in MatriboxChainSlot.values) data.getUint16(stateOffset(s), Endian.little),
      ],
      bpm: data.getUint16(bpmOffset, Endian.little),
      volume: data.getUint16(volumeOffset, Endian.little),
      fx1CodeCopy: data.getUint32(fx1CodeCopyOffset, Endian.little),
    );
  }
}
