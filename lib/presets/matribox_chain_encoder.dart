/// Offline, capture-grounded encoder for the slot-based Matribox 1 live-edit
/// messages seen in the editor big capture:
///
/// - MODEL SELECT  `F0 21 25 7F 51 4D 45 32 12 10 SS 00 01 <u32 code, nibble-paired> F7` (22 B)
/// - PARAMETER     `F0 21 25 7F 51 4D 45 32 12 10 SS 00 02 <u32 code, u16 index, f32 value, nibble-paired> F7` (34 B)
/// - BLOCK TOGGLE  MIDI CC `B1 (0x30 + SS - 1) (00 = ON | 7F = OFF)` (3 B)
/// - metadata (name / BPM / VOL), offline only for now.
///
/// The API takes a [MatriboxChainSlot] and catalog-resolved algorithm and
/// parameter objects; raw slot numbers, algorithm ids, parameter indices
/// and bytes can never be supplied by a caller. Building bytes is not
/// permission to send them: nothing here has a transport.
library;

import 'dart:typed_data';

import 'matribox_chain_catalog.dart';
import 'matribox_chain_slot.dart';

const _qme2Prefix = [0xf0, 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32];

class MatriboxChainEncodingError implements Exception {
  const MatriboxChainEncodingError(this.message);
  final String message;
  @override
  String toString() => 'MatriboxChainEncodingError: $message';
}

List<int> _nibbles(Uint8List raw) => [
  for (final byte in raw) ...[byte >> 4, byte & 15],
];

abstract final class MatriboxChainEncoder {
  static void _checkSlot(MatriboxChainSlot slot, MatriboxChainAlgorithm algorithm) {
    if (!algorithm.slots.contains(slot)) {
      throw MatriboxChainEncodingError(
        '${algorithm.name} ist für ${slot.label} nicht capture-bestätigt.',
      );
    }
  }

  static List<int> modelSelect(MatriboxChainSlot slot, MatriboxChainAlgorithm algorithm) {
    _checkSlot(slot, algorithm);
    final data = ByteData(4)..setUint32(0, algorithm.code, Endian.little);
    return List.unmodifiable([
      ..._qme2Prefix,
      0x12, 0x10, slot.wireSlot, 0x00, 0x01,
      ..._nibbles(data.buffer.asUint8List()),
      0xf7,
    ]);
  }

  static List<int> parameterWrite(
    MatriboxChainSlot slot,
    MatriboxChainAlgorithm algorithm,
    MatriboxChainParameter parameter,
    double value,
  ) {
    _checkSlot(slot, algorithm);
    if (!algorithm.parameters.any((p) => identical(p, parameter))) {
      throw MatriboxChainEncodingError(
        'Parameter ${parameter.name} gehört nicht zu ${algorithm.name}.',
      );
    }
    if (parameter.wireIndex < 0 || parameter.wireIndex > 15) {
      throw MatriboxChainEncodingError(
        'Parameter ${parameter.name} hat keinen gültigen Wire-Index (${parameter.wireIndex}).',
      );
    }
    if (!parameter.accepts(value)) {
      throw MatriboxChainEncodingError(
        'Wert $value ist für ${algorithm.name}/${parameter.name} nicht erlaubt.',
      );
    }
    final data = ByteData(10)
      ..setUint32(0, algorithm.code, Endian.little)
      ..setUint16(4, parameter.wireIndex, Endian.little)
      ..setFloat32(6, value, Endian.little);
    return List.unmodifiable([
      ..._qme2Prefix,
      0x12, 0x10, slot.wireSlot, 0x00, 0x02,
      ..._nibbles(data.buffer.asUint8List()),
      0xf7,
    ]);
  }

  static List<int> blockToggle(MatriboxChainSlot slot, {required bool enabled}) =>
      List.unmodifiable([
        matriboxBlockToggleStatus,
        slot.blockToggleController,
        enabled ? matriboxBlockOnValue : matriboxBlockOffValue,
      ]);

  static List<int> _metadata(int selector, List<int> body) => List.unmodifiable([
    ..._qme2Prefix,
    0x12, 0x11, 0x00, 0x00, selector,
    ...body,
    0xf7,
  ]);

  static List<int> _metadataU16(int selector, int value) {
    if (value < 0 || value > 0xffff) {
      throw const MatriboxChainEncodingError('u16 außerhalb des Bereichs.');
    }
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    return _metadata(selector, _nibbles(data.buffer.asUint8List()));
  }

  /// Offline only; not part of the first Full Live hardware test.
  static List<int> presetVolume(int volume) {
    if (volume < 0 || volume > 99) {
      throw const MatriboxChainEncodingError('Preset VOL muss 0..99 sein.');
    }
    return _metadataU16(3, volume);
  }

  /// Offline only. BPM range is limited to the documented editor range.
  static List<int> presetBpm(int bpm) {
    if (bpm < 40 || bpm > 300) {
      throw const MatriboxChainEncodingError('BPM muss 40..300 sein.');
    }
    return _metadataU16(2, bpm);
  }

  /// Offline only. 34-byte message: 8 zero bytes, up to 11 ASCII characters
  /// from offset 21, NUL padding (layout as captured for `CAP TEST 01`).
  static List<int> presetName(String name) {
    if (name.isEmpty || name.length > 11 || name.codeUnits.any((c) => c < 0x20 || c > 0x7e)) {
      throw const MatriboxChainEncodingError('Name: 1..11 druckbare ASCII-Zeichen.');
    }
    final body = List<int>.filled(20, 0);
    for (var i = 0; i < name.length; i++) {
      body[8 + i] = name.codeUnitAt(i);
    }
    return _metadata(0, body);
  }
}
