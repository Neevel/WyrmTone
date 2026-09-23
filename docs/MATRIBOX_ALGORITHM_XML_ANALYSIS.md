# algorithm.xml – Herstelleranalyse (generiert, read-only)

Quelle: `algorithm.xml` des Sonicake-Editors, ausschließlich gelesen. Erzeugt mit `tool/analyze_manufacturer_xml.dart`.

## Umfang

- Algorithmen: **181** (AMP 45, CAB 53, DLY 11, EQ 2, FX1 25, FX2 25, MOD 10, NR 2, RVB 8)
- Parameter: **631**

## idx vs. ID − 1

- idx == ID − 1: **566**
- idx != ID − 1: **65**
- Algorithmen mit ID-Lücken (Einträge): **59**
  - je Modul: AMP 2, CAB 53, DLY 2, FX1 1, FX2 1
  - davon mit leerem Namen (User IR): 15

Alle Parameter mit idx != ID − 1 (Modul Name/Parameter: idx → ID → Wire):
- FX1 Boost/Bright: idx 1 → ID 3 → Wire 2
- FX2 Boost/Bright: idx 1 → ID 3 → Wire 2
- AMP Calif Star OD/Gain: idx 0 → ID 2 → Wire 1
- AMP Calif Star OD/PRES: idx 1 → ID 3 → Wire 2
- AMP Calif Star OD/Master: idx 2 → ID 4 → Wire 3
- AMP Calif Star OD/Bass: idx 3 → ID 5 → Wire 4
- AMP Calif Star OD/Middle: idx 4 → ID 6 → Wire 5
- AMP Calif Star OD/Treble: idx 5 → ID 7 → Wire 6
- AMP Halen 51/PRES: idx 5 → ID 7 → Wire 6
- CAB Supero 1x6/VOL: idx 0 → ID 2 → Wire 1
- CAB TWD 1x8/VOL: idx 0 → ID 2 → Wire 1
- CAB TWD-P 1x10/VOL: idx 0 → ID 2 → Wire 1
- CAB Bog SV 1x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Viblux 1x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Voks 1x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Calif 1x12/VOL: idx 0 → ID 2 → Wire 1
- CAB TWD 2x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Double 2x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Star 2x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Rock 2x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Jazz 2x12/VOL: idx 0 → ID 2 → Wire 1
- CAB BritGN 2x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Free 2x12/VOL: idx 0 → ID 2 → Wire 1
- CAB B-Man 4x10/VOL: idx 0 → ID 2 → Wire 1
- CAB Brit75 4x12/VOL: idx 0 → ID 2 → Wire 1
- CAB BritGN 4x12/VOL: idx 0 → ID 2 → Wire 1
- CAB BritLD 4x12/VOL: idx 0 → ID 2 → Wire 1
- CAB BritDK 4x12/VOL: idx 0 → ID 2 → Wire 1
- CAB BritMD 4x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Bog 4x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Dizzy 4x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Eng 4x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Halen 4x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Sol 4x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Calif 4x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Dual 4x12/VOL: idx 0 → ID 2 → Wire 1
- CAB WAM 4x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Tanger 4x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Watt 4x12/VOL: idx 0 → ID 2 → Wire 1
- CAB Calif 2x10/VOL: idx 0 → ID 2 → Wire 1
- CAB Work 4x10/VOL: idx 0 → ID 2 → Wire 1
- CAB A Bass 4x10/VOL: idx 0 → ID 2 → Wire 1
- CAB A Bass 8x10/VOL: idx 0 → ID 2 → Wire 1
- CAB D/VOL: idx 0 → ID 2 → Wire 1
- CAB OM/VOL: idx 0 → ID 2 → Wire 1
- CAB Jumbo/VOL: idx 0 → ID 2 → Wire 1
- CAB GA/VOL: idx 0 → ID 2 → Wire 1
- DLY Slap/Trail: idx 3 → ID 5 → Wire 4
- DLY Tape/Sync: idx 4 → ID 6 → Wire 5
- DLY Tape/Trail: idx 5 → ID 7 → Wire 6
- (+ 15 Einträge ohne Namen, User IR)

## Strukturprüfung der IDs

- doppelte IDs innerhalb eines Algorithmus: 0
- doppelte idx innerhalb eines Algorithmus: 0
- ID <= 0: 0
- Parameter ohne ID: 0
- Parameter ohne/mit nichtnumerischem idx: 0
- nichtnumerische IDs: 0
- Algorithmen mit fehlenden IDs im Bereich 1..maxID: **59**
- maximale ID: 8 (Verteilung maxID → Algorithmen: 1:1, 2:60, 3:32, 4:17, 5:30, 6:33, 7:7, 8:1)

Fehlende IDs je Algorithmus (nicht User IR):
- FX1 Boost: fehlende IDs [2]
- FX2 Boost: fehlende IDs [2]
- AMP Calif Star OD: fehlende IDs [1]
- AMP Halen 51: fehlende IDs [6]
- CAB Supero 1x6: fehlende IDs [1]
- CAB TWD 1x8: fehlende IDs [1]
- CAB TWD-P 1x10: fehlende IDs [1]
- CAB Bog SV 1x12: fehlende IDs [1]
- CAB Viblux 1x12: fehlende IDs [1]
- CAB Voks 1x12: fehlende IDs [1]
- CAB Calif 1x12: fehlende IDs [1]
- CAB TWD 2x12: fehlende IDs [1]
- CAB Double 2x12: fehlende IDs [1]
- CAB Star 2x12: fehlende IDs [1]
- CAB Rock 2x12: fehlende IDs [1]
- CAB Jazz 2x12: fehlende IDs [1]
- CAB BritGN 2x12: fehlende IDs [1]
- CAB Free 2x12: fehlende IDs [1]
- CAB B-Man 4x10: fehlende IDs [1]
- CAB Brit75 4x12: fehlende IDs [1]
- CAB BritGN 4x12: fehlende IDs [1]
- CAB BritLD 4x12: fehlende IDs [1]
- CAB BritDK 4x12: fehlende IDs [1]
- CAB BritMD 4x12: fehlende IDs [1]
- CAB Bog 4x12: fehlende IDs [1]
- CAB Dizzy 4x12: fehlende IDs [1]
- CAB Eng 4x12: fehlende IDs [1]
- CAB Halen 4x12: fehlende IDs [1]
- CAB Sol 4x12: fehlende IDs [1]
- CAB Calif 4x12: fehlende IDs [1]
- CAB Dual 4x12: fehlende IDs [1]
- CAB WAM 4x12: fehlende IDs [1]
- CAB Tanger 4x12: fehlende IDs [1]
- CAB Watt 4x12: fehlende IDs [1]
- CAB Calif 2x10: fehlende IDs [1]
- CAB Work 4x10: fehlende IDs [1]
- CAB A Bass 4x10: fehlende IDs [1]
- CAB A Bass 8x10: fehlende IDs [1]
- CAB D: fehlende IDs [1]
- CAB OM: fehlende IDs [1]
- CAB Jumbo: fehlende IDs [1]
- CAB GA: fehlende IDs [1]
- DLY Slap: fehlende IDs [4]
- DLY Tape: fehlende IDs [5]

## Parameter-Typen

- Tag: Combox 8, Knob 573, Switch 50
- Type: Combox/Type=2 8, Knob/Type=1 573, Switch/Type=3 49, Switch/Type=4 1
- valueType: (fehlt) 614, 1 13, 2 4
- SubType: (fehlt) 604, Power 27
- Suffix: (fehlt) 614, Hz 13, ms 4
- Step: (fehlt) 618, 0.10 13
- Attribute an Parametern: Dmax, Dmin, ID, Name, Step, SubType, Suffix, Type, bind, default, idx, valueType
- Attribute an Algorithmen: Code, Index, Module, Name

## bind

- bind-Verteilung: (fehlt) 606, Swp Sync 1, Sync 23, Time Sync 1
- gebundene Parameter: **25** in 24 Algorithmen
- FX1 Auto-W/Rate → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=1
- FX1 Filter/Rate → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=1
- FX2 Auto-W/Rate → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=1
- FX2 Filter/Rate → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=1
- MOD Chorus A/Rate → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=1
- MOD Chorus B/Rate → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=1
- MOD Flanger/Rate → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=1
- MOD Phaser/Rate → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=1
- MOD Vibrato/Rate → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=1
- MOD Vibe/Rate → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=1
- MOD Tremolo/Rate → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=1
- MOD Sine Trem/Rate → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=1
- MOD Bias Trem/Rate → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=1
- DLY Warm/Time → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=-
- DLY Pure/Time → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=-
- DLY Mag/Time → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=-
- DLY Tube/Time → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=-
- DLY 999 Echo/Time → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=-
- DLY Reverse/Time → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=-
- DLY Slap/Time → bind="Sync" (Ziel im selben Algorithmus: NEIN), valueType=-
- DLY Rack/Time → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=-
- DLY Sweep/Time → bind="Time Sync" (Ziel im selben Algorithmus: ja), valueType=-
- DLY Sweep/Swp Rate → bind="Swp Sync" (Ziel im selben Algorithmus: ja), valueType=-
- DLY Ping Pong/Time → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=-
- DLY Tape/Time → bind="Sync" (Ziel im selben Algorithmus: ja), valueType=-

Sync-/Power-Schalter (Ziel der Bindung): 27
- FX1 Auto-W/Sync idx 6 ID 7 SubType=Power
- FX1 Filter/Sync idx 5 ID 6 SubType=Power
- FX2 Auto-W/Sync idx 6 ID 7 SubType=Power
- FX2 Filter/Sync idx 5 ID 6 SubType=Power
- MOD Chorus A/Sync idx 3 ID 4 SubType=Power
- MOD Chorus B/Sync idx 3 ID 4 SubType=Power
- MOD Flanger/Sync idx 4 ID 5 SubType=Power
- MOD Phaser/Sync idx 1 ID 2 SubType=Power
- MOD Vibrato/Sync idx 2 ID 3 SubType=Power
- MOD Vibe/Sync idx 2 ID 3 SubType=Power
- MOD Tremolo/Sync idx 2 ID 3 SubType=Power
- MOD Sine Trem/Sync idx 3 ID 4 SubType=Power
- MOD Bias Trem/Sync idx 3 ID 4 SubType=Power
- DLY Warm/Sync idx 3 ID 4 SubType=Power
- DLY Pure/Sync idx 3 ID 4 SubType=Power
- DLY Mag/Sync idx 3 ID 4 SubType=Power
- DLY Tube/Sync idx 3 ID 4 SubType=Power
- DLY 999 Echo/Sync idx 3 ID 4 SubType=Power
- DLY Reverse/Sync idx 3 ID 4 SubType=Power
- DLY Rack/Sync idx 5 ID 6 SubType=Power
- DLY Rack/Trail idx 6 ID 7 SubType=Power
- DLY Sweep/Swp Sync idx 5 ID 6 SubType=Power
- DLY Sweep/Time Sync idx 6 ID 7 SubType=Power
- DLY Sweep/Trail idx 7 ID 8 SubType=Power
- DLY Ping Pong/Sync idx 3 ID 4 SubType=Power
- DLY Tape/Sync idx 4 ID 6 SubType=Power
- DLY Tape/Trail idx 5 ID 7 SubType=Power

## Wertebereiche (Dmin/Dmax)

- Knobs ohne Dmin: 0, ohne Dmax: 0
- Bereiche (Knob): -12..0 ×2, -24..0 ×2, -50..50 ×15, 0..+12 ×1, 0..+24 ×2, 0..100 ×6, 0..99 ×519, 0.0..99.0 ×1, 0.00..+12.00 ×1, 0.10..10.00 ×13, 20.0..300.0 ×1, 20.0..4000.0 ×10
- Knobs mit Default außerhalb des Bereichs:

## Switch / Combox / Menu

- Switch: 50 Parameter; Menü-Größen: 2 Einträge ×50
  - Menü-ID-Mengen: {0,1} ×49, {0,2} ×1
- Combox: 8 Parameter; Menü-Größen: 2 Einträge ×3, 3 Einträge ×2, 4 Einträge ×2, 5 Einträge ×1
  - Menü-ID-Mengen: {0,1,2,3,4} ×1, {0,1,2,3} ×2, {0,1,2} ×2, {0,1} ×3
- Switches ohne Menü-ID 0: 0
- Combox-Parameter (Auszug der ersten 15):
  - FX1 AC Sim/Mode: 0=STD, 1=Jumbo, 2=ENH, 3=Piezo
  - FX1 Touch-W/Mode: 0=Guitar, 1=Bass
  - FX1 Dist Plus/Mode: 0=Normal, 1= Scoop, 2= Edge
  - FX2 Dist Plus/Mode: 0=Normal, 1=Scoop, 2=Edge
  - FX2 AC Sim/Mode: 0=STD, 1=Jumbo, 2=ENH, 3=Piezo
  - FX2 Touch-W/Mode: 0=Guitar, 1=Bass
  - AMP Voks 30TB/Char: 0=Cool, 1= Hot
  - AMP A BassVT/MRange: 0=220Hz, 1=450Hz, 2=800Hz, 3=1.6kHz, 4=3kHz

## Algorithmen: Namen, Codes, Index

- Algorithmen mit leerem Namen: 15 (Modul {CAB: 15})
- doppelte Namen innerhalb eines Moduls: 0
- doppelte Codes innerhalb eines Moduls: 0
- nichtnumerische Codes: 0
- Parameter je Algorithmus (Verteilung): 1:54, 2:9, 3:30, 4:18, 5:29, 6:36, 7:4, 8:1
- Zeichen `|` `~` `;` `\t` in Namen: 0

## Weitere Fälle, in denen idx-Adressierung falsch wäre

Jeder Parameter mit idx != ID − 1 (siehe oben) sowie jeder Parameter hinter einer fehlenden ID im selben Algorithmus. Die Regel Wire = ID − 1 ist für alle 46 Capture-Gruppen und für Boost Bright (Wire 2) und CAB VOL (Wire 1) hardwarebestätigt.
