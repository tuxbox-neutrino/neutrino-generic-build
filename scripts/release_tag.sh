#!/bin/sh
#
# release_tag.sh - name the tag an archived AppImage release hangs on.
#
# The artefact's own version says nothing about this repository. version_info.sh
# builds it from Neutrino's configure.ac and Neutrino's HEAD, so two builds from
# the same Neutrino commit are named identically even when ffmpeg, libstb-hal or
# the packaging changed in between. A permanent release keyed on that name alone
# would collide, and two different packages would end up under one label.
#
# The tag therefore names every *source* input that can move:
#
#   build/<slug>-<build commit>-hal<libstb-hal>-dvbsi<libdvbsi++>[-dirty]
#
#   slug   which Neutrino is inside (version_info.sh)
#   build  what built it -- packaging, recipes, patches
#   hal    libstb-hal: make/neutrino.mk clones LIBSTB_HAL_GIT_REF (`mpx`) at
#          its tip
#   dvbsi  libdvbsi++: make/deps.mk clones DVBSI_GIT_REF (`master`) at its tip
#
# The last two are the dependencies that are *not* pinned, so their content
# moves without any of the other parts moving. Either reads `sys` where there is
# no checkout at all: both builds are skipped when the host already provides a
# matching library, and a system library cannot be named by a commit. CI always
# has a checkout of both.
#
# ffmpeg needs no part of its own: make/third_party/ffmpeg.mk pins a version.
#
# What the tag deliberately does not name is the machine. CI builds on
# ubuntu-latest and installs host packages unpinned, and GitHub rebuilds that
# image weekly -- docs/PACKAGING says as much about the glibc floor. The build is
# not byte-reproducible either way: measured 2026-08-20, two dispatches of the
# very same commit, minutes apart on the same runner image, produced AppImages
# with different checksums. So a rebuild always differs, not merely eventually.
# And every commit here is abbreviated to seven characters, which is short
# enough to collide in principle -- for the build commit and for either dependency, and the more so
# because CI clones shallowly, so git abbreviates against very few objects.
# Neither is fixed here: a tag long enough to name a runner image is a tag
# nobody reads.
# The workflow closes the hole at the other end instead. Its archive step
# compares the SHA256SUMS already published under a tag with the one just built
# and fails on a mismatch, so drift or a collision that produced a *different*
# package surfaces as an error rather than silently keeping whichever build
# arrived first. A collision between two dependency commits lands in the same
# place: the second archive is refused rather than published over the first.
# Two things it cannot surface, both harmless by construction:
# where the bytes are identical there is nothing to tell apart -- the archive
# holds the package it claims to, and only the release's target still names the
# commit that got there first. And an archive that never got as far as a
# checksum has nothing to compare against, so a repair run fills it with the
# build it has.
#
# The rolling `latest` release needs none of this -- it is overwritten on every
# run; only the archive has to stay distinguishable.
#
# None of this reaches the release page as a heading. What makes a good key
# makes a poor label, so publish_release.sh's archive_title reduces the name
# back to what a person asked in the first place -- which Neutrino, from when --
# and leaves the key in the URL.
#
# Usage: release_tag.sh [<build-commit>]
#   <build-commit>  the build system's commit. CI passes github.sha; when it is
#                   omitted the value comes from HEAD, and a modified worktree
#                   adds -dirty, because the bare commit would name a state that
#                   is not the one being packaged.
#
# LIBSTB_HAL_DIR and DVBSI_SRC_DIR override where those two are looked for,
# named after the make variables that place them (make/env.mk, make/deps.mk).
#
# Exits non-zero and says why rather than printing a name it cannot stand behind.

set -eu

# An inherited git environment would silently point every command below at
# another repository -- under `git rebase --exec`, inside a hook, under `git
# bisect run`. `git -C <dir>` does not save us: GIT_DIR outranks it, so the two
# dependency commits in the tag could come from the caller's repository instead.
# version_info.sh unsets the same set for the same reason.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

# git can be told to stop looking at a file, and `git diff` then calls a patched
# tree clean -- the tag would name a commit that is not what got packaged.
# scripts/version_info.sh documents all three ways at length, having been caught
# by each; the two below are the ones an environment can close.
#
# GIT_CONFIG_PARAMETERS is exported by git into every child of a `git -c ...`
# invocation -- a hook, `rebase --exec`, `bisect run` -- and outranks the
# injection that follows, so it is dropped rather than argued with.
unset GIT_CONFIG_PARAMETERS

# core.fsmonitor is the way `git ls-files -v` cannot see: it flags nothing, and
# the diff simply takes the monitor's word for it. Injected through the
# environment because that outranks both the repository's configuration and the
# user's.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=core.fsmonitor
export GIT_CONFIG_VALUE_0=false

# A replacement object changes what git reports for a commit without changing
# its id. With refs/replace/<HEAD> pointing at a commit whose tree matches the
# locally changed files, rev-parse still hands back the original id while diff
# honours the replacement and calls the tree clean -- a patched build under a
# clean name. version_info.sh exports this for the same reason.
export GIT_NO_REPLACE_OBJECTS=1

# CDPATH makes `cd` write the directory it resolved to, on *stdout*. ROOT_DIR
# would then hold two newline-separated paths and every path derived from it
# would be wrong -- the script reports a version_info.sh that is plainly there.
# scripts/version_info.sh unsets CDPATH at its own head for exactly this reason,
# and names the builder's profile as the place it comes from. This script calls
# that one, so the two have to agree.
unset CDPATH

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_INFO="$ROOT_DIR/scripts/version_info.sh"

if [ ! -x "$VERSION_INFO" ]; then
	echo "release_tag: missing or not executable: $VERSION_INFO" >&2
	exit 1
fi

# Same field and same fallback chain as gen_appimage.sh: slug, not package. The
# package version carries a '+' for dpkg's sake, and a '+' in a release asset
# name is read as a space by uploaders that do not encode it.
# SRC_DIR anchored to this repository. version_info.sh defaults it to a
# *caller-relative* `sources/neutrino` (its line 68), so running this script by
# absolute path while standing in another build checkout would take the slug
# from that checkout and the commits from this one -- a tag that looks valid and
# describes a build that never existed. An SRC_DIR set on purpose still wins.
slug=$(SRC_DIR="${SRC_DIR:-$ROOT_DIR/sources/neutrino}" "$VERSION_INFO" \
	| python3 -c 'import sys,json;data=json.load(sys.stdin);print(data.get("slug") or data.get("base") or "dev")')
if [ -z "$slug" ]; then
	echo "release_tag: version_info.sh reported no version" >&2
	exit 1
fi

dirty=""

# mark_if_dirty <dir> -- tracked modifications only. `git status --porcelain`
# would count untracked files too, and an untracked directory next to the
# sources -- a developer's own plugin checkout, say -- changes nothing about
# what gets built. The one untracked exception that does is handled by
# mark_if_overridden below. Prints nothing; sets dirty. Refuses on any status
# other than 0 or 1, for the same reason version_info.sh does: an answer nobody
# can interpret must not be turned into "clean".
#
# What it cannot see is a tracked file hidden behind `git update-index
# --assume-unchanged` or --skip-worktree, because git then reports the file as
# unchanged on purpose. There is no cheap defence, and it takes a deliberate act
# to arrange: where git has been told to lie, the tag believes git.
mark_if_dirty() {
	# assume-unchanged and skip-worktree are the two ways the index does show:
	# a lowercase tag means assume-unchanged, `S` means skip-worktree. Where any
	# are set, this refuses to claim clean and says -dirty instead.
	# version_info.sh goes further -- it copies the index, clears the bits and
	# diffs against that -- because it needs the true state for a version string
	# that has to sort correctly against other versions. A name only has to stop
	# lying, and duplicating fifty lines of that in POSIX sh would be the more
	# expensive mistake. The price is a sparse checkout, which carries the bit
	# on every excluded path and is therefore always called dirty here.
	if ! scan=$(git -C "$1" ls-files -v 2>/dev/null); then
		echo "release_tag: cannot tell whether $1 is modified" >&2
		echo "release_tag: (its index could not be read); refusing to guess." >&2
		exit 1
	fi
	if printf '%s\n' "$scan" | cut -c1 | grep -q '[a-zS]'; then
		dirty="-dirty"
		return 0
	fi

	diff_rc=0
	git -C "$1" diff --quiet HEAD -- || diff_rc=$?
	case "$diff_rc" in
		0) ;;
		1) dirty="-dirty" ;;
		*)
			echo "release_tag: cannot tell whether $1 is modified" >&2
			echo "release_tag: (git diff exited ${diff_rc}); refusing to guess." >&2
			exit 1
			;;
	esac
}

# mark_if_overridden -- the untracked files that do change the build.
# make/main.mk includes Makefile.local and Makefile.local.post into every build,
# and CLAUDE.md recommends the first for TOOLCHAIN_GCC_VERSION. Both are
# git-ignored, so mark_if_dirty cannot see them, yet a different compiler or a
# different FFmpeg produces a different package. Their presence alone is enough:
# the file is read, so the result is no longer reproducible from the commits the
# tag names. Checked whichever way the commit arrived -- a caller-supplied
# commit vouches for a commit, and nobody vouches for a file that is in none.
mark_if_overridden() {
	for override in "$ROOT_DIR/Makefile.local" "$ROOT_DIR/Makefile.local.post"; do
		if [ -e "$override" ]; then
			dirty="-dirty"
		fi
	done
}

build_commit="${1:-}"
if [ -n "$build_commit" ]; then
	# A caller-supplied commit is taken at its word except for its length:
	# github.sha is 40 characters, and a tag carrying both it and the slug gets
	# unreadable.
	#
	# The caller vouches for *which* commit was built, not for the tree still
	# matching it. CI passes github.sha and then runs a bootstrap that could
	# patch tracked packaging code, and the archive would carry a clean name
	# for a build that is not that commit. So the tree is checked here too,
	# wherever there is one to check: with no repository at all there is
	# nothing to compare against and the caller's word is all there is.
	short_commit=$(printf '%.7s' "$build_commit")
	if git -C "$ROOT_DIR" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
		mark_if_dirty "$ROOT_DIR"
	fi
else
	if ! short_commit=$(git -C "$ROOT_DIR" rev-parse --short=7 HEAD 2>/dev/null); then
		echo "release_tag: no build commit given and $ROOT_DIR has no usable HEAD" >&2
		exit 1
	fi
	mark_if_dirty "$ROOT_DIR"
fi

mark_if_overridden

# The two dependencies nobody passes in. Both are cloned at a branch tip, so
# both are exactly the inputs that can move silently, and both are skipped when
# the host already provides a matching library -- make/neutrino.mk:28-32 for
# libstb-hal, make/deps.mk:14-18 for libdvbsi++. A build that used the host's
# copy is perfectly valid; it just cannot be described by a commit, and refusing
# would reject it.
#
# What `sys` states precisely is that there is no checkout here to name -- which
# is what make leaves behind when it skipped the build. It is not a measurement
# of which library the linker took: a checkout left lying around from an earlier
# build is still named, even if this build used the host's copy. `make distclean`
# is the cure for that, and CI, which starts from nothing, never has it.
#
# Sets dep_commit rather than printing it: mark_if_dirty writes a variable, and
# a command substitution would run it in a subshell where that is lost.
dep_part() {
	dep_commit="sys"
	[ -d "$1" ] || return 0

	# `git -C <dir>` walks *upward*. With sources/libdvbsi++ present as an
	# ordinary directory -- an emptied checkout, a stray mkdir -- git answers
	# about the build repository enclosing it, and the tag would carry the
	# build commit as the dependency's provenance. Measured here: `git -C
	# sources/probe-plain rev-parse HEAD` returned this repository's HEAD. So
	# the directory has to be the top of its own worktree, not merely inside
	# one.
	top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 0
	here=$(cd "$1" && pwd -P) || return 0
	[ "$top" = "$here" ] || return 0

	# Past that point it *is* a checkout, so an unreadable HEAD is a broken one,
	# not an absent one. Calling that `sys` would report a host library where
	# there is a half-finished clone.
	if ! dep_commit=$(git -C "$1" rev-parse --short=7 HEAD 2>/dev/null); then
		echo "release_tag: $1 is a checkout whose HEAD cannot be read" >&2
		echo "release_tag: refusing to call that a host library." >&2
		exit 1
	fi
	mark_if_dirty "$1"
}

HAL_DIR="${LIBSTB_HAL_DIR:-$ROOT_DIR/sources/libstb-hal}"
dep_part "$HAL_DIR"
hal_commit="$dep_commit"

DVBSI_DIR="${DVBSI_SRC_DIR:-$ROOT_DIR/sources/libdvbsi++}"
dep_part "$DVBSI_DIR"
dvbsi_commit="$dep_commit"

tag="build/${slug}-${short_commit}-hal${hal_commit}-dvbsi${dvbsi_commit}${dirty}"

# The slug is sanitised upstream and the commit is hexadecimal, so this should
# never fire. It is here so that a later change to either sanitiser fails at the
# build that introduces it, rather than at `git tag` inside a release job.
if ! git check-ref-format "refs/tags/${tag}" 2>/dev/null; then
	echo "release_tag: refusing to emit an invalid tag name: ${tag}" >&2
	exit 1
fi

printf '%s\n' "$tag"
