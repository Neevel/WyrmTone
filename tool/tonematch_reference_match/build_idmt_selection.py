"""Freezes the IDMT-SMT-Guitar selection (clips, pairs, signature clip sets) BEFORE any result is looked at.

usage: python build_idmt_selection.py <path to IDMT-SMT-GUITAR_V2.zip>

Rules (deterministic, no result-based choices):
 clips (electric, dry DI only; dataset 1 is skipped because its files are 1-3 s single events, acoustic parts of dataset 4 are skipped):
  dataset2, per guitar LP (Gibson Les Paul), FS (Fender Stratocaster), AR (Aristides 010):
    muted   Lick2_MN, Lick8_MN      picked  Lick5_KN, Lick11_KN     finger  Lick2_FN
    lead    Lick4_KBSH, Lick5_KBVDN single  E_fret_0-20
  dataset4, per electric guitar (Career SG, Ibanez RG2820): first file (sorted) of slow/metal, fast/rock_blues, slow/pop
  dataset3 (Ibanez RG2820): pathetique_poly (polyphonic), quintfall (monophonic)
 pairs A same group / different performance, B cross technique, C cross guitar (see PAIRS below).
 signatures: for every reference clip r, pool = frozen clip order without clips of the same guitar as r;
   signature clips for N = [pool[int((k + 0.5) * len(pool) / N)] for k in range(N)], N in (3, 5, 10).
"""
import hashlib, json, re, sys, wave, zipfile, itertools

ZIP = sys.argv[1]
OUT = 'tool/tonematch_reference_match/'
DATA = OUT + 'data/idmt/'
R = 'IDMT-SMT-GUITAR_V2/'
G = {'LP': 'Gibson Les Paul', 'FS': 'Fender Stratocaster', 'AR': 'Aristides 010'}

z = zipfile.ZipFile(ZIP)
names = set(i.filename for i in z.infolist())
clips = []

def add(cid, group, guitar, technique, path, slot=None):
    assert R + path in names, path
    clips.append({'id': cid, 'group': group, 'guitar': guitar, 'technique': technique, 'zip': R + path, 'slot': slot})

for g in ('LP', 'FS', 'AR'):
    for lick in (2, 8):
        add(f'{g}_Lick{lick}_MN', 'muted', G[g], 'muted, normal', f'dataset2/audio/{g}_Lick{lick}_MN.wav', lick)
    for lick in (5, 11):
        add(f'{g}_Lick{lick}_KN', 'picked', G[g], 'picked, normal', f'dataset2/audio/{g}_Lick{lick}_KN.wav', lick)
    add(f'{g}_Lick2_FN', 'finger', G[g], 'finger-style, normal', f'dataset2/audio/{g}_Lick2_FN.wav', 2)
    add(f'{g}_Lick4_KBSH', 'lead', G[g], 'picked, bending/slide/harmonics', f'dataset2/audio/{g}_Lick4_KBSH.wav', 4)
    add(f'{g}_Lick5_KBVDN', 'lead', G[g], 'picked, bending/vibrato/dead notes', f'dataset2/audio/{g}_Lick5_KBVDN.wav', 5)
    add(f'{g}_E_fret_0-20', 'single', G[g], 'single notes (plain), E string frets 0-20', f'dataset2/audio/{g}_E_fret_0-20.wav')
SLOTS = (('slow', 'metal'), ('fast', 'rock_blues'), ('slow', 'pop'))
for gid, gname, short in (('Career SG', 'Career SG', 'Career'), ('Ibanez 2820', 'Ibanez RG2820', 'Ibanez')):
    for tempo, genre in SLOTS:
        cand = sorted(n for n in names if n.startswith(R + f'dataset4/{gid}/{tempo}/{genre}/audio/') and n.endswith('.wav'))
        add(f'D4_{short}_{tempo}_{genre}_' + cand[0].split('/')[-1][:-4], 'poly', gname, f'polyphonic piece, {genre} {tempo}', cand[0][len(R):], f'{tempo}/{genre}')
add('D3_pathetique_poly', 'poly', 'Ibanez RG2820', 'polyphonic piece (dataset 3)', 'dataset3/audio/pathetique_poly.wav', 'd3')
add('D3_quintfall', 'mono', 'Ibanez RG2820', 'monophonic piece (dataset 3)', 'dataset3/audio/quintfall.wav', 'd3')

for c in clips:
    b = z.read(c['zip'])
    open(DATA + c['id'] + '.wav', 'wb').write(b)
    c['sha256'] = hashlib.sha256(b).hexdigest()
    c['bytes'] = len(b)
    w = wave.open(DATA + c['id'] + '.wav')
    c['rate'], c['channels'], c['bits'], c['seconds'] = w.getframerate(), w.getnchannels(), w.getsampwidth() * 8, round(w.getnframes() / w.getframerate(), 2)
    ann = c['zip'].replace('/audio/', '/annotation/')[:-4] + '.xml'
    if ann in names:
        x = z.read(ann).decode('utf-8', 'ignore')
        for tag in ('instrumentModel', 'pickUpSetting', 'audioFX', 'recordingArtist'):
            m = re.search(f'<{tag}>(.*?)</{tag}>', x)
            if m:
                c[tag] = m.group(1).strip()
ids = [c['id'] for c in clips]
guitar = {c['id']: c['guitar'] for c in clips}
by_id = {c['id']: c for c in clips}

pairs = []
def P(cond, group, a, b):
    pairs.append({'cond': cond, 'group': group, 'ref': a, 'cand': b})

# A: same group, different performance (same guitar, different lick/piece)
for g in ('LP', 'FS', 'AR'):
    for grp, (x, y) in {'muted': (f'{g}_Lick2_MN', f'{g}_Lick8_MN'), 'picked': (f'{g}_Lick5_KN', f'{g}_Lick11_KN'), 'lead': (f'{g}_Lick4_KBSH', f'{g}_Lick5_KBVDN')}.items():
        P('A', grp, x, y); P('A', grp, y, x)
for short in ('Career', 'Ibanez'):
    d4 = [c['id'] for c in clips if c['id'].startswith(f'D4_{short}_')]
    for a, b in itertools.permutations(d4, 2):
        P('A', 'poly', a, b)
# B: cross technique, same guitar
for g in ('LP', 'FS', 'AR'):
    for c in (f'{g}_Lick2_MN', f'{g}_Lick5_KN', f'{g}_Lick4_KBSH'):
        P('B', 'single->' + by_id[c]['group'], f'{g}_E_fret_0-20', c)
    P('B', 'finger->picked', f'{g}_Lick2_FN', f'{g}_Lick5_KN')
    P('B', 'muted->picked', f'{g}_Lick2_MN', f'{g}_Lick11_KN')
for c in ids:
    if c.startswith('D4_Ibanez_'):
        P('B', 'mono->poly', 'D3_quintfall', c)
P('B', 'mono->poly', 'D3_quintfall', 'D3_pathetique_poly')
# C: cross guitar, same technique/lick (re-performed on another guitar) and same dataset-4 slot
for stem, grp in (('Lick2_MN', 'muted'), ('Lick5_KN', 'picked'), ('Lick4_KBSH', 'lead')):
    for ga, gb in itertools.permutations(('LP', 'FS', 'AR'), 2):
        P('C', grp, f'{ga}_{stem}', f'{gb}_{stem}')
for tempo, genre in SLOTS:
    a = next(c['id'] for c in clips if c['id'].startswith(f'D4_Career_{tempo}_{genre}_'))
    b = next(c['id'] for c in clips if c['id'].startswith(f'D4_Ibanez_{tempo}_{genre}_'))
    P('C', 'poly', a, b); P('C', 'poly', b, a)

for p in pairs:
    assert p['ref'] != p['cand']

signatures = {}
for r in sorted({p['ref'] for p in pairs}):
    pool = [c for c in ids if guitar[c] != guitar[r]]
    signatures[r] = {str(n): [pool[int((k + 0.5) * len(pool) / n)] for k in range(n)] for n in (3, 5, 10)}
    assert all(r not in v for v in signatures[r].values())

out = {
    'dataset': 'IDMT-SMT-GUITAR V2', 'url': 'https://zenodo.org/records/7544110', 'doi': '10.5281/zenodo.7544110', 'version': '1.0.0 (file IDMT-SMT-GUITAR_V2.zip, dataset description v2.0 2016-01-20)',
    'license': 'CC BY-NC-ND 4.0', 'acquired': '2026-10-03', 'zipMd5': hashlib.md5(open(ZIP, 'rb').read()).hexdigest(), 'zipExpectedMd5': '06796e08731bccffaed6ae59361486e4',
    'filesAvailable': {'wav': sum(1 for n in names if n.endswith('.wav'))}, 'exclusions': [], 'rule': __doc__.split('Rules')[1],
    'clips': clips, 'pairs': pairs, 'signatures': signatures,
}
json.dump(out, open(OUT + 'idmt_selection.json', 'w'), indent=1)
import collections
print(len(clips), 'clips;', len(pairs), 'pairs', collections.Counter(p['cond'] for p in pairs), 'ref clips', len(signatures), 'md5 ok', out['zipMd5'] == out['zipExpectedMd5'])
for c in clips:
    print(c['id'], c['group'], c['bits'], c['channels'], c['rate'], c['seconds'], c.get('instrumentModel'), c.get('pickUpSetting'), c.get('audioFX'))
