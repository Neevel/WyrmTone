/// RESEARCH SPIKE "Hör-Match / Reference Tone Match" (docs/TONE_MATCH.md section 13).
/// NOT product code: nothing in lib/ imports this. Similarity V1 and AnalysisVersion 1 are untouched;
/// the reference distances below are separate research scores built ONLY from the already accepted
/// stable features (centroid, rolloff85, MID+HIGH_MID share, crest). attackMs, decay, transient,
/// saturation composite and HF generation are never used.
///
/// PRE-REGISTERED before any result was seen:
///  - normalisation: the production tone normalisation of the extractor (output scaled to an
///    active-frame RMS of -20 dBFS); no extra normalisation.
///  - representations: brightness = mean of z(ln centroid) and z(ln rolloff85); mids = z(logit(share of
///    MID+HIGH_MID)); dynamics = z(crest dB). z = (x - mean) / std over the CANDIDATE set of that case.
///  - D1: sqrt((db^2 + dm^2 + dc^2) / 3).
///  - D2 (V1-like groups): ((sqrt((db^2 + dm^2) / 2) + |dc|) / 2).
///  - D3 (V1-like percentile ranks over the candidate set): mean of |dp| over brightness, mids, dynamics.
///  - no weight tuning, no threshold tuning, results reported for all three.
library;

import 'dart:math' as math;

import 'package:wyrmtone/tonematch/tone_features.dart';
import 'package:wyrmtone/tonematch/tone_match_models.dart';

class RefFeatures {
  const RefFeatures(
    this.id,
    this.lnCentroid,
    this.lnRolloff,
    this.midLogit,
    this.crestDb,
  );
  final String id;
  final double lnCentroid, lnRolloff, midLogit, crestDb;

  factory RefFeatures.from(String id, AudioFeatureVector v) {
    final t = v.tone;
    final share = (t['tone.band.MID']! + t['tone.band.HIGH_MID']!).clamp(
      1e-6,
      1 - 1e-6,
    );
    return RefFeatures(
      id,
      math.log(t[ToneFeatureIds.centroidHz]!),
      math.log(t[ToneFeatureIds.rolloff85Hz]!),
      math.log(share / (1 - share)),
      t[ToneFeatureIds.crestDb]!,
    );
  }

  Map<String, double> toJson() => {
    'lnCentroid': lnCentroid,
    'lnRolloff': lnRolloff,
    'midLogit': midLogit,
    'crestDb': crestDb,
  };
}

class Ranked {
  const Ranked(this.id, this.distance);
  final String id;
  final double distance;
}

double _mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;
double _std(List<double> v) {
  final m = _mean(v);
  return math.max(
    1e-9,
    math.sqrt(v.fold(0.0, (a, x) => a + (x - m) * (x - m)) / v.length),
  );
}

double _percentile(double v, List<double> all) {
  if (all.length < 2) return 0.5;
  final below = all.where((x) => x < v).length,
      equal = all.where((x) => x == v).length;
  return (below + 0.5 * equal) / all.length;
}

/// The three dimensions of one item in the z-space of [candidates] (brightness, mids, dynamics).
({double b, double m, double c}) _z(RefFeatures x, List<RefFeatures> cands) {
  double z(double v, double Function(RefFeatures) f) {
    final all = cands.map(f).toList();
    return (v - _mean(all)) / _std(all);
  }

  return (
    b:
        (z(x.lnCentroid, (r) => r.lnCentroid) +
            z(x.lnRolloff, (r) => r.lnRolloff)) /
        2,
    m: z(x.midLogit, (r) => r.midLogit),
    c: z(x.crestDb, (r) => r.crestDb),
  );
}

({double b, double m, double c}) _p(RefFeatures x, List<RefFeatures> cands) => (
  b:
      (_percentile(x.lnCentroid, cands.map((r) => r.lnCentroid).toList()) +
          _percentile(x.lnRolloff, cands.map((r) => r.lnRolloff).toList())) /
      2,
  m: _percentile(x.midLogit, cands.map((r) => r.midLogit).toList()),
  c: _percentile(x.crestDb, cands.map((r) => r.crestDb).toList()),
);

/// Candidates ordered nearest first (ties by id) for the distance method [method] in {D1, D2, D3}.
List<Ranked> rank(
  RefFeatures reference,
  List<RefFeatures> candidates,
  String method,
) {
  final r = _z(reference, candidates), rp = _p(reference, candidates);
  final out = <Ranked>[];
  for (final c in candidates) {
    final z = _z(c, candidates), p = _p(c, candidates);
    final db = r.b - z.b, dm = r.m - z.m, dc = r.c - z.c;
    final d = switch (method) {
      'D1' => math.sqrt((db * db + dm * dm + dc * dc) / 3),
      'D2' => (math.sqrt((db * db + dm * dm) / 2) + dc.abs()) / 2,
      'D3' =>
        ((rp.b - p.b).abs() + (rp.m - p.m).abs() + (rp.c - p.c).abs()) / 3,
      _ => throw ArgumentError(method),
    };
    out.add(Ranked(c.id, d));
  }
  out.sort((a, b) {
    final c = a.distance.compareTo(b.distance);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  return out;
}
