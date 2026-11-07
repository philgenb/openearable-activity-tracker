# Sprunghöhe

Stand: 07.11.2026. Code: [`activity_engine.dart`](../../open_wearable/lib/apps/activity_tracker/models/activity_engine.dart), Klasse `_JumpDetector`. Grundlage ist Phils Prototyp vom 06.11.2026.

## Ansatz: Flugzeit

Während der Flugphase ist der Kopf im freien Fall, der Beschleunigungssensor misst dann fast 0 g. Aus der Flugzeit `t` folgt die Höhe des Körperschwerpunkts:

```text
h = g · t² / 8
```

Das ist dieselbe Methode, die Kontaktmatten und Slow-Motion-Apps nutzen. Sie setzt voraus, dass Absprung- und Landehaltung gleich sind (gestreckte Beine).

**Ablauf im Detektor:**

1. **Bereit:** mindestens 0,5 s ruhig stehen (|a| innerhalb ±0,8 m/s² um g, Gyro < 0,3 rad/s).
2. **Abdruck:** innerhalb von 0,7 s nach der Ruhephase |a| > 12,3 m/s² (≈ 1,25 g).
3. **Absprung:** innerhalb von 0,5 s nach dem Abdruck fällt |a| unter 3,5 m/s² (≈ 0,36 g).
4. **Landung:** |a| steigt wieder über 3,5 m/s². Innerhalb von 120 ms muss ein Aufprall > 12,3 m/s² folgen, sonst gibt es keine Höhe.
5. Danach 0,8 s Sperrzeit.

Die Ruhephase vor dem Sprung verhindert, dass die kurzen Flugphasen beim Joggen als Sprünge zählen.

## Parameter

| Parameter | Wert | Bedeutung |
| --- | --- | --- |
| Freifall-Schwelle | 3,5 m/s² | Absprung und Landung |
| Abdruck/Aufprall | 12,3 m/s² | Abdruck vor dem Sprung, Bestätigung der Landung |
| Gültige Flugzeit | 0,12–0,85 s | entspricht ca. 1,8–89 cm |
| Mindestrate | 40 Hz | langsamere Samples → keine Höhe |
| `flightOffset` | 0 s | systematische Korrektur, wird gegen die Referenz gefittet |

## Änderungen gegenüber dem Prototyp (07.11.2026)

**1. Abgeschnittene Spitzen machen die Höhe nicht mehr ungültig.** Der Prototyp verwarf jeden Sprung, bei dem eine Achse ±2 g erreichte. Bei der Landung erreicht der Kopf aber typischerweise mehrere g, damit hätte fast jeder echte Sprung keine Höhe bekommen. In die Höhe gehen nur die Zeitpunkte ein, an denen |a| die Schwelle von 0,36 g kreuzt. Ob die Spitze danach bei 2 g abgeschnitten wird, ändert an diesen Zeitpunkten nichts. Für Schritte und Wiederholungen bleibt die Clipping-Erkennung unverändert.

**2. Absprung und Landung werden zwischen zwei Samples interpoliert.** Bei 100 Hz lag der Zeitpunkt bisher bis zu 10 ms daneben, pro Ende. Die Höhe reagiert darauf empfindlich: `dh/dt = g·t/4`, bei 0,5 s Flugzeit sind 10 ms also rund 1,2 cm. Jetzt wird linear zwischen dem letzten Sample über und dem ersten unter der Schwelle interpoliert (und umgekehrt bei der Landung). Ein Test mit synthetischem Signal und vier verschiedenen Abtastphasen zeigt: Mit Interpolation liegt die Flugzeit innerhalb 1 ms, ohne lag sie 7 ms daneben.

**3. Kalibrier-Knopf `flightOffset`.** Am Ohr misst der Detektor die Flugzeit vermutlich etwas zu lang: Die 0,36-g-Schwelle wird kurz vor dem Abheben der Zehen unterschritten, und der Landestoß kommt am Kopf leicht verzögert an. Beides führt zu überschätzten Höhen. Wie groß der Fehler ist, kann nur ein Vergleich mit einer Referenz zeigen. Bis dahin steht der Wert auf 0.

## Verworfene Alternativen

- **Abhebegeschwindigkeit integrieren** (`h = v²/2g`): Die vertikale Beschleunigung wird während des Abdrucks aufintegriert. Das braucht eine saubere Lage- und Gravitationsschätzung, und gerade die Abdruckphase wird bei ±2 g abgeschnitten, was die Geschwindigkeit systematisch unterschätzt. Als zweite Schätzung für die Evaluation weiter interessant.
- **Doppelte Integration der Kopfbewegung:** Driftet schnell, und die Kopfhöhe ist nicht die Schwerpunkthöhe, weil Rumpf und Knie mitarbeiten.
- **ML-Regressor:** Ohne Datensatz nicht trainierbar. Erst sinnvoll, wenn die Flugzeit-Methode einen systematischen Restfehler zeigt.

## Bekannte Grenzen

- Landet jemand mit stark gebeugten Knien, wird die Flugzeit länger und die Höhe überschätzt. Das ist eine Eigenschaft der Methode, nicht des Sensors.
- Die Schwellen und das 0,7-s-Fenster nach der Ruhephase sind nur an synthetischen Signalen geprüft. Bei sehr langsamer Ausholbewegung kann der Sprung durchrutschen.
- Der tatsächliche Messbereich der OE2-IMU ist noch nicht überprüft. Die ±2 g stammen aus dem Prototyp.
- Bisher gibt es **keine Messungen mit echter Hardware**.

## Evaluationsplan

**Referenz:** Slow-Motion-Video mit 240 fps von der Seite, Kamera auf Fußhöhe. Flugzeit = Anzahl Frames zwischen dem letzten Frame mit Bodenkontakt und dem ersten Frame mit Bodenkontakt, geteilt durch 240 (Auflösung ≈ 4 ms, ca. 0,5 cm). Das ist kostenlos und in der Literatur gegen Kraftmessplatten validiert (My-Jump-Methode). Falls der Lehrstuhl eine Kontaktmatte hat, ist die besser.

**Ablauf je Person:** Counter-Movement-Jumps mit Händen an der Hüfte, 3 Höhenstufen (niedrig, mittel, maximal), je 5 Sprünge. Dazu ein paar Squat Jumps aus der Hocke und als Negativkontrolle Hüpfen auf der Stelle und Joggen.

**Metriken:**

- Mittlerer absoluter Fehler (MAE) und Bias der Höhe in cm, Bland-Altman-Diagramm
- Anteil der Sprünge mit gültiger Höhe (Abdeckung) und Anteil verpasster Sprünge
- Falsch erkannte Sprünge in den Negativkontrollen

**Vorgehen:** `flightOffset` auf einigen Personen fitten (Median der Flugzeit-Differenz), auf den übrigen auswerten. Die App bietet dafür schon den Study-Modus mit Referenzhöhe und exportiert Roh-CSV. Mit `dart run tool/replay_activity_trace.dart <session.csv>` lässt sich jede Aufnahme mit geänderten Parametern erneut auswerten.
