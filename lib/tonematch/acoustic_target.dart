/// Mapping layer ToneIntent -> AcousticTargetProfile.
///
/// A [ToneIntent] speaks in semantic dimensions ("tight", "gain 72"); an analysed NAM speaks in
/// measured audio features. The two spaces are NOT compared directly. This layer states only those
/// acoustic DIRECTIONS for which a defensible relation exists, as RELATIVE targets (no absolute
/// Hz/dB values), each with its evidence. Everything else stays explicitly unmapped.
library;

import '../models/tone_target.dart' show SoundRole, ToneDimension;
import 'evaluation_signal.dart';
import 'tone_match_models.dart';

enum BrightnessTarget { dark, neutral, bright }

enum MidTarget { scooped, neutral, forward }

enum DynamicsTarget { dynamic, neutral, compressed }

/// One acoustic target direction with where it comes from.
class TargetDimension<T> {
  const TargetDimension(this.value, this.evidence, this.basis);
  final T value;
  final ToneEvidence evidence;

  /// Plain-language reason for the mapping (shown under "Details").
  final String basis;
}

class UnmappedAspect {
  const UnmappedAspect(this.aspect, this.reason);
  final String aspect, reason;
}

class AcousticTargetProfile {
  const AcousticTargetProfile({
    required this.role,
    required this.signalRole,
    this.brightness,
    this.mids,
    this.dynamics,
    this.unmapped = const [],
  });

  /// Musical role of the wanted sound (from the knowledge layer).
  final SoundRole role;

  /// Which fixed test recording is used to measure the NAMs for this role.
  final EvaluationRole signalRole;
  final TargetDimension<BrightnessTarget>? brightness;
  final TargetDimension<MidTarget>? mids;
  final TargetDimension<DynamicsTarget>? dynamics;

  /// Aspects of the intent that have no defensible acoustic measure and therefore do not steer the match.
  final List<UnmappedAspect> unmapped;

  /// True when at least one acoustic direction exists; otherwise only the description-based
  /// pre-selection can be shown.
  bool get hasAcousticTargets => brightness != null || mids != null || dynamics != null;
}

/// Fixed, documented class boundaries of the mapping (semantic 0..100 dimension -> direction).
/// They are heuristic boundaries; the evidence of each result says so.
abstract final class TargetMappingRules {
  static const brightHigh = 60, brightLow = 40; // mean of treble / presence / IR brightness
  static const midForward = 58, midScooped = 42; // mids dimension
  static const gainCompressed = 65, gainDynamic = 35; // gain dimension (more gain -> more compression of dynamics)
}

class AcousticTargetMapper {
  const AcousticTargetMapper();

  AcousticTargetProfile map(ToneIntent intent) {
    final d = intent.dimensions;
    final source = intent.evidence['gain']; // the knowledge basis of the dimensions (CURATED / KNOWN / INFERRED)
    ToneEvidence fromKnowledge(String what) =>
        ToneEvidence(source?.kind ?? EvidenceKind.inferred, '$what aus der Klangbeschreibung (${source?.source ?? 'Wissensbasis'})');
    final heuristic = ToneEvidence(EvidenceKind.heuristic, 'Festgelegte Zuordnungsgrenze von WyrmTone');

    // Brightness: only when at least two of the three brightness-related dimensions are stated.
    final bright = [d[ToneDimension.treble], d[ToneDimension.presence], d[ToneDimension.irBrightness]].whereType<int>().toList();
    TargetDimension<BrightnessTarget>? brightness;
    if (bright.length >= 2) {
      final mean = bright.reduce((a, b) => a + b) / bright.length;
      brightness = TargetDimension(
        mean >= TargetMappingRules.brightHigh
            ? BrightnessTarget.bright
            : mean <= TargetMappingRules.brightLow
            ? BrightnessTarget.dark
            : BrightnessTarget.neutral,
        fromKnowledge('Höhen'),
        'Mittel aus Höhen, Präsenz und Helligkeit der Klangbeschreibung; Grenzen ${TargetMappingRules.brightLow}/${TargetMappingRules.brightHigh}.',
      );
    }

    final mid = d[ToneDimension.mids];
    final mids = mid == null
        ? null
        : TargetDimension(
            mid >= TargetMappingRules.midForward
                ? MidTarget.forward
                : mid <= TargetMappingRules.midScooped
                ? MidTarget.scooped
                : MidTarget.neutral,
            fromKnowledge('Mitten'),
            'Mitten der Klangbeschreibung; Grenzen ${TargetMappingRules.midScooped}/${TargetMappingRules.midForward}.',
          );

    // Dynamics: more gain compresses the dynamics of a guitar signal (the measured NAMs confirm
    // that clean captures keep a high peak-to-average ratio, high-gain ones do not). This link is a
    // heuristic, not a fact about the song, and is labelled as such.
    final gain = d[ToneDimension.gain];
    final dynamics = gain == null
        ? null
        : TargetDimension(
            gain >= TargetMappingRules.gainCompressed
                ? DynamicsTarget.compressed
                : gain <= TargetMappingRules.gainDynamic
                ? DynamicsTarget.dynamic
                : DynamicsTarget.neutral,
            heuristic,
            'Aus dem Gain-Anteil der Klangbeschreibung abgeleitet (mehr Gain ≈ stärker komprimierte Dynamik); Grenzen ${TargetMappingRules.gainDynamic}/${TargetMappingRules.gainCompressed}.',
          );

    const noMeasure = 'Keine belastbare Messgröße zugeordnet';
    final unmapped = <UnmappedAspect>[
      if (d.containsKey(ToneDimension.tightness)) const UnmappedAspect('Straffheit', noMeasure),
      if (d.containsKey(ToneDimension.attack)) const UnmappedAspect('Anschlag', noMeasure),
      if (d.containsKey(ToneDimension.sustain)) const UnmappedAspect('Sustain', noMeasure),
      if (intent.delayKind != null || (d[ToneDimension.delay] ?? 0) > 0) const UnmappedAspect('Delay', 'Wird nicht am NAM gemessen'),
      if (intent.reverbKind != null || (d[ToneDimension.reverb] ?? 0) > 0) const UnmappedAspect('Hall', 'Wird nicht am NAM gemessen'),
      if (d.containsKey(ToneDimension.bass)) const UnmappedAspect('Bass', 'Nur über das Gesamtspektrum, kein eigenes Ziel'),
    ];

    return AcousticTargetProfile(
      role: intent.role,
      signalRole: switch (intent.role) {
        SoundRole.rhythm => EvaluationRole.rhythm,
        SoundRole.lead => EvaluationRole.lead,
        SoundRole.clean => EvaluationRole.clean,
      },
      brightness: brightness,
      mids: mids,
      dynamics: dynamics,
      unmapped: unmapped,
    );
  }
}
