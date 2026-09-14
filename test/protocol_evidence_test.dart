import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/protocol_evidence.dart';

void main() {
  test('capability matrix keeps Matribox 1 and II Pro evidence separate', () {
    final capabilities = ProtocolEvidenceRegistry.capabilities;
    expect(
      capabilities.map((entry) => entry.id).toSet().length,
      capabilities.length,
    );

    final presetSelect = capabilities.singleWhere(
      (entry) => entry.id == 'preset.select',
    );
    expect(presetSelect.level, EvidenceLevel.correlated);
    expect(
      presetSelect.description,
      contains('confirmed targets are listed separately'),
    );
    expect(presetSelect.knownLengths, [22]);
    expect(presetSelect.matriboxOneTested, isTrue);
    expect(presetSelect.matriboxIiProTested, isFalse);
    expect(presetSelect.productionApproved, isFalse);

    final looper = capabilities.singleWhere((entry) => entry.id == 'looper');
    expect(looper.sourceTarget, 'matriboxIiPro');
    expect(looper.level, EvidenceLevel.unknown);
    expect(looper.matriboxOneTested, isFalse);
    expect(looper.matriboxIiProTested, isTrue);
    expect(looper.productionApproved, isFalse);
  });

  test(
    'machine-readable capability output contains required evidence fields',
    () {
      final json = ProtocolEvidenceRegistry.capabilities.first.toJson();
      for (final key in [
        'sourceTarget',
        'messageFamily',
        'knownLengths',
        'relevantOffsets',
        'direction',
        'matriboxOneTested',
        'matriboxIiProTested',
        'hardwareTestPossible',
        'nextEvidenceStep',
      ]) {
        expect(json, contains(key));
      }
    },
  );
}
