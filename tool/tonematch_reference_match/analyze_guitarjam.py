"""Aggregates results/guitarjam_a2_raw.json into results/guitarjam_a2_results.json (pre-registered metrics only)."""
import json, statistics as st, itertools, collections, math

D = 'tool/tonematch_reference_match/'
raw = json.load(open(D + 'results/guitarjam_a2_raw.json'))
sel = json.load(open(D + 'guitarjam_selection.json'))
nams = raw['nams']
cat = {k: v['category'] for k, v in nams.items()}
cases = raw['cases']
N = len(nams)

def metrics(ranks):
    n = len(ranks)
    b = collections.Counter()
    for r in ranks:
        b['1' if r == 1 else '2-3' if r <= 3 else '4-5' if r <= 5 else '6-10' if r <= 10 else '11-14'] += 1
    return {'n': n, 'top1': sum(r == 1 for r in ranks) / n, 'top3': sum(r <= 3 for r in ranks) / n, 'top5': sum(r <= 5 for r in ranks) / n,
            'mrr': sum(1 / r for r in ranks) / n, 'medianRank': st.median(ranks), 'meanRank': sum(ranks) / n,
            'rankDistribution': {k: b[k] / n for k in ('1', '2-3', '4-5', '6-10', '11-14')}}

res = {'provenance': {k: sel[k] for k in ('dataset', 'revision', 'license', 'acquired', 'filesAvailable', 'selection', 'pairs', 'exclusions')},
       'clips': [{k: c[k] for k in ('path', 'file', 'sha256', 'sec')} for c in sel['clips']], 'clipLevels': raw['clipInfo'],
       'nams': nams, 'pairCount': len(raw['pairs']), 'pairs': raw['pairs'], 'modes': {}}

for mode in ('blind', 'di'):
    res['modes'][mode] = {}
    for method in ('D1', 'D2', 'D3'):
        sub = [c for c in cases if c['mode'] == mode and c['method'] == method]
        main = [c for c in sub if not c['loo']]
        loo = [c for c in sub if c['loo']]
        m = metrics([c['rank'] for c in main])
        per_nam = {}
        for k in nams:
            m_k = metrics([c['rank'] for c in main if c['ref'] == k])
            per_nam[k] = {x: m_k[x] for x in ('top1', 'top3', 'mrr', 'medianRank')}
        per_cat = {}
        for ccat in ('clean', 'crunch', 'highgain'):
            rs = [c['rank'] for c in main if cat[c['ref']] == ccat]
            per_cat[ccat] = {'n': len(rs), 'top1': sum(r == 1 for r in rs) / len(rs), 'top3': sum(r <= 3 for r in rs) / len(rs), 'mrr': sum(1 / r for r in rs) / len(rs)}
        # confusion with the reference present: what is on top when the NAM itself is not top-1
        conf = {k: collections.Counter() for k in nams}
        for c in main:
            conf[c['ref']][c['top3'][0]] += 1
        confusion = {k: dict(v.most_common()) for k, v in conf.items()}
        catconf = {a: collections.Counter() for a in ('clean', 'crunch', 'highgain')}
        for c in main:
            a, t = cat[c['ref']], cat.get(c['top3'][0], '')
            if a:
                catconf[a][t or 'unlabelled'] += 1
        # leave-one-out
        labelled = [c for c in loo if cat[c['ref']] in ('clean', 'highgain', 'crunch')]
        wrong = [c for c in labelled if (cat[c['ref']] == 'clean' and any(cat[t] == 'highgain' for t in c['top3'])) or (cat[c['ref']] == 'highgain' and any(cat[t] == 'clean' for t in c['top3']))]
        nb = {}
        for k in nams:
            cs = [c for c in loo if c['ref'] == k]
            top1 = collections.Counter(c['top3'][0] for c in cs)
            top3 = collections.Counter(t for c in cs for t in c['top3'])
            sets = [set(c['top3']) for c in cs]
            jac = [len(a & b) / len(a | b) for a, b in itertools.combinations(sets, 2)]
            nb[k] = {'top1Neighbours': dict(top1.most_common(3)), 'top3Frequency': {t: v / len(cs) for t, v in top3.most_common(4)},
                     'modalTop1Share': top1.most_common(1)[0][1] / len(cs), 'meanTop3Jaccard': sum(jac) / len(jac)}
        crit = {'top3>=0.70': m['top3'] >= 0.70, 'mrr>=0.60': m['mrr'] >= 0.60, 'noCategoryTop3<0.50': min(v['top3'] for v in per_cat.values()) >= 0.50,
                'obviouslyWrong<=10%': len(wrong) / len(labelled) <= 0.10}
        res['modes'][mode][method] = {'overall': m, 'perNam': per_nam, 'perCategory': per_cat, 'top1Confusion': confusion, 'categoryConfusionTop1': {a: dict(v) for a, v in catconf.items()},
                                      'leaveOneOut': {'labelledCases': len(labelled), 'obviouslyWrong': len(wrong), 'obviouslyWrongRate': len(wrong) / len(labelled), 'neighbours': nb},
                                      'criteria': crit, 'criteriaAllPassed': all(crit.values())}

# within-NAM (across DI performances) vs between-NAM variation, DI-gated production-style features
feats = raw['features']
var = {}
for f in ('lnCentroid', 'lnRolloff', 'midLogit', 'crestDb'):
    within = math.sqrt(sum(st.pvariance([feats[k][c][f] for c in raw['clips']]) for k in nams) / N)
    means = [st.mean([feats[k][c][f] for c in raw['clips']]) for k in nams]
    b_means = st.pstdev(means)
    b_clip = st.mean([st.pstdev([feats[k][c][f] for k in nams]) for c in raw['clips']])
    var[f] = {'withinNamStd': within, 'betweenNamStdOfMeans': b_means, 'betweenNamStdPerClip': b_clip, 'withinOverBetweenMeans': within / b_means, 'withinOverBetweenPerClip': within / b_clip}
res['variation'] = var
json.dump(res, open(D + 'results/guitarjam_a2_results.json', 'w'), indent=1)

# console summary (primary = blind)
for mode in ('blind', 'di'):
    print('=== mode', mode)
    for method in ('D1', 'D2', 'D3'):
        r = res['modes'][mode][method]; o = r['overall']
        print(method, 'n=%d top1=%.3f top3=%.3f top5=%.3f mrr=%.3f median=%.1f mean=%.2f' % (o['n'], o['top1'], o['top3'], o['top5'], o['mrr'], o['medianRank'], o['meanRank']),
              'dist', {k: round(v, 2) for k, v in o['rankDistribution'].items()})
        print('   cats', {k: (round(v['top3'], 2), round(v['mrr'], 2)) for k, v in r['perCategory'].items()}, 'wrong %d/%d' % (r['leaveOneOut']['obviouslyWrong'], r['leaveOneOut']['labelledCases']), 'criteria', r['criteria'])
print('=== variation (within-NAM across DIs vs between-NAM)')
for f, v in var.items():
    print(' %-10s within=%.3f between(means)=%.3f between(per clip)=%.3f ratios=%.2f / %.2f' % (f, v['withinNamStd'], v['betweenNamStdOfMeans'], v['betweenNamStdPerClip'], v['withinOverBetweenMeans'], v['withinOverBetweenPerClip']))
levels = [v['rmsDb'] for v in raw['clipInfo'].values()]
print('clip RMS dBFS min/median/max %.1f / %.1f / %.1f' % (min(levels), st.median(levels), max(levels)))
