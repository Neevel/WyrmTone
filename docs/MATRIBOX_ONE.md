# Sonicake Matribox 1 / QME-50

## Belegter Stand

Die offizielle Sonicake-Produktseite nennt die Matribox 1 als QME-50, 15 User-IR-Slots und Firmware V1.1.0 als Voraussetzung für NAM-Captures. Das lokale Geräteprofil modelliert deshalb Custom IR mit 15 Slots sowie NAM A1 als zunächst bestätigtes Ziel. Preset-, IR- und NAM-Transfer aus WyrmTone sind `notImplemented`; USB-Verbindung und Protokoll sind `unverified`.

Die auf der Produktseite genannte Desktopsoftware-Unterstützung für NAM A2 beweist keine native A2- oder A2-Lite-Ausführung auf der Hardware. Beide bleiben sichtbar unbestätigt. Die App verwendet keine geratenen VID/PID-, Interface-, Endpoint- oder Payloadwerte.

## Beobachteter USB-Befund vom 11. September 2026

Auf Marcels Samsung-Handy wurde die angeschlossene Matribox als `0x84EF:0x0054` (dezimal 34031:84) mit einer Konfiguration, acht Interface-/Alternate-Setting-Einträgen und sechs Endpunkten beobachtet. Die Interfaces 0–2 bilden eine USB-Audio-Struktur mit isochronen Endpunkten.

Interface 3/Alt 0 meldete Klasse 1, Subklasse 3, Protokoll 0, Bulk-IN `0x83` mit maximal 64 Byte und Bulk-OUT `0x03` mit maximal 256 Byte. Klasse 1/Subklasse 3 begründet die Hypothese USB-MIDI-Streaming, beweist aber weder das Matribox-Editorprotokoll noch die Bedeutung möglicher Nachrichten. VID/PID gelten als **beobachteter Matribox-1-Kandidat**, nicht als Garantie für jede Hardware- oder Firmwarevariante.

Der Samsung-Test vom 12. September 2026 bestätigte `SONICAKE AUDIO`, `SONICAKE MatriBox PRODUCT`, MIDI-Zuordnung, einen Input-/Output-Port und wiederholtes Öffnen/Schließen. Abziehen bei geöffnetem MIDI-Gerät schloss sicher, ohne Absturz; danach jeweils 0 USB-/MIDI-Geräte. Dabei wurden keine Nutzdaten gesendet. Der nicht erzwungene Interface-3-Claim scheiterte erwartbar; Android verwaltet die MIDI-Schnittstelle.

## Bevorzugter Android-MIDI-Weg

Geräte-Output bedeutet **Matribox → App**, Geräte-Input **App → Matribox**. Nur `openOutputPort` wird für den ausdrücklich gestarteten passiven Monitor verwendet. Ein empfangender Receiver verarbeitet `onSend`-Callbacks; WyrmTone ruft niemals `send`/`flush` oder `openInputPort` auf. Es gibt keine Anfrage, Initialisierung oder Antwort. Alle Protokollbedeutungen bleiben unbekannt.

Stop löst den Receiver und schließt den Output-Port. App-Pause, MIDI-Removal, USB-Detach und Geräteschließen beenden zuerst den Monitor und schließen anschließend das Gerät. Wiederanschließen oder Resume starten nichts automatisch. Limits, SysEx und Export: [MIDI_CAPTURE.md](MIDI_CAPTURE.md).

## Read-only Claim-Strategie

Nach ausdrücklicher Nutzeraktion prüft WyrmTone VID/PID, Interface 3/Alt 0, Klasse, Subklasse, Protokoll, Endpunktrichtung, Bulk-Typ und Paketgrößen. Die Audiointerfaces 0–2 werden niemals als Ersatz gewählt.

Der native Aufruf verwendet `claimInterface(interface3, false)` und verdrängt damit keinen bestehenden Android-MIDI-Treiber. Ein Fehlschlag wird einmal diagnostiziert; es gibt keine aggressive Wiederholung. Auch nach erfolgreichem Claim erfolgen weder Lesen noch Schreiben und keinerlei MIDI-, SysEx-, Bulk-, Control-, Interrupt- oder Isochronous-Transfer. Schließen und Detach geben Interface und Verbindung frei.

## Aktueller Ablauf

1. Matribox in **Empfehlung** als Zielgerät wählen.
2. In **NAM-Bibliothek** gezielt NAM A1 bei TONE3000 auswählen oder eine einzelne lokale Datei importieren.
3. Ein Modell ausdrücklich herunterladen.
4. Architektur, Kompatibilität, Attribution, lokalen Status und Cabinet-Warnung prüfen.
5. Capture nur als Vormerkung für eine spätere Übertragungsphase verwenden.

Eine Übertragungsschaltfläche existiert absichtlich nicht.

## Weiterhin benötigt

- exakte Modell-/Hardware-Revision und installierte Firmware;
- passive RX-Exporte mit isolierten manuellen Markierungen (auch leere Captures sind aussagekräftig);
- offizielle oder kontrolliert beobachtete Dateiformate und Transferabläufe der Sonicake-Software;
- belastbare Bestätigung, welche A1-/A2-/A2-Lite-Varianten das Pedal selbst akzeptiert;
- Slotgrenzen, Dateigrößen und Cabinet-/Full-Rig-Semantik;
- vor jedem späteren Schreibtest ein vollständiges Backup und ein explizit freigegebener Testslot.

Schreibtransfers sind in diesem Entwicklungsstand ausdrücklich verboten und werden erst nach separater Protokollprüfung und ausdrücklicher Bestätigung erwogen.

Quelle, geprüft am 10. September 2026: [Sonicake Matribox Produktseite](https://www.sonicake.com/products/matribox).
