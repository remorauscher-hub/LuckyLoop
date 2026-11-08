# LuckyLoop

Processing-Sketch für macOS. Leertaste startet die Aufnahme, der nächste Druck speichert die Schleife und spielt sie ab. Das Livebild liegt darüber (Multiply, Screen oder Normal). Jede weitere Aufnahme wird eine neue Ebene.

## Öffnen

1. [Processing](https://processing.org/) installieren.
2. Library **Syphon** installieren (Contribution Manager). **Video** kommt mit Processing.
3. Diesen Ordner als Sketch öffnen (`LuckyLoop.pde`).
4. Sketch starten.

iPhone-Bild kommt über LuckyTether, die Continuity-Kamera oder Syphon. iPad-Zeichnung kommt über LuckyPad. Beide Programme liegen nicht in diesem Repo.

## Native Bibliotheken

Unter `data/` liegen die macOS-Bibliotheken (`lib*.dylib`), die der Sketch direkt lädt. Neu bauen, falls sie auf dem Rechner nicht laden:

```bash
bash native/build-macmenu.sh
bash native/build-midictl.sh
bash native/build-padctl.sh
bash native/build-tether.sh
bash native/build-h264dec.sh
```

Dafür braucht es die Xcode-Kommandozeilenwerkzeuge und ein JDK mit `jni.h` (das JDK von Processing reicht). `JAVA_HOME` setzen, wenn das Script `jni.h` nicht findet.

`libcamctl.dylib` (Kamera: Belichtung, Fokus, Zoom, Continuity) hat Quelltext in `native/camctl.m` und `native/uvc.m`. Ein Build-Script dafür liegt nicht bei; die mitgelieferte Bibliothek ist die laufende Fassung.

## Schriften

- Source Code Pro: SIL Open Font License, Text in `data/OFL.txt`
- Roboto Mono: Apache License 2.0

`data/settings.json`, `data/app.json` und `data/camera-diag.txt` sind der Stand von diesem Rechner, inklusive Projektpfaden.
