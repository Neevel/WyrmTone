import 'dart:typed_data';

/// Offline analysis only. This library has no transport or platform channel.
class OfflineParameterMessage {
  const OfflineParameterMessage(
    this.algorithmCode,
    this.parameterIndex,
    this.value,
  );
  final int algorithmCode, parameterIndex;
  final double value;
  String get status => 'offlineEncoded';
  bool get deviceWriteApproved => false;
}

abstract final class ConfirmedParameterCodec {
  static const _prefix = [
    0xf0,
    0x21,
    0x25,
    0x7f,
    0x51,
    0x4d,
    0x45,
    0x32,
    0x12,
    0x10,
    0x03,
    0x00,
    0x02,
  ];
  // Bytes 8..12 are observed constants, not inferred block or command IDs.
  static OfflineParameterMessage decode(List<int> bytes) {
    if (bytes.length != 34 || bytes.last != 0xf7) {
      throw const FormatException('Expected complete 34-byte QME2 message.');
    }
    for (var i = 0; i < _prefix.length; i++) {
      if (bytes[i] != _prefix[i]) {
        throw const FormatException('Unknown message header.');
      }
    }
    final decoded = Uint8List(10);
    for (var i = 0; i < 10; i++) {
      final high = bytes[13 + i * 2], low = bytes[14 + i * 2];
      if (high < 0 || high > 15 || low < 0 || low > 15) {
        throw const FormatException('Invalid nibble.');
      }
      decoded[i] = high * 16 + low;
    }
    final data = ByteData.sublistView(decoded);
    final value = data.getFloat32(6, Endian.little);
    if (!value.isFinite) {
      throw const FormatException('Non-finite parameter value.');
    }
    return OfflineParameterMessage(
      data.getUint32(0, Endian.little),
      data.getUint16(4, Endian.little),
      value,
    );
  }

  /// Encoding is deliberately limited to the two byte-confirmed references.
  /// Structural decoding of other observed values is not writing permission.
  static List<int> encodeReference(OfflineParameterMessage message) {
    if (message.algorithmCode != 0x07000047 ||
        message.parameterIndex != 0 ||
        !message.value.isFinite ||
        (message.value != 40 && message.value != 41)) {
      throw const FormatException(
        'Only verified Sol 100 OD Gain 40/41 references may be encoded.',
      );
    }
    final data = ByteData(10)
      ..setUint32(0, message.algorithmCode, Endian.little)
      ..setUint16(4, message.parameterIndex, Endian.little)
      ..setFloat32(6, message.value, Endian.little);
    return List.unmodifiable([
      ..._prefix,
      for (final byte in data.buffer.asUint8List()) ...[byte >> 4, byte & 15],
      0xf7,
    ]);
  }
}
