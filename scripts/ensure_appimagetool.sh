#!/usr/bin/env bash
set -euo pipefail

APPIMAGE_TOOL_OVERRIDDEN="${APPIMAGE_TOOL:-}"
if [[ -n "${APPIMAGE_TOOL_OVERRIDDEN}" ]] && command -v "${APPIMAGE_TOOL_OVERRIDDEN}" >/dev/null 2>&1; then
  command -v "${APPIMAGE_TOOL_OVERRIDDEN}"
  exit 0
fi

if command -v appimagetool >/dev/null 2>&1; then
  command -v appimagetool
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
tools_dir="${repo_root}/tools"
mkdir -p "${tools_dir}"

local_candidate="${tools_dir}/appimagetool"
if [[ -x "${local_candidate}" ]]; then
  echo "${local_candidate}"
  exit 0
fi

arch=$(uname -m)
case "${arch}" in
  x86_64|amd64)
    asset="appimagetool-x86_64.AppImage"
    ;;
  aarch64|arm64)
    asset="appimagetool-aarch64.AppImage"
    ;;
  *)
    echo "[appimage] No prebuilt appimagetool available for architecture '${arch}'." >&2
    exit 1
    ;;
esac

url="https://github.com/AppImage/AppImageKit/releases/download/continuous/${asset}"
target="${tools_dir}/${asset}"
echo "[appimage] Downloading ${asset} from ${url}" >&2
if command -v curl >/dev/null 2>&1; then
  curl -fsSL -o "${target}" "${url}"
elif command -v wget >/dev/null 2>&1; then
  wget -O "${target}" "${url}"
else
  echo "[appimage] Neither curl nor wget is available to download appimagetool." >&2
  exit 1
fi
chmod +x "${target}"
ln -sf "${asset}" "${local_candidate}"

echo "${local_candidate}"
