# Packaging

## Schnellnavigation

- [Projektüberblick](README.de.md)
- [Schnellstart](QUICKSTART.de.md)
- [Test-Handbuch](TESTING.de.md)
- [Paketierungsleitfaden](PACKAGING.de.md) *(diese Seite)*
- [Hardware-Hinweise](HARDWARE.de.md)
- Need English? Switch to [PACKAGING.en.md](PACKAGING.en.md)

Diese Umgebung unterstützt drei Paketarten:

1. **AppImage (`make package-appimage`)**
   - Erstellt eine portable AppDir-Struktur und ruft `appimagetool` auf.
   - Root-Rechte sind für die Nutzung weiterhin erforderlich; der Launcher weist darauf hin.
   - Abhängigkeiten werden in die AppDir kopiert, verbleiben jedoch dynamisch gelinkt.
   - `make package-appimage` ruft automatisch `scripts/ensure_appimagetool.sh` auf. Fehlt das Tool, wird die passende Version nach `tools/` heruntergeladen und für spätere Aufrufe wiederverwendet.
   - Manuelle Einrichtung (z. B. für Offline-Systeme oder eigene Mirror):
     1. Aktuelles Binary laden (bei 404 auf den *continuous*-Channel zurückgreifen):
        ```bash
        wget -O appimagetool-x86_64.AppImage \
          https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
        ```
     2. Ausführbar machen und in den `PATH` verschieben:
        ```bash
        chmod +x appimagetool-x86_64.AppImage
        sudo mv appimagetool-x86_64.AppImage /usr/local/bin/appimagetool
        # -- oder ohne Root-Rechte --
        mkdir -p "$HOME/.local/bin"
        mv appimagetool-x86_64.AppImage "$HOME/.local/bin/appimagetool"
        export PATH="$HOME/.local/bin:$PATH"
        ```
     3. FUSE-Unterstützung sicherstellen (AppImages mounten intern ein Dateisystem):
        ```bash
        sudo apt install libfuse2        # Debian/Ubuntu
        sudo pacman -S fuse2             # Arch
        ```
     4. Test mit `appimagetool --version`.
     5. Fehlt FUSE auf dem Build-Host, setzt das Skript automatisch `APPIMAGE_EXTRACT_AND_RUN=1` und entpackt das Tool temporär. Das erzeugte AppImage benötigt auf dem Zielsystem dennoch FUSE, sofern es nicht vorab extrahiert wird.
     - Arch Linux: Alternativ `appimagetool-bin` oder `appimagetool-git` aus dem AUR nutzen.

2. **Debian-Paket (`make package-deb`)**
   - Generiert eine minimalistische `DEBIAN/control`-Datei und ein `postinst`-Skript mit Root-Hinweisen.
   - Installation via `dpkg -i neutrino-generic-pc_<version>_<arch>.deb`.
   - Empfohlene Nacharbeit: Benutzer zu `video`, `input`, `plugdev` hinzufügen.

3. **Statisches Archiv (`make package-static`)**
   - Führt intern `make neutrino-static` aus und archiviert das Ergebnis.
   - Achtung: Statisch gelinkte Builds können größer sein und Probleme mit proprietären Grafiktreibern verursachen.

## Vorbereitung

- Vor dem Paketieren mindestens einmal `make neutrino` ausführen, damit das Sysroot `artifacts/sysroot` gefüllt ist.  
  Für statische Bundles zusätzlich `make neutrino-static` starten.
- Prüfen, ob alle benötigten Tools installiert sind:
  - `appimagetool` (wird bei Bedarf durch `scripts/ensure_appimagetool.sh` heruntergeladen) plus FUSE (`libfuse2`) für AppImage.
  - `dpkg-deb` (Teil von `dpkg-dev`) für Debian-Pakete.
- `python3` für `scripts/version_info.sh` (wird durch `make deps` bereitgestellt).
- Die Make-Targets selbst benötigen keine Root-Rechte; Installation/Entpacken der Artefakte üblicherweise schon.
- Alle Formate in einem Rutsch bauen: `make package-appimage package-deb package-static`.
Hinweis: Die früheren Container-Workflows sind entfernt; alle Targets laufen direkt auf dem Host.

## Wichtige Variablen

Alle Werte lassen sich inline (`make PACKAGE_VERSION=3.30.0 package-deb`) oder dauerhaft in einer `Makefile.local` überschreiben. Standardpfade beziehen sich auf das Repository-Stammverzeichnis (`${PWD}`).

| Variable | Standard | Verwendet von | Wirkung |
| --- | --- | --- | --- |
| `APPIMAGE_TOOL` | `appimagetool` | AppImage | Pfad/Name des AppImage-Generators. |
| `APPIMAGE_OUTPUT_DIR` | `artifacts/appimage` | AppImage | Zielordner für erzeugte AppImage-Dateien. |
| `NEUTRINO_NAME` | `Neutrino` | AppImage | Basisname für `Neutrino_<version>_<arch>.AppImage`. |
| `PACKAGE_NAME` | `neutrino-generic-pc` | Debian | Paketname (`Package:`-Feld und Dateiname). |
| `PACKAGE_VERSION` | aus Git abgeleitet | Debian | Versionsstring; für Releases überschreiben (z. B. `PACKAGE_VERSION=3.30.0`). |
| `DEB_OUTPUT_DIR` | `artifacts/deb` | Debian | Zielordner für `.deb`-Pakete. |
| `STATIC_OUTPUT_DIR` | `artifacts/static` | Statisch | Zielordner für statische Tarballs. |
| `NEUTRINO_INSTALL_DIR` | `artifacts/sysroot` | AppImage / Debian | Sysroot, das in die Pakete/AppDir kopiert wird. |
| `NEUTRINO_INSTALL_DIR_STATIC` | `artifacts/sysroot-static` | Statisch | Installationsbaum aus `make neutrino-static`. |
| `NEUTRINO_PREFIX` | `/usr` | Alle | Prefix innerhalb des Pakets/AppImage (z. B. `/opt/neutrino`). |

Tipp für automatisierte Releases:

```bash
make PACKAGE_VERSION=3.30.0 \
     PACKAGE_NAME=neutrino-generic-pc \
     NEUTRINO_NAME="Neutrino Desktop" \
     package-appimage package-deb
```

## Lizenzhinweise

- Behalten Sie Lizenzdateien der eingebetteten Bibliotheken bei (GPL, LGPL, MIT etc.).
- Für AppImage/Static können zusätzliche `LICENSES/`-Ordner sinnvoll sein.

## Typische Stolpersteine

- **`appimagetool not found`**: `scripts/ensure_appimagetool.sh` ausführen (wird durch `make package-appimage` automatisch gestartet) oder Binary von https://appimage.github.io/AppImageKit/ herunterladen und im `PATH` ablegen.
- **`dpkg-deb` fehlt**: Paket `dpkg-dev` nachinstallieren.
- **Statische Builds scheitern**: Prüfen, ob alle Abhängigkeiten `--enable-static` unterstützen (ggf. auf musl wechseln).

Weitere Hintergrundinfos befinden sich in `docs/README.de.md`.

## Installation & Start der Artefakte

- **AppImage** (z. B. `Neutrino_0a129a0-x86_64.AppImage`)
  1. AppImage auf das Zielsystem kopieren.
  2. Ausführbar machen: `chmod +x Neutrino_<version>-<arch>.AppImage`.
  3. Start (Root empfohlen): `sudo ./Neutrino_<version>-<arch>.AppImage`. `ALLOW_NON_ROOT=1` nur nutzen, wenn fehlende Gerätefunktion akzeptabel ist.

- **Debian-Paket** (z. B. `neutrino-generic-pc_3.25.0+git0a129a0_amd64.deb`)
  1. Installation per `sudo apt install ./neutrino-generic-pc_<version>_<arch>.deb`.
  2. Binary liegt anschließend unter `/usr/bin/neutrino`; Start über `sudo neutrino` (oder via Service/Unit). Das Postinst-Skript weist nochmals auf Root-/Geräteanforderungen hin.
