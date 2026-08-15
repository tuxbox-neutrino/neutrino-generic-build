#!/usr/bin/env bash
set -euo pipefail

VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    -v|--verbose) VERBOSE=1 ;;
    -h|--help)
      cat <<'EOF'
Detect DVB/V4L2 tuner hardware.

Usage:
  detect_devs.sh [--verbose]
EOF
      exit 0
      ;;
  esac
done

log() {
  echo "[detect_devs] $*"
}

list_devices() {
  local path pattern label
  path="$1"
  pattern="$2"
  label="$3"

  if compgen -G "${path}/${pattern}" >/dev/null 2>&1; then
    log "Gefundene ${label}-Devices unter ${path}:"
    log "Found ${label} devices under ${path}:"
    for node in "${path}"/${pattern}; do
      [[ -e "${node}" ]] || continue
      printf '    - %s\n' "${node}"
      if [[ "${VERBOSE}" -eq 1 ]]; then
        if command -v udevadm >/dev/null 2>&1; then
          udevadm info --query=property --name="${node}" 2>/dev/null | sed 's/^/      /'
        fi
      fi
    done
  else
    log "Keine ${label}-Devices gefunden."
    log "No ${label} devices detected."
  fi
}

list_adapter() {
  local adapter
  for adapter in /dev/dvb/adapter*; do
    [[ -d "${adapter}" ]] || continue
    log "Adapter $(basename "${adapter}"):"
    for node in "${adapter}"/*; do
      [[ -e "${node}" ]] || continue
      printf '    - %s\n' "${node}"
    done
    if [[ "${VERBOSE}" -eq 1 ]]; then
      find "/sys/class/dvb" -maxdepth 1 -name "$(basename "${adapter}")*" -print 2>/dev/null | sed 's/^/      sysfs: /'
    fi
  done
}

log "Suche nach DVB/HW-Devices..."
log "Scanning for DVB/V4L2/input devices..."

if [[ -d /dev/dvb ]]; then
  list_adapter
else
  log "Verzeichnis /dev/dvb nicht vorhanden."
  log "Directory /dev/dvb not present."
fi

list_devices "/dev" "video*" "V4L2/Video"
list_devices "/dev/input" "event*" "Input"
list_devices "/dev" "fb*" "Framebuffer"
