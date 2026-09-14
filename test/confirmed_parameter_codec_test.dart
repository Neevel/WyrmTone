import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/confirmed_parameter_codec.dart';
import 'package:wyrmtone/presets/protocol_evidence.dart';

List<int> bytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

void main() {
  const references = {
    40: 'f021257f514d453212100300020407000000000007000000000000000002000402f7',
    41: 'f021257f514d453212100300020407000000000007000000000000000002040402f7',
  };
  for (final entry in references.entries) {
    test('Gain ${entry.key} golden offline roundtrip', () {
      final original = bytes(entry.value);
      final decoded = ConfirmedParameterCodec.decode(original);
      expect(decoded.algorithmCode, 0x07000047);
      expect(decoded.parameterIndex, 0);
      expect(decoded.value, entry.key.toDouble());
      expect(ConfirmedParameterCodec.encodeReference(decoded), original);
      expect(decoded.status, 'offlineEncoded');
      expect(decoded.deviceWriteApproved, isFalse);
    });
  }
  test('Malformed messages are rejected without repairs', () {
    final original = bytes(references[40]!);
    for (final offset in [0, 4, 8, 12, 33]) {
      final corrupt = List<int>.of(original)..[offset] ^= 1;
      expect(
        () => ConfirmedParameterCodec.decode(corrupt),
        throwsFormatException,
      );
    }
    expect(
      () => ConfirmedParameterCodec.decode(original.sublist(1)),
      throwsFormatException,
    );
    for (final nibble in [-1, 16, 256]) {
      final corrupt = List<int>.of(original)..[13] = nibble;
      expect(
        () => ConfirmedParameterCodec.decode(corrupt),
        throwsFormatException,
      );
    }
  });
  test('NaN and infinity are rejected on decode and encode', () {
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      final original = bytes(references[40]!);
      final data = ByteData(4)..setFloat32(0, value, Endian.little);
      for (var i = 0; i < 4; i++) {
        original[25 + i * 2] = data.getUint8(i) >> 4;
        original[26 + i * 2] = data.getUint8(i) & 15;
      }
      expect(
        () => ConfirmedParameterCodec.decode(original),
        throwsFormatException,
      );
      expect(
        () => ConfirmedParameterCodec.encodeReference(
          OfflineParameterMessage(0x07000047, 0, value),
        ),
        throwsFormatException,
      );
    }
  });
  test('Only the two verified references can be offline encoded', () {
    for (final message in [
      const OfflineParameterMessage(0x07000059, 0, 41),
      const OfflineParameterMessage(0x07000047, 3, 41),
      const OfflineParameterMessage(0x07000047, 0, 42),
    ]) {
      expect(
        () => ConfirmedParameterCodec.encodeReference(message),
        throwsFormatException,
      );
    }
  });
  test('Confirmed one-shot evidence never approves production writes', () {
    expect(ProtocolEvidenceRegistry.decide('probe.gain41').allowed, isFalse);
    expect(ProtocolEvidenceRegistry.decide('preset.transfer').allowed, isFalse);
    expect(ProtocolEvidenceRegistry.decide('nonexistent').allowed, isFalse);
    expect(ProtocolEvidenceRegistry.decide('midi.device.open').allowed, isTrue);
    expect(
      ProtocolEvidenceRegistry.decide('algorithm.solLd').capability!.level,
      EvidenceLevel.correlated,
    );
    expect(
      ProtocolEvidenceRegistry.decide('algorithm.califCl').capability!.level,
      EvidenceLevel.correlated,
    );
  });
}
