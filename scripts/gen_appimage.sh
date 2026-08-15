#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${NEUTRINO_INSTALL_DIR:-}"
OUTPUT_DIR="${APPIMAGE_OUTPUT_DIR:-artifacts/appimage}"
APPIMAGE_TOOL="${APPIMAGE_TOOL:-appimagetool}"
APPDIR="${OUTPUT_DIR}/Neutrino.AppDir"
NEUTRINO_PREFIX="${NEUTRINO_PREFIX:-/usr}"
NEUTRINO_NAME="${NEUTRINO_NAME:-Neutrino}"

VERSION_JSON=$(scripts/version_info.sh)
VERSION_PKG=$(printf '%s' "${VERSION_JSON}" | python3 -c 'import sys,json;data=json.load(sys.stdin);print(data.get("package") or data.get("slug") or data.get("base") or "dev")')
ARCH=$(uname -m)
APPIMAGE_NAME="${NEUTRINO_NAME}_${VERSION_PKG}_${ARCH}.AppImage"
rm -f "${OUTPUT_DIR}/${NEUTRINO_NAME}_"*-$(uname -m).AppImage
rm -f "${OUTPUT_DIR}/${NEUTRINO_NAME}_"*_"${ARCH}.AppImage"

if [[ -z "${INSTALL_DIR}" || ! -d "${INSTALL_DIR}" ]]; then
  echo "[appimage] NEUTRINO_INSTALL_DIR invalid: ${INSTALL_DIR}" >&2
  exit 1
fi

mkdir -p "${APPDIR}"
rm -rf "${APPDIR:?}/"*
mkdir -p "${APPDIR}/usr"
cp -a "${INSTALL_DIR}${NEUTRINO_PREFIX}/." "${APPDIR}/usr/"

cat >"${APPDIR}/neutrino.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Neutrino (generic-pc)
Comment=Neutrino DTV application (requires root privileges for device access)
Exec=neutrino
Terminal=false
Icon=neutrino
Categories=AudioVideo;Video;TV;
EOF

cat >"${APPDIR}/AppRun" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "${EUID}" -ne 0 ]]; then
  echo "Neutrino benötigt Root-Rechte für den Zugriff auf DVB/Input-Devices."
  echo "Neutrino requires root privileges to access DVB/input devices."
fi
export APPDIR="$(dirname "$0")"
export LD_LIBRARY_PATH="${APPDIR}/usr/lib:${APPDIR}/usr/lib64:${LD_LIBRARY_PATH:-}"
exec "${APPDIR}/usr/bin/neutrino" "$@"
EOF
chmod +x "${APPDIR}/AppRun"

if [[ -f "${INSTALL_DIR}${NEUTRINO_PREFIX}/share/icons/hicolor/256x256/apps/neutrino.png" ]]; then
  cp "${INSTALL_DIR}${NEUTRINO_PREFIX}/share/icons/hicolor/256x256/apps/neutrino.png" "${APPDIR}/neutrino.png"
else
  # Generate a simple placeholder icon if none was installed.
  python3 - "${APPDIR}/neutrino.png" <<'PY'
import sys
from pathlib import Path

try:
    from PIL import Image
except ModuleNotFoundError:
    Image = None

dest = Path(sys.argv[1])
if Image is None:
    # fallback: create a minimal PNG via RGB tuples using stdlib only
    import struct, zlib
    width = height = 64
    pixels = b''.join(b'\x00' + b'\x00\x66\xa3\xff' * width for _ in range(height))
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    data = zlib.compress(pixels, 9)
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', data) + chunk(b'IEND', b'')
    dest.write_bytes(png)
else:
    img = Image.new('RGBA', (256, 256), (0, 102, 163, 255))
    img.save(dest)
PY
fi

if ! command -v "${APPIMAGE_TOOL}" >/dev/null 2>&1; then
  cat >&2 <<MSG
[appimage] Required generator '${APPIMAGE_TOOL}' is not available.
[appimage] Re-run scripts/ensure_appimagetool.sh (or install appimagetool manually) and ensure FUSE/libfuse2 is present.
[appimage] See docs/PACKAGING.en.md (AppImage section) for detailed instructions.
MSG
  exit 1
fi

(
  cd "${OUTPUT_DIR}"
  APPIMAGE_EXTRACT_AND_RUN=1 "${APPIMAGE_TOOL}" "$(basename "${APPDIR}")" "${APPIMAGE_NAME}"
)

echo "[appimage] Fertig. Artefakte in ${OUTPUT_DIR}"
