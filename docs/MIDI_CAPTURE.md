# Passiver MIDI-Empfang in WyrmTone

## Bestätigt und weiterhin unbekannt

Marcel bestätigte auf seinem Samsung am 12. September 2026: Matribox 1 / QME-50, VID/PID 0x84EF:0x0054, SONICAKE AUDIO / SONICAKE MatriBox PRODUCT, eindeutige Android-MIDI-Zuordnung, einen Input-/Output-Port, Öffnen/Schließen und sicheres Detach ohne Absturz. Anschließend wurden jeweils 0 USB-/MIDI-Geräte angezeigt. Keine Nutzdaten wurden gesendet. Der neue passive Empfang braucht noch einen separaten Hardwaretest. Das Matribox-Protokoll und spontane Nachrichtenausgabe bleiben unbekannt.

## Architektur und Richtung

Android-Portnamen gelten aus Sicht des Geräts. Geräte-Output liefert Matribox → App, Geräte-Input würde App → Matribox senden. Produktionscode verwendet nur `openOutputPort` und verbindet einen `MidiReceiver` mit `onSend` als Empfangs-Callback. Kein produktiver Aufruf von `send`, `flush`, `openInputPort`, keine USB-Transfers und kein Force-Claim.

`MidiReceiveSource` kennt nur Empfangsstream, Unterbrechungen und Start/Stop. `MidiCaptureController` kennt keine USB-/Sendeschnittstelle. Kotlin kapselt einen `ReceiveOnlyMidiPort` und weist alte Callback-Generationen nach Stop ab. Native Batches gehen über einen eigenen EventChannel an Flutter. Der Parser klassifiziert lokal Struktur, niemals proprietäre Bedeutung.

Zustände: disconnected, deviceDetected, deviceOpened, monitoring, stopping, error. Start ist nur bei eindeutig zugeordnetem und geöffnetem Matribox-Gerät möglich; genau ein Geräte-Output-Port muss vorhanden sein. Kein Auto-Start/Resume. Stop trennt Receiver und schließt Output; Geräteschließen, Pause und Detach schließen danach das MidiDevice. Auch der native Activity-onPause-Pfad greift unabhängig von Flutter.

## Grenzen und SysEx

- Native Callback-Limit: 4096 Byte. Größere Callbacks werden verworfen, nicht in unbeschränkte Arrays kopiert.
- Native Pending-Batch: höchstens 256 Chunks und 256 KiB; Lieferung alle 50 ms. Überlauf verwirft den Pending-Präfix mit sichtbarer Lückenmeldung, damit keine SysEx über eine Lücke zusammengefügt wird.
- Dart-Ring: höchstens 300 Einträge / 256 KiB Payload, einschließlich Chunks und zusammengesetzter Nachrichten. Alte Einträge werden gezählt und verworfen. Objekt-/Text-Overhead ist zusätzlich durch Eintragszahl und Markerlimit begrenzt.
- SysEx: maximal 64 KiB, Timeout nach 2 Sekunden ohne neues Fragment (monotone Zeit). F0 startet, F7 beendet. Real-Time F8–FF wird separat verarbeitet und nicht in SysEx eingefügt. Neue Statusbytes, Timeout, Überlauf, Stop oder Empfangslücke schließen eine Assemblierung als unvollständig/verworfen ab. Running Status und fragmentierte normale MIDI-Nachrichten werden lokal verarbeitet.
- UI: höchstens 100-ms-Updates, 25 letzte Einträge je Bereich und 256-Byte-Hexvorschau. Export enthält den gesamten verbliebenen Ring, nicht nur die Vorschau. Keine dauerhafte Ablage ohne Export.
- Nummern sind monoton, auch nach „Anzeige leeren“. Markierungen sind maximal 120 Unicode-Codepoints; Steuer-/Bidi-Zeichen und Zeilenumbrüche werden bereinigt. Offensichtliche Schlüssel-/Pfadtexte werden abgewiesen. Markierungen verändern nur lokale Daten.

## Export und Datenschutz

Für gemeinsame Messungen kann während aktiver Beobachtung in einer Debug-APK „Live-Debug-Log über ADB“ eingeschaltet werden (standardmäßig aus, nicht gespeichert). Android-Logcat zeigt dann `WYRMTONE_RX`-Zeilen mit lokal klassifizierten Empfangsnachrichten und bereinigten Markierungen. Maximal 20 Zeilen/s und 256 Payload-Byte je Nachricht; Unterdrückungen werden in der App gezählt. Stop, Pause und Detach deaktivieren die Ausgabe. Der JSON-Export bleibt unabhängig davon. Debugging-Werkzeuge können diese Rohdaten lesen; unbekannte SysEx vor dem Teilen auf sensible Inhalte prüfen. Keine Netzwerkweitergabe und keine Geräteausgabe. Zum Lesen: `adb logcat -s flutter:I` und nach `WYRMTONE_RX` filtern.

Export wird ausdrücklich ausgelöst, stoppt den Monitor und öffnet Android ACTION_CREATE_DOCUMENT für JSON. Die Dateiauswahl kann das MidiDevice wegen App-Pause schließen. Abbruch speichert nichts; nur die ausgewählte Dokument-URI wird beschrieben. Kein allgemeiner Speicherzugriff, keine automatische Netzwerkweitergabe. Größenlimit des Exportkanals: 3 Mi Zeichen.

Schema 1 enthält App, beobachtete Matribox-Identität, Startzeit, Zähler, Lücken und Einträge (chunk/message/marker/loss), lokale Zeit und ursprünglichen Android-Timestamp. `session.receiveOnly` ist immer true. Keine USB-/privaten Pfade, Seriennummern, Kontotokens, Clientkeys oder zusätzlichen Handydaten. Unbekannte Rohpayloads könnten selbst gerätespezifische Informationen enthalten; vor dem Teilen prüfen. Dies ist keine semantische Anonymisierung unbekannter SysEx.

## Konkreter Samsung-Test

1. Neue Debug-APK über Android Studio Run installieren. PC-Kabel entfernen, Matribox über OTG verbinden.
2. Prüfen: Matribox korrekt zugeordnet, 1 Input / 1 Output. Falls erforderlich USB-Berechtigung erteilen.
3. MIDI-Gerät öffnen. Noch keine Beobachtung: Zähler bleiben unverändert.
4. Passive MIDI-Beobachtung starten; sichtbarer Hinweis „Nur Empfang“ und Output-Port 0.
5. Erst 10 Sekunden ohne Bedienung beobachten. Dann Markierung setzen, genau eine Änderung direkt am Pedal ausführen, 2–3 Sekunden warten. Beispiele Gain 40 → 41, dann 41 → 42, Amp-Block auswählen, Footswitch A, Preset 01 → 02. Lautstärke dabei sicher halten; die App selbst ändert nichts.
6. Stoppen, Pedal bedienen: Zähler dürfen nicht weiter steigen. Neu starten, mehrfacher Start darf keinen zweiten Receiver erzeugen.
7. Während Beobachtung Home/App-Wechsel: Port/Gerät schließen, Resume startet nichts. Danach ausdrücklich Gerät öffnen und neu starten.
8. Während Beobachtung OTG abziehen: kein Absturz, keine weiteren RX, Output-Port geschlossen, 0 USB-/MIDI-Geräte. Wiederanschließen startet nichts automatisch.
9. Vor Ringüberlauf exportieren. Für jedes isolierte Experiment eine Datei speichern und umbenennen: `matribox_idle.json`, `matribox_gain_40_41_42.json`, `matribox_foot-switch_a.json`, `matribox_preset_01_02.json`. Bei leerem Empfang kurze Beschreibung/Screenshot mit Zählern bereitstellen; keine aktive Anfrage hinzufügen.

Bitte diese JSON-Dateien und eine kurze Liste der manuellen Aktionen bereitstellen. Keine WAV/NAM/ZIP, keine Kontodaten oder Seriennummern. Vorläufig keinerlei Protokollbedeutung aus Einzelbytes ableiten.

## Verifikation

Flutter-/Kotlin-Tests verwenden ausschließlich Empfangs-/Port-Fakes. Der Sicherheitstest prüft den gesamten produktiven Kotlin-Baum auf Input-Port-, Send-/Flush-, USB-Transfer- und Force-Claim-Verwendungen. Ein empfangender onSend-Override wird erlaubt; ein `.send(...)`-Aufruf nicht. DNAfx-Raw-USB bleibt separat, Matribox-Raw-USB ist eingeklappt und während MIDI-Open gesperrt.

Abschlussprüfung am 12.09.2026: Formatierung durchgeführt, `flutter analyze` ohne Probleme, alle 120 Flutter-/Dart-Tests und alle 18 App-Kotlin-Tests erfolgreich. Debug-APK erfolgreich gebaut; Archivprüfung: 0 WAV-, NAM- oder ZIP-Dateien. Anzeigename WyrmTone, Paket-ID de.neevel.wyrmtone. APK: `D:\Develop\dnafx_bridge\build\app\outputs\flutter-apk\app-debug.apk`, 200312613 Byte / 191,03 MiB. Kein Commit, kein Push, keine Installation und kein neuer Hardware-Empfangstest durch diesen Task.

## Neue und geänderte Dateien dieses Tasks

Neue Dateien:

- `lib/midi/midi_receive_source.dart`
- `lib/midi/midi_parser.dart`
- `lib/midi/midi_capture_controller.dart`
- `lib/screens/midi_capture_panel.dart`
- `android/app/src/main/kotlin/de/neevel/wyrmtone/PassiveMidiMonitor.kt`
- `android/app/src/main/kotlin/de/neevel/wyrmtone/MidiCaptureExportChannel.kt`
- `android/app/src/test/kotlin/de/neevel/wyrmtone/PassiveMidiMonitorTest.kt`
- `test/midi_capture_test.dart`
- `test/midi_capture_panel_test.dart`
- `test/support/fake_midi_receive_source.dart`
- `docs/MIDI_CAPTURE.md`

Geänderte Dateien:

- `lib/app.dart`
- `lib/controllers/usb_controller.dart`
- `lib/services/usb_service.dart`
- `lib/services/usb_platform_service.dart`
- `lib/screens/home_page.dart`
- `android/app/src/main/kotlin/de/neevel/wyrmtone/MidiDiagnosticsManager.kt`
- `android/app/src/main/kotlin/de/neevel/wyrmtone/UsbPlatformChannels.kt`
- `android/app/src/main/kotlin/de/neevel/wyrmtone/MainActivity.kt`
- `test/home_page_test.dart`
- `test/usb_controller_test.dart`
- `test/usb_no_write_test.dart`
- `test/support/fake_usb_service.dart`
- `README.md`
- `docs/MATRIBOX_ONE.md`
- `docs/PROTOCOL_NOTES.md`
