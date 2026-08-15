#!/usr/bin/env bash
# Stage shared libraries from the container root into the runtime prefix so the
# Neutrino binary can be launched directly on the host without chroot/proot.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <runtime-prefix>" >&2
  exit 1
fi

runtime_prefix="$1"
runtime_prefix="${runtime_prefix%/}"
neutrino_bin="${runtime_prefix}/usr/bin/neutrino"
compat_dir="${runtime_prefix}/usr/lib/compat"

if [[ ! -x "${neutrino_bin}" ]]; then
  echo "[stage-libs] Neutrino binary not found at ${neutrino_bin}. Run 'make neutrino' first." >&2
  exit 1
fi

mkdir -p "${compat_dir}"
ln -sfn compat "${runtime_prefix}/usr/lib/c"
ln -sfn tuxbox "${runtime_prefix}/usr/lib/t"

missing_libs=()

skip_runtime_copy() {
  case "$(basename "$1")" in
    libc.so.*|libm.so.*|libpthread.so.*|libdl.so.*|librt.so.*|ld-linux*.so*|libresolv.so.*|libnsl.so.*|libnss_*.so*|libc-*.so|libm-*.so|libpthread-*.so|libdl-*.so|libgcc_s.so.*|libstdc++.so.*)
      return 0
      ;;
  esac
  return 1
}

mapfile -t deps < <(ldd "${neutrino_bin}")

for line in "${deps[@]}"; do
  case "${line}" in
    *"=>"*"not found"*)
      lib_name="${line%% *}"
      lib_name="${lib_name//[$' \t\r\n']/}"
      missing_libs+=("${lib_name}")
      continue
      ;;
  esac

  path=""
  if [[ "${line}" == /* ]]; then
    path="${line%% (*}"
  elif [[ "${line}" == *"=>"* ]]; then
    # shellcheck disable=SC2001
    path="$(echo "${line}" | sed -E 's/.*=> ([^ ]+).*/\1/')"
  fi

  if [[ -z "${path}" || "${path}" == "statically" ]]; then
    continue
  fi
  if [[ "${path}" == "${runtime_prefix}"* ]]; then
    continue
  fi
  if skip_runtime_copy "${path}"; then
    continue
  fi
  if [[ ! -e "${path}" ]]; then
    continue
  fi

  rsync -aL --no-owner --no-group --ignore-existing "${path}" "${compat_dir}/"
  base_name="$(basename "${path}")"
  if [[ ! -e "${runtime_prefix}/usr/lib/${base_name}" ]]; then
    ln -sfn "compat/${base_name}" "${runtime_prefix}/usr/lib/${base_name}"
  fi
done

if [[ ${#missing_libs[@]} -ne 0 ]]; then
  unresolved=()
  for lib in "${missing_libs[@]}"; do
    candidate=$(ldconfig -p 2>/dev/null | awk -v name="${lib}" '$1 == name { print $4; exit }') || candidate=""
    if [[ -n "${candidate}" && -e "${candidate}" ]]; then
      rsync -aL --no-owner --no-group --ignore-existing "${candidate}" "${compat_dir}/"
      base_name="$(basename "${candidate}")"
      if [[ ! -e "${runtime_prefix}/usr/lib/${base_name}" ]]; then
        ln -sfn "compat/${base_name}" "${runtime_prefix}/usr/lib/${base_name}"
      fi
    else
      unresolved+=("${lib}")
    fi
  done
  if [[ ${#unresolved[@]} -ne 0 ]]; then
    printf '[stage-libs] Warning: the following libraries are still unresolved after staging:\n' >&2
    for lib in "${unresolved[@]}"; do
      printf '  %s\n' "${lib}" >&2
    done
    printf '[stage-libs] Install the matching packages on the host or extend scripts/stage_runtime_libs.sh.\n' >&2
    exit 1
  fi
fi
