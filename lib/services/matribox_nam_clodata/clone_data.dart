import 'dart:typed_data';

/// Byte-exact offline model of the 8,232-byte CloData buffer, limited to what
/// captures A/B/C and the editor's static code confirm. Everything else stays
/// raw (`unknown…`) so `parse(x).serialize()` is always identical to `x`.
///
/// Layout (absolute offsets):
///   0x0000..0x000F  name, ASCII, NUL padded (file name without `.nam`, max 16)
///   0x0010..0x001F  constant zero in A/B/C            (unknownPrefixPad)
///   0x0020..0x0027  `VTSI` magic + u32 size 0x1288     (header)
///   0x0028..0x0033  zero in A/B/C (u16 CRC field, 0 for size 0x1288 per code)
///   0x0034          u32 data length 0x1200 (= 1152 float32)
///   0x0038..0x0087  constant across A/B/C              (constantHeader)
///   0x0088..0x0097  four float32, model dependent      (variableParams)
///   0x0098..0x00A7  u32 0, 128, 128, 1024 (partition counts at 0xA0/0xA4)
///   0x00A8..0x12A7  1152 float32, model dependent       (firTaps)
///   0x12A8..0x2027  zeros, last 8 bytes 0xFF            (tail)
class MatriboxCloneData {
  MatriboxCloneData._({
    required this.name,
    required this.unknownPrefixPad,
    required this.headerA,
    required this.constantHeader,
    required this.variableParams,
    required this.partitionRegion,
    required this.firTaps,
    required this.tail,
  });

  static const totalLength = 8232;
  static const nameLength = 16;
  static const vtsiMagic = 0x49535456; // 'VTSI' little endian
  static const vtsiSize = 0x1288;
  static const dataLength = 0x1200;
  static const firFirstPartition = 128;
  static const firSecondPartition = 1024;

  final Uint8List name; // 16 raw bytes
  final Uint8List unknownPrefixPad; // 0x10..0x1F
  final Uint8List
  headerA; // 0x20..0x37: magic, size, crc, reserved, data length
  final Uint8List constantHeader; // 0x38..0x87
  final Uint8List variableParams; // 0x88..0x97
  final Uint8List partitionRegion; // 0x98..0xA7
  final Uint8List firTaps; // 0xA8..0x12A7
  final Uint8List tail; // 0x12A8..0x2027

  String get nameText {
    final end = name.indexOf(0);
    return String.fromCharCodes(end < 0 ? name : name.sublist(0, end));
  }

  int get firTapCount => firTaps.length ~/ 4;

  /// Throws [FormatException] when a fixed, code-confirmed field differs.
  static MatriboxCloneData parse(Uint8List bytes) {
    if (bytes.length != totalLength) {
      throw FormatException('CloData must be $totalLength bytes.');
    }
    final view = ByteData.sublistView(bytes);
    if (view.getUint32(0x20, Endian.little) != vtsiMagic) {
      throw const FormatException('Missing VTSI magic at 0x20.');
    }
    if (view.getUint32(0x24, Endian.little) != vtsiSize) {
      throw const FormatException('Unsupported VTSI size.');
    }
    if (view.getUint32(0x34, Endian.little) != dataLength ||
        view.getUint32(0xa0, Endian.little) != firFirstPartition ||
        view.getUint32(0xa4, Endian.little) != firSecondPartition) {
      throw const FormatException('Unexpected FIR partition fields.');
    }
    Uint8List part(int from, int to) =>
        Uint8List.fromList(bytes.sublist(from, to));
    return MatriboxCloneData._(
      name: part(0, 16),
      unknownPrefixPad: part(16, 32),
      headerA: part(0x20, 0x38),
      constantHeader: part(0x38, 0x88),
      variableParams: part(0x88, 0x98),
      partitionRegion: part(0x98, 0xa8),
      firTaps: part(0xa8, 0xa8 + dataLength),
      tail: part(0xa8 + dataLength, totalLength),
    );
  }

  Uint8List serialize() => Uint8List.fromList([
    ...name,
    ...unknownPrefixPad,
    ...headerA,
    ...constantHeader,
    ...variableParams,
    ...partitionRegion,
    ...firTaps,
    ...tail,
  ]);
}
