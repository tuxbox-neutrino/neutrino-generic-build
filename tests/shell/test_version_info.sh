#!/bin/sh
#
# Unit test for scripts/version_info.sh.
#
# The version this script reports names every artefact the build produces. It
# used to report two different schemes and pick between them silently: with tags
# in the clone `git describe` decided, without them it fell back to configure.ac.
# `git clone --depth 1` produces a tagless clone, so CI and a developer machine
# named the same commit differently and nothing anywhere noticed.
#
# So the assertions below are mostly about *sameness*: the same commit, fetched
# in different ways, examined under different environments, must produce one
# answer. The rest guard the failure modes, because the old script had none --
# a missing configure.ac died with a localised grep message, an empty version
# define produced "2026.8." and travelled on.
#
# POSIX sh. Exits 0 on success, 1 on any failure.

set -u

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/version_info.sh"
WORK="$(mktemp -d)"
trap 'chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

pass=0
fail=0
ok() { printf 'ok   %s\n' "$1"; pass=$((pass + 1)); }
ko() { printf 'FAIL %s\n' "$1"; printf '     %s\n' "$2"; fail=$((fail + 1)); }

if [ ! -f "$SCRIPT" ]; then
	printf 'FAIL scripts/version_info.sh not found\n'
	exit 1
fi

BASH_BIN="$(command -v bash 2>/dev/null || true)"
if [ -z "$BASH_BIN" ]; then
	ko "bash is available to run version_info.sh" \
		"version_info.sh needs bash; without it nothing here is exercised"
	printf -- '----\n[test-version-info] pass=%d fail=%d\n' "$pass" "$fail"
	exit 1
fi

# $1 = key, $2.. = command producing JSON on stdout
jget() {
	key="$1"
	sed -n "s/.*\"${key}\": \"\([^\"]*\)\".*/\1/p"
}

# Runs version_info.sh with SRC_DIR set. Extra environment goes in front.
run_vi() { # $1 = src dir; prints JSON, returns exit status
	SRC_DIR="$1" "$BASH_BIN" "$SCRIPT" 2>"$WORK/stderr.last"
}

git_q() { git -c user.email=t@example.invalid -c user.name=Test -c init.defaultBranch=main "$@"; }

write_configure() { # $1 = dir, $2 = micro (default 27)
	cat > "$1/configure.ac" <<ACSRC
define(ver_major, 2026)
define(ver_minor, 8)
define(ver_micro, ${2:-27})
ACSRC
}

# A repository with two commits and the tag on the OLDER one. That detail is the
# whole point of the shallow-clone case below: a tag pointing at HEAD is fetched
# even by a depth-1 clone, and then the shallow and full shapes are
# indistinguishable and the assertion proves nothing.
make_repo() { # $1 = dir
	rm -rf "$1"; mkdir -p "$1"
	write_configure "$1"
	( cd "$1" && git_q init -q . >/dev/null 2>&1 &&
	  echo first > file.txt && git_q add -A &&
	  GIT_AUTHOR_DATE="2026-08-01T10:00:00+0000" GIT_COMMITTER_DATE="2026-08-01T10:00:00+0000" \
	    git_q commit -q -m first &&
	  git_q tag v2026.8 &&
	  echo second > file.txt && git_q add -A &&
	  GIT_AUTHOR_DATE="2026-08-02T11:22:33+0000" GIT_COMMITTER_DATE="2026-08-02T11:22:33+0000" \
	    git_q commit -q -m second ) >/dev/null 2>&1
}

# ---------------------------------------------------------- reproducibility
make_repo "$WORK/repo"

# The production scenario. file:// is mandatory: with a plain local path git
# ignores --depth with nothing but a warning and hands back a full clone, so the
# assertion would compare a full clone against a full clone.
git clone --quiet --depth 1 "file://$WORK/repo" "$WORK/shallow" >/dev/null 2>&1
if [ -f "$WORK/shallow/.git/shallow" ] && [ "$(git -C "$WORK/shallow" tag | wc -l)" -eq 0 ]; then
	pkg_shallow="$(run_vi "$WORK/shallow" | jget package)"
	pkg_full="$(run_vi "$WORK/repo" | jget package)"
	if [ -n "$pkg_full" ] && [ "$pkg_shallow" = "$pkg_full" ]; then
		ok "a shallow clone and a full clone report the same version"
	else
		ko "a shallow clone and a full clone report the same version" \
			"shallow='$pkg_shallow' full='$pkg_full'"
	fi
else
	ko "the shallow fixture is actually shallow and tagless" \
		"clone was not shallow or carried tags; the comparison would prove nothing"
fi

# The length guarantee lives here, not above: git derives the automatic
# abbreviation from the object count, which only diverges around 370k objects --
# far beyond any fixture. core.abbrev reaches it at any size.
( cd "$WORK/repo" && git config core.abbrev 4 )
hash_abbrev4="$(run_vi "$WORK/repo" | jget git_hash)"
( cd "$WORK/repo" && git config --unset core.abbrev )
if [ "${#hash_abbrev4}" -eq 10 ]; then
	ok "the commit hash is 10 characters even with core.abbrev=4"
else
	ko "the commit hash is 10 characters even with core.abbrev=4" \
		"got '${hash_abbrev4}' (${#hash_abbrev4} characters)"
fi

# Same commit, one fixture with the tag, one without.
cp -a "$WORK/repo" "$WORK/repo-untagged"
( cd "$WORK/repo-untagged" && git tag -d v2026.8 ) >/dev/null 2>&1
pkg_tagged="$(run_vi "$WORK/repo" | jget package)"
pkg_untagged="$(run_vi "$WORK/repo-untagged" | jget package)"
if [ -n "$pkg_tagged" ] && [ "$pkg_tagged" = "$pkg_untagged" ]; then
	ok "the presence of a tag does not change the version"
else
	ko "the presence of a tag does not change the version" \
		"tagged='$pkg_tagged' untagged='$pkg_untagged'"
fi

pkg_utc="$(TZ=UTC run_vi "$WORK/repo" | jget package)"
pkg_kiritimati="$(TZ=Pacific/Kiritimati run_vi "$WORK/repo" | jget package)"
if [ "$pkg_utc" = "$pkg_kiritimati" ]; then
	ok "the builder's time zone does not change the version"
else
	ko "the builder's time zone does not change the version" \
		"UTC='$pkg_utc' Kiritimati='$pkg_kiritimati'"
fi

# ------------------------------------------------------------------- guards
# The production layout: sources/neutrino is a symlink to the repository root.
ln -sfn "$WORK/repo" "$WORK/repo-link"
pkg_link="$(run_vi "$WORK/repo-link" | jget package)"
if [ "$pkg_link" = "$pkg_full" ]; then
	ok "a symlink to the repository root is recognised as git"
else
	ko "a symlink to the repository root is recognised as git" \
		"via symlink='$pkg_link' direct='$pkg_full'"
fi

# .git as a file rather than a directory (linked worktree, --separate-git-dir).
rm -rf "$WORK/sep" "$WORK/sepgit"
mkdir -p "$WORK/sep"
write_configure "$WORK/sep"
( cd "$WORK/sep" && git_q init -q --separate-git-dir="$WORK/sepgit" . &&
  echo x > f && git_q add -A &&
  GIT_AUTHOR_DATE="2026-08-03T00:00:00+0000" GIT_COMMITTER_DATE="2026-08-03T00:00:00+0000" \
    git_q commit -q -m sep ) >/dev/null 2>&1
pkg_sep="$(run_vi "$WORK/sep" | jget package)"
case "$pkg_sep" in
	*+git*.g*) ok "a .git file instead of a directory is recognised as git" ;;
	*) ko "a .git file instead of a directory is recognised as git" "got '$pkg_sep'" ;;
esac

# A plain directory inside somebody else's worktree must not inherit their
# commit. sources/ lives inside this build repository, so this is the real
# layout, not a contrived one.
mkdir -p "$WORK/repo/nested"
write_configure "$WORK/repo/nested"
pkg_nested="$(run_vi "$WORK/repo/nested" | jget package)"
base_nested="$(run_vi "$WORK/repo/nested" | jget base)"
if [ "$pkg_nested" = "$base_nested" ]; then
	ok "a plain directory inside a foreign repository yields the bare version"
else
	ko "a plain directory inside a foreign repository yields the bare version" \
		"got '$pkg_nested', which carries a commit that is not its own"
fi

# The same theft through the environment instead of the directory tree. Reached
# by anything run from `git rebase --exec`, a hook, or `git bisect run`.
make_repo "$WORK/other"
# A distinct commit, or the two fixtures share a hash -- same content, same
# pinned dates, same tree -- and the assertion below could not tell a leak from
# a clean run.
( cd "$WORK/other" && echo foreign > marker.txt && git_q add -A &&
  GIT_AUTHOR_DATE="2026-08-04T09:09:09+0000" GIT_COMMITTER_DATE="2026-08-04T09:09:09+0000" \
    git_q commit -q -m foreign ) >/dev/null 2>&1
other_hash="$(run_vi "$WORK/other" | jget git_hash)"
own_hash="$(run_vi "$WORK/repo" | jget git_hash)"
leaked_hash="$(GIT_DIR="$WORK/other/.git" run_vi "$WORK/repo" | jget git_hash)"
if [ "$leaked_hash" = "$own_hash" ] && [ "$own_hash" != "$other_hash" ]; then
	ok "an inherited GIT_DIR does not stamp a foreign commit on the version"
else
	ko "an inherited GIT_DIR does not stamp a foreign commit on the version" \
		"own='$own_hash' foreign='$other_hash' with GIT_DIR set='$leaked_hash'"
fi

# ------------------------------------------------------------- failure modes
rm -rf "$WORK/tarball"; mkdir -p "$WORK/tarball"
write_configure "$WORK/tarball"
out_tar="$(run_vi "$WORK/tarball")"; rc_tar=$?
pkg_tar="$(printf '%s' "$out_tar" | jget package)"
base_tar="$(printf '%s' "$out_tar" | jget base)"
slug_tar="$(printf '%s' "$out_tar" | jget slug)"
if [ "$rc_tar" -eq 0 ] && [ "$pkg_tar" = "$base_tar" ] && [ "$slug_tar" = "$base_tar" ]; then
	ok "an export without .git reports the bare version and succeeds"
else
	ko "an export without .git reports the bare version and succeeds" \
		"rc=$rc_tar package='$pkg_tar' base='$base_tar' slug='$slug_tar'"
fi

# .git present but unusable is NOT the same thing, and used to be indistinguish-
# able from it. The bare version sorts below every real artefact, so a silent
# fallback here produces a package that can never be an upgrade.
rm -rf "$WORK/brokengit"; mkdir -p "$WORK/brokengit"
write_configure "$WORK/brokengit"
echo "this is not a gitdir" > "$WORK/brokengit/.git"
if run_vi "$WORK/brokengit" >/dev/null 2>&1; then
	ko "an unusable .git aborts instead of quietly reporting the bare version" \
		"the script succeeded and reported a version anyway"
else
	if grep -q 'cannot use it' "$WORK/stderr.last"; then
		ok "an unusable .git aborts instead of quietly reporting the bare version"
	else
		ko "an unusable .git aborts instead of quietly reporting the bare version" \
			"aborted, but without saying why: $(head -1 "$WORK/stderr.last")"
	fi
fi

rm -rf "$WORK/noconf"; mkdir -p "$WORK/noconf"
if run_vi "$WORK/noconf" >/dev/null 2>&1; then
	ko "a missing configure.ac is reported by name" "the script succeeded"
elif grep -q 'configure.ac' "$WORK/stderr.last"; then
	ok "a missing configure.ac is reported by name"
else
	ko "a missing configure.ac is reported by name" \
		"got: $(head -1 "$WORK/stderr.last")"
fi

# Missing and empty are two different failures in the old script -- exit 1 with
# no output, and exit 0 with "2026.8." -- so they get one assertion each.
rm -rf "$WORK/nomicro"; mkdir -p "$WORK/nomicro"
printf 'define(ver_major, 2026)\ndefine(ver_minor, 8)\n' > "$WORK/nomicro/configure.ac"
if run_vi "$WORK/nomicro" >/dev/null 2>&1; then
	ko "a missing ver_micro is reported by name" "the script succeeded"
elif grep -q 'ver_micro' "$WORK/stderr.last"; then
	ok "a missing ver_micro is reported by name"
else
	ko "a missing ver_micro is reported by name" "got: $(head -1 "$WORK/stderr.last")"
fi

rm -rf "$WORK/emptymicro"; mkdir -p "$WORK/emptymicro"
printf 'define(ver_major, 2026)\ndefine(ver_minor, 8)\ndefine(ver_micro, )\n' > "$WORK/emptymicro/configure.ac"
if run_vi "$WORK/emptymicro" >/dev/null 2>&1; then
	ko "an empty ver_micro is reported by name" "the script produced a version anyway"
elif grep -q 'ver_micro' "$WORK/stderr.last"; then
	ok "an empty ver_micro is reported by name"
else
	ko "an empty ver_micro is reported by name" "got: $(head -1 "$WORK/stderr.last")"
fi

# ------------------------------------------------------------ format promises
# The property that matters for dpkg: no hyphen, therefore no Debian revision.
# `dpkg --validate-version` cannot express this -- it accepts the old broken
# value too, because a version *with* a revision is still a valid version.
case "$pkg_full" in
	*-*) ko "the version carries no Debian revision" \
		"'$pkg_full' contains a hyphen; dpkg would split it at the last one" ;;
	*) ok "the version carries no Debian revision" ;;
esac
if command -v dpkg >/dev/null 2>&1; then
	if dpkg --validate-version "$pkg_full" >/dev/null 2>&1; then
		ok "dpkg accepts the version"
	else
		ko "dpkg accepts the version" "dpkg --validate-version rejected '$pkg_full'"
	fi
fi

# Ordering. The committer dates are pinned in the fixture: two commits made
# back to back land in the same second, and the comparison would silently fall
# through to the hash, which orders arbitrarily.
rm -rf "$WORK/older"; cp -a "$WORK/repo" "$WORK/older"
( cd "$WORK/older" && git_q reset -q --hard HEAD~1 ) >/dev/null 2>&1
pkg_older="$(run_vi "$WORK/older" | jget package)"
if command -v dpkg >/dev/null 2>&1; then
	if dpkg --compare-versions "$pkg_full" gt "$pkg_older"; then
		ok "a later commit sorts above an earlier one"
	else
		ko "a later commit sorts above an earlier one" "'$pkg_full' !> '$pkg_older'"
	fi
else
	# Without dpkg the timestamp is still comparable: lexicographic order on
	# YYYYMMDDHHMMSS is chronological order.
	if [ "$pkg_full" \> "$pkg_older" ]; then
		ok "a later commit sorts above an earlier one"
	else
		ko "a later commit sorts above an earlier one" "'$pkg_full' !> '$pkg_older'"
	fi
fi

# A modified tree is marked, and the mark sorts BELOW the clean build -- with
# "+dirty" it would sort above, and a patched CI build would outrank the release
# it was built from.
rm -rf "$WORK/dirty"; cp -a "$WORK/repo" "$WORK/dirty"
echo changed > "$WORK/dirty/file.txt"
pkg_dirty="$(run_vi "$WORK/dirty" | jget package)"
case "$pkg_dirty" in
	*~dirty)
		if command -v dpkg >/dev/null 2>&1; then
			if dpkg --compare-versions "$pkg_dirty" lt "$pkg_full"; then
				ok "a modified tree is marked and sorts below the clean build"
			else
				ko "a modified tree is marked and sorts below the clean build" \
					"'$pkg_dirty' !< '$pkg_full'"
			fi
		else
			ok "a modified tree is marked and sorts below the clean build"
		fi
		;;
	*) ko "a modified tree is marked and sorts below the clean build" "got '$pkg_dirty'" ;;
esac

# Untracked leftovers are not a source change: autogen produces them on every
# build, and marking those would make every artefact dirty.
rm -rf "$WORK/untracked"; cp -a "$WORK/repo" "$WORK/untracked"
echo leftover > "$WORK/untracked/Makefile.in"
pkg_untracked="$(run_vi "$WORK/untracked" | jget package)"
case "$pkg_untracked" in
	*dirty*) ko "an untracked leftover does not count as a modification" \
		"got '$pkg_untracked'" ;;
	*) ok "an untracked leftover does not count as a modification" ;;
esac

slug_full="$(run_vi "$WORK/repo" | jget slug)"
case "$slug_full" in
	*+*) ko "the filename form carries no plus sign" "got '$slug_full'" ;;
	*) ok "the filename form carries no plus sign" ;;
esac
if printf '%s' "$slug_full" | LC_ALL=C grep -q '^[A-Za-z0-9._-]\{1,\}$'; then
	ok "the filename form uses only characters safe in a file name"
else
	ko "the filename form uses only characters safe in a file name" "got '$slug_full'"
fi

# make_deb.sh must hand dpkg exactly what version_info.sh reports. Testing the
# expression itself rather than grepping for the absence of the old one: the
# question is what the value IS, not what the source text is not.
deb_expr="$(grep -m1 '^DEFAULT_VERSION=' "$ROOT_DIR/scripts/make_deb.sh" || true)"
if [ -z "$deb_expr" ]; then
	ko "make_deb.sh uses the reported version verbatim" \
		"no DEFAULT_VERSION assignment found in scripts/make_deb.sh"
else
	VERSION_JSON="$(run_vi "$WORK/repo")"
	export VERSION_JSON
	deb_version="$("$BASH_BIN" -c "set -euo pipefail; VERSION_JSON=\"\$VERSION_JSON\"; ${deb_expr}; printf '%s' \"\$DEFAULT_VERSION\"" 2>/dev/null || true)"
	if [ "$deb_version" = "$pkg_full" ]; then
		ok "make_deb.sh uses the reported version verbatim"
	else
		ko "make_deb.sh uses the reported version verbatim" \
			"make_deb='$deb_version' version_info='$pkg_full'"
	fi
fi

printf -- '----\n'
printf '[test-version-info] pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
