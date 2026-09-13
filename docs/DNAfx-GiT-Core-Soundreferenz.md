# Harley Benton DNAfx GiT Core – Soundreferenz

Stand: 1. September 2026

Diese Referenz ist die feste Grundlage für zukünftige Sound-Vorschläge. Verwendet werden ausschließlich Modelle und Parameter, die im DNAfx GiT Core beziehungsweise im reverse-engineerten Presetformat nachgewiesen sind.

## 1. Signalweg und Presetformat

Feste Blockreihenfolge:

`FX/COMP → DS/OD → AMP → CAB → NS GATE → EQ → MOD → DELAY → REVERB`

Jeder Block besitzt `SWITCH` (an/aus), `TYPE` (Modell-ID) und `Data` (Parameterwerte). Ein Preset kann alle neun Blöcke gleichzeitig verwenden. Das offizielle `.phb`-Format ist JSON; das Geräteformat `.bhb` umfasst nach aktuellem Reverse Engineering 184 Byte. Der Open-Source-Editor kann 200 Presets sichern und zwischen beiden Formaten konvertieren.

Wichtig: `effects.h` bestätigt Namen und Reihenfolge der Parameter, dokumentiert aber nicht für jeden Regler die angezeigte Einheit oder den gültigen Wertebereich. Klangvorschläge werden deshalb zunächst in den am Gerät üblichen Einstellwerten formuliert. Spezialwerte wie Pitch-Intervalle, Mikrofontypen und Delay-Unterteilungen müssen vor einer automatisch erzeugten `.phb` einmal mit einem echten Export aus dem offiziellen Editor des jeweiligen Geräts abgeglichen werden.

## 2. Vollständige Modellübersicht

### FX/COMP (8)

| ID | Modell | Parameter |
|---:|---|---|
| 0 | CRY WAH | Q, POSITION, PEAK, LEVEL |
| 1 | 535 WAH | Q, POSITION, PEAK, LEVEL |
| 2 | AUTO WAH | RATE, RANGE, PEAK, LEVEL |
| 3 | TALK WAH AH | RATE, RANGE, PEAK, LEVEL |
| 4 | TOUCH WAH | RATE, RANGE, PEAK, LEVEL |
| 5 | TOUCH WAH ENVELOPE | ATTACK, SENS, PEAK, LEVEL |
| 6 | YELLOW COMP | ATTACK, THRES, RATIO, LEVEL |
| 7 | BLUE COMP | ATTACK, THRES, RATIO, LEVEL |

### DS/OD (20)

Alle Modelle besitzen `VOLUME`, `TONE`, `GAIN`.

| ID | Modell | ID | Modell |
|---:|---|---:|---|
| 0 | TUBE DR | 10 | OBSESSIVE DIST |
| 1 | 808 | 11 | JIMMY OD |
| 2 | PURE BOOST | 12 | FULL DRV |
| 3 | FLEX BOOST | 13 | SHRED |
| 4 | DDRIVE | 14 | BeeBee PRE |
| 5 | BLACKRAT | 15 | BeeBee + |
| 6 | GREY FAZE | 16 | RIET |
| 7 | MUFFY | 17 | TIGHT DS |
| 8 | MTL ZONE | 18 | FULL DS |
| 9 | MTL MASTER | 19 | GOLD CLON |

### AMP (55)

Alle Ampmodelle besitzen `GAIN`, `BASS`, `MID`, `TREBLE`, `PRES`, `MST`.

| ID | Modell | ID | Modell | ID | Modell |
|---:|---|---:|---|---:|---|
| 0 | 65US DX | 19 | TRI REC CL | 38 | REGAL TONE Od1 |
| 1 | 65 USTW | 20 | TRI REC DS | 39 | REGAL TONE Od2 |
| 2 | 59 US BASS | 21 | ROCK VRB CL | 40 | CAROL CL |
| 3 | US SONIC | 22 | ROCK VRB DS | 41 | CAROL DS |
| 4 | US BLUES CL | 23 | CITRUS 30 | 42 | CARDEEF |
| 5 | US BLUES OD | 24 | CITRUS 50 | 43 | Ev5050 CL |
| 6 | J800 | 25 | SLOW 100 CR | 44 | Ev5050 DS |
| 7 | J900 | 26 | SLOW 100 DS | 45 | HT CLUB CL |
| 8 | PLX 100 | 27 | DR.ZEE 18 JR | 46 | HT CLUB DS |
| 9 | E650 CL | 28 | DR.ZEE | 47 | HUGEN CL |
| 10 | E650 DS | 29 | JET100H CL | 48 | HUGEN OD |
| 11 | POWERBELL CL | 30 | JET100H OD | 49 | HUGEN DS |
| 12 | POWERBELL DS | 31 | JAZZ 120 | 50 | KOCHE OD |
| 13 | BLACKNIGHT CL | 32 | UK30 CL | 51 | KOCHE DS |
| 14 | BLACKNIGHT DS | 33 | UK30 DS | 52 | ACOUSTIC 1 |
| 15 | MARKIII CL | 34 | HWT103 | 53 | ACOUSTIC 2 |
| 16 | MARKIII DS | 35 | Pv5050 CL | 54 | ACOUSTIC 3 |
| 17 | MARKV CL | 36 | Pv5050 DS |  |  |
| 18 | MARKV DS | 37 | REGAL TONE CL |  |  |

### CAB / IR

Die 26 Werks-Cabs besitzen `TUBE`, `MIC`, `CENTER`, `DISTANCE`. Die zehn Custom-IR-Slots besitzen laut Projekt nur `TUBE` als Presetparameter.

| ID | Werks-Cab | ID | Werks-Cab |
|---:|---|---:|---|
| 0 | US DLX112 | 13 | DRZEE 112 |
| 1 | US TWN 212 | 14 | DRZEE 212 |
| 2 | US BASS 410 | 15 | JAZZ 212 |
| 3 | SONIC 112 | 16 | UK 212 |
| 4 | BLUES 112 | 17 | HW T412 |
| 5 | 1960 412 | 18 | PV 5050 412 |
| 6 | EAGLE P412 | 19 | REGAL TONE 110 |
| 7 | EAGLE S412 | 20 | TWO STONES 212 |
| 8 | MARK 112 | 21 | CARDEFF 112 |
| 9 | REC 412 | 22 | EV 5050 412 |
| 10 | CITRUS 412 | 23 | HT 412 |
| 11 | CITRUS 212 | 24 | GAS STATION 412 |
| 12 | SLOW 412 | 25 | ACOUSTIC 112 |

Custom IR 1–10 liegen auf den IDs 26–35.

### Geprüfte Custom-IR-Sammlung

Die Sammlung **„Best & Biggest IR Files Collection – from AC/DC to Arch Enemy“** wurde vollständig technisch geprüft. Dieser Abschnitt richtet sich an alle, die dieselbe Sammlung heruntergeladen haben:

- 205 WAV-Dateien insgesamt
- 204 Dateien: 44,1 kHz, 24 Bit, Mono
- 1 Datei: 44,1 kHz, 24 Bit, Stereo (`EDGE -1 I Inch ala Sneap pic.wav`)
- Länge: etwa 17 ms bis 1,46 Sekunden
- drei inhaltsgleiche Dateipaare mit unterschiedlich geschriebenen Namen

Damit besitzen 204 Dateien das für den DNAfx Core besonders passende Grundformat. Ob der offizielle Editor sehr lange Dateien beim Import selbst kürzt, muss beim ersten Upload beobachtet werden. Die einzelne Stereo-Datei wird zunächst nicht verwendet.

Die Namen deuten überwiegend auf albumbezogene Tone-Matching-IRs statt auf lückenlos dokumentierte Messungen bestimmter Boxen, Lautsprecher, Mikrofone und Positionen hin. Ein Band- oder Albumname belegt deshalb nicht die tatsächlich verwendete Hardware.

#### Vorauswahl für CKY

| Priorität | Datei | Erwarteter Einsatz |
|---:|---|---|
| 1 | `Splawn Quick Rod.wav` | Marshall-artiger, druckvoller Rock-Grundcharakter; erste Wahl mit J900 |
| 2 | `Limp Bizkit Significant Other.wav` | dichter Alternative-/Nu-Metal-Sound der späten 1990er; stilistisch und zeitlich nah |
| 3 | `DownNola.wav` | dunkler, rauer und mittiger; Alternative bei zu scharfem Grundsound |
| 4 | `System of a Down Toxicity.wav` | aggressiver, definierter Alternative-Metal-Vergleich |
| 5 | `GodsmackTheOracle.wav` | kräftiger moderner Hard-Rock-Vergleich |

Weitere brauchbare Vergleichsdateien sind `Papa roach Getting away with murder.wav`, `StoneSourHouseOfGoldAndBones.wav`, `Black label Society order of the Black.wav` und `GreenDayDookie.wav`. Die ausdrücklich als `Celestion V30 SM7B` bezeichneten Dateien dürften dunkler und moderner wirken und sind deshalb für CKY zunächst nur zweite Wahl.

Empfohlener Hörvergleich: Amp-, Drive-, EQ- und Pitch-Einstellungen unverändert lassen und ausschließlich nacheinander `Splawn Quick Rod`, `Limp Bizkit Significant Other` und `DownNola` im selben Custom-IR-Slot vergleichen. Nur so lässt sich der Einfluss der IR zuverlässig beurteilen.

### NS GATE (3)

| ID | Modell | Parameter |
|---:|---|---|
| 0 | NOISE KILLER | THRES |
| 1 | INTEL REDUCER | SENS |
| 2 | NOISE GATE | ATTACK, RELEASE, THRES |

#### Besonderheit der Noise-Gate-Kodierung

Beim DNAfx GiT Core darf `ATTACK` nicht wie ein gewöhnlicher, direkt angezeigter Zeitwert interpretiert werden. Die `.phb`-Rohwerte verhalten sich praktisch umgekehrt: Ein hoher Wert entspricht einer kurzen Attack-Zeit und lässt das Gate schnell öffnen; ein niedriger Wert kann Anschlag und Nutzsignal deutlich stärker abschneiden.

- `ATTACK 90`: sehr schnelles Öffnen, typischer Metal-Ausgangspunkt
- `ATTACK 80`: schnelles Öffnen mit etwas stärkerer Bedämpfung; am Gerät mit dem CKY-Preset positiv hörgeprüft
- `ATTACK 10`: sehr langsames Öffnen und deshalb Gefahr, große Teile des Anschlags beziehungsweise Signals zu verschlucken

Als Startbereich für straffe Metal-Sounds gelten `ATTACK 80–90`, `RELEASE 70–85` und `THRES 35–50`. Der passende Threshold hängt weiterhin von Gitarre, Pickups, Gain und Nebengeräuschpegel ab. Diese Interpretation wird durch die am Gerät positiv getestete CKY-v2 (`80/80/40`) und das offizielle Werks-Preset `US REC` (`88/85/50`) gestützt.

### EQ (4)

| ID | Modell | Parameter |
|---:|---|---|
| 0 | GUITAR EQ | 100 Hz, 250 Hz, 630 Hz, 1.6 kHz, 4 kHz |
| 1 | METAL EQ | 80 Hz, 240 Hz, 750 Hz, 2.2 kHz, 6.6 kHz |
| 2 | 6BAND EQ | 100 Hz, 200 Hz, 400 Hz, 800 Hz, 1.6 kHz, 3.2 kHz |
| 3 | CUSTOM EQ | GAIN1, 100 Hz, GAIN2, 600 Hz, GAIN3, 1250 Hz |

### MOD (19)

| ID | Modell | Parameter |
|---:|---|---|
| 0 | PHASER | RATE, LEVEL, DEPTH |
| 1 | STEP PHASER | RATE, LEVEL, DEPTH |
| 2 | FAT PHASER | RATE, LEVEL, DEPTH |
| 3 | FLANGER | RATE, MIX, F.BACK |
| 4 | JET-FLANGER | RATE, MIX, F.BACK |
| 5 | TREMOLO | RATE, MIX, TONE |
| 6 | STUTTER | RATE, MIX, TONE |
| 7 | VIBRATO | RATE, DEPTH, TONE |
| 8 | PITCH SHIFT | PITCH, MIX, TONE |
| 9 | DETUNE | PITCH, MIX, TONE |
| 10 | ROTARY | RATE, MIX, TONE |
| 11 | ANA-CHORUS | RATE, MIX, TONE, DEPTH |
| 12 | TRI-CHORUS | RATE, MIX, TONE, DEPTH |
| 13 | RING MOD | RATE, MIX, TONE |
| 14 | Q-FILTER | RATE, MIX, Q |
| 15 | HIGH PASS | RATE, MIX, RANGE |
| 16 | LOW PASS | RATE, MIX, RANGE |
| 17 | SLOW GEAR | RISE, LEVEL |
| 18 | LOFI | SAMPLE, MIX, BIT |

### DELAY (9)

| ID | Modell | Parameter |
|---:|---|---|
| 0 | DIGITAL | LEVEL, F.BACK, TIME, SUB-D |
| 1 | ANALOG | LEVEL, F.BACK, TIME, SUB-D |
| 2 | DYNAMIC | LEVEL, F.BACK, TIME, SUB-D |
| 3 | REAL | LEVEL, F.BACK, TIME, SUB-D |
| 4 | TAPE | LEVEL, F.BACK, TIME, SUB-D |
| 5 | MOD | LEVEL, F.BACK, TIME, SUB-D |
| 6 | REVERSE | LEVEL, F.BACK, TIME, SUB-D |
| 7 | DUAL DELAY 2 | LEVEL, F.BACK, TIME, SUB-D, THRES |
| 8 | PINGPONG | LEVEL, F.BACK, TIME A, SUB A, TIME B, SUB B |

### REVERB (7)

Alle Modelle besitzen `P.DELAY`, `LEVEL`, `DECAY`, `TONE`.

| ID | Modell | ID | Modell |
|---:|---|---:|---|
| 0 | ROOM | 4 | SPRING |
| 1 | HALL | 5 | MOD |
| 2 | CHURCH | 6 | CAVE |
| 3 | PLATE |  |  |

## 3. Schema für zukünftige Sound-Aufträge

Jeder Vorschlag nennt:

1. Gitarre, Pickup, Stimmung und Wiedergabeweg.
2. Jeden der neun Blöcke mit `AN/AUS`, Modell und allen Parametern.
3. Eine kurze Begründung der klangentscheidenden Bausteine.
4. Zwei bis drei gezielte Korrekturen für zu dumpf, zu scharf, zu matschig oder zu dünn.
5. Den Status: Startpunkt nach Quellenlage oder am Gerät/Editor verifiziert.

## 4. Erstes Referenz-Preset: CKY – „96 Quite Bitter Beings“

Status: **am DNAfx GiT Core hörgeprüft; die überarbeitete v2 wurde vom Anwender als extrem gut klingend bestätigt**.

Klangentscheidend ist der deutlich beigemischte Suboktavton. Für Deron Millers frühen CKY-Sound wird ein Boss OC-2 als wesentlicher Baustein genannt; außerdem ist ein Marshall JCM2000 dokumentiert. Da der DNAfx weder OC-2 noch JCM2000 wörtlich modelliert, werden `PITCH SHIFT` (eine Oktave abwärts) und `J900` als nächstliegende interne Bausteine verwendet. Ein Mesa/Rectifier-artiger Alternativansatz ist `TRI REC DS`.

| Block | Status | Modell | Startwerte |
|---|---|---|---|
| FX/COMP | Aus | – | – |
| DS/OD | An | 808 | VOLUME 62, TONE 44, GAIN 12 |
| AMP | An | J900 | GAIN 58, BASS 60, MID 68, TREBLE 56, PRES 38, MST 80 |
| CAB | An | 1960 412 / später Custom IR | `.phb`: TUBE 1, MIC 6, CENTER 10, DISTANCE 50; erster Custom-Test: `Splawn Quick Rod.wav` |
| NS GATE | An | NOISE GATE | ATTACK 80, RELEASE 80, THRES 40 |
| EQ | An | GUITAR EQ | 100 Hz +1, 250 Hz −1, 630 Hz +2, 1.6 kHz +2, 4 kHz −1 |
| MOD | An | PITCH SHIFT | PITCH −12 Halbtöne (`.phb`: `PITCH: 0`), MIX 42, TONE 38 |
| DELAY | Aus | – | – |
| REVERB | An | ROOM | P.DELAY 8, LEVEL 10, DECAY 18, TONE 42 |

Spielhinweise: Halstonabstimmung (Eb), zunächst Bridge-Humbucker. Wenn die Oktave schlecht oder unruhig trackt, Hals-Pickup testen, Gitarrenton etwas zurücknehmen und möglichst sauber/einstimmig spielen. Für Akkordpassagen kann der Pitch-Block ausgeschaltet oder sein Mix deutlich reduziert werden.

Feinabstimmung:

- Zu matschig: Pitch MIX auf 32–36, AMP BASS zunächst auf 52–55 und 250 Hz weiter absenken.
- Zu dünn: Pitch MIX auf 46, 100 Hz leicht anheben und AMP MID nicht reduzieren.
- Zu scharf/zischelig: PRES zuerst auf 30, danach TREBLE auf 52; den Gate-Threshold nicht unnötig hoch einstellen.
- Zu wenig Biss: 808 TONE auf 50 oder AMP MID auf 72, nicht einfach mehr Gain geben.
- Interne und Custom-IR vergleichen: zuerst `1960 412`, dann `Splawn Quick Rod`, `Limp Bizkit Significant Other` und `DownNola`; alle anderen Werte unverändert lassen.

## 5. Durch offizielle `.phb`-Exporte verifiziert

Die Presetstruktur wurde anhand von 19 unterschiedlichen, mit dem offiziellen DNAfx GiT Core Editor V1.0.0 exportierten Werks-Presets geprüft. Alle Dateien sind valides JSON und verwenden übereinstimmend das Schema `HB100 Preset`, das Gerät `HB100` und dieselben neun Effektblöcke.

### Sicher bestätigte Kodierung

| Feld/Parameter | Bestätigte Bedeutung |
|---|---|
| `fileInfo.preset_name` | Presetname; Werksnamen können mit Leerzeichen auf feste Länge aufgefüllt sein |
| `effectModule.<BLOCK>.SWITCH` | `0` = Block aus, `1` = Block an |
| `effectModule.<BLOCK>.TYPE` | Nullbasierte Modell-ID entsprechend den Modelltabellen dieser Referenz |
| AMP: `GAIN`, `BASS`, `MID`, `TREBLE`, `PRES`, `MST` | Direkte Werte von 0–100 |
| DS/OD sowie die meisten Pegel-/Klangregler | Direkte Werte von 0–100 |
| CAB: `CENTER`, `DISTANCE` | Direkte Werte von 0–100 |
| DELAY: `TIME`, `TIME A`, `TIME B` | Millisekunden; in den Exporten wurden 240–1000 ms beobachtet |
| EQ-Bänder | Rohwert `16` ist neutral; Werte darunter senken und Werte darüber heben das Band an |
| Expression Volume | `VOL_MIN` und `VOL_MAX` als direkte Werte von 0–100 |

Jedes Preset enthält außerdem den vollständigen `Exp`-Block mit `MODULE_CTRL`, `PARA_CTRL`, `FUN_SWITCH`, `VOL_SWITCH`, `VOL_MIN` und `VOL_MAX`.

### Beobachtete Auswahl- und Spezialwerte

| Parameter | In den 19 Exporten beobachtet | Noch offen |
|---|---|---|
| CAB `TUBE` | IDs 0–4 | Zuordnung der IDs zu den Röhrentypen der Oberfläche |
| CAB `MIC` | IDs 0–6 | Zuordnung der IDs zu den Mikrofonmodellen |
| DELAY `SUB-D` | IDs 1–5 | Zuordnung zu den rhythmischen Unterteilungen |
| PITCH SHIFT `PITCH` | Rohwerte 0 und 240 | `0` ist durch einen gezielten Export eindeutig als −12 Halbtöne bestätigt; Bedeutung von `240` noch nicht zugeordnet |
| DETUNE `PITCH` | Rohwert 275 | Zuordnung zum angezeigten Detune-Wert |

Damit können strukturell gültige `.phb`-Dateien zuverlässig aus einem offiziellen Export abgeleitet werden. Die für CKY entscheidende Suboktave wurde zusätzlich mit dem gezielten Export `CKY.phb` verifiziert: MOD `TYPE: 8` (`PITCH SHIFT`), `SWITCH: 1`, `PITCH: 0` (−12 Halbtöne), `MIX: 50` und im gelieferten Testexport `TONE: 56`.

Offizielle Downloads:

- [DNAfx GiT Core – Produktseite mit Downloads](https://harleybenton.com/product/dnafx-git-core/)
- [DNAfx GiT Core Editor und Firmware für Windows](https://images.static-thomann.de/pics/atg/atgdata/file/misc/578764_dnafx_git_core_v1.0.0_win_setup.exe.zip)

Nach der Installation das DNAfx per USB verbinden, ein beliebiges Preset im Editor öffnen und als `.phb` exportieren. Vor Änderungen am Gerät empfiehlt sich eine Sicherung der vorhandenen Presets.

## 6. Vollständiger Katalog der 205 IR-Dateien

Alle Einträge stammen aus der geprüften Sammlung. Soweit nicht anders markiert, sind sie WAV, 44,1 kHz, 24 Bit und Mono. Die Dauer ist auf Millisekunden gerundet. Sie beschreibt nur die Länge der Datei, nicht automatisch ihre Qualität.

| Nr. | Dateiname | Kanäle | Dauer | Hinweis |
|---:|---|---:|---:|---|
| 1 | `5150 Preamp.wav` | Mono | 1000.0 ms | – |
| 2 | `Adgar Tiempos de cambio.wav` | Mono | 351.5 ms | – |
| 3 | `Angeles del infierno Diabolicca.wav` | Mono | 1010.9 ms | – |
| 4 | `Angelus Apatrida Clockwork.wav` | Mono | 168.2 ms | – |
| 5 | `Angelus apatrida The call.wav` | Mono | 614.9 ms | – |
| 6 | `AnnihilatorFeast.wav` | Mono | 453.3 ms | – |
| 7 | `Anthrax Spreading The Disease.wav` | Mono | 452.5 ms | – |
| 8 | `archenemy rise of the tyrant.wav` | Mono | 250.0 ms | – |
| 9 | `ArchEnemyDoomsdayMachine.wav` | Mono | 244.7 ms | – |
| 10 | `ArchenemyRiseOfTheTyrant.wav` | Mono | 396.8 ms | – |
| 11 | `AsILayDyingAwakened.wav` | Mono | 93.6 ms | – |
| 12 | `Asking Alexandria From death to destiny.wav` | Mono | 403.8 ms | – |
| 13 | `AskingAlexandriaFromDeathToDestiny.wav` | Mono | 250.0 ms | – |
| 14 | `AskingAlexandriaStandUpAndScream.wav` | Mono | 83.8 ms | – |
| 15 | `Attack Attack Celestion V30 SM7B (1).wav` | Mono | 1000.0 ms | – |
| 16 | `AtTheGatesSlaughterOfTheSoul.wav` | Mono | 250.0 ms | – |
| 17 | `Avalanch Los poetas han muerto.wav` | Mono | 210.0 ms | – |
| 18 | `Avenged Sevenfold Hail to the king.wav` | Mono | 265.1 ms | – |
| 19 | `AvengedSevenfoldHailToTheKing.wav` | Mono | 250.0 ms | – |
| 20 | `AvengedSevenfoldNightmare.wav` | Mono | 159.8 ms | – |
| 21 | `Avulsed Gorespattered suicide.wav` | Mono | 265.6 ms | – |
| 22 | `Axhom Galaxy.wav` | Mono | 394.4 ms | – |
| 23 | `AxhomArchalien.wav` | Mono | 250.0 ms | – |
| 24 | `BattlecrossWarOfWill.wav` | Mono | 250.0 ms | – |
| 25 | `BelphegorBondageGoatZombie.wav` | Mono | 103.9 ms | – |
| 26 | `BestpluginsPunk.wav` | Mono | 250.0 ms | – |
| 27 | `Black dahlia murder Deflorate.wav` | Mono | 219.8 ms | – |
| 28 | `Black label Society order of the Black.wav` | Mono | 191.7 ms | – |
| 29 | `Blackat Leon S7.wav` | Mono | 63.1 ms | – |
| 30 | `BlackKeysElCamino.wav` | Mono | 250.0 ms | – |
| 31 | `Blink182DudeRanch.wav` | Mono | 250.0 ms | – |
| 32 | `Born of Osiris Tomorrow We Die Alive.wav` | Mono | 393.8 ms | – |
| 33 | `Brain drill Quantum Catastrophe.wav` | Mono | 378.2 ms | – |
| 34 | `Bring me the Horizon Sempiternal.wav` | Mono | 249.3 ms | – |
| 35 | `BulletForMyValentineTemperTemper.wav` | Mono | 114.0 ms | – |
| 36 | `Cannibal Corpse Celestion V30 SM7B Pack 2 (1).wav` | Mono | 1000.0 ms | – |
| 37 | `CannibalCorpseVile.wav` | Mono | 291.4 ms | – |
| 38 | `CarnifexUntilIFeelNothing.wav` | Mono | 182.0 ms | – |
| 39 | `Cattle decapitation Monolith Of Inhumanity.wav` | Mono | 194.6 ms | – |
| 40 | `CelestionV30-SM7B-BOO.wav` | Mono | 1000.0 ms | – |
| 41 | `CelestionV30-SM7B-TBDM.wav` | Mono | 1000.0 ms | – |
| 42 | `CelestionV30-SM7B-TBDM2.wav` | Mono | 1000.0 ms | – |
| 43 | `CelestionV30-SM7B-Whitechapel-ANEOC.wav` | Mono | 1000.0 ms | – |
| 44 | `Children of Bodom Are You Dead Yet.wav` | Mono | 134.4 ms | – |
| 45 | `Chimaira Ressurrection 2.wav` | Mono | 364.5 ms | – |
| 46 | `ChimairaRessurrection.wav` | Mono | 174.3 ms | – |
| 47 | `CONTRA Arma de asalto.wav` | Mono | 76.4 ms | – |
| 48 | `Crisix The menace.wav` | Mono | 648.8 ms | – |
| 49 | `CrownTheEmpireTheFallout.wav` | Mono | 250.0 ms | – |
| 50 | `Cryptopsy Cryptopsy.wav` | Mono | 547.6 ms | – |
| 51 | `DaathTheHinderers.wav` | Mono | 126.8 ms | – |
| 52 | `DarkTranquilityCharacter.wav` | Mono | 74.7 ms | – |
| 53 | `Death over threat Sangre.wav` | Mono | 121.3 ms | – |
| 54 | `Decapitated Carnival Is Forever.wav` | Mono | 164.8 ms | – |
| 55 | `DeicideTheStenchOfRedemption.wav` | Mono | 224.1 ms | – |
| 56 | `DevildriverTheLastKindWords.wav` | Mono | 344.3 ms | – |
| 57 | `Diamond head Lightning to the Nations.wav` | Mono | 301.7 ms | – |
| 58 | `DiezelDMoll.wav` | Mono | 250.0 ms | – |
| 59 | `DimmuBorgirEnthroneDarknessTriumphant.wav` | Mono | 296.4 ms | – |
| 60 | `Disonance in design Neurotransmitting An Epiphany.wav` | Mono | 187.2 ms | – |
| 61 | `DisturbedIndestructible.wav` | Mono | 145.1 ms | – |
| 62 | `DivineHeresyBringerOfPlagues.wav` | Mono | 229.3 ms | – |
| 63 | `Down of the maya The truth is in front of you.wav` | Mono | 426.2 ms | – |
| 64 | `DownNola.wav` | Mono | 168.7 ms | – |
| 65 | `DreamTheaterBlackCloudsSilverLinings.wav` | Mono | 156.7 ms | – |
| 66 | `DV Mark Triple 6.wav` | Mono | 56.8 ms | – |
| 67 | `DyingFetusWarOfAttrition.wav` | Mono | 118.5 ms | – |
| 68 | `EDGE -1 I Inch ala Sneap pic.wav` | Stereo | 1138.2 ms | Stereo; vor Nutzung besser in Mono umwandeln |
| 69 | `EdguyHellfireClub.wav` | Mono | 328.5 ms | – |
| 70 | `El reno Renardo babuinos del metal.wav` | Mono | 189.1 ms | – |
| 71 | `Engl Retro Tube.wav` | Mono | 125.1 ms | – |
| 72 | `Engl Special Edition.wav` | Mono | 220.6 ms | – |
| 73 | `EpicaDesignYourUniverse.wav` | Mono | 776.8 ms | – |
| 74 | `EVH 5150 III.wav` | Mono | 117.2 ms | – |
| 75 | `EvileFiveSerpentsTeeth.wav` | Mono | 55.9 ms | – |
| 76 | `ExodiaHellbringer.wav` | Mono | 250.0 ms | – |
| 77 | `ExodusExhibitBTheHumanCondition.wav` | Mono | 59.1 ms | – |
| 78 | `Exploited beat the Bastards.wav` | Mono | 128.3 ms | – |
| 79 | `Exquisite pus Dead (Forgotten).wav` | Mono | 199.8 ms | – |
| 80 | `FearedVinter.wav` | Mono | 250.0 ms | – |
| 81 | `FearFactoryDemanufacture.wav` | Mono | 230.0 ms | – |
| 82 | `FirewindDaysOfDefiance.wav` | Mono | 116.3 ms | – |
| 83 | `Fortin Natas.wav` | Mono | 276.7 ms | – |
| 84 | `Ghost B C Infestissumam.wav` | Mono | 335.9 ms | – |
| 85 | `GodsmackTheOracle.wav` | Mono | 144.0 ms | – |
| 86 | `GojiraLenfantSauvage.wav` | Mono | 244.8 ms | – |
| 87 | `GreenDayDookie.wav` | Mono | 141.1 ms | – |
| 88 | `Hamlet Amnesia.wav` | Mono | 107.9 ms | Inhaltsgleich mit HamletAmnesia.wav |
| 89 | `HamletAmnesia.wav` | Mono | 107.9 ms | Inhaltsgleich mit Hamlet Amnesia.wav |
| 90 | `hatebreed The divinity of purpose.wav` | Mono | 25.5 ms | – |
| 91 | `Havok PONR.wav` | Mono | 100.0 ms | – |
| 92 | `HavokPointOfNoReturnponr.wav` | Mono | 250.0 ms | – |
| 93 | `HeavenShallBurnVeto.wav` | Mono | 250.0 ms | – |
| 94 | `Helloween better than Raw.wav` | Mono | 108.4 ms | – |
| 95 | `HexenBeingAndNothingness.wav` | Mono | 219.9 ms | – |
| 96 | `HijsDePutHoraDePreAventuras.wav` | Mono | 250.0 ms | – |
| 97 | `Hora Zulu Siempre soñé saber sobre nadie negó nunca nada.wav` | Mono | 144.0 ms | Inhaltsgleich mit der kompakten Schreibweise |
| 98 | `HoraZuluSiempreSoSaberSobreNadieNegNuncaNada.wav` | Mono | 144.0 ms | Inhaltsgleich mit der Schreibweise mit Leerzeichen |
| 99 | `Ignominious incarceration Of winter born.wav` | Mono | 218.6 ms | – |
| 100 | `Impending Doom The Serpent Servant.wav` | Mono | 156.9 ms | – |
| 101 | `Infernoise Chainsaws Law.wav` | Mono | 241.4 ms | – |
| 102 | `InFlamesWhoracle.wav` | Mono | 17.3 ms | – |
| 103 | `IronMaidenPowerslave.wav` | Mono | 250.0 ms | – |
| 104 | `IssuesBlackDiamonds.wav` | Mono | 250.0 ms | – |
| 105 | `JimmyHendrixlive.wav` | Mono | 250.0 ms | – |
| 106 | `JudasPriestJugulator.wav` | Mono | 250.0 ms | – |
| 107 | `Kaos Sludge 15.wav` | Mono | 187.5 ms | – |
| 108 | `KillswitchEngageAsDaylightDies.wav` | Mono | 61.6 ms | – |
| 109 | `Krank Krankenstein.wav` | Mono | 155.2 ms | – |
| 110 | `KreatorViolentRevolution.wav` | Mono | 119.3 ms | – |
| 111 | `Lamb of God Wrath.wav` | Mono | 330.3 ms | – |
| 112 | `Laney ironheart.wav` | Mono | 264.9 ms | – |
| 113 | `LegionOfTheDamnedDescentIntoChaos.wav` | Mono | 52.9 ms | – |
| 114 | `Limp Bizkit Significant Other.wav` | Mono | 315.0 ms | – |
| 115 | `LosSuavesSiYoFueraDios.wav` | Mono | 250.0 ms | – |
| 116 | `MachineHeadThroughTheAshesOfEmpires.wav` | Mono | 89.1 ms | – |
| 117 | `Mago de oz Finisterra.wav` | Mono | 325.7 ms | – |
| 118 | `MakosampCustomHatred.wav` | Mono | 86.5 ms | – |
| 119 | `ManowarBattleHymnsMmxi.wav` | Mono | 165.0 ms | – |
| 120 | `Marshall MG 15.wav` | Mono | 101.2 ms | – |
| 121 | `MastodonCurlOfTheBurl.wav` | Mono | 372.2 ms | – |
| 122 | `MegadethCountdownToExtinction.wav` | Mono | 250.0 ms | – |
| 123 | `MegadethCountdownToExtintion.wav` | Mono | 176.2 ms | – |
| 124 | `MegadethHolyWars.wav` | Mono | 250.0 ms | – |
| 125 | `MegadethSupercollider.wav` | Mono | 250.0 ms | – |
| 126 | `MegadethYouthtanasia.wav` | Mono | 388.8 ms | – |
| 127 | `Mesa Boogie Mark V.wav` | Mono | 75.1 ms | – |
| 128 | `Metallica Master of puppets.wav` | Mono | 602.5 ms | – |
| 129 | `MindlessInfernussong.wav` | Mono | 250.0 ms | – |
| 130 | `Nancys Rubias Ahora o nunca.wav` | Mono | 335.8 ms | – |
| 131 | `NapalmDeathTimeWaitsForNoSlave.wav` | Mono | 54.9 ms | – |
| 132 | `Narco Versiones para no dormir.wav` | Mono | 208.7 ms | – |
| 133 | `Nevermore The Obsidian Conspiracy.wav` | Mono | 618.3 ms | – |
| 134 | `NEWSTED.wav` | Mono | 119.2 ms | – |
| 135 | `NineInchNailsBroken.wav` | Mono | 250.0 ms | – |
| 136 | `Noctem Oblivion.wav` | Mono | 258.6 ms | – |
| 137 | `Overkill The Years of Decay.wav` | Mono | 95.8 ms | – |
| 138 | `Pan de Higo.wav` | Mono | 236.1 ms | – |
| 139 | `PanteraVulgarDisplayOfPower.wav` | Mono | 30.0 ms | – |
| 140 | `Papa roach Getting away with murder.wav` | Mono | 194.4 ms | – |
| 141 | `ParadiseLostTragicIdol.wav` | Mono | 86.6 ms | – |
| 142 | `ParkwayDriveAtlas.wav` | Mono | 250.0 ms | – |
| 143 | `Peavey Vypyr 15.wav` | Mono | 506.1 ms | – |
| 144 | `PeripheryPeriphery.wav` | Mono | 250.0 ms | – |
| 145 | `PerspectivesPerspectives.wav` | Mono | 163.6 ms | – |
| 146 | `Piel de serpiente Inevitable.wav` | Mono | 179.1 ms | – |
| 147 | `PrimalFearUnbreakable.wav` | Mono | 250.0 ms | – |
| 148 | `Que desilusion A golpe de alfil.wav` | Mono | 373.1 ms | – |
| 149 | `Randall Satan.wav` | Mono | 191.5 ms | – |
| 150 | `Randall thrasher.wav` | Mono | 105.7 ms | – |
| 151 | `RandallDiavloRd5.wav` | Mono | 250.0 ms | – |
| 152 | `Red Fang Murder the Mountains.wav` | Mono | 382.0 ms | – |
| 153 | `Red wine Sueños y locura.wav` | Mono | 337.5 ms | – |
| 154 | `Revocation Revocation.wav` | Mono | 321.2 ms | – |
| 155 | `S O D Speak English Or Die.wav` | Mono | 545.7 ms | – |
| 156 | `Sanctity Road To Bloodshed.wav` | Mono | 789.9 ms | – |
| 157 | `Saratoga Nemesis.wav` | Mono | 181.3 ms | – |
| 158 | `Satyricon Now, Diabolical.wav` | Mono | 229.8 ms | – |
| 159 | `SepulturaArise.wav` | Mono | 138.9 ms | – |
| 160 | `Skizoo Skizoo.wav` | Mono | 269.8 ms | – |
| 161 | `Slayer Hell awaits.wav` | Mono | 551.9 ms | – |
| 162 | `SlayerChristIllusion.wav` | Mono | 128.0 ms | – |
| 163 | `Slypknot Iowa.wav` | Mono | 168.4 ms | – |
| 164 | `Sober Superbia.wav` | Mono | 462.9 ms | – |
| 165 | `Soulfly Enslaved.wav` | Mono | 246.2 ms | – |
| 166 | `Soziedad Alkoholika Tiempos Oscuros.wav` | Mono | 617.2 ms | – |
| 167 | `Sphinx Renacer.wav` | Mono | 334.5 ms | – |
| 168 | `Splawn Nitro.wav` | Mono | 52.0 ms | – |
| 169 | `Splawn Quick Rod.wav` | Mono | 131.0 ms | – |
| 170 | `Steelgar Xenocide.wav` | Mono | 215.6 ms | – |
| 171 | `Steelhorse In the storm.wav` | Mono | 383.6 ms | – |
| 172 | `StoneSourHouseOfGoldAndBones.wav` | Mono | 280.9 ms | – |
| 173 | `StrappingYoungLadselfTitled.wav` | Mono | 250.0 ms | – |
| 174 | `Stratovarius legions.wav` | Mono | 147.9 ms | – |
| 175 | `Structures Divided by.wav` | Mono | 313.0 ms | – |
| 176 | `SuperjointRitualUseOnceAndDestroy.wav` | Mono | 262.4 ms | – |
| 177 | `Symphony X Iconoclast.wav` | Mono | 160.5 ms | – |
| 178 | `System of a Down Toxicity.wav` | Mono | 132.4 ms | – |
| 179 | `TAIM Celestion V30 SM7B Pack 2.wav` | Mono | 1000.0 ms | – |
| 180 | `Taurus Stomphead.wav` | Mono | 253.0 ms | – |
| 181 | `Terroristars made in Hellspain.wav` | Mono | 224.7 ms | – |
| 182 | `Testament dark Roots of Earth.wav` | Mono | 101.7 ms | – |
| 183 | `Textures Silhouettes.wav` | Mono | 118.3 ms | – |
| 184 | `The Bronx IV.wav` | Mono | 364.7 ms | – |
| 185 | `The Faceless Celestion V30 SM7B Pack 1 (1).wav` | Mono | 1000.0 ms | – |
| 186 | `TheBlackKeysElCamino.wav` | Mono | 164.9 ms | – |
| 187 | `TheGhostInsideGetWhatYouGive.wav` | Mono | 250.0 ms | – |
| 188 | `TheHauntedRevolver.wav` | Mono | 250.0 ms | – |
| 189 | `TheSorrowMiseryEscape.wav` | Mono | 162.5 ms | – |
| 190 | `Thirteen bled promises Heliopause Fleets.wav` | Mono | 777.5 ms | – |
| 191 | `Thy art is murder The adversary.wav` | Mono | 520.9 ms | – |
| 192 | `Tierra Santa Apocalipsis.wav` | Mono | 1458.4 ms | – |
| 193 | `Trivium In Waves.wav` | Mono | 127.9 ms | – |
| 194 | `Trivium Shogun.wav` | Mono | 766.1 ms | – |
| 195 | `Trivium Vengeance falls.wav` | Mono | 266.6 ms | – |
| 196 | `Trocotombix Somormujo Lavanco.wav` | Mono | 336.3 ms | – |
| 197 | `Uzzhuaia Destino Perdicion.wav` | Mono | 100.6 ms | – |
| 198 | `Vader Necropolis.wav` | Mono | 116.2 ms | – |
| 199 | `Vita Imana Uluh.wav` | Mono | 310.8 ms | – |
| 200 | `Warcry Revolucion.wav` | Mono | 68.4 ms | Inhaltsgleich mit WarcryRevolucion.wav |
| 201 | `WarcryRevolucion.wav` | Mono | 68.4 ms | Inhaltsgleich mit Warcry Revolucion.wav |
| 202 | `Wayne Static Pighammer.wav` | Mono | 113.1 ms | – |
| 203 | `White Chappel Hate Creation.wav` | Mono | 205.6 ms | – |
| 204 | `WoodsOfYpressWoods5GreySkiesAndElectrricLight.wav` | Mono | 250.0 ms | – |
| 205 | `WoodsOfYpressWoods5GreySkiesElectricLight.wav` | Mono | 229.8 ms | – |

## Quellen

- Harley Benton: DNAfx GiT Core Produktseite und aktuelles Benutzerhandbuch.
- lminiero: `dnafx-editor`, insbesondere `src/effects.h`, `src/presets.c` und README (experimentelles Reverse Engineering, nicht mit Harley Benton verbunden).
- Equipboard: Deron Miller – Boss OC-2 und weiterer dokumentierter Gerätebezug.
- Guitar.com-Angabe, zusammengefasst in der Deron-Miller-Biografie: Marshall JCM2000 (Interview 2002).
