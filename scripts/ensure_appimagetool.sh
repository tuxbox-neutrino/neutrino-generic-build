#!/usr/bin/env bash
# Provision the AppImage tooling, pinned and verified.
#
# Three artefacts are needed:
#
#   tool     appimagetool, which packs the AppDir into an AppImage
#   runtime  the type2 runtime that gets prepended to that AppImage and is what
#            actually mounts it when a user runs the file
#   deploy   linuxdeploy, which collects the shared libraries the binary needs
#            and applies the upstream exclude list while doing so
#
# All three are pinned to a tagged upstream release and checked against a recorded
# SHA-256. The previous version pulled appimagetool from the moving
# "continuous" tag with no verification at all, so two builds a week apart could
# ship different tooling with nothing to show for it.
#
# The runtime matters for a second reason: the one from AppImageKit links
# against libfuse.so.2, which neither Ubuntu 24.04 nor Fedora 41 install by
# default. The pinned type2 runtime is static-pie linked with fuse3 built in, so
# no libfuse2 has to be installed for "chmod +x, run it" to work. It still needs
# a fusermount binary to mount itself; without one it prints a line starting
# with "Error:" and then extracts itself to a temporary directory and runs
# anyway. Desktop installations of Ubuntu 24.04 and Fedora 41 have fuse3,
# minimal images do not.
set -euo pipefail

APPIMAGETOOL_RELEASE="1.9.1"
TYPE2_RUNTIME_RELEASE="20251108"
LINUXDEPLOY_RELEASE="1-alpha-20251107-1"

usage() {
  cat >&2 <<'MSG'
Usage: ensure_appimagetool.sh [tool|runtime|deploy]
  tool     (default) provision appimagetool and print its path
  runtime  provision the static type2 runtime and print its path
  deploy   provision linuxdeploy and print its path
MSG
}

what="${1:-tool}"
case "${what}" in
  tool|runtime|deploy) ;;
  -h|--help) usage; exit 0 ;;
  *) echo "[appimage] Unknown artefact '${what}'." >&2; usage; exit 1 ;;
esac

arch="$(uname -m)"
case "${arch}" in
  x86_64|amd64) arch="x86_64" ;;
  aarch64|arm64) arch="aarch64" ;;
  *)
    echo "[appimage] No pinned AppImage tooling for architecture '${arch}'." >&2
    exit 1
    ;;
esac

# Recorded from the pinned releases. Update these together with the release
# variables above, never on their own.
case "${what}:${arch}" in
  tool:x86_64)
    asset="appimagetool-x86_64.AppImage"
    url="https://github.com/AppImage/appimagetool/releases/download/${APPIMAGETOOL_RELEASE}/${asset}"
    sha256="ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"
    ;;
  tool:aarch64)
    asset="appimagetool-aarch64.AppImage"
    url="https://github.com/AppImage/appimagetool/releases/download/${APPIMAGETOOL_RELEASE}/${asset}"
    sha256="f0837e7448a0c1e4e650a93bb3e85802546e60654ef287576f46c71c126a9158"
    ;;
  runtime:x86_64)
    asset="runtime-x86_64"
    url="https://github.com/AppImage/type2-runtime/releases/download/${TYPE2_RUNTIME_RELEASE}/${asset}"
    sha256="2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d"
    ;;
  runtime:aarch64)
    asset="runtime-aarch64"
    url="https://github.com/AppImage/type2-runtime/releases/download/${TYPE2_RUNTIME_RELEASE}/${asset}"
    sha256="00cbdfcf917cc6c0ff6d3347d59e0ca1f7f45a6df1a428a0d6d8a78664d87444"
    ;;
  deploy:x86_64)
    asset="linuxdeploy-x86_64.AppImage"
    url="https://github.com/linuxdeploy/linuxdeploy/releases/download/${LINUXDEPLOY_RELEASE}/${asset}"
    sha256="c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d"
    ;;
  deploy:aarch64)
    asset="linuxdeploy-aarch64.AppImage"
    url="https://github.com/linuxdeploy/linuxdeploy/releases/download/${LINUXDEPLOY_RELEASE}/${asset}"
    sha256="620095110d693282b8ebeb244a95b5e911cf8f65f76c88b4b47d16ae6346fcff"
    ;;
esac

# Explicit override, for a maintainer who wants to test different tooling. The
# lookup of a bare "appimagetool" in PATH that used to happen here is gone on
# purpose: it silently unpinned the build on any machine that had one
# installed, and the resulting AppImage differed for no visible reason.
if [[ "${what}" == "tool" && -n "${APPIMAGE_TOOL:-}" ]]; then
  if command -v "${APPIMAGE_TOOL}" >/dev/null 2>&1; then
    command -v "${APPIMAGE_TOOL}"
    exit 0
  fi
  echo "[appimage] APPIMAGE_TOOL is set to '${APPIMAGE_TOOL}' but that is not executable." >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
tools_dir="${repo_root}/tools"
mkdir -p "${tools_dir}"
target="${tools_dir}/${asset}"

verify() {
  [[ -f "$1" ]] || return 1
  echo "${sha256}  $1" | sha256sum --check --status
}

if ! verify "${target}"; then
  echo "[appimage] Fetching ${asset} (${url})" >&2
  tmp="${target}.part"
  rm -f "${tmp}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "${tmp}" "${url}" || { rm -f "${tmp}"; exit 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "${tmp}" "${url}" || { rm -f "${tmp}"; exit 1; }
  else
    echo "[appimage] Neither curl nor wget is available to download ${asset}." >&2
    exit 1
  fi

  if ! verify "${tmp}"; then
    got="$(sha256sum "${tmp}" | cut -d' ' -f1)"
    rm -f "${tmp}"
    cat >&2 <<MSG
[appimage] Checksum mismatch for ${asset}.
[appimage]   expected ${sha256}
[appimage]   got      ${got}
[appimage] The pinned upstream asset changed, or the download was tampered
[appimage] with. Verify the new asset by hand before touching the checksum in
[appimage] scripts/ensure_appimagetool.sh.
MSG
    exit 1
  fi
  mv "${tmp}" "${target}"
fi

chmod +x "${target}"
echo "${target}"
