# Direct Preset Transfer V1 – erstellter Sound → Matribox-Preset

Ein Sound, der in WyrmTone gefunden, beschrieben, erzeugt oder angepasst wurde, läuft durch **einen**
generischen Pfad. Es gibt keinen song-spezifischen Sender; Angels und FAMILY_EXPANSION sind nur
Zertifizierungsfälle, die den Evidence-Ledger füllen.

## Pfad

```
Sound (ToneVault / NLU / Guitar Reimagined / Wyrm Original / Stil-Vorlage)
  + Nutzerwünsche (USER_OVERRIDE), Gitarren- und Stimmungskorrekturen
        -> lokaler Sound (OfflineSoundEngine, PresetDraft)      <- Quelle der Wahrheit
        -> CanonicalToneRecipe (9 Blöcke, defined / off / unchanged / incomplete)
        -> MatriboxToneTranslator  (einzige Geräte-Brücke; Heuristiken standardmäßig aus)
        -> MatriboxTargetPreset
        -> MatriboxTranslationAnalyzer   (Vorschau/Verdikt, nichts gesendet)
        -> [Nutzer bestätigt] frisches Lesen des gewählten Slots (P11–P99) -> verifiziertes Backup -> Diff
        -> MatriboxToneTransferPlan (Evidence-Gate über den GANZEN Plan)
        -> Bestätigung -> Live-Write (ein nativer Pfad, typed ops, kein Retry, Stop beim ersten Fehler)
        -> Nutzer speichert MANUELL am Gerät ("Ich habe am Gerät gespeichert" sendet null MIDI)
        -> frischer Readback des gespeicherten Stands -> Vergleich
```

Der erstellte (ggf. angepasste) Sound wird **nicht** erneut aus dem Katalog geladen:
`SoundSession.prepareForMatribox` baut aus dem aktuellen lokalen Sound das Ziel.

## Schichten (strikt getrennt)

| Schicht | Frage | Code |
|---|---|---|
| Sound-Wissen | Wie soll der Sound klingen? | ToneVault, Sound Engine, Recipe |
| Geräte-Übersetzung | Welches Matribox-Modell/welcher Wert entspricht dem? | `MatriboxToneTranslator`, Regeln + `ApproximationQuality` |
| Protokoll-Evidenz | Was ist adressierbar (A) / produktiv sendbar (B) / semantisch belegt (C)? | Evidence V2, Ledger, Hersteller-ID − 1 |
| Transport | Wie kommen typisierte Operationen zum Gerät? | Kotlin-Port, nur typed ops, ZERO-SEND bei ungültiger Op |
| Verifikation | Ist der gespeicherte Zustand das Ziel? | Readback: `MANUAL_SAVE_PERSISTENCE_VERIFIED`, `TARGET_MISMATCH`, `UNEXPECTED_KNOWN_CHANGE`, `UNKNOWN_RAW_CHANGE`, `READ_FAILED` |

A/B/C werden nie vermischt: ein Parameter kann adressierbar, aber nicht produktiv freigegeben oder ohne
belegte semantische Regel sein. Wire-Index = Hersteller-ID − 1, es gibt keinen `idx`-Fallback.

## Übersetzungsergebnis (`matribox_translation_result.dart`)

`MatriboxTranslationResult`: `mappedIntents`, `approximatedIntents`, `unsupportedIntents`,
`blockedOperations`, `unchangedIntents`, `warnings`, `overallCompatibility`.

* **FULL** – alle festgelegten Bestandteile übersetzt und freigegeben.
* **PARTIAL** – sinnvoll übertragbar; Angenähertes/Weggelassenes wird aufgelistet (nie stilles Weglassen).
* **BLOCKED** – Amp ohne Modell, kein Block festgelegt oder eine nötige Operation nicht freigegeben.

Es gibt keine erfundenen Prozentwerte. Fehlende ToneVault-Werte sind *nicht* AUS („ohne Reverb“ = explizit AUS,
„mit Chorus“ = gewünschte Modulation). Der Analyzer ist beratend; entscheidend bleibt der Plan mit frischem Read.

## Mapping-Politik

DIRECT / GOOD_APPROXIMATION / LIMITED_APPROXIMATION / UNSUPPORTED. Was keine belegte Abbildungsregel hat
(z. B. Gate-Stärke, Öffnungscharakter, Lautsprecher-/Mikrofonwunsch, Menge bei MOD/DLY/RVB), wird als
„nicht übertragen“ ausgewiesen statt geraten.

## Zielplätze

Zentrale Regel (`MatriboxSlotPolicy` in `matribox_transfer_slots.dart`, nativ unabhängig in
`MatriboxSlotPolicy.kt`):

* **P01–P10 = geschützte Spiel-Presets.** Der produktive Transfer liest, plant und schreibt sie nie
  (Dart-Session, Plan, Contract, MethodChannel-Client und Kotlin-Validator lehnen ab, null Sends).
* **P11–P99 = produktiv beschreibbar**: P11 `HARDWARE_CERTIFIED` (2026-09-23), P12–P99
  `SOFTWARE_VALIDATED` (keine Übertragung der P11-Evidenz auf andere Slots). Factory-Bank nie.
* Kein Default-Slot: fehlend/ungültig wird abgelehnt, es gibt keinen Rückfall auf P01 oder P11.
* Adressierung `Geräteindex = Presetnummer − 1` (P11 → 0x0A, P99 → 0x62): Read (Bank/Slot-Byte an Offset
  13/14 der bestätigten Requests) und Preset-Select (22-Byte-Editor-Nachricht, Index an Offset 18).
* Der gewählte Slot ist an den ganzen Ablauf gebunden: frischer Read + Backup genau dieses Slots → Diff →
  Plan → nativer Preflight → Preset-Select → Live Write → manuelles Speichern → Readback desselben Slots →
  Verify. Transfer-Status liegt je Slot in `tone_transfer_Pxx.state`; jede Slot-Abweichung verhindert
  Senden bzw. VERIFIED.

Ein Platz wird nie automatisch überschrieben: aktuelle Werte werden frisch gelesen, gesichert und
ausdrücklich bestätigt. Vor dem manuellen Speichern prüfen, dass am Gerät der gewählte Platz angezeigt wird.

## UI

„Dein Sound“ → **Für Gerät vorbereiten** (keine Kommunikation) → `DevicePreparePage`: Verdikt, Blockvorschau
(✓ übersetzt, ~ angenähert, ! nicht übersetzbar, · unverändert), „Nicht übertragen“-Liste, Zielplatz,
„Bis hierhin wurde nichts gesendet“, „Technische Details“. Erst „Mit der Matribox fortfahren“ führt in den
bestätigten Transferfluss (`ToneTransferPage`, deutsche Texte, technische Kürzel nur als Detailzeile).

## Bekannte Grenzen

* Kein Store/Auto-Save; Speichern immer manuell am Gerät.
* Kein generischer User-IR-Transfer, Part8 nur wie bisher korreliert toleriert.
* Sync/Bind-Parameter, Notenwerte, Enum-Parameter außerhalb der Freigabe bleiben gesperrt.
* Gate-Stärke/-Öffnung, Speaker/Mic-Zuordnung, Menge bei MOD/DLY/RVB: keine belegte Regel.
* Nicht jeder ToneVault-Sound funktioniert vollständig auf der Matribox; die Vorschau zeigt, was fehlt.
* Kataloge (aus dem Code abgeleitet, `test/sound_to_transfer_workflow_test.dart` Gruppe 9): Hersteller-XML 181 Einträge /
  631 Parameter -> Transferkatalog 142 Modelle / 525 Parameter. Grund: FX1 und FX2 teilen dieselben 25 Algorithmus-Codes
  (25 Einträge / 92 Parameter sind Doppelungen, kein Verlust) und 14 unbenannte CAB-Einträge (je 1 Parameter) werden nicht
  als Modell angeboten. Ansicht je Block (FX1/FX2 doppelt gezählt): 617 Parameter, davon A adressierbar 615 (nur der
  FX1/FX2-Konflikt "Tape Mod Output/VOL" fehlt), B produktiv sendbar 548 (Sync/Bind, Enum, User IR, Vendor-only bleiben
  gesperrt), 166 von 167 Modell-Slots wählbar (User IR gesperrt). C (semantisch belegte Regel) ist eine eigene, kleinere Menge.

## Build für Hardware-Tests

Es gibt nur noch zwei Gates (`android/app/build.gradle.kts`, beide nur Debug, Release immer `false`):
`ENABLE_MATRIBOX_P01_RAW_BACKUP` (lesender Reader/Backup) und `ENABLE_MATRIBOX_TONE_TRANSFER` (produktiver
Transfer P11–P99, schaltet den Reader mit ein). Die früheren Probe-/Certification-Gates und -Werkzeuge sind
entfernt; ein alter Define schaltet nichts frei. Hardware-Stand: P11 zertifiziert (2026-09-23), P12–P99
software-validiert (siehe `MULTI_SLOT_CERTIFICATION_PLAN.md`).

```
flutter build apk --debug --dart-define=ENABLE_MATRIBOX_TONE_TRANSFER=true
```
