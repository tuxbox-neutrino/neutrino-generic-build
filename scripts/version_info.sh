#!/usr/bin/env bash
set -euo pipefail

SRC_DIR=${SRC_DIR:-sources/neutrino}
if [[ ! -d ${SRC_DIR} ]]; then
  echo "sources/neutrino not found" >&2
  exit 1
fi

cd "${SRC_DIR}"

read_ver() {
  local name=$1
  grep -E "^define\(${name}," configure.ac | sed -E "s/define\(${name}, ?([^\)]*)\).*/\1/" | tr -d '\"'
}

MAJOR=$(read_ver ver_major)
MINOR=$(read_ver ver_minor)
MICRO=$(read_ver ver_micro)

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  TAG=$(git describe --tags --dirty --always 2>/dev/null || true)
  HASH=$(git rev-parse --short HEAD 2>/dev/null || true)
else
  TAG=""
  HASH=""
fi

VERSION="${MAJOR}.${MINOR}.${MICRO}"
VERSION_TAGGED=""
if [[ -n ${TAG} ]]; then
  # Accept tags that look like semantic versions (allow optional leading 'v' and suffixes)
  if [[ ${TAG} =~ ^v?[0-9]+(\.[0-9]+){1,2}([._-].*)?$ ]]; then
    VERSION_TAGGED=${TAG#v}
  else
    VERSION_TAGGED=${VERSION}
  fi
else
  VERSION_TAGGED=${VERSION}
fi

slug_source=${VERSION_TAGGED:-${VERSION}}
slug=$(printf '%s' "${slug_source}" | tr -c '[:alnum:]._+-' '-')
slug=${slug#-}; slug=${slug%-}
[ -n "${slug}" ] || slug="dev"

cat <<JSON
{
  "major": "${MAJOR}",
  "minor": "${MINOR}",
  "micro": "${MICRO}",
  "base": "${VERSION}",
  "package": "${VERSION_TAGGED}",
  "git_tag": "${TAG}",
  "git_hash": "${HASH}",
  "pretty": "${VERSION_TAGGED:-${VERSION}}",
  "slug": "${slug}"
}
JSON
