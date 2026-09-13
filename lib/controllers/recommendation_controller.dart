import 'package:flutter/foundation.dart';

import '../data/dnafx_capabilities.dart';
import '../data/target_sounds.dart';
import '../devices/device_profile.dart';
import '../models/guitar_profile.dart';
import '../models/ir_catalog_entry.dart';
import '../models/ir_metadata.dart';
import '../models/recommendation.dart';
import '../models/target_sound.dart';
import '../services/ir_file_picker_service.dart';
import '../services/ir_filename_parser.dart';
import '../services/ir_reference_catalog_service.dart';
import '../services/local_persistence.dart';
import '../nam/local_nam_capture.dart';
import '../services/recommendation_engine.dart';
import '../services/nam_recommendation_engine.dart';

class RecommendationController extends ChangeNotifier {
  RecommendationController({
    required this.profileRepository,
    required this.irRepository,
    required this.filePicker,
    this.referenceCatalogService = const EmptyIrReferenceCatalogService(),
    this.parser = const IrFilenameParser(),
    this.engine = const RecommendationEngine(),
    this.namEngine = const NamRecommendationEngine(),
  });

  final ProfileRepository profileRepository;
  final IrCatalogRepository irRepository;
  final IrFilePickerService filePicker;
  final IrReferenceCatalogService referenceCatalogService;
  final IrFilenameParser parser;
  final RecommendationEngine engine;
  final NamRecommendationEngine namEngine;
  TargetDeviceId selectedTargetDevice = TargetDeviceId.dnafxGitCore;

  List<GuitarProfile> profiles = const [];
  List<IrCatalogEntry> referenceCatalog = const [];
  List<PickedIrFile> folderFiles = const [];
  List<IrLibraryEntry> libraryEntries = const [];
  List<IrMetadata> irCatalog = const [];
  String? selectedFolderUri;
  List<TargetSound> get sounds => targetSounds;
  String? selectedProfileId;
  String selectedSoundId = targetSounds.first.id;
  bool busy = false;
  String? message;

  int countFor(IrAvailabilityStatus status) =>
      libraryEntries.where((entry) => entry.status == status).length;

  GuitarProfile? get selectedProfile {
    for (final profile in profiles) {
      if (profile.id == selectedProfileId) return profile;
    }
    return null;
  }

  TargetSound get selectedSound =>
      sounds.firstWhere((sound) => sound.id == selectedSoundId);

  SoundRecommendation? get recommendation {
    if (selectedTargetDevice != TargetDeviceId.dnafxGitCore) return null;
    final profile = selectedProfile;
    if (profile == null) return null;
    return engine.recommend(
      target: selectedSound,
      guitar: profile,
      irCatalog: irCatalog,
      capabilities: confirmedDnafxCapabilities,
    );
  }

  Future<void> initialize() async {
    try {
      profiles = await profileRepository.load();
      referenceCatalog = await referenceCatalogService.load();
      final restoredFolder = await filePicker.restorePersistedWavFolder();
      if (restoredFolder != null) _applyFolder(restoredFolder);
      _rebuildLibrary();
      selectedProfileId = profiles.firstOrNull?.id;
    } catch (error) {
      message = 'Lokale Daten konnten nicht geladen werden: $error';
    }
    notifyListeners();
  }

  Future<void> saveProfile(GuitarProfile profile) async {
    final updated = [...profiles];
    final index = updated.indexWhere((item) => item.id == profile.id);
    if (index < 0) {
      updated.add(profile);
    } else {
      updated[index] = profile;
    }
    profiles = updated;
    selectedProfileId = profile.id;
    await profileRepository.save(profiles);
    message = 'Gitarrenprofil gespeichert.';
    notifyListeners();
  }

  void selectProfile(String id) {
    selectedProfileId = id;
    notifyListeners();
  }

  void selectSound(String id) {
    selectedSoundId = id;
    notifyListeners();
  }

  void selectTargetDevice(TargetDeviceId id) {
    selectedTargetDevice = id;
    notifyListeners();
  }

  List<NamRecommendation> namRecommendations(List<LocalNamCapture> captures) =>
      namEngine.recommend(
        device: selectedTargetDevice,
        target: selectedSound,
        captures: captures,
      );

  Future<void> selectIrFolder() async {
    if (busy) return;
    busy = true;
    message = null;
    notifyListeners();
    try {
      final folder = await filePicker.pickWavFolder();
      if (folder == null) {
        message = 'Ordnerauswahl abgebrochen.';
      } else {
        _applyFolder(folder);
        _rebuildLibrary();
        message = '${folder.files.length} WAV-Datei(en) im Ordner gefunden.';
      }
    } catch (error) {
      message = 'IR-Ordner konnte nicht gelesen werden: $error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _applyFolder(PickedIrFolder folder) {
    selectedFolderUri = folder.treeUri;
    folderFiles = folder.files;
  }

  void _rebuildLibrary() {
    final filesByName = <String, List<PickedIrFile>>{};
    for (final file in folderFiles) {
      filesByName
          .putIfAbsent(parser.normalizeFileName(file.fileName), () => [])
          .add(file);
    }

    final duplicateGroupFileCounts = <String, int>{};
    for (final reference in referenceCatalog) {
      final group = reference.duplicateGroup;
      if (group != null) {
        duplicateGroupFileCounts[group] =
            (duplicateGroupFileCounts[group] ?? 0) +
            (filesByName[reference.normalizedFileName]?.length ?? 0);
      }
    }

    final entries = <IrLibraryEntry>[];
    final knownNames = <String>{};
    final availableMetadata = <IrMetadata>[];
    for (final reference in referenceCatalog) {
      knownNames.add(reference.normalizedFileName);
      final matches = filesByName[reference.normalizedFileName] ?? const [];
      final isDuplicate =
          matches.length > 1 ||
          (reference.duplicateGroup != null &&
              (duplicateGroupFileCounts[reference.duplicateGroup] ?? 0) > 1);
      final status = matches.isEmpty
          ? IrAvailabilityStatus.missing
          : isDuplicate
          ? IrAvailabilityStatus.duplicate
          : IrAvailabilityStatus.present;
      final metadata = matches.isEmpty
          ? reference.metadata
          : reference.metadata.copyWith(uri: matches.first.uri);
      entries.add(
        IrLibraryEntry(
          metadata: metadata,
          status: status,
          matchedFiles: matches,
          reference: reference,
        ),
      );
      if (matches.isNotEmpty) availableMetadata.add(metadata);
    }

    for (final group in filesByName.entries) {
      if (knownNames.contains(group.key)) continue;
      final status = group.value.length > 1
          ? IrAvailabilityStatus.duplicate
          : IrAvailabilityStatus.unknown;
      final metadata = parser.parse(
        group.value.first.fileName,
        uri: group.value.first.uri,
      );
      entries.add(
        IrLibraryEntry(
          metadata: metadata,
          status: status,
          matchedFiles: group.value,
        ),
      );
      availableMetadata.add(metadata);
    }
    libraryEntries = entries;
    irCatalog = irRepository.merge(const [], availableMetadata);
  }
}
