# Matribox NAM Transfer Research

Stand: 25.09.2026 · Phase: **Evidence (Reverse Engineering), kein Upload implementiert.**
**V1** (Abschnitte bis „Safety constraints“) ist der Stand vor den Captures; wo V2 etwas geklärt hat,
gilt der Abschnitt „V2“ am Ende und überschreibt die V1-Einträge.
Alle Erkenntnisse stammen aus lesender Offline-Analyse: Repository, installierte
Herstellerdateien, vorhandene Captures (`D:\Develop\wyrmtone-captures\`, außerhalb des
Repos) und eine lokale `.nam`. Es wurde nichts an ein Gerät gesendet, die Sonicake-Software
wurde weder gestartet noch verändert.

Evidenzklassen: **CONFIRMED** (eindeutige statische Herstellerinformation oder
reproduzierbarer Capture-Beleg) · **CORRELATED** · **HYPOTHESIS** · **UNKNOWN**.
Geräteklassen: `CONFIRMED_MATRIBOX_1` · `CONFIRMED_OTHER_DEVICE` · `POSSIBLY_SHARED` · `UNKNOWN`.

## Goal

Lokale `.nam`-Dateien (insbesondere von TONE3000) deterministisch, slotgebunden,
validiert und verifizierbar in die NAM-Slots einer Matribox 1 übertragen. Dazu muss
zuerst das Protokoll der offiziellen Software belegt sein. Stand V1: **NAM TRANSFER PROTOCOL READY: NO.**
Stand V2: Transport **YES**, Konverter **NO** (siehe „Readiness“).

## Existing WyrmTone NAM support

```
TONE3000 (OAuth PKCE, prompt=select_tone, format=nam, architecture=1)
  → Tone-Metadaten (Tone3000Tone / Tone3000Model: architectureVersion, modelUrl)
  → NAM-Download (nur offizielles HTTPS, Bearer, ein Tastendruck je Datei)
  → Validierung (HTTP 200, Content-Type-Allowlist, 100 B–100 MiB, .nam, JSON-Objekt
                 mit bekanntem Schlüssel, SHA-256, Model-ID, Duplikate)
  → Lokale NAM-Bibliothek (NamRepository / LocalNamCapture, privater App-Speicher)
  → NamRecommendationEngine (nur lokale A1-Captures, 2 fest verdrahtete Zielsounds)
  → ??? (nicht vorhanden)
  → Matribox-NAM-Slot
```

Belegt im Code: `lib/nam/nam_download_service.dart` (Validator, SHA-256, Architektur nur aus
`architecture_version` der API), `lib/nam/nam_import_service.dart` (einzelne lokale Datei über
SAF, Architektur `unknown`), `lib/tone3000/tone3000_oauth.dart` (A1-Filter `architecture=1`),
`lib/devices/device_profile.dart` (`supportsNamTransfer: notImplemented`, Matribox: NAM A1),
`lib/screens/nam_library_page.dart` (Hinweis „Geräteübertragung noch nicht verfügbar“).

**Was fehlt** (bewusst nicht Teil dieses Milestones):

- Kein NAM-Slot-Modell, keine Slotauswahl, kein Transferplan, kein Sender.
- `lib/presets/protocol_evidence.dart` führt `nam.slot.select` nur aus der II-Pro-Quelle
  (`matriboxIiPro`, Level `unknown`); für Matribox 1 gibt es keine NAM-Nachricht.
- Der Validator liest nie `architecture`, `version` oder `sample_rate` **aus der Datei**; die
  A1-Einstufung beruht allein auf der API-Angabe. Für lokale Importe bleibt sie `unknown`.
- Keine Verknüpfung `CanonicalToneRecipe → NAM-Empfehlung`; `Clone 1–5` existieren nur als
  Preset-Amp-Modelle (`MatriboxManufacturerCatalog.kt`), nicht als Ziel eines Datei-Uploads.

Es gibt keinen Sonicake-/Matribox-2-/QME-Codepfad außer dem QME-50-Katalog der Matribox 1.

## Manufacturer resources

Installiert: `C:\Program Files\Sonicake\Matribox\` (Matribox.exe **1.1.1**, Authenticode gültig,
Ressourcen vom 27.07.2026). Nur gelesen.

| Datei | NAM-relevanter Inhalt | Klasse |
|---|---|---|
| `Resource\Matribox\File\algorithm.xml` (QME-50) | Genau fünf AMP-Modelle `Clone 1`–`Clone 5`, Codes `251658240`–`251658244` (`0x0F000000`–`0x0F000004`), je Gain/VOL/Bass/Middle/Treble. Kein Wort „NAM“, keine Größe/Format/Slotadresse. | CONFIRMED_MATRIBOX_1 |
| `Resource\Matribox\File\nam_input_wav.wav` | 12.348.104 Byte, PCM 44,1 kHz, 2 Kanal, 16 Bit (70 s), SHA-256 `9bb6c1b136dfbeb7538a6060499d98c89342b76ec568b76836e36ab98b29aa1a`. Referenz-Eingangssignal für die Editor-eigene NAM-Verarbeitung (siehe unten). | CONFIRMED_MATRIBOX_1 (Datei), Verwendung CORRELATED |
| `English.lng` / `SimplifiedChinese.lng` | Nur UI-Texte; die NAM-Texte stehen in der EXE (s. u.). | – |
| `Matribox Software Release Note.rtf` | „Supports loading NAM tone profiling files in A2 format.“ (Eintrag V1.1.1). | CONFIRMED_MATRIBOX_1 (Text) |
| `preset.xml` | `Ampero`/`QME-50`-Vorlage, keine NAM-Daten. | – |

## Official editor findings

Statische String-/Importanalyse von `Matribox.exe` (nur lesend, keine Ausführung, keine
Disassemblierung, keine Patches):

| Befund | Klasse |
|---|---|
| Einzige Geräte-I/O-Schnittstelle der EXE ist **WinMM-MIDI**: `midiOutOpen`, `midiOutLongMsg` (SysEx), `midiOutShortMsg`, `midiIn*`. Keine Importe/Strings für HID, WinUSB, SetupAPI oder libusb. | CONFIRMED (statisch) |
| UI-Texte für NAM: `Load nam`, `Choose a nam file to open it`, `Select nam import Location`, `Wrong nam file!`, `Sending`, `Loading....`, `Load success!`, `Request timeout!`, `Request error!`, `Device not found!`; Slotbeschriftungen `Clone %d` (neben `User IR %d`); Hinweis „If the Clone function is enabled, the CAB module will be disabled.“ | CONFIRMED (Text); Zuordnung Import-Location = Clone-Slot CORRELATED |
| Debug-Strings `checksum:%d`, `Nam Data:` (zweimal), `IR Data:`, `Temporary.wav` liegen im selben Modul wie die Import-Texte. Der Editor berechnet also vermutlich eine Prüfsumme über NAM-/IR-Daten; Algorithmus und Bezug (Datei oder abgeleitete Daten) unbekannt. | CORRELATED |
| Die EXE enthält den NAM-Core (`nam::wavenet`, `lstm`, `convnet`, `linear`, `slimmable_wavenet`, `container` mit `SlimmableContainer`, `a2_fast`), JUCE-/nlohmann-JSON und Eigen. Der Editor parst `.nam` also selbst. | CONFIRMED (statisch) |
| Log-Strings `[NAM] getNamOutput …`, `namFile`, `inputFile`, `outputFile`, `converting input sampleRate`, `input peak`, `output peak`, `audiowrite done`, `namConverterCloData abort: fs=` und die Pfade `nam_input_wav.wav` / `/nam_output_wav.wav`: Der Editor lässt das Modell offenbar lokal über die mitgelieferte Referenz-WAV laufen und übergibt das Ergebnis an eine Funktion `namConverterCloData` („Clone-Daten“). | CORRELATED (aus Namen); Schluss „Payload ist abgeleitet statt roh“ = **HYPOTHESIS** |
| Nebenbefund: Strings `GP-100`, `MP-100 (Ampero)`, Pfad `/../Resource/Ampero II Stomp/` – der Editor stammt aus einer Hotone-/Ampero-Codebasis. Nur `QME50`/`Matribox` als Gerätenamen; kein Matribox 2. | CONFIRMED (Text) |

Nicht ermittelbar ohne Capture oder Disassemblierung: Nachrichtenformat, Chunking, Slotadresse,
ob die `.nam` roh oder abgeleitet übertragen wird. Disassemblierung des Konverters ist bewusst
nicht Teil dieses Schritts.

## NAM file structure

Einzige lokale Testdatei (liegt außerhalb des Repos in einem Codex-Arbeitsverzeichnis;
das Projekt verteilt keine NAM-Dateien): `EVH5150Boosted.nam`. Reproduzierbar:

```powershell
dart run tool/matribox_nam_analysis/matribox_nam_analysis.dart describe-nam "<datei.nam>"
```

| Feld | Wert |
|---|---|
| Größe / SHA-256 | 294.810 Byte / `1060a12aa70ab4103a5e0b2a6efce7d4d0aa6055e6a300e942770890f447c910` |
| Kodierung | UTF-8-JSON, kompakt (kein Zeilenumbruch, kein BOM, kein Newline am Ende); Schlüsselreihenfolge `version, architecture, config, weights, sample_rate, metadata` |
| `version` / `architecture` | `0.7.0` / `SlimmableContainer` |
| `sample_rate` | 48000 |
| Submodelle | 2× `WaveNet` (0.7.0): `max_value` 0,5 → 1.871 Gewichte; `max_value` 1,0 → 12.146 Gewichte; Top-Level-`weights` leer; gesamt 14.017 |
| Metadata | `gear_make`/`gear_model` „EVH 5150 III 6L6“, `gear_type` amp, `tone_type` high-gain, `gain`, `loudness` |

Die Datei enthält **kein** A1/A2-Etikett (das kommt von TONE3000). `SlimmableContainer` passt
zum A2-Hinweis in den Release Notes (HYPOTHESIS). Für WyrmTones A1-Ziel ist sie deshalb nur
zweite Wahl; Capture X/Y sollten echte A1-Dateien sein (siehe Next experiment).

Der Befehl erzeugt zusätzlich deterministische **Suchmuster** (Dateianfang/-mitte/-ende, erste
Gewichte als Text und Float32 LE/BE, Metadatenstrings, 32-Bit-Prüfsummenkandidaten CRC32/Adler32/
Summe). Ein Treffer im Capture belegt unveränderte Übertragung; ein Nichttreffer belegt nichts.

## USB transport

| Aussage | Klasse |
|---|---|
| Die Matribox 1 (USB `84EF:0054`) exponiert laut Konfigurationsdeskriptor (Capture 05) genau vier Interfaces: Audio Control, Audio Streaming IN (`0x82`, isochron) und OUT (`0x02`, isochron) sowie **MIDI Streaming** mit Bulk IN `0x83` (64 B) und Bulk OUT `0x03` (256 B). Kein HID-, Vendor- oder weiteres Bulk-Interface. | CONFIRMED_MATRIBOX_1 |
| Preset-/Parameter-/Sync-Verkehr des Editors läuft als SysEx über `0x03`/`0x83` (Captures 01–07, mit dem neuen Reader reproduziert: 2.304 Host→Gerät + 2.303 Gerät→Host SysEx in Capture 01, identisch zur früheren TShark-Auswertung). | CONFIRMED |
| Der NAM-Upload nutzt denselben USB-MIDI-Weg (WinMM, `midiOutLongMsg`), weil der Editor keine andere Geräte-API importiert und das Gerät keine andere Datenschnittstelle anbietet. Ausgeschlossen ist damit nur Nicht-MIDI-Verkehr, nicht ein anderes SysEx-Layout. | CORRELATED (stark) |
| SysEx vs. andere MIDI-Nachrichten, eigener Transfermodus/Bootloader | UNKNOWN |

Kein vorhandener Capture enthält einen NAM-Upload: die größte Host→Gerät-Nachricht in den
Captures 01–07 hat 34 Byte, eine 295-KB-Datei passt nicht hinein; alle 14 Suchmuster der Testdatei
liefern in allen sieben Captures 0 Treffer (roh und in SysEx-Nibble-Dekodierung).

## Slot addressing

| Frage | Ergebnis | Klasse |
|---|---|---|
| Anzahl NAM-Slots | 5 (`Clone 1`–`Clone 5` in `algorithm.xml`, Modul AMP) | CONFIRMED_MATRIBOX_1 (Katalog); Gleichsetzung „Clone n = NAM-Slot n“ CORRELATED (Editor-Text `Clone %d` + Nutzerbeobachtung: importiertes „JCM 900“ erschien als Clone-1-Code, siehe `MATRIBOX_OFFLINE_ANALYSIS.md`) |
| Getrennte Amp-/NAM-Slots | NAM-Slots sind AMP-Modelle (`Clone n`); ein separater Ablageraum-Index ist nicht belegt | CORRELATED |
| Adresse im Upload (0-/1-basiert, Feld, Offset) | Die Modellcodes `0x0F00000n` sind Modellselektoren für Presets, **nicht** belegte Upload-Adressen | UNKNOWN |
| Slot muss vorab gewählt werden | UNKNOWN | UNKNOWN |

## Transfer framing

`NAM_TRANSFER_FRAMING = UNKNOWN` (Begin/Select/Metadata/Allocate/Chunks/Finalize/Verify: keine
Evidenz für oder gegen eine dieser Phasen). Die UI-Texte `Sending` → `Loading....` →
`Load success!` sprechen für einen mehrschrittigen Ablauf mit Erfolgsmeldung (CORRELATED, nur
Text). Das bekannte QME2-SysEx-Muster (Nibblepaare, Header, Teilnummern) ist für Presets belegt;
eine Übertragung auf NAM ist HYPOTHESIS.

## Chunking

`NAM_CHUNK_SIZE`, Sequenznummer, Offset, Länge, ACK, Retry, Timeout: **UNKNOWN**.
Einziger Hinweis: UI-Meldungen `Request timeout!` / `Request error!` (CORRELATED, Text).
Hinweis für die Auswertung: Preset-Antworten kamen in 210-Byte-SysEx-Teilen; die NAM-Chunkgröße
darf daraus nicht abgeleitet werden.

## Integrity / checksum

`NAM_CHECKSUM = UNKNOWN`. Strings `checksum:%d` legen eine Prüfsumme nahe (CORRELATED). Der
Analyzer sucht CRC32/Adler32/Summe der Quelldatei; das ist nur sinnvoll, wenn die Nutzdaten die
Rohdatei sind. Das `%d` (vorzeichenbehaftete Dezimalausgabe) ist ein Hinweis auf eine
Ganzzahl-Prüfsumme, mehr nicht.

## Metadata

Name/Autor/Tone3000-ID/Architektur/Version im Upload: **UNKNOWN**. Der Editor-Namensdialog
erlaubt für Presets maximal 16 ASCII-Zeichen; ob dies für NAM-Slots gilt, ist nicht belegt.

## Device responses

Bekannt für Presets: Editor-Anfragen `0x11`, Geräteantworten `0x12` (Sync). Für NAM: **UNKNOWN**.
Wichtige Lehre aus früheren Captures (`MATRIBOX_OFFLINE_ANALYSIS.md`, Endpoint-Lücke): mehrere
spätere Captures enthalten **keinen einzigen** `0x83`-Frame, weil sie erst nach dem Verbindungsaufbau
begonnen wurden oder falsch gefiltert waren. Ein NAM-Capture ohne `0x83` kann ACK/Status nicht
belegen und ist unbrauchbar für „Geräteantwort“-Fragen.

## Evidence table

| Schlüssel | Wert | Klasse |
|---|---|---|
| `EDITOR_DEVICE_IO_API` | WinMM MIDI, kein HID/WinUSB | CONFIRMED |
| `USB_DEVICE_INTERFACES` | Audio ×3 + MIDI Streaming (Bulk 0x03/0x83) | CONFIRMED_MATRIBOX_1 |
| `NAM_TRANSFER_TRANSPORT` | USB-MIDI (0x03/0x83) | CORRELATED |
| `NAM_TRANSFER_MESSAGE_TYPE` (SysEx?) | – | UNKNOWN |
| `NAM_SLOT_COUNT` | 5 (`Clone 1–5`) | CONFIRMED (Katalog) / CORRELATED (= NAM-Slots) |
| `NAM_SLOT_ADDRESS` | – | UNKNOWN |
| `NAM_PAYLOAD_FORMAT` | roh vs. vom Editor abgeleitet („CloData“) | UNKNOWN; abgeleitet = HYPOTHESIS |
| `NAM_EDITOR_PARSES_NAM_LOCALLY` | ja (NAM-Core in der EXE) | CONFIRMED |
| `NAM_SLIMMABLE_A2_IN_EDITOR` | Container/A2Fast im Editor, Release Note „A2“ | CONFIRMED (Editor); Hardware-A2 UNKNOWN |
| `NAM_CHUNK_SIZE` | – | UNKNOWN |
| `NAM_CHECKSUM` | existiert vermutlich, Algorithmus offen | CORRELATED / UNKNOWN |
| `NAM_METADATA_IN_UPLOAD` | – | UNKNOWN |
| `NAM_DEVICE_ACK` | – | UNKNOWN |
| `NAM_ACTIVE_AFTER_UPLOAD` / `NAM_STORE_REQUIRED` / `NAM_READBACK` | – | UNKNOWN |
| Gerätebezug der Erkenntnisse | Editor 1.1.1 ist Matribox-1-spezifisch (`QME50`) | CONFIRMED_MATRIBOX_1 |
| Übertragbarkeit auf Matribox 2 / Ampero | gemeinsame Editor-Codebasis, Transfercode unbekannt | POSSIBLY_SHARED (nur Framework), sonst UNKNOWN |

## Unknowns

Transfer-Nachrichtentyp und -Framing · Slotadresse und Basis · Vorab-Slotwahl · Nutzdatenformat
(roh/abgeleitet/komprimiert/quantisiert) · Vorgehen von `namConverterCloData` · Chunkgröße,
Sequenz, Offset · Prüfsumme · Metadaten · ACK/Status/Retry/Timeout · sofortige Aktivierung ·
Store-Pflicht · Readback · Größenlimit und akzeptierte NAM-Versionen der Hardware · ob A2 nativ
läuft oder vom Editor auf ein Gerätemodell umgerechnet wird.

**Größtes Risiko:** Falls die Nutzdaten vom Editor aus der `.nam` **abgeleitet** werden (Modell
über die 70-s-Referenz-WAV rechnen, Ergebnis konvertieren), kann WyrmTone keine `.nam` einfach
„kopieren“. Dann müsste die Konvertierung reproduziert werden – ein Aufwand ganz anderer
Größenordnung, der eine Disassemblierung des Konverters und eine gesonderte Freigabe erfordert.
Capture A/C entscheiden genau das (siehe unten).

## Capture A / B / C

Seit V2 vorhanden (Details und Ergebnisse: Abschnitt „V2“ am Ende).
A = GOJIRA → Clone 1, B = GOJIRA → Clone 5, C = Solid Ryhthm Mid Hi → Clone 1.

Werkzeuge (rein datei-basiert):

```powershell
dart run tool/matribox_nam_analysis/matribox_nam_analysis.dart inspect <capture> --nam <file.nam> --output <report.json>
dart run tool/matribox_nam_analysis/matribox_nam_analysis.dart messages <capture> --output <messages.jsonl>
dart run tool/matribox_nam_analysis/matribox_nam_analysis.dart analyze-transfer A=<a> B=<b> C=<c> --nam-for A=<a.nam> --nam-for B=<b.nam> --nam-for C=<c.nam> --out-dir <dir> --output <report.json>
```

`inspect` liefert je Endpoint/Richtung Nachrichtenzahl, Längenverteilung, Entropie, wiederkehrende
8-Byte-Header, Bursts/Chunk-Sequenzen, Zeitachse und Suchmuster-Treffer (roh, im URB-Strom und in
SysEx-Nibble-Dekodierungen); `compare` gibt je Richtung konstante/variable Byte-Bereiche aus.
Isochrones USB-Audio wird standardmäßig ausgeblendet. Der Analyzer ist rein datei-basiert (der
Test `tool sources cannot reach a device` sichert das); `tool/matribox_capture_inspector.dart`
(TShark, nur MIDI-Endpunkte) bleibt für die Preset-Auswertung unverändert.

## Proposed architecture

Nur Design, kein Code. Der NAM-Pfad erweitert die bestehende Kette statt eine zweite zu bauen:

```
ToneVault / Suche → CanonicalToneRecipe → NamRecommendationEngine → TONE3000
  → NAM-Download → NamValidator (+ Dateifelder architecture/version/sample_rate)
  → Lokale NAM-Bibliothek (LocalNamCapture)
  → Matribox NAM Compatibility Check (Architektur, Größe, Version; Datei- UND API-Angabe)
  → NAM-Slot-Auswahl (Clone 1–5, Schutz-/Backup-Regel analog P01–P10)
  → NamTransferPlan (Slot, SHA-256, Größe, Payload-Form, erwartete Nachrichtenfolge)
  → Whole-Transfer-Preflight (komplette Nachrichtenfolge vorab validiert, Zero-send-Test)
  → Nutzerbestätigung (Slot wird überschrieben)
  → Upload (ein Sendepfad, DEBUG-Gate wie beim Preset-Writer)
  → Geräteverifikation (ACK/Readback, sofern belegt)
```

Erst nach belegtem Protokoll zu entscheiden: `DeviceCapabilities.supportsNamTransfer` bleibt bis dahin
`notImplemented`; ein NAM-Slot-Richtlinienobjekt analog `MatriboxSlotPolicy`; Evidence-Ledger-Eintrag
je NAM-Operation. Langfristiges Nutzerziel („Gojira Silvera“ → Amp/NAM/Slot N03/Preset P11/Cab/Effekte →
„NAM installieren → Preset übertragen“) ist ausdrücklich nicht Teil dieses Milestones.

## Safety constraints

Keine NAM-/IR-Datei, keine Presets, kein Store, keine SysEx-/USB-/MIDI-Schreiboperation, kein ADB,
keine Hardware-Probe; P01–P10 geschützt, P11–P99-Transfer und alle Preset-Komponenten unverändert.
Aktives Senden erfordert ausdrückliche Freigabe und ist nicht Teil dieses Milestones. Rohe Captures
bleiben außerhalb des Repos (enthalten USB-Audio und Deskriptoren).

## Next experiment

Erledigt (V1: Capture A/B/C aufgenommen). Der nächste Schritt steht unter „V2 → Readiness“.

---

# V2 – CloData, Converter und Transportprotokoll

Klassen: **CONFIRMED · CORRELATED · STRONGLY_INFERRED · HYPOTHESIS · UNKNOWN**. Alles offline (drei
Captures, zwei `.nam`, installierte Software, Editor-Logdatei); nichts wurde gesendet. Reproduzierbar mit
`analyze-transfer` (siehe oben); Artefakte liegen außerhalb des Repos (`D:\Develop\wyrmtone-captures\v2\`:
`*_clodata.bin`, `*_acks.csv`, `*_vs_*_blocks.csv`, `transfer_report.json`).

| | Capture | NAM | Slot | Größe / SHA-256 (Capture) |
|---|---|---|---|---|
| A | `nam test.pcapng` | GOJIRA - JOE DUPLANTIER.nam (294.340 B, `7d70a61a…2b85`) | Clone 1 | 18.382.328 B / `550b71e7…5b9a` |
| B | `nam test 2.pcapng` | dieselbe Datei | Clone 5 | 11.159.096 B / `cab23e87…1d68` |
| C | `nam test 3.pcapng` | Solid Ryhthm Mid Hi.nam (294.150 B, `ba495fb8…3f24`) | Clone 1 | 12.224.240 B / `65c17405…924b` |

Integrität: alle drei vollständig und brauchbar (USBPcap, Bulk-Endpoints `0x03` **und** `0x83` vorhanden,
jeweils 590 Host→Gerät-Blöcke und 590 Gerät→Host-ACKs, keine fehlenden oder konfliktierenden Blöcke,
0 Prüfsummenfehler, 0 fehlerhafte Nachrichten).

## Logical transport

Normalisierung: USBPcap-Frames → USB-MIDI-Event-Pakete (4 Byte, CIN) → logischer MIDI-Strom → komplette
SysEx (`extractMessages`). USB-Segmentierung ist damit aus dem Vergleich entfernt.

| Größe | Richtung | Anzahl je Capture | Inhalt |
|---|---|---:|---|
| 47 B | Host→Gerät, EP `0x03` | 590 | Datenblock (Frame) |
| 18 B | Gerät→Host, EP `0x83` | 590 | ACK |

**Frame (47 B):** `F0 21 25 7F 'QME2' 12 12 00 10 13 | SLOT | BLK_HI BLK_LO | 28 Nibble-Bytes | CHK_HI CHK_LO | F7`.
**ACK (18 B):** dieselben 13 Präfix-Bytes, dann `SLOT | BLK_HI BLK_LO | STATUS | F7`. Alle 590 ACKs je
Capture haben `STATUS = 0x01`; es gibt kein NACK und keinen anderen Status (nur der Erfolgspfad ist beobachtet).
Status: **CONFIRMED** (drei Captures, 1.770 Frames und 1.770 ACKs, vom Offline-Codec byte-genau reproduziert).

## Clone slot addressing

- Das Slotfeld ist **Byte 13** in Frame **und** ACK. In A/B unterscheidet sich das Frame ausschließlich an
  Position 13; die ACKs tragen denselben Slotwert. Andere Nachrichten enthalten es nicht.
- Clone 1 = `0x00` (A, C) — **CONFIRMED**. Clone 5 = `0x04` (B) — **CONFIRMED**.
- Clone 2/3/4 = `0x01/0x02/0x03` — **STRONGLY_INFERRED** (lückenloses Muster, fünf `Clone`-Modelle in
  `algorithm.xml`); kein Capture. Vor jedem Einsatz ist ein eigener Capture nötig.
- Ob das Gerät Slotwerte > 4 ablehnt, ist **UNKNOWN**.
- Die Modellcodes `0x0F00000n` (Presets) und die Wire-Slotnummer sind getrennte Dinge; `Clone n` und `Pxx`
  dürfen nie vermischt werden (NAM-Slots sind ein eigener Ressourcentyp).

## CloData reconstruction

Aus den Host-Blöcken (Blocknummer, Payload) ohne Wiederholungen zusammengesetzt:

| | Blöcke | Bytes | SHA-256 | vollständig |
|---|---:|---:|---|---|
| A | 588 (0…587) | 8.232 | `c3a44e9282b679130104c14d2f97e690e6e3172b7efa0a4b1d47615de19c35b1` | ja |
| B | 588 | 8.232 | identisch mit A | ja |
| C | 588 | 8.232 | `a3fffddfc155a3b5a6f9fd2e56e67a7a0aa01210ed497c022ad4e7a95bd79414` | ja |

Reihenfolge streng aufsteigend 0…587; fehlende Blöcke: keine; doppelte: nur Block 587 (3 Sendungen,
byte-identisch, keine konfliktierenden Duplikate). 588 × 14 = 8.232 — **CONFIRMED**.
**A == B bytegenau ⇒ CloData sind slot-unabhängig** (der Slot steckt nur im Transportframe) — **CONFIRMED**
(für Clone 1 und 5 mit derselben NAM). Damit ist die Kette `NAM → CloData → Slot wählen → übertragen` belegt.
Zwei getrennte Editor-Läufe derselben NAM (A 19:52, B 20:54) lieferten identische CloData ⇒ der Konverter ist
deterministisch (**CONFIRMED**).

## CloData layout

Absolute Offsets; „Evidenz“ nennt den Grund, nicht eine Bedeutung. Modell: `clone_data.dart`
(`MatriboxCloneData.parse(x).serialize() == x`, getestet an A/B/C und synthetisch).

| Offset | Länge | Region | Evidenz |
|---|---:|---|---|
| 0x0000 | 16 | NAME | CONFIRMED (= Dateiname) |
| 0x0010 | 16 | UNKNOWN_REGION_1 (Nullen) | CORRELATED (in A/B/C null) |
| 0x0020 | 8 | Magic `VTSI` + u32 `0x1288` | CONFIRMED (Bytes und Editor-Code) |
| 0x0028 | 12 | UNKNOWN_REGION_2 (Nullen; u16-CRC-Feld) | CORRELATED (siehe Checksum) |
| 0x0034 | 4 | u32 `0x1200` = Datenlänge in Byte | CONFIRMED (Bytes und Editor-Code) |
| 0x0038 | 80 | CONSTANT_REGION (u. a. Double 1,0 bei 0x38; fünf Doubles ab 0x60: 0,99630 / −1,99261 / 0,99630 / −1,99260 / 0,99262) | CORRELATED (in A/B/C identisch) |
| 0x0088 | 16 | VARIABLE_REGION_1: vier Float32 | CORRELATED (A: 0,0808 / 0,0936 / 777,74 / 581,73; C: 0,0892 / 0,1143 / 751,87 / 374,74) |
| 0x0098 | 16 | u32 0, 128, 128, 1024 | 0xA0/0xA4 CONFIRMED (Editor liest `+0x80`/`+0x84` als Anzahlen, Maximum 0x400) |
| 0x00A8 | 4.608 | VARIABLE_REGION_2: 1.152 × Float32 (128 + 1.024) | Länge CONFIRMED; Werte unterscheiden sich zwischen NAMs |
| 0x12A8 | 3.456 | TAIL: Nullen, letzte 8 Byte `FF` | CORRELATED (identisch); die `FF` sind Blockfüllung (s. u.) |

Der Puffer, den der Editor überträgt, hat **0x2020 = 8.224 Byte** (Namensfeld 0x20 + 0x2000 Byte Struktur;
**CONFIRMED** durch Editor-Code `0x1401EBA60`). 8.224 = 587 × 14 + 6: Block 587 trägt 6 echte Byte, die
restlichen 8 Byte sind `0xFF`-Füllung, ergibt 588 Blöcke. Die `VTSI`-Struktur (0x1288 = 0x88 Header +
0x1200 Daten) wird im Editor an zwei Stellen mit denselben Konstanten aufgebaut (`0x1400B68A0`, `0x140211EE0`).

Beobachtung (keine Deutung): Die Float32-Region beginnt bei Index 128 mit einer **neuen Anstiegsflanke**
(Betragsmaximum bei Index 5 bzw. 3), Partition 1 hat ab Index 117 Nullen. Das passt eher zu zwei getrennten
Antworten (128 und 1.024 Werte) als zu einer durchgehenden mit 1.152 Werten — **HYPOTHESIS**. Was die Werte
bedeuten, ist **UNKNOWN**; Wörter wie „Impulsantwort“ sind nur Arbeitsbegriffe.

## Name field

`0x0000–0x000F`, 16 Byte ASCII, mit NUL aufgefüllt (bei genau 16 Zeichen steht kein NUL im Feld; Bytes
0x10–0x1F sind null). **Quelle ist der Dateiname ohne `.nam`**, nicht `metadata.name`:
A/B `GOJIRA - JOE DUPLANTIER` (23 Zeichen) → `GOJIRA - JOE DUP`; C `Solid Ryhthm Mid Hi` (19) →
`Solid Ryhthm Mid`; `metadata.name` lautete dagegen `GOJIRA NDSP_JD RTHM1_1000e` bzw.
`Neural DSP - Gojira X`. Maximale Länge **16** (Editor-Code: Schleife bricht nach 16 Zeichen ab; CONFIRMED).
Encoding: ein Byte je Zeichen (Editor-Code schreibt das niederwertige Byte des Codepoints); Verhalten bei
Nicht-ASCII ist UNKNOWN.

## Variable regions

Zwischen A und C (verschiedene NAM, gleicher Slot) unterscheiden sich **3.899 von 8.232 Byte** in 693
Bereichen: NAME (0x00–0x0F), VARIABLE_REGION_1 und VARIABLE_REGION_2, Einhüllende der Unterschiede
0…4.775. A↔B: 0 Unterschiede. Block-Heatmap: `a_vs_c_blocks.csv` (je Block gleiche/andere Byte, Prozent,
Entropie). Die Float-Region hat ≈ 7,4 Bit/Byte Entropie; sie enthält **keine** direkten NAM-Bytefolgen
(siehe „NAM converter“).

## Constant regions

`0x0010–0x0087` (ohne Name), `0x0098–0x00A7` und der TAIL sind in A, B und C identisch. Ob sie bei anderen
NAM-Architekturen (reines WaveNet/LSTM, A1) gleich bleiben, ist **UNKNOWN**: beide Testdateien sind
`SlimmableContainer` 0.7.0 mit identischen Gewichtsanzahlen.

## Nibble encoding

Je Block 14 Nutzbytes → 28 Wire-Bytes, **High-Nibble zuerst**: `0xAB → 0x0A 0x0B`. Alle 8-Bit-Werte werden so
transportiert; es gibt keine Escape- oder Maskierungsregel (Wire-Bytes ≤ 0x0F, `F0`/`F7` kommen im Payload
nicht vor). Nicht zum Payload gehören Präfix (13), Slot, Blocknummer (2), Prüfwert (2) und `F7`. Das
Encoding ist in allen 1.770 Frames identisch. `encodeTransferPayload` / `decodeTransferPayload`
(Offline-Codec) sind roundtrip-getestet. **CONFIRMED.**

## Block numbering

Bytes 14–15 = 14-Bit-Zahl aus **zwei 7-Bit-Bytes, höherwertiges zuerst**, **nicht** nibble-codiert;
Wertebereich 0…16.383. Alle Blöcke 0…587 geprüft (`0x04 0x4B` = 587 im letzten Block). Zählung 0-basiert
und lückenlos. **CONFIRMED.**

## Checksum

Je Block: **Summe der 28 Payload-Wire-Bytes (Nibbles) modulo 256**, gesendet als zwei Nibbles (High zuerst)
vor `F7`. Trifft auf **1.770 von 1.770** Frames zu (A/B/C, zwei Slots, zwei NAMs). Alle anderen getesteten
Kandidaten (Summe der 14 Bytes, XOR, Zweierkomplement, CRC-8 0x07/0x31, Summe mit Slot/Block, Summe 7 Bit)
scheitern an mindestens 300 Frames. Slot und Blocknummer gehen **nicht** ein (A und B haben gleiche
Prüfwerte bei verschiedenem Slot). **CONFIRMED.** Das „modulo 256“ ist am Überlauf belegt: Blocksummen
reichen bis 292 und werden auf 8 Bit abgeschnitten.

Weitere Ebenen: Eine Gesamtprüfsumme (laufende 8-Bit-Summe über alle 16.448 Nibbles, Editor-Log
`checksum:%d`, Code `0x1401EBD20`) existiert nur im Editor; auf dem Draht gibt es keine entsprechende
Nachricht (**CONFIRMED** in A/B/C). Das u16-CRC-Feld der `VTSI`-Struktur (Offset 0x28) berechnet der Editor
(`0x140195560`, tabellengetriebenes CRC-16) laut Code nur für die Größe `0x2288`; für `0x1288` bleibt es 0
(**CORRELATED**: Feld ist in A/B/C null).

## ACK protocol

Stop-and-wait: **jeder** Block wird einzeln quittiert; der Host sendet den nächsten Block erst nach dem ACK
(587 von 587 Übergängen; ACK→nächster Block 0,1–3,0 ms). ACK-Reihenfolge = Blockreihenfolge; der ACK
enthält Slot, Blocknummer und Status `0x01`. Ausnahme: die letzten drei Sendungen von Block 587 (siehe
Finalize) gehen ohne Warten hinaus und werden danach dreifach quittiert. NACK, Wiederholungen für
Nicht-Endblöcke und andere Statuswerte wurden nicht beobachtet (**UNKNOWN**, nicht „gibt es nicht“). Für
einen späteren Sender sicherheitskritisch: belegt ist nur Stop-and-wait.

## Timing

Messwerte (keine Timeout-Empfehlung):

| | Block→ACK (min / Median / max) | ACK→nächster Block (min / Median / max) | Transfer gesamt |
|---|---|---|---:|
| A | 0,08 / 3,50 / 208,0 ms | 0,14 / 0,87 / 2,28 ms | 2.762 ms |
| B | 0,08 / 3,41 / 215,4 ms | 0,13 / 0,85 / 2,19 ms | 2.744 ms |
| C | 7,10 / 9,32 / 247,8 ms | 0,17 / 0,92 / 3,02 ms | 6.590 ms |

Ausreißer sind ausschließlich die Sendungen von Block 587 (208–248 ms, dann 111–151 ms, 11–51 ms; alle
übrigen Blöcke ≤ 20 ms). C ist pro Block langsamer (Median 9,3 statt 3,4 ms; Ursache nicht untersucht,
andere Sitzung).

## Begin sequence

Unmittelbar vor Block 0 steht in B und C keine weitere Host-Nachricht (nur drei USB-Deskriptorabfragen bei
Capture-Start). In A gibt es **21,9 s** vor Block 0 zwei Nachrichten: CC `B1 34 7F` und ein 22-Byte-SysEx
`F0 21 25 7F 'QME2' 12 10 03 00 01 00 00 00 00 00 00 00 0F F7`, ohne ACK. Der Schluss
`00 00 00 00 00 00 00 0F` ist die in `MATRIBOX_OFFLINE_ANALYSIS.md` bekannte Nibble-Kodierung des
Modellcodes **Clone 1 (`0x0F000000`)** ⇒ **CORRELATED**: Auswahl des Amps Clone 1, vermutlich Nutzeraktion im
Editor vor dem Import. Ob der Editor vor dem Import eine Begin-/Select-Nachricht sendet, ist **UNKNOWN**:
das Capture-Fenster von B und C beginnt 21,9 s bzw. 21,1 s vor Block 0, eine Nachricht ganz am Fensteranfang
ließe sich dort nicht ausschließen. Belegt ist: Block 0 folgt ohne Allocate-/Size-/Name-Nachricht; Name und
Größe stecken in den Daten.

## Finalize sequence

Kein separater Finalize-/Commit-/Store-Frame. Nach Block 586 wird **Block 587 dreimal byte-identisch
gesendet** (Abstand 96,6–101,7 ms), erst danach kommen drei ACKs. Das Gerät braucht für den letzten Block
auffällig lange (208–248 ms gegenüber ≤ 20 ms). Zwei Erklärungen passen: (a) Editor-Timeout um 100 ms mit
zwei Wiederholungen, weil das Gerät den Abschluss noch erledigt, (b) feste Dreifach-Sendung. Nicht
unterscheidbar — **HYPOTHESIS**. Der Simulator bildet die beobachtete Dreifach-Sendung nach
(`lastBlockRepeats: 3`); das ist keine Protokollaussage. Block 587 enthält 6 Nullbytes + 8 × `0xFF`
(Blockfüllung). Ob „Load success“ nach dem dritten ACK erscheint, ist UNKNOWN (UI nicht im Capture). Ein
Preset-Store kommt nicht vor (**CONFIRMED**: keine Nachricht nach dem letzten ACK innerhalb der Captures).
Sofortige Aktivierung des Slots und Readback: **UNKNOWN**.

## NAM converter

Belegt durch Editor-Logdatei (`C:\ProgramData\HTCache\logfile.txt`, vom Editor geschrieben) und statischen
Code (nur Lesen, keine Ausführung):

- **CONFIRMED:** Der Editor liest `nam_input_wav.wav`, rechnet es auf die Modellrate um (48 kHz, mono,
  3.360.000 Samples; Zwischendatei `HTCache\48000.wav`, 24 Bit), lässt das NAM-Modell darüber laufen
  (≈ 6–7 s) und schreibt `HTCache\nam_output_wav.wav` (70 s, 48 kHz). Das Log zeigt drei Läufe: 19:52 und
  20:54 (GOJIRA, entsprechen A und B) sowie 21:16 (Solid, entspricht C).
- **CONFIRMED (Code):** Die Funktion um `namConverterCloData` (`0x1400B63E0`) ruft `getNamOutput`
  (`0x1400B4D10`), baut danach die `VTSI`-Struktur (`0x1400B68A0`) und übergibt sie an die Sendefunktion
  (`0x1401EBA60`; Logs `Nam Data:` und `checksum:%d`). Datenlänge `0x1200` und Größe `0x1288` sind
  Konstanten ⇒ die Ausgabe hat **feste Größe** unabhängig vom Modell.
- **CORRELATED:** Die Nutzdaten sind **nicht** die NAM-Gewichte: 0 Treffer von 14.017 Gewichten je Datei
  (Float32 LE/BE, Float64 LE; Einzeltreffer und Dreierläufe; Zufallserwartung ≈ 0,03), CloData hat feste
  8.232 Byte bei ≈ 294-KB-Dateien, die V1-Suchmuster (Dateibytes, Text) fehlen. Die Modellgewichte werden
  also nicht quantisiert weitergereicht.
- **HYPOTHESIS:** Aus dem Paar (Referenz-WAV, Modellausgabe) wird durch eine Anpassung das Gerätformat
  erzeugt. Nur als Kennzahl geprüft (keine Umsetzung): Eine Kreuzspektrum-Schätzung aus `48000.wav` und
  `nam_output_wav.wav` (Lauf C) korreliert im Zeitbereich nicht mit den Float-Werten (|r| < 0,12); im
  Betragsfrequenzgang (Oktavbänder 100 Hz–12 kHz) liegen die Korrelationen je nach Signalabschnitt bei
  0,9–0,97. Das ist schwach (glatte Tiefpasskurven korrelieren fast immer) und **kein Beleg**.
- **UNKNOWN:** die Berechnungsvorschrift (Unterfunktionen der Funktion `0x1400B63E0`, u. a. `0x1400B6C60`,
  `0x1400B6CC0`, `0x1400B67E0`, `0x1400B6080`) und die Bedeutung der Float-Regionen.

Wiederverwendbarkeit: Der NAM-Core ist **statisch in `Matribox.exe` eingebettet**; es gibt keine Exporte
und keine eigene DLL (importiert werden nur System- und MFC-DLLs). Der Konverter ist eine interne Funktion
mit den Eingaben (`.nam`-Pfad, Referenz-WAV) und der Ausgabe `VTSI`-Struktur + Name; eine isolierbare
Bibliotheksschnittstelle existiert nicht. **Er ist nicht wiederverwendbar, ohne ihn nachzubauen.** Kein
Nachbau in V2.

## nam_input_wav

`Resource\Matribox\File\nam_input_wav.wav`: 3.087.000 Frames, 44,1 kHz, 2 Kanäle (L = R identisch), 16 Bit,
exakt 70,000 s, Spitze 0 dBFS, RMS −16,6 dBFS, Gleichanteil ≈ 6 LSB. Aufbau (RMS je Sekunde, gemessen):
0–5 s ansteigender Pegel (−41 → −6 dB); 5–6 s digitale Stille; ≈ 6 s ein Impuls; 7–21 s stationäres Signal
bei −61,8 dB RMS; 21–23 s und 28–30 s digitale Stille; 23–28 s stationäres Signal bei −8 dB RMS (Spitze
−5 dB); 30–50 s langsam ansteigender Pegel (−28,4 → −24,7 dB) mit tieffrequenzbetontem Spektrum; 50–70 s
breitbandiges Programmmaterial (−14 bis −21 dB RMS). Es ist ein mehrteiliges Testsignal; die Art je
Abschnitt (Sweep, Rauschen, Gitarre) ist nicht identifiziert.
Rolle: **CONFIRMED** als Eingangssignal der Editor-NAM-Verarbeitung (Log); Rolle als Grundlage der
CloData-Erzeugung: **HYPOTHESIS** (s. o.).

## A1/A2 findings

- TONE3000 dokumentiert den API-Filter `architecture` mit `1` (A1), `2` (A2) oder `custom`; eine Zuordnung
  zum internen NAM-Feld `architecture` (`WaveNet`/`LSTM`/`SlimmableContainer`) ist dort nicht
  dokumentiert ⇒ Gleichsetzung **UNKNOWN**, nicht annehmen. Die Dateien tragen kein A1/A2-Etikett.
- Beide Testdateien sind intern `SlimmableContainer` 0.7.0 (48 kHz, 2 × WaveNet, 14.017 Gewichte) und wurden
  von Editor 1.1.1 importiert, übertragen und vom Gerät je Block quittiert (Status `01`) — **CONFIRMED** als
  reale Kompatibilität dieses Dateityps mit dem offiziellen Pfad. Die TONE3000-Einstufung der beiden Dateien
  ist nicht aufgezeichnet.
- Der Editor enthält Code für WaveNet, LSTM, ConvNet, Linear, Slimmable/Container und `a2_fast`
  (**CONFIRMED**, statisch); dass reine A1-Dateien akzeptiert werden, ist sehr wahrscheinlich, aber in
  keinem Capture geprüft (**CORRELATED**).
- Wichtig: Das Gerät bekommt **nie die NAM**, sondern die vom Editor erzeugten CloData. „A2 supported“
  betrifft die Editor-Software (Inferenz auf dem PC), nicht die Hardware. WyrmTones A1-Beschränkung war
  bisher konservativ und ist ohne eigenen Konverter für die Übertragung unerheblich.

## Offline simulator

`encodeCloneTransfer(cloData, slot)` erzeugt aus 8.232 Byte CloData die 590 logischen SysEx-Frames
(588 Blöcke + zwei beobachtete Wiederholungen des letzten). Gegen die Captures geprüft: **alle 590 Frames
von A (Slot 0), B (Slot 4) und C (Slot 0) sind byte-identisch** mit den erfassten Frames (Test
`captures A/B/C reconstruct, match the simulator…`; übersprungen, wenn die lokalen Captures fehlen). Die
Frames existieren nur als Bytes im Speicher; es gibt keinen Sendeweg (Codec und Analyse importieren kein
`dart:io`, statisch getestet). Offline-Modelle: `NamTransferFrame`, `NamTransferAck`, `MatriboxCloneSlot`,
`MatriboxCloneData` (unter `tool/matribox_nam_analysis/`, bewusst nicht in `lib/`).

## Evidence table

| Aussage | Klasse |
|---|---|
| Transport = USB-MIDI-SysEx auf EP `0x03`/`0x83`, Stop-and-wait je Block | CONFIRMED |
| Frame-Aufbau (Präfix, Slot, Block, 28 Nibbles, Prüfwert, `F7`), ACK-Aufbau | CONFIRMED |
| Nibble-Encoding High zuerst, keine Escapes | CONFIRMED |
| Blocknummer 2 × 7 Bit, 0-basiert, 588 Blöcke | CONFIRMED |
| Prüfwert = Summe der 28 Payload-Bytes mod 256 | CONFIRMED |
| Clone 1 = `0x00`, Clone 5 = `0x04` | CONFIRMED |
| Clone 2/3/4 = `0x01/0x02/0x03` | STRONGLY_INFERRED |
| CloData slot-unabhängig | CONFIRMED (Clone 1 gegen 5) |
| CloData 8.232 Byte fest, aus der NAM erzeugt, Konverter deterministisch | CONFIRMED |
| Name = Dateiname ohne `.nam`, max. 16 Byte | CONFIRMED |
| `VTSI`-Struktur, Datenlänge `0x1200`, Partitionen 128/1.024 | CONFIRMED |
| Bedeutung der Float-Regionen, Konverter-Algorithmus | UNKNOWN |
| Nutzdaten leiten sich aus (Referenz-WAV, Modellausgabe) ab | HYPOTHESIS |
| Begin-/Select-Nachricht vor Block 0 | UNKNOWN (A zeigt Clone-Auswahl: CORRELATED) |
| Dreifach-Sendung von Block 587 = Timeout-Retry | HYPOTHESIS |
| NACK/Fehlerantworten, Aktivierung, Readback, Zeitpunkt von „Load success“ | UNKNOWN |
| Konverter als Bibliothek wiederverwendbar (DLL/Export) | CONFIRMED: nein |

## Remaining unknowns

Konverter-Vorschrift und Bedeutung der Float-Regionen · Verhalten bei anderen NAM-Architekturen (A1-WaveNet,
LSTM) und anderen Namen/Nicht-ASCII · ob Clone 2–4 wie inferiert adressiert werden · Fehler-/NACK-Pfade und
Timeouts des Geräts · ob eine Vorab-Auswahl (Clone-Amp) nötig ist · Aktivierung/Persistenz nach dem
Transfer, Readback · Ursache der Dreifach-Sendung von Block 587 · Wirkung auf Presets, die den Slot nutzen.

## Readiness

```
NAM TRANSPORT PROTOCOL READY: YES
NAM TO CLODATA CONVERTER READY: NO
```

Transport: Aufbau, Codec, Prüfwert, Blocknummer, Slotfeld und ACK-Ablauf sind aus drei Captures
byte-genau nachgebildet (Simulator == Capture). „READY“ bedeutet: das Protokoll des **beobachteten
Erfolgspfads** ist verstanden, nicht, dass gesendet werden darf (Clone 2–4, Fehlerpfade und Vorab-Auswahl
sind offen). Converter: Die Berechnungsvorschrift fehlt; es gibt keine Approximation und keinen Nachbau.

Empfohlener nächster Schritt: **V3 – NAM → CloData Converter Reverse Engineering.** Beweismaterial liegt
bereits lokal: `HTCache\48000.wav` und `nam_output_wav.wav` für Lauf C samt CloData C sowie die
Unterfunktionen der Funktion `0x1400B63E0`. Eine weitere Capture-Runde ist dafür nicht nötig; für mehr
Trainingspaare genügt je NAM ein Import mit anschließendem Kopieren der beiden WAV-Dateien aus `HTCache`
(sie werden bei jedem Lauf überschrieben).

# V3 – NAM → CloData Converter

Ziel: Referenz-WAV + Modellausgabe → 8.232 Byte CloData, byte-identisch zum Editor. Kein Transport-, USB-,
MIDI- oder Geräteweg; `Matribox.exe` wurde nur statisch gelesen. Zusätzlich lief der **aus der EXE
ausgelesene Berechnungscode in einem Offline-CPU-Emulator** (Unicorn, Analyse-Werkzeug außerhalb des
Repos): das ist ein **Orakel** zum Prüfen, kein Produktcode und kein Bestandteil des Nachbaus. Die EXE selbst
wurde weder gestartet noch verändert.

## Input artifacts

`C:\ProgramData\HTCache` (nur gelesen, kopiert nach `D:\Develop\wyrmtone-captures\v3\`; nicht im Repo):
`48000.wav` (24 Bit, mono, 48 kHz, 3.360.000 Frames = Referenz auf Modellrate umgerechnet),
`nam_output_wav.wav` (16 Bit, stereo L = R, 48 kHz, 3.360.000 Frames) und `logfile.txt`. Beide WAV gehören
zum **letzten** Lauf (Solid Rhythm, Capture C); HTCache wird bei jedem Import überschrieben, für GOJIRA (A/B)
existiert **keine** Ausgabe-WAV mehr. CloData A/B/C: `wyrmtone-captures\v2\`.

## CloData layout

Wie V2, jetzt mit Herkunft (Editor-Code + Orakel, **CONFIRMED**): `0x00–0x0F` Name; `0x20–0x87` Kopf der
VTSI-Struktur aus konstanten Voreinstellungen (fünf Filter-Doubles, u. a. Biquad 0,9963 / −1,9926 / 0,9963 /
−1,9926 / 0,9926); `0x88–0x97` vier Float32 = Ergebnis der Modellanpassung (Region A); `0x98–0xA7`
Partitionsfelder 0 / 128 / 128 / 1.024; `0xA8–0x12A7` 1.152 Float32 = zwei FIR-Antworten (Region B);
Rest Nullen, letzte 8 Byte `FF` (Blockfüllung).

## VTSI structure

Die Engine (Funktion `0x14019FCC0`, aufgerufen aus `0x1400B6080`, diese aus `0x1400B63E0`) erzeugt eine
Struktur der Größe **0x2288** (Datenlänge 0x2200 = 128 + 2.048 Float32 bei 48 kHz). `0x1400B68A0` kürzt sie
auf **0x1288**: Kopf 0x88 Byte + 0x1200 Datenbyte kopieren, Größenfeld `0x1288`, Datenlänge `0x1200`,
Partitionsanzahl `+0x84` auf höchstens 0x400 (1.024) begrenzen, u16-Prüffeld bei `+8` über `0x140195560`
(im Capture 0). Konsequenz: von den 2.048 FIR2-Werten gehen nur die ersten 1.024 in die CloData.

## WAV alignment

Die Engine sucht selbst die Latenz: erster Betrag > 0,01 in `nam_output_wav` im Fenster ab 6,000 s
(Impuls der Referenz) → **28 Samples** in Lauf C (**CONFIRMED**, Orakel und Nachbau in Python stimmen).
Vorab wird die Ausgabe von Mittelwert und linearem Trend befreit (Float32, sequentielle Summen; **CONFIRMED**).

## Test-signal segmentation

Feste Abschnitte der Referenz (**CONFIRMED**, Code + Nachbau; Ausgabe jeweils um die gefundene Latenz
verschoben, beide Signale vorher auf 70 s + 600 Samples mit Nullen aufgefüllt): 0–5 s Pegelrampe → Stufe A
(Modellparameter); 6–21 s (Impuls + leises Signal) → Stufe B (Betragsgang ohne Filter); Stufe C 23–28 s
(Anfangsschätzung); Stufe L dreimal in der Reihenfolge 23 s/5 s/3 Durchläufe, 6 s/15 s/2, 30 s/20 s/5 (iterative
Anpassung von FIR1/FIR2, Zwischenergebnisse werden weitergereicht); Stufe F 50–70 s (Endanpassung FIR2 und
Pegel).

## Region A analysis

Vier Float32 (Solid: 0,08917 / 0,11430 / 751,87 / 374,74). **CONFIRMED** (byte-genau gegen Orakel und
Capture C): Kennlinie `y = P·(1 − e^(−a₊·x))` für x > 0 bzw. `N·(e^(a₋·x) − 1)` für x < 0. `P`/`N` sind die
größte positive/negative Spitze der Modellausgabe in den ersten 5 s (100-ms-Blockmaxima); `a₊`/`a₋` folgen aus
der Verstärkung der Blöcke bis zum ersten, der 50 % der Spitze erreicht, und einer Gittersuche mit Skalierung
0,80…1,20 in 0,05-Schritten (eine Runde je Vorzeichen). Reihenfolge in der Struktur: `P, N, a₊, a₋`
(`+0x68…+0x74`; **CONFIRMED** durch den Nachbau, der genau diese Werte in dieser Reihenfolge liefert).

## Region B analysis

Zwei FIR-Antworten: FIR1 mit 128 Slots (117 Werte, Rest 0), FIR2 mit 1.024 Slots. **CONFIRMED** (Orakel):
Die Engine berechnet FIR1/FIR2 bei 48 kHz (128 / 2.048 Werte), multipliziert FIR2 mit 4 und schickt beide
durch einen Resampler 48 → 44,1 kHz (r8brain-Bauart: Sperrdämpfung 180,15 dB, Übergangsband 2,0 %;
**STRONGLY_INFERRED** Voxengo r8brain-free-src, Bibliotheksname nicht belegt); 128 → 117 und 2.048 → 1.881
Werte, danach Kürzung auf die Slots. Die 44,1-kHz-Antwort steckt also **nicht** direkt in den 48-kHz-Werten.

## Static converter analysis

Aufrufkette: `0x1400B63E0` (`namConverterCloData`) → `0x1400B4D10` (`getNamOutput`) → `0x1400B6080` → Einlesen
über `0x1401A0E50/0x1401A0A50` → Engine `0x14019FCC0` → `0x1400B68A0` (Kürzen, Prüffeld). Engine-Stufen
(Arbeitsnamen): A `0x14019EA20` (Kennlinie), B `0x14019E2D0` (Welch-Betragsschätzung, Hamming, 6.000 → 2.048
gefaltet), C `0x14019D4F0`, L `0x14019C050` (dreimal, iterative Anpassung), F `0x14019A9B0` (Ausgabe-FIR),
danach Skalierung ×4 (FIR2), Resampler `0x14020C2F0`. Bausteine (**CONFIRMED**): 4×-Überabtastung mit
HIIR-Allpass-Polyphasen für die Kennlinie, Biquads in Double, Ooura-fft4g (Double) und AudioFFT (Float),
Gauß-Glättung, `interp1`, Mel-Rasterung, Minimalphasen-FIR-Entwurf. Float32-Mathe (`expf`, `cosf`, `sinf`,
`logf`, `log10f`, `powf`) kommt aus der Windows-UCRT (FMA-Pfad) und ist **nicht korrekt gerundet**; ein Nachbau
muss diese Pfade bitgenau abbilden. Der Resampler nutzt eine große Interpolationstabelle (`0x1417F2E10`, 385.869
Byte), die ein statischer C++-Initialisierer (`0x14003EFC0` → `0x1400B0CD0`) beim Programmstart füllt.

## Reconstructed formulas

Vollständig als **Clean-Room-Nachbau in Dart** (`tool/matribox_nam_analysis/engine/`, ohne `dart:io`, kein Teil
von `lib/`), Stufe für Stufe bitgenau gegen den Editor-Code im Orakel geprüft (Python-Prototypen und Orakel
außerhalb des Repos): Vorverarbeitung, Latenzsuche, Stufen A, B, C, L (×3), F, Kennlinie mit Überabtastung,
Biquads, Ooura-fft4g (Double), 128-Punkt-Float-FFT mit Q15-Sinustabelle und Partitionsfaltung (Blocklänge 64),
Welch-Schätzer, Gauß-Glättung, `interp1`, Mel-Rasterung, Minimalphasen-FIR-Entwurf, r8brain-artiger Resampler
(2×-Blockfaltung + Bruchteil-Interpolator mit 673-Phasen-Tabelle) sowie die Float32-Mathe der UCRT (`expf`,
`cosf`, `sinf`, `logf`, `log10f`, `powf`, FMA-Pfad) und der SVML-Vektorfunktionen (`logf`, `log10f`, `cosf`,
`powf(10, y)`). Zwei Feinheiten, die erst der Vergleich zeigte: `expf` muss außerhalb ±(88…104) auf 0/∞ gehen
(Stufe A fragt −700 ab), und Stufe L multipliziert den Puffer `a10` (Ist-Betrag der Stufe C) **in place** mit
dem Rasterergebnis — das wirkt erst im nächsten Durchlauf und im Ergebnis, wenn ein späterer Durchlauf der beste
ist. Die Ergebnisse hängen von den Double-Funktionen `sin`/`cos`/`exp`/`pow` der Plattform ab (verifiziert unter
Windows/UCRT).

## Golden comparison

| Prüfung | Ergebnis |
|---|---|
| Orakel (Editor-Code im Emulator), Solid Rhythm | Modellparameter 4/4, FIR 1.152/1.152 Float32 bitgleich |
| Dart-Konverter `nam_clodata_converter.dart`, Solid Rhythm (C) | **8.232 / 8.232 Byte identisch** (Engine ≈ 10 s, `48000.wav` + `nam_output_wav.wav` + Name); Zwischenwerte FIR1 128/128, FIR2 2.048/2.048 gleich dem Orakel |
| Dart-Konverter, GOJIRA (A) | **nicht getestet**: keine `nam_output_wav.wav`; der Test `GOJIRA` liest `v3/gojira_nam_output_wav.wav` und läuft, sobald die Datei existiert |
| Bereits vorher belegt | Name/Kopf/Partitionsfelder/Füllung: 3.608 Byte für A und C identisch |

Reproduzierbar mit `dart run tool/matribox_nam_analysis/matribox_nam_analysis.dart nam-to-clodata 48000.wav
nam_output_wav.wav --name FILE.nam --clodata OUT.bin` (nur Dateien, kein Gerätezugriff).

## Remaining unknowns

GOJIRA-Golden (fehlende Ausgabe-WAV); nur **ein** Datenpaar (Solid Rhythm) prüft alle Verzweigungen der
Engine — Wiederholungen in Stufe L (Zurücksetzen bei Verschlechterung ≥ 20 %), Latenz-Rückfall (600) oder
`eP`/`eN` = 0 in Stufe A sind aus dem Code, nicht aus Daten belegt; Verhalten für andere Modellarchitekturen
oder Namen außerhalb ASCII; die NAM-Inferenz selbst (`nam_output_wav.wav` entsteht im Editor und ist nicht
nachgebaut); Plattformabhängigkeit der Double-Funktionen (nur Windows verifiziert).

## Readiness

```
NAM TRANSPORT PROTOCOL READY: YES
NAM TO CLODATA CONVERTER READY: NO
```


Solid Rhythm ist byte-identisch (8.232/8.232), aber die Freigabe verlangt auch GOJIRA. Nächster Schritt:
GOJIRA in der offiziellen App erneut importieren, `C:\ProgramData\HTCache\nam_output_wav.wav` als
`D:\Develop\wyrmtone-captures\v3\gojira_nam_output_wav.wav` sichern (nur kopieren) und den Golden-Test
ausführen.

(Aktualisiert in V3c: Solid Rhythm und GOJIRA sind 8.232/8.232; Status dort.)


# V3c – Multi-NAM Golden Validation

Rein offline (Dateien rein, Bytes raus). Kein ADB, USB-/MIDI-/SysEx-Schreiben, NAM-/IR-Upload, Preset-Schreiben
oder STORE. Kein Produktcode (`lib/`, Nativ, Transport) geändert.

## Ergebnis

| Fall | Ergebnis | SHA-256 CloData (erwartet = erzeugt) |
|---|---|---|
| Solid Rhythm (Mid Hi), Capture C | **8.232 / 8.232**, 0 Abweichungen, 0 Regionen | `a3fffddf…d79414` |
| GOJIRA – JOE DUPLANTIER, Captures A = B | **8.232 / 8.232**, 0 Abweichungen, 0 Regionen | `c3a44e92…19c35b1` |

Beide Fälle liefen mit **unverändertem** Konverter (kein GOJIRA-spezifischer Code, keine Konstanten) und je
zweimal mit identischem Hash (deterministisch). Bytevergleich exakt, keine Toleranz. Reproduzierbar mit
`dart run tool/matribox_nam_analysis/matribox_nam_analysis.dart golden-report` (Korpus, beide Läufe, Hashes).

**Herkunft der GOJIRA-Ausgabe (offen gelegt):** `v3/gojira_nam_output_wav.wav` existierte nicht. Der
Editor hat aber am 25.09.2026 23:59:45 GOJIRA erneut gerechnet (`logfile.txt`: Ausgabe-Peak 0,252853), sodass
`C:\ProgramData\HTCache\nam_output_wav.wav` (SHA-256 `a3fd44e4…b0eb`, Peak 0,25287 gemessen) diese Datei ist. Sie
wurde nur kopiert (Quelle unverändert), nicht erzeugt. Ein falsches Paar könnte 8.232/8.232 nicht erreichen;
der Treffer bestätigt die Zuordnung. Klasse: Zuordnung **CONFIRMED** (Log + Peak + Byte-Identität).

## Corpus design

`tool/matribox_nam_analysis/nam_golden_corpus.dart` (nur Metadaten, kein `dart:io`): pro Fall ID, Name,
gespeicherter Dateiname, SHA-256 von NAM, Referenz-WAV, Ausgabe-WAV und offizieller CloData, Herkunft. Große
Dateien bleiben unter `D:\Develop\wyrmtone-captures` (extern). Der parametrisierte Test prüft zuerst die
SHA-256 aller Eingaben; fehlt eine Datei, wird der Fall **übersprungen und als NOT VALIDATED gemeldet**, nie als
bestanden. Ein Golden ist nur ein Modell mit offizieller Editor-Ausgabe **und** offizieller CloData aus USB-Capture.

## Kandidaten (keine Goldens)

Erwartete CloData werden nie selbst erzeugt. Bibliothek: 317 `.nam` (270× WaveNet 0.5.4, 29× 0.5.0, 11× 0.5.2,
7× SlimmableContainer 0.7.0). **Beide Goldens sind SlimmableContainer 0.7.0, Gain ≈ 0,81, ≈ 294 KB und nutzen
dasselbe Referenzsignal** – die Vielfalt ist gering. NEEDS OFFICIAL OUTPUT:

| Kandidat | Warum nützlich |
|---|---|
| Fender Super Reverb 1977 (Gain 0,02) | clean/leise, WaveNet 0.5.4 |
| Boogie Mark V Lead | WaveNet 0.5.0 ohne Metadaten, 408 KB |
| Marshall JVM410H Boosted High Accuracy | größte Architektur (3 Layer-Arrays), 505 KB |
| Marshall JVM410H Boosted Lite | kleinste Architektur (12/6), 134 KB |
| Bugera 6262 Hit Quitter | High Gain, WaveNet 0.5.2 |
| Solid Rhythm Fat | Slimmable, leiser (Loudness −21,3) |

Pro Kandidat nötig (mit derselben Editor-Version): NAM im Editor importieren und **auf das Gerät übertragen,
während USBPcap mitschneidet** (ergibt die offizielle CloData wie Capture A–C), danach sofort
`C:\ProgramData\HTCache\nam_output_wav.wav` und `logfile.txt` kopieren (HTCache wird bei jedem Import
überschrieben). Ohne Gerätetransfer gibt es keine offizielle CloData; das Hochladen führt der Editor aus, nicht
WyrmTone. Details/Hashes: `nam_golden_corpus.dart`.

## Platform reproducibility

Audit `engine/`: alle Float32-Operationen sind mit Double-Arithmetik plus exakter Rundung (`f32`) und
softwaremäßigem `fma32/fma64` nachgebildet und damit plattformunabhängig, ebenso `sqrt`. Alle UCRT-/SVML-Float-
Funktionen (`expf`, `cosf`, `sinf`, `logf`, `log10f`, `powf`) sind eigene Implementierungen mit Tabellen. Plattformabhängig sind nur die
Double-Aufrufe der C-Bibliothek: `sin`/`cos`/`atan` (Ooura-Twiddles `ooura_fft.dart`, Trig-Tabellen
`dsp_helpers.dart`), `exp` (Gauß-Kern, Bessel in `r8b_resampler.dart`) und `pow` (dB-Boden, Resampler-Fenster).
`test/tool/matribox_nam_engine_test.dart` fixiert dafür Bitvektoren (Windows/UCRT). Status: Windows
**VERIFIED**; Android/andere **NOT VERIFIED** (nicht getestet, keine Identität behauptet). Bei Bedarf könnten
die Aufrufe später durch eigene, korrekt gerundete Implementierungen ersetzt werden.

## NAM inference gap

```
.nam → NAM-Inferenz mit Referenzsignal → nam_output_wav.wav → (Konverter, CONFIRMED) → CloData (8.232 B)
     → bekannter Clone-Transport
```

Der Editor linkt **NeuralAmpModelerCore** (Strings: Slimmable/WaveNet, `get_dsp`) mit Eigen statisch
(**CONFIRMED**, statisch gelesen). WyrmTone fehlt nur der Schritt `.nam → nam_output_wav.wav`. Zu klären:
1. **Bitidentität ist vermutlich nicht erreichbar.** Die Ausgabe wird auf 16 Bit quantisiert; Rundungsdifferenzen
   einer anderen Inferenz kippen einzelne LSB. Sensitivitätstest (GOJIRA): 348 Samples (0,01 %) um ±1 LSB →
   2.327 CloData-Bytes anders, FIR-Fehler **−80 dB** bezogen auf die Energie; 33.434 Samples (1 %) → −71 dB,
   Modellparameter bis auf ≈ 1e‑7 relativ gleich. Funktional nahezu gleich, aber nicht byte-identisch.
   Das Prüfkriterium für eigene Inferenz muss daher ein anderes sein (z. B. FIR-Fehler ≤ −60 dB) und wird als
   **eigene Evidenzklasse** geführt; Byte-Goldens bleiben an die offizielle Ausgabe gebunden.
2. Ob byte-gleiche Ausgabe mit derselben Core-Version (Aktivierungen, Eigen-Reihenfolge, Float32-Ausgabe →
   16 Bit, Dither/Rundung) erreichbar ist, ist **UNKNOWN**; prüfbar erst mit einem Nachbau und dem Golden-Paar.
3. Rechenaufwand: 3,36 M Samples WaveNet (Editor ≈ 7 s auf PC laut Log); auf Android einmalig je Import vertretbar.

Vorschlag (nur Recherche): **NeuralAmpModelerCore (C++) per Android-NDK/CMake und `dart:ffi`** – gleiche Quelle wie
der Editor, unterstützt Slimmable und WaveNet 0.5.x, kleine Nativschicht, kein Java-Laufzeitpaket. Alternative
RTNeural (nur Teilmenge, eigener Import nötig) oder reiner Dart-Nachbau (langsam, hoher Testaufwand). Lizenzen
(vom Upstream-`LICENSE` gelesen, vor Übernahme erneut prüfen): NeuralAmpModelerCore **MIT** (© 2023 Steven
Atkinson), RTNeural **BSD-3-Clause**, Eigen **MPL-2.0** (dateiweise Copyleft; als unveränderte Bibliothek
verlinkbar). Nichts davon wurde ins Projekt kopiert; kein GPL-Code. Hinweis: dieselbe Ausgabe-WAV ist auch die
Grundlage für Kandidaten-Goldens (siehe oben).

## Readiness matrix

| Kriterium | Stand |
|---|---|
| Solid Rhythm | 8.232 / 8.232 |
| GOJIRA | 8.232 / 8.232 |
| Determinismus (je 2 Läufe) | PASS |
| Vielfalt der Modelle | gering: beide Slimmable 0.7.0, Gain ≈ 0,81, ≈ 294 KB |
| Clean / anderes Architektur-Modell | NOT TESTED |
| Dritte unabhängige Referenz | NOT TESTED |
| Windows | VERIFIED |
| Android / andere Plattformen | NOT VERIFIED |
| Plattform-Mathe | Bitvektoren nur Windows |
| Eigene NAM-Inferenz | NOT IMPLEMENTED |

Entscheidung: **PROVISIONALLY VERIFIED** (zwei Goldens, Byte-Identität, deterministisch), **nicht** READY
CANDIDATE, weil die beiden Fälle ähnlich sind (gleiche Architektur/Gain/Referenz) und weder Clean-Modell noch
WaveNet 0.5.x noch eine andere Plattform geprüft wurden. Evidenz: Byte-Identität **CONFIRMED** für die zwei
Fälle; Verallgemeinerung auf andere Modelle **CORRELATED**; Android-Identität **UNKNOWN**.

## Next milestone

V3d: mindestens zwei offizielle Referenzen mit **WaveNet 0.5.x** (Clean und High Gain, z. B. Fender Super Reverb
und Marshall JVM410H) – Editor-Import mit USBPcap-Mitschnitt, HTCache-Ausgabe sichern, `golden-report` laufen
lassen; danach Entscheidung READY CANDIDATE. Erst danach Inferenz-Spike (NeuralAmpModelerCore/FFI).


# V3d – Diverse Golden Validation

Rein offline. Kein ADB, USB-/MIDI-/SysEx-Schreiben, NAM-/IR-Upload, Preset-Schreiben oder STORE; kein
Nativ-/Transportcode geändert.

## Ergebnis (Kurz)

**Stand des ersten V3d-Laufs (überholt, siehe „V3d Fortsetzung – JVM410H Standard" unten; die Annahme „High
Accuracy" war falsch):** Fender Super Reverb und JVM410H High Accuracy konnten nicht validiert werden, die
offiziellen Beweisdateien lagen lokal nicht vor. Es wurde kein Golden erzeugt oder abgeleitet. Basislinie
unverändert: Solid Rhythm 8.232/8.232, GOJIRA 8.232/8.232 (je 2 Läufe, identische Hashes).

## Evidence provenance

Durchsucht (Änderungsdatum, Namen): `D:\Develop`, `D:\Desktop 3d sachen`, Downloads/Desktop/Dokumente,
`C:\ProgramData\HTCache`. Befund:

- `C:\ProgramData\HTCache` (Stand 25.09. 23:59:52) enthält weiter nur den GOJIRA-Lauf; `logfile.txt` listet vier
  Läufe (GOJIRA, GOJIRA, Solid Rhythm, GOJIRA), **kein** Fender-/JVM-Eintrag.
- Neueste Captures: `nam test.pcapng`, `nam test 2.pcapng`, `nam test 3.pcapng` (25.09. 19:53–21:16) = die
  bekannten Captures A/B/C. Keine neuere `.pcap`/`.pcapng`, keine Fender-/JVM-Datei in `wyrmtone-captures`.
- Damit fehlen je Referenz: (1) USBPcap-Capture der Editor-Übertragung, (2) `nam_output_wav.wav` des Imports,
  (3) `logfile.txt` (zur Zuordnung), (4) Angabe, welche NAM importiert wurde.

**Mehrdeutigkeit Fender:** lokal existieren **drei** Super-Reverb-Dateien (`…AKG 414.nam`, `…sm57 and AKG 414.nam`,
`…sm57.nam`; Gain 0,021/0,023/0,028, alle WaveNet 0.5.4, ≈ 283 KB). Der Dateiname wird nicht geraten; es muss
gesagt werden, welche importiert wird. JVM410H High Accuracy ist eindeutig
(`Marshall JVM410H Boosted - Full Rig (Custom_High Accuracy).nam`, SHA-256 `ef0860d9…5a83`, 505.159 B; die
übrigen JVM-Dateien heißen anders).

Zuordnungsprüfung, die beim Eintreffen angewandt wird (nie nur über Dateinamen): letzter `namFile` im Log =
importierte NAM; Log-`output peak` ≈ Peak der WAV (GOJIRA: 0,252853 ↔ 0,25287 gemessen); Zeitstempel Log ↔
Capture; Name-Feld der rekonstruierten CloData = Dateiname (V2-Regel); `48000.wav`-Hash = Korpus; am Ende
Byte-Identität. Erwarteter Ablageort (`nam_golden_corpus.dart`): `wyrmtone-captures\v4\<id>\nam_output_wav.wav`,
`logfile.txt`, `transfer.pcapng`; CloData via `analyze-transfer NEU=transfer.pcapng --nam-for NEU=<nam>
--out-dir …`, danach `golden-report`.

## Structural diversity audit

NAM-Struktur (aus den lokalen Dateien, **CONFIRMED**):

| | Solid Rhythm | GOJIRA | Fender (alle 3) | JVM High Accuracy |
|---|---|---|---|---|
| Format | SlimmableContainer 0.7.0 | SlimmableContainer 0.7.0 | WaveNet 0.5.4 | WaveNet 0.5.4 |
| Submodelle | 2 (3 ch / 8 ch, 1.871 / 12.146 Gewichte) | identisch | – (13.802 Gewichte) | – (24.410 Gewichte) |
| Layer-Arrays | 23 Dilations, LeakyReLU 0,01 | identisch | 2 × 10 Dilations (1…512), Tanh, 16/8 ch | 3 × 10 (bis 701), Tanh, 16/8/8 ch, Kernel 3/6/12 |
| Größe | 294.150 B | 294.340 B | 283.481 B | 505.159 B |
| Gain / Loudness | 0,805 / −15,6 | 0,815 / −17,3 | 0,021 / −22,1 | 0,848 / −19,8 |

**Solid Rhythm und GOJIRA sind praktisch dieselbe Modellfamilie** (gleiches Netz; die Metadaten der Solid-Datei
nennen „Neural DSP – Gojira X“). Fender/JVM sind dagegen strukturell und im Pegelbereich klar anders.

Signalseitig (der Konverter bekommt nur die WAVs; die NAM-Datei geht nur über den Dateinamen ein, **CONFIRMED**
durch den Code) bei den vorhandenen Goldens:

| | Solid | GOJIRA |
|---|---|---|
| Latenz | 28 | 0 |
| Stufe A: eP / eN (erster Block ≥ 50 % Spitze) | 1 / 1 | 1 / 1 |
| Stufe A: Skalierung a₊ / a₋ (Raster 0,8…1,2) | 1,2 (Rand) / 0,85 | 1,2 (Rand) / 1,15 |
| Parameter P, N, a₊, a₋ | 0,0892 / 0,1143 / 751,9 / 374,7 | 0,0808 / 0,0936 / 777,7 / 581,7 |
| Stufe L: verbessert / behalten / **RESET** | 4 / 5 / **1** (dritter Aufruf, Durchlauf 2) | 3 / 7 / 0 |
| FIR-Spitze (44,1 kHz) | 0,470 | 0,678 |

## Branch coverage

Durch echte Goldens **bestätigt** (Engine-Log, `runEngine(log:)`): Latenz ≠ 600 (28 und 0), Stufe-L-
Verbesserung, „behalten" und **RESET bei > 20 % Verschlechterung** (Solid, dritter L-Aufruf, Durchlauf 2:
0,01479 > 1,2 · 0,01204). Das korrigiert V3c, wo RESET nur als aus dem Code belegt stand.

**Nicht durch ein Golden belegt:** eP/eN > 1 (clean/leise), Latenzrückfall 600, „nie verbessert", Stufe-A-Raster
im Inneren (beide Fälle am Rand). Diese Zweige laufen ohne Fehler: Rauchtest (**kein Golden**) mit synthetisch
erzeugter Ausgabe (tanh-Sättigung + Tiefpass, Latenz 173/5): erkannte Latenz 171/1, eP = eN = 41/23, RESET in
mehreren Stufen, 0 nicht-endliche Floats. Das belegt Robustheit, **nicht** Byte-Identität.

Für den Konverter zählt das **Ausgabesignal**, nicht die NAM-Struktur. Fender (clean, Gain 0,02) und JVM (High
Gain, andere Aktivierung) liefern voraussichtlich die bisher unbelegten Zweige (eP/eN > 1, andere Latenz) und sind
deshalb wertvolle Evidenz – **CORRELATED**, nicht bewiesen.

## Generic fixes

Keine. Der Konverter ist unverändert; hinzugekommen ist nur ein optionales `log` in `stageA`/`stageL`
(Diagnose, Ergebnis identisch, alle Goldens grün).

## Readiness matrix

| | Solid | GOJIRA | Fender | JVM |
|---|---|---|---|---|
| 8.232-Byte-Golden | PASS | PASS | NOT TESTED (Beweise fehlen) | NOT TESTED (Beweise fehlen) |
| Deterministisch | PASS | PASS | – | – |
| Anderes Gain-Regime | – | – | ? | ? |
| Andere NAM-Struktur | – | – | ? | ? |
| Bisher ungesehener Zweig | RESET bestätigt | – | ? | ? |

Status: **PROVISIONALLY VERIFIED** (unverändert). READY CANDIDATE wird nicht vergeben: es gibt keine
clean/high-gain-Diversität, und die zwei Goldens sind praktisch dieselbe Modellfamilie. Windows bleibt die einzige
verifizierte Plattform.

## NAM inference preparation

Beide Formate werden vom Editor akzeptiert (Slimmable 0.7.0 mit LeakyReLU-WaveNet, Standard-WaveNet 0.5.x mit
Tanh, verschiedene Kernelgrößen/Dilationen/Layer-Arrays). Eine eigene Inferenz muss also `SlimmableContainer`
(Submodell-Auswahl nach `max_value`), WaveNet mit mehreren Layer-Arrays (Head-Skalierung), Tanh und LeakyReLU,
`metadata.gain/loudness` und Sample-Rate-Behandlung beherrschen (Editor-Log: „model sampleRate: 48000",
„converting input sampleRate to 48000").

Bewertung **NeuralAmpModelerCore** (Upstream gelesen): MIT-Lizenz (© 2023 Steven Atkinson), CMake-Projekt mit
Eigen, unterstützt WaveNet, LSTM, ConvNet und SlimmableContainer (seit Release v0.5.0, aktuell v0.5.4 vom
24.06.2026; „0.7.0" bezeichnet die `.nam`-Dateiversion, nicht die Core-Version). Der Editor linkt denselben Core
statisch (Strings, **CONFIRMED**); Empfehlung bleibt: **derselbe Core**, damit Format und Rundungsverhalten dem
Editor am nächsten sind. Welche Core-Version der Editor enthält, ist **UNKNOWN**; Byte-Identität der 16-Bit-
Ausgabe bleibt offen (Sensitivität siehe V3c). Lizenz vor Übernahme erneut gegen den gepinnten Stand prüfen
(Eigen: MPL-2.0).

Bedarf für die Integration (nur Plan, nichts vendort): fest gepinnter Core-Stand samt Lizenzdatei → kleine
C-Schnittstelle (`nam_load`, `nam_process`, `nam_free`) → CMake im Android-NDK (`externalNativeBuild`, arm64-v8a/
x86_64) → `dart:ffi` in einem Isolate (Rechenzeit des Editors ≈ 7 s für 70 s Signal als Größenordnung) →
Float32-Puffer, Quantisierung auf 16 Bit → vorhandener Konverter → Clone-Transport. Die **Windows-Entwicklung**
sollte denselben Core per CMake als DLL nutzen (eine Implementierung, kein zweiter Inferenzpfad); Vergleich gegen
die Golden-Ausgabe-WAVs.

## Remaining limitations

Keine Fender-/JVM-Evidenz; nur Windows-Plattformmathe verifiziert; Byte-Identität mit eigener Inferenz
unbewiesen; Konverterzweige eP/eN > 1, Latenzrückfall, „nie verbessert" ohne Golden.

## Next milestone

Evidenz einsammeln (siehe oben) – zuerst **JVM410H High Accuracy** (eindeutiger Dateiname) und die genannte
Fender-Variante; danach `golden-report`. Erst dann Entscheidung READY CANDIDATE und ein eigener Commit der
V1–V3d-Arbeit; anschließend NAM-Inferenz-Spike.


## V3d Fortsetzung – JVM410H Standard

**Korrektur:** Die oben genannte Annahme „JVM = Custom_High Accuracy" war falsch. Importiert wurde
`Marshall JVM410H Boosted - Full Rig (Standard).nam`. High Accuracy bleibt nur als **mögliche künftige
Referenz** im Korpus (nicht importiert, keine Evidenz).

### Identität der importierten NAM (zwei gleichnamige Dateien!)

Lokal gibt es zwei Dateien mit demselben Namen, aber verschiedenen Modellen:

| Pfad | Format | Größe | SHA-256 |
|---|---|---|---|
| `Desktop\Marshall JVM410H - 100 Watt Head Boosted\…(Standard).nam` | **SlimmableContainer 0.7.0** (2 LeakyReLU-WaveNets, 3/8 ch), Metadaten-Name „Marshall JVM Boosted (Standard)", OD1-Kanal | 294.105 B | `8e2c4688…f0ef859` |
| `Desktop\AMP Presets\Marshall JVM410H … (Full Rig_Head)\…(Standard).nam` | WaveNet 0.5.4, Tanh, 2 Layer-Arrays 16/8 | 283.360 B | `ed1cca50…7c061ec3b` |

Das Editor-Log nennt den ersten Pfad (`namFile: …\Desktop\Marshall JVM410H - 100 Watt Head Boosted\…(Standard).nam`).
**Importiert wurde also die Slimmable-Datei (294.105 B), nicht die WaveNet-Datei.** Bestätigende Korrelation:
`analyze-transfer` liefert mit dieser Datei 14.017 Gewichte (1.871 + 12.146 der zwei Submodelle). Die Datei stammt
vom 26.09. 21:26, also vor dem Import (23:31). Beide Dateien haben denselben Stem, das Name-Feld der CloData
(„Marshall JVM410H") unterscheidet sie nicht; ausschlaggebend ist der Logpfad (**CONFIRMED**).

### Provenienz der drei neuen Dateien (`v4\jvm410h_standard\`)

- `logfile.txt`: Lauf 26.09. 23:31:55 → 23:32:02, `output peak: 0.224781`, Ausgabe `C:\ProgramData/HTCache/nam_output_wav.wav`.
- `nam_output_wav.wav`: Änderungszeit 23:32:02 (= Logende), 16 Bit, 2 Kanäle L = R, 48 kHz, 3.360.000 Frames,
  gemessener Peak 0,22476 (Log 0,224781) – eindeutig dem Log zugeordnet; SHA-256 `6ccde156…a92c8`.
- `transfer.pcapng` (SHA-256 `b986c736…cd945`): Dateiende 23:32:32; Länge 50,6 s, also Beginn ≈ 23:31:41
  (**vor** dem NAM-Lauf); der Blocktransfer dauert 4,53 s und endet 0,06 s vor Capture-Ende (≈ 23:32:27,6 –
  23:32:32,1), **nach** dem Ende der NAM-Rechnung (23:32:02). Zeitlich konsistent (**CONFIRMED**). Die Zeitstempel im
  Capture sind relativ; die Verankerung erfolgt über die Dateiänderungszeit.
- `48000.wav`: unverändert (SHA-256 `a8da7250…3cf33`, in HTCache und `v3` identisch).

Keine Mehrdeutigkeit: Log, WAV (Peak, Zeit) und Capture (Zeit, Namensfeld = `Marshall JVM410H`, 590 Blöcke)
passen zusammen.

### Transport-Vergleich mit A/B/C

| | A (GOJIRA) | B (GOJIRA) | C (Solid) | JVM Standard |
|---|---|---|---|---|
| Blocknachrichten / ACKs | 590 / 590 | 590 / 590 | 590 / 590 | 590 / 590 |
| Distinkte Blöcke, Wiederholung | 588, Block 587 ×2 | 588, 587 ×2 | 588, 587 ×2 | 588, 587 ×2 |
| ACK-Status | alle 1 | alle 1 | alle 1 | alle 1 |
| ACK-Folge = Blockfolge | ja | ja | ja | ja |
| Prüfsummenfehler, fehlend, Konflikt | 0 | 0 | 0 | 0 |
| Slot-Byte | 0 | 4 | 0 | 4 |
| CloData | 8.232 B | 8.232 B | 8.232 B | 8.232 B |

Kein unerwarteter Protokollunterschied. Offizielle CloData aus dem Capture (V2-Parser, nicht aus dem Konverter):
SHA-256 `3613a1aa…eb64e8`, Name-Feld `Marshall JVM410H`.

### Konverter-Ergebnis

Unveränderter `MatriboxNamCloDataConverter`, Eingaben `48000.wav` + JVM-`nam_output_wav.wav` + Dateiname der
Standard-Datei: erwartet 8.232 B, erzeugt 8.232 B, **8.232 / 8.232 identisch**, 0 abweichende Bytes, keine
Regionen, SHA-256 erwartet = erzeugt = `3613a1aa…eb64e8`. Zwei Läufe: gleicher Hash. Regression: Solid
8.232/8.232, GOJIRA 8.232/8.232.

### Diversität der drei Goldens

| | Solid | GOJIRA | JVM Standard |
|---|---|---|---|
| NAM | Slimmable 0.7.0, 294.150 B | Slimmable 0.7.0, 294.340 B | Slimmable 0.7.0, 294.105 B |
| Struktur | 2 × WaveNet 3/8 ch (1.871/12.146), 23 Dilations, LeakyReLU | identisch | identisch |
| Gain / Loudness | 0,805 / −15,6 | 0,815 / −17,3 | 0,839 / −19,7 |
| Ausgabe-Peak (Log) | 0,3075 | 0,2529 | 0,2248 |
| Impuls-Fenstermaximum | 0,099 | 0,088 | 0,141 |
| Latenz (Engine) | 28 | 0 | **67** |
| Stufe A: eP/eN | 1/1 | 1/1 | 1/1 |
| Stufe A: Skalierung a₊ / a₋ | 1,2 (Rand) / 0,85 | 1,2 (Rand) / 1,15 | 1,2 (Rand) / **1,05 (Inneres)** |
| Parameter P, N, a₊, a₋ | 0,0892 / 0,1143 / 751,9 / 374,7 | 0,0808 / 0,0936 / 777,7 / 581,7 | 0,0560 / 0,0579 / 612,9 / 487,6 |
| Stufe L: verbessert / behalten / RESET | 4 / 5 / 1 | 3 / 7 / 0 | **8** / 2 / 0 |
| L-Fehlerniveau (Größenordnung) | 0,010–0,018 | 0,009–0,023 | **0,06–0,12** |
| FIR-Spitze (44,1 kHz) | 0,470 | 0,678 | **0,966** |
| CloData-SHA-256 | `a3fffddf…` | `c3a44e92…` | `3613a1aa…` |

**Liefert JVM Standard bedeutsam andere Evidenz?**

- **CONFIRMED (Daten):** neue Latenz (67), neue Stufe-A-Skalierung im Inneren des Rasters, deutlich anderes
  Parameter- und Fehlerregime (Stufe-L-Fehler ≈ 5× höher, häufige Verbesserungen bis zum letzten Durchlauf),
  größte FIR-Amplitude, anderes Ausgabespektrum. Byte-Identität gilt unverändert.
- **CONFIRMED (Struktur):** **nicht** bedeutsam anders bei der NAM: wieder dieselbe Slimmable-Struktur (gleiche
  Submodelle, gleiche Aktivierung). Damit gibt es weiterhin **keine** Evidenz für ein Standard-WaveNet mit Tanh.
  Für den Konverter ist das kein Nachteil (er sieht nur die WAVs), für die spätere NAM-Inferenz schon.
- **CORRELATED:** Die Konverter-Zweige hängen am Ausgabesignal, nicht an der NAM-Struktur; JVM erweitert den
  Signalbereich (Latenz, Skalierung, Fehlerniveau), ohne neue Zweige einer anderen Art zu aktivieren.
- **UNKNOWN:** eP/eN > 1, Latenzrückfall 600, „nie verbessert", Verhalten bei echt clean/leisen Signalen und
  bei Tanh-WaveNet-Ausgaben.

### Neu geübte Zweige

Durch JVM zusätzlich bestätigt: Latenz 67; Stufe-A-Skalierung im Rasterinneren (1,05); Stufe L mit vielen
aufeinanderfolgenden Verbesserungen (bis Durchlauf 4 im dritten Aufruf); größerer FIR-Pegelbereich. Weiter
ungeübt: eP/eN > 1, Latenzrückfall 600, „nie verbessert".

### Readiness

| | Solid | GOJIRA | JVM Standard | Fender |
|---|---|---|---|---|
| 8.232-Byte-Golden | PASS | PASS | PASS | NOT TESTED |
| Deterministisch (2 Läufe) | PASS | PASS | PASS | – |
| Anderes Gain-Regime | – | – | leicht (0,84; anderes Fehlerniveau) | ? |
| Andere NAM-Struktur | – | – | **nein** (Slimmable 0.7.0) | ? (WaveNet 0.5.4) |
| Neuer Zweig | RESET | – | Latenz 67, Skalierung innen | ? |

Entscheidung: **PROVISIONALLY VERIFIED** bleibt. Drei Byte-Goldens ohne modellspezifischen Code sind deutlich
stärker, aber alle drei gehören derselben Modellfamilie an (Metal-Full-Rigs, Gain 0,8–0,84, Slimmable 0.7.0);
clean/low-gain und Tanh-WaveNet fehlen. Nur Windows verifiziert; Android/Plattformmathe unbewiesen.

### Nächste Referenz: Fender Super Reverb

Lokal drei Dateien (`AMP Presets\Fender Super Reverb 1977\`, alle WaveNet 0.5.4, Tanh, 13.802 Gewichte):

| Datei | Größe | Gain | Loudness | SHA-256 |
|---|---|---|---|---|
| `Fender Super Reverb_ EQ Flat, Volume 3, AKG 414.nam` | 283.481 | **0,0208** | −22,06 | `88a26b54…7364` |
| `Fender Super Reverb_ EQ Flat, Volume 3, sm57 and AKG 414.nam` | 283.524 | 0,0226 | −19,77 | `c5206d0f…1382` |
| `Fender Super Reverb_ EQ Flat, Volume 3, sm57.nam` | 283.622 | 0,0276 | −22,88 | `4c782d9f…db40` |

Empfehlung (technisch, nicht klanglich): **`Fender Super Reverb_ EQ Flat, Volume 3, AKG 414.nam`** – der kleinste
Gain-Wert (0,0208) bedeutet die geringste Nichtlinearität und den größten Abstand zu den bisherigen Metal-
Referenzen; alle drei sind strukturell gleich, die Unterschiede sind klein und keine Variante ist beweisbar
besser. Zu sichern: `transfer.pcapng` (USBPcap über den ganzen Transfer), `nam_output_wav.wav` und `logfile.txt`
aus `C:\ProgramData\HTCache` direkt nach dem Import, unter `v4\fender_super_reverb_akg414\`.

**Korrektur (V3e):** Diese Datei war ein guter Vorschlag, wurde aber nicht importiert. Es existiert eine
**dritte** gleichnamige Datei direkt unter `Desktop\`, und das Editor-Log nennt genau deren Pfad. Diese Datei
ist – anders als angenommen – wieder ein SlimmableContainer 0.7.0 (dieselbe WaveNet-0.7.0/LeakyReLU-Familie wie
Solid Rhythm, GOJIRA und JVM Standard), nicht das erwartete WaveNet-0.5.4/Tanh-Modell. Details unten.

# V3e – Fender Super Reverb Clean Golden & Readiness-Entscheidung

Rein offline. Kein ADB, USB-/MIDI-/SysEx-Schreiben, NAM-/IR-Upload, Preset-Schreiben oder STORE; kein Zugriff auf
die Matribox, der Sonicake-Editor wurde nicht gestartet (die Beweise lagen bereits vor).

## Ergebnis (Kurz)

**Fender Super Reverb (AKG 414) ist ein viertes Golden: 8.232 / 8.232, mit dem unveränderten Konverter im
ersten Lauf.** Alle drei bisherigen Goldens bleiben unverändert grün. Die tatsächlich importierte Datei ist
aber, entgegen der V3d-Annahme, **kein** WaveNet-0.5.4/Tanh-Modell, sondern erneut SlimmableContainer 0.7.0 –
die Architektur-Diversität fehlt also weiterhin. Signalseitig liefert der Fall trotzdem neue, wichtige Evidenz
(sehr niedriger Pegel, `eP = eN = 43`, bisher unbelegter Zweig).

## Exakte Fender-NAM-Identität

Es gibt lokal **drei** Dateien mit demselben Namen `Fender Super Reverb_ EQ Flat, Volume 3, AKG 414.nam`:

| Pfad | Format | Größe | Gain | SHA-256 |
|---|---|---|---|---|
| `Desktop\…AKG 414.nam` (direkt) | **SlimmableContainer 0.7.0** (2 × WaveNet 0.7.0, LeakyReLU, 1.871/12.146 Gew.) | 298.052 B | 0,0297 | `e31984c8…d44f3c` |
| `Desktop\AMP Presets\Fender Super Reverb 1977\…AKG 414.nam` | WaveNet 0.5.4, Tanh, 2 Layer-Arrays 16/8, 13.802 Gew. | 283.481 B | 0,0208 | `88a26b54…7364` |
| (weitere WaveNet-0.5.4-Varianten sm57 / sm57+AKG414, siehe V3d) | WaveNet 0.5.4, Tanh | 283.5xx B | 0,023/0,028 | – |

Das Editor-Log nennt exakt `D:\Desktop 3d sachen\Desktop\Fender Super Reverb_ EQ Flat, Volume 3, AKG 414.nam`
– die **erste** Zeile, also die Desktop-Root-Datei (**CONFIRMED**). Sie wurde am 27.09. 07:36 angelegt, gut zwei
Stunden vor dem Import (09:40); ihre Metadaten (`gear_make: AKG c414`, `modeled_by: spooky`) passen zum Namen.
Die V3d-Vermutung, es handle sich um die WaveNet-0.5.4-Kopie aus `AMP Presets`, war **falsch** und wurde nicht
weiterverwendet.

## Evidence provenance

- `logfile.txt`: Lauf 27.09. 09:40:36–09:40:4x, `namFile` = Desktop-Root-Pfad (siehe oben), `output peak:
  0.234904`, Ausgabe `C:\ProgramData/HTCache/nam_output_wav.wav`.
- `nam_output_wav.wav`: Änderungszeit 09:40:43 (= Logende), 16 Bit, 2 Kanäle L = R, 48 kHz, 3.360.000 Frames,
  gemessener Peak 0,234894 (Log 0,234904 – Rundung durch Quantisierung) → **CONFIRMED**.
- `transfer.pcapng`: Änderungszeit 09:41:29; der Blocktransfer beginnt 12,35 s und endet 5,85 s vor Capture-Ende,
  bei einer Capture-Länge von 31,5 s – zeitlich nach dem Ende der WAV-Erzeugung (**CONFIRMED**, wie bei GOJIRA
  und JVM: Rechnung zuerst, Übertragung danach, Capture umschließt beides).
- CloData-Namensfeld aus dem Capture: `Fender Super Rev` (16-Byte-Kürzung des Dateinamens, deckt sich mit der
  V2-Regel). Slot-Byte 4.

Keine Mehrdeutigkeit; alle Indizien passen zusammen.

## Capture/Transport-Validierung

V2-Parser (`analyze-transfer`, unabhängig vom Konverter): 590 Blocknachrichten, 590 ACKs, 588 distinkte Blöcke
(Block 587 doppelt – wie bei A/B/C und JVM), 0 Prüfsummenfehler, 0 fehlend, 0 im Konflikt, ACK-Folge = Blockfolge,
alle Status 1. Kein Protokollunterschied zu den bisherigen Captures. Rekonstruierte CloData: **8.232 Byte**,
SHA-256 `d41fbafa…73366cd`.

## Konverter-Ergebnis (erster Lauf, unverändert)

Eingaben: `48000.wav` + Fender-`nam_output_wav.wav` + Dateiname. Ergebnis: erwartet 8.232 B, erzeugt 8.232 B,
**8.232 / 8.232 identisch**, 0 abweichende Bytes, keine Regionen, SHA-256 erwartet = erzeugt = `d41fbafa…73366cd`.
**Kein Fix nötig** – der erste Lauf des unveränderten Konverters trifft exakt.

## Regression und Determinismus

Solid Rhythm 8.232/8.232, GOJIRA 8.232/8.232, JVM410H Standard 8.232/8.232 – alle unverändert. Alle vier Fälle
liefen über `golden-report` zweimal mit gleichem Hash; zusätzlich wurde die Reihenfolge Fender → GOJIRA → JVM →
Solid Rhythm einzeln durchlaufen (kein `golden-report`), GOJIRA lieferte dabei byte-identisch zum Normallauf –
kein Zustand leckt zwischen Konvertierungen.

## Diversität – alle vier Goldens

| | Solid | GOJIRA | JVM Standard | Fender AKG414 |
|---|---|---|---|---|
| NAM-Format | Slimmable 0.7.0 | Slimmable 0.7.0 | Slimmable 0.7.0 | Slimmable 0.7.0 |
| Gain | 0,805 | 0,815 | 0,839 | **0,0297** |
| Ausgabe-Peak (Log) | 0,3075 | 0,2529 | 0,2248 | 0,2349 |
| Latenz (Engine) | 28 | 0 | 67 | 6 (**korrigiert, siehe V3f**; hier stand irrtümlich 78) |
| Stufe A: eP/eN | 1/1 | 1/1 | 1/1 | **43/43** |
| Stufe A: Skalierung a₊/a₋ | 1,2/0,85 | 1,2/1,15 | 1,2/1,05 | 1,2/1,2 (beide Rand) |
| Parameter P, N, a₊, a₋ | 0,089/0,114/752/375 | 0,081/0,094/778/582 | 0,056/0,058/613/488 | 0,235/0,225/1,17/1,19 |
| Stufe L: verbessert/behalten/RESET | 4/5/1 | 3/7/0 | 8/2/0 | 6/4/0 (**korrigiert, siehe V3f**; hier stand irrtümlich 5/5/0) |
| L-Fehlerniveau | 0,01–0,02 | 0,01–0,02 | 0,06–0,12 | **0,006–0,015** (am niedrigsten) |
| CloData-SHA-256 | `a3fffddf…` | `c3a44e92…` | `3613a1aa…` | `d41fbafa…` |

## Neu geübter Zweig

**`eP = eN = 43`** (Stufe A, erster 100-ms-Block, der 50 % des Spitzenwerts erreicht) ist erstmals ungleich 1 –
genau der in V3c/V3d als UNKNOWN geführte Zweig. Ursache: bei sehr niedrigem Pegel (Gain 0,03) steigt das
Testsignal über viele Blöcke langsam an, bevor es die Hälfte seiner eigenen Spitze erreicht. Zusätzlich ist das
Stufe-L-Fehlerniveau hier am niedrigsten aller vier Fälle – auch das ist neu. Damit ist der Konverter jetzt mit
eP/eN sowohl = 1 als auch ≫ 1 belegt.

## Verbleibende UNKNOWN-Zweige

Latenzrückfall auf 600 (keiner der vier Fälle kommt annähernd in die Nähe); Stufe L „nie verbessert" (b11 bleibt
null); Stufe-A-Skalierung an einem anderen inneren Rasterpunkt als 1,05/1,15 (0,8…1,15 unbelegt); ein
WaveNet-0.5.4/Tanh-Ausgangssignal (weiterhin nur über die drei WaveNet-Kandidaten aus V3d erreichbar, keiner
davon importiert).

## Golden-Korpus

`nam_golden_corpus.dart` enthält jetzt vier Fälle (Solid, GOJIRA, JVM Standard, Fender AKG414); der Fender-Fall
nutzt wie JVM die Capture-Rekonstruktion (`capture`/`captureSha256`) statt einer vorab gespeicherten CloData-
Datei. Die Kandidatenliste ist korrigiert: die AKG-414-WaveNet-Kopie aus „AMP Presets" bleibt Kandidat (jetzt
mit dem Hinweis, dass sie ein anderes Modell ist als die gleichnamige, bereits als Golden verwendete Datei);
kein neuer Testfile, der bestehende parametrisierte Test deckt Fender mit ab.

## Readiness-Entscheidung

Drei getrennte Fragen, wie gefordert:

```
NAM TRANSPORT PROTOCOL:      READY (unverändert seit V1/V2)
NAM → CLODATA CONVERTER:     PROVISIONALLY VERIFIED (nicht READY CANDIDATE)
NAM INFERENCE:                NOT READY (nicht implementiert)
```

Begründung gegen READY CANDIDATE trotz vier Byte-Goldens ohne jeden modellspezifischen Code: Alle vier
Referenzen sind **derselbe NAM-Architekturtyp** (SlimmableContainer 0.7.0, WaveNet 0.7.0, LeakyReLU). Fender
liefert echte *Signal*-Diversität (Pegel, eP/eN, Fehlerniveau), aber keine *Struktur*-Diversität. Zusätzliche
Einschränkungen: nur Windows-Plattformmathe verifiziert; mehrere Codezweige weiterhin unbelegt (siehe oben);
das Ergebnis hängt exakt vom WAV-Eingang ab (keine Toleranzprüfung gegen Rauschen/Resampling); Fehler-/NACK-
Transportpfade sind nicht Teil dieser Milestones und weiterhin nicht validiert (nur erfolgreiche Transfers).

## Nächster Architektur-Schritt (nur Planung, nichts implementiert)

Ziel bleibt, die Abhängigkeit vom Sonicake-Editor für `.nam → nam_output_wav.wav` aufzulösen:

```
.nam → NAM-Inferenz → nam_output_wav-Äquivalent → (unveränderter) CloData-Konverter → 8.232 B → Clone-Transport
```

**NeuralAmpModelerCore** bleibt der empfohlene Weg (MIT-Lizenz, vom Editor selbst statisch gelinkt, deckt
SlimmableContainer und WaveNet ab; siehe V3d). Wichtig, neu präzisiert: Die Abnahme einer eigenen Inferenz sollte
**nicht** Byte-Identität der WAV-Ausgabe verlangen – schon ±1 LSB auf 0,01 % der Samples ändert laut V3c-
Sensitivitätstest ~2.300 CloData-Bytes. Stattdessen zwei getrennte Kriterien:

1. **CloData-Golden-Tests** (dieser Datei): weiterhin strikt byte-exakt, ausschließlich gegen echte
   Editor-Ausgaben – unverändert.
2. **Eigene-Inferenz-Abnahme** (neues, noch zu bauendes Kriterium für die nächste Milestone): Signal-/FIR-
   Ebene, z. B. FIR-Fehler-Energie ≤ −60 dB gegenüber der offiziellen Ausgabe (Größenordnung aus dem V3c-Test),
   plus Kennlinien-Parameter (P, N, a₊, a₋) innerhalb einer engen relativen Toleranz. Diese Abnahme ersetzt
   nicht die Golden-Tests, sondern entscheidet, ob eine eigene Inferenz für den produktiven Einsatz taugt, ohne
   Byte-Gleichheit zu verlangen, die die Plattform vermutlich nicht liefern kann.

Nur Recherche/Planung in diesem Schritt; kein Vendoring, kein FFI/NDK.


# V3f – WaveNet 0.5.4/Tanh Golden & finale Diversitätsprüfung

Rein offline. Kein ADB, USB-/MIDI-/SysEx-Schreiben, NAM-/IR-Upload, Preset-Schreiben oder STORE; kein Zugriff auf
die Matribox, der Sonicake-Editor wurde nicht gestartet.

## Ergebnis (Kurz)

**FNDR PANO Clean2 BAL 6V6 CAB ist ein fünftes Golden: 8.232 / 8.232, mit dem unveränderten Konverter im ersten
Lauf.** Es ist das erste Golden mit einer wirklich anderen NAM-Architektur (WaveNet 0.5.4, Tanh, kein
SlimmableContainer). Zusätzlich korrigiert dieser Abschnitt zwei Fehler im V3e-Bericht (Fender-Latenz und
Stufe-L-Zählung, siehe unten).

## Exakte NAM-Identität (unabhängig verifiziert, nicht blind übernommen)

Lokal existiert genau **eine** Datei `FNDR PANO Clean2 BAL 6V6 CAB.nam`
(`Desktop\AMP Presets\Fender Pano-Verb\`), keine Mehrdeutigkeit. Verifiziert:

| Merkmal | Vorgabe | Gemessen |
|---|---|---|
| Größe | ca. 283.400 B | 283.400 B, stimmt |
| SHA-256 | ee7a3708...9006bdb | ee7a3708...9006bdb, stimmt |
| Version / Architektur | 0.5.4 / WaveNet | 0.5.4 / WaveNet, stimmt |
| Aktivierung | Tanh | Tanh, stimmt |
| Sample-Rate | 48.000 | 48.000, stimmt |
| Modellname | "FNDR PANO Clean2 BAL 6V6 CAB FREE" | "FNDR PANO Clean2 BAL 6V6 CAB FREE", stimmt |

Zusätzlich (nicht vorgegeben, jetzt festgestellt): Gain 0,5013, Loudness -17,45, 13.802 Gewichte, zwei
Layer-Arrays (16/8 Kanäle, Kernel 3, Dilationen 1...512, gated=false, Head 8/1). **Damit ist dies das erste
Golden mit einer strukturell wirklich anderen NAM-Architektur** - kein SlimmableContainer, kein WaveNet 0.7.0,
kein LeakyReLU (CONFIRMED, aus der Datei selbst gelesen).

## Evidence provenance

- `logfile.txt` in diesem Ordner enthält zwei Läufe: den bereits für V3e verwendeten Fender-Lauf von diesem
  Morgen (09:40:36) und den FNDR-PANO-Lauf von heute Abend (19:24:07-19:24:12, namFile = obiger Pfad,
  output peak: 0.195617). Das ist derselbe Editor-Prozess, dessen Logdatei über den Tag weitergeschrieben
  wurde; die Datei `nam_output_wav.wav` in diesem Ordner kann nur eine der beiden Ausgaben sein, da HTCache bei
  jedem Import überschrieben wird.
- `nam_output_wav.wav`: Änderungszeit 19:24:12, exakt das Ende des zweiten (FNDR-PANO-)Laufs, nicht des
  ersten - damit gehört die WAV eindeutig zu FNDR PANO, nicht zu Fender (CONFIRMED durch Zeitgleichheit).
  Gemessener Peak 0,195618, Log 0,195617.
- `tranfer.pcapng` (bewusst so geschrieben, ohne "s" - im Dateisystem so vorgefunden, nicht umbenannt):
  Änderungszeit 19:25:00; Blocktransfer beginnt 10,96 s und endet 4,40 s vor Capture-Ende (Capture-Länge 34,2 s)
  - nach der WAV-Fertigstellung, wie bei allen bisherigen Captures.
- CloData-Namensfeld aus dem Capture: "FNDR PANO Clean2", Slot-Byte 4.

Keine Mehrdeutigkeit; alle Indizien passen zusammen.

## Capture/Transport-Validierung

V2-Parser (unabhängig vom Konverter): 590 Blocknachrichten, 590 ACKs, 588 distinkte Blöcke (Block 587
doppelt), 0 Prüfsummenfehler, 0 fehlend, 0 im Konflikt, ACK-Folge = Blockfolge, alle Status 1 - identisch zum
Muster von A/B/C/JVM/Fender. Rekonstruierte CloData: 8.232 Byte, SHA-256 9dbb8d52...0f716da87.

## Konverter-Ergebnis (erster Lauf, unverändert)

Eingaben: 48000.wav + FNDR-PANO-nam_output_wav.wav + Dateiname. Ergebnis: erwartet 8.232 B, erzeugt 8.232 B,
8.232 / 8.232 identisch, 0 abweichende Bytes, keine Regionen, SHA-256 erwartet = erzeugt = 9dbb8d52...716da87.
Kein Fix nötig.

## Regression und Determinismus

Solid Rhythm, GOJIRA, JVM410H Standard und Fender AKG414 bleiben alle unverändert bei 8.232/8.232. Alle fünf
Fälle liefen über golden-report zweimal mit identischen Hashes. Zusätzlich Reihenfolge FNDR PANO -> Fender ->
JVM -> GOJIRA -> Solid Rhythm einzeln durchlaufen: alle fünf lieferten wieder 8.232 Bytes, und Solid Rhythm blieb
in dieser Reihenfolge byte-identisch zum Normallauf - kein Zustand leckt zwischen Konvertierungen, kein
Reihenfolge-Effekt.

## Korrektur zweier Fehler im V3e-Bericht

Beim Nachrechnen für diese Tabelle fielen zwei Abweichungen im V3e-Text auf (nicht im Code - der Konverter war
zu keinem Zeitpunkt verändert, die CloData-Bytes waren immer korrekt):

- Latenz Fender: V3e nannte 78, korrekt ist 6 (erster Sample über 0,01 im Fenster ab 6 s).
- Stufe-L-Zählung Fender: V3e nannte 5/5/0 (verbessert/behalten/RESET), korrekt ist 6/4/0.

Beide Werte wurden direkt aus einem frischen Diagnose-Log neu berechnet (runEngine(log:)); die Tabelle in V3e
ist oben entsprechend markiert. Die CloData-Bytes und Golden-Ergebnisse selbst sind von diesem Fehler nicht
betroffen.

## Diversität - alle fünf Goldens

| | Solid | GOJIRA | JVM Standard | Fender AKG414 | FNDR PANO |
|---|---|---|---|---|---|
| NAM-Format | Slimmable 0.7.0 | Slimmable 0.7.0 | Slimmable 0.7.0 | Slimmable 0.7.0 | WaveNet 0.5.4 |
| Aktivierung (NAM) | LeakyReLU | LeakyReLU | LeakyReLU | LeakyReLU | Tanh |
| Gain | 0,805 | 0,815 | 0,839 | 0,0297 | 0,501 |
| Ausgabe-Peak (Log) | 0,3075 | 0,2529 | 0,2248 | 0,2349 | 0,1956 |
| Latenz (Engine) | 28 | 0 | 67 | 6 | 10 |
| Stufe A: eP/eN | 1/1 | 1/1 | 1/1 | 43/43 | 30/26 |
| Stufe A: Skalierung a+/a- | 1,2/0,85 | 1,2/1,15 | 1,2/1,05 | 1,2/1,2 | 1,15/1,2 |
| Parameter P, N, a+, a- | 0,089/0,114/752/375 | 0,081/0,094/778/582 | 0,056/0,058/613/488 | 0,235/0,225/1,17/1,19 | 0,065/0,062/3,81/5,14 |
| Stufe L: verbessert/behalten/RESET | 4/5/1 | 3/7/0 | 8/2/0 | 6/4/0 | 4/6/0 |
| L-Fehlerniveau | 0,01-0,02 | 0,01-0,02 | 0,06-0,12 | 0,006-0,015 | 0,004-0,012 |
| FIR-Spitze (44,1 kHz) | 0,470 | 0,678 | 0,966 | 2,150 | 3,039 |
| CloData-SHA-256 | a3fffddf... | c3a44e92... | 3613a1aa... | d41fbafa... | 9dbb8d52... |

Auffällig: a+ liegt in allen fünf Fällen am oberen Rasterrand (1,15 oder 1,2), nie im Inneren - das ist eine
Beobachtung über die realen Signale, kein Hinweis auf einen Fehler (die Bytes stimmen exakt).

**Liefert der WaveNet/Tanh-Fall genuine neue Evidenz zur NAM-Architektur?**

- CONFIRMED: Die offizielle WaveNet-0.5.4/Tanh-Ausgabe des Editors durchläuft den generischen
  WAV-zu-CloData-Konverter fehlerfrei und byte-exakt. Das beweist, dass der Konverter nicht an die
  SlimmableContainer-Familie gekoppelt ist.
- CORRELATED: Erstmals asymmetrische eP/eN-Werte (30/26 statt gleich) und die größte Stufe-L-Fehlerspanne
  aller fünf Fälle - vermutlich durch das andere Signalverhalten der WaveNet/Tanh-Ausgabe bedingt, aber nicht
  auf die NAM-Architektur selbst zurückführbar (der Konverter sieht nur die WAV, nicht den Graphen).
- UNKNOWN, wichtig zu betonen: Ein erfolgreicher WaveNet-Golden beweist NICHT, dass eine eigene
  WyrmTone-NAM-Inferenz (V4) ebenfalls WaveNet korrekt berechnet - er beweist nur, dass der Konverter mit
  einer solchen Ausgabe zurechtkommt, wenn sie vom offiziellen Editor stammt.

## Neu geübte / weiterhin offene Zweige

Neu bestätigt: eP/eN ungleich zueinander (30 vs. 26); WaveNet/Tanh als Eingangssignalquelle. Weiterhin
UNKNOWN: Latenzrückfall auf 600 (größter beobachteter Wert bleibt 67, weit entfernt); Stufe L "nie
verbessert" (b11 bleibt null) - bei allen fünf echten Fällen verbessert bereits der erste Durchlauf jedes
Aufrufs, weil der Vergleichswert best mit 100,0 startet und alle beobachteten Fehler weit darunter liegen;
dieser Zweig scheint mit realistischen Signalen kaum erreichbar (HYPOTHESIS, aus dem Code plausibel, nicht
mit echten Daten belegt). Kein synthetischer Test wurde als Ersatz für echte Bytegleichheit gewertet.

## Golden-Korpus

nam_golden_corpus.dart enthält jetzt fünf Fälle. FNDR PANO nutzt wie JVM und Fender die
Capture-Rekonstruktion. Kein neuer Testfile; der bestehende parametrisierte Test deckt alle fünf ab
(flutter test test/tool: 28 bestanden).

## CloData-Readiness-Entscheidung

Drei getrennte Fragen:

```
NAM TRANSPORT PROTOCOL:      READY
NAM ZU CLODATA KONVERTER:    READY CANDIDATE
NAM INFERENCE:                NOT READY
```

Begründung für READY CANDIDATE (Hochstufung gegenüber V3e): Fünf unabhängige offizielle Goldens, alle mit
dem unveränderten Konverter im ersten Lauf byte-exakt, ohne jeden modellspezifischen Code, decken jetzt ab:
niedrigen (0,03) und hohen (0,84) Gain, drei verschiedene Latenzregime (0, 6-28, 67), symmetrische und
asymmetrische Stufe-A-Ergebnisse, Stufe-L mit und ohne RESET, und zwei grundverschiedene NAM-Architekturen
(SlimmableContainer/WaveNet-0.7.0/LeakyReLU und reines WaveNet-0.5.4/Tanh). Das ist genug Diversität, um die
Byte-Treue nicht mehr als Zufall einzelner ähnlicher Fälle zu erklären.

Ausdrücklich bestehende Einschränkungen, nicht verschwiegen:
- Nur Windows ist für die plattformabhängige Mathematik verifiziert (siehe V3c).
- Zwei Zweige bleiben unbelegt: Latenzrückfall 600, Stufe L "nie verbessert" (vermutlich mit echten Signalen
  praktisch unerreichbar).
- Fehler-/NACK-Transportpfade sind nicht Teil dieser Milestones und weiterhin nicht validiert.
- Eine eigene NAM-Inferenz existiert nicht; "READY CANDIDATE" gilt ausschließlich für den WAV-zu-CloData-Schritt.

## V1-V3-Abschluss

**Kann die V1-V3-NAM-Transport-/CloData-Forschung jetzt geschlossen werden? JA.**

Begründung: Das Transportprotokoll ist seit V1/V2 vollständig verstanden und byte-exakt simuliert. Der
CloData-Konverter hat fünf unabhängige, architektonisch und signalseitig diverse offizielle Goldens ohne
Sonderfall-Code bestanden, ist deterministisch und reihenfolgeunabhängig. Weitere Modelle würden nur die Zahl
erhöhen, ohne neue Zweige zu erschließen, solange sie keine neue NAM-Architektur oder keinen neuen Signalbereich
(insbesondere Latenz nahe 600) mitbringen. Das goldene Verhalten wird als Basis für V4 eingefroren; an diesem
Konverter wird in dieser Aufgabe nicht weiter reverse-engineered.

## V4-Plan: Direkte NAM-Inferenz (nur Planung, nichts implementiert)

```
.nam -> NAM-Inferenz -> nam_output_wav-Äquivalent -> (eingefrorener) CloData-Konverter -> 8.232 B -> Clone-Transport
     -> Matribox-Clone-Slot
```

NeuralAmpModelerCore (MIT, (c) 2023 Steven Atkinson) bleibt der empfohlene Weg:
- Architekturabdeckung: Unterstützt WaveNet und SlimmableContainer (seit v0.5.0) - deckt beide in V3f
  bestätigten Familien ab. LSTM/ConvNet werden hier nicht benötigt.
- Windows-Integration: CMake-Build als DLL, per dart:ffi aus dem Flutter-Windows-Build geladen; derselbe
  Core wie unter Android, um zwei Inferenzpfade zu vermeiden.
- Android-Integration: CMake im Android-NDK (externalNativeBuild, ABIs mindestens arm64-v8a; x86_64 für
  Emulatoren), Ausgabe als .so, ebenfalls über dart:ffi.
- Dart-FFI-Grenze: schlanke C-Schicht (nam_load(path) -> handle, nam_process(handle, in, out, n),
  nam_free(handle)); Puffer als Float32 contiguous, Fehler über Rückgabecode statt Exceptions (FFI-Grenzen
  vertragen keine Dart-Exceptions).
- Lifecycle/Threading: Laden und Verarbeiten in einem eigenen Isolate (Rechenzeit des Editors ca. 6-13 s für
  70 s Signal als Größenordnung, siehe Logs); Handle-Freigabe über finalizer/explizites dispose(), kein
  Zugriff aus dem UI-Thread.
- Sample-Rate: Editor konvertiert Eingang stets auf 48 kHz vor der Inferenz (Log: "converting input
  sampleRate to 48000") - dieselbe Regel muss die eigene Pipeline übernehmen.
- Speicher: 70 s x 48 kHz x 4 Byte ca. 13,4 MB pro Puffer (Eingang/Ausgang), unkritisch.
- Fehlerbehandlung: ungültige/unbekannte NAM-Version, nicht unterstützte Architektur (LSTM/ConvNet, falls
  später gebraucht) müssen als eigene, geprüfte Fehlerpfade existieren, nicht als Absturz.
- Lizenz: MIT für den Core; Eigen (Abhängigkeit) MPL-2.0 - als unveränderte Bibliothek verlinkbar, Lizenztext
  muss beiliegen. Vor tatsächlicher Übernahme erneut gegen den dann aktuellen Upstream-Stand prüfen. Nichts
  wurde vendort oder heruntergeladen.
- On-Device-Tauglichkeit: Die vom Editor gemessenen 6-13 s für ein 70-s-Testsignal auf einem PC sind ein
  Anhaltspunkt, kein Android-Benchmark; ein früher Prototyp-Test auf Zielhardware ist Teil von V4, nicht dieser
  Recherche.

## V4-Abnahmestrategie (Entwurf, noch nicht umgesetzt)

A. NAM-Inferenz-Korrektheit (eigene Ausgabe vs. offizielle nam_output_wav.wav): kein Byte-Vergleich.
Vorschlag: Latenzausrichtung (Kreuzkorrelation), dann RMS-Fehler und Spitzenfehler auf das ausgerichtete Signal,
zusätzlich ein Frequenzbereichsfehler (z. B. gemittelte Betragsdifferenz im Log-Spektrum). Schwellenwerte sind
noch zu kalibrieren, sobald eine erste eigene Inferenz existiert.

B. Klanggleichheit nach dem Konverter: beide Signale (offiziell und eigen) durch den unveränderten
CloData-Konverter schicken und P, N, a+, a-, FIR1, FIR2 und die finale CloData vergleichen. Vorschlag für ein
technisches Kriterium (keine Byte-Gleichheit): FIR-Fehler-Energie <= -60 dB relativ (Größenordnung aus dem
V3c-Sensitivitätstest: +-1 LSB auf 0,01 % der Samples ergab bereits -80 dB), plus enge relative Toleranz auf die
vier Parameter (z. B. < 1 %). Diese Zahlen sind ein erster Vorschlag, keine endgültige Spezifikation.

C. Bestehende offizielle Goldens: bleiben strikt 8.232/8.232 gegen echte Editor-Ausgaben, unverändert und
ohne Toleranz. Sie werden durch V4 nicht ersetzt oder abgeschwächt.


# V4a - Windows-native NAM-Inferenz und Ende-zu-Ende-Validierung

Rein Windows, ausschliesslich lokale Dateien. Kein Android, kein NDK, kein Matribox-Zugriff, kein
MIDI-/SysEx-Write, kein NAM-/IR-Upload, kein Preset-Write, kein Store. Der bestehende CloData-Konverter
(tool/matribox_nam_analysis/) ist zu keinem Zeitpunkt geaendert worden.

## Ergebnis (Kurz)

Eine unabhaengige, eigene NAM-Inferenz (NeuralAmpModelerCore, C-ABI, dart:ffi) laeuft auf Windows fuer beide
NAM-Architekturen (SlimmableContainer und WaveNet), deterministisch, ohne NaN/Inf, mit exakter FFI/Native-
Identitaet. Das rohe Ausgangssignal stimmt bei allen fuenf Goldens bis auf einen **festen, ueber alle funf
Faelle nahezu identischen Skalierungsfaktor 0,31** (Korrelation > 0,999998) mit der offiziellen
`nam_output_wav.wav` ueberein - eine reproduzierbare, im offiziellen Editor-Pfad liegende Groesse, keine
Ungenauigkeit unserer Inferenz. Durch den eingefrorenen CloData-Konverter geschickt (ohne jede Anpassung)
ergibt das erwartungsgemaess **keine** Byte-Gleichheit zu den offiziellen CloData-Goldens; das ist das
Messergebnis dieses Meilensteins, nicht ein Fehler des Konverters.

## Exakte NAM-Bridge (C-ABI)

`native/nam_bridge/include/wyrmtone_nam.h` (Header, siehe Datei fuer die volle Dokumentation): opake
`wyrmtone_nam_engine`-Handles, `wyrmtone_nam_create/load/process/unload/destroy/last_error`, definierte
Fehlercodes (0=OK, 1..7 spezifisch, 99=unbekannt). Keine C++-Typen, keine Exceptions ueber die ABI-Grenze
(jede native Funktion faengt `std::exception`/`...` und meldet stattdessen einen Statuscode plus Textmeldung).
Kein globaler Modellzustand: jede Instanz besitzt genau ein Modell; wiederholtes Load/Unload/Reload auf
demselben Handle ist erlaubt und getestet. Thread-Eigentum ist dokumentiert (ein Handle nicht parallel von
mehreren Threads verwenden; mehrere Handles sind unabhaengig).

Quellen: `third_party/NeuralAmpModelerCore` @ `0b3d3c97b0859a3a8c92a8628c4dd89a25eb5842` (MIT), darin per
Directory-Junction `Dependencies/eigen` @ `bc3b39870ecb690a623a3f49149a358b95c5781d` (MPL-2.0) und
`Dependencies/AudioDSPTools` @ `0827c6c2fc0deced568536142ea86f189e0b98a1` (MIT, im Kernpfad ungenutzt, nur fuer
den optionalen Linear/WAV-Modelltyp referenziert); `nlohmann/json` liegt bereits einzel-Header im Core-Repo
vor. Keine weiteren Abhaengigkeiten. Gebaut mit der in dieser Session vervollstaendigten Windows-Toolchain
(MSVC 19.44.35229, Windows-SDK 10.0.22621.0, CMake 4.4.3, NMake-Generator) als `wyrmtone_nam.dll` (48 %-Build)
und ein unabhaengiger nativer Test-Runner `nam_bridge_runner.exe`, der dieselben Quellen **erneut kompiliert**
(nicht gegen die DLL gelinkt), damit ein Unterschied zwischen Runner und FFI nur von der FFI-Grenze selbst
stammen kann.

## Referenzsignal

Verwendet wie in V1-V3 belegt: `wyrmtone-captures/v3/48000.wav` (24 Bit, mono, 48 kHz, 3.360.000 Frames =
70 s), identisch zur editor-internen, bereits auf 48 kHz resampelten Kopie des Referenzsignals (Editor-Log:
"model sampleRate: 48000", "converting input sampleRate to 48000"). Alle funf .nam-Dateien melden
`sample_rate: 48000`; `Reset(48000.0, blockSize)` entspricht daher der Trainings-/Erwartungsrate, keine
Resampling-Notwendigkeit in der Bruecke selbst. Kanalwahl: mono direkt (Referenz ist mono); die 16-Bit-Stereo-
Ausgabe des Runners dupliziert L=R exakt wie der Editor. Keine Normalisierung, keine Skalierung im Runner
ausser der reinen Float-zu-PCM16-Quantisierung beim Schreiben der WAV.

**Lizenzfrage (nicht in diesem Meilenstein geloest, siehe unten):** `48000.wav`/`nam_input_wav.wav` ist eine
proprietaere Sonicake-Ressource (`C:\Program Files\Sonicake\Matribox\Resource\Matribox\File\nam_input_wav.wav`,
44,1 kHz Stereo 16 Bit, SHA-256 `9bb6c1b1...b29aa1a`, aus der Editor-Installation gelesen, nicht kopiert). Fuer
diese Forschungsvalidierung wurde ausschliesslich die bereits lokal vorhandene, aus einer eigenen HTCache-Kopie
stammende 48-kHz-Version verwendet; sie liegt unter `wyrmtone-captures/` (per `.gitignore` ausserhalb der
Git-Historie) und wurde **nicht** nach `lib/`, `assets/` oder in die Git-Historie uebernommen.

## Native Smoke-Tests

FNDR PANO (WaveNet 0.5.4/Tanh) und alle vier Slimmable-Faelle (Solid Rhythm, GOJIRA, JVM410H Standard, Fender
AKG414) laden erfolgreich, liefern 3.360.000 Ausgangs-Samples (= Eingangslaenge), **keine NaN/Inf**, deterministisch
bei wiederholtem Lauf (bytegleiche `.f32`-Ausgabe). Fehlerpfade getestet: nicht existierende Datei
(`WYRMTONE_NAM_ERR_FILE_NOT_FOUND`), kaputtes JSON (`..._LOAD_FAILED`, Fehlermeldung nennt die nlohmann-
Parse-Position, kein Absturz), fehlendes Pflichtfeld (`..._LOAD_FAILED`).

## Rohvergleich (RAW, vor jeder Alignment-Analyse)

| Fall | NAM-Architektur | corr (lag 0) | Skalar k=Sig/official | 1/k | NRMSE nach Skalierung |
|---|---|---|---|---|---|
| Solid Rhythm | Slimmable/WaveNet 0.7.0 | 0,99999999 | 0,31000368 | 3,225768 | 3,25e-4 |
| GOJIRA | Slimmable/WaveNet 0.7.0 | 0,99999998 | 0,31000070 | 3,225799 | 3,72e-4 |
| JVM410H Standard | Slimmable/WaveNet 0.7.0 | 0,99999997 | 0,30999813 | 3,225826 | 4,67e-4 |
| Fender AKG414 | Slimmable/WaveNet 0.7.0 | 0,99999995 | 0,30999968 | 3,225810 | 6,34e-4 |
| FNDR PANO | WaveNet 0.5.4/Tanh | 0,99999852 | 0,31013752 | 3,224376 | 1,84e-3 |

`k` = kleinste-Quadrate-Skalar (unser Signal * k = offizielles Signal, ohne Achsenabschnitt). Latenzversatz:
Kreuzkorrelation zeigt in allen fuenf Faellen das Maximum bei **Lag 0** (keine Verschiebung notwendig; siehe
Lag-Scan fuer GOJIRA/FNDR im Rohtest). DC-Offset beider Signale ist praktisch 0 (Referenzsignal und
Modellausgabe sind Wechselsignale). Peak/RMS: Peaks unserer Rohausgabe liegen 3,22-3,23x hoeher als offiziell,
exakt im gleichen Verhaeltnis wie k.

**Sind die Samples identisch?** Nein, in keinem Fall exakt gleich (Ratio ~3,226, kein einziges Sample matcht
bit-genau); der erste "Unterschied" ist also Sample 0. Bit-/ULP-Vergleich ist bei einem derart grossen Skalar
nicht aussagekraeftig und wurde deshalb nicht weiter verfolgt.

## Begruendete Alignment-Analyse (danach)

Die Konstante 0,31 (bzw. 1/0,31=3,2258) ist **modellunabhaengig**: sie ist fuer alle fuenf Faelle - trotz
vollstaendig unterschiedlicher `gain`/`loudness`-Metadaten (0,0297 bis 0,839) und zwei verschiedener
Architekturen - auf 4-5 signifikante Stellen identisch. Geprueft und **ausgeschlossen** als Erklaerung:

- `head_scale` (WaveNet-Kopfskalierung aus der .nam-Config): wird laut Quellcode (`NAM/wavenet/model.cpp:909`)
  bereits **innerhalb** von `process()` angewandt, ist also nicht die fehlende Grosse.
- `metadata.gain`: wird von `get_dsp()`/`get_dsp.cpp` **nicht gelesen** (nur `loudness`, `input_level_dbu`,
  `output_level_dbu`); ausserdem passt der Wert nicht zu 0,31 (unterschiedliche gain-Werte, gleicher Faktor).
- `SetLoudness`/`SetInputLevel`/`SetOutputLevel`: laut `NAM/dsp.cpp` reine Speicherfelder, werden in
  `process()` an keiner Stelle gelesen oder angewandt.

**Nicht ausgeschlossen, aber nicht belegbar ohne weitere Schritte:** ein fester, in der proprietaeren
Sonicake-Anwendung (nicht in NeuralAmpModelerCore) liegender Ausgangs- oder Eingangs-Trim von ca. 0,31. Da
alle fuenf Modelle bei diesem Testsignal quasi-linear reagieren (Korrelation > 0,9999985 selbst fuer
"Metal"-Presets), laesst sich aus den vorliegenden Daten **nicht** unterscheiden, ob der Faktor vor oder nach
der Inferenz angewandt wird. Evidenzklasse: **CORRELATED** (empirisch robust, fuenf unabhaengige Faelle,
keine Ausnahme), nicht CONFIRMED (Ursache im Sonicake-Code nicht statisch verifiziert - das waere eine
gesonderte, hier nicht durchgefuehrte Read-only-Analyse von `Matribox.exe`).

Keine willkuerliche Verschiebung/Normalisierung wurde vorgenommen; der Faktor wurde ausschliesslich zur
**Erklaerung** verwendet, nicht in den Produktionscode oder die Testausgabe eingebaut.

## Inferenz -> CloData (das wichtigste Ergebnis dieses Meilensteins)

Rohe (unskalierte) WyrmTone-Inferenzausgabe, unveraendert durch den eingefrorenen
`MatriboxNamCloDataConverter` geschickt, verglichen mit der jeweiligen offiziellen CloData:

| Fall | Groesse | gleiche Bytes/8232 | abweichende Bytes | Regionen | P/N (offiziell) | P/N (unsere Roh-Inferenz) | Verhaeltnis |
|---|---|---|---|---|---|---|---|
| Solid Rhythm | 8232/8232 | 4680 | 3552 | 1008 | 0,0892/0,1143 | 0,2876/0,3688 | 3,224/3,226 |
| GOJIRA | 8232/8232 | 5302 | 2930 | 1130 | 0,0808/0,0936 | 0,2605/0,3020 | 3,225/3,226 |
| JVM410H Standard | 8232/8232 | 4666 | 3566 | 984 | 0,0560/0,0579 | 0,1806/0,1868 | 3,226/3,227 |
| Fender AKG414 | 8232/8232 | 3961 | 4271 | 304 | 0,2348/0,2251 | 0,7575/0,7261 | 3,226/3,226 |
| FNDR PANO | 8232/8232 | 4539 | 3693 | 882 | 0,0655/0,0617 | 0,2112/0,1990 | 3,226/3,226 |

P und N skalieren in allen fuenf Faellen exakt mit demselben ~3,226-Faktor - vollstaendig konsistent mit dem
Rohvergleich oben und ein starker, unabhaengiger Beweis dafuer, dass die **Kennlinienform** unserer Inferenz
korrekt ist. Die Exponenten a+/a- (Kruemmung der Kennlinie) liegen dagegen fuer alle fuenf Faelle innerhalb
von unter 1 % der offiziellen Werte (z. B. Solid: 751,84 vs. 751,87; GOJIRA: 777,45 vs. 777,74) - ein deutlich
staerkerer Hinweis, dass **die eigentliche Modellinferenz** (Kennlinienform, Nichtlinearitaet) bereits ohne
jede Anpassung nahezu korrekt ist; nur die absolute Verstaerkung unterscheidet sich um den bekannten Faktor.
FIR1/FIR2 unterscheiden sich in absoluter Amplitude proportional (die Stufe-F-Energienormierung skaliert die
FIR-Antwort auf die tatsaechliche - zu laute - Ausgangsenergie), was ebenfalls zum Bild passt.

**Keine der offiziellen Goldens wurde veraendert. Der Konverter wurde nicht angepasst. Die Byte-Abweichung ist
das erwartete Messergebnis, kein Fehler.**

## FFI/Nativ-Identitaet

Derselbe NAM (FNDR PANO) mit denselben ersten 200.000 Frames des Referenzsignals: einmal ueber den nativen
Runner (eigenstaendig kompiliert), einmal ueber `dart:ffi`/`NamInferenceEngine`. Ergebnis: **bytegleich**
(`orderedEquals` auf den Float32-Samples bestanden). Das FFI selbst veraendert keine Daten.

## Determinismus, Lebenszyklus, Fehlerbehandlung (Dart-Ebene)

`test/tool/nam_inference_test.dart` (Windows-only via `@TestOn('windows')`): Laden/Verarbeiten/Entladen im
Wechsel (auch Modellwechsel auf demselben Handle), deterministischer Wiederholungslauf (bytegleich), ungueltiger
Pfad -> `NamInferenceException(fileNotFound)`, kaputtes JSON -> `loadFailed`, Verarbeitung ohne geladenes
Modell -> `notLoaded`, `dispose()` idempotent (zweiter Aufruf ist ein No-op), jede weitere Methode nach
`dispose()` wirft `StateError` (Use-after-free-Schutz). Alle Tests bestanden.

## Performance (Windows, Debug-Build der Bruecke, Release-Flags nicht gesetzt)

| Phase | GOJIRA (Slimmable) | FNDR PANO (WaveNet) |
|---|---|---|
| DLL laden | 3 ms | 0 ms |
| NAM laden | 26 ms | 32 ms |
| Inferenz (70 s Signal) | 13.068 ms | 13.645 ms |
| CloData-Konvertierung (unser bestehender Dart-Engine) | 16.954 ms | 17.081 ms |
| **Gesamt** | **30.054 ms** | **30.763 ms** |

Peak Working Set des nativen Prozesses (FNDR PANO, ganzer Lauf inkl. WAV-I/O): **~60 MB**. Das ist eine
Offline-Konvertierung (kein Echtzeit-Audio); 13 s Inferenz + 17 s CloData fuer ein 70-Sekunden-Testsignal sind
fuer diesen Anwendungsfall unproblematisch, wie in der Aufgabe vorgegeben akzeptabel. Die CMake-Konfiguration
wurde ohne expliziten `-O2`/`Release`-Optimierungs-Build erstellt (nur `CMAKE_BUILD_TYPE=Release` gesetzt, aber
kein separates Speed-Tuning); ein spaeterer Android-Build sollte dieselbe Konfiguration mit expliziten
Optimierungsflags pruefen.

## Tests, Analyze, Regression

- `flutter test test/tool/nam_inference_test.dart`: 12/12 bestanden (Windows-only-Datei).
- `flutter test -j 2` (Vollsuite, 668 Tests): **667 bestanden, 1 fehlgeschlagen** beim ersten Lauf
  (`ToneTransferPage: ... goes STALE immediately ...` in `test/product_experience_v2_test.dart`) - **isoliert
  erneut ausgefuehrt: bestanden.** Kein `lib/`-Code wurde in diesem Meilenstein geaendert (`git diff --stat --
  lib/` ist leer); die Abweichung ist ein unter Last (668 Tests, `-j 2`, gleichzeitig laufende Zeitgeber-Tests)
  zeitkritischer, vorbestehender Test, kein durch V4a verursachter Regressionsfehler. Kein Test wurde geloescht
  oder abgeschwaecht, um Gruen zu erreichen.
- `flutter analyze`: 33 Hinweise (alle Stufe "info", keine Fehler); 32 davon vorbestehend in
  `tool/matribox_analyzer.dart` (nicht in diesem Meilenstein beruehrt); die letzten "avoid_print"-Hinweise
  betrafen ein bereits wieder geloeschtes Wegwerf-Diagnoseskript.
- Die fuenf offiziellen CloData-Goldens (`test/tool/matribox_nam_analysis_test.dart`) sind **unveraendert
  gruen**, mit denselben SHA-256 wie in V3f.

## Referenzsignal - Lizenz-/Produktionsplan (Analyse, keine Umstellung)

Der CloData-Algorithmus (Stufen A/B/C/L/F, siehe V1-V3) braucht vom Referenzsignal konkret: eine 0-5-s-
Pegelrampe fuer die Kennlinienanpassung (Stufe A), einen Impuls plus ruhiges Signal um 6 s fuer die Latenzsuche
und Stufe B, sowie mehrere Abschnitte mit stationaerem/breitbandigem Inhalt bei 6-70 s fuer die
Frequenzgangschaetzung (Stufen C/L/F). Mathematisch sind das reproduzierbare Eigenschaften (Amplitudenrampe,
kurzer Nadelimpuls, spektral reichhaltiges Rauschen/Sweep-artiges Signal) - **keine** Eigenschaft des Signals
verlangt zwingend exakt das proprietaere Sonicake-Sample. Plan fuer ein eigenes, redistributierbares
WyrmTone-Signal (Option B aus der Aufgabenstellung, rein rechnerisch erzeugt, keine Aufnahme mit unklarer
Lizenz):

1. 0-5 s: linearer/logarithmischer Pegel-Sweep von sehr leise bis Vollausschlag (deckt Stufe-A-Kennlinien-
   anpassung ab; die Blockgroesse 100 ms und der 50-%-Schwellenwert aus Stufe A sind bekannt und muessen beim
   Amplitudenverlauf beruecksichtigt werden).
2. Ab 6 s: kurzer Nadelimpuls (fuer die Latenzsuche, die exakt im 600-Sample-Fenster ab 6 s nach einem Betrag
   > 0,01 sucht) gefolgt von einem ruhigen, aber nicht stillen Abschnitt.
3. 6-70 s: ein deterministisch erzeugtes, breitbandiges Signal (z. B. Summe von Sinustoenen oder ein
   pseudozufaelliges Rauschen mit festem Seed) mit ausreichender spektraler Dichte fuer die
   Frequenzgangschaetzung der Stufen B/C/L/F.

**Wichtige Konsequenz, die separat zu klaeren ist:** Ein anderes Signal fuehrt zu einem anderen
Zeit-/Frequenzverlauf durch dieselbe (unveraenderte) CloData-Mathematik - das aendert weder den Konverter noch
die bestehenden Goldens (die bleiben an das offizielle Signal gebunden), bedeutet aber, dass ein WyrmTone-NAM,
das mit dem **eigenen** Referenzsignal erzeugt wurde, **nicht** direkt gegen die fuenf offiziellen Goldens
pruefbar ist - ein neues, eigenes Golden-Set (WyrmTone-Referenzsignal + eigene Inferenz + eigene CloData, ohne
offiziellen Vergleich moeglich) waere fuer die Produktvalidierung notwendig. Das ist ein eigener, spaeterer
Arbeitsschritt (nicht in V4a), aber der oben beschriebene Plan macht ihn konkret umsetzbar, sobald das
0,31-Ratsel (Ursache des Skalierungsfaktors) entweder geklaert oder als irrelevant fuer den eigenen Signalweg
eingestuft ist.

## Sicherheit

NO ADB - NO ANDROID INSTALL - NO USB WRITE - NO MIDI WRITE - NO SYSEX WRITE - NO NAM UPLOAD - NO IR UPLOAD -
NO PRESET WRITE - NO STORE. Kein Testupload. Kein Matribox-Zugriff zu irgendeinem Zeitpunkt.

## Naechster Meilenstein

Der Prompt nach diesem Bericht entscheidet anhand der Messergebnisse (insbesondere: 0,31-Faktor geklaert oder
nicht, Inferenzform bereits sehr nahe an offiziell) ueber Android/NDK. Empfehlung dieses Berichts (siehe
Abschlusszeilen): **HOLD**, bis der 0,31-Faktor entweder erklaert (z. B. durch eine gezielte, read-only
Analyse der Matribox.exe-Aufrufkette rund um `getNamOutput`) oder bewusst als irrelevant fuer eine zukuenftige
eigene Referenzsignal-Pipeline eingestuft ist - eine native Portierung auf Android waere sonst verfrueht, weil
noch unklar ist, ob die fehlende Konstante ein Sonicake-Implementierungsdetail oder ein Hinweis auf einen
zusaetzlichen, noch fehlenden Verarbeitungsschritt ist.


# V4b - Untersuchung der Skalierungsluecke der eigenen NAM-Inferenz

Rein Read-only (Matribox.exe nur statisch gelesen, nicht gestartet), keine Aenderung an
NeuralAmpModelerCore, third_party unveraendert, kein Android, kein Hardware-Zugriff, kein Commit.

## Ergebnis (Kurz)

Der ~0,31-Faktor aus V4a ist jetzt praezise vermessen: **ein einziger, modellunabhaengiger Skalar
k = 0,3100 (Streuung 0,00002 fuer vier von fuenf Faellen, 0,0001 fuer den fuenften)**, angewandt NACH der
Inferenz, nicht vor ihr (per Experiment ausgeschlossen). Die genaue Quelle im Sonicake-Binary wurde
**nicht** zweifelsfrei identifiziert; ein vielversprechender Kandidat (eine Multiplizier-und-Peak-Schleife
in `getNamOutput`) fuehrte zu einem Konstantenwert (420,0), der nicht zu 0,3100 passt - vermutlich eine
andere, unabhaengige Konstante (z. B. eine Pegelmesser-Ballistik), keine bestaetigte Erklaerung. Deshalb:
**kein** `output *= 0,31` in Produktions- oder Wrapper-Code. Der Skalar wurde ausschliesslich in
Wegwerf-Experimentcode (`native/nam_bridge/out/*.dart`, nicht Teil des Produkts) verwendet.

## B. Exakte Skalierungsmessung fuer alle fuenf Modelle

| Fall | k (LS ohne Achsenabschnitt) | k (LS mit Achsenabschnitt) | DC-Achsenabschnitt | RMS-Verhaeltnis | Peak-Verhaeltnis | Median-Verhaeltnis | Pos.-Verhaeltnis | Neg.-Verhaeltnis | corr (vor Skalierung) | corr (nach Skalierung) | NRMSE vor | NRMSE nach | Rest-RMS |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Solid | 0,31000368 | 0,30999988 | -1,58e-5 | 0,31000370 | 0,31001211 | 0,31000637 | 0,30988655 | 0,31010808 | 0,99999999 | 0,99999999 | 2,2258 | 3,25e-4 | 1,80e-5 |
| GOJIRA | 0,31000070 | 0,31000001 | -1,57e-5 | 0,31000072 | 0,31001920 | 0,31000040 | 0,30987230 | 0,31012633 | 0,99999998 | 0,99999998 | 2,2258 | 3,72e-4 | 1,80e-5 |
| JVM Standard | 0,30999813 | 0,31000013 | -1,59e-5 | 0,30999816 | 0,30997350 | 0,30999180 | 0,30982189 | 0,31017767 | 0,99999997 | 0,99999997 | 2,2258 | 4,67e-4 | 1,82e-5 |
| Fender AKG414 | 0,30999968 | 0,31000002 | -1,47e-5 | 0,30999974 | 0,30998636 | 0,31000472 | 0,30972099 | 0,31028394 | 0,99999995 | 0,99999995 | 2,2258 | 6,34e-4 | 1,71e-5 |
| FNDR PANO | 0,31013752 | 0,31013771 | -2,09e-5 | 0,31013804 | 0,30991735 | 0,31024342 | 0,31003774 | 0,31051098 | 0,99999852 | 0,99999852 | 2,2244 | 1,84e-3 | 5,94e-5 |

(corr vor/nach Skalierung ist erwartungsgemaess mathematisch identisch - Pearson-Korrelation ist
skaleninvariant fuer positive Skalare; die Kennzahl bestaetigt aber, dass bereits die unskalierte
Rohausgabe fast perfekt korreliert ist, also kein Zeitversatz/keine Formaenderung noetig ist.)

**Einordnung A-F:**
- **A. Ein konstanter Skalar:** stark gestuetzt. `k_ls` und `k_dc` (mit Achsenabschnitt) sind praktisch
  gleich -> kein DC-Anteil (schliesst **C. Gain+DC-Offset** aus). Pos./Neg.-Verhaeltnis unterscheiden sich
  nur um ~0,1 %, im Rahmen der 16-Bit-Quantisierung der offiziellen Referenz.
- **B. Modellabhaengiger Skalar:** ausgeschlossen (siehe global-Fit-Experiment unten - eine einzige
  Konstante ueber alle fuenf Modelle aendert die Fehlerwerte praktisch nicht).
- **D. Gain+Latenz:** ausgeschlossen - Kreuzkorrelation hat ihr Maximum bei Lag 0 in allen fuenf Faellen
  (aus V4a bereits belegt).
- **E. Nichtlineare Transformation:** durch das Experiment in Abschnitt F unten aktiv widerlegt.
- **F. Preprocessing-Unterschied (Eingang):** durch das Experiment in Abschnitt F unten aktiv widerlegt.

## C. Experiment: pro Modell bester Skalar -> CloData

Rohe Inferenzausgabe offline mit dem **je Modell** unabhaengig gemessenen `k_ls` multipliziert, dann durch
den unveraenderten `MatriboxNamCloDataConverter`:

| Fall | gleiche Bytes/8232 | abweichend | Regionen |
|---|---|---|---|
| Solid | 5302 | 2930 | 1129 |
| GOJIRA | 5169 | 3063 | 1127 |
| JVM Standard | 5079 | 3153 | 1121 |
| Fender AKG414 | 4072 | 4160 | 414 |
| FNDR PANO | 4955 | 3277 | 1121 |

## D. Experiment: EIN globaler Skalar (ueber alle fuenf gemeinsam gefittet) -> CloData

Globaler Skalar (kleinste Quadrate ueber alle 5*3.360.000 Samples gemeinsam): **k_global = 0,31001760**
(1/k = 3,225623). NRMSE mit diesem einen globalen Wert bleibt fuer jedes einzelne Modell praktisch
unveraendert (3,3e-4 bis 1,9e-3) - **ein globaler Skalar erklaert die Amplitude genauso gut wie fuenf
individuelle**, ein starkes Argument fuer Hypothese A.

| Fall | gleiche Bytes/8232 | abweichend | Regionen |
|---|---|---|---|
| Solid | 5332 | 2900 | 1132 |
| GOJIRA | 5224 | 3008 | 1129 |
| JVM Standard | 5076 | 3156 | 1120 |
| Fender AKG414 | 4053 | 4179 | 394 |
| FNDR PANO | 4914 | 3318 | 1118 |

**Wichtige Erkenntnis aus C/D:** Die Skalierung alleine bringt die CloData-Uebereinstimmung nur moderat
voran (von 3.961-5.302 unskaliert auf 4.053-5.332 skaliert) - **keine Byte-Identitaet**. Das ist erwartbar:
V3c hatte bereits gezeigt, dass +-1 LSB auf 0,01 % der Samples bereits ~2.300 CloData-Bytes aendert; die
CloData-Mathematik ist so empfindlich, dass Amplitudenkorrektur allein niemals reicht, wenn die eigene
Inferenz nicht auch **bit-exakt** zur offiziellen Sonicake-Berechnung ist (anderer Compiler, andere
FMA-Reihenfolge, moeglicherweise andere NeuralAmpModelerCore-Version). Das ist ein separates,
eigenstaendiges Ergebnis, keine Ueberraschung.

## E. NAM-gain-Handhabung (Code-Trace, nicht aus Namen geraten)

Fuenf .nam-Metadaten (`gain`): Solid 0,8058; GOJIRA 0,8150; JVM 0,8389; Fender 0,0297; FNDR PANO 0,5013 -
voellig unterschiedlich, waehrend k in allen fuenf Faellen ~0,3100 ist. Das allein schliesst `gain` als
Erklaerung so gut wie aus. Code-Beleg (`NAM/get_dsp.cpp`, Funktion `get_dsp_with_current_prewarm_default`):
nur `loudness`, `input_level_dbu`, `output_level_dbu` werden aus den Metadaten gelesen und per
`SetLoudness`/`SetInputLevel`/`SetOutputLevel` gespeichert (`NAM/dsp.cpp`); `metadata.gain` wird an **keiner
Stelle** aus der JSON extrahiert. `SetLoudness`/`SetInputLevel`/`SetOutputLevel` sind reine Speicherfelder
(`mLoudness`, `mHasLoudness`) - in `process()` (`NAM/dsp.cpp`, `NAM/wavenet/model.cpp`) wird keines dieser
Felder gelesen. `head_scale` (WaveNet-Kopfskalierung aus der Modell-Config, bei FNDR PANO 0,02) wird
dagegen **innerhalb** von `process()` angewandt (`NAM/wavenet/model.cpp:909`,
`output[ch][s] = this->_head_scale * final_head_outputs(ch, s);`) - ist also bereits in unserer Rohausgabe
enthalten und keine fehlende Grosse. Fuer `SlimmableContainer` (Solid/GOJIRA/JVM/Fender): `max_value` je
Submodell (z. B. 0,5 und 1,0) ist laut `NAM/container.cpp` eine **Auswahl-Schwelle** fuer das aktive
Submodell (Zeile 90: `if (val < _submodels[i].max_value) { active_index = i; ... }`), **keine**
Skalierung - schliesst eine Container-spezifische Erklaerung fuer den einheitlichen Faktor aus, was auch
dazu passt, dass FNDR PANO (kein Container) denselben Faktor zeigt.

## F. Sonicake-Eingangspfad: entscheidendes Experiment

Referenzsignal mit 0,31 vor-skaliert, durch unsere (unveraenderte) Inferenz fuer JVM410H Standard (das
Modell mit dem hoechsten `gain`, am ehesten echt saettigend) geschickt, direkt (ohne weitere Skalierung)
mit der offiziellen Ausgabe verglichen:

| | Korrelation | noetiger Nachskalar | NRMSE (nach Nachskalierung) |
|---|---|---|---|
| Eingang skaliert (×0,31) -> Inferenz | **0,854** | 0,294 | 0,519 |
| Voller Eingang -> Inferenz -> Ausgang ×0,31 | **0,99999997** | (bereits angewandt) | 4,67e-4 |

Eingangsskalierung um 0,31 veraendert die Ausgabe (Peak 0,7251 -> 0,6956, nur 4 % leiser statt 69 %) -
klarer Beleg fuer echte Nichtlinearitaet bei diesem Modell in diesem Pegelbereich. Waere der Faktor
eingangsseitig, muesste die eingangsskalierte Inferenz die offizielle Ausgabe direkt reproduzieren - tut
sie nicht (Korrelation faellt auf 0,854). **Das schliesst eine Eingangs-Vorskalierung (Hypothese F) fuer
JVM410H eindeutig aus** und bestaetigt zusammen mit den unveraenderten Kennlinien-Exponenten a+/a- aus
V4a, dass der Faktor auf der Ausgabeseite, nach der eigentlichen Modellinferenz, angewandt wird.

## G./H. Sonicake-Inferenz-Wrapper und Ausgabepfad (statische Analyse, Matribox.exe)

Disassembliert (Capstone, x86-64, rein lesend): `getNamOutput` (0x1400B4D10 bis 0x1400B6074, 934
Instruktionen im Kernbereich). Gefunden bei 0x1400B5A4E ein virtueller Aufruf
`call qword ptr [rax + 0x10]` mit Parametern, die zur `DSP::process(input, output, num_frames)`-Signatur
passen (this=rbx, output-aehnlicher Zeiger bei rsp+0x60, Frameanzahl in r9d) - passt zur erwarteten
NeuralAmpModelerCore-`process()`-Vtable-Position. Direkt danach (0x1400B5A90-0x1400B5B84): eine
4-fach entrollte Schleife, die jeden Sample aus dem Puffer bei `[rsp+0x60]` mit einem festen Register
`xmm7` multipliziert, in einen zweiten Puffer (`[r14]`) schreibt und dabei per `andps`/`comiss` das
laufende Maximum des Betrags verfolgt - strukturell **exakt** das Muster "Ausgabe skalieren und dabei den
Peak fuer die Log-Zeile mitzaehlen". Rueckverfolgung von `xmm7` fuehrte zu
`movss xmm7, dword ptr [rip+0x167352b]` (Zeile 610 im Dump, VA 0x1400B57ED) - eine feste
`.rdata`-Gleitkommakonstante. **Aufgeloester Wert: 420,0** - passt nicht zu 0,31/3,226 und auch nicht zu
den in der Aufgabe genannten Kandidaten (1/sqrt(10), -10 dB usw.).

## I. Erster abweichender Checkpoint

Aus den Experimenten (B, F) eindeutig belegt: die Divergenz liegt **zwischen** "rohe
NeuralAmpModelerCore-Ausgabe" (Checkpoint C) und "in die WAV geschriebene/an CloData weitergereichte
Ausgabe" (Checkpoint D/E) - **nicht** zwischen Referenzsignal und NAM-Eingang (A/B). Die exakte
Code-Adresse innerhalb dieses Intervalls wurde **nicht** zweifelsfrei gefunden: der wahrscheinlichste
Kandidat (die Multiplizier-Schleife bei 0x1400B5A90) ergab beim Rueckverfolgen des Multiplikators einen
Wert (420,0), der nicht zum gemessenen Faktor passt - vermutlich eine andere, im selben Funktionsabschnitt
liegende Grosse (z. B. eine Pegelmesser-/Ballistik-Konstante fuer die im Log ausgegebene "peak"-Zahl,
keine Signalskalierung), oder ein Fehler in der Rueckverfolgung (z. B. eine zwischenzeitliche
xmm7-Ueberschreibung ueber einen nicht erfassten Befehlstyp). Weiteres Nachverfolgen haette den fuer
diesen Meilenstein vertretbaren Aufwand deutlich ueberschritten.

## J. Root Cause

**NICHT bestaetigt auf Code-Ebene.** Empirisch jedoch sehr gut belegt (Abschnitte B, D, F): ein einziger,
modellunabhaengiger, auf der Ausgabeseite (nach der eigentlichen Inferenz) angewandter Faktor von
k approx 0,3100 (1/k approx 3,2256). Evidenzklasse **CORRELATED** (fuenf unabhaengige, konsistente
Messungen ohne Ausnahme; global vs. pro Modell praktisch identisch), nicht CONFIRMED (Quelle im
Sonicake-Binary nicht verifiziert).

## K. Generischer Fix

**Keiner implementiert.** Die Aufgabenstellung verlangt ausdruecklich einen "evidenz-gestuetzten" Fix nur
bei zweifelsfrei identifizierter Ursache; das ist hier nicht der Fall. Kein `output *= 0.31` und kein
aequivalenter Code wurde in `native/nam_bridge/`, `tool/nam_inference/` oder dem eingefrorenen Konverter
ergaenzt. Der Skalar wurde ausschliesslich in Wegwerf-Experimentskripten
(`native/nam_bridge/out/*.dart`, nicht Teil des Produkts, nicht importiert von Produktionscode) verwendet,
sowie in zwei neuen, klar als "Evidence, not a production rule" gekennzeichneten Tests
(`test/tool/nam_inference_test.dart`, Gruppe "V4b: output-scale characterization"), die die Messung
regressionssicher machen, ohne eine Korrekturregel zu behaupten.

## L./M. Offizieller-WAV- und CloData-Vergleich nach dem "Fix"

Kein Fix implementiert -> keine Aenderung gegenueber V4a. Werte siehe Abschnitte C/D oben (Experimente,
nicht Produktionsergebnis).

## N. Regression

Fuenf offizielle CloData-Goldens (`test/tool/matribox_nam_analysis_test.dart`), FFI/Nativ-Identitaet,
Determinismus und Architektur-Diversitaet (`test/tool/nam_inference_test.dart`) unveraendert grün (siehe
Testlauf-Protokoll in diesem Bericht).

## O./P. Tests/Analyze

Zwei neue, fokussierte Tests (Skalierungscharakterisierung, Eingangsskalierung-widerlegt) in der
bestehenden `test/tool/nam_inference_test.dart` ergaenzt, keine neue Testdatei. `dart analyze` ohne
Befunde.

## Q. Sicherheit

Ausschliesslich Read-only: `Matribox.exe` wurde nur mit Capstone statisch disassembliert, nicht gestartet,
nicht verandert, kein Patch, kein Hook. NO ADB - NO ANDROID - NO USB WRITE - NO MIDI WRITE - NO SYSEX WRITE
- NO NAM UPLOAD - NO PRESET WRITE - NO STORE.

## R. Verbleibende Unbekannte

Exakte Code-Adresse/Ursache des 0,31-Faktors in Matribox.exe; ob NeuralAmpModelerCore in der von Sonicake
gelinkten (vermutlich aelteren oder gepatchten) Version an dieser Stelle abweicht von unserem gepinnten
Stand; ob eine bit-exakte eigene Inferenz ueberhaupt technisch erreichbar ist, ohne genau denselben
Compiler/dieselbe Bibliotheksversion wie Sonicake zu verwenden.

## S. Android-Empfehlung

**HOLD**, unveraendert gegenueber V4a. Die Untersuchung hat das Verstaendnis stark verbessert (Ausschluss
von Eingangs-Skalierung, gain-Metadaten, head_scale, Container-max_value; Bestaetigung eines einzigen
globalen Ausgabe-Skalars), aber weder die exakte Ursache noch einen Weg zu Byte-Identitaet geliefert. Eine
Android-Portierung waere verfrueht, solange unklar ist, ob die CloData-Konvertierung mit der eigenen
Inferenz jemals nutzbar nah an die offizielle heran kommt.


# V4c - Laufzeitnachweis fuer die getNamOutput-Skalierung (Ergebnis: nicht erbracht)

Ausschliesslich Read-only-Disassemblierung (Capstone, statisch). Matribox.exe wurde zu keinem Zeitpunkt
gestartet, kein Emulator ausgefuehrt (Begruendung siehe Abschnitt B). Kein Android, kein Hardware-Zugriff,
kein Commit, kein Push, keine Aenderung an NeuralAmpModelerCore, keine Aenderung am eingefrorenen Konverter.

## Ergebnis (Kurz)

Der Kandidat aus V4b (Schleife bei 0x1400B5A90, Register xmm7) ist jetzt **aktiv widerlegt**: der exakt
zurueckverfolgte Konstantenwert ist 420,0 (nicht 0,31/3,226), eingebettet in eine Tabelle aehnlicher Werte
(407,0 / 420,0 / 442,0) - keine Gleitkomma-Gain-Konstante. Eine erschoepfende Suche **aller**
RIP-relativen Float-/Double-Konstanten in der gesamten Funktion `getNamOutput` (0x1400B4D10-0x1400B6074,
8 Treffer) ergab **keinen einzigen** Wert nahe 0,31 oder 3,226. **OUTCOME C: xmm7 ist nicht der gesuchte
Skalar; eine zuverlaessige Ausfuehrung des Pfads (Emulation) wurde fuer dieses Milestone nicht versucht**
(Begruendung unten). Kein `output *= 0.31` oder eine Approximation davon wurde hinzugefuegt.

## B. Emulator-Setup

Die in V1-V3 verwendete Unicorn-Emulationsumgebung lag im sitzungsgebundenen Scratchpad-Verzeichnis, das
zwischen Konversationsabschnitten geleert wurde; sie war zu Beginn von V4c **nicht mehr vorhanden** und
haette komplett neu aufgesetzt werden muessen. Wichtiger als das reine Fehlen der alten Skripte: jene
Emulation deckte ausschliesslich die **arithmetisch einfache CloData-Identifikationsengine**
(0x14019FCC0, Stufen A/B/C/L/F) ab - Gleitkomma-Schleifen, FFTs, Filter. Um tatsaechlich bis zur
Multiplikationsschleife in `getNamOutput` zu gelangen, muesste dagegen der **vollstaendige
NeuralAmpModelerCore-Forward-Pass** (Eigen-Matrixmultiplikationen, WaveNet-Faltungen, ueber 3.360.000
Samples) innerhalb des Emulators lauffaehig gemacht werden - eine um Groessenordnungen aufwendigere Aufgabe
als die vorherige Emulation, mit ungewissem Ausgang (Heap-Allokationen, C++-Exception-Handling,
CRT-Initialisierung, moeglicherweise SIMD-Intrinsics, die Unicorn nicht direkt unterstuetzt). Das haette den
fuer dieses Milestone vertretbaren Aufwand um ein Vielfaches ueberschritten. Diese Abwaegung wird hier
offen gelegt, statt eine unvollstaendige oder unzuverlaessige Emulation als "Beweis" auszugeben.

**Entscheidung:** Weiter mit vertiefter **statischer** Analyse (Capstone, wie V4b), um die V4b-Hypothese
gezielt zu pruefen und zu widerlegen/bestaetigen, statt eine Emulation zu erzwingen, deren Zuverlaessigkeit
nicht sichergestellt werden konnte.

## C./D. Ueberprueftes Codesegment und Instruktionen um 0x1400B5A90

Vollstaendige Neudisassemblierung von `getNamOutput` (0x1400B4D10 bis zum ersten `ret` bei 0x1400B6074,
4.452 Instruktionen). Praezise Bytepruefung der Instruktion bei 0x1400B57ED:
`f3 0f 10 3d 2b 35 67 01` = `movss xmm7, dword ptr [rip+0x167352b]`, 8 Byte lang, RIP-Ziel nach der
Instruktion (0x1400B57F5) + Verschiebung = **0x141728D20**. Umgebende Bytes an dieser Adresse:
`... 00 00 ca 43 | 00 80 cb 43 | 00 00 d2 43 | 00 00 dd 43 | 00 00 de 43 ...` = **407,0 / 420,0 / 442,0 / ...**
als aufeinanderfolgende Float32-Werte - eine Tabelle kleiner, ganzzahliger Werte, keine Gain-Konstante.

Zwischen dem Laden von xmm7 (Zeile 610 des Dumps) und der ersten Nutzung in der Multiplikationsschleife
(Zeile 774) gibt es **keine** weitere Zuweisung an xmm7 (vollstaendig durchsucht) - xmm7 traegt beim
Erreichen der Schleife also nachweislich den Wert 420,0.

## E./F. xmm7-Laufzeitwert

**Nicht als Laufzeitwert erfasst** (keine Ausfuehrung, siehe B), sondern statisch aus dem Speicherabbild
gelesen - fuer eine unveraenderliche `.rdata`-Konstante ist das aequivalent, da dieser Speicherbereich
read-only ist und zur Ladezeit nicht durch Relokationen ueberschrieben wird (keine Relokationseintraege in
diesem Adressbereich; ImageBase-Relokation aendert an dieser Stelle nichts, da es sich um Rohdaten, nicht
um Zeiger handelt).

- Rohbytes: `00 00 ca 43`
- Interpretation als Float32: **420,0**
- Interpretation als Float64 (an derselben Adresse, 8 Byte): kein sinnvoller Wert (die Tabelle ist
  Float32, kein Float64-Array; eine Float64-Interpretation ergaebe einen bedeutungslosen Bitmix zweier
  Float32-Eintraege)
- IEEE-754-Hex (Float32): `0x43CA0000`
- Dezimal: 420,0

## G./H. Ursprung und Formel

**Nicht rekonstruierbar mit den vorliegenden Mitteln.** xmm7 stammt aus einer festen Speicherstelle
(`0x141728D20`, Teil einer Tabelle mit den Nachbarwerten 407,0 und 442,0), nicht aus einer Berechnung
innerhalb dieser Funktion. Der Wert 420,0 passt zu **keinem** aus V4b bekannten Kandidaten (kein Bezug zu
Gain/Loudness-Metadaten, keinem dB-Wert, keinem 1/sqrt(10)-Faktor). Eine erschoepfende Suche aller
RIP-relativen Gleitkomma-Konstanten in der gesamten Funktion (8 Treffer: 0,0529; ein nicht auflösbarer
Zeiger-artefakt; 420,0; NaN-Artefakt; 140,42; NaN-Artefakt; zwei weitere Zeiger-Artefakte) ergab **keinen**
Wert nahe 0,31 oder 3,226. Schlussfolgerung: **entweder** wird der Faktor an anderer Stelle (in einer
aufgerufenen Funktion, in der WAV-Schreibroutine oder in der von Sonicake gelinkten
NeuralAmpModelerCore-Version) angewandt, **oder** er ist kein literales Konstantenliteral, sondern ein zur
Laufzeit berechneter Wert (z. B. aus einer Kopfzeile/Header-Struktur gelesen) - beides ohne echte Ausfuehrung
nicht weiter unterscheidbar.

## I. Drei-Modell-Vergleich

**Nicht durchgefuehrt** (setzt voraus, dass xmm7 tatsaechlich der gesuchte Skalar ist - das ist hiermit
widerlegt; ein Vergleich eines nachweislich falschen Kandidaten ueber drei Modelle liefert keine
zusaetzliche Erkenntnis).

## J./K./L./M. Multiplikations-Semantik, erster Divergenzpunkt, Vorher/Nachher-Vergleich

Entfaellt aus demselben Grund. Der in V4b/V4a bereits empirisch (nicht code-seitig) belegte erste
Divergenzpunkt - zwischen roher NeuralAmpModelerCore-Ausgabe und der final geschriebenen WAV, siehe V4b
Abschnitt I - bleibt unveraendert gueltig; er wurde in V4c nicht neu bewiesen, aber auch nicht entkraeftet.

## N. Generische Implementierung

**Keine.** Es gibt keinen bewiesenen Skalar/keine bewiesene Formel, die implementiert werden koennte.
Weiterhin **kein** `output *= 0.31` oder eine Naeherung davon in `native/nam_bridge/`,
`tool/nam_inference/` oder dem eingefrorenen Konverter.

## O./P. WAV- und CloData-Ergebnisse

Unveraendert gegenueber V4b (kein neuer Code, keine neue Ausfuehrung):

| Fall | CloData gleich/8232 |
|---|---|
| Solid Rhythm | 4680 |
| GOJIRA | 5302 |
| JVM410H Standard | 4666 |
| Fender AKG414 | 3961 |
| FNDR PANO | 4539 |

## Q./R. Tests, Analyze, Regression

Keine neuen Tests (kein bewiesenes Verhalten zu testen). Bestehende Tests nicht erneut ausgefuehrt, da
keine Code-Aenderung erfolgt ist, die eine Regression verursachen koennte; der Stand aus V4b
(24/24 offizielle-Goldens-Tests, 14/14 `nam_inference_test.dart`, `dart analyze` ohne Befunde) bleibt
gueltig.

## S. Sicherheit

Ausschliesslich statische Disassemblierung mit Capstone (Python), `Matribox.exe` nicht gestartet, kein
Prozess erzeugt, keine Emulation ausgefuehrt. NO ADB - NO ANDROID - NO USB - NO MIDI - NO SYSEX - NO NAM
UPLOAD - NO PRESET WRITE - NO STORE - keine Hardware.

## T. Verbleibende Unbekannte

Der exakte Ort und die Formel des ~0,31-Faktors sind weiterhin ungeklaert. Zwei realistische naechste
Schritte, beide mit erheblichem Aufwand: (1) eine vollstaendige, funktionsfaehige Emulation des
NeuralAmpModelerCore-Forward-Pass innerhalb von Unicorn (mehrere Tage Aufwand, ungewisser Erfolg), oder
(2) gezielte statische Suche in den von `getNamOutput` aufgerufenen Unterfunktionen (0x1401939b4,
0x140194ed0, 0x140106f40, 0x140195110, 0x1402dad50, 0x1402dacd0 - alle mehrfach aufgerufen, vermutlich
Puffer-/Kanal-Hilfsfunktionen) und in der WAV-Schreibroutine selbst, die in diesem Milestone aus
Zeitgruenden nicht mehr untersucht wurden.

## U. Android-Empfehlung

**HOLD**, unveraendert. Root Cause weiterhin nicht bewiesen; keine neue Erkenntnis, die eine andere
Empfehlung rechtfertigen wuerde.

# V4d – Eigenes, redistributierbares WyrmTone-Referenzsignal

Rein offline. Kein Android, kein Matribox-Zugriff, kein Commit. Der eingefrorene
`MatriboxNamCloDataConverter` wurde NICHT verändert; V1-V3 bleiben unangetastet.

## B. Eingefrorene Skalierungsfrage (V4b/V4c)

Bewusst zurückgestellt, nicht gelöst: ein empirischer Ausgabe-Skalar ~0,31 zwischen unserer rohen
NeuralAmpModelerCore-Inferenz und Sonicakes offizieller `nam_output_wav.wav` besteht bei allen fünf
untersuchten Fällen; die exakte Ursache ist UNKNOWN. Der Kandidat aus V4c (Register xmm7 bei der Schleife
um 0x1400B5A90) ist widerlegt: statisch verifiziert 420,0 / `0x43CA0000` - keine Gain-Konstante. Kein
`output *= 0.31` (oder eine Näherung) ist oder wird in Produktionscode verwendet. Das Thema kann später
wieder aufgenommen werden, ist für dieses Milestone aber irrelevant (siehe M).

## C./D. Signalabhängigkeiten des bestehenden Konverters (Code gelesen, `engine/stages.dart`)

| Stufe | Zeitfenster (hart codiert) | Was die Mathematik tatsächlich braucht | Einordnung |
|---|---|---|---|
| Delay-Suche | y[6,000s .. 6,0125s) | eine erkennbare Transiente in der Ausgabe, |y|>0,01, innerhalb 600 Samples; davor Ruhe erwartet | Mathematik GENERISCH; Fenster SIGNAL-LAYOUT-ABHÄNGIG |
| Stufe A (P/N/a+/a-) | x/y[0s..5s), 4.800-Sample-Blöcke | pro Block wachsender positiver/negativer Betragspeak über die volle Aussteuerung | Mathematik GENERISCH (Kurvenanpassung an beliebige Amplitudenrampe); Fenster/Blockgröße SIGNAL-LAYOUT-ABHÄNGIG |
| Stufe B | x/y[6s..21s), 15 s | breitbandige Energie fürs Kreuzspektrum (Sxy/Sxx) | Mathematik GENERISCH; Fenster SIGNAL-LAYOUT-ABHÄNGIG |
| Stufe C | x/y[23s..28s), 5 s | wie Stufe B | GENERISCH / SIGNAL-LAYOUT-ABHÄNGIG |
| Stufe L (3 Aufrufe) | [23s,5s) / [6s,15s) / [30s,20s) | wie Stufe B, iterativ verfeinert | GENERISCH / SIGNAL-LAYOUT-ABHÄNGIG |
| Stufe F | x/y[50s..70s), 20 s | wie Stufe B, plus 4.800-Sample-Faltung (beliebiges Signal faltbar) | GENERISCH / SIGNAL-LAYOUT-ABHÄNGIG |

**Ergebnis der Klassifizierung:** Keine Stufe liest einen hartcodierten Sonicake-Signalwert oder -Hash;
nirgends ist SONICAKE-SPEZIFISCHER Code gefunden worden. Jede Stufe ist in ihrer Mathematik GENERISCH
(funktioniert mit jedem Signal, das die geforderte Eigenschaft - Amplitudenrampe, erkennbare Transiente,
breitbandige Energie - im jeweiligen Zeitfenster besitzt). Die einzige echte Abhängigkeit ist
SIGNAL-LAYOUT: die exakten Zeitstempel/Längen sind im Code fixiert und müssen von JEDEM Eingangssignal
eingehalten werden, unabhängig von dessen Inhalt.

## E./F. WyrmTone-Referenzsignal - Design und Mathematik

`tool/nam_inference/wyrmtone_reference_signal.dart`, Klasse `WyrmToneReferenceSignal.generate()`. Kein
`dart:io`, kein Zufallszahlengenerator, kein Seed nötig - jede Sample ist eine geschlossene Formel:

- **0-5 s**: 110-Hz-Ton mit linear von 0 auf 1 wachsender Amplitude (`envelope(t) = t/5`) - liefert Stufe A
  pro 100-ms-Block einen wachsenden Betragspeak in beiden Polaritäten.
- **5-6 s**: Stille (Float32List ist nullinitialisiert) - erfüllt die Ruhe-Annahme der Latenzsuche.
- **6,000-6,005 s** (240 Samples): 1-kHz-Ton unter Hann-Fenster, Spitze 0,5 - eine sauber erkennbare
  Transiente weit innerhalb der 600-Sample-Suchfenster.
- **6,005-70 s** (64 s): Schroeder-Phasen-Multiton, 300 Töne logarithmisch 80 Hz-18 kHz, Phase
  `phase_k = -pi*k*(k+1)/300` (Schroeder 1970, minimiert den Crest-Faktor), Spitze 0,2 - breitbandig, dicht,
  deterministisch, ohne Zufallszahlengenerator.

Gesamtlänge exakt 70 s * 48.000 Hz = 3.360.000 Samples (die vom Konverter selbst ergänzten 600
Nullsamples kommen automatisch on top, wie bei der offiziellen Referenz).

## G. Determinismus

`WyrmToneReferenceSignal.generate()` zweimal aufgerufen: bytegleich. SHA-256 der erzeugten Samples fest in
`test/tool/wyrmtone_reference_signal_test.dart` verankert (`8d1ffb66...`). Kein Zufall, keine Systemzeit,
keine Plattform-API - nur `dart:math` `sin`/`cos`/`pow`, deren Ergebnis fuer feste Eingaben laut V3c bereits
als Windows-verifiziert bekannt ist (Cross-Plattform-Identität nicht neu belegt, siehe Bekannte Risiken).

## H. Fünf-Modell-Inferenzergebnis

Alle fünf Modelle mit dem WyrmTone-Signal durchlaufen (Solid, GOJIRA, JVM410H Standard, Fender AKG414, FNDR
PANO):

| Modell | Peak | RMS | NaN/Inf | Determinismus (2 unabhängige Läufe) |
|---|---|---|---|---|
| Solid | 0,942 | 0,205 | nein | bytegleich |
| GOJIRA | 0,791 | 0,173 | nein | bytegleich |
| JVM410H Standard | 0,645 | 0,151 | nein | bytegleich |
| Fender AKG414 | 0,924 | 0,102 | nein | bytegleich |
| FNDR PANO | 0,495 | 0,122 | nein | bytegleich |

Sinnvolle Dynamik und breitbandige Reaktion in allen fünf Fällen (keine Stille, keine Sättigung bei k=1,0
ausser den unten dokumentierten künstlichen k=2,0-Testfällen).

## I./J. Generische vs. Sonicake-spezifische Extraktionslogik / Schätzer

**Entscheidung: keine neue Parallelarchitektur.** Da die Mathematik jeder Stufe generisch ist (siehe C/D)
und unser Signal exakt dieselbe Zeitlayout-Struktur erfüllt, wird Pipeline B mit dem **unveränderten**
`MatriboxNamCloDataConverter`/`runEngine` betrieben - derselbe Code, andere Eingabe. Eine separate
`ReferenceSignalDefinition`/`NamIdentificationOutput`/`MatriboxCloDataEstimator`-Klassenhierarchie wurde
bewusst **nicht** angelegt: sie hätte den bestehenden, bereits gegen fünf offizielle Goldens verifizierten
Code duplizieren müssen, ohne einen mathematischen Unterschied zu haben - genau die Art von
Parallelarchitektur, die in diesem Projekt wiederholt vermieden werden soll. Das ist selbst ein Beleg fürs
Ergebnis von I: die Extraktionsmathematik hängt nicht an Sonicake, sondern nur an der Zeitstruktur.

## K. Kreuzsignal-Parametervergleich (Sonicake-Signal vs. WyrmTone-Signal, gleiches Modell)

| Modell | P/N/a+/a- (Sonicake-Signal, roh, aus V4a/V4b) | P/N/a+/a- (WyrmTone-Signal) |
|---|---|---|
| Solid | 0,2876 / 0,3688 / 751,84 / 370,96 | 0,8191 / 0,7335 / 35,52 / 55,03 |
| GOJIRA | 0,2605 / 0,3020 / 777,45 / 581,78 | 0,7347 / 0,6917 / 41,91 / 53,92 |
| JVM410H | 0,1806 / 0,1868 / 612,86 / 484,02 | 0,6433 / 0,6376 / 55,02 / 54,67 |
| Fender AKG414 | 0,7575 / 0,7261 / 1,17 / 1,19 | 0,8797 / 0,9239 / 1,30 / 1,25 |
| FNDR PANO | 0,2112 / 0,1990 / 3,81 / 5,12 | 0,4825 / 0,4951 / 11,55 / 11,58 |

Erwartungsgemäß **keine** Übereinstimmung in absoluten Werten - andere Anregung, anderer Arbeitspunkt,
andere Amplitude. Bemerkenswert: die relative Größenordnung von a+/a- bleibt je Modell in ähnlicher
Reihenfolge (Fender AKG414 klar am "linearsten", FNDR PANO moderat, Solid/GOJIRA/JVM deutlich
nichtlinearer) - ein plausibilitätsstützendes, aber kein quantitatives Ergebnis.

## L. FIR/Frequenzgang-Vergleich

FIR1 und FIR2 sind fuer alle fünf Modelle mit dem WyrmTone-Signal **endlich und stabil** (keine NaN/Inf,
keine Ausreisser) - die eingefrorene Stufe F (Energienormierung, Minimalphasen-Entwurf) verhält sich mit
einem strukturell anderen Breitbandsignal genauso robust wie mit dem Sonicake-Signal. Ein quantitativer
Frequenzgang-Abgleich (z. B. Kohärenz beider FIR-Sätze) wurde in diesem Milestone nicht durchgeführt - dafür
müsste zunächst eine gemeinsame Normierung (Pegel, Bezugsimpedanz) definiert werden, was über den
Recherche-Rahmen von V4d hinausgeht.

## M. Skalierungsempfindlichkeit (Antwort auf die Kernfrage von V4d)

Für jedes Modell wurde die eigene (unskalierte) Inferenzausgabe zusätzlich mit k=0,5 und k=2,0 durch den
unveränderten Konverter geschickt (nur intern, kein Sonicake-Bezug):

| Modell | P bei k=0,5 | P bei k=1,0 | P bei k=2,0 | a+ bei k=0,5 | a+ bei k=1,0 | a+ bei k=2,0 |
|---|---|---|---|---|---|---|
| Solid | 0,4095 | 0,8191 | 1,0104* | 35,516 | 35,515 | 61,372* |
| GOJIRA | 0,3674 | 0,7347 | 1,0057* | 41,917 | 41,915 | 61,305* |
| JVM410H | 0,3217 | 0,6433 | 0,9963* | 55,017 | 55,017 | 61,389* |
| Fender AKG414 | 0,4398 | 0,8797 | 0,9995* | 1,297 | 1,297 | 2,407* |
| FNDR PANO | 0,2413 | 0,4825 | 0,9651* | 11,552 | 11,552 | 11,553 |

(*) bei k=2,0 stösst die 16-Bit-WAV-Kodierung unseres Testskripts an ihre ±1,0-Kappungsgrenze (reines
Artefakt des Testaufbaus, nicht der Mathematik) - deshalb weichen P und a+ bei k=2,0 vom erwarteten
linearen Verhalten ab.

**Antwort:** P und N skalieren im unbeschnittenen Bereich (k=0,5 zu k=1,0) exakt proportional zu k; a+/a-
sind in diesem Bereich praktisch **invariant** (Solid: 35,516 vs. 35,515). Die Extraktionsmathematik ist
also - solange keine Kappung eintritt - **äquivalent zu einer globalen Ausgabeskalierung**: sie berechnet
für jede beliebige tatsächliche Ausgabeamplitude die dazu passenden Kennlinienparameter, ohne dass ein
externer Referenzwert nötig wäre. Damit ist der ungeklärte Sonicake-Faktor **mathematisch nicht
erforderlich** für Pipeline B - er ist ausschließlich eine Kompatibilitätsfrage fuer den Abgleich mit
Sonicakes absoluten Zahlen (Pipeline A), nicht ein Bestandteil einer korrekten Verstärker-Charakterisierung.

## N. Experimentelle CloData

**Gerechtfertigt und erzeugt** (siehe K/L/M: die Mathematik verhält sich mit dem neuen Signal in jeder
Hinsicht robust und sinnvoll). Für alle fünf Modelle wurde eine vollständige, 8.232 Byte lange,
strukturell gültige CloData erzeugt - klar markiert **EXPERIMENTAL - NOT HARDWARE VALIDATED**, nur in
Testskripten (`native/nam_bridge/out/pipeline_b_check.dart`, nicht Teil des Produkts), niemals an ein Gerät
gesendet. Struktur: Header/Name-Feld korrekt (256 Bytes wie beim eingefrorenen Konverter), vier
Nichtlinearitäts-Parameter finit (siehe K), FIR1 (128) und FIR2 (1.024 von 2.048) durchgehend finit,
Partitionsfelder und Endfüllung identisch zur bestehenden Struktur (derselbe Konverter-Code, ungeändert).
Checksummen-/Frame-Kompatibilität mit dem Transportprotokoll ist durch die reine Byte-Struktur (8.232 Byte,
identisches Layout) formal gegeben, wurde aber - wie gefordert - **nicht** an Hardware getestet.

## O. Performance

| Phase | Solid (Slimmable) | FNDR PANO (WaveNet) |
|---|---|---|
| Signalerzeugung | << 1 s (einmalig, nicht separat gemessen, geschätzt aus Gesamtlaufzeit) | s. o. |
| NAM-Laden | 33 ms | 19 ms |
| Inferenz (70 s Signal) | ~13 s (aus Gesamtlaufzeit abgeleitet) | ~13 s |
| CloData-Konvertierung | ~11,7 s | ~9,6 s |
| Gesamt (1 Inferenz + 1 CloData) | ~23,3 s (Skript maß 2 Inferenzen + 4 Konversionen zusammen) | ~23,6 s |

Grössenordnung deckt sich mit V4a (Sonicake-Signal); kein signifikanter Unterschied durch das neue Signal
zu erwarten, da Inferenz- und CloData-Rechenzeit primär von der Signallänge (70 s), nicht vom Inhalt
abhängen.

## P. Tests

Neue, fokussierte Datei `test/tool/wyrmtone_reference_signal_test.dart` (plattformunabhängig, kein
dart:ffi): exakte Länge/Determinismus, fester SHA-256-Hash, keine NaN/Inf, monoton wachsender
Block-Peak 0-5 s, Stille 5-6 s, Transiente ab 6,000 s im Suchfenster, breitbandige Energie **rund um** vier
Referenzfrequenzen (Bandsumme statt Einzelbin, um Picket-Fence-Effekte des diskreten Multitons zu
vermeiden), WAV-Export-Rundlauf, sowie der kritische Test: **der Generator referenziert im Code (nicht in
Kommentaren) an keiner Stelle Sonicake, `nam_input_wav`, `HTCache`, `48000.wav`, `wyrmtone-captures` oder
`Program Files`, und importiert kein `dart:io`.**

## Q. Analyze/Regression

`dart analyze tool/nam_inference test/tool`: keine Befunde. Bestehende fünf offizielle CloData-Goldens,
FFI/Nativ-Identität und Determinismus wurden in diesem Milestone nicht erneut ausgeführt, da kein
bestehender Code verändert wurde (nur neue Dateien ergänzt); der V4c-Stand bleibt gültig.

## R. Lizenz/Provenienz

`WyrmToneReferenceSignal` liest keine Datei, importiert kein `dart:io`, enthält keine Sonicake-Werte -
verifiziert durch den Code-Test in P. Alle Konstanten (Frequenzen, Phasenformel, Amplituden) sind im
Quelltext dokumentiert und stammen aus Standard-DSP-Lehrbuchformeln (Schroeder 1970 fuer die
Multiton-Phasen), nicht aus einer Aufnahme.

## S. Sicherheit

NO ADB - NO ANDROID INSTALL - NO USB WRITE - NO MIDI WRITE - NO SYSEX WRITE - NO NAM UPLOAD - NO IR UPLOAD
- NO PRESET WRITE - NO STORE - NO MATRIBOX HARDWARE ACCESS. Alle erzeugten CloData bleiben lokal
(`native/nam_bridge/out/`, per `.gitignore` ausgeschlossen).

## T. Verbleibende Risiken

Cross-Plattform-Identität von `sin`/`cos` (Windows vs. Android) fuer das neue Signal nicht separat erneut
verifiziert (nur die UCRT-/SVML-Bausteine der Engine selbst waren in V3c geprüft, nicht `dart:math`s
`sin`/`cos` auf allen Zielplattformen). Kein quantitativer Frequenzgang-Vergleich zwischen Pipeline A und
B. Der ~0,31-Sonicake-Faktor bleibt ungeklärt (bewusst zurückgestellt). Die 16-Bit-Kappung im Testskript
bei k=2,0 ist ein Artefakt des Testaufbaus, nicht der Produktkette - fuer eine echte Produktkette müsste die
Quantisierung sauber gegen Übersteuerung abgesichert werden (z. B. durch Pegelvorschau vor dem Rendern).

## U. Android-Empfehlung

**HOLD**, unverändert - dieses Milestone war Signal-Forschung, kein Android-Fortschritt.

## V. Hardware-Validierungsempfehlung

**HOLD.** Die experimentelle CloData ist strukturell gültig, aber nicht hardwaregeprüft und beruht auf
einer noch ungeklärten Skalierungsfrage gegenüber der offiziellen Sonicake-Kette (Pipeline A). Vor jeder
Hardware-Validierung wäre mindestens ein quantitativer Vergleich der resultierenden Klangcharakteristik
(nicht nur Byte-Struktur) nötig.

# V4e – Pipeline A vs Pipeline B: Verstärkercharakteristik-Validierung

Rein offline. Kein Android, kein Matribox-Zugriff, kein Commit. Der eingefrorene Konverter und die
Pipeline-A-Goldens wurden nicht veraendert.

## Ergebnis (Kurz)

**Pipeline B produziert strukturell gueltige CloData (alle fuenf Modelle: 8.232 Byte, alle Floats finit,
deterministisch, Transport-Encoder + Checksummen validieren offline fehlerfrei). Die repraesentierte
Verstaerkercharakteristik stimmt jedoch bei vier von fuenf Modellen NICHT bzw. nur schwach mit Pipeline A
ueberein** (niedrige bis negative Korrelation, grosse FIR-Differenzen, deutlich unterschiedliche
Kennlinien-Exponenten a+/a-). Nur FNDR PANO (WaveNet 0.5.4/Tanh) zeigt eine **teilweise** Uebereinstimmung.
Auf dieser Evidenzbasis wird **keine** Hardware-Validierung empfohlen.

## B. Unabhaengiges Probesignal

`tool/nam_inference/wyrmtone_validation_probe.dart`, `WyrmToneValidationProbe.generate()` - eine dritte,
eigenstaendige Konstruktion (logarithmischer Sinus-Sweep statt Schroeder-Multiton, andere Burst-Frequenz/
-Laenge, nicht-monotone +/- Huellkurve statt linearer Rampe), ~14,8 s: Einheitsimpuls, Impuls bei niedrigem
Pegel, 2-kHz-Hann-Burst, drei log-Sweeps 20 Hz-20 kHz bei 0,3/0,05/0,9 Spitze, eine 150-Hz-Huellkurve mit
vollem +/- Zyklus. Kein Bezug zu Sonicake oder zum WyrmTone-Identifikationssignal (durch Quelltest
verifiziert).

## C. Modelle/Evidenz

Alle fuenf Referenzen mit ausreichender Evidenz fuer beide Pipelines verfuegbar und verglichen: Solid
Rhythm, GOJIRA, JVM410H Standard, Fender Super Reverb AKG414, FNDR PANO.

## D./E. Parameter- und Kennlinienvergleich

| Modell | P/N/a+/a- Pipeline A | P/N/a+/a- Pipeline B | Kennlinien-NRMSE (gain-matched) |
|---|---|---|---|
| Solid | 0,0892/0,1143/751,87/374,74 | 0,8191/0,7336/35,51/55,03 | 0,210 |
| GOJIRA | 0,0808/0,0936/777,74/581,73 | 0,7347/0,6917/41,91/53,92 | 0,154 |
| JVM410H | 0,0560/0,0579/612,89/487,63 | 0,6433/0,6376/55,02/54,67 | 0,103 |
| Fender AKG414 | 0,2348/0,2251/1,165/1,194 | 0,8797/0,9239/1,297/1,251 | **0,028** |
| FNDR PANO | 0,0655/0,0617/3,813/5,142 | 0,4825/0,4950/11,55/11,58 | 0,179 |

a+/a- (Kruemmung der Kennlinie) unterscheiden sich bei Solid/GOJIRA/JVM **um den Faktor 10-20**, nicht nur
im Rahmen einer Skalierung - das ist keine reine Amplitudenfrage (siehe M). Nur bei Fender AKG414 (ohnehin
der linearste Fall, a+/a- nahe 1) ist die Kennlinie nach Gain-Anpassung nahe (2,8 % NRMSE); bei den anderen
vier liegt die Kennlinienform-Abweichung selbst nach optimaler Skalierung bei 10-21 %.

## F./G./H. FIR- und Frequenzgangvergleich

| Modell | FIR1 ΔdB (max/mean/rms) | FIR2 ΔdB (max/mean/rms) | Kombiniert, Kleinsignal (max/mean/rms) |
|---|---|---|---|
| Solid | 30,5 / 13,5 / 17,3 | 28,3 / 12,7 / 14,7 | 34,8 / 15,1 / 18,5 |
| GOJIRA | 25,6 / 12,7 / 15,0 | 30,7 / 13,3 / 15,4 | 40,6 / 18,1 / 21,5 |
| JVM410H | 20,9 / 7,6 / 10,0 | 24,6 / 10,0 / 11,6 | 26,4 / 17,3 / 18,3 |
| Fender AKG414 | 21,4 / 11,7 / 13,1 | 29,1 / 19,6 / 20,9 | 14,8 / 6,0 / 7,4 |
| FNDR PANO | **10,7 / 6,1 / 6,6** | 28,3 / 13,2 / 14,4 | 17,0 / 9,6 / 10,5 |

Vollstaendige Einzelfrequenz-Tabelle fuer Solid (repraesentativ, keine Mittelwertbildung versteckt Ausreisser):

| Hz | A (dB) | B (dB) | Δ (dB) |
|---|---|---|---|
| 20 | −19,67 | −18,72 | −0,94 |
| 40 | −13,73 | −12,81 | −0,92 |
| 80 | −8,04 | −7,20 | −0,84 |
| 100 | −6,34 | −5,58 | −0,77 |
| 200 | −1,83 | −2,29 | 0,46 |
| 400 | 5,59 | −6,09 | **11,69** |
| 800 | 15,17 | −3,09 | **18,26** |
| 1.000 | 16,78 | −0,68 | **17,45** |
| 2.000 | 13,04 | 2,18 | **10,86** |
| 4.000 | −2,39 | 2,33 | −4,72 |
| 6.000 | −16,32 | 2,85 | **−19,17** |
| 8.000 | −17,04 | −0,20 | **−16,84** |
| 10.000 | −27,77 | 2,78 | **−30,55** |
| 12.000 | −19,67 | 3,67 | **−23,34** |
| 16.000 | −29,35 | 0,07 | **−29,42** |
| 20.000 | −31,29 | −1,65 | **−29,64** |

Bei tiefen Frequenzen (20-200 Hz) ist die Abweichung moderat (< 1 dB); ab 400 Hz weicht FIR1 um 10-30 dB
ab - FIR1(B) ist im Mittel- und Hochtonbereich deutlich flacher/anders geformt als FIR1(A). Dieses Muster
(gute Uebereinstimmung bei tiefen Frequenzen, grosse Abweichung ab dem mittleren Bereich) zeigt sich bei
allen fuenf Modellen in aehnlicher Form.

## I. Transientenvergleich

| Modell | Einheitsimpuls Korr. | Impuls (niedrig) Korr. | Burst Korr. |
|---|---|---|---|
| Solid | 0,016 | 0,110 | −0,117 |
| GOJIRA | 0,015 | 0,025 | −0,060 |
| JVM410H | 0,405 | 0,501 | 0,712 |
| Fender AKG414 | 0,107 | 0,361 | 0,261 |
| FNDR PANO | **0,648** | **0,790** | **0,599** |

Solid/GOJIRA praktisch unkorreliert bis leicht negativ korreliert bei transienten Ereignissen - die
FIR/Kennlinien-Unterschiede wirken sich hier direkt und deutlich aus. FNDR PANO durchgehend am besten.

## J./K. Probesignal-Vergleich (RAW und Gain-Matched)

| Modell | Korr. (raw) | NRMSE (raw) | k (Gain-Match) | NRMSE (gain-matched) | Crest A/B |
|---|---|---|---|---|---|
| Solid | 0,304 | 1,579 | 0,194 | 0,953 | 3,37 / 5,88 |
| GOJIRA | 0,336 | 1,528 | 0,218 | 0,942 | 3,28 / 6,78 |
| JVM410H | 0,586 | 1,126 | 0,429 | 0,810 | 4,28 / 5,10 |
| Fender AKG414 | **0,060** | 2,403 | 0,027 | 0,998 | 5,25 / 7,08 |
| FNDR PANO | **0,892** | 1,733 | 0,348 | **0,451** | 5,81 / 6,06 |

DC-Offset in allen Faellen vernachlaessigbar (< 3·10⁻⁵). Crest-Faktor von Pipeline B durchgehend hoeher als
A - B ist "spitziger"/weniger komprimiert bei diesem Probesignal. Selbst nach optimaler Gain-Anpassung
bleibt die normalisierte Fehlerenergie bei vier von fuenf Modellen ueber 80 % (!) - nur FNDR PANO kommt auf
45 %.

## L. Ergebnistabelle pro Modell (geforderte Kompaktuebersicht)

| Modell | Latenz A/B | Kennlinien-NRMSE (gain-matched) | FIR-RMS-Fehler (Mittel FIR1+FIR2) | Max. Frequenzgang-Δ | Probe-Korr. (raw) | Probe-Korr. (gain-matched) | Probe-NRMSE (raw) | Probe-NRMSE (gain-matched) | CloData strukturell gueltig |
|---|---|---|---|---|---|---|---|---|---|
| Solid | - / - (s. u.) | 0,210 | 16,0 dB | 34,8 dB | 0,304 | 0,304 | 1,579 | 0,953 | JA |
| GOJIRA | - / - | 0,154 | 15,2 dB | 40,6 dB | 0,336 | 0,336 | 1,528 | 0,942 | JA |
| JVM410H | - / - | 0,103 | 10,8 dB | 26,4 dB | 0,586 | 0,586 | 1,126 | 0,810 | JA |
| Fender AKG414 | - / - | 0,028 | 17,0 dB | 29,1 dB | 0,060 | 0,060 | 2,403 | 0,998 | JA |
| FNDR PANO | - / - | 0,179 | 10,5 dB | 28,3 dB | 0,892 | 0,892 | 1,733 | 0,451 | JA |

(Korrelation ist skaleninvariant, raw = gain-matched; das ist mathematisch erwartet, nicht neu gemessen.
Latenzwerte A/B liegen aus V4a/V4d vor: A ∈ {28,0,67,6,10}, B war fuer das WyrmTone-Signal nicht separat neu
gemessen und wird hier nicht behauptet - siehe Bekannte Risiken.)

## M. CloData-Strukturvalidität von Pipeline B

Fuer alle fuenf Modelle: Groesse exakt 8.232 Byte, alle Parameter- und FIR-Floats finit, zwei unabhaengige
Konvertierungen bytegleich (deterministisch), der bestehende, unveraenderte Transport-Encoder
(`encodeCloneTransfer`, Slot 0x04) erzeugt daraus Bloecke, die per `reconstructCloneTransfer` **ohne jeden
Checksummen- oder Formatfehler** wieder zur identischen CloData zusammengesetzt werden. **Rein strukturell:
JA, gueltig.** (Fragen zur inhaltlichen/klanglichen Gueltigkeit siehe D-L.)

## N. Performance (Pipeline B, pro Modell)

Aus dem Vergleichslauf (inklusive zweier CloData-Konvertierungen fuer den Determinismus-Test):

| Phase | typische Dauer |
|---|---|
| NAM laden | 19-33 ms |
| Inferenz (WyrmTone-Signal, 70 s) | ~13 s (Groessenordnung aus V4a/V4d, hier nicht einzeln erneut gestoppt) |
| Parameter-/FIR-Schaetzung (`runEngine`, 48-kHz-Domaene) | ~17 s |
| CloData-Erzeugung (inkl. Resampling) | ~10-12 s |
| Gesamt (eine vollstaendige Pipeline-B-Konvertierung) | ~30-40 s |

Groessenordnung unveraendert gegenueber V4a/V4d - fuer eine Offline-Konvertierung weiterhin unproblematisch.

## O. Tests

Neue, fokussierte Datei `test/tool/wyrmtone_validation_probe_test.dart` (plattformunabhaengig): Probe
deterministisch/endlich/korrekte Laenge, Impulspositionen exakt, drei Sweep-Pegel treffen ihre Zielamplitude,
kein Bezug zu Sonicake oder zum Identifikationssignal (Code-Test wie in V4d), sowie Sanity-Tests fuer den
neuen `evaluateAmp`/`evaluateWaveshaperAt`-Evaluator (endliche, deterministische, nicht explodierende
Ausgabe; Monotonie der positiven Kennlinienseite für ein plausibles Beispielmodell).

## P. Analyze/Regression

`dart analyze tool/nam_inference test/tool`: keine Befunde. Bestehende Tests (fuenf offizielle CloData-
Goldens, FFI/Nativ-Identitaet, V4d-Referenzsignal-Tests) in diesem Milestone nicht erneut ausgefuehrt, da
kein bestehender Code veraendert wurde (nur neue Dateien): der V4d-Stand bleibt gueltig.

## Q. Ableitung von Abnahmeschwellen (aus den gemessenen Daten, nicht erfunden)

Aus der beobachteten Modell-zu-Modell-Streuung: selbst innerhalb Pipeline A variieren a+/a- um den Faktor
~200 zwischen Modellen (1,17 bei Fender bis 778 bei GOJIRA) - absolute Werte sind also ohnehin nicht
directly vergleichbar; **relative/gain-matched Metriken sind die einzig sinnvolle Basis.**

- **RESEARCH ACCEPTANCE** (fuer weitere Untersuchung, nicht fuer Hardware): Probe-Korrelation (raw) > 0,5
  UND Kennlinien-NRMSE (gain-matched) < 0,25. Erfuellt nur von: JVM410H (Korr. 0,586, aber Kennlinie 0,103 -
  erfuellt), FNDR PANO (Korr. 0,892, Kennlinie 0,179 - erfuellt). Solid/GOJIRA/Fender erfuellen die
  Korrelationsschwelle nicht.
- **PRODUCTION ACCEPTANCE** (Voraussetzung fuer eine kontrollierte Hardware-Pruefung): Probe-Korrelation
  (gain-matched) > 0,9 UND Probe-NRMSE (gain-matched) < 0,25 UND max. Frequenzgang-Δ < 10 dB UND
  Transienten-Korrelation > 0,7 fuer alle drei Transiententypen. **Kein einziges Modell erfuellt diese
  Schwelle** (selbst FNDR PANO: NRMSE 0,451 > 0,25, max. Δ 28,3 dB > 10 dB).

Diese Schwellen sind bewusst aus der Datenverteilung abgeleitet (nicht vorab erfunden) und explizit
konservativ fuer PRODUCTION, da eine falsch charakterisierte Kennlinie auf echter Hardware zu unerwartetem
Klangverhalten fuehren wuerde.

## R. Sicherheit

NO ADB - NO ANDROID - NO USB WRITE - NO MIDI WRITE - NO SYSEX WRITE - NO NAM UPLOAD - NO IR UPLOAD - NO
PRESET WRITE - NO STORE - NO MATRIBOX HARDWARE ACCESS. Alle Vergleichsdaten bleiben lokal
(`native/nam_bridge/out/`, per `.gitignore` ausgeschlossen).

## S. Verbleibende Risiken

Die grosse Kennlinien-/FIR-Abweichung ist noch nicht ursachlich geklaert - denkbare Erklaerungen (nicht
geprueft): das WyrmTone-Signal regt die Nichtlinearitaet anders an als Sonicakes Signal (andere
Ramp-Form/-Dauer fuehrt zu anderer eP/eN-Blockverteilung in Stufe A, was den Kurvenfit dominiert, obwohl
a+/a- eigentlich eine Eigenschaft des Verstaerkers und nicht des Anregungssignals sein sollten); die
Multiton-Breitbandsektion regt Stufe B/C/L/F anders an als Sonicakes (unbekannte) Breitbandsektion; die
Modelle koennten bei den in Sonicakes Signal erreichten Pegeln in einem anderen Betriebsbereich arbeiten als
bei WyrmTones Pegeln. Latenzwerte A/B wurden in diesem Milestone nicht systematisch neu vermessen und
verglichen (in der Kompakttabelle als offen markiert). Kein Hoertest, keine subjektive Bewertung
vorgenommen oder behauptet.

## T. Hardware-Empfehlung

**HOLD.** Vier von fuenf Modellen erfuellen nicht einmal die lockere Forschungs-Schwelle; kein Modell
erfuellt die Produktions-Schwelle. Eine Hardware-Pruefung auf dieser Basis waere nicht durch Evidenz
gedeckt.

## U. Android-Empfehlung

**HOLD**, unveraendert - dieselbe Begruendung wie beim Hardware-Befund.

## Drei Kernfragen (getrennt beantwortet)

1. **Erzeugt Pipeline B strukturell gueltige Matribox-CloData?** **JA** - fuer alle fuenf Modelle, mit
   vollstaendiger Transport-/Checksummen-Validierung offline bestaetigt.
2. **Repraesentiert Pipeline B annaehernd dieselbe Verstaerkercharakteristik wie Pipeline A?**
   **UEBERWIEGEND NEIN** - vier von fuenf Modellen zeigen schwache bis keine Uebereinstimmung (niedrige
   Probe-Korrelation, grosse FIR-/Kennlinienabweichung); FNDR PANO zeigt eine **teilweise** Uebereinstimmung
   (beste Korrelation und Transientenverhalten, aber immer noch weit von der Produktions-Schwelle entfernt).
3. **Reicht die Evidenz fuer EINE kontrollierte Hardware-Pruefung auf Clone 5?** **NEIN**, aktuell nicht -
   siehe Q/T.

## V4f — Stage-A Excitation / Nonlinear-Kennlinien-Identifikation

Ausgangshypothese (aus V4e): Stage A ist ein nichtlinearer Least-Squares-Fit
(`P(1-e^{-a+x})` / `N(e^{a-x}-1)`), dessen Ergebnis stark davon abhaengt,
*welche* x-Werte die Anregung im 0-5s-Fenster tatsaechlich abtastet - nicht
nur vom Endverstaerker. Ziel: das isoliert und kontrolliert pruefen, ohne
NeuralAmpModelerCore/FFI, den eingefrorenen Konverter, FIR-Stufen B/C/L/F,
Transport oder den CloData-Encoder anzufassen.

### A. Harness (nur Stage A, read-only)

- `tool/nam_inference/stage_a_excitation.dart`: 8 parametrisierte,
  generische Anregungsfamilien (A-H: linearer/exponentieller/dreieckiger/
  langsamer-Sinus-Umhuellter-Einton, gestufter Sweep, getrennte Pos/Neg-
  Haelften, Multisine-Rampe, breitbandiges gestuftes Gain) - reine Mathematik,
  kein Bezug zu Sonicake oder einem bestimmten Golden-Modell.
- `tool/nam_inference/stage_a_harness.dart`: `runStageAExperiment()` ruft
  die *unveraenderte* `NamInferenceEngine` und die *unveraenderte, eingefrorene*
  `stageA()` aus `engine/stages.dart` auf; `stageADiagnostics()` ist ein
  read-only Spiegel der eP/eN-Blockschwellen-Berechnung, rein zur
  Protokollierung (aendert nichts an `stageA()`s Rueckgabewert).
- `tool/nam_inference/stage_a_distance.dart`: Distanzmetrik zwischen einem
  Kandidaten-Fit und einem Pipeline-A-Zielwert: P-/N-/a+-/a--Fehler
  (relativ) plus - als primaere semantische Metrik - der mittlere Fehler der
  dichten Kennlinie (401 Punkte, x in [-1,1], exakt dieselbe Formel, die
  `stageA()`s Fit optimiert), getrennt fuer positive/negative Seite.
- Tests: `test/tool/stage_a_excitation_test.dart` (21 Faelle: Determinismus/
  Endlichkeit aller 8 Familien, Distanzmetrik = 0 bei Identitaet, monotone
  Verschlechterung bei groesserem a+/a--Fehler, Kennlinienformel-Check,
  Reproduzierbarkeit, Verbot Sonicake-/Modell-spezifischer Konstanten in den
  Generatoren, struktureller Holdout-Isolations-Test: TRAIN/DEV-Sweeps
  duerfen GOJIRA nicht in ihrer `trainModels`-Liste fuehren).

### B. Pipeline-A-Zielwerte (P/N/a+/a-, eP/eN)

`native/nam_bridge/out/v4f_stage_a_targets.dart` reproduziert exakt
`runEngine()`s Vorverarbeitung (Padding auf `engineLength`, `detrend(yRaw)`,
`findDelay()`, dann `stageA(x[0..5s), y[d..d+5s))`) - Ergebnisse stimmen
bitgenau mit V4e's `pipeline_ab_compare.log` ueberein (Cross-Check bestanden)
und ergaenzen eP/eN, die dort nicht protokolliert waren:

| Modell | P | N | a+ | a- | eP | eN | delay |
|---|---|---|---|---|---|---|---|
| Solid | 0.08917 | 0.11430 | 751.87 | 374.74 | 1 | 1 | 28 |
| GOJIRA (Holdout) | 0.08076 | 0.09362 | 777.74 | 581.73 | 1 | 1 | 0 |
| JVM410H | 0.05599 | 0.05793 | 612.89 | 487.63 | 1 | 1 | 67 |
| Fender AKG414 | 0.23484 | 0.22509 | 1.165 | 1.194 | 43 | 43 | 6 |
| FNDR PANO | 0.06546 | 0.06170 | 3.813 | 5.142 | 30 | 26 | 10 |

Wichtiger Befund: bei den drei High-Gain-Modellen (Solid/GOJIRA/JVM410H)
erreicht Sonicakes Anregung bereits im *ersten* 100-ms-Block 50% des
spaeteren Peaks (eP=eN=1) - die Kennlinie dieser Modelle wird effektiv aus
sehr wenigen unabhaengigen Amplitudenstuetzstellen gefittet, waehrend die
beiden Low-Gain-Modelle (Fender, FNDR PANO) erst nach 2.6-4.3s saettigen und
damit den vollen Rampenverlauf tatsaechlich abtasten.

### C-G. Sweep Runde 1 (TRAIN/DEV, vor der grossen Ausfuehrung geplant)

Plan vor Ausfuehrung: 25 Anregungsdefinitionen x 4 Trainingsmodelle (Solid,
JVM410H, Fender, FNDR PANO; GOJIRA bewusst ausgeschlossen) = 100 Experimente,
564.4s Audio insgesamt. Vor dem Sweep wurde der reale Durchsatz mit einem
Testlauf gemessen (375ms fuer 5s Audio = 640 Samples/ms) und daraus die
Laufzeit auf 42.3s geschaetzt (reines Inferenz-Timing; stageA()-Kosten
vernachlaessigbar). Tatsaechliche Laufzeit: **49.4s fuer 100 Experimente**
(`native/nam_bridge/out/v4f_stage_a_sweep.dart`,
`v4f_stage_a_sweep_results.json`).

Familien-Ranking (mittlerer Score ueber alle Varianten & 4 Trainingsmodelle,
niedriger = besser):

| Familie | mittlerer Score | n |
|---|---|---|
| G-multisine | **4.37** | 4 |
| H-broadband | 7.72 | 4 |
| C-freq (Einton, Frequenz variiert) | 8.63 | 24 |
| F-stepped | 9.21 | 4 |
| A-shape (110Hz, Rampenform variiert) | 9.51 | 16 |
| E-asym | 10.62 | 4 |
| B-duration (110Hz, Dauer variiert) | 15.12 | 16 |
| D-peak (110Hz, Peak-Pegel variiert) | 28.73 | 28 |

Bester Einzelkandidat: Multisine aus 5 Toenen (80/200/440/1000/2000Hz,
gleiche Amplitude, feste Phasen), lineare 0->1-Umhuellende, 5s Dauer, Peak
1.0 - Mittelwert-Score 4.37, deutlich vor dem naechstbesten Einzelton bei
2000Hz (6.37) und weit vor V1s eigenem 110Hz-Einton (8.58).

D-peak (sehr niedriger Anregungspegel) ist mit Abstand am schlechtesten:
bei sehr kleinem Peak (0.05) wird `accx(eP)`/`accx(eN)` extrem klein, der
Fit wird numerisch instabil und extrapoliert stark (Score bis 350) - ein
eigenstaendiger, wichtiger Befund unabhaengig von der Ausgangshypothese.

### H. Sweep Runde 2 (Verfeinerung um den Runde-1-Sieger)

52 weitere Experimente (13 Varianten x 4 Modelle), 32.5s Laufzeit
(`v4f_stage_a_sweep2.dart`): breiteres Band (8 Toene bis 6kHz), Mitte/
Hochlage (ohne 80Hz), Dauer 2/10/20s, Peak 0.3/0.5/0.7, drei alternative
Umhuellungsformen. Ergebnis: der Runde-1-Kandidat (5 Toene, linear, 5s,
Peak 1.0) bleibt nahe optimal (Score 4.37); eine Variante mit
langsamer-Sinus-Umhuellung ist minimal besser (4.27, ~2%), wird aber wegen
hoeherer Komplexitaet und marginalem Vorteil nicht gewaehlt. Breiteres Band,
laengere Dauer und niedrigerer Peak verschlechtern das Ergebnis durchweg
(Score bis 40.7 bzw. 23.4) - bestaetigt D-peak/B-duration aus Runde 1.

### I. Variablen-Klassifikation (basierend auf gemessenem Einfluss)

| Variable | Einfluss | Befund |
|---|---|---|
| Frequenzinhalt (Einton vs. Multiton) | **HOCH** | Multiton (5 Toene) halbiert den mittleren Score gegenueber jedem Einton |
| Anregungspegel (Peak) | **HOCH** | Peak <1.0 verschlechtert stark, v.a. bei Low-Gain-Modellen (Score bis 350 bei Peak 0.05) |
| Dauer des Rampenfensters | **HOCH** | vom eingefrorenen Motor fest auf 5s verdrahtet (`runEngine` ruft `stageA(...,5*fs,...)` hart codiert); eigene Abweichung davon verschlechtert das Ergebnis konsistent - bestaetigt die bestehende Fensterannahme, statt sie infrage zu stellen |
| Frequenzlage bei Einton | MITTEL | 1000-4000Hz Einton deutlich besser als 80-200Hz Einton (Score ~4.8-6.7 vs. 9.2-10.9) |
| Umhuellungsform (linear/exp/dreieck/langsamer Sinus) | NIEDRIG | Unterschiede innerhalb einer Familie meist <10% |
| Bandbreite des Multitons (5 vs. 8 Toene, 2kHz vs. 6kHz Obergrenze) | NIEDRIG-MITTEL | mehr/breitere Toene verschlechtern leicht (4.37 -> 6.26-10.41) |
| Polaritaets-Asymmetrie (Familie E) | NIEDRIG | kein klarer Vorteil ggue. symmetrischem Einton |
| Silence/Sample-Dichte | NICHT SEPARAT GEMESSEN | in dieser Runde nicht isoliert variiert (Zeitbudget) |

### J. GOJIRA-Holdout (einmalig, nach Auswahl)

`native/nam_bridge/out/v4f_stage_a_holdout.dart` - GOJIRA wurde bis zu
diesem Zeitpunkt in keinem Auswahlschritt verwendet.

| | P | N | a+ | a- | Score |
|---|---|---|---|---|---|
| Ziel (Pipeline A) | 0.08076 | 0.09362 | 777.74 | 581.73 | - |
| alt (110Hz Einton) | 0.73246 | 0.69402 | 41.85 | 53.95 | 10.19 |
| neu (5-Ton-Multisine) | 0.79129 | 0.54361 | 45.13 | 45.13 | 9.52 |

Verbesserungsfaktor auf dem Holdout: **1.07x** - eine Verbesserung, aber
deutlich schwaecher als der ~2x-4x-Faktor auf den vier Trainingsmodellen.
Das ist ehrlich zu berichten: die Generalisierung ist vorhanden, aber
bescheidener als die TRAIN/DEV-Zahlen vermuten liessen.

### K. Reference Signal V2

`tool/nam_inference/wyrmtone_reference_signal_v2.dart`
(`WyrmToneReferenceSignalV2`): identisch zu V1
(`WyrmToneReferenceSignal`, V4d) bis auf das 0-5s-Segment, das jetzt die
gewaehlte 5-Ton-Multisine-Rampe (80/200/440/1000/2000Hz, linear, Peak 1.0)
statt des 110Hz-Eintons verwendet. 5-6s-Stille, 6.000-6.005s-Burst und
6.005-70s-Schroeder-Multiton sind absichtlich in der neuen Datei dupliziert
(nicht aus V1 importiert), damit V1 unveraendert und durch seinen eigenen
Hash-Test weiter abgesichert bleibt. Tests:
`test/tool/wyrmtone_reference_signal_v2_test.dart` (Determinismus, exakte
Laenge, Stille 5-6s, Rampen-Endpegel, Sonicake-Referenz-Verbot).

### L-N. Voller Pipeline-A-vs-B-Vergleich mit V2 (alle 5 Modelle)

`native/nam_bridge/out/pipeline_ab_compare_v2.dart` (Kopie von V4e's
Vergleichsskript, einzige Aenderung: `WyrmToneReferenceSignal` ->
`WyrmToneReferenceSignalV2`), volle 70s-Pipeline fuer alle 5 Modelle,
Laufzeit vergleichbar mit V4e (`pipeline_ab_compare_v2.log`).

**Kennlinienform (P/N/a+/a- gain-matched NRMSE) - deutliche Verbesserung:**

| Modell | V1 (V4e, qualitativ) | V2 gain-matched NRMSE |
|---|---|---|
| Solid | Kennlinienform falsch (a+/a- 10-20x daneben) | **0.104** |
| GOJIRA | Kennlinienform falsch | **0.089** |
| JVM410H | Kennlinienform falsch | **0.092** |
| Fender AKG414 | Kennlinienform falsch | **0.027** |
| FNDR PANO | teilweise passend | **0.110** |

Alle fuenf Modelle liegen jetzt bei 2.7%-11% NRMSE fuer die *reine
Kennlinienform* (gain-matched) - das ist eine drastische Verbesserung
gegenueber V4e's "a+/a- differieren um 10-20x" und bestaetigt die
Ausgangshypothese direkt: die Anregungstrajektorie beeinflusst Stage A's
Kennlinien-Fit stark, und die Multisine-Anregung trifft die tatsaechliche
Kennlinienform von Pipeline A deutlich besser als V1's 110Hz-Einton.

**Aber: absolute P/N und die vollstaendige Probe-Validierung verbessern
sich kaum:**

| Modell | Probe-Korrelation (raw) | Probe NRMSE (gain-matched) | P(B)/P(A) |
|---|---|---|---|
| Solid | 0.310 | 0.951 | 4.62x |
| GOJIRA | 0.358 | 0.934 | 3.93x |
| JVM410H | 0.603 | 0.798 | 4.92x |
| Fender AKG414 | 0.042 | 0.999 | 2.04x |
| FNDR PANO | 0.915 | 0.404 | 5.35x |

Diese Werte liegen im selben Bereich wie V4e's V1-Ergebnisse (JVM410H
0.586->0.603, FNDR PANO 0.89->0.915, jeweils nahezu unveraendert; Solid/
GOJIRA/Fender weiterhin schwach, Fender sogar leicht schwaecher: 0.042 vs.
vorher "0.06-0.34"-Bereich). D.h.: **die Reparatur von Stage A allein
verbessert den unabhaengigen Gesamt-Vergleich NICHT wesentlich**, obwohl sie
die Kennlinienform-Metrik stark verbessert.

Grund, direkt aus den Daten ablesbar: FIR1/FIR2 (Stufen B/C/L/F, in diesem
Meilenstein bewusst nicht angefasst) bleiben massiv unterschiedlich (FIR1
Mittel 5.4-12.7dB, Maximalwerte bis 27dB; FIR2 aehnlich) - das dominiert
jetzt den Gesamtfehler. Zusaetzlich bleibt ein globaler Pegel-Unterschied:
P(B) ist durchgaengig 2-5x groesser als P(A) - eine Groessenordnung, die an
den seit V4a/b/c ungeklaerten ~3.226x-Sonicake-Ausgangsfaktor erinnert
(CORRELATED, nicht CONFIRMED - hier nicht weiter untersucht, nur als
Beobachtung festgehalten). Eine alternative, ebenfalls ungeprueft gebliebene
Erklaerung: die Multisine hat bei gleichem Momentan-Peak eine andere
Crest-/Energieverteilung als ein Einton, was P (der groesste Block-Peak der
Modellausgabe) unabhaengig von der Kennlinienform veraendern kann.

### O. Antworten auf die 5 Leitfragen

1. **Ist Stage A signalabhaengig?** JA - klar bestaetigt. Bei gleichem
   Modell fuehren unterschiedliche 0-5s-Anregungen zu stark
   unterschiedlichen a+/a- (z.B. Fender: 110Hz-Einton liefert a+=24.0,
   Ziel ist 1.165; Multisine liefert a+=0.095 - beide falsch, aber die
   Multisine liegt naeher an der *Kennlinienform*, siehe Q).
2. **Welche Eigenschaften der Anregung zaehlen?** Frequenzinhalt
   (Einton vs. Multiton) und Anregungspegel sind HOCH-Einfluss; die
   5-Sekunden-Fensterdauer ist strukturell fest vom eingefrorenen Motor
   vorgegeben und darf nicht variiert werden. Umhuellungsform ist
   NIEDRIG-Einfluss.
3. **Kann eine generische Anregung Pipeline A's Kennlinie ueber Modelle
   hinweg reproduzieren?** TEILWEISE JA fuer die Kennlinien*form* (2.7-11%
   NRMSE bei allen 5 Modellen, inkl. Holdout-Verbesserung um 1.07x), aber
   NEIN fuer absolute Pegel/P/N und fuer die vollstaendige unabhaengige
   Probe-Uebereinstimmung.
4. **Verbessert die Reparatur von Stage A den vollstaendigen unabhaengigen
   Vergleich wesentlich?** NEIN, nicht wesentlich - Probe-Korrelation und
   gain-matched NRMSE bleiben nahe an V1's (teils sogar minimal
   schlechter bei Fender).
5. **Ist die verbleibende Abweichung jetzt primaer FIR-bedingt?** JA, nach
   dieser Evidenz - FIR1/FIR2-Deltas (bis 27dB) sind jetzt die groesste
   sichtbare Fehlerquelle, waehrend die Kennlinienform selbst gut passt.

### P. Sicherheits-/Scope-Hinweis

Ausschliesslich offline: kein ADB, kein USB-/MIDI-/SysEx-Schreiben, kein
NAM-/IR-/Preset-Upload, kein Store, kein Hardwarezugriff, kein Android. Kein
Commit, kein Push. `Matribox.exe` wurde in diesem Meilenstein nicht
angefasst. Pipeline-A-Zielwerte wurden nur gelesen, nie veraendert. GOJIRA
wurde erst nach abgeschlossener TRAIN/DEV-Auswahl verwendet (siehe J).

## V4g — FIR1/FIR2 Excitation Identification (Stufen B/C/L/F)

Ausgangslage: Stage A ist geloest (V4f). Die vollstaendige Pipeline-A-vs-B-
Validierung schlaegt aber weiterhin fehl; FIR1/FIR2 (Stufen B/C/L/F) wurden
als dominante Restfehlerquelle identifiziert. Ziel: dieselbe Methodik wie
V4f, aber fuer die FIR-Schaetzung - erst die Datenflusskarte, dann eine
kontrollierte Ablation, dann ein gezielter (nicht blind-brachialer) Sweep.

### B. B/C/L/F-Datenflusskarte (aus dem Code extrahiert, nicht geraten)

`runEngine()` (`engine/stages.dart:485-548`) nach Stage A:

| Stufe | Eingabefenster (x) | Eingabefenster (y, delay-verschoben) | FFT/Fenster | Bins | Iterationen |
|---|---|---|---|---|---|
| "Stage B" (Schwellenwert-Referenz) | 6-21s (15s, 720000) | 6-21s+d | Welch(nperseg=6000, nfft=2048), 50% Overlap, in 2048 gefaltet | 1025 | - |
| Stage C | 23-28s (5s, 240000) | 23-28s+d | firFilter(50 Taps)+shapeChain, dann Welch(6000,2048) | 1025 | - |
| Stage L, Aufruf 1 | 23-28s (5s) | 23-28s+d | Welch(6000,2048) je Iteration | 1025 | 3 |
| Stage L, Aufruf 2 | 6-21s (15s) | 6-21s+d | Welch(6000,2048) je Iteration | 1025 | 2 |
| Stage L, Aufruf 3 | 30-50s (20s, 960000) | 30-50s+d | Welch(6000,2048) je Iteration | 1025 | 5 |
| Stage F | 50-70s (20s, 960000) | 50-70s+d | eigene DFT (nb=2401, seg=4800=100ms), Hamming | 2401 | - |

28-30s wird von keiner Stufe gelesen ("unused gap").

**Entscheidender Befund direkt aus `WelchEstimator.magnitude()`
(`engine/spectral.dart`):** die Funktion berechnet
`mag[k] = |Sxy[k]| / (Sxx[k]+eps)` - eine H1-artige Kreuzspektrum-
Betragsschaetzung. Ein Frequenz-Bin, in dem die ANREGUNG kaum Energie hat
(`Sxx[k]~0`), liefert unabhaengig vom tatsaechlichen Modellverhalten eine
schlecht konditionierte Schaetzung. Das ist eine CONFIRMED (aus dem Code
abgeleitete, nicht nur empirisch vermutete) Erklaerung dafuer, dass
breitbandige spektrale Deckung *innerhalb jedes einzelnen Analysefensters*
entscheidend sein sollte.

Stage L: iterativer Fit (`stageL()`), Fehlermetrik = mittlerer
|log(Amplitude)|-Fehler auf einem 512-Punkte-Mel-Gitter (`_makeQ512`, 80Hz-
10kHz), feste, unveraenderte Reset-Regel (`err > best*1.2` -> RESET,
Schrittweite g *= 0.5). Stage F: finale FIR2-Korrektur ueber ein
gefaltetes 100ms-Segment (Hamming, 2401-Punkt-DFT), RMS-Energie-Angleichung
am Ende. Alles unveraendert, nur gelesen.

### D. Harness

`tool/nam_inference/fir_pipeline_harness.dart` (`runBclf()`): exakte
Reproduktion von `runEngine()`s Orchestrierung (Zeilen 490-547) aus dessen
EIGENEN oeffentlichen Funktionen (`stageA`, `stageC`, `stageL`, `stageF`,
`shapeChain`, `WelchEstimator`) - keine Neuimplementierung. Verifiziert:
`fir1`/`fir2x4` bitgenau identisch mit `runEngine()`s eigener Ausgabe auf
echten Daten (`v4g_bclf_harness_check.dart`), inklusive bitgenauer
Nachbildung von `_makeQ512()` ueber dieselben float32-Praezisions-Helfer
(`f32`, `log10f`, `powf`, `linspace32`) - keine Aenderung an `stages.dart`.
`tool/nam_inference/fir_distance.dart`: semantische FIR-Distanz (nie rohe
Koeffizientengleichheit) - Betragsantwort bei den 16 geforderten
Frequenzen, RMS/Mittel/Max-Fehler in dB, Phasenfehler, Impulsantwort-
Korrelation/NRMSE, FIR1 und FIR2 getrennt.

### C. Fenster-Ablation (VOR dem grossen Sweep)

`v4g_window_ablation.dart`, ein Modell (JVM410H), Reference Signal V2
unveraendert bis auf jeweils eine Region, die durch Stille ersetzt wird:

| Zeitregion | Ergebnis |
|---|---|
| 6-21s (Stage B/L2) | **NUMERISCH INSTABIL** (NaN-Kaskade im eingefrorenen `stageL`/`melResample`) - HIGH IMPACT |
| 23-28s (Stage C/L1) | **NUMERISCH INSTABIL** - HIGH IMPACT |
| 28-30s (ungenutzte Luecke) | bMagPeak 13.9%[MEDIUM, vermutlich Einzel-Bin-Rauschen], StageC.ratio/FIR1/FIR2 1-2%[LOW] - bestaetigt: praktisch KEIN EINFLUSS |
| 30-50s (Stage L3) | **NUMERISCH INSTABIL** - HIGH IMPACT |
| 50-70s (Stage F) | **NUMERISCH INSTABIL** - HIGH IMPACT |

Wichtiger Befund: der eingefrorene Schaetzer selbst ist nicht robust gegen
vollstaendige Stille in einem gelesenen Fenster (Division durch ~eps in
`WelchEstimator`, propagiert durch `powf`/`melResample` bis NaN). Das ist
eine Eigenschaft des eingefrorenen Algorithmus, kein Fehler dieses
Kabelbaums - und bestaetigt die theoretische Karte empirisch: jede
tatsaechlich gelesene Region ist kritisch, die unbenutzte Luecke ist es
nicht.

### E. Pipeline-A-FIR-Zielwerte

`v4g_fir_targets.dart`: `runEngine()` auf echten Referenz-/Ausgabe-WAVs
fuer alle 5 Modelle (inkl. GOJIRA, nur zur Dokumentation, nicht zur
Auswahl), FIR1 (128 Taps)/FIR2 (2048 Taps, x4 skaliert) gespeichert in
`v4g_fir_targets.json`. ~10s pro Modell (B/C/L/F-DSP-Kosten).

### F/G. Experimentmatrix & Laufzeitstrategie

Vor Runde 1: Laufzeit gemessen (Harness-Check: `runBclf()` allein ~10.1s
DSP, NAM-Inferenz ~5.3s bei 70s Audio -> ~15.3s/Experiment geschaetzt).
Runde 1: 6 Familien x 4 Trainingsmodelle = 24 Experimente, geschaetzt
367s, tatsaechlich **578.6s** (Overhead durch die groessere
`runBclf`-Kosten bei laengeren Signalen als im Kurztest). Runde 2 auf 4
Varianten x 4 Modelle = 16 reduziert, um im Zeitbudget zu bleiben -
tatsaechlich 378.8s. Kein unkontrollierter Multi-Stunden-Lauf.

### H/I/J/K. Signalfamilien-, Frequenzdeckungs-, Dauer- und Pegel-Ergebnisse

Runde 1 (mittlerer FIR1+FIR2-RMS-dB-Fehler, TRAIN/DEV):

| Familie | Score (dB) |
|---|---|
| **Log-Sweep, 20Hz-20kHz, alle 5s neu gestartet** | **17.76** |
| MLS (16-Bit-LFSR) | 19.19 |
| Weisses Rauschen (deterministisch) | 19.76 |
| Baseline V2 (Schroeder-Multiton, einmalig ueber 64s) | 22.66 |
| Multisine (40 Toene, alle 5s neu gestartet) | 25.66 |
| Log-Sweep, einmalig ueber 64s | 28.03 |

Entscheidender Befund: der EINMALIGE Log-Sweep (28.03dB) ist DEUTLICH
schlechter als derselbe Sweep, alle 5s wiederholt (17.76dB) - bestaetigt
die aus dem Code abgeleitete Hypothese direkt: Periodizitaet relativ zur
Fenstergroesse zaehlt mehr als die Familie selbst. MLS und Rauschen (von
Natur aus in jedem Teilfenster breitbandig) schneiden ebenfalls klar besser
ab als die Baseline.

Runde 2 (Verfeinerung des Siegers):

| Variante | Score (dB) |
|---|---|
| **5s-Zyklus, 20kHz, Pegel 0.5** | **17.17** |
| 5s-Zyklus, 20kHz, Pegel 1.0 (Runde-1-Sieger) | 17.61 |
| 15s-Zyklus, 20kHz | 18.58 |
| 5s-Zyklus, 12kHz (statt 20kHz) | 20.04 |

12kHz-Deckung ist klar schlechter als 20kHz (bestaetigt: volle Deckung bis
20kHz noetig). 15s-Zyklus schlechter als 5s-Zyklus (kuerzere Zyklen
gewinnen, passend zu Stage C/L1's kurzem 5s-Fenster). Pegel 0.5 leicht
besser als 1.0 (~2.5% relativ) - schwacher, aber konsistenter Hinweis auf
nichtlineare Kontamination bei voller Aussteuerung (siehe L).

### L. Nichtlineare Kontamination

Nur schwach messbar: Pegel 0.5 vs. 1.0 aendert den Score um ~2.5% (nicht
dramatisch). Keine grosse, eindeutige Pegelabhaengigkeit gefunden - die
Verbesserung stammt ueberwiegend aus der Zyklus-/Frequenzdeckungs-
Eigenschaft, nicht aus der Amplitude.

### M. Stage-L-Verhalten

Aus den Iterationsprotokollen (Baseline, JVM410H): Fenster 23s (3 It.):
1x improved, 2x kept; Fenster 6s (2 It.): 2x improved; Fenster 30s
(5 It.): 2x improved, 1x kept, 1x RESET, 1x kept. Reset-Schwelle (20%)
unveraendert verwendet, nicht angetastet. Kein systematischer Unterschied
in der Konvergenzguete zwischen den getesteten Anregungen wurde gesondert
vertieft (Zeitbudget) - die primaere Metrik blieb die FIR-Distanz.

### N/O/P. Bester generischer Kandidat, Training, GOJIRA-Holdout

Gewaehlt: **Log-Sweep, 20Hz-20kHz, alle 5s neu gestartet, Pegel 0.5**
(logarithmische Chirp-Phasenformel, deterministisch). GOJIRA-Holdout
(`v4g_fir_holdout.dart`, einmalig):

| | FIR1 RMS (dB) | FIR2 RMS (dB) | Score |
|---|---|---|---|
| V2-Baseline | 14.14 | 10.28 | 24.42 |
| V3-Kandidat | 15.94 | **5.27** | 21.21 |

Verbesserungsfaktor 1.15x - FIR2 verbessert sich stark (Korrelation
0.564->0.976), FIR1 verschlechtert sich leicht. Ehrlich berichtet: kein
gleichmaessiger Gewinn auf beiden FIRs, aber ein Netto-Gewinn.

### Q. Reference Signal V3

`tool/nam_inference/wyrmtone_reference_signal_v3.dart`: identisch zu V2
bis auf den 6.005-70s-Schwanz, der jetzt den gewaehlten Log-Sweep
verwendet. 0-6.005s (Multisine-Rampe, Stille, Burst) bewusst dupliziert
(nicht aus V1/V2 importiert), damit beide frueheren Versionen unveraendert
bleiben. Tests: `test/tool/wyrmtone_reference_signal_v3_test.dart`.

### R/S/T. Vollstaendige 5-Modell-Validierung, V1/V2/V3-Vergleich

`native/nam_bridge/out/pipeline_ab_compare_v3.dart` (Kopie von V4f's
Vergleichsskript, nur `WyrmToneReferenceSignalV3` statt V2), alle 5
Modelle, vollstaendig ausgefuehrt.

**Probe-Korrelation RAW (unabhaengige Sonde, nicht fuer die Identifikation
verwendet):**

| Modell | V1 | V2 | V3 |
|---|---|---|---|
| Solid | 0.304 | 0.310 | **0.620** |
| GOJIRA | 0.336 | 0.358 | **0.755** |
| JVM410H | 0.586 | 0.603 | **0.716** |
| Fender AKG414 | 0.060 | 0.042 | **0.979** |
| FNDR PANO | 0.892 | 0.915 | 0.907 |

**Probe-NRMSE, gain-matched:**

| Modell | V1 | V2 | V3 |
|---|---|---|---|
| Solid | 0.953 | 0.951 | **0.784** |
| GOJIRA | 0.942 | 0.934 | **0.655** |
| JVM410H | 0.810 | 0.798 | **0.698** |
| Fender AKG414 | 0.998 | 0.999 | **0.203** |
| FNDR PANO | 0.451 | 0.404 | 0.420 |

**FIR2 RMS-Fehler (dB):**

| Modell | V1 | V2 | V3 |
|---|---|---|---|
| Solid | 14.70 | 12.04 | **3.80** |
| GOJIRA | 15.43 | 10.28 | **4.44** |
| JVM410H | 11.55 | 6.42 | 6.36 |
| Fender AKG414 | 20.95 | 16.27 | **4.89** |
| FNDR PANO | 14.41 | 11.12 | 7.97 |

**FIR1 RMS-Fehler (dB):**

| Modell | V1 | V2 | V3 |
|---|---|---|---|
| Solid | 17.31 | 15.43 | 16.51 |
| GOJIRA | 14.99 | 14.14 | 15.96 |
| JVM410H | 10.00 | 10.16 | 9.24 |
| Fender AKG414 | 13.05 | 13.37 | **6.75** |
| FNDR PANO | 6.56 | 5.81 | 11.78 |

**Nichtlineare Kennlinie (gain-matched NRMSE) - unveraendert gut (V4f-Fix
bleibt erhalten):**

| Modell | V1 | V2 | V3 |
|---|---|---|---|
| Solid | 0.210 | 0.104 | 0.110 |
| GOJIRA | 0.154 | 0.089 | 0.089 |
| JVM410H | 0.103 | 0.092 | 0.091 |
| Fender AKG414 | 0.028 | 0.027 | 0.029 |
| FNDR PANO | 0.179 | 0.110 | 0.112 |

**Zusammenfassung:** V3 verbessert die vollstaendige unabhaengige
Probe-Validierung fuer 4 von 5 Modellen DRASTISCH (Fender: Korrelation
0.04->0.98, NRMSE 0.999->0.203; GOJIRA: Korrelation 0.36->0.76, NRMSE
0.93->0.66) - der groesste Einzelfortschritt der gesamten V4-Serie. FNDR
PANO bleibt praktisch unveraendert (war schon vorher am besten). Getrieben
ueberwiegend durch FIR2 (dramatisch besser bei 4/5 Modellen); FIR1 bleibt
gemischt (besser bei Fender, leicht schlechter bei Solid/GOJIRA/FNDR PANO).
Absolute P/N-Pegelabweichung (2-5x) bleibt unveraendert bestehen (nicht
untersucht, wie angewiesen) - Raw-Korrelation und Gain-matched-NRMSE weisen
getrennt aus, wie viel davon reiner Pegel- vs. Formfehler ist.

### U. Performance

Harness-DSP (`runBclf`, ohne NAM-Inferenz): ~10.1s/Modell (dominiert durch
die eingefroreren FFT-/Mel-Resampling-Schleifen, nicht optimierbar/nicht
angefasst). Pro Experiment (Inferenz+DSP): ~15-27s je nach Modell. Runde 1:
578.6s/24 Exp. Runde 2: 378.8s/16 Exp. GOJIRA-Holdout: ~35s. Voller
5-Modell-V1/V2/V3-Vergleich: im ueblichen Rahmen der Vorgaenger-Meilensteine.

### V. Tests/Analyze

Neu: `test/tool/fir_excitation_test.dart` (17 Faelle: Determinismus aller
9 Generatoren, Zyklus-Wiederholung, MLS-Bipolaritaet, Verbot Sonicake-/
Modell-spezifischer Konstanten, FIR-Distanz-Identitaet/Skalierungs-Test,
Frequenzsatz-Check, Stage-L-Fensterlayout-Check, Holdout-Isolations-Guard)
+ `test/tool/wyrmtone_reference_signal_v3_test.dart` (5 Faelle). Alle 23
gruen. `dart analyze tool/nam_inference test/tool`: clean.

### W/X. Sicherheit, verbleibende Risiken

Ausschliesslich offline, kein ADB/USB/MIDI/SysEx/NAM-Upload/Store/
Hardwarezugriff/Android. Kein Commit, kein Push. `NeuralAmpModelerCore`,
`native/FFI`, Stage A, Reference Signal V1/V2, der eingefrorene Konverter,
Transport-Encoder und CloData-Wireformat wurden nicht veraendert. Der 0.31/
3.226-Faktor wurde NICHT untersucht (wie angewiesen) - die verbleibende
absolute P/N-Pegelabweichung (2-5x) ist weiterhin unberuehrt und separat
ausgewiesen. FIR1 verbessert sich uneinheitlich (3/5 Modelle leicht
schlechter) - ein moeglicher naechster Ansatzpunkt. GOJIRA-Verbesserung
(1.15x) ist bescheidener als der TRAIN/DEV-Fortschritt vermuten liess -
Generalisierung vorhanden, aber nicht garantiert fuer jedes zukuenftige
Modell.

### Y. Empfehlung

Der Fortschritt ist real und bedeutend (4/5 Modelle mit drastisch
verbesserter unabhaengiger Probe-Uebereinstimmung), aber nicht vollstaendig
(FNDR PANO unveraendert, FIR1 uneinheitlich, absoluter Pegel weiterhin
falsch). Fuer eine Produktionsfreigabe fehlt: (1) FIR1-spezifische
Untersuchung (aktuell nur als Nebeneffekt der FIR2-Optimierung
mitbehandelt), (2) eine Erklaerung des absoluten Pegelunterschieds, (3)
Bestaetigung an mindestens einem weiteren, bisher ungesehenen Modell ueber
GOJIRA hinaus. HOLD auf Hardware/Android bleibt bestehen.

## V4h — FIR1 + Absolute-Scale Root-Cause-Analyse

Ausgangslage: V3 verbesserte die unabhaengige Probe-Validierung fuer 4/5
Modelle drastisch (V4g), getragen vor allem durch FIR2; FIR1 blieb
uneinheitlich (3/5 Modelle leicht schlechter), der absolute 2-5x P/N-
Pegelunterschied blieb bestehen. Ziel: beide Fragen UNABHAENGIG klaeren,
ohne V3 selbst zu aendern.

### B/C. FIR1-Datenpfad & Divergenzpunkt

FIR1 wird AUSSCHLIESSLICH innerhalb der drei `stageL()`-Aufrufe neu
entworfen (`a12 = designFir(b10, 128, 128)`, aus einem auf 128 mel-Punkte
resampelten, geometrisch geglaetteten `a9`) - Stage F ruehrt FIR1 nie an
(nur FIR2). Entscheidender struktureller Fund: die Fehlermetrik, die
Keep/Reset in `stageL()` steuert, basiert auf `b6` - der Welch-Magnitude
NACH FIR1 UND FIR2 - `stageL()` bewertet FIR1 also NIE isoliert, nur die
KOMBINIERTE Antwort. Das erklaert strukturell, warum eine fuer FIR2
optimierte Anregung (V4g) FIR1 nicht zwangslaeufig mitverbessert: der
Algorithmus kompensiert ueber FIR2, solange die Summe passt.

**Checkpoint-Divergenz** (`v4h_checkpoint_and_scaleflow.dart`, FIR1-Snapshot
nach jedem der 3 `stageL()`-Fenster, Pipeline A vs. B):

| Modell | nach Fenster 1 (23s) | nach Fenster 2 (6s) | nach Fenster 3 (30s) |
|---|---|---|---|
| Solid | 15.31dB | 16.51dB | 16.51dB |
| JVM410H | 8.87dB | 8.86dB | 9.24dB |
| Fender AKG414 | 4.44dB | 5.58dB | 6.75dB |
| FNDR PANO | 11.73dB | 11.74dB | 11.78dB |

**Klarer Befund:** die FIR1-Abweichung ist bei allen 4 Modellen bereits
nach dem ALLERERSTEN `stageL()`-Aufruf (23-28s-Fenster, gemeinsam mit
Stage C) fast vollstaendig vorhanden - die beiden spaeteren Fenster
aendern nur wenig. Klassifikation: **STAGE C / erstes STAGE-L-Fenster
(23-28s)**, nicht Resampling, nicht Skalierung (siehe H).

### D. Divergenzklassifikation

INPUT: teilweise (andere Anregung im 23-28s-Fenster). SPEKTRALE SCHAETZUNG:
ja (Stage C's Ratio-Konstruktion vergleicht zwei verschiedene Fenster,
6-21s und 23-28s). STAGE C: **primaerer Divergenzort**. STAGE L: bestaetigt
den bei Fenster 1 gesetzten Fehler, aendert ihn kaum. RESAMPLING/SKALIERUNG:
ausgeschlossen (siehe H, J).

### E/F/G. FIR1-Matrix (nur 23-28s-Region variiert, Rest = V3 unveraendert)

`v4h_fir1_matrix.dart`: Log-Sweep in der 23-28s-Region, Zyklus in
{1s, 2.5s} x Pegel in {0.1, 0.5}, gegen V3-Baseline (5s-Zyklus, Pegel 0.5)
verglichen; FIR2 zur Kontrolle mitgemessen (haette bei korrekter Isolation
unveraendert bleiben muessen - **bestaetigt**: FIR2 bleibt in allen
Varianten innerhalb der Modell-eigenen Streuung).

| Variante | mittlerer FIR1-RMS-Fehler (dB) |
|---|---|
| Zyklus 2.5s, Pegel 0.5 | 10.89 |
| Zyklus 1s, Pegel 0.5 | 10.89 |
| **V3-Baseline (5s, 0.5)** | **11.07** |
| Zyklus 1s, Pegel 0.1 | 12.45 |
| Zyklus 2.5s, Pegel 0.1 | 13.35 |

Kein Kandidat verbessert FIR1 klar (~1.6% Unterschied, im Rauschen).
Niedriger Pegel (0.1) ist fuer FIR1 durchweg schlechter als 0.5 (anders als
bei FIR2 in V4g, wo 0.5 leicht besser als 1.0 war) - der Grund: bei der
Stage-C-Berechnung sinkt vermutlich das Sxx/SNR-Verhaeltnis bei sehr
niedrigem Pegel. **Ergebnis: kein generischer FIR1-Kandidat innerhalb
dieser Matrix gefunden.**

### H. Skalierungsfluss-Tabelle

`v4h_checkpoint_and_scaleflow.dart`, Pipeline A (offizielles Signal) vs.
Pipeline B (V3), pro Modell:

| Modell | P-Verhaeltnis | N-Verhaeltnis | a+-Verhaeltnis | a--Verhaeltnis | FIR1-Energie-Verh. | FIR2-Energie-Verh. |
|---|---|---|---|---|---|---|
| Solid | 4.68x | 4.27x | 0.081x | 0.143x | 0.327x | 0.501x |
| JVM410H | 4.90x | 4.70x | 0.095x | 0.133x | 0.068x | 0.269x |
| Fender AKG414 | 2.03x | 2.18x | 1.092x | 1.069x | 0.055x | 1.081x |
| FNDR PANO | 5.34x | 6.97x | 1.949x | 1.180x | 0.042x | 0.179x |

P/N liegen bei allen 4 Modellen im bekannten 2-7x-Bereich. a+/a- weichen
NUR bei den drei Hochgewinn-Modellen (Solid/JVM410H, ~0.08-0.14x) stark ab
- Fender (niedriger Gewinn) und FNDR PANO liegen nahe bei 1x. Diese
Verhaeltnisse stammen aus dem Vergleich VERSCHIEDENER Signale (Sonicake
vs. V3) und vermischen echten Formunterschied mit dem bekannten
Inferenz-Pegel-Bias - siehe I/J fuer die saubere Trennung.

### I/J. Offizieller vs. nativer NAM-Output (kontrolliertes Skalierungsexperiment)

`v4h_scale_experiment.dart`: dasselbe bereits berechnete V3-Inferenz-
Ergebnis wurde mit k in {0.5, 1.0, 2.0} skaliert, VOR der Schaetzung
angewendet (RESEARCH-ONLY, nie in Produktionscode geschrieben):

| k | P (Solid) | a+ (Solid) | FIR1-Korrelation vs. k=1 | FIR2-Energie (Solid) |
|---|---|---|---|---|
| 0.5 | 0.2087 (=0.500x) | 61.05 (=1.000x) | 0.9993 | 0.6767 |
| 1.0 | 0.4174 (Basis) | 61.05 (Basis) | 1.0000 | 0.6829 |
| 2.0 | 0.8349 (=2.000x) | 61.05 (=1.000x) | 1.0000 | 0.6829 |

(Fender zeigt dasselbe Muster.) **P/N skalieren EXAKT linear mit k. a+/a-
und die FIR1-FORM bleiben vollstaendig invariant (Korrelation ~1.000).**
Auch FIR2s Energie bleibt nahezu konstant - unerwartet auf den ersten
Blick, aber durch die Algebra erklaerbar (siehe K).

### K. Mathematische Herleitung (aus dem Code, nicht nur gemessen)

Aus `stageA()`: `gp = dsum(pm,eP)/accx(eP)`, `aP = gp/pmax`. Skaliert y um
k, skaliert `pmax` (=P) und `gp` BEIDE um k (accx haengt nur von x ab) ->
`aP` kuerzt sich vollstaendig weg. Formal: **P,N ∝ k; a+,a- invariant.**
Aus `stageL()`/`stageF()`: FIR1 wird nie energie-renormiert, haengt nur von
Verhaeltnissen ab (`b2r[i]=ratioDiv(b5[i],a10[i])`), die sich ebenfalls
wegkuerzen -> **FIR1-Form invariant.** Stage F's finale FIR2-Skalierung
(`scale = sqrt(sum(y^2))/sqrt(sum(sigf^2))`) skaliert scheinbar mit k -
ABER `sigf` durchlaeuft den Waveshaper, dessen P/N (jetzt selbst k-fach
groesser) ebenfalls proportional mitskalieren, wodurch sich k in diesem
Verhaeltnis KUeRZT. Empirisch bestaetigt (I). **Schlussfolgerung: nur P und
N tragen die Pegelabhaengigkeit; a+, a-, FIR1 und (nach Stage F) auch FIR2
sind gegenueber einer gleichfoermigen Ausgangsskala k unabhaengig.**

### L. Forschungs-Skalierungsexperiment (Zusammenfassung, siehe I)

Bestaetigt Abschnitt K vollstaendig empirisch fuer 2 reprsentative Modelle
(Solid, Fender). Kein Skalar wurde in Reference Signal V3 oder
Produktionscode uebernommen.

### M. Gemeinsame oder unabhaengige Ursache?

**CASE B: FIR1-Fehlanpassung und absoluter Pegelunterschied sind
UNABHAENGIGE Probleme.** Beweis: der absolute Pegelunterschied betrifft
ausschliesslich P/N (mathematisch bewiesen und empirisch bestaetigt, K/I);
FIR1 ist gegenueber genau dieser Groesse nachweislich invariant - ein
FIR1-Fehler kann also nicht durch denselben Mechanismus entstehen, der
P/N verschiebt. FIR1s eigener Fehler entsteht stattdessen in Stage C /
dem ersten Stage-L-Fenster (23-28s) und liess sich durch die getestete
Parametervariation dieser Region nicht beheben (E/F/G) - die genaue
Ursache bleibt UNGEKLAERT (nicht: unloesbar, aber nicht mehr in dieser
Matrix gefunden).

### N/O. Bester FIR1-Kandidat, GOJIRA-Holdout

Kein Kandidat verbesserte TRAIN/DEV klar (siehe E/F/G) - daher **kein**
Kandidat zur GOJIRA-Validierung vorgelegt (wie angewiesen: GOJIRA nur nach
Auswahl eines klar verbessernden Kandidaten).

### P/Q. Reference Signal V4

**NICHT ERSTELLT** - die Bedingung ("ein generischer FIR1-Kandidat
verbessert TRAIN/DEV klar") wurde nicht erfuellt. Reference Signal V3
bleibt der aktuelle, eingefrorene Bestwert.

### R. Strukturelle CloData-Validierung

Unveraendert: V3s CloData wurde bereits in V4g vollstaendig strukturell
validiert (8232 Byte, alle Floats endlich, deterministisch,
Transport-Round-Trip fehlerfrei, fuer alle 5 Modelle). V4h hat den
Konverter, Transport-Encoder oder das CloData-Wireformat an keiner Stelle
beruehrt.

### S. Performance

Checkpoint+Skalierungsfluss (4 Modelle): ~140s. Skalierungsexperiment
(2 Modelle x 3 k): ~80s. FIR1-Matrix (5 Varianten x 4 Modelle): 697,1s
(laenger als geschaetzt, da `runBclf` bei diesen Signalen im Mittel naeher
an 27-30s statt der in V4g gemessenen ~20-23s lag - lief im Hintergrund
weiter, kein Abbruch noetig).

### T. Tests/Analyze

Neu: `test/tool/fir1_scale_analysis_test.dart` (2 Faelle: P/N-Linearitaet
und a+/a--Invarianz gegenueber einer synthetischen Skalierung, rein ueber
den eingefrorenen `stageA()` - kein NAM noetig; Holdout-Isolations-Guard
fuer die V4h-Trainingsskripte). Beide gruen. `dart analyze
tool/nam_inference test/tool`: clean. Bestehende Tests unveraendert
(V4f/V4g-Tests weiterhin gruen, nicht erneut vollstaendig ausgefuehrt -
risikobasiert, da an den zugrunde liegenden Dateien nichts geaendert
wurde ausser einer rueckwaertskompatiblen Erweiterung von
`BclfResult`/`fir_pipeline_harness.dart` um das neue `lSnapshots`-Feld,
verifiziert per erneutem Bit-Identitaets-Check gegen `runEngine()`).

### U/V. Sicherheit, verbleibende Risiken

Ausschliesslich offline, kein ADB/USB/MIDI/SysEx/Hardware/Android. Kein
Commit, kein Push. Stage A V2, der V3-FIR-Abschnitt, NeuralAmpModelerCore,
FFI, der eingefrorene Konverter, Transport und CloData-Wireformat wurden
nicht veraendert - alle Experimente zweigten von V3 ab, ohne es zu
aendern. Kein 0.31/3.226-Konstante in Produktionscode. Verbleibendes
Risiko: FIR1s eigentliche Ursache bleibt ungeklaert (nur der Divergenzort
ist bekannt); die getestete Matrix war bewusst kompakt (2 Zyklen x 2
Pegel), ein groesserer Suchraum (andere Fenster-Kombinationen, andere
Signalfamilien speziell fuer die 23-28s-Region) wurde nicht erschoepfend
geprueft.

### W/X. Hardware-Freigabe, Android

**HOLD.** V3 bleibt der beste erreichte Stand, aber FIR1 und der absolute
Pegel sind beide weiterhin ungeklaert (wenn auch nachweislich unabhaengig
voneinander). Die Bedingungen fuer eine kontrollierte Clone-5-Pruefung
("kein Modell regressiert katastrophal" ist erfuellt, aber "Restfehler
ueberwiegend Pegel statt Form" ist NICHT eindeutig gezeigt - FIR1 bleibt
ein Form-Fehler) sind nicht vollstaendig erfuellt.

## V4i — Stage C / FIR1 Ratio Root-Cause-Analyse

Ausgangslage: FIR1 weicht bereits nach dem ersten `stageL()`-Fenster
(23-28s, gemeinsam mit Stage C) fast vollstaendig ab (V4h); eine
Anregungs-Parametervariation NUR dieser Region half nicht. Ziel: Stage C
selbst mathematisch rekonstruieren und die Zwei-Fenster-Beziehung
(6-21s vs. 23-28s) klaeren.

### 2. Stage C in mathematischer Notation

Aus dem Code (`engine/stages.dart:226-257`, `engine/spectral.dart:20-107`):

`WelchEstimator(nperseg=6000, nfft=2048).magnitude(a,b)` berechnet, mit
50%-Overlap-Hamming-Segmenten (in `nfft` gefaltet, da `nfft<nperseg`):
`Sxx[k] = Σ_segs (Xi[k]²+Xr[k]²)`, `Sxy[k] = Σ_segs (Yi[k]Xi[k]+Yr[k]Xr[k]) + i(Yi[k]Xr[k]-Yr[k]Xi[k])`,
`mag[k] = |Sxy[k]| / (Sxx[k]+ε)` mit `ε=2^-23`. Frequenzachse:
`freq[k] = k/nfft * fs`.

`bMag = WelchEstimator.magnitude(shapeChain(x[6-21s],p), y[6-21s+d])`
(15s-Fenster, `runEngine`).

In `stageC(x[23-28s], y[23-28s+d], p, bMag)`:
`xf = firFilter(fir50Taps, x)`, `w = shapeChain(xf,p)`,
`(mag,freq) = Welch(w,y)`, `t = gaussSmooth(mag, ⌊1025·0.001⌋=1)`,
`m3 = gaussSmooth(t, ⌊1025·0.005⌋=5)` (praktisch minimale Glaettung).
`mx = max_i(bMag[i])` (ueber alle nicht-NaN Werte, aus dem ANDEREN
15s-Fenster!). `thr = mx·0.001`, `two = 2·thr`,
`k = (two-thr)/two² = thr/(4·thr²) = 1/(4·thr)`.
Fuer jedes `i` mit `m3[i] < two`: `m3[i] ← k·m3[i]² + thr` (glatte,
C¹-stetige parabolische Bodenfunktion: bei `v=0` -> `thr`, bei `v=two` ->
`two`). `ratio[i] = bMag[i] / (m3[i]+ε)`.

### 3. Annahmen von Stage C

| Annahme | Status |
|---|---|
| bMag und m3 liegen auf vergleichbarer absoluter Skala (sonst ist die Bodenfunktion sinnlos) | REQUIRED MATHEMATICALLY (aus der Formel `thr=mx(bMag)*0.001` als Boden fuer m3) |
| Gleiche spektrale Dichte in beiden Fenstern | NOT REQUIRED (Code behandelt sie explizit unterschiedlich: 50-Tap-Vorfilter + Glaettung nur bei C) |
| Gleicher Erregungspegel in beiden Fenstern | HYPOTHESIS, per Abschnitt 4 WIDERLEGT: die Fenster sind bei Sonicake NICHT gleich laut |
| Stationaritaet innerhalb jedes Fensters | REQUIRED MATHEMATICALLY (Welch mittelt ueber Segmente) |
| Gleiche Anzahl nuetzlicher Welch-Segmente | CONFIRMED BY CODE (beide 6000/2048, aber unterschiedliche Fensterlaenge -> B hat mehr Segmente als C) |
| bMag repraesentiert einen RUHE-/BODEN-Referenzwert, kein zweites Breitbandsignal | CONFIRMED BY CODE + Abschnitt 4 (Rolle als reine Boden-Schwelle, `mx*0.001`) |

### 4/5. Fensterstatistik A vs. B, erste numerische Abweichung

`v4i_stagec_analysis.dart` (externe Evidenz, nur Skalarstatistik, keine
Wellenform rekonstruiert):

| | 6-21s (RMS / Peak / Crest) | 23-28s (RMS / Peak / Crest) | RMS-Verhaeltnis (6-21s/23-28s) |
|---|---|---|---|
| **Offizielles Referenzsignal** | 0,0018 / 0,9644 / **528** | 0,3976 / 0,5744 / 1,44 | **0,005** |
| V3-Signal | 0,3535 / 0,5000 / 1,41 | 0,3536 / 0,5000 / 1,41 | 1,000 |

**Entscheidender Befund:** Sonicakes 6-21s-Fenster ist praktisch STILL
(RMS 0,0018) mit einem einzelnen kurzen Transienten (Peak 0,96, Crest
528!) - waehrend das 23-28s-Fenster normal-laut breitbandig ist (RMS 0,40,
Crest 1,44, typisch fuer Rauschen/Multiton). V3 verwendet in BEIDEN
Fenstern denselben Pegel (Verhaeltnis 1,000) - eine strukturelle
Fehlannahme, kein Zufall.

Frueheste numerische Abweichung: bereits bei den ROHEN EINGABEFENSTERN
(Checkpoint A) - nicht bei Sxx/Sxy/bMag/m3 selbst (die sind nur die
Konsequenz). Klassifikation: **FORM-Abweichung** (unterschiedliches
Pegelverhaeltnis zwischen zwei Fenstern ist eine RELATIONALE/strukturelle
Eigenschaft, keine reine globale Skalierung - siehe Abgrenzung zu V4h's
SKALA-Befund, der eine gleichfoermige Ausgangsskala betraf, nicht ein
Pegelverhaeltnis ZWISCHEN zwei Fenstern).

`c.ratio`-Flachheit (Variationskoeffizient, vor Glaettung/Resampling):

| Modell | Pipeline A (Flachheit / Median) | Pipeline B/V3 (Flachheit / Median) |
|---|---|---|
| Solid | 2,247 / 0,164 | 0,368 / 0,991 |
| JVM410H | 1,918 / 0,063 | 0,763 / 0,367 |
| Fender AKG414 | 1,164 / 4,900 | 0,608 / 2,634 |
| FNDR PANO | 0,698 / 3,657 | 0,597 / 1,214 |

Pipeline A's Ratio ist deutlich UNFLACHER (mehr echte Struktur) als
Pipeline B's - passend zum Befund: V3s Ratio liegt naeher an einer Konstante
(Median nahe 1 bei Solid/JVM410H), weil beide Fenster bei V3 aehnlich laut
sind.

### 6. Bin-Konditionierung

Nicht gesondert vertieft (Zeitbudget) - die Fenster-Pegel-Erkenntnis (4/5)
lieferte bereits eine ausreichend starke, generische Erklaerung; eine
detaillierte Bin-fuer-Bin-Korrelationsanalyse wurde durch das direkte,
erfolgreiche Kandidatenexperiment (Abschnitt 9/13) ersetzt.

### 7. Zwei-Fenster-Beziehung

**Bestaetigt:** die Fenster repraesentieren KEINE zwei Kopien desselben
Breitbandsignals, sondern unterschiedliche Bedingungen - eines nahezu
still (Boden-/Rauschreferenz), das andere breitbandig-laut (eigentliche
Messung). Die Beziehung ist ein PEGEL-Verhaeltnis (~1:220 RMS), keine
unterschiedliche Kennlinien-Arbeitspunkt-Messung (keine Evidenz fuer
"gleiches Spektrum, andere Nichtlinearitaet" - eher "Stille vs. Signal").

### 8. Normalisierte Beziehung (Forschungsexperiment)

Nicht als eigener Zwischenschritt gebraucht - das direkte Kandidatenexperiment
(9) implementiert die Erkenntnis unmittelbar und bestaetigt sie empirisch,
ohne einen separaten Normalisierungs-Test zu benoetigen.

### 9/10/11. Kontrolliertes Experiment & Stage-C-Semantik

`v4i_stagec_candidate.dart`: 6-21s auf 2% des V3-Pegels reduziert (NICHT
auf 0 - vollstaendige Stille laesst `stageL()` numerisch divergieren, siehe
V4g), 23-28s und alles andere unveraendert:

| Modell | FIR1 RMS (V3 -> Kandidat) | FIR1-Korrelation (V3 -> Kandidat) | FIR2 RMS (V3 -> Kandidat) |
|---|---|---|---|
| Solid | 16,51 -> **12,73dB** | 0,079 -> 0,150 | 3,80 -> 3,89dB |
| JVM410H | 9,24 -> **7,13dB** | 0,462 -> 0,614 | 6,36 -> 7,50dB |
| Fender AKG414 | 6,75 -> **1,70dB** | 0,545 -> 0,927 | 4,89 -> 5,27dB |
| FNDR PANO | 11,78 -> **2,85dB** | 0,632 -> 0,936 | 7,97 -> 8,97dB |

FIR1 verbessert sich bei ALLEN 4 Trainingsmodellen deutlich (17-76%), FIR2
bleibt im Rahmen der Modellstreuung (≤1,1dB). **Stage-C-Semantik:
SPECTRAL CORRECTION mit einer STILLE-/BODEN-REFERENZ** (nicht "Linear
Response Estimation" zwischen zwei gleichwertigen Breitbandmessungen) -
`bMag` liefert den Rauschboden, `m3`/`ratio` die eigentliche Korrektur.

### 12. GOJIRA-Holdout

`v4i_stagec_holdout.dart`, einmalig, keine Nachjustierung:
FIR1 15,96dB -> **13,22dB** (-17%), Korrelation 0,066 -> 0,154 (mehr als
verdoppelt), FIR2 4,44dB -> 4,56dB (unveraendert). **PASS** - konsistent
mit den drei Hochgewinn-Trainingsmodellen (Solid/JVM410H/GOJIRA zeigen
alle ~17-25% Verbesserung; Fender/FNDR PANO zeigen die groesseren
Spruenge, GOJIRA wurde dafuer nicht selektiert).

### 13/14. Reference Signal V4

Bedingungen erfuellt (materielle FIR1-Verbesserung TRAIN/DEV, keine
materielle FIR2-Regression, Stage A unberuehrt) -> **V4 ERSTELLT**:
`tool/nam_inference/wyrmtone_reference_signal_v4.dart` - identisch zu V3
bis auf die Abschwaechung des 6-21s-Fensters auf 2% seines bisherigen
Pegels; 0-6,005s-Praefix und 23-70s-Inhalt unveraendert (aus V3 dupliziert,
nicht importiert, damit V1/V2/V3 eingefroren bleiben).

### 15. Vollstaendige 5-Modell-Validierung (V3 vs. V4)

`pipeline_ab_compare_v4.dart`, alle 5 Modelle:

| Modell | FIR1 RMS V3->V4 | FIR2 RMS V3->V4 | Probe-Korr. raw V3->V4 | Gain-matched NRMSE V3->V4 |
|---|---|---|---|---|
| Solid | 16,51->**12,76dB** | 3,80->3,86dB | 0,620->**0,784** | 0,784->**0,621** |
| GOJIRA | 15,96->**13,16dB** | 4,44->4,14dB | 0,755->**0,850** | 0,655->**0,527** |
| JVM410H | 9,24->**7,06dB** | 6,36->6,49dB | 0,716->**0,788** | 0,698->**0,616** |
| Fender AKG414 | 6,75->**1,70dB** | 4,89->5,27dB | 0,979->**0,986** | 0,203->**0,167** |
| FNDR PANO | 11,78->**2,85dB** | 7,97->8,97dB | 0,907->0,859 | 0,420->0,512 |

Nichtlineare Kennlinie (Stage A) unveraendert bei allen 5 Modellen
(erwartungsgemaess, da 0-5s nicht angetastet wurde). **4 von 5 Modellen
verbessern sich auch in der VOLLSTAENDIGEN unabhaengigen Probe** (nicht
nur in der FIR1-Metrik selbst, die optimiert wurde) - FNDR PANO ist die
Ausnahme (leicht schlechter: 0,907->0,859 Korrelation, 0,420->0,512 NRMSE),
trotz seiner eigenen dramatischen FIR1-Verbesserung, vermutlich durch
FIR2s leichte Verschlechterung (7,97->8,97dB) dort ueberkompensiert.
Ehrlich berichtet: kein reiner Gewinn, aber netto klar positiv.

### 16. Absoluter Pegel

Nicht Gegenstand dieses Meilensteins. Kein 0,31/3,226 verwendet. Die in
V4h bewiesene Unabhaengigkeit (P/N linear in einer globalen Ausgangsskala,
a+/a-/FIR1 invariant) bleibt unberuehrt - der hier gefundene
Fenster-PEGEL-Unterschied (6-21s vs. 23-28s) ist ein anderer Mechanismus
(ein Verhaeltnis INNERHALB der Anregung, nicht eine globale NAM-
Ausgangsskala) und wird nicht mit dem ungeloesten 2-5x-P/N-Thema vermischt.

### 17. Hardware-Entscheidung

**HOLD**, aber mit klar verbessertem Stand: FIR1s Ursache ist jetzt
strukturell verstanden (Stage C's Boden-Referenz-Fehlannahme) und ein
generischer, nicht modellspezifischer Fix wurde gefunden und auf 5/5
Modellen (inkl. Holdout) validiert. Fuer GO fehlt weiterhin: FNDR PANOs
Regression erklaeren, und der absolute Pegel bleibt ungeklaert (V4h).

### 18. Tests

`test/tool/wyrmtone_reference_signal_v4_test.dart` (4 Faelle: Determinismus,
Fenster-Pegel-Verhaeltnis, Byte-Identitaet ausserhalb 6-21s, Sonicake-Verbot)
+ `test/tool/stage_c_analysis_test.dart` (3 Faelle: Boden-Formel-Verhalten
bei stillem bMag, Determinismus, Holdout-Isolations-Guard) - alle gruen.
`dart analyze tool/nam_inference test/tool`: clean.

### Sicherheit

Ausschliesslich offline, kein ADB/USB/MIDI/SysEx/Hardware/Android. Kein
Commit, kein Push. NeuralAmpModelerCore, FFI, Stage A, Stage B/C/L/F selbst,
V1/V2/V3, CloData-Encoder und Transport wurden nicht veraendert - V4
aendert ausschliesslich das REFERENZSIGNAL (die Anregung), nie die
Algorithmen.

## V4j — Finales Offline-Gate: FNDR-PANO-Regression + Clone-5-Entscheidung

Kleiner, gezielter Diagnose-Meilenstein (kein neuer Signal-Suchlauf). V4
bleibt unveraendert (`v4j_fndr_regression.dart`, read-only, nutzt
ausschliesslich bereits vorhandene V3/V4/Pipeline-A-Daten plus zwei frische
NAM-Inferenzlaeufe pro Modell zur Diagnose).

### 2/3. FNDR PANO: Komponenten- und Frequenzband-Zerlegung

Stage A (nichtlinear) fast identisch V3/V4 (erwartungsgemaess, 0-5s
unveraendert): P/N/a+/a- weichen zwischen V3 und V4 um <1% voneinander ab.

Pro-Band-Fehler gegen Pipeline A (dB, 5-Punkt-Mittel je Band):

| Band | FIR1 V3->V4 | FIR2 V3->V4 |
|---|---|---|
| 20-80Hz | 4,15->**1,08** (-3,07) | 8,87->10,52 (+1,65) |
| 80-200Hz | 3,87->**1,05** (-2,82) | 9,61->10,26 (+0,65) |
| 200-500Hz | 5,25->**2,29** (-2,96) | 6,74->7,11 (+0,37) |
| 500Hz-1kHz | 11,87->**3,77** (-8,10) | 7,25->7,60 (+0,34) |
| 1-2kHz | 15,97->**3,62** (-12,35) | 6,47->7,14 (+0,67) |
| 2-4kHz | 18,66->**3,76** (-14,90) | 6,93->8,09 (+1,16) |
| 4-8kHz | 18,52->**3,72** (-14,80) | 6,62->8,28 (+1,66) |
| 8-12kHz | 10,41->**2,40** (-8,01) | 7,60->9,45 (+1,85) |
| 12-20kHz | 5,24->**2,01** (-3,23) | 4,84->7,68 (+2,84) |

**FIR1 verbessert sich in JEDEM Band drastisch** (v.a. Mitten/Hochmitten,
bis -14,9dB). **FIR2 verschlechtert sich in JEDEM Band leicht, mit
zunehmender Tendenz zu hohen Frequenzen** (4-20kHz: +1,2 bis +2,8dB).
Klassifikation: **breitbandig, mit leichtem Hochfrequenz-Schwerpunkt bei
der FIR2-Verschlechterung** - keine reine Transient-/Phasen-Ursache.

### 4/5. Komponenten-Interaktion (A/B/C/D, isoliert mit Pipeline A's eigenen
Stage-A-Parametern fuer alle vier Kombinationen, um NUR den FIR1/FIR2-
Tausch zu isolieren)

| Kombination | FNDR PANO | Fender AKG414 | Solid |
|---|---|---|---|
| A = V3 FIR1 + V3 FIR2 | 0,904 | 0,979 | 0,620 |
| B = V4 FIR1 + V3 FIR2 | 0,888 | 0,805 | **0,787** |
| C = V3 FIR1 + V4 FIR2 | 0,878 | 0,938 | 0,611 |
| D = V4 FIR1 + V4 FIR2 (= V4 gesamt) | **0,859** | **0,986** | **0,784** |

(Werte = Probe-Rohkorrelation gegen Pipeline A.)

**Drei unterschiedliche Muster:**
- **Solid:** FIR1-Verbesserung traegt die gesamte Verbesserung fast allein;
  FIR2 spielt kaum eine Rolle (C≈A).
- **Fender AKG414:** WEDER FIR1 NOCH FIR2 allein hilft (B und C beide
  schlechter als A!) - nur die VOLLSTAENDIGE V4-Kombination hilft (D>A).
  Das bestaetigt V4h's Befund direkt: Stage L fitted FIR1 und FIR2 GEMEINSAM
  (gemeinsame Fehlermetrik) - ein Mischen von V4-FIR1 mit V3-FIR2 zerstoert
  diese gemeinsame Kalibrierung.
- **FNDR PANO:** BEIDE Komponenten allein verschlechtern (B<A, C<A), UND
  die Kombination verschlechtert am staerksten (D<A<B,C). FNDR PANO ist der
  EINZIGE der drei getesteten Faelle, bei dem die volle V4-Rekalibrierung
  NICHT hilft, sondern schadet.

### 6. Modellcharakteristik

Aus bereits vorhandenen Metadaten (`nam_golden_corpus.dart`, keine neue
Annahme): **FNDR PANO ist das einzige der 5 Golden-Modelle mit einer
grundlegend anderen NAM-Architektur** - "plain WaveNet 0.5.4 (Tanh,
2 Layer-Arrays 16/8 Kanaele, 13.802 Gewichte)", waehrend alle vier anderen
(Solid, GOJIRA, JVM410H, Fender) "SlimmableContainer 0.7.0/WaveNet
0.7.0/LeakyReLU" verwenden. Diese dokumentierte, architektonische
Besonderheit (Tanh statt LeakyReLU, andere WaveNet-Variante) ist eine
plausible, datengestuetzte (nicht erfundene) Erklaerung dafuer, dass FNDR
PANOs Stage-L-Kalibrierung anders auf die V4i-Fensteraenderung reagiert als
die vier LeakyReLU/SlimmableContainer-Modelle - keine semantische
"cleaner Amp"-Spekulation, sondern eine dokumentierte Architekturdifferenz.

### 7. Generische Korrektur?

**NEIN** - kein generischer, modellunabhaengiger Defekt gefunden. Vier von
fuenf Modellen (inkl. des ebenfalls stark unterschiedlichen Fender-Falls)
profitieren klar von V4s vollstaendiger Rekalibrierung; nur FNDR PANO nicht,
mit einer plausiblen architektonischen Erklaerung. Eine Modell-spezifische
Sonderbehandlung ist laut Vorgabe ausdruecklich verboten. **V4 bleibt
unveraendert.**

### 8. Finale 5-Modell-Bewertung (V4 unveraendert, aus V4i wiederverwendet)

| Modell | CloData valide | FIR1 RMS | FIR2 RMS | Probe-Korr. raw | Gain-matched NRMSE |
|---|---|---|---|---|---|
| Solid | JA | 12,76dB | 3,86dB | 0,784 | 0,621 |
| GOJIRA | JA | 13,16dB | 4,14dB | 0,850 | 0,527 |
| JVM410H | JA | 7,06dB | 6,49dB | 0,788 | 0,616 |
| Fender AKG414 | JA | 1,70dB | 5,27dB | 0,986 | 0,167 |
| FNDR PANO | JA | 2,85dB | 8,97dB | 0,859 | 0,512 |

Alle 5 CloData-Ausgaben: 8232 Byte, alle Floats endlich, deterministisch,
Transport-Round-Trip fehlerfrei (0 Checksummenfehler, 0 fehlerhafte
Bloecke) - **bereits in V4i vollstaendig bestaetigt**, hier nochmals
verifiziert (kein Unterschied zu vorher, da V4 nicht geaendert wurde).

### 9. Hardware-Gate

**TRANSPORT SAFETY:** ERFUELLT - 8232-Byte-Struktur bei allen 5 Modellen
valide, Clone-5-Slot-Byte (0x04) und 590-Frame-Transport-Encoding stammen
unveraendert aus dem bereits in V1-V3 verifizierten, eingefrorenen
`nam_transfer_codec.dart` (in V4j nicht angefasst), Checksummen
reproduziert (0 Fehler), kein Store-Kommando irgendwo im Codepfad.

**MODEL REPRESENTATION:** ERFUELLT MIT EINSCHRAENKUNG - kein katastrophaler
Ausreisser, alle Werte endlich/beschraenkt, die unabhaengige Probe zeigt
bei 4/5 Modellen eine deutliche, bei FNDR PANO eine schwaechere (aber nicht
katastrophale) Aehnlichkeit (Korrelation weiterhin 0,86, nur gegenueber V3
leicht regressiert). Verbleibende Abweichungen sind vollstaendig
dokumentiert (V4f-j).

**RECOVERY/CONTAINMENT:** wird durch den Testplan (Abschnitt 10) erzwungen,
nicht durch diesen Meilenstein selbst veraendert.

**Bewertung:** die Kriterien fuer EINE kontrollierte Experiment-Freigabe
(nicht Produktionsfreigabe) sind erfuellt - alle 5 Ausgaben sind
strukturell sicher, keine Instabilitaet, dokumentierte (nicht versteckte)
Restabweichungen, und die Evidenz ist bei 4/5 Modellfamilien konsistent
stark. FNDR PANOs schwaechere Repraesentation ist verstanden (Architektur-
bedingt) und nicht sicherheitskritisch (keine Instabilitaet, nur ein
Aehnlichkeitsgrad).

### 10. V5-Testplan (NUR DEFINIERT, NICHT AUSGEFUEHRT)

Ziel: genau EIN kontrollierter Transfer auf den reservierten Clone-5-Slot
mit einem bekannten Forschungs-NAM (Vorschlag: JVM410H Standard - mittlere
Verbesserung, gut dokumentiert, keine Extremwerte).

Ablauf (nur Definition):
1. Aktuelles, offline erzeugtes 8232-Byte-CloData (Reference Signal V4,
   unveraendertes `MatriboxNamCloDataConverter`) fuer das gewaehlte Modell
   bereitstellen, Struktur ein letztes Mal vor der Uebertragung pruefen.
2. Nur den bestehenden, in V1-V3 verifizierten Transport-Encoder verwenden
   (590-Frame-Encoding, Slot-Byte 0x04, Stop-and-Wait-ACK).
3. Keine undokumentierten Kommandos, kein Store, kein Preset-Schreiben,
   kein Zugriff auf P01-P10.
4. Vollstaendiges Logging jedes gesendeten und empfangenen Bytes/Frames.
5. Sofortiger Abbruch bei jeder unerwarteten ACK-/Status-/Timeout-Antwort
   oder abweichendem Geraeteverhalten.
6. Erwartetes Erfolgskriterium: Geraet bestaetigt alle 590 Frames mit dem
   bekannten ACK-Muster, keine Fehler-Statusmeldung, Clone-5-Slot zeigt
   danach den uebertragenen Namen/Zustand (nur Lesen/Beobachten, kein
   Soundtest in diesem Schritt).
   Erwartetes Fehlschlagskriterium: jede ACK-Abweichung, Timeout, oder vom
   USBPcap-Referenzmuster (V1-V3) abweichendes Byte-Muster - sofortiger
   Abbruch, keine Wiederholung ohne erneute Freigabe.

**Dieser Plan wird in V4j NICHT ausgefuehrt.**

### 11. Absoluter Pegel - Risikobewertung (nicht behoben)

Der ungeklaerte 2-5x P/N-Unterschied bleibt bestehen. Risikobewertung fuer
EINE kontrollierte Uebertragung: **NIEDRIG** - P/N beeinflussen nur die
Kennlinien-Amplitude innerhalb der bereits geometrisch/strukturell validen
CloData (alle Werte endlich, im gueltigen Bereich, wie in V4e/V4g/V4i
mehrfach strukturell verifiziert); ein falscher absoluter Pegel bedeutet
potenziell "zu leise/zu laut klingender Testton", nicht eine ungueltige
Byte-Struktur oder ein Geraete-Sicherheitsrisiko. Keine 0,31/3,226-Korrektur
eingefuehrt.

### 12/13/14. Tests, Sicherheit, Git

Keine neuen Tests hinzugefuegt - V4j hat keine Produktions-/getrackte Datei
veraendert (nur Analyse-Skripte in `native/nam_bridge/out/`, bereits
gitignored, kein neues Verhalten abzusichern). Ausschliesslich offline in
V4j: kein ADB/USB/MIDI/SysEx/NAM-Upload/Store/Hardwarezugriff/Android.
Kein Commit, kein Push.

## V5A — Kontrollierte Clone-5-Hardware-Validierung: Preflight (offline)

Bereitet den ersten echten WyrmTone-generierten NAM-Transfer auf Clone 5
vor. **Nichts wurde an die Matribox gesendet.** Kein USB-/MIDI-Geraet
geoeffnet, keine Hardware-Enumeration, kein SysEx gesendet. Eine gesonderte
Freigabe ist fuer V5B (den echten Transfer) erforderlich.

### B/C. JVM410H-Quellidentitaet & finale V4-CloData-Identitaet

`tool/matribox_nam_analysis/v5_clodata_builder.dart` (`buildV5CloData()`):
baut CloData ausschliesslich ueber die eingefrorene Reference-Signal-V4-
Pipeline (eigenes Signal, eigene native NAM-Inferenz, unveraenderter
`MatriboxNamCloDataConverter`) - liest kein Sonicake-Asset.

| Feld | Wert |
|---|---|
| Quell-NAM | `D:/Desktop 3d sachen/Desktop/Marshall JVM410H - 100 Watt Head Boosted/Marshall JVM410H Boosted - Full Rig (Standard).nam` |
| NAM SHA-256 | `8e2c468813e0332d4c0907b2dd3ec120bdc863ac1778b7ddb7f34ed32f0ef859` (identisch mit dem bereits verifizierten Golden-Eintrag) |
| Architektur | SlimmableContainer 0.7.0 / WaveNet 0.7.0, LeakyReLU |
| Eingebetteter Clone-Name | `Marshall JVM410H Boosted - Full Rig (Standard).nam` |
| CloData-Laenge | 8232 Byte |
| CloData SHA-256 | `b00c2d0ca6e5679a863aedd1219d83684354cc219b82fd5e5fc864f1e2b20d2d` |
| Alle Werte endlich | JA (nach Korrektur eines Fehlers im eigenen Pruef-Skript - der urspruengliche naive Scan interpretierte auch Header-/Fuellbytes als Float32 und meldete faelschlich `false`; die korrigierte Pruefung nutzt exakt dieselben Byte-Bereiche wie die bereits etablierten V4e/V4g/V4i-Strukturchecks) |
| Alle Werte beschraenkt | JA |

### D. Clone-5-Transferplan

`tool/matribox_nam_analysis/v5_transfer_plan.dart` (`V5TransferPlan.build()`),
ausschliesslich ueber den bereits bestaetigten, unveraenderten
`nam_transfer_codec.dart` (`encodeCloneTransfer`):

- Frame-Anzahl: **590** (587 Bloecke 0..586 einmal + Block 587 dreifach)
- Jeder Frame validiert ueber `NamTransferFrame.parse` (Praefix, Slot,
  Blocknummer, Checksumme, `F7`-Trailer) - kein Frame kann diese Pruefung
  ohne exakte Uebereinstimmung mit dem bekannten Transportformat passieren
- Jeder Frame-Slot == `0x04` (Clone 5) - hart verdrahtet,
  `V5TransferPlan.build()` hat **keinen** Slot-/Clone-Parameter
- Letzter Block dreifach wiederholt, genau am Ende, exakt wie in den
  offiziellen Captures beobachtet

### E. Sicherheits-Hardschranken

Programmatisch erzwungen in `V5TransferPlan.build()` (wirft `StateError`,
kein stilles Degradieren): CloData-Laenge == 8232, Blockanzahl == 588,
Frame-Anzahl == 590, jeder Frame == bekannte Transport-Familie (Praefix-
Pruefung in `NamTransferFrame.parse`), jeder Frame-Slot == 0x04, keine
Blocknummer ausserhalb 0..587, letzter Block exakt 3x wiederholt. Kein
Store-Frame, kein generischer Roh-SysEx-Eingabepfad - der EINZIGE Weg,
ausgehende Bytes zu erzeugen, ist `NamTransferFrame.encode()`.

### F/G. ACK-Zustandsautomat & Trockenlauf

`tool/matribox_nam_analysis/v5_ack_state_machine.dart`
(`V5AckStateMachine`), betrieben ausschliesslich gegen
`v5_fake_transport.dart` (rein simulierte Gegenstelle, kein Geraet). Fuer
jeden Frame: senden -> auf GENAU eine Antwort warten -> als `NamTransferAck`
parsen -> Slot/Block/Status validieren -> erst dann fortfahren. Bei
Timeout/Fehlformat/falschem Slot/falschem Block/Fehlerstatus/zusaetzlicher
Nachricht: **sofortiger Abbruch**, kein automatischer Retry (ausser den
bereits im Plan enthaltenen 3 Wiederholungen des letzten Blocks).

Fehlerinjektion (7 Szenarien A-G, `test/tool/v5_ack_state_machine_test.dart`,
17 Tests, alle gruen):

| Szenario | Ergebnis |
|---|---|
| A: alle ACKs korrekt | Transfer vollstaendig, 590/590 ACKs, letzter bestaetigter Block = 587 |
| B: Timeout | Abbruch genau beim betroffenen Frame, kein weiterer Versand |
| C: fehlerhaftes ACK | Abbruch |
| D: falscher Slot im ACK | Abbruch |
| E: falsche Blocknummer im ACK | Abbruch |
| F: Fehlerstatus im ACK | Abbruch |
| G: zusaetzliche unerwartete Nachricht | Abbruch |
| Spaeter Fehler (nahe der Block-Wiederholung) | Abbruch, kein Teilerfolg |

### I. Schreibbudget

`V5WriteBudget`: genau EIN Transferversuch pro Instanz, erzwungen VOR dem
ersten Sendeversuch (`consumeAttempt()` wirft bei zweitem Aufruf) - auch
nach einem fehlgeschlagenen Versuch gibt es keinen automatischen Neustart
(Test: "a failed attempt still consumes the budget").

### J. Logging

`V5LogEntry` pro versuchtem Frame: Zeitstempel, Frame-Ordinalzahl,
logischer Block, Ziel-Slot, sichere Hex-Darstellung des ausgehenden Frames,
ACK-Ankunftsdauer, ACK-Block, ACK-Status, Abbruchgrund. `V5TransferSummary`:
geplante/gesendete Frames, empfangene ACKs, letzter bestaetigter Block,
Ergebnis, Abbruchgrund. Keine unbezogenen Geraete-/Personendaten protokolliert.

### K. Preset-Isolationsnachweis

Struktureller Test (`v5_transfer_plan_test.dart`): keine der drei V5-
Kerndateien importiert oder referenziert (ausserhalb von Kommentaren)
`matribox_chain_*`, `matribox_tone_transfer_*`, `p01_readback_*`,
`confirmed_parameter_codec`, `usb_controller` oder MIDI-Empfangsklassen.
Zusaetzlich strukturell erzwungen: `V5TransferPlan.build()`s Signatur
enthaelt keinen Slot-/Clone-Parameter - der Clone-5-Zielwert ist nicht
veraenderbar, nicht nur per Konvention, sondern per Typsignatur.

### L. Checkliste fuer Marcel vor V5B (NICHT ausgefuehrt)

1. Matribox normal eingeschaltet und betriebsbereit.
2. Sonicake-Editor geschlossen (keine Ueberschneidung mit WyrmTones Zugriff).
3. Clone 5 ist bewusst als Opfer-Slot gewaehlt - Marcel muss den aktuellen
   Inhalt von Clone 5 NICHT schuetzen (kann ueberschrieben werden).
4. Stabile USB-/MIDI-Verbindung (kein Hub-Wechsel waehrend des Transfers).
5. Bestaetigt: das zu uebertragende Modell ist JVM410H Standard.
6. Verstanden: dies ist ein experimenteller Forschungstest, keine
   produktionsreife Funktion - das Klangergebnis kann von Sonicakes
   eigenem Editor abweichen.

### M. Erwartete Hardware-Beobachtungen (fuer V5B)

**TRANSPORT-ERFOLG:** jedes erwartete ACK akzeptiert, Transfer erreicht die
bekannte Abschlusssequenz (3x Block 587), keine unerwartete Antwort/Status.
**GERAETE-ERFOLG:** Geraet bleibt reaktionsfaehig, Clone 5 bleibt
zugaenglich, keine unbeabsichtigten Preset-Aenderungen. **MODELL-ERFOLG:**
Clone 5 liefert nach manueller Auswahl ein benutzbares Gitarrensignal, keine
extreme Instabilitaet/Rauschen/Stille als Zeichen einer klar ungueltigen
Modell-Repraesentation. Exakte klangliche Identitaet mit Sonicakes Editor
wird fuer den ersten Hardware-Erfolg NICHT gefordert.

### N. Fehlerklassifikation

`TRANSPORT_FAIL` (ACK-Zustandsautomat bricht ab) / `DEVICE_BEHAVIOR_FAIL`
(Geraet reagiert nicht mehr, unerwarteter Zustand nach Transport-Erfolg) /
`MODEL_OUTPUT_FAIL` (Transport und Geraet erfolgreich, aber Klangergebnis
eindeutig ungueltig) / `SUCCESS` (alle drei Ebenen erfolgreich). Ein
Transport-Erfolg mit schlechtem Klang ist KEIN voller Erfolg; eine
plausibel aussehende ACK-Sequenz ohne manuelle Klangpruefung ist KEIN
voller Erfolg.

### O. V5B-Einstiegspunkt (nur benannt, nicht implementiert, nicht aufgerufen)

Ein zukuenftiges `tool/matribox_nam_analysis/v5b_execute_clone5_transfer.dart`
(existiert NICHT in V5A) muesste: im Terminal deutlich "EXPERIMENTAL",
"CLONE 5" und "JVM410H" ausgeben, vor jedem Sendeversuch eine explizite
Endbestaetigung verlangen (z. B. exaktes Eintippen einer Bestaetigungsphrase,
kein einfaches Ja/Enter), und **keinen generischen Zielslot-Parameter**
besitzen (wie `V5TransferPlan.build()` selbst). Dieser Einstiegspunkt wurde
in V5A weder erstellt noch aufgerufen.

### P. Tests/Analyze

`test/tool/v5_transfer_plan_test.dart` (6 Faelle) +
`test/tool/v5_ack_state_machine_test.dart` (11 Faelle) = 17 Faelle, alle
gruen. `dart analyze tool/matribox_nam_analysis test/tool`: clean.
Sicherheits-Grep bestaetigt: keine der vier neuen V5-Dateien referenziert
irgendeine USB-/MIDI-/Seriell-/FFI-Bibliothek.

### Q/R. Git-Status, Sicherheit

`git status` unveraendert zum bisherigen Diff-Stand. Ausschliesslich
offline in V5A: kein ADB, kein USB-Geraet geoeffnet, kein MIDI-Geraet
geoeffnet, kein SysEx gesendet, keine Matribox-Verbindung, keine Hardware-
Enumeration, kein NAM-Transfer, kein Store, kein Preset-Zugriff. Kein
Commit, kein Push.

## V5B.1 — Android MIDI Send Transport fuer den kontrollierten Clone-5-Test

Kleinstmoegliche, sichere Sendefaehigkeit hinzugefuegt, damit der bereits
eingefrorene V5-Clone-5-Transfer spaeter ausgefuehrt werden kann. **Kein
Byte an die echte Matribox gesendet** - das verbundene Telefon wurde nicht
zum Testen des Senders verwendet.

### 1/2. Bestehender Android-MIDI-Pfad & Port-Richtung

Nachvollzogen von `lib/services/usb_service.dart` durch den MethodChannel
(`de.neevel.wyrmtone/usb_methods`) zu `UsbPlatformChannels.kt` ->
`MidiDiagnosticsManager.kt`. **Bestaetigt (nicht angenommen):**
`MidiDevice.openInputPort(0)` = App->Geraet (Senden, bereits zweifach im
bestehenden Code verwendet: `MatriboxPresetReaderPort`,
`MatriboxToneTransferWriterPort`, beide via `input.send(...)`);
`MidiDevice.openOutputPort(...)` = Geraet->App (Empfangen, verwendet vom
passiven Monitor). Lifecycle/Cleanup: `closeDevice()` schliesst alle
Sender inkl. des neuen; Threading: blockierende Operationen laufen auf
`blockingExecutor`, nie auf dem Plattform-Kanal-Thread.

### 3/4. Minimale Sende-API

`MatriboxNamCloneSendPort.kt` (neu): `sendFrame(frame: NamCloneTransferFrame)`
- **kein** Slot-Parameter, **keine** SysEx-Konstruktion, **kein** roher
`ByteArray` im Interface (siehe wichtiger Befund unten). Gated durch
`BuildConfig.DEBUG && BuildConfig.REAL_MATRIBOX_WRITE` - neue, dritte
Compile-Gate, in `build.gradle.kts` **hart auf `false`** verdrahtet (kein
Dart-Define-Pfad existiert dafuer), sodass sie in diesem Meilenstein durch
nichts aktivierbar ist.

**Wichtiger Befund waehrend der Umsetzung:** die bestehende statische
Sicherheitspruefung (`test/native_safety_static_test.dart`) verbietet
explizit jeden Sender, dessen Override-Signatur `ByteArray` roh entgegennimmt
("nothing but typed, validated values reaches the port"). Eine
naive `sendBytes(bytes: ByteArray)`-API haette das gebrochen - zu Recht,
denn ein reiner Byte-Durchreicher gibt der nativen Seite keine eigene,
unabhaengige Verteidigungsschicht. Loesung: `NamCloneTransferFrame` ist
undurchsichtig und nur ueber `MatriboxNamCloneTransferReference
.parseValidated()` konstruierbar - eine native Kotlin-Nachbildung von
`nam_transfer_codec.dart`s bestaetigtem Wire-Format (Praefix, Laenge=47,
**Slot==0x04 hart verdrahtet**, Blockbereich 0..587, Checksumme, F7-
Abschluss). Ungueltige oder falsch adressierte Bytes koennen den Port
strukturell nie erreichen - dieselbe Sicherheitsarchitektur wie bei den
beiden bestehenden Sendern, nur mit dem Wire-Format statt einem
Preset-/Live-Edit-Objekt als "Vertrauensanker".

### 5/6. Testbarkeit & Byte-Integritaet

`lib/services/v5_android_transport.dart` (`V5AndroidTransport`): nimmt nur
zwei injizierte Funktionen/Streams entgegen (`sendBytes`, `incoming`) -
beruehrt nie `UsbService` oder einen Plattform-Kanal direkt. Bewiesen mit
echten Frames aus dem eingefrorenen V5A-Plan (erster, mittlerer, letzter
wiederholter Block): Dart-`Uint8List` -> `V5AndroidTransport` ->
`V5LibTransportAdapter` (tool/-seitige Bruecke, siehe unten) - bytegleich
in allen drei Faellen (`test/tool/v5_lib_transport_adapter_test.dart`).

**Architektur-Randbedingung:** `lib/`-Dateien duerfen laut Darts eigenen
Paketregeln keinen relativen Import verwenden, der aus `lib/` hinausfuehrt
(direkt verifiziert: `dart analyze` meldet "Target of URI doesn't exist"
selbst wenn die Zieldatei existiert). Deshalb definiert
`v5_android_transport.dart` eine eigene, strukturell identische Kopie von
`V5Transport`/`V5TransportResponse` (dasselbe bewusste Dopplungsmuster wie
bei jeder V1->V2->V3->V4-Signalgrenze in diesem Projekt), und
`tool/matribox_nam_analysis/v5_lib_transport_adapter.dart` verbindet beide
Seiten ueber `package:wyrmtone/...` (die Richtung, die Dart erlaubt).

### 7/8. Failure Behavior

`V5AndroidTransport`: Timeout, `sendBytes`-Exception (propagiert ohne
Retry-Versuch), und eine zusaetzliche unerwartete Nachricht innerhalb der
"Quiet Period" werden alle korrekt erkannt (Dart-Tests, 5 Faelle).

### 9. ACK-Empfangskompatibilitaet - **ehrlicher Befund, kein Uebergehen**

Der bestehende Empfangspfad (`MidiReceiveSource`/`startMidiCapture`) ist
der **passive Diagnose-Monitor**, und `ProbeEligibility.check()` - von
JEDEM Sender durchlaufen, auch dem neuen - verlangt explizit `!monitoring`.
**Das heutige Architektur erlaubt kein gleichzeitiges Senden und passives
Monitoring.** Ein echtes Stop-and-Wait-ACK-Protokoll braucht einen
Empfangspfad, der WAEHREND des Sendens offen bleibt - das existiert noch
nicht und ist bewusst NICHT Teil dieses "kleinstmoeglichen, sicheren"
Meilensteins. `V5AndroidTransport.incoming` ist deshalb in diesem
Meilenstein ausschliesslich ein Fake-Stream in Tests - es gibt noch keine
echte Implementierung, die etwas liefern koennte.

### 10. V5-Zustandsautomat offline verdrahtet

`test/tool/v5_lib_transport_adapter_test.dart`: der ECHTE, in V5A
eingefrorene `V5AckStateMachine` laeuft durch `V5LibTransportAdapter` gegen
Fakes - Happy Path **590/590** bestaetigt, Timeout-Fehlerinjektion bricht
korrekt beim betroffenen Frame ab. Rein offline, kein Geraet beteiligt.

### 11. Hartes V5-Ziel-Lock

Unveraendert aus V5A: `V5TransferPlan.build()` hat keinen Slot-Parameter.
Neu bestaetigt: `sendNamCloneTransferFrame` im Kotlin-Methodkanal nimmt nur
`bytes` entgegen (statischer Test prueft das Fehlen von "slot", "clone5",
"store", "preset", "sysex" im Kanal-Codeblock). Kein Modell-/Slot-Picker,
keine rohe SysEx-Eingabe existiert irgendwo.

### 12. Kill-Switch

`REAL_MATRIBOX_WRITE` - dritte Compile-Gate, hart `false` in
`build.gradle.kts` (beide Build-Typen), kein Dart-Define-Pfad. Bestehender
statischer Sicherheitstest (`native_safety_static_test.dart`) erweitert
und verifiziert: exakt drei Gates, alle `false` im Release, jeder in
Kotlin verwendete `BuildConfig`-Flag ist eines der drei bekannten.

### Bestehende Sicherheitsnetz respektiert, nicht umgangen

`test/native_safety_static_test.dart` (5 Tests) wurde bewusst erweitert -
nicht abgeschwaecht: der neue Sender ist jetzt Teil der Liste "genau drei
gated Sender", jeweils mit GENAU einem `.send(`-Aufruf, eigener Gate-
Pruefung, eigener Validierung vor dem Senden, und OHNE rohen `ByteArray`
in der Override-Signatur (durch das `NamCloneTransferFrame`-Design
strukturell, nicht nur textuell, erfuellt). Alle 5 Tests gruen.

### Tests/Analyze

Dart: `dart analyze lib test tool/matribox_nam_analysis` - clean. Neue
Tests: `test/v5_android_transport_test.dart` (5), `test/tool/
v5_lib_transport_adapter_test.dart` (3), `test/native_safety_static_test
.dart` (erweitert, 5) - alle gruen. Bestehende betroffene Tests erneut
gelaufen (`usb_controller_test.dart`, `midi_capture_panel_test.dart`) -
weiterhin gruen (28 Faelle).

Kotlin: `MatriboxNamCloneTransferReferenceTest.kt` (9 Faelle: Format-,
Slot-, Laengen-, Praefix-, Block-, Checksummen-, Trailer-Validierung, Kill-
Switch) geschrieben, folgt exakt dem bestehenden JUnit-Stil - **konnte
in dieser Sitzung nicht tatsaechlich ausgefuehrt werden**: der Gradle-
Testlauf schlug wegen Speicherplatzmangel auf C: fehl (~1,98GB frei,
AGP-Instrumentierungs-Cache braucht mehr), ein bekanntes, bereits aus V4a
dokumentiertes Umgebungsproblem. Kein Cleanup-Versuch ohne Rueckfrage
unternommen (bestehende Projektregel). Code wurde sorgfaeltig gegen das
bestehende Muster (`MatriboxToneTransferTest.kt` etc.) und gegen den bereits
gruenen `native_safety_static_test.dart` abgeglichen, ist aber bis zur
naechsten erfolgreichen Gradle-Ausfuehrung **ungetestet, nicht nur
theoretisch korrekt**.

### Sicherheit

Ausschliesslich offline in diesem Meilenstein: kein Byte an die reale
Matribox gesendet, keine Verwendung des verbundenen Telefons zum Testen.
Kein Commit, kein Push.

## V5B.2a — Bidirektionale NAM-Transfer-Sitzung + Telefon-Installation (blockiert vor Build)

**Kein Byte an die echte Matribox gesendet.** `REAL_MATRIBOX_WRITE` bleibt
`false`. APK-Build/Telefon-Installation NICHT durchgefuehrt - Speicherplatz
auf C: reicht nicht (siehe unten), wie in Punkt 12 gefordert gemeldet statt
selbst bereinigt.

### 1-4. Architektur

`MatriboxNamTransferSession.kt` (neu): einzige Stelle im Repository, die
gleichzeitig einen Sende- (`MatriboxNamCloneSendPort`, `openInputPort(0)`)
und einen Empfangs-Port (`ReceiveOnlyMidiPort`, `openOutputPort(...)`,
bestehendes Interface aus `PassiveMidiMonitor.kt` wiederverwendet) haelt.
ACK-Rahmung/-Validierung: `MatriboxNamCloneTransferReference
.parseValidatedAck()` (neu) - eigene native Kopie des bestaetigten
18-Byte-ACK-Formats, verwirft alles, was nicht exakt passt.

### 3. Passiv-Monitor-Isolation (beide Richtungen getestet)

Richtung "Monitor->Sitzung": `ProbeEligibility.check()` (bereits von allen
drei Sendern durchlaufen) verlangt `!monitoring` - dynamisch bestaetigt
(`not eligible (monitoring active) refuses...`-Test). Richtung
"Sitzung->Monitor": `startCapture()` verweigert jetzt, solange
`currentNamTransferSession?.isActive == true`, VOR jedem Monitor-Zugriff -
statisch verifiziert (`native_safety_static_test.dart`, neuer Test).

### 5/6. Strikt Stop-and-Wait, Timeout/Abbruch

Blockierende `LinkedBlockingQueue` je Sitzung: Senden -> auf GENAU eine
naechste Nachricht warten (Timeout konfigurierbar) -> zusaetzliche
Nachricht innerhalb der Ruheperiode = Abbruch -> validieren
(Slot/Block/Status) -> erst dann naechster Frame. Kein Pipelining, kein
automatischer Retry (nur die bereits im Plan enthaltene Wiederholung des
letzten Blocks bleibt erlaubt, wie in V5A).

### 7. Sitzungs-Bereinigung (deterministisch bewiesen)

`cancel()` (neu) schliesst beide Ports von einem ANDEREN Thread aus,
waehrend `execute()` auf ein ACK wartet - bewiesen mit einem echten
Hintergrund-Thread-Test (`cancel while a send is blocked...`). In
`MidiDiagnosticsManager.closeDevice()`/`onUsbDetached()` verdrahtet -
statisch verifiziert.

### 8/9. Fake-End-zu-Ende-Test & Fehlerinjektion

`MatriboxNamTransferSessionTest.kt` (neu, 15 Faelle): Happy Path mit
strikter Ordnungspruefung (jedes ACK unmittelbar nach seinem Send, nie zwei
Sends ohne dazwischenliegendes ACK), **echter 590-Frame-Fake-Transfer**
(JVM410H->Clone5-Groesse) mit Ordnungspruefung "keine Frame-Nummer vor
ihrer Vorgaengerin gesendet", Timeout (frueh + mittig), fehlerhaftes ACK,
falscher Slot, falscher Block, Fehlerstatus, zusaetzliche Nachricht,
Sende-Exception, Empfangs-Port-Oeffnen-Exception, Nicht-berechtigt (Monitor
aktiv), Abbruch vor erstem Senden, Abbruch waehrend Warten, `isActive`-
Zustand. **Jeder Fehlerfall bestaetigt: kein Frame danach gesendet.**

### 10/11. Kill-Switch & Ziel-Isolation

`REAL_MATRIBOX_WRITE` unveraendert `false` (kein Dart-Define-Pfad, kein
Debug-Button, kein Laufzeit-Bypass hinzugefuegt). Weiterhin nur
JVM410H->Clone5(0x04): `executeNamCloneTransferSession` im Kanal nimmt nur
`frames` entgegen, statisch gegen "slot/clone5/store/preset/sysex"
geprueft.

### Bereinigung ueberholter V5B.1-Duplizierung

`sendNamCloneTransferFrame` (V5B.1) und die neue Sitzung teilten sich sonst
zwei getrennte `openInputPort(0)`-Aufrufstellen - zu einer gemeinsamen
privaten `openNamCloneSendPort()`-Hilfsfunktion konsolidiert (kein
zwischengespeicherter Port mehr, jeder Aufruf oeffnet/schliesst frisch) -
haelt die bestehende "genau drei Sender"-Zaehlung im statischen
Sicherheitstest exakt.

### 12. Kotlin-Tests - BLOCKIERT, nicht selbst bereinigt

`MatriboxNamCloneTransferReferenceTest.kt` (V5B.1, 9 Faelle) +
`MatriboxNamTransferSessionTest.kt` (neu, 15 Faelle) geschrieben, folgen
dem bestehenden JUnit-Stil, **nicht ausgefuehrt**:

- Freier Speicher auf C: aktuell: **2,01 GB**
- `C:\Users\simpl\.gradle\caches`: 1,33 GB
- `C:\Users\simpl\.gradle\wrapper`: 0,68 GB
- `C:\Users\simpl\AppData\Local\Android\Sdk`: 6,39 GB
- `C:\Users\simpl\AppData\Local\Temp`: 0,04 GB
- (`D:\Develop\Wyrmtone\build`: 2,35 GB - liegt auf D:, nicht Teil des
  C:-Engpasses)

Der Gradle-Testlauf schlug bereits beim reinen `testDebugUnitTest`-Versuch
fehl ("nicht genug Speicherplatz", beim Instrumentieren der AGP-/Kotlin-
Abhaengigkeits-Jars in `.gradle\caches\...\transforms\`). Ein APK-Build ist
ressourcenintensiver als ein reiner Testlauf und wuerde hoechstwahrscheinlich
am selben Punkt scheitern. **Vorgeschlagene minimale Bereinigung** (nicht
durchgefuehrt, wartet auf deine Freigabe): `C:\Users\simpl\.gradle\caches`
leeren (1,33 GB, von Gradle bei Bedarf automatisch neu aufgebaut/
heruntergeladen - kein Quellcode- oder Projektverlust, aber der naechste
Build wird dadurch langsamer). Falls das nicht reicht, zusaetzlich
`%LOCALAPPDATA%\Temp` pruefen (aktuell klein, 0,04 GB, vermutlich schon
weitgehend bereinigt von V4a).

### 13. Dart/Flutter-Tests - vollstaendig gruen

`dart analyze lib test tool/matribox_nam_analysis`: clean. Alle betroffenen
Tests erneut gelaufen: `native_safety_static_test.dart` (6, inkl. der neuen
Isolations-/Cleanup-Pruefung), `v5_android_transport_test.dart` (5),
`v5_lib_transport_adapter_test.dart` (3), `v5_transfer_plan_test.dart` (6),
`v5_ack_state_machine_test.dart` (17), `usb_controller_test.dart` (26),
`midi_capture_panel_test.dart` (2) - alle gruen.

### 14/15. APK-Build & Telefon-Installation - NICHT VERSUCHT

Wegen des Speicherplatz-Engpasses nicht versucht (haette wahrscheinlich
denselben Fehler wie der Kotlin-Testlauf reproduziert, ohne neue Erkenntnis
zu liefern, aber Zeit/Speicher verbraucht). Kein Zugriff auf die Matribox
erfolgte oder war noetig, da dieser Schritt gar nicht erreicht wurde.

### 16. Sicherheit/Git

Ausschliesslich offline: kein Byte an die reale Matribox, keine
Geraete-Enumeration der Matribox in diesem Meilenstein. Kein Commit, kein
Push. Kein Speicherplatz-Cleanup ohne Rueckfrage durchgefuehrt.
