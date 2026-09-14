import 'package:flutter/foundation.dart';

import 'dart:io';

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
import '../services/offline_sound_profiles.dart';
import '../models/tone_target.dart';
import '../tone3000/local_ir_record.dart';

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
  List<TargetSound> offlineProfiles = const [];
  PresetDraft? offlineDraft, offlinePreview, _originalDraft;
  PresetDraft? get offlineOriginalDraft => _originalDraft;
  final List<PresetDraft> _draftHistory = [];
  PresetDraft Function(ToneTarget, List<String>)? _draftFactory;
  bool offlineBusy = false;
  String? offlineMessage;
  int _offlineGeneration = 0;

  Future<void> loadOfflineProfiles() async {
    if (offlineProfiles.isNotEmpty || offlineBusy) return;
    offlineBusy = true;
    notifyListeners();
    try {
      offlineProfiles = await OfflineSoundProfiles.load();
    } catch (error) {
      offlineMessage = 'Offline-Profile konnten nicht geladen werden: $error';
    } finally {
      offlineBusy = false;
      notifyListeners();
    }
  }

  void clearOfflineDraft() {
    ++_offlineGeneration;
    offlineDraft = null;
    offlinePreview = null;
    _originalDraft = null;
    _draftHistory.clear();
    _draftFactory = null;
  }

  Future<void> createOfflineSound({
    required TargetSound sound,
    required GuitarTuning tuning,
    required SoundRole role,
    required List<LocalNamCapture> nams,
    required List<LocalIrRecord> irs,
    String? selectedNamId,
  }) async {
    if (offlineBusy) return;
    final guitar = selectedProfile;
    if (guitar == null) {
      offlineMessage = 'Bitte zuerst ein Gitarrenprofil wählen.';
      notifyListeners();
      return;
    }
    clearOfflineDraft();
    final generation = _offlineGeneration;
    final device = selectedTargetDevice;
    final namSnapshot = List<LocalNamCapture>.unmodifiable(nams);
    final irSnapshot = List<LocalIrRecord>.unmodifiable(irs);
    final folderSnapshot = List<IrLibraryEntry>.unmodifiable(libraryEntries);
    offlineBusy = true;
    offlineMessage = null;
    notifyListeners();
    try {
      final available = <String>{...folderFiles.map((f) => f.uri)};
      for (final path in [
        ...namSnapshot.map((n) => n.localUri),
        ...irSnapshot.map((i) => i.localUri),
      ]) {
        final uri = Uri.tryParse(path);
        if (uri?.scheme == 'file' && await File.fromUri(uri!).exists()) {
          available.add(path);
        }
      }
      if (generation != _offlineGeneration) {
        offlineMessage = 'Auswahl geändert; bitte neu erstellen.';
        return;
      }
      final first = engine.offline.create(
        device: device,
        profile: sound,
        guitar: guitar,
        tuning: tuning,
        role: role,
        nams: namSnapshot,
        irs: irSnapshot,
        folderIrs: folderSnapshot,
        availableUris: Set.unmodifiable(available),
        selectedNamId: selectedNamId,
      );
      _draftFactory = (tone, history) => engine.offline.create(
        device: device,
        profile: sound,
        guitar: guitar,
        tuning: tuning,
        role: role,
        nams: namSnapshot,
        irs: irSnapshot,
        folderIrs: folderSnapshot,
        availableUris: Set.unmodifiable(available),
        selectedNamId: selectedNamId,
        toneOverride: tone,
        history: history,
      );
      offlineDraft = first;
      _originalDraft = first;
      offlineMessage = 'Offline erstellt · Keine KI verwendet · Noch keine Übertragung an die Matribox.';
    } catch (error) {
      offlineMessage = 'Kein Draft erstellt: $error';
    } finally {
      offlineBusy = false;
      notifyListeners();
    }
  }

  void previewCorrection(RecommendationFeedback feedback) {
    final current = offlineDraft,
        baseline = _originalDraft,
        factory = _draftFactory;
    if (current == null || baseline == null || factory == null) return;
    final corrected = engine.offline.corrected(
      current.tone,
      baseline.tone,
      feedback,
    );
    offlinePreview = factory(corrected, [
      ...current.history,
      '${feedback.label}: begrenzte, manuell bestätigte Klangkorrektur.',
    ]);
    notifyListeners();
  }

  void applyCorrection() {
    final current = offlineDraft, preview = offlinePreview;
    if (current == null || preview == null) return;
    _draftHistory.add(current);
    offlineDraft = preview;
    offlinePreview = null;
    notifyListeners();
  }

  void cancelCorrection() {
    offlinePreview = null;
    notifyListeners();
  }

  void undoCorrection() {
    if (_draftHistory.isEmpty) return;
    offlineDraft = _draftHistory.removeLast();
    offlinePreview = null;
    notifyListeners();
  }

  void resetCorrections() {
    offlineDraft = _originalDraft;
    offlinePreview = null;
    _draftHistory.clear();
    notifyListeners();
  }

  bool get canUndoCorrection => _draftHistory.isNotEmpty;

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
    clearOfflineDraft();
    selectedProfileId = id;
    notifyListeners();
  }

  void selectSound(String id) {
    selectedSoundId = id;
    notifyListeners();
  }

  void selectTargetDevice(TargetDeviceId id) {
    clearOfflineDraft();
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
