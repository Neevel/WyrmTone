# Verbindliche Arbeitsregeln für WyrmTone

Diese Regeln gelten ab sofort für alle Arbeiten in diesem Projekt. Ausdrückliche aufgabenspezifische Freigaben des Nutzers sind zu beachten.

## Tests: risikobasiert und zielgerichtet

- Führe standardmäßig nur die Tests aus, die unmittelbar von der Änderung betroffen sind.
- Starte nicht automatisch die vollständige Flutter-, Dart-, Kotlin- oder Android-Testsuite.
- `flutter analyze` ist nur erforderlich, wenn Dart-/Flutter-Produktionscode verändert wurde oder ein konkreter Analysebedarf besteht.
- Ein vollständiger Debug-APK-Build ist nur erforderlich, wenn die Änderung anschließend auf einem echten Android-Gerät getestet werden soll, Android-Konfiguration, Manifest, Gradle, Kotlin oder Plattformkanäle verändert wurden oder ausdrücklich ein APK-Build verlangt wurde.
- Für reine Dokumentationsänderungen werden weder Tests noch APK-Builds ausgeführt.
- Für kleine UI- oder Logikänderungen genügen die direkt betroffenen Testdateien.
- Neue Tests werden nur ergänzt, wenn neues Verhalten, ein behobener Fehler oder ein relevantes Sicherheitsversprechen abgesichert werden muss.
- Vorhandene Tests dürfen nicht nur zur Erhöhung der Testanzahl dupliziert oder unnötig erweitert werden.
- Vollständige Regressionstests sind nur vor einem Release, nach größeren Querschnittsänderungen oder auf ausdrückliche Aufforderung auszuführen. Auch in den ersten beiden Fällen ist vorab eine Freigabe einzuholen, sofern diese nicht bereits ausdrücklich vorliegt.
- Falls aus Sicherheitsgründen mehr Tests notwendig sind, begründe kurz, welche konkrete Gefahr damit geprüft wird. Für eine vollständige Testsuite ist weiterhin eine vorherige Freigabe erforderlich.

## Besondere Hardware-Sicherheit

- Bei Änderungen an USB-, MIDI-, SysEx-, Preset-, IR- oder NAM-Übertragungen müssen zusätzlich die unmittelbar betroffenen Sicherheitstests ausgeführt werden.
- Eine Änderung vom passiven Lesen zum aktiven Senden gilt als sicherheitsrelevant und darf nicht stillschweigend erfolgen.
- Aktives Senden an ein Gerät darf nur nach ausdrücklicher Freigabe umgesetzt werden.

## Dokumentation: nur das Notwendige

- Aktualisiere nur Dokumente, deren Inhalt durch die konkrete Änderung tatsächlich falsch oder unvollständig geworden ist.
- Erstelle keine neuen Dokumente, wenn eine kurze Ergänzung in einem vorhandenen Dokument genügt.
- Wiederhole dieselben Informationen nicht in `README.md`, mehreren Dateien unter `docs/` und im Abschlussbericht.
- Interne Implementierungsdetails müssen nicht dokumentiert werden, solange sie keine öffentliche Schnittstelle, Einrichtung, Bedienung oder Sicherheitsregel betreffen.
- Reine Refactorings ohne Verhaltensänderung benötigen grundsätzlich keine Dokumentationsänderung.
- Testzahlen, APK-Größen und vollständige Dateilisten sollen nicht dauerhaft in mehreren Dokumenten gepflegt werden.
- Der Abschlussbericht soll kompakt sein und nur enthalten: was geändert wurde, welche gezielten Prüfungen ausgeführt wurden, deren Ergebnis, bekannte Einschränkungen und gegebenenfalls den APK-Pfad.

## Arbeitsumfang

- Ändere nur Dateien, die für die Aufgabe erforderlich sind.
- Keine nebenbei entdeckten Refactorings oder kosmetischen Umbauten.
- Keine Commits und kein Push ohne ausdrückliche Freigabe des Nutzers.
- Wenn eine vollständige Testsuite, umfangreiche Dokumentation oder eine Erweiterung des Aufgabenbereichs sinnvoll erscheint, frage vorher nach, sofern keine entsprechende ausdrückliche Freigabe bereits vorliegt.
