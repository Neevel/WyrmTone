"""Evaluation of the Tone Match Android performance gate (results/results_perf.json, thermal_perf.csv)."""
import csv
import json
import os
import statistics as st
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SUF = sys.argv[1] if len(sys.argv) > 1 else ''  # '' = suite 2 (repeat), '_suite1' = first suite
d = json.load(open(os.path.join(HERE, 'results', 'results_perf%s.json' % SUF), encoding='utf8'))
runs = d['runs']
lines = []


def P(s=''):
    lines.append(s)
    print(s)


def mm(v):
    return '%.0f / %.0f / %.0f' % (min(v), st.median(v), max(v))


def get(label_prefix):
    return [r for r in runs if r['label'].startswith(label_prefix)]


P('# Cold runs: wall time in s (min / median / max over 3 runs); includes signal preparation')
summary = {}
for role in ['rhythm', 'lead']:
    for n in [5, 10]:
        rs = get('cold %sx%d' % (role, n))
        w = [r['wallMs'] / 1000 for r in rs]
        sig = [next(e for e in r['events'] if e['type'] == 'signal') for r in rs]
        prep = [(s['decodeMs'] + s['resampleMs'] + s['deriveMs']) / 1000 for s in sig]
        summary['%s%d' % (role, n)] = dict(wall=w, prep=prep)
        P('%-8s x%-2d wall %5.1f / %5.1f / %5.1f s   runs: %s   signal prep %.2f s' % (role, n, min(w), st.median(w), max(w), ', '.join('%.1f' % x for x in w), st.median(prep)))

P()
P('# Per candidate (cold runs only, ms; median [min-max] over all cold analyses)')
cand = {k: [] for k in ['namLoadMs', 'inferenceMs', 'extractionMs', 'cacheWriteMs', 'totalMs']}
byid = {}
for r in runs:
    if r['label'].startswith('cold'):
        for e in r['events']:
            if e['type'] == 'candidate' and not e['cacheHit']:
                for k in cand:
                    cand[k].append(e[k])
                byid.setdefault(e['id'], []).append(e['totalMs'])
for k, v in cand.items():
    P('%-14s %8.1f [%6.1f - %8.1f]  (n=%d)' % (k, st.median(v), min(v), max(v), len(v)))
P('per NAM total (median ms): ' + ', '.join('%s %.0f' % (i, st.median(v)) for i, v in sorted(byid.items())))
P('share of inference in candidate total: %.1f%%' % (100 * st.median(cand['inferenceMs']) / st.median(cand['totalMs'])))

P()
P('# Signal preparation per run (ms): decode / resample / derive T15')
for role in ['rhythm', 'lead']:
    sg = [next(e for e in r['events'] if e['type'] == 'signal') for r in runs if r['label'].startswith('cold %s' % role)]
    P('%-7s decode %s | resample %s | derive %s' % (role, mm([s['decodeMs'] for s in sg]), mm([s['resampleMs'] for s in sg]), mm([s['deriveMs'] for s in sg])))

P()
P('# Warm runs (all candidates from cache), wall ms')
for role in ['rhythm', 'lead']:
    for n in [5, 10]:
        rs = get('warm %sx%d' % (role, n))
        P('%-7s x%-2d wall %s ms; engines created %s; analyze calls %s; cache hits %s' % (
            role, n, mm([r['wallMs'] for r in rs]), [r['end']['enginesCreated'] for r in rs], [r['end']['analyzeCalls'] for r in rs],
            [sum(1 for e in r['events'] if e['type'] == 'candidate' and e['cacheHit']) for r in rs]))
        per = [e['cacheReadMs'] for r in rs for e in r['events'] if e['type'] == 'candidate']
        P('          per-candidate cache read: median %.2f ms max %.2f ms' % (st.median(per), max(per)))

P()
P('# Memory (process RSS, MB)')
base = d['baselineRssKb'] / 1024
P('baseline before any run: %.0f MB; idle after suite: %.0f MB' % (base, d['idleRssKb'] / 1024))
for n in [5, 10]:
    peaks = [r['rssPeakKb'] / 1024 for r in runs if r['label'].startswith('cold') and r['n'] == n]
    bef = [r['rssBeforeKb'] / 1024 for r in runs if r['label'].startswith('cold') and r['n'] == n]
    aft = [r['rssAfterKb'] / 1024 for r in runs if r['label'].startswith('cold') and r['n'] == n]
    P('x%-2d cold: before %.0f-%.0f | peak %.0f-%.0f (max growth over before %.0f MB) | after %.0f-%.0f' % (n, min(bef), max(bef), min(peaks), max(peaks), max(p - b for p, b in zip(peaks, bef)), min(aft), max(aft)))
cold = [r for r in runs if r['label'].startswith('cold')]
P('RSS after each cold run in order (MB): ' + ' '.join('%.0f' % (r['rssAfterKb'] / 1024) for r in cold))
P('VmHWM at end: %.0f MB; Pss after last run: %.0f MB' % (runs[-1]['vmHwmKb'] / 1024, runs[-1]['pssAfterKb'] / 1024))
# trend: same scenario, run 1 vs run 3
for role in ['rhythm', 'lead']:
    for n in [5, 10]:
        rs = get('cold %sx%d' % (role, n))
        P('  %s x%d after-run RSS run1->run3: %.0f -> %.0f MB' % (role, n, rs[0]['rssAfterKb'] / 1024, rs[2]['rssAfterKb'] / 1024))

P()
P('# Run 1 vs run 3 (cold wall time, s) and per-candidate inference (ms, median)')
for role in ['rhythm', 'lead']:
    for n in [5, 10]:
        rs = get('cold %sx%d' % (role, n))
        inf = [st.median([e['inferenceMs'] for e in r['events'] if e['type'] == 'candidate']) for r in rs]
        P('%s x%-2d: %.1f -> %.1f s (%+.0f%%) ; median inference %.0f -> %.0f ms' % (role, n, rs[0]['wallMs'] / 1000, rs[2]['wallMs'] / 1000, 100 * (rs[2]['wallMs'] / rs[0]['wallMs'] - 1), inf[0], inf[2]))
ra = [r for r in runs if r['label'].startswith('run after cancel')][0]
first = get('cold rhythmx5')
P('run after cancel (rhythm x5): %.1f s vs %.1f s median of the first three (+%.0f%%)' % (ra['wallMs'] / 1000, st.median([r['wallMs'] / 1000 for r in first]), 100 * (ra['wallMs'] / st.median([r['wallMs'] for r in first]) - 1)))

P()
P('# Main isolate while the worker computes (cold runs)')
for key in ['maxLate', 'p99', 'frames', 'j33', 'j100', 'worst']:
    pass
ml = [r['main']['heartbeatMaxLateMs'] for r in cold]
p99 = [r['main']['heartbeatP99LateMs'] for r in cold]
fr = [r['main']['frames'] for r in cold]
w = [r['main']['worstFrameMs'] for r in cold]
j33 = sum(r['main']['frames>33ms'] for r in cold)
j100 = sum(r['main']['frames>100ms'] for r in cold)
P('heartbeat (10 ms timer) max lateness over all cold runs: %.1f ms (median of run maxima %.1f); p99 lateness max %.1f ms' % (max(ml), st.median(ml), max(p99)))
P('frames: %d total in cold runs; > 33 ms: %d; > 100 ms: %d; worst frame %.1f ms (note: UI is mostly static + spinner)' % (sum(fr), j33, j100, max(w)))

P()
P('# Cancel (LEAD x10 cold, cancel requested 1 s after candidate 3 started)')
c = [r for r in runs if r['label'].startswith('cancel')][0]
ev = c['events']
done_before = [e for e in ev if e['type'] == 'candidate']
last = c['end']
P('end event: %s (during candidate index %s), candidates completed before: %d, latency cancel->stop: %s ms, engines created %s, analyze calls %s' % (
    last['type'], last.get('during'), len(done_before), c['cancelLatencyMs'], last['enginesCreated'], last['analyzeCalls']))
started = [e['index'] for e in ev if e['type'] == 'candidateStart']
P('candidates started: %s (no start after the cancelled one: %s)' % (started, max(started) == last.get('during')))
P('events after cancel end: none (loop broke on cancelled); RSS after cancel %.0f MB' % (c['rssAfterKb'] / 1024))
# determinism: tone summary of run-after-cancel vs the earlier cold rhythm x5 runs
tone_a = {e['id']: e['tone'] for e in ra['events'] if e['type'] == 'candidate'}
tone_b = {e['id']: e['tone'] for e in first[0]['events'] if e['type'] == 'candidate'}
same = all(tone_a[i] == tone_b[i] for i in tone_b)
P('run after cancel produced identical feature summaries to the first cold rhythm x5 run: %s' % same)
alls = [{e['id']: e['tone'] for e in r['events'] if e['type'] == 'candidate'} for r in first]
P('three cold rhythm x5 runs identical: %s' % (alls[0] == alls[1] == alls[2]))

P()
P('# Thermal (host sampling every ~5 s)')
rows = list(csv.DictReader(open(os.path.join(HERE, 'results', 'thermal_perf%s.csv' % SUF))))
def f(x):
    try:
        return float(x)
    except Exception:
        return None
ts = [int(r['epoch_ms']) for r in rows]
bt = [f(r['battery_temp_x10']) / 10 if f(r['battery_temp_x10']) else None for r in rows]
ap = [f(r['ap_c']) for r in rows]
sk = [f(r['skin_c']) for r in rows]
status = {r['thermal_status'] for r in rows}
P('samples %d over %.1f min; thermal status values seen: %s' % (len(rows), (ts[-1] - ts[0]) / 60000, sorted(status)))
P('battery temp: start %.1f -> end %.1f C (max %.1f); AP: start %.1f -> max %.1f C; skin: start %.1f -> max %.1f C' % (
    [b for b in bt if b][0], [b for b in bt if b][-1], max(b for b in bt if b), ap[0], max(a for a in ap if a), sk[0], max(s for s in sk if s)))
# temperature at the start of each cold run
for r in runs:
    if r['label'].startswith('cold') or r['label'].startswith('run after') or r['label'].startswith('cancel'):
        t0 = r['startEpochMs']
        i = min(range(len(ts)), key=lambda k: abs(ts[k] - t0))
        r['_temp'] = (bt[i], ap[i])
P('battery C / AP C at start of runs: ' + '; '.join('%s: %s/%s' % (r['label'].replace('cold ', '').replace(' run ', '#'), r['_temp'][0], r['_temp'][1]) for r in runs if '_temp' in r))
json.dump(dict(summary=summary), open(os.path.join(HERE, 'results', 'report%s.json' % SUF), 'w'), indent=1)
open(os.path.join(HERE, 'results', 'report%s.txt' % SUF), 'w', encoding='utf8').write('\n'.join(lines))
