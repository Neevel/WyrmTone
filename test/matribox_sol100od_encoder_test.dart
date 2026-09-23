import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/confirmed_parameter_codec.dart';
import 'package:wyrmtone/presets/matribox_amp_field_evidence.dart';
import 'package:wyrmtone/presets/matribox_sol100od_encoder.dart';

import 'support/matribox_sol100od_write_fixtures.dart';

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
      expect(
        MatriboxAmpFieldEvidenceRegistry.forField(f.field)!.catalogIndex,
        f.parameterIndex,
      );
    }
  });

  test('encoder reproduces EXACT real capture bytes for all six fields', () {
    for (final f in sol100OdCaptureFixtures) {
      expect(
        _hex(MatriboxSol100OdEncoder.encode(f.field, f.value)),
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

  test('the six formats differ only in the index nibble and the value nibbles', () {
    final a = _bytes(sol100OdCaptureFixtures.first.hex);
    for (final f in sol100OdCaptureFixtures) {
      final b = _bytes(f.hex);
      for (var i = 0; i < 34; i++) {
        if (i == 22 || (i >= 25 && i <= 32)) continue;
        expect(b[i], a[i], reason: 'byte $i of ${f.field} must be constant');
      }
    }
  });

  test('ENCODABLE is not HARDWARE_WRITABLE: only Gain may be sent', () {
    for (final e in MatriboxAmpFieldEvidenceRegistry.all) {
      expect(e.encodable, isTrue, reason: e.field);
      expect(e.rawWriteCaptureEvidence.name, 'confirmed', reason: e.field);
      expect(e.hardwareWritable, e.field == 'gain', reason: e.field);
    }
  });

  test('encoder rejects unknown fields and out-of-range values', () {
    expect(() => MatriboxSol100OdEncoder.encode('reverb', 10), throwsA(isA<UnencodableMatriboxField>()));
    expect(() => MatriboxSol100OdEncoder.encode('presence', -1), throwsA(isA<UnencodableMatriboxField>()));
    expect(() => MatriboxSol100OdEncoder.encode('presence', 100), throwsA(isA<UnencodableMatriboxField>()));
    expect(() => MatriboxSol100OdEncoder.encode('presence', double.nan), throwsA(isA<UnencodableMatriboxField>()));
  });
}
