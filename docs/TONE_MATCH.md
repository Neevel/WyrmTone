# Tone Match (V1) – Research, ADR, Grenzen

Status: Slice 1 (Song/Artist → Intent → NAM-Ranking → Plan) und Slice 2 (reproduzierbare akustische Charakterisierung von NAMs mit einem DI-Evaluation-Signal) sind umgesetzt. Slice 2 ist noch nicht an die UI oder das Ranking angebunden. Ähnlichkeit und Optimierung sind **nicht implementiert**.

## 1. Research-Bewertung (live geprüft am 2026-10-02)

Quellen: GitHub-Repositories und GitHub-API der jeweiligen Projekte (Lizenz-Feld, `pushed_at`, `archived`, letztes Release). Aussagen zu Android/Modellgröße stammen aus den Projekt-READMEs oder sind als *nicht verifiziert* markiert. Diese Tabelle ersetzt die frühere Fassung aus Fachwissen; die Entscheidung „eigene STFT in Dart“ bleibt bestehen.

| Projekt | Lizenz (verifiziert) | Wartung | Android | Native Abhängigkeiten | Größe/Impact | Urteil |
|---|---|---|---|---|---|---|
| Essentia | AGPL-3.0 | aktiv (Push 2026-09-30); GitHub-„latest release“ ist ein Tag von 2014, aktuelle Version nicht verifiziert | `build_android.sh` vorhanden | C++ (waf), optional TensorFlow | nicht verifiziert | **nicht verwenden** (AGPL); Modell-Lizenzen nicht geprüft |
| librosa | ISC | aktiv (Release 1.0.0 vom 2026-08-11, Push 2026-09-29) | nein (Python/NumPy/SciPy) | Python-Stack | – | nur Offline-Referenz für Golden-Werte |
| aubio | GPL-3.0 | Push 2026-04-10; letztes Release 0.4.9 (2019) | im README nicht genannt | C | klein | **nicht verwenden** (GPL; Pitch/Onset ohne Timbre-Mehrwert) |
| TarsosDSP | GPL-3.0 | Release 2.5 (2023), Push 2026-06-18 | ja (Java) | JTransforms, libresample4j | klein | **nicht verwenden** (GPL, JVM statt Dart/FFI) |
| OpenL3 (marl/openl3) | MIT (Code); torchopenl3-Fork nennt Apache-2.0 | letzter Push 2023-06, Release 0.4.2 (2023-05) | nicht genannt | Keras/TF bzw. PyTorch | Gewichte-Lizenz und Größe nicht verifiziert | zurückgestellt (kaum gepflegt, kein Nachweis für Amp-Timbre) |
| LAION-CLAP | CC0-1.0 (Code) | letzter Push 2025-05-15 | README: PyTorch/CUDA, nicht mobil-optimiert | PyTorch | Checkpoints nicht verifiziert | verworfen für V1; Checkpoint-Lizenzen vor Nutzung prüfen |
| NeuralAmpModelerCore | MIT | sehr aktiv (Release v0.6.0, 2026-10-01); unser Vendor-Stand ebenfalls 0.6.0 | bereits produktiv eingebunden | Eigen (vendored), CMake | bereits im APK | bleibt die einzige NAM-Runtime |

Folge: keine neue Dependency. Slice 2 nutzt eigene STFT/Features in Dart, die vorhandene `NamInferenceEngine` und die vorhandene Hash-Funktion. Native Auslagerung erst, wenn die Performance-Messung es verlangt.

## 2. Wichtige Befunde im Bestand

- `lib/tonevault/` enthält bereits Künstler-/Album-/Song-/Genre-Wissen mit Quellenklasse, Confidence, Amp-Familien, NAM-Tags, Cab/Speaker/Mic und Effekt-Hinweisen. Tone Match **wiederverwendet** das über einen `ToneKnowledgeProvider`, statt eine zweite Wissensbasis zu bauen.
- „The Loner“ und „Heresy“ haben **keinen eigenen Song-Eintrag**; der Resolver fällt ehrlich auf den Künstlerstil zurück (Evidenz `INFERRED`, Song unbekannt).
- `NamInferenceEngine` (native NAM-Inferenz) existiert; Slice 2 nutzt sie, ohne sie zu ändern.

## 3. Architecture Decision Record

**Entscheidung:** Hybride, providerunabhängige Pipeline in `lib/tonematch/`, ohne neue schwere Dependency und ohne Änderung an NAM-Protokoll, CloData V4, Reference Signal V4, Android-Bridge oder Write-Gates.

```
ToneMatchRequest
 → ToneIntentResolver (ToneKnowledgeProvider: Local[ToneVault] | optional Online)
 → ToneIntent (+ ToneEvidence je Feld)
 → NamCandidateProvider (Metadaten-Ranking, lokale Library)
 → [Slice 2] NamAnalyzer + AudioFeatureExtractor + ToneSimilarityEngine + ToneMatchCache
 → [Slice 3] ToneOptimizer
 → TonePlanBuilder (abstrakt) → DeviceTonePlan (DeviceCapabilities)
 → ToneMatchResult → vorhandener NAM-Detail-/Transferflow (nie automatisch)
```

Komponenten (Dateien in `lib/tonematch/`):

| Komponente | Verantwortung |
|---|---|
| `ToneMatchController` | Zustand, Phasen, Cancel; keine Logik |
| `ToneKnowledgeProvider` / `LocalToneKnowledgeProvider` | Text → `ToneIntent` aus ToneVault |
| `NamCandidateProvider` | LocalNamCapture → Kandidaten + Metadaten-Score |
| `TonePlanBuilder` | Intent + Kandidat → abstrakter `TonePlan` |
| `DeviceAdapter` | `TonePlan` + `DeviceCapabilities` → `DeviceTonePlan` (ehrliche Transfer-Flags) |
| (Slice 2) `NamAnalyzer`, `AudioFeatureExtractor`, `ToneSimilarityEngine`, `ToneMatchCache` | siehe unten |
| (Slice 3) `ToneOptimizer` | siehe unten |

**ToneIntent** ist geräteunabhängig (0–100-Skalen, wie ToneVault-Dimensionen) und trägt je Aspekt eine `ToneEvidence` (`KNOWN`, `MEASURED`, `LIBRARY_METADATA`, `USER_INPUT`, `INFERRED`, `HEURISTIC`, `UNKNOWN`). Es gibt keinen Confidence-Prozentwert, sondern eine grobe Stufe.

**Scores:** `MetadataScore` (V1, heuristisch: Treffer von Amp-Familien/NAM-Tags/Rolle, Kompatibilität) ist eine *Rangzahl zum Sortieren*, kein „Prozent klingt wie“. In der UI erscheint nur eine Stufe („passt gut / passt teilweise / unsicher“) plus die Gründe. Spätere Anteile: `AudioFeatureScore`, `ReferenceAudioScore`, `IntentScore`, `DeviceFeasibilityScore`, `UserPreferenceScore`; Gewichte rollenabhängig (Rhythm: Tightness/Attack/Low-Mid; Lead: Sustain/Mids/Glätte/Raum).

**Slice 2 (Audioanalyse):** siehe Abschnitt 5 (Spezifikation und Architektur).

**Slice 3 (Optimierung), Entwurf:** kleiner Raum (Gain, Bass, Mid, Treble, Presence) nur für von `DeviceCapabilities` unterstützte Parameter; Random-Search-Baseline mit Seed → coarse-to-fine; CMA-ES nur, wenn der Benchmark es belegt. Messung baseline vs. optimiert.

**Audio-Referenz (Modus B):** Architektur vorbereitet (`ToneMatchRequest.mode`), in V1 **nicht** als Button sichtbar. Ein gemasterter Mix ist kein isolierter Gitarrenton; der Ansatz wäre: isolierte Spur/eigener Referenzton → gleiche Feature-Distanz. Keine Behauptung, aus einem Master den exakten Amp zu rekonstruieren. Keine Spotify/YouTube-Extraktion.

**Datenschutz:** Audio lokal, kein Upload, keine Pfad-/Audiologs. Kein API-Key im APK; optionaler Online-Provider nur hinter dem Interface und nach Zustimmung.

**Gating der Fähigkeiten:** NAM-Transfer und Preset-/Sound-Transfer sind getrennte Capabilities. V1 setzt `namTransfer` aus dem bestehenden Flow (Nutzer übertragen explizit) und `presetTransfer = false` mit ehrlichem Hinweis, solange kein produktiver Tone-Transfer für den Plan existiert.

## 4. Was Tone Match V1 kann / nicht kann

Kann: Song/Artist-Text auf einen Klangstil abbilden (aus ToneVault, quellenmarkiert), lokale NAMs nach Metadaten ranken, einen abstrakten Plan mit Begründung und Unsicherheiten zeigen, in den vorhandenen NAM-Detail-Flow springen.

Kann nicht: den Originalklang eines Songs rekonstruieren; Audio vergleichen (noch nicht); Parameter optimieren (noch nicht); etwas automatisch übertragen.

Alle Rangzahlen in V1 sind **heuristisch (Metadaten)**; nichts davon ist gemessen.

## 5. Slice 2: Evaluation-Signal, Analyse-Architektur (vorbereitet, nicht implementiert)

Status: Code vorbereitet (`evaluation_signal.dart`, `tone_features.dart`, `analysis_interfaces.dart`). Es gibt **kein** Evaluation-Signal und **keine** Analyse, bis die selbst aufgenommenen WAVs vorliegen. Es wird kein synthetisches Ersatzsignal erzeugt; `EvaluationSignalRegistry.bundled` ist leer. CloData Reference V4 bleibt vollständig getrennt.

### 5.1 Aufnahme-Spezifikation (DI Evaluation Set v1)

**Format der Originalaufnahmen (tatsächlich aufgenommen):** WAV, Stereo, 44,1 kHz, 24 Bit PCM (Matribox USB Audio; links = DRY, rechts = WET). Nur der linke Kanal ist das Evaluation-Signal, der rechte wird nie verwendet. Die Originale bleiben unverändert. Die `NamInferenceEngine` braucht mono Float32 bei 48 kHz und resampelt nicht; deshalb gibt es genau einen zentralen Resampling-Schritt (siehe 5.2). *(Die ursprüngliche Spezifikation „nativ 48 kHz mono“ wurde durch das reale Aufnahmegerät korrigiert.)*

**Aufnahme-Setup v1:** Harley Benton Fusion 4 HSH, Steg-Humbucker, Volume/Tone voll offen, E-Standard, Rec Mode Left = DRY / Right = WET, Rec Level +9 dB, Monitor 0 dB, keine Nachbearbeitung. Gemessen (Dry-Kanal): RHYTHM 29,12 s, Peak −9,64 dBFS; LEAD 24,15 s, −13,97 dBFS; CLEAN 14,28 s, −9,07 dBFS; kein Clipping. Beobachtung: Der Rauschteppich ist nicht überall „echtes Interface-Rauschen“ (RHYTHM-Kopf ≈ −132 dBFS, LEAD/CLEAN ≈ −89 dBFS); das beeinflusst die Analyse nicht, weil aktive Frames am DI-Pegel hängen.

**Signalweg:** Gitarre → Hi-Z-Instrumenteneingang des Audiointerfaces → DAW-Spur. Kein Amp, Cab, IR, EQ, Compressor, Reverb, Delay, Gate, Limiter, keine Plugins und kein Monitoring-Effekt in der Spur. Beim Export: kein Normalisieren, kein Dither, kein Limiter, kein Fade. Nur Schnitt am Anfang/Ende gemäß Stille-Regel.

**Pegel:** Interface-Gain einmal einstellen und für alle drei Dateien **gleich lassen**. Lauteste Anschläge ca. −10 dBFS Peak (Bereich −12 bis −8), nie clippen (kein Peak über −3 dBFS). Leiseste gespielte Noten sollen noch deutlich über dem Rauschen liegen (Peak nicht unter ca. −40 dBFS). Die Interface-Einstellung bitte notieren (Gain-Stellung, Gitarren-Volume/Tone offen).

**Stille:** 0,5 s Raumrauschen am Anfang (echtes Interface-Rauschen, kein digitales Null, kein Gate), 1,5 s Ausklingen am Ende. Zwischen den Abschnitten mindestens 0,5 s Pause (Decay und Rauschen sind Messgrößen).

**Pickup:** Immer dieselbe Gitarre, **Steg-Humbucker** (passiv, mittlere Leistung), Volume und Tone voll offen, E-Standard. Begründung: ein Humbucker liefert volles Spektrum und typische Treiberleistung für Amp-Captures; Singlecoils würden High-Gain-NAMs anders ansteuern, und ein einziger fester Pickup hält die Vergleichbarkeit. Weitere Pickups/Stimmungen wären spätere, eigene Signal-Versionen.

**Urheberrecht:** Nur eigene, frei erfundene Phrasen. Keine erkennbaren Riffs oder Melodien bestehender Songs.

**Dateien und Inhalt** (Dauer: Ziel / Maximum):

1. `wyrmtone-rhythm-v1.wav` (28 s / 30 s): (A) Palm Mutes auf der tiefen E-Saite, Achtel, je ca. 4 s leicht / mittel / hart; (B) Powerchords (z. B. E5, A5, G5, D5), je ca. 2 Schläge gehalten, wechselnd weich bis hart; (C) kurze offene, ausklingende Akkorde (Em, Am, D), je bis zum Ausklingen; (D) kurze Staccato-Anschläge mit Pausen.
2. `wyrmtone-lead-v1.wav` (28 s / 30 s): (A) einzelne gehaltene Noten (z. B. E4, A4, E5), je ca. 4 s, weich / mittel / hart; (B) Bendings (Ganzton, gehalten; Pre-Bend); (C) Vibrato (schmal und breit) auf gehaltener Note; (D) kurzer Skalenlauf, gebunden und gepickt.
3. `wyrmtone-clean-v1.wav` (optional, 18 s / 20 s): Einzelnoten in drei Dynamikstufen (leise / mittel / laut), Arpeggio, gespielte offene Akkorde leise und laut.

**Ablage:** `assets/tonematch/evaluation/` (Entwicklung/Golden/Evaluation); **nicht** in `pubspec.yaml` eingetragen, also nicht im APK. Größe der Originale: 7,7 + 6,4 + 3,8 MB ≈ 17,9 MB (Stereo, 44,1 kHz, 24 Bit; WAV komprimiert kaum). Die Release-Distribution ist eine spätere Entscheidung (siehe 5.6).

Aus den Dateien wird je ein `EvaluationSignalDescriptor` (id, version, role, file, sampleRate, channels, bitDepth, durationSeconds, sha256) erzeugt; ungültige Formate/Dauer werden abgelehnt.

### 5.2 Pipeline

```
Original-WAV → EvaluationSignalLoader (SHA des Originals prüfen, Format validieren, nur LINKS/DRY, exakter 24-Bit-Decode)
  → EvaluationResampler (44,1 → 48 kHz, der einzige Resampler)
  → NamAnalyzer: bestehende NamInferenceEngine, chunkweise (1 s), Cancel zwischen Chunks
  → AudioFeatureExtractor (rein, deterministisch: Input + Output)
  → AudioFeatureVector (LEVEL getrennt von TONE) → NamAnalysis (+ Timings)
  → ToneMatchCache
```

Chunk-Verarbeitung muss per Test dasselbe Ergebnis liefern wie ein Einzelaufruf (Toleranz, Golden). Das Anfangsrauschen wird als Warm-up genutzt und aus den Features ausgeschlossen.

**Cache-Key:** `NAM_SHA256 | EVALUATION_SIGNAL_SHA256 | EVALUATION_SIGNAL_ID(+Version) | ANALYSIS_VERSION`, nie ein Dateiname.

### 5.3 Features V1 (bewusst klein)

- **LEVEL (gespeichert, nie bewertet):** RMS, Peak, Pegeländerung gegenüber dem DI-Eingang.
- **TONE (auf Ausgang mit aktivem-Frame-RMS −20 dBFS normalisiert):** Crest-Faktor, Spektral-Centroid, Rolloff 85 %, Bandbreite, Bandenergie-Anteile LOW 60–250, LOW_MID 250–600, MID 600–1500, HIGH_MID 1,5–3,5 k, HIGH 3,5–8 kHz, dazu Attack-Zeit, Decay (dB/s) und Hüllkurven-Umfang.
- Bandgrenzen: untere Kante 60 Hz (tiefes E = 82 Hz, Drop A ≈ 55 Hz), obere 8 kHz (darüber überwiegend Fizz/Rauschen; Centroid/Rolloff sehen es trotzdem). Zentral in `GuitarBand`.
- Aktive Frames werden relativ zum Pegel des **DI-Eingangs** bestimmt, damit ein lauteres NAM nicht ändert, welche Frames zählen.
- Ein lauteres NAM gilt nicht als „mehr Gain“ oder „besser“: Pegel fließt nie in eine Ähnlichkeit ein (per Test abgesichert).

**Sättigung** wird nicht von einer Kennzahl gemessen. `SaturationDescriptor` ist der einfache Mittelwert von vier Komponenten, die immer mit ausgewiesen werden: spektrale Flachheit 1–8 kHz, HF-Erzeugung gegenüber dem DI, Crest-Reduktion, Hüllkurven-Kompression. Wertebereiche werden erst mit der Drei-NAM-Validierung kalibriert.

### 5.4 Validierung (sobald WAVs vorliegen)

Drei deutlich verschiedene lokale NAMs (Clean, Crunch/Classic High Gain, Modern High Gain), identisches Signal. Zu beweisen ist nur: reproduzierbare, stabile Unterscheidung (Mehrfachläufe innerhalb definierter Toleranz, Golden-Werte), keine Bewertung „besser“ und keine Prozentaussage zu einem Song. Messung von NAM-Load, Inferenz, Feature-Extraktion und Gesamtzeit je NAM; 5er/10er-Läufe erst danach.

### 5.5 UI (vorbereitet, nichts sichtbar)

Spätere ehrliche Statuszeilen: „Passende NAMs werden geprüft“, „3 NAMs werden klanglich verglichen“. Kein Prozentwert ohne messbaren Fortschritt.

### 5.6 Distribution des Evaluation-Signals (offen, nach Slice 2 zu entscheiden)

Die WAVs liegen für Entwicklung, Golden Tests und Evaluation unter `assets/tonematch/evaluation/`. Es steht **nicht** fest, dass die unkomprimierten Dateien Teil des Release-APK werden; bis dahin hat Messqualität Vorrang vor APK-Größe. Nach Slice 2 wird gemessen und verglichen: benötigte Signallänge, Einfluss einer Kürzung auf die Feature-Stabilität, APK-Größe, ein kürzeres kanonisches Signal, Precomputation/Cache (Analysen vorab berechnet statt Signal ausliefern) sowie verlustfreie/kompaktere Speicherung, sofern die Dekodierung bitgenau dasselbe Signal liefert (Prüfung per SHA des dekodierten PCM). Dabei bleibt die Spezifikation aus 5.1 unverändert.


### 5.7 Umsetzung Slice 2 (Stand 2026-10-02)

**Resampler** (`evaluation_resampler.dart`): polyphasiger Windowed-Sinc-Interpolator, Verhältnis 160/147; 160 vorberechnete Phasenfilter à 48 Taps, Tiefpass 21,5 kHz, Kaiser-Fenster (β = 9), je Phase auf DC-Gain 1 normiert. Rand: Nullfortsetzung (Aufnahmen beginnen/enden leise), Ausgabelänge floor(N·160/147). Deterministisch: keine Zufallswerte, feste Summationsreihenfolge; auf derselben Plattform bitgleich, plattformübergreifend nur durch libm-Rundung der Filtertabelle beeinflusst (≈ 1e-6). Getestet: Sinus-Amplitude/-Frequenz, Gitarrenband (5/8 kHz) unverändert, Wiederholung identisch. Der SHA-256 des **Originals** bleibt die Signal-Identität; der SHA des abgeleiteten 48-kHz-PCM ist ein getrennter Derived-Hash (im Golden/Report).

**Features** (`stft_feature_extractor.dart`, Frame 2048 / Hop 512, Hann; Hüllkurve 256/64): aktive Frames = DI-Frame-RMS ≤ 35 dB unter dem lautesten DI-Frame (nicht am NAM-Output).
- LEVEL (nie bewertet): RMS, Peak, Pegeländerung gegenüber DI.
- TONE (Output auf −20 dBFS aktiver RMS normiert): Crest (skaleninvariant, deshalb TONE), Centroid, Rolloff 85 %, Bandbreite (LTAS 60 Hz–20 kHz), Bandanteile LOW/LOW_MID/MID/HIGH_MID/HIGH, Attack-Zeit, Decay (dB/s), Transient-zu-Körper (dB), Hüllkurven-Umfang (p95−p10); Attack/Decay-Werte beruhen auf DI-Onsets mit ≥ 200 ms ungestörtem Ausklang (`onsetCount` wird mitgespeichert).
- Sättigung (`SaturationDescriptor`): vier gleich gewichtete Komponenten (je 1/4): spektrale Flachheit 1–8 kHz, HF-Erzeugung gegenüber dem DI, Crest-Reduktion, Hüllkurven-Kompression. Jede Komponente wird mit festen, a priori gesetzten und **noch nicht kalibrierten** Bereichen auf 0..1 abgebildet (0–0,3 / 0–20 dB / 0–15 dB / 0–15 dB). Der Composite ist keine Messung von „Gain“.

**Cache:** `NAM-SHA256 | Original-WAV-SHA256 | Signal-ID (inkl. Version) | Analyse-Version`, Persistenz über den vorhandenen `StringStore` (`StringStoreToneMatchCache`) oder im Speicher; `CachedNamAnalyzer` ruft die Inferenz nur bei Miss auf.

**Validierung** (`test/tool/tone_match_slice2_analysis_test.dart`, nur Windows-Dev-Bridge, ohne Voraussetzungen übersprungen): drei vorab nach Namen festgelegte echte NAMs (Fender Pano-Verb Clean2 · Marshall JVM410 Crunch · Bugera 6262 High Gain) × alle drei Signale, jeweils zweimal gerechnet. Ergebnisse: Wiederholungen identisch (Toleranz 1e-9); chunked (48 000 / 4096 Frames) und Einzelaufruf stimmen auf < 1e-5 überein; alle drei NAM-Paare sind pro Signal auf ≥ 2 unabhängigen TONE-Features getrennt; der Sättigungs-Composite ordnet bei allen drei Signalen Clean < Crunch < High Gain. Golden: `test/golden/tonematch_slice2_golden.json` (Toleranz 1e-4 relativ).

**Bekannte Grenzen der Messung:**
- `hfGenerationDb` ist durch Cab-Filterung konfundiert: Full-Rig-NAMs mit Speaker-Rolloff erscheinen weniger „HF-erzeugend“ (z. B. LEAD/Bugera ≈ 0 dB vs. Clean ≈ 7 dB). Die Komponente ist transparent ausgewiesen; eine Korrektur wäre eine neue Analyse-Version.
- Der Decay-Wert kann bei stark komprimierten NAMs positiv werden (Hüllkurve wächst nach dem Peak: Kompression/Rauschen).
- Zeiten stammen von einem Windows-Desktop, nicht von einem Android-Gerät.


## 6. Validation-/Ablation-Gate für AnalysisVersion 1 (Vorab-Festlegung, 2026-10-02)

Dieser Abschnitt wurde **vor** der Analyse geschrieben. `toneAnalysisVersion` bleibt 1; STFT, Bandgrenzen, Active-Frame-Schwelle, Normalisierung, Sättigungsgewichte und alle vier Sättigungskomponenten werden im Experiment nicht verändert. Bestehende Goldens bleiben unangetastet; Experimentdaten liegen getrennt in `tool/tonematch_gate/`.

### 6.1 Zehn-NAM-Set (nach Namen/Metadaten gewählt, nicht nach Ergebnis)

Kategorien sind **nicht** als Ground Truth zu lesen: Sie stammen aus Dateiname/Metadaten und sind unverifiziert. „Amp-only/Full-rig“ ist eine Inferenz, kein Wissen. Ersatz nur bei technischem Ladefehler (Reihenfolge: Randall SATAN 50 Mic Center, „Solid Rhythm Fat“), nie nach Ergebnis.

| # | NAM (Datei) | SHA-256 (Anfang) | Metadaten | Rig-Typ (inferiert) | Vorab-Grund |
|---|---|---|---|---|---|
| 01 | FNDR PANO Clean2 BAL 6V6 CAB | ee7a3708 | WaveNet, amp_cab, overdrive | Full-rig (Metadaten) | Clean/Fender-artig |
| 02 | Badlander [AMP] 100W BOLD CLEAN Clean-Pushed #01 | e82cce6b | WaveNet, amp, hi_gain | unbekannt | Edge-of-breakup |
| 03 | JVM410_crunch_green_sd1 | fc31144d | WaveNet, amp, overdrive | unbekannt | Crunch |
| 04 | Marshall JVM410H Boosted – Full Rig (Standard) | ed1cca50 | WaveNet, amp (Name: „Full Rig“) | widersprüchlich → unbekannt | Classic British gain |
| 05 | Bugera 6262 1 Hit Quitter | 5317db99 | WaveNet, keine Metadaten | unbekannt | Modern High Gain |
| 06 | EVH 5150 III (Amp Only) Boosted | 1060a12a | SlimmableContainer, amp, high-gain | Amp-only (Name+Metadaten) | 5150-artig, Amp-only |
| 07 | Badlander [AMP] 100W BOLD CRUSH Heavy-Solo #02 | 99c518dc | WaveNet, amp, hi_gain | unbekannt | stark komprimiertes High Gain |
| 08 | GOJIRA – JOE DUPLANTIER | 7d70a61a | SlimmableContainer, full-rig | Full-rig (Metadaten) | Full-rig/Cab-gefiltert |
| 09 | JP2C Capture 12 JP Lead CH3 G9 | f9be8c60 | WaveNet, keine Metadaten | unbekannt (Pack liefert separate IR) | Amp-only-Kandidat, Lead-Voicing |
| 10 | JP2C Capture 20 Power Amp Only No EQ | 5e17483f | WaveNet, keine Metadaten | Amp-only (nur Endstufe, Name) | deutlicher Ausreißer |

Die vollständigen SHA-256 stehen in `tool/tonematch_gate/ten_nam_set.json`.

### 6.2 Varianten (aus den ORIGINAL-Aufnahmen, deterministisch, keine neuen Aufnahmen)

Abgeleitet wird aus dem bereits resampelten 48-kHz-DI (Originale unverändert). Aktive Spanne [a, b] = erster/letzter 10-ms-Frame des DI, dessen RMS höchstens 35 dB unter dem lautesten 10-ms-Frame liegt (RHYTHM 9,75–27,72 s, LEAD 1,09–23,61 s, CLEAN 1,24–14,27 s; RHYTHM hat also ca. 9,75 s ungespielten Vorlauf, LEAD/CLEAN sind ohne Pausen durchgespielt).

- **FULL**: ganze Originaldatei (Slice-2-Verhalten).
- **SPAN** (nur RHYTHM/LEAD/CLEAN als Zusatz): [a − 0,5 s, b + 1,5 s], also verlustfreie Entfernung toter Zeit.
- **Tn** (n = Content-Sekunden 15, 10, 5; CLEAN nur 10 und 5): k = round(n / 2,5) Fenster à n/k Sekunden. Die aktive Spanne wird in k gleich lange Teile geteilt; jedes Fenster liegt zentriert in seinem Teil. So sind alle Spielabschnitte (RHYTHM: Palm Mutes → Akkorde → Staccato; LEAD/CLEAN: Noten, Bendings, Vibrato, Akkorde) proportional vertreten. Den Anfang abzuschneiden wird bewusst vermieden. Vor dem ersten Fenster stehen 0,5 s Original-Rauschen (aus [a − 0,5, a]); Fenster werden mit 20 ms linearem Ein-/Ausblenden aneinandergefügt.

### 6.3 Messung und Entscheidungsregeln (vorab)

- Pro NAM und Signal je Variante der volle FeatureVector; je Feature absolutes und relatives Delta zu FULL.
- Stabilität über die 10 NAMs: Spearman-Rangkorrelation je Feature gegen FULL; außerdem Spearman der Paar-Distanzen (Distanz = euklidisch über z-standardisierte TONE-Features, Standardisierung aus FULL des jeweiligen Signals; der Composite zählt nicht doppelt).
- **Länge:** kürzeste Variante, bei der (a) Spearman der Paar-Distanzen ≥ 0,95, (b) für jedes Kern-Feature Spearman ≥ 0,90 und (c) |Δ Composite| ≤ 0,05 gelten. Wenn 10 s ≈ FULL und 5 s deutlich instabiler, dann 10 s.
- **V2 gerechtfertigt**, wenn ein Problem an den Daten belegt ist (z. B. HF-Komponente korreliert systematisch mit gemessener Cab-Filterung und verzerrt Paar-Distanzen) und eine alternative Metrik es offline beheben würde, ohne Differenzierung zu verlieren. Das Aussehen der Kategorienreihenfolge Clean < Crunch < High Gain ist **kein** Kriterium.
- Diagnose Cab-Abhängigkeit: je NAM ein „linearer Tilt“ aus einem Offline-Rauschprobe (seeded Gauß-Rauschen bei −30 und −20 dBFS RMS, nur Diagnose, kein Evaluation-Signal): dB(3,5–8 kHz) − dB(250–1500 Hz) des Outputs. Dieser Wert beschreibt Cab-/Voicing-Filterung unabhängig von Spielmaterial.


### 6.4 Ergebnisse (Rohdaten und Auswertung: `tool/tonematch_gate/results/`, Skript `tool/tonematch_gate/analyze.py`)

AnalysisVersion 1 blieb unverändert; `test/golden/tonematch_slice2_golden.json` ist byteidentisch (SHA-256 `3cbf0b68…`), alle Slice-2-Tests bestehen weiterhin.

**Signal-Länge** (Spearman der Paar-Distanzen über 10 NAMs gegen FULL / max. |Δ Composite|):

| Signal | SPAN | T15 | T10 | T5 |
|---|---|---|---|---|
| RHYTHM (FULL 29,1 s) | 0,983 / 0,003 | 0,978 / 0,010 | 0,909 / 0,063 | 0,857 / 0,131 |
| LEAD (FULL 24,2 s) | 0,990 / 0,001 | 0,975 / 0,011 | 0,955 / 0,076 | 0,856 / 0,083 |
| CLEAN (FULL 14,3 s) | 1,000 / 0,004 | – | 0,972 / 0,058 | 0,909 / 0,052 |

- **Beobachtung:** SPAN (nur toter Vorlauf entfernt, gleicher Inhalt) ist selbst bereits nicht identisch zu FULL: `attackMs` ±17 %, `decayDbPerSec` ±8–32 %, `transientPeakToBody` ±12 % (RHYTHM). Diese drei Features haben also ein Rauschniveau durch bloße Frame-/Hüllkurven-Rasterverschiebung und sind in V1 nicht belastbar.
- **Pre-registered Kriterium (b)** („jedes Kern-Feature Spearman ≥ 0,90“) war deshalb nicht erfüllbar: strikt besteht nur CLEAN-SPAN alle drei Kriterien. Ausgewertet wurde zusätzlich, welche Features erst *jenseits* des SPAN-Rauschniveaus ausfallen: RHYTHM T15 und LEAD T15 keine, T10/T5 viele (RHYTHM T10: Centroid ρ 0,83, hfGen ρ 0,79; LEAD T10: LOW-Band).
- **Empfehlung:** RHYTHM 15 s, LEAD 15 s (T15), CLEAN SPAN; verlustfrei zusätzlich RHYTHM-SPAN (19,9 s). 10 s ist nicht „nahezu FULL“. Dies sind abgeleitete Varianten; als kanonisches Signal bräuchte T15 eine eigene Signal-ID/Version.

**HF-Komponente:** Die V1-Komponente `hfGenerationDb` korreliert in RHYTHM nicht mit dem Cab-/Voicing-Tilt (ρ 0,04), in LEAD moderat (ρ 0,52, bei n = 10 nicht belastbar), stimmt aber mit den anderen drei Sättigungskomponenten nicht überein (ρ −0,10 / −0,53) und ist längenabhängig instabil (Median-Delta 21–67 %). Die Cab-Hypothese ist damit **nicht bestätigt**; belegt ist nur: die Komponente trägt wenig und instabil bei. Alternativen (offline): B HF/Mid und C Spektralneigung (Δ gegen DI) stimmen stark mit den übrigen Sättigungskomponenten überein (ρ 0,70–0,91), sind aber selbst spektrale Neigungsmaße und damit teils zirkulär; D Valley-Fill korreliert negativ mit dem Tilt (−0,59) und kaum mit den Komponenten; E Bandverhältnisse messen Voicing, nicht Sättigung.

**Composite 4 vs. 3 Komponenten (ohne HF):** Spearman 0,95 / 0,94 / 0,99 (RHYTHM / LEAD / CLEAN); getrennte NAM-Paare (Δ > 0,05) 40→42, 39→40, 40→40 von 45. Ohne HF geht keine Differenzierung verloren; die Längenrobustheit wird aber nicht besser (max. Δ T10: 0,049 vs. 0,063 RHYTHM, 0,085 vs. 0,076 LEAD).

**Distanzmatrix** (FULL, z-standardisierte TONE-Features, keine Prozentwerte): kleinste Distanzen 2,4–3,4 (Bugera 05 / Badlander Heavy-Solo 07 / JP2C Lead 09; JVM Full-Rig 04 / Gojira 08 in LEAD): keine praktisch identischen NAMs. Ausreißer: Endstufe 10 (RHYTHM z = 2,7), LEAD zusätzlich Fender-Clean 01 (z = 2,0). Cluster (Average Linkage, 3): {01, 02} | übrige Sieben | {10}. Kein einzelnes Feature dominiert (größter mittlerer Anteil 8–9 %: `attackMs`, `band.MID`, `band.LOW`); unerwartet ist, dass das rauschbehaftete `attackMs` zu den größten Distanzbeiträgen zählt.

**Desktop-Zeiten** (Mittel über 10 NAMs, kalt; diese Session war ca. 2× langsamer als die Slice-2-Messung, relative Skalierung ist robust: Inferenz ≈ 0,21 × Echtzeit): RHYTHM FULL 6,2 s, SPAN 4,4 s, T15 3,5 s, T10 2,4 s, T5 1,2 s; LEAD FULL 5,5 s, T15 3,5 s, T10 2,4 s. Cache (20 Analysen): FULL kalt 121,9 s / warm 1,35 s; T10 kalt 49,3 s / warm 0,53 s.

**Einschätzung:** AnalysisVersion 1 ist für Länge und Differenzierung brauchbar; die V2-Notwendigkeit ist **nicht bewiesen**. Offene Punkte: (1) `attackMs`/`decayDbPerSec`/`transientPeakToBody` sind rauschbehaftet, sollten in V1 nicht in eine Ähnlichkeit eingehen oder erst robuster werden; (2) die Gültigkeit der Sättigungskomponenten ist ohne unabhängige Referenz (z. B. gemessene Harmonische je NAM) nicht belegt; (3) n = 10 ist für Korrelationsaussagen knapp.


## 7. Saturation Validation Gate (Vorab-Festlegung, 2026-10-02)

Ausschließlich eine **Offline-Diagnose-Probe**: kein Evaluation-Signal, kein Ersatz für RHYTHM/LEAD/CLEAN, kein Teil eines Tone Scores, kein Release-Asset, kein Gitarrenklang. AnalysisVersion 1 bleibt eingefroren; dieselben 10 NAMs wie in 6.1. Code und Daten: `tool/tonematch_saturation_gate/`.

### 7.1 Probe
- 48 kHz direkt erzeugt (kein Resampling), deterministisch (reine Funktion von Frequenz und Pegel; Test: bit-identisch).
- Frequenzen: 82,4 / 110 / 220 / 440 / 880 / 1760 Hz. Pegel (Spitzenamplitude des Sinus in dBFS): −36 / −30 / −24 / −18 / −12 / −9. **−6 dBFS entfällt vorab:** die aufgenommenen Gitarren-DI-Spitzen liegen bei höchstens −9,07 dBFS, ein Sinus mit −6 dBFS Spitze (−9 dBFS RMS) läge außerhalb des Gitarrenbereichs. Keine Kombination wird nach Ergebnis entfernt.
- Aufbau je Probe: 0,1 s Fade-in (Raised Cosine), 1,4 s stationär, 0,1 s Fade-out, 0,1 s Null. **Messfenster 0,4–1,4 s** (vollständig stationär, 0,3 s Einschwingzeit nach dem Fade-in). Kein Fade im Messfenster. Pro Probe wird das NAM frisch geladen (keine Zustandsübernahme).
- Harmonische per gemeinsamer Least-Squares-Anpassung (DC + Sinus/Cosinus von f0…H8) über das Messfenster, nicht per FFT; das Residuum ist alles Übrige (Rauschen, Aliasing, H9+, Nicht-Harmonische). Gültig sind Hk mit k·f0 ≤ 0,45·fs (21,6 kHz); für alle gewählten Frequenzen sind H2…H8 gültig (größtes 8·1760 = 14,08 kHz). Harmonische darüber wären Alias und zählen nie als Hk.
- Kennzahlen je NAM × Frequenz × Pegel: Grundton-Amplitude, Grundton-Gain, H2…H8, THD (nur H2…H8), THD+N (Residuum eingeschlossen; methodisch sauber, weil Fenster stationär und rauschfrei erzeugt), ungerade/gerade/gesamte Oberwellenenergie, Output RMS, Peak, Crest, Residuum.
- Diagnosekennzahlen (physikalisch, ohne 0..1): `gainChangeDb(−12)` und `gainChangeDb(−9)` relativ zu −36 dBFS (Kompression negativ), `compressionOnsetDbfs` (erster Pegel mit ≥ 1 dB Gain-Abfall gegen −36 dBFS, linear interpoliert, sonst „nicht erreicht“), `thdAtLowInput` (−36), `thdAtHighInput` (−9), `thdGrowthSlope` (Steigung von 20·log10(THD) über Eingangspegel in dB), `oddEvenRatioDb` bei −12 dBFS. Aggregation über Frequenzen: Median über alle sechs Frequenzen; zusätzlich Einzelwerte.
- Cab/EQ-Einfluss wird offen untersucht (kein Robustheitsannahme): ein nachgeschaltetes lineares Filter lässt die Gain-Änderung über den Pegel unverändert, verändert aber THD (Hk/H1 wird mit |H(k·f0)|/|H(f0)| gewichtet).

### 7.2 Vergleich mit V1 und Entscheidungsregeln (vorab)
- Verglichen werden die V1-Komponenten `flatness1to8k`, `hfGenerationDb`, `crestReductionDb`, `envelopeCompressionDb`, der 4-Komponenten-Composite und der 3-Komponenten-Composite ohne HF (FULL-Daten aus 6.4, RHYTHM und LEAD) gegen die Probe-Kennzahlen: Spearman und Pearson über 10 NAMs. Jede Kennzahl wird einzeln berichtet, keine Auswahl der günstigsten Korrelation.
- **Dimensionalität:** Hauptkomponentenanalyse (PCA) der z-standardisierten Probe-Kennzahlen (thdLow, thdHigh, thdGrowthSlope, gainChange12, gainChange9, oddEvenRatio). Eine einzelne Sättigungsdimension gilt als **gerechtfertigt**, wenn PC1 ≥ 70 % der Varianz erklärt und die Kern-Kennzahlen thdHigh, gainChange9 paarweise |ρ| ≥ 0,7 haben; sie gilt als **nicht gerechtfertigt**, wenn PC2 ≥ 20 % erklärt und der Betrag der Korrelation zwischen Verzerrung (thdHigh) und Kompression (gainChange9) < 0,5 ist; sonst **unklar**.
- **Entscheidung** (A–D): A (V1-Composite ausreichend validiert) nur, wenn eine Dimension gerechtfertigt ist, der Composite mit dem PC1-Wert |ρ| ≥ 0,7 in RHYTHM und LEAD hat und jede V1-Komponente |ρ| ≥ 0,5 mit PC1; B (Composite ändern), wenn eine Dimension gerechtfertigt ist, der V1-Composite aber verfehlt wird und eine Variante ihn um ≥ 0,1 verbessert; C (mehrere Deskriptoren), wenn die Dimension nicht gerechtfertigt ist; D, wenn die Regeln nicht entscheidbar sind. Die Clean/Crunch/High-Gain-Sortierung ist kein Kriterium.
- n = 10 ist knapp; Aussagen sind Indikatoren, keine Signifikanztests.

### 7.3 Raster-Offset-Experiment (nur quantifizieren, nicht reparieren)
Für dieselben FULL-NAM-Ausgänge (RHYTHM, LEAD) wird der Extractor mit den Frame-Offsets 0, 128, 256, 384 Samples (wie gefordert) sowie den Sub-Hop-Offsets 16, 32, 48 ausgeführt (Offset = erste Samples von Input und Output verwerfen; das NAM läuft nicht neu). Gemessen werden Variationskoeffizient und Rangstabilität (Spearman gegen Offset 0 über 10 NAMs) für `attackMs`, `decayDbPerSec`, `transientPeakToBodyDb` und stabile Vergleichsfeatures. Offsets 128/256/384 sind Vielfache des Hüllkurven-Hops (64) und ändern dessen Raster nicht; die Sub-Hop-Offsets sind deshalb ergänzt.


### 7.4 Ergebnisse (Rohdaten/Bericht: `tool/tonematch_saturation_gate/results/`, Skript `analyze.py`)

AnalysisVersion 1 und alle Goldens sind unverändert (`test/golden/tonematch_slice2_golden.json` SHA-256 `3cbf0b68…`); alle Slice-2-Tests bestehen.

**Validierung der Messmethode:** Generator bit-identisch pro (Frequenz, Pegel); Harmonic-Analyzer an synthetischen Signalen geprüft (reiner Sinus, Sinus + bekanntes H2, + bekannte H3/H5 bei nicht ganzzahliger Zykluszahl, bekannte Hard-Clipping-Funktion gegen numerisch bestimmte Fourier-Koeffizienten, THD+N mit seeded Rauschen, Alias-Komponente wird nicht als Hk gezählt). Für alle sechs Frequenzen sind H2…H8 gültig.

**Befund 1 – die Probe hat einen Ceiling-Effekt:** Bei 7 von 10 NAMs (03–09) fällt die Verstärkung schon zwischen −36 und −30 dBFS um ≥ 1 dB. Der lineare Bereich dieser NAMs liegt unterhalb des tiefsten vorab festgelegten Pegels; `compressionOnsetDbfs` ist für sie nur „≤ −35 dBFS“ (zensiert), nicht messbar. Die Gain-Änderung bei −9 dBFS liegt bei ihnen einheitlich bei −26 bis −28 dB (Ausgang praktisch konstant). Nur 01, 02, 10 werden im Messbereich graduell abgebildet.

**Befund 2 – eine dominante Dimension, aber stark dichotom:** PC1 erklärt 88 % (PC2 9 %), ρ(thdHigh, gainChange9) = −0,87 ⇒ nach Regel 7.2 „eine Dimension gerechtfertigt“. Diese Struktur wird jedoch fast vollständig von der Trennung {01, 02, 10} gegen die übrigen sieben getragen. Innerhalb der sieben gesättigten NAMs (n = 7, explorativ, nicht Teil der Regel) sind die Korrelationen der V1-Features mit den Probe-Kennzahlen schwach bis uneinheitlich (|ρ| meist < 0,5); die Probe kann sie nicht auflösen. Es gibt keine belegte Ground-Truth-Rangfolge innerhalb der Hochgain-Gruppe.

**V1 gegen die unabhängige Probe** (Spearman gegen PC1, RHYTHM / LEAD): `flatness1to8k` 0,60 / 0,55; `hfGenerationDb` 0,15 / −0,24; `crestReductionDb` 0,81 / 0,82; `envelopeCompressionDb` 0,66 / 0,77; Composite (4) 0,73 / 0,70; Composite ohne HF 0,76 / 0,72. Gegen `thdHigh`/`gainChange9`: HF 0,04 / 0,07 (RHYTHM) bzw. −0,36 / 0,37 (LEAD) – nicht gestützt; Crest-Reduktion und Hüllkurven-Kompression am stärksten (0,70–0,89), also eher Kompressions-/Dynamikmaße als Verzerrungsmaße. Die HF-Komponente wird von der unabhängigen Referenz nicht unterstützt; ihr Entfernen verbessert den Composite aber nur um 0,02 (Regel B verlangt ≥ 0,1).

**Entscheidung nach vorab festgelegter Regel 7.2: D** („Daten reichen nicht“). A scheitert an der HF-Komponente (ρ mit PC1 < 0,5), B am fehlenden Gewinn ≥ 0,1, C weil keine zweite Dimension (PC2 < 20 %) belegt ist. Die Probe löst die Hochgain-Gruppe nicht auf und n = 10 ist knapp.

**Cab/EQ-Einfluss (offen, nicht gelöst):** ρ(Tilt, Probe-Kennzahl) ist hoch (thdHigh −0,83, gainChange12 0,82). Der Tilt stammt aus einer Rauschprobe durch ein stark sättigendes NAM und ist daher selbst mit der Sättigung konfundiert; er ist kein reines Cab-Maß. Bei hohen Frequenzen (880–1760 Hz, Harmonische werden stärker vom Cab gewichtet) verschwindet der Zusammenhang (0,09 / 0,10), bei tiefen bleibt er (−0,60 / 0,77). Die Gain-Änderung über den Pegel ist für ein nachgeschaltetes lineares Filter theoretisch cab-unabhängig; THD und Oberwellen-Verhältnisse sind es nicht. Amp-only (06, 10) und Full-rig (01, 08) verhalten sich jeweils völlig unterschiedlich (06 ≈ −27 dB Kompression, 10 ≈ −1,3 dB; 01 ≈ −12 dB, 08 ≈ −27 dB). Der Rig-Typ erklärt das Verhalten nicht; n ist zu klein für Gruppenaussagen.

**Raster-Offset (nur quantifiziert):** Der Median-Variationskoeffizient über Offsets beträgt `attackMs` 11,4 %, `decayDbPerSec` 14,1 %, `transientPeakToBody` 2,9 %; STFT-basierte Features ≤ 0,4 % (Centroid, Crest, Bänder, Composite ≈ 0,02 %). Bei Offsets, die Vielfache des Hüllkurven-Hops (64) sind, ist die Streuung exakt 0; sie entsteht vollständig durch die **Phase des Hüllkurven-Rasters** (Sub-Hop-Offsets: 14 % / 16 %), nicht durch das STFT-Raster. Rangstabilität gegen Offset 0 (Minimum): `attackMs` ρ 0,64, `decayDbPerSec` 0,92, `transient` 0,85, alle stabilen Features ≥ 0,99.

**Einschätzung:** (a) Ein einzelner Sättigungs-Composite ist **unklar** gerechtfertigt: die Probe zeigt eine dominante, aber dichotome Dimension; Composite und Probe stimmen in der Grobtrennung überein, die Feinstruktur ist nicht validiert. Mehrdimensionale Deskriptoren (Verzerrung/Kompression/spektrale Änderung) sind mit diesen Daten weder belegt noch widerlegt. (b) Für `attackMs`/`decayDbPerSec` ist AnalysisVersion 2 gerechtfertigt (Messrauschen belegt, siehe unten). (c) Für den Sättigungs-Composite nicht.

#### V2-Proposal (nur Attack/Decay, nicht implementiert)
- **Problem:** Die Hüllkurven-Features hängen von der Phase des 64-Sample-Rasters ab.
- **Evidence:** CV 11,4 % (`attackMs`) und 14,1 % (`decayDbPerSec`) bei reinem Rasterversatz, Rangstabilität bis ρ 0,64; Slice-2-Gate: SPAN-vs-FULL-Abweichung 17 % bzw. 8–32 %.
- **Old Metric:** Onset-Medianwerte auf einem Hüllkurvenraster (Fenster 256, Hop 64, Auflösung 1,33 ms), Spitze als Rasterindex.
- **Proposed Metric:** Hüllkurve auf mehreren Rasterphasen (z. B. 0/16/32/48 Samples) berechnen und je Onset den Median über die Phasen verwenden (bzw. Spitzenposition per Parabel-Interpolation); gleiche Definition sonst.
- **Expected Benefit:** CV auf ≈ der Quantisierungsgrenze (< 3 % erwartet), Rangstabilität ≥ 0,95; erst dann sinnvoll in eine Ähnlichkeit aufnehmbar. Zu verifizieren per Wiederholung desselben Offset-Experiments.
- **Tradeoff:** 4× Hüllkurvenaufwand (Extraktion ≈ +0,1 s je Analyse auf dem Desktop), Werte ändern sich leicht.
- **Golden Migration:** `attackMs`, `decayDbPerSec`, `transientPeakToBody` im Golden werden neu erzeugt, bewusst in einer neuen Datei `…_v2.json`; das V1-Golden bleibt als Referenz unverändert.
- **Cache Invalidation / Version:** `toneAnalysisVersion` 1 → 2; alte Cache-Einträge werden nie gefunden (Key enthält die Analyse-Version).
- Keine weiteren V2-Änderungen empfohlen, solange der Sättigungs-Composite nicht mit einer Probe validiert ist, die die Hochgain-Gruppe auflöst (z. B. zusätzliche Pegel unterhalb −36 dBFS und Gain-abhängige Einordnung).


## 8. AnalysisVersion 2: Hüllkurven-Stabilisierung (Vorab-Festlegung, 2026-10-03)

Auftrag: ausschließlich die belegte Rasterphasen-Abhängigkeit von `attackMs`, `decayDbPerSec` und `transientPeakToBody` beseitigen (Befund 7.4: Median-CV 11,4 % / 14,1 % / 2,9 %, Rangstabilität bis ρ 0,64). Das Sättigungsmodell, die HF-Komponente, alle Gewichte und Abbildungen bleiben unverändert.

### 8.1 Änderung
- **V1 bleibt vollständig reproduzierbar:** `StftFeatureExtractor(analysisVersion: 1)` ist der Default und rechnet bit-genau wie zuvor (`EnvelopeFeatures.atPhase(…, phase: 0)` ist die unveränderte V1-Logik). V1-Golden `tonematch_slice2_golden.json` bleibt byte-identisch.
- **V2** (`analysisVersion: 2`, opt-in): dieselbe V1-Hüllkurvenlogik (Fenster 256, Hop 64) auf den Rasterphasen **0, 16, 32, 48 Samples**; Aggregation je Feature als **Median über die vier Phasen** (Features, die in einer Phase fehlen, werden übersprungen). `onsetCount` wird als Median der Phasenzahlen (nicht gerundet) berichtet.
- **Abhängigkeitsprüfung:** Die 64-Sample-Hüllkurve verwenden nur `attackMs`, `decayDbPerSec`, `transientPeakToBodyDb` und `onsetCount`. `envelopeRangeDb` und `envelopeCompressionDb` stammen aus den 2048/512-STFT-Frames und teilen die Primitive nicht; sie bleiben deshalb V1-identisch und es ist keine Trennung nötig. Erwartung: im V2-Golden ändern sich nur diese vier Felder.
- **transientPeakToBody:** V2 übernimmt die Mehrphasen-Aggregation für dieses Feature **nur**, wenn der Offset-Test sie als nicht schlechter ausweist (CV und min. Rangstabilität jeweils ≥ V1); sonst bleibt die V1-Definition (Phase 0).
- **Cache:** `NamAnalysisKey` enthält die Analyse-Version; ein V2-Analyzer findet nie V1-Einträge. `CachedNamAnalyzer` verweigert eine abweichende Version (Fehler), der V1-Cache muss nicht gelöscht werden.
- Aktivierung als Produktionsdefault ist eine eigene spätere Entscheidung; Default bleibt V1.

### 8.2 Abnahme (vorab, Schwellen werden nicht nachträglich geändert)
Wiederholung des Offset-Experiments aus 7.3: dieselben 10 NAMs, dieselben FULL-Evaluationssignale, Offsets 0 / 16 / 32 / 48 / 128 / 256 / 384, Median-CV über NAMs × {RHYTHM, LEAD}, minimale Rangstabilität (Spearman gegen Offset 0).
- `attackMs`: Median-CV < 3 % **und** min. ρ ≥ 0,95
- `decayDbPerSec`: Median-CV < 3 % **und** min. ρ ≥ 0,95
- `transientPeakToBody`: nicht schlechter als V1
- synthetische Hüllkurventests bestanden (sofortiger/linearer/exponentieller Attack, bekannter exponentieller Decay, Attack+Sustain+Decay, mehrere Transienten; die Mehrphasenberechnung muss auf bekannte Änderungen reagieren, nicht konstant sein)
- alle übrigen Features numerisch identisch zu V1 (exakte Gleichheit in den Experimentdaten; V1-Golden-Werte im Golden-Test)
- V1-Golden byte-identisch; V1/V2-Cache-Isolation; V2-Golden deterministisch; bestehende Slice-2-Tests unverändert grün.
Das Ergebnis ist ACCEPT nur, wenn alle Punkte erfüllt sind, sonst REJECT.

**Methodischer Vorbehalt (vorab):** Die geforderten Offsets 16/32/48 sind Vielfache des Phasenabstands 16. Das Phasen-Set {0,16,32,48}+o fällt dann (modulo 64) auf dasselbe Gitter wie für o = 0; V2 ist dort fast zwangsläufig stabil. Zusätzlich werden deshalb **Generalisierungs-Offsets** 5, 11, 24, 37, 53 gemessen, die nicht auf dem Phasengitter liegen. Sie sind nicht Teil der oben festgelegten Abnahme, werden aber getrennt und ungeschönt berichtet und fließen in die Einschätzung ein.

### 8.3 Aufwand
Desktop: 10 NAMs × RHYTHM-T15 und LEAD-T15; getrennt: NAM-Inferenz, V1-Extraktion, V2-Extraktion, absolute/prozentuale Differenz, Gesamtwirkung. Keine Optimierung vor der Messung.


### 8.4 Ergebnisse (Rohdaten/Bericht: `tool/tonematch_envelope_v2/results/`, Skript `analyze.py`; Golden: `test/golden/tonematch_slice2_golden_v2.json`)

**V1 unverändert:** `test/golden/tonematch_slice2_golden.json` ist byteidentisch (SHA-256 `3cbf0b68…`, vor und nach). Der refaktorierte V1-Extractor reproduziert alle 440 Werte des früheren Gates (FULL, 10 NAMs × RHYTHM/LEAD) **exakt**. V2 ist opt-in (`StftFeatureExtractor(analysisVersion: 2)`); V1 bleibt Default.

**Offset-Experiment** (dieselben 10 NAMs und FULL-Signale; Median-CV in % über NAM × Signal / minimale Rangstabilität):

| Feature | V1, vorgegebene Offsets | V2, vorgegebene Offsets | V1, Gitter-fremde Offsets | V2, Gitter-fremde Offsets |
|---|---|---|---|---|
| `attackMs` | 11,41 / 0,64 | **0,00 / 1,00** | 12,70 / 0,64 | 6,06 / 0,85 |
| `decayDbPerSec` | 14,11 / 0,92 | **0,00 / 1,00** | 20,53 / 0,94 | 4,72 / 0,96 |
| `transientPeakToBody` | 2,87 / 0,85 | 0,00 / 1,00 | 4,23 / 0,85 | 1,31 / 0,95 |

Vorgegebene Offsets: 0, 16, 32, 48, 128, 256, 384. Gitter-fremd (Zusatz, nicht Teil der Abnahme): 0, 5, 11, 24, 37, 53.

- **Formale Abnahme (8.2):** attack CV 0,00 % < 3 und ρ 1,00 ≥ 0,95; decay CV 0,00 % < 3 und ρ 1,00 ≥ 0,95; transient nicht schlechter (CV und ρ jeweils ≥ V1) – alle erfüllt; transient übernimmt deshalb die Mehrphasen-Aggregation.
- **Vorbehalt (in 8.2 vorab angekündigt):** Die vorgegebenen Offsets liegen auf dem Phasengitter {0,16,32,48} (Vielfache von 16; das Phasen-Set ist dort modulo 64 identisch), V2 ist dort per Konstruktion stabil. Dieser Test beweist die Gitter-Unabhängigkeit nicht. Bei Offsets außerhalb des Gitters wird die Streuung gegenüber V1 deutlich, aber nicht unter die Schwellen gesenkt: Attack-CV −52 % (12,7 → 6,1 %), Decay −77 % (20,5 → 4,7 %), Transient −69 %; Attack-Rangstabilität 0,64 → 0,85, Decay 0,94 → 0,96. Bei diesen Offsets würden `attackMs` (CV und ρ) und `decayDbPerSec` (CV) die Schwellen von 3 % / 0,95 **nicht** erreichen.

**Synthetische Hüllkurven** (Erwartung / V1 / V2; Eingang = Ausgang, 6 Noten):

| Fall | Erwartung | V1 | V2 |
|---|---|---|---|
| Decay τ = 0,15 / 0,3 / 0,6 s | −57,9 / −29,0 / −14,5 dB/s | −57,9 / −29,0 / −14,5 | −57,9 / −29,0 / −14,5 |
| Attack: sofort / linear 5 / 20 / 40 ms | Hop-1-Referenz der Metrikdefinition 6,5 / 10,3 / 21,2 / 39,2 ms | 9,3 / 10,7 / 24,0 / 38,7 | 9,3 / 10,7 / 24,0 / 39,3 |
| Attack: exponentiell τ = 10 / 30 ms | Referenz 36,7 / 76,6 ms | 40,0 / 80,0 | 38,7 / 73,3 |
| Sustain-Note vs. reiner Decay (τ = 0,2) | Sustain ≈ 0, Decay −43,4 dB/s | −0,11 vs. −43,5 | −0,05 vs. −43,5 |
| Transient, Körper 1,0 + Spike (12 ms) | flach ≈ 0 dB, Spike deutlich größer | 0,42 / 9,24 | 0,41 / 9,27 |
| 6 Noten, τ wechselt 0,15 / 0,6 s | 6 Onsets, Median-Decay −36,2 dB/s | 6 / −36,23 | 6 / −36,22 |
| Raster-Verschiebung 0/5/11/24/37/53, CV Attack / Decay | – | 11,7 % / 0,07 % | 3,2 % / 0,06 % |

V2 reagiert erwartungsgemäß auf bekannte Änderungen (Ordnung der Attack-Zeiten, Decay-Steigungen, Sustain, Spike, Median bei gemischten Noten) und liefert keine Konstanten. **Ehrliche Korrektur:** Meine erste Erwartung („physikalische“ Attackzeit, Toleranz ±4 ms) war falsch, weil die Metrik definitionsgemäß die Lage des Maximums einer RMS-Hüllkurve mit Fenster 256 misst; bei einem 196-Hz-Träger liegt das Maximum auf einem flachen Ripple-Rücken. Die Referenz ist deshalb eine unabhängige Hop-1-Implementierung der Metrikdefinition. Auch die danach gesetzte Toleranz von ±1,5 ms erreichten weder V1 noch V2 (mittlerer Fehler V1 2,2 ms, V2 1,9 ms; max. 3,4 / 3,2 ms). Attack-Genauigkeit ist bei schnellen Attacken auf etwa 3 ms begrenzt; das Kriterium wurde als „V2 nicht ungenauer als V1 und nie schlechter als 4 ms“ festgehalten. Das erste Testsignal hatte außerdem keinen stillen Vorlauf (kein Onset erkennbar), das ist behoben.

**Unverändertes:** Alle 3600 verglichenen übrigen Werte (alle NAMs × Signale × Offsets: Level, Centroid, Rolloff, Bandbreite, Bänder, Crest, Flachheit, HF, Crest-Reduktion, Hüllkurven-Kompression, Composite, `envelopeRangeDb`) sind V1/V2 **exakt gleich**. `envelopeRangeDb` und `envelopeCompressionDb` benutzen die 2048/512-STFT-Frames, nicht die 64-Sample-Hüllkurve; eine Trennung war nicht nötig.

**V2-Golden:** gleiche echte WAVs und die drei NAMs des V1-Goldens; gegenüber V1 ändern sich ausschließlich `tone.attackMs`, `tone.decayDbPerSec`, `tone.transientPeakToBodyDb`, `tone.onsetCount`. Typische Verschiebung bei Offset 0 (Median über NAM × Signal): Attack 7,9 %, Decay 8,7 %, Transient 1,4 %.

**Cache:** V1- und V2-Schlüssel unterscheiden sich (Analyse-Version im Key); ein V2-Analyzer erhält nie einen V1-Eintrag, der V1-Eintrag bleibt unverändert und wird weiterhin von V1 bedient; `CachedNamAnalyzer` verweigert eine Version, die von der des inneren Analyzers abweicht.

**Aufwand** (Desktop, Mittel über 10 NAMs, T15, ms): RHYTHM: Inferenz 3316, V1-Extraktion 141, V2-Extraktion 173 (+31 ms, +22 % der Extraktion), Gesamteffekt +0,9 %. LEAD: Inferenz 3322, V1 175, V2 203 (+28 ms, +16 %), Gesamteffekt +0,8 %. Vier Hüllkurven-Durchläufe kosten also nicht das Vierfache der Extraktion.

**Vorläufige Entscheidung (durch 9.6 ersetzt – der Mehrphasen-Ansatz wurde im finalen Gate verworfen): V2 ACCEPT (formal, nach den vorab festgelegten Kriterien).** V2 bleibt opt-in; Aktivierung als Produktionsdefault ist eine eigene Entscheidung. Das Ziel „Raster-Abhängigkeit beseitigen“ ist nur teilweise erreicht (Gitter-fremde Offsets: Attack-CV 6,1 %, ρ 0,85). Mehr Phasen (z. B. 8 oder 16) wären ein eigener, vorab zu registrierender Test auf frischen Hold-out-Offsets.


## 9. Finales Envelope-Stability-Gate (Vorab-Festlegung, 2026-10-03)

Begründung: Die Abnahme-Offsets 0/16/32/48 aus 8.2 liegen auf dem Phasengitter des 4-Phasen-Prototyps, die perfekte Stabilität dort ist teilweise konstruktionsbedingt; Gitter-fremde Offsets zeigten deutliche, aber nicht schwellenerfüllende Verbesserung (8.4). Dies ist **das eine** finale Gate; danach wird die Envelope-Architektur eingefroren, es folgen keine weiteren Varianten und kein Nachoptimieren (kein 32-/64-Phasen-Test).

### 9.1 Kandidaten (nur Anzahl/Position der Rasterphasen variiert; alles andere unverändert)
- **V1:** eine Phase (0), bestehendes Verhalten.
- **V2-4:** 0, 16, 32, 48.
- **V2-8:** 0, 8, 16, 24, 32, 40, 48, 56.
- **V2-16:** 0, 4, 8, …, 60.
Aggregation: Median, ohne Gewichtung. Unverändert: NAM-Set, Evaluations-WAVs, Segmentierung (T15), STFT, Normalisierung, Bänder, Crest, Centroid, Rolloff, Bandbreite, Sättigungsmodell, HF-Metrik, Hüllkurven-Metrikdefinitionen.

### 9.2 Hold-out-Offsets (festgeschrieben vor dem Lauf, nicht mehr änderbar)
`1, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61` Samples. Alle sind ungerade und liegen damit auf keinem der Gitter (Vielfache von 16, 8 oder 4). Es werden keine Offsets hinzugefügt oder entfernt; Auswertung modulo 64. Referenz für die Rangstabilität ist der Wert bei Offset 0 des jeweiligen Kandidaten (die Zielgröße „gleich wie auf dem Gitter“); der Variationskoeffizient wird **nur über die Hold-out-Offsets** gebildet (Offset 0 geht nicht ein).

### 9.3 Primäre Abnahmekriterien (unverändert, auf den Hold-out-Offsets; Median-CV über NAM × {RHYTHM, LEAD}, minimale Spearman-Rangstabilität über 10 NAMs)
- `attackMs`: CV < 3 % und min. ρ ≥ 0,95
- `decayDbPerSec`: CV < 3 % und min. ρ ≥ 0,95
- `transientPeakToBody`: nicht schlechter als V1 (CV und ρ), bevorzugt CV < 3 % und ρ ≥ 0,95
- synthetische Hüllkurventests (die bestehenden, unverändert; für 8 und 16 zusätzlich): reagieren auf unterschiedliche Attackzeiten, Decay-Konstanten und Transientenstärken mit unterschiedlichen, monotonen/plausiblen Ergebnissen (nicht konstant, nicht flachgemedianed)
- Accuracy gegen die unabhängige Hop-1-Referenz (Attack: mittlerer und maximaler Absolutfehler, auf den echten NAM-Ausgängen und synthetisch): der Kandidat darf nicht ungenauer als V1 sein (mittlerer Absolutfehler ≤ V1). Die praktische Auflösung von etwa 3 ms (Ripple-Rücken, siehe 8.4) wird offen dokumentiert; es gibt keine zusätzliche Accuracy-Schwelle.
- unveränderte Features exakt gleich; V1-Golden byte-identisch; V1/V2-Cache-Isolation; Determinismus.

### 9.4 Auswahlregel (vorab)
Gewählt wird die **kleinste** Phasenzahl (4 < 8 < 16), die alle primären Kriterien erfüllt, auch wenn eine größere minimal bessere Werte hat. Erfüllt keiner, wird der Mehrphasen-Ansatz verworfen und das Problem dokumentiert. Keine Auswahl nach Clean/Crunch/High-Gain-Sortierung.

### 9.5 Folgen
- **Gewinner:** V2 wird auf genau diesen Gewinner umgestellt; ein neues finales V2-Golden entsteht. Das bisherige 4-Phasen-V2-Golden wird nicht still überschrieben, sondern als „experimentell, 4-Phasen-Prototyp, ersetzt“ gekennzeichnet bzw. mit dokumentierter Migration ersetzt. V1-Golden bleibt unangetastet.
- **Cache:** Es existiert kein persistierter V2-Cache (der Cache ist nur in Tests im Speicher eingebunden); das wird geprüft und dokumentiert. Der Prototyp wird nirgends als finaler V2 ausgegeben.
- **Aufwand:** Extraktions- und Gesamtzeit für 4/8/16 Phasen auf 10 NAMs × RHYTHM-T15 und LEAD-T15 (Mittel über NAMs je Mittelwert aus 5 Läufen nach einem Warm-up; NAM-Inferenz identisch).


### 9.6 Ergebnisse und Entscheidung (Rohdaten/Bericht: `tool/tonematch_envelope_v2/results/final_gate_*`, Skript `analyze_final.py`)

Auf den 18 festgeschriebenen Hold-out-Offsets (Median-CV in % über 10 NAMs × RHYTHM/LEAD / minimale Rangstabilität ρ; mittlerer / maximaler Absolutfehler gegen die Hop-1-Referenz):

| | V1 | V2-4 | V2-8 | V2-16 |
|---|---|---|---|---|
| `attackMs` CV / ρ | 14,48 / 0,49 | 6,63 / 0,83 | 3,52 / 0,92 | **1,11 / 0,92** |
| Attack-Fehler (ms) | 4,73 / 24,9 | 3,17 / 12,5 | 3,15 / 10,2 | 2,99 / 10,2 |
| `decayDbPerSec` CV / ρ | 20,87 / 0,88 | 5,88 / 0,95 | **2,31 / 0,99** | **0,92 / 0,99** |
| Decay-Fehler (dB/s) | 1,67 / 22,3 | 1,06 / 8,6 | 0,92 / 8,6 | 0,87 / 8,6 |
| `transientPeakToBody` CV / ρ | 5,09 / 0,86 | 1,58 / 0,95 | 0,85 / 0,95 | 0,22 / 0,96 |

- **Primäre Kriterien:** `attackMs` (CV < 3 % und ρ ≥ 0,95) wird von **keinem** Kandidaten erfüllt; V2-16 erreicht die CV (1,11 %), scheitert aber an der Rangstabilität (0,924). `decayDbPerSec` erfüllen 8 und 16 Phasen, 4 nicht (CV 5,88 %). `transientPeakToBody` ist bei allen nicht schlechter als V1 und erfüllt sogar die bevorzugten Werte. Attack-Genauigkeit ist bei allen Kandidaten nicht schlechter als V1 (besser: 4,73 → 3,0 ms mittlerer Fehler).
- **Synthetische Hüllkurventests** (4/8/16 Phasen, unveränderte Fälle und Toleranzen): bestanden. Decay folgt −8,686/τ, Attack-Zeiten und Transientenstärken sind unterscheidbar und monoton (Spike 0 / 1 / 3 → 0,4 / 4,3 / 9,3 dB), nichts ist flachgemedianed; mittlerer Attack-Fehler gegen Hop-1: V1 2,2 ms, 4 Phasen 1,87, 8 Phasen 1,43, 16 Phasen 1,31 ms.
- **Informationsverlust:** Die Rangfolge über die NAMs gegenüber der Hop-1-Referenz bleibt erhalten (Attack ρ 0,89 → 0,91–0,93, Decay 0,99, Transient 0,95–0,99); die Streuung zwischen NAMs bleibt (Attack 15,3 → 14,3–15,4 ms).
- **Übrige Features:** 17 100 verglichene Werte (alle Kandidaten, NAMs, Signale, Offsets) exakt identisch zu V1.

**Auswahlregel (9.4): Kein Kandidat erfüllt alle primären Kriterien → Mehrphasen-Ansatz VERWORFEN.** Es gibt keine finale AnalysisVersion 2 und kein finales V2-Golden. Keine weiteren Phasenzahlen werden getestet.

**Diagnose für später (nicht zur Nachoptimierung):** Die verbleibende Rangunsicherheit des Attacks (ρ 0,92 bei 8 und 16 Phasen) kommt von Beinahe-Gleichständen zwischen NAMs (Abstände der sortierten Werte bei Offset 0 oft nur 0,3–2,7 ms, also im Bereich der etwa 1–3 ms Auflösung) und von einzelnen NAMs mit zwei konkurrierenden Maxima auf dem Ripple-Rücken (CV 9–11 % auch bei 16 Phasen: NAM 07 und 08 in LEAD). Ein Rangkriterium über 10 eng liegende Attackzeiten ist damit an der Auflösungsgrenze der Metrik, nicht (nur) an der Rasterphase.

**Behandlung des Prototyps:** Das 4-Phasen-V2-Golden ist umbenannt und gekennzeichnet (`test/golden/tonematch_slice2_golden_experimental_4phase_rejected.json`, Feld `status`), nicht überschrieben und nicht als V2 geführt. `analysisVersion: 2` bleibt nur als Forschungs-/Reproduktionsoption im Extractor, ist dokumentiert als verworfen, und der persistente Cache (`StringStoreToneMatchCache`) speichert und liefert ausschließlich Version 1; ein Test sichert das ab. Im Repository existiert kein persistierter Analyse-Cache (die Klasse wird nur in Tests verwendet), es kann also kein Prototyp-Wert als finaler Wert gelesen werden. Das V1-Golden ist unverändert.

**Aufwand** (Desktop, T15, Mittel über 10 NAMs, ms; NAM-Inferenz identisch ≈ 1950 ms): RHYTHM V1 94 / 4 Phasen 117 / 8 Phasen 151 / 16 Phasen 207 (Gesamtanalyse +1,1 % / +2,8 % / +5,5 % gegenüber V1); LEAD 108 / 137 / 168 / 233 (+1,4 % / +2,9 % / +6,0 %). Mittelwert aus je 5 Läufen nach einem Warm-up, Median im Bericht.

**Entscheidung: Envelope REJECT (Mehrphasen-Ansatz verworfen); die Envelope-Architektur ist auf V1 eingefroren.** `attackMs` und `decayDbPerSec` bleiben in V1 rasterphasen-abhängig (Gitter-fremde Offsets: CV 14,5 % / 20,9 %) und sollen deshalb nicht in eine Ähnlichkeit eingehen, bevor ein anderes Verfahren existiert. `transientPeakToBody` ist mit CV 5,1 % deutlich stabiler.


## 10. Android Performance Gate (Vorab-Festlegung, 2026-10-03)

Ziel: die **eingefrorene** Tone-Match-V1-Pipeline (AnalysisVersion 1, RHYTHM-T15 und LEAD-T15, unveränderter Resampler/NAM-Inferenz/Extraktion/Cache-Key) auf echter ARM64-Android-Hardware messen. Rein lesend/rechnend: kein Matribox, kein USB/MIDI, keine Schreibzugriffe, keine Optimierung, keine Similarity.

**Gerät:** Samsung SM-G991B (Galaxy S21, Exynos 2100), Android 14 (API 34), arm64-v8a, 7,4 GB RAM; per USB verbunden und dabei ladend (Akkustand 93 %, Akkutemperatur 27,2 °C, Thermal Status 0 vor dem Lauf).

**Sets (vor dem Benchmark festgelegt, nicht nach Performance änderbar):**
- 10er-Set: dieselben 10 NAMs wie in 6.1 (01–10).
- 5er-Set, nach Charakter gewählt (nicht nach Geschwindigkeit): **01** Fender Pano-Verb Clean2 (Clean), **03** JVM410 crunch (Crunch), **04** Marshall JVM410H Boosted Full Rig Standard (Classic British High Gain), **06** EVH 5150 III Amp Only (5150-artig), **08** Gojira Joe Duplantier (Full-Rig, deutlich anderer Charakter). Hinweis: 06 und 08 sind SlimmableContainer-Modelle und waren auf dem Desktop die langsamsten; das 5er-Set ist damit eher konservativ.

**Messung:** Je Szenario (RHYTHM×5, RHYTHM×10, LEAD×5, LEAD×10) 3 Cold-Runs (leerer Analyse-Cache; NAM-Runtime normal initialisiert) und danach 3 Warm-Runs (vollständig aus dem Cache). Je Kandidat: NAM-Load, Inferenz, Extraktion, Cache-Write, Gesamt. Je Run: WAV-Laden/Dekodieren, Resampling (44,1→48 kHz, unverändert), T15-Ableitung, Gesamtzeit. Min/Median/Max. Kandidaten werden strikt sequenziell in **einem Worker-Isolate** analysiert (eine Engine zur selben Zeit, keine parallelen Inferenzen); der Main-Isolate rechnet nicht.
- **Cache-Hit:** erwartet keine Engine und keine Inferenz (gezählt, nicht angenommen).
- **Speicher:** Prozess-RSS (`/proc/self/status`, Probe alle 100 ms im Main-Isolate) vor/Spitze/nach; Trend über wiederholte Runs.
- **Thermik:** Host-seitig `dumpsys thermalservice` und Akkutemperatur alle 5 s; kein künstliches Kühlen; Run 1 gegen Run 3.
- **Reaktionsfähigkeit:** Heartbeat-Timer (10 ms) im Main-Isolate (max. Verspätung), Frame-Timings, laufende Animation; zusätzlich echte Touch-Eingaben per `adb input` (Scrollen, Cancel) während eines 10-NAM-Cold-Runs; ANR per logcat/dumpsys.
- **Cancel:** während eines 10-NAM-Laufs per gemeinsamem Cancel-Flag (kein Isolate-Kill); die laufende NAM-Inferenz darf in ihrem 1-s-Chunk fertig laufen, danach startet kein weiterer Chunk/Kandidat, das Ergebnis des laufenden Kandidaten wird verworfen (nicht in den Cache geschrieben), die Engine wird entsorgt; anschließend muss ein neuer Lauf gelingen.
- **Bewertung** (GOOD / ACCEPTABLE / TOO SLOW) wird anhand der gemessenen Zeiten begründet; es gibt keine vorab erfundenen harten Grenzwerte und keine Fake-Prozentanzeige.

**Bereitstellung der Evaluation-WAVs:** Die zwei Original-WAVs (RHYTHM, LEAD) und die zehn `.nam` werden per `adb push` in das app-spezifische externe Verzeichnis der Benchmark-App kopiert (`/sdcard/Android/data/de.neevel.wyrmtone.bench/files/`) und nach dem Test wieder gelöscht. Sie werden **nicht** in `pubspec.yaml` aufgenommen und stecken nicht im APK. Die Benchmark-App läuft unter eigener App-ID, damit die installierte WyrmTone-App samt Daten unberührt bleibt; sie wird nach dem Test deinstalliert.


### 10.1 Ergebnisse (Samsung SM-G991B, Android 14, arm64-v8a; Rohdaten/Berichte: `tool/tonematch_android_bench/results/`, Harness: `tool/tonematch_android_bench/`)

Release-Build (AOT) des Harness als eigener Einstiegspunkt, Analyse in einem Worker-Isolate, sequenziell, AnalysisVersion 1. Zwei vollständige Suiten: Suite 1 (Start bei Akku 32 °C), Suite 2 (Wiederholung nach etwa 5 Minuten Ruhe, Akku 33 °C). Gerät per USB verbunden und ladend.

**Cold-Wartezeit** (Gesamtlauf inkl. Signal-Vorbereitung, s; min / Median / max über 3 Läufe):

| | Suite 1 | Suite 2 |
|---|---|---|
| RHYTHM × 5 | 13,7 / 14,5 / 15,7 | 13,5 / 17,0 / 19,3 |
| RHYTHM × 10 | 45,9 / 47,4 / 47,9 | 46,3 / 47,4 / 58,9 |
| LEAD × 5 | 20,1 / 20,2 / 20,6 | 24,2 / 25,4 / 25,9 |
| LEAD × 10 | 48,6 / 51,3 / 59,5 | 60,1 / 61,1 / 61,6 |

**Je Kandidat (cold, ms, Median [min–max], 90 Analysen je Suite):** NAM-Load 41–43 [23–83]; Inferenz 4938–5498 [944–7551]; Feature-Extraktion 215 [138–386]; Cache-Write 3,2 [1,9–44]; Gesamt 5240–5742 [1130–7883]. Inferenz macht 94–96 % aus. Die zwei SlimmableContainer-NAMs (06, 08) brauchen nur 1,1–1,9 s, die übrigen WaveNet-NAMs 4,7–7,4 s. Die Android-Features sind numerisch identisch zum Desktop (max. relative Abweichung 0,0006 % über alle 20 NAM × Signal-Kombinationen, inkl. der Slimmable-NAMs).

**Signal-Vorbereitung je Lauf (ms):** WAV-Laden/Dekodieren 124–234, Resampling 111–230, T15-Ableitung 45–109, zusammen 0,3–0,55 s (die vollständige Original-WAV wird dekodiert; ein vorab abgeleitetes kanonisches T15 würde das etwa halbieren).

**Warm (alles aus dem Cache):** 2–20 ms für 5 bzw. 10 Kandidaten (je Cache-Lesen median 0,4–0,8 ms). Engine erzeugt: **0**, Analysen/Inferenz: **0** (gezählt, in allen 24 Warm-Läufen).

**Speicher** (Prozess-RSS): Ausgangswert 210–224 MB; Spitze während 5 Kandidaten 260–288 MB, während 10 Kandidaten 272–294 MB (höchstens +49 MB über dem Wert vor dem Lauf); nach den Läufen Plateau 241–275 MB; VmHWM 287–297 MB. Zwischen den Wiederholungen eines Szenarios wächst der Wert nicht (Lauf 1 → Lauf 3: −3 bis +3 MB); keine OOM. Es existiert nur eine Engine zugleich.

**Thermik/Throttling:** Suite 1: Android-Thermal-Status durchgehend 0 (AP bis 47,6 °C, Haut 38,0 °C, Akku 32 → 36,1 °C). Suite 2: Status zeitweise 1 (AP bis 46,6 °C, Akku 33,3 → 37,5 °C). Die Laufzeit steigt unter Dauerlast deutlich: Lauf 3 gegenüber Lauf 1 +15 % / −3 % / −1 % / +16 % (Suite 1) bzw. +43 % / +24 % / +5 % / +1 % (Suite 2, RHYTHM×5 / ×10 / LEAD×5 / ×10); der Lauf nach dem Cancel war 72 % bzw. 45 % langsamer als die ersten drei Läufe. Alle Teilschritte werden gleichzeitig langsamer (auch Dekodieren und Resampling), das spricht für Taktdrosselung des SoC und nicht für Software-Effekte. Es gab keine künstliche Kühlung.

**Reaktionsfähigkeit:** Der Main-Isolate rechnet nicht. Während der Cold-Läufe: Heartbeat-Timer (10 ms) max. 12,9 ms (Suite 1) bzw. 47 ms (Suite 2) verspätet, p99 ≤ 2,0 ms; bei 48 260 bzw. 55 288 gerenderten Frames in Suite 1 kein Frame über 33 ms, in Suite 2 drei über 33 ms (schlechtester Frame 52 ms), keiner über 100 ms. Per echter Touch-Eingabe (`adb input`) wurde während eines laufenden 10-NAM-Cold-Runs gescrollt (Liste bewegt sich, Fortschrittsanimation läuft, Text „Analysiere 2 von 10“) und der Abbrechen-Button gedrückt; dabei 2298 Frames, keiner über 16,7 ms (schlechtester 16,4 ms). Kein ANR (logcat).

**Cancel:** per Flag (kein Isolate-Kill). Im 10-NAM-Lauf 1 s nach Start des 3. Kandidaten angefordert: 370–413 ms bis zum Stopp (laufender 1-s-Chunk wurde beendet, danach kein weiterer Chunk), Kandidat 3 verworfen und nicht in den Cache geschrieben, kein 4. Kandidat gestartet, Engine entsorgt (Worker-`finally`), die 2 fertigen Kandidaten blieben gültig im Cache. Der anschließende neue Lauf (RHYTHM×5) gelang und lieferte Feature-Werte identisch zu den früheren Läufen; ebenso nach dem Abbruch per Touch.

**Einordnung (aus den Messzeiten, ohne vorab erfundene Grenzwerte):** 5 Kandidaten cold ≈ 14–26 s: **ACCEPTABLE** (spürbar, aber mit candidate-basiertem Fortschritt „Analysiere 3 von 5“ und Cancel tragbar; erstes Ergebnis nach etwa 5 s). 10 Kandidaten cold ≈ 46–62 s und unter Dauerlast mehr: **TOO SLOW** als einzelner blockierender Standard-Ablauf; nur als bewusst gewählte, abbrechbare tiefere Suche vertretbar. Warm ≈ 2–20 ms: **GOOD**. Innerhalb einer atomaren Inferenz (5–7 s) gibt es keinen messbaren Fortschritt; echter Fortschritt kann nur pro Kandidat gezeigt werden.

**Bereitstellung/Durchführung:** WAVs und `.nam`-Dateien per `adb push` in das app-spezifische externe Verzeichnis der Benchmark-App, nach dem Test mit der Deinstallation der Benchmark-App entfernt; nicht in `pubspec.yaml`, nicht im APK (0 `.wav` im APK geprüft). Die Benchmark-App läuft mit eigener App-ID (`de.neevel.wyrmtone.bench`), die über die Gradle-Property `wyrmtoneBenchApplicationId` in `android/gradle.properties` gesetzt werden muss (die Umgebungsvariable greift nicht); die Paket-ID des APKs ist vor dem Installieren mit `aapt2 dump badging` zu prüfen.


## 11. Tone Match als Produktfluss (Stand 2026-10-03)

Die Forschungsphase (Envelope, Android-Leistung) ist abgeschlossen; Analysis V1 bleibt unverändert. Dieser Abschnitt beschreibt, was der Endnutzerfluss wirklich tut und was nicht.

**Ablauf:** Eingabe („Gary Moore – The Loner“) → `ToneIntent` aus dem lokalen Wissen → Vorauswahl nach **Beschreibung** über **alle** nutzbaren lokalen NAMs → die besten **5** werden akustisch geprüft (Cache zuerst) → Similarity V1 → höchstens **3** Treffer. „Weitere Sounds prüfen“ prüft ausdrücklich auf Nutzeraktion die nächsten 5; nichts läuft von selbst weiter. Weniger als 5 NAMs: alle werden geprüft. Bereits gemessene NAMs werden nie erneut gemessen (Schlüssel: NAM-SHA-256 + SHA-256 der ORIGINAL-Aufnahme + Signal-ID + Analyse-Version). „NAM ansehen“ öffnet die bestehende NAM-Detailseite; dort bleibt jeder Übertragungsschritt wie bisher bestätigungspflichtig. Tone Match startet nie eine Übertragung.

**Akustisches Zielprofil** (`AcousticTargetProfile`, nur relative Richtungen mit Herkunft):
- Klang (hell/ausgewogen/dunkel) aus dem Mittel von Höhen, Präsenz und Helligkeit der Klangbeschreibung (Grenzen 40/60),
- Mitten (zurückgenommen/ausgewogen/kräftig) aus der Mitten-Angabe (Grenzen 42/58),
- Dynamik (lebendig/ausgewogen/komprimiert) aus dem Gain-Anteil (Grenzen 35/65); dieser Zusammenhang („mehr Gain ≈ stärker komprimierte Dynamik“) ist als **HEURISTIC** gekennzeichnet.
Nicht zugeordnet (und deshalb ohne Einfluss): Straffheit, Anschlag, Sustain, Delay, Hall, Bass. Die Rolle wählt die feste Testaufnahme (Rhythm/Lead/Clean). Für „The Loner“ ergibt sich Lead, kräftige Mitten, ausgewogene Dynamik; für „Heresy“ Rhythm, zurückgenommene Mitten, komprimierte Dynamik (jeweils aus der vorhandenen kuratierten Beschreibung, mit Evidenz).

**Similarity V1:** Verwendet nur stabile Messwerte: Schwerpunkt und Rolloff des Spektrums (zu einer Helligkeits-Dimension zusammengefasst), Anteil von MID + HIGH_MID (Mitten-Dimension) und Crest-Faktor (Dynamik). Nicht verwendet: `attackMs`, `decayDbPerSec`, `transientPeakToBody` (diagnostisch), Sättigungs-Composite und seine Komponenten, Flachheit, Bandbreite, einzelne Bänder, Hüllkurven-Umfang. Ziele sind relativ: Jeder Wert wird als Rangposition unter den bereits geprüften Sounds gelesen. Dimensionen werden zu zwei Gruppen (Klangfarbe, Dynamik) gemittelt; jede Gruppe mit Ziel zählt gleich. Der interne Score dient nur der Reihenfolge; Gleichstand entscheidet die Beschreibungs-Vorauswahl, dann der Name. Es gibt **keine Prozentzahl und keine Qualitätsklasse** („Sehr passend“ o. ä.), weil es dafür keine kalibrierten Schwellen gibt; angezeigt werden die passendsten Sounds in Reihenfolge, mit Begründungen. Aussagen wie „heller als die meisten geprüften Sounds“ erscheinen nur bei mindestens drei geprüften Sounds und nur dort, wo Ziel und Messwert sie tragen.

**Grenzen:** Die Reihenfolge ist relativ zu den geprüften Sounds (kommen weitere hinzu, kann sie sich ändern) und kein Beleg für Originalequipment. Gemessen wird immer mit derselben festen Testaufnahme, nicht mit der gewählten Gitarre; Gitarre und Zielgerät beeinflussen nur Einordnung und Aktionen. Ohne die Testaufnahmen auf dem Gerät (ihre Verteilung ist noch nicht entschieden; Suchort: app-eigener externer Ordner `tonematch/evaluation`) zeigt die Seite ehrlich nur die Vorauswahl nach Beschreibung an.

### 11.1 Geräte-Review (Galaxy S21, 2026-10-03)

Fluss, Abbrechen (echte Oberfläche), erneutes Suchen, „Weitere Sounds prüfen“ und „NAM ansehen“ wurden auf dem Gerät geprüft; Korrekturen: Begründungen nennen Abweichungen offen („weicht vom Gesuchten ab“) und stehen unter einer Zeile „Gesucht: …“, Platzhinweis für importierte Modelle nur einmal, nur Rang 1 mit gefülltem Button, Navigationsleisten-Beschriftung bricht bei großer Systemschrift nicht mehr. **Offen:** Tone Match braucht die kanonischen Testaufnahmen (nicht Teil der Release-Verteilung, App-Ordner `tonematch/evaluation`); wie sie zu Nutzern kommen, ist eine eigene Produkt-/Architekturentscheidung.

### 11.2 Messsignale im Produkt (2026-10-03)

Tone Match liefert seine Messsignale mit der App aus; keine Einrichtung, kein Download, kein Netz. Ausgeliefert werden nur die vom Produktfluss genutzten, bereits validierten PCM-Signale (Mono, Float32, 48 kHz, als einfache WAV-Container in `assets/tonematch/runtime/`): Rhythm-T15 und Lead-T15 (je 15,5 s) sowie Clean (14,28 s, wird für Clean-Ziele wie „Come As You Are“ gebraucht). Erzeugt mit `tool/tonematch_runtime/generate_runtime_signals.dart` ausschließlich über die festgelegte Ableitung (der Generator bricht ab, wenn T15 nicht byte-gleich zur Validierungs-Gate-Version ist). Die Forschungsaufnahmen (`assets/tonematch/evaluation/`) sind weiterhin keine App-Assets. Cache-Schlüssel unverändert (SHA der Originalaufnahme + `…#T15` + Analyseversion 1): vorhandene Messwerte bleiben gültig. Fehlt oder ist ein Signal beschädigt (Hash/Format), wird nur geloggt und die Seite zeigt die Vorauswahl nach Beschreibung. Der Ordner `tonematch/evaluation` im App-Verzeichnis wirkt nur noch als Override in Nicht-Release-Builds. Herkunft: eigene Gitarren-DI-Aufnahmen, kein Songmaterial. Der Byte-Vergleich mit den lokalen Originalaufnahmen (`assets/tonematch/evaluation/`, git-ignoriert) läuft nur gated als `test/tool/tone_match_runtime_source_identity_test.dart` (`WYRMTONE_RUN_SOURCE_IDENTITY=1`); der normale Test `test/tone_match_runtime_signals_test.dart` prüft ausschließlich die versionierten Runtime-Signale (Format, Rate, Länge, PCM-SHA-256).

| Signal | Samples | PCM-SHA-256 |
|---|---|---|
| Rhythm T15 | 744000 | 6a592f7a…9803a5 |
| Lead T15 | 744000 | c21ae35c…1a7d |
| Clean | 685259 | 8b43e255…a7fa0 |

Release-APK (flutter build apk --release): 62.970.051 B ohne → 71.663.946 B mit Signalen (+8.693.895 B, +13,8 %). Die WAVs werden unkomprimiert abgelegt; Deflate würde je Datei nur rund 7–8 % sparen und lohnt die Komplexität nicht.

## 12. Tone Match V2 – TONE3000-Suche: Phase A (live geprüft 2026-10-03)

Quellen: <https://www.tone3000.com/api>, <https://www.tone3000.com/api/terms>, <https://github.com/tone-3000/api>, Changelog.

- **Auth:** OAuth 2.0 + PKCE; Publishable Key (`client_id`) darf in die App, Secret Key (`t3k_cs_…`) nie. Auch die Suche braucht ein Nutzer-Access-Token. Unser OAuth-PKCE (Tokens in Secure Storage, Callback `wyrmtone://oauth/callback`) ist kompatibel.
- **`GET /api/v1/tones/search`:** `query`, `page`, `page_size` (max. 25), `sort` (`best-match`, `newest`, `oldest`, `trending`, `downloads-all-time`), `gears`, `sizes`, `tags`, `makes`, `creators`, `format` (`nam`, `ir`, …), `architecture` (`1`/`2`/`custom`; ohne Angabe A1 + Custom), `calibrated`, `verified`. Antwort je Tone: `id`, `title`, `description`, `gear`, `images`, `format`, `license`, `user`, `sizes`, `makes`, `tags`, `models_count`, `downloads_count`, … Modelle über `GET /models?tone_id=`: `id`, `name`, `size`, `architecture_version`, `model_url` (Download nur mit Bearer-Token), `tone_id`. Kein Byte-Größenfeld.
- **Rate Limit:** 100 Anfragen/min Standard; die Suche ist „heavily rate-limited by default“, für Produktion ist `support@tone3000.com` zu kontaktieren.
- **Tarife (wörtlich):** Free tier „may only use the OAuth prompt flows (`select_tone` and `get_tone`) and bounded list endpoints (`favorited`, `downloaded`, `created`, `trending` and `latest`)“ und nur für nicht-kommerzielle Produkte; „Commercial products may use the full API“, müssen aber vor Veröffentlichung von TONE3000 geprüft und freigegeben werden. **`/tones/search` ist damit im Free tier nicht erlaubt.**
- **Weitere Bedingungen:** nicht scrapen, spiegeln oder den Katalog cachen; Modelle nur auf Nutzeranfrage laden; „Powered by TONE3000“ mit Link, Creator-/Tone-/Lizenzangaben nicht verändern; Design Requirements (Einstieg über TONE3000-Auswahl, Partnerschafts-Splash vor der Anmeldung, Listen mit Bild/Gear/Format/Creator, Tone-Detailansicht mit Modellauswahl, Logo-Regeln).
- **Offiziell unterstützte Alternative:** Select-Flow (`prompt=select_tone`) mit den dokumentierten Filtern `format`, `architecture`, `gears`, `calibrated` (genutzt wird bereits `format=nam&architecture=1`). Eine Textsuche oder Vorbelegung der Auswahl ist dort nicht dokumentiert.

**Entscheidung/Stand:** Die geplante automatische Kandidatensuche über `/tones/search` ist nur mit kommerzieller Vereinbarung und TONE3000-Freigabe zulässig, ob WyrmTone dort fällt, ist eine Produkt-/Rechtsentscheidung. Bis dahin wird nichts implementiert (kein Scraping, kein Umgehen). Lokales Tone Match bleibt unverändert.

## 13. Hör-Match / Reference Tone Match – Research Spike, Gate A (2026-10-03)

Forschung, kein Produktcode (`tool/tonematch_reference_match/`, `test/tool/tone_match_reference_match_experiment_test.dart`, nur mit `WYRMTONE_RUN_REFMATCH=1`; Rohdaten `results/results.json`). Similarity V1, AnalysisVersion 1 und Runtime-Signale unverändert. Wir suchen vorhandene Modelle, die einer Referenz ähneln; es wird kein Modell erzeugt (kein „Profiling“).

**Aufbau.** 14 reale lokale NAMs (10 aus dem Validierungs-Set: Fender Pano-Verb Clean2, Badlander Clean-Pushed und Crush Heavy-Solo, JVM410 Crunch und Boosted Full Rig, Bugera 6262, EVH 5150 III Amp Only, Gojira, JP2C Lead und Power-Amp-Only; dazu Boogie Mark V Clean/Rhythm/Lead und Fender Super Reverb sm57). Jedes NAM war einmal die Referenz: DI A → NAM → „Aufnahme“. Kandidaten: DI B → alle NAMs → Merkmale. Referenz-Merkmale zweifach: wie im Produkt (Gate aus dem DI) und „blind“ (Gate aus der Referenz selbst, weil bei echtem Audio kein DI vorliegt).
- **Merkmale (nur die akzeptierten stabilen):** Schwerpunkt, Rolloff85, MID+HIGH_MID-Anteil, Crest. Nicht verwendet: attackMs, decayDbPerSec, transientPeakToBody, Saturation Composite, HF Generation.
- **Normalisierung:** die Produkt-Tonnormalisierung des Extraktors (Ausgang auf −20 dBFS Aktiv-RMS), sonst keine. Darstellung: Helligkeit = Mittel aus z(ln Schwerpunkt) und z(ln Rolloff), Mitten = z(logit Anteil), Dynamik = z(Crest); z über die Kandidatenmenge des Falls.
- **Distanzen (vorab festgelegt, nicht optimiert):** D1 = RMS der drei Dimensionen; D2 = V1-ähnliche Gruppen (Klangfarbe und Dynamik je zur Hälfte); D3 = mittlere Perzentil-Rangdifferenz.
- **A1 (gleiche Performance, DI A = DI B):** Pipeline-Sanity. **Ergebnis: bestanden**, Top-1 = Top-3 = MRR = 1,00 in allen 3 Rollen, alle 3 Distanzen, DI-Gate und blind (42 Fälle je Variante).
- **A2 (unabhängiges DI B): BLOCKED – ein zweites unabhängiges DI je Rolle fehlt.** Vorhanden ist nur je eine Aufnahme (rhythm/lead/clean). Als Näherung „A2x“ wurden die Hälften derselben Aufnahme verwendet (Referenz aus erster, Kandidaten aus zweiter Hälfte, dieselbe T15-Ableitung). Das ist **keine unabhängige Performance** und zählt nicht als A2.
- **A2x-Ergebnis** (Referenz-NAM ist unter den Kandidaten, 14 Kandidaten, Zufall: Top-1 0,07 / Top-3 0,21 / MRR ≈ 0,23): D2 blind Top-1 0,36, Top-3 0,64, MRR 0,54; D2 mit DI-Gate Top-1 0,38, Top-3 0,69, MRR 0,57; D1 und D3 schlechter (Top-3 0,50–0,60). Je Rolle (D2 blind): Rhythm Top-3 0,43, Lead 0,71, Clean 0,79.
- **Warum es einbricht:** Dasselbe NAM verschiebt sich zwischen zwei Ausschnitten derselben Aufnahme in Schwerpunkt, Rolloff und Mitten um etwa so viel wie der Abstand zwischen NAMs (Rhythm: 2–3×, Lead/Clean: 0,7–0,9× der NAM-Streuung); nur der Crest ist stabil (0,1–0,3×). Das Spektrum einer Aufnahme hängt also stark davon ab, was gespielt wurde (Palm Mute, Lage, Akkord), nicht nur vom Amp. Das ist die zentrale Grenze von Hör-Match ohne bekanntes Eingangssignal.
- **Leave-one-out (Referenz-NAM entfernt, D2 blind):** High-Gain-Referenzen landen überwiegend bei High-Gain/Crunch-Modellen (am besten in der Lead-Rolle), Clean-Referenzen bei den anderen Clean-NAMs, aber nicht verlässlich (z. B. Pano-Verb Clean2 findet bei der Clean-Rolle High-Gain-Nachbarn). Top-1 gleiche Kategorie (nur benannte Kategorien): 16 von 24 bei A2x. Offensichtlich falsch (Clean-Referenz mit High-Gain im Top 3 oder umgekehrt): 3 von 33 (A2x) bzw. 4 von 33 (A1). Einordnung: **PARTIAL**.
- **Bewertung:** Digital taugt die Pipeline (A1), aber die Zuordnung ist nicht unabhängig von der Performance, ein Handy-Mikrofon-Test ist noch nicht gerechtfertigt. Ein Vollsong-Anspruch ist nicht gerechtfertigt, ein Anspruch für isolierte Gitarre noch nicht.

**Vorab festgelegte Kriterien für den echten A2 (mit unabhängigem DI B; nach Kenntnis der A2x-Näherung festgelegt, daher nur für den echten A2 und Gate B bindend):** über alle Rollen, Referenz unter den Kandidaten, beste der drei Distanzen ohne Nachbesserung: Top-3 ≥ 0,70, MRR ≥ 0,60, keine Rolle mit Top-3 < 0,50; Leave-one-out „offensichtlich falsch“ ≤ 10 % der benannten Referenzen. **Gate B (Lautsprecher + Raum + S21-Mikrofon):** Top-3-Rate ≥ 80 % der A2-Rate, MRR ≥ 70 % der A2-MRR, Kategorie (Clean/Crunch/High-Gain) des Top-1 bei ≥ 80 % der benannten Referenzen stabil, offensichtlich falsch ≤ 15 %.

**Was Marcel für den echten A2 aufnehmen müsste:** je Rolle (Rhythm, Lead, Clean) ein zweites, unabhängiges trockenes DI wie bei den bestehenden (Matribox-USB, linker Kanal, 44,1 kHz/24 Bit), 45–60 s, anderes Riff/andere Passage als in der ersten Aufnahme, gleiche Gitarre und gleicher Pickup, möglichst gleicher Pegel, nicht normalisieren.

**Aufnahmeplan Gate B (erst nach bestandenem A2, noch nicht vorbereitet):** stabiler Lautsprecher (Studiomonitor oder gutes Regallautsprecher-Paar, keine Handy-Lautsprecher), Handy 30 cm vor dem Lautsprecher auf Achse in Hochtönerhöhe, gleiche Position für alle Clips, Raum ohne laufende Geräte, Lautstärke fest (Bezug: Referenz-NAM-Render mit gleichem Pegel, Wiedergabepegel einmal markieren und nie ändern), je Clip 15 s, Aufnahme-App mit WAV 48 kHz/16 Bit ohne Rauschunterdrückung/AGC (Quelle „unprocessed“, falls wählbar), plus 15 s Raumrauschen. Referenzen: 8 NAMs (Clean, Crunch, High-Gain Rhythm/Lead, Amp-only, Full-Rig) × Rhythm und Lead.

**Nicht Teil des Spikes:** Reglerwerte (Gain, Bass, Mitte, Höhen) werden aus Aufnahmen nicht abgeleitet. Die große IR-Sammlung wurde nicht einbezogen; NAM + IR Matching wäre höchstens ein späterer zweiter Forschungsschritt, falls Hör-Match grundsätzlich trägt.

### 13.1 GuitarJam A2 – unabhängige Performances (2026-10-03)

Begriffe: **A1** = identische Performance (Sanity), **A2x** = Hälften derselben Aufnahme (Näherung, nicht unabhängig), **GuitarJam A2** = Datensatz mit unabhängigen Performances. Research only, keine Produktaussage; Similarity V1, AnalysisVersion 1 und Runtime-Signale unverändert.

**Datensatz.** <https://huggingface.co/datasets/Julian-br/GuitarJam>, Revision `2d467bfec90af19301b01123494f4b2ba64c5a3a`, Lizenz CC0-1.0 (Dataset-Karte und API geprüft), 580 WAV-Clips, 44,1 kHz, 16 Bit, mono, DI ohne Amp/Effekte (Fender Stratocaster Neck/Middle, Focusrite Scarlett Solo), bezogen am 2026-10-03. Beschrieben als monophone Melodien/Improvisationen. Ausgewählt wurden vorab genau 30 Clips: Clip k = `sortierte_Pfadliste[int((k+0.5)·580/30)]` (Liste aller 580 WAV-Pfade, sortiert), eingefroren in `tool/tonematch_reference_match/guitarjam_selection.json` (mit SHA-256 je Datei) vor jeder Auswertung; keine Ausnahmen nötig (alle 30 ladbar, nicht still). Die WAVs liegen nur lokal in `tool/tonematch_reference_match/data/guitarjam/` (per `.gitignore` ausgeschlossen, nicht im Repo/APK). Auffällig: alle Clips haben exakt −30,0 dBFS RMS (der Datensatz ist pegelnormalisiert), unsere Kanon-DIs liegen bei −31 bis −36 dBFS; die Clips wurden unverändert (nur 44,1→48 kHz mit dem Produkt-Resampler) durch die NAMs gerechnet.

**Aufbau.** Dieselben 14 NAMs und dieselben Merkmale/Distanzen D1/D2/D3 wie in §13, unverändert, keine Gewichtsanpassung. 30 DIs × 14 NAMs = 420 Renderings (420 gerechnet; Zeitmessung 14 NAMs × 1 Clip = 50 s, Gesamtlauf rund 13 Minuten). Vorab festgelegte Paare: Referenz-Clip i gegen Kandidaten-Clip (i+5), (i+11), (i+17) mod 30, also 90 Cross-Performance-Paare × 14 Referenz-NAMs = **1260 Ranking-Fälle** je Distanz und Modus (Referenz und Kandidaten nie aus demselben Clip). **Primär: BLIND** (Referenz-Gate aus der Referenz selbst, kein Original-DI); DI-Gate nur als Kontrolle. Rohdaten: `results/guitarjam_a2_raw.json`, ausgewertet in `results/guitarjam_a2_results.json` (`analyze_guitarjam.py`).

**Ergebnis blind** (Referenz-NAM unter den 14 Kandidaten; Zufall Top-1 0,07 / Top-3 0,21 / MRR ≈ 0,23):

| Distanz | Top-1 | Top-3 | Top-5 | MRR | Median-/Mittel-Rang | Top-3 je Kategorie (clean / crunch / highgain) | offensichtlich falsch (LOO) |
|---|---|---|---|---|---|---|---|
| D1 | 0,364 | 0,650 | 0,800 | 0,547 | 2 / 3,51 | 0,50 / 0,56 / 0,80 | 95/990 (9,6 %) |
| **D2** | 0,386 | **0,713** | 0,839 | **0,578** | 2 / 3,13 | 0,51 / 0,62 / 0,86 | 89/990 (9,0 %) |
| D3 | 0,319 | 0,605 | 0,794 | 0,510 | 3 / 3,65 | 0,50 / 0,53 / 0,71 | 112/990 (11,3 %) |

Rangverteilung D2: Rang 1 39 %, 2–3 33 %, 4–5 13 %, 6–10 12 %, 11–14 4 %. Kontrolle mit DI-Gate: D2 Top-1 0,426, Top-3 0,726, MRR 0,603.

**Vorab festgelegte Kriterien** (Top-3 ≥ 0,70, MRR ≥ 0,60, keine Kategorie mit Top-3 < 0,50, offensichtlich falsch ≤ 10 %): Blind erreicht nur D2 Top-3, die MRR liegt knapp darunter (0,578 < 0,60); D1 und D3 verfehlen mehr. **Nicht bestanden (GuitarJam A2: FAIL, knapp).** Nur die DI-Gate-Kontrolle mit D2 erfüllt alle Kriterien, zählt aber nicht, weil der Produktfall kein Original-DI hat. Die Kriterien wurden nicht angepasst.

**Je NAM (D2, blind: Top-1 / Top-3 / MRR / Medianrang):** JP2C Lead 09: 0,49 / 0,94 / 0,70 / 2; Badlander Heavy-Solo 07: 0,78 / 0,91 / 0,84 / 1; EVH 5150 06: 0,40 / 0,88 / 0,64 / 2; Bugera 6262 05: 0,41 / 0,84 / 0,64 / 2; Gojira 08: 0,44 / 0,82 / 0,64 / 2; JVM410 Full Rig 04: 0,60 / 0,79 / 0,72 / 1; Mark V Lead: 0,43 / 0,77 / 0,62 / 2; JP2C Power-Amp-Only 10: 0,22 / 0,70 / 0,47 / 3; FenderSR: 0,40 / 0,67 / 0,58 / 2; JVM410 Crunch 03: 0,21 / 0,62 / 0,47 / 2,5; Badlander Clean-Pushed 02: 0,31 / 0,61 / 0,49 / 3; Mark V Rhythm: 0,19 / 0,57 / 0,43 / 3; Pano-Verb Clean2 01: 0,30 / 0,50 / 0,46 / 3,5; Mark V Clean: 0,21 / 0,37 / 0,39 / 4,5. Die High-Gain-Modelle werden deutlich besser wiedererkannt als die Clean-Modelle.

**Verwechslungen (Top-1 bei benannten Kategorien):** High-Gain → High-Gain 441 von 540 (82 %), → Crunch 65, → Clean 2; Clean → Clean 163 von 270 (60 %), → High-Gain 42 (16 %), → Crunch 14; Crunch → High-Gain 65, → Crunch 58, → Clean 11. Einzelne High-Gain-NAMs sind untereinander austauschbar (05↔09 33 %, 03/08/04/06 gegenseitig), Clean-NAMs landen beieinander (FenderSR, JP2C Power-Amp-Only, Mark V Rhythm, Mark V Clean, Pano-Verb). Trennung Clean/Crunch/High-Gain: **PARTIAL** (High-Gain gut, Clean mittel, Crunch schwach).

**Leave-one-out (Referenz-NAM entfernt):** Nachbarschaften sind auf Gruppenebene stabil: {Bugera 6262, JP2C Lead, Badlander Heavy-Solo, Mark V Lead}, {JVM410 Full Rig, JVM410 Crunch, EVH 5150, Gojira} und die Clean-Gruppe; die genaue Reihenfolge innerhalb der Gruppe wechselt (Anteil des häufigsten Top-1-Nachbarn 0,19–0,69, mittlere Top-3-Übereinstimmung 0,27–0,78 je nach NAM, am stabilsten Badlander Heavy-Solo).

**Variation derselben NAM über die 30 DIs gegenüber der Variation zwischen NAMs** (Standardabweichung, within / between der NAM-Mittel): ln Schwerpunkt 0,365 / 0,430 (0,85×), ln Rolloff 0,475 / 0,572 (0,83×), Mitten-Logit 1,093 / 0,787 (1,39×), Crest 1,42 dB / 3,01 dB (0,47×). Bei monophonen Melodien variiert das Spektrum innerhalb eines NAMs also etwa so stark wie zwischen den NAMs, bei den Mitten sogar stärker; nur der Crest trennt NAMs klar. **Performance-Invarianz: PARTIAL.**

**Einordnung.** Die Merkmale tragen eine grobe Zuordnung (Top-3 70 % blind, gut für High-Gain), reichen aber nicht für eine verlässliche Einzelmodell-Empfehlung; ein Handy-Mikrofon-Test ist noch nicht gerechtfertigt. Nicht belegt: Metal-Rhythmus, Palm Mute, Akkorde (GuitarJam ist monophon). Keine Gewichtsableitung aus diesen Daten.

### 13.2 IDMT A2 und Multi-Performance-Signatur (2026-10-03)

Begriffe: **A1** = identische Performance (Sanity), **A2x** = Hälften derselben Aufnahme (Näherung), **GuitarJam A2** = §13.1, **IDMT A2** = dieser Abschnitt (vielfältigere unabhängige DI-Performances), **IDMT Multi-Performance-Signatur** = NAM-Beschreibung aus mehreren Performances. Research only; Similarity V1, AnalysisVersion 1 und Runtime-Signale unverändert. ToneTwist wurde nicht heruntergeladen, nicht analysiert und nicht verwendet (späterer Holdout).

**Datensatz.** Fraunhofer IDMT-SMT-Guitar, <https://zenodo.org/records/7544110> (DOI 10.5281/zenodo.7544110), Version 1.0.0 (Datei `IDMT-SMT-GUITAR_V2.zip`, MD5 `06796e08731bccffaed6ae59361486e4` nach dem Download bestätigt), Lizenz **CC BY-NC-ND 4.0** (nur lokal, keine Weitergabe, keine abgeleiteten Audiodateien committet), bezogen am 2026-10-03. 1173 WAV; direkt am Interface aufgenommene Gitarren (Ausnahme: ein akustischer Teil mit Mikrofon). Genutzt: Dataset 2 (3 E-Gitarren: Gibson Les Paul, Fender Stratocaster, Aristides 010; Licks mit Spielweisen picked/muted/finger-style und Ausdrucksformen; 24 Bit), Dataset 3 (Ibanez RG2820, Pickup neck bzw. middle) und Dataset 4 (E-Gitarren Career SG und Ibanez RG2820, polyphone Stücke nach Genre; 16 Bit). Nicht genutzt: Dataset 1 (Einzelereignisse von 1–3 s, Pickup-Variation daher nicht getestet) und die akustischen Teile. Pickup-Angaben stehen nur bei Dataset 3 in den Annotationen („unknown“ sonst). Das PDF nennt die Bittiefen von Dataset 1/2 vertauscht, maßgeblich waren die tatsächlichen WAV-Header.

**Auswahl (vorab eingefroren in `tool/tonematch_reference_match/idmt_selection.json`, per `build_idmt_selection.py`, vor jeder Auswertung):** 32 Clips. Pro Dataset-2-Gitarre: muted Lick2_MN, Lick8_MN; picked Lick5_KN, Lick11_KN; finger-style Lick2_FN; lead Lick4_KBSH, Lick5_KBVDN; Einzeltöne E_fret_0-20 (24 Clips); Dataset 4 je E-Gitarre erste Datei von slow/metal, fast/rock_blues, slow/pop (6 Clips); Dataset 3 `pathetique_poly` und `quintfall` (2 Clips; erstere liegt als 2 Kanäle vor, genutzt wurde Kanal 1). Länge 6–28 s, Pegel unnormalisiert (−35 bis −15 dBFS RMS, Median −26). Keine Ausnahmen, keine Ergebnis-basierte Auswahl.

**Aufbau.** Dieselben 14 NAMs, Merkmale, Distanzen D1/D2/D3 und Metriken wie §13/13.1, keine Optimierung. 32 Clips × 14 NAMs = 448 Renderings (Zeitmessung 14 NAMs × 1 Clip = 19 s, Gesamtlauf rund 12 Minuten). **73 vorab definierte Paare** (nie derselbe Clip auf beiden Seiten): **A** gleiche Gruppe, andere Performance (30: muted, picked, lead je Gitarre, polyphone Stücke je E-Gitarre); **B** Technikwechsel bei gleicher Gitarre (19: Einzeltöne → muted/picked/lead, finger → picked, muted → picked, monophon → polyphon); **C** andere Gitarre, gleicher Lick bzw. gleicher Genre-Slot (24; der Lick wird auf einer anderen Gitarre neu gespielt, ist also inhaltlich nahe an der Referenz). 73 Paare × 14 Referenz-NAMs = **1022 Ranking-Fälle** je Distanz und Modus. Primär **BLIND**, Distanz **D2**.
**Multi-Signatur:** je NAM der Median der vier Merkmale über N ∈ {3, 5, 10} unabhängige Clips; Pool = alle Clips anderer Gitarren als die Referenz (Referenz-Clip und Referenz-Gitarre nie enthalten, im Test auf Leakage geprüft), Auswahl `pool[int((k+0.5)·len/N)]`, ebenfalls eingefroren.

**Vorab festgelegte Kriterien:** Single (D2, blind, alle Paare): Top-3 ≥ 0,70, MRR ≥ 0,60, offensichtlich falsch ≤ 10 %, keine Kategorie mit Top-3 < 0,50. Multi gegenüber Single auf denselben Referenzfällen (D2, blind, N = 10): Top-3 nicht schlechter, MRR mindestens +0,05, Median-Rang nicht schlechter, „offensichtlich falsch“ nicht höher.

**Single-Performance (D2, blind):** gesamt Top-1 0,386, Top-3 0,696, Top-5 0,836, MRR 0,573, Median 2, Mittel 3,15, offensichtlich falsch 17,4 % (140/803) → **nicht bestanden** (Top-3 knapp, MRR und „falsch“ deutlich). Je Bedingung: A (gleiche Technik) Top-3 0,707 / MRR 0,566 / falsch 17,6 %; B (Technikwechsel) 0,519 / 0,453 / 16,7 %; C (andere Gitarre, gleicher Lick) 0,821 / 0,677 / 17,8 %. Je mehr Inhalt Referenz und Kandidaten-Performance teilen (C), desto besser; bei verschiedenem Inhalt (B) bricht es ein. GuitarJam (Top-3 0,713, MRR 0,578) und IDMT (0,696, 0,573) liegen damit sehr dicht beieinander.

**Multi-Performance-Signatur (D2, blind, gleiche Referenzfälle):** N=3 / 5 / 10: Top-3 0,568 / 0,529 / 0,571, MRR 0,438 / 0,438 / 0,457, Median 3 / 3 / 3, offensichtlich falsch 24,5 / 22,0 / 23,8 %. Gegenüber Single sind alle vier Kriterien verfehlt (Top-3 −0,12, MRR −0,12, Median +1, falsch +6 Prozentpunkte). **Keine Verbesserung.** Nur bei Technikwechsel (B) hilft N = 5 (Top-3 0,647, MRR 0,508, bestanden), N = 10 nicht (MRR +0,035, falsch höher); bei C bricht die Signatur stark ein (Top-3 0,82 → 0,54). D1 und D3 verhalten sich gleich.

**Warum:** Der Median über mehrere Performances reduziert die Streuung der NAM-Beschreibung deutlich (Verhältnis within/between über alle Clips: Schwerpunkt 1,36 / Rolloff 1,69 / Mitten 2,20 / Crest 0,52; Signatur aus N=3: 0,95 / 1,23 / 1,58 / 0,28; N=5: 0,65 / 0,83 / 1,00 / 0,18; N=10: 0,45 / 0,59 / 0,66 / 0,12), aber die Referenz bleibt eine einzelne Performance mit eigenem Inhalts-Bias. Ein inhaltlich passender Einzelclip trägt diesen Bias mit und schlägt den gemittelten Durchschnitt. Das Hindernis ist die Inhaltsabhängigkeit der Referenz, nicht das Rauschen der NAM-Seite.

**Stabilität je Eingabeart (within/between, Einzelclips; Schwerpunkt / Rolloff / Mitten / Crest):** Einzeltöne 0,16 / 0,15 / 0,29 / 0,27; picked 0,23 / 0,27 / 0,54 / 0,28; finger 0,30 / 0,50 / 0,78 / 0,24; lead 0,37 / 0,33 / 0,79 / 0,31; muted 0,61 / 0,78 / 0,62 / 0,20; **polyphon 1,01 / 1,33 / 1,14 / 0,37**; gleicher Lick auf anderer Gitarre 0,23 / 0,25 / 0,39 / 0,25. Die stabilsten NAM-Signaturen liefern Einzeltöne und einheitliche Licks, die instabilsten polyphone Stücke und gemischter Inhalt; Mitten sind das schwächste, Crest das stabilste Merkmal. Der Gitarren-Einfluss (gleicher Lick) ist klein gegenüber dem Inhalt.

**Kategorien (Single, Top-3 je Kategorie):** clean 0,73, crunch 0,69, high-gain 0,67 (Multi N=10: 0,67 / 0,43 / 0,54). Top-1 gleiche Kategorie: clean 85 %, high-gain 69 % (102 von 385 landen bei Crunch), crunch 50 %. Je NAM Top-3 (Single): Fender Super Reverb und Badlander Heavy-Solo 0,88; Pano-Verb Clean2 0,58 und Gojira 0,59 am schwächsten. Nachbarschaften (Referenz entfernt) bleiben gruppenweise stabil (Clean-Gruppe; Bugera/JP2C/Badlander Heavy-Solo; JVM410/EVH/Gojira), mittlere Top-3-Übereinstimmung 0,22–0,52.

**Bewertung.** **Kriterien nicht bestanden, keine Verbesserung durch Mehrfach-Performance, Performance-Invarianz PARTIAL**; ein Handy-Mikrofon-Test ist nicht gerechtfertigt. Nicht belegt: Metall-Rhythmus-Gitarre, Pickup-Einfluss (Dataset 1 nicht genutzt). Eine mögliche, hier ungetestete Ursache ist der große Pegelunterschied der Clips (rund 20 dB), der die NAM-Sättigung ändert; ein Test mit gleichem Eingangspegel wäre ein eigener, vorab festzulegender Schritt. Keine Gewichts- oder Feature-Änderung wurde aus diesen Daten abgeleitet.

### 13.3 IDMT Final Controlled Gate (2026-10-03)

Begriffe: **A1** identische Performance (Sanity), **A2x** Hälften derselben Aufnahme, **GuitarJam A2** §13.1, **IDMT A2** und **IDMT Multi-Performance** §13.2 (Multi-Signaturen sind abgeschlossen und werden nicht weiterverfolgt), **IDMT Final Controlled Gate** dieser Abschnitt. Research only; Similarity V1, AnalysisVersion 1, Runtime-Signale, UI und Hardware unverändert. ToneTwist blieb versiegelt (nicht heruntergeladen, nicht geöffnet, nicht analysiert).

**Pre-Registration** (`tool/tonematch_reference_match/final_gate_preregistration.json`, gebaut mit `build_final_gate_prereg.py` vor jedem Rendering, vom Test vor dem Lauf per SHA-256 geprüft): **SHA-256 `445a308b7f080dcc114954814fbc5a793ec637cee41b25ebf17305e1a00c571d`**. Inhalt: IDMT-SMT-GUITAR 1.0.0 (nur die bereits eingefrorenen Clips), 14 NAMs mit Hashes, feste Content-Gruppen aus Dateinamen-Codes/Dataset-Zugehörigkeit (SINGLE_NOTE_PICKED 9 Clips, MUTED 6, LEAD 6, POLYPHONIC 7; ausgeschlossen: finger-style (3 Clips, ein Lick auf drei Gitarren) und das monophone Dataset-3-Stück (1 Clip)), alle 174 geordneten Paare verschiedener WAV-Dateien innerhalb einer Gruppe (SINGLE_NOTE_PICKED 72, MUTED 30, LEAD 30, POLYPHONIC 42) × 14 Referenz-NAMs = **2436 Ranking-Fälle** je Distanz und Modus; Etiketten SAME/CROSS_GUITAR und SAME/DIFFERENT_MATERIAL (nur beschreibend). **Pegelkontrolle:** lineare Verstärkung des trockenen 48-kHz-DI vor der NAM-Inferenz auf **−30 dBFS aktiven RMS** (exakt die Produktdefinition des Extraktors: Frames innerhalb 35 dB unter dem lautesten Eingangsframe, Mittel der Frame-Leistungen), kein Limiter, keine Kompression, keine EQ; die Output-Tonnormalisierung bleibt. Der Pegel wurde nicht anhand von Ergebnissen gewählt (Verstärkung −16 bis +1 dB, Median −6 dB; höchste Spitze danach −4,5 dBFS, kein Clipping). Merkmale, Distanzen D1–D3, Rangregeln und „offensichtlich falsch“ unverändert; **PASS/FAIL nur nach D2 blind**.
**Vorab festgelegte harte Kriterien (alle müssen gelten, kein „knapp“):** Top-3 ≥ 0,70, MRR ≥ 0,60, offensichtlich falsch ≤ 0,10, Median-Rang ≤ 2, und jede Content-Gruppe mit ≥ 100 Fällen Top-3 ≥ 0,50.

**Ergebnis D2 blind (alle Paare):** Top-1 0,391, Top-3 **0,682**, Top-5 0,823, MRR **0,571**, Median-Rang 2, Mittel-Rang 3,23, offensichtlich falsch **13,5 %** (258/1914). Rangverteilung: Rang 1 39 %, 2–3 29 %, 4–5 14 %, 6–10 13 %, 11–14 4 %. **Final Gate: FAIL** (Top-3, MRR und „falsch“ verfehlt; Median-Rang und Content-Gruppen-Regel erfüllt).
**Delta gegenüber IDMT-Einzel-Baseline** (0,386 / 0,696 / 0,573 / 2 / 17,4 %): Top-1 +0,005, Top-3 −0,014, MRR −0,002, Median 0, „falsch“ −3,9 Prozentpunkte. **Pegelkontrolle plus Content-Gruppen bringen praktisch keinen Gewinn** bei Top-1/Top-3/MRR; nur „offensichtlich falsch“ verbessert sich.
**Je Content-Gruppe (D2 blind; Fälle / Top-1 / Top-3 / MRR / Median / falsch):** LEAD 420 / 0,471 / 0,788 / 0,648 / 2 / 17,0 %; MUTED 420 / 0,405 / 0,738 / 0,600 / 2 / 11,5 %; SINGLE_NOTE_PICKED 1008 / 0,412 / 0,670 / 0,576 / 2 / 12,9 %; POLYPHONIC 588 / 0,287 / 0,587 / 0,487 / 3 / 13,4 %. **Gitarre:** SAME_GUITAR 672 Fälle Top-3 0,634, MRR 0,530; CROSS_GUITAR 1764 Fälle Top-3 0,700, MRR 0,586 (Content-Matching hängt also nicht an derselben Gitarre; Hinweis: alle SAME_MATERIAL-Paare sind Cross-Guitar-Neuaufnahmen desselben Licks). **Material:** SAME_MATERIAL 672 Fälle Top-3 0,841, MRR 0,701, Median 1, falsch 9,8 %; DIFFERENT_MATERIAL 1764 Fälle Top-3 0,621, MRR 0,521, Median 3, falsch 14,9 %. Das Verfahren funktioniert, wenn Referenz und Kandidaten-Performance dasselbe Material spielen, aber nicht über verschiedenes Material derselben Spielart.
**Kontrollen (nicht entscheidend):** D1 Top-3 0,631 / MRR 0,538, D3 0,596 / 0,497; mit DI-Gate D2 Top-3 0,732 / MRR 0,627 / falsch 11,6 % (auch das erfüllt nicht alle Kriterien).
**Je NAM (D2 blind, Top-1 / Top-3 / MRR / Median):** Badlander Heavy-Solo 07 0,54 / 0,80 / 0,69 / 1; Fender SR 0,52 / 0,76 / 0,66 / 1; JP2C Power-Amp-Only 10 0,28 / 0,72 / 0,53 / 2; JP2C Lead 09 0,40 / 0,71 / 0,59 / 2; JVM410 Crunch 03 0,33 / 0,70 / 0,53 / 2,5; Mark V Rhythm 0,45 / 0,69 / 0,60 / 2; EVH 5150 06 0,36 / 0,69 / 0,56 / 2; Gojira 08 0,39 / 0,68 / 0,57 / 2; Badlander Clean-Pushed 02 0,43 / 0,65 / 0,57 / 2; Bugera 6262 05 0,31 / 0,64 / 0,52 / 3; JVM410 Full Rig 04 0,37 / 0,64 / 0,56 / 2; Mark V Lead 0,32 / 0,63 / 0,53 / 2; Pano-Verb Clean2 01 0,51 / 0,61 / 0,61 / 1; Mark V Clean 0,26 / 0,61 / 0,47 / 3.
**Kategorien:** Top-3 clean 0,66, crunch 0,67, high-gain 0,69; Top-1 gleiche Kategorie clean 82 %, high-gain 81 %, crunch 54 %; „offensichtlich falsch“ clean 32 %, high-gain 9 %.
**Pegelempfindlichkeit** (±3 dB am DI, 3 NAMs × 4 Clips, nur dokumentiert; mittlere |Änderung| −33 bzw. −27 gegenüber −30 dBFS): ln Schwerpunkt 0,032 / 0,030, ln Rolloff 0,029 / 0,030, Mitten-Logit 0,050 / 0,052, Crest 0,41 / 0,48 dB (Maximum 0,11 / 0,11 / 0,29 / 1,45). Das ist klein gegenüber der Streuung zwischen NAMs (Größenordnung 0,4–0,6 bzw. rund 3 dB); der Eingangspegel war also nicht der Hauptgrund für die Streuung.

**Entscheidung (vorab festgelegt):** Final Gate **FAIL**. Der Exact-NAM-Hör-Match-Zweig wird **eingefroren**, ToneTwist bleibt **versiegelt** (nicht verbraucht), ein Handy-Mikrofon-Test wird nicht durchgeführt. Es gibt keine weitere Pegel-, Feature-, Gewichts- oder Paar-Optimierung. Gesagt werden kann nur: Controlled digital reference matching passed **nicht** the pre-registered gate. Mögliche spätere, kleinere Research-Idee (nicht bewertet, nicht implementiert): Audio → grobe Klangrichtung/Kategorie (Clean / Crunch / High-Gain, hell / ausgewogen / dunkel, dynamisch / komprimiert) → ToneIntent ergänzen → bestehende lokale NAM-Vorauswahl.
