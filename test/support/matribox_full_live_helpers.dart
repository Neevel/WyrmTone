import 'dart:typed_data';

import 'package:wyrmtone/presets/matribox_preset_layout.dart';
import 'package:wyrmtone/presets/raw_preset_backup_format.dart';


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
