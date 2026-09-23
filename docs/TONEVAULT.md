# ToneVault V1

Offline, geräteunabhängige Klangwissensbasis. Kein Netz, keine Cloud, keine Geräte-/MIDI-/SysEx-/Wire-Daten.
Ein Eintrag beschreibt nur perceptuelle Ziele (bestehende `ToneDimension` 0..100, Block-Typ-Hinweise, Amp-Familien,
Cab/Speaker/Mikro-Texte). Die Übersetzung auf ein Gerät bleibt bei der bestehenden Pipeline
(`ToneDefinition.toTargetSound()` → `ToneRecipeBuilder` → `CanonicalToneRecipe` → Translator).

## Daten (`assets/tonevault/`)
- `manifest.json` (Pack-Liste), `taxonomy.json` (Genres/Eras, erweiterbar), `vocabulary.json` (Rollen-, Modifier-, Deskriptor-Wörter DE/EN)
- `packs/*.json`: `{pack:{id,name,version,schemaVersion,license}, entries:[…]}`; Schema-Version `1`, strikt geparst (unbekannte Felder werden abgelehnt).
- Eintragstypen: GENRE_TEMPLATE, STYLE_TEMPLATE, ARTIST_SIGNATURE, ERA_SIGNATURE, ALBUM_SIGNATURE, SONG, ORIGINAL_WYRMTONE, GUITAR_REIMAGINED.
  Varianten: RHYTHM, LEAD, SOLO, CLEAN, CRUNCH, AMBIENT, SPECIAL.
- `source.classification` (RESEARCHED, CURATED, STYLE_INSPIRED, WYRM_ORIGINAL, GUITAR_REIMAGINED, COMMUNITY, AI_GENERATED) ist von `confidence` (HIGH/MEDIUM/LOW) getrennt.
  RESEARCHED verlangt `source.references`. Ohne Quelle keine Behauptung über Originalequipment.

## Vererbung
Genre → Style → Artist → Era → Album → Song → Variante, über `parents` (Typ-Rang muss strikt steigen; Zyklen/fehlende Parents werden abgelehnt).
Ein Kind überschreibt nur, was es nennt: fehlendes Feld = UNSPECIFIED (nichts ändern), `"inherit"`, `"off"` (nur Effekt-Dimensionen), Zahl = DEFINED.
Je Ebene erst Basis-Tone, dann Varianten-Tone. Unspezifiziertes bleibt unspezifiziert (kein Template-Fallback: `TargetSound.templateFallback=false`).

## Suche
`ToneVault.resolve(text)` → `ToneVaultResolution` (`exact` / `choose` / `none`). Normalisierung (Diakritika, Apostrophe, Satzzeichen), Phrasen-Wörterbücher
(Exact > Alias > Fuzzy) und Fuzzy über Vokabular-Korrektur (Edit-Distanz + Phonetikschlüssel). Mehrdeutige Anfragen (z. B. „Metallica“) liefern eine Auswahl,
nie eine willkürliche Einzelauswahl. Score/`ToneMatchReason` sind intern; Ranking ist deterministisch. Ein späterer Mini-NLU füllt nur `ToneQuery`
(`ToneQueryParser`) und ruft `resolveQuery`; `ToneModifier` (MORE_GAIN, DARKER, …) wirken als Deltas nur auf definierte Dimensionen.

## Import/Validierung
`ToneVault.fromTexts/build` validiert alle Packs gemeinsam (`ToneVaultValidator`): doppelte IDs, Parent-Refs/Zyklen/Rang, Genre-/Era-Refs, Rollen,
Wertebereiche, widersprüchliche Zustände, RESEARCHED ohne Quelle, doppelte Aliase, Gerätebegriffe. Jeder Fehler lehnt den ganzen Import ab.

## Katalog
- **Seed:** 87 Einträge in 8 Packs (core_genres, metal_essentials, modern_metal, extreme_metal, rock_essentials, alternative_grunge, punk_pop_punk, electronic_reimagined); unverändert, IDs stabil.
- **Mass Catalog V1:** weitere Packs (`core_genres_ext`, `metal_*`, `rock_*`, `punk_emo_posthardcore`, `ambient_postrock`, `blues`, `funk_soul`, `country`, `jazz_fusion`, `instrumental_shred`,
  `roots_surf_rockabilly`, `artist_eras`, `song_layer`, `electronic_reimagined_ext`, `wyrm_originals`, `wyrm_fun_sounds`). Die Breite entsteht über Templates, Artist-/Era-/Album-Signaturen und Vererbung,
  nicht über kopierte Rezepte; Songs sind ein kleiner kuratierter Layer, der vom Parent erbt.
- **Quellen:** Artists/Eras/Alben/Songs sind `STYLE_INSPIRED` (Name = Referenz/Suchbegriff, keine Aussage über Originalequipment), Templates `CURATED`. Nichts ist `RESEARCHED`, `AI_GENERATED` oder `COMMUNITY`.
- **Generator:** `python tool/tonevault_catalog/build.py` (deterministisch, kein Zufall/Hash; Daten sind von Hand kuratierte Tabellen; überflüssige Overrides werden entfernt). Die Packs sind das versionierte Ergebnis.
- **Bericht:** `tool/tonevault_catalog/catalog_report.json` (Statistik, Genre-Abdeckung, Duplikate/Kollisionen); neu erzeugen mit `WRITE_TONEVAULT_REPORT=1 flutter test test/tonevault/tone_vault_mass_test.dart`.
  Ähnliche Artists/Templates werden gemeldet, nie automatisch gelöscht.
- **Pack-Metadaten:** `id`, `name`, `version`, `schemaVersion`, `description`, `license`, optional `entryCount` (wird validiert) und `sourceClassification`. Die Pack-Reihenfolge beeinflusst das Ergebnis nicht.
- **Era:** `era` (eine Ära) und `eras` (Liste) als Such-Kontext; Ären sind Taxonomie-Knoten (1960s..2020s, `modern`). Das nackte Wort „modern“ bleibt ein Adjektiv („modern metal“), die Ära heißt „modern era“.
- **Stimmungen:** `GuitarTuning` kennt zusätzlich C# Standard, Drop C# und Drop A; die vorhandene Tuning-Korrektur (`depth`) wendet sie an.
- **User-Wünsche:** Modifier/Effekte des Nutzers werden NACH den Tuning-/Gitarren-Korrekturen angewandt (`ToneUserAdjustments`) und im Rezept als `USER_OVERRIDE` geführt.

## Mini-NLU V1 (offline, deterministisch)
Deutsch/Englisch, kein Chatbot, keine erzeugten Texte. `vault.nlu.understand(text)` → `ToneNluResult` (`ToneQuery` + Resolver-Ergebnis + Stimmung).
- Pipeline: Rohtext → Normalisierung (Roh-Rewrites wie `c#`, Komposita wie „Rhythmussound“) → **derselbe** Index/Resolver für Artist/Song/Album/Genre/Ära (exact > alias > fuzzy) →
  Komposition von Intensität, Negation, Modifier, Adjektiven und Effekten → befülltes `ToneQuery` → **ein** Resolver-Durchlauf.
- Sprachdaten liegen in `assets/tonevault/nlu.json` (Intensitäten, Negationen, Richtung×Parameter, Effekte, Adjektive, Stimmungen, Stoppwörter); der Code enthält nur Struktur.
- Intensität `SLIGHT/NORMAL/STRONG` skaliert das zentrale Modifier-Delta (50/100/200 %); Summe je Dimension ≤ ±35, Ergebnis 0..100. Unspezifizierte Dimensionen bleiben unspezifiziert.
- Negation („ohne Reverb“) ist explizit AUS, nicht `LESS_*`. Effekte sind kanonische Ideen (chorus, delay, …), keine Geräte-Algorithmen.
- Ein Nutzerwunsch wirkt in `ToneVault.definitionFor(entryId, query:)` auf die Vault-Definition; Stimmungs-/Gitarren-Korrekturen folgen danach im bestehenden `ToneRecipeBuilder`.
  Stimmungen, die die App nicht kennt (Drop C#, Drop A, C# Standard), werden gemeldet, nicht ersetzt.
- Testkorpus: `test/tonevault/nlu_corpus.json` (versioniert, deutsch/englisch).

## UI (Sounds)
Ein einziger Sound-Flow ersetzt den alten „Sound erstellen“-Wizard und dessen eigenen Künstler-/Genre-Katalog (`SoundsPage` → `SoundDetailPage` → `YourSoundPage`):
Suche/Beschreibung („Was möchtest du spielen?“) → Verstanden-Chips und Treffer → Sound mit Charakter, Gitarre/Stimmung/Variante und Schnellanpassungen → „Sound verwenden“ → „Dein Sound“.
In der normalen Oberfläche heißt das „Sound“ / „Sound-Bibliothek“; die Namen ToneVault/NLU/Recipe bleiben intern.
- **Zustand:** `SoundSession` (`lib/sounds/`) hält Bibliothek, aktuellen Sound und „Zuletzt verwendet“. Gespeichert wird nur die kleine `SoundSelection` (Sound, Variante, Stimmung, Wünsche); der lokale Entwurf wird nach einem Neustart daraus deterministisch neu gebaut. Defekte oder veraltete Daten führen zu einer verständlichen Meldung und „Verwerfen“, nie zu einem Absturz.
- **Wünsche:** Schnellanpassungen und Text-Wünsche laufen über `ToneModifierIntent`/`ToneUserAdjustments` (`USER_OVERRIDE`).
- **Gerät:** „Für Gerät vorbereiten“ öffnet unverändert die bestehende Tone-Transfer-Seite; nichts wird automatisch gesendet.
- Weiterhin vorhanden, aber nicht mehr in der normalen Oberfläche: Legacy-Profile (`assets/catalog/sound_profiles.json`, `OfflineSoundProfiles`, statische `targetSounds`) für Regression und die Matribox-Zertifizierungs-Panels.

## Tests
`flutter test -j 1 test/tonevault` (Schema, Vererbung, Suche, Validator, Pipeline-Hand-over, Performance) und `test/sound_flow_test.dart` (Sound-Flow, Wiederherstellung, Responsive).
