"""Evaluation of the final envelope-stability gate (docs/TONE_MATCH.md section 9). Reads
results/final_gate_raw.json. Offsets, thresholds and the selection rule were fixed beforehand.
"""
import json
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
raw = json.load(open(os.path.join(HERE, 'results', 'final_gate_raw.json'), encoding='utf8'))
ids = sorted(raw['offsets'])
roles = ['rhythm', 'lead']
HOLD = raw['holdoutOffsets']
CANDS = raw['candidates']
FEATS = {'attack': 'tone.attackMs', 'decay': 'tone.decayDbPerSec', 'transient': 'tone.transientPeakToBodyDb'}
ENV = set(FEATS.values()) | {'tone.onsetCount'}
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


def val(i, role, o, c, f):
    return raw['offsets'][i]['%s/%d' % (role, o)][c][FEATS.get(f, f)]


def stability(c, f):
    cvs, mins = [], []
    for role in roles:
        for i in ids:
            v = np.array([val(i, role, o, c, f) for o in HOLD])
            cvs.append(100 * v.std() / max(abs(v.mean()), 1e-9))
        for o in HOLD:
            mins.append(spearman([val(i, role, 0, c, f) for i in ids], [val(i, role, o, c, f) for i in ids]))
    return float(np.median(cvs)), float(np.nanmin(mins))


def accuracy(c, f):
    key = {'attack': 'attackMs', 'decay': 'decayDbPerSec', 'transient': 'transientPeakToBodyDb'}[f]
    errs, errs0 = [], []
    for role in roles:
        for i in ids:
            ref = raw['reference']['%s/%s' % (i, role)][key]
            for o in HOLD:
                errs.append(abs(val(i, role, o, c, f) - ref))
            errs0.append(abs(val(i, role, 0, c, f) - ref))
    return float(np.mean(errs)), float(np.max(errs)), float(np.mean(errs0))


res = {}
P('# Hold-out offsets: %s' % HOLD)
P()
P('# Stability on hold-out offsets (median CV%% over NAM x role / minimum Spearman rho vs offset 0)  | accuracy vs hop-1 reference: mean abs / max abs error (all hold-out offsets) | mean abs at offset 0')
for f in FEATS:
    for c in CANDS:
        cv, mr = stability(c, f)
        ma, mx, m0 = accuracy(c, f)
        res[(c, f)] = dict(cv=cv, minRho=mr, maeHold=ma, maxHold=mx, mae0=m0)
        unit = 'ms' if f == 'attack' else ('dB/s' if f == 'decay' else 'dB')
        P('%-10s %-6s CV %6.2f%%  min rho %.3f  | MAE %.2f %s  max %.2f %s | MAE@0 %.2f %s' % (f, c, cv, mr, ma, unit, mx, unit, m0, unit))
    P()

# criteria
P('# Primary criteria per candidate (section 9.3)')
passing = {}
for c in CANDS[1:]:
    a, d, t = res[(c, 'attack')], res[(c, 'decay')], res[(c, 'transient')]
    t1 = res[('v1', 'transient')]
    ok = dict(
        attack=a['cv'] < 3.0 and a['minRho'] >= 0.95,
        decay=d['cv'] < 3.0 and d['minRho'] >= 0.95,
        transientNotWorse=t['cv'] <= t1['cv'] + 1e-12 and t['minRho'] >= t1['minRho'] - 1e-12,
        transientPreferred=t['cv'] < 3.0 and t['minRho'] >= 0.95,
        attackAccuracyNotWorseThanV1=a['maeHold'] <= res[('v1', 'attack')]['maeHold'] + 1e-12,
    )
    passing[c] = ok
    P('%-6s attack %s | decay %s | transient not worse %s (preferred %s) | attack accuracy <= V1 %s' % (
        c, 'PASS' if ok['attack'] else 'FAIL', 'PASS' if ok['decay'] else 'FAIL', 'PASS' if ok['transientNotWorse'] else 'FAIL',
        'yes' if ok['transientPreferred'] else 'no', 'PASS' if ok['attackAccuracyNotWorseThanV1'] else 'FAIL'))

# information loss / spread
P()
P('# Information retained (offset 0): Spearman across the 20 NAM x role values vs the hop-1 reference, and between-NAM std')
for f, key in [('attack', 'attackMs'), ('decay', 'decayDbPerSec'), ('transient', 'transientPeakToBodyDb')]:
    refv = [raw['reference']['%s/%s' % (i, r)][key] for r in roles for i in ids]
    for c in CANDS:
        v = [val(i, r, 0, c, f) for r in roles for i in ids]
        P('%-10s %-6s rho vs reference %.3f   std %.3f   distinct values %d/20' % (f, c, spearman(v, refv), np.std(v), len(set(round(x, 6) for x in v))))

# unaffected features
P()
P('# Unaffected features identical to V1 (all NAM x role x offsets, exact equality)')
bad = 0
n = 0
for i in ids:
    for role in roles:
        for o in [0] + HOLD:
            e = raw['offsets'][i]['%s/%d' % (role, o)]
            for c in CANDS[1:]:
                for k, v in e['v1'].items():
                    if k in ENV:
                        continue
                    n += 1
                    if e[c].get(k) != v:
                        bad += 1
P('compared %d values, differing %d' % (n, bad))

# performance
P()
P('# Extraction cost on T15 (desktop; mean over the 10 NAMs of the mean of 5 runs after a warm-up), ms')
perf = {}
for role in roles:
    rows = [raw['perf']['%s/%s' % (i, role)] for i in ids]
    inf = float(np.mean([r['inferenceMs'] for r in rows]))
    base = float(np.mean([r['v1Us'] for r in rows])) / 1000
    line = '%s (15.5 s audio): inference %.0f | ' % (role, inf)
    perf[role] = dict(inferenceMs=inf)
    for c in CANDS:
        ext = float(np.mean([r['%sUs' % c] for r in rows])) / 1000
        med = float(np.median([r['%sUs' % c] for r in rows])) / 1000
        perf[role][c] = dict(extractionMs=ext, medianMs=med, totalMs=inf + ext, overheadVsV1Pct=100 * (ext - base) / (inf + base))
        line += '%s %.0f (median %.0f, total overhead vs V1 +%.1f%%) | ' % (c, ext, med, perf[role][c]['overheadVsV1Pct'])
    P(line)

# decision (section 9.4)
P()
winner = None
for c in CANDS[1:]:
    ok = passing[c]
    if ok['attack'] and ok['decay'] and ok['transientNotWorse'] and ok['attackAccuracyNotWorseThanV1']:
        winner = c
        break
P('SMALLEST PASSING CANDIDATE (primary criteria, before synthetic/golden checks): %s' % (winner or 'NONE'))
json.dump(dict(results={'%s/%s' % k: v for k, v in res.items()}, passing=passing, winner=winner, perf=perf),
          open(os.path.join(HERE, 'results', 'final_gate_report.json'), 'w', encoding='utf8'), indent=1, default=float)
open(os.path.join(HERE, 'results', 'final_gate_report.txt'), 'w', encoding='utf8').write('\n'.join(lines))
