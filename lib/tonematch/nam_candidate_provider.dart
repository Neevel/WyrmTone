import '../models/tone_target.dart' show ToneDimension;
import '../nam/local_nam_capture.dart';
import 'tone_match_models.dart';

/// Stage 1 of the candidate pipeline: reduce the local NAM library by METADATA only (no
/// inference). The score is a sorting number from names/tags/description -- heuristic, not a
/// measurement and never shown as a percentage.
class NamCandidateProvider {
  const NamCandidateProvider({this.maxCandidates = 5});
  final int maxCandidates;

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[_\-]+'), ' ');

  /// Usable captures only (see below); the rest is counted in [excluded] so the UI can say why.
  ({List<ToneMatchCandidate> ranked, int excluded}) rank(ToneIntent intent, List<LocalNamCapture> captures) {
    // Usable for a Tone Match: models known to fit the device, and models whose fit has not been
    // determined (a locally imported file carries no architecture information). Whether such a model
    // can be transferred is decided on the NAM detail page, never here. Models that are known not to
    // work (unsupported, conversion needed, invalid, file missing) are left out.
    final usable = [
      for (final c in captures)
        if (c.compatibility == NamCompatibility.compatible || c.compatibility == NamCompatibility.unknown) c,
    ];
    final gain = intent.dim(ToneDimension.gain) ?? 0;
    final ranked = <ToneMatchCandidate>[];
    for (final c in usable) {
      final hay = _norm('${c.toneName} ${c.captureName} ${c.make ?? ''} ${c.gearType ?? ''} ${c.tags.join(' ')} ${c.description ?? ''}');
      var score = 0.0;
      final reasons = <String>[], cautions = <String>[];
      final ampHits = [for (final a in intent.ampFamilies) if (hay.contains(_norm(a))) a];
      final tagHits = [for (final t in intent.namTags) if (hay.contains(_norm(t))) t];
      if (ampHits.isNotEmpty) {
        score += 3.0 * ampHits.length;
        reasons.add('Amp-Familie passt: ${ampHits.join(', ')}.');
      }
      if (tagHits.isNotEmpty) {
        score += 2.0 * tagHits.length;
        reasons.add('Eigenschaften passen: ${tagHits.join(', ')}.');
      }
      final isClean = hay.contains('clean');
      final isHighGain = hay.contains('high gain') || hay.contains('metal') || hay.contains('lead') && gain >= 65;
      if (gain >= 65 && isClean) {
        score -= 3;
        cautions.add('Als Clean beschrieben, der Zielklang braucht viel Gain.');
      } else if (gain >= 65 && isHighGain) {
        score += 1;
        reasons.add('Als High-Gain/Metal beschrieben.');
      } else if (gain > 0 && gain < 40 && isClean) {
        score += 1;
        reasons.add('Als Clean beschrieben, passend zu wenig Gain.');
      }
      if (c.cabinetContent == NamCabinetContent.unknown) {
        cautions.add('Cabinet-Anteil unbekannt.');
      }
      if (reasons.isEmpty) reasons.add('Keine Metadaten-Übereinstimmung; nur als Ausweichkandidat.');
      final level = score >= 6
          ? NamMatchLevel.good
          : score >= 3
          ? NamMatchLevel.partial
          : NamMatchLevel.uncertain;
      ranked.add(ToneMatchCandidate(capture: c, score: score, level: level, reasons: reasons, cautions: cautions));
    }
    // Deterministic: score desc, then name, then id.
    ranked.sort((a, b) {
      final s = b.score.compareTo(a.score);
      if (s != 0) return s;
      final n = a.capture.toneName.compareTo(b.capture.toneName);
      return n != 0 ? n : a.capture.localId.compareTo(b.capture.localId);
    });
    return (ranked: ranked.take(maxCandidates).toList(), excluded: captures.length - usable.length);
  }
}
