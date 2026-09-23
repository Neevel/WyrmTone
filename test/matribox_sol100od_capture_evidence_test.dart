import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/confirmed_parameter_codec.dart';
import 'package:wyrmtone/presets/matribox_chain_encoder.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_transfer_catalog.dart';

import 'support/matribox_sol100od_write_fixtures.dart';

/// CONFIRMED protocol evidence: the six Sol 100 OD AMP parameter writes of the original editor store
/// capture (real host->device messages). They are decoded independently and reproduced byte-exact by
/// the PRODUCTIVE chain encoder -- no separate legacy encoder.
String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _bytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
];

void main() {
  test('fixtures are complete: all six parameters, real 34-byte host->device messages', () {
    expect(matriboxStoreCaptureSha256, hasLength(64));
    expect(matriboxStoreCaptureDirection, 'hostToDevice');
    expect(sol100OdCaptureFixtures.map((f) => f.field).toSet(), {
      'gain', 'presence', 'volume', 'bass', 'middle', 'treble',
    });
    for (final f in sol100OdCaptureFixtures) {
      expect(f.length, 34);
      expect(_bytes(f.hex), hasLength(34));
      expect(f.algorithmCode, 0x07000047);
    }
  });

  test('independent decode of every fixture matches its recorded metadata', () {
    for (final f in sol100OdCaptureFixtures) {
      final decoded = ConfirmedParameterCodec.decode(_bytes(f.hex));
      expect(decoded.algorithmCode, f.algorithmCode, reason: f.field);
      expect(decoded.parameterIndex, f.parameterIndex, reason: f.field);
      expect(decoded.value, f.value, reason: f.field);
    }
  });

  test('the productive encoder reproduces EXACT real capture bytes for all six fields', () {
    for (final f in sol100OdCaptureFixtures) {
      final parameter = matriboxSol100Od.parameters.singleWhere((p) => p.wireIndex == f.parameterIndex);
      expect(
        _hex(MatriboxChainEncoder.parameterWrite(MatriboxChainSlot.amp, matriboxSol100Od, parameter, f.value)),
        f.hex,
        reason: '${f.field}=${f.value} seq ${f.sequence}',
      );
    }
  });

  test('final captured values are the documented markers 17/73/47/23/67/31', () {
    const finals = {'gain': 17.0, 'presence': 73.0, 'volume': 47.0, 'bass': 23.0, 'middle': 67.0, 'treble': 31.0};
    for (final entry in finals.entries) {
      final last = sol100OdCaptureFixtures.lastWhere((f) => f.field == entry.key);
      expect(last.value, entry.value, reason: entry.key);
    }
  });
}
