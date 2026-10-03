"""Writes final_gate_preregistration.json + .sha256 BEFORE any final-gate rendering or evaluation.

Everything here is derived from the already frozen IDMT selection (idmt_selection.json) and the already
documented 14 NAMs. Nothing is chosen with a result in view. After this file is written it must not change;
the experiment test verifies its SHA-256 before it does anything else.
"""
import hashlib, json, itertools

D = 'tool/tonematch_reference_match/'
sel = json.load(open(D + 'idmt_selection.json'))
ten = json.load(open('tool/tonematch_gate/ten_nam_set.json'))
DESK = 'D:/Desktop 3d sachen/Desktop/'
EXTRA = {
    'MkV-Clean': (DESK + 'AMP Presets/Boogie Mark V - Rhythm, Lead and Clean/Clean.nam', 'clean'),
    'MkV-Rhythm': (DESK + 'AMP Presets/Boogie Mark V - Rhythm, Lead and Clean/Rythm.nam', ''),
    'MkV-Lead': (DESK + 'AMP Presets/Boogie Mark V - Rhythm, Lead and Clean/Lead.nam', ''),
    'FenderSR': (DESK + 'Fender Super Reverb 1977/Fender Super Reverb_ EQ Flat, Volume 3, sm57.nam', 'clean'),
}
CAT = {'01': 'clean', '02': 'crunch', '03': 'crunch', '04': 'highgain', '05': 'highgain', '06': 'highgain', '07': 'highgain', '08': 'highgain', '09': 'highgain', '10': ''}
nams = {n['id']: {'file': n['path'].replace('\\', '/').split('/')[-1], 'sha256': n['sha'], 'category': CAT[n['id']]} for n in ten}
for k, (p, c) in EXTRA.items():
    nams[k] = {'file': p.split('/')[-1], 'sha256': hashlib.sha256(open(p, 'rb').read()).hexdigest(), 'category': c}
assert len(nams) == 14

clips = {c['id']: c for c in sel['clips']}
# content groups: objective, from dataset file-name codes / dataset membership only (no listening, no results)
GROUPS = {
    'SINGLE_NOTE_PICKED': [c for c in clips if clips[c]['group'] in ('single', 'picked')],
    'MUTED': [c for c in clips if clips[c]['group'] == 'muted'],
    'LEAD': [c for c in clips if clips[c]['group'] == 'lead'],
    'POLYPHONIC': [c for c in clips if clips[c]['group'] == 'poly'],
}
EXCLUDED = {c: why for c, why in [(c, 'finger-style: only one lick on three guitars, not enough independent clips for a hard group') for c in clips if clips[c]['group'] == 'finger'] +
            [(c, 'monophonic dataset-3 piece: a single clip, no same-group partner') for c in clips if clips[c]['group'] == 'mono']}

def material(c):
    s = clips[c]
    if s['group'] == 'poly':
        return 'd3' if c.startswith('D3_') else s['technique'].split(',')[1].strip()  # genre slot of dataset 4
    return c.split('_', 1)[1]  # lick id / fret sweep, identical across the three guitars

pairs = []
for g, ids in GROUPS.items():
    for a, b in itertools.permutations(ids, 2):
        pairs.append({'group': g, 'ref': a, 'cand': b,
                      'guitar': 'SAME_GUITAR' if clips[a]['guitar'] == clips[b]['guitar'] else 'CROSS_GUITAR',
                      'material': 'SAME_MATERIAL' if material(a) == material(b) else 'DIFFERENT_MATERIAL'})
assert all(p['ref'] != p['cand'] for p in pairs)

prereg = {
    'name': 'Hoer-Match IDMT final controlled gate (pre-registration)',
    'status': 'frozen before any final-gate rendering or evaluation; ToneTwist sealed and not used',
    'dataset': {'name': 'IDMT-SMT-GUITAR', 'version': sel['version'], 'url': sel['url'], 'doi': sel['doi'], 'license': sel['license'], 'zipMd5': sel['zipMd5'],
                'onlyAlreadyFrozenClipsOf': 'tool/tonematch_reference_match/idmt_selection.json'},
    'clips': {c: {'sha256': clips[c]['sha256'], 'group': clips[c]['group'], 'guitar': clips[c]['guitar']} for g in GROUPS.values() for c in g},
    'excludedClips': EXCLUDED,
    'exclusionRules': 'only clips whose content group is not suitable (see excludedClips); no result-based exclusion; a NAM that cannot be loaded makes the gate BLOCKED, it is never dropped',
    'contentGroups': GROUPS,
    'pairRule': 'all ordered pairs (reference clip, candidate clip) of different WAV files inside one content group; tags SAME/CROSS_GUITAR from the dataset guitar names and SAME/DIFFERENT_MATERIAL from the lick id / fret sweep / genre slot (descriptive only, never a gate)',
    'pairs': pairs,
    'nams': nams,
    'inputLevel': {
        'targetActiveRmsDbfs': -30.0,
        'method': 'linear gain only, applied to the dry 48 kHz DI (after the production 44.1->48 kHz resampler) BEFORE NAM inference; no limiter, no compression, no EQ; the output tone normalisation of the extractor stays unchanged',
        'activeRms': 'exactly the production definition (StftFeatureExtractor): frames ToneAnalysisParams.frameSize / hopSize, a frame is active if its mean square is within ToneAnalysisParams.activeGateDbBelowInputPeak dB of the loudest input frame; active RMS = 10*log10(mean over active frames of the frame mean squares)',
        'primaryTargetIndependentOfControl': True,
    },
    'levelSensitivityControl': {
        'levelsDbfs': [-33.0, -30.0, -27.0], 'nams': ['01', '03', '06'], 'clips': ['LP_Lick2_MN', 'FS_Lick5_KN', 'AR_Lick4_KBSH', 'D4_Ibanez_slow_pop_pop_1_130BPM'],
        'purpose': 'document only how much the four features change with +/-3 dB input; NOT used to choose a level',
    },
    'features': ['ln(spectral centroid)', 'ln(rolloff85)', 'logit(MID + HIGH_MID share)', 'crest dB'],
    'excludedFeatures': ['attackMs', 'decayDbPerSec', 'transientPeakToBody', 'saturation composite', 'HF generation'],
    'distance': {'primary': 'D2', 'secondary': ['D1', 'D3'], 'definitions': 'tool/tonematch_reference_match/spike.dart, unchanged (z over the candidate set of the case; D2 = (sqrt((db^2+dm^2)/2) + |dc|)/2)'},
    'mode': {'primary': 'blind (reference gate from the reference output itself, no original DI)', 'control': 'DI-gated reference, never used for pass/fail'},
    'rankingRules': 'candidates are the 14 NAMs analysed on the candidate clip the production way (DI-gated); ranked nearest first, ties by NAM id; reference NAM rank = 1-based position; leave-one-out cases remove the reference NAM from the candidates',
    'obviouslyWrong': 'unchanged definition: on leave-one-out cases of labelled reference NAMs (clean/crunch/highgain): a clean reference with a highgain NAM in the top 3, or a highgain reference with a clean NAM in the top 3; crunch references are labelled but cannot be wrong; rate = wrong / labelled leave-one-out cases',
    'baseline': {'name': 'IDMT single performance D2 blind', 'top1': 0.386, 'top3': 0.696, 'mrr': 0.573, 'medianRank': 2, 'obviouslyWrong': 0.174},
    'successCriteria': {
        'primary': 'D2 BLIND, all pairs, ALL must hold, no near-pass',
        'top3': '>= 0.70', 'mrr': '>= 0.60', 'obviouslyWrong': '<= 0.10', 'medianRank': '<= 2',
        'contentGroupRule': 'every content group with >= 100 ranking cases must reach Top-3 >= 0.50; groups with fewer cases are descriptive only',
        'notGates': ['D1', 'D3', 'DI-gated control', 'SAME/CROSS_GUITAR split', 'SAME/DIFFERENT_MATERIAL split', 'per-NAM and per-category numbers'],
    },
    'afterTheRun': 'STOP: no tuning, no other levels, no other pairs, no new features; PASS -> frozen method may be run once on the sealed ToneTwist holdout; FAIL -> exact-NAM research branch frozen, ToneTwist stays sealed',
}
raw = json.dumps(prereg, indent=1, sort_keys=True).encode('utf-8')
open(D + 'final_gate_preregistration.json', 'wb').write(raw)
sha = hashlib.sha256(raw).hexdigest()
open(D + 'final_gate_preregistration.sha256', 'w').write(sha + '\n')
import collections
print('SHA256', sha)
print({g: len(v) for g, v in GROUPS.items()}, 'pairs', len(pairs), collections.Counter(p['group'] for p in pairs), collections.Counter(p['guitar'] for p in pairs), collections.Counter(p['material'] for p in pairs))
print('excluded', list(EXCLUDED))
