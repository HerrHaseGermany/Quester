## Changelog

### 0.5.3

- Inventarsperre automatisch nach tatsächlicher Entlastung lösen und offene Questdialoge fortsetzen.
- Unveränderte Inventar-Events und verschobene Stapel erzeugen keine neuen Versuche.
- Erneut fehlgeschlagene Versuche pausieren wieder; geschlossene Dialoge werden nicht geöffnet.

### 0.5.2

- Automatik bei Inventar-/Questlogfehlern und wiederholten Aktionen ohne Erfolgsbestätigung anhalten.
- Wartende Aktionen verwerfen; Sperre bleibt über Dialogwechsel hinweg aktiv.
- `/quester resume` zum bewussten Fortsetzen nach Beheben des Fehlers.

### 0.5.1

- Rechtsklick auf den Griff klappt die Ziel-Icons ein oder aus; der Griff bleibt sichtbar.
- Zustand wird gespeichert, Änderungen im Kampf werden bis Kampfende aufgeschoben.

### 0.5.0

- Automatische Questabgabe einschließlich Auswahl fertiger Quests und Abholen eindeutiger Belohnungen.
- Annahme und Abgabe nach Dialogaufbau ausführen; veraltete Aktionen beim Schließen verwerfen.
- `/quester auto on/off` und `/quester turnin`; graue Quests standardmäßig mit auswählen.
- Mehrere Auswahlbelohnungen und Geldkosten bleiben manuell; Shift pausiert beide Funktionen.

### 0.4.2

- Kompakte Zielleiste mit dunklem WoW-Hintergrund und dezent goldenem Rahmen.
- Grafischer Griff ersetzt das vom Client nicht dargestellte Unicode-Zeichen.

### 0.4.1

- Tooltip-Fehler beim Überfahren der Ziel-Icons behoben: Der Texthelfer gibt nur den Text statt zusätzlich der Ersetzungsanzahl zurück.
- Regressionstest führt die Tooltip-OnEnter- und OnLeave-Handler aus.

### 0.4.0

- NPC-Namen für Sammel- und Tötungsziele aus strukturierten Forever-Tooltips lernen.
- Eindeutiger Abgleich von Quest-ID und offenem Zieltext; erledigte oder mehrdeutige Ziele ausschließen.
- Zuordnungen nach NPC-ID, Client-Build und Sprache speichern; echte Namen vor Texterkennung bevorzugen.
- Regressionstests mit dem gemeldeten Fall Rascally Rodents / Stolen Book / Kobold Worker.

### 0.3.1

- `/quester inspect` zeigt eine kopierbare NPC-, Tooltip-, Questlog- und Karten-Diagnose.
- Fehlende moderne APIs werden kenntlich gemacht; Tooltip- und Questlog-Fallbacks für ältere Clients.
- Diagnosefenster nur auf ausdrücklichen Befehl, ohne Änderungen an der Zielerkennung.

### 0.3.0

- Großes Questfenster durch kompakte, anklickbare Ziel-Icons ersetzt; Details nur im Tooltip.
- Englische Mehrzahlformen über gezielte Wortzuordnung normalisiert, inklusive Kobold Workers → Kobold Worker.
- Geschützte Zielbuttons mit Aufschub von Layout- und Zieländerungen im Kampf.
- Rohdaten zur Fehlersuche über `/quester debug` verfügbar.

### 0.2.0

- Verschiebbares Questfenster mit Originaltexten, Gegnernamen, Erkennungsstatus und Makro-Vorschau.
- Globales Zielmakro mit Migration der alten Charakterkopie nach erfolgreicher Erstellung.
- Erweiterte Erkennung für nummerierte Platzhalter, Farbmarkierungen und einfache Zählertexte.
- Fenster bleibt bei Kampf und deaktivierter Makro-Aktualisierung aktuell.

### 0.1.1

- Questlog-Abfragen verwenden bevorzugt C_QuestLog; ältere globale APIs bleiben als Fallback erhalten.
- Regressionstest für Clients ohne globale Questlog-Funktionen ergänzt.

### 0.1.0

- Automatische Questannahme mit Shift-Pause und optionaler Auswahl grauer Quests.
- Charakter-Makro für offene Gegnerziele, mit Aktualisierung nach Queständerungen.
- Kampfaufschub, Makro-Platzlimit und gespeicherte Einstellungen.
