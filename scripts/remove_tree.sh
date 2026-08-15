#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
docker_image="${DOCKER_IMAGE:-neutrino-dev}"

remove_path() {
  local target="${1}"
  if [[ -z "${target}" ]]; then
    return 0
  fi
  # Safety: never delete working sources or plugins.
  local guard_prefixes=("${repo_root}/sources" "${repo_root}/plugins")
  for prefix in "${guard_prefixes[@]}"; do
    case "${target}" in
      "${prefix}"|${prefix}/*)
        echo "[distclean] Refusing to remove ${target} (protected source tree)" >&2
        return 0
        ;;
    esac
  done
  if [[ ! -e "${target}" ]]; then
    return 0
  fi
  if rm -rf --one-file-system "${target}" 2>/dev/null; then
    return 0
  fi
  if [[ ! -e "${target}" ]]; then
    return 0
  fi
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "[distclean] Retrying removal of ${target} via Docker root helper"
    docker run --rm \
      -e CLEANUP_TARGET="${target}" \
      -v "${repo_root}:${repo_root}" \
      -w "${repo_root}" \
      "${docker_image}" \
      bash -lc 'set -euo pipefail; target="${CLEANUP_TARGET:-}"; if [[ -n "${target}" && -e "${target}" ]]; then rm -rf --one-file-system "${target}" || rm -rf "${target}"; fi'
    if [[ ! -e "${target}" ]]; then
      return 0
    fi
  fi
  echo "[distclean] Unable to remove ${target}. Please delete it manually (sudo may be required)." >&2
  return 1
}

status=0
for path in "$@"; do
  if ! remove_path "$path"; then
    status=1
  fi
done

exit ${status}
