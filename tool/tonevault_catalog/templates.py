"""Genre and style templates of the mass catalog (perceptual 0..100 targets, no device data).

Every template is musically distinguishable: the numbers below are curated stylistic starting points
(WyrmTone opinion, no statement about original equipment). Artists inherit and override only a few values.
"""
from common import C, template, variant

AB = 'british,high gain'      # ampFamilies are character words, not products
AC = 'british,crunch'
AUS = 'american,high gain'
AUC = 'american,clean'
VC = 'vintage,clean'
AF = 'fuzz,vintage'


def build():
    C.pack('core_genres_ext', 'Genre-Templates (Erweiterung)',
           'Zusätzliche Genre- und Style-Templates für den Massenkatalog; Basis der Vererbung.', 'CURATED')

    # ------------------------------------------------------------------ METAL
    template('genre.nwobhm', 'GENRE_TEMPLATE', 'NWOBHM (Basis)', 'nwobhm,heavy_metal', '',
             'g=54,sa=52,ti=52,at=56,su=58,ba=50,lm=52,mi=64,um=58,tr=58,pr=56,co=12,gs=8,go=60,sp=6,de=off,re=8,mo=off,ir=56',
             'reverb:room', 'vintage=55,aggr=55', tags='raw,vintage,galloping,mid-forward', amp=AC, cab='4x12',
             eras='1980s', tunings='eStandard',
             variants=[variant('LEAD', 'g=58,su=68,de=12,re=14', 'delay:tape')], roles='RHYTHM,LEAD')
    template('genre.speed_metal', 'GENRE_TEMPLATE', 'Speed Metal (Basis)', 'speed_metal', '',
             'g=66,sa=62,ti=78,at=76,su=56,ba=46,lm=44,mi=54,um=62,tr=60,pr=58,co=10,gs=35,go=80,sp=4,de=off,re=5,mo=off,ir=58',
             'reverb:room', 'aggr=75,clarity=62', tags='fast,tight,aggressive', amp=AB, cab='4x12', eras='1980s',
             variants=[variant('LEAD', 'g=68,su=66,de=12,re=10', 'delay:digital')])
    template('genre.power_metal', 'GENRE_TEMPLATE', 'Power Metal (Basis)', 'power_metal', '',
             'g=58,sa=56,ti=70,at=66,su=74,ba=46,lm=44,mi=56,um=64,tr=64,pr=62,co=22,gs=25,go=78,sp=12,de=8,re=14,mo=off,ir=62',
             'reverb:hall;delay:digital', 'clarity=75,aggr=45,width=60', tags='melodic,bright,epic,polished', amp=AB, cab='4x12',
             eras='1990s,2000s',
             variants=[variant('LEAD', 'g=62,su=82,de=22,re=22', 'delay:digital;reverb:hall')])
    template('style.progressive_metal', 'STYLE_TEMPLATE', 'Progressive Metal (Style)', 'progressive_metal', 'genre.heavy_metal',
             'g=56,sa=54,ti=66,at=62,su=70,ba=48,lm=44,mi=54,um=62,tr=60,pr=58,co=25,gs=15,go=75,sp=14,de=10,re=16,mo=10,ir=60',
             'reverb:hall', 'clarity=82,aggr=50,width=55', tags='technical,clear,dynamic,layered', roles='RHYTHM,LEAD,CLEAN,SOLO',
             variants=[variant('CLEAN', 'g=14,sa=16,ti=30,mo=28,re=26,de=18', 'modulation:chorus;delay:analogWarm'),
                       variant('LEAD', 'g=58,su=80,de=24,re=22', 'delay:digital;reverb:hall')])
    template('genre.groove_metal', 'GENRE_TEMPLATE', 'Groove Metal (Basis)', 'groove_metal', '',
             'g=68,sa=66,ti=76,at=78,su=52,ba=56,lm=48,mi=40,um=58,tr=56,pr=58,co=10,gs=40,go=80,sp=4,de=off,re=4,mo=off,ir=54',
             'reverb:room', 'aggr=80,body=70', tags='groove,punchy,scooped,heavy', amp=AB, cab='4x12', eras='1990s,2000s',
             tunings='dStandard,dropC',
             variants=[variant('LEAD', 'g=70,su=64,de=10,re=10', 'delay:digital')])
    template('genre.industrial_metal', 'GENRE_TEMPLATE', 'Industrial Metal (Basis)', 'industrial_metal', '',
             'g=62,sa=70,ti=88,at=82,su=48,ba=52,lm=42,mi=44,um=60,tr=58,pr=60,co=35,gs=70,go=88,sp=4,de=off,re=4,mo=off,ir=56',
             'drive:boost', 'aggr=70,clarity=55,lofi=25', tags='mechanical,tight,gated,rhythmic', amp=AB, cab='4x12', eras='1990s',
             roles='RHYTHM,LEAD,SPECIAL',
             variants=[variant('SPECIAL', 'g=54,sa=76,mo=18,de=12,re=10', 'modulation:flanger')])
    template('genre.alt_metal', 'GENRE_TEMPLATE', 'Alternative Metal (Basis)', 'alternative_metal', '',
             'g=58,sa=58,ti=64,at=62,su=62,ba=54,lm=50,mi=52,um=54,tr=52,pr=50,co=20,gs=20,go=70,sp=10,de=6,re=12,mo=12,ir=52',
             'reverb:plate', 'body=62,aggr=55,width=50', tags='dynamic,moody,heavy', amp=AC, cab='4x12', eras='1990s,2000s',
             roles='RHYTHM,LEAD,CLEAN',
             variants=[variant('CLEAN', 'g=16,sa=18,ti=30,mo=24,re=28,de=20', 'modulation:chorus;delay:analogWarm')])
    template('genre.technical_death_metal', 'GENRE_TEMPLATE', 'Technical Death Metal (Basis)', 'technical_death_metal', '',
             'g=72,sa=70,ti=92,at=88,su=52,ba=46,lm=40,mi=48,um=64,tr=60,pr=62,co=8,gs=68,go=92,sp=3,de=off,re=3,mo=off,ir=60',
             'reverb:room', 'clarity=82,aggr=88', tags='precise,tight,technical,brutal', amp=AB, cab='4x12', eras='1990s,2010s',
             variants=[variant('LEAD', 'g=70,su=66,de=8,re=8', 'delay:digital')])
    template('genre.black_metal', 'GENRE_TEMPLATE', 'Black Metal (Basis)', 'black_metal', '',
             'g=76,sa=78,ti=72,at=70,su=78,ba=34,lm=36,mi=48,um=70,tr=72,pr=68,co=5,gs=25,go=70,sp=20,de=off,re=22,mo=off,ir=68',
             'reverb:hall', 'lofi=45,aggr=85,dark=55,width=55', tags='cold,icy,raw,tremolo-picking', amp=AB, cab='4x12', eras='1990s',
             variants=[variant('LEAD', 'g=72,su=84,re=28', 'reverb:hall'),
                       variant('AMBIENT', 'g=10,sa=12,re=70,de=44,mo=24,sp=26', 'reverb:hall;delay:analogWarm;modulation:chorus')],
             roles='RHYTHM,LEAD,AMBIENT')
    template('genre.symphonic_metal', 'GENRE_TEMPLATE', 'Symphonic Metal (Basis)', 'symphonic_metal', '',
             'g=56,sa=54,ti=74,at=66,su=68,ba=44,lm=40,mi=52,um=58,tr=60,pr=58,co=25,gs=30,go=80,sp=14,de=6,re=18,mo=8,ir=62',
             'reverb:hall', 'clarity=78,width=70,aggr=50', tags='polished,layered,epic,controlled', amp=AB, cab='4x12', eras='2000s',
             roles='RHYTHM,LEAD,CLEAN',
             variants=[variant('CLEAN', 'g=14,sa=16,ti=30,mo=26,re=32', 'modulation:chorus;reverb:hall')])
    template('genre.gothic_metal', 'GENRE_TEMPLATE', 'Gothic Metal (Basis)', 'gothic_metal', '',
             'g=54,sa=56,ti=50,at=52,su=70,ba=58,lm=56,mi=52,um=48,tr=46,pr=44,co=22,gs=12,go=60,sp=18,de=8,re=22,mo=22,ir=46',
             'modulation:chorus;reverb:hall', 'dark=70,warmth=55,width=60', tags='dark,moody,warm,wide', amp=AB, cab='4x12',
             eras='1990s', roles='RHYTHM,LEAD,CLEAN',
             variants=[variant('CLEAN', 'g=14,sa=16,ti=28,mo=34,re=34,de=22', 'modulation:chorus;delay:analogWarm')])
    template('genre.folk_viking_metal', 'GENRE_TEMPLATE', 'Folk / Viking Metal (Basis)', 'folk_metal,viking_metal', '',
             'g=60,sa=58,ti=68,at=66,su=64,ba=48,lm=48,mi=56,um=60,tr=60,pr=58,co=18,gs=22,go=76,sp=12,de=6,re=16,mo=off,ir=58',
             'reverb:hall', 'clarity=66,aggr=60,warmth=45', tags='epic,melodic,driving', amp=AB, cab='4x12', eras='2000s',
             variants=[variant('LEAD', 'g=62,su=76,de=16,re=20', 'delay:digital;reverb:hall')])
    template('genre.sludge_metal', 'GENRE_TEMPLATE', 'Sludge Metal (Basis)', 'sludge_metal', '',
             'g=68,sa=76,ti=34,at=40,su=80,ba=66,lm=64,mi=50,um=44,tr=42,pr=40,co=28,gs=4,go=45,sp=10,de=off,re=10,mo=off,ir=40',
             'drive:fuzz;reverb:plate', 'fuzz=65,aggr=75,warmth=40', tags='heavy,thick,murky,slow', amp=AB, cab='4x12',
             eras='1990s', tunings='dStandard,dropC',
             variants=[variant('LEAD', 'g=66,su=84,re=18', 'reverb:plate')])
    template('genre.post_metal', 'GENRE_TEMPLATE', 'Post Metal (Basis)', 'post_metal', '',
             'g=58,sa=60,ti=42,at=44,su=82,ba=60,lm=56,mi=48,um=50,tr=50,pr=46,co=30,gs=5,go=50,sp=30,de=20,re=38,mo=14,ir=48',
             'delay:analogWarm;reverb:hall', 'width=80,clarity=55,dark=45', tags='wide,ambient,heavy,slow', amp=AB, cab='4x12',
             eras='2000s', roles='RHYTHM,LEAD,AMBIENT,CLEAN',
             variants=[variant('AMBIENT', 'g=12,sa=14,re=68,de=48,mo=22,sp=28', 'reverb:hall;delay:analogWarm;modulation:chorus'),
                       variant('CLEAN', 'g=14,sa=16,ti=28,re=36,de=26,mo=20', 'delay:analogWarm;reverb:hall')])
    template('style.melodic_metalcore', 'STYLE_TEMPLATE', 'Melodic Metalcore (Style)', 'melodic_metalcore,metalcore', 'genre.modern_metal',
             'g=70,ti=80,su=70,um=64,tr=62,re=8,de=6', 'reverb:room', 'clarity=74,aggr=68', tags='melodic,modern,tight,polished',
             eras='2000s', roles='RHYTHM,LEAD,CLEAN',
             variants=[variant('CLEAN', 'g=14,sa=16,ti=32,re=30,de=22,mo=18', 'delay:digital;reverb:plate')])
    template('style.deathcore', 'STYLE_TEMPLATE', 'Deathcore (Style)', 'deathcore', 'genre.modern_metal',
             'g=78,sa=78,ti=92,at=86,su=48,ba=52,lm=42,mi=44,um=56,tr=54,pr=56,co=8,gs=75,go=90,re=3', 'reverb:room',
             'aggr=92,body=72', tags='brutal,downtuned,tight,heavy', eras='2010s', tunings='dropB,dropA')
    template('style.modern_djent', 'STYLE_TEMPLATE', 'Modern Djent (Style)', 'djent', 'genre.progressive_djent',
             'g=74,ti=94,at=90,su=54,ba=44,lm=36,mi=46,um=62,tr=58,co=10,gs=74,go=92,re=4', 'reverb:room',
             'clarity=86,aggr=72', tags='precise,percussive,modern,clear', eras='2010s', tunings='dropB,dropA',
             roles='RHYTHM,LEAD,CLEAN',
             variants=[variant('CLEAN', 'g=14,sa=16,ti=34,mo=24,re=34,de=28', 'modulation:chorus;delay:digital;reverb:hall')])
    template('style.dark_modern_metal', 'STYLE_TEMPLATE', 'Dark Modern Metal (Style)', 'alternative_metal,metalcore', 'genre.modern_metal',
             'g=68,ba=52,mi=48,tr=54,pr=52,de=10,re=16,sp=12', 'delay:analogWarm;reverb:hall', 'dark=62,width=55,aggr=62',
             tags='dark,moody,modern,atmospheric', eras='2010s,2020s', roles='RHYTHM,LEAD,CLEAN,AMBIENT',
             variants=[variant('AMBIENT', 'g=10,sa=12,re=64,de=42,mo=22,sp=24', 'reverb:hall;delay:analogWarm;modulation:chorus'),
                       variant('CLEAN', 'g=14,sa=16,ti=30,re=32,de=24,mo=20', 'delay:analogWarm;reverb:hall')])

    # ------------------------------------------------------------------ ROCK
    template('genre.blues_clean', 'GENRE_TEMPLATE', 'Electric Blues Clean (Basis)', 'blues', '',
             'g=26,sa=30,ti=30,at=52,su=54,ba=48,lm=54,mi=62,um=52,tr=50,pr=46,co=22,gs=off,sp=10,de=off,mo=off,re=22,ir=46',
             'reverb:spring', 'vintage=75,warmth=70', tags='warm,vintage,dynamic,expressive', amp=VC, cab='2x12',
             roles='CLEAN,CRUNCH,LEAD,SOLO', eras='1960s,1970s',
             variants=[variant('CRUNCH', 'g=40,sa=44'), variant('LEAD', 'g=44,su=68,re=22,de=10', 'delay:analogWarm'),
                       variant('SOLO', 'g=46,su=72,re=24,de=12', 'delay:analogWarm')])
    template('style.texas_blues', 'STYLE_TEMPLATE', 'Texas Blues (Style)', 'texas_blues,blues', 'genre.blues_clean',
             'g=36,sa=38,ti=36,at=58,su=58,ba=46,lm=52,mi=60,um=58,tr=56,pr=52,co=14,re=20', 'reverb:spring',
             'vintage=70,warmth=60,aggr=40', tags='bright,punchy,dynamic,spring-reverb', amp='american,vintage', cab='1x12',
             eras='1970s,1980s', tunings='ebStandard')
    template('style.chicago_blues', 'STYLE_TEMPLATE', 'Chicago Blues (Style)', 'chicago_blues,blues', 'genre.blues_clean',
             'g=34,sa=40,ti=28,at=50,su=48,ba=52,lm=58,mi=64,um=50,tr=44,pr=42,co=20,re=14,ir=42', 'reverb:room',
             'vintage=85,warmth=75,lofi=25', tags='warm,gritty,vintage,raw', amp='vintage,tweed', cab='4x10', eras='1960s')
    template('genre.psychedelic_rock', 'GENRE_TEMPLATE', 'Psychedelic Rock (Basis)', 'psychedelic_rock', '',
             'g=50,sa=58,ti=36,at=48,su=72,ba=50,lm=54,mi=56,um=52,tr=52,pr=48,co=26,gs=off,sp=22,de=20,mo=32,re=32,ir=48',
             'modulation:phaser;delay:tape;reverb:spring', 'vintage=85,warmth=55,fuzz=45,width=65',
             tags='swirling,vintage,fuzzy,wide', amp=AF, cab='4x12', eras='1960s,1970s',
             variants=[variant('LEAD', 'g=58,su=80,de=26,mo=36', 'drive:fuzz;delay:tape')])
    template('genre.garage_rock', 'GENRE_TEMPLATE', 'Garage Rock (Basis)', 'garage_rock', '',
             'g=52,sa=56,ti=40,at=54,su=50,ba=46,lm=50,mi=58,um=56,tr=56,pr=54,co=12,gs=off,sp=6,de=off,mo=off,re=10,ir=54',
             'reverb:spring', 'lofi=35,aggr=55,vintage=55', tags='raw,loose,fuzzy,lo-fi', amp='vintage,crunch', cab='2x12',
             eras='1960s,2000s')
    template('genre.southern_rock', 'GENRE_TEMPLATE', 'Southern Rock (Basis)', 'southern_rock', '',
             'g=42,sa=46,ti=44,at=54,su=64,ba=50,lm=56,mi=62,um=54,tr=52,pr=48,co=18,gs=off,sp=8,de=off,mo=off,re=16,ir=48',
             'reverb:spring', 'warmth=65,vintage=70', tags='warm,twin-lead,singing,vintage', amp=AC, cab='2x12', eras='1970s',
             variants=[variant('LEAD', 'g=50,su=76,re=18,de=8', 'delay:tape'), variant('SOLO', 'g=52,su=80,re=20,de=10', 'delay:tape')],
             roles='RHYTHM,LEAD,SOLO')
    template('genre.glam_metal', 'GENRE_TEMPLATE', 'Glam / Hair Metal (Basis)', 'glam_metal', '',
             'g=58,sa=54,ti=58,at=54,su=64,ba=46,lm=46,mi=60,um=60,tr=64,pr=62,co=25,gs=18,go=68,sp=14,de=10,mo=24,re=16,ir=62',
             'modulation:chorus;delay:digital;reverb:plate', 'clarity=68,width=65,vintage=45', tags='polished,bright,chorused,80s',
             amp=AB, cab='4x12', eras='1980s',
             variants=[variant('LEAD', 'g=62,su=76,de=18,mo=20', 'delay:digital'), variant('CLEAN', 'g=14,sa=16,mo=42,re=30', 'modulation:chorus')],
             roles='RHYTHM,LEAD,CLEAN')
    template('genre.progressive_rock', 'GENRE_TEMPLATE', 'Progressive Rock (Basis)', 'progressive_rock', '',
             'g=36,sa=40,ti=40,at=50,su=68,ba=48,lm=50,mi=56,um=54,tr=54,pr=50,co=28,gs=off,sp=20,de=18,mo=20,re=28,ir=52',
             'modulation:chorus;delay:analogWarm;reverb:hall', 'clarity=68,warmth=55,width=65', tags='dynamic,layered,melodic,spacious',
             amp=AC, cab='4x12', eras='1970s,1980s', roles='RHYTHM,LEAD,CLEAN,AMBIENT,SOLO',
             variants=[variant('CLEAN', 'g=14,sa=16,mo=34,de=24,re=32', 'modulation:chorus'),
                       variant('AMBIENT', 'g=10,sa=12,re=60,de=40,mo=26,sp=24', 'reverb:hall;delay:analogWarm'),
                       variant('SOLO', 'g=50,su=82,de=26,re=26', 'delay:analogWarm')])
    template('genre.post_grunge', 'GENRE_TEMPLATE', 'Post-Grunge (Basis)', 'post_grunge', '',
             'g=56,sa=58,ti=52,at=54,su=60,ba=54,lm=52,mi=54,um=54,tr=52,pr=50,co=28,gs=10,go=62,sp=8,de=off,mo=8,re=12,ir=52',
             'reverb:plate', 'clarity=60,aggr=50,body=62', tags='polished,radio,dense', amp=AC, cab='4x12', eras='1990s,2000s')
    template('genre.punk_classic', 'GENRE_TEMPLATE', 'Punk Rock (Basis)', 'punk_rock', '',
             'g=52,sa=56,ti=58,at=64,su=40,ba=46,lm=48,mi=56,um=60,tr=58,pr=58,co=10,gs=off,sp=4,de=off,mo=off,re=6,ir=58',
             'reverb:room', 'aggr=70,lofi=30', tags='raw,fast,upstroke,direct', amp=AC, cab='4x12', eras='1970s,1980s',
             roles='RHYTHM,LEAD')
    template('genre.post_punk', 'GENRE_TEMPLATE', 'Post-Punk (Basis)', 'post_punk', '',
             'g=28,sa=30,ti=48,at=62,su=44,ba=42,lm=44,mi=52,um=62,tr=64,pr=60,co=18,gs=off,sp=16,de=14,mo=28,re=22,ir=64',
             'modulation:chorus;delay:analogWarm;reverb:plate', 'clarity=70,dark=45,width=55', tags='angular,cold,bright,chorused',
             amp=AUC, cab='2x12', eras='1980s,2000s', roles='RHYTHM,LEAD,CLEAN',
             variants=[variant('CLEAN', 'g=14,sa=16,mo=36,de=18,re=26', 'modulation:chorus')])
    template('genre.emo', 'GENRE_TEMPLATE', 'Emo (Basis)', 'emo', '',
             'g=38,sa=40,ti=46,at=58,su=50,ba=46,lm=46,mi=56,um=60,tr=58,pr=56,co=16,gs=off,sp=14,de=12,mo=18,re=20,ir=58',
             'delay:digital;reverb:plate', 'clarity=68,warmth=45,width=55', tags='twinkly,clean-crunch,expressive,dynamic',
             amp=AUC, cab='2x12', eras='1990s,2000s', roles='RHYTHM,LEAD,CLEAN',
             variants=[variant('CLEAN', 'g=14,sa=16,mo=22,de=20,re=26', 'delay:digital')])
    template('genre.post_hardcore', 'GENRE_TEMPLATE', 'Post-Hardcore (Basis)', 'post_hardcore', '',
             'g=62,sa=62,ti=62,at=66,su=54,ba=48,lm=48,mi=56,um=62,tr=60,pr=58,co=14,gs=12,go=66,sp=8,de=8,mo=10,re=10,ir=58',
             'delay:digital;reverb:room', 'aggr=68,clarity=62,lofi=15', tags='energetic,angular,dynamic', amp=AC, cab='4x12',
             eras='2000s', roles='RHYTHM,LEAD,CLEAN',
             variants=[variant('CLEAN', 'g=16,sa=18,ti=32,de=20,re=26,mo=16', 'delay:digital')])
    template('style.britpop_indie', 'STYLE_TEMPLATE', 'Britpop / Indie (Style)', 'indie_rock,alternative_rock', 'genre.alt_indie',
             'g=44,sa=46,ti=44,at=56,su=52,tr=58,pr=54,mi=58,re=16,de=8', 'reverb:spring', 'clarity=65,warmth=50',
             tags='jangly,bright,anthemic,layered', eras='1990s,2000s', roles='RHYTHM,LEAD,CLEAN',
             variants=[variant('CLEAN', 'g=14,sa=16,mo=20,re=22,de=14', 'delay:analogWarm')])
    template('genre.shoegaze', 'GENRE_TEMPLATE', 'Shoegaze / Dream Pop (Basis)', 'shoegaze', '',
             'g=48,sa=62,ti=24,at=30,su=84,ba=50,lm=52,mi=44,um=46,tr=54,pr=44,co=32,gs=off,sp=44,de=32,mo=44,re=58,ir=52',
             'modulation:chorus;delay:analogWarm;reverb:hall', 'width=90,warmth=55,fuzz=45,clarity=35',
             tags='washy,dreamy,layered,wall-of-sound', amp=AF, cab='4x12', eras='1990s,2010s', roles='RHYTHM,LEAD,AMBIENT,CLEAN',
             variants=[variant('AMBIENT', 'g=14,sa=18,re=72,de=46,mo=40,sp=36', 'reverb:hall;delay:analogWarm;modulation:chorus'),
                       variant('CLEAN', 'g=14,sa=16,mo=46,re=48,de=30', 'modulation:chorus;reverb:hall')])
    template('genre.post_rock', 'GENRE_TEMPLATE', 'Post Rock (Basis)', 'post_rock', '',
             'g=32,sa=36,ti=30,at=42,su=76,ba=48,lm=48,mi=48,um=52,tr=54,pr=46,co=30,gs=off,sp=38,de=42,mo=16,re=52,ir=54',
             'delay:analogWarm;reverb:hall', 'width=85,clarity=62,warmth=50', tags='swelling,ambient,dynamic,cinematic',
             amp=AUC, cab='2x12', eras='2000s', roles='RHYTHM,LEAD,CLEAN,AMBIENT',
             variants=[variant('CLEAN', 'g=14,sa=16,de=44,re=48', 'delay:analogWarm;reverb:hall'),
                       variant('AMBIENT', 'g=10,sa=12,re=70,de=52,mo=18,sp=32', 'reverb:hall;delay:analogWarm'),
                       variant('LEAD', 'g=36,su=84,de=46,re=52', 'delay:analogWarm;reverb:hall')])
    template('style.classic_rock_early', 'STYLE_TEMPLATE', 'Classic Rock 60s/70s (Style)', 'classic_rock', 'genre.classic_rock',
             'g=38,sa=42,ti=36,at=52,su=60,ba=48,mi=62,tr=52,re=14', 'reverb:spring', 'vintage=85,warmth=68',
             tags='vintage,warm,dynamic,organic', eras='1960s,1970s',
             variants=[variant('SOLO', 'g=52,su=74,re=18,de=10', 'delay:tape')], roles='RHYTHM,LEAD,SOLO')
    template('style.hard_rock_80s', 'STYLE_TEMPLATE', '80s Hard Rock (Style)', 'hard_rock', 'genre.hard_rock',
             'g=60,sa=58,ti=58,su=64,tr=60,pr=58,co=22,mo=18,de=10,re=16,gs=15', 'modulation:chorus;delay:digital;reverb:plate',
             'clarity=64,width=60', tags='polished,80s,bright,chorused', eras='1980s',
             variants=[variant('LEAD', 'g=62,su=78,de=20,mo=20', 'delay:digital')])
    template('style.pop_punk_modern', 'STYLE_TEMPLATE', 'Modern Pop Punk (Style)', 'pop_punk', 'genre.punk_pop_punk',
             'g=54,sa=56,ti=62,at=64,su=46,tr=60,pr=60,co=16,re=8', 'reverb:room', 'clarity=68,aggr=55',
             tags='bright,tight,radio,energetic', eras='2000s,2010s')

    # ------------------------------------------------------------------ OTHER GUITAR
    template('genre.blues_soul_rnb', 'GENRE_TEMPLATE', 'Soul / R&B Guitar (Basis)', 'soul', '',
             'g=14,sa=18,ti=30,at=60,su=44,ba=44,lm=48,mi=54,um=54,tr=52,pr=46,co=40,gs=off,sp=10,de=off,mo=12,re=20,ir=48',
             'reverb:spring', 'warmth=70,vintage=70,clarity=70', tags='warm,clean,tight,compressed', amp=VC, cab='1x12',
             roles='CLEAN,CRUNCH,LEAD', eras='1960s,1970s',
             variants=[variant('CRUNCH', 'g=32,sa=34'), variant('LEAD', 'g=30,su=56,de=8')])
    template('genre.funk', 'GENRE_TEMPLATE', 'Funk Guitar (Basis)', 'funk', '',
             'g=10,sa=12,ti=44,at=76,su=30,ba=40,lm=42,mi=56,um=62,tr=62,pr=56,co=48,gs=off,sp=6,de=off,mo=14,re=12,ir=60',
             'reverb:spring', 'clarity=82,warmth=45', tags='clean,funky,percussive,compressed,tight', amp=AUC, cab='1x12',
             roles='RHYTHM,CLEAN,LEAD', eras='1970s,1980s',
             variants=[variant('CLEAN', 'g=8,sa=10'), variant('LEAD', 'g=22,sa=24,su=52,de=8', 'delay:analogWarm')])
    template('genre.country', 'GENRE_TEMPLATE', 'Country Guitar (Basis)', 'country', '',
             'g=16,sa=20,ti=38,at=70,su=44,ba=42,lm=46,mi=50,um=60,tr=64,pr=58,co=44,gs=off,sp=8,de=10,mo=6,re=18,ir=64',
             'delay:tape;reverb:spring', 'clarity=76,vintage=55,warmth=45', tags='twangy,bright,snappy,compressed', amp=AUC, cab='1x12',
             roles='CLEAN,CRUNCH,LEAD', eras='1960s,1990s,2010s',
             variants=[variant('CRUNCH', 'g=34,sa=36'), variant('LEAD', 'g=26,su=54,de=14', 'delay:tape')])
    template('genre.jazz_guitar', 'GENRE_TEMPLATE', 'Jazz Guitar (Basis)', 'jazz', '',
             'g=6,sa=8,ti=24,at=38,su=52,ba=54,lm=58,mi=48,um=38,tr=30,pr=26,co=30,gs=off,sp=8,de=off,mo=off,re=16,ir=32',
             'reverb:plate', 'warmth=85,dark=60,clarity=55,vintage=60', tags='warm,round,dark,smooth,clean', amp=VC, cab='1x12',
             roles='CLEAN,LEAD,SOLO', eras='1960s,1970s',
             variants=[variant('LEAD', 'g=8,su=58,re=20'), variant('SOLO', 'g=10,su=60,re=22,de=6', 'delay:analogWarm')])
    template('style.jazz_fusion', 'STYLE_TEMPLATE', 'Jazz Fusion (Style)', 'fusion', 'genre.jazz_guitar',
             'g=30,sa=34,ti=48,at=60,su=68,ba=46,lm=46,mi=56,um=58,tr=54,pr=52,co=32,de=14,mo=18,re=18,ir=48',
             'modulation:chorus;delay:digital;reverb:plate', 'clarity=72,warmth=55,dark=25', tags='singing,articulate,sustaining,modern',
             eras='1970s,1980s', roles='CLEAN,LEAD,SOLO,RHYTHM',
             variants=[variant('SOLO', 'g=38,su=82,de=20,mo=16', 'delay:digital')])
    template('genre.surf', 'GENRE_TEMPLATE', 'Surf Guitar (Basis)', 'surf', '',
             'g=22,sa=26,ti=42,at=72,su=40,ba=40,lm=44,mi=48,um=58,tr=66,pr=58,co=16,gs=off,sp=30,de=16,mo=30,re=68,ir=66',
             'modulation:tremolo;reverb:spring', 'vintage=85,width=60,clarity=65', tags='reverb-drenched,twangy,bright,splashy',
             amp=VC, cab='1x12', eras='1960s', roles='LEAD,RHYTHM,SPECIAL',
             variants=[variant('SPECIAL', 'g=30,re=78,mo=42', 'reverb:spring;modulation:tremolo')])
    template('genre.rockabilly', 'GENRE_TEMPLATE', 'Rockabilly (Basis)', 'rockabilly', '',
             'g=22,sa=26,ti=40,at=68,su=38,ba=44,lm=48,mi=52,um=58,tr=62,pr=56,co=22,gs=off,sp=10,de=30,mo=off,re=22,ir=62',
             'delay:tape;reverb:spring', 'vintage=90,warmth=55,lofi=20', tags='slapback,twangy,vintage,snappy', amp='vintage,tweed', cab='1x12',
             eras='1960s', roles='RHYTHM,LEAD',
             variants=[variant('LEAD', 'g=28,su=48,de=34', 'delay:tape')])
    template('genre.clean_pop', 'GENRE_TEMPLATE', 'Clean Pop Guitar (Basis)', 'clean_pop', '',
             'g=10,sa=12,ti=36,at=62,su=48,ba=46,lm=46,mi=52,um=56,tr=60,pr=54,co=36,gs=off,sp=16,de=22,mo=26,re=26,ir=60',
             'modulation:chorus;delay:digital;reverb:plate', 'clarity=80,width=65,warmth=50', tags='clean,shimmering,polished,bright',
             amp=AUC, cab='2x12', eras='1980s,2000s,2010s', roles='CLEAN,RHYTHM,LEAD',
             variants=[variant('LEAD', 'g=24,sa=26,su=58,de=26', 'delay:digital')])
    template('genre.ambient_guitar', 'GENRE_TEMPLATE', 'Ambient Guitar (Basis)', 'ambient', '',
             'g=8,sa=10,ti=14,at=22,su=88,ba=42,lm=44,mi=44,um=50,tr=52,pr=42,co=36,gs=off,sp=50,de=50,mo=26,re=72,ir=50',
             'modulation:chorus;delay:analogWarm;reverb:hall', 'width=95,warmth=55,clarity=55,dark=35', tags='swelling,wide,drone,soft,ambient',
             amp=AUC, cab='2x12', eras='1980s,2010s', roles='AMBIENT,CLEAN,LEAD',
             variants=[variant('LEAD', 'g=20,sa=24,su=90,de=54,re=68', 'delay:analogWarm;reverb:hall'), variant('CLEAN', 'g=8,re=60,de=42')])
    template('genre.lo_fi_guitar', 'GENRE_TEMPLATE', 'Lo-Fi Guitar (Basis)', 'lo_fi', '',
             'g=18,sa=26,ti=28,at=44,su=42,ba=46,lm=52,mi=50,um=42,tr=36,pr=30,co=42,gs=off,sp=12,de=14,mo=36,re=24,ir=34',
             'modulation:chorus;delay:tape;reverb:spring', 'lofi=80,warmth=65,vintage=75,dark=45,clarity=30', tags='wobbly,warm,dusty,lo-fi,tape',
             amp=VC, cab='1x12', eras='2010s', roles='CLEAN,LEAD,RHYTHM,SPECIAL',
             variants=[variant('SPECIAL', 'g=20,mo=52,de=20,ir=26', 'modulation:chorus')])
    template('genre.instrumental_rock', 'GENRE_TEMPLATE', 'Instrumental Rock / Shred (Basis)', 'instrumental_rock', '',
             'g=66,sa=64,ti=62,at=60,su=80,ba=46,lm=46,mi=58,um=62,tr=60,pr=58,co=28,gs=18,go=72,sp=14,de=18,mo=14,re=20,ir=60',
             'modulation:chorus;delay:digital;reverb:hall', 'clarity=76,width=60', tags='singing,sustaining,articulate,virtuosic',
             amp=AB, cab='4x12', eras='1980s,1990s', roles='LEAD,SOLO,RHYTHM,CLEAN',
             variants=[variant('SOLO', 'g=68,su=88,de=22,re=24', 'delay:digital'), variant('CLEAN', 'g=14,sa=16,mo=30,de=24,re=28', 'modulation:chorus')])

    # ------------------------------------------------------------------ ELECTRONIC / GUITAR REIMAGINED
    template('genre.trance_guitar', 'GENRE_TEMPLATE', 'Trance Guitar (Basis)', 'trance_inspired', '',
             'g=46,sa=52,ti=64,at=66,su=84,ba=42,lm=40,mi=52,um=62,tr=62,pr=58,co=32,gs=45,go=80,sp=22,de=34,mo=22,re=34,ir=62',
             'drive:octave;modulation:chorus;delay:digital;reverb:hall', 'clarity=70,width=80', tags='pulsing,sustaining,gated,synth-like',
             roles='LEAD,RHYTHM,SPECIAL',
             variants=[variant('RHYTHM', 'g=52,ti=76,su=40,gs=60', 'delay:digital'), variant('SPECIAL', 'g=40,su=90,de=44,re=44', 'reverb:hall')])
    template('genre.techno_guitar', 'GENRE_TEMPLATE', 'Techno / House Guitar (Basis)', 'techno_inspired', '',
             'g=52,sa=58,ti=74,at=72,su=56,ba=46,lm=44,mi=54,um=60,tr=56,pr=56,co=34,gs=55,go=84,sp=8,de=20,mo=10,re=16,ir=58',
             'drive:distortion;delay:digital', 'aggr=55,clarity=60,lofi=15', tags='rhythmic,pulsing,mechanical,driving',
             roles='RHYTHM,LEAD,SPECIAL')
    template('genre.eurodance_guitar', 'GENRE_TEMPLATE', 'Eurodance Guitar (Basis)', 'eurodance_inspired', '',
             'g=40,sa=44,ti=60,at=64,su=70,ba=42,lm=40,mi=56,um=62,tr=64,pr=60,co=34,gs=25,go=76,sp=14,de=22,mo=18,re=22,ir=64',
             'drive:octave;delay:digital;reverb:plate', 'clarity=74,width=60', tags='bright,catchy,synth-like,poppy',
             roles='LEAD,RHYTHM,CLEAN')
    template('genre.house_funk_guitar', 'GENRE_TEMPLATE', 'French House / Disco Guitar (Basis)', 'house_inspired', '',
             'g=14,sa=22,ti=50,at=70,su=40,ba=42,lm=44,mi=56,um=60,tr=60,pr=54,co=52,gs=off,sp=8,de=16,mo=30,re=14,ir=58',
             'modulation:phaser;delay:digital', 'clarity=76,warmth=45', tags='filtered,funky,compressed,groovy',
             roles='RHYTHM,LEAD,CLEAN',
             variants=[variant('CLEAN', 'g=8,sa=12,mo=36', 'modulation:phaser')])
    template('genre.chiptune_guitar', 'GENRE_TEMPLATE', '8-Bit / Chiptune Guitar (Basis)', 'chiptune_inspired', '',
             'g=44,sa=60,ti=80,at=90,su=46,ba=36,lm=34,mi=58,um=66,tr=66,pr=64,co=24,gs=75,go=92,sp=2,de=8,mo=off,re=6,ir=70',
             'drive:octave', 'lofi=70,clarity=50,aggr=45', tags='square-ish,bright,retro,gated,arcade',
             roles='LEAD,RHYTHM,SPECIAL')
    template('genre.cinematic_ambient', 'GENRE_TEMPLATE', 'Cinematic Ambient (Basis)', 'cinematic,ambient', '',
             'g=8,sa=12,ti=12,at=18,su=92,ba=44,lm=46,mi=42,um=46,tr=48,pr=40,co=38,gs=off,sp=58,de=56,mo=30,re=78,ir=46',
             'modulation:chorus;delay:analogWarm;reverb:hall', 'width=98,dark=50,warmth=45', tags='vast,swelling,cinematic,dark,drone',
             roles='AMBIENT,SPECIAL,CLEAN',
             variants=[variant('SPECIAL', 'g=14,sa=20,re=84,de=62,mo=34,sp=64', 'reverb:hall;delay:analogWarm')])
    template('style.industrial_electronic_guitar', 'STYLE_TEMPLATE', 'Industrial Machine Guitar (Style)', 'industrial_electronic', 'genre.industrial_metal',
             'g=60,sa=76,ti=90,at=86,su=44,mi=42,tr=54,pr=58,co=42,gs=78,go=90,mo=16,de=8', 'drive:distortion;modulation:flanger',
             'aggr=78,lofi=35,clarity=50', tags='machine,gated,metallic,mechanical', roles='RHYTHM,LEAD,SPECIAL')

    template('genre.cyberpunk_synth', 'GENRE_TEMPLATE', 'Cyberpunk (Basis)', 'cyberpunk,synth_like_guitar', '',
             'g=54,sa=62,ti=66,at=66,su=74,ba=40,lm=40,mi=54,um=60,tr=50,pr=52,co=36,gs=40,go=80,sp=14,de=34,re=30,mo=16,ir=54',
             'drive:distortion;delay:digital', 'dark=70,aggr=55,lofi=20', tags='cold,neon,dark,synth-like', roles='LEAD,RHYTHM,SPECIAL',
             eras='1980s,2010s',
             variants=[variant('LEAD', 'g=52,su=84,de=40,re=34', 'delay:digital'), variant('SPECIAL', 'g=44,sa=70,mo=24,lofi=35', 'modulation:flanger')])
    template('genre.darkwave', 'GENRE_TEMPLATE', 'Darkwave (Basis)', 'darkwave', '',
             'g=26,sa=30,ti=50,at=58,su=60,ba=44,lm=46,mi=48,um=56,tr=52,pr=48,co=24,gs=off,sp=22,de=24,mo=40,re=36,ir=50',
             'modulation:chorus;delay:analogWarm;reverb:hall', 'dark=75,width=65,warmth=40', tags='dark,cold,chorused,moody',
             roles='RHYTHM,CLEAN,AMBIENT,LEAD', eras='1980s',
             variants=[variant('CLEAN', 'g=12,sa=14,mo=46,re=42', 'modulation:chorus'), variant('AMBIENT', 'g=8,sa=10,re=70,de=44,mo=30,sp=30', 'reverb:hall'),
                       variant('LEAD', 'g=34,su=72,de=32', 'delay:analogWarm')])
