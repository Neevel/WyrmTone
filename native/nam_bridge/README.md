# NAM Native Bridge

Dünne C-ABI-Bridge (`include/wyrmtone_nam.h`, `src/wyrmtone_nam.cpp`) über den NeuralAmpModelerCore. Die Dart-FFI-Schicht (`lib/services/nam_native_bindings.dart`, `nam_inference_engine.dart`) lädt die gebaute Bibliothek `wyrmtone_nam`.

## Voraussetzung: Submodule

Der Core liegt als **Git-Submodule** unter `third_party/NeuralAmpModelerCore` (Upstream `https://github.com/sdatkinson/NeuralAmpModelerCore.git`), gepinnt auf den Commit

`0b3d3c97b0859a3a8c92a8628c4dd89a25eb5842`

Frisch klonen:

```bash
git clone --recurse-submodules https://github.com/Neevel/WyrmTone.git
```

Bestehender Clone:

```bash
git submodule update --init --recursive
```

Eigen (`Dependencies/eigen`, Commit `bc3b39870ecb690a623a3f49149a358b95c5781d`) und AudioDSPTools (`Dependencies/AudioDSPTools`, Commit `0827c6c2fc0deced568536142ea86f189e0b98a1`) kommen rekursiv aus dem Core; `nlohmann/json` liegt im Core-Repository selbst. Es sind keine lokalen oder absoluten Symlinks nötig. Unter Windows kann bei sehr tiefen Klon-Pfaden `Filename too long` auftreten (verschachtelte Submodule): dann nahe am Laufwerksstamm klonen oder `git config --global core.longpaths true` setzen. Die Submodule-Version darf nur bewusst und mit ausdrücklicher Freigabe geändert werden (Änderung des Gitlinks = andere NAM-Inferenz).

## Core-Pfad und Build

`CMakeLists.txt` erwartet den Core unter `../../third_party/NeuralAmpModelerCore` (relativ zu dieser Datei) und bricht mit einer klaren Fehlermeldung ab, wenn `NAM/dsp.h` fehlt (Submodule nicht initialisiert). Benötigt werden `NAM/`, `Dependencies/eigen/` und `Dependencies/nlohmann/`; AudioDSPTools wird nicht mitkompiliert.

- **Android:** Gradle (`android/app/build.gradle.kts`) baut `wyrmtone_nam` über `externalNativeBuild` mit CMake 3.22.1 und dem NDK, das Flutter vorgibt (`flutter.ndkVersion`), immer als Release. Produktziel ist `arm64-v8a`; ein normaler Build erzeugt zusätzlich `armeabi-v7a` und `x86_64`. Aufruf wie üblich, z. B. `flutter build apk --release --target-platform android-arm64`.
- **Windows (nur Entwicklung, FFI-Tests):** `build.bat` baut `wyrmtone_nam.dll` mit NMake. Das Skript enthält Pfade der Entwicklungsmaschine (VS Build Tools, `TEMP`) und muss für andere Rechner angepasst werden; Ergebnis liegt in `native/nam_bridge/build/` (git-ignoriert).
