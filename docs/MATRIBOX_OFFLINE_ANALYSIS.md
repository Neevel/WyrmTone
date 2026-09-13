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
