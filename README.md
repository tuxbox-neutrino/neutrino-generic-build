# Neutrino Generic Build (`dx` branch)

This branch hosts the revamped Make-based build, test, and packaging environment for Neutrino (generic-pc).
Builds and tests now run directly on the host; the former Docker auto-wrapper is removed.

## What this is

[Neutrino](https://github.com/tuxbox-neutrino/neutrino) is the open-source TV
user interface that runs on Tuxbox set-top boxes. **This repository builds it for
your PC** — an ordinary x86_64 Linux desktop or laptop — so you can develop on it,
test it, and look at it without owning a receiver.

What you get is the same Neutrino, in a window on your desktop, with its web
interface reachable at <http://localhost:31344>.

## What you need

|  | |
|---|---|
| **A PC** | x86_64 Linux. Debian 12/13, Ubuntu 22.04/24.04 and Fedora 41 are the ones CI checks. Not a set-top box — that is what [tuxbox-os-builder](https://github.com/tuxbox-neutrino/tuxbox-os-builder) is for. |
| **`git` and `make`** | Everything else the build tells you about and installs on request. |
| **~2 GB of free disk** | Sources, the local FFmpeg build and the staged runtime. See [Quickstart](docs/QUICKSTART.en.md#2-bootstrap-dependencies--first-build) for the breakdown. |
| **Patience on the first run** | `make bootstrap` compiles FFmpeg from source. This is the long part. |
| **A DVB tuner — optional** | Without one, Neutrino starts in simulation mode (`SIMULATE_FE=1`) and everything but live TV works. The run targets set this for you. |
| **Root — only for hardware** | Not needed to build, not needed to run in simulation mode. Only for real tuner/input devices. Never run `make` itself under `sudo`. |

## Try it

```bash
git clone -b dx https://github.com/tuxbox-neutrino/neutrino-generic-build.git
cd neutrino-generic-build
make deps-doctor      # check the host, changes nothing
                      # then run the install command it prints
make bootstrap        # build Neutrino (long on the first run)
make run              # start it
```

See the [Quickstart](docs/QUICKSTART.en.md) for the full walkthrough.

## Documentation Overview

Pick your language and follow the direct links:

### English

- [Project Overview](docs/README.en.md) – prerequisites, build layout.
- [Quickstart](docs/QUICKSTART.en.md) – shortest path: clone → build → run.
- [Testing Guide](docs/TESTING.en.md) – GUI/web smoke tests, optional hardware checks, CI notes.
- [Packaging Guide](docs/PACKAGING.en.md) – AppImage, Debian package, static bundle, release hints.
- [Plugin Setup](docs/PLUGINS_SETUP.md) – how plugins are obtained, built and installed (German only).
- [Hardware Notes](docs/HARDWARE.en.md) – tuner/input setup, permissions, troubleshooting tips.
- [Adding a Plugin](docs/HOWTO_ADD_PLUGIN.en.md) – register a new plugin with the build.
- [Adding a Target](docs/HOWTO_ADD_TARGET.en.md) – extend the Makefile modules.

### Deutsch

**Worum es geht:** [Neutrino](https://github.com/tuxbox-neutrino/neutrino) ist
die freie TV-Oberfläche der Tuxbox-Receiver. Dieses Repository baut sie **für den
PC** — ein gewöhnliches x86_64-Linux —, damit man sie ohne Receiver entwickeln,
testen und ansehen kann. Ein DVB-Tuner ist optional: ohne einen startet Neutrino
im Simulationsmodus (`SIMULATE_FE=1`), und alles außer Live-TV funktioniert.
Root braucht man nur für echte Geräte, nicht zum Bauen und nicht zum Starten.
Die Weboberfläche liegt unter <http://localhost:31344>. Rechne für den ersten
Build mit ~2 GB freiem Plattenplatz und etwas Geduld: FFmpeg wird lokal
übersetzt. Der [Schnellstart](docs/QUICKSTART.de.md) führt durch alles Weitere.

- [Projektüberblick](docs/README.de.md) – Voraussetzungen, Build-Struktur.
- [Schnellstart](docs/QUICKSTART.de.md) – Schnellster Ablauf: Klonen → Bauen → Starten.
- [Test-Handbuch](docs/TESTING.de.md) – GUI/Web-Smoketests, optionale Hardwareprüfungen, CI-Hinweise.
- [Paketierungsleitfaden](docs/PACKAGING.de.md) – AppImage, Debian-Paket, statisches Bundle, Release-Tipps.
- [Plugin-Einrichtung](docs/PLUGINS_SETUP.md) – wie Plugins bezogen, gebaut und installiert werden.
- [Hardware-Hinweise](docs/HARDWARE.de.md) – Tuner-/Eingabe-Setup, Berechtigungen, Fehlerbehebung.
- [Plugin hinzufügen](docs/HOWTO_ADD_PLUGIN.de.md) – ein neues Plugin im Build registrieren.
- [Target hinzufügen](docs/HOWTO_ADD_TARGET.de.md) – die Makefile-Module erweitern.

> Root privileges are needed only to reach real tuner and input devices. Building
> never needs them, and neither does running in simulation mode. Scripts never
> elevate automatically — see the [Hardware Notes](docs/HARDWARE.en.md)
> ([DE](docs/HARDWARE.de.md)) for the device-access path.

## License

GPL-2.0-or-later — see [LICENSE](LICENSE) and [LICENSES/README.md](LICENSES/README.md).
Neutrino, libstb-hal, FFmpeg and the plugins are not part of this repository;
the build fetches each from its own upstream, and each keeps its own license.
