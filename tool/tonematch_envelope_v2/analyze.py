"""Evaluation of the AnalysisVersion-2 acceptance experiment (reads results/raw.json).
Thresholds were fixed before the run in docs/TONE_MATCH.md section 8.2 and are not changed here.
"""
import json
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
raw = json.load(open(os.path.join(HERE, 'results', 'raw.json'), encoding='utf8'))
g1 = json.load(open(os.path.join(HERE, '..', 'tonematch_gate', 'results', 'raw.json'), encoding='utf8'))
ids = sorted(raw['offsets'].keys())
roles = ['rhythm', 'lead']
EXACT = raw['exactOffsets']
GEN = [0] + raw['generalizationOffsets']
ALL = sorted(set(EXACT + raw['generalizationOffsets']))
ENV = ['tone.attackMs', 'tone.decayDbPerSec', 'tone.transientPeakToBodyDb', 'tone.onsetCount']
STABLE = ['tone.centroidHz', 'tone.crestDb', 'tone.envelopeRangeDb', 'tone.band.MID', 'tone.sat.flatness1to8k', 'tone.sat.hfGenerationDb',
          'tone.sat.crestReductionDb', 'tone.sat.envelopeCompressionDb', 'tone.sat.composite']
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


def val(i, role, o, ver, name):
    e = raw['offsets'][i]['%s/%d' % (role, o)][ver]
    return {**e['level'], **e['tone']}[name]


def stats(ver, name, offs):
    cvs = []
    mins = []
    for role in roles:
        for i in ids:
            v = np.array([val(i, role, o, ver, name) for o in offs])
            cvs.append(100 * v.std() / max(abs(v.mean()), 1e-9))
        for o in offs:
            if o == 0:
                continue
            mins.append(spearman([val(i, role, 0, ver, name) for i in ids], [val(i, role, o, ver, name) for i in ids]))
    return float(np.median(cvs)), float(np.nanmin(mins))


out = {}
P('# Offset stability V1 vs V2 (median CV%% over NAM x role / minimum rank stability rho vs offset 0)')
P('%-30s | %-26s | %-26s | %-26s' % ('feature', 'EXACT offsets (acceptance)', 'generalization (0,5,11,24,37,53)', 'all offsets'))
for name in ENV[:3] + STABLE:
    row = {}
    cells = []
    for label, offs in [('exact', EXACT), ('gen', GEN), ('all', ALL)]:
        a1, a2 = stats('v1', name, offs), stats('v2', name, offs)
        row[label] = dict(v1=a1, v2=a2)
        cells.append('V1 %5.2f/%.2f  V2 %5.2f/%.2f' % (a1[0], a1[1], a2[0], a2[1]))
    out[name] = row
    P('%-30s | %s | %s | %s' % (name.replace('tone.', ''), cells[0], cells[1], cells[2]))

P()
P('# Acceptance criteria (section 8.2), EXACT offsets')
ok = {}
a = out['tone.attackMs']['exact']['v2']
d = out['tone.decayDbPerSec']['exact']['v2']
t1 = out['tone.transientPeakToBodyDb']['exact']['v1']
t2 = out['tone.transientPeakToBodyDb']['exact']['v2']
ok['attack'] = a[0] < 3.0 and a[1] >= 0.95
ok['decay'] = d[0] < 3.0 and d[1] >= 0.95
ok['transientNotWorse'] = t2[0] <= t1[0] + 1e-12 and t2[1] >= t1[1] - 1e-12
P('attack  V2: CV %.2f%% (<3) min rho %.3f (>=0.95) -> %s   [V1: %.2f%% / %.3f]' % (a[0], a[1], 'PASS' if ok['attack'] else 'FAIL', *out['tone.attackMs']['exact']['v1']))
P('decay   V2: CV %.2f%% (<3) min rho %.3f (>=0.95) -> %s   [V1: %.2f%% / %.3f]' % (d[0], d[1], 'PASS' if ok['decay'] else 'FAIL', *out['tone.decayDbPerSec']['exact']['v1']))
P('transient: V1 CV %.2f%% / rho %.3f ; V2(multiphase) CV %.2f%% / rho %.3f -> %s' % (t1[0], t1[1], t2[0], t2[1], 'not worse' if ok['transientNotWorse'] else 'WORSE (keep V1 definition for this feature)'))
P('generalization offsets (not part of acceptance): attack V2 CV %.2f%% / rho %.3f ; decay V2 CV %.2f%% / rho %.3f' % (
    *out['tone.attackMs']['gen']['v2'], *out['tone.decayDbPerSec']['gen']['v2']))

# unaffected features identical
P()
P('# Unaffected features identical between V1 and V2 (exact equality, all NAMs x roles x offsets)')
bad = []
n = 0
for i in ids:
    for role in roles:
        for o in ALL:
            e = raw['offsets'][i]['%s/%d' % (role, o)]
            if e['v1']['level'] != e['v2']['level']:
                bad.append((i, role, o, 'level'))
            for k in e['v1']['tone']:
                if k in ENV:
                    continue
                n += 1
                if e['v1']['tone'][k] != e['v2']['tone'].get(k):
                    bad.append((i, role, o, k))
P('compared %d values; differing: %d %s' % (n, len(bad), bad[:6]))
out['unaffectedIdentical'] = len(bad) == 0

# V1 reproduces the previous gate bit-exactly at offset 0
P()
P('# V1 (refactored extractor) vs the earlier gate data, FULL, offset 0 (exact equality of every tone and level value)')
bad2 = []
n2 = 0
for i in ids:
    for role in roles:
        prev = g1['runs'][i]['%s/FULL' % role]
        cur = raw['offsets'][i]['%s/0' % role]['v1']
        for grp in ['tone', 'level']:
            for k, v in prev[grp].items():
                n2 += 1
                if cur[grp].get(k) != v:
                    bad2.append((i, role, k))
P('compared %d values; differing: %d %s' % (n2, len(bad2), bad2[:6]))
out['v1Reproduced'] = len(bad2) == 0

# how much V2 values differ from V1
P()
P('# V2 vs V1 values at offset 0 (median relative difference over NAM x role)')
for k in ENV[:3]:
    rel = [abs(val(i, r, 0, 'v2', k) - val(i, r, 0, 'v1', k)) / max(abs(val(i, r, 0, 'v1', k)), 1e-9) for i in ids for r in roles]
    P('%-30s %.1f%% (max %.1f%%)' % (k.replace('tone.', ''), 100 * float(np.median(rel)), 100 * max(rel)))

# performance
P()
P('# Extraction cost, T15, desktop (mean over 10 NAMs; ms)')
perf = {}
for role in roles:
    rows = [raw['perf']['%s/%s' % (i, role)] for i in ids]
    inf = np.mean([r['inferenceMs'] for r in rows])
    e1 = np.mean([r['v1ExtractUs'] for r in rows]) / 1000
    e2 = np.mean([r['v2ExtractUs'] for r in rows]) / 1000
    perf[role] = dict(inferenceMs=float(inf), v1ExtractMs=float(e1), v2ExtractMs=float(e2), deltaMs=float(e2 - e1), deltaPct=float(100 * (e2 - e1) / e1),
                      totalImpactPct=float(100 * (e2 - e1) / (inf + e1)), audioSeconds=rows[0]['seconds'])
    P('%s (%.1f s audio): inference %.0f | V1 extraction %.1f | V2 extraction %.1f | delta %.1f ms (+%.0f%% of extraction) | total analysis impact +%.1f%%' % (
        role, rows[0]['seconds'], inf, e1, e2, e2 - e1, 100 * (e2 - e1) / e1, 100 * (e2 - e1) / (inf + e1)))
out['perf'] = perf
out['acceptance'] = ok
json.dump(out, open(os.path.join(HERE, 'results', 'report.json'), 'w', encoding='utf8'), indent=1, default=float)
open(os.path.join(HERE, 'results', 'report.txt'), 'w', encoding='utf8').write('\n'.join(lines))
