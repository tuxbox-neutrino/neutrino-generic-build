#!/usr/bin/env bash
# Runtime wrapper for the staged Neutrino binary.
#
# runtime-sync installs this file verbatim as <prefix>/bin/neutrino, next to the
# real executable, which is staged alongside it as neutrino.real. Everything is
# resolved relative to the wrapper's own location, so the staged prefix can be
# moved without rebuilding.
#
# Note on the exit status: `set -e` aborts as soon as "$real_bin" returns
# non-zero, so handle_exit_code below is only ever reached for a clean exit.
# Neutrino's own 1/2/3 shutdown codes therefore arrive at the caller unchanged,
# which is what scripts/neutrino_run_report.sh expects to decode.
set -euo pipefail

bin_dir="$(cd "$(dirname "$0")" && pwd)"
real_bin="$bin_dir/neutrino.real"
# Both refusals below happen before Neutrino runs, so neither may exit 1, 2
# or 3: those are its legacy poweroff/reboot/restart codes, and
# scripts/neutrino_run_report.sh would decode them as a clean shutdown and
# let `make run` exit 0 for a Neutrino that never started. 69 is
# EX_UNAVAILABLE.
if [[ ! -x "$real_bin" ]]; then
  echo "[neutrino-wrapper] Missing binary: $real_bin" >&2
  exit 69
fi

# A plain `cd` would abort here under `set -e` with exactly that bare 1.
if ! runtime_lib="$(cd "$bin_dir/../lib" 2>/dev/null && pwd)"; then
  echo "[neutrino-wrapper] Missing runtime libraries: $bin_dir/../lib" >&2
  exit 69
fi
search_paths=("$runtime_lib" "$runtime_lib/c" "$runtime_lib/t")
ld_path=""
for p in "${search_paths[@]}"; do
  [[ -d "$p" ]] || continue
  if [[ -z "$ld_path" ]]; then
    ld_path="$p"
  else
    ld_path="$ld_path:$p"
  fi
done
if [[ -n "$ld_path" ]]; then
  if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
    export LD_LIBRARY_PATH="$ld_path:$LD_LIBRARY_PATH"
  else
    export LD_LIBRARY_PATH="$ld_path"
  fi
fi

lua_share=""
if lua_share_tmp="$(cd "$bin_dir/../share/lua" 2>/dev/null && pwd)"; then
  lua_share="$lua_share_tmp"
fi
if [[ -n "$lua_share" ]]; then
  lua_path_segments=()
  for ver in 5.1 5.2 5.3; do
    if [[ -d "$lua_share/$ver" ]]; then
      lua_path_segments+=("$lua_share/$ver/?.lua" "$lua_share/$ver/?/init.lua")
    fi
  done
  if [[ -d "$lua_share" ]]; then
    lua_path_segments+=("$lua_share/?.lua" "$lua_share/?/init.lua")
  fi
  if [[ "${#lua_path_segments[@]}" -gt 0 ]]; then
    lua_path_join="${lua_path_segments[0]}";
    for ((i=1; i<${#lua_path_segments[@]}; ++i)); do
      lua_path_join="$lua_path_join;${lua_path_segments[i]}";
    done
    if [[ -n "${LUA_PATH:-}" ]]; then
      export LUA_PATH="$lua_path_join;${LUA_PATH}"
    else
      export LUA_PATH="$lua_path_join"
    fi
  fi
fi

if [[ -z "${SIMULATE_FE:-}" ]]; then
  export SIMULATE_FE=1
fi
handle_exit_code() {
  local rc="${1:-0}"
  case "$rc" in
    0) ;;
    1) echo "[neutrino-wrapper] Exit requested: shutdown (code 1)"; rc=0 ;;
    2) echo "[neutrino-wrapper] Exit requested: reboot (code 2)"; rc=0 ;;
    255) echo "[neutrino-wrapper] Exit error (code 255)"; ;;
    *) echo "[neutrino-wrapper] Exit with code $rc"; ;;
  esac
  return "$rc"
}

"$real_bin" "$@"
rc=$?
handle_exit_code "$rc"
rc=$?
exit "$rc"
