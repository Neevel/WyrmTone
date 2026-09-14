import 'ir_metadata.dart';
import '../nam/local_nam_capture.dart';
import '../devices/device_profile.dart';
import 'guitar_profile.dart';
import 'target_sound.dart';
import 'tone_target.dart';

class ParameterRecommendation {
  const ParameterRecommendation({
    required this.name,
    required this.baseValue,
    required this.value,
    required this.reasons,
    required this.confirmed,
  });

  final String name;
  final int baseValue;
  final int value;
  final List<String> reasons;
  final bool confirmed;
}

class NamRecommendation {
  const NamRecommendation({
    required this.capture,
    required this.score,
    required this.reasons,
    required this.additionalIrRequired,
    required this.uncertainties,
  });
  final LocalNamCapture capture;
  final int score;
  final List<String> reasons;
  final bool? additionalIrRequired;
  final List<String> uncertainties;
}

class IrRecommendation {
  const IrRecommendation({
    required this.ir,
    required this.score,
    required this.reasons,
    required this.isUncertain,
  });

  final IrMetadata ir;
  final int score;
  final List<String> reasons;
  final bool isUncertain;
}

class SoundRecommendation {
  const SoundRecommendation({
    required this.ampModel,
    required this.effectChain,
    required this.parameters,
    required this.irCandidates,
    required this.cabSimulationEnabled,
    required this.reasons,
    required this.warnings,
  });

  final String ampModel;
  final List<String> effectChain;
  final List<ParameterRecommendation> parameters;
  final List<IrRecommendation> irCandidates;
  final bool cabSimulationEnabled;
  final List<String> reasons;
  final List<String> warnings;
}

enum RecommendationFeedback {
  tooDark,
  tooBright,
  tooLittleGain,
  tooMuchGain,
  tooThin,
  tooMuddy,
  gateCutsNotes,
  tooBassy,
  tooNasal,
  notCutting,
  softAttack,
  lowSustain,
  tooWet,
  tooDry,
}

extension RecommendationFeedbackLabel on RecommendationFeedback {
  String get label => switch (this) {
    RecommendationFeedback.tooDark => 'Zu dumpf',
    RecommendationFeedback.tooBright => 'Zu schrill',
    RecommendationFeedback.tooLittleGain => 'Zu wenig Gain',
    RecommendationFeedback.tooMuchGain => 'Zu viel Gain',
    RecommendationFeedback.tooThin => 'Zu dünn',
    RecommendationFeedback.tooMuddy => 'Zu matschig',
    RecommendationFeedback.gateCutsNotes => 'Gate frisst Töne',
    RecommendationFeedback.tooBassy => 'Zu bassig',
    RecommendationFeedback.tooNasal => 'Zu mittig/nasal',
    RecommendationFeedback.notCutting => 'Setzt sich nicht durch',
    RecommendationFeedback.softAttack => 'Anschläge zu weich',
    RecommendationFeedback.lowSustain => 'Zu wenig Sustain',
    RecommendationFeedback.tooWet => 'Zu viel Hall',
    RecommendationFeedback.tooDry => 'Zu trocken',
  };

  String get proposedCorrection => switch (this) {
    RecommendationFeedback.tooDark =>
      'TREBLE/PRESENCE vorsichtig erhöhen oder hellere IR wählen.',
    RecommendationFeedback.tooBright =>
      'TREBLE/PRESENCE vorsichtig senken oder wärmere IR wählen.',
    RecommendationFeedback.tooLittleGain =>
      'GAIN oder bestätigten Boost moderat erhöhen.',
    RecommendationFeedback.tooMuchGain => 'GAIN reduzieren.',
    RecommendationFeedback.tooThin =>
      'BASS/Mitten vorsichtig erhöhen oder vollere IR wählen.',
    RecommendationFeedback.tooMuddy =>
      'BASS/GAIN reduzieren und straffere IR wählen.',
    RecommendationFeedback.gateCutsNotes => 'DNAfx-spezifisch: ATTACK erhöhen, damit das Gate schneller öffnet; nicht senken.',
    RecommendationFeedback.tooBassy => 'Bass vorsichtig reduzieren.',
    RecommendationFeedback.tooNasal => 'Mitten moderat reduzieren.',
    RecommendationFeedback.notCutting =>
      'Mitten erhöhen, Bass kontrollieren; keine Lautstärkeanhebung.',
    RecommendationFeedback.softAttack => 'Straffheit und Anschlag erhöhen.',
    RecommendationFeedback.lowSustain => 'Sustain moderat erhöhen.',
    RecommendationFeedback.tooWet => 'Hallanteil reduzieren.',
    RecommendationFeedback.tooDry => 'Räumlichkeit moderat erhöhen.',
  };
}

class DraftCandidate {
  DraftCandidate({
    required this.id,
    required this.name,
    required Map<String, int> parts,
    this.reasons = const [],
    this.exclusions = const [],
    this.uncertainties = const [],
    this.localAvailable = true,
    this.manualDownload = false,
  }) : parts = Map.unmodifiable(parts);
  final String id, name;
  final Map<String, int> parts;
  final List<String> reasons, exclusions, uncertainties;
  final bool localAvailable, manualDownload;
  int get score => parts.values.fold(0, (a, b) => a + b).clamp(0, 100);
  bool get eligible => exclusions.isEmpty;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'score': score,
    'parts': parts,
    'reasons': reasons,
    'exclusions': exclusions,
    'uncertainties': uncertainties,
    'localAvailable': localAvailable,
    'manualDownload': manualDownload,
  };
}

class DraftBlock {
  const DraftBlock({
    required this.slot,
    required this.model,
    required this.enabled,
    required this.parameters,
    required this.provenance,
    required this.note,
  });
  final String slot;
  final String? model;
  final bool enabled;
  final Map<String, int> parameters;
  final Map<String, String> provenance;
  final String note;
  Map<String, Object?> toJson() => {
    'slot': slot,
    'model': model,
    'enabled': enabled,
    'parameters': parameters,
    'provenance': provenance,
    'note': note,
  };
}

class PresetDraft {
  const PresetDraft({
    required this.device,
    required this.profile,
    required this.guitar,
    required this.tuning,
    required this.role,
    required this.tone,
    required this.blocks,
    required this.candidates,
    required this.reasons,
    required this.warnings,
    required this.history,
    required this.searchRequirements,
    this.selectedNamId,
  });
  final TargetDeviceId device;
  final TargetSound profile;
  final GuitarProfile guitar;
  final GuitarTuning tuning;
  final SoundRole role;
  final ToneTarget tone;
  final List<DraftBlock> blocks;
  final Map<String, List<DraftCandidate>> candidates;
  final List<String> reasons, warnings, history, searchRequirements;
  final String? selectedNamId;
  bool get cabEnabled => blocks.any((b) => b.slot == 'CAB' && b.enabled);
  Map<String, Object?> toJson() => {
    'device': device.name,
    'profile': profile.id,
    'profileVersion': tone.version,
    'guitar': guitar.toJson(),
    'tuning': tuning.name,
    'role': role.name,
    'tone': tone.values.map((k, v) => MapEntry(k.name, v)),
    'confidence': tone.confidence,
    'source': tone.source,
    'selectedNamId': selectedNamId,
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'candidates': candidates.map(
      (k, v) => MapEntry(k, v.map((c) => c.toJson()).toList()),
    ),
    'reasons': reasons,
    'warnings': warnings,
    'history': history,
    'searchRequirements': searchRequirements,
  };
}
