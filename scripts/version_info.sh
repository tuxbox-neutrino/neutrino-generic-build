#!/usr/bin/env bash
# Report the version of the Neutrino source tree as JSON.
#
# One rule, deliberately: <base>+git<UTC timestamp>.g<hash>, where base comes
# from configure.ac. The previous version had two rules and picked between them
# silently -- with tags in the clone `git describe` decided the name, without
# them it fell back to configure.ac. `git clone --depth 1` produces a tagless
# clone, so CI and a developer machine named the same commit differently and
# neither was wrong. An artefact version has to be a function of the commit, not
# of how the commit was fetched.
#
# Nothing is lost by dropping the describe branch: ver_micro *is* the commit
# distance from the anchor tag (ver_micro=27 <-> v2026.8-27-g9c028a658f), so
# base and describe encode the same number.
set -euo pipefail

# Inherited git environment would silently point every command below at another
# repository -- under `git rebase --exec`, inside a hook, under `git bisect
# run`. The path check further down cannot see that: it asks git, and git
# answers about the repository it was pointed at.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

SRC_DIR=${SRC_DIR:-sources/neutrino}
if [[ ! -d ${SRC_DIR} ]]; then
  echo "version_info: source tree not found: ${SRC_DIR}" >&2
  echo "version_info: set SRC_DIR to the Neutrino source directory." >&2
  exit 1
fi

# Decide what kind of tree this is before cd'ing anywhere: SRC_DIR defaults to a
# relative path, so `git -C` has to run from here.
#
# Three outcomes, and keeping them apart is the point. A tarball export has no
# .git and legitimately yields the bare base version. A .git that exists but
# cannot be used -- unreadable, foreign-owned ("dubious ownership" in a
# container), no commits yet -- used to give exactly the same answer, and that
# answer sorts below every real artefact and would never be offered as an
# upgrade. That one aborts.
GIT_MODE=none
if [[ -e "${SRC_DIR}/.git" ]]; then
  git_toplevel="$(git -C "${SRC_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
  src_real="$(realpath "${SRC_DIR}" 2>/dev/null || true)"
  if [[ -z "${git_toplevel}" ]]; then
    echo "version_info: ${SRC_DIR}/.git exists but git cannot use it." >&2
    echo "version_info: refusing to guess a version -- the result would sort" >&2
    echo "version_info: below every properly versioned package." >&2
    exit 1
  fi
  # A plain directory inside somebody else's worktree answers with *their*
  # toplevel. sources/ lives inside this build repository's worktree, so that is
  # not a hypothetical. git always reports the physical path, which is why
  # realpath is the right thing to compare against -- checked against the
  # sources/neutrino symlink, a symlinked parent, and a .git file from a linked
  # worktree.
  if [[ "${git_toplevel}" != "${src_real}" ]]; then
    echo "version_info: ${SRC_DIR} is not the root of its own git repository" >&2
    echo "version_info: (git reports ${git_toplevel}); treating it as an export." >&2
  else
    GIT_MODE=repo
  fi
fi

cd "${SRC_DIR}"

if [[ ! -f configure.ac ]]; then
  echo "version_info: no configure.ac in ${SRC_DIR}" >&2
  exit 1
fi

read_ver() {
  local name=$1 line value
  line="$(grep -E "^define\(${name}," configure.ac || true)"
  if [[ -z "${line}" ]]; then
    echo "version_info: configure.ac has no define(${name}, ...)" >&2
    exit 1
  fi
  value="$(printf '%s' "${line}" | sed -E "s/define\(${name}, ?([^\)]*)\).*/\1/" | tr -d '\"')"
  # Empty and non-numeric both used to pass straight through and produce
  # versions like "2026.8." or "..", which no consumer could have caught.
  if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
    echo "version_info: configure.ac define(${name}, ...) is not a number: '${value}'" >&2
    exit 1
  fi
  printf '%s' "${value}"
}

# `|| exit 1` spelled out: read_ver's own `exit` only ends the subshell the
# command substitution runs in. errexit does propagate the failed assignment
# here, but relying on that is how a check ends up not checking.
MAJOR=$(read_ver ver_major) || exit 1
MINOR=$(read_ver ver_minor) || exit 1
MICRO=$(read_ver ver_micro) || exit 1
VERSION="${MAJOR}.${MINOR}.${MICRO}"

TAG=""
HASH=""
COMMIT_DATE=""
DIRTY=""
if [[ "${GIT_MODE}" == "repo" ]]; then
  # A fixed length, never the automatic one: git derives it from the number of
  # objects in the repository, so the same commit abbreviates to 7 characters in
  # a shallow clone and 10 in a full one. core.abbrev can move it as well.
  HASH="$(git rev-parse --short=10 HEAD 2>/dev/null || true)"
  if [[ -z "${HASH}" ]]; then
    echo "version_info: ${SRC_DIR} is a git repository without commits." >&2
    exit 1
  fi
  # TZ=UTC with format-local, so the number does not travel with whoever builds.
  # Plain `format:` would be deterministic too, but it uses the offset recorded
  # in the commit, which is not comparable across contributors in other zones.
  COMMIT_DATE="$(TZ=UTC git show -s --format=%cd --date=format-local:%Y%m%d%H%M%S HEAD 2>/dev/null || true)"
  # Tracked files only. autogen leaves untracked artefacts behind and those are
  # not a change to the source.
  if ! git diff --quiet HEAD -- 2>/dev/null; then
    DIRTY="~dirty"
  fi
  # Informational only. This one *is* clone-shape dependent -- a shallow clone
  # has no tags to describe against -- which is exactly why it no longer decides
  # the package version.
  TAG="$(git describe --tags --dirty --always 2>/dev/null || true)"
fi

if [[ -n "${HASH}" && -n "${COMMIT_DATE}" ]]; then
  # ~dirty sorts *below* the clean build in dpkg's ordering, deliberately. With
  # +dirty a patched CI build would outrank the clean release and apt would
  # never come back to it.
  PACKAGE="${VERSION}+git${COMMIT_DATE}.g${HASH}${DIRTY}"
else
  PACKAGE="${VERSION}"
fi

# The filename form. dpkg wants the '+', GitHub does not: release assets with
# special characters get renamed, and an uploader that does not encode the name
# reads '+' as a space and writes it as '.', leaving the download link pointing
# at nothing. So the version keeps the '+' and the filename gets a dot.
#
# The order of the two substitutions matters: '+' has to become '.' before the
# sanitiser runs, because the sanitiser would otherwise turn it into '-' and the
# separator would read as a hyphen. (It also turns the '~' of ~dirty into '-',
# which is fine -- slug names files, it never orders packages.)
slug=$(printf '%s' "${PACKAGE}" | tr '+' '.' | tr -c '[:alnum:]._-' '-')
slug=${slug#-}; slug=${slug%-}
[ -n "${slug}" ] || slug="dev"

cat <<JSON
{
  "major": "${MAJOR}",
  "minor": "${MINOR}",
  "micro": "${MICRO}",
  "base": "${VERSION}",
  "package": "${PACKAGE}",
  "git_tag": "${TAG}",
  "git_hash": "${HASH}",
  "pretty": "${PACKAGE}",
  "slug": "${slug}"
}
JSON
