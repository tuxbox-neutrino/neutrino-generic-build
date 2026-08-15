#!/usr/bin/env bash
set -euo pipefail

host_display="${DISPLAY:-}"
if [[ -n "${RUN_NEUTRINO_DISPLAY:-}" ]]; then
  DISPLAY="${RUN_NEUTRINO_DISPLAY}"
elif [[ -n "${host_display}" ]]; then
  DISPLAY="${host_display}"
else
  DISPLAY=":99"
fi
BACKEND="${NEUTRINO_HEADLESS_BACKEND:-xvfb}"
NEUTRINO_PREFIX="${NEUTRINO_PREFIX:-/usr}"
INSTALL_DIR="${NEUTRINO_INSTALL_DIR:-}"
BUILD_DIR="${NEUTRINO_BUILD_DIR:-}"
PROOT_ROOT="${PROOT_ROOT:-}"
PROOT_BIN="${PROOT_BIN:-}"

if [[ -z "${INSTALL_DIR}" ]]; then
  echo "[run] NEUTRINO_INSTALL_DIR is not set." >&2
  exit 1
fi

NEUTRINO_BIN="${INSTALL_DIR}${NEUTRINO_PREFIX}/bin/neutrino"
if [[ ! -x "${NEUTRINO_BIN}" && -n "${BUILD_DIR}" && -x "${BUILD_DIR}/src/neutrino" ]]; then
  NEUTRINO_BIN="${BUILD_DIR}/src/neutrino"
fi

if [[ ! -x "${NEUTRINO_BIN}" ]]; then
  echo "[run] Neutrino binary not found at ${NEUTRINO_BIN}" >&2
  exit 1
fi

wrapper_cmd=()
wrapper_is_gdb=0
gdb_bin=""
gdb_prefix_opts=()
gdb_post_args=()
gdb_user_commands_raw="${NEUTRINO_GDB_COMMANDS:-}"
gdb_autorun="${NEUTRINO_GDB_AUTORUN:-1}"
if [[ -n "${NEUTRINO_RUN_WRAPPER:-}" ]]; then
  # shellcheck disable=SC2206 # deliberate splitting to preserve args
  raw_wrapper=(${NEUTRINO_RUN_WRAPPER})
  if [[ ${#raw_wrapper[@]} -gt 0 ]]; then
    printf '[run] Using wrapper: %s\n' "${raw_wrapper[*]}"
    wrapper_base="$(basename "${raw_wrapper[0]}")"
    if [[ "${wrapper_base}" == gdb || "${wrapper_base}" == gdb* ]]; then
      wrapper_is_gdb=1
      gdb_bin="${raw_wrapper[0]}"
      extras=("${raw_wrapper[@]:1}")
      args_index=-1
      for ((i = 0; i < ${#extras[@]}; i++)); do
        if [[ "${extras[$i]}" == "--args" ]]; then
          args_index=$i
          break
        fi
        gdb_prefix_opts+=("${extras[$i]}")
      done
      if [[ ${args_index} -ge 0 ]]; then
        gdb_post_args=("${extras[@]:args_index}")
      else
        gdb_post_args=(--args)
      fi
    else
      wrapper_cmd=("${raw_wrapper[@]}")
    fi
  fi
fi

gdb_build_wrapper() {
  local bin="${gdb_bin:-gdb}"
  wrapper_cmd=("${bin}")
  local quiet_present=0
  for opt in "${gdb_prefix_opts[@]}"; do
    if [[ "${opt}" == "--quiet" || "${opt}" == "-q" ]]; then
      quiet_present=1
      break
    fi
  done
  if [[ ${quiet_present} -eq 0 ]]; then
    wrapper_cmd+=("--quiet")
  fi
  wrapper_cmd+=("${gdb_prefix_opts[@]}")

  gdb_add_ex() {
    wrapper_cmd+=(-ex)
    wrapper_cmd+=("$1")
  }

  if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
    gdb_add_ex "set environment LD_LIBRARY_PATH=${LD_LIBRARY_PATH}"
  fi
  if [[ -n "${PATH:-}" ]]; then
    gdb_add_ex "set environment PATH=${PATH}"
  fi
  if [[ -n "${LIBGL_DRIVERS_PATH:-}" ]]; then
    gdb_add_ex "set environment LIBGL_DRIVERS_PATH=${LIBGL_DRIVERS_PATH}"
  fi
  if [[ -n "${LIBGL_ALWAYS_SOFTWARE:-}" ]]; then
    gdb_add_ex "set environment LIBGL_ALWAYS_SOFTWARE=${LIBGL_ALWAYS_SOFTWARE}"
  fi
  gdb_add_ex "set environment SIMULATE_FE=1"
  gdb_add_ex "set environment DISPLAY=${DISPLAY}"

  if [[ -n "${gdb_user_commands_raw}" ]]; then
    IFS=';' read -r -a gdb_user_cmds <<< "${gdb_user_commands_raw}"
    for raw_cmd in "${gdb_user_cmds[@]}"; do
      cmd_trimmed="$(echo "${raw_cmd}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      if [[ -n "${cmd_trimmed}" ]]; then
        gdb_add_ex "${cmd_trimmed}"
      fi
    done
  fi

  if [[ "${gdb_autorun}" != "0" ]]; then
    gdb_add_ex "run"
  fi

  wrapper_cmd+=("${gdb_post_args[@]}")
}

interpret_exit_code() {
  local rc="${1:-0}"
  case "${rc}" in
    0)
      ;;
    1)
      echo "[run] Exit requested: shutdown (code 1)"
      rc=0
      ;;
    2)
      echo "[run] Exit requested: reboot (code 2)"
      rc=0
      ;;
    3)
      echo "[run] Exit requested: restart (code 3)"
      rc=0
      ;;
    255)
      echo "[run] Neutrino exited with error (code 255)"
      ;;
    *)
      echo "[run] Neutrino exited with code ${rc}"
      ;;
  esac
  return "${rc}"
}

run_and_report() {
  # Capture the child's exit status without letting "set -e" abort here first,
  # so interpret_exit_code() always runs (a clean shutdown must not look like a
  # wrapper failure).
  local rc=0
  "$@" || rc=$?
  interpret_exit_code "${rc}"
}

cleanup() {
  if [[ -n "${XVFB_PID:-}" ]]; then
    kill "${XVFB_PID}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${WESTON_PID:-}" ]]; then
    kill "${WESTON_PID}" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

effective_backend="${BACKEND}"

case "${BACKEND}" in
  xvfb)
    display_socket=""
    display_id=""
    case "${DISPLAY}" in
      :*)
        display_id="${DISPLAY#:}"
        ;;
      unix/:*)
        display_id="${DISPLAY#unix/:}"
        ;;
    esac
    display_id="${display_id%%.*}"
    if [[ -n "${display_id}" ]]; then
      display_socket="/tmp/.X11-unix/X${display_id}"
    fi
    if [[ -n "${display_socket}" && -S "${display_socket}" ]]; then
      echo "[run] Reusing existing X11 socket ${display_socket}"
      effective_backend="x11-host"
    else
      if ! command -v Xvfb >/dev/null 2>&1; then
        echo "[run] Xvfb not installed. Install package 'xvfb'." >&2
        exit 1
      fi
      Xvfb "${DISPLAY}" -screen 0 1280x720x24 -nolisten tcp &
      XVFB_PID=$!
      effective_backend="xvfb"
      sleep 1
    fi
    ;;
  weston)
    if ! command -v weston >/dev/null 2>&1; then
      echo "[run] Weston not installed. Install package 'weston'." >&2
      exit 1
    fi
    weston --backend=headless --socket=wayland-99 &
    WESTON_PID=$!
    export WAYLAND_DISPLAY=wayland-99
    effective_backend="weston"
    sleep 2
    ;;
  *)
    echo "[run] Unsupported backend: ${BACKEND}" >&2
    exit 1
    ;;
esac

echo "[run] Launching Neutrino using ${effective_backend} on DISPLAY=${DISPLAY}"

export DISPLAY
export NEUTRINO_HEADLESS=1
export SIMULATE_FE=1
# A clean shutdown on the PC should exit 0 rather than signal poweroff/reboot
# through the status. Default to POSIX codes unless the caller overrides it.
export NEUTRINO_EXIT_CODES="${NEUTRINO_EXIT_CODES:-posix}"

if [[ -n "${PROOT_ROOT}" ]]; then
  if [[ -z "${PROOT_BIN}" ]]; then
    if command -v proot >/dev/null 2>&1; then
      PROOT_BIN="$(command -v proot)"
    elif [[ -n "${ROOT_DIR:-}" && -x "${ROOT_DIR}/tools/proot" ]]; then
      PROOT_BIN="${ROOT_DIR}/tools/proot"
    fi
  fi
  if [[ -z "${PROOT_BIN}" ]]; then
    echo "[run] No proot binary found. Install it via 'sudo apt install proot' or run 'make tools-install-proot'." >&2
    exit 2
  fi
  target_bin="${NEUTRINO_PREFIX}/bin/neutrino"
  proot_args=(
    -S "${PROOT_ROOT}"
    -b /dev
    -b /proc
    -b /sys
    -b /tmp/.X11-unix
    -b /usr/bin/env
    -b /bin/bash
    -b /bin/sh
    -b /lib
    -b /lib64
    -b /etc
  )
  # shellcheck source=gst-env.sh
  source "$(dirname "${BASH_SOURCE[0]}")/gst-env.sh"

  existing_ld="${LD_LIBRARY_PATH:-}"
  ld_parts=()
  if [[ -n "${existing_ld}" ]]; then
    ld_parts+=("${existing_ld}")
  fi
  if [[ -d /usr/lib ]]; then
    proot_args+=(-b /usr/lib:/host/usr/lib)
    ld_parts+=("/host/usr/lib")
    if [[ -d /usr/lib/x86_64-linux-gnu ]]; then
      ld_parts+=("/host/usr/lib/x86_64-linux-gnu")
    fi
  fi
  if [[ ${#ld_parts[@]} -gt 0 ]]; then
    export LD_LIBRARY_PATH="$(join_colon "${ld_parts[@]}")"
  fi

  gst_plugin_parts=()
  for d in "${GST_DETECTED_PLUGIN_DIRS[@]}"; do
    gst_plugin_parts+=("/host${d}")
  done
  if [[ -n "${GST_PLUGIN_SYSTEM_PATH_1_0:-}" ]]; then
    gst_plugin_parts+=("${GST_PLUGIN_SYSTEM_PATH_1_0}")
  fi
  if [[ ${#gst_plugin_parts[@]} -gt 0 ]]; then
    export GST_PLUGIN_SYSTEM_PATH_1_0="$(join_colon "${gst_plugin_parts[@]}")"
    export GST_PLUGIN_SYSTEM_PATH="${GST_PLUGIN_SYSTEM_PATH:-${GST_PLUGIN_SYSTEM_PATH_1_0}}"
  fi
  if [[ -z "${GST_PLUGIN_SCANNER:-}" && -n "${GST_DETECTED_SCANNER}" ]]; then
    export GST_PLUGIN_SCANNER="/host${GST_DETECTED_SCANNER}"
  fi
  if [[ -z "${GST_REGISTRY:-}" ]]; then
    export GST_REGISTRY="/tmp/.gst-registry-neutrino.bin"
  fi
  existing_path="${PATH:-}"
  path_parts=()
  if [[ -n "${existing_path}" ]]; then
    path_parts+=("${existing_path}")
  fi
  if [[ -d /usr/bin ]]; then
    proot_args+=(-b /usr/bin:/host/usr/bin)
    path_parts+=("/host/usr/bin")
  fi
  if [[ -d /usr/sbin ]]; then
    proot_args+=(-b /usr/sbin:/host/usr/sbin)
    path_parts+=("/host/usr/sbin")
  fi
  if [[ ${#path_parts[@]} -gt 0 ]]; then
    export PATH="$(join_colon "${path_parts[@]}")"
  fi
  if [[ -d /usr/lib/x86_64-linux-gnu/dri ]]; then
    libgl_parts=("/host/usr/lib/x86_64-linux-gnu/dri")
    if [[ -n "${LIBGL_DRIVERS_PATH:-}" ]]; then
      libgl_parts+=("${LIBGL_DRIVERS_PATH}")
    else
      libgl_parts+=("/usr/lib/x86_64-linux-gnu/dri")
    fi
    export LIBGL_DRIVERS_PATH="$(join_colon "${libgl_parts[@]}")"
  fi
  if [[ -n "${ROOT_DIR:-}" && -d "${ROOT_DIR}/tools/proot-libs" ]]; then
    proot_args+=(-b "${ROOT_DIR}/tools/proot-libs:/proot-libs")
    export LD_LIBRARY_PATH="${ROOT_DIR}/tools/proot-libs:${LD_LIBRARY_PATH:-}"
  fi
  if [[ -z "${LIBGL_ALWAYS_SOFTWARE:-}" ]]; then
    export LIBGL_ALWAYS_SOFTWARE=1
  fi
  if [[ ${wrapper_is_gdb} -eq 1 ]]; then
    gdb_build_wrapper
  fi
  if [[ ${#wrapper_cmd[@]} -gt 0 ]]; then
    run_and_report "${PROOT_BIN}" "${proot_args[@]}" "${wrapper_cmd[@]}" "${target_bin}" "$@"
    exit $?
  fi
  run_and_report "${PROOT_BIN}" "${proot_args[@]}" "${target_bin}" "$@"
  exit $?
fi

if [[ ${wrapper_is_gdb} -eq 1 ]]; then
  gdb_build_wrapper
fi
if [[ ${#wrapper_cmd[@]} -gt 0 ]]; then
  run_and_report "${wrapper_cmd[@]}" "${NEUTRINO_BIN}" "$@"
  exit $?
fi

run_and_report "${NEUTRINO_BIN}" "$@"
exit $?
