# Matribox: lokale Offline-Analyse

## Zweck und Aufruf

Entwicklerwerkzeug außerhalb der App; keine Build-Abhängigkeit auf Editor-Ressourcen. `dart run tool/matribox_analyzer.dart --algorithm "<algorithm.xml>" --preset "<preset.xml>" --capture "<capture.json>" [--capture "<weiterer.json>"] --output "<bericht.md>"`. Fehlende Capture-Pfade werden ausgewiesen; ungültige Captures abgelehnt. Ausgabe enthält nur abgeleitete kompakte Erkenntnisse, keine Originalressourcen. Originaldateien bleiben unverändert.

## Quellen und Warnungen

Lokal installierte Editor-Ressourcen: algorithm.xml, preset.xml.
Captures: ferse bis spitze.json, letzte (1).json, letzte.json, pause.json, spitze bis ferse.json, wyrmtone_midi_capture_1789202822050.json, wyrmtone_midi_capture_1789203093915.json, wyrmtone_midi_capture_1789196818677.json (Papierkorb), wyrmtone_midi_capture2_1789198028316.json (Papierkorb). Mehrere Exporte können überlappen; Gesamtzahlen sind Export-Beobachtungen, keine unabhängigen Geräteereignisse.
- letzte.json: identische erhaltene Nachrichten wie letzte (1).json; keine unabhängige Gegenprobe.
- algorithm.xml:832:61: duplicate ID; values 2, 2 retained; meaning conflicting if unequal
- algorithm.xml:840:61: duplicate ID; values 2, 2 retained; meaning conflicting if unequal
- algorithm.xml:1367:62: duplicate ID; values 3, 3 retained; meaning conflicting if unequal
- wyrmtone_midi_capture2_1789198028316.json (Papierkorb): droppedEntries=89; chronology incomplete

## Bestehende Projektmittel

Wiederverwendet: der reine `MidiParser` für Chunk-/SysEx-Rekonstruktion. `MidiCaptureEntry` und der JSON-Export definieren Zeit, Sequenz, kind, Bytes und Marker; der Import nutzt deren Schema, ohne den Flutter-Controller oder Plattformkanäle zu laden. `ParameterRecommendation` beschreibt Empfehlungen, nicht Editor-Algorithmus-/Wire-IDs. Die neuen ResourceNode-/Evidence-Modelle bleiben ausschließlich in `tool/`.

## Algorithmus- und Presetstruktur

| Kategorie | Algorithmen | direkte Parameter |
|---|---:|---:|
| FX1 | 25 | 92 |
| FX2 | 25 | 92 |
| AMP | 45 | 250 |
| NR | 2 | 4 |
| CAB | 53 | 53 |
| EQ | 2 | 12 |
| MOD | 10 | 36 |
| DLY | 11 | 60 |
| RVB | 8 | 32 |

181 Algorithmuseinträge und 631 direkte Parameterelemente über neun Kategorien; gleiche Algorithmen können in mehreren Blöcken auftreten. Keine vollständige Herstellerliste dauerhaft übernommen.

Observed: Alg(Name, Module, Code, Index); Parameter(Knob/Switch/Combox) mit Name, ID, idx, default, Dmin/Dmax, Step/step, Suffix, Type/valueType, bind und Menu(Name, ID), soweit vorhanden. Fehlende Werte bleiben unbekannt; unbekannte Attribute und Elemente bleiben im Importmodell erhalten. Numerische Rohdarstellung, Basis und normalisierter Wert bleiben getrennt. Doppelte Attribute werden als Liste mit Position erhalten, nicht überschrieben. Dies sind Editor-Felder, keine bestätigten Wire-IDs.

Beispiel-Preset: Name=Marshell-1, ID=0, volume=50; Reihenfolge FX1 → FX2 → AMP → NR → CAB → EQ → MOD → DLY → RVB. Blöcke enthalten Name/code/switch und Parameterattribute; switch als Aktivzustand ist eine Hypothese. Die Vorlage ist kein live gelesener Preset-Dump.

Hinweis: Die Preset-Vorlage enthält außerdem die Bezeichnung Ampero und eine Hotone-URL. Das belegt wiederverwendete Vorlagenfelder, nicht eine bestätigte Geräte-/Protokollgleichheit.

## Nachrichtenfamilien und Differenzen

### 18 Byte

7 Nachrichten; konstantes Präfix 10 Byte, Suffix 3 Byte; variable Offsets (nullbasiert): [10, 11, 12, 14]. Markierungen: Under screen regler left, underscreen regler mid, underscreen regler right, drum button.
Observed: Offsets 4–7 = ASCII QME2; Kennzeichner, Semantik unknown.
- Aktion Under screen regler left: 2 Nachrichten, variable Offsets [14]; alle übrigen Offsets konstant innerhalb dieser Gruppe.
- Aktion underscreen regler mid: 2 Nachrichten, variable Offsets [14]; alle übrigen Offsets konstant innerhalb dieser Gruppe.
- Aktion underscreen regler right: 2 Nachrichten, variable Offsets [14]; alle übrigen Offsets konstant innerhalb dieser Gruppe.
- Aktion drum button: 1 Nachrichten, variable Offsets []; alle übrigen Offsets konstant innerhalb dieser Gruppe.

| Offset | Hexwerte | Dezimalwerte | ASCII | Zustand |
|---:|---|---|---|---|
| 0 | F0 | 240 |  | konstant |
| 1 | 21 | 33 | ! | konstant |
| 2 | 25 | 37 | % | konstant |
| 3 | 7F | 127 |  | konstant |
| 4 | 51 | 81 | Q | konstant |
| 5 | 4D | 77 | M | konstant |
| 6 | 45 | 69 | E | konstant |
| 7 | 32 | 50 | 2 | konstant |
| 8 | 12 | 18 |  | konstant |
| 9 | 00 | 0 |  | konstant |
| 10 | 01 02 | 1,2 |  | variabel |
| 11 | 00 02 | 0,2 |  | variabel |
| 12 | 04 05 0A 0B | 4,5,10,11 |  | variabel |
| 13 | 00 | 0 |  | konstant |
| 14 | 00 01 | 0,1 |  | variabel |
| 15 | 00 | 0 |  | konstant |
| 16 | 00 | 0 |  | konstant |
| 17 | F7 | 247 |  | konstant |

Offline-Prüfsummenkandidaten (Payload 1..L-3 gegen L-2, F7 ausgeschlossen): sum7: 0/7 passend; xor7: 0/7 passend; complement7: 0/7 passend. Teiltreffer bestätigen nichts; andere Prüfsummen/Positionen bleiben offen.
### 22 Byte

18 Nachrichten; konstantes Präfix 14 Byte, Suffix 3 Byte; variable Offsets (nullbasiert): [14, 17, 18]. Markierungen: preset regler, Volume regler, pedal left, pedal right.
Observed: Offsets 4–7 = ASCII QME2; Kennzeichner, Semantik unknown.
- Aktion preset regler: 4 Nachrichten, variable Offsets [18]; alle übrigen Offsets konstant innerhalb dieser Gruppe.
- Aktion Volume regler: 5 Nachrichten, variable Offsets [18]; alle übrigen Offsets konstant innerhalb dieser Gruppe.
- Aktion pedal left: 5 Nachrichten, variable Offsets [14, 17, 18]; alle übrigen Offsets konstant innerhalb dieser Gruppe.
- Aktion pedal right: 4 Nachrichten, variable Offsets [14, 17, 18]; alle übrigen Offsets konstant innerhalb dieser Gruppe.

| Offset | Hexwerte | Dezimalwerte | ASCII | Zustand |
|---:|---|---|---|---|
| 0 | F0 | 240 |  | konstant |
| 1 | 21 | 33 | ! | konstant |
| 2 | 25 | 37 | % | konstant |
| 3 | 7F | 127 |  | konstant |
| 4 | 51 | 81 | Q | konstant |
| 5 | 4D | 77 | M | konstant |
| 6 | 45 | 69 | E | konstant |
| 7 | 32 | 50 | 2 | konstant |
| 8 | 12 | 18 |  | konstant |
| 9 | 00 | 0 |  | konstant |
| 10 | 02 | 2 |  | konstant |
| 11 | 00 | 0 |  | konstant |
| 12 | 00 | 0 |  | konstant |
| 13 | 00 | 0 |  | konstant |
| 14 | 00 01 | 0,1 |  | variabel |
| 15 | 00 | 0 |  | konstant |
| 16 | 00 | 0 |  | konstant |
| 17 | 00 06 | 0,6 |  | variabel |
| 18 | 00 01 02 03 04 08 | 0,1,2,3,4,8 |  | variabel |
| 19 | 00 | 0 |  | konstant |
| 20 | 00 | 0 |  | konstant |
| 21 | F7 | 247 |  | konstant |

Offline-Prüfsummenkandidaten (Payload 1..L-3 gegen L-2, F7 ausgeschlossen): sum7: 0/18 passend; xor7: 3/18 passend; complement7: 0/18 passend. Teiltreffer bestätigen nichts; andere Prüfsummen/Positionen bleiben offen.
### 34 Byte

642 Nachrichten; konstantes Präfix 25 Byte, Suffix 1 Byte; variable Offsets (nullbasiert): [25, 26, 27, 28, 29, 30, 31, 32]. Markierungen: (keine; Dateiname ist kein Marker), ferse bis mittelstellung, nach pause und mittelstellung richtung spitze, Expression-Pedal, ferse bis spitze, spitze bis ferse zurck, expression pedal.
Observed: Offsets 4–7 = ASCII QME2; Kennzeichner, Semantik unknown.
- Aktion (unmarkiert): 246 Nachrichten, variable Offsets [25, 26, 27, 28, 29, 30, 31, 32]; alle übrigen Offsets konstant innerhalb dieser Gruppe.
- Aktion ferse bis mittelstellung: 30 Nachrichten, variable Offsets [25, 26, 27, 28, 29, 30, 31, 32]; alle übrigen Offsets konstant innerhalb dieser Gruppe.
- Aktion nach pause und mittelstellung richtung spitze: 31 Nachrichten, variable Offsets [25, 26, 27, 28, 29, 30]; alle übrigen Offsets konstant innerhalb dieser Gruppe.
- Aktion Expression-Pedal: 66 Nachrichten, variable Offsets [25, 26, 27, 28, 29, 30, 31, 32]; alle übrigen Offsets konstant innerhalb dieser Gruppe.
- Aktion ferse bis spitze: 63 Nachrichten, variable Offsets [25, 26, 27, 28, 29, 30, 31, 32]; alle übrigen Offsets konstant innerhalb dieser Gruppe.
- Aktion spitze bis ferse zurck: 59 Nachrichten, variable Offsets [25, 26, 27, 28, 29, 30, 31, 32]; alle übrigen Offsets konstant innerhalb dieser Gruppe.
- Aktion expression pedal: 147 Nachrichten, variable Offsets [25, 26, 27, 28, 29, 30, 31, 32]; alle übrigen Offsets konstant innerhalb dieser Gruppe.

| Offset | Hexwerte | Dezimalwerte | ASCII | Zustand |
|---:|---|---|---|---|
| 0 | F0 | 240 |  | konstant |
| 1 | 21 | 33 | ! | konstant |
| 2 | 25 | 37 | % | konstant |
| 3 | 7F | 127 |  | konstant |
| 4 | 51 | 81 | Q | konstant |
| 5 | 4D | 77 | M | konstant |
| 6 | 45 | 69 | E | konstant |
| 7 | 32 | 50 | 2 | konstant |
| 8 | 12 | 18 |  | konstant |
| 9 | 10 | 16 |  | konstant |
| 10 | 01 | 1 |  | konstant |
| 11 | 00 | 0 |  | konstant |
| 12 | 02 | 2 |  | konstant |
| 13 | 00 | 0 |  | konstant |
| 14 | 08 | 8 |  | konstant |
| 15 | 00 | 0 |  | konstant |
| 16 | 00 | 0 |  | konstant |
| 17 | 00 | 0 |  | konstant |
| 18 | 00 | 0 |  | konstant |
| 19 | 00 | 0 |  | konstant |
| 20 | 05 | 5 |  | konstant |
| 21 | 00 | 0 |  | konstant |
| 22 | 00 | 0 |  | konstant |
| 23 | 00 | 0 |  | konstant |
| 24 | 00 | 0 |  | konstant |
| 25 | 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F | 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15 |  | variabel |
| 26 | 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F | 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15 |  | variabel |
| 27 | 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F | 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15 |  | variabel |
| 28 | 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F | 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15 |  | variabel |
| 29 | 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F | 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15 |  | variabel |
| 30 | 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F | 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15 |  | variabel |
| 31 | 00 03 04 | 0,3,4 |  | variabel |
| 32 | 00 01 02 0F | 0,1,2,15 |  | variabel |
| 33 | F7 | 247 |  | konstant |

Offline-Prüfsummenkandidaten (Payload 1..L-3 gegen L-2, F7 ausgeschlossen): sum7: 0/642 passend; xor7: 0/642 passend; complement7: 0/642 passend. Teiltreffer bestätigen nichts; andere Prüfsummen/Positionen bleiben offen.

## Korrelationsmatrix und Wertkandidaten

| Capture/Markierung | Muster | XML-Zuordnung | Wertkandidat | Vertrauen |
|---|---|---|---|---|
| ferse bis spitze.json /  | 63 SysEx | unknown | Offsets 25–32, Nibble-Paare → Float32 LE: 0.0000 → 99.0000 | hypothesis; wiederkehrende Endpunkte correlated |
| letzte (1).json /  | 63 SysEx | unknown | Offsets 25–32, Nibble-Paare → Float32 LE: 0.0000 → 99.0000 | hypothesis; wiederkehrende Endpunkte correlated |
| letzte.json /  | 63 SysEx | unknown | Offsets 25–32, Nibble-Paare → Float32 LE: 0.0000 → 99.0000 | hypothesis; wiederkehrende Endpunkte correlated |
| pause.json / ferse bis mittelstellung; pause; nach pause und mittelstellung richtung spitze | 61 SysEx | unknown | Offsets 25–32, Nibble-Paare → Float32 LE: 0.0000 → 99.0000 | hypothesis; wiederkehrende Endpunkte correlated |
| spitze bis ferse.json /  | 57 SysEx | unknown | Offsets 25–32, Nibble-Paare → Float32 LE: 99.0000 → 0.0000 | hypothesis; wiederkehrende Endpunkte correlated |
| wyrmtone_midi_capture_1789202822050.json / Expression-Pedal | 66 SysEx | unknown | Offsets 25–32, Nibble-Paare → Float32 LE: 0.0000 → 99.0000 | hypothesis; wiederkehrende Endpunkte correlated |
| wyrmtone_midi_capture_1789203093915.json / ferse bis spitze; spitze bis ferse zurck | 122 SysEx | unknown | Offsets 25–32, Nibble-Paare → Float32 LE: 0.0000 → 0.0000 | hypothesis; wiederkehrende Endpunkte correlated |
| wyrmtone_midi_capture_1789196818677.json (Papierkorb) / preset regler; expression pedal; global button; pedal left; Volume regler; pedal left; pedal right; preset regler; global button; Under screen regler left; underscreen regler mid; underscreen regler right; volume regler; expression pedal | 24 SysEx | unknown | unknown | unknown |
| wyrmtone_midi_capture2_1789198028316.json (Papierkorb) / volume regler; para regler drücken; drum button; global button | 148 SysEx | unknown | Offsets 25–32, Nibble-Paare → Float32 LE: 52.4118 → 0.0000 | hypothesis; wiederkehrende Endpunkte correlated |

Vierbyte-Codekandidaten, Offsets ab 8: BE32@11=0; BE32@11=1; BE32@12=0; BE32@12=167772160; BE32@12=184549376; BE32@12=67108864; BE32@13=0; BE32@14=0; BE32@15=0; BE32@15=1; BE32@16=0; BE32@17=0; BE32@21=0; BE32@22=0; BE32@22=1; BE32@23=0; BE32@24=0; BE32@25=0; BE32@26=0; BE32@27=0; BE32@28=0; BE32@29=0; LE32@11=0; LE32@12=0; weitere Zufallstreffer unterdrückt. Padding und kleine Codes erzeugen Mehrfachtreffer; kein eindeutiges Codefeld. Andere Bitpackungen, Offsets oder invertierte IDs bleiben unbewiesen.

Observed numerische Byte-Treffer: Algorithmus-Codes [0, 1]; Parameter-IDs [1, 2, 3, 4, 5, 6, 7, 8]. Kleine Zahlen treffen Header, Padding und Werte zufällig; keine Zuordnung daraus. XML-default 50 bzw. Bereiche 0–99 sind mit dem Float-Kandidaten plausibel vereinbar, aber keinem konkreten Parameter zugeordnet. Direkte/offset/invertierte/skalierte 7-Bit- oder Mehrbyte-ID-Darstellungen sind ohne kontrollierten Algorithmuswechsel nicht unterscheidbar.

Hypothesis: acht Bytes 25–32 sind High-/Low-Nibbles von vier Little-Endian-Bytes, interpretiert als IEEE754 Float32. Wiederkehrende Endpunkte 0 und 99 sind correlated mit den vom Nutzer beschriebenen Pedalanschlägen, nicht confirmed als allgemeine Protokollsemantik. Keine belegte invertierte Skalierung. Keine XML-Algorithmus-/Parameter-Zuordnung confirmed. Marker können Aktionen zeitlich versetzt zuordnen; Dateinamen sind nur Nutzerkontext. Sequenznummern sind App-Lognummern, kein Wire-Zähler. Konstante/schwankende Bytes allein belegen weder Nachrichtentyp noch Länge oder Prüfsumme. 18/22/34-Byte-Gruppen sind observed unterschiedliche Strukturen; ihre proprietären Nachrichtentypen bleiben unknown.

## Kleinste offene Gegenproben

- Die kontrollierten Gain-/Bass-/Middle-Aufnahmen und der Algorithmuswechsel liegen seit 13.09.2026 vor; Ergebnisse siehe Nachmessung unten.
- Für eine Blockzuordnung denselben sichtbaren Wert in einem anderen Effektblock aufnehmen und Offsets 10–12 vergleichen. Die bisherigen AMP-/Pedaldaten bestätigen Offset 12 nicht als AMP-Kennung.
- Für die Identität des zweiten Amps einen Screenshot von Modellname und Clone-/Slotzuweisung bereitstellen. Keine Geräteabfrage notwendig.
- Pedalzuweisung und sichtbare Werte fehlen; Float-Kandidat darf ohne diese Gegenprobe nicht als bestätigte Pedal-Prozentanzeige verwendet werden.
- Button-Drücken und Regler-Drehen getrennt markieren; aktuelle 0/1-Paare unterscheiden Schaltzustand, UI-Aktion und Parameterwert nicht eindeutig.

## Sicherheitsstatus

Nur explizit angegebene lokale Dateien gelesen; kein MIDI-Port geöffnet, keine Matribox angesprochen, nichts gesendet oder wiederholt, keine USB-Transfers, kein Editor gestartet. Herstellerdateien und Captures unverändert; keine Originalressourcen/Binärdateien kopiert. Umfangreiche Herstellerlisten verbleiben nur im Arbeitsspeicher. Keine rechtliche Freigabe zur Veröffentlichung solcher Listen abgeleitet; dauerhafte Übernahme würde eine gesonderte Bewertung erfordern.

## Kontrollierte Nachmessung vom 13.09.2026

Zusätzliche Quellen: `gain.json`, `bass.json`, `mid.json`, `anderer amp.json` aus dem vom Nutzer genannten Exportordner. Ausgeführt mit dem unveränderten Offline-Analyzer gegen dieselben lokalen `algorithm.xml`-/`preset.xml`-Dateien; positionsbezogene Nibble-Dekodierung anschließend separat überprüft. Alle vier Dateien: `receiveOnly=true`, jeweils drei vollständige 34-Byte-SysEx; keine gemeldeten unvollständigen Nachrichten, Empfangsverluste oder verworfenen Einträge. Die Chunk-/Nachrichtenrekonstruktion des Analyzers meldet keine Abweichungen. Diese zwölf Nachrichten sind nicht in den älteren Familienzahlen oben enthalten.

Offsets sind nullbasiert einschließlich F0 an Offset 0. Nibble-Paare werden als `16*a+b` zu Bytes kombiniert; Mehrbytezahlen werden Little-Endian gelesen.

| Capture | Offsets 13–20 als UInt32 | exakter XML-Treffer | Offset 22 | XML idx / ID | Offsets 25–32 als Float32 |
|---|---|---|---:|---|---|
| gain.json | 117440601 / 0x07000059 | AMP: Sol 100 LD | 0 | Gain: idx=0 / ID=1 | 41 → 42 → 41 |
| bass.json | 117440601 / 0x07000059 | AMP: Sol 100 LD | 3 | Bass: idx=3 / ID=4 | 41 → 42 → 41 |
| mid.json | 117440601 / 0x07000059 | AMP: Sol 100 LD | 4 | Middle: idx=4 / ID=5 | 41 → 42 → 41 |
| anderer amp.json | 251658240 / 0x0F000000 | AMP: Clone 1 | 0 | Gain: idx=0 / ID=1 | 41 → 42 → 41 |

**Algorithmusfeld 13–20 — correlated:** Erste drei Captures enthalten `05 09 00 00 00 00 00 07`, also die Bytes `59 00 00 07` und exakt den XML-Code für `Sol 100 LD` (algorithm.xml:622). Der vierte enthält `00 00 00 00 00 00 00 0F`, also `00 00 00 0F` und exakt den Code für `Clone 1` (Zeile 757). Zwei unterschiedliche Codes bei unverändertem Gain-Index und Wertverlauf stützen ein Algorithmus-/Modellselektorfeld. Allgemeine Bedeutung über andere Nachrichtentypen hinweg ist nicht confirmed.

**Nutzerklärung zur NAM-Bezeichnung:** Die lokale XML nennt `Sol 100 LD`, nicht `Sol 1000 LD`. Der Nutzer bestätigte, dass `j9 gain` den importierten NAM „Marshall JCM 900“ bezeichnet. Sein beobachteter Code passt zum XML-Eintrag `Clone 1`; damit sind Klangmodellname und interner Clone-/NAM-Platz zu unterscheiden (correlated). `0x0F000000` ist kein bestätigter allgemeiner JCM-900-Code. Eine feste Zuordnung zu Slot 1 unabhängig vom geladenen NAM ist noch unknown.

**Parameterfeld — correlated, nicht XML-ID:** Offset 22 passt bei Gain/Bass/Middle jeweils zu `idx` (0/3/4) und ebenso zu `ID-1`, nicht zur unveränderten `ID` (1/4/5). Diese beiden Interpretationen sind mit den vorhandenen Parametern nicht unterscheidbar. Offsets 21, 23 und 24 sind stets 0. Daher könnte 21–24 insgesamt ein nibble-kodiertes UInt16-Indexfeld sein; eine allgemeine Feldbreite oder die alleinige Bedeutung von Byte 22 ist nicht confirmed. Ein XML-Parameter mit `idx != ID-1` wäre die kleinste Gegenprobe, sofern am Gerät passiv messbar.

**Offset 12 als AMP-Block — unknown/unbelegt:** Alle zwölf AMP-Nachrichten haben hier 02; derselbe Wert steht jedoch auch in den bisherigen Pedalnachrichten. Die Konstanz im AMP-Versuch allein bestätigt keine AMP-spezifische Kennung. Offset 10 ist hier 03, in den Pedalnachrichten 01; eine Klassifikation oder Block-/Slotkennung an dieser Stelle ist lediglich hypothesis. Andere Effektblöcke fehlen als kontrollierte Gegenprobe.

**Wertfeld 25–32 — confirmed für diese gemessenen Werte:** Nibble-Paare zu vier Bytes, anschließend IEEE754 Float32 Little-Endian, ergeben in allen vier Reihen exakt die markierten neuen Werte 41, 42 und erneut 41. Die Rückkehr zu 41 wiederholt jeweils dieselbe vollständige Nachricht. Das bestätigt die numerische Darstellung für diese Captures; eine universelle Einheit, Prozentanzeige, Feldsemantik aller 34-Byte-Nachrichten oder Pedalskalierung folgt daraus nicht. Keine zusätzliche Invertierung oder Skalierung ist für diese Messwerte erforderlich.

**Prüfsumme/Zähler:** Die rückkehrenden identischen 41-Nachrichten zeigen keinen zwangsläufig fortlaufenden Wire-Zähler. Die bisherigen einfachen Prüfsummenkandidaten werden durch diese Aufnahmen nicht bestätigt. Byte 32 gehört bei der passenden Float-Dekodierung zum Wertkandidaten; eine gesonderte Prüfsumme darf dort nicht unterstellt werden. Keine Aussage über andere Verfahren/Felder.

Nur Bericht ergänzt; Werkzeug, App und Hersteller-/Capture-Dateien unverändert. Daher keine neuen Tests erforderlich, keine Testsuite, kein App-Build und keine Gerätekommunikation.

## Ergänzung: Calif Star CL

`calif gain.json` enthält drei vollständige 34-Byte-SysEx mit `receiveOnly=true`, ohne gemeldete Verluste oder unvollständige Nachrichten. Offsets 13–20 dekodieren jeweils zu 117440537 / `0x07000019`; dies ist exakt der Code des AMP-Eintrags `Calif Star CL` in der lokal installierten `algorithm.xml` (Zeile 415, Index 3). Offset 22 ist 0 und passt zu Gain `idx=0` (XML-ID=1); Offsets 25–32 ergeben exakt 41 → 42 → 41. XML-Name/Code sind observed, die Zuordnung dieser Empfangsreihe zum Algorithmus ist correlated. Host→Gerät-Verkehr wurde damit nicht untersucht oder bestätigt.

## PC-Editor-Mitschnitte: Sol 100 OD

Der Nutzer bestätigte Sol 100 OD statt des zunächst geplanten Sol 100 LD. Die unveränderten Dateien wurden offline mit capinfos/TShark ausgewertet; USBPcap1, Bus 1, Matribox-Adresse 12. Wireshark dekodiert die USB-MIDI-Event-Pakete: CIN 4 liefert drei SysEx-Bytes, CIN 5 das abschließende F7; Cable/CIN und Padding sind keine MIDI-Nutzbytes. Fragmentierung über URBs wird vor dem positionsbezogenen Vergleich zusammengesetzt.

| Datei | Größe (Byte) | Dauer (s) | relevante Datenpakete | beobachteter Vorgang |
|---|---:|---:|---|---|
| 01_matribox_editor_connect_only_retry.pcap | 78562080 | 203,089927 | OUT 03 und IN 83 vorhanden; Anzahl hier nicht ausgewertet | Initialisierung; kurze QME2-Nachrichten mit anderem Headerfeld an Offset 8 beobachtet, vollständige Bedeutung offen |
| 02_matribox_editor_gain_40_to_41.pcapng | 4216020 | 11,008191 | OUT: Frames 779/780, zusammen eine SysEx; IN: keine MIDI-Daten im untersuchten Endpunktfilter | Änderung im PC-Editor auf 41 |
| 03_matribox_editor_gain_41_to_40.pcapng | 2922036 | 7,621647 | OUT: Frame 683, eine SysEx; IN: keine MIDI-Daten im untersuchten Endpunktfilter | korrigierte Änderung im PC-Editor auf 40 |

SHA-256 der untersuchten Dateien:

- 01: `EB57F3506928E6C157A12584190C4DE2782F79A61D43198BE8769BA22DFF342D`
- 02: `700AAFDAC7316D60B6850349A54ECF29B7A6384473E1DD0BF8631F1E03C417D0`
- 03: `4836839C096000B050324A14EE3B872CA74711025F8DB149E5BFCD7FA51B9052`

| Richtung | Länge | Algorithmuscode 13–20 | XML-Modell | Index 22 | Float-Wert 25–32 | Vertrauen |
|---|---:|---|---|---:|---:|---|
| Editor → Matribox, OUT 03 | 34 | 0x07000047 | Sol 100 OD | 0 | 41 | confirmed für diesen kontrollierten Editor-Vorgang |
| Editor → Matribox, OUT 03 | 34 | 0x07000047 | Sol 100 OD | 0 | 40 | confirmed für diesen kontrollierten Editor-Vorgang |

Die rekonstruierten Hin-/Rücknachrichten unterscheiden sich ausschließlich an Offset 30 (04 für 41, 00 für 40). Beide haben das bekannte QME2-/34-Byte-Layout und sind strukturell gleich aufgebaut wie die bisherigen Android-Empfangsnachrichten; dort wurden jedoch andere Modelle untersucht. Eine frühere, vom Nutzer anschließend ersetzte 03-Datei zeigte die gleiche Sol-100-OD-Struktur und Wert 40 auf IN 83; der Nutzer bestätigte dazu Bedienung am Gerät. Sie ist kein PC-Editor-Rückweg und kein Echo-Beleg. Das Original dieser früheren Version steht unter dem genannten Pfad nicht mehr zur Verfügung.

Damit ist Host→Gerät-Parameteränderung für diese zwei Editor-Aktionen belegt. Allgemeine Schreibfreigabe, universelle Feldbedeutung oder ein notwendiger Handshake folgen daraus nicht. Kein Echo/ACK im MIDI-Endpunktfilter der beiden kurzen Editor-Captures sichtbar; USB-Transferstatus und proprietäre Bestätigung sind zu unterscheiden. Der Initialisierungsmitschnitt ist noch nicht vollständig semantisch ausgewertet. Die Rohdateien enthalten zusätzlich USB-Audio und möglicherweise Deskriptoren/Seriennummern und bleiben außerhalb des Repositorys; keine ungeprüfte Veröffentlichung.

Nur bestehender Bericht angepasst, kein Parser-/App-Code verändert; keine Tests erforderlich. Ausschließlich Offline-Auswertung in diesem Schritt, keine Gerätekommunikation durch WyrmTone oder eigene Sender, kein App-Build, Commit oder Push.

### Bytegenauer Vorvergleich für den freigegebenen Einmaltest

Erneut offline aus den Original-URBs extrahiert: 02 / Host → Gerät / OUT 03 / Frames 779–780 und 03 / Host → Gerät / OUT 03 / Frame 683. Neue Gegenprobe `04_matribox_device_gain_41_to_40.pcapng`: SHA-256 `9B536567D03F4EF0E1CAA7B681220930F545AF21DA7947F11F27856686B76033`, Deskriptor 84EF:0054, Bus 1 / Adresse 13, Gerät → Host / IN 83 / Frame 775. Die aktuelle 04-Datei ersetzt frühere Fehlversuche mit DualSense beziehungsweise Sol 100 LD.

Vollständige 34-Byte-MIDI-Nachrichten (ohne USB-MIDI-CIN und Padding):

```text
41: f021257f514d453212100300020407000000000007000000000000000002040402f7
40: f021257f514d453212100300020407000000000007000000000000000002000402f7
```

Beide: F0…F7, QME2 an 4–7, Algorithmuscode 07000047 an 13–20 (Nibble → UInt32 LE), Gain-Index 0 an 21–24, Float32 LE 41 beziehungsweise 40 an 25–32. Die 40-Nachricht der Gegenprobe ist bytegleich mit der 40-Nachricht des Editors. Einziger Unterschied zur 41-Nachricht: Offset 30 = 00 statt 04. Keine weiteren variablen Bytes, Sequenz-/Zeitfelder oder variable zusätzliche Prüfsumme in diesen drei Referenznachrichten erkennbar; keine universelle Aussage über andere Befehle. SHA-256 der 41-Nachricht: `00A5945FC81C6345E37E9662314490E675B5D7080B76C285E09C339F2A2A57ED`. Die exakte 41-Originalnachricht ist die maßgebliche Referenz, keine aus Feldannahmen erzeugte Nachricht.
## Maschinenlesbare Freigabematrix

Die aktuelle Quelle der Laufzeitentscheidung ist
`lib/presets/protocol_evidence.dart`. Sie trennt `observed`,
`correlated`, `confirmed` und `unknown` sowie Lesen, Schreiben,
Produktionsfreigabe und nötige Hardwaretests. Bestätigt sind Identität,
Android-MIDI-Öffnen/Schließen und der eng begrenzte Sol-100-OD-Gain-Versuch.
Sol 100 LD, Calif Star CL sowie Bass-/Middle-Indizes bleiben Korrelationen.
Alle vollständigen Presetoperationen bleiben unbekannt und gesperrt.

Das öffentliche Projekt `hurricaneabel/Matribox_II_Pro_MidiCon` wurde nur
vergleichend gelesen. Im Repository-Baum war keine Lizenzdatei vorhanden; es
wurde deshalb weder Code noch Architektur oder Zuordnung übernommen. Seine
Angaben betreffen zudem die Matribox II Pro und sind kein Beleg für Matribox 1.

### Bestätigte Presetauswahl im PC-Editor

Die kontrollierten Mitschnitte `05_matribox_editor_select_test_A_to_test_B.pcapng`
(SHA-256 `010CF51A124F5B6A0F3AFE1D4A61EBC06DBCDB1B858D4E3A8630F5D2A305C042`)
und `06_matribox_editor_select_test_B_to_test_A.pcapng` (SHA-256
`E074073A18DDD7E96A8C538D331C7B97DB9D6646F331087C7005BEC73BDAF6EF`)
enthalten jeweils zweimal dieselbe 22-Byte-SysEx vom PC-Editor über OUT 03.
Es ist keine MIDI-Antwort über IN 83 enthalten. Der Nutzer bestätigte den
sichtbar erfolgreichen Wechsel P10 „Baby Cry“ → P11 „Cream OD“ sowie die
Gegenprobe P11 → P10.

```text
P11: f021257f514d4532120002000000000000000a0000f7
P10: f021257f514d453212000200000000000000090000f7
```

Die Nachrichten unterscheiden sich ausschließlich an Offset 18 (nullbasiert
einschließlich F0): `0A` für P11 und `09` für P10. Damit ist Offset 18 für diese
beiden kontrollierten Editorwechsel als nullbasierter Ziel-Presetindex
bestätigt. Nicht bestätigt sind die allgemeine Gültigkeit über weitere Bänke,
die Bedeutung der übrigen Felder und ob die unmittelbar wiederholte zweite
Nachricht erforderlich ist. Daraus folgt keine allgemeine Schreibfreigabe;
Presetübertragung durch WyrmTone bleibt gesperrt.

### Gegenprobe P11 → P01 und Abgrenzung zur Matribox II Pro

Die kontrollierte Datei `07_matribox_editor_select_P11_to_P01.pcapng`
(SHA-256 `BFA1B37FB948B2858B072252F476CD6C5ACB05B77B2241A10D053504BFC0E903`)
enthält auf OUT 03 erneut zweimal dieselbe vollständige 22-Byte-Nachricht. Der
Nutzer bestätigte den sichtbaren Wechsel P11 → P01 im PC-Editor.

```text
P01: f021257f514d453212000200000000000000000000f7
```

Damit sind für diese drei kontrollierten Ziele folgende Zuordnungen bestätigt:

| sichtbares Preset | Geräteindex an Offset 18 | Wiederholung | Abstand im Mitschnitt |
|---|---:|---:|---:|
| P01 | 0 / `00` | 2 identische Nachrichten | 2,881 ms |
| P10 | 9 / `09` | 2 identische Nachrichten | 2,417 ms |
| P11 | 10 / `0A` | 2 identische Nachrichten | 1,867 ms |

Die drei Beobachtungen bestätigen die nullbasierte Abbildung
`Geräteindex = sichtbare Presetnummer - 1` nur für P01, P10 und P11. Sie
bestätigen außerdem, dass der PC-Editor jeden dieser Wechsel in den untersuchten
Mitschnitten zweimal sendete. Ob die Wiederholung technisch erforderlich ist,
bleibt unbekannt; es gab keine MIDI-Nutzdatenantwort auf IN 83. Der Offline-Parser
behandelt die von TShark gelieferten MIDI-Nutzfelder ebenso wie rohe
USB-MIDI-Vierergruppen, entfernt CIN-/Kabelbytes und Padding, setzt fragmentierte
SysEx zusammen und weist unvollständige Nachrichten sowie nicht zuordenbaren
Geräteverkehr ausdrücklich aus.

### WyrmTone-Hardware-Evidenz für P01

Am 14.09.2026 wurde die separate P01-Debug-Probe über Android MIDI mit einem
Samsung SM_F946B und echter Matribox-1-Hardware ausgeführt. Nach ausdrücklicher
Sicherheits- und Testbestätigung sendete WyrmTone zweimal die unveränderte bekannte
22-Byte-P01-Referenz mit ungefähr 3 ms Abstand. Android akzeptierte beide
Sendecalls; die Matribox wechselte sichtbar von einem anderen Preset auf P01.
Der Port wurde danach geschlossen und die Probe für diese Verbindung als
verbraucht behandelt. Es wurde kein Save/Store oder Überschreiben ausgeführt.

Diese WyrmTone-Hardware-Evidenz gilt ausschließlich für P01 beziehungsweise
Geräteindex 0. Sie beweist weder, dass zwei Sendecalls oder 3 ms protokollseitig
notwendig sind, noch eine Geräteantwort. P10 und P11 besitzen weiterhin nur die
oben dokumentierte PC-Editor-/Display-Evidenz. Eine allgemeine Presetauswahl- oder
Schreibfreigabe folgt daraus nicht.

Die separate Debug-Probe kann weiterhin ausschließlich die bestätigte
P01-Referenz zweimal mit festem Abstand senden. Sie ist standardmäßig in Flutter
und nativ deaktiviert, nicht parametrisierbar und keine allgemeine
Presetfreigabe. Vollständige Presetübertragung bleibt gesperrt.

Der Offline-Vergleich des öffentlichen Projekts
`hurricaneabel/Matribox_II_Pro_MidiCon` erfolgte am Commit
`f76dace6dfb9b19ea55e85e52086a41b4d5ef237`. Im untersuchten Baum war keine
Lizenzdatei vorhanden; WyrmTone übernimmt daraus keinen Code. Das Projekt
beschreibt die Matribox II Pro und trennt sich technisch klar von den eigenen
Matribox-1-Captures:

- Preset- und Banksteuerung wird dort über MIDI CC/Program Change beschrieben.
- Empfangsdecoder verwenden andere SysEx-Strukturen: Presetdaten ab 40 Byte,
  Blockstatus ab 48 Byte und Modelle mit 108 oder 128 Byte.
- Die II-Pro-AMP-Tupel `(1,9)`, `(4,7)` und `(5,9)` stimmen mit den lokal
  installierten Matribox-1-XML-Codes für Calif Star CL, Sol 100 OD und
  Sol 100 LD überein. Das ist eine unabhängige Namens-/Codekorrelation, keine
  Bestätigung gleicher Nachrichten oder Schreibbefehle.
- Der II-Pro-Listener führt Softwarezustand aus empfangenen Nachrichten; daraus
  folgt kein bestätigtes Geräte-Readback und keine Matribox-1-Kompatibilität.

Die maschinenlesbare Matrix weist II-Pro-Hinweise deshalb als eigenes
`sourceTarget` aus. CC/PC-Angaben, empfangene Modell-SysEx und Matribox-1-QME2-
Nachrichten bleiben getrennte Familien. Für die nächste Matribox-1-Evidenz ist
je Fähigkeit ein eigener kontrollierter Capture nötig.


## Full Preset Laboratory: erneute Offline-Auswertung vom 14.09.2026

Die Quellen blieben lokal und unveraendert: Sonicake Matribox Software 1.1.1,
`algorithm.xml` (SHA-256
`EF6668D29038CD5556A9A3557BD381E290E019270DAD72CD34291218B8F83DAD`) und
`preset.xml` (SHA-256
`74CA199EB3C072EB84BEA45239A2673AC87CE8041D8D9685E89EB74A9E680B60`).
Beide Herstellerdateien sind QME-50-bezogen. Die Sprachressource belegt
Save-Dialoge und `.prst`-Export als Editorfunktionen, aber keine
Protokollbytes. Kein lokales Herstellerartefakt benennt Matribox II oder II Pro.

`tool/matribox_capture_inspector.dart` liest bestehende PCAP-/PCAPNG-Dateien
nur offline. Es behaelt Richtung, Zeitstempel, Reihenfolge, vollstaendiges Hex,
Laenge und unbekannte Nachrichten. Identische Nachrichten erhalten eine
Gruppen-ID und Gesamtzahl, ohne die zeitliche Sequenz zusammenzufassen.
`usbaudio.midi.event` wird bevorzugt; falls TShark wegen fehlender
Deskriptorbindung nur `usb.capdata` liefert, wird derselbe gespeicherte
USB-MIDI-Payload verwendet. CIN-/Kabelbytes und Padding werden entfernt,
fragmentierte SysEx werden zusammengesetzt. Beispiel:

```text
dart run tool/matribox_capture_inspector.dart --capture "<capture.pcapng>" --output "<report.json>"
```

### Connect-/Synchronisations-Capture

Der korrigierte Fallback rekonstruiert aus
`01_matribox_editor_connect_only_retry.pcap` 4.607 vollstaendige SysEx:
2.304 Host-zu-Geraet und 2.303 Geraet-zu-Host. Beobachtete Laengen:

| Richtung | Laenge | Anzahl | Einordnung |
|---|---:|---:|---|
| Host -> Geraet | 14 | 6 | QME2, unklassifizierte Anfragefamilie |
| Host -> Geraet | 15 | 45 | QME2, unklassifizierte Anfragefamilie |
| Host -> Geraet | 16 | 200 | QME2, Beginn wiederkehrender Presetzyklen |
| Host -> Geraet | 17 | 200 | QME2, Anfrage innerhalb eines Presetzyklus |
| Host -> Geraet | 18 | 62 | QME2, weitere Anfragefamilie |
| Host -> Geraet | 19 | 1.791 | QME2, Teilanfragen innerhalb der Presetzyklen |
| Geraet -> Host | 16 | 2 | QME2-Antwort |
| Geraet -> Host | 17 | 1 | QME2-Antwort |
| Geraet -> Host | 18 | 199 | QME2, Teil 9 der Presetzyklen |
| Geraet -> Host | 20 | 200 | QME2, Status/Kopf eines Presetzyklus |
| Geraet -> Host | 28 | 61 | QME2-Antwort |
| Geraet -> Host | 42 | 2 | QME2-Antwort |
| Geraet -> Host | 46 | 199 | QME2, Teil 8 der Presetzyklen |
| Geraet -> Host | 58 | 5 | QME2; einzelne Payloads enthalten ASCII-Namen |
| Geraet -> Host | 89 | 40 | QME2-Antwort |
| Geraet -> Host | 162 | 1 | QME2-Antwort |
| Geraet -> Host | 210 | 1.593 | QME2, Teile 0 bis 7 der Presetzyklen |

Observed: Nachrichten mit Headerbyte 0x11 gehen vom Host aus; darauf folgen
zeitnah Nachrichten mit Headerbyte 0x12 vom Geraet. In den grossen Zyklen
laufen beobachtete Slotwerte 0 bis 98. Teile 0 bis 7 sind 210 Byte lang, Teil 8
ist 46 Byte und Teil 9 ist 18 Byte. Der Dateiname `retry`, doppelte
Uebertragungen und ein nicht symmetrischer Rest verbieten, die Rohanzahl als
exakte Presetanzahl oder notwendige Wiederholungsregel zu interpretieren.

Correlated: Die 210-Byte-Payloads bestehen nach dem Familienkopf weitgehend aus
Nibblepaaren. Deren Zusammenfassung zu Bytes zeigt im ersten Teil lesbare
ASCII-Namen (zum Beispiel `MatriBox`, `60's OD`, `Natural CL` und
`Morden Lead`), geordnete kleine Blockwerte und in weiteren Teilen zahlreiche
plausible Float32-Werte. Pro Slot werden neun Teilnummern beobachtet. Zusammen
mit der neunblockigen Struktur der lokalen `preset.xml` ist dies starke
Evidenz fuer einen Editor-initiierten Preset-Readback beziehungsweise
Bibliothekssync. Feldgrenzen, Checksummen, Vollstaendigkeit, Slotnummerierung
und die Schreibrichtung sind noch nicht bestaetigt. Die 58-/89-/162-Byte-
Familien werden nicht als Presetname, IR, NAM oder Firmware klassifiziert,
solange kontrollierte Gegenproben fehlen.

Die kurzen Aktionscaptures 02 bis 07 enthalten weiterhin nur ihre bekannten
Nachrichten: 02/03 je eine Host-zu-Geraet-34-Byte-Parameternachricht, 04 eine
bytegleiche Geraet-zu-Host-34-Byte-Parameternachricht und 05/06/07 jeweils zwei
identische Host-zu-Geraet-22-Byte-Presetauswahlen. Keine dieser Dateien enthaelt
eine unbekannte Laenge, eine Nachricht ueber 34 Byte oder eine bestaetigte
MIDI-Antwort auf die Presetauswahl.

### Status der Full-Preset-Fragen

| Frage | Status | Begrenzte Aussage |
|---|---|---|
| Live-Parameter | CONFIRMED | Kontrollierte Editoraktion Gain erzeugt genau eine 34-Byte-Nachricht mit Algorithmuscode, Parameterindex und Float32-Wert; allgemeine Aussage fuer alle Parameter bleibt offen. |
| Algorithmuswechsel | CORRELATED | Algorithmuscodes korrelieren zwischen XML und 34-Byte-Nachrichten verschiedener geladener Modelle; die Sequenz eines Modellwechsels wurde nicht isoliert. |
| Bypass/Enable | HYPOTHESIS | XML und Presetvorlage enthalten `switch`; keine kontrollierte Wire-Aktion ordnet das Feld zu. |
| Load/Recall | CONFIRMED | P01/P10/P11-Auswahl ist als 22-Byte-Familie sichtbar bestaetigt; in den isolierten Auswahldateien folgt keine MIDI-Antwort. |
| Save/Store | UNKNOWN | Editor-UI und Dialogtexte belegen die Funktion, aber kein vorhandener Capture trennt Live-Aenderungen vom Store-Vorgang. |
| Presetname | CORRELATED | Grosse Readback-Kandidaten enthalten feste ASCII-Bereiche mit plausiblen Presetnamen; genaue Feldlaenge, Padding und Schreibweg sind offen. |
| Readback | CORRELATED | Direkte Request/Response-Zyklen liefern neun strukturierte Teile je beobachtetem Slot; dass dies der vollstaendige und spaeter rueckschreibbare Presetzustand ist, ist noch nicht bewiesen. |

### Kleinste noch notwendige Capture-Serie

Capture A ist durch den Connect-/Sync-Capture 01 und den isolierten P11-zu-P01-
Capture 07 ausreichend abgedeckt. Separate Captures B und C sind redundant,
weil Capture F dieselben sechs markanten Parameteraktionen mit Pausen enthaelt.
Notwendig bleiben deshalb nur D, E, F und G:

1. `matribox1_p01_amp_model_switch.pcapng`: P01, Sol 100 OD -> Sol 100 LD,
   zwei Sekunden warten, zurueck zu Sol 100 OD, zwei Sekunden warten, nicht
   speichern.
2. `matribox1_p01_block_bypass.pcapng`: einen eindeutig benannten Block
   OFF -> ON, eine Sekunde warten, ON -> OFF, zwei Sekunden warten, nicht
   speichern.
3. `matribox1_p01_store.pcapng`: P01 auf Sol 100 OD setzen; Gain 17, Bass 23,
   Middle 67, Treble 31, Presence 73 und Volume 47 jeweils mit einer Sekunde
   Abstand setzen; zwei Sekunden warten; im offiziellen Editor Save/Store
   gezielt auf P01 ausfuehren; drei Sekunden warten; Capture stoppen.
4. `matribox1_p01_recall_after_store.pcapng`: Capture starten; P10 waehlen,
   drei Sekunden warten; P01 waehlen, fuenf Sekunden warten; nichts aendern;
   Capture stoppen und die sechs Werte manuell pruefen.

Alle vier Dateien bleiben ausserhalb von Git, Assets und APK. Diese Serie
beobachtet ausschliesslich Herstellerkommunikation. Sie ist keine Freigabe,
die beobachteten Nachrichten aus WyrmTone zu senden.


### Auswertung der vier Labor-Captures

Die vier am 14.09.2026 aufgenommenen Dateien wurden nur offline gelesen:

- `matribox1_p01_amp_model_switch.pcapng`: SHA-256
  `A1124C05E9CF4FE2CD9B6F6DE4919A2A6E082D42DF070EA223D454851CCD5FDD`
- `matribox1_p01_block_bypass.pcapng`: SHA-256
  `FA41693D78A5F7728906278033AA3AEF7C9F2373B3CD278149A789A37C905D94`
- `matribox1_p01_store.pcapng`: SHA-256
  `35D845D3855A4DABFC1E57A4F8C53227729FF0A77282F5AB5ACC4BB83169CC1C`
- `matribox1_p01_recall_after_store.pcapng`: SHA-256
  `5FB1EF134F38339D40426CC1401E398589E50AB461C631B46DE9C2A0865240D8`

Alle vier enthalten den USB-Deskriptor 84EF:0054. In den untersuchten
MIDI-Endpunkten ist ausschliesslich Host-zu-Geraet-Verkehr vorhanden; eine
MIDI-Antwort wurde nicht beobachtet.

**Algorithmuswechsel -- confirmed fuer die Nachrichtenfamilie:** Der Capture
enthaelt zwei 22-Byte-QME2-Nachrichten mit dem bekannten Nibble-zu-UInt32-LE-
Algorithmusfeld an Offset 13 bis 20. Die Codes sind `0x07000059`
(Sol 100 LD laut lokaler XML) und danach `0x0700004A` (Calif Star OD), mit
4.707 ms Abstand. Der beobachtete zweite Code ist daher nicht Sol 100 OD
(`0x07000047`). Die Familie belegt eine direkte Algorithmusauswahl; welche
UI-Aktion beabsichtigt war und ob weitere Initialisierungen in anderen
Situationen folgen, bleibt getrennt zu bewerten.

**Bypass/Enable -- confirmed fuer den kontrollierten Toggle:** Es wurden genau
zwei MIDI-Control-Change-Nachrichten beobachtet: Kanal 2, Controller 49
(`0x31`), zuerst Wert 0 und nach 5,021 s Wert 127. Keine SysEx-Nachricht und
keine MIDI-Antwort trat auf. Die Zuordnung von CC49 zu dem konkret bedienten
Block ist ohne die Blockbezeichnung nicht bestaetigt; eine allgemeine
Blocknummernformel wird nicht abgeleitet.

**Live-Parameter -- confirmed fuer alle sechs AMP-Parameter von Sol 100 OD:**
Der Store-Capture enthaelt 118 gueltige 34-Byte-Parameternachrichten. Der Editor
sendete jeden durchlaufenen Zwischenwert, nicht nur den Endwert. Bestaetigte
Endwerte und Indizes sind Gain 17 / 0, PRES 73 / 1, Master 47 / 2, Bass 23 / 3,
Middle 67 / 4 und Treble 31 / 5; alle tragen Algorithmuscode `0x07000047`.

**Save/Store -- confirmed als beobachteter und erfolgreicher P01-Ablauf:**
12,752 s nach der letzten Parameternachricht sendete der Editor innerhalb
0,620 ms einen Burst aus exakt fuenf QME2-Nachrichten mit Laengen
34, 34, 18, 64 und 22 Byte. Die erste 34-Byte-Nachricht enthaelt den
ASCII-Bereich `CKY 96 STUD\0`. Es wurde dabei kein Full-Preset-Dump der
210-Byte-Readback-Familie und keine MIDI-Antwort beobachtet. Die einzelnen
Bedeutungen der fuenf Nachrichten bleiben unklassifiziert; insbesondere wird
keine davon isoliert als allein ausreichender Store-Befehl bezeichnet.

**Persistenz/Recall -- confirmed fuer diesen P01-Laborzustand:** Der
Recall-Capture enthaelt nur die bekannten, jeweils doppelt gesendeten
Presetselections P10 und P01. Marcel bestaetigte danach auf der Hardware
weiterhin Gain 17, PRES 73, Master 47, Bass 23, Middle 67 und Treble 31. Damit
ist bestaetigt, dass der unmittelbar zuvor im offiziellen Editor gespeicherte
P01-Zustand den Wechsel P01 -> P10 -> P01 ueberstand. Es folgt daraus noch
keine vollstaendige Preset-Serialisierung, kein WyrmTone-Backup/Restore und
keine Schreibfreigabe fuer den beobachteten Store-Burst.

Die geplanten Captures D bis G sind damit abgeschlossen. Vor einer weiteren
Hardwareaktion werden zuerst Segmentfelder, Store-Burst und Readback offline
gemeinsam bewertet.

## Vertiefte OUT-Auswertung und Endpoint-Lücke (14.09.2026, zweiter Durchgang)

Erneute Offline-Auswertung derselben vier Dateien (identische SHA-256 wie
oben) mit `tool/matribox_capture_inspector.dart` sowie gezielten TShark-
Abfragen. Kein Parser-/App-Code geändert, keine neue Datei kopiert, keine
Gerätekommunikation.

### Endpoint-Inventar: 0x83 fehlt vollständig in allen vier Dateien

`usb.endpoint_address` über alle Frames (nicht nur `usb.data_len > 0`) zeigt
in allen vier Dateien ausschließlich 0x02 (isochron, USB-Audio-Stream,
Mehrheit der Pakete), 0x03 (Bulk OUT, MIDI) und 0x80 (Control, vier
Enumerationspakete). **Kein einziges Frame mit `usb.endpoint_address == 0x83`
existiert in einer der vier Dateien** — auch keine leere Poll-/Complete-URB.

Das ist eine **Capture-Lücke, kein Beleg für Geräte-Schweigen**. Der Status
für Geräte→Host in diesem Auswertungsdurchgang lautet für alle sechs Marker
und für Store/Recall ausdrücklich `NOT CAPTURED`, nicht „NOT FOUND“, „NO
RESPONSE“ oder „DEVICE SILENT“.

### Vergleich mit dem alten Connect-Capture (01)

| Merkmal | 01 (Connect/Sync, 13.09.2026) | vier neue Labor-Captures (14.09.2026) |
|---|---|---|
| USBPcap-Quelle | USBPcap (Bus 1), Legacy-`.pcap`, kein gespeicherter Interface-Name | USBPcap1 (Bus 1), `.pcapng`, Interface-Name `\\.\USBPcap1` gespeichert |
| USB-Bus | 1 | 1 |
| USB-Geräteadresse | 12 | 59 |
| Endpoint 0x02 (isochron) | 40.620 Pakete | vorhanden (2.254–11.958 je Datei) |
| Endpoint 0x03 (Bulk OUT) | 5.030 Pakete, transfer_type 0x03 | 2–254 Pakete je Datei, transfer_type 0x03 |
| Endpoint 0x83 (Bulk IN) | **17.446 Pakete**, transfer_type 0x03 | **0 Pakete** |
| 210/46/18-Byte-Zyklen | vorhanden (0–7×210, 8×46, 9×18) | nicht vorhanden (keine 0x83-Daten) |

Unterschiedliche Geräteadresse (12 vs. 59) ist normale Windows-Neuvergabe bei
späterer Neuverbindung, kein Hinweis auf ein anderes Gerät oder Interface.
Bus, Endpointnummern und Transferarten (0x02 isochron, 0x03 Bulk) sind
identisch; das Interface-Layout ist damit vergleichbar aufgebaut.

Kein im Dateiheader gespeicherter Capture-Filter-String war in den vier neuen
Dateien auffindbar (`capinfos -a` und Feldsuche liefern keinen Treffer). Zwei
Erklärungen bleiben offen und sind nicht gegeneinander entschieden:

1. **Hypothese (Verhalten):** Die Bulk-IN-Endpoint 0x83 liefert bei diesem
   Gerät nur dann URBs, wenn der Editor aktiv einen Lesevorgang anstößt (wie
   beim vollständigen Connect/Sync in Capture 01). Reine UI-Aktionen wie
   Algorithmuswechsel, Bypass, Parameterschreiben oder Store/Recall würden
   dann grundsätzlich keinen Host-seitigen Lesevorgang auslösen, solange kein
   erneuter Sync erfolgt.
2. **Hypothese (Capture-Setup):** Die Aufnahmesitzung für die vier neuen
   Dateien hat 0x83 aus einem nicht mehr rekonstruierbaren Grund (z. B. Start
   der Aufnahme erst nach Verbindungsaufbau, oder eine nicht gespeicherte
   Anzeigefilter-/Auswahleinstellung beim Sichern als `.pcapng`) nicht
   erfasst, obwohl der Endpoint aktiv war.

Keine der beiden Hypothesen ist mit den vorhandenen Metadaten allein
entscheidbar; keine wird als Tatsache behauptet.

### Store-Capture: vollständige chronologische Zerlegung

121 vollständige Host→Gerät-Nachrichten, 0 Geräte→Host (siehe oben, NOT
CAPTURED). 116 reguläre 34-Byte-QME2-Parameternachrichten plus ein Burst aus
fünf Nachrichten unmittelbar um Save/Store.

**Die sechs Markerwrites** (Algorithmuscode `0x07000047` / Sol 100 OD in
allen sechs Gruppen; Wert ist der von `ConfirmedParameterCodec` dekodierte
Float32):

| Marker | XML-Parameterindex | Anzahl Zwischenwerte | erster Wert @ ms | letzter/Endwert @ ms |
|---|---:|---:|---:|---:|
| Gain | 0 | 13 | 29 @ 3.731,4 | **17** @ 5.484,5 |
| Presence | 1 | 23 | 51 @ 8.949,4 | **73** @ 11.499,4 |
| Bass | 3 | 29 | 49 @ 18.108,3 | **23** @ 21.382,1 |
| Volume/Master | 2 | 3 | 49 @ 28.134,7 | **47** @ 28.984,8 |
| Middle | 4 | 25 | 49 @ 32.471,1 | **67** @ 37.802,5 |
| Treble | 5 | 23 | 51 @ 41.994,4 | **31** @ 43.912,8 |

Alle sechs Endwerte stimmen exakt mit den vorgegebenen Markerwerten überein
(Gain 17, Bass 23, Middle 67, Treble 31, Presence 73, Volume 47) —
**FOUND, Host→Device, confirmed** für die Schreibrichtung. Die tatsächliche
Bedienreihenfolge war Gain → Presence → Bass → Volume → Middle → Treble, nicht
die im Auftrag genannte Reihenfolge; das ist nur eine Beobachtung zur
Zuordnung der Zeitstempel, keine Protokollaussage.

**Store/Commit-Burst:** 12.752,298 ms nach der letzten Parameternachricht
(Treble, 43.912,825 ms) sendet der Editor innerhalb von 0,620 ms exakt fünf
Nachrichten einer bisher unbeobachteten Familie (Kopfbyte 9 = `0x11`, zuletzt
`0x12`, statt `0x10` bei Parameterschreiben oder `0x00` bei Presetauswahl):

| # | Länge | Kopf (Offset 8–9) | Offset 12 | Inhalt |
|---:|---:|---|---:|---|
| 1 | 34 | `12 11` | `00` | ASCII `CKY 96 STUD\0` ab Offset 21 — Presetname |
| 2 | 34 | `12 11` | `04` | alle übrigen Bytes 0 |
| 3 | 18 | `12 11` | `05` | Offset 14 = `04`, sonst 0 |
| 4 | 64 | `12 11` | `07` | alle übrigen Bytes 0 |
| 5 | 22 | `12 12` | `02` | alle übrigen Bytes 0; vom Inspector explizit als „rejected preset-selection candidate“ (`invalidOffset: 9`) markiert, da Offset 9 nicht dem bestätigten Presetauswahl-Header entspricht |

Damit zu den Auftragsfragen:

- **Neue Nachrichtenfamilie:** ja, correlated — Kopfbyte 9 = `0x11`/`0x12`
  tritt sonst in keiner der vier Dateien auf.
- **Kleiner Store-/Commit-Befehl:** hypothesis — Nachricht 5 (22 Byte, `12 12
  … 02 …`) ist der einzige Kandidat mit eigenem Header und passender Kürze;
  ihre Bedeutung als tatsächlicher Commit ist nicht bestätigt, nur zeitlich
  und strukturell auffällig.
- **P01-Index in diesem Burst:** nicht gefunden — keine der fünf Nachrichten
  enthält einen erkennbaren Presetindex im Format der bekannten 22-Byte-
  Presetauswahl (Offset 18/09 hex Muster).
- **Größerer Dump (210/46/18-Byte-Familie):** nicht vorhanden.
- **Wiederholungen:** keine; alle fünf Nachrichten sind einmalig und
  unterschiedlich lang.
- **Kein zusätzlicher Befehl:** trifft nicht zu — es gibt eindeutig
  zusätzlichen Host→Gerät-Verkehr nach dem letzten Parameterwrite.

Geräte→Host-Antwort auf den Burst: `NOT CAPTURED` (siehe Endpoint-Inventar
oben), nicht „keine Antwort“.

### Algorithmuswechsel — Byte-Diff

Zwei 22-Byte-Nachrichten, 4.707,297 ms auseinander:

```text
Sol 100 LD:     F0 21 25 7F 51 4D 45 32 12 10 03 00 01 05 09 00 00 00 00 00 07 F7
Calif Star OD:  F0 21 25 7F 51 4D 45 32 12 10 03 00 01 04 0A 00 00 00 00 00 07 F7
```

Einziger Unterschied: Offset 13 (`05`→`04`) und Offset 14 (`09`→`0A`), also
genau die Nibble-Positionen des bekannten Algorithmuscode-Felds
(`0x07000059` → `0x0700004A`). Auftragsannahme „Sol 100 OD → Sol 100 LD →
Sol 100 OD“ trifft auf die tatsächlichen Codes nicht zu: Der zweite Code ist
laut lokaler `algorithm.xml` **Calif Star OD**, nicht Sol 100 OD
(`0x07000047`); vermutlich wurde am Gerät ein anderes Amp-Modell gewählt als
in der Aufgabenbeschreibung angenommen. Kein zusätzlicher Parameter- oder
Blockverkehr um die beiden Nachrichten; nur der Algorithmus wird übertragen,
kein kompletter Block. Geräte→Host: `NOT CAPTURED`.

### Bypass — Byte-Diff

Exakt zwei Nachrichten, keine SysEx, reine MIDI-Control-Change, Kanal 2,
Controller 49 (`0x31`), 5.021,515 ms auseinander:

```text
OFF: B1 31 00
ON:  B1 31 7F
```

Einziger Unterschied ist das dritte Byte (`00` vs `7F`); Länge, Kanal und
Controller sind identisch. Starker Bool-Kandidat (0/127 statt eines
Zwischenwertbereichs). Blockzuordnung von CC49 bleibt ohne Blockbezeichnung
unbestätigt. Geräte→Host: `NOT CAPTURED`.

### Recall-Capture

Ausschließlich vier Host→Gerät-Nachrichten, keine anderen: P10 zweimal
(2,251 ms Abstand), dann P01 zweimal (5,603 ms Abstand), Gesamtabstand
P10→P01 8.250,820 ms. Keine Parameter-, Algorithmus- oder Store-Nachricht in
dieser Datei. Geräte→Host: `NOT CAPTURED` — nicht „keine Antwort“, da 0x83 in
dieser Datei durchgehend fehlt.

### Warum Persistenz-Readback aktuell nicht verifizierbar ist

Alle sechs Marker sind für die Schreibrichtung `FOUND` (siehe Tabelle oben).
Für die Geräteseite gilt für alle sechs Marker sowie für Store und Recall
`NOT CAPTURED`: Die vorhandenen Dateien enthalten keine einzige 0x83-Nachricht,
also strukturell keine Daten, in denen ein Readback auch nur ambig auftauchen
könnte. Ein automatischer Soll/Ist-Vergleich (Punkt F/H des Auftrags) würde
auf diesen vier Dateien zwangsläufig nur „kein Vergleich möglich“ statt eines
echten Ergebnisses liefern und wird deshalb nicht gebaut, solange 0x83-Daten
fehlen. Die bisherige Aussage „Persistenz confirmed“ im Abschnitt oben beruht
weiterhin ausschließlich auf Marcels manueller Sichtprüfung an der Hardware,
nicht auf Wire-Evidenz.

### Kleinster nächster Capture-Schritt

Kein Parameter-, Preset- oder Store-Test ist als nächstes nötig — diese sind
für die Schreibrichtung bereits vollständig ausgewertet. Nötig ist ein
Capture, das nachweislich 0x83-Verkehr enthält:

1. Aufnahme auf demselben Interface (`USBPcap1`, Bus 1) ohne Anzeige- oder
   Capture-Filter starten, bevor der Editor verbunden wird.
2. Editor wie gewohnt verbinden lassen (das löst laut Capture 01 den
   210/46/18-Byte-Sync-Zyklus über 0x83 aus) und diesen Sync im Capture
   belassen.
3. Erst danach P01 mit den sechs Markerwerten setzen, Save/Store ausführen,
   auf P10 und zurück auf P01 wechseln — weiterhin in derselben laufenden
   Aufnahme, ohne zwischendurch zu stoppen.
4. Optional zusätzlich: nach dem Store gezielt eine erneute Trennung/
   Neuverbindung des Editors (oder eine vorhandene „Sync“/„Refresh“-Funktion)
   auslösen, damit ein zweiter vollständiger Readback-Zyklus die gespeicherten
   Werte tatsächlich vom Gerät abfragt.

Erst mit einem solchen Capture lässt sich prüfen, ob die sechs Markerwerte in
den 210-Byte-Segmenten auftauchen, und ein Verifier mit einem expliziten
`READBACK_NOT_CAPTURED`-Zustand sinnvoll gegen echte Daten testen.

## Vollständiger Device→Host-Readback und Persistenzbeweis (14.09.2026, dritter Durchgang)

Neue Datei `matribox1_p01_full_readback_after_store.pcapng`
(SHA-256 `77370B22BAF759DA1B5D8C919BFF0BDE24E8D9C21E93BA77E4E353E68488D15E`),
1.870.416 Byte, 17,16 s, USBPcap1/Bus 1/Geräteadresse 59. Sequenz: Editor
vollständig geschlossen, Aufnahme ohne Filter gestartet, danach Editor neu
verbunden (voller Sync), 5 s Pause, P10, 3 s Pause, P01, 5 s Pause, Stop. Nur
offline mit `tool/matribox_capture_inspector.dart` und gezielten
TShark-/Node-Auswertungen gelesen; kein Parser-/App-Code geändert, kein
Commit, kein Push, keine Gerätekommunikation.

### Endpoint-Check (Pflichtprüfung vor jeder Interpretation)

Diesmal **vorhanden**: 17.447 Frames auf 0x83 (Bulk, Geräteadresse 59, Bus 1)
und 4.716 Frames auf 0x03. Damit entfällt die bisherige `NOT CAPTURED`-
Einschränkung für diese Datei; echte Geräteantworten liegen vor.

### Zyklus-Rekonstruktion

4.609 vollständige Nachrichten (2.307 Host→Gerät, 2.302 Gerät→Host). Die
bekannten Segmentlängen aus Capture 01 treten erneut auf: 1.593×210 Byte,
199×46 Byte (Teil 8), zugehörige 18-Byte-Footer (Teil 9, ohne Nutzdaten nach
Nibble-Dekodierung — reines Zyklusende-Signal mit abweichendem Header
`... 01 00 05 00 00 00 09 F7`, nicht dem sonst konstanten `01 00 03 01 ...`).

Reihenfolge: **99 Slots Factory-Bank** (Slot 0 = „MatriBox“, Slot 1 = „60's
OD“ … Slot 98), danach **99 Slots User-Bank** (Slot 0 = „CKY 96 STUD“, Slot 1
= „OLA SATAN V2“, Slot 2 = „Natural CL“, Slot 3 = „Morden Lead“ … stimmt für
alle 15 geprüften Slots exakt mit der im Editor sichtbaren User-Presetliste
P01–P15 überein), danach ein einzelner **wiederholter** zehnteiliger Zyklus
für User-Slot 0 („CKY 96 STUD“ erneut, Sequenz 4452–4470). Jeder Slot besteht
aus genau Teil 0–7 (210 Byte) + Teil 8 (46 Byte) + Teil 9 (18 Byte, Footer).
Slotnummer steht an Offset 14 (LE, low byte) im rohen Header, Teilnummer an
Offset 16; beide sind Klartextbytes, kein Nibble-Paar.

**P01-Anker — CONFIRMED:** Der String „CKY 96 STUD“ tritt in den
rekonstruierten Zyklen ausschließlich in Teil 0 von User-Slot 0 auf (zweimal,
identisch) und stimmt mit dem Editor-Header aus dem eingangs gezeigten
Screenshot überein. Zusätzlich stimmen 14 weitere aufeinanderfolgende
Slotnamen (User Slot 1–14) exakt mit den im Editor sichtbaren P02–P15
überein. Diese Namens- und Reihenfolgekorrelation ist eindeutig einem
einzigen Zyklus zugeordnet; „User-Slot 0 = P01“ wird auf dieser Basis als
bestätigt behandelt.

### Markersuche — Ergebnis: alle sechs CONFIRMED

Nibble-Dekodierung (High-/Low-Nibble je Bytepaar → ein Byte) über Teil 0–7
von User-Slot 0 ergibt 768 zusammenhängende Bytes. Eine Float32-LE-Suche über
jeden Byte-Offset (nicht nur 4-byte-aligned) liefert für jeden Marker genau
einen einzigen Treffer, alle vier-byte-aligned, alle in einem zusammen-
hängenden Block Offset 188–208 (Grenze Teil 1/Teil 2):

| Marker | Zielwert | Segment | Offset (global/lokal) | Raw Bytes (LE) | Encoding | Status |
|---|---:|---|---|---|---|---|
| Gain | 17 | Teil 1, letztes Feld | 188 / lokal 92 | `00 00 88 41` | Float32 LE | **CONFIRMED** |
| Presence | 73 | Teil 2, Feld 0 | 192 / lokal 0 | `00 00 92 42` | Float32 LE | **CONFIRMED** |
| Volume | 47 | Teil 2, Feld 1 | 196 / lokal 4 | `00 00 3C 42` | Float32 LE | **CONFIRMED** |
| Bass | 23 | Teil 2, Feld 2 | 200 / lokal 8 | `00 00 B8 41` | Float32 LE | **CONFIRMED** |
| Middle | 67 | Teil 2, Feld 3 | 204 / lokal 12 | `00 00 86 42` | Float32 LE | **CONFIRMED** |
| Treble | 31 | Teil 2, Feld 4 | 208 / lokal 16 | `00 00 F8 41` | Float32 LE | **CONFIRMED** |

Die Feldreihenfolge (Gain, Presence, Volume, Bass, Middle, Treble) ist exakt
identisch mit der aus den Live-Parameterschreibvorgängen bekannten
XML-Indexreihenfolge (idx 0–5) des AMP-Blocks — starke zusätzliche
Korrelation. Direkt danach (Offset 212) folgt ein siebtes Float32-Feld mit
Wert `50.0` (unveränderter XML-Default, kein Marker), danach Nullen; davor
(Offset 176–184) drei Nullfelder. Die Zuordnung dieser Nachbarfelder zu
konkreten weiteren AMP-Parametern bleibt HYPOTHESIS.

Der komplette zehnteilige Zyklus wiederholt sich am Ende der Aufnahme
byteidentisch für Teil 0–7 (Sequenz 4452–4466); alle sechs Werte wurden dort
unabhängig ein zweites Mal exakt bestätigt. Teil 8 unterscheidet sich
zwischen den beiden Wiederholungen an Offset 10 (`01` vs. `02`) und im
nibble-dekodierten Anhang, obwohl der Presetinhalt identisch ist — ein
inhaltsunabhängiger Zähler/Session-Wert ist damit ein plausiblerer Kandidat
als eine Inhalts-Prüfsumme; nicht abschließend geklärt.

### Store ↔ Readback-Korrelation — Ergebnis pro Marker

| Marker | STORE (Host→Device, vorheriger Capture) | READBACK (Device→Host, dieser Capture) | Ergebnis |
|---|---:|---:|---|
| Gain | 17 | 17 | **PASS** |
| Presence | 73 | 73 | **PASS** |
| Volume | 47 | 47 | **PASS** |
| Bass | 23 | 23 | **PASS** |
| Middle | 67 | 67 | **PASS** |
| Treble | 31 | 31 | **PASS** |

Wichtige Einschränkung zur Testart: Der Beweis stammt aus dem **initialen
Connect-/Sync-Lesevorgang** direkt nach Editor-Neustart, nicht aus einer
Reaktion auf den späteren expliziten P10→P01-Wechsel. Nach den beiden
Presetauswahl-Nachrichten für P01 am Ende der Aufnahme (Sequenz 4608/4609,
17.159,3 ms) folgt **keine einzige weitere Nachricht** bis zum Aufnahmeende —
bei durchgehend aktivem 0x83. Das bestätigt jetzt mit vollständiger
Endpoint-Abdeckung (nicht mehr `NOT CAPTURED`, sondern echte Abwesenheit),
was die vorherige kleine Recall-Datei bereits nahelegte: Eine reine
Presetauswahl über die UI löst keinen sichtbaren Geräte-Readback aus. Der
Persistenzbeweis gilt für „Store → Editor schließen → USB-Neuverbindung →
voller Gerätesync“, nicht für „Store → Recall-Klick → sofortige
Geräteantwort“.

Damit ist die Persistenz von Gain, Presence, Volume, Bass, Middle und Treble
für P01/„CKY 96 STUD“ über einen vollständigen App-Neustart und eine neue
USB-Sitzung hinweg direkt aus Geräte-Rohdaten bewiesen — ohne manuelle
Sichtprüfung. Kein Aussage über einen Power-Zyklus des Pedals selbst; das
wäre der einzig noch stärkere verbleibende Test.

### Vorläufige Segmentkarte, User-Slot 0

```text
Preset cycle (User Slot 0 / P01 / "CKY 96 STUD")
  Teil 0 (210 B, decoded 96 B)
    Offset 0–12:  Presetname ASCII "CKY 96 STUD\0"      CONFIRMED
    Offset 14–29: aufsteigende UInt16-LE-Liste 1..8      HYPOTHESIS (Blockreihenfolge?)
    Offset 30+:   weitere Zahlen-/Float-Felder           UNKNOWN
  Teil 1 (210 B, decoded 96 B)
    Offset 88 (lokal): Gain (Float32 LE) = 17             CONFIRMED
    übrige Felder                                          UNKNOWN
  Teil 2 (210 B, decoded 96 B)
    Offset 0–16 (lokal): Presence, Volume, Bass, Middle,
                          Treble (Float32 LE)              CONFIRMED
    Offset 20 (lokal): Float 50.0 (unveränderter Default)  HYPOTHESIS
    übrige Felder                                          UNKNOWN
  Teil 3–7 (210 B je)                                       UNKNOWN
  Teil 8 (46 B, decoded 14 B): vermutlich Zähler/Session   HYPOTHESIS
  Teil 9 (18 B, kein Payload): Zyklusende-Signal           CONFIRMED
```

Keine weiteren Feldnamen erfunden; alle nicht geprüften Bereiche bleiben
ausdrücklich UNKNOWN. Kein vollständiges Presetformat, kein Full-Preset-
Schreiber, keine Gerätekommunikation aus diesem Auswertungsschritt.

### Store-Burst, Bypass, Amp-Wechsel — unverändert, nur Statuslabel bestätigt

- Store-Burst-Schlussnachricht (22 Byte, Header `12 12`) bleibt
  `STORE_COMMIT_CANDIDATE`, nicht bestätigt.
- Bypass (CC2/49, `0x00`↔`0x7F`) bleibt CORRELATED, nicht auf weitere
  Effektblöcke verallgemeinert.
- Amp-Wechsel wird weiterhin nur als 22-Byte-Familie mit Algorithmuscode-
  Änderung an Offset 13/14 beschrieben; die vom Auftrag angenommene Abfolge
  „Sol 100 OD → Sol 100 LD → Sol 100 OD“ deckt sich laut lokaler XML weiterhin
  nicht mit dem beobachteten zweiten Code (Calif Star OD statt Sol 100 OD).

### Nächster sinnvoller Schritt

P01 bleibt unverändert; keine weitere Store-Aktion nötig. Offen und mit
kleinem Aufwand prüfbar: ob Teile 3–7 weitere Effektblöcke (FX1, FX2, CAB,
EQ, MOD, DLY, RVB, NR) in fester Reihenfolge enthalten — dafür würde sich ein
Vergleich von zwei Presets mit bekannten, unterschiedlichen Blockeinstellungen
eignen (rein offline gegen bereits vorhandene Captures, falls ausreichend
Varianz vorhanden ist, sonst ein weiterer gezielter Capture). Kein Verifier-
Code wurde in diesem Schritt gebaut; die obenstehende Tabelle ist ein
manueller Beleg, kein Tool-Output.

## Connect-/Readback-Auslöser und Offline-P01-Decoder (14.09.2026, vierter Durchgang)

Ausschließlich Offline-Analyse der bereits vorhandenen Dateien
(`matribox1_p01_full_readback_after_store.pcapng` und
`01_matribox_editor_connect_only_retry.pcap`). Neu hinzugekommen:
`tool/matribox_p01_readback_decoder.dart` (liest nur Dateien, öffnet keinen
MIDI-Port, sendet nichts, kein Writer) mit gezielten Tests in
`test/matribox_p01_readback_decoder_test.dart` (5 Tests, mit echten
Capture-Bytes, `flutter analyze` sauber). Kein Commit, kein Push, keine
Gerätekommunikation, P01 unverändert.

### Aufgabe 1+2: Connect-Sequenz und Readback-Start

Chronologische Rekonstruktion vor der ersten 210-Byte-Antwort (neue Datei,
Sequenz 1–95):

1. `F0…11 12 00 00 00 F7` (14 B, Host) → `…12 12 00 00 00 01 00 F7` (16 B,
   Gerät, +0,13 ms) — einfacher Ping, byteidentisch in beiden Captures.
2. `F0…11 13 00 00 00 F7` (14 B, Host) → 162-Byte-Antwort (Gerät) — einzige
   einmalige „Capability“/Statusantwort; ein Byte (Offset 14) und die letzten
   8 Byte unterscheiden sich zwischen den beiden Sessions (siehe unten).
3. `…11 13 02 00 07 F7` (14 B, je zweimal, Host) → 42-Byte-Antwort (Gerät,
   ebenfalls zweimal) — Inhalt unterscheidet sich zwischen den Sessions
   erheblich; keine erkennbare Slot-/Bank-Bedeutung, bleibt UNKNOWN.
4. Enumerationsschleife `…11 12 00 10 02 [00..13] F7` (15 B, je zweimal,
   Host) ↔ 89-Byte-Antworten (Gerät, je zweimal), Index 0x00–0x13 (20
   Werte) — vermutlich Geräte-/Firmware-Metadaten, nicht Presetdaten.
5. `…11 13 01 00 00 01 00 F7` (16 B, zweimal) → `…12 13 01 00 01 01 00 0C 1C
   01 40 F7` (20 B, zweimal) — Vorbereitungs-Handshake unmittelbar vor dem
   ersten Slot.
6. **`F0 21 25 7F 51 4D 45 32 12 13 01 00 02 01 00 01 F7`** (17 B, zweimal)
   → erste 210-Byte-Antwort (Teil 0, Slot 0, Factory „MatriBox“). Dieser
   17-Byte-Trigger ist **byteidentisch** in beiden unabhängigen Captures.

### Aufgabe 3: Request/Response-Korrelation über alle 199 Slots

199 eindeutige 17-Byte-Trigger (Duplikate entfernt) korrelieren **exakt
1:1 monoton** mit den 199 beobachteten Slot-Zyklen, in beiden Captures
identisch:

```text
F0 21 25 7F 51 4D 45 32 12 13 01 00 02 [BANK] [SLOT] 01 F7
```

- Offset 13 = **BANK**: `0x01` für die ersten 99 Trigger (Factory,
  Slot 0–98), `0x00` für die zweiten 99 (User, Slot 0–98) — CONFIRMED
  (n=99+99, beide Sessions gleich).
- Offset 14 = **SLOT**, 0-basiert, steigt streng monoton 0x00…0x62 (0–98)
  innerhalb jeder Bank — CONFIRMED.
- Für jeden Teil 1–9 folgt zusätzlich ein 19-Byte-Trigger (Host) je
  Antwort; 199×9 = 1.791 trifft exakt die beobachtete Gesamtzahl —
  CONFIRMED.
- Ein zusätzlicher, einzelner 200. Trigger mit **Offset 10 = 0x02** statt
  `0x01` tritt am Ende beider Sessions je einmal auf und liefert einen
  weiteren vollständigen Zyklus dessen Slot **in beiden Sessions exakt dem
  zuletzt aktiven Gerätepreset entspricht**: neue Session → Slot 0 (User,
  „CKY 96 STUD“ — direkt nach dem Store auf P01 aktiv), alte Session →
  Slot 9 (User, P10) — CORRELATED, starker Kandidat für „lies aktuell
  aktiven Slot“, aber nur n=2, keine kontrollierte Gegenprobe mit
  bewusst unterschiedlichem angefordertem Slot.

Kein Byte in den 210/46/18-Byte-Antworten selbst kodiert die Bank; Bank ist
ausschließlich im vorangehenden Trigger sichtbar. Der Decoder identifiziert
einen Zyklus deshalb über den mitgeschnittenen ASCII-Namen in Teil 0, nicht
über die Bank-/Slot-Bytes der Antwort.

### Aufgabe 4: Minimaler Read-Request-Kandidat

**„Read User P01“ (bestbelegter Kandidat, NICHT gesendet):**

```text
F0 21 25 7F 51 4D 45 32 12 13 01 00 02 00 00 01 F7
```

Status: **CONFIRMED auf Byte- und Feldebene** (byteidentisch in zwei
unabhängigen Sessions; Bank/Slot-Zuordnung durch 198 konsistente Beispiele
belegt) für „löst das Streamen von Bank=User, Slot=0 aus“ innerhalb des
bestehenden Enumerationsablaufs. **Nicht bestätigt:** ob dieser Trigger auch
**isoliert** (ohne vorherigen vollständigen Enumerationsstart ab Slot 0
Factory) funktioniert, und ob er ein eigenständiges „Random Access“-Read
ist oder nur der erste Schritt einer zwingend sequenziellen Kette ist. Der
Offset-10=0x02-Kandidat für „lies aktiven Slot ohne Slot-Nummer zu kennen“
bleibt CORRELATED (siehe oben). Beide Kandidaten wurden **nicht** gesendet.

### Aufgabe 5: Vergleich der zwei Connect-Captures

| Merkmal | Alt (13.09., „retry“) | Neu (14.09.) | Bewertung |
|---|---|---|---|
| Ping (`11 12`) | `F0…11 12 00 00 00 F7` → `…01 00 F7` | identisch | CONFIRMED fix |
| 199 Slot-Trigger (`12 13 01 00 02 …`) | byteidentisch je Slot | byteidentisch je Slot | CONFIRMED fix, kein Sessionbezug |
| 162-Byte-Antwort, Offset 14 | `09` | `00` | UNKNOWN — evtl. Retry-/Statuszähler (Dateiname alt: „retry“) |
| 162-Byte-Antwort, letzte 8 Byte | `08 0C 00 03 07 0B 0C 0C` | `0A 06 0E 02 0D 09 07 01` | UNKNOWN — session-eigener Wert (Nonce/Zähler), kein Presetbezug erkennbar |
| 42-Byte-Antwort (Kategorie 7) | größtenteils anderer Inhalt | größtenteils anderer Inhalt | UNKNOWN — variabler Laufzeitzustand, keine Slot-/Bankkorrelation erkennbar |
| Offset-10=0x02-Sonderzyklus, Slot | 9 (P10) | 0 (P01) | CORRELATED mit dem jeweils aktiven Gerätepreset der Session |

Ergebnis: Die **199-Slot-Enumeration und ihr Trigger-Format sind
protokollfix** (identisch über zwei unabhängige Sessions und einen
Tag Abstand); die **162-/42-Byte-Nebenantworten sind session-/
laufzeitabhängig** und tragen nach aktuellem Stand keine Slot- oder
Bank-Information. Zufällige Init-Bytes (162-/42-Byte-Familie) sind damit von
echten Read-Requests (17-/19-Byte-Trigger-Familie) klar getrennt.

### Aufgabe 6: Offline-P01-Decoder

`tool/matribox_p01_readback_decoder.dart` liest eine oder mehrere
PCAP/PCAPNG-Dateien, rekonstruiert Preset-Zyklen aus dem bestätigten
Antwort-Header (Offset 8/9 = `0x12/0x13`, Offset 10 ∈ `{0x01,0x02}`, Offset
11 = `0x00`, Offset 12 ∈ `{0x03,0x05}`), dekodiert nur Teil 0–7 bei
vollständigem Zyklus und gibt ausschließlich die sechs bestätigten
AMP-Marker sowie den Presetnamen aus, wenn dieser exakt `--name`
(Default `CKY 96 STUD`) entspricht:

```text
dart run tool/matribox_p01_readback_decoder.dart \
  --capture matribox1_p01_full_readback_after_store.pcapng
```

Ausgabe (beide Zyklen des Captures, byteidentisch):

```text
User P01
Name: CKY 96 STUD

Amp:
  Gain:     17.0
  Presence: 73.0
  Volume:   47.0
  Bass:     23.0
  Middle:   67.0
  Treble:   31.0
```

Kein Feld wird benannt, das nicht bereits oben bestätigt ist; ein
Namensmismatch oder ein unvollständiger Zyklus liefert explizit keinen
Treffer statt eines geratenen Werts.

### Aufgabe 7: Backup-Repräsentation — Machbarkeitseinschätzung

Die vorhandenen Daten reichen für ein **verlustfreies Rohbackup von User
P01** bereits jetzt aus, ohne dass jedes Feld verstanden sein muss: Die
zehn Originalnachrichten (Teil 0–7 à 210 B, Teil 8 à 46 B, Teil 9 à 18 B,
insgesamt 1.812 Rohbyte inklusive SysEx-Rahmen) sind vollständig
rekonstruierbar und bereits vom Decoder isoliert. Eine Backup-Struktur
könnte ohne weitere Protokollarbeit bestehen aus: Bank (`user`), Slot (`0`),
Name (`CKY 96 STUD`), den zehn rohen Teil-Nachrichten als Hex, den sechs
bereits dekodierten AMP-Feldern, Capture-Metadaten (Dateiname, SHA-256,
Zeitstempel) und einer SHA-256 über die zehn Rohteile zur späteren
Integritätsprüfung. Das ist eine reine Datenstrukturfrage, kein
Protokollrätsel mehr. **Nicht gebaut** in diesem Schritt (kein
Restore-Writer, keine neue Serialisierung) — nur die Machbarkeit
bestätigt, wie angefordert.

### Was für den vollen Zyklus fehlt

READ (User-Slot-Trigger, CONFIRMED) → BACKUP (Datenstruktur machbar,
Aufgabe 7) → WRITE (34-Byte-Parameterschreiben, CONFIRMED aus früheren
Captures) → STORE (Burst-Kandidat, weiterhin nur
`STORE_COMMIT_CANDIDATE`) → READ (derselbe Trigger erneut) → VERIFY
(Feldvergleich, im Decoder bereits möglich) → RESTORE (kompletter
Write-Pfad für alle neun Blöcke, nicht nur AMP — ungeklärt, Teile 3–7
weiterhin UNKNOWN). Größte offene Lücke bleibt RESTORE: nur der AMP-Block
ist parameterweise schreibbar bestätigt, ein vollständiger Presetschreiber
für alle neun Blöcke liegt außerhalb der aktuellen Evidenz.

## Vollständige Request/Response-Sequenz für User P01 und Bestätigung des 19-Byte-Triggers (15.09.2026)

Reiner Offline-Nachtrag aus der bereits vorhandenen
`matribox1_p01_full_readback_after_store.pcapng`; kein neuer Capture, keine
Gerätekommunikation. Anlass: der erste echte Hardwaretest des
Read-Probes (siehe unten) lieferte `READBACK_INCOMPLETE` nach genau einer
vollständigen SysEx-Antwort — das wird hier gegen das PC-Capture geprüft.

### Vollständige Teile 0–9 für User/Slot 0 (P01)

| Teil | Request (Host→Device, Länge) | t Request | Response-Länge | t Response | Δt |
|---:|---|---:|---:|---:|---:|
| 0 | `F0 21 25 7F 51 4D 45 32 12 13 01 00 02 00 00 01 F7` (17B) | 4630,203 | 210 | 4630,287 | 0,084 ms |
| 1 | `F0 21 25 7F 51 4D 45 32 12 13 01 00 04 00 00 00 00 01 F7` (19B) | 4630,590 | 210 | 4630,700 | 0,110 ms |
| 2 | `...04 00 00 00 01 01 F7` | 4630,996 | 210 | 4632,309 | 1,313 ms |
| 3 | `...04 00 00 00 02 01 F7` | 4632,618 | 210 | 4633,887 | 1,269 ms |
| 4 | `...04 00 00 00 03 01 F7` | 4634,587 | 210 | 4634,696 | 0,109 ms |
| 5 | `...04 00 00 00 04 01 F7` | 4635,002 | 210 | 4636,309 | 1,307 ms |
| 6 | `...04 00 00 00 05 01 F7` | 4636,642 | 210 | 4636,733 | 0,091 ms |
| 7 | `...04 00 00 00 06 01 F7` | 4638,360 | 210 | 4638,666 | 0,306 ms |
| 8 | `...04 00 00 00 07 01 F7` | 4638,987 | 46 | 4640,312 | 1,325 ms |
| 9 | `...04 00 00 00 08 01 F7` | 4640,824 | 18 | 4642,304 | 1,480 ms |

Streng sequenziell (1 Request → genau 1 Response, keine Bündelung); Δt
schwankt unvorhersehbar zwischen 0,08 ms und 1,48 ms — passt nicht zu einem
festen Delay-Schema, sondern zu tatsächlicher Antwortsteuerung durch das
Gerät.

### 19-Byte-Trigger — jetzt CONFIRMED, nicht nur ein Beispiel

```text
F0 21 25 7F 51 4D 45 32 12 13 01 00 04 [BANK] [SLOT] 00 [TEIL-1] 01 F7
```

Unabhängig bestätigt an drei Bank/Slot-Kombinationen:

| Quelle | Offset 13 (Bank) | Offset 14 (Slot) | Beispiel Offset 16 |
|---|---:|---:|---|
| Factory Slot 0 (P01), Teil 1 | `01` | `00` | `00` |
| User Slot 0 (P01), Teile 1–9 | `00` | `00` | `00`…`08` |
| User Slot 1 (P02), Teil 1 | `00` | `01` | `00` |

Offset 12 = `0x04` (gegenüber `0x02` beim 17-Byte-Start-Trigger) markiert die
Anfragefamilie „nächster Teil“. Offset 16 = Zielteil − 1 (0-basiert: 0 fordert
Teil 1 an, …, 8 fordert Teil 9 an). Offset 17 = `0x01` konstant, wie beim
17-Byte-Trigger. Bank/Slot-Feldposition ist damit identisch zum bereits
bestätigten 17-Byte-Trigger, keine Neuinterpretation nötig.

### Bewertung des ersten Read-Probe-Hardwaretests

Ergebnis war `READBACK_INCOMPLETE`, 2 Roh-Chunks, 1 vollständige SysEx.
`decodeConfirmedFields` verlangt `hasAllPayloadParts` (Teile 0–7 vorhanden);
eine einzelne Antwort erfüllt das strukturell nicht — die sechs Marker
liegen in Teil 1/2, nicht in Teil 0. **`READBACK_INCOMPLETE` ist damit die
korrekte, erwartete Klassifizierung, kein Fehlverhalten.** Der gesendete
Request entspricht exakt Teil-0-Anfrage (17 Byte, Bank=User, Slot=0); die
eine erhaltene Antwort ist mit Teil 0 konsistent (plausibelste Erklärung:
ohne die neun 19-Byte-Folgeanfragen antwortet das Gerät nur auf den
einzigen gesendeten Trigger). **Nicht verifizierbar:** Die App loggt aktuell
keine Rohbytes der Antwort, nur Textereignisse — der tatsächliche Inhalt der
einen Antwort ist nicht mehr rekonstruierbar. Für Probe V2 als fehlende
Beobachtbarkeit vorgemerkt: Rohbytes/Hex je Schritt müssen geloggt werden.

## Standard-MIDI CC/PC bestätigt (15.09.2026, außerhalb WyrmTone)

Anlass: Vergleich mit dem fremden, nicht lizenzierten Projekt
`hurricaneabel/Matribox_II_Pro_MidiCon` (zielt laut eigener Doku
ausschließlich auf die Matribox II Pro; Quellcode-Prüfung zeigte, dass
dessen Live-Steuerung ausschließlich Standard-MIDI Control Change und
Program Change sendet, kein proprietäres SysEx — SysEx-Handling dort ist
reiner Empfänger für Statusanzeige).

Marcel hat daraufhin **unabhängig von WyrmTone**, mit einem eigenständigen
Python-Skript (`mido`/`python-rtmidi`, kein Code aus dem fremden Repo
übernommen) direkt gegen die reale Matribox 1 getestet:

- `control_change(channel=1, control=49, value=0)` dann `value=127`
  (mido-Kanalzählung 0-basiert = MIDI-Kanal 2 in menschlicher Zählung, exakt
  die aus `matribox1_p01_block_bypass.pcapng` bekannte Bypass-CC) —
  **bestätigt erfolgreich am Gerät.**
- `program_change(channel=1, program=1)` (Zielpreset P02, 0-basiert) —
  **bestätigt erfolgreich am Gerät**, Display wechselte sichtbar auf P02.

Damit ist **Program Change als zusätzlicher, deutlich einfacherer Weg zur
Presetauswahl bestätigt** — unabhängig von der bisherigen, aufwendig
reverse-engineerten 22-Byte-QME2-SysEx-Route
(`ConfirmedPresetSelectionCodec`). Kein Store/Save getestet, keine
SysEx-Schreibpfade aus dem fremden Projekt übernommen oder ausprobiert.

### Nachtrag: Stichproben über den vollen User-Bank-Bereich (15.09.2026)

Vier gezielte zusätzliche Stichproben mit demselben eigenständigen Skript
(`matribox_midi_test.py`, weiterhin außerhalb WyrmTone, kein Factory-Test,
kein CC0 — siehe unten), alle **erfolgreich, Display zeigte exakt die
erwartete Nummer**:

| Sichtbares Preset | Program Change (0-basiert) | Ergebnis |
|---|---:|---|
| P01 | 0 | CONFIRMED |
| P10 | 9 | CONFIRMED |
| P50 | 49 | CONFIRMED |
| P99 | 98 | CONFIRMED |

Zusammen mit dem bereits bestätigten P02 (Program Change 1) ist die Formel
`Program Change = sichtbare Presetnummer − 1` jetzt an fünf über den
gesamten User-Bank-Bereich verteilten Werten (1, 2, 10, 50, 99) bestätigt —
CONFIRMED für die gesamte User-Bank, nicht mehr nur ein Einzelfall.

**Korrektur Bypass-Polarität:** Der Bypass-Test (CC 49) wurde ebenfalls live
nachgestellt und hat reagiert, aber **umgekehrt** zur bisherigen, in der
passiven Capture-Analyse nur als Hypothese markierten Zuordnung. Bisher
stand `0x00`/`0x7F` als reiner Bool-Kandidat ohne bestätigte Polarität in
der Dokumentation (`Bypass/Enable -- CORRELATED`, Polarität nie confirmed).
Jetzt live bestätigt: **Wert `0` schaltet den Block EIN, Wert `127`
schaltet ihn AUS** — nicht wie naiv angenommen umgekehrt. Weiterhin nicht
bestätigt: welcher konkrete Effektblock CC 49 zugeordnet ist (Blockname
fehlt weiterhin), und ob andere Blöcke dieselbe Polarität verwenden.

## Hardwaretest Probe V2 (P01-Full-Read): Teil 0 bestätigt, Teil 1 liefert Endmarker statt Daten (15.09.2026)

Erster echter Hardwaretest von `VerifiedPresetP01FullReadProbe` (Samsung
SM_F946B, Matribox 1 per OTG, Sonicake-Editor geschlossen). Vollständiges
Protokoll aus der App kopiert und byteweise offline geprüft, kein
Wireshark nötig — wie für V2 vorgesehen.

**Teil 0 — CONFIRMED, byteidentisch:**

```text
REQUEST_PART_0  (17 B): F0 21 25 7F 51 4D 45 32 12 13 01 00 02 00 00 01 F7
RESPONSE_PART_0 (210 B): [byteidentisch mit der aus dem PC-Editor-Capture
                          bestätigten Referenz fuer User/Slot 0 / "CKY 96 STUD"]
```

Der isolierte 17-Byte-Trigger liefert also weiterhin zuverlässig Teil 0,
und der P01-Inhalt ist seit dem PC-Capture unverändert.

**Teil 1 — unerwartet, Probe stoppt korrekt:**

```text
REQUEST_PART_1            (19 B): F0 21 25 7F 51 4D 45 32 12 13 01 00 04 00 00 00 00 01 F7
Erhaltene Antwort (nicht passend, 18 B): F0 21 25 7F 51 4D 45 32 12 13 01 00 05 00 00 00 09 F7
```

Der Request ist byteidentisch mit dem im PC-Capture bestätigten
Teil-1-Trigger (Bank=User, Slot=0, Zielteil-Feld=00). Die Antwort ist aber
**keine unbekannte oder kaputte Nachricht** — sie ist strukturell exakt der
bereits bekannte **Teil-9-Endmarker** (Offset 12 = `05`, Offset 16 = `09`,
identisch zum in Capture 01 und im Full-Readback-Capture beobachteten
Zyklusende-Signal). Das Gerät antwortet also mit „Zyklus fertig", obwohl
gerade erst Teil 0 geliefert wurde und Teil 1 angefragt war. Die Probe hat
das korrekt als strukturell nicht passend erkannt und sofort gestoppt, ohne
weiterzuschalten oder erneut zu senden — genau wie vorgesehen.

**Hypothese (nicht bestätigt):** In allen bisher passiv beobachteten
Captures ging dem 17-Byte-Start-Trigger stets eine längere Präambel voraus
(Ping, 162-Byte-Capability-Antwort, 42-Byte-Kategorie-7-Abfrage,
Enumerationsschleife, Vorbereitungs-Handshake mit 16-/20-Byte-Nachrichten)
— siehe „Connect-/Readback-Auslöser" oben. Der isolierte V2-Probe überspringt
diese Präambel vollständig und sendet nur den nackten Start-Trigger. Es ist
plausibel, dass das Gerät einen Mehrteil-Lesevorgang erst nach dieser
Präambel korrekt verwaltet und ohne sie nach Teil 0 direkt in den
„Zyklus-Ende"-Zustand fällt, sobald ein weiterer Teil angefragt wird — das
ist aber nicht bewiesen, nur die naheliegendste Erklärung für das exakte
Auftreten des bekannten Endmarkers.

**Konsequenz:** Der bisherige V2-Ansatz (nur die zehn Teil-Requests ohne
Präambel) kann in dieser Form keinen vollständigen Zyklus liefern. Eine
Erweiterung um Teile der Präambel wäre ein neuer, deutlich größerer Eingriff
(mehrere weitere hartcodierte Nachrichten) und wurde nicht umgesetzt oder
angefragt. Die Verbindung ist für einen erneuten V2-Versuch verbraucht
(One-Shot-Latch); ein neuer Versuch benötigt einen echten Reconnect.

## Präambel-Analyse: die fehlende Phase D vor Part 0 (15.09.2026, rein offline)

Anlass: Probe V2 liefert Part 0 zuverlässig, aber die Device-Antwort auf den
danach gesendeten, bytegleich bestätigten Part-1-Trigger ist der bekannte
Teil-9-Endmarker statt Nutzdaten (siehe oben). Reine Offline-Auswertung der
zwei vorhandenen erfolgreichen Connect-Captures (13.09. und 14.09.), keine
Gerätekommunikation, kein V3 implementiert.

### Fünf Phasen vor dem ersten Preset-Read

In beiden Sessions identisch aufgebaut, bytegleiche Nachrichtenfamilien:

| Phase | Rolle | Häufigkeit | Nachrichten |
|---|---|---|---|
| A · Ping/Identity | UNKNOWN (Verbindungstest?) | einmal pro Session | `F0…11 12 00 00 00 F7` (14B) → `…12 12 00 00 00 01 00 F7` (16B) |
| B · Capability | UNKNOWN (Geräteinfo?) | einmal pro Session | `F0…11 13 00 00 00 F7` (14B) → 162-Byte-Antwort (1 Byte + 8-Byte-Tail sessionabhängig) |
| C · Metadaten-Enumeration | UNKNOWN | einmal pro Session | `F0…11 13 02 00 07 F7` (14B) → 42B; danach 20 Schritte `F0…11 12 00 10 02 [00..13] F7` (15B) → je 89B |
| **D · Preset-Read-Vorbereitung** | **CORRELATED: kündigt Bank+Slot an** | **einmal PRO SLOT, nicht nur einmal pro Session** | `F0…11 13 01 00 [BANK] [SLOT] F7` (16B) → `F0…12 13 01 00 01 [BANK] [SLOT] 0C 1C 01 40 F7` (20B) |
| E · Eigentlicher Preset-Read | CONFIRMED | einmal pro Slot | bereits bekannter 17B-Start-Trigger + Part-0-Antwort + neun 19B-Folge-Trigger |

**Wichtigste Korrektur gegenüber der bisherigen Analyse:** Phase D ist keine
einmalige Sitzungseinleitung, sondern wiederholt sich vor **jedem einzelnen**
der 199 beobachteten Slot-Übergänge im vollständigen Readback-Capture
(199 Vorkommen, exakt wie beim 17B-Trigger selbst). Ihre Bank-/Slot-Felder
liegen an denselben Offsets wie beim bereits bestätigten 17B-Trigger
(Offset 13 = Bank, Offset 14 = Slot), unabhängig an drei Bank/Slot-Werten
bestätigt (Factory/Slot 0, User/Slot 0, User/Slot 98) und am
Factory→User-Übergang exakt weiterverfolgt (Offset 13 wechselt 01→00,
Offset 14 setzt auf 0 zurück — keine zusätzliche Übergangsnachricht nötig,
siehe unten).

### State-Machine (Request → Response → nächster Request)

```text
[nur einmal pro Session]
HOST Ping (14B)          → DEV Echo (16B)
HOST Capability-Query     → DEV 162B-Antwort
HOST Kategorie-7-Query    → DEV 42B-Antwort
HOST Enum[0..19] (15B)    → DEV Enum-Antwort (89B)   -- 20× wiederholt

[pro Slot, hier fuer Bank=User(00)/Slot=0]
HOST Announce(Bank,Slot) (16B) → DEV Ack(Bank,Slot) (20B)
HOST Start-Trigger(Bank,Slot) (17B) → DEV Part-0-Antwort (210B)
HOST Naechster-Teil(1) (19B)   → DEV Part-1-Antwort (210B)
...
HOST Naechster-Teil(8) (19B)   → DEV Part-9-Antwort (18B)
```

Jede Phase ist strikt sequenziell (Response vor nächstem Request), keine
Nachricht wird ohne vorherige passende Antwort weitergeschickt — bestätigt
eine echte State Machine, keine reine Zeitliste.

### Factory → User-Übergang

Unmittelbar nach Factory-P99s Teil-9-Endmarker (der selbst Bank=01/Slot=98
in seinen eigenen Offsets 13/14 trägt — neue Beobachtung: der Endmarker
kodiert, welcher Slot gerade beendet wurde) folgt **direkt** Phase D für
User-Slot 0 — keine zusätzliche Bank-Wechsel- oder Reset-Nachricht. Der
Übergang läuft über exakt dasselbe Phase-D/E-Muster wie jeder andere
Slot-Übergang auch, nur mit geflipptem Bank-Feld.

### Part-0→Part-1: erfolgreich vs. V2-Hardware

| | vor Part 0 | Part-0-Request | Part-1-Request | Ergebnis |
|---|---|---|---|---|
| Erfolgreicher Editor (Capture) | Phase A+B+C+D | identisch | identisch | Part-1-Daten |
| V2-Hardwaretest | **keine** | identisch | identisch | Teil-9-Endmarker |

Die Requests sind bytegleich; der einzige Unterschied ist der fehlende
Zustand aus Phase D (und A/B/C) vor dem Start-Trigger. Das erklärt den
beobachteten Fehlschlag konsistent, ohne neue Semantik zu erfinden.

### Präambel-Kandidaten für V3

**Candidate A — kleinstmöglich (HYPOTHESIS, ungetestete Kombination):**
Nur Phase D für Bank=User/Slot=0 direkt vor dem bereits bekannten
17B-Trigger:
```text
F0 21 25 7F 51 4D 45 32 11 13 01 00 00 00 F7                          (16B, Announce)
→ warten auf F0 21 25 7F 51 4D 45 32 12 13 01 00 01 00 00 0C 1C 01 40 F7  (20B, Ack)
→ bereits bekannte 17B/19B-Sequenz aus V2
```
Begründung: strukturell unmittelbar an Part 0 angrenzend, gleiche
Bank/Slot-Adressierung wie der bereits bestätigte Trigger. Ausgeschlossen:
Phasen A–C, weil sie session-global (nicht pro Slot) auftreten und V1/V2
bereits bewiesen haben, dass Part 0 auch ganz ohne sie geliefert wird —
ihre Notwendigkeit speziell für die Mehrteil-Fortsetzung ist dadurch
unwahrscheinlich, aber nicht ausgeschlossen. Risiko: gering (2 zusätzliche,
bereits bytegenau beobachtete Nachrichten). Evidenzgrad: CORRELATED für die
Existenz/Adressierung von Phase D, HYPOTHESIS für ihre Hinlänglichkeit
allein.

**Candidate B — konservativer (HYPOTHESIS):**
Candidate A plus Phase A (Ping/Echo) direkt davor:
```text
F0 21 25 7F 51 4D 45 32 11 12 00 00 00 F7        (14B, Ping)
→ warten auf F0 21 25 7F 51 4D 45 32 12 12 00 00 00 01 00 F7  (16B, Echo)
→ Candidate A
```
Begründung: Ping ist die günstigste, session-öffnende Nachricht in beiden
Captures, könnte plausibel einen Verbindungszustand zurücksetzen, den ein
frisch geöffneter MIDI-Port sonst nicht auslöst. Kostet nur 2 weitere
Nachrichten. Evidenzgrad: HYPOTHESIS, kein stärkerer Beleg als für A.

**Candidate C — vollständig belegt (Phasen A+B+C+D, dann E einmal für Slot=User/0):**
Exakt die in beiden Sessions tatsächlich beobachtete volle Präambel
(Ping, Capability, Kategorie-7, 20-Schritt-Enumeration), danach direkt
Phase D+E für User/Slot 0 — **ohne** die anderen 197 Slots zu lesen.
Evidenzgrad: Die Abfolge als Ganzes ist CONFIRMED (exakt das, was in beiden
realen Sessions vor jedem erfolgreichen Mehrteil-Read stand); dass sie bei
einer nativen WyrmTone-Nachbildung (statt dem echten Editor) identisch
funktioniert, ist nicht separat bewiesen. Risiko: höher (Session-abhängige
Bytes in Phase B/C, siehe unten), aber jede einzelne Nachricht ist bereits
bytegenau bekannt.

### Session-/Counter-Bytes

- Phase B (162B): 1 Byte (Offset 14) und die letzten 8 Byte unterscheiden
  sich zwischen den Sessions (bereits dokumentiert, vermutlich Zähler/Nonce)
  — für Candidate C müsste WyrmTone diese Bytes ignorieren/nicht prüfen,
  nicht nachbilden.
- Phase C (42B-Antwort): Inhalt unterscheidet sich ebenfalls zwischen
  Sessions, ohne erkennbare Slot-/Bankkorrelation.
- Phase D/E: **keine** Session-abhängigen Bytes gefunden — beide Sessions
  liefern für dieselbe Bank/Slot-Kombination bytegleiche Requests.

### Random-P01-Read vs. Bank-Sync

| | A) Gezielter P01-Read (Candidate A/B) | B) Einmalige Session-Präambel (Candidate C) + gezielter Slot |
|---|---|---|
| Nachrichten bis Part 0 | 2–4 | ca. 44 (A+B+C) |
| Dauer (geschätzt anhand Timing) | < 50 ms | ca. 100–150 ms |
| Protokollevidenz | HYPOTHESIS | CONFIRMED als Ganzes |
| Robustheit | ungetestet, evtl. unzureichend | folgt exakt echtem Editor-Verhalten |
| Implementierungsaufwand | gering (2 weitere feste Nachrichten) | mittel (weitere ~24 feste Referenz-Nachrichten, aber weiterhin kein voller 198-Slot-Walk nötig) |

Wichtig: Auch Candidate C erfordert **nicht** das Lesen aller 198 Slots —
die Enumerationsschleife (Phase C) ist eine feste 20-Schritt-Sequenz
unbekannter Bedeutung, keine Slot-Enumeration; der eigentliche
198-Slot-Walk beginnt erst mit Phase D/E und wird für einen gezielten
P01-Read nur einmal (für Slot=User/0) durchlaufen, nicht 198-mal.

**Wichtige Trennung — zwei unabhängige Wege, nicht zu verwechseln:**

**Standard-MIDI Live Control** (siehe „Standard-MIDI CC/PC bestätigt" oben):
- User-Preset-Wechsel per Program Change: CONFIRMED (P01/P02/P10/P50/P99).
- Bankwahl für die Factory-Bank per Standard-MIDI (CC0/CC32): **UNKNOWN**.
  Alle sechs vorhandenen Captures (inklusive des vollständigen
  Connect-/Sync-Durchlaufs über 99+99 Presets) enthalten kein einziges CC0
  oder CC32; der offizielle Editor wechselt Bänke ausschließlich über sein
  eigenes SysEx, nicht über Standard-MIDI. Das fremde Projekt
  (`hurricaneabel/Matribox_II_Pro_MidiCon`) nutzt MSB 0/1 für sein eigenes
  60-Bank×4-Presets-Schema der Matribox II Pro, das nicht auf die flache
  P01–P99-Struktur der Matribox 1 übertragbar ist. Kein CC0-Wert wurde
  geraten oder gesendet.

**QME2 Preset Management** (Phase D + Full-Read, dieses Dokument):
- Gezielter User/P01-Read: CONFIRMED (Hardwaretest V3A, siehe oben).
- QME2 trägt eigene Bank-/Slot-Felder in Phase D und in den Teil-Requests
  (Offset 13/14) — unabhängig von Standard-MIDI CC0/CC32. Der
  Sonicake-Editor hat in den passiv beobachteten Captures Factory-Bank-Slots
  bereits über genau dieses QME2-Feld gelesen (z. B. Factory-P99,
  Bank=01/Slot=98, siehe „Factory → User-Übergang" oben) — ganz ohne
  Standard-MIDI-Bankwahl.
- Ein von WyrmTone aktiv ausgelöster Factory-Random-Read (Phase D mit
  Bank=01) wurde bisher **nicht getestet** — das ist ein offener möglicher
  nächster Schritt für Candidate A, keine Aussage über Standard-MIDI.

**Explizit keine Aussage:** dass ein Standard-MIDI-CC0-Wert für einen
QME2-Factory-Read notwendig wäre. Beide Wege sind unabhängig; das offene
Standard-MIDI-CC0/CC32-Problem ist **kein Blocker** für einen zukünftigen
QME2-Factory-Read-Test.

## Hardwaretest Probe V3A (Phase D + P01-Full-Read): CONFIRMED — Phase D ist die fehlende Voraussetzung (15.09.2026)

Setup: Samsung SM_F946B, Matribox 1 per OTG (USB `84EF:0054`), Sonicake-Editor
geschlossen, Debug-Build mit `ENABLE_MATRIBOX_P01_FULL_READ_PROBE_V3A=true`.
APK vor Installation und nach Rückzug SHA-256-identisch verifiziert
(`08a0bf087573c8880ef79fdc4832888b96e281c30341b2d6b0c06754713bd349`).
Vollständiges Rohprotokoll aus der App kopiert; zusätzlich unabhängig vom
App-eigenen Verdict-Text mit dem seit V1 unveränderten Offline-Decoder
(`evaluateP01ReadProbeResponse`/`decodeMatchingPresets`) offline
nachgerechnet.

### Rohprotokoll (Kernnachrichten)

```text
PHASE_D_REQUEST  (16B): F0 21 25 7F 51 4D 45 32 11 13 01 00 00 00 00 F7
PHASE_D_RESPONSE (20B): F0 21 25 7F 51 4D 45 32 12 13 01 00 01 00 00 0C 1C 01 40 F7
  -> byteidentisch mit der in "Fünf Phasen vor dem ersten Preset-Read"
     (Phase D) dokumentierten Referenz für Bank=User(00)/Slot=0(00).
```

| Teil | Request | Response | `isValidResponseForPart` | Vergleich zu V2 |
|---|---|---|---|---|
| 0 | 17B | 210B | bestanden | wie V2: Teil 0 bereits ohne Phase D bestätigt |
| 1 | 19B | 210B | bestanden | **anders als V2**: dort kam hier der Teil-9-Endmarker statt Daten |
| 2 | 19B | 210B | bestanden | — |
| 3 | 19B | 210B | bestanden | — |
| 4 | 19B | 210B | bestanden | — |
| 5 | 19B | 210B | bestanden | — |
| 6 | 19B | 210B | bestanden | — |
| 7 | 19B | 210B | bestanden | — |
| 8 | 19B | 46B | bestanden | — |
| 9 | 19B | 18B (Endmarker) | bestanden | wie erwartet |

Offline-Decoder-Ergebnis (Outcome `confirmed`): Name `CKY 96 STUD`, Slot 0;
Gain 17, Presence 73, Volume 47, Bass 23, Middle 67, Treble 31 — alle sechs
Marker identisch mit der PC-Editor-Referenz aus "Vollständiger
Device→Host-Readback und Persistenzbeweis".

### Aktualisierter Evidenzstand

**CONFIRMED (hardwarebestätigt durch diesen Test):**
- Phase-D-Announce/Ack (Bank=User/Slot=0) unmittelbar vor Part 0 ist für den
  gezielten Read von User/P01 hinreichend, um den vollständigen 10-Teile-
  Zyklus zu erhalten.
- Ohne Phase D (V2, oben) stoppt der Zyklus nach Teil 0 mit dem
  Teil-9-Endmarker; mit Phase D (V3A) werden alle 10 Teile korrekt geliefert.
  Die Requests sind in beiden Tests byteidentisch — der einzige Unterschied
  ist Phase D.
- Candidate A (siehe "Präambel-Kandidaten für V3") wird damit für genau
  diesen Pfad (User-Bank, Slot 0) von HYPOTHESIS auf **CONFIRMED**
  angehoben.

**CORRELATED (unverändert, nicht durch diesen Test zusätzlich geprüft):**
- Phase D korreliert in den Offline-Captures mit jedem der 199 beobachteten
  Slot-Übergänge, nicht nur Slot 0. Das war bereits vor diesem Hardwaretest
  bekannt und wird durch ihn weder bestätigt noch widerlegt.

**HYPOTHESIS (bleibt offen):**
- Ob Phase D auch für andere Slots (User P02–P99, Factory F01–F99) für sich
  genommen ausreicht, ist weiterhin ungetestet. Nur Slot 0/User wurde real
  geprüft.
- Candidate B (zusätzlich Phase A/Ping) und Candidate C (volle Präambel)
  bleiben ungetestete Alternativen; da Candidate A bereits ausreichte,
  besteht aktuell kein Anlass, sie zu testen.

**UNKNOWN (unverändert):**
- Bedeutung von Phase A/B/C (Ping/Capability/Enumeration) bleibt unbekannt —
  für den bestätigten Lesepfad sind sie nicht erforderlich.
- Verhalten von Phase D bei einem bereits vorbelegten Verbindungszustand
  (z. B. nach einem fehlgeschlagenen vorherigen Read in derselben
  Verbindung) ist unbekannt; der One-Shot-Latch verhindert eine
  Testwiederholung in derselben Verbindung.

**Nicht behauptet:** dass Phase D global bzw. für alle Bank-/Slot-
Kombinationen notwendig oder hinreichend ist. Bestätigt ist ausschließlich
User/P01.

### Herkunft und Verifikation

- Einmaliger Lauf (One-Shot-Latch); für eine höhere Evidenzstufe
  (reproduzierte Bestätigung über eine zweite, unabhängige Verbindung) wäre
  ein weiterer Lauf nötig — nicht Teil dieses Berichts.
- Kein Store, kein Schreiben, keine Presetauswahl über Standard-MIDI in
  diesem Test.

## V3A Reproduktion: zweiter unabhängiger Lauf, byteidentisch (16.09.2026)

Der gezielte User/P01 Full-Read über Candidate A wurde über zwei
unabhängige Geräteverbindungen erfolgreich reproduziert (Verbindung
getrennt und neu aufgebaut, Sonicake-Editor geschlossen, exakt dieselbe,
nicht neu gebaute V3A-APK). Ablauf in beiden Sessions identisch:

```text
Phase-D Announce → Phase-D ACK → Part 0 → Part 1 → ... → Part 9
  → Decode → READBACK_CONFIRMED
```

**Bytevergleich Lauf 1 (15.09.2026) vs. Lauf 2 (16.09.2026)** — geprüft
nicht nur an den sechs bekannten/dekodierten Feldern, sondern an
**sämtlichen** übertragenen Bytes einschließlich noch unklassifizierter
Nutzdaten:

| Nachricht | Ergebnis |
|---|---|
| Phase-D Announce | byteidentisch |
| Phase-D ACK | byteidentisch |
| Part 0 | byteidentisch |
| Part 1 | byteidentisch |
| Part 2 | byteidentisch |
| Part 3 | byteidentisch |
| Part 4 | byteidentisch |
| Part 5 | byteidentisch |
| Part 6 | byteidentisch |
| Part 7 | byteidentisch |
| Part 8 | byteidentisch |
| Part 9 | byteidentisch |

Decoder-Ergebnis in beiden Fällen identisch: Name `CKY 96 STUD`; Gain 17,
Presence 73, Volume 47, Bass 23, Middle 67, Treble 31.

**Evidenzstatus: CONFIRMED + REPRODUCED** für den gezielten User/P01-Read
(Phase D → ACK → Parts 0-9) via QME2. Keine Generalisierung auf andere
User-Slots oder die Factory-Bank. Candidate B und Candidate C wurden
weiterhin nicht benötigt und nicht hardwaregetestet.

### Methodik-Hinweis: Transkriptionsfehler beim Bytevergleich

Beim ersten manuellen Übertragen von `RESPONSE_PART_7` aus dem Rohlog in
ein Vergleichsskript gingen 6 Byte verloren (erwartet 210 Byte, manuell
übertragen 204 Byte), was zunächst einen scheinbaren Mismatch zwischen
Lauf 1 und Lauf 2 erzeugte. Nach programmatischer Erzeugung der
Vergleichsdaten direkt aus einer wortgetreuen Kopie des Rohlogs (kein
manuelles Abtippen) war Part 7 vollständig und beide Sessions
byteidentisch. Das war **kein Hardwarefehler, kein Protokollfehler und
keine variable Antwort**, sondern ausschließlich ein manueller
Übertragungsfehler beim Erstellen der Vergleichsdaten.

**Projektregel daraus:** Protocol-Fixtures, Golden Captures und
Byte-Vergleiche dürfen nicht von Hand aus Hex-Logs abgeschrieben werden.
Sie müssen programmatisch aus der Originalquelle erzeugt oder bytegenau
gegen sie validiert werden (vgl. bereits bestehende Regel für
`test/support/matribox_p01_readback_fixtures.dart`).

### V3A-Abschluss

V3A ist als experimentelle Untersuchung **abgeschlossen**. Kein weiterer
P01-Reproduktionslauf und kein V4 erforderlich. Die nächste
Entwicklungsphase ist `MatriboxPresetReader` → `RawPresetSnapshot` →
validiertes lokales Raw-Backup (siehe Architekturentwurf oben). Die
experimentelle V3A-UI und ihr Compile-Gate bleiben als historisch
nachvollziehbarer, weiterhin funktionsfähiger Diagnosepfad bestehen und
werden nicht entfernt oder refactored.

## Produktiver P01 Raw-Backup-Pfad: hardwarebestätigt (16.09.2026)

Der produktive, nicht-experimentelle Pfad wurde auf echter Matribox-1-
Hardware erfolgreich ausgeführt (Samsung SM_F946B, Sonicake-Editor
geschlossen, Debug-Build mit `ENABLE_MATRIBOX_P01_RAW_BACKUP=true`):

```text
MatriboxPresetReader.readVerifiedUserP01()
  → Phase-D Announce → Phase-D ACK
  → Part 0 → ... → Part 9
→ RawPresetSnapshot.capture() (Validierung: 10 Teile, Längen, QME2-Struktur,
  Bank/Slot-Konsistenz, Reihenfolge, Presetname)
→ Serialisierung (raw_preset_backup_format.dart)
→ Speicherung als *.wyrmtone-raw-preset.json (Android, App-internes Verzeichnis)
→ Datei erneut geladen → deserialisiert → Hash/Struktur erneut validiert
→ READBACK_CONFIRMED (UI: „Backup erfolgreich erstellt und validiert.")
```

UI-Ergebnis: Preset `CKY 96 STUD` (P01), Hash
`2c4b74e41d46dbc0031dac4b2faa801f15035c745332a28994865f29cd2b0552`, Datei
`matribox_raw_backups/<hash>.wyrmtone-raw-preset.json`.

### Unabhängige Verifikation

Die UI-Erfolgsmeldung allein wurde **nicht** als Beweis akzeptiert. Die
tatsächlich auf dem Gerät gespeicherte Datei wurde per `adb shell run-as`
vom Gerät gezogen und offline erneut mit dem seit V1 unveränderten Decoder
(`decodeRawPresetBackupJson`) verarbeitet. Dabei bestätigt:

- Die on-device gespeicherte Datei ist strukturell gültig und
  eigenständig dekodierbar (nicht nur die Laufzeit-UI-Meldung).
- Phase-D-ACK in der Datei entspricht bytegenau der bestätigten Referenz.
- Alle 10 Raw Parts entsprechen bytegenau den V3A-Referenzen (Lauf 1 vom
  15.09. und Lauf 2 vom 16.09., die bereits untereinander byteidentisch
  sind — siehe oben).
- Presetname (`CKY 96 STUD`) und alle sechs bekannten AMP-Felder (Gain 17,
  Presence 73, Volume 47, Bass 23, Middle 67, Treble 31) korrekt.
- Der im Backup gespeicherte SHA-256 ist gültig (Struktur- und
  Hash-Validierung beim erneuten Laden bestanden).

**Besonders wichtig:** Der Hash des produktiv erzeugten Backups
(`2c4b74e41...cd2b0552`) ist **identisch** mit dem Hash, der offline aus
den beiden bereits byteidentischen V3A-Läufen berechnet wurde. Damit
stimmen V3A-Lauf 1, V3A-Lauf 2 und der produktive
`MatriboxPresetReader`-Lauf für Phase-D-ACK + Parts 0–9 bytegenau
überein — drei unabhängige Hardware-Durchläufe über zwei unterschiedliche
Codepfade (experimentelle Probe vs. produktiver Reader), ein Ergebnis.

### Aktualisierter Evidenzstatus

**CONFIRMED + REPRODUCED + PRODUCTIVE-PATH-CONFIRMED** für User/P01:

- Gezielter QME2-Read (Phase D → ACK → Parts 0–9) — CONFIRMED, REPRODUCED
  (V3A, zwei Läufe) und jetzt zusätzlich über den produktiven
  `MatriboxPresetReader` bestätigt.
- `RawPresetSnapshot`-Validierung, Serialisierung, persistiertes
  Raw-Backup, erneutes Laden und Integritätsprüfung — CONFIRMED über
  echte Hardware-Daten (nicht nur Fixtures/Offline-Tests).

**Nicht behauptet:** dass andere User-Slots oder die Factory-Bank damit
hardwarebestätigt sind. Bestätigt ist ausschließlich User/P01 über den
produktiven Pfad.

### P01-Meilenstein

Der User/P01 Read-Only-Pfad gilt damit als **abgeschlossen**. Für P01 sind
keine weiteren experimentellen Read-Probes oder Reproduktionsläufe
erforderlich. V3A bleibt als historische, weiterhin verifizierbare
Diagnoseimplementierung bestehen, ist aber **nicht mehr der primäre
Anwendungspfad**. Der primäre Pfad ist jetzt:

```text
MatriboxPresetReader → RawPresetSnapshot → RawPresetBackup
```

### Methodik: bevorzugte Verifikationsmethode für künftige Slots/Pfade

Ein erfolgreiches Backup gilt nicht bereits durch eine UI-Erfolgsmeldung
als bewiesen. Für diesen Test und für künftige neue Slots/Backup-Pfade
gilt als bevorzugte Verifikationskette:

```text
DEVICE READ → SAVE → DEVICE FILE → EXTERNAL READBACK (z. B. adb run-as)
  → OFFLINE DECODE → HASH/RAW-BYTE COMPARE
```

### Nächster Evidenzschritt (nur dokumentiert, nicht umgesetzt)

Nächster sinnvoller Hardware-Evidenzschritt: **User/P10 READ-ONLY**. Ziel
ist nicht P10s Inhalt, sondern zu prüfen, ob das aus den Editor-Captures
abgeleitete Bank-/Slot-Schema mit demselben Phase-D → ACK → Parts-0–9-
Ablauf auch für einen zweiten User-Slot funktioniert. Erst nach einem
erfolgreichen P10-Test wird über eine kontrollierte Generalisierung von
`readVerifiedUserP01()` zu einem eingeschränkten `readUserPreset(slot)`
entschieden — ohne daraus eine Factory-Unterstützung abzuleiten. Weder
P10 noch die Generalisierung sind mit diesem Dokumentationsschritt
implementiert.

## User/P01 vs. User/P10: Offline-Byte-Diff zur Vorbereitung (17.09.2026, rein offline)

Reine Auswertung bereits vorhandener Bytes (keine neue Capture, keine
Hardwarekommunikation). Ziel: exakt bestimmen, welche Bytes in Phase D
und den Read-Requests die Slot-Adresse tragen, welche konstant sind und
welche ggf. Zähler/Prüfsummen sein könnten — als Vorbereitung für einen
späteren, noch nicht durchgeführten P10-Test.

### Grundlage

Bestätigt sind bislang genau drei Bank/Slot-Kombinationen für das
Phase-D/Readback-Schema (siehe „Präambel-Analyse" oben): Factory/Slot 0,
User/Slot 0 (P01, dieser Bericht) und User/Slot 98 (P99, Endmarker-Beobachtung
beim Bank-Übergang). **User/Slot 9 (P10) wurde bislang in keiner Capture
und in keinem Hardwaretest beobachtet.** Alles Folgende zu P10 ist daher
ausdrücklich **HYPOTHESIS**, nicht CONFIRMED — es überträgt nur das bereits
an drei anderen Punkten bestätigte Offsetschema auf einen vierten,
ungetesteten Wert.

### Byte-Diff je Nachrichtentyp

**Phase-D Announce (16 Byte) — CONFIRMED: Offset 13 = Bank, Offset 14 = Slot:**

```text
User/P01 (bestätigt): F0 21 25 7F 51 4D 45 32 11 13 01 00 00 00 00 F7
                                                              ^^ Offset14=00 (Slot 0)
User/P10 (HYPOTHESIS): F0 21 25 7F 51 4D 45 32 11 13 01 00 00 00 09 F7
                                                              ^^ Offset14=09 (Slot 9 = P10)
```

Konstant (in allen drei bestätigten Datenpunkten identisch): Offsets 0–12
und 15 (Terminator). Offset 13 (Bank) bliebe für P10 unverändert `00`
(User). Offset 14 (Slot) ist der einzige Byte, der sich laut Schema ändern
müsste.

**Phase-D ACK (20 Byte) — CONFIRMED: Offset 13 = Bank, Offset 14 = Slot; Offsets 15–18 UNKNOWN:**

```text
User/P01 (bestätigt): F0 21 25 7F 51 4D 45 32 12 13 01 00 01 00 00 0C 1C 01 40 F7
                                                              ^^ Offset14=00
User/P10 (HYPOTHESIS): F0 21 25 7F 51 4D 45 32 12 13 01 00 01 00 09 ?? ?? ?? ?? F7
                                                              ^^ Offset14=09      ^^^^^^^^^^^ unbekannt
```

Offsets 15–18 (`0C 1C 01 40` bei User/P01) sind **UNKNOWN, ob slot-abhängig
oder konstant** — die bisherige Dokumentation vermerkt zwar „keine
Session-abhängigen Bytes" (also nicht capture-zu-capture variabel für
denselben Slot), trifft aber keine Aussage darüber, ob sich diese vier
Byte zwischen unterschiedlichen Slots ändern, da nur Slot 0 jemals als
ACK-Payload beobachtet wurde. Ein zukünftiger P10-Test darf diese vier
Byte deshalb **nicht** als bytegleich zu P01 voraussetzen — `isValidAck`
prüft aktuell ohnehin nur exakte Gleichheit mit der einen bekannten
Referenz und würde einen abweichenden P10-ACK korrekt als „nicht
bestätigt" werten, nicht fälschlich akzeptieren.

**Part-0-Request (17 Byte) — CONFIRMED: Offset 13 = Bank, Offset 14 = Slot:**

```text
User/P01 (bestätigt): F0 21 25 7F 51 4D 45 32 12 13 01 00 02 00 00 01 F7
                                                              ^^ Offset14=00
User/P10 (HYPOTHESIS): F0 21 25 7F 51 4D 45 32 12 13 01 00 02 00 09 01 F7
                                                              ^^ Offset14=09
```

**Parts 1–9 (19 Byte je Request) — CONFIRMED, byteidentisch für jeden Slot, durch Konstruktion:**
Diese neun Folge-Requests tragen laut bereits bestätigtem Schema
(`VerifiedPresetP01FullReadReference`, `isValidResponseForPart`) **keine
Bank-/Slot-Adresse** — nur einen Fortsetzungszähler an Offset 16 (0–8) und
konstante Header-Bytes. Sie wären für einen P10-Read **exakt dieselben
19 Byte** wie für P01, da die Bank/Slot-Zuordnung laut aktuellem
Verständnis bereits durch Phase D + Part 0 für die gesamte Lesesitzung
etabliert wird. Das ist keine neue Hypothese, sondern eine direkte Folge
des bereits bestätigten Nachrichtenformats — aber ebenfalls nicht
unabhängig an einem zweiten Slot geprüft.

### Zusammenfassung: was ein P10-Test bestätigen oder widerlegen würde

| Erwartung | Evidenzgrad vor P10-Test |
|---|---|
| Phase-D Announce/Part-0: nur Offset 14 ändert sich (00→09) | HYPOTHESIS (Schema an 3 anderen Punkten CONFIRMED, P10 selbst nicht) |
| Phase-D ACK Offsets 15–18 bleiben `0C 1C 01 40` | UNKNOWN — könnte auch slot-abhängig sein |
| Parts 1–9 sind byteidentisch zu P01 | Folgt aus bestätigtem Format, aber an P10 nicht geprüft |
| Gesamter Zyklus liefert `READBACK_CONFIRMED` für P10 | Offen — genau das wäre das Testziel |

Keine dieser Byte-Werte wurde gesendet oder geraten an das Gerät
übertragen; diese Tabelle dient ausschließlich der Vorbereitung eines
späteren, separat freizugebenden P10-Hardwaretests.

## STORE-Wiederauswertung für den Safe-Write-Lab-Meilenstein (17.09.2026, rein offline)

Reine Neubewertung bereits vorhandener Befunde (Store-Capture-Zerlegung
oben, „Vollständiger Device→Host-Readback und Persistenzbeweis"). Keine
neue Capture, keine Gerätekommunikation. Ziel: für die Safe-Write-Lab-
Architektur einen expliziten, gerätenachrichtenscharfen Evidenzstatus
festzulegen, statt implizit von „Persistenz war ja schon bewiesen"
auszugehen.

### Die fünf Burst-Nachrichten einzeln bewertet

| # | Länge | Header | Inhalt | Verdict |
|---:|---:|---|---|---|
| 1 | 34 | `12 11`/`00` | ASCII „CKY 96 STUD\0" | CORRELATED — neue Nachrichtenfamilie (Kopfbyte `0x11`/`0x12`, sonst nirgends beobachtet), zeitlich unmittelbar nach dem letzten Parameterwrite; Bedeutung als Store-Bestandteil plausibel, aber isoliert nicht bestätigt |
| 2 | 34 | `12 11`/`04` | alle übrigen Bytes 0 | CORRELATED — gleiche Begründung wie #1 |
| 3 | 18 | `12 11`/`05` | Offset 14 = `04`, sonst 0 | CORRELATED — gleiche Begründung wie #1 |
| 4 | 64 | `12 11`/`07` | alle übrigen Bytes 0 | CORRELATED — gleiche Begründung wie #1 |
| 5 | 22 | `12 12`/`02` | alle übrigen Bytes 0 | HYPOTHESIS — einziger Kandidat mit eigenem, abweichendem Header (`12 12` statt `12 11`) und passender Kürze für einen „kleinen Commit-Befehl"; vom Capture-Inspector zusätzlich strukturell als „rejected preset-selection candidate" markiert (Offset 9 passt nicht zum bestätigten Presetauswahl-Header) — also nachweislich **keine** Presetauswahl, aber ihre positive Bedeutung als Store-Commit bleibt unbestätigt |

Keine der fünf Nachrichten enthält einen erkennbaren Presetindex, keine
wiederholt sich, keine löste in ihrer eigenen Capture eine beobachtbare
Geräteantwort aus (`NOT CAPTURED`, echte Endpoint-Lücke in dieser
spezifischen Datei — siehe Endpoint-Inventar oben).

### Die Persistenz-Korrelation ist real, aber beweist nicht, welche Nachricht speichert

Der spätere Persistenzbeweis (dritter Durchgang) zeigt: Nach Store-Burst
→ Editor schließen → USB-Neuverbindung → vollem Gerätesync sind alle
sechs Marker weiterhin korrekt. Das ist **CONFIRMED** als Gesamtergebnis
(„der Zustand nach diesem Ablauf ist persistent"), aber es isoliert
**nicht**, ob Nachricht 5, eine andere der fünf Nachrichten, eine
Kombination oder sogar ein reiner Zeit-/Timeout-Mechanismus des Geräts
für die Persistenz verantwortlich ist. Zwischen dem Store-Burst und dem
Persistenzbeweis liegt außerdem eine vollständig andere Capture-Sitzung
(Editor-Neustart) — kein durchgehend beobachteter Kausalpfad von
Nachricht 5 zu einem beobachteten Geräte-Commit-Ereignis.

### Verdict

**STORE bleibt BLOCKED.** Keine einzelne Nachricht aus dem Burst kann
mit der vorhandenen Evidenz allein als hinreichender, allgemeiner
Store-Befehl freigegeben werden — Nachricht 5 bleibt
`STORE_COMMIT_CANDIDATE` (HYPOTHESIS), die übrigen vier Nachrichten sind
CORRELATED, aber ohne erkennbaren eigenständigen Commit-Charakter. Für
den Safe-Write-Lab-Meilenstein folgt daraus: Der erste Hardware-Schritt
endet bei **BACKUP → WRITE GAIN → IMMEDIATE READ/OBSERVATION**; ein
STORE-Aufruf ist in dieser Phase weder implementiert noch vorgesehen.
Eine gezielte, isolierte Store-Hardwareuntersuchung (z. B. Store-Burst
einzeln mit vorhandenem 0x83-Capture, ohne die übrigen vier Sessions
dazwischen) bleibt ein möglicher, separat freizugebender späterer
Schritt.

## Write-Evidence-Matrix für die sechs AMP-Felder (Safe-Write-Lab-Meilenstein)

Maschinenlesbar geführt in `lib/presets/matribox_amp_field_evidence.dart`
(`MatriboxAmpFieldEvidenceRegistry`) — hier nur die Zusammenfassung, damit
sie nicht doppelt gepflegt wird:

| Feld | READ | INDEX | WRITE | STORE |
|---|---|---|---|---|
| Gain | CONFIRMED | CONFIRMED | **CONFIRMED** (40→41) | UNKNOWN |
| Presence | CONFIRMED | observed | UNKNOWN | UNKNOWN |
| Volume | CONFIRMED | observed | UNKNOWN | UNKNOWN |
| Bass | CONFIRMED | observed | UNKNOWN | UNKNOWN |
| Middle | CONFIRMED | observed | UNKNOWN | UNKNOWN |
| Treble | CONFIRMED | observed | UNKNOWN | UNKNOWN |

Nur Gain ist `hardwareWritable`. Alle sechs sind `readable`/`translatable`/
`writePlannable` (ihre Position ist bekannt genug, um in einem Plan
aufzutauchen), aber nur Gain darf ein Plan als tatsächlich schreibbar
markieren. `writeEvidence` für ein Feld wird ausschließlich in dieser
einen Registrierung angehoben, nie implizit durch `MatriboxPresetDecoder`,
`MatriboxPresetTranslator` oder `MatriboxPresetWritePlanner`, die alle
drei jetzt aus dieser Registrierung lesen statt eigene Kopien zu führen.

## Erster produktiver WyrmTone-Hardware-Write: Gain 17→18 (17.09.2026)

### Beweiskette

```
P01 Gain 17
  → WyrmTone produktiver READ (MatriboxPresetReader)
  → verifiziertes Raw-Backup (Hash re-verifiziert nach Save/Reload)
  → Safe Write Plan (MatriboxPresetWritePlanner, READY_FOR_HARDWARE_TEST)
  → Gain 17→18 (einzige geplante Operation)
  → manueller Nutzer-Confirm (Bestätigungsdialog)
  → produktiver QME2-Parameter-Write (MatriboxConfirmedGainWriter, ein Send)
  → App meldet SUCCESS / VOLATILE_WRITE_SENT
  → Gerät zeigt Gain = 18 (physisches Display, vom Nutzer fotografiert)
  → Gerät markiert Preset sichtbar als verändert (Sternchen vor Presetname)
  → manueller Hardware-Save (physische Save-Funktion am Gerät, NICHT durch WyrmTone ausgelöst)
  → USB-Disconnect (unabhängig vom Save, durch App-Backgrounding/Kabel ausgelöst)
  → USB-Reconnect
  → neuer produktiver WyrmTone-READ ("Safe Write Lab vorbereiten")
  → Gain = 18 (frisch gelesen, neues Backup, Hash validiert)
  → neuer Plan korrekt 18→19
```

Ein zweiter Schreibversuch (18→19) wurde vom Nutzer ausgelöst, scheiterte
aber mit `channelError`. Logcat-Auswertung (`adb logcat`, Zeitstempel
22:43:35.391) zeigt exakt zu diesem Zeitpunkt `MidiService: Removing
SONICAKE AUDIO SONICAKE MatriBox PRODUCT` — ein echter physischer
USB-Trennung, keine Logikfehler in `MatriboxConfirmedGainWriteSession`
oder im Plattformkanal. Der Fehler wurde korrekt und ohne stillen Erfolg
oder undefinierten Zustand als `SEND_FAILED`/`channelError` gemeldet.

### Das Sternchen als Korrelat für "ungespeichert"

Am physischen Gerätedisplay erschien nach dem Write `*CKY 96 STUD` (Sternchen
vor dem Presetnamen), wo vorher `CKY 96 STUD` ohne Sternchen stand. Das
**korreliert stark** mit einem veränderten/ungespeicherten Preset-Zustand —
mehr wird hier nicht behauptet. Insbesondere:

- Es ist NICHT bewiesen, dass das Sternchen ausschließlich diesen Zustand
  anzeigt (keine Gegenprobe mit anderen Änderungsarten durchgeführt).
- Es ist NICHT geprüft, ob/wie das Sternchen verschwindet (vermutlich über
  die physische Save-Funktion, aber nicht instrumentiert nachgewiesen).
- Es sagt nichts über QME2 STORE aus. WyrmTone hat keinerlei Store-Kommando
  gesendet; der Save nach dem Sternchen war eine rein manuelle
  Nutzeraktion am Gerät selbst.

### Finaler Gain-Evidenzstand (Sol 100 OD)

| Dimension | Status |
|---|---|
| READ | CONFIRMED |
| PARAMETER IDENTITY (Index 0) | CONFIRMED |
| WRITE MESSAGE (Byte-Format) | CONFIRMED |
| PRODUKTIVER WRITE-PFAD (Safe Write Session → nativer Writer) | CONFIRMED |
| DEVICE VALUE CHANGE (physisches Display zeigt 18) | CONFIRMED |
| READBACK (frischer produktiver Read zeigt 18) | CONFIRMED |
| PERSISTENCE NACH MANUELLEM GERÄTE-SAVE | CONFIRMED |
| QME2 STORE | **UNKNOWN/BLOCKED** — WyrmTone hat kein Store-Kommando gesendet und keines isoliert |

Maschinenlesbar in `lib/presets/matribox_amp_field_evidence.dart` als
`MatriboxAmpFieldEvidenceRegistry.gain.manualSavePersistenceEvidence`
(getrennt von `storeEvidence`, das weiterhin `unknown` bleibt und bleiben
muss).

### Presence: Offline-Untersuchung ohne neue Hardwarekommunikation

Durchsucht wurden alle lokalen Capture-/Fixture-/Analysedaten im Repository
nach einer rohen 34-Byte Sol-100-OD-Parameterschreib-Nachricht mit
Parameterindex 1 (Presence), analog zu den bestätigten Gain-Referenzen
(`f021257f...02040402f7` / `...02000402f7`).

**Ergebnis: keine solche rohe Byte-Nachricht existiert irgendwo im Repository.**
Vorhanden ist ausschließlich die bereits oben dokumentierte narrative/
tabellarische Auswertung aus dem Store-Capture (Abschnitt "Store-Capture:
vollständige chronologische Zerlegung"): Parameterindex 1, 23
Zwischennachrichten, Endwert 73 — abgeleitet von einer externen `.pcapng`-
Datei, die bewusst außerhalb von Git gehalten wird. Kein einziges rohes
Byte dieser Nachrichten ist im Repository, in Tests, in Fixtures oder in
Kotlin-/Dart-Quellcode hinterlegt.

Projektregel: Golden Protocol Fixtures werden niemals manuell
transkribiert. Da keine rohen Bytes vorliegen, aus denen programmatisch
extrahiert werden könnte, wurden folgende Schritte bewusst NICHT
durchgeführt:

- Kein `encodePresenceWrite(...)`-Encoder wurde gebaut. Die Encoding-
  *Formel* (Nibble-Pairing, Präfix, Struktur) ist zwar durch Gain
  bestätigt und ließe sich mechanisch mit Parameterindex 1 statt 0
  anwenden — aber ohne eine echte Presence-Referenznachricht zum
  Gegenprüfen wäre das Ergebnis eine unbewiesene Vorhersage, kein Golden
  Fixture. Das hätte "WRITE_FORMAT_CAPTURE_CONFIRMED" vorgetäuscht, wo nur
  eine Struktur-Hypothese vorläge.
- Kein Gain-vs-Presence-Byte-Diff wurde erzeugt, weil dafür zwei echte,
  beobachtete Nachrichten nötig wären; nur eine (Gain) existiert.
- Presence bleibt in `MatriboxAmpFieldEvidenceRegistry` unverändert:
  `readEvidence: confirmed`, `indexEvidence: observed`,
  `writeEvidence: unknown`. `writePlannable` bleibt `true` (die Position im
  AMP-Block ist bekannt genug für die Anzeige), `hardwareWritable` bleibt
  `false` -- der Write-Plan blockiert Presence weiterhin vollständig.

Um Presence auf denselben Stand wie Gain zu bringen, wird eine echte
Editor→Gerät-Presence-Schreibnachricht benötigt (z. B. Rohbytes/Hexdump
aus `matribox1_p01_store.pcapng` oder einem neuen, gezielten Presence-
Capture), aus der programmatisch extrahiert werden kann.

### Generalisierter Readback-Verifier (bereits vorhanden, jetzt auch für Presence getestet)

`MatriboxWriteVerifier` (`lib/presets/matribox_write_verification.dart`)
war bereits vollständig feldunabhängig implementiert (`expectedField` als
Parameter, `_fieldWindows`-Tabelle mit allen sechs AMP-Feldern) — es waren
bisher nur Gain-Testfälle vorhanden. `test/matribox_write_verification_test.dart`
wurde um zwei Presence-Fälle ergänzt (isolierte Presence-Änderung wird
vollständig verifiziert; Presence erwartet aber Gain geändert wird korrekt
als `expectedChangeMissing` mit Gain als `unexpectedChange` klassifiziert).
Damit gilt bestätigt: **Verifizieren darf mehr als Schreiben** — der
Verifier kann Presence (und die anderen vier bekannten Felder) bereits
korrekt beurteilen, obwohl der Writer sie weiterhin blockiert.

### Roadmap-Matrix der sechs Sol-100-OD-AMP-Regler

Abgeleitet aus dem tatsächlichen Registrierungsstand
(`MatriboxAmpFieldEvidenceRegistry`) und den obigen Feststellungen:

| Feld | Read | Encode (Offline) | CapturedWrite (rohe Bytes) | HardwareWrite | Readback |
|---|---|---|---|---|---|
| Gain | CONFIRMED | CONFIRMED | CONFIRMED | CONFIRMED | CONFIRMED |
| Presence | CONFIRMED | NO (keine Rohbytes vorhanden) | NO (nur narrative Index/Wert-Korrelation) | NO | Verifier-fähig, aber nichts zu verifizieren ohne Write |
| Volume | CONFIRMED | NO | NO (nur narrative Korrelation) | NO | Verifier-fähig |
| Bass | CONFIRMED | NO | NO (nur narrative Korrelation) | NO | Verifier-fähig |
| Middle | CONFIRMED | NO | NO (nur narrative Korrelation) | NO | Verifier-fähig |
| Treble | CONFIRMED | NO | NO (nur narrative Korrelation) | NO | Verifier-fähig |

"Verifier-fähig" heißt: `MatriboxWriteVerifier` kann bei einem zukünftigen
Write dieses Feld korrekt als erwartete Änderung erkennen und alle anderen
fünf Felder plus unklassifizierte Bytes als unerwartet/unbekannt
klassifizieren -- das wurde bereits jetzt für Gain und Presence getestet,
gilt aber strukturell für alle sechs, da `_fieldWindows` alle sechs
Byte-Fenster bereits enthält.

### Presence-Hardwaretest: vorbereitet, NICHT ausgeführt

Sobald eine echte Presence-Schreibnachricht aus einem Originalcapture
vorliegt und ein Encoder byteidentisch dagegen verifiziert ist, sieht der
nächste kontrollierte Test strukturell genauso aus wie der Gain-Test:

```
READ (produktiv) → BACKUP → HASH VERIFY → Presence-Plan
  (current+1, oder current-1 bei 99, analog zur Gain-Lab-Regel)
  → manueller Confirm → genau ein Presence-Write → Gerät beobachten
  → Save nur falls Nutzer das explizit will → Reconnect
  → READBACK (produktiver Read) → BYTE VERIFY (MatriboxWriteVerifier,
    expectedField: 'presence')
```

In diesem Auftrag wurde dafür **nichts gesendet** -- weder ein Presence-
Write noch ein erneuter Gain-Write (18→19 bleibt offen für einen späteren,
separat freigegebenen Test).

### Welche vorhandenen WyrmTone-Sounds nutzen heute bereits Sol 100 OD?

Der Katalog `assets/catalog/sound_profiles.json` enthält aktuell genau zwei
Einträge: `cob-angels-dont-kill` ("Angels Don't Kill") und
`melodic-death-tight-rhythm` (Genre-Fallback, `baseId` zeigt auf denselben
Song). Beide basieren auf `lib/data/target_sounds.dart`s `ampModel: 'J900'`
-- das gilt aber nur für den **DNAfx-GiT-Core-Pfad** (Standard-Zielgerät,
`RecommendationController.selectedTargetDevice` startet mit
`TargetDeviceId.dnafxGitCore`). Für dieses Zielgerät bleibt die frühere
Aussage korrekt: J900 hat keine Matribox-Wire-Zuordnung, der Translator
meldet `unsupported`.

Wird stattdessen **`TargetDeviceId.matriboxOne`** als Zielgerät gewählt,
verwendet `OfflineDeviceCatalog.amps()` eine komplett andere, Matribox-
eigene Amp-Kandidatenliste (`Sol 100 OD` / `Sol 100 LD`) -- J900 kommt für
Matribox nie in Frage. Ein neuer, unabhängiger Test
(`test/offline_sound_test.dart`, "both bundled profiles resolve to Sol 100
OD (not LD) on Matribox") bestätigt programmatisch: **für beide gebündelten
Profile gewinnt bei Matribox als Zielgerät `Sol 100 OD`** (das Gain-
Scoring zieht beide Profile näher an "OD" als an "LD"). Damit übersetzen
beide heute bereits erfolgreich (nicht `unsupported`) über den bestätigten
Sol-100-OD-Wire-Pfad -- vorausgesetzt, der Nutzer wählt Matribox explizit
als Zielgerät. Das ist keine neue Zuordnung, die wir erfunden hätten,
sondern bereits vorhandenes, jetzt nur erstmals programmatisch bestätigtes
Verhalten des bestehenden `OfflineSoundEngine`/`OfflineDeviceCatalog`-Codes.


## Sol 100 OD: vollständige AMP-Write-Evidenz aus dem Original-Store-Capture (18.09.2026, rein offline)

Ersetzt die Aussage des vorigen Abschnitts ("keine rohen Presence-Bytes
verfügbar"): die Originaldatei wurde lokal gefunden und programmatisch
ausgewertet. Keine Hardwarekommunikation, kein Store, kein Read.

### Quelle und Methode

| Punkt | Wert |
|---|---|
| Datei | `matribox1_p01_store.pcapng` (lokal außerhalb des Repos, nur gelesen, nicht kopiert/verschoben) |
| SHA-256 | `35D845D3855A4DABFC1E57A4F8C53227729FF0A77282F5AB5ACC4BB83169CC1C` — identisch mit dem oben dokumentierten Wert |
| Extraktion | vorhandener `tool/matribox_capture_inspector.dart` (TShark) → JSON-Report im Scratchpad, dann temporäres Analyseskript (nach Gebrauch gelöscht) |
| Unabhängiger Decode | eigener Nibble-/Float32-Decode aus den Rohbytes **und** `ConfirmedParameterCodec.decode`; beide stimmen für alle Nachrichten überein |
| Fixtures | `test/support/matribox_sol100od_write_fixtures.dart`, **generiert** (nicht abgeschrieben); nur 18 Nachrichten, keine Binärdatei |

Gefunden: 121 Host→Gerät-Nachrichten (0 Gerät→Host), davon 118 mit 34 Byte.
116 davon sind QME2-Parameterschreibnachrichten (Algorithmus `0x07000047`);
2 weitere 34-Byte-Nachrichten haben Kopfbyte 9 = `0x11` (Store-Burst,
unverändert unklassifiziert).

### Parametergruppen (Host→Gerät, Reihenfolge der Bedienung)

| Index | Feld | Anzahl | Zeit (ms) | erster → letzter Wert | Min/Max |
|---:|---|---:|---|---|---|
| 0 | Gain | 13 | 3.731–5.484 | 29 → **17** | 17/29 |
| 1 | Presence | 23 | 8.949–11.499 | 51 → **73** | 51/73 |
| 3 | Bass | 29 | 18.108–21.382 | 49 → **23** | 22/49 (22 → 23 Korrektur am Ende) |
| 2 | Volume | 3 | 28.134–28.984 | 49 → **47** | 47/49 |
| 4 | Middle | 25 | 32.471–37.802 | 49 → **67** | 49/67 (nicht monoton) |
| 5 | Treble | 23 | 41.994–43.912 | 51 → **31** | 31/52 |

Die Endwerte **17 / 73 / 47 / 23 / 67 / 31** werden direkt aus den
extrahierten Bytes reproduziert. Kein Mismatch, kein unerwartetes Byte in
den 116 Parameternachrichten.

### Byte-Layout (gegen alle 116 Nachrichten geprüft)

```
 0..12  F0 21 25 7F 51 4D 45 32 12 10 03 00 02   konstant
13..20  Algorithmus-ID  u32 LE, nibble-gepaart (8 Bytes)   = 0x07000047, konstant
21..24  Parameterindex  u16 LE, nibble-gepaart (4 Bytes)   Byte 22 variiert (0..5)
25..32  Wert            float32 LE, nibble-gepaart (8 Bytes) variiert
33      F7
```

Über alle 116 Nachrichten variieren ausschließlich die Positionen 22
(Index) und 29/30/32 (Wertnibbles); alles andere ist konstant. Damit ist
das aus Gain bekannte Format **parameterunabhängig** belegt.

### Kontrolle und byteidentische Encoder-Tests

- **Gain-Kontrolle:** `encodeMessageBytes` reproduziert alle 116 Nachrichten
  byteidentisch (einmalig offline gemessen); die 18 eingecheckten
  Fixtures werden in `test/matribox_sol100od_encoder_test.dart` dauerhaft
  byteexakt gegen `MatriboxSol100OdEncoder` (alle sechs Felder) und den
  bestätigten `MatriboxConfirmedParameterWriter` (Gain) geprüft. Der native
  Kotlin-`MatriboxConfirmedGainWriter` reproduziert drei echte Capture-
  Nachrichten (29/23/17) byteexakt (`MatriboxConfirmedGainWriterTest`).
- Fixture-Auswahl je Feld: erste, mittlere, letzte Nachricht (Volume: alle 3).

### Evidenz-Upgrade (Quelle: `MatriboxAmpFieldEvidenceRegistry`)

| Feld | Read | Index | Raw-Write-Capture | Encode | Aktiver HW-Write | Readback nach Write | Manuelles Save | QME2 Store |
|---|---|---|---|---|---|---|---|---|
| Gain | CONFIRMED | CONFIRMED | CONFIRMED | CONFIRMED | CONFIRMED | CONFIRMED | CONFIRMED | UNKNOWN |
| Presence | CONFIRMED | CONFIRMED | CONFIRMED | CONFIRMED | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN |
| Volume | CONFIRMED | CONFIRMED | CONFIRMED | CONFIRMED | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN |
| Bass | CONFIRMED | CONFIRMED | CONFIRMED | CONFIRMED | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN |
| Middle | CONFIRMED | CONFIRMED | CONFIRMED | CONFIRMED | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN |
| Treble | CONFIRMED | CONFIRMED | CONFIRMED | CONFIRMED | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN |

Begründung Index-Upgrade `observed → confirmed`: Endwert jeder Indexgruppe
= Markerwert des benannten Reglers **und** derselbe Wert steht im
Full-Preset-Readback an der bestätigten Knob-Position.

**ENCODABLE ≠ HARDWARE_WRITABLE:** alle sechs Felder sind `encodable`;
nur Gain ist `hardwareWritable`. `MatriboxSol100OdEncoder` hat keinen
Transport; `MatriboxConfirmedParameterWriter.isSupported` und die nativen
Kanäle erlauben weiterhin nur Gain (kein neuer Plattformkanal,
`usb_no_write_test.dart` unverändert grün). Der capture-bestätigte Editor-
Write beweist nicht, dass **WyrmTones** Nachricht am Gerät wirkt — dafür
bleibt je Feld ein aktiver Hardwaretest nötig.

### Echter Song-Plan: Angels Don't Kill → Matribox (offline)

Reale Pipeline (`test/matribox_song_plan_test.dart`): Profil
`cob-angels-dont-kill` → `OfflineSoundEngine` (Zielgerät `matriboxOne`,
Testgitarre HB Fusion 4, Drop C, Rhythm) → `DraftPresetAdapter` →
`MatriboxPresetTranslator` → Diff gegen den CKY-96-STUD-Fixture-Snapshot
(Gain 17, Stand vor dem Hardware-Write) → `MatriboxPresetWritePlanner`.

| Feld | aktuell | Ziel | Translation | Encode | HW-Write | Plan |
|---|---:|---:|---|---|---|---|
| Gain | 17 | 67 | translated | ENCODABLE | CONFIRMED | writable |
| Presence | 73 | 59 | translated | ENCODABLE | UNKNOWN | blocked |
| Volume | 47 | 50 | translated | ENCODABLE | UNKNOWN | blocked |
| Bass | 23 | 41 | translated | ENCODABLE | UNKNOWN | blocked |
| Middle | 67 | 59 | translated | ENCODABLE | UNKNOWN | blocked |
| Treble | 31 | 61 | translated | ENCODABLE | UNKNOWN | blocked |

Amp: Sol 100 OD. Plan-Gate: **BLOCKED** (fünf von sechs Änderungen nicht
hardware-schreibbestätigt). Zielwerte kommen unverändert aus der
Recommendation-Engine; die Gitarre ist ein Testprofil, andere Gitarren
verschieben die Werte.

### Vorbereiteter Hardwaretest je Feld (NICHT ausgeführt)

Reihenfolge Presence → Volume → Bass → Middle → Treble, jeweils:
READ → BACKUP → VERIFY → aktueller Wert ±1 (bei 99: −1) → genau ein Feld →
WritePlan → manuelle Bestätigung → ein Write → Geräteanzeige beobachten →
manueller Save → Reconnect → READBACK → `MatriboxWriteVerifier`
(`expectedField` = Feld). Dafür fehlt je Feld noch ein freigegebener,
evidenzgesteuerter Writer-Pfad (Store bleibt UNKNOWN/BLOCKED).

## Sol 100 OD AMP Hardware Certification (18.09.2026, Build/Bedienung)

Ein einziger Lab-Pfad zertifiziert Presence → Volume → Bass → Middle →
Treble **einzeln** (je ein ±1-Write: `current+1`, bei 99 `current-1`; reine
Lab-Logik, keine Recommendation). Gain gilt als zertifiziert und wird nicht
erneut getestet.

- **Gate:** `--dart-define=ENABLE_MATRIBOX_SOL100OD_AMP_CERTIFICATION=true`
  (nur Debug; Default und Release `false`). Aktiviert nativ zusätzlich
  Raw-Backup/Read; exklusiv zu `ENABLE_MATRIBOX_P01_GAIN_WRITE` und allen
  Experimental-Probes.
- **Kanal:** `writeCertificationAmpField` nimmt ausschließlich `field`
  (Whitelist) und `targetValue`; Algorithmus fest Sol 100 OD, Wert 0..99,
  nur User/P01, ein Write pro USB-Verbindung, kein Retry, kein Store.
- **Ablauf je Feld:** Vorbereiten (READ → Backup → Reload → Hash → ±1-
  Ein-Feld-Diff) → manuelle Bestätigung → genau ein Write → STOP
  (`WRITE_SENT`, nicht zertifiziert). Danach manuell: Gerät prüfen, am Gerät
  speichern, USB trennen/neu verbinden, „Readback prüfen" (neuer Read gegen
  das BEFORE-Backup, `MatriboxWriteVerifier`). Nur bei erwartetem Feld = Ziel,
  keiner anderen bekannten Änderung und keiner unbekannten Raw-Änderung:
  `CERTIFIED`; sonst `EXPECTED_CHANGE_MISSING`, `UNEXPECTED_KNOWN_CHANGE`,
  `UNKNOWN_RAW_CHANGE`, `READ_FAILED` oder `BACKUP_MISMATCH`.
- **Keine Selbstzertifizierung:** Ergebnisse stehen nur im lokalen
  Session-Store (`sol100od_amp_certification.state` im Backup-Ordner).
  `MatriboxAmpFieldEvidenceRegistry` (`writeEvidence`, `readbackAfterWrite`)
  wird nur in einem separaten Entwicklungsschritt nach ausgewertetem
  Hardwaretest angehoben. Der Song-WritePlan bleibt bis dahin BLOCKED.
- **Unterschieden bleiben:** aktiver Write, Readback, manuelles Save, QME2
  Store (UNKNOWN/BLOCKED).

## Strategiewechsel: Big Capture für Blöcke FX1/FX2/AMP/CAB/NR/EQ/MOD/DLY/RVB (18.09.2026, Planung, keine Hardwareaktion)

Gain und Presence sind physisch bestätigt; das 34-Byte-Parameterformat
gilt als ausreichend belegt. Volume/Bass/Middle/Treble sind **pausiert**.
Ziel ist ein einziger Editor-Capture (User P01, **inklusive CAB**),
der Modellwahl, Parameter, ON/OFF, Name und Store gleichzeitig sichtbar
macht.

### Matribox-1-Katalog (aus `assets/catalog/matribox_preset_catalog.json`, generiert aus `algorithm.xml`)

181 Algorithmen / 631 Parameter (Summe der Blöcke unten stimmt). Codes sind
über alle Blöcke eindeutig, **außer** dass FX1 und FX2 dieselben 25 Codes
teilen — der Code allein kann den Slot also nicht unterscheiden.

| Block | Modelle | Klassenbyte(s) im Code | Parameter | Hinweis |
|---|---:|---|---:|---|
| FX1 | 25 | 00, 01, 03, 05 | 92 | gleiche Codes wie FX2 |
| FX2 | 25 | 00, 01, 03, 05 | 92 | gleiche Codes wie FX1 |
| AMP | 45 | 07, 08, 0f | 250 | 6 Knobs (Gain/PRES/Master/Bass/Middle/Treble) |
| NR | 2 | 00 | 4 | Gate 1 (1 P), Gate 2 (3 P) |
| CAB | 53 | 0a | 53 | 38 benannte Cabs (0x0a0000xx) + 15 unbenannte Einträge (0x0a1000xx, vermutlich IR-Slots, unbestätigt); je nur `VOL` 0..99 |
| EQ | 2 | 01 | 12 | Guitar EQ / Bass EQ, ±50 |
| MOD | 10 | 04 (Detune: 01) | 36 | Sync = Schalter |
| DLY | 11 | 0b | 60 | Time 20..4000, Sync/Trail = Schalter |
| RVB | 8 | 0c | 32 | Trail = Schalter |

### Big-Capture-Testplan (User P01, inklusive CAB)

Alle Werte liegen in den XML-Bereichen und wurden gegen den echten
Ist-Zustand geprüft (jedes Zielmodell weicht vom aktuellen ab). Vor Beginn
den Editor-Screenshot mit allen Blöcken erneuern. Werte bewusst nie „50“.

**Ist-Zustand von P01 laut Editor-Screenshot (Editor V1.1.1):** FX1 Octaver,
FX2 Skreamer, AMP Sol 100 OD, NR Gate 2, CAB Bog SV 1x12 (VOL 50), EQ
Guitar EQ, MOD Chorus A, DLY Warm, RVB Room; Preset BPM 120, Preset VOL 50.
**Einschaltzustand (Ground Truth, korrigiert):** FX1 ON, FX2 OFF, AMP ON,
**NR ON, CAB OFF**, EQ ON, MOD OFF, DLY OFF, RVB ON. Die erste mündliche
Angabe (NR OFF, CAB ON) widersprach dem Editor-Export (`effectState`: NR 1,
CAB 0) und dem Screenshot (NR-Schalter hell, CAB-Schalter dunkel); Export und
Screenshot stimmen überein und gelten. Das CAB-Fenster
listet **User IR 1..15** — die 15 unbenannten Katalogeinträge (0x0a1000xx)
sind damit die IR-Slots (Zuordnung Slot ↔ Code noch nicht belegt).

| Block | Ist → Test | Code (Test) | Testwerte |
|---|---|---|---|
| FX1 | Octaver → Skreamer | 0x03000000 | Gain 23, Tone 47, VOL 59 |
| FX2 | Skreamer (bleibt zuerst gleich, Slot-Test) → Blues OD | 0x03000000, dann 0x03000009 | Skreamer: Gain 31, Tone 73, VOL 41; danach Blues OD: Gain 19, Tone 61, VOL 37 |
| AMP | Sol 100 OD → Brit 800 | 0x07000035 | Gain 17, PRES 67, Master 31, Bass 41, Middle 47, Treble 59 |
| CAB | Bog SV 1x12 → BritMD 4x12; optional danach User IR 7 wählen (nichts importieren) | 0x0a000021 (User IR 7: vermutlich 0x0a100006, unbelegt) | VOL 43; bei User IR 7 VOL 37 |
| NR | Gate 2 → erst Gate 1, dann wieder Gate 2 | 0x0000001b, dann 0x0000001d | Gate 1: THRE 17; Gate 2: THRE 31, ATK 41, Rel 59 |
| EQ | Guitar EQ → Bass EQ | 0x0100003a | 50Hz +17, 120Hz −23, 400Hz +31, 800Hz −41, 2kHz +47, VOL 59 |
| MOD | Chorus A → Flanger | 0x04000011 | Depth 23, Rate 3.7 Hz, PreDly 47, FdBk 59, Sync einmal umschalten |
| DLY | Warm → Sweep | 0x0b000006 | Mix 17, FdBk 31, Time 743, Swp Depth 41, Swp Rate 59; Swp Sync/Time Sync/Trail je einmal umschalten |
| RVB | Room → Mod RVB | 0x0c000008 | Mix 23, Pre Delay 67, Decay 41, Lo End +17, Hi End −23, Trail einmal umschalten |
| Preset (optional) | Preset VOL 50, Preset BPM 120 | unbekannt | Preset VOL 37, Preset BPM 137 |

Warum FX2 zuerst noch Skreamer bleibt: FX1 (dann Skreamer) und FX2
(Skreamer) haben denselben Code. Schreibt der Editor die Parameter beider
Slots mit identischem Code, zeigt der Vergleich, **wo** die Slot-
Information in der Nachricht steckt (Header Bytes 8..12, in allen 116
Amp-Writes konstant `12 10 03 00 02`, sind der erste Kandidat).

### Bedienreihenfolge im Sonicake-Editor (mit Pausen)

Vorbereitung: (a) WyrmTone am Handy: P01 Full Read → Raw-Backup **BEFORE**;
(b) im Editor P01 zusätzlich über die Editor-Exportfunktion sichern
(.prst); (c) Matribox an den PC, Editor verbinden, P01 wählen, warten bis
Verkehr ruht; (d) USBPcap/Wireshark auf dem Bus der Matribox starten,
Stoppuhr (Sekunden) im selben Moment starten; jede Aktion mit Stoppuhrzeit
notieren. Nach jeder Aktion **3 s Pause**, nach jedem Block **6 s**.

1. FX1 Modell Octaver → Skreamer
2. FX1 Parameter: Gain 23, Tone 47, VOL 59
3. FX2 Parameter (Modell bleibt Skreamer, Slot-Test): Gain 31, Tone 73, VOL 41
4. FX2 Modell Skreamer → Blues OD
5. FX2 Parameter: Gain 19, Tone 61, VOL 37
6. AMP Modell → Brit 800
7. AMP Parameter: Gain 17, PRES 67, Master 31, Bass 41, Middle 47, Treble 59
8. CAB Modell Bog SV 1x12 → BritMD 4x12
9. CAB Parameter: VOL 43; optional User IR 7 wählen (nichts importieren), VOL 37
10. NR Modell Gate 2 → Gate 1, THRE 17; dann wieder Gate 2, THRE 31, ATK 41, Rel 59
11. EQ Modell → Bass EQ
12. EQ Parameter: 50Hz +17, 120Hz −23, 400Hz +31, 800Hz −41, 2kHz +47, VOL 59
13. MOD Modell → Flanger
14. MOD Parameter: Depth 23, Rate 3.7, PreDly 47, FdBk 59, Sync umschalten
15. DLY Modell → Sweep
16. DLY Parameter: Mix 17, FdBk 31, Time 743, Swp Depth 41, Swp Rate 59, dann Swp Sync, Time Sync, Trail je einmal umschalten
17. RVB Modell → Mod RVB
18. RVB Parameter: Mix 23, Pre Delay 67, Decay 41, Lo End +17, Hi End −23, Trail einmal umschalten
19. (optional) Preset VOL 50 → 37, Preset BPM 120 → 137
20. Block ON/OFF (je Aktion 3 s Pause, Reihenfolge wie aufgeführt; jeder Block wird einmal in den anderen Zustand und danach wieder zurück geschaltet, Endzustand = Ausgangszustand):
    - FX1: ON → OFF → ON
    - FX2: OFF → ON → OFF
    - AMP: ON → OFF → ON
    - CAB: OFF → ON → OFF
    - NR: ON → OFF → ON
    - EQ: ON → OFF → ON
    - MOD: OFF → ON → OFF
    - DLY: OFF → ON → OFF
    - RVB: ON → OFF → ON
21. Presetname → `CAP TEST 01` (11 Zeichen wie `CKY 96 STUD`)
22. STORE (Button **Save** im Editor); danach 10 s warten, Capture stoppen und als `.pcapng` sichern (Datei nicht ins Repo)

Nach dem Save zusätzlich im Editor **Export → `P01_AFTER_BIG_CAPTURE.prst`** (XML mit allen Blöcken/Werten, Ground Truth des Endzustands).
Danach: Matribox ans Handy, WyrmTone P01 Full Read → Raw-Backup **AFTER**.
Ground-Truth-Triple: BEFORE-Backup, Editor-Capture, AFTER-Backup.

### Automatisierte Auswertung danach

```text
dart run tool/matribox_capture_inspector.dart --capture big.pcapng --output big_report.json
dart run tool/matribox_big_capture_analyzer.dart --report big_report.json \
  --before <BEFORE.wyrmtone-raw-preset.json> --after <AFTER.wyrmtone-raw-preset.json> \
  --output big_analysis.md
```

Der Analyzer (`lib/presets/matribox_capture_classifier.dart`) clustert **alle**
Host→Gerät-SysEx nach Länge + Header (nicht nur 34 Byte), dekodiert die
bekannte Parameterfamilie, bildet Algorithmuscodes auf den Katalog ab,
listet Codewechsel samt dazwischenliegender Nachrichten (Kandidaten für
Modellwahl), Namenskandidaten (ASCII), variable Bytepositionen je Cluster
und die zusammenhängenden BEFORE/AFTER-Rohbyteänderungen. Getestet an den
echten Store-Capture-Fixtures; ein Probelauf auf `matribox1_p01_store.pcapng`
findet 116 Parameterwrites, den Namen `CKY 96 STUD` und die fünf
Store-Burst-Cluster. Der optionale II-Pro-Abgleich (`--reference`) liefert
nur EXACT/STRUCTURAL/NO MATCH als Hinweis, nie ein Matribox-1-CONFIRMED.

### II-Pro-Referenz (MATRIBOX_II_PRO_REFERENCE, nichts davon Matribox-1-bestätigt)

**Quelle.** Das genannte Repo `hurricaneabel/matribox-ii-pro-sysex-research` ist
öffentlich **nicht erreichbar (HTTP 404)**; das Konto hat öffentlich nur
`Matribox_II_Pro_MidiCon` (Commit `f76dace`, 04.06.2026). Nur dieses wurde
ausgewertet (frischer Klon; der ältere lokale Klon enthielt nur 4 Dateien).
`catalog/effects/`, `tools/commands/`, `tools/experiments/`, Add/Replace/
Remove-Kommandos, Checksummen-Forschung und Preset-Dump-Doku **existieren dort
nicht**. Falls das SysEx-Research-Repo privat/anders benannt ist, muss es
separat bereitgestellt und dieser Abschnitt erneut geprüft werden.

**Was das Repo enthält:** hauptsächlich Standard-MIDI CC/PC (II Pro,
hardwaregetestet), dazu **passiv mitgeschnittene, nur empfangene** SysEx der
II Pro (`matribox_sysex.py`, `descobrindo/*.txt`). Kein Sender, keine
Parameterwerte, kein Store, keine Checksumme.

| Element | II Pro (Referenz) | Matribox 1 (unsere Belege) | Urteil |
|---|---|---|---|
| Header | `F0 21 25 4D 50 00 00 …` | `F0 21 25 7F 51 4D 45 32 …` ("QME2") | STRUCTURALLY_SIMILAR nur im Herstellerpräfix `21 25`, danach DIFFERENT |
| Nachrichtenlängen | 130 / 110 / 128 (geräteseitig) | 34 / 22 / 18 / 64 / 210 / 46 (host→Gerät und Readback) | DIFFERENT |
| 34-Byte-Parameterwrite | nicht vorhanden | bestätigt | UNKNOWN (Referenz) |
| Algorithmus-/Modellcodierung | Klassennibble `d[49]` + Modellnibblepaar `d[60..61]` (AMP zusätzlich `d[67]`) | u32-LE-Code, Klassenbyte oben (0x03 Drive, 0x07 AMP, 0x0b DLY, 0x0c RVB …) | DIFFERENT |
| Parameterindex / Float | nicht vorhanden | u16 LE / float32 LE | UNKNOWN (Referenz) |
| Nibble-Paarung der Nutzdaten | Werte 0..15 je Byte, `hi*16+lo` | identisch belegt | STRUCTURALLY_SIMILAR |
| Modellwahl / Ersetzen / Entfernen | nur als Geräte→Host-Benachrichtigung | unbekannt | UNKNOWN |
| Enable/Disable | CC43–54 (Plain-MIDI) + ungetesteter Decoder | unbekannt (SysEx) | UNKNOWN |
| Preset-Dump | nur ungetesteter Decoder-Rate, kein Sample | 10-Teile-Readback bestätigt | UNKNOWN (Referenz) |
| Store/Commit | nicht vorhanden | Burst `12 11`/`12 12` (hypothesis) | UNKNOWN (Referenz) |
| Checksumme | Byte 6 variiert, nicht erklärt (Summe/XOR passen nicht) | Part 8 Byte 37..44 ändert sich mit jedem Write (korreliert) | UNKNOWN |

**Referenzmatrix je Block** (II-Pro-„Tabelleneinträge“ sind Größen der
Python-Dicts, keine belegten Modellzahlen; Klassen-IDs sind II-Pro-
Nummerierung):

| Block | II-Pro-Klasse | II-Pro-Selektorfamilie | II-Pro-Parameterformat | II-Pro-Einträge | II-Pro-Hardwarebeleg | Matribox-1-XML | M1-Algorithmus-IDs | M1-Captureevidenz | Ähnlichkeit | Status |
|---|---|---|---|---:|---|---|---|---|---|---|
| FX/DRIVE | 3 (DRV), 0 AC, 1 FILTER, 2 WAH | 128-Byte-Modellwechsel | keins | 24 (DRV) | 1–8 Captures je Klasse | FX1/FX2 (25) | 0x00/01/03/05… | nur Amp-Writes | keine belegbar | DIFFERENT |
| AMP | 4 | 128 B, Schlüssel `d[60],d[61],d[67]` | keins | 63 | 7 Captures | AMP (45) | 0x07/08/0f… | 6 Knobs bestätigt (Gain hardware, Presence hardware) | keine belegbar | DIFFERENT |
| NR/DYN/GATE | keine (108-B-Familie) | 108-Byte-Modellwechsel, Schlüssel `d[58],d[59]` | keins | 12 | 40 Captures | NR (2) | 0x1b, 0x1d | keine | keine belegbar | UNKNOWN |
| EQ | 7 | 128 B | keins | 5 | 2 Captures | EQ (2) | 0x01000035/3a | keine | keine belegbar | DIFFERENT |
| MOD | 8 | 128 B | keins | 23 | 3 Captures | MOD (10) | 0x04… | keine | keine belegbar | DIFFERENT |
| DLY | 9 | 128 B | keins | 16 | 4 Captures | DLY (11) | 0x0b… | keine | keine belegbar | DIFFERENT |
| RVB | 10 | 128 B | keins | 12 | 3 Captures | RVB (8) | 0x0c… | keine | keine belegbar | DIFFERENT |
| CAB | 5 (+ IR 6) | 128 B | keins | 61 | 3 Captures | CAB (53) | 0x0a… | keine (jetzt im Big Capture geplant) | keine belegbar | DIFFERENT |

**Hypothese „gleiche PC-Software ⇒ gleiches Protokoll“:** durch dieses
Material **nicht gestützt**. Der Header unterscheidet sich ab Byte 3,
Längen, Richtung und Klassennummerierung passen nicht; gemeinsam sind nur
Herstellerpräfix und Nibble-Paarung (bei M1 unabhängig belegt). Die
Verwandtschaft der Editor-Strukturen bleibt eine ungetestete Annahme.

**Als Hypothese für Matribox 1 nutzbar (nur zu prüfen, nicht übernehmen):**
(1) Modellwechsel trägt Klasse + Modellschlüssel, ggf. ein Unterindex bei
gleichen Schlüsselpaaren — beim Big Capture Header Bytes 8..12 und
Codewechsel gezielt ansehen; (2) Enable/Disable könnte slotnummeriert sein;
(3) eine größere Nachricht könnte den „Kettenzustand“ als konstante
Familie tragen.
**Nicht übernehmen:** Offsets, Längen, Klassen-IDs, Modelltabellen, das
Byte 6 als Checksumme, die ungetesteten Decoder für Preset/On-Off, die
CC-Belegung als SysEx-Beleg und die Widersprüche der CC29-Doku.

### Durchführung Big Capture (19.09.2026)

**Phase 1, BEFORE-Read (WyrmTone, read-only):** APK nur mit
`ENABLE_MATRIBOX_P01_RAW_BACKUP` (alle Schreib-Gates false). Snapshot
User/P01 "CKY 96 STUD": SHA-256
`fe2a6b826fb42ddca9e95ec5de8d72cb58cee6f72c32b330250ac08d23a893a4`
(byteidentisch zum Read vom 18.09. 21:58, P01 seitdem unverändert); Werte
Gain 18, Presence 74, Volume 47, Bass 23, Middle 67, Treble 31.

**Phase 2, Editor-Export BEFORE:** `D:Desktop 3d sachenDesktopCapturesP01_BEFORE_BIG_CAPTURE.prst`
(nicht im Repo), 4257 Byte, SHA-256
`37880c087b9d361189a7832d3417f783b52f40acff5d29fd8ab33bff93dc0adc`.
Das `.prst` ist lesbares XML (`<Matribox>/<presets>/<Effect …>`) mit je
Block `effectModuleName`, `effectName`, `effectState` (0/1), `effectCode`
(dezimal, z. B. Sol 100 OD = 117440583 = 0x07000047), Kettenposition `x`
und `params_0..14`, dazu Preset-Metadaten (`ppName`, `ppVolume`, `ppBPM`,
`ppIRNum`). Die Amp-Werte stimmen mit dem Raw-Backup überein. Die
Blockreihenfolge in der Kette (x=0..8): FX1, FX2, AMP, NR, CAB, EQ, MOD,
DLY, RVB.

### Ergebnis Big Capture (19.09.2026, rein offline)

**Ground-Truth-Dataset** (alle Originale außerhalb des Repos, unverändert):

| Teil | Datei | SHA-256 |
|---|---|---|
| A BEFORE Raw | `fe2a6b82…a893a4.wyrmtone-raw-preset.json` (WyrmTone, read-only) | `fe2a6b826fb42ddca9e95ec5de8d72cb58cee6f72c32b330250ac08d23a893a4` |
| B Editor-Capture | `Captures\matribox1_p01_big_capture_20260919.pcapng` | `a14167a1293f51ab0a666832601eb8edd533c83c99cd2d124f5904660bcaa7fb` |
| C AFTER Raw | `41231fb8…62fd.wyrmtone-raw-preset.json` | `41231fb81b20858a1014bebca6ebb0b2815a2a1e2b5afd26fe657873d94a62fd` |
| D Export BEFORE | `P01_BEFORE_BIG_CAPTURE.prst` | `37880c087b9d361189a7832d3417f783b52f40acff5d29fd8ab33bff93dc0adc` |
| D' Export AFTER | `P01_AFTER_BIG_CAPTURE.prst` | `e88051b12deb7c50d835cacf5e800af8f1c765d6d567092eddbab9b6e7665b29` |

1065 Host→Gerät-Nachrichten (0 Gerät→Host): 1028 slotadressierte
Parameterwrites, 11 Modellwahlen, 18 MIDI-CC (3 B), 4 Preset-Metadaten
(`12 11`, 18/34/34/64 B, dazu Namensnachricht doppelt), 1 Commit (`12 12`).
Alle Aktionen des Plans sind in der Zeitleiste wiederzufinden (Analyzer-
Ausgabe, Bursts durch die vorgegebenen Pausen getrennt); der AFTER-Export
bestätigt jeden gesetzten Wert.

**Nachrichtenfamilien.** Status: CONFIRMED (Capture) = Nachrichteninhalt
stimmt exakt mit bekannter Bedienung **und** AFTER-Zustand überein;
**nicht** durch einen WyrmTone-Sendetest bestätigt (das gilt weiter nur für
Gain/Presence).

| Familie | Form | Bedeutung | Status |
|---|---|---|---|
| Slot | Header-Byte 10 = Kettenposition+1: FX1=1, FX2=2, AMP=3, NR=4, CAB=5, EQ=6, MOD=7, DLY=8, RVB=9 | unterscheidet **FX1/FX2** trotz gleichem Algorithmuscode (beide Skreamer: Code `0x03000000`, Slot 1 vs 2) | CONFIRMED (Capture) |
| Parameterwrite | `12 10 SS 00 02`, 34 B, u32-Code/u16-Index/float32 (Nibble-Paare) | für **alle** neun Blöcke gleich aufgebaut; Slot 3 (AMP) zusätzlich hardware-bestätigt | CONFIRMED (Capture), WyrmTone-Test nur Slot 3 |
| Modellwahl | `12 10 SS 00 01`, 22 B, u32-Code (Nibble-Paare) | wählt Modell je Slot; andere Nachricht als Parameterwrite; kommt vor den Parameterwrites | CONFIRMED (Capture) |
| Boolesche Parameter | Parameterwrite mit float `1.0` (Sync/Trail: Flanger Idx 4, Sweep Idx 5/6/7, Mod RVB Idx 5) | gleiche 34-B-Familie | CONFIRMED (Capture) |
| Block ON/OFF | MIDI-CC `b1 (0x30+Slot−1) vv`, `0x7f` = Block **aus**, `0x00` = Block **an** | 9/9 Blöcke konsistent mit Ausgangszustand und Bedienreihenfolge; keine SysEx | CONFIRMED (Capture) |
| User IR | Modellwahl Slot 5 mit Code `0x0a100006` = User IR 7 | User-IR-Slot n = `0x0a1000(n−1)`; Parameterwrites danach mit diesem Code, VOL = Index 1 | CONFIRMED (Capture) |
| Preset VOL / BPM | `12 11 00 00 03` = VOL, `12 11 00 00 02` = BPM, je u16 LE (Nibble-Paare), live beim Ändern | 37 / 137 | CONFIRMED (Capture) |
| Presetname | `12 11 00 00 00`, 34 B, ASCII ab Offset 22, live bei Namensänderung | `CAP TEST 01` | CONFIRMED (Capture) |
| Save-Burst | Name (`…00`), `…04` (34 B Nullen), `…05` (u16 = ppType 4), `…07` (64 B Nullen), `12 12 00 00 02` (22 B, Nutzdaten 0) | **keine Blockdaten**: Save sendet nur Metadaten + Commit; die Blockedits waren schon live | Inhalt CONFIRMED (Capture); Bedeutung von `04`/`07` (Autor/Notizen) und Commit-Nutzdaten (Slot?) HYPOTHESIS |

**Wire-Index ≠ Katalogindex.** Wire-Index = `params_N` im `.prst` (CAB VOL
= Index 1, im Katalog Index 0). Einige Parameter der Blöcke sind Float,
Schalter Float 0/1.

**Abweichung:** die erste CAB-Modellwahl trägt `0x0a000022` (= `BritGN 4x12`
im lokalen Katalog), der Plan nannte `BritMD 4x12` (`0x0a000021`). Der
Endzustand (User IR 7) ist unberührt; ob der Editor-Listenname von der
Katalogbenennung abweicht oder ein anderer Eintrag gewählt wurde, ist offen.

**Sync-Nebenwirkung.** Nach dem Umschalten von Sync zeigen Time/Rate den
Notenwert (`1/4`); im AFTER-Zustand steht Time 4.0 und Flanger-Rate 4, ohne
dass dafür ein weiterer Parameterwrite gesendet wurde — das Gerät wandelt den
Wert selbst um.

**Raw-Preset-Layout (decodierter 768-Byte-Puffer, BEFORE/AFTER-Diff
vollständig erklärt außer Part 8):**

| Decodierter Offset | Inhalt |
|---|---|
| 2.. | Presetname (ASCII) |
| 14..31 | Kettenreihenfolge u16 0..8 |
| 32 + 4·(Slot−1) | Algorithmuscode u32 je Slot (Modell) |
| 68 + 60·(Slot−1) | 15 float32-Parameter je Slot (`params_0..14`) |
| 608 + 2·(Slot−1) | Blockzustand u16 (1 = an, 0 = aus); im Diff unverändert, passt zum Ausgangszustand |
| 626 / 628 | Preset BPM / Preset VOL (u16) |
| 652 | Kopie des FX1-Codes (Bedeutung offen) |

Jede geänderte Byte-Gruppe des Diffs (Name, Code-Tabelle, Parameter der
Slots 1–9, BPM/VOL, Offset 652) liegt in einem dieser Bereiche. **Part 8
(Byte 37..44, vermutlich Prüfsumme):** ändert sich weiter mit jedem Edit; kein
CRC-32-Variantentest (Polynome, Init, XOR, Spiegelung, mehrere Bereiche) über
vier bekannte Snapshots passt — Berechnung UNKNOWN.

**II-Pro-Abgleich:** alle Matribox-1-Cluster ergeben NO MATCH gegen die drei
II-Pro-Familien (anderer Header, andere Längen, nur passiv/geräteseitig
dokumentiert); II-Pro-Material wurde nicht für diese Zuordnung verwendet.

**Was wir vom kompletten Preset-Write jetzt verstehen:** die Live-Bearbeitung
(Modellwahl, Parameter inkl. Schalter, Block ON/OFF, Preset-VOL/BPM, Name) und
die Struktur des Save-Bursts sind aus Editor-Traffic entschlüsselt; die
Wirksamkeit gesendeter WyrmTone-Nachrichten ist bisher nur für den Amp-
Parameterwrite hardware-belegt. Offen: Prüfsummenberechnung, Bedeutung der
Save-Selektoren `04`/`07` und der Commit-Nutzdaten, Sync-Umrechnung,
Kopie bei Offset 652, Klärung der CAB-Abweichung.

## Full Live Edit Certification (User P01, Debug-Gate)

**Evidenz:** Alle 25 Operationen des Plans `FULL_LIVE_P01_V1` existieren als
exakte Nachrichten im Big Capture (CAPTURE_CONFIRMED). Sie sind **nicht**
ACTIVE_WYRMTONE_HARDWARE_CONFIRMED; hardware-belegt bleiben nur Sol100OD Gain
und Presence. User IR 7 (`0x0a100006`) ist repräsentiert, die allgemeine Formel
bleibt HYPOTHESIS, nicht sendbar. Part 8 bleibt CORRELATED (keine Prüfsumme,
nicht synthetisiert).

**Architektur:** geschlossenes `MatriboxChainSlot` (FX1..RVB, Wire-Slot 1..9),
Modellwahl- und Parameter-Encoder aus Slot + bestätigtem Katalog-Algorithmus;
keine Roh-Index-/Algorithmus-/Byte-API nach außen. CAB VOL: Wire-Index 1
(Katalog-Index 0) als explizite Matribox-1-Wire-Evidenz. Blockschalter: MIDI CC
Kanal 2, `0x30 + Slot − 1`, `0x00` = ON, `0x7F` = OFF.

**Ablauf:** READ → BACKUP → SAVE → RELOAD → HASH → DECODE, eine explizite
Bestätigung „FULL LIVE TEST STARTEN“ (kein Store), feste sequentielle Liste
(9 Modelle, 14 Parameter, 2 Blockschalter), erster Fehler stoppt, kein Retry,
kein Rollback; Readback separat und manuell mit den Klassen
EXPECTED_MODEL/PARAMETER/BLOCK_CHANGE, CORRELATED_PART8_CHANGE,
UNEXPECTED_KNOWN_CHANGE, UNKNOWN_RAW_CHANGE.

**Gate:** `ENABLE_MATRIBOX_FULL_LIVE_CERTIFICATION` (Default false, Release
false, exklusiv zu den übrigen Schreib-/Probe-Gates). Store (`12 12`) und
Metadaten (`12 11`) werden nativ abgelehnt.

**Hinweise:** CAB im Capture ist BritGN 4x12 (`0x0a000022`), nicht der geplante
BritMD (`0x0a000021`) — Abweichung, offen. Der Sync-Schalter wandelt Rate 3.7 am
Gerät in den Notenwert-Index 4.0; der Plan akzeptiert beide Werte für Rate.
Ob nur Endwerte (ohne Zwischenwerte der Slider) vom Gerät akzeptiert werden, ist
ungetestet.

## Tone Transfer: Song → Matribox P01 (End-to-End, offline)

**Pipeline (eine, keine parallele):** Song/Genre-Profil → `OfflineSoundEngine`
(Gitarre/Tuning/Rolle) → `PresetDraft` → `DraftPresetAdapter` →
`CanonicalPreset` → `ToneIntent` (geräteunabhängig, mit Herkunft je
Entscheidung) → `MatriboxToneTranslator` → `MatriboxTargetPreset` → frisch
gelesener P01-Zustand (Read → Backup → Reload → Hash → Decode) → semantischer
Diff → evidenzgeprüfter `MatriboxToneTransferPlan` → Transport → Readback.

**Regeln:** Fehlende Empfehlungen bleiben NOT_SPECIFIED/UNCHANGED (kein
Auffüllen). Editor-Defaults (Amp Master = 50) sind keine Empfehlung. Ein Block
wird nur eingeschaltet, wenn das Modell gesetzt ist oder der Slot nur eine
Effektart enthält (FX1 mischt Kompressor/Wah/Simulator → kein Auto-Enable).
Herkunft: SONG_PROFILE, GENRE_FALLBACK, GUITAR_CORRECTION, DEVICE_TRANSLATION,
USER_OVERRIDE, UNCHANGED.

**Evidenz-Gate:** Jede Operation trägt Protokoll- und Hardware-Evidenz.
CAPTURE_CONFIRMED genügt nie. Hardware-Baseline: nur Sol 100 OD Gain und
Presence. Nach einem **CERTIFIED** Full-Live-Readback (aus dem Record abgeleitet,
nicht hartkodiert) gelten die Generalisierungsregeln G1 (MODEL SELECT pro
zertifiziertem Slot, für capture-bestätigte Algorithmen), G2 (PARAMETER WRITE
pro zertifiziertem Slot × Werttyp) und G3 (Block-CC für alle neun Slots, wenn
ON und OFF auf ≥ 2 Slots zertifiziert wurden). Nichts darüber hinaus; Sol 100 OD
MODEL SELECT bleibt CORRELATED (kein Select-Capture) und damit blockiert.

**Send:** nur wenn JEDE geplante Operation eligible ist und ein produktiver
Transport existiert. In diesem Meilenstein existiert **kein** nativer
Tone-Transfer-Transport (`UnavailableToneTransferChannel`): Plan und Vorschau
funktionieren, Senden bleibt BLOCKED. Kein Store, kein Restore, kein Retry,
Metadaten (Name/BPM/VOL) nur offline. Manual-Save-Nachprüfung
(MANUAL_SAVE_PERSISTENCE_VERIFIED) ist getrennt von QME2 Store (UNKNOWN).

## Sound Engine V2: vollständiger 9-Block-Ton (offline)

**Schichten:** Profil/Genre/Gitarre/Tuning/Rolle → `ToneRecipeBuilder` →
`CanonicalToneRecipe` (geräteunabhängig, alle neun Blöcke, Zustand DEFINED /
OFF / UNCHANGED / INCOMPLETE, Herkunft je Entscheidung) →
`MatriboxToneTranslator` (Modellwahl per Tag-/Score-Regeln gegen die 181
Katalogmodelle, explizite Parameterregeln mit Katalog-Range/-Typ) →
`MatriboxTargetPreset` → Diff/Plan (unverändert, evidenzgeprüft).

**Regeln:** Fallback-Hierarchie USER_OVERRIDE → SONG/ARTIST_PROFILE →
GENRE_PROFILE-Template (nur wo das Profil schweigt) → ROLE/TUNING/GUITAR-
Korrekturen nach der Basis → DEFAULT_SAFE (Block, zu dem nichts gesagt wird,
ist deterministisch AUS). ON ohne Modell ⇒ INCOMPLETE_TARGET; das aktuelle
Gerätemodell wird nie übernommen; OFF braucht kein Modell; UNCHANGED nur
ausdrücklich (Override). Recipe und Translator sehen keinen Gerätezustand.
Tags (`matribox_model_tags.dart`) sind DEVICE_APPROXIMATION aus Modellnamen,
keine Aussage über Originalequipment; ungetaggte Modelle sind (noch) nicht
wählbar. Abstrakte Hallmenge ≠ Mix, Gate-Stärke ≠ THRE: ohne belegte Regel
bleibt der Parameter ungesetzt (LIMITED_APPROXIMATION, sichtbar im Report).

**Evidenz getrennt:** Katalog-Modelle haben Protokoll-Evidenz `observed`
(nur XML); ihre Modellwahl bleibt BLOCKED, auch wenn der Sound musikalisch
passt. Empfehlung und Hardware-Evidenz werden getrennt angezeigt.

## Angels Don't Kill – Product Unlock Certification (`ANGELS_DONT_KILL_P01_V1`)

**Zweck:** ein einziger kontrollierter Hardwaretest, der exakt den Sound-Engine-V2-
Plan gegen ein bekanntes User P01 ausführt (11 Operationen: 2 MODEL SELECT
Boost `0x0000001a` / Sol 4x12 `0x0a000028`, 5 Sol-100-OD-Parameter, 4 Block-CC).
Er läuft über die vorhandene geschlossene Full-Live-Infrastruktur (Session,
Executor, Port, Codec, Verifier); `FULL_LIVE_P01_V1` bleibt unverändert.

**Evidenz:** Boost und Sol 4x12 bleiben bis zum CERTIFIED-Readback nicht
ACTIVE_HARDWARE_CONFIRMED (Katalog `observed`). Bei CERTIFIED gelten exakt die
getesteten Operationen (Modelle, fünf AMP-Parameter, vier Toggles) als
bestätigt; weitere Katalogmodelle werden nicht automatisch freigegeben
(G4 nur dokumentiert, nicht aktiv). Der Ausgangszustand „CKY 96 STUD" ist nur
Certification-Precondition (SOURCE_PRESET_MISMATCH / ALREADY_AT_TARGET);
Gate `ENABLE_MATRIBOX_ANGELS_PRODUCT_CERTIFICATION` (default false, exklusiv).
Kein Store, kein `12 11`, kein Name/BPM/VOL, kein NR/RVB-Write.

## Korrektur: Readback sieht nur den GESPEICHERTEN Stand (Hardware-Befund 2026-09-20)

Der reale Angels-Hardwarelauf hat gezeigt: Live-Writes wirken sofort am Gerät
(Werte, Modelle, Blockzustände, Sternchen), der Full Read liefert aber nur das
**gespeicherte** Preset. Ein Readback direkt nach dem Live Write zeigt daher den
alten Zustand (TARGET_MISMATCH); erst nach dem **manuellen Speichern am Gerät**
verifiziert er. Frühere Abschnitte dieser Datei (Full Live, Angels-Certification,
Tone Transfer), die einen Readback ohne Speichern beschreiben, sind
entsprechend zu lesen. Der korrekte Ablauf ist überall:

LIVE WRITE → PHYSICAL CHECK → MANUAL DEVICE SAVE → FRESH READBACK.

WyrmTone sendet weiterhin **kein Store**; das manuelle Speichern ist kein
QME2-Store, der Erfolg heißt `MANUAL_SAVE_PERSISTENCE_VERIFIED`.

## Produktiver Tone-Transfer-Transport V1

**Evidenz (ACTIVE_WYRMTONE_HARDWARE_CONFIRMED, exakt):** Sol 100 OD Gain/Presence
(älter) sowie der reale, CERTIFIED Angels-Lauf: FX1 OFF, FX2 Select Boost
`0x0000001a` + ON, Sol 100 OD Bass/Middle/Treble, CAB Select Sol 4x12
`0x0a000028` + ON, EQ OFF. Keine Generalisierung auf andere Modelle, Slots,
Parameter oder Toggle-Richtungen. Dart-Ledger (`MatriboxHardwareLedger.product`)
und die native Evidenztabelle (`MatriboxToneTransferCatalog.kt`) spiegeln
denselben Satz (getestet).

**Transport:** Dart → Kotlin nur über den geschlossenen Vertrag
`executeToneTransfer {planId, targetBank: USER, targetSlot: 1, backupHash,
operations[SELECT_MODEL | SET_PARAMETER | ENABLE_BLOCK | DISABLE_BLOCK]}`
(Slotnamen, Katalog-Modell-/Parameternamen, Werte; keine Bytes, keine
Algorithmus-IDs, keine Indizes). Kotlin validiert den GANZEN Plan vor dem
ersten Send erneut gegen die eigene Evidenztabelle (Reihenfolge, Bereiche,
Ziel), sendet deterministisch in Planreihenfolge über den wiederverwendeten
Codec, ein Lauf je Plan und Verbindung, kein Retry, erster Fehler stoppt
(completed / failed / notSent), kein Rollback, kein Store, kein `12 11`. Gate
`ENABLE_MATRIBOX_TONE_TRANSFER` (Debug, Default false, Release false,
exklusiv zu allen Certification-Sendern).

**Workflow-Zustände:** PREPARED (nur im Speicher) → LIVE_WRITE_COMPLETE →
AWAITING_MANUAL_SAVE („Ich habe am Gerät gespeichert“ sendet nichts) →
VERIFYING → VERIFIED | FAILED | STALE. Nach Trennung/Neustart wird der Live-
Zustand nie angenommen (STALE); ein frischer Read entscheidet.

## Product Expansion: generische Evidenz + volle Sound-Parameter (Analyse, offline)

Stand: Dies ist die ursprüngliche Analyse (vor dem Hardwarelauf). Sie wurde durch `FAMILY_EXPANSION_P01_V1` (CERTIFIED, 2026-09-21) bestätigt
und in der Milestone „Product Evidence V2“ (letzter Abschnitt) produktiv übernommen; die dortigen Zahlen und Regeln gelten. Wo unten
„heute“, „nativ unverändert“ oder „CAB-Sonderfall“ steht, beschreibt es den Stand VOR dieser Milestone.
Code: `lib/presets/matribox_evidence_v2.dart` (Entscheidungsmodell), `matribox_family_expansion_plan.dart` (Plandaten),
`test/matribox_evidence_v2_test.dart`.

### Evidenz-Hierarchie V2 (schwach → stark; nur die letzten beiden dürfen senden)

| Stufe | Bedeutung |
|---|---|
| BLOCKED | nie erlaubt oder strukturell abgelehnt (Store 12 12, Metadaten 12 11, Factory, P02+, Restore/Retry, Roh-SysEx, freie ID, falsche Kategorie, unbekannter/außer-Bereich-Parameter) |
| STRUCTURE_CONFIRMED | Nachrichtenaufbau byte-genau gegen den Big Capture (46 Parametergruppen, alle vier Wertarten; 11 Model Selects; 18 CC) |
| CATALOG_CONFIRMED | Vendor-Katalog kennt Algorithmus/Parameter/Bereich, Kategorie = Slot. **Keine Hardware-Evidenz.** |
| CAPTURE_CONFIRMED | der Editor hat genau diese Identität gesendet |
| ACTIVE_SAMPLE_CONFIRMED | genau diese Identität wurde von WyrmTone gesendet und nach manuellem Save verifiziert (Einzelprobe) |
| FAMILY_CONFIRMED | Regel über Gerät + Slot/Kategorie + Katalog + Protokollfamilie + AKTIVE Proben deckt die Operation |
| EXACT_OPERATION_CONFIRMED | genau diese Operation wurde gesendet und verifiziert |

Werte werden nie zertifiziert, nur Identitäten (Slot, Modell, Parameter, Wertart). Der Wert wird gegen den Katalogbereich geprüft.

### Katalog-Vertrauensgrenze

Produktiv nutzbar als Identitäts-/Bereichs-Input einer Familie (nie selbst Hardware-Evidenz): `algorithm.name/category`,
`algorithm.code` (u32-Payload), `parameter.name/index` (Nicht-CAB: Wire = Katalogindex), `minimum/maximum/step/default`,
`xmlControlType` (Switch → Flag 0/1). Braucht Capture-/Hardware-Evidenz: den Wire-Index bei ID-Lücken (siehe Korrektur am Ende: Wire = XML-`ID` − 1),
User-IR-Codes (leere Namen, nicht wählbar), Semantik von ATK/Rel/Tone/Bright (keine Richtung/Einheit im Katalog),
jede musikalische Eignung. Ein Katalogcode ist stärker als eine erfundene ID, aber nicht automatisch Hardware-Evidenz.

### Analyse der Protokollfamilien

**Parameterwrite** `12 10 SS 00 02` (34 B): Slot SS = 1..9 (CONFIRMED), Algorithmus = u32 LE (nibble-paart), Index = u16 LE,
Wert = float32 LE. Der Encoder reproduziert die letzte Capture-Nachricht **jeder** der 46 Gruppen byte-genau (Test), darunter
negativ (Bass EQ −23, −41), dezimal (Flanger Rate 3.7), boolesch (Sync/Trail 1.0), groß (Sweep Time 743) → STRUCTURE_CONFIRMED
für alle vier Wertarten. Wire-Index = XML-`ID` − 1 (== Katalogindex, solange die IDs lückenlos bei 1 beginnen; korrigiert, siehe letzter Abschnitt). **Per-Wert-Zertifizierung
(Gain 67 vs. 68) ist nicht sinnvoll:** die Payload ist für alle Werte gleich aufgebaut, das Risiko liegt in Slot + Code + Index +
Wertart, nicht im Wert. Regel: PARAMETER+WERTART pro Slot (FAMILY), Bereich aus dem Katalog.

**Model Select** `12 10 SS 00 01` (22 B): Regel MODEL_SELECT_SLOT_FAMILY. FAMILY_CONFIRMED in Slot S, wenn (a) Algorithmus im
Original-Katalog, (b) Kategorie = Slot, (c) Code aus dem Vendor-Katalog, (d) Encoder byte-genau, (e) ein AKTIVER Select in S
existiert; für nur-Katalog-Modelle muss diese Probe selbst ein nur-Katalog-Modell gewesen sein. **Heute erfüllt: FX2 (Boost) und
CAB (Sol 4x12).** Es fehlen: je ein aktiver Select in FX1, AMP, NR, EQ, MOD, DLY, RVB. FX1 erbt nicht von FX2 (anderer Slot-Byte).

**Block-CC** (`B1 30..38`, 0x00 = ON, 0x7F = OFF): Capture 9/9 konsistent; aktiv: FX1 OFF, FX2 ON, CAB ON, EQ OFF = vier Controller,
beide Polaritäten. Regel BLOCK_CC_FAMILY (≥3 Controller, ON und OFF belegt) → **FAMILY_CONFIRMED für alle 9 Slots** (Randrisiko:
AMP/NR/MOD/DLY/RVB ohne aktive Probe). Nativ noch nicht übernommen; der Test ergänzt NR/EQ/RVB ON als Bestätigung.

### Sound-Parameter-Lücken

| Bereich | Katalog | Capture | Ergebnis |
|---|---|---|---|
| Boost | Gain idx0 0..99 (Default 20, Knob), Bright idx1 (Switch) | nie parametrisiert; Skreamer/Blues OD haben Gain idx0 | Gain: CORRELATED (strukturell vergleichbar); Bright: nur CATALOG, Semantik UNKNOWN |
| Gate 1 | THRE idx0 | 18→17 | THRE CAPTURE_CONFIRMED |
| Gate 2 | THRE 0..99 (Default 20), ATK (25), Rel (60) | THRE 21→31, ATK 23→41, Rel 61→59 | Bereich klar; Richtung nur Konvention (CORRELATED); ATK/Rel Semantik UNKNOWN. Capture-Werte sind Editor-Sweeps, keine musikalischen Sollwerte |
| Reverb | Room: Mix, Pre Delay 0..100, Decay, Trail (idx3) | Mod RVB Mix 29→23, Pre 48→67, Decay 51→41, Lo +17, Hi −23, Trail 1 | Room Mix/Decay technisch schreibbar (nur nach Katalogfamilie); Amount ≠ Mix, siehe Heuristik |
| CAB | nur VOL (idx0 → Wire 1) + Familiennamen (Sol/BritGN/Brit75/Eng/Dizzy 4x12 …) | BritGN VOL 49→43 | keine Speaker-/Mikro-Daten: V30/SM57 nicht belegbar; Auswahl bleibt Konfig + Familienpräfix |
| EQ | Guitar EQ 5 Bänder ±50 + VOL; Bass EQ | Bass EQ negativ (−23, −41) | vorzeichenbehaftete Familie strukturell belegt; keine künstliche EQ-Kurve |
| MOD/DLY | Flanger Rate 0.1..10 step 0.1; Sweep Time 20..4000 | Rate 0.6→3.7, Sync 1; Time 548→743 (173 Writes), Trail/Sync 1 | Dezimal-/Bool-/Zeit-Familie strukturell belegt; Sync wandelt Rate in Notenwert (Vorsicht im Test) |

### Sound-Heuristiken (HEURISTIC / DEVICE_APPROXIMATION, strikt getrennt von Protokoll-Evidenz)

Umgesetzt im Übersetzer hinter `heuristics: true` (Standard **aus**, damit die Produkt-Pipeline keine Operationen bekommt, die noch keine
Familie freigibt; Angels bleibt bei 11 Operationen):
- Gate-Stärke 0..100 → **nur Gate 2** THRE in der Sicherheitsspanne **20..60** (Katalog-Default bis oberhalb des im Capture gefahrenen Maximums 59); MEDIUM (50) → 40. ATK/Rel bleiben ungesetzt (UNKNOWN).
- Reverb-Amount 0..100 → Mix **0..50** (Amount 4 ergibt Mix 2, nicht 4; 100 % Amount ist kein 100 % Wet). Decay/Pre Delay sind aus dem Amount nicht ableitbar. Ein ausdrücklicher Gerät-`mix` schlägt die Heuristik.
- Jeder solche Wert trägt `HEURISTIC/DEVICE_APPROXIMATION` in Begründung und Report; die Protokoll-Evidenz des Parameters ändert sich dadurch nicht.

### Verallgemeinerungsmatrix (heute → nach erfolgreichem Test)

| Protokollfamilie | Capture-Proben | Aktive Proben | Katalog | Heute | Fehlende Evidenz | Endstatus |
|---|---|---|---|---|---|---|
| Model Select | 11 | FX2 Boost, CAB Sol 4x12 (beide nur-Katalog) | 181 | FAMILY: FX2, CAB; sonst CAPTURE/CATALOG | aktiver Select je FX1/AMP/NR/EQ/MOD/DLY/RVB | FAMILY in allen 9 Slots (Tier B nötig für FX1, AMP) |
| Float32 positiv (Zahl) | 46 Gruppen | AMP (5 Params) | ja | FAMILY: AMP (nur capture-bestätigte Params) | Zahl in NR, FX2, CAB, DLY, RVB | FAMILY pro Slot + slotübergreifend (≥3 Nicht-CAB-Slots) |
| Float32 negativ (signed) | Bass EQ, Mod RVB Lo/Hi | – | ja | CAPTURE | ein negativer Write (EQ) | FAMILY EQ |
| Float32 dezimal | Flanger Rate | – | ja | CAPTURE | ein dezimaler Write (MOD) | FAMILY MOD |
| Float32 boolesch | Sync/Trail | – | ja | CAPTURE | Flag in FX2, DLY, RVB | FAMILY (3 Slots, slotübergreifend) |
| Block ON | 18 CC (9/9) | FX2, CAB | – | FAMILY (Regel) | Bestätigung NR/EQ/RVB | FAMILY, bestätigt |
| Block OFF | siehe oben | FX1, EQ | – | FAMILY (Regel) | – | FAMILY |
| CAB-Parameter | BritGN VOL | – | Sol 4x12 VOL | CAPTURE (BritGN); Sol 4x12 CATALOG | CAB VOL (Wire 1) auf Sol 4x12 | FAMILY CAB |
| Gate/EQ/MOD/DLY/RVB-Parameter | ja | – | ja | CAPTURE | je ein Sample pro Slot und Wertart | FAMILY je Slot |

### Test-Plan (`FAMILY_EXPANSION_P01_V1`, Offline-Daten; Sender siehe letzter Abschnitt)

User P01; frischer Read + Backup + Hash; ganzer Plan vorab validiert; kein Store durch WyrmTone; danach physische Prüfung →
manuelles Speichern → frischer Readback. Alle Werte stammen aus dem Big Capture, keine Extremwerte.

| Operation | Warum | Bestehende Evidenz | Beweist bei Erfolg | Verallgemeinerbar? | Upgrade |
|---|---|---|---|---|---|
| FX2 Boost Select | sauberer Start | EXACT | – | – | – |
| FX2 Boost Gain 23 | Drive | Katalog | Zahl auf nur-Katalog-Param in FX2 | Zahl FX | Boost Gain: ACTIVE, Zahl-FAMILY FX2 |
| FX2 Boost Bright 1 | Flag | Katalog | Flag in FX2 | Flag-Breite (3. Slot) | Flag-FAMILY slotübergreifend |
| NR Select Gate 2 | neue Kategorie | CAPTURE | Select NR | alle NR-Modelle | Select-FAMILY NR |
| NR THRE 31 | Gate-Heuristik | CAPTURE | Zahl in NR | Gate-Parameter | Zahl-FAMILY NR |
| NR ON | neue Richtung/Slot | Capture | CC NR | Block-CC | bestätigt |
| CAB Select Sol 4x12 | Start | EXACT | – | – | – |
| CAB VOL 43 | CAB Wire-1-Sonderfall | nur BritGN | Wire 1 für Katalog-CAB | alle CAB-VOL | Zahl-FAMILY CAB |
| EQ Select Guitar EQ | neue Kategorie | Katalog | nur-Katalog-Select EQ | alle EQ | Select-FAMILY EQ |
| EQ 400Hz −23 | negativer Float32 | Bass EQ Capture | signed auf nur-Katalog-Param | alle EQ-Bänder | signed-FAMILY EQ |
| EQ ON | Richtung | nur OFF | ON auf EQ | Block-CC | bestätigt |
| MOD Select Chorus A | neue Kategorie | Katalog | Select MOD | alle MOD | Select-FAMILY MOD |
| MOD Rate 3.7 | dezimal | Flanger Capture | dezimal, nur-Katalog | Rate-Parameter | dezimal-FAMILY MOD |
| DLY Select Warm | neue Kategorie | Katalog | Select DLY | alle DLY | Select-FAMILY DLY |
| DLY Time 743 | Zeit-Parameter | Sweep Capture | großer Bereich 20..4000 | Zeitparameter | Zahl-FAMILY DLY |
| DLY Trail 1 | boolesch | Capture | Flag in DLY | Flags | Flag-FAMILY |
| RVB Select Room | neue Kategorie | Katalog | Select RVB | alle RVB | Select-FAMILY RVB |
| RVB Mix 23 / Decay 41 | Reverb-Normalisierung | Mod RVB Capture | Zahl auf nur-Katalog-Param | Reverb-Parameter | Zahl-FAMILY RVB |
| RVB Trail 1 | boolesch | Capture | Flag in RVB | Flags | Flag-FAMILY |
| RVB ON | äußerster Controller | Capture | CC 0x38 | Block-CC | bestätigt |
| Tier B: FX1 Select Boost, AMP Select Sol 100 OD | schließen FX1/AMP | Katalog / CORRELATED | Select FX1, AMP | alle FX1-/AMP-Modelle | Select-FAMILY FX1, AMP |

(Reichweite und Blocker: siehe Milestone „Product Evidence V2“ am Ende, neu berechnet.)

## FAMILY_EXPANSION_P01_V1 und Milestone „Product Evidence V2“ (2026-09-21)

### Der Test
Debug-/Certification-Test für User P01 (eigenes Gate `ENABLE_MATRIBOX_FAMILY_EXPANSION_P01_V1`, Default false, Release false, exklusiv zu allen
anderen Sendern), 23 Operationen (FX2 3 + NR 3 + CAB 2 + EQ 3 + MOD 2 + DLY 3 + RVB 5 = 21, plus Tier B FX1 Boost und AMP Sol 100 OD), Kettenreihenfolge,
je Slot SELECT → PARAMETER → Block-CC, Pausen 60/200 ms. Code: `matribox_family_expansion_certification.dart`, `matribox_family_expansion_panel.dart`,
nativ `MatriboxFamilyExpansionPlan.kt` (eigene Tabelle, Ganz-Plan-Preflight vor dem ersten Send, ein Sendepfad). Ablauf: Vorbereiten (Full Read, Backup, Hash) →
Testnamen eintippen → Live-Write → STOP → am Gerät prüfen → MANUELL speichern → „Ich habe am Gerät gespeichert“ (sendet nichts) → frischer Readback.
Der Lauf blockiert bei nicht beobachtbarem Startzustand (Modell schon aktiv, NR/EQ/RVB schon ON).
Build: `flutter build apk --debug --dart-define=ENABLE_MATRIBOX_FAMILY_EXPANSION_P01_V1=true`.

### Erster Lauf (Fehler) und korrigierter Lauf (CERTIFIED)
- Der erste Lauf erzeugte auf der Matribox einen ERROR LOG (`CODE: 0`, `LINE: 243`, `..\..\Drivers\audio\AlgorDstConstData.c`, Version V1.1.0); nach Neustart
  war P01 unverändert, nichts war gespeichert.
- Der damalige Bright-Write nutzte fälschlich Wire-Index 1. Die Hersteller-XML zeigt für Boost `Bright` `ID = 3` (idx 1), also Wire 2.
- Der korrigierte Lauf (Bright auf Wire 2, sonst gleicher Plan, gleiche Reihenfolge, gleiche 60/200-ms-Pausen) wurde vollständig **CERTIFIED**
  (`MANUAL_SAVE_PERSISTENCE_VERIFIED`, 23/23, `UNEXPECTED_KNOWN_CHANGE` 0, `UNKNOWN_RAW_CHANGE` 0, Part8 Byte 37..44 8 Bytes nur CORRELATED, kein bestätigter Checksum;
  WyrmTone sendete keinen Store).
- Die falsche Wire-Adresse ist damit die stärkste Erklärung des ersten Fehlers. Kausalität ist nicht mathematisch bewiesen. Die Pausen 60/200 ms funktionierten für diesen
  getesteten Plan; es gibt keinen Beleg, dass kürzere Pausen sicher sind.

### Wire-Regel: `wireParameterIndex = manufacturerParameterId − 1`
- Quelle: `algorithm.xml` (Hersteller, Matribox 1 / QME-50), Vollanalyse in `docs/MATRIBOX_ALGORITHM_XML_ANALYSIS.md` (`tool/analyze_manufacturer_xml.dart`):
  181 Algorithmen, 631 Parameter, 566 mit `idx == ID − 1`, **65 mit `idx != ID − 1`** in **59 Algorithmus-Einträgen** (2 Boost/Bright, Calif Star OD, Halen 51, Delays Slap und Tape,
  53 CAB-Einträge inkl. 15 User IR). Keine doppelten IDs, keine ID ≤ 0, maximale ID 8.
- Belegt durch alle 46 Capture-Gruppen sowie durch den Hardwarelauf (Boost Bright Wire 2, CAB VOL Wire 1). Der frühere „CAB-Sonderfall“ ist ein Fall dieser Regel.
- Zentral in `lib/presets/matribox_parameter_addressing.dart`; der Katalog trägt `xmlId`. **Kein Fallback auf idx**: fehlende, nicht positive, doppelte oder zu große ID → Parameter BLOCKED.
  FX1/FX2-Definitionen, die der Hersteller unterschiedlich beschreibt (nur Tape Mod: `Output` vs `VOL`), blockieren den Parameter ebenfalls.

### Produktiv promotet (Evidence V2 über die aktiven Samples: Angels + FAMILY_EXPANSION; `MatriboxHardwareLedger.product()`)
- **Model Select** für alle 9 Slots (jeder Herstelleralgorithmus des Slots), Code nativ aus der Herstellertabelle.
- **Parameterwrite** für Zahl, Flag 0/1 und signed (nur EQ belegt), Wert gegen Hersteller-Typ, -Bereich und -Raster; Wire = ID − 1.
- **Block-CC** für alle 9 Slots, beide Richtungen; Controller nativ aus dem Slot.
- Der native Pfad (`MatriboxToneTransferCatalog.kt` + generiert `MatriboxManufacturerCatalog.kt` aus `tool/generate_native_manufacturer_catalog.dart`) bleibt: typed operations, Preflight des ganzen Plans
  vor dem ersten Send, ein Sendepfad, null Sends bei Fehler, kein Retry, kein Rollback, kein Store, manueller Save, frischer Readback.

### Weiter BLOCKED / UNKNOWN / CORRELATED
- **bind/Sync:** alle 25 gebundenen Parameter (Rate, Delay Time, Swp Rate) und alle 24 Sync-Ziele sind produktiv gesperrt (Bedeutung bei aktivem Sync unbekannt), obwohl der Zertifizierungslauf Rate 3.7 und Time 743 schrieb.
- **Combox** (8 Parameter) und Switches mit Menü-IDs ≠ {0,1}: gesperrt (keine Hardware-Probe). **signed** außerhalb EQ (Pitch, Ring Mod, Detune, Mod RVB Lo/Hi End): kein aktiver Sample.
- **User IR** (15 Einträge mit leerem Namen; das handerfasste User IR 7 gehört dazu) bleibt BLOCKED, samt Parametern. Store UNKNOWN/BLOCKED, Metadaten/Name/BPM/VOL nicht ausdrückbar.
- Gate ATK/Rel, Bright-Bedeutung über ON/OFF hinaus, Reverb Amount→Mix/Decay/PreDelay, Sync/Notenwerte, Speaker/Mic: UNKNOWN. Part8: CORRELATED, kein Checksum.

### Reichweite (neu berechnet aus dem Herstellerkatalog: `dart run tool/generate_native_manufacturer_catalog.dart`)
| Klasse | Algorithmen | Parameter |
|---|---|---|
| Gesamt | 181 | 631 |
| **A** technisch adressierbar | 166 (15 User IR gesperrt) | 614 (Rest der 631: 15 in User IR, 1 durch FX1/FX2-Konflikt blockiert, 1 nicht zuordenbar) |
| **B** produktiv FAMILY/EXACT | 166 | 548 (alle Ende-zu-Ende mit wählbarem Modell) |
| **C** semantisch abgebildet (Translator-Regel im passenden Block) | – | 350, davon 320 in B |

B-Sperrgründe (Parameter): BIND_UNRESOLVED 25, SYNC_SEMANTICS_UNKNOWN 24, ENUM_UNCONFIRMED 8, kein aktiver signed-Sample 9 (FX1 3, FX2 3, RVB 2, MOD 1), FX1/FX2-Konflikt 1.
A, B und C sind verschieden: technisch schreibbar ist nicht musikalisch verstanden. Die alten Zahlen (165/181, 601/631) stammten aus der Zeit vor der ID-Regel und gelten nicht mehr.
