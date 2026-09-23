/// The state of the unified sound flow: the (lazily loaded) sound library, the sound the user is
/// working on, recent sounds and their persistence. The local draft itself stays in
/// [RecommendationController]; this session creates it and can rebuild it after an app restart.
library;

import 'package:flutter/foundation.dart';

import '../controllers/recommendation_controller.dart';
import '../controllers/tone3000_controller.dart';
import '../devices/device_profile.dart';
import '../models/guitar_profile.dart';
import '../presets/device_catalog.dart';
import '../presets/matribox_tone_transfer_pipeline.dart';
import '../tonevault/tone_definition.dart';
import '../tonevault/tone_vault.dart';
import 'sound_selection.dart';

class SoundSession extends ChangeNotifier {
  SoundSession({
    required this.controller,
    required this.repository,
    this.tone3000,
    Future<ToneVault> Function()? vaultLoader,
  }) : _vaultLoader = vaultLoader ?? ToneVault.loadAssets;

  final RecommendationController controller;
  final SoundSelectionRepository repository;
  final Tone3000Controller? tone3000;
  final Future<ToneVault> Function() _vaultLoader;

  ToneVault? vault;
  Object? vaultError;
  Future<void>? _loading;

  /// The sound the user is working on (also the one restored after a restart).
  SoundSelection? current;
  List<SoundSelection> recent = const [];

  /// A saved sound that could not be restored (library changed or data damaged).
  bool restoreFailed = false;

  /// A short, user-facing message about the last action (null = nothing to say).
  String? notice;
  bool busy = false;

  /// Loads the library and the saved state once. Safe to call from several widgets.
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      vault = await _vaultLoader();
      final saved = await repository.loadCurrent();
      final all = await repository.loadRecent();
      final v = vault!;
      recent = [for (final s in all) if (v.entry(s.entryId) != null) s];
      if (saved != null) {
        if (v.entry(saved.entryId) == null) {
          restoreFailed = true;
        } else {
          current = saved;
        }
      }
    } catch (error) {
      vaultError = error;
    }
    notifyListeners();
  }

  bool get ready => vault != null;

  /// After a failed load: try again.
  Future<void> retryLoad() {
    vaultError = null;
    _loading = null;
    notifyListeners();
    return ensureLoaded();
  }

  ToneDefinition? definitionOf(SoundSelection s) {
    final v = vault;
    if (v == null || v.entry(s.entryId) == null) return null;
    return v.definitionFor(s.entryId, variant: s.variant, query: s.toQuery());
  }

  /// Creates the local sound from [selection]. Returns false (with a [notice]) when that is not possible.
  Future<bool> use(SoundSelection selection, {String? selectedNamId, bool remember = true}) async {
    await ensureLoaded();
    final v = vault;
    if (v == null) {
      notice = 'Die Sound-Bibliothek konnte nicht geladen werden.';
      notifyListeners();
      return false;
    }
    if (controller.selectedProfile == null) {
      notice = 'Bitte zuerst unter „Profil“ eine Gitarre anlegen.';
      notifyListeners();
      return false;
    }
    final definition = definitionOf(selection);
    if (definition == null) {
      notice = 'Dieser Sound ist nicht mehr verfügbar.';
      notifyListeners();
      return false;
    }
    busy = true;
    notice = null;
    notifyListeners();
    try {
      await controller.createOfflineSound(
        sound: definition.toTargetSound(),
        tuning: selection.tuning,
        role: definition.role,
        nams: tone3000?.namCaptures ?? const [],
        irs: tone3000?.localRecords ?? const [],
        selectedNamId: selectedNamId,
      );
      if (controller.offlineDraft == null) {
        notice = controller.offlineMessage ?? 'Der Sound konnte nicht erstellt werden.';
        return false;
      }
      current = selection;
      restoreFailed = false;
      if (remember) {
        await repository.saveCurrent(selection);
        recent = await repository.addRecent(selection);
      }
      return true;
    } catch (_) {
      notice = 'Der Sound konnte nicht erstellt werden.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Makes sure the local sound exists for [current] (after a restart there is none yet).
  Future<bool> reopen() async {
    await ensureLoaded();
    final sel = current;
    if (sel == null) return false;
    if (controller.offlineDraft != null) return true;
    return use(sel, remember: false);
  }

  /// The created sound as a Matribox target: local sound (with the user's wishes, guitar and tuning
  /// corrections already in it) -> recipe -> device translation. Nothing is sent and no device is read.
  /// The sound is NOT looked up again in the library: the current local sound is the source of truth.
  Future<ToneTransferRecommendation?> prepareForMatribox(DevicePresetCatalog catalog) async {
    final sel = current;
    if (sel == null) return null;
    if (controller.selectedTargetDevice != TargetDeviceId.matriboxOne || controller.offlineDraft == null) {
      final nam = controller.offlineDraft?.selectedNamId;
      controller.selectTargetDevice(TargetDeviceId.matriboxOne);
      if (!await use(sel, remember: false, selectedNamId: nam)) return null;
    }
    final draft = controller.offlineDraft;
    if (draft == null || draft.device != TargetDeviceId.matriboxOne) return null;
    try {
      return MatriboxToneTransferPipeline.fromDraft(draft, catalog: catalog);
    } catch (_) {
      notice = 'Der Sound konnte nicht für die Matribox vorbereitet werden.';
      notifyListeners();
      return null;
    }
  }

  Future<void> discardCurrent() async {
    current = null;
    restoreFailed = false;
    notice = null;
    controller.clearOfflineDraft();
    await repository.clearCurrent();
    notifyListeners();
  }

  /// The tuning to start from: the guitar's own, else the sound's reference tuning, else Drop C.
  GuitarTuning defaultTuning(ToneDefinition definition) =>
      controller.selectedProfile?.tuning ?? definition.referenceTuning ?? GuitarTuning.dropC;
}
