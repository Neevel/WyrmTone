"""Guitar Reimagined (GUITAR_REIMAGINED) and WyrmTone originals / special sounds (WYRM_ORIGINAL).

Reimagined entries describe how the IMPRESSION of an electronic track can be hinted with a guitar; they are
never a reproduction of the original synthesizer or studio equipment. Originals are WyrmTone's own creations.
"""
from common import C, entry, tone, lst, variant, NOTE_REIM, NOTE_ORIGINAL

# slug|Artist|Title|aliases|parent template|genres|tags|overrides|kinds|roles
REIMAGINED = [
    'prodigy_firestarter|The Prodigy|Firestarter|Firestarter Guitar|genre.techno_guitar|techno_inspired,industrial_electronic|aggressive,distorted,rhythmic|g=68,sa=74,ti=82,gs=62,mo=14,aggr=80|drive:distortion;modulation:flanger|RHYTHM,LEAD,SPECIAL',
    'prodigy_breathe|The Prodigy|Breathe|Breathe Guitar|genre.techno_guitar|techno_inspired,industrial_electronic|gritty,riff,dark|g=66,sa=72,ti=78,gs=58,dark=55|drive:distortion|RHYTHM,LEAD',
    'daft_punk_around_the_world|Daft Punk|Around the World|Around the World Guitar|genre.house_funk_guitar|house_inspired|filtered,funky,repetitive|g=10,mo=42,co=58,at=76|modulation:phaser|RHYTHM,CLEAN',
    'daft_punk_one_more_time|Daft Punk|One More Time|One More Time Guitar|genre.house_funk_guitar|house_inspired|disco,bright,uplifting|g=8,mo=30,co=54,tr=64|modulation:phaser|RHYTHM,CLEAN,LEAD',
    'daft_punk_harder_better_faster_stronger|Daft Punk|Harder, Better, Faster, Stronger|Harder Better Faster Stronger,Harder Better Faster Stronger Guitar|genre.techno_guitar|house_inspired,techno_inspired|vocoder-like,rhythmic,robotic|g=44,mo=24,mi=62,co=48,de=16|modulation:flanger|LEAD,RHYTHM',
    'eiffel_65_blue|Eiffel 65|Blue (Da Ba Dee)|Blue,Da Ba Dee|genre.eurodance_guitar|eurodance_inspired|catchy,bright,poppy|g=34,su=66,tr=66,de=24|drive:octave|LEAD,RHYTHM',
    'gigi_dagostino_lamour_toujours|Gigi D\'Agostino|L\'Amour Toujours|L Amour Toujours,Lamour Toujours|genre.trance_guitar|trance_inspired,eurodance_inspired|melodic,uplifting,arpeggiated|g=36,su=80,de=40,re=38,mo=26|drive:octave|LEAD,CLEAN',
    'atb_9_pm|ATB|9 PM (Till I Come)|9 PM,Nine PM,Till I Come|genre.trance_guitar|trance_inspired|arpeggiated,delay-driven,melodic|g=30,su=76,de=52,re=36,ti=60|delay:digital|LEAD,CLEAN',
    'scooter_hyper_hyper|Scooter|Hyper Hyper|Hyper Hyper Guitar|genre.eurodance_guitar|eurodance_inspired,techno_inspired|fast,driving,hard|g=54,sa=58,ti=72,su=60|drive:distortion|LEAD,RHYTHM',
    'safri_duo_played_a_live|Safri Duo|Played-A-Live (The Bongo Song)|Played A Live,The Bongo Song|genre.eurodance_guitar|eurodance_inspired,trance_inspired|percussive,bright,rhythmic|g=28,ti=62,at=76,su=50,de=22|delay:digital|LEAD,RHYTHM',
    'paul_van_dyk_for_an_angel|Paul van Dyk|For an Angel|For an Angel Guitar|genre.trance_guitar|trance_inspired|epic,building,melodic|g=40,su=88,de=44,re=48,mo=24|reverb:hall|LEAD,AMBIENT',
    'sash_ecuador|Sash!|Ecuador|Ecuador Guitar|genre.eurodance_guitar|eurodance_inspired,trance_inspired|catchy,bright,latin-tinged|g=32,su=68,tr=66,de=26|drive:octave|LEAD',
    'fatboy_slim_right_here_right_now|Fatboy Slim|Right Here, Right Now|Right Here Right Now|genre.techno_guitar|techno_inspired|building,repetitive,big-beat|g=50,sa=56,ti=70,gs=48,de=18|drive:distortion|RHYTHM,LEAD',
    'chemical_brothers_block_rockin_beats|The Chemical Brothers|Block Rockin\' Beats|Block Rockin Beats|genre.techno_guitar|techno_inspired|gritty,riff,big-beat|g=62,sa=70,ti=74,gs=52,lofi=25|drive:fuzz|RHYTHM,LEAD',
    'underworld_born_slippy|Underworld|Born Slippy|Born Slippy Guitar|genre.trance_guitar|trance_inspired,techno_inspired|pulsing,building,anthemic|g=42,su=78,de=46,re=34,ti=66|delay:digital|LEAD,RHYTHM',
    'vengaboys_boom_boom_boom|Vengaboys|Boom, Boom, Boom!!|Boom Boom Boom|genre.eurodance_guitar|eurodance_inspired|poppy,bouncy,bright|g=30,su=60,tr=68,mo=20|modulation:chorus|LEAD,CLEAN',
    'basshunter_boten_anna|Basshunter|Boten Anna|Boten Anna Guitar|genre.eurodance_guitar|eurodance_inspired,trance_inspired|catchy,bright,chippy|g=34,su=72,tr=68,de=28|drive:octave|LEAD',
    'modjo_lady|Modjo|Lady (Hear Me Tonight)|Lady Hear Me Tonight|genre.house_funk_guitar|house_inspired|disco,funky,compressed|g=8,co=56,mo=28,at=78|modulation:phaser|RHYTHM,CLEAN',
    'cascada_everytime_we_touch|Cascada|Everytime We Touch|Everytime We Touch Guitar|genre.trance_guitar|trance_inspired,eurodance_inspired|uplifting,bright,melodic|g=34,su=76,tr=68,de=36,re=34|delay:digital|LEAD,CLEAN',
    'jean_michel_jarre_oxygene_4|Jean-Michel Jarre|Oxygène (Part IV)|Oxygene Part 4,Oxygene 4|genre.cinematic_ambient|cinematic,ambient|floating,vintage,wide|g=10,su=86,mo=36,re=66,de=42,vintage=75|modulation:chorus|LEAD,AMBIENT',
    'kraftwerk_the_robots|Kraftwerk|The Robots|The Robots Guitar|genre.techno_guitar|techno_inspired|robotic,minimal,mechanical|g=30,sa=40,ti=76,gs=40,lofi=20|drive:octave|RHYTHM,LEAD',
    'tiesto_adagio_for_strings|Tiësto|Adagio for Strings|Adagio for Strings Guitar|genre.trance_guitar|trance_inspired,cinematic|epic,building,emotional|g=30,su=90,de=42,re=56,mo=22|reverb:hall|LEAD,AMBIENT',
    'deadmau5_strobe|deadmau5|Strobe|Strobe Guitar|genre.trance_guitar|trance_inspired,ambient|progressive,evolving,pulsing|g=26,su=82,de=46,re=44,mo=30|delay:analogWarm|LEAD,AMBIENT,CLEAN',
    'avicii_levels|Avicii|Levels|Levels Guitar|genre.trance_guitar|trance_inspired,eurodance_inspired|uplifting,bright,anthemic|g=38,su=78,tr=68,de=34,re=32|delay:digital|LEAD,CLEAN',
    'swedish_house_mafia_dont_you_worry_child|Swedish House Mafia|Don\'t You Worry Child|Dont You Worry Child|genre.trance_guitar|trance_inspired|anthemic,uplifting,wide|g=34,su=80,de=38,re=42,mo=20|reverb:hall|LEAD,CLEAN',
    'justice_dance|Justice|D.A.N.C.E.|DANCE Justice|genre.house_funk_guitar|house_inspired,industrial_electronic|distorted,funky,bright|g=42,sa=60,mo=20,co=50,tr=64|drive:distortion|RHYTHM,LEAD',
]

# slug|Title|aliases|parent|genres|tags|overrides|kinds|roles|char/extra
ORIGINALS = [
    # --- synthwave / cyber / retro family
    'dark_cyber_lead|Dark Cyber Lead|Dark Cyberpunk Lead|genre.cyberpunk_synth|cyberpunk,synth_like_guitar|dark,cold,lead|g=58,ti=66,tr=46,pr=50,de=34,re=28,dark=80|drive:distortion;delay:digital|LEAD',
    'arcade_lead|Arcade Lead|Retro Arcade Lead|genre.chiptune_guitar|chiptune_inspired,synthwave|arcade,bright,retro,lead|g=48,ti=86,su=60,de=14|drive:octave|LEAD',
    'industrial_machine|Industrial Machine Rhythm|Industrial Machine|style.industrial_electronic_guitar|industrial_electronic,industrial_metal|machine,gated,mechanical|g=64,ti=94,gs=82,mo=14,de=6|drive:distortion|RHYTHM,SPECIAL',
    'trance_gate_guitar|Trance Gate Guitar|Trance Gate|genre.trance_guitar|trance_inspired|gated,pulsing,rhythmic|g=48,ti=72,su=44,gs=70,de=36|delay:digital|RHYTHM,LEAD',
    'acid_inspired_lead|Acid-Inspired Lead|Acid Lead|genre.techno_guitar|techno_inspired|squelchy,resonant,wah-like|g=56,sa=66,mi=66,um=68,su=70,mo=10|drive:wah|LEAD',
    'dreamwave_clean|Dreamwave Clean|Dreamwave|genre.synthwave|synthwave,retrowave|dreamy,chorused,soft|g=10,mo=52,re=56,de=36,tr=52,warmth=60|modulation:chorus;reverb:hall|CLEAN,AMBIENT',
    'night_drive_lead|Night Drive Lead|Night Drive|style.synth_lead|synthwave,retrowave|smooth,neon,sustaining|g=40,su=86,de=38,re=42,mo=28,warmth=55|delay:analogWarm;reverb:hall|LEAD',
    'sci_fi_noir_ambient|Sci-Fi Noir Ambient|Blade Runner Inspired Ambient|genre.cinematic_ambient|cinematic,cyberpunk,ambient|noir,rainy,dark,cinematic|g=8,re=80,de=54,mo=32,tr=34,dark=78|reverb:hall;delay:analogWarm|AMBIENT,SPECIAL',
    'eighties_movie_lead|80s Movie Lead|80er Film Lead,Eighties Movie Lead|genre.synthwave|synthwave,retrowave|heroic,chorused,bright|g=46,su=82,mo=36,de=32,re=34,tr=62|modulation:chorus;delay:digital|LEAD',
    'space_chorus_clean|Space Chorus Clean|Space Clean|genre.ambient_guitar|ambient,synthwave|spacey,chorused,wide|g=10,mo=58,re=58,de=40,width=92|modulation:chorus;reverb:hall|CLEAN,AMBIENT',
    'darkwave_rhythm|Darkwave Rhythm||genre.darkwave|darkwave,post_punk|dark,cold,chorused,driving|g=34,ti=54,mo=34,de=20,re=26,dark=68|modulation:chorus|RHYTHM,CLEAN',
    'synthwave_pulse_rhythm|Synthwave Pulse Rhythm|Synthwave Rhythm|genre.synthwave|synthwave|pulsing,tight,retro|g=40,ti=72,su=44,gs=36,mo=20,de=26|delay:digital|RHYTHM',
    # --- fun / special sounds
    'telephone_guitar|Telephone Guitar|Telefon Gitarre|genre.lo_fi_guitar|lo_fi,experimental|telephone,narrow,midrangey|g=30,ba=8,lm=20,mi=82,um=74,tr=30,pr=40,ir=30,co=60,mo=0,lofi=75,clarity=40|drive:other|SPECIAL,LEAD',
    'radio_guitar|Radio Guitar|Radio Gitarre|genre.lo_fi_guitar|lo_fi,experimental|radio,narrow,midrangey,vintage|g=36,ba=20,lm=36,mi=78,um=70,tr=34,ir=36,lofi=60,re=12|drive:other|SPECIAL,LEAD',
    'underwater_clean|Underwater Clean|Unterwasser Clean|genre.ambient_guitar|ambient,experimental|underwater,dark,wobbly,muffled|g=8,tr=12,pr=8,ir=12,mo=72,re=58,de=30,sp=40,dark=80|modulation:chorus;reverb:hall|CLEAN,AMBIENT,SPECIAL',
    'broken_speaker|Broken Speaker|Kaputter Lautsprecher|genre.lo_fi_guitar|lo_fi,experimental|broken,fuzzy,crackly,lo-fi|g=60,sa=84,ba=20,tr=62,pr=40,ir=60,gs=30,fuzz=75,lofi=92|drive:fuzz|SPECIAL,RHYTHM',
    'eight_bit_inspired|8-Bit Inspired|8 Bit Guitar,Chiptune Guitar|genre.chiptune_guitar|chiptune_inspired|square-ish,arcade,retro,bright|g=52,ti=90,su=48,lofi=78|drive:octave|SPECIAL,LEAD,RHYTHM',
    'horror_ambience|Horror Ambience|Horror Ambient|genre.cinematic_ambient|cinematic,ambient,experimental|horror,dark,eerie,dissonant|g=10,tr=26,pr=20,re=84,de=60,mo=36,sp=60,dark=88|reverb:hall;delay:analogWarm|AMBIENT,SPECIAL',
    'space_ambience|Space Ambience|Space Ambient,Weltraum Ambient|genre.cinematic_ambient|cinematic,ambient|space,vast,floating,wide|g=8,tr=56,re=86,de=66,mo=40,sp=66,width=100|reverb:hall;delay:analogWarm|AMBIENT,SPECIAL',
    'huge_arena_lead|Huge Arena Lead|Arena Lead|genre.hard_rock|hard_rock,instrumental_rock|huge,anthemic,sustaining,big|g=62,su=90,co=34,de=34,re=44,sp=30,tr=60,pr=60|delay:digital;reverb:hall|LEAD,SOLO',
    'tiny_practice_amp|Tiny Practice Amp|Kleiner Übungsverstärker|genre.classic_rock|classic_rock,lo_fi|small,boxy,honky,lo-fi|g=40,sa=44,ba=26,lm=44,mi=62,um=58,tr=50,ir=36,re=0,lofi=40,clarity=45|reverb:room|RHYTHM,LEAD,CLEAN',
    'garage_fuzz|Garage Fuzz|Garagen Fuzz|genre.garage_rock|garage_rock,lo_fi|fuzzy,raw,loose,lo-fi|g=70,sa=84,ti=30,at=40,re=12,fuzz=85,lofi=40|drive:fuzz|RHYTHM,LEAD',
    'doom_wall|Doom Wall|Doom Wand|genre.doom_stoner|doom_metal,sludge_metal|wall,slow,massive,fuzzy|g=78,sa=86,ti=20,ba=74,lm=70,fuzz=75,body=90|drive:fuzz|RHYTHM,SPECIAL',
    'chainsaw_metal|Chainsaw Metal|Kettensäge Metal|genre.death_metal|death_metal,thrash_metal|buzzsaw,brutal,sharp|g=86,sa=88,ti=88,mi=60,um=66,pr=66,tr=62,ba=40,gs=70,aggr=95|drive:boost|RHYTHM',
    'dream_clean|Dream Clean|Traum Clean|genre.shoegaze|shoegaze,clean_pop|dreamy,soft,shimmering|g=10,mo=50,re=62,de=44,tr=54,clarity=60|modulation:chorus;reverb:hall|CLEAN,AMBIENT',
    'cathedral_clean|Cathedral Clean|Kathedralen Clean|genre.ambient_guitar|ambient,post_rock|cathedral,huge-reverb,slow,clean|g=6,re=92,sp=70,de=20,ir=44,tr=40|reverb:hall|CLEAN,AMBIENT',
    'western_tremolo|Western Tremolo|Western Tremolo Gitarre|genre.surf|surf,country|western,tremolo,dusty,vintage|g=16,mo=66,re=38,ir=60,vintage=88,warmth=60|modulation:tremolo;reverb:spring|CLEAN,LEAD,SPECIAL',
    'surf_spring|Surf Spring|Surf Federhall|genre.surf|surf|spring-reverb,splashy,wet|g=20,re=84,mo=26,tr=66|reverb:spring|LEAD,SPECIAL',
    'lo_fi_cassette|Lo-Fi Cassette|Lofi Kassette|genre.lo_fi_guitar|lo_fi,ambient|cassette,tape,wobbly,dusty|g=14,mo=44,ir=26,de=24,lofi=92,dark=50|modulation:chorus;delay:tape|CLEAN,SPECIAL',
    'vhs_wobble|VHS Wobble|VHS Wackeln|genre.lo_fi_guitar|lo_fi,retrowave|vhs,wobbly,retro,warped|g=12,mo=62,de=26,lofi=75,vintage=80|modulation:chorus|CLEAN,SPECIAL',
]


def build():
    C.pack('electronic_reimagined_ext', 'Guitar Reimagined (Erweiterung)',
           'Elektronische Titel als WyrmTone-Gitarreninterpretation; kein Nachbau der Originalklänge.', 'GUITAR_REIMAGINED')
    for row in REIMAGINED:
        slug, artist, title, aliases, parent, genres, tags, ov, kd, roles = [x.strip() for x in row.split('|')]
        C.add(entry('reimagined.%s' % slug, 'GUITAR_REIMAGINED', '%s – %s (Guitar Reimagined)' % (artist, title),
                    'GUITAR_REIMAGINED', 'MEDIUM', artist=artist, song=title, songAliases=lst(aliases), genres=lst(genres),
                    parents=['tpl.' + parent], tags=lst(tags), roles=lst(roles), tone=tone(ov, kd), notes=NOTE_REIM))

    C.pack('wyrm_originals', 'WyrmTone Originals',
           'Eigene WyrmTone-Klangkreationen (Synthwave, Cyber, Retro); keine Referenz auf Originale.', 'WYRM_ORIGINAL')
    fun_from = 'telephone_guitar'
    fun_started = False
    for row in ORIGINALS:
        slug = row.split('|')[0]
        if slug == fun_from and not fun_started:
            C.pack('wyrm_fun_sounds', 'WyrmTone Special- und Fun-Sounds',
                   'Ungewöhnliche WyrmTone-Sounds (Telefon, Unterwasser, Lo-Fi, Horror, Doom Wall, ...); keine Emulation echter Geräte.',
                   'WYRM_ORIGINAL')
            fun_started = True
        _slug, title, aliases, parent, genres, tags, ov, kd, roles = [x.strip() for x in row.split('|')]
        C.add(entry('original.%s' % slug, 'ORIGINAL_WYRMTONE', title, 'WYRM_ORIGINAL', 'MEDIUM', genres=lst(genres),
                    parents=['tpl.' + parent], tags=lst(tags), roles=lst(roles), searchAliases=lst(aliases),
                    tone=tone(ov, kd), notes=NOTE_ORIGINAL))
