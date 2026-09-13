import 'package:wyrmtone/controllers/recommendation_controller.dart';
import 'package:wyrmtone/models/guitar_profile.dart';
import 'package:wyrmtone/models/ir_metadata.dart';
import 'package:wyrmtone/screens/recommendation_page.dart';
import 'package:wyrmtone/services/local_persistence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recommendation_fakes.dart';

void main() {
  testWidgets('renders deterministic settings and three ranked IR candidates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryStringStore();
    final picker = FakeIrFilePicker(const [
      PickedIrFile(
        fileName: 'Marshall_1960_V30_SM57_CapEdge.wav',
        uri: 'content://ir/1',
      ),
      PickedIrFile(
        fileName: 'Mesa_OS_V30_MD421_OffAxis.wav',
        uri: 'content://ir/2',
      ),
      PickedIrFile(
        fileName: 'Orange_4x12_Greenback_R121_Room.wav',
        uri: 'content://ir/3',
      ),
    ]);
    final controller = RecommendationController(
      profileRepository: ProfileRepository(store),
      irRepository: IrCatalogRepository(store),
      filePicker: picker,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.saveProfile(
      const GuitarProfile(
        id: 'alexi',
        name: 'Alexi Superstrat',
        guitarType: GuitarType.superstrat,
        pickupType: PickupType.passiveHumbucker,
        outputLevel: OutputLevel.high,
        toneCharacter: ToneCharacter.bright,
        tuning: GuitarTuning.dStandard,
        playbackPath: PlaybackPath.frfr,
      ),
    );
    controller.selectSound('cob-angels-dont-kill');
    await controller.selectIrFolder();

    await tester.pumpWidget(
      MaterialApp(home: RecommendationPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('PURE BOOST'), findsWidgets);
    expect(find.textContaining('GAIN: 64'), findsOneWidget);
    expect(controller.recommendation!.irCandidates, hasLength(3));
    for (final fileName in [
      'Marshall_1960_V30_SM57_CapEdge.wav',
      'Mesa_OS_V30_MD421_OffAxis.wav',
      'Orange_4x12_Greenback_R121_Room.wav',
    ]) {
      final candidate = find.byKey(Key('ir-recommendation-$fileName'));
      expect(candidate, findsOneWidget);
    }
    final fineTune = find.textContaining('Ausgangspunkt zum Feinabstimmen');
    expect(fineTune, findsOneWidget);
  });
}
