#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${NEUTRINO_INSTALL_DIR_STATIC:-}"
OUTPUT_DIR="${STATIC_OUTPUT_DIR:-artifacts/static}"
NEUTRINO_PREFIX="${NEUTRINO_PREFIX:-/usr}"

if [[ -z "${INSTALL_DIR}" || ! -d "${INSTALL_DIR}" ]]; then
  echo "[static] Static installation directory missing. Run 'make neutrino-static' first." >&2
  exit 1
fi

VERSION_JSON=$(scripts/version_info.sh)
VERSION_SLUG=$(printf '%s' "${VERSION_JSON}" | python3 -c 'import sys,json;data=json.load(sys.stdin);print(data.get("slug") or "dev")')

mkdir -p "${OUTPUT_DIR}"
ARCHIVE="${OUTPUT_DIR}/neutrino-generic-static_${VERSION_SLUG}.tar.gz"
tar -czf "${ARCHIVE}" -C "${INSTALL_DIR}" .

cat <<EOF
[static] Fertig. Archiv: ${ARCHIVE}
[static] Hinweis: Statische Builds können inkompatibel zu proprietären GPU-Treibern sein.
[static] Hinweis: Prüfen Sie glibc/musl-Versionen auf Zielsystemen.
EOF
