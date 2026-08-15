#!/usr/bin/env bash
cat <<'EOF'
Neutrino benötigt Root-Rechte für den Zugriff auf DVB-, Audio- und Eingabegeräte.
Neutrino requires root privileges to access DVB, audio, and input devices.

Empfohlene Schritte / Recommended steps:
  * sudo usermod -a -G video,input,plugdev $USER
  * Firmware-Dateien für Ihren Tuner ins Verzeichnis /lib/firmware kopieren.
  * Siehe docs/HARDWARE.de.md bzw. docs/HARDWARE.en.md für Details.
EOF
