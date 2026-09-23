"""Builds the ToneVault mass catalog packs (deterministic, no randomness).

    python tool/tonevault_catalog/build.py

Adds packs next to the 8 seed packs (which stay untouched), extends taxonomy.json (new genres, era "modern"),
and rewrites manifest.json (fixed pack order). Rows whose id or artist name already exists in the seed are skipped.
"""
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))

import common
from common import C, OUT
import templates
import artists_metal
import artists_rock
import artists_other
import songs_eras
import electronic


def norm(s):
    return re.sub(r'[^a-z0-9]+', ' ', s.lower().replace('ö', 'o').replace('ü', 'u').replace('ä', 'a').replace('ý', 'y')
                  .replace('ÿ', 'y').replace('ï', 'i').replace('é', 'e').replace('ó', 'o').replace('ë', 'e')).strip()


def load_json(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def write_json(path, obj):
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(obj, f, ensure_ascii=False, indent=1)
        f.write('\n')


# ------------------------------------------------------------------ taxonomy
NEW_GENRES = [
    # id, name, parent, aliases
    ('nwobhm', 'NWOBHM', 'metal', ['new wave of british heavy metal']),
    ('technical_death_metal', 'Technical Death Metal', 'metal', ['tech death', 'technical death']),
    ('symphonic_metal', 'Symphonic Metal', 'metal', ['symphonic']),
    ('sludge_metal', 'Sludge Metal', 'metal', ['sludge']),
    ('melodic_metalcore', 'Melodic Metalcore', 'metal', ['melodic metalcore']),
    ('folk_metal', 'Folk Metal', 'metal', ['folk']),
    ('viking_metal', 'Viking Metal', 'metal', ['viking']),
    ('gothic_metal', 'Gothic Metal', 'metal', ['gothic', 'goth metal']),
    ('post_grunge', 'Post-Grunge', 'rock', ['post grunge']),
    ('post_punk', 'Post-Punk', 'rock', ['post punk']),
    ('emo', 'Emo', 'rock', ['emo rock']),
    ('post_hardcore', 'Post-Hardcore', 'rock', ['post hardcore']),
    ('texas_blues', 'Texas Blues', 'blues', ['texas blues']),
    ('chicago_blues', 'Chicago Blues', 'blues', ['chicago blues']),
    ('rockabilly', 'Rockabilly', 'other_guitar', ['rockabilly']),
    ('clean_pop', 'Clean Pop Guitar', 'other_guitar', ['clean pop', 'pop clean']),
    ('instrumental_rock', 'Instrumental Rock / Shred', 'other_guitar', ['shred', 'instrumental', 'guitar hero']),
    ('eurodance_inspired', 'Eurodance-inspired', 'electronic_guitar', ['eurodance']),
    ('house_inspired', 'House-inspired', 'electronic_guitar', ['house', 'french house']),
    ('chiptune_inspired', 'Chiptune-inspired', 'electronic_guitar', ['chiptune', '8 bit', '8-bit']),
    ('cinematic', 'Cinematic', 'electronic_guitar', ['film score', 'cinematic guitar']),
]
EXTRA_ALIASES = {'fusion': ['jazz fusion'], 'ambient': ['ambient guitar'], 'lo_fi': ['lo-fi guitar', 'lofi guitar'],
                 'blues': ['electric blues'], 'alternative_rock': ['alternative', 'alt rock']}
# the bare word "modern" stays an adjective ("modern metal"); the era is reached through explicit phrases
MODERN_ERA = {'id': 'modern', 'name': 'Moderne Ära', 'fromYear': 2015, 'toYear': 2100,
              'aliases': ['modern era', 'modern day', 'contemporary', 'heute', 'aktuell']}


def extend_taxonomy():
    path = os.path.join(OUT, 'taxonomy.json')
    t = load_json(path)
    have = {g['id'] for g in t['genres']}
    for gid, name, parent, aliases in NEW_GENRES:
        if gid not in have:
            t['genres'].append({'id': gid, 'name': name, 'parent': parent, 'aliases': aliases})
    for g in t['genres']:
        for a in EXTRA_ALIASES.get(g['id'], []):
            if a not in g['aliases']:
                g['aliases'].append(a)
    t['eras'] = [e for e in t['eras'] if e['id'] != 'modern'] + [MODERN_ERA]
    write_json(path, t)
    return t


# ------------------------------------------------------------------ main
def prune_redundant(seed_by_id, catalog):
    """Drops generated overrides that only repeat what the parent chain already gives (data hygiene)."""
    by_id = dict(seed_by_id)
    for es in catalog.entries.values():
        for e in es:
            by_id[e['id']] = e
    cache = {}

    def ancestors(x, out, seen):
        e = by_id[x]
        assert x not in seen, 'cycle ' + x
        seen.add(x)
        for p in e.get('parents', []):
            ancestors(p, out, seen)
        seen.discard(x)
        if x not in out:
            out.append(x)

    def resolved(x):
        if x in cache:
            return cache[x]
        chain = []
        ancestors(x, chain, set())
        dims, char = {}, {}
        for cid in chain:
            t = by_id[cid].get('tone', {})
            for k, v in t.get('dimensions', {}).items():
                if v not in ('inherit',):
                    dims[k] = 0 if v == 'off' else v
            for k, v in t.get('character', {}).items():
                if v != 'inherit':
                    char[k] = v
        cache[x] = (dims, char)
        return cache[x]

    removed = 0
    for es in catalog.entries.values():
        for e in es:
            if not e.get('parents') or 'tone' not in e:
                continue
            dims, char = {}, {}
            chain = []
            for p in e['parents']:
                ancestors(p, chain, set())
            for cid in chain:
                t = by_id[cid].get('tone', {})
                for k, v in t.get('dimensions', {}).items():
                    if v != 'inherit':
                        dims[k] = 0 if v == 'off' else v
                for k, v in t.get('character', {}).items():
                    if v != 'inherit':
                        char[k] = v
            t = e['tone']
            for k in list(t.get('dimensions', {})):
                v = t['dimensions'][k]
                if v != 'off' and dims.get(k) == v:
                    del t['dimensions'][k]
                    removed += 1
                elif v == 'off' and dims.get(k) == 0:
                    del t['dimensions'][k]
                    removed += 1
            for k in list(t.get('character', {})):
                if char.get(k) == t['character'][k]:
                    del t['character'][k]
                    removed += 1
            for key in ('dimensions', 'character'):
                if key in t and not t[key]:
                    del t[key]
            if not t:
                del e['tone']
    print('pruned redundant overrides:', removed)


def existing_state():
    ids, names = set(), {}
    seed_manifest = ['packs/core_genres.json', 'packs/metal_essentials.json', 'packs/modern_metal.json', 'packs/extreme_metal.json',
                     'packs/rock_essentials.json', 'packs/alternative_grunge.json', 'packs/punk_pop_punk.json',
                     'packs/electronic_reimagined.json']
    for rel in seed_manifest:
        pack = load_json(os.path.join(OUT, rel))
        for e in pack['entries']:
            ids.add(e['id'])
            if e['type'] == 'ARTIST_SIGNATURE':
                names[e['id'].split('.', 1)[1]] = e['artist']
    return seed_manifest, ids, names


def main():
    extend_taxonomy()
    seed_manifest, seed_ids, seed_names = existing_state()
    seed_entries_by_id = {}
    for rel in seed_manifest:
        for e in load_json(os.path.join(OUT, rel))['entries']:
            seed_entries_by_id[e['id']] = e
    seed_artist_norms = {norm(n) for n in seed_names.values()}

    # skip rows that the seed already covers (same id or same artist name)
    original_add = C.add
    skipped = []

    def add(e):
        if e['id'] in seed_ids or (e['type'] == 'ARTIST_SIGNATURE' and norm(e['artist']) in seed_artist_norms):
            skipped.append(e['id'])
            return None
        return original_add(e)

    C.add = add

    templates.build()
    artists_metal.build()
    artists_rock.build()
    artists_other.build()

    names = dict(seed_names)
    for pid, es in C.entries.items():
        for e in es:
            if e['type'] == 'ARTIST_SIGNATURE':
                names[e['id'].split('.', 1)[1]] = e['artist']
    songs_eras.NAMES.update(names)

    C.pack('artist_eras', 'Artist-Ären und Alben', 'Era- und Album-Signaturen: Klangphasen bekannter Acts (Suche und Unterscheidung).',
           'STYLE_INSPIRED')
    songs_eras.build_eras()
    songs_eras.build_albums()
    C.pack('song_layer', 'Ausgewählte Songs', 'Kuratierte, bekannte Songs; minimale Einträge, die vom Artist/Album/Era erben.',
           'STYLE_INSPIRED')
    songs_eras.build_songs()
    electronic.build()

    prune_redundant(seed_entries_by_id, C)

    # every parent must exist
    all_ids = set(seed_ids) | C.ids
    for pid, es in C.entries.items():
        for e in es:
            for p in e.get('parents', []):
                assert p in all_ids, '%s: missing parent %s' % (e['id'], p)

    manifest_path = os.path.join(OUT, 'manifest.json')
    manifest = load_json(manifest_path)
    packs = C.write(os.path.join(OUT, 'packs'), list(seed_manifest))
    # fixed order: seed packs, then templates, then everything else in build order
    manifest['packs'] = packs
    write_json(manifest_path, manifest)
    total = sum(len(v) for v in C.entries.values())
    print('packs', len([p for p in C.entries.values() if p]), 'new entries', total, 'skipped', len(skipped), skipped[:10])


if __name__ == '__main__':
    main()
