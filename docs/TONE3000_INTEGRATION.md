# TONE3000-Integration

## Umfang und Grenzen

WyrmTone verwendet ausschließlich die dokumentierte TONE3000 API. Es gibt kein Scraping, keinen Massendownload und keinen Download eines vollständigen Tone-ZIP-Archivs. Die App öffnet die offizielle Auswahl im Android-Systembrowser, lädt Metadaten zu genau dem ausgewählten IR-Tone und bietet dessen Modelle einzeln zum Download an.

Die Integration überträgt keine IR-Datei und keine Einstellung an das DNAfx. Die bestehende USB-Diagnose bleibt davon getrennt und sendet weiterhin keine USB-Nutzdaten.

Offizielle Referenzen:

- API-Dokumentation: <https://www.tone3000.com/api>
- API-Nutzungsbedingungen: <https://www.tone3000.com/api/terms>
- Allgemeine Bedingungen: <https://www.tone3000.com/terms>

## Entwicklerkonfiguration

1. In den TONE3000-Entwicklereinstellungen eine Anwendung mit der Redirect-URI `wyrmtone://oauth/callback` registrieren.
2. Nur den **Publishable Key** als Client-ID verwenden. Ein Client Secret gehört niemals in App, Quellcode, APK oder Build-Parameter.
3. Die App so starten oder bauen:

```powershell
flutter run --dart-define=TONE3000_CLIENT_ID=<PUBLISHABLE_KEY>
flutter build apk --debug --dart-define=TONE3000_CLIENT_ID=<PUBLISHABLE_KEY>
```

Ohne `TONE3000_CLIENT_ID` startet die App normal und zeigt im TONE3000-Bereich eine klare Konfigurationsmeldung. Alle lokalen Katalog-, Empfehlungs- und USB-Funktionen bleiben nutzbar.

WyrmTone verwendet die Android-ID `de.neevel.wyrmtone` und den kanonischen Callback `wyrmtone://oauth/callback`. Dieser Callback muss in den TONE3000-Entwicklereinstellungen exakt neu registriert werden. Die frühere Entwickler-App besitzt eine andere Android-ID; ihre verschlüsselten Tokens und lokalen Daten werden nicht übernommen und es gibt bewusst keine Datenmigration.

## OAuth2 und Sicherheit

- Authorization Endpoint: `https://www.tone3000.com/api/v1/oauth/authorize`
- Token/Refresh Endpoint: `https://www.tone3000.com/api/v1/oauth/token`
- Flow: Authorization Code mit PKCE (`S256`), zufälligem Verifier und zufälligem `state`
- Auswahlmodus: `prompt=select_tone` und `format=ir`
- Browser: Android-Systembrowser, kein eingebettetes WebView
- Callback: ausschließlich exakt `wyrmtone://oauth/callback`
- Tokens: Android-verschlüsselte Secure Storage; niemals Shared Preferences, Logs oder UI
- Ablauf: Access Token wird mit Refresh Token erneuert; `invalid_grant` löscht die Sitzung und verlangt eine neue Anmeldung
- Logout: löscht Access Token, Refresh Token, ausstehende PKCE-Daten und die sichtbare Auswahl

Alle Netzwerkaufrufe werden auf HTTPS und `tone3000.com` beziehungsweise dessen Subdomains begrenzt. Fehlertexte enthalten weder Token noch Authorization Header.

## Verwendete API-Aufrufe

- aktueller Benutzer: `GET /api/v1/user`
- ausgewählter Tone: `GET /api/v1/tones/{id}`
- Modelle dieses Tone: `GET /api/v1/models?tone_id={id}`
- einzelnes Modell: explizites `GET` auf die offizielle `model_url` mit Bearer Token

Die Modellantwort enthält eine TONE3000-Größenklasse, aber nicht zwingend die Byte-Dateigröße. Deshalb zeigt die App die Größenklasse vorab und ermittelt die echte Dateigröße beim Download. Die API-Rate-Grenze wird durch die gezielte Auswahl und wenige Einzelaufrufe respektiert; es existiert keine Schleife zum Sammeln des gesamten Katalogs.

## Download und lokale Attribution

Vor jedem Download zeigt die App Tone, Modell, Creator, Lizenz und Größenklasse. Nur der ausdrücklich angetippte Modell-Button startet genau einen Download. Währenddessen werden Fortschritt und Abbruch angeboten.

Die Datei wird zunächst als `.part` im privaten App-Dokumentordner `tone3000_irs` gespeichert. Danach werden HTTP-Status, Content-Type, RIFF/WAVE-Struktur, Chunk-Grenzen, Encoding, Mono/Stereo, 8–192 kHz, 16/24/32 Bit und ein sicherer lokaler Dateiname geprüft.

Erst nach erfolgreicher Validierung wird die Datei atomar auf `.wav` umbenannt. Abbruch, Netzwerkfehler oder ungültige Daten entfernen die Teil-Datei. Eine vorhandene Zieldatei wird nur nach sichtbarer Bestätigung ersetzt. SHA-256 erkennt inhaltliche Dubletten.

Der lokale Metadatensatz speichert URI, Tone-/Modell-ID, Namen, Creator, Lizenz, TONE3000-Quell-URL, Datum, Bytegröße, WAV-Format, Dauer, Prüfsumme und Status. Die Oberfläche weist Creator, Lizenz, Mono/Stereo und Duplikate sichtbar aus. Heruntergeladene IRs verbleiben lokal und werden nicht in Flutter-Assets, Git oder spätere APK-Builds aufgenommen.

## Manueller Android-Test

1. Mit registrierter Redirect-URI und `TONE3000_CLIENT_ID` bauen und installieren.
2. Unter **Bibliothek → IRs** auf **Mit TONE3000 verbinden** tippen und prüfen, dass der Systembrowser die TONE3000-Domain öffnet. NAM-Auswahl und lokaler Import liegen unter **Bibliothek → NAM**.
3. Anmeldung einmal abbrechen; die App muss ohne Download zurückkehren und „Auswahl abgebrochen“ anzeigen.
4. Erneut öffnen, einen IR-Tone wählen und prüfen, dass Titel, Creator, Lizenz und nur dessen Modelle erscheinen.
5. Ein Modell antippen, Fortschritt prüfen und einmal abbrechen. Es darf keine `.part`-Datei verbleiben.
6. Dasselbe Modell vollständig laden. Prüfen, dass Attribution und technische WAV-Daten lokal erscheinen.
7. Noch einmal laden und den Ersetzen-Dialog zunächst ablehnen, danach bewusst bestätigen.
8. App neu starten: verschlüsselte Sitzung und lokale Attribution müssen wieder verfügbar sein.
9. **Verbindung trennen** tippen und prüfen, dass eine neue Auswahl erneut zur Anmeldung führt.
10. Während aller Schritte das DNAfx beobachten: Es darf kein Preset-, IR- oder Gerätezustand verändert werden.

## Tarif- und Freigabehinweis

Die implementierten Auswahl-, Tone- und Modellaufrufe richten sich nach der öffentlich dokumentierten API. Funktionen oder Nutzungsarten, die laut TONE3000 eine Partnerfreigabe oder kommerzielle Vereinbarung benötigen, sind nicht implementiert. Vor einer kommerziellen Veröffentlichung müssen die dann aktuellen TONE3000-Bedingungen und gegebenenfalls eine schriftliche Vereinbarung geprüft werden.

## NAM-Auswahl

IR und NAM verwenden dieselbe OAuth2-/PKCE-Sitzung, dieselbe verschlüsselte Tokenablage und denselben Callback. Es existiert keine zweite Anmeldung. Der IR-Weg bleibt `prompt=select_tone&format=ir`; der Matribox-NAM-Weg verwendet die offiziell dokumentierten Parameter `prompt=select_tone&format=nam&architecture=1`.

Die App baut keinen eigenen TONE3000-Katalog auf. Erst die bewusste Auswahl im Systembrowser liefert eine Tone-ID. Danach werden nur die Modelle dieser Auswahl geladen und jedes NAM-Modell besitzt einen eigenen Button **NAM herunterladen**. Es gibt weder Download-All noch ZIP-, Hintergrund- oder Massendownloads.

Der Download akzeptiert nur offizielle HTTPS-URLs unter `tone3000.com` beziehungsweise Subdomains, sendet den Access Token nur als Bearer-Header, prüft HTTP-Status und Content-Type und validiert Dateiname, `.nam`-Endung, plausible Größe und erkennbare JSON-Struktur. Die Architekturangabe der API hat Vorrang. Fehlende oder unbekannte Architektur wird nicht zu A1 umgedeutet. SHA-256, Model-ID, Creator, Lizenz und TONE3000-Herkunft bleiben im getrennten lokalen NAM-Katalog erhalten.

Abbruch und Fehler entfernen `.part`-Dateien. Vor dem Ersetzen eines vorhandenen Ziels fragt die UI nach. Die lokal gespeicherte Datei ist kein Flutter-Asset und wird nicht in Git oder die APK aufgenommen. Einzelheiten zur Kompatibilität und zum lokalen SAF-Import stehen in [`NAM_SUPPORT.md`](NAM_SUPPORT.md).
