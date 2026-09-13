import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/models/ir_metadata.dart';
import 'package:wyrmtone/services/local_persistence.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recommendation_fakes.dart';

void main() {
  test('saves and loads a complete guitar profile', () async {
    final repository = ProfileRepository(MemoryStringStore());
    const profile = GuitarProfile(
      id: 'g1',
      name: 'Alexi Test',
      guitarType: GuitarType.superstrat,
      pickupType: PickupType.passiveHumbucker,
      outputLevel: OutputLevel.high,
      toneCharacter: ToneCharacter.bright,
      tuning: GuitarTuning.dStandard,
      stringGauge: '11–52',
      playbackPath: PlaybackPath.frfr,
    );

    await repository.save([profile]);
    final loaded = await repository.load();

    expect(loaded.single.name, 'Alexi Test');
    expect(loaded.single.pickupType, PickupType.passiveHumbucker);
    expect(loaded.single.stringGauge, '11–52');
  });

  test('IR merge prevents duplicate URI and normalized filename keys', () {
    final repository = IrCatalogRepository(MemoryStringStore());
    const first = IrMetadata(
      fileName: 'A.wav',
      uri: 'content://IR/1',
      confidence: 0,
      detectedTags: [],
    );
    const replacement = IrMetadata(
      fileName: 'renamed.wav',
      uri: 'CONTENT://ir/1',
      confidence: 0.8,
      detectedTags: ['V30'],
    );

    final merged = repository.merge([first], [replacement]);
    expect(merged, hasLength(1));
    expect(merged.single.fileName, 'renamed.wav');
  });
}
