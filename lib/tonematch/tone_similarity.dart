/// Similarity V1: a conservative, explainable ranking of analysed NAMs against an
/// [AcousticTargetProfile].
///
/// Rules (docs/TONE_MATCH.md section 11):
///  - only stable, validated measurements are used: spectral centroid + rolloff (brightness),
///    MID + HIGH_MID band share (mid balance) and crest factor (dynamics);
///  - `attackMs`, `decayDbPerSec`, `transientPeakToBodyDb`, the saturation composite and its
///    components, flatness, bandwidth and the individual bands are NOT used (attack/decay are
///    rasterphase-noisy, the composite mainly reflects dynamics/compression, not "gain");
///  - targets are RELATIVE: a NAM's value is compared with the other analysed NAMs (percentile
///    rank), never with an absolute Hz/dB target;
///  - correlated measurements are first merged into one dimension, dimensions into groups, and
///    every group that has a target counts equally (no five band values outweighing the dynamics);
///  - the score is internal and only orders results; there is no percentage and no quality class.
library;

import 'acoustic_target.dart';
import 'tone_features.dart';
import 'tone_match_models.dart';

/// One NAM that has been measured.
class AnalyzedSound {
  const AnalyzedSound({
    required this.id,
    required this.name,
    required this.analysis,
    this.metadataScore = 0,
  });
  final String id, name;
  final NamAnalysis analysis;

  /// Description-based pre-ranking score, only used as a tie-breaker.
  final double metadataScore;
}

/// How a sound sits among the analysed ones, per dimension: 0 = lowest, 1 = highest (percentile rank).
class RelativePosition {
  const RelativePosition({this.brightness, this.midBalance, this.crest});
  final double? brightness, midBalance, crest;
}

class SimilarityEntry {
  const SimilarityEntry({
    required this.sound,
    required this.score,
    required this.voicingScore,
    required this.dynamicsScore,
    required this.position,
    required this.rank,
  });
  final AnalyzedSound sound;

  /// Internal ordering value in 0..1 (relative to the analysed set, not calibrated, never shown).
  final double score;
  final double? voicingScore, dynamicsScore;
  final RelativePosition position;
  final int rank;
}

abstract final class SimilarityV1 {
  /// The ONLY measured features that enter the ranking.
  static const usedFeatureIds = [
    ToneFeatureIds.centroidHz,
    ToneFeatureIds.rolloff85Hz,
    'tone.band.MID',
    'tone.band.HIGH_MID',
    ToneFeatureIds.crestDb,
  ];

  /// Features that stay diagnostic and must never influence the ranking.
  static const excludedFeatureIds = [
    ToneFeatureIds.attackMs,
    ToneFeatureIds.decayDbPerSec,
    ToneFeatureIds.transientPeakToBodyDb,
    ToneFeatureIds.onsetCount,
    ToneFeatureIds.saturationComposite,
    ToneFeatureIds.flatness1to8k,
    ToneFeatureIds.hfGenerationDb,
    ToneFeatureIds.crestReductionDb,
    ToneFeatureIds.envelopeCompressionDb,
    ToneFeatureIds.envelopeRangeDb,
    ToneFeatureIds.bandwidthHz,
  ];

  /// Percentile rank of [v] among [all] (ties count half). One value carries no information: 0.5.
  static double percentile(double v, List<double> all) {
    if (all.length < 2) return 0.5;
    final below = all.where((x) => x < v).length;
    final equal = all.where((x) => x == v).length;
    return (below + 0.5 * equal) / all.length;
  }

  static double _toward(double p, int direction) =>
      direction > 0 ? p : (direction < 0 ? 1 - p : 1 - 2 * (p - 0.5).abs());

  /// [sounds] must contain every analysed NAM so far; the result is deterministic and ordered best first.
  static List<SimilarityEntry> rank(
    List<AnalyzedSound> sounds,
    AcousticTargetProfile target,
  ) {
    double f(AnalyzedSound s, String id) => s.analysis.features.tone[id]!;
    List<double> col(String id) => [for (final s in sounds) f(s, id)];
    final centroid = col(ToneFeatureIds.centroidHz),
        rolloff = col(ToneFeatureIds.rolloff85Hz);
    final mid = [
      for (final s in sounds)
        f(s, 'tone.band.MID') + f(s, 'tone.band.HIGH_MID'),
    ];
    final crest = col(ToneFeatureIds.crestDb);

    final entries = <SimilarityEntry>[];
    for (var i = 0; i < sounds.length; i++) {
      final s = sounds[i];
      final bright =
          (percentile(centroid[i], centroid) +
              percentile(rolloff[i], rolloff)) /
          2;
      final midP = percentile(mid[i], mid);
      final crestP = percentile(crest[i], crest);

      final voicing = <double>[
        if (target.brightness != null)
          _toward(bright, target.brightness!.value.index - 1),
        if (target.mids != null) _toward(midP, target.mids!.value.index - 1),
      ];
      // Dynamics: compressed means a LOW peak-to-average ratio, so the direction is inverted.
      final dynamics = target.dynamics == null
          ? null
          : _toward(crestP, -(target.dynamics!.value.index - 1));
      final voicingScore = voicing.isEmpty
          ? null
          : voicing.reduce((a, b) => a + b) / voicing.length;
      final groups = [?voicingScore, ?dynamics];
      entries.add(
        SimilarityEntry(
          sound: s,
          score: groups.isEmpty
              ? 0
              : groups.reduce((a, b) => a + b) / groups.length,
          voicingScore: voicingScore,
          dynamicsScore: dynamics,
          position: RelativePosition(
            brightness: bright,
            midBalance: midP,
            crest: crestP,
          ),
          rank: 0,
        ),
      );
    }
    // Deterministic order: score, then description pre-ranking, then name, then id.
    entries.sort((a, b) {
      final c = _q(b.score).compareTo(_q(a.score));
      if (c != 0) return c;
      final m = b.sound.metadataScore.compareTo(a.sound.metadataScore);
      if (m != 0) return m;
      final n = a.sound.name.compareTo(b.sound.name);
      return n != 0 ? n : a.sound.id.compareTo(b.sound.id);
    });
    return [
      for (var i = 0; i < entries.length; i++)
        SimilarityEntry(
          sound: entries[i].sound,
          score: entries[i].score,
          voicingScore: entries[i].voicingScore,
          dynamicsScore: entries[i].dynamicsScore,
          position: entries[i].position,
          rank: i + 1,
        ),
    ];
  }

  // Scores that agree to 9 digits count as equal so float noise cannot reorder results.
  static int _q(double v) => (v * 1e9).round();

  /// Plain-language reasons. Only statements that follow from the target and the measured relative
  /// position among the analysed sounds; relative statements need at least three sounds.
  static List<String> explain(
    SimilarityEntry e,
    AcousticTargetProfile target,
    int analysedCount,
  ) {
    final relative = analysedCount >= 3;
    // "Heller als die meisten geprüften Sounds" / "... im Mittelfeld der geprüften Sounds".
    // [wanted] is the direction the search asks for in the same terms as the position (-1/0/+1);
    // an opposite measurement is said openly instead of being dressed up as a reason.
    String level(double p, int wanted, String high, String low, String mid) {
      final actual = p >= 2 / 3 ? 1 : (p <= 1 / 3 ? -1 : 0);
      final text = actual > 0
          ? '$high als die meisten geprüften Sounds'
          : (actual < 0
                ? '$low als die meisten geprüften Sounds'
                : '$mid der geprüften Sounds');
      return actual != 0 && wanted != 0 && actual != wanted
          ? '$text – weicht vom Gesuchten ab'
          : text;
    }

    final pos = e.position;
    final wanted = <String>[];
    final measured = <String>[];
    if (target.brightness != null) {
      final b = target.brightness!.value;
      wanted.add(switch (b) {
        BrightnessTarget.bright => 'eher hell',
        BrightnessTarget.dark => 'eher dunkel',
        BrightnessTarget.neutral => 'ausgewogene Höhen',
      });
      measured.add(
        level(
          pos.brightness!,
          b.index - 1,
          'Heller',
          'Dunkler',
          'Höhen im Mittelfeld',
        ),
      );
    }
    if (target.mids != null) {
      final m = target.mids!.value;
      wanted.add(switch (m) {
        MidTarget.forward => 'kräftige Mitten',
        MidTarget.scooped => 'zurückgenommene Mitten',
        MidTarget.neutral => 'ausgewogene Mitten',
      });
      measured.add(
        level(
          pos.midBalance!,
          m.index - 1,
          'Kräftigere Mitten',
          'Zurückhaltendere Mitten',
          'Mitten im Mittelfeld',
        ),
      );
    }
    if (target.dynamics != null) {
      final d = target.dynamics!.value;
      wanted.add(switch (d) {
        DynamicsTarget.compressed => 'eher komprimierte Dynamik (geschätzt)',
        DynamicsTarget.dynamic => 'eher lebendige Dynamik (geschätzt)',
        DynamicsTarget.neutral => 'ausgewogene Dynamik (geschätzt)',
      });
      // High crest factor = more lively dynamics, so the wanted direction is inverted.
      measured.add(
        level(
          pos.crest!,
          -(d.index - 1),
          'Lebendigere Dynamik',
          'Stärker komprimierte Dynamik',
          'Dynamik im Mittelfeld',
        ),
      );
    }
    return [
      if (wanted.isNotEmpty) 'Gesucht: ${wanted.join(', ')}',
      if (relative) ...measured,
    ];
  }
}
