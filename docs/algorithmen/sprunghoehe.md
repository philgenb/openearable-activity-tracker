# Sprunghöhe

Stand: 15.11.2026. Code: [`activity_engine.dart`](../../open_wearable/lib/apps/activity_tracker/models/activity_engine.dart), Klasse `_JumpDetector`. Grundlage ist Phils Prototyp vom 06.11.2026.

## Ansatz: Flugzeit

Während der Flugphase ist der Kopf im freien Fall, der Beschleunigungssensor misst dann fast 0 g. Aus der Flugzeit `t` folgt die Höhe des Körperschwerpunkts:

```text
h = g · t² / 8
```

Das ist dieselbe Methode, die Kontaktmatten und Slow-Motion-Apps nutzen. Sie setzt voraus, dass Absprung- und Landehaltung gleich sind (gestreckte Beine).

**Ablauf im Detektor:**

1. **Bereit:** Im Sprung-Test immer. Im Schritt-Modus erst nach mindestens 0,5 s ruhig stehen (|a| innerhalb ±0,8 m/s² um die kalibrierte Schwerkraft, Gyro < 0,3 rad/s).
2. **Abdruck:** innerhalb von 2 s nach der Ruhephase |a| > 12,3 m/s² (≈ 1,25 g).
3. **Absprung:** die erste Unterschreitung von 3,5 m/s² (≈ 0,36 g) innerhalb von 0,5 s nach dem letzten Abdruck-Sample. Kommt innerhalb von 80 ms wieder ein Sample > 12,3 m/s², drückt der Fuß noch: Die Suche nach dem Absprung beginnt neu, ohne Sperrzeit.
4. **Landung:** die letzte Überschreitung von 3,5 m/s² vor dem Aufprall (> 12,3 m/s²). Kurze Überschreitungen in der Luft beenden den Flug nicht. Bleibt |a| länger als 120 ms über 3,5 m/s², ohne dass ein Aufprall kommt, wird der Versuch ohne Höhe gemeldet.
5. Danach 0,8 s Sperrzeit.

Die Ruhephase im Schritt-Modus verhindert, dass die kurzen Flugphasen beim Joggen als Sprünge zählen. Im Sprung-Test hat der Nutzer Sprünge angekündigt, dort reicht Abdruck plus Freifall.

## Parameter

| Parameter | Wert | Bedeutung |
| --- | --- | --- |
| Freifall-Schwelle | 3,5 m/s² | Absprung und Landung |
| Abdruck/Aufprall | 12,3 m/s² | Abdruck vor dem Sprung, Bestätigung der Landung |
| Gültige Flugzeit | 0,12–0,85 s | entspricht ca. 1,8–89 cm |
| Mindestrate | 40 Hz | langsamere Samples → keine Höhe |
| Bereitschaftsfenster | 2 s | Zeit zwischen Ruhe und Abdruck (nur Schritt-Modus relevant) |
| Mindestflugzeit | 80 ms | Aufprall-Sample davor = Fuß drückt noch |
| Landewartezeit | 120 ms | so lange über 3,5 m/s² ohne Aufprall = keine Landung |
| `flightOffset` | 0 s | systematische Korrektur, wird gegen die Referenz gefittet |

## Änderungen gegenüber dem Prototyp (07.11.2026)

**1. Abgeschnittene Spitzen machen die Höhe nicht mehr ungültig.** Der Prototyp verwarf jeden Sprung, bei dem eine Achse ±2 g erreichte. Bei der Landung erreicht der Kopf aber typischerweise mehrere g, damit hätte fast jeder echte Sprung keine Höhe bekommen. In die Höhe gehen nur die Zeitpunkte ein, an denen |a| die Schwelle von 0,36 g kreuzt. Ob die Spitze danach bei 2 g abgeschnitten wird, ändert an diesen Zeitpunkten nichts. Für Schritte und Wiederholungen bleibt die Clipping-Erkennung unverändert.

**2. Absprung und Landung werden zwischen zwei Samples interpoliert.** Bei 100 Hz lag der Zeitpunkt bisher bis zu 10 ms daneben, pro Ende. Die Höhe reagiert darauf empfindlich: `dh/dt = g·t/4`, bei 0,5 s Flugzeit sind 10 ms also rund 1,2 cm. Jetzt wird linear zwischen dem letzten Sample über und dem ersten unter der Schwelle interpoliert (und umgekehrt bei der Landung). Ein Test mit synthetischem Signal und vier verschiedenen Abtastphasen zeigt: Mit Interpolation liegt die Flugzeit innerhalb 1 ms, ohne lag sie 7 ms daneben.

**3. Kalibrier-Knopf `flightOffset`.** Am Ohr misst der Detektor die Flugzeit vermutlich etwas zu lang: Die 0,36-g-Schwelle wird kurz vor dem Abheben der Zehen unterschritten, und der Landestoß kommt am Kopf leicht verzögert an. Beides führt zu überschätzten Höhen. Wie groß der Fehler ist, kann nur ein Vergleich mit einer Referenz zeigen. Bis dahin steht der Wert auf 0.

## Erster Hardware-Test (13.11.2026)

**Aufbau:** 1 Person (JP), OpenEarable 2.0, ca. 100 Hz, App-Sprung-Test, keine Referenzmessung. 4 Sprünge in einer Session von 96 s. Die App zeigte für keinen Sprung eine Höhe an, nur „—“.

**Befund aus der Roh-CSV:** Alle vier Flugphasen sind klar sichtbar (|a| 0,6–2,5 m/s² über 0,37–0,42 s). Der Detektor hat sie aus drei Gründen verworfen:

1. **Ausholbewegung zu lang.** Von der letzten ruhigen Phase bis zum Abdruck vergingen ≥ 0,7 s, das Fenster war genau 0,7 s.
2. **Schein-Flug im Abdruck.** Beim Abdruck kommen einzelne Samples unter 3,5 m/s² vor (Vibration, z. B. 2,4 m/s² für 10 ms). Der Detektor wertete das als Absprung, verwarf den 10-ms-„Flug“ und setzte danach 0,8 s Sperrzeit. Der echte Flug fiel genau in diese Sperre.
3. **Keine Ruhephase.** Vor Sprung 3 bewegte sich der Kopf (Gyro 0,3–0,6 rad/s), und die Ruheprüfung nutzte fest 9,81 m/s², während dieses Earable in Ruhe 10,0–10,3 m/s² misst.

**Änderung:** Fenster 2 s, kurze Unterschreitungen ohne Sperrzeit verwerfen, Ruheprüfung gegen die kalibrierte Schwerkraft, im Sprung-Test keine Ruhepflicht.

**Ergebnis (Replay derselben Aufnahme):** 3 von 3 Sprüngen im kalibrierten Sprung-Test erkannt, geschätzt 17,1 / 21,4 / 16,4 cm (Flugzeit 0,373 / 0,418 / 0,366 s). Der 4. Sprung lag nach einer Pause, bevor neu kalibriert war, und wird absichtlich nicht gewertet. Ohne Referenz sagt das nichts über die Genauigkeit, nur über die Erkennung. Die Rohdaten bleiben lokal, ins Repo kommt ein synthetischer Test mit derselben Signalform.

## Erster Vergleich mit Slow-Motion-Video (13.11.2026)

**Aufbau:** 1 Person, 8 Sprünge in einer Session, OpenEarable 2.0 mit ca. 100 Hz, App-Version mit den Fixes vom 13.11. Referenz: Pixel-Slow-Motion von der Seite auf Fußhöhe, aufgenommen mit 240 fps (gespeichert mit 30 fps, `com.android.capture.fps=240`, also 1 Frame = 1/240 s). Abheben = letzter Frame mit Zehenkontakt, Landung = erster Frame mit Kontakt, abgelesen von Hand an vergrößerten Bildstreifen. Ablesefehler etwa ±2 Frames pro Ende (±8 ms). Die Zuordnung ist geprüft: Die Erkennungszeitpunkte der App liegen bei allen 8 Sprüngen höchstens 70 ms nach der Landung im Video. Auch die Abstände zwischen den Sprüngen stimmen auf unter 0,1 s überein. Damit ist bestätigt, dass das Video durchgehend mit 240 fps läuft.

| Nr | Flug Video | Flug App | Diff | Höhe Video | Höhe App | Diff |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 0,456 s | 0,405 s | −52 ms | 25,5 cm | 20,1 cm | −5,4 cm |
| 2 | 0,377 s | (0,201 s, verworfen) | – | 17,4 cm | – | – |
| 3 | 0,427 s | 0,339 s | −88 ms | 22,4 cm | 14,1 cm | −8,3 cm |
| 4 | 0,510 s | 0,368 s | −142 ms | 31,9 cm | 16,6 cm | −15,3 cm |
| 5 | 0,217 s | 0,231 s | +14 ms | 5,8 cm | 6,5 cm | +0,8 cm |
| 6 | 0,283 s | 0,339 s | +56 ms | 9,8 cm | 14,1 cm | +4,2 cm |
| 7 | 0,412 s | 0,370 s | −43 ms | 20,9 cm | 16,8 cm | −4,1 cm |
| 8 | 0,435 s | 0,255 s | −180 ms | 23,2 cm | 8,0 cm | −15,3 cm |

Über die 7 Sprünge mit App-Höhe: Bias der Flugzeit −62 ms, MAE 82 ms. Bias der Höhe −6,2 cm, MAE 7,6 cm.

**Beobachtungen:**

- Die App misst die Flugzeit im Mittel **kürzer**, nicht wie vermutet länger. Die Erwartung beim Anlegen von `flightOffset` war also falsch.
- Die Streuung ist zu groß für eine feste Korrektur. Die größten Fehler (Sprung 4 und 8, je −15 cm) haben die Sprünge, bei denen die Füße in der Luft weit hochgezogen sind (Standbild vom höchsten Punkt). Vermutung: Beim Anziehen der Beine wirkt eine Kraft auf den Rumpf, der Kopf ist dann nicht mehr im freien Fall und |a| steigt in der Luft über 3,5 m/s². Der Detektor sieht dadurch einen späteren Absprung oder eine frühere Landung. Sprung 2 (Flug in der IMU kurz unterbrochen) passt in dasselbe Bild.
- Die Kontaktzeit im Video ist bei hochgezogenen Beinen ebenfalls keine saubere Referenz für die Schwerpunkthöhe. Die Formel setzt gleiche Haltung bei Absprung und Landung voraus.

**Konsequenzen:**

- `flightOffset` bleibt vorerst bei 0. Vor einem Fit braucht es Sprünge mit einheitlicher Technik: Counter-Movement-Jump, Hände an der Hüfte, Beine in der Luft gestreckt.
- Ursache geklärt, siehe nächster Abschnitt.
- 1 Person und 8 Sprünge sind nur ein Plausibilitätscheck, keine Evaluation.

### Session 2 und Ursache der Abweichung (Auswertung 15.11.2026)

Session 2 derselben Person (9 Sprünge, Video `PXL_20261113_172540690`) wurde genauso ausgewertet. Die Zuordnung ist wieder eindeutig: Die Abstände zwischen den Landungen stimmen auf 0,03 s mit der App überein. Über beide Sessions (17 Sprünge, 16 davon mit App-Höhe):

| | App (Stand 13.11.) | Variante: erste Unterschreitung |
| --- | --- | --- |
| Bias Flugzeit | −51 ms | +14 ms |
| MAE Flugzeit | 75 ms | 40 ms |
| Max. Fehler Flugzeit | 180 ms | 80 ms |
| Bias Höhe | −5,2 cm | +1,1 cm |
| MAE Höhe | 6,9 cm | 3,9 cm |
| Max. Fehler Höhe | 15,3 cm | 9,3 cm |

**Ursache (aus den Roh-CSVs):** Die Landung ist in allen Sprüngen sauber: Der Freifall endet direkt mit dem Aufprall. Das Problem liegt beim Absprung. Nach dem letzten Abdruck-Sample pendelt |a| 0,1–0,2 s lang zwischen etwa 2 und 9 m/s², bevor es dauerhaft unter 3,5 m/s² bleibt. Der Fix vom 13.11. verwirft Unterschreitungen unter 80 ms und setzt den Absprung deshalb an den Beginn der langen Freifallphase, also zu spät. Die Vermutung von oben, dass hochgezogene Beine den Flug in der Luft unterbrechen, bestätigt sich so nicht.

**Variante:** Absprung = erste Unterschreitung von 3,5 m/s² nach dem letzten Sample über 12,3 m/s², Landung unverändert. Höhere Absprung-Schwellen (5–8 m/s²) verbessern nichts (MAE 39–47 ms). Seit 15.11. in der App umgesetzt, siehe nächster Abschnitt.

### Umbau des Detektors (15.11.2026)

Absprung und Landung wie oben unter „Ablauf“ beschrieben. Die alte Regel, kurze Unterschreitungen als Vibration zu verwerfen, ist ersetzt: Ob eine Unterschreitung Vibration war, entscheidet jetzt das nächste Abdruck-Sample, nicht ihre Dauer.

**Prüfung:** Replay der drei Roh-CSVs vom 13.11. durch die App-Algorithmen (mit der Kalibrierung aus dem JSON, wie live). Das Replay reproduziert die alten App-Werte exakt. Mit dem neuen Detektor:

| | vorher | nachher |
| --- | --- | --- |
| Sprünge mit Höhe | 16 von 17 | 17 von 17 |
| Bias Flugzeit | −51 ms | +20 ms |
| MAE Flugzeit | 75 ms | 40 ms |
| Max. Fehler Flugzeit | 180 ms | 81 ms |

Die erste Aufnahme (ohne Video) liefert weiterhin genau die 3 Sprünge des Sprung-Tests, ohne zusätzliche Erkennungen in den Schritt-Phasen. Die größten Restfehler (−75 und −81 ms) sind die beiden Sprünge mit stark hochgezogenen Beinen. Die meisten anderen liegen bei +40 bis +55 ms.

**`flightOffset` bleibt bei 0.** Ein Offset von etwa 35 ms würde den MAE auf denselben Daten auf etwa 30 ms senken. Das wäre aber an derselben einen Person gefittet und ausgewertet. Erst fitten, wenn Sprünge mehrerer Personen mit einheitlicher Technik vorliegen (Plan unter Evaluationsplan).

**Verworfen:** Impuls-Methode (`h = v²/2g`) als zweite Schätzung. Die Abdruckphase ist bei ±2 g abgeschnitten (Maximum in den Aufnahmen 19,62 m/s²), die Geschwindigkeit wäre systematisch zu klein. Wieder prüfen, falls die IMU mit größerem Messbereich konfiguriert werden kann.

Werte, abgelesene Frames und Formeln liegen in einer Excel-Datei außerhalb des Repos (enthält Dateinamen der Videos). Die Rohdaten bleiben lokal.

## Verworfene Alternativen

- **Abhebegeschwindigkeit integrieren** (`h = v²/2g`): Die vertikale Beschleunigung wird während des Abdrucks aufintegriert. Das braucht eine saubere Lage- und Gravitationsschätzung, und gerade die Abdruckphase wird bei ±2 g abgeschnitten, was die Geschwindigkeit systematisch unterschätzt. Als zweite Schätzung für die Evaluation weiter interessant.
- **Doppelte Integration der Kopfbewegung:** Driftet schnell, und die Kopfhöhe ist nicht die Schwerpunkthöhe, weil Rumpf und Knie mitarbeiten.
- **ML-Regressor:** Ohne Datensatz nicht trainierbar. Erst sinnvoll, wenn die Flugzeit-Methode einen systematischen Restfehler zeigt.

## Bekannte Grenzen

- Landet jemand mit stark gebeugten Knien, wird die Flugzeit länger und die Höhe überschätzt. Das ist eine Eigenschaft der Methode, nicht des Sensors.
- Die Schwellen sind an einer einzigen Hardware-Aufnahme (1 Person) und synthetischen Signalen geprüft.
- Der tatsächliche Messbereich der OE2-IMU ist noch nicht überprüft. Die ±2 g stammen aus dem Prototyp.
- Bisher gibt es **keine Messung mit Referenz**. Ob die Flugzeit am Ohr systematisch zu lang ist, ist offen.

## Evaluationsplan

**Referenz:** Slow-Motion-Video mit 240 fps von der Seite, Kamera auf Fußhöhe. Flugzeit = Anzahl Frames zwischen dem letzten Frame mit Bodenkontakt und dem ersten Frame mit Bodenkontakt, geteilt durch 240 (Auflösung ≈ 4 ms, ca. 0,5 cm). Das ist kostenlos und in der Literatur gegen Kraftmessplatten validiert (My-Jump-Methode). Falls der Lehrstuhl eine Kontaktmatte hat, ist die besser.

**Ablauf je Person:** Counter-Movement-Jumps mit Händen an der Hüfte, 3 Höhenstufen (niedrig, mittel, maximal), je 5 Sprünge. Dazu ein paar Squat Jumps aus der Hocke und als Negativkontrolle Hüpfen auf der Stelle und Joggen.

**Metriken:**

- Mittlerer absoluter Fehler (MAE) und Bias der Höhe in cm, Bland-Altman-Diagramm
- Anteil der Sprünge mit gültiger Höhe (Abdeckung) und Anteil verpasster Sprünge
- Falsch erkannte Sprünge in den Negativkontrollen

**Vorgehen:** `flightOffset` auf einigen Personen fitten (Median der Flugzeit-Differenz), auf den übrigen auswerten. Die App bietet dafür schon den Study-Modus mit Referenzhöhe und exportiert Roh-CSV. Mit `dart run tool/replay_activity_trace.dart <session.csv>` lässt sich jede Aufnahme mit geänderten Parametern erneut auswerten.
