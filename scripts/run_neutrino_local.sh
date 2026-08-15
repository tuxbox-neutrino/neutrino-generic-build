#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME_DIR="${NEUTRINO_RUNTIME_PREFIX:-${ROOT_DIR}/root}"
CHROOT_BIN="/usr/bin/neutrino"

if [[ ! -x "${RUNTIME_DIR}/usr/bin/neutrino" ]]; then
  echo "[run-local] Runtime tree missing. Build with 'make neutrino' first." >&2
  exit 1
fi

if command -v systemd-nspawn >/dev/null 2>&1; then
  nspawn_args=(
    --quiet
    --directory="${RUNTIME_DIR}"
    --bind=/dev
    --bind=/proc
    --bind=/sys
    --setenv=SIMULATE_FE=1
    --setenv=GST_REGISTRY=/tmp/.gst-registry-neutrino.bin
    --chdir=/
  )

  # shellcheck source=gst-env.sh
  source "$(dirname "${BASH_SOURCE[0]}")/gst-env.sh"

  for d in "${GST_DETECTED_PLUGIN_DIRS[@]}"; do
    nspawn_args+=(--bind="${d}")
  done
  if [[ ${#GST_DETECTED_PLUGIN_DIRS[@]} -gt 0 ]]; then
    gst_plugin_system_path="$(join_colon "${GST_DETECTED_PLUGIN_DIRS[@]}")"
    nspawn_args+=(--setenv=GST_PLUGIN_SYSTEM_PATH_1_0="${gst_plugin_system_path}")
    nspawn_args+=(--setenv=GST_PLUGIN_SYSTEM_PATH="${gst_plugin_system_path}")
  fi

  if [[ -n "${GST_DETECTED_SCANNER_DIR}" ]]; then
    nspawn_args+=(--bind="${GST_DETECTED_SCANNER_DIR}")
  fi
  if [[ -n "${GST_DETECTED_SCANNER}" ]]; then
    nspawn_args+=(--setenv=GST_PLUGIN_SCANNER="${GST_DETECTED_SCANNER}")
  fi

  exec sudo systemd-nspawn "${nspawn_args[@]}" "${CHROOT_BIN}" "$@"
else
  echo "[run-local] systemd-nspawn not found. Try: sudo chroot \"${RUNTIME_DIR}\" ${CHROOT_BIN}" >&2
  exit 1
fi
