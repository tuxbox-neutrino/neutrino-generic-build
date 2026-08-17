#!/usr/bin/env bash
set -euo pipefail

# Simple helper to launch the built Neutrino binary with the matching GCC runtime
# on the host. This avoids GLIBCXX/ABI mismatches when using a newer toolchain
# than the host provides.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEUTRINO_BIN="${NEUTRINO_BIN:-$ROOT_DIR/root/usr/bin/neutrino}"

# Pick toolchain prefix (override with TOOLCHAIN_PREFIX or TOOLCHAIN_GCC_VERSION)
if [[ -n "${TOOLCHAIN_PREFIX:-}" ]]; then
  TOOLCHAIN_DIR="$TOOLCHAIN_PREFIX"
else
  gcc_ver="${TOOLCHAIN_GCC_VERSION:-}"
  if [[ -n "$gcc_ver" ]]; then
    if [[ "$gcc_ver" =~ ^[0-9]+$ ]]; then
      TOOLCHAIN_DIR="$(ls -1d "$ROOT_DIR"/artifacts/toolchains/gcc-"$gcc_ver".* 2>/dev/null | sort -V | tail -n1 || true)"
    else
      TOOLCHAIN_DIR="$ROOT_DIR/artifacts/toolchains/gcc-$gcc_ver"
    fi
  else
    # no version given: take newest available toolchain if present
    TOOLCHAIN_DIR="$(ls -1d "$ROOT_DIR"/artifacts/toolchains/gcc-* 2>/dev/null | sort -V | tail -n1 || true)"
  fi
fi

if [[ -n "${TOOLCHAIN_DIR:-}" && -d "$TOOLCHAIN_DIR" ]]; then
  export LD_LIBRARY_PATH="$TOOLCHAIN_DIR/lib64:$TOOLCHAIN_DIR/lib:$ROOT_DIR/root/usr/lib/compat:${LD_LIBRARY_PATH:-}"
else
  echo "[run-neutrino] Toolchain libs not found; starting with system libstdc++ (set TOOLCHAIN_GCC_VERSION or TOOLCHAIN_PREFIX to force)." >&2
  export LD_LIBRARY_PATH="$ROOT_DIR/root/usr/lib/compat:${LD_LIBRARY_PATH:-}"
fi

# shellcheck source=gst-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/gst-env.sh"

gst_plugin_paths=("${GST_DETECTED_PLUGIN_DIRS[@]}")
if [[ -n "${GST_PLUGIN_SYSTEM_PATH_1_0:-}" ]]; then
  gst_plugin_paths+=("${GST_PLUGIN_SYSTEM_PATH_1_0}")
fi
if [[ ${#gst_plugin_paths[@]} -gt 0 ]]; then
  export GST_PLUGIN_SYSTEM_PATH_1_0="$(join_colon "${gst_plugin_paths[@]}")"
  export GST_PLUGIN_SYSTEM_PATH="${GST_PLUGIN_SYSTEM_PATH:-${GST_PLUGIN_SYSTEM_PATH_1_0}}"
fi
if [[ -z "${GST_PLUGIN_SCANNER:-}" && -n "${GST_DETECTED_SCANNER}" ]]; then
  export GST_PLUGIN_SCANNER="${GST_DETECTED_SCANNER}"
fi
if [[ -z "${GST_REGISTRY:-}" ]]; then
  export GST_REGISTRY="/tmp/.gst-registry-neutrino.bin"
fi
export SIMULATE_FE="${SIMULATE_FE:-1}"
# On the PC a clean Neutrino shutdown should exit 0, not signal poweroff/reboot
# through the exit status. Default to POSIX codes unless the caller overrides it.
export NEUTRINO_EXIT_CODES="${NEUTRINO_EXIT_CODES:-posix}"

# Prevent multiple instances — avoids config corruption (e.g. lost satellite settings)
# Use pgrep -x to match only the exact process name (not paths containing "neutrino")
#
# Not `exit 1`: 1, 2 and 3 are the legacy exit codes for poweroff, reboot and
# restart, so neutrino_run_report.sh decoded this refusal as a clean shutdown --
# `make run` printed "Neutrino requested shutdown" and exited 0 for a Neutrino
# that never started. 75 is EX_TEMPFAIL: try again once the other one is gone.
existing_pid="$(pgrep -x neutrino.real 2>/dev/null | head -1 || true)"
if [[ -n "$existing_pid" ]]; then
  echo "[run-neutrino] ERROR: Neutrino is already running (PID $existing_pid)." >&2
  echo "[run-neutrino] Stop the existing instance first or use 'kill $existing_pid'." >&2
  exit 75
fi

exec "$NEUTRINO_BIN" "$@"
