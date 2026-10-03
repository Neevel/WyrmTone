"""Statistics for the Tone Match validation/ablation gate (reads results/raw.json).

Nothing here changes AnalysisVersion 1: it only reads raw feature vectors and offline metrics.
Decision rules were fixed beforehand in docs/TONE_MATCH.md section 6.3.
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
raw = json.load(open(os.path.join(HERE, 'results', 'raw.json'), encoding='utf8'))
nams = json.load(open(os.path.join(HERE, 'ten_nam_set.json'), encoding='utf8'))
ids = [n['id'] for n in nams]
short = {n['id']: n['id'] for n in nams}

BANDS = ['LOW', 'LOW_MID', 'MID', 'HIGH_MID', 'HIGH']
CORE = (['tone.centroidHz', 'tone.rolloff85Hz', 'tone.bandwidthHz'] + ['tone.band.' + b for b in BANDS] +
        ['tone.crestDb', 'tone.attackMs', 'tone.decayDbPerSec', 'tone.transientPeakToBodyDb', 'tone.envelopeRangeDb',
         'tone.sat.flatness1to8k', 'tone.sat.hfGenerationDb', 'tone.sat.crestReductionDb', 'tone.sat.envelopeCompressionDb',
         'tone.sat.composite'])
DIST = [f for f in CORE if f != 'tone.sat.composite']
RANGES = {'tone.sat.flatness1to8k': (0.0, 0.3), 'tone.sat.hfGenerationDb': (0.0, 20.0),
          'tone.sat.crestReductionDb': (0.0, 15.0), 'tone.sat.envelopeCompressionDb': (0.0, 15.0)}


def rank(a):
    a = np.asarray(a, float)
    order = np.argsort(a, kind='mergesort')
    r = np.empty(len(a))
    i = 0
    while i < len(a):
        j = i
        while j + 1 < len(a) and a[order[j + 1]] == a[order[i]]:
            j += 1
        r[order[i:j + 1]] = (i + j) / 2 + 1
        i = j + 1
    return r


def spearman(a, b):
    ra, rb = rank(a), rank(b)
    if ra.std() == 0 or rb.std() == 0:
        return float('nan')
    return float(np.corrcoef(ra, rb)[0, 1])


def pearson(a, b):
    a, b = np.asarray(a, float), np.asarray(b, float)
    return float(np.corrcoef(a, b)[0, 1])


def feat(role, variant, nid, name):
    e = raw['runs'][nid]['%s/%s' % (role, variant)]
    allf = {**e['level'], **e['tone'], **e.get('alt', {})}
    return allf.get(name, float('nan'))


def vec(role, variant, name):
    return np.array([feat(role, variant, i, name) for i in ids])


def composite3(role, variant, nid):
    comps = ['tone.sat.flatness1to8k', 'tone.sat.crestReductionDb', 'tone.sat.envelopeCompressionDb']
    s = 0
    for c in comps:
        lo, hi = RANGES[c]
        s += min(1, max(0, (feat(role, variant, nid, c) - lo) / (hi - lo)))
    return s / 3


def zmatrix(role, variant, ref_variant='FULL'):
    """z-standardise with mean/std of the FULL variant across the 10 NAMs (same scaling for all variants)."""
    cols = []
    for f in DIST:
        ref = vec(role, ref_variant, f)
        cur = vec(role, variant, f)
        sd = ref.std() or 1.0
        cols.append((cur - ref.mean()) / sd)
    return np.array(cols).T  # nams x features


def dmat(z):
    n = len(z)
    d = np.zeros((n, n))
    for i in range(n):
        for j in range(n):
            d[i, j] = math.sqrt(((z[i] - z[j]) ** 2).sum())
    return d


def upper(d):
    n = len(d)
    return np.array([d[i, j] for i in range(n) for j in range(i + 1, n)])


out = {}
lines = []


def P(s=''):
    lines.append(s)
    print(s)


roles = ['rhythm', 'lead', 'clean']
variants = {r: [v for v in raw['signals'][r].keys() if v != 'FULL'] for r in roles}

# ---------- 1. FULL results
P('# FULL: composite and key tone features per NAM')
for r in roles:
    P('## ' + r)
    P('id  composite  comp3(noHF) centroid  rolloff   crest  attack  transient  envRange  flat   hfGen  crestRed envComp  | probeTilt-30 probeTilt-20')
    for i in ids:
        g = lambda n: feat(r, 'FULL', i, n)
        P('%s  %.3f      %.3f     %7.0f %7.0f  %5.1f  %6.1f  %6.1f  %6.1f  %.3f  %5.1f  %5.1f  %5.1f   | %6.1f  %6.1f' % (
            i, g('tone.sat.composite'), composite3(r, 'FULL', i), g('tone.centroidHz'), g('tone.rolloff85Hz'), g('tone.crestDb'),
            g('tone.attackMs'), g('tone.transientPeakToBodyDb'), g('tone.envelopeRangeDb'), g('tone.sat.flatness1to8k'),
            g('tone.sat.hfGenerationDb'), g('tone.sat.crestReductionDb'), g('tone.sat.envelopeCompressionDb'),
            raw['probe'][i]['tilt-30'], raw['probe'][i]['tilt-20']))

# ---------- 2. length ablation
P()
P('# Length ablation (vs FULL)')
length = {}
for r in roles:
    length[r] = {}
    zfull = zmatrix(r, 'FULL')
    dfull = upper(dmat(zfull))
    for v in variants[r]:
        zv = zmatrix(r, v)
        dv = upper(dmat(zv))
        rho_d = spearman(dfull, dv)
        per = {}
        for f in CORE:
            a, b = vec(r, 'FULL', f), vec(r, v, f)
            absd = np.abs(b - a)
            rel = absd / np.maximum(np.abs(a), 1e-9)
            per[f] = dict(spearman=spearman(a, b), medAbs=float(np.median(absd)), maxAbs=float(absd.max()),
                          medRel=float(np.median(rel)), maxRel=float(rel.max()))
        dcomp = np.abs(vec(r, v, 'tone.sat.composite') - vec(r, 'FULL', 'tone.sat.composite'))
        failing = [f for f in CORE if not (per[f]['spearman'] >= 0.90)]
        crit = dict(distSpearman=rho_d, a=bool(rho_d >= 0.95), b=len(failing) == 0, failingFeatures=failing,
                    maxDeltaComposite=float(dcomp.max()), c=bool(dcomp.max() <= 0.05))
        crit['pass'] = crit['a'] and crit['b'] and crit['c']
        length[r][v] = dict(criteria=crit, perFeature=per, seconds=raw['signals'][r][v]['seconds'])
        P('%s %-5s (%.1fs audio) distSpearman=%.3f  maxDeltaComposite=%.3f  features<0.90: %s  -> %s' % (
            r, v, raw['signals'][r][v]['seconds'], rho_d, dcomp.max(), failing if failing else 'none', 'PASS' if crit['pass'] else 'fail'))
        worst = sorted(CORE, key=lambda f: -per[f]['medRel'])[:4]
        c3f = np.array([composite3(r, 'FULL', i) for i in ids]); c3v = np.array([composite3(r, v, i) for i in ids])
        base_fail = length[r]['SPAN']['criteria']['failingFeatures'] if 'SPAN' in length[r] else []
        crit['newFailingVsSpanNoiseFloor'] = [f for f in failing if f not in base_fail]
        crit['maxDeltaComposite3'] = float(np.abs(c3v - c3f).max())
        P('    spearman: composite %.2f centroid %.2f crest %.2f flat %.2f hfGen %.2f crestRed %.2f envComp %.2f | maxDeltaComposite3(noHF)=%.3f | new failures beyond SPAN noise floor: %s' % (
            per['tone.sat.composite']['spearman'], per['tone.centroidHz']['spearman'], per['tone.crestDb']['spearman'], per['tone.sat.flatness1to8k']['spearman'],
            per['tone.sat.hfGenerationDb']['spearman'], per['tone.sat.crestReductionDb']['spearman'], per['tone.sat.envelopeCompressionDb']['spearman'],
            crit['maxDeltaComposite3'], crit['newFailingVsSpanNoiseFloor'] or 'none'))
        P('    largest median relative deltas: ' + ', '.join('%s %.1f%%' % (f.replace('tone.', ''), 100 * per[f]['medRel']) for f in worst))
out['length'] = length

# ---------- 3. alternative HF metrics + cab dependency
P()
P('# HF metrics vs cab/voicing filtering (probe tilt) and vs the other saturation components (FULL)')
alt = {}
for r in ['rhythm', 'lead']:
    P('## ' + r)
    rows = []
    others = (vec(r, 'FULL', 'tone.sat.flatness1to8k'), vec(r, 'FULL', 'tone.sat.crestReductionDb'), vec(r, 'FULL', 'tone.sat.envelopeCompressionDb'))
    nonhf = np.mean([rank(o) for o in others], axis=0)
    tilt = np.array([raw['probe'][i]['tilt-30'] for i in ids])
    tilt20 = np.array([raw['probe'][i]['tilt-20'] for i in ids])
    metrics = {'A hfGenerationDb (V1)': vec(r, 'FULL', 'tone.sat.hfGenerationDb')}
    for k, name in [('B hfOverMidDeltaDb', 'alt.B.hfOverMidDeltaDb'), ('B hfOverMidOutDb', 'alt.B.hfOverMidOutDb'),
                    ('C slopeDeltaDbPerOct', 'alt.C.slopeDeltaDbPerOct'), ('C slopeOutDbPerOct', 'alt.C.slopeOutDbPerOct'),
                    ('D valleyFillDb', 'alt.D.valleyFillDb'), ('E midOverLowMidDb', 'alt.E.midOverLowMidDb'),
                    ('E highMidOverMidDb', 'alt.E.highMidOverMidDb')]:
        metrics[k] = vec(r, 'FULL', name)
    P('%-26s  rho(tilt-30)  rho(tilt-20)  rho(non-HF sat. components)' % 'metric')
    alt[r] = {}
    for k, v in metrics.items():
        a = dict(rhoTilt30=spearman(v, tilt), rhoTilt20=spearman(v, tilt20), rhoNonHf=spearman(v, nonhf))
        alt[r][k] = a
        P('%-26s  %8.2f      %8.2f      %8.2f' % (k, a['rhoTilt30'], a['rhoTilt20'], a['rhoNonHf']))
    out_amp = {i: vec(r, 'FULL', 'tone.sat.hfGenerationDb')[ids.index(i)] for i in ids}
    P('  hfGenerationDb by NAM: ' + ', '.join('%s=%.1f' % (i, out_amp[i]) for i in ids))
    P('  probeTilt-30 by NAM  : ' + ', '.join('%s=%.1f' % (i, t) for i, t in zip(ids, tilt)))
out['altHF'] = alt

# ---------- 4. composite 4 vs 3
P()
P('# Composite: 4 components vs 3 (without HF)')
cmp = {}
for r in roles:
    c4 = vec(r, 'FULL', 'tone.sat.composite')
    c3 = np.array([composite3(r, 'FULL', i) for i in ids])
    tilt = np.array([raw['probe'][i]['tilt-30'] for i in ids])
    d4 = upper(dmat(zmatrix(r, 'FULL')))
    cmp[r] = dict(rho43=spearman(c4, c3), rhoC4Tilt=spearman(c4, tilt), rhoC3Tilt=spearman(c3, tilt),
                  rank4=[int(x) for x in rank(c4)], rank3=[int(x) for x in rank(c3)], spread4=float(c4.max() - c4.min()), spread3=float(c3.max() - c3.min()))
    P('%s: spearman(comp4,comp3)=%.3f  rho(comp4,tilt)=%.2f  rho(comp3,tilt)=%.2f  spread4=%.3f spread3=%.3f' % (
        r, cmp[r]['rho43'], cmp[r]['rhoC4Tilt'], cmp[r]['rhoC3Tilt'], cmp[r]['spread4'], cmp[r]['spread3']))
    P('   ranks comp4: %s' % cmp[r]['rank4'])
    P('   ranks comp3: %s' % cmp[r]['rank3'])
    # pairwise-distinguishability: pairs whose composite differs by > 0.05
    n4 = sum(1 for i in range(10) for j in range(i + 1, 10) if abs(c4[i] - c4[j]) > 0.05)
    n3 = sum(1 for i in range(10) for j in range(i + 1, 10) if abs(c3[i] - c3[j]) > 0.05)
    P('   pairs separated by >0.05: comp4=%d/45  comp3=%d/45' % (n4, n3))
    cmp[r].update(sep4=n4, sep3=n3)
out['composite'] = cmp

# ---------- 5. distance matrices
P()
P('# Pairwise distance matrices (FULL, z-scored tone features, euclidean)')
mats = {}
for r in ['rhythm', 'lead']:
    z = zmatrix(r, 'FULL')
    d = dmat(z)
    mats[r] = d.tolist()
    P('## ' + r)
    P('     ' + ' '.join('%5s' % i for i in ids))
    for i, row in zip(ids, d):
        P('%s   ' % i + ' '.join('%5.1f' % v for v in row))
    ud = upper(d)
    pairs = [(d[i, j], ids[i], ids[j]) for i in range(10) for j in range(i + 1, 10)]
    pairs.sort()
    P('  closest pairs: ' + ', '.join('%s-%s %.1f' % (a, b, x) for x, a, b in pairs[:4]))
    P('  farthest pairs: ' + ', '.join('%s-%s %.1f' % (a, b, x) for x, a, b in pairs[-3:]))
    mean_d = d.sum(1) / 9
    zz = (mean_d - mean_d.mean()) / mean_d.std()
    P('  mean distance per NAM (outlier z): ' + ', '.join('%s %.1f(%.1f)' % (i, m, s) for i, m, s in zip(ids, mean_d, zz)))
    # dominating features
    share = np.zeros(len(DIST))
    for i in range(10):
        for j in range(i + 1, 10):
            q = (z[i] - z[j]) ** 2
            share += q / q.sum()
    share /= 45
    order = np.argsort(-share)
    P('  dominating features (mean share of squared distance): ' + ', '.join('%s %.0f%%' % (DIST[k].replace('tone.', ''), 100 * share[k]) for k in order[:6]))
    mats[r + '_share'] = {DIST[k]: float(share[k]) for k in range(len(DIST))}
    # average-linkage clustering
    clusters = [[k] for k in range(10)]
    merges = []
    while len(clusters) > 3:
        best = None
        for a in range(len(clusters)):
            for b in range(a + 1, len(clusters)):
                dd = np.mean([d[x, y] for x in clusters[a] for y in clusters[b]])
                if best is None or dd < best[0]:
                    best = (dd, a, b)
        _, a, b = best
        clusters[a] = clusters[a] + clusters[b]
        del clusters[b]
    P('  3 clusters (average linkage): ' + ' | '.join(','.join(ids[k] for k in c) for c in clusters))
    mats[r + '_clusters'] = [[ids[k] for k in c] for c in clusters]
out['distance'] = mats

# ---------- 6. performance
P()
P('# Desktop timings (cold, ms; mean over 10 NAMs: load / inference / extraction / total)')
perf = {}
for r in roles:
    for v in ['FULL'] + variants[r]:
        L = [raw['runs'][i]['%s/%s' % (r, v)]['ms'] for i in ids]
        m = {k: float(np.mean([x[k] for x in L])) for k in ['load', 'inference', 'extraction']}
        m['total'] = sum(m.values())
        m['seconds'] = raw['signals'][r][v]['seconds']
        perf['%s/%s' % (r, v)] = m
        P('%s %-5s audio %.1fs : %4.0f / %5.0f / %4.0f = %5.0f ms   (inference x realtime %.3f)' % (
            r, v, m['seconds'], m['load'], m['inference'], m['extraction'], m['total'], m['inference'] / 1000 / m['seconds']))
out['perf'] = perf
P()
P('# Cache (10 NAMs x RHYTHM+LEAD = 20 analyses, wall ms)')
for k, v in raw['cache'].items():
    P('%s: cold %d ms, warm %d ms (hits %d, misses %d)' % (k, v['coldMs'], v['warmMs'], v['hits'], v['misses']))
out['cache'] = raw['cache']

json.dump(out, open(os.path.join(HERE, 'results', 'report.json'), 'w', encoding='utf8'), indent=1)
open(os.path.join(HERE, 'results', 'report.txt'), 'w', encoding='utf8').write('\n'.join(lines))
