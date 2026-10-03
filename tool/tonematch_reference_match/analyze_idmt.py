"""Aggregates results/idmt_a2_raw.json into results/idmt_a2_results.json.

PRE-REGISTERED BEFORE THE RUN (not changed afterwards):
  single-performance (primary: D2, BLIND, all 73 pairs): Top-3 >= 0.70, MRR >= 0.60, obviously wrong <= 10 %,
    no labelled category with Top-3 < 0.50. Per condition (A same group, B cross technique, C cross guitar) reported separately.
  multi-performance vs single-performance on the SAME reference cases (primary: D2, BLIND, N=10, all pairs):
    Top-3 not worse, MRR improves by >= +0.05, median rank not worse, obviously-wrong rate not higher.
    MULTI-PERFORMANCE SIGNATURE = PASS iff all four hold for the primary; N = 3 and 5 and D1/D3 are reported, not decisive.
  obviously wrong (leave-one-out, labelled NAMs): clean reference with a high-gain NAM in the top 3 or the reverse.
"""
import json, statistics as st, itertools, collections, math

D = 'tool/tonematch_reference_match/'
raw = json.load(open(D + 'results/idmt_a2_raw.json'))
sel = json.load(open(D + 'idmt_selection.json'))
nams = raw['nams']
cat = {k: v['category'] for k, v in nams.items()}
pairs = sel['pairs']
clips = {c['id']: c for c in sel['clips']}
PRIMARY = ('D2', 'blind')
N_PRIMARY = 10

def metrics(ranks):
    n = len(ranks)
    b = collections.Counter()
    for r in ranks:
        b['1' if r == 1 else '2-3' if r <= 3 else '4-5' if r <= 5 else '6-10' if r <= 10 else '11-14'] += 1
    return {'n': n, 'top1': sum(r == 1 for r in ranks) / n, 'top3': sum(r <= 3 for r in ranks) / n, 'top5': sum(r <= 5 for r in ranks) / n,
            'mrr': sum(1 / r for r in ranks) / n, 'medianRank': st.median(ranks), 'meanRank': sum(ranks) / n,
            'rankDistribution': {k: b[k] / n for k in ('1', '2-3', '4-5', '6-10', '11-14')}}

def wrong(top3, ref):
    return (cat[ref] == 'clean' and any(cat[t] == 'highgain' for t in top3)) or (cat[ref] == 'highgain' and any(cat[t] == 'clean' for t in top3))

# --- index single and multi cases
single = collections.defaultdict(list)            # (mode, method, loo) -> cases
for c in raw['single']:
    single[(c['mode'], c['method'], c['loo'])].append(c)
multi = {}                                        # (refClip, n, mode, method, loo, ref) -> case
for c in raw['multi']:
    multi[(c['refClip'], c['n'], c['mode'], c['method'], c['loo'], c['ref'])] = c

def select(cases, pred):
    return [c for c in cases if pred(pairs[c['pair']])]

CONDS = {'ALL': lambda p: True, 'A': lambda p: p['cond'] == 'A', 'B': lambda p: p['cond'] == 'B', 'C': lambda p: p['cond'] == 'C'}
for grp in sorted({(p['cond'], p['group']) for p in pairs}):
    CONDS[f'{grp[0]}:{grp[1]}'] = (lambda g: lambda p: (p['cond'], p['group']) == g)(grp)

def obviously_wrong(cases_loo):
    lab = [c for c in cases_loo if cat[c['ref']] in ('clean', 'crunch', 'highgain')]
    w = [c for c in lab if wrong(c['top3'], c['ref'])]
    return len(w), len(lab)

res = {'provenance': {k: sel[k] for k in ('dataset', 'url', 'doi', 'version', 'license', 'acquired', 'zipMd5', 'zipExpectedMd5', 'filesAvailable', 'exclusions', 'rule')},
       'clips': [{k: c.get(k) for k in ('id', 'group', 'guitar', 'technique', 'instrumentModel', 'pickUpSetting', 'seconds', 'bits', 'channels', 'rate', 'sha256', 'zip')} for c in sel['clips']],
       'clipLevels': raw['clipInfo'], 'nams': nams, 'pairCount': len(pairs), 'pairs': pairs, 'conditions': {}}

for mode in ('blind', 'di'):
    for method in ('D1', 'D2', 'D3'):
        key = f'{mode}/{method}'
        out = {}
        for cname, pred in CONDS.items():
            base = select(single[(mode, method, False)], pred)
            if not base:
                continue
            loo_cases = select(single[(mode, method, True)], pred)
            sm = metrics([c['rank'] for c in base])
            ow = obviously_wrong(loo_cases)
            sm['obviouslyWrong'] = {'count': ow[0], 'of': ow[1], 'rate': ow[0] / ow[1]}
            entry = {'single': sm, 'multi': {}}
            for n in (3, 5, 10):
                mranks, mloo = [], []
                for c in base:
                    p = pairs[c['pair']]
                    mranks.append(multi[(p['ref'], n, mode, method, False, c['ref'])]['rank'])
                for c in loo_cases:
                    p = pairs[c['pair']]
                    mloo.append(multi[(p['ref'], n, mode, method, True, c['ref'])])
                mm = metrics(mranks)
                mow = obviously_wrong(mloo)
                mm['obviouslyWrong'] = {'count': mow[0], 'of': mow[1], 'rate': mow[0] / mow[1]}
                mm['delta'] = {'top3': mm['top3'] - sm['top3'], 'mrr': mm['mrr'] - sm['mrr'], 'medianRank': mm['medianRank'] - sm['medianRank'], 'obviouslyWrongRate': mm['obviouslyWrong']['rate'] - sm['obviouslyWrong']['rate']}
                mm['improvementCriteria'] = {'top3NotWorse': mm['top3'] >= sm['top3'], 'mrrPlus0.05': mm['mrr'] >= sm['mrr'] + 0.05, 'medianNotWorse': mm['medianRank'] <= sm['medianRank'], 'wrongNotHigher': mm['obviouslyWrong']['rate'] <= sm['obviouslyWrong']['rate']}
                mm['improvementAllPassed'] = all(mm['improvementCriteria'].values())
                entry['multi'][str(n)] = mm
            out[cname] = entry
        res['conditions'][key] = out

# per-NAM and per-category and confusions for the primary (single and multi N=10)
method, mode = PRIMARY
base = single[(mode, method, False)]
def per_nam(ranks_by_ref):
    return {k: {x: metrics(v)[x] for x in ('top1', 'top3', 'mrr', 'medianRank')} for k, v in ranks_by_ref.items()}
sn = collections.defaultdict(list); mn = collections.defaultdict(list)
conf_s = {k: collections.Counter() for k in nams}; conf_m = {k: collections.Counter() for k in nams}
catconf_s = {a: collections.Counter() for a in ('clean', 'crunch', 'highgain')}; catconf_m = {a: collections.Counter() for a in ('clean', 'crunch', 'highgain')}
percat_s = collections.defaultdict(list); percat_m = collections.defaultdict(list)
for c in base:
    p = pairs[c['pair']]
    m = multi[(p['ref'], N_PRIMARY, mode, method, False, c['ref'])]
    sn[c['ref']].append(c['rank']); mn[c['ref']].append(m['rank'])
    conf_s[c['ref']][c['top3'][0]] += 1; conf_m[c['ref']][m['top3'][0]] += 1
    if cat[c['ref']] in catconf_s:
        catconf_s[cat[c['ref']]][cat.get(c['top3'][0]) or 'unlabelled'] += 1
        catconf_m[cat[c['ref']]][cat.get(m['top3'][0]) or 'unlabelled'] += 1
        percat_s[cat[c['ref']]].append(c['rank']); percat_m[cat[c['ref']]].append(m['rank'])
res['primaryDetail'] = {
    'perNamSingle': per_nam(sn), 'perNamMultiN10': per_nam(mn),
    'perCategorySingle': {k: {'n': len(v), 'top3': sum(r <= 3 for r in v) / len(v), 'mrr': sum(1 / r for r in v) / len(v)} for k, v in percat_s.items()},
    'perCategoryMultiN10': {k: {'n': len(v), 'top3': sum(r <= 3 for r in v) / len(v), 'mrr': sum(1 / r for r in v) / len(v)} for k, v in percat_m.items()},
    'top1ConfusionSingle': {k: dict(v.most_common()) for k, v in conf_s.items()}, 'top1ConfusionMultiN10': {k: dict(v.most_common()) for k, v in conf_m.items()},
    'categoryConfusionSingle': {a: dict(v) for a, v in catconf_s.items()}, 'categoryConfusionMultiN10': {a: dict(v) for a, v in catconf_m.items()},
}
# leave-one-out neighbours (single vs multi N=10)
nb = {}
for k in nams:
    cs = [c for c in single[(mode, method, True)] if c['ref'] == k]
    ms = [multi[(pairs[c['pair']]['ref'], N_PRIMARY, mode, method, True, k)] for c in cs]
    def summary(lst):
        t3 = collections.Counter(t for c in lst for t in c['top3'])
        sets = [set(c['top3']) for c in lst]
        jac = [len(a & b) / len(a | b) for a, b in itertools.combinations(sets, 2)]
        return {'top3Frequency': {t: v / len(lst) for t, v in t3.most_common(4)}, 'meanTop3Jaccard': sum(jac) / len(jac)}
    nb[k] = {'single': summary(cs), 'multiN10': summary(ms)}
res['leaveOneOutNeighbours'] = nb

# feature stability: within-NAM vs between-NAM, by technique group, single clips and multi-clip signatures
feats = raw['features']
F = ('lnCentroid', 'lnRolloff', 'midLogit', 'crestDb')
def wb(clip_ids):
    out = {}
    for f in F:
        within = math.sqrt(sum(st.pvariance([feats[k][c][f] for c in clip_ids]) for k in nams) / len(nams))
        between = st.pstdev([st.mean([feats[k][c][f] for c in clip_ids]) for k in nams])
        out[f] = {'within': within, 'between': between, 'ratio': within / between}
    return out
groups = collections.defaultdict(list)
for c in sel['clips']:
    groups[c['group']].append(c['id'])
stability = {'allClips': wb([c['id'] for c in sel['clips']])}
for g, ids in groups.items():
    if len(ids) >= 3:
        stability[g] = wb(ids)
# cross-guitar: the same lick re-performed on the three dataset-2 guitars
cg = {}
for f in F:
    w = []; b = []
    for stem in ('Lick2_MN', 'Lick5_KN', 'Lick4_KBSH'):
        ids = [f'{g}_{stem}' for g in ('LP', 'FS', 'AR')]
        w += [st.pvariance([feats[k][c][f] for c in ids]) for k in nams]
        b.append(st.pstdev([st.mean([feats[k][c][f] for c in ids]) for k in nams]))
    cg[f] = {'within': math.sqrt(sum(w) / len(w)), 'between': st.mean(b), 'ratio': math.sqrt(sum(w) / len(w)) / st.mean(b)}
stability['crossGuitarSameLick'] = cg
# signature stability: disjoint interleaved partitions of all clips, per-feature median
ids_all = [c['id'] for c in sel['clips']]
sig_stab = {}
for n in (3, 5, 10):
    K = len(ids_all) // n
    parts = [ids_all[j::K][:n] for j in range(K)]
    row = {}
    for f in F:
        sigs = {k: [st.median([feats[k][c][f] for c in part]) for part in parts] for k in nams}
        within = math.sqrt(sum(st.pvariance(v) for v in sigs.values()) / len(nams))
        between = st.pstdev([st.mean(v) for v in sigs.values()])
        row[f] = {'within': within, 'between': between, 'ratio': within / between}
    sig_stab[str(n)] = {'groups': K, 'features': row}
stability['signatureByN'] = sig_stab
res['featureStability'] = stability
json.dump(res, open(D + 'results/idmt_a2_results.json', 'w'), indent=1)

# ---------------- console summary
def line(m):
    return 'n=%d top1=%.3f top3=%.3f top5=%.3f mrr=%.3f med=%.1f mean=%.2f wrong=%d/%d(%.1f%%)' % (m['n'], m['top1'], m['top3'], m['top5'], m['mrr'], m['medianRank'], m['meanRank'], m['obviouslyWrong']['count'], m['obviouslyWrong']['of'], 100 * m['obviouslyWrong']['rate'])
for mode in ('blind', 'di'):
    for method in ('D1', 'D2', 'D3'):
        print('=== %s %s' % (mode, method))
        for cname in ('ALL', 'A', 'B', 'C'):
            e = res['conditions'][f'{mode}/{method}'][cname]
            print(' %-4s single %s' % (cname, line(e['single'])))
            for n in ('3', '5', '10'):
                m = e['multi'][n]
                print('       N=%-2s %s | d.top3=%+.3f d.mrr=%+.3f d.med=%+.1f d.wrong=%+.3f pass=%s' % (n, line(m), m['delta']['top3'], m['delta']['mrr'], m['delta']['medianRank'], m['delta']['obviouslyWrongRate'], m['improvementAllPassed']))
print('=== primary groups (D2 blind)')
for cname, e in res['conditions']['blind/D2'].items():
    if ':' in cname:
        print(' %-16s single top3=%.2f mrr=%.2f | N10 top3=%.2f mrr=%.2f' % (cname, e['single']['top3'], e['single']['mrr'], e['multi']['10']['top3'], e['multi']['10']['mrr']))
print('=== stability within/between ratio (single clips)')
for g, v in stability.items():
    if g != 'signatureByN':
        print(' %-22s' % g, {f: round(x['ratio'], 2) for f, x in v.items()})
print('=== signature within/between ratio')
for n, v in sig_stab.items():
    print(' N=%s groups=%d' % (n, v['groups']), {f: round(x['ratio'], 2) for f, x in v['features'].items()})
