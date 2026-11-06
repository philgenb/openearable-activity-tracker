# Journal

Neueste Einträge oben. Format siehe [README](README.md#journal-eintrag).

## 2026-11-06: Android-Build auf Java 25 umgestellt

**Was:** Gradle von 8.14 auf 9.3.1 aktualisiert, AGP von 8.12.1 auf 9.1.0, Kotlin von 2.2.21 auf 2.4.0.

**Warum:** Der Build brach unter Java 25 ab, weil Gradle das erst ab Version 9.1 unterstützt. Wir nehmen 9.3.1 statt einer neueren Version, weil das die höchste ist, die Flutter 3.47 kennt. AGP und Kotlin entsprechen der Vorlage von Flutter 3.47. Die Alternative, lokal ein älteres JDK zu installieren und per `flutter config --jdk-dir` einzustellen, hätte jeder im Team einzeln machen müssen.

**Folgeänderungen, die dafür nötig waren:**

- `flutter_headset_detector` entfernt. Es nutzt `jcenter()`, das in Gradle 9 nicht mehr existiert, und es gibt keine neuere Version. Die App verwendete das Paket nirgends.
- `android.newDsl` und `android.builtInKotlin` auf `false` gesetzt, wie in der Flutter-Vorlage. Mit AGP 9 gehen sonst Flutter-Plugins kaputt.
- `proguard-android.txt` durch `proguard-android-optimize.txt` ersetzt, weil AGP 9 die alte Datei ablehnt. Mit `-dontoptimize` in `proguard-rules.pro` bleibt das Verhalten der Release-App wie bisher.

**Ergebnis:** Mit Java 25.0.3 und Flutter 3.47.6 laufen Debug- und Release-APK durch, `flutter analyze` ist sauber und alle 142 Tests bestehen.

**Offen:**

- Noch nicht auf einem echten Gerät ausprobiert.
- `ios/Podfile.lock` wurde von Hand angepasst, weil unter Windows kein `pod install` läuft.
- `-dontoptimize` kann raus, sobald ein Release-Build mit R8-Optimierung auf einem Gerät getestet wurde.
- Flutter warnt, dass künftige Versionen Plugins mit eigenem Kotlin-Plugin nicht mehr bauen (`flutter_archive`, `mcumgr_flutter`). Das betrifft uns erst beim nächsten Flutter-Update.
