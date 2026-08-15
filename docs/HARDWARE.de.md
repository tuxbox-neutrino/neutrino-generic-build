# Hardware & Tuner

## Schnellnavigation

- [Projektüberblick](README.de.md)
- [Schnellstart](QUICKSTART.de.md)
- [Test-Handbuch](TESTING.de.md)
- [Paketierungsleitfaden](PACKAGING.de.md)
- [Hardware-Hinweise](HARDWARE.de.md) *(diese Seite)*
- Need English? Visit [HARDWARE.en.md](HARDWARE.en.md)

## Geräteeinbindung

1. Fügen Sie Ihren Benutzer zu den Gruppen `video`, `input`, `dvb`, `plugdev` hinzu:
   ```bash
   sudo usermod -a -G video,input,dvb,plugdev $USER
   ```
2. Firmware-Dateien entsprechend den Herstellerangaben nach `/lib/firmware` kopieren.
3. Starten Sie das System neu oder melden Sie sich neu an, damit Gruppenrechte greifen.

## Geräteerkennung

`scripts/detect_devs.sh` listet gefundene DVB-, V4L2- und Eingabegeräte.

```bash
make test-hw
```

Ausgabe erfolgt zweisprachig und enthält optional (Flag `--verbose`) zusätzliche Udev-Informationen.

## Bekannte funktionierende Kombinationen (Beispiele)

- USB-DVB-C Tuner basierend auf dem RTL2832U-Chipsatz mit aktuellem Kernel.
- PCIe-Dual-Tuner (CX23885-Serie) unter Kernel ≥ 5.10.

> Hinweis: Diese Liste ist bewusst generisch. Prüfen Sie immer die Kernel-Support-Matrix des Herstellers.

## Out-of-Kernel-Tuner-Treiber (DVB)

Nicht jeder Tuner wird vom Kernel-eigenen Treiber unterstützt. Bleibt `/dev/dvb`
trotz angeschlossenem Tuner leer, muss der Treiber ggf. außerhalb des Kernels
gebaut werden (media_build / linux-media).

- Helfer-Repo: <https://github.com/dbt1/linux-media> baut die Module je
  Tuner-Profil (z. B. TBS5580 USB) und hält sie in `out/`, statt nach
  `/lib/modules` zu installieren.
  **Persönliches Repo eines Entwicklers, kein Bestandteil von Tuxbox und nicht
  supported** — hier nur genannt, weil es einen gangbaren Weg zeigt. Jede andere
  media_build-Variante tut es genauso.
- Voraussetzung: passende Kernel-Header — `sudo apt install linux-headers-amd64`
  als Metapaket, damit sie Kernel-Updates folgen.
- **Wartung:** Solche Module sind an die vermagic des laufenden Kernels gebunden.
  Nach jedem Kernel-Update müssen sie **neu gebaut** werden, sonst verschwindet
  `/dev/dvb` und Neutrino startet ohne Tuner — das ist kein Fehler von Neutrino
  oder diesem Build-System.

> Hinweis: `neutrino-generic-build` baut diese Treiber nicht selbst. Das
> Treiber-Provisioning ist host- und kernelspezifisch und liegt im
> linux-media-Helfer, nicht in diesem Repo.

## Tests mit realer Hardware

1. Neutrino mit `make run` starten — als normaler Benutzer, niemals
   `sudo make`, sonst bleiben root-eigene Build-Artefakte zurück. Ist der
   Tuner nicht erreichbar, lieber in die Gruppe `video` aufnehmen
   (`sudo usermod -aG video $USER`, danach neu anmelden), statt den Build
   mit Root-Rechten zu fahren.
2. Sicherstellen, dass `/dev/dvb/adapter*` sichtbar ist (sonst Firmware prüfen).
3. Optionale Smoke-Tests vorbereiten (z. B. Sender-Scan via `neutrino`-Menü).

## Fehlersuche

- **Geräte fehlen**: Kernel-Module via `dmesg` prüfen, Firmware laden.
- **Geräte nach Kernel-Update weg**: Out-of-Kernel-Module gegen den neuen Kernel neu bauen (siehe Abschnitt „Out-of-Kernel-Tuner-Treiber (DVB)").
- **Zugriff verweigert**: Gruppenmitgliedschaft kontrollieren (`id $USER`).
- **Kein Bild/Ton**: Audio/Video-Pipeline in `libstb-hal` prüfen; Logs unter `logs/` analysieren.
