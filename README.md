# Quester

Leichter Questhelfer für den installierten Classic-Beta-Client 1.60.1.

## Erste Verwendung

1. WoW neu starten, falls das Addon noch nicht in der Addonliste erscheint; sonst `/reload`.
2. Quester in der Addonliste aktivieren.
3. Unter `/macro` → **Allgemeine Makros** das globale Makro **QuesterTarget** auf die Aktionsleiste ziehen.
4. Die kompakte Leiste zeigt ein 30-Pixel-Icon pro erkanntem Gegnerziel. Linksklick visiert das Ziel an; Name und Questfortschritt stehen im Tooltip. Am Griff links verschieben, per Rechtsklick auf den Griff ein- und ausklappen. Der Griff bleibt eingeklappt sichtbar; der Zustand wird gespeichert. `/quester hide` blendet die gesamte Leiste aus, `/quester` zeigt sie wieder.
5. Für Sammelquests einen passenden Gegner anvisieren oder mit der Maus darüberfahren. Nennt sein Tooltip ein eindeutig zuordenbares, offenes Questziel, erscheint der echte NPC-Name als Ziel-Icon und im Makro.
6. Questgeber ansprechen: verfügbare Quests werden ausgewählt und angenommen. Mit gedrückter **Shift-Taste** bleibt die Annahme manuell.

Das Makro wird bei Queständerungen aktualisiert, im Kampf erst nach Kampfende. Ein Klick sucht offene Gegnerziele in Questlog-Reihenfolge und stoppt beim ersten vorhandenen lebenden Ziel. Dabei wird die vorherige Zielauswahl aufgehoben. Das Makro startet keinen Angriff.

## Befehle

| Befehl | Wirkung |
| --- | --- |
| `/quester` oder `/quester show` | Ziel-Icons einblenden |
| `/quester hide` | Ziel-Icons ausblenden |
| `/quester inspect` | Kopierbare Diagnose für den anvisierten NPC öffnen |
| `/quester debug` | Original-Zieltexte und erkannte Namen im Chat ausgeben |
| `/quester status` | Hilfe, Einstellungen und Anzahl ausgelassener Ziele |
| `/quester auto on` / `/quester auto off` | Annahme und Abgabe ausdrücklich ein-/ausschalten |
| `/quester resume` | Fehlersperre lösen; danach den Questgeber erneut ansprechen |
| `/quester turnin` | Nur automatische Abgabe umschalten |
| `/quester auto` | Automatische Annahme und Abgabe gemeinsam umschalten |
| `/quester macro` | Makro-Aktualisierung umschalten; vorhandenes Makro bleibt erhalten |
| `/quester trivial` | Graue Quests im Auswahlfenster ebenfalls auswählen |
| `/quester update` | Makro-Aktualisierung anfordern |

Questannahme, Questabgabe, Auswahl grauer Quests und Makro-Aktualisierung sind standardmäßig aktiv. Bereits ausdrücklich gespeicherte Einstellungen bleiben erhalten. Einstellungen und Makro werden accountweit gespeichert. Das Makro wird jeweils mit den Zielen des aktuell eingeloggten Charakters befüllt. Der Name `QuesterTarget` ist für dieses Addon reserviert. Eine alte Charakterkopie wird erst nach erfolgreicher Erstellung des globalen Makros entfernt. Danach das globale Makro einmal neu auf die Aktionsleiste ziehen. Bei vollem globalem Makrospeicher bleibt die alte Kopie erhalten.

## Grenzen der ersten Version

- Gegnernamen stammen aus lokalisierten Blizzard-Texten für offene Tötungsziele, einschließlich nummerierter Platzhalter und einfacher Zählertexte wie `Waldwolf: 0/8`. Häufige englische Mehrzahlformen werden über eine begrenzte Zuordnung normalisiert, etwa `Kobold Workers` zu `Kobold Worker`. Andere NPC-Namen bleiben unverändert. Für Sammel- und Tötungsziele werden eindeutige NPC-Tooltip-Zuordnungen bevorzugt. Ohne eine solche Beobachtung bleiben Sammelziele unbekannt. Weltobjekte sind keine anvisierbaren Gegner. `/quester debug` zeigt die Zieltexte bei Bedarf; eine externe Questdatenbank wird nicht benötigt.
- Es werden die durch die Questlog-API gelieferten Einträge berücksichtigt; eingeklappte Kategorien können abhängig vom Client Ziele ausblenden. Bei fehlenden Zielen Kategorien aufklappen und `/quester update` ausführen.
- Das Makro ist auf 255 Bytes begrenzt. Überzählige Ziele werden ausgelassen; `/quester status` zeigt deren Anzahl. Über die einzelnen Icons lassen sich auch Ziele außerhalb dieses Limits anvisieren. Abgeschlossene Ziele machen wieder Platz.
- Ein freier globaler Makroplatz ist erforderlich. Die Ausführung erfolgt durch deinen Tastendruck bzw. Klick.
- Graue Quests werden standardmäßig ebenfalls ausgewählt; `/quester trivial` schaltet dies um. Öffnest du deren Questdetail selbst, greift die automatische Annahme ebenfalls; Shift pausiert sie.
- Abgabebereite Quests werden beim NPC geöffnet und abgeschlossen. Ohne Auswahlbelohnung oder mit genau einer Auswahl wird die Belohnung automatisch abgeholt. Bei mehreren Auswahlbelohnungen und bei Geldkosten bleibt die manuelle Auswahl bzw. Bestätigung erhalten. Shift pausiert Annahme und Abgabe.

## Prüfung im Spiel

Questgeber mit mehreren Quests öffnen, Shift-Unterbrechung prüfen, eine Gegnerquest annehmen und das Makro testen. Nach Fortschritt, Abschluss oder Abbruch muss sich der Makrotext anpassen. Im Kampf muss der Text unverändert bleiben und nach Kampfende aktualisiert werden. `/console scriptErrors 1` aktiviert Lua-Fehleranzeigen.

API-Referenz: [Blizzard QuestLog-Dokumentation](https://github.com/Gethe/wow-ui-source/blob/classic_beta/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua) und [GossipInfo-Dokumentation](https://github.com/Gethe/wow-ui-source/blob/classic_beta/Interface/AddOns/Blizzard_APIDocumentationGenerated/GossipInfoDocumentation.lua), als Spiegel des Blizzard-UI-Quellcodes.

Die Icons verwenden geschützte WoW-Aktionsbuttons. Im Kampf bleiben die bestehenden Icons anklickbar; Änderungen an Zielen, Position oder Sichtbarkeit erfolgen erst danach. Makro und Icons teilen dieselbe Namenserkennung. Ohne Gegnerziele bleibt nur der kleine Griff sichtbar. Die Symbole sind nummerierte Ziel-Icons, keine NPC-Porträts.

## Diagnose für Sammelquest-Gegner

Nach `/reload` einen möglichen Beutegegner einer offenen Sammelquest anvisieren und `/quester inspect` ausführen. Den markierten Bericht mit Strg+C beziehungsweise Cmd+C kopieren. Das Diagnosefenster öffnet sich ausschließlich auf diesen Befehl; Escape schließt es.

Der Bericht enthält Client-Build, Sprache, NPC-Name und NPC-ID, rohe Tooltip-Zeilen einschließlich unbekannter Beta-Felder, Questlog-Ziele und verfügbare Quest-Kartendaten. Fehlende oder fehlschlagende APIs werden kenntlich gemacht. Ohne moderne Tooltip-API wird ein separater Tooltip zum Auslesen verwendet. Bei noch nicht geladenen Zieltexten nach kurzem Darüberfahren erneut prüfen.

Die Diagnose-Momentaufnahme bleibt nur bis zum Reload im Speicher. Die automatische Tooltip-Erkennung läuft unabhängig vom Diagnosefenster.

## Gelernte Questziele

Quester beobachtet Zielwechsel und Mouseover. Im Forever-Tooltip verknüpft eine Questüberschrift (Typ 17, Quest-ID) die folgenden Zielzeilen (Typ 8) mit einer Quest. Eine Zuordnung wird nur gespeichert, wenn genau ein offenes Sammel- oder Tötungsziel dieser aktiven Quest nach Entfernen des Fortschrittszählers zum Tooltiptext passt. Der NPC muss angreifbar sein; sein tatsächlicher Name und seine NPC-ID werden verwendet.

Die Zuordnungen werden accountweit in `QuesterDB.learnedTargets` nach Client-Build und Sprache getrennt gespeichert. Mehrere NPC-Arten je Ziel sind möglich. Erledigte oder abgebrochene Quests liefern keine aktiven Makroziele mehr; die Zuordnung bleibt für eine erneute Annahme bzw. andere Charaktere gespeichert. Bei neuen Beta-Builds wird neu gelernt.

Es wird die vom Spiel angezeigte Questzugehörigkeit gelernt, keine Dropchance oder vollständige Beutetabelle. Unbekannte NPC-Arten werden erst nach einer Begegnung erkannt. Fehlende, widersprüchliche oder nicht zugängliche Tooltipdaten erzeugen keine Zuordnung. Makro und geschützte Icons aktualisieren sich im Kampf erst nach Kampfende.

Wenn Annahme oder Abgabe ausgeschaltet war: `/quester auto on`, dann den NPC erneut ansprechen. `/quester debug` zeigt zusätzlich die letzte Automationsaktion. Dialogaktionen werden kurz verzögert und beim Schließen oder Wechsel der Quest verworfen.

## Schutz vor fehlgeschlagenen Questschleifen

Meldet der Client nach einer automatischen Aktion ein volles Inventar/Questlog oder ein Gegenstandslimit, hält Quester die Annahme und Abgabe an. Zusätzlich wird dieselbe Aktion für dieselbe Quest ohne bestätigten Erfolg nicht wiederholt. Der Abbruch verwirft wartende Aktionen und meldet sich einmal im Chat.

Nach tatsächlicher Entlastung des Inventars (mehr freie Plätze oder weniger Gegenstände) bzw. des Questlogs wird die Sperre automatisch aufgehoben. Ein noch offener Questdialog wird fortgesetzt; bei geschlossenem Dialog genügt das nächste normale Ansprechen des NPCs. Unveränderte Inventar-Events und bloßes Verschieben von Stapeln lösen keinen neuen Versuch aus. Scheitert der Versuch erneut, pausiert Quester bis zur nächsten Entlastung. Im Kampf wird die Fortsetzung bis Kampfende aufgeschoben. `/quester resume` bleibt als optionaler manueller Reset verfügbar.
