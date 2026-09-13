import 'package:wyrmtone/controllers/recommendation_controller.dart';
import 'package:wyrmtone/models/ir_catalog_entry.dart';
import 'package:wyrmtone/models/ir_metadata.dart';
import 'package:wyrmtone/services/local_persistence.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recommendation_fakes.dart';

void main() {
  test('reimporting the same Android URI does not create duplicates', () async {
    final store = MemoryStringStore();
    final picker = FakeIrFilePicker(const [
      PickedIrFile(
        fileName: 'Marshall_1960_V30_SM57_CapEdge.wav',
        uri: 'content://ir/one',
      ),
    ]);
    final controller = RecommendationController(
      profileRepository: ProfileRepository(store),
      irRepository: IrCatalogRepository(store),
      filePicker: picker,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    await controller.selectIrFolder();
    await controller.selectIrFolder();

    expect(controller.irCatalog, hasLength(1));
    expect(controller.irCatalog.single.speaker, 'V30');
  });

  test(
    'reference IR stays missing until matching folder file exists',
    () async {
      final store = MemoryStringStore();
      final repository = IrCatalogRepository(store);
      final controller = RecommendationController(
        profileRepository: ProfileRepository(store),
        irRepository: repository,
        filePicker: FakeIrFilePicker(),
        referenceCatalogService: FakeIrReferenceCatalog([
          IrCatalogEntry(
            metadata: IrMetadata(
              fileName: 'ArchEnemy_DoomsdayMachine.wav',
              confidence: 0,
              detectedTags: [],
            ),
            normalizedFileName: 'archenemy doomsdaymachine',
            format: WavFormatInfo(
              container: 'WAV',
              encoding: 'PCM',
              sampleRateHz: 44100,
              channels: 1,
              bitsPerSample: 24,
              durationMs: 500,
            ),
            suitabilityHints: ['Modern Metal'],
          ),
        ]),
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.countFor(IrAvailabilityStatus.missing), 1);
      expect(controller.irCatalog, isEmpty);
      expect(await repository.load(), isEmpty);
    },
  );

  test(
    'restored folder reports present missing unknown and duplicate',
    () async {
      final store = MemoryStringStore();
      final picker = FakeIrFilePicker()
        ..restoredFolder = const PickedIrFolder(
          treeUri: 'content://tree/persisted',
          files: [
            PickedIrFile(fileName: 'Known.wav', uri: 'content://known'),
            PickedIrFile(fileName: 'Dupe One.wav', uri: 'content://dupe-1'),
            PickedIrFile(fileName: 'DupeTwo.wav', uri: 'content://dupe-2'),
            PickedIrFile(fileName: 'Mystery.wav', uri: 'content://mystery'),
            PickedIrFile(fileName: 'Copy.wav', uri: 'content://copy-1'),
            PickedIrFile(fileName: 'copy.WAV', uri: 'content://copy-2'),
          ],
        );
      final controller = RecommendationController(
        profileRepository: ProfileRepository(store),
        irRepository: IrCatalogRepository(store),
        filePicker: picker,
        referenceCatalogService: FakeIrReferenceCatalog([
          _reference('Known.wav', 'known'),
          _reference('Missing.wav', 'missing'),
          _reference('Dupe One.wav', 'dupe one', duplicateGroup: 'same-audio'),
          _reference('DupeTwo.wav', 'dupetwo', duplicateGroup: 'same-audio'),
        ]),
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.selectedFolderUri, 'content://tree/persisted');
      expect(controller.countFor(IrAvailabilityStatus.present), 1);
      expect(controller.countFor(IrAvailabilityStatus.missing), 1);
      expect(controller.countFor(IrAvailabilityStatus.unknown), 1);
      expect(controller.countFor(IrAvailabilityStatus.duplicate), 3);
    },
  );
}

IrCatalogEntry _reference(
  String fileName,
  String normalizedFileName, {
  String? duplicateGroup,
}) => IrCatalogEntry(
  metadata: IrMetadata(
    fileName: fileName,
    confidence: 0,
    detectedTags: const [],
  ),
  normalizedFileName: normalizedFileName,
  format: const WavFormatInfo(
    container: 'WAV',
    encoding: 'PCM',
    sampleRateHz: 44100,
    channels: 1,
    bitsPerSample: 24,
    durationMs: 500,
  ),
  suitabilityHints: const [],
  duplicateGroup: duplicateGroup,
);
