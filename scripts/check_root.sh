#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-run}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-0}"

if [[ "${EUID}" -eq 0 ]]; then
  exit 0
fi

if [[ "${ALLOW_NON_ROOT}" == "1" ]]; then
  cat <<EOF
[check_root] Hinweis: Aktion "${ACTION}" wird ohne Root-Rechte ausgeführt.
[check_root] Caution: "${ACTION}" is running without root privileges (ALLOW_NON_ROOT=1).
EOF
  exit 0
fi

cat <<'EOF'
[check_root] Diese Aktion benötigt Root-Rechte (sudo oder root-shell).
[check_root] This action requires root privileges (sudo or root shell).
Setzen Sie ALLOW_NON_ROOT=1, wenn Sie bewusst ohne Gerätezugriff testen wollen.
Set ALLOW_NON_ROOT=1 if you deliberately want to run without device access.
EOF
exit 1
