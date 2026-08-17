#!/usr/bin/env bash
# Report the version of the Neutrino source tree as JSON.
#
# One rule, deliberately: <base>+git<UTC timestamp>.g<hash>, where base comes
# from configure.ac. The previous version had two rules and picked between them
# silently -- with a describable tag in the clone `git describe` decided the
# name, without one it fell back to configure.ac. `git clone --depth 1` fetches
# no history behind HEAD, so unless a tag sits on the fetched commit itself
# there is nothing to describe against; CI and a developer machine named the
# same commit differently and neither was wrong. An artefact version has to be a function of the commit, not
# of how the commit was fetched.
#
# The describe branch has to go because whether it answers at all depends on the
# clone -- a shallow one carries only a tag that sits exactly on HEAD, and never
# the history behind it -- so it cannot be the rule. What that costs is the exact commit
# distance: ver_micro is *not* that distance. Upstream bumps it in a commit of
# its own ("build (ci): bump configure.ac version"), where the two agree, and it
# then stands still while the distance keeps counting -- ver_micro=27 at
# distances 27 through 31 in the tree this was measured on, and 32 at 32,
# because that distance is the next bump. It restarts at 0 on
# a new version line (2026.7.53 -> 2026.8.0), so ver_micro on its own is not
# monotonic either; what never regresses is the three-part base, because
# ver_minor rises in the same commit. Within one base the commit timestamp
# orders the builds, and no further: two commits sharing a second are ordered by
# their hash, which is to say by chance, and a backdated committer date is
# ordered the wrong way round. docs/PACKAGING.*.md says so too.
set -euo pipefail

# Inherited git environment would silently point every command below at another
# repository -- under `git rebase --exec`, inside a hook, under `git bisect
# run`. The path check further down cannot see that: it asks git, and git
# answers about the repository it was pointed at.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
# GIT_CONFIG_PARAMETERS carries the `-c` options of a parent git invocation into
# every child, so it arrives in exactly the same situations as the variables
# above -- a hook, `rebase --exec`, `bisect run` -- and it outranks every other
# source of configuration, including the one exported below. Left in place, it
# could switch core.fsmonitor back on and hand a patched tree the clean release
# name; measured.
unset GIT_CONFIG_PARAMETERS

# core.fsmonitor is a third way for git to stop looking at a file, and the one
# the scan below cannot see: `ls-files -v` does not show the fsmonitor-valid
# bit, so nothing looks flagged and the ordinary diff takes the monitor's word
# for it. A monitor that misses a path -- a stale token, a hook that answers
# "nothing changed" -- then hands a patched tree the clean release name, and the
# answer depends on the builder's git configuration. Injected through the
# environment rather than repeated on every call: it outranks the repository and
# the user's own configuration. It does *not* outrank GIT_CONFIG_PARAMETERS,
# which is why that one is unset above rather than argued with.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=core.fsmonitor
export GIT_CONFIG_VALUE_0=false

# Replacement objects change what git reports for a commit without changing the
# commit id. A local `refs/replace/<HEAD>` moves the timestamp while the hash
# stays put, so two clones of the same commit would disagree again -- the same
# defect this script exists to remove, arriving through a different door.
export GIT_NO_REPLACE_OBJECTS=1

# CDPATH makes `cd` echo the directory it resolved to, on *stdout*. SRC_DIR is
# relative by default, so with CDPATH exported in the builder's profile the two
# `cd`s below would each emit a stray line: one into the path comparison, which
# then never matches and reopens the very guard it implements, and one into this
# script's own JSON, which the consumers then fail to parse.
unset CDPATH

SRC_DIR=${SRC_DIR:-sources/neutrino}
# `cd` reads a leading dash as an option, and `cd -` means something else
# entirely, so a directory whose name starts with one would be reported broken
# although git handles it. `git -C` needs no such help; the two `cd`s below do.
case "${SRC_DIR}" in
  -*) SRC_DIR="./${SRC_DIR}" ;;
esac
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
#
# `-L` alongside `-e`, because `-e` is false for a dangling symlink: a .git
# pointing at a directory that is gone would otherwise pass for a tarball.
GIT_MODE=none
if [[ -e "${SRC_DIR}/.git" || -L "${SRC_DIR}/.git" ]]; then
  git_toplevel="$(git -C "${SRC_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
  # `cd && pwd -P` rather than realpath(1): a builtin cannot be missing from
  # PATH. With realpath the guard failed *open* -- the substitution yielded an
  # empty string, the comparison below could then never match, and every build
  # on such a host silently produced the bare version.
  src_real="$(cd "${SRC_DIR}" 2>/dev/null && pwd -P || true)"
  if [[ -z "${git_toplevel}" || -z "${src_real}" ]]; then
    echo "version_info: ${SRC_DIR}/.git exists but git cannot use it." >&2
    echo "version_info: refusing to guess a version -- the result would sort" >&2
    echo "version_info: below every properly versioned package." >&2
    exit 1
  fi
  # A plain directory inside somebody else's worktree answers with *their*
  # toplevel. sources/ lives inside this build repository's worktree, so that is
  # not a hypothetical. git always reports the physical path, which is why the
  # physical path is what to compare against -- checked against the
  # sources/neutrino symlink, a symlinked parent, and a .git file from a linked
  # worktree.
  #
  # A mismatch aborts rather than falling back to the export path. git's
  # discovery walks *up*: when .git is something it skips instead of erroring on
  # -- a dangling symlink, an empty or half-written directory from an
  # interrupted clone -- it answers with the enclosing worktree, which is not
  # empty, merely wrong. sources/neutrino is cloned inside this repository's
  # worktree, so that is the production layout, and the export fallback turned
  # it into a bare version at exit 0.
  if [[ "${git_toplevel}" != "${src_real}" ]]; then
    echo "version_info: ${SRC_DIR} has a .git, but git reports" >&2
    echo "version_info: ${git_toplevel} as the repository root. That .git is" >&2
    echo "version_info: broken or foreign; refusing to stamp another" >&2
    echo "version_info: repository's commit on this tree." >&2
    exit 1
  fi
  GIT_MODE=repo
fi

cd "${SRC_DIR}"

TAG=""
HASH=""
COMMIT_DATE=""
DIRTY=""
if [[ "${GIT_MODE}" == "repo" ]]; then
  # The full object id, sliced to a fixed width. `--short=10` is a *minimum*:
  # git widens it whenever ten characters are ambiguous, so the same commit can
  # abbreviate to ten in one clone and eleven in another. Slicing cannot.
  full_hash="$(git rev-parse HEAD 2>/dev/null || true)"
  if [[ ! "${full_hash}" =~ ^[0-9a-f]{40}$ && ! "${full_hash}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "version_info: ${SRC_DIR} is a git repository without a usable HEAD." >&2
    exit 1
  fi
  HASH="${full_hash:0:10}"

  # TZ=UTC with format-local, so the number does not travel with whoever builds.
  # Plain `format:` would be deterministic too, but it uses the offset recorded
  # in the commit, which is not comparable across contributors in other zones.
  #
  # Guarded exactly like the hash. Ungated, a HEAD whose commit object is gone
  # -- or a git too old for `format-local:` -- produced JSON at exit 0 that
  # reported a hash next to a package version carrying none.
  # log.showSignature makes `git show` write signature lines to *stdout* ahead
  # of the format, so a signed HEAD on a machine with that option produced
  # "No signature\n20260805013000", failed the guard below, and took every
  # packaging target down with it.
  COMMIT_DATE="$(TZ=UTC git -c log.showSignature=false show -s \
    --format=%cd --date=format-local:%Y%m%d%H%M%S HEAD 2>/dev/null || true)"
  if [[ ! "${COMMIT_DATE}" =~ ^[0-9]{14}$ ]]; then
    echo "version_info: cannot read the commit date of HEAD in ${SRC_DIR}" >&2
    echo "version_info: (got '${COMMIT_DATE}'); refusing to fall back to a bare" >&2
    echo "version_info: version that would sort below every real package." >&2
    exit 1
  fi

  # Tracked files only. autogen leaves untracked artefacts behind and those are
  # not a change to the source.
  #
  # Three exit codes, and `! git diff --quiet` saw two: 0 clean, 1 modified,
  # anything beyond that a failure. An unreadable index exits 128 and used to be
  # reported as a perfectly ordinary ~dirty build.
  #
  # assume-unchanged and skip-worktree tell git to stop looking at a file, and
  # the dirty check then calls a patched tree clean -- the build takes the name
  # of the release it was patched away from. Reading the index is cheap, so the
  # second opinion below only runs where somebody has set one of the two.
  #
  # The scan is written to a file and read from there, rather than piped in from
  # a process substitution, because a process substitution's exit status cannot
  # be observed: a scan that failed read as "nothing is flagged", the ordinary
  # diff cannot see past a flag, and the hidden modification took the clean name.
  #
  # -z throughout: `ls-files` C-quotes any path holding a quote, a backslash or
  # a control character, and core.quotePath does not turn that off. The quoted
  # spelling matched no file, so such a path counted as absent and its
  # modification stayed hidden.
  scan="$(mktemp 2>/dev/null || true)"
  if [[ -z "${scan}" ]] || ! git ls-files -v -z > "${scan}" 2>/dev/null; then
    [[ -z "${scan}" ]] || rm -f "${scan}"
    echo "version_info: cannot tell whether ${SRC_DIR} is modified" >&2
    echo "version_info: (the index could not be read); refusing to guess." >&2
    exit 1
  fi

  # A lowercase tag means assume-unchanged, `S` means skip-worktree, and `s`
  # means both.
  flagged=0
  while IFS= read -r -d '' entry; do
    case "${entry:0:1}" in
      [a-z] | S) flagged=$((flagged + 1)) ;;
    esac
  done < "${scan}"

  diff_rc=0
  if [[ "${flagged}" -eq 0 ]]; then
    git diff --quiet HEAD -- 2>/dev/null || diff_rc=$?
  else
    # A copy of the real index with those bits cleared, rather than a fresh
    # `read-tree HEAD`: read-tree drops index-only entries, so a staged addition
    # disappeared and the same tree answered differently depending on whether
    # some unrelated path happened to be flagged. The copy also keeps the stat
    # cache, so nothing has to be re-hashed.
    tmp_index="$(mktemp 2>/dev/null || true)"
    real_index="$(git rev-parse --git-path index 2>/dev/null || true)"
    if [[ -z "${tmp_index}" || -z "${real_index}" || ! -f "${real_index}" ]] ||
       ! cp "${real_index}" "${tmp_index}" 2>/dev/null; then
      diff_rc=128
    else
      # One pass per flag: given both at once, `git update-index` clears
      # assume-unchanged and drops `--no-skip-worktree` on the floor, at exit 0
      # and whichever order they are written in. The skip-worktree bit stayed
      # set, and the modification behind it stayed hidden.
      #
      # The two flags do not mean the same thing about an absent file, so they
      # are not cleared over the same paths. skip-worktree is how a sparse
      # checkout says a file is deliberately not there; calling that a
      # modification would make a sparse checkout and a full clone of the same
      # commit disagree, so an absent skip-worktree path keeps its bit.
      # assume-unchanged says nothing of the kind -- it is a promise not to
      # change a file that is present -- so it is cleared whether the file is
      # there or not, and a deleted assume-unchanged file counts as the
      # modification it is. Exempting the whole repository on
      # `core.sparseCheckout` instead hid a patched *included* file.
      clear_rc=0
      while IFS= read -r -d '' entry; do
        case "${entry:0:1}" in
          [a-z]) printf '%s\0' "${entry:2}" ;;
        esac
      done < "${scan}" |
        GIT_INDEX_FILE="${tmp_index}" git update-index -z --no-assume-unchanged \
          --stdin 2>/dev/null || clear_rc=$?
      while IFS= read -r -d '' entry; do
        case "${entry:0:1}" in
          S | s)
            # `-e || -L`, because a tracked symlink whose target is missing is
            # not an absent path -- and Neutrino ships two of them.
            if [[ -e "${entry:2}" || -L "${entry:2}" ]]; then
              printf '%s\0' "${entry:2}"
            fi
            ;;
        esac
      done < "${scan}" |
        GIT_INDEX_FILE="${tmp_index}" git update-index -z --no-skip-worktree \
          --stdin 2>/dev/null || clear_rc=$?
      # Not ignored: a failure here leaves the bits in place, and the comparison
      # would then invent a version out of an error.
      if [[ "${clear_rc}" -ne 0 ]]; then
        diff_rc=128
      else
        GIT_INDEX_FILE="${tmp_index}" git diff --quiet HEAD -- 2>/dev/null || diff_rc=$?
      fi
    fi
    [[ -z "${tmp_index}" ]] || rm -f "${tmp_index}"
  fi
  rm -f "${scan}"
  case "${diff_rc}" in
    0) ;;
    1) DIRTY="~dirty" ;;
    *)
      echo "version_info: cannot tell whether ${SRC_DIR} is modified" >&2
      echo "version_info: (git diff exited ${diff_rc}); refusing to guess." >&2
      exit 1
      ;;
  esac

  # Informational only. This one *is* clone-shape dependent -- a shallow clone
  # has no history behind HEAD to describe against, and answers at all only if a
  # tag sits on HEAD itself -- which is exactly why it no longer decides the
  # package version.
  TAG="$(git describe --tags --dirty --always 2>/dev/null || true)"
fi

# The numbers come from the commit, not from the worktree. Read from the
# worktree, an edited configure.ac outranked the commit it was derived from:
# ver_micro 27 -> 99 gives 2026.8.99+git...~dirty, which sorts *above* the clean
# 2026.8.27+git..., and ~dirty stops meaning "below the clean build".
if [[ "${GIT_MODE}" == "repo" ]]; then
  CONFIGURE_SRC="HEAD:configure.ac in ${SRC_DIR}"
  if ! git cat-file -e HEAD:configure.ac 2>/dev/null; then
    echo "version_info: no configure.ac in HEAD of ${SRC_DIR}" >&2
    exit 1
  fi
  CONFIGURE_AC="$(git show HEAD:configure.ac 2>/dev/null || true)"
else
  CONFIGURE_SRC="configure.ac in ${SRC_DIR}"
  if [[ ! -f configure.ac ]]; then
    echo "version_info: no configure.ac in ${SRC_DIR}" >&2
    exit 1
  fi
  CONFIGURE_AC="$(cat configure.ac)"
fi

read_ver() {
  local name=$1 line value
  line="$(printf '%s\n' "${CONFIGURE_AC}" | grep -E "^define\(${name}," || true)"
  if [[ -z "${line}" ]]; then
    echo "version_info: ${CONFIGURE_SRC} has no define(${name}, ...)" >&2
    exit 1
  fi
  value="$(printf '%s' "${line}" | sed -E "s/define\(${name}, ?([^\)]*)\).*/\1/")"
  # One matching pair of quotes around the number is accepted; a quote anywhere
  # else is not. Deleting every quote wherever it sat repaired the value before
  # measuring it -- define(ver_micro, 2"7") normalised to 27 and travelled on as
  # though the source had said 27.
  case "${value}" in
    '"'*'"') value="${value#\"}"; value="${value%\"}" ;;
  esac
  # Empty and non-numeric both used to pass straight through and produce
  # versions like "2026.8." or "..", which no consumer could have caught.
  if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
    echo "version_info: ${CONFIGURE_SRC} define(${name}, ...) is not a number: '${value}'" >&2
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

# GIT_MODE alone decides the shape. The old `-n HASH && -n COMMIT_DATE` test let
# a failure inside the git block fall through to the bare version instead.
if [[ "${GIT_MODE}" == "repo" ]]; then
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
# Two substitutions, and both are part of the contract: '+' becomes '.', and the
# sanitiser then maps everything outside [A-Za-z0-9._-] to '-', which is what
# turns the '~' of ~dirty into '-dirty'. The order matters -- '+' has to become
# '.' first, or the sanitiser would make the separator a hyphen too. slug names
# files and never orders packages, so the lost tilde costs nothing there.
slug=$(printf '%s' "${PACKAGE}" | tr '+' '.' | tr -c '[:alnum:]._-' '-')
slug=${slug#-}; slug=${slug%-}
[ -n "${slug}" ] || slug="dev"

# git_tag is the one field carrying text this script did not build, and git refs
# are byte strings: a tag may legally contain '"' (check-ref-format allows it)
# and bytes that are not valid UTF-8. Both broke the JSON -- the quote
# syntactically, the stray byte at the decoder -- and every consumer parses this
# with python's json.load, so a *legal* local tag stopped the packaging of an
# artefact whose name it does not even influence. The field is informational, so
# it is cut down to printable ASCII first and escaped after. Every other field
# is built from digits this script validated or from an already sanitised value.
TAG_JSON=$(printf '%s' "${TAG}" | LC_ALL=C tr -cd '[:print:]' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

cat <<JSON
{
  "major": "${MAJOR}",
  "minor": "${MINOR}",
  "micro": "${MICRO}",
  "base": "${VERSION}",
  "package": "${PACKAGE}",
  "git_tag": "${TAG_JSON}",
  "git_hash": "${HASH}",
  "pretty": "${PACKAGE}",
  "slug": "${slug}"
}
JSON
