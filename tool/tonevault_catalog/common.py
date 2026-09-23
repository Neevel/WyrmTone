"""Shared helpers of the ToneVault mass-catalog generator.

Rules (see docs/TONEVAULT.md): the generator is DETERMINISTIC. It contains only curated data
(hand-written parents, tags and overrides) and no random or hash-derived values. Entries only
override what was consciously curated; everything else is inherited from the parent chain.
"""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'assets', 'tonevault')

DIM = dict(g='gain', sa='saturation', ti='tightness', at='attack', su='sustain', ba='bass', lm='lowMids', mi='mids',
           um='upperMids', tr='treble', pr='presence', co='compression', gs='gateStrength', go='gateOpening',
           sp='space', de='delay', re='reverb', mo='modulation', ir='irBrightness')
CHAR = dict(body='body', warmth='warmth', dark='darkness', clarity='clarity', aggr='aggression', vintage='vintage',
            fuzz='fuzziness', lofi='loFi', width='width')

NOTE_STYLE = ('Stilorientierte WyrmTone-Beschreibung; keine Aussage über Originalequipment oder Studioeinstellungen. '
              'Der Name dient nur als Referenz- und Suchbegriff.')
NOTE_TEMPLATE = 'Von WyrmTone gebaute, stilistische Ausgangsbasis; keine Aussage über Originalequipment.'
NOTE_REIM = ('WyrmTone-Gitarreninterpretation: beschreibt, wie sich der Eindruck mit Gitarre und Multi-FX andeuten lässt; '
             'kein Nachbau des Originalklangs oder -synthesizers.')
NOTE_ORIGINAL = 'Eigene WyrmTone-Kreation; keine Referenz auf ein Original und keine Emulation eines echten Geräts.'


def val(v):
    v = v.strip()
    return 'off' if v == 'off' else int(v)


def over(spec):
    """'g=70,ti=86,de=off' -> {'gain': 70, 'tightness': 86, 'delay': 'off'}"""
    d = {}
    for part in [p for p in (spec or '').split(',') if p.strip()]:
        k, v = part.split('=')
        d[DIM[k.strip()]] = val(v)
    return d


def kinds(spec):
    """'drive:boost;reverb:room' -> {'drive': 'boost', 'reverb': 'room'}"""
    d = {}
    for part in [p for p in (spec or '').split(';') if p.strip()]:
        k, v = part.split(':')
        d[k.strip()] = v.strip()
    return d


def char(spec):
    d = {}
    for part in [p for p in (spec or '').split(',') if p.strip()]:
        k, v = part.split('=')
        d[CHAR[k.strip()]] = int(v)
    return d


def tone(dim_spec=None, kind_spec=None, char_spec=None, **extra):
    t = {}
    dd = {}
    cc = {}
    # one override string may mix perceptual dimensions (g, ti, ...) and character axes (aggr, clarity, ...)
    for part in [p for p in (dim_spec or '').split(',') if p.strip()] if isinstance(dim_spec, str) else []:
        k, v = part.split('=')
        k = k.strip()
        if k in CHAR:
            cc[CHAR[k]] = int(v)
        else:
            dd[DIM[k]] = val(v)
    if isinstance(dim_spec, dict):
        dd = dim_spec
    if dd:
        t['dimensions'] = dd
    cc = {**cc, **(char(char_spec) if isinstance(char_spec, str) else (char_spec or {}))}
    if cc:
        t['character'] = cc
    kk = kinds(kind_spec) if isinstance(kind_spec, str) else (kind_spec or {})
    if kk:
        t['kinds'] = kk
    t.update(extra)
    return t


def lst(s):
    return [x.strip() for x in (s or '').split(',') if x.strip()]


def variant(kind, dim_spec=None, kind_spec=None, char_spec=None, notes=None):
    v = {'kind': kind}
    t = tone(dim_spec, kind_spec, char_spec)
    if t:
        v['tone'] = t
    if notes:
        v['notes'] = notes
    return v


def entry(id, type, title, cls, conf, **kw):
    e = {'id': id, 'schemaVersion': 1, 'type': type, 'title': title, 'source': {'classification': cls},
         'confidence': conf}
    t = kw.pop('tone', None)
    variants = kw.pop('variants', None)
    e.update({k: v for k, v in kw.items() if v not in (None, [], {}, '')})
    if t:
        e['tone'] = t
    if variants:
        e['variants'] = variants
    return e


class Catalog:
    """Collects entries per pack. Insertion order is the (deterministic) output order."""

    def __init__(self):
        self.packs = {}      # id -> meta
        self.entries = {}    # pack id -> [entry]
        self.ids = set()
        self.current = None

    def pack(self, id, name, description, classification, note=None):
        self.packs[id] = dict(id=id, name=name, description=description, classification=classification, note=note)
        self.entries.setdefault(id, [])
        self.current = id

    def add(self, e):
        assert e['id'] not in self.ids, 'duplicate id ' + e['id']
        self.ids.add(e['id'])
        self.entries[self.current].append(e)
        return e

    def write(self, packs_dir, existing_manifest_packs):
        os.makedirs(packs_dir, exist_ok=True)
        names = []
        for pid, meta in self.packs.items():
            es = self.entries[pid]
            if not es:
                continue
            obj = {
                'pack': {
                    'id': pid, 'name': meta['name'], 'version': 1, 'schemaVersion': 1,
                    'description': meta['description'], 'entryCount': len(es),
                    'sourceClassification': meta['classification'],
                    'license': {'name': 'WyrmTone Katalog (eigene Beschreibungen)',
                                'note': meta['note'] or 'Nur Such-Metadaten (Namen) und eigene musikalische Beschreibungen. '
                                                        'Keine Tabs, Noten, Lyrics oder fremden Presets.'}},
                'entries': es,
            }
            with open(os.path.join(packs_dir, pid + '.json'), 'w', encoding='utf-8', newline='\n') as f:
                json.dump(obj, f, ensure_ascii=False, indent=1)
                f.write('\n')
            names.append('packs/%s.json' % pid)
        return existing_manifest_packs + [n for n in names if n not in existing_manifest_packs]


C = Catalog()


def template(slug, type, title, genres, parents, dim_spec, kind_spec=None, char_spec=None, variants=None, tags='',
             roles='RHYTHM,LEAD', eras='', amp=None, cab=None, tunings='', conf='MEDIUM'):
    t = tone(dim_spec, kind_spec, char_spec)
    if amp:
        t['ampFamilies'] = lst(amp)
    if cab:
        t['cabinet'] = cab
    return C.add(entry('tpl.%s' % slug, type, title, 'CURATED', conf, genres=lst(genres),
                       parents=['tpl.' + p for p in lst(parents)], tags=lst(tags), roles=lst(roles), eras=lst(eras),
                       tuningHints=lst(tunings), tone=t, variants=variants, notes=NOTE_TEMPLATE))


def artist(row, conf='MEDIUM'):
    """slug|Name|aliases|parent|genres|eras|tags|overrides|tunings|roles|kinds"""
    f = [x.strip() for x in row.split('|')]
    f += [''] * (11 - len(f))
    slug, name, aliases, parent, genres, eras, tags, ov, tunings, roles, kd = f[:11]
    g = lst(genres)
    return C.add(entry('artist.%s' % slug, 'ARTIST_SIGNATURE', '%s – Signature' % name, 'STYLE_INSPIRED', conf,
                       artist=name, artistAliases=lst(aliases), genres=g[:1], subgenres=g[1:], eras=lst(eras),
                       tags=lst(tags), parents=['tpl.' + parent], tuningHints=lst(tunings),
                       roles=lst(roles) or ['RHYTHM', 'LEAD'], tone=tone(ov, kd), notes=NOTE_STYLE))


def era_sig(row, conf='MEDIUM'):
    """artistslug|label|eraId|Artist Name|Title suffix|parent(entry id without prefix)|genres|tags|overrides|roles|kinds"""
    f = [x.strip() for x in row.split('|')]
    f += [''] * (11 - len(f))
    aslug, label, era, aname, suffix, parent, genres, tags, ov, roles, kd = f[:11]
    return C.add(entry('era.%s.%s' % (aslug, label), 'ERA_SIGNATURE', '%s – %s' % (aname, suffix), 'STYLE_INSPIRED', conf,
                       artist=aname, era=era, genres=lst(genres), tags=lst(tags), parents=[parent or 'artist.' + aslug],
                       roles=lst(roles) or ['RHYTHM', 'LEAD'], tone=tone(ov, kd), notes=NOTE_STYLE))


def album(row, conf='MEDIUM'):
    """artistslug|slug|Artist Name|Album|year|era|parent|tags|overrides"""
    f = [x.strip() for x in row.split('|')]
    f += [''] * (9 - len(f))
    aslug, slug, aname, title, year, era, parent, tags, ov = f[:9]
    return C.add(entry('album.%s.%s' % (aslug, slug), 'ALBUM_SIGNATURE', '%s – %s (Album)' % (aname, title), 'STYLE_INSPIRED',
                       conf, artist=aname, album=title, year=int(year) if year else None, era=era,
                       parents=[parent or 'artist.' + aslug], tags=lst(tags), tone=tone(ov), notes=NOTE_STYLE))


def song(row, conf='MEDIUM'):
    """artistslug|slug|Artist Name|Title|aliases|parent|roles|tunings|tags|overrides|year"""
    f = [x.strip() for x in row.split('|')]
    f += [''] * (11 - len(f))
    aslug, slug, aname, title, aliases, parent, roles, tunings, tags, ov, year = f[:11]
    return C.add(entry('song.%s.%s' % (aslug, slug), 'SONG', title, 'STYLE_INSPIRED', conf, artist=aname, song=title,
                       songAliases=lst(aliases), year=int(year) if year else None,
                       parents=[parent or 'artist.' + aslug], roles=lst(roles) or ['RHYTHM', 'LEAD'],
                       tuningHints=lst(tunings), tags=lst(tags), tone=tone(ov), notes=NOTE_STYLE))
