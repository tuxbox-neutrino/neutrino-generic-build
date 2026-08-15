#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${NEUTRINO_INSTALL_DIR:-}"
OUTPUT_DIR="${DEB_OUTPUT_DIR:-artifacts/deb}"
NEUTRINO_PREFIX="${NEUTRINO_PREFIX:-/usr}"
PACKAGE_NAME="${PACKAGE_NAME:-neutrino-generic-pc}"
VERSION_JSON=$(scripts/version_info.sh)
DEFAULT_VERSION=$(printf '%s' "${VERSION_JSON}" | python3 -c 'import sys,json;data=json.load(sys.stdin);base=data.get("base") or "0.0.0";slug=data.get("slug") or "dev";print(f"{base}+git{slug}")')
PACKAGE_VERSION="${PACKAGE_VERSION:-$DEFAULT_VERSION}"
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"

if [[ -z "${INSTALL_DIR}" || ! -d "${INSTALL_DIR}" ]]; then
  echo "[deb] NEUTRINO_INSTALL_DIR invalid: ${INSTALL_DIR}" >&2
  exit 1
fi

if ! command -v dpkg-deb >/dev/null 2>&1; then
  echo "[deb] dpkg-deb missing. Install the dpkg-dev package." >&2
  exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

mkdir -p "${WORKDIR}/DEBIAN"
mkdir -p "${WORKDIR}${NEUTRINO_PREFIX}"
cp -a "${INSTALL_DIR}${NEUTRINO_PREFIX}/." "${WORKDIR}${NEUTRINO_PREFIX}/"

INSTALLED_SIZE=$(du -sk "${WORKDIR}${NEUTRINO_PREFIX}" | cut -f1)

cat >"${WORKDIR}/DEBIAN/control" <<EOF
Package: ${PACKAGE_NAME}
Version: ${PACKAGE_VERSION}
Section: misc
Priority: optional
Architecture: ${ARCH}
Maintainer: Neutrino Team <dev@neutrino>
Description: Neutrino generic-pc build (requires root for device access)
Installed-Size: ${INSTALLED_SIZE}
Depends: adduser, libstdc++6, libc6, libgcc-s1
EOF

mkdir -p "${WORKDIR}/DEBIAN"
cat >"${WORKDIR}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
echo "Neutrino benötigt Root-Rechte für DVB/Input-Geräte."
echo "Neutrino requires root privileges for DVB/input devices."
echo "Bitte fügen Sie den Benutzer zu den Gruppen video,input,plugdev hinzu."
EOF
chmod 0755 "${WORKDIR}/DEBIAN/postinst"

mkdir -p "${OUTPUT_DIR}"
dpkg-deb --build "${WORKDIR}" "${OUTPUT_DIR}/${PACKAGE_NAME}_${PACKAGE_VERSION}_${ARCH}.deb"

echo "[deb] Paket erstellt unter ${OUTPUT_DIR}/${PACKAGE_NAME}_${PACKAGE_VERSION}_${ARCH}.deb"
