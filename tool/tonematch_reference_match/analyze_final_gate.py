"""Evaluates results/idmt_final_gate_raw.json exactly as defined in final_gate_preregistration.json (no new definitions)."""
import json, statistics as st, collections, hashlib

D = 'tool/tonematch_reference_match/'
pre_bytes = open(D + 'final_gate_preregistration.json', 'rb').read()
pre = json.loads(pre_bytes)
assert hashlib.sha256(pre_bytes).hexdigest() == open(D + 'final_gate_preregistration.sha256').read().strip()
raw = json.load(open(D + 'results/idmt_final_gate_raw.json'))
assert raw['preregistrationSha256'] == hashlib.sha256(pre_bytes).hexdigest()
nams = pre['nams']
cat = {k: v['category'] for k, v in nams.items()}
pairs = pre['pairs']
BASE = pre['baseline']

def wrong(top3, ref):
    return (cat[ref] == 'clean' and any(cat[t] == 'highgain' for t in top3)) or (cat[ref] == 'highgain' and any(cat[t] == 'clean' for t in top3))

def metrics(ranks, loo_cases):
    n = len(ranks)
    b = collections.Counter('1' if r == 1 else '2-3' if r <= 3 else '4-5' if r <= 5 else '6-10' if r <= 10 else '11-14' for r in ranks)
    lab = [c for c in loo_cases if cat[c['ref']] in ('clean', 'crunch', 'highgain')]
    w = sum(wrong(c['top3'], c['ref']) for c in lab)
    return {'n': n, 'top1': sum(r == 1 for r in ranks) / n, 'top3': sum(r <= 3 for r in ranks) / n, 'top5': sum(r <= 5 for r in ranks) / n,
            'mrr': sum(1 / r for r in ranks) / n, 'medianRank': st.median(ranks), 'meanRank': sum(ranks) / n,
            'obviouslyWrong': {'count': w, 'of': len(lab), 'rate': w / len(lab) if lab else None},
            'rankDistribution': {k: b[k] / n for k in ('1', '2-3', '4-5', '6-10', '11-14')}}

idx = collections.defaultdict(list)
for c in raw['cases']:
    idx[(c['mode'], c['method'], c['loo'])].append(c)

def block(mode, method, pred=lambda p: True):
    main = [c for c in idx[(mode, method, False)] if pred(pairs[c['pair']])]
    loo = [c for c in idx[(mode, method, True)] if pred(pairs[c['pair']])]
    return metrics([c['rank'] for c in main], loo)

res = {'preregistrationSha256': raw['preregistrationSha256'], 'targetActiveRmsDbfs': raw['targetActiveRmsDbfs'], 'renderings': raw['renderings'], 'elapsedSeconds': raw['elapsedSeconds'], 'pairCount': len(pairs),
       'levels': raw['levels'], 'modes': {}}
groups = sorted({p['group'] for p in pairs})
for mode in ('blind', 'di'):
    for method in ('D1', 'D2', 'D3'):
        e = {'overall': block(mode, method), 'byGroup': {g: block(mode, method, (lambda g: lambda p: p['group'] == g)(g)) for g in groups},
             'byGuitar': {t: block(mode, method, (lambda t: lambda p: p['guitar'] == t)(t)) for t in ('SAME_GUITAR', 'CROSS_GUITAR')},
             'byMaterial': {t: block(mode, method, (lambda t: lambda p: p['material'] == t)(t)) for t in ('SAME_MATERIAL', 'DIFFERENT_MATERIAL')}}
        res['modes'][f'{mode}/{method}'] = e

# primary decision: D2 BLIND only
P = res['modes']['blind/D2']
o = P['overall']
crit = {'top3>=0.70': o['top3'] >= 0.70, 'mrr>=0.60': o['mrr'] >= 0.60, 'obviouslyWrong<=0.10': o['obviouslyWrong']['rate'] <= 0.10, 'medianRank<=2': o['medianRank'] <= 2}
gcrit = {g: (P['byGroup'][g]['n'] < 100) or (P['byGroup'][g]['top3'] >= 0.50) for g in groups}
crit['contentGroups(>=100 cases need top3>=0.50)'] = all(gcrit.values())
res['primary'] = {'decisionMode': 'D2 BLIND', 'criteria': crit, 'contentGroupGate': gcrit, 'allPassed': all(crit.values()),
                  'deltaVsBaseline': {'top1': o['top1'] - BASE['top1'], 'top3': o['top3'] - BASE['top3'], 'mrr': o['mrr'] - BASE['mrr'], 'medianRank': o['medianRank'] - BASE['medianRank'], 'obviouslyWrong': o['obviouslyWrong']['rate'] - BASE['obviouslyWrong']}}

# per NAM / category (primary)
main = idx[('blind', 'D2', False)]
pn = {}
for k in nams:
    rs = [c['rank'] for c in main if c['ref'] == k]
    pn[k] = {'top1': sum(r == 1 for r in rs) / len(rs), 'top3': sum(r <= 3 for r in rs) / len(rs), 'mrr': sum(1 / r for r in rs) / len(rs), 'medianRank': st.median(rs)}
pc = {}
conf = {a: collections.Counter() for a in ('clean', 'crunch', 'highgain')}
for a in ('clean', 'crunch', 'highgain'):
    cs = [c for c in main if cat[c['ref']] == a]
    rs = [c['rank'] for c in cs]
    for c in cs:
        conf[a][cat.get(c['top3'][0]) or 'unlabelled'] += 1
    lab = [c for c in idx[('blind', 'D2', True)] if cat[c['ref']] == a]
    pc[a] = {'n': len(rs), 'top3': sum(r <= 3 for r in rs) / len(rs), 'mrr': sum(1 / r for r in rs) / len(rs),
             'top1SameCategory': conf[a][a] / sum(v for kk, v in conf[a].items() if kk != 'unlabelled'), 'wrongRate': sum(wrong(c['top3'], c['ref']) for c in lab) / len(lab)}
top1conf = {k: dict(collections.Counter(c['top3'][0] for c in main if c['ref'] == k).most_common(3)) for k in nams}
res['perNam'] = pn; res['perCategory'] = pc; res['categoryConfusionTop1'] = {a: dict(v) for a, v in conf.items()}; res['top1Confusion'] = top1conf

# level sensitivity control (documentation only)
F = ('lnCentroid', 'lnRolloff', 'midLogit', 'crestDb')
sens = collections.defaultdict(dict)
for r in raw['levelSensitivity']:
    sens[(r['nam'], r['clip'])][r['levelDbfs']] = r
deltas = {f: {'-33vs-30': [], '-27vs-30': []} for f in F}
by_nam = collections.defaultdict(lambda: {f: [] for f in F})
for (nam, clip), v in sens.items():
    for f in F:
        deltas[f]['-33vs-30'].append(v[-33.0][f] - v[-30.0][f]); deltas[f]['-27vs-30'].append(v[-27.0][f] - v[-30.0][f])
        by_nam[nam][f].append(max(abs(v[-33.0][f] - v[-30.0][f]), abs(v[-27.0][f] - v[-30.0][f])))
res['levelSensitivity'] = {'perFeature': {f: {k: {'mean': st.mean(x), 'meanAbs': st.mean(abs(y) for y in x), 'maxAbs': max(abs(y) for y in x)} for k, x in d.items()} for f, d in deltas.items()},
                           'maxAbsChangePerNam': {n: {f: st.mean(v) for f, v in d.items()} for n, d in by_nam.items()}, 'cases': len(sens)}
json.dump(res, open(D + 'results/idmt_final_gate_results.json', 'w'), indent=1)

def line(m):
    return 'n=%d top1=%.3f top3=%.3f top5=%.3f mrr=%.3f med=%.1f mean=%.2f wrong=%d/%d (%.1f%%)' % (m['n'], m['top1'], m['top3'], m['top5'], m['mrr'], m['medianRank'], m['meanRank'], m['obviouslyWrong']['count'], m['obviouslyWrong']['of'], 100 * m['obviouslyWrong']['rate'])
print('PREREG', raw['preregistrationSha256'], 'renderings', raw['renderings'], 'elapsed %.0fs' % raw['elapsedSeconds'], 'pairs', len(pairs))
lv = raw['levels']; print('gain dB min/median/max %.1f %.1f %.1f; peak after %.1f dBFS max' % (min(v['gainDb'] for v in lv.values()), st.median(v['gainDb'] for v in lv.values()), max(v['gainDb'] for v in lv.values()), max(v['peakAfterDbfs'] for v in lv.values())))
for key, e in res['modes'].items():
    print('==', key, line(e['overall']), {k: round(v, 2) for k, v in e['overall']['rankDistribution'].items()})
    if key in ('blind/D2', 'di/D2'):
        for g, m in e['byGroup'].items():
            print('    group %-20s %s' % (g, line(m)))
        for g, m in e['byGuitar'].items():
            print('    %-20s %s' % (g, line(m)))
        for g, m in e['byMaterial'].items():
            print('    %-20s %s' % (g, line(m)))
print('PRIMARY D2 BLIND criteria', res['primary']['criteria'], 'groups', res['primary']['contentGroupGate'], 'ALL PASSED =', res['primary']['allPassed'])
print('delta vs baseline', {k: round(v, 3) for k, v in res['primary']['deltaVsBaseline'].items()})
print('per NAM'); [print(' %-10s %-8s top1=%.2f top3=%.2f mrr=%.2f med=%.1f' % (k, cat[k] or '-', v['top1'], v['top3'], v['mrr'], v['medianRank'])) for k, v in pn.items()]
print('per category', {a: {x: round(y, 2) for x, y in v.items()} for a, v in pc.items()})
print('category confusion top1', res['categoryConfusionTop1'])
print('level sensitivity (feature: mean|d| -33vs-30 / -27vs-30, max)'); [print(' ', f, round(v['-33vs-30']['meanAbs'], 3), round(v['-27vs-30']['meanAbs'], 3), round(max(v['-33vs-30']['maxAbs'], v['-27vs-30']['maxAbs']), 3)) for f, v in res['levelSensitivity']['perFeature'].items()]
print('per NAM mean max|d|', {n: {f: round(x, 3) for f, x in d.items()} for n, d in res['levelSensitivity']['maxAbsChangePerNam'].items()})
