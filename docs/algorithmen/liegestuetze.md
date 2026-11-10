# Liegestütz-Zählung: Algorithmusprüfung

Stand: 10.11.2026. Manuell gewählter Push-up-Modus, ohne ML.

## Befund und Entscheidung

Der Prototyp verwendete denselben Detektor wie Squats, lediglich mit anderer
Mindestamplitude. Geschwindigkeit und Position wurden fortlaufend gedämpft.
Dadurch verschwand ein abgesenkter Positionswert während einer Pause, obwohl
keine vollständige Rückbewegung stattfand.

Reproduzierbarer synthetischer Gegenfall: 16 cm Absenken in 0,9 s, 3 s halten,
2 cm zurück in 0,9 s, anschließend 5 s halten. Der alte Code zählte 1, der
korrigierte Code 0 Wiederholungen. Das sind simulierte Kopfbewegungen, keine
Messungen von Liegestütztiefe oder Versuchspersonen.

Ein eigener Push-up-Detektor wurde gewählt, damit die Korrektur den Squat-Zähler
nicht verändert. Die alte Positionsdämpfung wurde verworfen: Sie erzeugt eine
scheinbare Rückkehr. Kontinuierliches Zurücksetzen der Geschwindigkeit wurde
verworfen, weil es bei nahtlosen Wiederholungen neue Integrationsfehler erzeugt.

## Funktionsweise

1. Die gemeinsame IMU-Vorverarbeitung schätzt die Schwerkraftrichtung und glättet
   die projizierte vertikale Beschleunigung.
2. Der Push-up-Detektor verlangt 0,7 s mit ruhigem Beschleunigungs- und Gyrosignal.
   Der Restoffset wird erst nach 0,45 s Filter-Einschwingzeit gemittelt.
3. Die offsetbereinigte Beschleunigung wird kurzfristig integriert. Der
   Positionswert bleibt während einer Pause erhalten.
4. Auf Absenken folgt eine Rückbewegung von mindestens 80 % der geschätzten
   Absenkung. Erst nahe geschätzter Geschwindigkeit null wird gezählt. Eine
   Mindestbewegung und Mindestdauer verwerfen kleine beziehungsweise kurze Zyklen.
5. Nahe Stillstand darf die Geschwindigkeit korrigiert werden, nicht die aktive
   Absenkung. Restgeschwindigkeit bleibt beim Übergang zur nächsten Wiederholung
   erhalten. Große Kopfrotationen, Übersteuerung, Datenlücken und Moduswechsel
   verwerfen unvollständige Zyklen; ein Zeitlimit von 8 s begrenzt Drift.

Die Schwellwerte sind Heuristiken. Insbesondere der Positionsproxy mit 0,035 m
Mindestamplitude ist keine gemessene anatomische Tiefe. Bei nur geringer
Beschleunigung kann ein IMU-Detektor Stillstand nicht sicher von konstanter
Geschwindigkeit unterscheiden. Ein kurzer Halt in der oberen Position hilft
bei der Bestätigung der letzten Wiederholung.

## Evaluation und Grenzen

- 0 Versuchspersonen, keine Hardware-Aufnahmen; ausschließlich synthetische Signale.
- 38 Regressionstests in `open_wearable/test/apps/activity_tracker/push_up_detector_test.dart`.
- Unabhängige quintische Ruhe-zu-Ruhe-Trajektorien liefern die Referenz: jeweils
  6 Zyklen bei 8/16/25 cm simuliertem Hub und 1/1,8/3/5/7 s Zyklusdauer, 100 Hz.
  In diesen 15 Signalen wurden vorher 82 von 90, jetzt 90 von 90 Zyklen gezählt.
- Weitere Fälle: 50/100/200 Hz, Halten oben/unten, Teilrückkehr, flache Bewegungen,
  Zeitüberschreitung, Kopfrotation, Clipping, Datenlücke, Moduswechsel, andere
  feste Sensororientierung, konstante Restoffsets und reproduzierbares Rauschen.
- Die drei Rauschtests verwenden gleichverteilte, unabhängige Störungen bis
  ±0,02/0,05/0,1 m/s² bei 100 Hz und festem Zufallsseed; kein Modell realer Störsignale.

Das ist ein Implementierungsvergleich, kein Nachweis nutzerübergreifender
Genauigkeit. Nächster Schritt: synchronisierte Earable-/Video-Aufnahmen mit
mehreren Personen, Tempi, Kopfhaltungen und Negativkontrollen; Parameter nur auf
Entwicklungspersonen abstimmen, anschließend getrennte Testpersonen auswerten.

Ausführen aus `open_wearable/`:

```sh
flutter test test/apps/activity_tracker/push_up_detector_test.dart
```
