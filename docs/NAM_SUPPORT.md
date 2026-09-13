# NAM-Unterstützung

## Umfang

WyrmTone kann ein einzelnes NAM-Capture bei TONE3000 auswählen, nach ausdrücklichem Antippen herunterladen, lokal validieren und in einem vom IR-Katalog getrennten Katalog verwalten. Alternativ kann genau eine lokale `.nam`-Datei über Androids Storage Access Framework nur lesend ausgewählt und in den privaten App-Speicher kopiert werden. Es gibt keine Ordner-Masseneinlesung, keinen Download-All und keinen Upload zu einem Pedal.

## Architektur und Kompatibilität

- **A1:** aktuelles, konservatives Zielformat für Matribox 1; wird als `compatible` markiert.
- **A2:** neuere NAM-Architektur; native Matribox-1-Unterstützung ist anhand der geprüften Gerätequelle nicht bestätigt und bleibt `unknown`.
- **A2-Lite:** reduzierte A2-Variante; ebenfalls nicht als nativ bestätigt und daher `unknown`.
- **Fehlende/andere Angabe:** bleibt `unknown`; die App erfindet kein A1.

Die Bezeichnung „NAM A2 Supported“ für Sonicake-Desktopsoftware ist kein Beleg dafür, dass die Matribox-1-Hardware A2 nativ ausführt. Eine mögliche Konvertierung wird erst implementiert, wenn sie offiziell und belastbar dokumentiert ist.

## Auswahl und Download

Die TONE3000-Auswahl verwendet die bestehende OAuth-Sitzung mit `prompt=select_tone`, `format=nam` und `architecture=1`. Nach der Auswahl listet die App nur die Modelle dieses Tone. Jeder Download erfordert einen einzelnen Buttondruck.

Geprüft werden offizielle HTTPS-Herkunft, HTTP 200, erlaubter Content-Type, sicherer Dateiname, `.nam`-Endung, Größe von 100 Byte bis 100 MiB, erkennbare JSON-Struktur, SHA-256 und API-Architektur. Es wird bewusst kein spekulativer vollständiger NAM-Parser implementiert. Die Datei landet zunächst als `.part` im privaten App-Speicher; Abbruch und Fehler räumen diese Datei auf. Bestehende Ziele werden nur nach Bestätigung ersetzt. Model-ID und SHA-256 kennzeichnen Dubletten.

Der Katalog enthält Tone-/Model-ID, Namen, Creator, Beschreibung, Make, Gear-Typ, Tags, Lizenz, Quelle, Architektur, Größe, lokalen Pfad, SHA-256, Zeitpunkt, Status, Zielgerät, Warnungen und Attribution. Fehlt eine katalogisierte lokale Datei nach einem Neustart, erhält sie `missingLocalFile`.

## Lokaler Import

`ACTION_OPEN_DOCUMENT` gewährt nur Lesezugriff auf eine einzelne vom Nutzer gewählte `.nam`-Datei. Die App validiert und kopiert sie in ihren privaten Speicher. Ohne belastbare API-Metadaten bleiben Architektur, Creator und Lizenz `unknown`; ein Import wird niemals als TONE3000-Download ausgegeben.

## Cabinet-Signalweg

- belegtes Amp-/Preamp-Capture ohne Cabinet: passende Custom-IR erforderlich;
- belegtes Amp+Cab- oder Full-Rig-Capture: zusätzliche IR normalerweise deaktiviert;
- unbekannter Cabinet-Anteil: Warnung und keine automatische Vermutung.

## Sicherheitsgrenze

Keine NAM-Datei wird als Asset verteilt. Es existieren keine USB-Schreibbefehle, keine Matribox-Erkennung mit geratenen IDs, keine Preset-/IR-/NAM-Übertragung und keine A2-zu-A1-Konvertierung.

Offizielle Quellen, geprüft am 10. September 2026: [TONE3000 API](https://www.tone3000.com/api), [API Terms](https://www.tone3000.com/api/terms), [TONE3000 Terms](https://www.tone3000.com/terms), [Sonicake Matribox](https://www.sonicake.com/products/matribox).
