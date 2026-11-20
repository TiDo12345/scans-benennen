# scans-benennen

Ein kleiner Docker-Dienst, der neue Rohscans automatisch sinnvoll benennt:

`20261007_185514_Report_0001.pdf` → `2026-10-07 Stadtwerke Musterstadt Jahresabrechnung Strom 2025.pdf`

Gedacht für einen Scanner, der PDFs in einen Netzwerkordner legt (z. B. auf einem NAS). Der Dienst liest die
ersten Seiten per Texterkennung, lässt die Claude-API Datum, Absender und Betreff bestimmen und benennt die
Datei um. Ist er sich nicht sicher, bleibt die Datei liegen und er sagt Bescheid.

Läuft seit November 2026 auf einer QNAP TS-464 (Container Station), sollte aber auf jedem Linux-Rechner mit
Docker laufen. Regeln und Beispiele sind auf deutsche Briefe und Belege zugeschnitten.

## Ablauf

| Schritt | Was passiert |
| --- | --- |
| 1. Suchen | alle 15 s: Rohscans (`*_Report_NNNN.pdf`) im Scan-Ordner und seinen direkten Unterordnern (z. B. ein Ordner je Person; nicht `_…`, `.…`, `@…`, `#…`). Die Datei muss 15 s und zwei Durchläufe lang unverändert sein, damit der Scanner sicher fertig ist. Ein Scan ist meist nach 30–60 s umbenannt |
| 2. Lesen | `pdftotext`, bei Scans ohne Textebene lokale OCR (OCRmyPDF/Tesseract, Deutsch), erste 2 Seiten (`SEITEN`). Kopfüber oder quer eingelegte Seiten werden gedreht, schiefe gerade gerichtet. Das Original bleibt unverändert |
| 3. Benennen | nur der erkannte Text geht an die Claude-API (strukturierte JSON-Antwort): Dokumentdatum, Absender, Betreff, sicher ja/nein |
| 4. Umbenennen | wenn sicher: umbenennen, nie überschreiben (bei gleichem Namen ` (2)`), Zeile ins Protokoll `daten/umbenennungen.csv` (für `undo`) |
| Unklar | Datei bleibt liegen, daneben eine `.txt` mit dem Grund, optional eine ntfy-Meldung. Kein erneuter Versuch, solange die Datei unverändert ist |
| Fehler | API nicht erreichbar, Rate-Limit oder überlastet: der nächste Durchlauf versucht es erneut. Andere Fehler betreffen nur diese eine Datei |

**Dateiname:** `JJJJ-MM-TT Absender Betreff.pdf`

- **Datum:** Brief-, Bescheid- oder Rechnungsdatum aus dem Text. Fehlt es oder liegt es nach dem Scan-Datum, gilt das Scan-Datum.
- **Absender:** kurz und wiedererkennbar. Firmen, Versicherungen und Praxen nur mit dem prägenden Namen, ohne Rechtsform und Branchenwort („Procar Automobile GmbH & Co. KG“ → „Procar“), Ärzte mit Titel („Dr. Müller“), Behörden, Kassen, Banken und Kliniken mit Ort („Finanzamt Musterstadt“). Gängige Abkürzungen werden genutzt (TK, AOK, Kfz, AGB …).
- **Betreff:** Dokumentart und wichtigstes Merkmal, 2 bis 6 Wörter, ohne Nummern, Beträge oder Namen.

Die Regeln stehen als Anweisung an Claude in [dienst.py](dienst.py) (`ANWEISUNG`) und lassen sich dort anpassen.

## Voraussetzungen

- Linux-Rechner oder NAS mit Docker und `docker compose`
- ein Schlüssel für die [Claude-API](https://console.anthropic.com) (eigener Schlüssel nur für diesen Dienst, mit monatlichem Ausgabelimit)
- ein Scanner, der Dateien wie `20261007_185514_Report_0001.pdf` ablegt. Andere Namensmuster: `ROHSCAN_MUSTER` setzen (regulärer Ausdruck, die ersten drei Gruppen sind Jahr, Monat, Tag)
- optional ein [ntfy](https://ntfy.sh)-Kanal für Meldungen aufs Handy

## Einrichtung

1. Repo in einen Ordner auf dem Docker-Rechner holen (`git clone` oder als ZIP).
2. **Benutzer:** am besten ein eigener Benutzer, der nur auf den Scan-Ordner schreiben darf. Seine Nummern mit `id -u <name>` und `id -g <name>`.
3. **`.env`** aus [.env.example](.env.example) anlegen: Pfad zum Scan-Ordner und die Benutzernummern.
4. **Geheimnisse** in den Unterordner `geheim/` (bleibt lokal, steht in `.gitignore`):
   - `geheim/anthropic.key`: der API-Schlüssel als einzige Zeile
   - `geheim/ntfy.url` (optional): die ntfy-Adresse `https://…`

   Rechte so setzen, dass nur der Dienst-Benutzer (und Admins) sie lesen können, z. B. `chown -R <name> geheim && chmod 700 geheim && chmod 600 geheim/*`.
5. Bauen, testen, starten:
   ```bash
   mkdir -p daten && chown <name> daten
   docker compose build
   docker compose run --rm scans-benennen probe       # zeigt Vorschläge, benennt nichts um
   docker compose run --rm scans-benennen ntfy-test   # optional: Testmeldung
   docker compose up -d
   docker logs --tail 20 scans-benennen               # "Scan-Dienst gestartet …"
   ```

**QNAP (Container Station):** Ordner unter `/share/Container/scans-benennen` anlegen, per SSH als Admin mit `sudo` arbeiten. Rechte auf Unterordner einer Freigabe gibt es in QTS nur mit „Erweiterte Ordnerberechtigungen“; ohne sie sieht der Container trotzdem nur den eingebundenen Scan-Ordner.

## Betrieb

| Aufgabe | Wie |
| --- | --- |
| Läuft er? | `docker logs --tail 40 scans-benennen`; Zeilen `OK …` bzw. `UNKLAR …` |
| Ein Durchlauf von Hand | `docker compose run --rm scans-benennen einmal` (oder `probe`, ohne Umbenennen) |
| Rückgängig | `docker exec scans-benennen /app/venv/bin/python /app/dienst.py undo 2026-11-14T16:00` dreht alle Umbenennungen ab diesem Zeitpunkt zurück; ohne Zeitpunkt alle |
| Unklaren Scan neu versuchen | Eintrag aus `daten/zustand.json` löschen oder die Datei einmal öffnen und speichern |
| Einstellungen ändern | `docker-compose.yml` anpassen, `docker compose up -d` |
| Neue Version | `git pull`, dann `docker compose up -d --build` |
| Update | Das Image wird lokal gebaut, Watchtower & Co. finden dafür nichts. Ist es älter als 90 Tage (`UPDATE_TAGE`), meldet der Dienst per ntfy „Update fällig“, danach alle 30 Tage. Dann: `docker compose build --pull && docker compose up -d` |

### Einstellungen (in `docker-compose.yml`)

| Variable | Standard | Bedeutung |
| --- | --- | --- |
| `MODELL` | `claude-opus-5-5` | günstiger: `claude-haiku-5-5` |
| `EFFORT` | `low` | Denkaufwand des Modells |
| `INTERVALL` | 15 | Sekunden zwischen zwei Durchläufen |
| `RUHEZEIT` | 15 | so lange muss eine Datei unverändert sein |
| `SEITEN` | 2 | so viele Seiten werden gelesen |
| `MAX_MB` | 200 | größere PDFs werden nicht gelesen |
| `MAX_ZEICHEN` | 30000 | höchstens so viel Text geht an die API |
| `NTFY_ERFOLG` | 0 | 1 = auch erfolgreiche Umbenennungen melden |
| `UPDATE_TAGE` | 90 | ab diesem Image-Alter „Update fällig“ |
| `ROHSCAN_MUSTER` | `^(\d{4})(\d{2})(\d{2})_(\d{6})_Report_(\d{4})\.pdf$` | Dateinamen des Scanners |

## Sicherheit

| Bereich | Maßnahme |
| --- | --- |
| Container | läuft nie als root; Dateisystem nur lesbar, beschreibbar nur `/tmp` (tmpfs) und die Mounts; keine Capabilities, `no-new-privileges`, Grenzen für Prozesse, Speicher und CPU; keine offenen Ports |
| Eingaben | nur Rohscan-Namen, keine Symlinks; leere, Nicht-PDF- und zu große Dateien werden nicht gelesen, sondern als unklar gemeldet |
| Prompt-Injection | der Scan-Text gilt laut Anweisung nur als Material; versucht er Vorgaben zu machen, ist das Ergebnis „unsicher“. Die Antwort wird auf Form und Typen geprüft |
| Dateiname | Längen begrenzt; Pfadzeichen, Steuer- und unsichtbare Unicode-Zeichen werden entfernt; der neue Name bleibt im selben Ordner und überschreibt nie |
| `undo` | dreht nur Zeilen zurück, deren Ordner im Scan-Ordner liegt und deren alter Name ein Rohscan-Name ist |

## Kosten und Datenschutz

- Pro Scan etwa 3.000 Eingabe- und wenige hundert Ausgabe-Token: mit `claude-opus-5-5` rund 1–2 Cent, mit `claude-haiku-5-5` deutlich weniger. Abgerechnet wird über die Claude-API.
- Das PDF verlässt den Rechner nicht, nur der erkannte Text der ersten Seiten. Der enthält Namen, Adressen und bei Arztunterlagen Gesundheitsdaten. Laut Anthropic werden API-Daten standardmäßig nicht zum Training verwendet.
- ntfy-Meldungen enthalten nur den Rohdateinamen und den Grund, keine Dokumentinhalte.

## Lizenz

[MIT](LICENSE)
