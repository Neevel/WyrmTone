"""Statistics for the Tone Match saturation validation gate (reads results/raw.json and the FULL
data of the previous gate). Nothing here changes AnalysisVersion 1. Decision rules were fixed
beforehand in docs/TONE_MATCH.md section 7.2.
"""
import json
import math
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GATE1 = os.path.join(HERE, '..', 'tonematch_gate')
raw = json.load(open(os.path.join(HERE, 'results', 'raw.json'), encoding='utf8'))
g1 = json.load(open(os.path.join(GATE1, 'results', 'raw.json'), encoding='utf8'))
nams = json.load(open(os.path.join(GATE1, 'ten_nam_set.json'), encoding='utf8'))
ids = [n['id'] for n in nams]
FREQ = raw['frequencies']
LEV = raw['levels']
RIG = {'01': 'full-rig', '08': 'full-rig', '06': 'amp-only', '10': 'amp-only'}
rig = {i: RIG.get(i, 'unknown') for i in ids}

lines = []


def P(s=''):
    lines.append(s)
    print(s)


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
    return float('nan') if ra.std() == 0 or rb.std() == 0 else float(np.corrcoef(ra, rb)[0, 1])


def pearson(a, b):
    a, b = np.asarray(a, float), np.asarray(b, float)
    return float('nan') if a.std() == 0 or b.std() == 0 else float(np.corrcoef(a, b)[0, 1])


def db20(x):
    return 20 * math.log10(max(x, 1e-30))


def db10(x):
    return 10 * math.log10(max(x, 1e-30))


# ---------------------------------------------------------------- per NAM x frequency probe metrics
def entry(i, f, l):
    return raw['probes'][i]['%s/%s' % (float(f), float(l))]


def curve(i, f):
    """(input levels, fundamental gain dB, THD dB) for one NAM and frequency."""
    gains, thds = [], []
    for l in LEV:
        e = entry(i, f, l)
        gains.append(db20(e['fundamental']) - l - 0.0)  # fundamental amplitude vs input peak amplitude
        thds.append(db20(e['thd']))
    return gains, thds


def onset(levels, gains):
    g0 = gains[0]
    for k in range(1, len(levels)):
        if gains[k] - g0 <= -1.0:
            lo, hi = gains[k - 1] - g0, gains[k] - g0
            t = (-1.0 - lo) / (hi - lo) if hi != lo else 0
            return levels[k - 1] + t * (levels[k] - levels[k - 1])
    return float('nan')


def slope(x, y):
    x, y = np.asarray(x, float), np.asarray(y, float)
    return float(((x - x.mean()) * (y - y.mean())).sum() / ((x - x.mean()) ** 2).sum())


M = {}  # id -> freq -> metrics
for i in ids:
    M[i] = {}
    for f in FREQ:
        gains, thds = curve(i, f)
        e12, e9 = entry(i, f, -12), entry(i, f, -9)
        M[i][f] = dict(
            gain0=gains[0],
            gainChange12=gains[LEV.index(-12)] - gains[0],
            gainChange9=gains[LEV.index(-9)] - gains[0],
            onset=onset(LEV, gains),
            thdLow=thds[0],
            thdHigh=thds[-1],
            thdGrowthSlope=slope(LEV, thds),
            oddEvenDb=db10(e12['odd'] / max(e12['even'], 1e-30)),
            residualOverThdDb=db20(e9['thdPlusN'] / e9['thd']),
            crest9=e9['crest'],
        )
CORE = ['thdLow', 'thdHigh', 'thdGrowthSlope', 'gainChange12', 'gainChange9', 'oddEvenDb']
ALLM = CORE + ['onset', 'gain0']


def agg(i, name, freqs=FREQ):
    v = [M[i][f][name] for f in freqs]
    ok = [x for x in v if not math.isnan(x)]
    if name == 'onset':
        # not reached = censored beyond the loudest probe level (-9 dBFS) -> -6 (documented, rank-only)
        v = [x if not math.isnan(x) else -6.0 for x in v]
        return float(np.median(v))
    return float(np.median(ok))


A = {i: {m: agg(i, m) for m in ALLM} for i in ids}

P('# PROBE: valid harmonics per frequency')
for f in FREQ:
    P('  %7.1f Hz: H2..H%d valid (k*f0 <= 21.6 kHz)' % (f, max(raw['validHarmonics']['%s' % f])))
P()
P('# PER-NAM SATURATION CURVES (median over the 6 probe frequencies)')
P('id rig       gain@-36  chg@-12  chg@-9  onset(-dBFS)  THD@-36(dB) THD@-9(dB) growth(dB/dB) odd/even@-12(dB)  notReachedAt')
for i in ids:
    nr = [f for f in FREQ if math.isnan(M[i][f]['onset'])]
    P('%s %-9s %7.1f  %7.2f  %6.2f  %9.1f  %10.1f  %9.1f  %8.2f  %10.1f     %s' % (
        i, rig[i], A[i]['gain0'], A[i]['gainChange12'], A[i]['gainChange9'], A[i]['onset'], A[i]['thdLow'], A[i]['thdHigh'],
        A[i]['thdGrowthSlope'], A[i]['oddEvenDb'], 'none' if not nr else ','.join('%g' % f for f in nr)))
P()
P('# Per frequency (THD@-9 dBFS in dB / gain change@-9 dB)')
P('id   ' + '  '.join('%12g' % f for f in FREQ))
for i in ids:
    P('%s   ' % i + '  '.join('%5.1f/%5.1f' % (M[i][f]['thdHigh'], M[i][f]['gainChange9']) for f in FREQ))

# ---------------------------------------------------------------- aliasing / residual observation
P()
P('# Residual (non-harmonic energy) vs THD at -9 dBFS: 20log10(THD+N / THD) per NAM (median over f); large = non-harmonic content (noise/alias/H9+)')
P('  ' + ', '.join('%s=%.1f' % (i, float(np.median([M[i][f]['residualOverThdDb'] for f in FREQ]))) for i in ids))
P('  at 1760 Hz: ' + ', '.join('%s=%.1f' % (i, M[i][1760.0]['residualOverThdDb']) for i in ids))

# ---------------------------------------------------------------- dimensionality
P()
P('# DIMENSIONALITY of the independent probe metrics (z-scored PCA, 10 NAMs)')
X = np.array([[A[i][m] for m in CORE] for i in ids])
Z = (X - X.mean(0)) / np.where(X.std(0) == 0, 1, X.std(0))
U, S, Vt = np.linalg.svd(Z, full_matrices=False)
var = S ** 2 / (S ** 2).sum()
P('  explained variance PC1..PC3: %.0f%% %.0f%% %.0f%%' % tuple(100 * var[:3]))
load = Vt[0] if Vt[0][CORE.index('thdHigh')] >= 0 else -Vt[0]
pc1 = Z @ (Vt[0] if Vt[0][CORE.index('thdHigh')] >= 0 else -Vt[0])
P('  PC1 loadings: ' + ', '.join('%s %.2f' % (m, l) for m, l in zip(CORE, load)))
P('  PC2 loadings: ' + ', '.join('%s %.2f' % (m, l) for m, l in zip(CORE, Vt[1])))
P('  Spearman among core metrics:')
P('      ' + ' '.join('%12s' % m[:12] for m in CORE))
for a in CORE:
    P('  %-12s' % a[:12] + ' '.join('%12.2f' % spearman([A[i][a] for i in ids], [A[i][b] for i in ids]) for b in CORE))
rho_dc = spearman([A[i]['thdHigh'] for i in ids], [A[i]['gainChange9'] for i in ids])
P('  rho(thdHigh, gainChange9) = %.2f (distortion vs compression)' % rho_dc)
one_dim = 'YES' if (var[0] >= 0.70 and abs(rho_dc) >= 0.7) else ('NO' if (var[1] >= 0.20 and abs(rho_dc) < 0.5) else 'UNCLEAR')
P('  SINGLE SATURATION DIMENSION JUSTIFIED (rule 7.2): %s' % one_dim)

# ---------------------------------------------------------------- V1 vs probe
def v1(role, i, name):
    e = g1['runs'][i]['%s/FULL' % role]
    return {**e['level'], **e['tone']}[name]


V1 = [('flatness1to8k', 'tone.sat.flatness1to8k'), ('hfGenerationDb', 'tone.sat.hfGenerationDb'),
      ('crestReductionDb', 'tone.sat.crestReductionDb'), ('envelopeCompressionDb', 'tone.sat.envelopeCompressionDb'),
      ('composite4', 'tone.sat.composite')]
RANGES = {'tone.sat.flatness1to8k': (0.0, 0.3), 'tone.sat.crestReductionDb': (0.0, 15.0), 'tone.sat.envelopeCompressionDb': (0.0, 15.0)}


def comp3(role, i):
    return float(np.mean([min(1, max(0, (v1(role, i, k) - lo) / (hi - lo))) for k, (lo, hi) in RANGES.items()]))


PROBE_TARGETS = CORE + ['onset', 'PC1']
for r in range(1):
    pass
res = {}
for role in ['rhythm', 'lead']:
    P()
    P('# V1 vs independent probe, %s FULL (Spearman / Pearson over 10 NAMs)' % role)
    P('%-22s ' % '' + ' '.join('%-13s' % t[:13] for t in PROBE_TARGETS))
    feats = {n: [v1(role, i, k) for i in ids] for n, k in V1}
    feats['composite3(noHF)'] = [comp3(role, i) for i in ids]
    res[role] = {}
    for n, vals in feats.items():
        row = []
        res[role][n] = {}
        for t in PROBE_TARGETS:
            tv = list(pc1) if t == 'PC1' else [A[i][t] for i in ids]
            s, p = spearman(vals, tv), pearson(vals, tv)
            res[role][n][t] = (s, p)
            row.append('%5.2f/%5.2f  ' % (s, p))
        P('%-22s ' % n + ' '.join(row))

# decision (rule 7.2)
P()
P('# DECISION per pre-registered rule 7.2')
okA = True
for role in ['rhythm', 'lead']:
    c4 = res[role]['composite4']['PC1'][0]
    comps = [res[role][n]['PC1'][0] for n, _ in V1 if n != 'composite4']
    P('  %s: rho(composite4, PC1)=%.2f; component rho(PC1): %s' % (role, c4, ', '.join('%.2f' % c for c in comps)))
    okA &= abs(c4) >= 0.7 and all(abs(c) >= 0.5 for c in comps)
improve = max(res[r_]['composite3(noHF)']['PC1'][0] - res[r_]['composite4']['PC1'][0] for r_ in ['rhythm', 'lead'])
if one_dim == 'YES':
    decision = 'A' if okA else ('B' if improve >= 0.1 else 'D')
elif one_dim == 'NO':
    decision = 'C'
else:
    decision = 'D'
P('  one dimension: %s, rule-A satisfied: %s, best composite3-vs-composite4 improvement: %.2f -> DECISION %s' % (one_dim, okA, improve, decision))

# ---------------------------------------------------------------- cab / rig
P()
P('# CAB / VOICING INFLUENCE (earlier noise-probe tilt = cab/voicing filtering; groups by inferred rig type)')
tilt = [g1['probe'][i]['tilt-30'] for i in ids]
P('  Spearman(probe metric, tilt-30): ' + ', '.join('%s %.2f' % (m, spearman([A[i][m] for i in ids], tilt)) for m in ALLM))
low = ['82.4', '110', '220']
lowf = [f for f in FREQ if f <= 220]
highf = [f for f in FREQ if f >= 880]
for name, fs in [('low-f (82.4-220 Hz)', lowf), ('high-f (880-1760 Hz)', highf)]:
    vals = {m: [agg(i, m, fs) for i in ids] for m in ['thdHigh', 'gainChange9']}
    P('  %-22s rho(thdHigh,tilt)=%.2f  rho(gainChange9,tilt)=%.2f' % (name, spearman(vals['thdHigh'], tilt), spearman(vals['gainChange9'], tilt)))
P('  group means (amp-only 06,10 / full-rig 01,08 / unknown):')
for m in ['thdHigh', 'gainChange9', 'onset', 'oddEvenDb', 'thdGrowthSlope']:
    P('    %-14s ' % m + '  '.join('%s %.1f' % (g, float(np.mean([A[i][m] for i in ids if rig[i] == g]))) for g in ['amp-only', 'full-rig', 'unknown']))
P('  THD@-9 dB at 1760 Hz minus THD@-9 dB at 110 Hz per NAM (cab/EQ weights higher harmonics): ' +
  ', '.join('%s %.1f' % (i, M[i][1760.0]['thdHigh'] - M[i][110.0]['thdHigh']) for i in ids))
P('  rho(that difference, tilt-30) = %.2f' % spearman([M[i][1760.0]['thdHigh'] - M[i][110.0]['thdHigh'] for i in ids], tilt))

# ---------------------------------------------------------------- offsets
P()
P('# FRAME-OFFSET VARIANCE (same NAM output, only the analysis grid shifts; 10 NAMs x RHYTHM+LEAD)')
OFFS = [0, 16, 32, 48, 128, 256, 384]
MULT = [0, 128, 256, 384]
SUB = [0, 16, 32, 48]
FE = ['tone.attackMs', 'tone.decayDbPerSec', 'tone.transientPeakToBodyDb', 'tone.centroidHz', 'tone.crestDb', 'tone.envelopeRangeDb',
      'tone.band.MID', 'tone.sat.flatness1to8k', 'tone.sat.hfGenerationDb', 'tone.sat.crestReductionDb', 'tone.sat.envelopeCompressionDb', 'tone.sat.composite']


def off(i, role, o, name):
    return raw['offsets'][i]['%s/%d' % (role, o)]['tone'][name]


P('%-34s %s' % ('feature', 'median CV%% all / mult-of-64 / sub-hop | min rank-stability rho vs offset 0 (all) | onsets(attack) '))
offres = {}
for name in FE:
    out = []
    cvs = {'all': [], 'mult': [], 'sub': []}
    mins = []
    for role in ['rhythm', 'lead']:
        for i in ids:
            for key, S_ in [('all', OFFS), ('mult', MULT), ('sub', SUB)]:
                v = np.array([off(i, role, o, name) for o in S_])
                cvs[key].append(100 * v.std() / max(abs(v.mean()), 1e-9))
        for o in OFFS[1:]:
            mins.append(spearman([off(i, role, 0, name) for i in ids], [off(i, role, o, name) for i in ids]))
    offres[name] = dict(cvAll=float(np.median(cvs['all'])), cvMult=float(np.median(cvs['mult'])), cvSub=float(np.median(cvs['sub'])), minRho=float(np.nanmin(mins)))
    P('%-34s %6.2f / %6.2f / %6.2f | %5.2f' % (name.replace('tone.', ''), offres[name]['cvAll'], offres[name]['cvMult'], offres[name]['cvSub'], offres[name]['minRho']))

# ---------------------------------------------------------------- exploratory (post-hoc, NOT part of the pre-registered rule)
P()
P('# EXPLORATORY (post-hoc): ceiling effect. NAMs whose compression onset is already at/below the lowest probe level')
sat = [i for i in ids if A[i]['onset'] <= -34.0]
P('  saturated at -36 dBFS already: %s (%d of 10); probe levels cannot resolve their linear region' % (sat, len(sat)))
P('  gain change @-9 dB among them: ' + ', '.join('%s %.1f' % (i, A[i]['gainChange9']) for i in sat))
P('  Spearman WITHIN these NAMs (n=%d), V1 feature vs probe metric:' % len(sat))
idx = [ids.index(i) for i in sat]
for role in ['rhythm', 'lead']:
    for n, k in V1 + [('composite3(noHF)', None)]:
        vals = [comp3(role, i) if k is None else v1(role, i, k) for i in sat]
        P('    %-6s %-22s thdHigh %5.2f  gainChange9 %5.2f  PC1 %5.2f' % (
            role, n, spearman(vals, [A[i]['thdHigh'] for i in sat]), spearman(vals, [A[i]['gainChange9'] for i in sat]), spearman(vals, [pc1[k_] for k_ in idx])))
rest = [i for i in ids if i not in sat]
P('  the %d less-saturated NAMs: %s ; the PC1 split is mainly %s vs %s' % (len(rest), rest, rest, sat))

json.dump(dict(aggregated=A, v1=res, offsets=offres, singleDimension=one_dim, decision=decision, pcaVariance=[float(x) for x in var]),
          open(os.path.join(HERE, 'results', 'report.json'), 'w', encoding='utf8'), indent=1, default=float)
open(os.path.join(HERE, 'results', 'report.txt'), 'w', encoding='utf8').write('\n'.join(lines))
