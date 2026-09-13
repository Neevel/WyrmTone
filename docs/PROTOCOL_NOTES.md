# USB-Protokollnotizen (nur Dokumentation)

## Passiver Android-MIDI-Monitor (12. September 2026)

Der manuelle Samsung-Test bestätigte Matribox-MIDI-Erkennung, einen Input-/Output-Port, wiederholtes Öffnen/Schließen und sicheres Detach bei geöffnetem Gerät ohne Absturz (danach 0 USB-/MIDI-Geräte). Raw-USB-Claim ist nicht notwendig; Android verwaltet Interface 3. Kein Force-Claim wird verwendet.

Der neue Monitor öffnet nach ausdrücklichem Start ausschließlich den Geräte-Output-Port: Matribox → empfangender App-Receiver. `onSend` ist ein von Android aufgerufener Empfangs-Callback, kein Sendeaufruf durch WyrmTone. Der Geräte-Input-Port bleibt ungeöffnet. Es gibt keine Anfrage/Antwort, Clock, Active Sensing oder andere Testausgabe.

Chunks werden in Reihenfolge erfasst, SysEx lokal von F0 bis F7 zusammengesetzt und Real-Time-Bytes separat klassifiziert. Größenlimit, Timeout, neue Statusbytes oder Empfangslücken brechen eine unvollständige Assemblierung transparent ab. Unbekannte Bytes erhalten keine erfundene Matribox-Bedeutung. Export speichert ausschließlich ein ausdrücklich ausgewähltes JSON-Dokument mit `receiveOnly=true`; keine Deskriptor-Seriennummern, Gerätepfade, OAuth-Daten oder privaten Pfade. Rohpayload vor Weitergabe prüfen. Details: [MIDI_CAPTURE.md](MIDI_CAPTURE.md).

> Die optionale TONE3000-Integration ist vollständig von dieser USB-Schicht getrennt. Heruntergeladene IR-Dateien werden nie an das DNAfx übertragen; es wurden dafür keine Transfer- oder Schreibaufrufe ergänzt.

Stand der Quellenprüfung: 7. September 2026; Hardwareabgleich: 8. September 2026. Diese Datei dokumentiert Reverse-Engineering-Erkenntnisse; WyrmTone sendet keinen dieser Payloads.

## `lminiero/dnafx-editor`

Quelle: [`src/usb.c`](https://github.com/lminiero/dnafx-editor/blob/master/src/usb.c), MIT-Lizenz.

- getestetes Ziel laut README: DNAfx GiT Core;
- Vendor-ID: `0x0483`;
- Product-ID: `0x5703`;
- beanspruchtes Interface: `0`;
- IN-Adresse: `0x81` (`LIBUSB_ENDPOINT_IN | 1`);
- OUT-Adresse: `0x02`;
- Timeout: 1.000 ms;
- logischer Nachrichtenpuffer: 40.960 Byte;
- Transfers für Initialisierung und Abrufe werden auf 64 Byte mit Nullen aufgefüllt.

Als Initialisierung sind zwei Präfixe definiert:

```text
08 00 00 00 00 00 00 00 00
08 AA 55 02 00 00 00 12 97
```

Der Code baut die Übertragungen mit `libusb_fill_bulk_transfer` auf. Der Hardwaredeskriptor des getesteten Geräts klassifiziert beide Endpunkte dagegen als Interrupt. Die Quelle bezeichnet den Ablauf als Initialisierung/Greeting, dokumentiert aber keine belastbare semantische Garantie, dass die Sequenz keinerlei Gerätezustand verändert. Sie ist deshalb nicht implementiert.

Die Quelle enthält weitere Get-/Change-/Rename-/Upload-Kommandos. Diese werden für Meilenstein 1 weder übernommen noch vollständig in diesem Projekt dokumentiert, um versehentliche Nutzung zu vermeiden.

## `jblackiex/DNAfx_Hack`

Quelle: [`server/.env`](https://github.com/jblackiex/DNAfx_Hack/blob/main/server/.env) und `server/src/usbhid_channel.py`.

- Vendor-ID `0x0483`, Product-ID `0x5703`, OUT-Endpunkt `0x02`;
- GiT Core laut Projekt-README ungetestet;
- Android-Client nutzt TCP-Sockets zum Raspberry-Pi-Server, nicht Android USB Host;
- Server sendet zustandsverändernde Preset-Payloads. Keine Payload wurde übernommen.

Im geprüften Repository war keine eigenständige Lizenzdatei vorhanden. Erkenntnisse aus dieser Quelle werden deshalb nur als Tatsachenabgleich genannt.

## Android-Hardwareabgleich

Der Test am 8. September 2026 bestätigte `0x0483:0x5703`, Hersteller STMicroelectronics und den Produkt-String „DNAfx GiT Advanced“. Interface 0 meldete Klasse 3 (HID), Subklasse 0, Protokoll 0 sowie genau zwei **Interrupt**-Endpunkte: IN `0x81` und OUT `0x02`, jeweils maximal 64 Byte und Intervall 2. Der Produkt-String kann auf eine gemeinsam genutzte Firmwarebezeichnung hinweisen; das ist eine Vermutung und noch nicht bestätigt.

Mit der hardwarekorrigierten Endpunktprüfung konnte Android Interface 0 erfolgreich beanspruchen. Anschließend wurden Interface und `UsbDeviceConnection` kontrolliert freigegeben bzw. geschlossen. Dabei wurde kein USB-Nutzdatentransfer ausgeführt und am Gerät keine Zustandsänderung ausgelöst.

Auch das physische Abziehen des USB-Kabels bei geöffneter Verbindung wurde ohne App-Absturz bestätigt; der Detach-Pfad schloss die native Verbindung sicher.

Diese direkt gelesenen Deskriptorwerte ersetzen für die Interfaceauswahl die zuvor aus der libusb-Aufrufart abgeleitete Bulk-Annahme.

## Implementierte Grenze

Der Kotlin-Code verwendet ausschließlich `UsbManager`, `UsbDevice`, `UsbConfiguration`, `UsbInterface`, `UsbEndpoint` und `UsbDeviceConnection` für Inventarisierung, Permission, `openDevice`, `claimInterface`, `releaseInterface` und `close`. Es gibt keinen Aufruf von `bulkTransfer`, `controlTransfer` oder `UsbRequest`.

## Matribox-1-Hardwareabgleich

Am 11. September 2026 wurde die Sonicake Matribox 1 / QME-50 auf einem Samsung-Handy als `0x84EF:0x0054` mit einer Konfiguration, acht Interface-/Alternate-Setting-Einträgen und sechs Endpunkten beobachtet. Interface 3/Alt 0 meldete Klasse 1, Subklasse 3, Protokoll 0 sowie Bulk-IN `0x83` (64 Byte) und Bulk-OUT `0x03` (256 Byte). Interfaces 0–2 gehören zur beobachteten USB-Audio-Struktur und werden nicht beansprucht.

USB-Klasse 1/Subklasse 3 deutet auf MIDI Streaming hin, ist aber kein Beweis für ein proprietäres Editor- oder NAM-Protokoll. Der Matribox-Pfad prüft alle genannten Interface- und Endpunktmerkmale und verwendet ausschließlich einen nicht erzwungenen Claim. Er startet keinerlei Transfer und versucht bei einem Claim-Fehlschlag nicht erneut.
