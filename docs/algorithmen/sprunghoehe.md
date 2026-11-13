# Sprunghöhe

Stand: 13.11.2026. Code: [`activity_engine.dart`](../../open_wearable/lib/apps/activity_tracker/models/activity_engine.dart), Klasse `_JumpDetector`. Grundlage ist Phils Prototyp vom 06.11.2026.

## Ansatz: Flugzeit

Während der Flugphase ist der Kopf im freien Fall, der Beschleunigungssensor misst dann fast 0 g. Aus der Flugzeit `t` folgt die Höhe des Körperschwerpunkts:

```text
h = g · t² / 8
```

Das ist dieselbe Methode, die Kontaktmatten und Slow-Motion-Apps nutzen. Sie setzt voraus, dass Absprung- und Landehaltung gleich sind (gestreckte Beine).

**Ablauf im Detektor:**

1. **Bereit:** Im Sprung-Test immer. Im Schritt-Modus erst nach mindestens 0,5 s ruhig stehen (|a| innerhalb ±0,8 m/s² um die kalibrierte Schwerkraft, Gyro < 0,3 rad/s).
2. **Abdruck:** innerhalb von 2 s nach der Ruhephase |a| > 12,3 m/s² (≈ 1,25 g).
3. **Absprung:** innerhalb von 0,5 s nach dem Abdruck fällt |a| unter 3,5 m/s² (≈ 0,36 g). Unterschreitungen, die kürzer als 80 ms dauern, gelten als Vibration im Abdruck und werden ohne Sperrzeit verworfen.
4. **Landung:** |a| steigt wieder über 3,5 m/s². Innerhalb von 120 ms muss ein Aufprall > 12,3 m/s² folgen, sonst gibt es keine Höhe.
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
| Mindestflugzeit | 80 ms | kürzere Unterschreitungen = Vibration |
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
