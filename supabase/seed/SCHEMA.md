# Übungs-Seed-Daten – Schema und Stilrichtlinie

Jede Übung ist ein JSON-Objekt. Dateien in `supabase/seed/exercises/*.json` enthalten jeweils ein JSON-Array von Übungen.
Die Daten werden per Skript in eine SQL-Migration übersetzt. Halte dich EXAKT an das Schema.

## Felder

| Feld | Typ | Pflicht | Beschreibung |
|---|---|---|---|
| slug | string | ja | kebab-case, nur a-z, 0-9, "-" (ä→ae, ö→oe, ü→ue, ß→ss). Eindeutig. |
| name | string | ja | Deutscher Anzeigename, z. B. "Schrägbankdrücken Maschine" |
| category | enum | ja | chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves, abs, forearms, adductors, cardio |
| equipment | enum | ja | machine, cable, barbell, dumbbell, bodyweight, smith_machine, bench, cardio, other |
| grip_id | enum/null | ja | Nur bei Kabelübungen (Kabelzug-Anbau): neutral_parallel, wide_lat_bar, close_v_grip, rope, single_handle, strap_handle, straight_bar, ez_bar, v_bar_triceps, ankle_strap. Sonst null. Empfohlener (einfachster) Griff. |
| grip_notes | string/null | ja | Freitext zum Griff bei Maschinen/Hanteln/Körpergewicht, z. B. "Neutrale oder pronierte Griffe, je nach Maschine; Handgelenke gerade". Bei Kabelübungen Empfehlung zur Griffbreite/Alternativgriff. null wenn nicht sinnvoll. |
| primary_muscles | string[] | ja | 1–2 IDs aus der Muskel-Liste |
| secondary_muscles | string[] | ja | 0–4 IDs aus der Muskel-Liste |
| description | string | ja | 1–2 sachliche Sätze: Was ist die Übung, wofür ist sie geeignet. |
| setup | string[] | ja | 3–6 Schritte: Startposition / Einstellung (Sitz, Polster, Gewicht, Griff, Fußposition). Jeder Schritt ein kurzer Satz. |
| execution | string[] | ja | 4–7 Schritte: Bewegungsablauf vom Start bis zur Rückführung. Jeder Schritt ein kurzer Satz. |
| range_of_motion | string | ja | 1–2 Sätze zum sinnvollen Bewegungsradius. |
| breathing | string | ja | 1–2 Sätze. Standard: Ausatmen in der konzentrischen (anstrengenden) Phase, Einatmen in der exzentrischen. |
| common_mistakes | string[] | ja | 3–5 typische Fehler, jeweils ein kurzer Satz. |
| tips | string[] | ja | 2–4 Hinweise (Tempo, Fokus, Progression, Alternativen). |
| cable_setup | object/null | ja | NUR bei equipment = "cable" (sonst null). Felder siehe unten. |
| image_url | string/null | nein | Nicht mehr verwendet: Gerätefotos wurden aus der App entfernt. Immer null. |
| machine_name | string/null | nein | Offizielle Gerätebezeichnung (z. B. DHZ Fitness "Incline Chest Press") |
| alternative_exercises | string[] | nein | Slugs alternativer Übungen am anderen Gerät (werden mit Foto verlinkt) |
| bodyweight_factor | number | nein | Nur bei equipment = "bodyweight": Anteil des Körpergewichts, der bewegt wird (0–2, Standard 1.0). Beispiele: Klimmzug/Dips 1.0, Liegestütz 0.65, Hyperextensions 0.6, Hanging Knee Raise 0.45. Daraus wird die reale Last berechnet (Körpergewicht × Anteil + Zusatzgewicht). |
| animation_source_url | string/null | nein | Seite mit einer Ausführungs-Animation (z. B. modusx.de). Wird nur verlinkt, nicht eingebettet oder kopiert. |
| variants | object[] | nein | Ausführungsvarianten derselben Übung (z. B. stehend/sitzend, Stange/Seil): `{ "name", "description", "source_url"? }`. Grundsatz: eine Übung je Bewegung, Unterschiede als Varianten erklären, nicht als eigene Übungen. |
| muscle_focus | string[] | ja | 2–4 Punkte "So triffst du den Muskel": nach aktuellem sportwissenschaftlichem Stand (Bewegungsradius, gedehnte Position, Ellenbogen-/Schulterführung, Tempo, typische Ausweichbewegung). Sachlich, keine Heilsversprechen. |
| requirements | string[] | ja | 1–4 Einträge "Das brauchst du": konkrete Ausstattung (Gerät, Hantelart, Bank, Griff, Stufe, Polster). Bei freien Übungen eindeutig, z. B. "Flachbank oder Hocker", "Kurzhanteln auf den Knien oder Langhantel mit Polster". |
| grip_alternatives | string[] | ja | Nur bei Kabelübungen: 0–3 alternative Griff-IDs (aus der grip_id-Liste), die ebenfalls gut funktionieren, z. B. statt Seil eine Stange. Bei Nicht-Kabelübungen leeres Array []. |

### Griffe (grip_id / grip_alternatives)

neutral_parallel (Neutraler Parallelgriff / MAG-Griff), wide_lat_bar (Latzugstange, breit), close_v_grip (enger V-Griff / Triangelgriff), rope (Seil), single_handle (Einzelgriff / D-Griff), strap_handle (Handschlaufe, weicher Schlaufengriff), straight_bar (gerade kurze Stange, Bizeps-Trizeps-Stange), ez_bar (SZ-Stange), v_bar_triceps (Trizeps-V-Stange), ankle_strap (Fußschlaufe).

Grundsatz: Als grip_id den Griff eintragen, der am einfachsten und schulterfreundlichsten ist; das Seil nur dort als Standard, wo es klar überlegen ist (Face Pull). Alternativen in grip_alternatives.

### cable_setup (nur bei Kabelübungen, alle Felder Strings)

```
{
  "cable": "Welcher Kabelzug (z. B. Kabelturm / Doppelkabelzug / integrierter Latzug / Kabelzug einarmig)",
  "seat_position": "Nur bei festen Stationen (Latzug-Station): Sitz-/Polstereinstellung; dann darf height leer sein",
  "height": "Rollenhöhe EXPLIZIT: eines von \"ganz oben\", \"über Kopfhöhe\", \"Schulterhöhe\", \"Brusthöhe\", \"Hüfthöhe\", \"Kniehöhe\", \"ganz unten\" – plus kurzer Begründung",
  "grip_width": "Griffbreite / Handposition",
  "body_position": "Körperposition (Stand, Sitz, Abstand, Neigung, Rumpfspannung)",
  "foot_position": "Fußposition",
  "movement_direction": "Bewegungsrichtung",
  "elbow_position": "Ellenbogenposition während der Bewegung",
  "end_position": "Endposition / Kontraktion",
  "return": "Rückführung (Tempo, Kontrolle, Endpunkt)"
}
```

## Muskel-IDs (nur diese verwenden)

chest, upper_chest, front_delts, side_delts, rear_delts, traps, lats, upper_back, mid_back, lower_back,
biceps, triceps, forearms, abs, obliques, quads, hamstrings, glutes, calves, adductors, abductors

Hinweise für Cardio-Geräte (category "cardio", equipment "cardio"): Dauer wird in der App als Wiederholungen (Minuten) eingetragen, Gewicht bleibt 0 bzw. steht für Widerstandsstufe; das in den Tipps erwähnen. cable_setup = null, grip_id = null.

Hinweise:
- Bei Zugübungen (Latzug, Rudern, Curls) `forearms` als sekundär aufnehmen.
- Bei Druckübungen Brust: `triceps` und `front_delts` sekundär.
- Bei Beinpresse/Hackenschmidt/Kniebeuge: primär `quads`, sekundär `glutes`, ggf. `hamstrings`.
- Bei Hip Thrust: primär `glutes`, sekundär `hamstrings`.
- Bei RDL: primär `hamstrings`, `glutes`; sekundär `lower_back`, `forearms`.

## Stilrichtlinie

- Sprache: Deutsch, sachlich, kurz, Sie-/Du-frei formulieren (Infinitiv- oder Imperativstil: "Rücken anlehnen.", "Griffe kontrolliert nach vorne drücken.").
- Keine Emojis. Keine Superlative. Keine Behauptung, dass eine Übung für jeden optimal ist.
- Keine riskanten Anweisungen (kein "bis zum Muskelversagen", kein "Maximalgewicht", kein Ruck).
- Fachlich korrekt: Schulterblätter, Rumpfspannung, Bewegungsradius, Kontrolle in der exzentrischen Phase.
- Jede Übung muss ALLE Pflichtfelder haben. Arrays niemals leer (außer secondary_muscles darf leer sein).
- Gültiges JSON (doppelte Anführungszeichen, keine Kommentare, keine abschließenden Kommas).

## Beispiel 1 (Maschine)

```json
{
  "slug": "schraegbankdruecken-maschine",
  "name": "Schrägbankdrücken Maschine",
  "category": "chest",
  "equipment": "machine",
  "grip_id": null,
  "grip_notes": "Pronierte Griffe (Handflächen nach vorne) oder neutrale Griffe, je nach Maschine. Handgelenke gerade halten.",
  "primary_muscles": ["upper_chest", "chest"],
  "secondary_muscles": ["triceps", "front_delts"],
  "description": "Geführte Druckbewegung in Schrägposition, die vor allem den oberen Anteil der Brust belastet. Gut geeignet als erste Druckübung im Oberkörpertraining.",
  "setup": [
    "Sitz so einstellen, dass die Griffe ungefähr auf Höhe der mittleren bis oberen Brust liegen.",
    "Rücken und Kopf vollständig an das Polster anlehnen.",
    "Füße flach auf den Boden stellen.",
    "Schulterblätter kontrolliert nach hinten und unten ziehen.",
    "Griffe fassen, Handgelenke gerade, Ellenbogen leicht unterhalb der Griffe."
  ],
  "execution": [
    "Griffe kontrolliert nach vorne-oben drücken.",
    "Ellenbogen am Ende nicht aggressiv durchstrecken.",
    "Spannung in der Brust halten, Schulterblätter bleiben hinten.",
    "Gewicht langsam und kontrolliert zurückführen.",
    "In der Endposition leichte Dehnung der Brust spüren, ohne dass das Gewicht aufsetzt.",
    "Nächste Wiederholung ohne Schwung beginnen."
  ],
  "range_of_motion": "Voller Bewegungsradius, soweit die Schultern schmerzfrei bleiben. In der unteren Position die Griffe etwa auf Brusthöhe bringen, oben kurz vor dem Durchstrecken stoppen.",
  "breathing": "Beim Drücken ausatmen, beim Zurückführen einatmen.",
  "common_mistakes": [
    "Schultern rollen beim Drücken nach vorne.",
    "Sitz zu niedrig, Griffe liegen auf Schulterhöhe.",
    "Gewicht wird mit Schwung aus der unteren Position gedrückt.",
    "Ellenbogen werden am Ende hart durchgestreckt.",
    "Rücken löst sich vom Polster."
  ],
  "tips": [
    "Exzentrische Phase etwa zwei Sekunden lang kontrollieren.",
    "Erst dann Gewicht erhöhen, wenn alle Sätze im oberen Wiederholungsbereich sauber ausgeführt werden.",
    "Wenn die Schultern unangenehm belastet sind, Sitz etwas höher stellen oder Griffweite ändern."
  ],
  "cable_setup": null
}
```

## Beispiel 2 (Kabel)

```json
{
  "slug": "neutraler-latzug",
  "name": "Neutraler Latzug",
  "category": "back",
  "equipment": "cable",
  "grip_id": "neutral_parallel",
  "grip_notes": "Neutraler Parallelgriff (Handflächen zeigen zueinander), etwa schulterbreit. Alternativ: breiter Latzuggriff für mehr Betonung der äußeren Lat-Anteile.",
  "primary_muscles": ["lats"],
  "secondary_muscles": ["biceps", "upper_back", "forearms", "rear_delts"],
  "description": "Vertikale Zugübung am Latzug mit neutralem Griff, die den Latissimus über einen großen Bewegungsradius belastet. Schulterfreundliche Variante des Latzugs.",
  "setup": [
    "Oberschenkelpolster so einstellen, dass die Beine fest fixiert sind.",
    "Neutralen Parallelgriff am oberen Kabel einhängen.",
    "Griff fassen, hinsetzen und Oberschenkel unter das Polster bringen.",
    "Oberkörper aufrecht, leicht nach hinten geneigt, Brust leicht angehoben.",
    "Arme gestreckt, Schultern bewusst nach unten ziehen, bevor die Bewegung beginnt."
  ],
  "execution": [
    "Griff in Richtung obere Brust ziehen, Ellenbogen führen die Bewegung nach unten.",
    "Schulterblätter nach unten und zusammen ziehen.",
    "In der Endposition kurz halten, Griff befindet sich etwa auf Höhe des Kinns bis der oberen Brust.",
    "Gewicht langsam zurückführen, Arme kontrolliert strecken.",
    "Schultern am oberen Ende leicht nach oben kommen lassen, um den Lat zu dehnen.",
    "Ohne Schwung die nächste Wiederholung beginnen."
  ],
  "range_of_motion": "Von vollständig gestreckten Armen bis der Griff etwa auf Höhe des Kinns bzw. der oberen Brust ist. Nicht bis zum Bauch ziehen.",
  "breathing": "Beim Ziehen ausatmen, beim Strecken der Arme einatmen.",
  "common_mistakes": [
    "Oberkörper wird stark nach hinten gelehnt und die Bewegung mit Schwung ausgeführt.",
    "Schultern bleiben während des Zugs oben am Ohr.",
    "Griff wird mit den Armen statt mit den Ellenbogen geführt.",
    "Gewicht fällt nach oben zurück, keine Kontrolle in der exzentrischen Phase.",
    "Ellenbogen weichen weit nach hinten aus, sodass der Rücken rund wird."
  ],
  "tips": [
    "Daumen auf die Griffe legen statt zu umschließen, um weniger mit den Unterarmen zu arbeiten.",
    "Vorstellen, die Ellenbogen in die Hosentaschen zu ziehen.",
    "Die exzentrische Phase bewusst zwei bis drei Sekunden lang ausführen."
  ],
  "cable_setup": {
    "cable": "Kabelturm mit Latzug-Station oder integrierter Latzug",
    "height": "Rolle ganz oben",
    "grip_width": "Schulterbreit, neutral (Handflächen zueinander)",
    "body_position": "Aufrecht sitzend, leichte Rücklage von etwa 10 bis 20 Grad, Brust angehoben, Rumpf stabil",
    "foot_position": "Füße flach auf dem Boden, Oberschenkel unter dem Polster fixiert",
    "movement_direction": "Vertikal von oben nach unten in Richtung obere Brust",
    "elbow_position": "Ellenbogen zeigen nach unten und leicht nach vorne, bleiben nah am Körper",
    "end_position": "Griff auf Höhe des Kinns bis der oberen Brust, Schulterblätter nach unten und zusammengezogen",
    "return": "Langsam und kontrolliert bis zur vollen Armstreckung, Schultern am Ende leicht nach oben kommen lassen"
  }
}
```
