# WyrmTone

Technischer Flutter-Prototyp für eine sichere Android-USB-OTG-Diagnose mit Harley Benton DNAfx GiT Core und Sonicake Matribox 1 / QME-50 sowie lokale IR-/NAM-Verwaltung.

> **Sicherheitsgrenze:** Normale Builds senden keine MIDI- oder USB-Nutzdaten. Preset-, IR-, NAM- und Firmwaretransfers sowie Handshakes bleiben gesperrt. DNAfx bleibt eine Raw-USB-Deskriptordiagnose; der Matribox-Monitor bleibt ausschließlich passiv. Eine gesondert freigegebene Entwickler-Ausnahme ist in [MIDI_CAPTURE.md](docs/MIDI_CAPTURE.md#separat-freigegebener-entwickler-einmaltest) abgegrenzt.

## Passive Matribox-MIDI-Diagnose

Der manuelle Samsung-Test vom 12. September 2026 bestätigte MIDI-Erkennung, einen Input-/Output-Port, wiederholtes Öffnen/Schließen und sicheres USB-Detach bei geöffnetem `MidiDevice` ohne Absturz; danach jeweils 0 USB-/MIDI-Geräte. Dies bestätigt noch kein Matribox-Editorprotokoll und keine spontane Nachrichtenausgabe.

Auf **Verbindung** zuerst **MIDI-Gerät öffnen**, dann ausdrücklich **Passive MIDI-Beobachtung starten**. Am Pedal Änderungen ausführen, vorher lokale Testmarkierungen setzen. Chunks und lokal klassifizierte Nachrichten/SysEx stehen getrennt im Live-Protokoll. Stop, App-Pause, Schließen und Detach lösen Receiver und Port; Pause/Detach schließen außerdem das Gerät. Es gibt kein automatisches Wiederanlaufen.

Der Ringpuffer hält höchstens 300 Einträge und 256 KiB Payload; SysEx ist auf 64 KiB und 2 Sekunden Inaktivität begrenzt. Native Lieferung erfolgt in 50-ms-Batches mit höchstens 256 Chunks/256 KiB; Callbacks über 4 KiB werden sichtbar als Empfangslücke verworfen. UI-Aktualisierung höchstens alle 100 ms; begrenzte Hexvorschau. JSON wird nur nach **Diagnose exportieren** über Android SAF gespeichert (`receiveOnly=true`, keine Seriennummern, USB-/privaten Pfade oder Kontoschlüssel). Die Rohbytes selbst sind unbekannte Geräteinhalte und sollten vor dem Teilen geprüft werden.

Matribox-Raw-USB liegt eingeklappt unter **Erweiterte Diagnose**, ist während geöffneter MIDI-Verbindung gesperrt und wiederholt einen erwartbaren Claim-Fehlschlag nicht. DNAfx-Diagnose bleibt vorhanden. Technische Details und konkrete Samsung-Testschritte: [MIDI_CAPTURE.md](docs/MIDI_CAPTURE.md).

Das Projekt ist nicht mit Harley Benton oder Thomann verbunden.

## Funktionsumfang

- listet alle Geräte aus `UsbManager.deviceList` auf;
- zeigt Device Name, VID/PID dezimal und hexadezimal, Geräteklasse/-subklasse/-protokoll sowie Konfigurationen, Interfaces und Endpunkte;
- liest Hersteller- und Produktdeskriptoren defensiv nur bei erteilter Berechtigung; die Seriennummer wird weder angezeigt noch protokolliert;
- markiert `0x0483:0x5703` als mögliches DNAfx GiT;
- markiert `0x84EF:0x0054` als am 11. September 2026 beobachteten Matribox-1-Kandidaten;
- fordert USB-Zugriff mit `PendingIntent` und lifecycle-sicher registriertem `BroadcastReceiver` an;
- meldet Permission-, Attach- und Detach-Ereignisse über einen Flutter `EventChannel`;
- öffnet nur den DNAfx-Kandidaten und beansprucht nur Interface 0, wenn die am echten Gerät bestätigten Interrupt-Endpunkte `0x81` (IN) und `0x02` (OUT) vorhanden sind;
- versucht beim Matribox-Kandidaten ausschließlich Interface 3/Alt 0, Klasse 1/Subklasse 3 mit Bulk-IN `0x83` und Bulk-OUT `0x03` nicht erzwungen zu beanspruchen;
- gibt Interface und Verbindung kontrolliert frei;
- hält ein lokales, flüchtiges Diagnoseprotokoll, das keine Seriennummer und keine Binärdaten enthält.

Die USB-Diagnose verwendet typisierte Dart-Modelle. Android-Zugriffe liegen in getrennten Kotlin-Klassen; Raw-USB-Open-/Close- und Deskriptorarbeiten laufen auf einem einzelnen Hintergrund-Executor.

Zusätzlich enthält die App jetzt einen deterministischen Empfehlungskern:

- lokal persistierte Gitarrenprofile mit Pickup, Ausgangspegel, Klang, Stimmung und Wiedergabeweg;
- drei mitgelieferte Ziel-Sounds für CKY, Children of Bodom und Nirvana;
- kleiner Metadatenkatalog für 210 bekannte IR-Dateinamen ohne eingebettete WAV-Audiodaten;
- persistente, ausschließlich lesende Android-SAF-Ordnerauswahl ohne allgemeine Speicherberechtigung;
- Abgleich nach normalisierten Dateinamen mit den Zuständen vorhanden, nicht gefunden, unbekannt und Duplikat;
- regelbasierte Erkennung von Cabinet, Speaker, Mikrofon, Position und technischen Klangtendenzen aus Dateinamen;
- durchsuchbarer, deduplizierter und lokal persistierter IR-Katalog;
- pickup-, stimmungs- und ausgabeabhängige DNAfx-Startwerte mit Begründungen;
- bis zu drei gewichtete IR-Empfehlungen samt Prozentwert und Unsicherheitskennzeichnung;
- Feedbackvorschau für spätere regelbasierte Korrekturen.

Optional kann die App über die offizielle TONE3000 API einen einzelnen IR-Tone im Systembrowser auswählen, dessen Modelle anzeigen und ein ausdrücklich gewähltes Modell in den privaten App-Speicher laden. OAuth2 verwendet PKCE und verschlüsselte Tokenablage. Es gibt weder Scraping noch Massen- oder ZIP-Downloads. Einrichtung, Sicherheitsgrenzen und Tests stehen in [`docs/TONE3000_INTEGRATION.md`](docs/TONE3000_INTEGRATION.md).

Die gleiche sichere TONE3000-Sitzung kann nun gezielt NAM-Captures für die **Sonicake Matribox 1 / QME-50** auswählen. Die App fordert `format=nam` und `architecture=1` an, bietet jedes Modell nur als einzelnen ausdrücklichen Download an und verwaltet es getrennt vom IR-Katalog. Ein einzelner lokaler `.nam`-Import über Android SAF ist ebenfalls möglich. NAM A1 gilt als Matribox-Zielformat; A2, A2-Lite und unbekannte Architektur werden nicht ungeprüft als kompatibel markiert. Es gibt noch **keinen NAM-, IR- oder Presettransfer zur Matribox**. Details: [`docs/NAM_SUPPORT.md`](docs/NAM_SUPPORT.md) und [`docs/MATRIBOX_ONE.md`](docs/MATRIBOX_ONE.md).

Empfehlungen sind nachvollziehbare Ausgangspunkte und keine exakten Rekonstruktionen einer Studioaufnahme. Es werden weiterhin **keine Presets oder IR-Dateien auf das DNAfx geschrieben**.

## Umbenennung und Android-Daten

WyrmTone verwendet die Android-ID `de.neevel.wyrmtone` und den OAuth-Callback `wyrmtone://oauth/callback`. Android behandelt WyrmTone als neue App; die frühere Entwickler-App wird nicht automatisch aktualisiert. Deren verschlüsselte OAuth-Tokens und lokale Testdaten werden bewusst nicht migriert. Vor dem Test kann die alte App manuell deinstalliert werden. In den TONE3000-Entwicklereinstellungen muss exakt die neue Redirect-URI registriert sein.

## Gitarrenprofil und IR-Sammlung verwenden

1. Unter **Gitarren** ein Profil anlegen und als Wiedergabeweg Kopfhörer, Studiomonitore, FRFR, Audiointerface oder Endstufe + Gitarrenbox wählen.
2. Unter **Sounds** einen der drei Ziel-Sounds auswählen.
3. Unter **IR-Bibliothek** „IR-Ordner auswählen“ tippen und den Ordner der eigenen externen WAV-Sammlung freigeben.
4. Android speichert eine persistierbare Leseberechtigung für diesen Ordner. Die App gleicht Dateinamen mit `assets/catalog/ir_catalog.json` ab und zeigt fehlende, unbekannte und doppelte Dateien transparent an.
5. Ohne ausgewählte oder installierte Sammlung funktioniert die App weiter; alle Referenzdateien werden dann als „nicht gefunden“ angezeigt.
5. Unter **Empfehlung** Profil und Sound kontrollieren und Startwerte, Begründungen, Warnungen sowie höchstens drei IR-Kandidaten ansehen.

Dateinamen wie `Marshall_1960_V30_SM57_CapEdge.wav` liefern hohe Metadatenzuverlässigkeit. Ein Name ohne technische Begriffe bleibt ausdrücklich unbekannt. Künstler- oder Songnamen werden höchstens als schwacher Hinweis gewertet.

Bei **Endstufe + Gitarrenbox** deaktiviert die Empfehlung Cab/Custom-IR standardmäßig, da bereits eine reale Gitarrenbox verwendet wird.

## Voraussetzungen

- Android-Handy mit USB-Host-Unterstützung;
- USB-C-OTG-Adapter bzw. ein echtes USB-C-Datenkabel (kein reines Ladekabel);
- Flutter Stable 3.47.2 oder kompatibel;
- Dart 3.13.2 oder kompatibel;
- ein zum Android-Gradle-Plug-in kompatibles JDK (lokal gebaut mit Android Studios JBR 25);
- Android SDK und ein per USB-Debugging autorisiertes Handy für `flutter run`.

## Starten, testen und bauen

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --debug
```

Für die optionale TONE3000-Anbindung muss `wyrmtone://oauth/callback` bei TONE3000 registriert sein und der Publishable Key beim Build übergeben werden:

```powershell
flutter run --dart-define=TONE3000_CLIENT_ID=<PUBLISHABLE_KEY>
```

Ohne diesen Parameter bleibt die App vollständig startfähig; nur die Online-TONE3000-Schaltfläche ist deaktiviert. Niemals ein Client Secret in die App geben.

Die Debug-APK liegt danach unter `build\app\outputs\flutter-apk\app-debug.apk`.

### APK-Größen und Audiodatenprüfung

- Ausgangslage vor der WAV-Bereinigung: ungefähr 160 MB (älterer Buildbericht).
- Kontrollbuild direkt nach Entfernung der WAV-Assets: 153.069.788 Byte (145,98 MiB), 0 `.wav`-Einträge.
- Aktueller sauberer WyrmTone-Debug-Build mit TONE3000-IR/NAM-Integration und Matribox-Diagnose: 160.224.018 Byte (152,80 MiB), 0 `.wav`-, 0 `.nam`- und 0 `.zip`-Einträge.

Die aktuelle APK ist wegen zusätzlicher Debug-/Secure-Storage-Bibliotheken größer als der reine Bereinigungs-Kontrollbuild. Die Archivprüfung bestätigt, dass der Größenunterschied nicht von IR-Audiodateien oder Sammlungsarchiven stammt.

## Manueller Test auf einem Samsung-Android-Handy

1. APK installieren (`adb install -r build\app\outputs\flutter-apk\app-debug.apk`) oder `flutter run` verwenden.
2. DNAfx noch nicht verbinden, App starten und prüfen: „Kein unterstütztes Gerät verbunden“ sowie eine leere Geräteliste müssen sichtbar sein.
3. DNAfx mit einem USB-C-OTG-/Datenkabel direkt am Samsung-Handy anschließen und das Pedal einschalten.
4. „USB-Geräte suchen“ tippen. Alle erkannten USB-Geräte müssen erscheinen. Für den Core wird `1155 (0x0483) : 22275 (0x5703)` erwartet.
5. Beim markierten Gerät „USB-Zugriff erlauben“ tippen. Den Android-Dialog einmal ablehnen, verständliche Meldung und erneute Anfrage prüfen; danach erneut anfragen und erlauben.
6. Hersteller, Produkt, Konfigurationen, Interface 0 und Endpunkte kontrollieren. Hardwarebestätigt sind Interrupt-IN `0x81` und Interrupt-OUT `0x02` mit je 64 Byte maximaler Paketgröße und Intervall 2.
7. „Verbindung öffnen“ tippen. Der Status muss „DNAfx GiT Core verbunden (read-only)“ melden; am Pedal darf sich kein Preset und kein anderer Zustand ändern.
8. „Verbindung schließen“ tippen und prüfen, dass die UI zu „DNAfx GiT Core erkannt“ wechselt.
9. Erneut öffnen und das Kabel abziehen. Die App darf nicht abstürzen und muss zu „Kein unterstütztes Gerät verbunden“ wechseln.
10. Handy drehen, App in den Hintergrund schicken/zurückholen und den Such-/Öffnen-/Schließen-Ablauf wiederholen.
11. Diagnoseprotokoll kopieren und prüfen, dass keine Seriennummer oder Binärdaten enthalten sind.

### Sicherer Matribox-Test

1. Alte Vorgänger-App bei Bedarf manuell deinstallieren und die neue WyrmTone-APK installieren.
2. WyrmTone ohne USB-Gerät starten; erwartet wird „Kein unterstütztes Gerät verbunden“.
3. Matribox einschalten und per OTG-Datenverbindung anschließen.
4. **USB-Geräte suchen** antippen und `0x84EF:0x0054` als Matribox-Kandidaten kontrollieren.
5. **USB-Zugriff erlauben** antippen und den Android-Dialog bestätigen.
6. Hersteller, Produkt, 1 Konfiguration, 8 Interface-/Alt-Einträge und 6 Endpunkte kontrollieren.
7. **Verbindung öffnen** antippen. Erwartet: Interface 3 wird nicht erzwungen beansprucht; es werden keine Transfers gestartet.
8. **Verbindung schließen** antippen.
9. Noch einmal öffnen und bei geöffneter Verbindung das Kabel abziehen; die App darf nicht abstürzen.
10. Diagnoseprotokoll und Screenshots der Geräte-/Interfaceinformationen senden. WyrmTone zeigt die Seriennummer absichtlich nicht an.

## Checkliste für den ersten Test mit Marcel

- [ ] Pedal und Samsung-Modell/Android-Version notiert
- [ ] OTG-/Datenkabel verifiziert
- [ ] App startet ohne angeschlossenes Gerät
- [ ] `0x0483:0x5703` erkannt oder abweichende VID/PID dokumentiert
- [ ] Permission-Ablehnung und erneute Anfrage funktionieren
- [ ] Permission-Erteilung funktioniert
- [ ] Anzahl Konfigurationen/Interfaces/Endpunkte dokumentiert
- [x] Interface 0 und Interrupt-Endpunkte `0x81`/`0x02` bestätigt
- [x] Verbindung lässt sich öffnen und schließen
- [x] Kabeltrennung bei offener Verbindung verursacht keinen Absturz
- [ ] Rotation und Hintergrund/Rückkehr getestet
- [ ] Pedalzustand und Preset bleiben unverändert
- [ ] anonymisiertes Diagnoseprotokoll gesichert

## Bestätigte Referenzdaten und Sicherheitsentscheidung

Das auf einem GiT Core getestete Projekt [`lminiero/dnafx-editor`](https://github.com/lminiero/dnafx-editor) definiert VID `0x0483`, PID `0x5703`, Interface 0, IN `0x81`, OUT `0x02` und einen Transfer-Timeout von 1.000 ms. Sein Code erstellt dafür libusb-„Bulk“-Transfers. Der Android-Hardwaretest zeigt jedoch eindeutig, dass beide Endpunkte im USB-Deskriptor vom Typ **Interrupt** sind. WyrmTone richtet sich beim sicheren Interface-Claim nach dem realen Deskriptor. Der Referenzeditor sendet beim Start zwei jeweils auf 64 Byte aufgefüllte Initialisierungsnachrichten, bevor er Presets abruft. Die Bytes sind in [`docs/PROTOCOL_NOTES.md`](docs/PROTOCOL_NOTES.md) nur zur Nachvollziehbarkeit dokumentiert.

Obwohl der Referenzeditor diese Sequenz „Greeting“ nennt, ist ihre Wirkung nicht hinreichend als garantiert nicht schreibend belegt. WyrmTone implementiert sie daher **nicht**. Dieser Meilenstein endet nach Deskriptoranzeige und erfolgreichem Öffnen/Beanspruchen des Interfaces.

[`jblackiex/DNAfx_Hack`](https://github.com/jblackiex/DNAfx_Hack) bestätigt VID/PID und OUT-Endpunkt `0x02`, ist für den Core aber als ungetestet bezeichnet. Dessen Android-App steuert einen Raspberry-Pi-Server per TCP-Socket und spricht nicht direkt per Android USB Host mit dem Pedal. Diese Netzwerkarchitektur wurde nicht übernommen.

### Lizenzen

- `dnafx-editor`: MIT License, Copyright 2025 Lorenzo Miniero. Es wurde kein Quellcode kopiert; dokumentiert und unabhängig mit Android-APIs umgesetzt wurden die oben genannten beobachteten Identifikatoren/Deskriptorerwartungen.
- `DNAfx_Hack`: Im am 7. September 2026 geprüften Repository wurde keine eigenständige Lizenzdatei gefunden. Deshalb wurde daraus weder Quellcode noch Payload übernommen; es dient nur als zusätzliche Vergleichsquelle.
- WyrmTone: Für diesen Prototyp wurde noch keine Distributionslizenz festgelegt.

## Hardwarebefund vom 8. September 2026

Auf einem Samsung-Android-Handy wurde ein angeschlossenes DNAfx erfolgreich erkannt:

- VID/PID: `0x0483:0x5703`;
- Hersteller: STMicroelectronics;
- vom Gerät gemeldeter Produktname: „DNAfx GiT Advanced“;
- eine Konfiguration, ein Interface und zwei Endpunkte;
- Interface 0: Klasse 3 (HID), Subklasse 0, Protokoll 0;
- `0x81` IN, Interrupt, maximal 64 Byte, Intervall 2;
- `0x02` OUT, Interrupt, maximal 64 Byte, Intervall 2;
- Attach, Detach und Android-Permission-Erteilung funktionieren.
- Interface 0 wurde erfolgreich beansprucht, anschließend freigegeben und die Verbindung kontrolliert geschlossen.

Die Seriennummer wird absichtlich nicht in dieser Dokumentation oder in kopierbaren App-Logs festgehalten.

## Bekannte Einschränkungen

- Die Kabeltrennung während einer geöffneten Verbindung wurde am echten Gerät ohne Absturz bestätigt.
- Android kann String-Deskriptoren je nach Gerät/Firmware erst nach Berechtigung liefern; fehlende Werte werden als „Nicht verfügbar“ gezeigt.
- Nur exakt `0x0483:0x5703` wird als DNAfx-Kandidat geöffnet. Abweichende Kennungen bleiben sichtbar, werden aber aus Sicherheitsgründen nicht beansprucht.
- Nur die hardwarebestätigte Interface-/Endpunktkombination wird beansprucht. Abweichungen werden diagnostiziert, nicht erraten.
- Die Verbindung wird bei Activity-Zerstörung (einschließlich Rotation) geschlossen. Nach Rotation muss sie bewusst neu geöffnet werden.
- Es gibt weder automatische Verbindung noch einen USB-Device-Intent-Filter zum automatischen Start der App.
- Außer `J900`, `PURE BOOST` und der DNAfx-spezifischen Noise-Gate-`ATTACK`-Semantik liegt noch keine vollständige Modell-/Parameterreferenz im Projekt vor. CKY- und Nirvana-Amp-Zuordnung sowie fast alle Basiswerte sind sichtbar als Annäherung gekennzeichnet.
- IR-Eigenschaften werden in diesem Meilenstein ausschließlich aus Dateinamen geschätzt; es findet noch keine Audioanalyse statt.
- Die APK enthält keine WAV-Dateien. Nur `assets/catalog/ir_catalog.json` mit Dateinamen, WAV-Formatangaben, Tags, bekannten Dublettengruppen und Eignungshinweisen wird verteilt.
- TONE3000-Downloads landen ausschließlich zur Laufzeit im privaten App-Dokumentordner. Sie sind keine Assets und werden nicht in die APK oder das Repository übernommen.
- Der ausgewählte externe Ordner wird rekursiv und ausschließlich lesend über `ACTION_OPEN_DOCUMENT_TREE` erfasst. Wird der Ordner entfernt oder die Berechtigung entzogen, bleiben App und Referenzkatalog nutzbar und die Dateien erscheinen als „nicht gefunden“.

## Spätere Phasen (nicht implementiert)

1. aktuelle Presetnummer lesen;
2. Liste der 200 Presets lesen;
3. vollständiges Backup;
4. `.phb` importieren und exportieren;
5. ausdrücklich ausgewählten Testslot beschreiben;
6. Custom IRs verwalten und übertragen;
7. Soundgenerator und Presetbibliothek.

Jede spätere Phase benötigt getrennte Protokollvalidierung, explizite Schreibschutzgrenzen und Hardwaretests.
## Offline-Presets

WyrmTone wandelt den vorhandenen Recommendation-Entwurf in ein versioniertes,
geräteunabhängiges Preset um. Vorschau, Validierung, Vergleich, lokale Sicherung,
Testslot-Planung sowie SAF-Import und -Export als menschenlesbare
`.wyrmtone.json` funktionieren offline. Das Austauschformat enthält nur
Metadaten und Hash-Referenzen für IR/NAM, niemals Binärdaten, Tokens,
Seriennummern, private absolute Pfade oder MIDI-Rohdaten.

Die lokale Sicherung ist ausdrücklich kein aus der Matribox gelesenes
Hardware-Backup. Vollständiges Lesen, Auswählen, Speichern, Übertragen,
Verifizieren und Wiederherstellen eines Matribox-Presets ist protokollseitig
nicht bestätigt und bleibt technisch blockiert. Der bestätigte Gain-41-Test
erteilt dafür keine allgemeine Freigabe.

Der faktische Matribox-Katalog wird reproduzierbar und nur lokal erzeugt:

`dart run tool/generate_preset_catalog.dart <algorithm.xml> assets/catalog/matribox_preset_catalog.json`

Die Hersteller-XML wird weder kopiert noch in die APK aufgenommen. Für einen
Offline-Vergleich eines exportierten Presets mit passiven Capture-JSON-Dateien:

`dart run tool/preset_compare.dart --preset <preset.wyrmtone.json> --capture <capture.json> [--json-output <report.json>]`

PCAP/PCAPNG wird transparent als noch nicht unterstützt gemeldet; es wird keine
Unterstützung vorgetäuscht und keine Geräteverbindung geöffnet.
