import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/tonematch/stft_feature_extractor.dart';
import 'package:wyrmtone/tonematch/tone_features.dart';

import 'tone_match_envelope_v2_test.dart' show expDecay, linAttack, notes, referenceHop1;

/// The synthetic envelope checks of tone_match_envelope_v2_test.dart (unchanged there), repeated
/// for the 4-, 8- and 16-phase candidates of the final gate (docs section 9). Same fixtures, same
/// tolerances; nothing was loosened after seeing results.
const _holdout = [1, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61];

Map<String, double?> measure(Float32List x, int version, {int phases = 4}) {
  final f = StftFeatureExtractor(analysisVersion: version, envelopePhaseCount: phases).extract(input: x, output: x).tone;
  return {'attack': f[ToneFeatureIds.attackMs], 'decay': f[ToneFeatureIds.decayDbPerSec], 'transient': f[ToneFeatureIds.transientPeakToBodyDb], 'onsets': f[ToneFeatureIds.onsetCount]};
}

void main() {
  final table = <String, Object?>{};
  for (final phases in [4, 8, 16]) {
    group('$phases phases', () {
      test('known exponential decay and distinct decay constants', () {
        final got = <double>[];
        for (final tau in [0.15, 0.3, 0.6]) {
          final x = notes(5, (t, i) => linAttack(t, 2) * expDecay(t, tau));
          final expected = -8.686 / tau;
          final v = measure(x, 2, phases: phases)['decay']!;
          expect((v - expected).abs(), lessThanOrEqualTo(math.max(1.5, 0.08 * expected.abs())), reason: 'tau $tau: $v vs $expected');
          got.add(v);
          table['$phases phases: decay tau=$tau'] = {'expected': expected, 'measured': v};
        }
        expect(got[0] + 10, lessThan(got[1])); // clearly distinct, monotone
        expect(got[1] + 10, lessThan(got[2]));
      });

      test('attack times: ordered, distinct, not less accurate than V1 against the hop-1 reference, never worse than 4 ms', () {
        final cases = <String, double Function(double)>{
          'instantaneous': (t) => expDecay(t, 0.4),
          'linear 5 ms': (t) => linAttack(t, 5) * expDecay(t, 0.4),
          'linear 20 ms': (t) => linAttack(t, 20) * expDecay(t, 0.4),
          'linear 40 ms': (t) => linAttack(t, 40) * expDecay(t, 0.4),
          'exponential tau 10 ms': (t) => (1 - math.exp(-t / 0.010)) * expDecay(t, 0.4),
          'exponential tau 30 ms': (t) => (1 - math.exp(-t / 0.030)) * expDecay(t, 0.4),
        };
        final v = <String, double>{};
        final e1 = <double>[], e2 = <double>[];
        for (final c in cases.entries) {
          final x = notes(5, (t, i) => c.value(t));
          final ref = referenceHop1(x).attackMs;
          final a1 = measure(x, 1)['attack']!, a2 = measure(x, 2, phases: phases)['attack']!;
          e1.add((a1 - ref).abs());
          e2.add((a2 - ref).abs());
          v[c.key] = a2;
        }
        double mean(List<double> l) => l.reduce((a, b) => a + b) / l.length;
        table['$phases phases: attack accuracy'] = {'meanAbsErrV1': mean(e1), 'meanAbsErrCandidate': mean(e2), 'maxAbsErrCandidate': e2.reduce(math.max), 'values': v};
        expect(mean(e2), lessThanOrEqualTo(mean(e1) + 1e-9));
        expect(e2.reduce(math.max), lessThanOrEqualTo(4.0));
        expect(v['linear 5 ms']!, lessThan(v['linear 20 ms']!));
        expect(v['linear 20 ms']!, lessThan(v['linear 40 ms']!));
        expect(v['exponential tau 10 ms']!, lessThan(v['exponential tau 30 ms']!));
        expect(v.values.map((e) => e.toStringAsFixed(2)).toSet().length, greaterThanOrEqualTo(5)); // not flattened
      });

      test('sustain vs decay, transient strength, multiple transients', () {
        final sustained = notes(5, (t, i) => linAttack(t, 10) * (t < 0.55 ? 1.0 : expDecay(t - 0.55, 0.2)));
        final plain = notes(5, (t, i) => linAttack(t, 10) * expDecay(t, 0.2));
        expect(measure(sustained, 2, phases: phases)['decay']!, greaterThan(measure(plain, 2, phases: phases)['decay']! + 15));

        double spike(double s) => 0 + s;
        final strengths = <double>[];
        for (final s in [0.0, 1.0, 3.0]) {
          final x = notes(5, (t, i) => linAttack(t, 3) * ((t < 0.7 ? 1.0 : expDecay(t - 0.7, 0.1)) * (1 + spike(s) * math.exp(-t / 0.012))));
          strengths.add(measure(x, 2, phases: phases)['transient']!);
        }
        table['$phases phases: transient strength (spike 0/1/3)'] = strengths;
        expect(strengths[0] + 2, lessThan(strengths[1])); // monotone and distinct
        expect(strengths[1] + 2, lessThan(strengths[2]));

        final mixed = notes(6, (t, i) => linAttack(t, 2) * expDecay(t, i.isEven ? 0.15 : 0.6));
        final m = measure(mixed, 2, phases: phases);
        expect(m['onsets']!, greaterThanOrEqualTo(5));
        expect((m['decay']! - (-8.686 / 0.15 + -8.686 / 0.6) / 2).abs(), lessThanOrEqualTo(8.0));
      });

      test('deterministic; unaffected features identical to V1; hold-out grid shifts do not exceed V1 variation', () {
        final base = notes(5, (t, i) => linAttack(t, 2) * expDecay(t, 0.3 + 0.05 * i));
        expect(measure(base, 2, phases: phases), measure(base, 2, phases: phases));
        final v1 = const StftFeatureExtractor().extract(input: base, output: base);
        final v2 = StftFeatureExtractor(analysisVersion: 2, envelopePhaseCount: phases).extract(input: base, output: base);
        const changed = {ToneFeatureIds.attackMs, ToneFeatureIds.decayDbPerSec, ToneFeatureIds.transientPeakToBodyDb, ToneFeatureIds.onsetCount};
        for (final k in v1.tone.keys.where((k) => !changed.contains(k))) {
          expect(v2.tone[k], v1.tone[k], reason: k);
        }
        expect(v2.level, v1.level);

        double cv(int version, String key) {
          final v = [for (final s in _holdout) measure(notes(5, (t, i) => linAttack(t, 2) * expDecay(t, 0.3), shift: s), version, phases: phases)[key]!];
          final mean = v.reduce((a, b) => a + b) / v.length;
          return 100 * math.sqrt(v.map((e) => (e - mean) * (e - mean)).reduce((a, b) => a + b) / v.length) / mean.abs();
        }

        table['$phases phases: synthetic hold-out CV% attack/decay (V1 -> candidate)'] = {'attack': [cv(1, 'attack'), cv(2, 'attack')], 'decay': [cv(1, 'decay'), cv(2, 'decay')]};
        expect(cv(2, 'attack'), lessThanOrEqualTo(cv(1, 'attack') + 1e-9));
        expect(cv(2, 'decay'), lessThanOrEqualTo(cv(1, 'decay') + 1e-9));
      });
    });
  }

  tearDownAll(() {
    if (Platform.environment['WYRMTONE_WRITE_SYNTHETIC'] == '1') {
      File('tool/tonematch_envelope_v2/results/synthetic_phases.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(table));
    }
  });
}
