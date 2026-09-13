import 'ir_metadata.dart';
import '../nam/local_nam_capture.dart';

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
}

extension RecommendationFeedbackLabel on RecommendationFeedback {
  String get label => switch (this) {
    RecommendationFeedback.tooDark => 'Zu dumpf',
    RecommendationFeedback.tooBright => 'Zu schrill',
    RecommendationFeedback.tooLittleGain => 'Zu wenig Gain',
    RecommendationFeedback.tooMuchGain => 'Zu viel Gain',
    RecommendationFeedback.tooThin => 'Zu dünn',
    RecommendationFeedback.tooMuddy => 'Zu matschig',
    RecommendationFeedback.gateCutsNotes => 'Gate schneidet Töne ab',
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
  };
}
