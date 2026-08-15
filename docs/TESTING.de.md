# Testen

## Schnellnavigation

- [Projektüberblick](README.de.md)
- [Schnellstart](QUICKSTART.de.md)
- [Test-Handbuch](TESTING.de.md) *(diese Seite)*
- [Paketierungsleitfaden](PACKAGING.de.md)
- [Hardware-Hinweise](HARDWARE.de.md)
- Need English? Jump to [TESTING.en.md](TESTING.en.md)

## Überblick

Die Make-Targets konzentrieren sich auf drei Testebenen:

- `make test-gui`: Steuerung der Neutrino-Oberfläche via `uinput`/`evdev`, Validierung per OCR.
- `make test-web`: Playwright-Smoketest für das Webinterface (benötigt `NEUTRINO_WEB_BASE_URL`).
- `make test-hw`: Optionaler Hardware-Scan (DVB/V4L2/Input).

`make test` führt die Shell-, GUI- und Web-Tests in dieser Reihenfolge aus. Nur `make test-shell` kommt ohne Voraussetzungen aus.

## Voraussetzungen

- Ein laufender Neutrino-Prozess (`make run` in separater Shell, **als normaler Benutzer** — siehe Abschnitt „Test-Suites ausführen“). `run` nutzt den Host-Wrapper; wer Isolation über systemd-nspawn/proot will, startet `make run-nspawn`.
- Installierte Hilfsprogramme: `fbgrab` + PNM→PNG-Converter (`netpbm` oder GraphicsMagick/ImageMagick), `tesseract`, `evtest`, Python-Module `opencv-python-headless`, `pytesseract`, `evdev`.
- Für `make run` wird `systemd-nspawn` **nicht** benötigt — das ist der einfache Host-Wrapper. Installiere es (Debian/Ubuntu: `sudo apt-get install systemd-container`) nur, wenn du die isolierte Variante `make run-nspawn` willst.
- Vorher einmal `make deps` ausführen, damit die Python-Virtualenv `pytest` und Co. enthält. Ohne `pytest` bricht die GUI-Test-Suite ab.
- Optional: Wer Eingaben über evdev simulieren möchte, lädt das Kernelmodul `uinput`. Andernfalls nutzt der Testhelfer automatisch die FIFO `/tmp/neutrino.input`.

Schnellinstallation auf dem Host (apt/dnf):

```bash
sudo ./scripts/setup_deps.sh --mode=auto
```

Das Skript installiert Systempakete (inkl. `tesseract`, `fbcat`, `xvfb`, `netpbm`, `evtest`) und legt die Python-Virtualenv mit `pytest`, `opencv-python-headless`, `pytesseract`, `evdev` an.
`uinput` ist kein Paket (Debian/Ubuntu/Fedora): Kernelmodul ggf. per `sudo modprobe uinput` laden und Schreibrechte über Gruppe `input` oder per `sudo` sicherstellen.

Beispiel Debian 12 – fehlende Laufzeitbibliotheken bereitstellen:

```bash
sudo apt-get install -y \
  libavcodec59 libavformat59 libavutil57 libswscale6 libswresample4 \
  libjpeg62-turbo freeglut3
```

Das Skript `scripts/setup_deps.sh` richtet eine Python-Virtualenv ein und installiert die benötigten Module automatisiert.

### Wichtige Umgebungsvariablen

| Variable | Standard | Bedeutung |
| --- | --- | --- |
| `NEUTRINO_WEB_BASE_URL` | — | Ziel-URL für Playwright. Auf die Weboberfläche der laufenden Neutrino-Instanz setzen (z. B. `http://localhost:31344`). |
| `TEST_ARTIFACT_DIR` | `artifacts/tests` | Basisverzeichnis für Screenshots, Logs und Playwright-Reports. |
| `PLAYWRIGHT_BIN` | `npx` | Kommando zum Starten von Playwright (`npx playwright …`). Überschreiben, falls global installiert. |
| `ALLOW_NON_ROOT` | `0` | Mit `1` lassen sich GUI-Tests ohne Root-Prüfung starten – nur für Umgebungen ohne echte Eingabegeräte sinnvoll. |
| `RUN_NEUTRINO_DISPLAY` | Host-`DISPLAY` (Fallback `:99`) | DISPLAY, das `make run` nutzt; standardmäßig der Host-X-Server, sonst ein headless `:99`. |

Variablen können direkt beim Aufruf gesetzt werden:

```bash
NEUTRINO_WEB_BASE_URL=http://localhost:31344 \
TEST_ARTIFACT_DIR=$PWD/out/tests \
make test-web
```

## Test-Suites ausführen

1. Neutrino bauen und installieren (`make neutrino`), falls noch nicht geschehen.
2. Neutrino in separater Shell starten, **als normaler Benutzer**:
   ```bash
   make run
   ```
   Die Sitzung während der Tests laufen lassen. Kein `sudo` vor `make`:
   die Run-Targets bauen und stagen vorher neu, root hinterlässt also
   root-eigene Dateien in `.venv/` und `artifacts/` und macht spätere
   Builds kaputt. Root braucht man nur für echte DVB-Geräte — siehe
   [Hardware-Hinweise](HARDWARE.de.md).
3. In einem zweiten Terminal das gewünschte Target starten:
   - Nur GUI: `make test-gui`
   - Nur Web: `NEUTRINO_WEB_BASE_URL=http://localhost:31344 make test-web`
   - Hardware-Scan: `make test-hw` (listet nur Geräte auf; kein Root nötig)
   - Komplettlauf: `make test`

Die Artefakte landen unter `artifacts/tests/`, sofern `TEST_ARTIFACT_DIR` nicht verändert wurde.

## Artefakte

Testausgaben werden unter `artifacts/tests/` abgelegt:

- `gui/` enthält Screenshots und Logs.
- `web/` enthält Playwright-Reports.

Das sind lokale Artefakte. Die CI erzeugt sie **nicht**: der Workflow fährt die
Shell-Suite und den Dependency-Preflight, niemals GUI oder Web, und lädt nur die
`deps-doctor`-Ausgabe sowie im Fehlerfall Build-Logs hoch.

## Neue GUI-Tests hinzufügen

1. Neuen Test in `tests/gui/` anlegen (Pytest-Konventionen beachten).
2. Hilfsfunktionen aus `tests/gui/utils.py` für OCR oder Screenshots nutzen.
3. Weitere Tastensequenzen können über `tests/gui/send_keys.py` oder neue Helfer abgedeckt werden.
4. Golden Images nach `tests/gui/golden/` legen (Ordner bei Bedarf anlegen) und im Test vergleichen.

## Neue Web-Tests hinzufügen

1. Playwright-Spezifikation in `tests/web/` ergänzen.
2. Falls zusätzliche npm-Pakete nötig sind, `tests/web/package.json` anpassen.
3. Lokale Tests mit `NEUTRINO_WEB_BASE_URL=http://localhost:31344 npx playwright test` ausführen.

## Fehlerbehebung

- **`DISPLAY not set`**: Headless-Server läuft nicht. `make run` erneut starten.
- **`python-evdev missing`**: `make deps` erneut ausführen oder Paket manuell installieren.
- **Tesseract-OCR liefert leere Ergebnisse**: Prüfen, ob `fbgrab` gültige Screenshots erzeugt (Dateien öffnen).
- **Playwright erreicht das Ziel nicht**: Prüfen, ob `NEUTRINO_WEB_BASE_URL` im Testumfeld auflösbar ist und der Port erreichbar bleibt.

Weitere Hinweise zur Hardware gibt es in `docs/HARDWARE.de.md`.
