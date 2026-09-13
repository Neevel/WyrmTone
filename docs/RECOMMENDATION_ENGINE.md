# Regelbasierter Empfehlungskern

## Zweck und Sicherheitsgrenze

Der Dienst `RecommendationEngine` berechnet reproduzierbare Startwerte aus strukturierten Eingaben. Er hat keine Abhängigkeit zu Flutter-Widgets, Android oder USB und sendet nichts an das DNAfx. Ergebnisse werden ausschließlich angezeigt.

## Eingaben

- Ziel-Sound: Künstler, Song, Stil, Referenzstimmung, Gain/Brightness/Tightness/Bass, Mitten- und Dynamikbeschreibung, Amp-/Cab-Stil, Effekte und Basisparameter;
- Gitarrenprofil: Bauart, Pickup-Typ und -Pegel, Klangcharakter, Stimmung, optionale Saitenstärke und Wiedergabeweg;
- bestätigte DNAfx-Fähigkeiten: derzeit `J900`, `PURE BOOST`, `GAIN`, `BASS`, `MID`, `TREBLE`, `PRESENCE` und `NOISE_GATE_ATTACK`;
- Metadaten aus dem eingebetteten JSON-Referenzkatalog und die Dateinamen des extern ausgewählten IR-Ordners.

## Ziel-Sounds und Evidenz

Für **Children of Bodom – Angels Don’t Kill** sind `J900`, vorgeschalteter `PURE BOOST`, Marshall-4x12-/V30-artige IR, D Standard und Gate-ATTACK ungefähr 86 als praktisch bestätigte Basis hinterlegt.

Für **CKY – 96 Quite Bitter Beings** und **Nirvana – Come As You Are** wird mangels vollständiger DNAfx-Modellreferenz ebenfalls das bestätigte `J900` als ausdrücklich gekennzeichnete Annäherung verwendet. Die Basisparameter aller drei Sounds außer der genannten CoB-Ausgangsbasis sind Startwerte, keine Behauptungen über Studioequipment oder exakte DNAfx-Rekonstruktionen.

## Anpassungsregeln

- aktiver Humbucker: Gain −6, Bass −5, Gate-ATTACK +3;
- heißer passiver Humbucker: Gain −4, Bass −3;
- schwacher passiver Humbucker: Gain +5;
- Singlecoil: Gain +5, Treble −3, Gate bewusst nicht aggressiver;
- dunkler Klang: Treble +4, Presence +4;
- heller Klang: Treble −4, Presence −4;
- D Standard und tiefer: Bass −4; Drop C/Drop B: Bass −7; Presence +2; Gain wird nicht automatisch erhöht.

Kombinierte Abweichungen werden je Parameter auf maximal ±10 Punkte gegenüber dem Basispreset begrenzt und danach auf den Bereich 0–100 geklemmt.

Bei Endstufe + realer Gitarrenbox wird Cab/Custom-IR deaktiviert und keine IR-Rangliste ausgegeben. Für Kopfhörer, Studiomonitore, FRFR und Audiointerface bleibt Cab/IR aktiv.

## DNAfx-spezifische Noise-Gate-Semantik

`ATTACK` wird nicht wie ein gewöhnlicher Zeitparameter interpretiert. Beim DNAfx bedeutet ein hoher Wert (beispielsweise 80–90), dass das Gate schnell öffnet. Ein niedriger Wert wie 10 kann Anschlag oder Signal abschneiden. Deshalb schlägt das Feedback „Gate schneidet Töne ab“ ausdrücklich vor, `ATTACK` zu **erhöhen**, nicht zu senken.

Diese Richtungsregel wird nicht pauschal auf Gain, Bass, Mid, Treble oder Presence übertragen.

## IR-Dateinamenparser

Der Parser normalisiert Groß-/Kleinschreibung, Bindestriche, Unterstriche und Leerzeichen. Er erkennt nur tatsächlich vorkommende Begriffe für Hersteller/Sammlung, Cabinet, Speaker, Mikrofon und Position. Mehrere Treffer bleiben als Tags erhalten. Ohne technische Treffer bleiben Eigenschaften `null` und die Zuverlässigkeit 0.

Brightness, Tightness und Low-End werden nur geschätzt, wenn ein erkannter Speaker oder ein Mikrofon eine explizite Regel besitzt. Künstler-/Songtags erzeugen keine erfundenen technischen Metadaten.

## IR-Gewichtung

- 30 % Cabinet-/Speaker-Übereinstimmung;
- 25 % gewünschte Brightness;
- 20 % Tightness;
- 15 % Mikrofon und Position;
- 10 % Anpassung an Gitarre und Stimmung.

Fehlende Komponenten erhalten 0 statt einer neutralen oder perfekten Wertung. Anschließend reduziert ein Faktor von `0,45 + 0,55 × Parser-Zuverlässigkeit` die Gesamtwertung bei dünner Datenlage. Ein Künstler-/Songhinweis darf höchstens drei Zusatzpunkte liefern. Weniger als 60 % Parser-Zuverlässigkeit oder weniger als 45 Bewertungspunkte wird als „unsichere Empfehlung“ markiert.

## Persistenz und Datenschutz

Gitarrenprofile werden als JSON in Android Shared Preferences gespeichert. Der kleine Referenzkatalog `ir_catalog.json` enthält nur Dateinamen, bekannte WAV-Headerdaten, abgeleitete Tags, Dublettengruppen und Eignungshinweise. Die APK enthält keine WAV-Audiodaten.

Die Ordnerauswahl verwendet `ACTION_OPEN_DOCUMENT_TREE` mit ausschließlich persistierbarer Leseberechtigung und ohne allgemeine Speicherberechtigung. Beim Neustart wird die gespeicherte Tree-URI erneut ausschließlich lesend aufgelistet. Der Abgleich erfolgt nach normalisierten Dateinamen; WAV-Inhalte werden nicht kopiert, verändert, analysiert oder zum DNAfx übertragen. Ohne freigegebenen Ordner bleiben Referenzkatalog und alle anderen App-Funktionen verfügbar.

Wenn keine geeignete lokale IR vorhanden ist, kann die Empfehlung gezielt zur TONE3000-Auswahl in der IR-Bibliothek führen. Bereits einzeln heruntergeladene TONE3000-IRs behalten Creator-, Lizenz- und Quellenattribution. Die Empfehlung öffnet nur die lokale IR-Ansicht; eine Übertragung an das DNAfx ist weiterhin ausdrücklich deaktiviert.

## Geplante Erweiterungen

- Audioanalyse von WAV-Dateien für echte spektrale und zeitliche Eigenschaften;
- vollständige, quellengeprüfte DNAfx-Modell- und Parameterbibliothek;
- persönliche Kalibrierung anhand freiwilligen Nutzerfeedbacks;
- getrennte Kalibrierung nach Gitarre, Abhörweg, Raum und Lautstärke;
- erst nach eigener Sicherheitsprüfung: bewusst bestätigter Transfer ausgewählter Einstellungen.

## Zielgeräte und NAM

Die Empfehlung unterscheidet nun `Harley Benton DNAfx GiT Core` und `Sonicake Matribox 1 / QME-50`. Beim DNAfx bleibt die bisherige Amp-/Effekt-/Custom-IR-Logik unverändert und liefert keine NAM-Empfehlung. Bei der Matribox werden keine DNAfx-Modellnamen oder unbelegten Matribox-Parameter angezeigt. Ein internes Matribox-Ampmodell erscheint nur als allgemeine, nicht weiter benannte Option.

Als zweite Matribox-Klangquelle werden höchstens drei lokal vorhandene und als kompatibel eingestufte NAM-A1-Captures bewertet. Die Wertung verwendet ausschließlich gespeicherte TONE3000-Metadaten wie Make, Gear-Typ, Tags und Creatorbeschreibung zusammen mit den vorhandenen drei Ziel-Sounds. Sie behauptet keine exakte Studio-Reproduktion.

Die Signalwegregel ist konservativ: Ein belegtes Amp-/Preamp-Capture ohne Cabinet verlangt eine zusätzliche Custom-IR; bei Amp+Cab oder Full Rig wird eine weitere IR normalerweise deaktiviert. Ist der Cabinet-Anteil unbekannt, bleibt die IR-Entscheidung offen und die UI zeigt eine Warnung. NAM A2, A2-Lite, unbekannte Architektur, ungültige oder verwaiste Dateien werden nicht empfohlen.
