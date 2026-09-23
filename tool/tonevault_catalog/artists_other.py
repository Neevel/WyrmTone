"""Blues, funk/soul, country, jazz/fusion, instrumental rock and roots artists."""
from common import C, artist

ROWS = {}

ROWS['blues'] = ('Blues und Blues Rock', 'Blues-, Texas-Blues-, Chicago-Blues- und Blues-Rock-Acts.', [
    'bb_king|B.B. King|BB King|genre.blues_clean|blues|1960s,1970s|singing,vibrato,warm,round|g=22,su=64,tr=46,warmth=80|eStandard',
    'albert_king|Albert King||genre.blues_clean|blues,texas_blues|1960s|biting,bent-notes,vintage|g=34,su=62,mi=62|eStandard',
    'freddie_king|Freddie King||style.texas_blues|texas_blues,blues|1960s|punchy,bright,instrumental|g=32,tr=58|eStandard',
    'buddy_guy|Buddy Guy||style.chicago_blues|chicago_blues,blues_rock|1960s,1990s|raw,dynamic,searing|g=44,at=64,tr=58|eStandard',
    'muddy_waters|Muddy Waters||style.chicago_blues|chicago_blues|1960s|gritty,slide,vintage|g=38,sa=44,lofi=30|eStandard',
    'howlin_wolf|Howlin\' Wolf|Howlin Wolf|style.chicago_blues|chicago_blues|1960s|raw,gritty,vintage|g=40,lofi=30|eStandard',
    'john_lee_hooker|John Lee Hooker||style.chicago_blues|blues,chicago_blues|1960s|droning,raw,minimal|g=36,lofi=30,re=10|eStandard',
    'tbone_walker|T-Bone Walker||genre.blues_clean|blues|1960s|jazzy,warm,clean|g=16,warmth=76|eStandard',
    'stevie_ray_vaughan|Stevie Ray Vaughan|SRV|style.texas_blues|texas_blues,blues_rock|1980s|fat,punchy,singing,spring-reverb|g=44,sa=48,ba=52,su=66,warmth=62|ebStandard',
    'gary_moore|Gary Moore||genre.blues_rock|blues_rock,hard_rock|1980s,1990s|singing,sustaining,thick|g=56,su=84,mi=64|eStandard',
    'joe_bonamassa|Joe Bonamassa|Bonamassa|genre.blues_rock|blues_rock|2000s,2010s|thick,singing,polished|g=50,su=76,warmth=64|eStandard',
    'john_mayer|John Mayer||genre.blues_clean|blues_rock,clean_pop|2000s|smooth,warm,dynamic,clean|g=26,su=64,warmth=74,re=24|eStandard',
    'robert_cray|Robert Cray||genre.blues_clean|blues,soul|1980s|smooth,clean,tight|g=24,at=62,tr=54|eStandard',
    'kenny_wayne_shepherd|Kenny Wayne Shepherd||style.texas_blues|texas_blues,blues_rock|1990s|punchy,vintage,singing|g=44,su=64|eStandard',
    'derek_trucks|Derek Trucks||genre.southern_rock|blues_rock,southern_rock|2000s|slide,singing,warm|g=34,su=84,warmth=70|eStandard',
    'susan_tedeschi|Susan Tedeschi||genre.blues_clean|blues,soul|2000s|warm,soulful,clean|g=26,warmth=72|eStandard',
    'rory_gallagher|Rory Gallagher||genre.blues_rock|blues_rock|1970s|raw,gritty,vintage|g=46,sa=52,lofi=15|eStandard',
    'peter_green|Peter Green||genre.blues_clean|blues,blues_rock|1960s|singing,vibrato,warm|g=30,su=70|eStandard',
    'johnny_winter|Johnny Winter||style.texas_blues|texas_blues,blues_rock|1970s|raw,fiery,gritty|g=48,sa=52|eStandard',
    'warren_haynes|Warren Haynes||genre.southern_rock|blues_rock,southern_rock|1990s,2000s|warm,singing,gritty|g=44,su=74|eStandard',
    'walter_trout|Walter Trout||genre.blues_rock|blues_rock|1990s|thick,singing,intense|g=52,su=76|eStandard',
    'eric_gales|Eric Gales||genre.blues_rock|blues_rock|2000s|fiery,expressive,dynamic|g=50,su=72|eStandard',
    'larkin_poe|Larkin Poe||genre.blues_rock|blues_rock,southern_rock|2010s|slide,gritty,warm|g=46,warmth=62|eStandard',
    'gary_clark_jr|Gary Clark Jr.|Gary Clark Junior|style.texas_blues|texas_blues,blues_rock|2010s|fuzzy,raw,modern|g=52,fuzz=30|eStandard',
    'robben_ford|Robben Ford||genre.blues_clean|blues,fusion|1980s,1990s|smooth,jazzy,warm|g=26,warmth=72,su=66|eStandard',
    'jimmie_vaughan|Jimmie Vaughan||style.texas_blues|texas_blues|1980s|clean,twangy,minimal|g=26,tr=58|eStandard',
    'albert_collins|Albert Collins||style.texas_blues|texas_blues|1970s|icy,biting,twangy|g=30,tr=64,pr=60|eStandard',
    'magic_sam|Magic Sam||style.chicago_blues|chicago_blues|1960s|tremolo-tinged,warm,vintage|g=30,mo=24,warmth=70|eStandard',
    'otis_rush|Otis Rush||style.chicago_blues|chicago_blues|1960s|intense,dark,expressive|g=34,dark=45|eStandard',
    'elmore_james|Elmore James||style.chicago_blues|chicago_blues|1960s|slide,raw,gritty|g=44,sa=50,lofi=25|eStandard',
    'hound_dog_taylor|Hound Dog Taylor||style.chicago_blues|chicago_blues|1970s|raw,slide,dirty|g=50,sa=56,lofi=35|eStandard',
    'junior_wells|Junior Wells||style.chicago_blues|chicago_blues|1960s|raw,vintage,gritty|g=34,lofi=30|eStandard',
    'lightnin_hopkins|Lightnin\' Hopkins|Lightnin Hopkins|style.texas_blues|texas_blues|1960s|raw,minimal,vintage|g=28,lofi=35|eStandard',
    'ana_popovic|Ana Popovic||genre.blues_rock|blues_rock,funk|2000s|funky,warm,dynamic|g=38,warmth=62|eStandard',
])

ROWS['funk_soul'] = ('Funk und Soul', 'Funk-, Soul- und R&B-Gitarrenacts.', [
    'nile_rodgers|Nile Rodgers||genre.funk|funk,soul|1970s,1980s|scratchy,percussive,clean,tight|g=6,co=56,at=82,re=8|eStandard',
    'cory_wong|Cory Wong||genre.funk|funk|2010s|percussive,clean,compressed,tight|g=6,co=54,at=80|eStandard',
    'prince|Prince||genre.funk|funk,soul,classic_rock|1980s|funky,expressive,chorused|g=24,mo=22,at=72|eStandard',
    'curtis_mayfield|Curtis Mayfield||genre.blues_soul_rnb|soul,funk|1970s|clean,wah-tinged,sweet|g=12,warmth=72,mo=14|eStandard',
    'steve_cropper|Steve Cropper||genre.blues_soul_rnb|soul|1960s|twangy,tight,dry|g=12,tr=60,re=10|eStandard',
    'funkadelic|Funkadelic||genre.funk|funk,psychedelic_rock|1970s|fuzzy,psychedelic,heavy-groove|g=44,mo=22,fuzz=40|eStandard',
    'sly_and_the_family_stone|Sly and the Family Stone|Sly Stone|genre.funk|funk,soul|1970s|percussive,clean,groovy|g=10,at=76|eStandard',
    'earth_wind_and_fire|Earth, Wind & Fire|Earth Wind and Fire|genre.funk|funk,soul|1970s|bright,tight,polished|g=8,clarity=84|eStandard',
    'vulfpeck|Vulfpeck||genre.funk|funk|2010s|dry,tight,compressed|g=6,co=56,re=6|eStandard',
    'tower_of_power|Tower of Power||genre.funk|funk,soul|1970s|tight,clean,percussive|g=8,at=80|eStandard',
    'jamiroquai|Jamiroquai||genre.funk|funk,soul|1990s|wah-driven,smooth,groovy|g=10,mo=18|eStandard',
    'lenny_kravitz|Lenny Kravitz||genre.classic_rock|classic_rock,funk|1990s|vintage,warm,fuzzy|g=44,vintage=78,warmth=64|eStandard',
    'john_frusciante|John Frusciante||genre.funk|funk,alternative_rock|1990s,2000s|dynamic,clean-to-fuzz,expressive|g=22,at=72|eStandard',
    'al_green_band|Al Green||genre.blues_soul_rnb|soul|1970s|warm,sparse,clean|g=10,warmth=76|eStandard',
    'motown_funk_brothers|The Funk Brothers|Funk Brothers|genre.blues_soul_rnb|soul|1960s|tight,warm,rhythmic|g=10,warmth=70|eStandard',
    'snarky_puppy|Snarky Puppy||style.jazz_fusion|fusion,funk|2010s|clean,tight,precise|g=8,clarity=84|eStandard',
    'tom_misch|Tom Misch||genre.funk|funk,clean_pop|2010s|smooth,warm,compressed|g=8,warmth=66,co=50|eStandard',
])

ROWS['country'] = ('Country', 'Country- und Americana-Gitarrenacts.', [
    'brad_paisley|Brad Paisley||genre.country|country|2000s|twangy,virtuosic,bright|g=22,at=76,tr=66|eStandard',
    'johnny_cash|Johnny Cash||genre.country|country,rockabilly|1960s|boom-chicka,dry,vintage|g=10,vintage=75,de=16|eStandard',
    'chet_atkins|Chet Atkins||genre.country|country,jazz|1960s|clean,finger-picked,warm|g=6,warmth=66,at=60|eStandard',
    'merle_haggard|Merle Haggard||genre.country|country|1960s,1970s|twangy,dry,vintage|g=14,vintage=72|eStandard',
    'brent_mason|Brent Mason||genre.country|country|1990s|twangy,snappy,studio|g=20,at=78,co=50|eStandard',
    'keith_urban|Keith Urban||genre.country|country|2000s|bright,delay-driven,modern|g=28,de=26,tr=66|eStandard',
    'vince_gill|Vince Gill||genre.country|country|1990s|clean,twangy,smooth|g=14,at=70,warmth=54|eStandard',
    'albert_lee|Albert Lee||genre.country|country,rockabilly|1970s|fast,twangy,dry|g=16,at=78|eStandard',
    'james_burton|James Burton||genre.country|country,rockabilly|1960s|twangy,snappy,vintage|g=14,at=78,vintage=78|eStandard',
    'buck_owens|Buck Owens||genre.country|country|1960s|bright,twangy,vintage|g=14,tr=66,vintage=78|eStandard',
    'waylon_jennings|Waylon Jennings||genre.country|country|1970s|dry,twangy,warm|g=16,warmth=58|eStandard',
    'chris_stapleton|Chris Stapleton||genre.country|country,blues_rock|2010s|warm,gritty,dynamic|g=34,warmth=64|eStandard',
    'zac_brown_band|Zac Brown Band||genre.country|country,southern_rock|2000s|warm,clean,layered|g=22,warmth=56|eStandard',
    'jerry_reed|Jerry Reed||genre.country|country|1970s|finger-picked,snappy,dry|g=8,at=76|eStandard',
    'marty_stuart|Marty Stuart||genre.country|country,rockabilly|1990s|twangy,bright,vintage|g=16,vintage=72|eStandard',
    'dwight_yoakam|Dwight Yoakam||genre.country|country|1980s|twangy,dry,bright|g=16,tr=66|eStandard',
])

ROWS['jazz_fusion'] = ('Jazz und Jazz Fusion', 'Jazz-, Fusion- und Instrumental-Gitarrenacts.', [
    'wes_montgomery|Wes Montgomery||genre.jazz_guitar|jazz|1960s|warm,round,octave-melodies|g=4,warmth=88,tr=24|eStandard',
    'george_benson|George Benson||genre.jazz_guitar|jazz,soul|1970s|smooth,warm,fluid|g=6,warmth=80,su=60|eStandard',
    'pat_metheny|Pat Metheny||style.jazz_fusion|fusion,jazz|1980s|warm,singing,chorused|g=22,mo=26,de=20,warmth=68|eStandard',
    'john_scofield|John Scofield||style.jazz_fusion|fusion,jazz|1980s|dirty-jazz,funky,dynamic|g=32,sa=36,mi=58|eStandard',
    'joe_pass|Joe Pass||genre.jazz_guitar|jazz|1970s|warm,clean,articulate|g=4,warmth=84|eStandard',
    'kenny_burrell|Kenny Burrell||genre.jazz_guitar|jazz|1960s|warm,round,bluesy|g=4,warmth=86|eStandard',
    'grant_green|Grant Green||genre.jazz_guitar|jazz,soul|1960s|warm,single-note,soulful|g=4,warmth=82|eStandard',
    'jim_hall|Jim Hall||genre.jazz_guitar|jazz|1960s|warm,subtle,dark|g=4,dark=62|eStandard',
    'charlie_christian|Charlie Christian||genre.jazz_guitar|jazz|1960s|warm,vintage,horn-like|g=6,vintage=88,lofi=25|eStandard',
    'bill_frisell|Bill Frisell||genre.jazz_guitar|jazz,fusion,country|1990s|atmospheric,twangy,delay-tinged|g=10,de=30,re=32,mo=16|eStandard',
    'julian_lage|Julian Lage||genre.jazz_guitar|jazz,country|2010s|articulate,warm,dynamic|g=8,tr=42|eStandard',
    'mike_stern|Mike Stern||style.jazz_fusion|fusion,jazz|1980s|chorused,singing,driving|g=32,mo=30,su=74|eStandard',
    'larry_carlton|Larry Carlton||style.jazz_fusion|fusion,jazz|1970s,1980s|warm,singing,smooth|g=24,su=70,warmth=72|eStandard',
    'lee_ritenour|Lee Ritenour||style.jazz_fusion|fusion,jazz|1980s|smooth,polished,clear|g=16,clarity=80|eStandard',
    'al_di_meola|Al Di Meola||style.jazz_fusion|fusion|1970s,1980s|fast,precise,bright|g=34,ti=60,tr=60|eStandard',
    'john_mclaughlin|John McLaughlin||style.jazz_fusion|fusion|1970s|fiery,fast,intense|g=44,su=78,ti=56|eStandard',
    'allan_holdsworth|Allan Holdsworth||style.jazz_fusion|fusion,progressive_rock|1980s|legato,singing,synth-like|g=40,su=90,de=20,mo=20|eStandard',
    'scott_henderson|Scott Henderson||style.jazz_fusion|fusion,blues_rock|1990s|fiery,bluesy,expressive|g=42,su=78|eStandard',
    'pat_martino|Pat Martino||genre.jazz_guitar|jazz|1970s|articulate,warm,fast|g=4,warmth=80|eStandard',
    'jeff_beck|Jeff Beck||style.jazz_fusion|fusion,blues_rock,classic_rock|1970s,2000s|expressive,whammy,dynamic|g=38,su=76,warmth=60|eStandard',
    'guthrie_govan|Guthrie Govan||style.jazz_fusion|fusion,progressive_rock|2000s|versatile,articulate,fluid|g=38,su=76,clarity=78|eStandard',
])

ROWS['instrumental_shred'] = ('Instrumental Rock und Shred', 'Instrumentale Gitarrenacts und Virtuosen.', [
    'joe_satriani|Joe Satriani|Satriani|genre.instrumental_rock|instrumental_rock,hard_rock|1980s,1990s|singing,sustaining,smooth,melodic|g=64,su=88,mi=62,de=20|eStandard',
    'steve_vai|Steve Vai||genre.instrumental_rock|instrumental_rock,hard_rock|1980s,1990s|expressive,sustaining,wide|g=66,su=90,mo=18,de=24|eStandard',
    'eric_johnson|Eric Johnson||genre.instrumental_rock|instrumental_rock,blues_rock|1990s|singing,warm,layered|g=48,su=84,warmth=66,de=26|eStandard',
    'yngwie_malmsteen|Yngwie Malmsteen|Yngwie|genre.instrumental_rock|instrumental_rock,heavy_metal|1980s|neoclassical,fast,scalloped|g=68,ti=66,su=84,tr=62|eStandard',
    'paul_gilbert|Paul Gilbert||genre.instrumental_rock|instrumental_rock,hard_rock|1980s,1990s|fast,precise,bright|g=60,ti=64,su=78|eStandard',
    'jason_becker|Jason Becker||genre.instrumental_rock|instrumental_rock,heavy_metal|1980s|neoclassical,fast,melodic|g=64,su=84|eStandard',
    'marty_friedman|Marty Friedman||genre.instrumental_rock|instrumental_rock,heavy_metal|1990s|exotic,melodic,expressive|g=62,su=82|eStandard',
    'zakk_wylde|Zakk Wylde||genre.hard_rock|heavy_metal,southern_rock|1990s,2000s|pinch-harmonics,thick,aggressive|g=66,mi=62,su=76|dStandard,eStandard',
    'randy_rhoads|Randy Rhoads||genre.instrumental_rock|heavy_metal,instrumental_rock|1980s|neoclassical,singing,tight|g=58,su=78,ti=62|eStandard',
    'dimebag_darrell|Dimebag Darrell|Dimebag|genre.groove_metal|groove_metal,heavy_metal|1990s|scooped,sharp,whammy|g=72,ti=78,mi=38|dStandard',
    'kirk_hammett|Kirk Hammett||genre.thrash_metal|thrash_metal,heavy_metal|1980s,1990s|wah-driven,expressive,bluesy-leads|g=68,su=70|eStandard',
    'steve_morse|Steve Morse||genre.instrumental_rock|instrumental_rock,progressive_rock|1980s|precise,country-tinged,fluid|g=52,su=78,clarity=76|eStandard',
    'vinnie_moore|Vinnie Moore||genre.instrumental_rock|instrumental_rock,heavy_metal|1980s|neoclassical,fast,precise|g=62,su=80|eStandard',
    'tony_macalpine|Tony MacAlpine||genre.instrumental_rock|instrumental_rock|1980s|neoclassical,fast,clear|g=60,su=80|eStandard',
    'michael_romeo|Michael Romeo||style.progressive_metal|progressive_metal,power_metal|1990s|neoclassical,heavy,precise|g=64,ti=76|eStandard',
    'frank_zappa|Frank Zappa||genre.instrumental_rock|instrumental_rock,progressive_rock|1970s|experimental,singing,wah-driven|g=44,su=82,mi=60|eStandard',
    'brian_may|Brian May||genre.classic_rock|classic_rock,hard_rock|1970s|singing,layered,harmonized|g=50,su=80,warmth=62|eStandard',
    'david_gilmour|David Gilmour||genre.progressive_rock|progressive_rock,blues_rock|1970s|singing,expressive,spacious|g=42,su=84,de=32,re=34|eStandard',
    'mark_knopfler|Mark Knopfler||genre.blues_rock|classic_rock,blues_rock|1980s|fingerstyle,clean-crunch,articulate|g=22,at=70,clarity=82|eStandard',
])

ROWS['roots_surf_rockabilly'] = ('Surf, Rockabilly und Roots', 'Surf-, Rockabilly- und Roots-Gitarrenacts.', [
    'dick_dale|Dick Dale||genre.surf|surf|1960s|fast,reverb-drenched,tremolo-picking|g=26,re=76,mo=24|eStandard',
    'the_ventures|The Ventures||genre.surf|surf|1960s|twangy,clean,bright|g=18,re=60|eStandard',
    'the_surfaris|The Surfaris||genre.surf|surf|1960s|bright,twangy,splashy|g=22,re=64|eStandard',
    'the_shadows|The Shadows||genre.surf|surf,rockabilly|1960s|echoey,melodic,twangy|g=14,de=30,re=48|eStandard',
    'link_wray|Link Wray||genre.garage_rock|garage_rock,rockabilly|1960s|fuzzy,raw,menacing|g=60,sa=66,fuzz=55,lofi=30|eStandard',
    'brian_setzer|Brian Setzer||genre.rockabilly|rockabilly|1980s|slapback,twangy,driving|g=26,de=34|eStandard',
    'stray_cats|Stray Cats||genre.rockabilly|rockabilly|1980s|slapback,twangy,bright|g=24,de=34|eStandard',
    'carl_perkins|Carl Perkins||genre.rockabilly|rockabilly,country|1960s|slapback,twangy,vintage|g=20,de=32,vintage=90|eStandard',
    'scotty_moore|Scotty Moore||genre.rockabilly|rockabilly|1960s|slapback,twangy,vintage|g=18,de=34,vintage=92|eStandard',
    'duane_eddy|Duane Eddy||genre.surf|surf,rockabilly|1960s|twangy,low-string-melody,reverb-soaked|g=16,ba=52,re=60|eStandard',
    'chris_isaak|Chris Isaak||genre.rockabilly|rockabilly,classic_rock|1990s|dreamy,tremolo-tinged,warm|g=18,mo=26,re=40|eStandard',
    'reverend_horton_heat|Reverend Horton Heat||genre.rockabilly|rockabilly,punk_rock|1990s|fast,twangy,driving|g=34,de=28|eStandard',
])


def build():
    for pack, spec in ROWS.items():
        name, desc, rows = spec
        C.pack(pack, name, desc, 'STYLE_INSPIRED')
        for row in rows:
            if row:
                artist(row)
