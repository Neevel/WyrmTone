"""Summarises results/results.json of the reference-match spike (no tuning, just the pre-registered metrics)."""
import json, collections, sys

r = json.load(open('tool/tonematch_reference_match/results/results.json'))
print('used NAMs:', len(r['usedNams']), 'skipped:', r['skipped'])
for k, v in r['usedNams'].items():
    print(' ', k, v['category'] or '-', v['file'][:60])
cases = r['cases']

def summary(filt):
    xs = [c for c in cases if filt(c) and not c['loo']]
    if not xs:
        return None
    n = len(xs)
    return n, sum(c['rank'] == 1 for c in xs) / n, sum(c['rank'] <= 3 for c in xs) / n, sum(1 / c['rank'] for c in xs) / n, sorted(c['rank'] for c in xs)[-3:]

print('\n== non-LOO (reference NAM is among the candidates): n, top1, top3, MRR, worst ranks')
for gate in ('A1', 'A2x'):
    for refmode in ('di', 'blind'):
        for method in ('D1', 'D2', 'D3'):
            rows = []
            for role in ('rhythm', 'lead', 'clean', None):
                s = summary(lambda c: c['gate'] == gate and c['refMode'] == refmode and c['method'] == method and (role is None or c['role'] == role))
                rows.append('%s:%d t1=%.2f t3=%.2f mrr=%.2f' % ((role or 'ALL')[:4], s[0], s[1], s[2], s[3]))
            print(gate, refmode, method, ' | '.join(rows))

print('\n== LOO: category plausibility (labelled refs only). wrong = clean ref with highgain in top3 or highgain ref with clean in top3')
for gate in ('A1', 'A2x'):
    for refmode in ('blind',):
        for method in ('D1', 'D2', 'D3'):
            xs = [c for c in cases if c['loo'] and c['gate'] == gate and c['refMode'] == refmode and c['method'] == method and c['refCat']]
            same1 = sum(c['top3'][0]['cat'] == c['refCat'] for c in xs if c['top3'][0]['cat'])
            lab1 = sum(1 for c in xs if c['top3'][0]['cat'])
            wrong = sum(1 for c in xs if (c['refCat'] == 'clean' and any(t['cat'] == 'highgain' for t in c['top3'])) or (c['refCat'] == 'highgain' and any(t['cat'] == 'clean' for t in c['top3'])))
            print(gate, refmode, method, 'labelled refs=%d  top1 same category=%d/%d  obviously wrong top3=%d' % (len(xs), same1, lab1, wrong))

if len(sys.argv) > 1:
    gate, refmode, method, role = sys.argv[1:5]
    print('\n== detail', sys.argv[1:5])
    for c in cases:
        if c['gate'] == gate and c['refMode'] == refmode and c['method'] == method and c['role'] == role:
            print(('LOO ' if c['loo'] else 'ALL '), c['ref'], c['refCat'] or '-', 'rank', c['rank'], 'top3', [(t['id'], round(t['d'], 3)) for t in c['top3']])
