#!/usr/bin/env bash
# Attempt to gracefully stop host processes that keep the staged sysroot busy.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

runtime_root="${NEUTRINO_RUNTIME_PREFIX:-${repo_root}/root}"
sysroot_prefix="${NEUTRINO_INSTALL_DIR:-${repo_root}/artifacts/sysroot}"
neutrino_prefix="${NEUTRINO_PREFIX:-/usr}"
sysroot_target="${sysroot_prefix%/}${neutrino_prefix}"

unique_paths=()
add_path() {
  local p="$1"
  [[ -n "$p" ]] || return 0
  [[ -d "$p" ]] || return 0
  for existing in "${unique_paths[@]}"; do
    [[ "$existing" == "$p" ]] && return 0
  done
  unique_paths+=("$p")
}

add_path "$runtime_root"
add_path "$sysroot_target"
add_path "${repo_root}/root/usr"
add_path "${repo_root}/artifacts/sysroot/usr"

# Stop proot-based run-now sessions.
if command -v ps >/dev/null 2>&1 && command -v awk >/dev/null 2>&1; then
  if [[ -d "$runtime_root" ]]; then
    proot_pids=$(ps -eo pid=,args= | awk -v root="$runtime_root" '
      index($0, "proot") && index($0, " -S ") && index($0, root) { print $1 }')
    if [[ -n "${proot_pids:-}" ]]; then
      echo "[distclean] Terminating proot sessions using ${runtime_root}"
      echo "$proot_pids" | xargs -r kill >/dev/null 2>&1 || true
      sleep 1
    fi
  fi
fi

if command -v pgrep >/dev/null 2>&1; then
  if pids=$(pgrep -f "/usr/bin/neutrino"); then
    echo "[distclean] Terminating Neutrino processes (${pids})"
    echo "$pids" | xargs -r kill >/dev/null 2>&1 || true
    sleep 1
  fi
fi

# Stop containers still mounting this workspace.
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    allowed_image="${NEUTRINO_DOCKER_IMAGE:-neutrino-dev}"
    allowed_prefix="${NEUTRINO_DOCKER_NAME_PREFIX:-build-}"
    while IFS= read -r container_id; do
      [[ -n "$container_id" ]] || continue
      image_name=$(docker inspect -f '{{.Config.Image}}' "$container_id" 2>/dev/null || true)
      case "${image_name}" in
        "${allowed_image}"|${allowed_image}:*|"${allowed_image}"-*) ;;
        *) continue ;;
      esac
      mounts=$(docker inspect -f '{{range .Mounts}}{{.Source}} {{end}}' "$container_id" 2>/dev/null || true)
      if [[ -n "$mounts" ]]; then
        repo_in_use=0
        for mount_point in $mounts; do
          if [[ "$repo_root" == "$mount_point"* || "$mount_point" == "$repo_root"* ]]; then
            repo_in_use=1
            break
          fi
        done
        if [[ $repo_in_use -eq 1 ]]; then
          container_name=$(docker inspect -f '{{.Name}}' "$container_id" 2>/dev/null | sed 's#^/##')
          if [[ -n "$allowed_prefix" && "${container_name}" != "${allowed_prefix}"* ]]; then
            continue
          fi
          echo "[distclean] Stopping Docker container ${container_name:-$container_id}"
          docker stop "$container_id" >/dev/null 2>&1 || true
        fi
      fi
    done < <(docker ps -q)
  fi
fi

# Last resort: advise user if the directories are still busy.
if command -v fuser >/dev/null 2>&1; then
  for path in "${unique_paths[@]}"; do
    if fuser -m "$path" >/dev/null 2>&1; then
      echo "[distclean] Warning: resources still busy for ${path}. Close applications using this directory if cleanup fails." >&2
    fi
  done
fi
