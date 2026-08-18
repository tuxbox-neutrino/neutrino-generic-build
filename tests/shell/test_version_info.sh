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
# Read `vi_field` before adding an assertion. Seven of the assertions here once
# compared two empty strings and passed while version_info.sh was exiting 1.
#
# POSIX sh. Exits 0 on success, 1 on any failure.

set -u

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/version_info.sh"
WORK="$(mktemp -d)"
trap 'chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

pass=0
fail=0
skip=0
ok() { printf 'ok   %s\n' "$1"; pass=$((pass + 1)); }
ko() { printf 'FAIL %s\n' "$1"; printf '     %s\n' "$2"; fail=$((fail + 1)); }
# An assertion that could not run has to say so. Gating a block on `command -v`
# with no else made the suite report `pass=40 fail=0` on a host without dpkg --
# green, exit 0, and quietly three assertions short, among them the only two
# that catch make_deb.sh reading the right version and then ignoring it.
sk() { printf 'skip %s\n' "$1"; printf '     %s\n' "$2"; skip=$((skip + 1)); }

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

# Two assertions below parse the JSON the way the consumers do. Stated as its
# own assertion so a host without python3 produces one message that names the
# cause instead of two that look like escaping bugs -- and make_deb.sh cannot
# build a package without it either, so this is not an incidental dependency.
if command -v python3 >/dev/null 2>&1; then
	ok "python3 is available to parse the reported JSON"
else
	ko "python3 is available to parse the reported JSON" \
		"make_deb.sh and gen_appimage.sh read this JSON with python3"
fi

# $1 = key. Reads JSON on stdin.
jget() {
	key="$1"
	sed -n "s/.*\"${key}\": \"\([^\"]*\)\".*/\1/p"
}

# Runs version_info.sh with SRC_DIR set. Extra environment goes in front.
run_vi() { # $1 = src dir; prints JSON, returns exit status
	SRC_DIR="$1" "$BASH_BIN" "$SCRIPT" 2>"$WORK/stderr.last"
}

# Reads one field out of a run. A failed run and a missing key both yield a
# sentinel rather than the empty string, because two empty strings compare equal
# and match every glob below -- which is how seven assertions here kept printing
# `ok` against a version_info.sh replaced by `exit 1`. Pair every use with
# `have`, which refuses to let a sentinel reach a comparison.
NOVALUE='<none>'
vi_field() { # $1 = src dir, $2 = key
	if ! vi_out="$(run_vi "$1")"; then printf '%s' "$NOVALUE"; return 0; fi
	vi_val="$(printf '%s\n' "$vi_out" | jget "$2")"
	if [ -z "$vi_val" ]; then printf '%s' "$NOVALUE"; else printf '%s' "$vi_val"; fi
}

have() { # $1.. = values; false as soon as one is missing
	for v in "$@"; do
		case "$v" in
			'' | *"$NOVALUE"*) return 1 ;;
		esac
	done
	return 0
}

# The fixtures must not inherit the developer's git config. A global
# `commit.gpgsign = true`, or the commit-msg hook a `core.hooksPath` installs,
# makes every fixture commit fail -- and the suite then reports the script under
# test as broken (pass=12 fail=35) for a reason that has nothing to do with it.
git_q() {
	GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
		git -c user.email=t@example.invalid -c user.name=Test \
		    -c init.defaultBranch=main -c commit.gpgsign=false \
		    -c core.hooksPath=/dev/null "$@"
}

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
pkg_full="$(vi_field "$WORK/repo" package)"

# The production scenario. file:// is mandatory: with a plain local path git
# ignores --depth with nothing but a warning and hands back a full clone, so the
# assertion would compare a full clone against a full clone.
git_q clone --quiet --depth 1 "file://$WORK/repo" "$WORK/shallow" >/dev/null 2>&1
if [ -f "$WORK/shallow/.git/shallow" ] && [ "$(git_q -C "$WORK/shallow" tag | wc -l)" -eq 0 ]; then
	pkg_shallow="$(vi_field "$WORK/shallow" package)"
	if have "$pkg_shallow" "$pkg_full" && [ "$pkg_shallow" = "$pkg_full" ]; then
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
( cd "$WORK/repo" && git_q config core.abbrev 4 )
hash_abbrev4="$(vi_field "$WORK/repo" git_hash)"
( cd "$WORK/repo" && git_q config --unset core.abbrev )
if have "$hash_abbrev4" && [ "${#hash_abbrev4}" -eq 10 ]; then
	ok "the commit hash is 10 characters even with core.abbrev=4"
else
	ko "the commit hash is 10 characters even with core.abbrev=4" \
		"got '${hash_abbrev4}' (${#hash_abbrev4} characters)"
fi

# `--short=N` is a *minimum*, not a width: git widens it as soon as N characters
# are ambiguous. This pins the property that makes that impossible -- the hash is
# a slice of the full object id, so it is a prefix of it and exactly ten
# characters long. The ambiguity itself is forced further down.
full_head="$(git_q -C "$WORK/repo" rev-parse HEAD 2>/dev/null || true)"
hash_full="$(vi_field "$WORK/repo" git_hash)"
if have "$hash_full" && [ -n "$full_head" ] &&
	[ "${#hash_full}" -eq 10 ] &&
	[ "$hash_full" = "$(printf '%s' "$full_head" | cut -c1-10)" ]; then
	ok "the hash is the first 10 characters of the full object id"
else
	ko "the hash is the first 10 characters of the full object id" \
		"reported='$hash_full' HEAD='$full_head'"
fi

# And the ambiguity for real, because the assertion above still passes if the
# slice is replaced by `git rev-parse --short=10 HEAD`. Two commit objects
# sharing a ten-hex prefix are a birthday search over ~2^20 candidates -- about
# a second in python -- and both are written straight into the object store, so
# git genuinely cannot abbreviate to ten characters here.
rm -rf "$WORK/collide"; mkdir -p "$WORK/collide"
write_configure "$WORK/collide"
( cd "$WORK/collide" && git_q init -q . >/dev/null 2>&1 && git_q add -A &&
  GIT_AUTHOR_DATE="2026-08-06T00:00:00+0000" GIT_COMMITTER_DATE="2026-08-06T00:00:00+0000" \
    git_q commit -q -m seed ) >/dev/null 2>&1
collide_ids="$(python3 - "$WORK/collide" <<'PY' 2>/dev/null || true
import hashlib, os, subprocess, sys
repo = sys.argv[1]
env = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null")
def git(*a, stdin=None):
    return subprocess.run(["git", "-C", repo, *a], input=stdin, env=env,
                          capture_output=True).stdout.decode().strip()
# Whatever the host's git uses. Hard-coding sha1 made this skip on a host with
# GIT_DEFAULT_HASH=sha256 -- and a skip here is a hole, because this is the only
# assertion that catches the abbreviation widening again.
digest = {"sha1": hashlib.sha1, "sha256": hashlib.sha256}.get(
    git("rev-parse", "--show-object-format"))
if digest is None:
    sys.exit(1)
head = ("tree %s\nparent %s\n"
        "author t <t@example.invalid> 1767225845 +0000\n"
        "committer t <t@example.invalid> 1767225845 +0000\n\n"
        % (git("rev-parse", "HEAD^{tree}"), git("rev-parse", "HEAD")))
# Only the loop counter is kept, and the two winning bodies are rebuilt from it.
# Storing the bodies measured 265 MB against 77 MB for the same search, and at
# the median search length that is the difference between fitting on a small CI
# runner and being OOM-killed -- which, with the no-skip rule below, fails the
# whole suite.
def body_of(i):
    return (head + "c%d\n" % i).encode()
seen, pair = {}, None
for i in range(8_000_000):
    body = body_of(i)
    h = digest(b"commit %d\0" % len(body) + body).hexdigest()
    key = int(h[:10], 16)
    if key in seen:
        pair = (seen[key], i)
        break
    seen[key] = i
if pair is None:
    sys.exit(1)
ids = []
for i in pair:
    ids.append(subprocess.run(
        ["git", "-C", repo, "hash-object", "-w", "-t", "commit", "--stdin"],
        input=body_of(i), env=env, capture_output=True).stdout.decode().strip())
print(ids[0], ids[1])
PY
)"
collide_a="${collide_ids%% *}"
collide_b="${collide_ids##* }"
if [ -z "$collide_ids" ] ||
	[ "$(git_q -C "$WORK/collide" cat-file -t "$collide_a" 2>/dev/null)" != commit ] ||
	[ "$(git_q -C "$WORK/collide" cat-file -t "$collide_b" 2>/dev/null)" != commit ]; then
	# Not a skip: this is the only assertion that catches the abbreviation
	# widening, so an unbuildable fixture is a failure of the suite, not a
	# property of the host to be waved through.
	ko "an ambiguous ten-character prefix does not widen the hash" \
		"could not build two colliding commit objects in this repository"
else
	git_q -C "$WORK/collide" update-ref refs/heads/main "$collide_a" >/dev/null 2>&1
	git_q -C "$WORK/collide" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1
	widened="$(git_q -C "$WORK/collide" rev-parse --short=10 HEAD 2>/dev/null || true)"
	hash_collide="$(vi_field "$WORK/collide" git_hash)"
	if [ "${#widened}" -le 10 ]; then
		ko "an ambiguous ten-character prefix does not widen the hash" \
			"the fixture is not ambiguous: git abbreviated to '$widened'"
	elif have "$hash_collide" && [ "${#hash_collide}" -eq 10 ] &&
		[ "$hash_collide" = "$(printf '%s' "$collide_a" | cut -c1-10)" ]; then
		ok "an ambiguous ten-character prefix does not widen the hash"
	else
		ko "an ambiguous ten-character prefix does not widen the hash" \
			"git widened to '$widened', version_info reported '$hash_collide'"
	fi
fi

# Same commit, one fixture with the tag, one without.
cp -a "$WORK/repo" "$WORK/repo-untagged"
( cd "$WORK/repo-untagged" && git_q tag -d v2026.8 ) >/dev/null 2>&1
pkg_tagged="$(vi_field "$WORK/repo" package)"
pkg_untagged="$(vi_field "$WORK/repo-untagged" package)"
if have "$pkg_tagged" "$pkg_untagged" && [ "$pkg_tagged" = "$pkg_untagged" ]; then
	ok "the presence of a tag does not change the version"
else
	ko "the presence of a tag does not change the version" \
		"tagged='$pkg_tagged' untagged='$pkg_untagged'"
fi

pkg_utc="$(TZ=UTC vi_field "$WORK/repo" package)"
pkg_kiritimati="$(TZ=Pacific/Kiritimati vi_field "$WORK/repo" package)"
if have "$pkg_utc" "$pkg_kiritimati" && [ "$pkg_utc" = "$pkg_kiritimati" ]; then
	ok "the builder's time zone does not change the version"
else
	ko "the builder's time zone does not change the version" \
		"UTC='$pkg_utc' Kiritimati='$pkg_kiritimati'"
fi

# The assertion above varies the *builder's* zone. It says nothing about the
# *commit's*, and every fixture so far commits at +0000 -- so dropping the UTC
# normalisation altogether passed the whole file. This commit is at +0200, which
# is 2026-08-04 23:30:00 in UTC and 2026-08-05 in the committer's own zone.
rm -rf "$WORK/offset"; mkdir -p "$WORK/offset"
write_configure "$WORK/offset"
( cd "$WORK/offset" && git_q init -q . >/dev/null 2>&1 &&
  echo x > file.txt && git_q add -A &&
  GIT_AUTHOR_DATE="2026-08-05T01:30:00+0200" GIT_COMMITTER_DATE="2026-08-05T01:30:00+0200" \
    git_q commit -q -m offset ) >/dev/null 2>&1
pkg_offset="$(vi_field "$WORK/offset" package)"
if ! have "$pkg_offset"; then
	ko "the timestamp is the commit date in UTC" "no version reported"
else
	case "$pkg_offset" in
		*+git20260804233000.g*) ok "the timestamp is the commit date in UTC" ;;
		*) ko "the timestamp is the commit date in UTC" \
			"got '$pkg_offset'; the +0200 commit must render as 20260804233000" ;;
	esac
fi

# And the shape itself, or `%s` instead of `%Y%m%d%H%M%S` would pass everything:
# a unix timestamp is monotonic, hyphen-free and comparable by dpkg too.
if have "$pkg_full" &&
	printf '%s' "$pkg_full" | LC_ALL=C grep -qE '^2026\.8\.27\+git[0-9]{14}\.g[0-9a-f]{10}$'; then
	ok "the version has the exact documented shape"
else
	ko "the version has the exact documented shape" \
		"got '$pkg_full', want 2026.8.27+git<14 digits>.g<10 hex>"
fi

# `git replace` rewrites what git reports for a commit while the commit id stays
# put. Left alone, one machine's local replace ref moves the timestamp and the
# same commit gets two versions again -- the original defect through a side door.
rm -rf "$WORK/replaced"; cp -a "$WORK/repo" "$WORK/replaced"
pkg_before_replace="$(vi_field "$WORK/replaced" package)"
rep_head="$(git_q -C "$WORK/replaced" rev-parse HEAD 2>/dev/null || true)"
rep_prev="$(git_q -C "$WORK/replaced" rev-parse HEAD~1 2>/dev/null || true)"
if [ -n "$rep_head" ] && [ -n "$rep_prev" ] &&
	( cd "$WORK/replaced" && git_q replace "$rep_head" "$rep_prev" ) >/dev/null 2>&1; then
	pkg_after_replace="$(vi_field "$WORK/replaced" package)"
	if have "$pkg_before_replace" "$pkg_after_replace" &&
		[ "$pkg_before_replace" = "$pkg_after_replace" ]; then
		ok "a replacement object does not change the version"
	else
		ko "a replacement object does not change the version" \
			"before='$pkg_before_replace' after='$pkg_after_replace'"
	fi
else
	ko "the replacement fixture could be created" \
		"git replace failed; the assertion would prove nothing"
fi

# ------------------------------------------------------------------- guards
# The production layout: sources/neutrino is a symlink to the repository root.
ln -sfn "$WORK/repo" "$WORK/repo-link"
pkg_link="$(vi_field "$WORK/repo-link" package)"
if have "$pkg_link" "$pkg_full" && [ "$pkg_link" = "$pkg_full" ]; then
	ok "a symlink to the repository root is recognised as git"
else
	ko "a symlink to the repository root is recognised as git" \
		"via symlink='$pkg_link' direct='$pkg_full'"
fi

# The guard that decides git-or-export compares the physical path against what
# git reports. It used to get that path from realpath(1) with `|| true`, so on a
# host without realpath it compared against the empty string, never matched, and
# every artefact on that host silently carried the bare version. A shim that
# fails is the regression test for it.
mkdir -p "$WORK/norealpath"
printf '#!/bin/sh\nexit 127\n' > "$WORK/norealpath/realpath"
chmod +x "$WORK/norealpath/realpath"
pkg_norealpath="$(PATH="$WORK/norealpath:$PATH" vi_field "$WORK/repo" package)"
if have "$pkg_norealpath" "$pkg_full" && [ "$pkg_norealpath" = "$pkg_full" ]; then
	ok "a broken realpath does not turn a repository into an export"
else
	ko "a broken realpath does not turn a repository into an export" \
		"without realpath='$pkg_norealpath' with='$pkg_full'"
fi

# `cd` prints the directory it resolved whenever it went through CDPATH, and it
# prints it on *stdout*. With a relative SRC_DIR -- which is the default -- that
# stray line landed in the path comparison, reopening the guard above, and in
# this script's own JSON, which the consumers then failed to parse. Needs a
# relative SRC_DIR: an absolute one never consults CDPATH.
cdpath_out="$( cd "$WORK" && CDPATH=. SRC_DIR=repo "$BASH_BIN" "$SCRIPT" 2>/dev/null )"
pkg_cdpath="$(printf '%s\n' "$cdpath_out" | jget package)"
if printf '%s\n' "$cdpath_out" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1 &&
	have "$pkg_full" && [ "$pkg_cdpath" = "$pkg_full" ]; then
	ok "an exported CDPATH neither degrades the version nor corrupts the JSON"
else
	ko "an exported CDPATH neither degrades the version nor corrupts the JSON" \
		"with CDPATH='$pkg_cdpath' without='$pkg_full'"
fi

# The other way `cd` reads a path as something else: a leading dash is an option
# to it, and a bare `-` means the previous directory. `git -C` takes both in its
# stride, so the guard declared a perfectly good repository broken.
rm -rf "$WORK/dashdir"; mkdir -p "$WORK/dashdir/-L"
cp -a "$WORK/repo/." "$WORK/dashdir/-L/"
pkg_dash="$( cd "$WORK/dashdir" && SRC_DIR=-L "$BASH_BIN" "$SCRIPT" 2>/dev/null | jget package )"
if have "$pkg_full" && [ "$pkg_dash" = "$pkg_full" ]; then
	ok "a source directory whose name starts with a dash still works"
else
	ko "a source directory whose name starts with a dash still works" \
		"SRC_DIR=-L gave '$pkg_dash', the same tree by absolute path gives '$pkg_full'"
fi

# .git as a file rather than a directory (linked worktree, --separate-git-dir).
rm -rf "$WORK/sep" "$WORK/sepgit"
mkdir -p "$WORK/sep"
write_configure "$WORK/sep"
( cd "$WORK/sep" && git_q init -q --separate-git-dir="$WORK/sepgit" . &&
  echo x > f && git_q add -A &&
  GIT_AUTHOR_DATE="2026-08-03T00:00:00+0000" GIT_COMMITTER_DATE="2026-08-03T00:00:00+0000" \
    git_q commit -q -m sep ) >/dev/null 2>&1
pkg_sep="$(vi_field "$WORK/sep" package)"
if ! have "$pkg_sep"; then
	ko "a .git file instead of a directory is recognised as git" "no version reported"
else
	case "$pkg_sep" in
		*+git*.g*) ok "a .git file instead of a directory is recognised as git" ;;
		*) ko "a .git file instead of a directory is recognised as git" "got '$pkg_sep'" ;;
	esac
fi

# A plain directory inside somebody else's worktree must not inherit their
# commit. sources/ lives inside this build repository, so this is the real
# layout, not a contrived one.
mkdir -p "$WORK/repo/nested"
write_configure "$WORK/repo/nested"
pkg_nested="$(vi_field "$WORK/repo/nested" package)"
base_nested="$(vi_field "$WORK/repo/nested" base)"
# Against the number the fixture actually wrote, not against another field of
# the same run: `package == base` also holds when both are wrong together.
if have "$pkg_nested" "$base_nested" && [ "$base_nested" = "2026.8.27" ] &&
	[ "$pkg_nested" = "2026.8.27" ]; then
	ok "a plain directory inside a foreign repository yields the bare version"
else
	ko "a plain directory inside a foreign repository yields the bare version" \
		"got package='$pkg_nested' base='$base_nested', want 2026.8.27 for both"
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
other_hash="$(vi_field "$WORK/other" git_hash)"
own_hash="$(vi_field "$WORK/repo" git_hash)"
leaked_hash="$(GIT_DIR="$WORK/other/.git" vi_field "$WORK/repo" git_hash)"
if have "$other_hash" "$own_hash" "$leaked_hash" &&
	[ "$leaked_hash" = "$own_hash" ] && [ "$own_hash" != "$other_hash" ]; then
	ok "an inherited GIT_DIR does not stamp a foreign commit on the version"
else
	ko "an inherited GIT_DIR does not stamp a foreign commit on the version" \
		"own='$own_hash' foreign='$other_hash' with GIT_DIR set='$leaked_hash'"
fi

# GIT_DIR above is the loud one. The other four in the unset list each get their
# own assertion, because they do not fail alike: GIT_INDEX_FILE is the quiet one
# -- with no usable index every tracked file looks modified, so a clean tree
# reports ~dirty at exit 0 -- while the rest abort. git exports these around
# `rebase --exec`, hooks and `bisect run`, and they are commonly relative, so
# they stop resolving the moment this script changes directory.
for leak in GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do
	case "$leak" in
		GIT_WORK_TREE) leak_value="$WORK/other" ;;
		GIT_INDEX_FILE) leak_value="$WORK/no-such-index" ;;
		# Paths that do not exist, not the sibling fixture's: `repo` and
		# `other` are built from identical content with identical pinned
		# dates, so `other`'s object store *contains* `repo`'s HEAD and
		# `other`'s common dir answers with `repo`'s own HEAD. Both
		# assertions then held whether the unset was there or not.
		GIT_COMMON_DIR) leak_value="$WORK/no-such-common-dir" ;;
		*) leak_value="$WORK/no-such-objects" ;;
	esac
	pkg_leaked="$(env "$leak=$leak_value" "$BASH_BIN" -c \
		'SRC_DIR="$1" "$0" 2>/dev/null' "$SCRIPT" "$WORK/repo" | jget package)"
	if have "$pkg_full" && [ "$pkg_leaked" = "$pkg_full" ]; then
		ok "an inherited $leak does not change the version"
	else
		ko "an inherited $leak does not change the version" \
			"with $leak set='$pkg_leaked' without='$pkg_full'"
	fi
done

# ------------------------------------------------------------- failure modes
rm -rf "$WORK/tarball"; mkdir -p "$WORK/tarball"
write_configure "$WORK/tarball"
out_tar="$(run_vi "$WORK/tarball")"; rc_tar=$?
pkg_tar="$(printf '%s' "$out_tar" | jget package)"
base_tar="$(printf '%s' "$out_tar" | jget base)"
slug_tar="$(printf '%s' "$out_tar" | jget slug)"
if [ "$rc_tar" -eq 0 ] && [ "$base_tar" = "2026.8.27" ] &&
	[ "$pkg_tar" = "$base_tar" ] && [ "$slug_tar" = "$base_tar" ]; then
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

# A .git symlink whose target is gone. `[ -e ]` alone is false for a dangling
# symlink, so this used to take the tarball path and hand back the bare version.
rm -rf "$WORK/danglinggit"; mkdir -p "$WORK/danglinggit"
write_configure "$WORK/danglinggit"
ln -s "$WORK/there-is-no-git-dir-here" "$WORK/danglinggit/.git"
if run_vi "$WORK/danglinggit" >/dev/null 2>&1; then
	ko "a dangling .git symlink aborts instead of passing for an export" \
		"the script succeeded and reported a version anyway"
elif grep -q 'cannot use it' "$WORK/stderr.last"; then
	ok "a dangling .git symlink aborts instead of passing for an export"
else
	ko "a dangling .git symlink aborts instead of passing for an export" \
		"aborted, but without saying why: $(head -1 "$WORK/stderr.last")"
fi

# The two assertions above only reach the abort because mktemp -d lands in /tmp,
# which is not inside a repository. In the layout the build actually uses,
# sources/neutrino sits inside this repository's worktree -- and git's discovery
# walks *up*, so a .git it skips rather than errors on makes it answer with the
# enclosing repository. Non-empty, merely wrong, which is how a half-written
# clone produced the bare version at exit 0. This is also the only fixture that
# exercises the physical-path comparison at all: replacing that comparison with
# `false` left every other assertion green.
rm -rf "$WORK/enclosing"
make_repo "$WORK/enclosing"
for broken in emptydir danglinglink; do
	sub="$WORK/enclosing/sub-${broken}"
	mkdir -p "$sub"
	write_configure "$sub"
	if [ "$broken" = emptydir ]; then
		mkdir -p "$sub/.git"
		label="a half-written .git inside another worktree does not borrow its commit"
	else
		ln -s "$WORK/there-is-no-git-dir-here" "$sub/.git"
		label="a dangling .git inside another worktree does not borrow its commit"
	fi
	if run_vi "$sub" >/dev/null 2>&1; then
		ko "$label" "the script succeeded and reported $(vi_field "$sub" package)"
	elif grep -q 'broken or foreign' "$WORK/stderr.last"; then
		ok "$label"
	else
		ko "$label" "aborted, but without saying why: $(head -1 "$WORK/stderr.last")"
	fi
done

# `git diff --quiet` has three outcomes: 0 clean, 1 modified, 128 broken. Read
# as a boolean, an unreadable index became an ordinary ~dirty build -- a version
# invented out of a failure, which is the whole class of defect this file exists
# to catch.
rm -rf "$WORK/badindex"; cp -a "$WORK/repo" "$WORK/badindex"
rm -rf "$WORK/badindex/nested"
printf 'not an index' > "$WORK/badindex/.git/index"
if run_vi "$WORK/badindex" >/dev/null 2>&1; then
	ko "an unreadable index aborts instead of reporting a dirty build" \
		"the script succeeded: $(vi_field "$WORK/badindex" package)"
elif grep -q 'is modified' "$WORK/stderr.last"; then
	ok "an unreadable index aborts instead of reporting a dirty build"
else
	ko "an unreadable index aborts instead of reporting a dirty build" \
		"aborted, but without saying why: $(head -1 "$WORK/stderr.last")"
fi

# A repository before its first commit: `git rev-parse HEAD` prints the literal
# string `HEAD` on *stdout* and fails, so the object id is checked for shape and
# not just for emptiness. The message has to be the one about HEAD -- ungated,
# the run travels on to the date lookup and aborts there instead, which sends
# whoever reads it looking at the wrong thing.
rm -rf "$WORK/nocommits"; mkdir -p "$WORK/nocommits"
write_configure "$WORK/nocommits"
( cd "$WORK/nocommits" && git_q init -q . ) >/dev/null 2>&1
if run_vi "$WORK/nocommits" >/dev/null 2>&1; then
	ko "a repository before its first commit aborts" \
		"the script succeeded: $(vi_field "$WORK/nocommits" package)"
elif grep -q 'usable HEAD' "$WORK/stderr.last"; then
	ok "a repository before its first commit aborts"
else
	ko "a repository before its first commit aborts" \
		"aborted, but not about HEAD: $(head -1 "$WORK/stderr.last")"
fi

# HEAD resolves from the ref file, so the hash survives a missing commit object
# and only the date lookup fails. Ungated, that produced JSON reporting a hash
# next to a package version that had none, at exit 0.
rm -rf "$WORK/nocommitobj"; cp -a "$WORK/repo" "$WORK/nocommitobj"
rm -rf "$WORK/nocommitobj/nested"
lost="$(git_q -C "$WORK/nocommitobj" rev-parse HEAD 2>/dev/null || true)"
if [ -n "$lost" ]; then
	lost_path="$WORK/nocommitobj/.git/objects/$(printf '%s' "$lost" | cut -c1-2)/$(printf '%s' "$lost" | cut -c3-)"
	rm -f "$lost_path"
fi
if [ -n "$lost" ] && [ ! -f "$lost_path" ]; then
	if run_vi "$WORK/nocommitobj" >/dev/null 2>&1; then
		ko "a missing commit object aborts instead of dropping the commit stamp" \
			"the script succeeded: $(vi_field "$WORK/nocommitobj" package)"
	elif grep -q 'commit date' "$WORK/stderr.last"; then
		ok "a missing commit object aborts instead of dropping the commit stamp"
	else
		ko "a missing commit object aborts instead of dropping the commit stamp" \
			"aborted, but without saying why: $(head -1 "$WORK/stderr.last")"
	fi
else
	ko "the missing-commit-object fixture could be created" \
		"the commit object was packed or absent; the assertion would prove nothing"
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

# The assertion above runs against a non-git directory, so it exercises the
# export path. A repository whose *commit* has no configure.ac is a different
# door to the same room: the worktree file is right there, and reading it would
# stamp the artefact with numbers no commit ever carried.
rm -rf "$WORK/noconfhead"; mkdir -p "$WORK/noconfhead"
( cd "$WORK/noconfhead" && git_q init -q . >/dev/null 2>&1 &&
  echo x > file.txt && git_q add -A &&
  GIT_AUTHOR_DATE="2026-08-07T00:00:00+0000" GIT_COMMITTER_DATE="2026-08-07T00:00:00+0000" \
    git_q commit -q -m "without configure.ac" ) >/dev/null 2>&1
write_configure "$WORK/noconfhead" 99
if run_vi "$WORK/noconfhead" >/dev/null 2>&1; then
	ko "a configure.ac missing from HEAD aborts" \
		"the script read the worktree instead and reported $(vi_field "$WORK/noconfhead" base)"
elif grep -q 'configure.ac' "$WORK/stderr.last"; then
	ok "a configure.ac missing from HEAD aborts"
else
	ko "a configure.ac missing from HEAD aborts" \
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

# Quotes were deleted wherever they sat, before the value was measured. So
# define(ver_micro, 2"7") normalised to 27 and the artefact carried a version
# the source never stated. One matching pair around the number is still fine.
rm -rf "$WORK/oddquote"; mkdir -p "$WORK/oddquote"
printf 'define(ver_major, 2026)\ndefine(ver_minor, 8)\ndefine(ver_micro, 2"7")\n' > "$WORK/oddquote/configure.ac"
if run_vi "$WORK/oddquote" >/dev/null 2>&1; then
	ko "a misplaced quote in ver_micro is rejected, not deleted" \
		"the script reported $(vi_field "$WORK/oddquote" base) for define(ver_micro, 2\"7\")"
elif grep -q 'ver_micro' "$WORK/stderr.last"; then
	ok "a misplaced quote in ver_micro is rejected, not deleted"
else
	ko "a misplaced quote in ver_micro is rejected, not deleted" \
		"got: $(head -1 "$WORK/stderr.last")"
fi

# The grep is anchored, and the anchor is what keeps a commented-out or
# indented define from being read as the real one.
rm -rf "$WORK/commented"; mkdir -p "$WORK/commented"
printf '# define(ver_micro, 99)\ndefine(ver_major, 2026)\ndefine(ver_minor, 8)\ndefine(ver_micro, 27)\n' \
	> "$WORK/commented/configure.ac"
base_commented="$(vi_field "$WORK/commented" base)"
if have "$base_commented" && [ "$base_commented" = "2026.8.27" ]; then
	ok "a commented-out define is not mistaken for the real one"
else
	ko "a commented-out define is not mistaken for the real one" \
		"got '$base_commented', want 2026.8.27"
fi

rm -rf "$WORK/quotednum"; mkdir -p "$WORK/quotednum"
printf 'define(ver_major, 2026)\ndefine(ver_minor, 8)\ndefine(ver_micro, "27")\n' > "$WORK/quotednum/configure.ac"
base_quotednum="$(vi_field "$WORK/quotednum" base)"
if have "$base_quotednum" && [ "$base_quotednum" = "2026.8.27" ]; then
	ok "a quoted number in ver_micro is still accepted"
else
	ko "a quoted number in ver_micro is still accepted" "got '$base_quotednum'"
fi

# ------------------------------------------------------------ format promises
# The property that matters for dpkg: no hyphen, therefore no Debian revision.
# `dpkg --validate-version` cannot express this -- it accepts the old broken
# value too, because a version *with* a revision is still a valid version.
if ! have "$pkg_full"; then
	ko "the version carries no Debian revision" "no version reported"
else
	case "$pkg_full" in
		*-*) ko "the version carries no Debian revision" \
			"'$pkg_full' contains a hyphen; dpkg would split it at the last one" ;;
		*) ok "the version carries no Debian revision" ;;
	esac
fi
if command -v dpkg >/dev/null 2>&1; then
	if have "$pkg_full" && dpkg --validate-version "$pkg_full" >/dev/null 2>&1; then
		ok "dpkg accepts the version"
	else
		ko "dpkg accepts the version" "dpkg --validate-version rejected '$pkg_full'"
	fi
else
	sk "dpkg accepts the version" "dpkg is not installed on this host"
fi

# git_tag is the one field carrying text this script did not build, and a tag
# name may legally contain a double quote. Unescaped it produced malformed JSON,
# and the python consumers in make_deb.sh and gen_appimage.sh then failed on a
# perfectly legal tag.
rm -rf "$WORK/quotedtag"; cp -a "$WORK/repo" "$WORK/quotedtag"
rm -rf "$WORK/quotedtag/nested"
if ( cd "$WORK/quotedtag" && git_q tag 'v9"quoted' ) >/dev/null 2>&1; then
	# Parseable *and* intact: an implementation that dropped the tag entirely
	# would satisfy the first half and defeat the point of escaping it.
	tag_quoted="$(run_vi "$WORK/quotedtag" |
		python3 -c 'import json,sys; print(json.load(sys.stdin)["git_tag"])' 2>/dev/null || true)"
	if [ "$tag_quoted" = 'v9"quoted' ]; then
		ok "a tag containing a quote leaves the JSON parseable and the tag intact"
	else
		ko "a tag containing a quote leaves the JSON parseable and the tag intact" \
			"json.load returned '$tag_quoted', want 'v9\"quoted'"
	fi
else
	ko "the quoted-tag fixture could be created" \
		"git refused the tag name; the assertion would prove nothing"
fi

# Git refs are byte strings and may hold bytes that are not valid UTF-8, which
# no amount of escaping repairs -- the decoder rejects them before the parser
# sees a string. All three consumers died on such a tag, over a field that
# influences no name at all, so it is cut down to printable ASCII.
rm -rf "$WORK/rawtag"; cp -a "$WORK/repo" "$WORK/rawtag"
rm -rf "$WORK/rawtag/nested"
raw_tag="$(printf 'v9\377tag')"
if ( cd "$WORK/rawtag" && LC_ALL=C git_q tag "$raw_tag" ) >/dev/null 2>&1; then
	if run_vi "$WORK/rawtag" |
		PYTHONIOENCODING=utf-8:strict python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; then
		ok "a tag with non-UTF-8 bytes leaves the JSON readable"
	else
		ko "a tag with non-UTF-8 bytes leaves the JSON readable" \
			"json.load raised under strict UTF-8, as it does in make_deb.sh and gen_appimage.sh"
	fi
else
	ko "the raw-byte-tag fixture could be created" \
		"git refused the tag name; the assertion would prove nothing"
fi

# Ordering. Two guarantees, and only these two: the base decides first, and
# within one base the commit second decides. Commits sharing a second, or a
# deliberately backdated committer date, are not ordered by this scheme -- see
# docs/PACKAGING.*.md, which says so rather than promising more.
rm -rf "$WORK/older"; cp -a "$WORK/repo" "$WORK/older"
rm -rf "$WORK/older/nested"
( cd "$WORK/older" && git_q reset -q --hard HEAD~1 ) >/dev/null 2>&1
pkg_older="$(vi_field "$WORK/older" package)"
if ! have "$pkg_full" "$pkg_older"; then
	ko "a later commit sorts above an earlier one" \
		"later='$pkg_full' earlier='$pkg_older'"
elif command -v dpkg >/dev/null 2>&1; then
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

# The base has to win against the timestamp, or a release would be overtaken by
# any later commit still carrying the previous ver_micro. Upstream bumps
# ver_micro in a commit of its own, so between bumps the timestamp is all there
# is -- and the moment it bumps, that has to outrank everything before it.
rm -rf "$WORK/newerbase"; mkdir -p "$WORK/newerbase"
write_configure "$WORK/newerbase" 28
( cd "$WORK/newerbase" && git_q init -q . >/dev/null 2>&1 &&
  echo x > file.txt && git_q add -A &&
  GIT_AUTHOR_DATE="2026-07-01T00:00:00+0000" GIT_COMMITTER_DATE="2026-07-01T00:00:00+0000" \
    git_q commit -q -m bumped ) >/dev/null 2>&1
pkg_newerbase="$(vi_field "$WORK/newerbase" package)"
if ! have "$pkg_newerbase" "$pkg_full"; then
	ko "a higher ver_micro outranks a newer commit date" \
		"bumped='$pkg_newerbase' current='$pkg_full'"
elif command -v dpkg >/dev/null 2>&1; then
	if dpkg --compare-versions "$pkg_newerbase" gt "$pkg_full"; then
		ok "a higher ver_micro outranks a newer commit date"
	else
		ko "a higher ver_micro outranks a newer commit date" \
			"'$pkg_newerbase' !> '$pkg_full'"
	fi
else
	if [ "$pkg_newerbase" \> "$pkg_full" ]; then
		ok "a higher ver_micro outranks a newer commit date"
	else
		ko "a higher ver_micro outranks a newer commit date" \
			"'$pkg_newerbase' !> '$pkg_full'"
	fi
fi

# ver_micro restarts at 0 when upstream opens a new version line (2026.7.53 ->
# 2026.8.0, seen twice in the real history). The three-part base still rises,
# because ver_minor does -- that, and not ver_micro on its own, is what carries
# the ordering.
rm -rf "$WORK/line-old" "$WORK/line-new"
for line in old new; do
	dir="$WORK/line-${line}"
	mkdir -p "$dir"
	if [ "$line" = old ]; then
		printf 'define(ver_major, 2026)\ndefine(ver_minor, 7)\ndefine(ver_micro, 53)\n' > "$dir/configure.ac"
		when="2026-07-30T12:00:00+0000"
	else
		printf 'define(ver_major, 2026)\ndefine(ver_minor, 8)\ndefine(ver_micro, 0)\n' > "$dir/configure.ac"
		when="2026-07-31T12:00:00+0000"
	fi
	( cd "$dir" && git_q init -q . >/dev/null 2>&1 &&
	  echo x > file.txt && git_q add -A &&
	  GIT_AUTHOR_DATE="$when" GIT_COMMITTER_DATE="$when" \
	    git_q commit -q -m "$line" ) >/dev/null 2>&1
done
pkg_line_old="$(vi_field "$WORK/line-old" package)"
pkg_line_new="$(vi_field "$WORK/line-new" package)"
if ! have "$pkg_line_old" "$pkg_line_new"; then
	ko "a new version line outranks the end of the previous one" \
		"old='$pkg_line_old' new='$pkg_line_new'"
elif command -v dpkg >/dev/null 2>&1; then
	if dpkg --compare-versions "$pkg_line_new" gt "$pkg_line_old"; then
		ok "a new version line outranks the end of the previous one"
	else
		ko "a new version line outranks the end of the previous one" \
			"'$pkg_line_new' !> '$pkg_line_old'"
	fi
else
	if [ "$pkg_line_new" \> "$pkg_line_old" ]; then
		ok "a new version line outranks the end of the previous one"
	else
		ko "a new version line outranks the end of the previous one" \
			"'$pkg_line_new' !> '$pkg_line_old'"
	fi
fi

# A modified tree is marked, and the mark sorts BELOW the clean build -- with
# "+dirty" it would sort above, and a patched CI build would outrank the release
# it was built from.
rm -rf "$WORK/dirty"; cp -a "$WORK/repo" "$WORK/dirty"
rm -rf "$WORK/dirty/nested"
echo changed > "$WORK/dirty/file.txt"
pkg_dirty="$(vi_field "$WORK/dirty" package)"
if ! have "$pkg_dirty"; then
	ko "a modified tree is marked and sorts below the clean build" "no version reported"
else
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
				# No lexicographic fallback here: '~' sorts *above* the
				# digits lexicographically and *below* them in Debian's
				# ordering, so a shell comparison would assert the
				# opposite of what is claimed. The suffix is checked
				# above; the sorting relation needs dpkg.
				sk "a modified tree is marked and sorts below the clean build" \
					"the ~dirty suffix is present, but only dpkg can order it"
			fi
			;;
		*) ko "a modified tree is marked and sorts below the clean build" "got '$pkg_dirty'" ;;
	esac
fi

# Both flags tell git to stop looking at a file, and the dirty check then called
# a patched tree clean -- so the build took the name of the release it had been
# patched away from, which is the one thing ~dirty exists to prevent. Both
# directions, because asserting only the patched one let the opposite defect
# ship: the second opinion first reported every *clean* flagged tree as ~dirty.
# The deleted state tells the two flags apart. skip-worktree is how a sparse
# checkout says a file is deliberately not there, so a file missing behind it is
# not a modification; assume-unchanged promises only that a file that is there
# will not change, so a file deleted behind it is exactly the modification the
# flag would otherwise hide.
# `both` is its own case, not a combination of the other two: `ls-files -v` tags
# such a path `s`, and two one-character slips -- reading only `S` for the
# skip-worktree list, only `h` for the assume-unchanged one -- let a patched tree
# report the clean release version while every single-flag fixture stayed green.
# It takes two update-index calls; one call carrying both options applies only
# assume-unchanged and yields `h`.
for flag in assume-unchanged skip-worktree both; do
	for state in clean patched deleted; do
		hidden_dir="$WORK/hidden-${flag}-${state}"
		rm -rf "$hidden_dir"; cp -a "$WORK/repo" "$hidden_dir"
		rm -rf "$hidden_dir/nested"
		if [ "$flag" = both ]; then
			( cd "$hidden_dir" && git_q update-index --skip-worktree file.txt &&
			  git_q update-index --assume-unchanged file.txt ) >/dev/null 2>&1
		else
			( cd "$hidden_dir" && git_q update-index "--${flag}" file.txt ) >/dev/null 2>&1
		fi
		case "$state" in
			patched) echo patched > "$hidden_dir/file.txt" ;;
			deleted) rm -f "$hidden_dir/file.txt" ;;
		esac
		case "${flag}-${state}" in
			both-clean)
				hidden_label="a clean tree carrying both flags is not called modified"
				hidden_want=same ;;
			*-clean)
				hidden_label="a clean tree with --${flag} is not called modified"
				hidden_want=same ;;
			skip-worktree-deleted)
				hidden_label="a file left out behind --skip-worktree is not called modified"
				hidden_want=same ;;
			both-deleted)
				hidden_label="a file left out behind both flags is not called modified"
				hidden_want=same ;;
			assume-unchanged-deleted)
				hidden_label="a deletion hidden by --assume-unchanged is still marked"
				hidden_want=dirty ;;
			both-patched)
				hidden_label="a modification hidden by both flags at once is still marked"
				hidden_want=dirty ;;
			*)
				hidden_label="a modification hidden by --${flag} is still marked"
				hidden_want=dirty ;;
		esac
		if [ "$flag" = both ]; then
			hidden_tag="$( cd "$hidden_dir" && git_q ls-files -v file.txt 2>/dev/null )"
			case "$hidden_tag" in
				s*) ;;
				*)
					ko "$hidden_label" \
						"the fixture carries '$hidden_tag', not both flags; it would prove nothing"
					continue ;;
			esac
		fi
		pkg_hidden="$(vi_field "$hidden_dir" package)"
		if [ "$hidden_want" = same ]; then
			if have "$pkg_hidden" "$pkg_full" && [ "$pkg_hidden" = "$pkg_full" ]; then
				ok "$hidden_label"
			else
				ko "$hidden_label" "got '$pkg_hidden', unflagged gives '$pkg_full'"
			fi
		else
			case "$pkg_hidden" in
				*~dirty) ok "$hidden_label" ;;
				*) ko "$hidden_label" "got '$pkg_hidden', but the tree differs from HEAD" ;;
			esac
		fi
	done
done

# Three shapes of path the scan used to read wrong. A name needing C-quoting
# came back quoted, matched no file and counted as absent; a tracked symlink
# whose target is missing is not absent either -- Neutrino ships two; and a
# staged addition vanished from a scratch index rebuilt with `read-tree HEAD`,
# so the same tree answered differently depending on whether some unrelated path
# happened to carry a flag.
rm -rf "$WORK/oddpaths"; mkdir -p "$WORK/oddpaths"
write_configure "$WORK/oddpaths"
( cd "$WORK/oddpaths" && git_q init -q . >/dev/null 2>&1 &&
  echo plain > plain.txt && echo odd > 'odd"name.txt' && ln -s nowhere dead.link &&
  git_q add -A &&
  GIT_AUTHOR_DATE="2026-08-09T00:00:00+0000" GIT_COMMITTER_DATE="2026-08-09T00:00:00+0000" \
    git_q commit -q -m odd ) >/dev/null 2>&1

# Driven under both flags, because the two are cleared over different paths: the
# assume-unchanged list is every flagged path, the skip-worktree list only the
# ones that are really there. A quoted name and a dangling symlink are exactly
# the paths that presence test used to get wrong, so it has to be the
# skip-worktree list that carries them, not just the other one.
odd_case() { # $1 = label, $2 = flag, $3 = flagged path, $4 = fragment applying the change
	rm -rf "$WORK/oddwork"; cp -a "$WORK/oddpaths" "$WORK/oddwork"
	( cd "$WORK/oddwork" && git_q update-index "--$2" "$3" ) >/dev/null 2>&1
	( cd "$WORK/oddwork" && eval "$4" ) >/dev/null 2>&1
	pkg_odd="$(vi_field "$WORK/oddwork" package)"
	case "$pkg_odd" in
		*~dirty) ok "$1" ;;
		*) ko "$1" "got '$pkg_odd', but the tree is modified" ;;
	esac
}
for odd_flag in assume-unchanged skip-worktree; do
	odd_case "a patched path whose name needs quoting is still marked (--$odd_flag)" \
		"$odd_flag" 'odd"name.txt' 'echo patched > '\''odd"name.txt'\'''
	odd_case "a retargeted dangling symlink is still marked (--$odd_flag)" \
		"$odd_flag" dead.link 'ln -sfn elsewhere dead.link'
done

# A staged addition, with and without an unrelated flag: the answer has to be
# the same either way.
for extra in none flagged; do
	rm -rf "$WORK/staged-add"; cp -a "$WORK/oddpaths" "$WORK/staged-add"
	( cd "$WORK/staged-add" && echo new > new.txt && git_q add new.txt ) >/dev/null 2>&1
	[ "$extra" = none ] ||
		( cd "$WORK/staged-add" && git_q update-index --assume-unchanged plain.txt ) >/dev/null 2>&1
	pkg_add="$(vi_field "$WORK/staged-add" package)"
	staged_label="a staged addition is marked (${extra} flag elsewhere)"
	case "$pkg_add" in
		*~dirty) ok "$staged_label" ;;
		*) ko "$staged_label" "got '$pkg_add'" ;;
	esac
done

# log.showSignature makes `git show` print signature lines to stdout ahead of
# the format. On a signed HEAD that fed "No signature" into the timestamp, the
# guard rejected it, and every packaging target died with it.
rm -rf "$WORK/signed"; mkdir -p "$WORK/signed"
write_configure "$WORK/signed"
if ssh-keygen -q -t ed25519 -N '' -f "$WORK/signkey" >/dev/null 2>&1 &&
	( cd "$WORK/signed" && git_q init -q . >/dev/null 2>&1 &&
	  echo x > file.txt && git_q add -A &&
	  git_q config gpg.format ssh && git_q config user.signingkey "$WORK/signkey.pub" &&
	  git_q config log.showSignature true &&
	  GIT_AUTHOR_DATE="2026-08-10T01:30:00+0000" GIT_COMMITTER_DATE="2026-08-10T01:30:00+0000" \
	    git_q commit -qS -m signed ) >/dev/null 2>&1; then
	pkg_signed="$(vi_field "$WORK/signed" package)"
	case "$pkg_signed" in
		*+git20260810013000.g*) ok "a signed HEAD with log.showSignature still reports a version" ;;
		*) ko "a signed HEAD with log.showSignature still reports a version" \
			"got '$pkg_signed'" ;;
	esac
else
	sk "a signed HEAD with log.showSignature still reports a version" \
		"could not create an ssh-signed commit on this host"
fi

# A sparse checkout sets skip-worktree on everything it leaves out, and those
# files are missing by intent. Treating that as a modification would make a
# sparse checkout and a full clone of the same commit disagree -- the defect
# this whole file guards against, arriving from the other side.
rm -rf "$WORK/sparse"; cp -a "$WORK/repo" "$WORK/sparse"
rm -rf "$WORK/sparse/nested"
( cd "$WORK/sparse" && git_q update-index --skip-worktree file.txt &&
  git_q config core.sparseCheckout true ) >/dev/null 2>&1
rm -f "$WORK/sparse/file.txt"
pkg_sparse="$(vi_field "$WORK/sparse" package)"
if have "$pkg_sparse" "$pkg_full" && [ "$pkg_sparse" = "$pkg_full" ]; then
	ok "a sparse checkout reports the same version as the full tree"
else
	ko "a sparse checkout reports the same version as the full tree" \
		"sparse='$pkg_sparse' full='$pkg_full'"
fi

# The other half, and the one a repository-wide exemption let through: a sparse
# checkout whose *included* file is patched behind an assume-unchanged bit. What
# is absent stays ignored, what is present gets compared.
rm -rf "$WORK/sparse-inc"; mkdir -p "$WORK/sparse-inc"
write_configure "$WORK/sparse-inc"
( cd "$WORK/sparse-inc" && git_q init -q . >/dev/null 2>&1 &&
  echo included > included.txt && echo omitted > omitted.txt && git_q add -A &&
  GIT_AUTHOR_DATE="2026-08-08T00:00:00+0000" GIT_COMMITTER_DATE="2026-08-08T00:00:00+0000" \
    git_q commit -q -m sparse &&
  # Both bits first, `core.sparseCheckout` last: with the config already on and
  # no patterns file, a later `update-index` treats every path as included and
  # clears the skip-worktree bit again -- which left this fixture unable to fail.
  git_q update-index --assume-unchanged included.txt &&
  git_q update-index --skip-worktree omitted.txt &&
  git_q config core.sparseCheckout true ) >/dev/null 2>&1
rm -f "$WORK/sparse-inc/omitted.txt"
echo patched > "$WORK/sparse-inc/included.txt"
pkg_sparse_patched="$(vi_field "$WORK/sparse-inc" package)"
if ! have "$pkg_sparse_patched"; then
	ko "a patched included file in a sparse checkout is still marked" "no version reported"
else
	case "$pkg_sparse_patched" in
		*~dirty) ok "a patched included file in a sparse checkout is still marked" ;;
		*) ko "a patched included file in a sparse checkout is still marked" \
			"got '$pkg_sparse_patched', but included.txt is patched" ;;
	esac
fi

# `git diff --quiet` without HEAD compares the index against the worktree, so a
# change that is staged and nothing else looks clean.
rm -rf "$WORK/staged"; cp -a "$WORK/repo" "$WORK/staged"
rm -rf "$WORK/staged/nested"
echo staged > "$WORK/staged/file.txt"
( cd "$WORK/staged" && git_q add file.txt ) >/dev/null 2>&1
pkg_staged="$(vi_field "$WORK/staged" package)"
case "$pkg_staged" in
	*~dirty) ok "a staged-only modification is marked" ;;
	*) ko "a staged-only modification is marked" "got '$pkg_staged'" ;;
esac

# `git diff` exits 128 when it cannot answer, and reading that as "modified"
# invents a lesser version out of an error: ~dirty at exit 0 where the tree is
# unknown. Driven twice, because the comparison happens in two places: directly
# for a tree with no flags, and against the scratch index for a tree that has
# one. The stub fails only `diff`, so everything before it -- the index scan,
# the scratch copy, clearing the flags -- still runs and this reaches the
# comparison rather than an earlier guard.
#
# Through a stub rather than a real git provoked into failing. The provocation
# used before, a textconv driver naming a program that is not there, yields 128
# only on a narrow band of versions: 2.39.5 and 2.52.0 both report a plain
# difference instead, and CI went red on debian-12 and fedora-41 while
# debian-13 (2.47.3, the version this was written on) stayed green. What the
# script owes its caller is a refusal when the comparison fails; how a real git
# can be talked into failing is not part of that contract.
diff128_real_git="$(command -v git 2>/dev/null || true)"
rm -rf "$WORK/diff128bin"; mkdir -p "$WORK/diff128bin"
{
	printf '#!/bin/sh\n'
	printf 'for a in "$@"; do [ "$a" = diff ] && exit 128; done\n'
	printf 'exec %s "$@"\n' "$diff128_real_git"
} > "$WORK/diff128bin/git"
chmod +x "$WORK/diff128bin/git"
for diff128 in plain flagged; do
	diff128_dir="$WORK/diff128-$diff128"
	rm -rf "$diff128_dir"; cp -a "$WORK/repo" "$diff128_dir"
	rm -rf "$diff128_dir/nested"
	[ "$diff128" = plain ] ||
		( cd "$diff128_dir" && git_q update-index --assume-unchanged file.txt ) >/dev/null 2>&1
	echo patched > "$diff128_dir/file.txt"
	diff128_label="a comparison that cannot answer aborts ($diff128)"
	# The message has to name the comparison. Aborting is not enough on its own:
	# an earlier guard failing would abort too, and then this would be green
	# without the comparison ever having been reached.
	if PATH="$WORK/diff128bin:$PATH" run_vi "$diff128_dir" >/dev/null 2>&1; then
		ko "$diff128_label" "the script succeeded: $(vi_field "$diff128_dir" package)"
	elif grep -q 'git diff exited 128' "$WORK/stderr.last"; then
		ok "$diff128_label"
	else
		ko "$diff128_label" "aborted elsewhere: $(head -2 "$WORK/stderr.last" | tr '\n' ' ')"
	fi
done

# The dirty check needs two temporary files: the scan it reads the index into,
# and the scratch index itself. Neither being available must abort, not quietly
# decide the tree is clean -- that is a version invented out of a failure, which
# is the whole class this file exists to catch.
#
# Two fixtures, because a stub that fails every mktemp only ever reaches the
# first one: the scan is written before anything is known about the flags, so
# the run aborts there and the scratch index is never attempted. The second stub
# counts, letting the scan through and failing after it.
rm -rf "$WORK/nomktemp"; cp -a "$WORK/repo" "$WORK/nomktemp"
rm -rf "$WORK/nomktemp/nested"
( cd "$WORK/nomktemp" && git_q update-index --assume-unchanged file.txt ) >/dev/null 2>&1
echo patched > "$WORK/nomktemp/file.txt"
mkdir -p "$WORK/nomktempbin"
printf '#!/bin/sh\nexit 1\n' > "$WORK/nomktempbin/mktemp"
chmod +x "$WORK/nomktempbin/mktemp"
if PATH="$WORK/nomktempbin:$PATH" run_vi "$WORK/nomktemp" >/dev/null 2>&1; then
	ko "a temporary file that cannot be created aborts" \
		"the script succeeded and reported a version anyway"
elif grep -q 'is modified' "$WORK/stderr.last"; then
	ok "a temporary file that cannot be created aborts"
else
	ko "a temporary file that cannot be created aborts" \
		"aborted, but without saying why: $(head -1 "$WORK/stderr.last")"
fi

# Same tree, but mktemp fails only from the second call on, so the scan is
# written and the scratch index is the thing that cannot be had.
rm -rf "$WORK/nosecond"; cp -a "$WORK/repo" "$WORK/nosecond"
rm -rf "$WORK/nosecond/nested"
( cd "$WORK/nosecond" && git_q update-index --assume-unchanged file.txt ) >/dev/null 2>&1
echo patched > "$WORK/nosecond/file.txt"
rm -rf "$WORK/nosecondbin"; mkdir -p "$WORK/nosecondbin"
real_mktemp="$(command -v mktemp 2>/dev/null || true)"
if [ -z "$real_mktemp" ]; then
	ko "a scratch index that cannot be created aborts" \
		"mktemp is not on PATH, so the stub has nothing to forward to"
else
	{
		printf '#!/bin/sh\n'
		printf 'n=$(cat "%s" 2>/dev/null || echo 0)\n' "$WORK/nosecond.count"
		printf 'echo $((n + 1)) > "%s"\n' "$WORK/nosecond.count"
		printf '[ "$n" -ge 1 ] && exit 1\n'
		printf 'exec %s "$@"\n' "$real_mktemp"
	} > "$WORK/nosecondbin/mktemp"
	chmod +x "$WORK/nosecondbin/mktemp"
	rm -f "$WORK/nosecond.count"
	if PATH="$WORK/nosecondbin:$PATH" run_vi "$WORK/nosecond" >/dev/null 2>&1; then
		ko "a scratch index that cannot be created aborts" \
			"the script succeeded and reported a version anyway"
	elif [ ! -s "$WORK/nosecond.count" ] || [ "$(cat "$WORK/nosecond.count")" -lt 2 ]; then
		ko "a scratch index that cannot be created aborts" \
			"mktemp ran $(cat "$WORK/nosecond.count" 2>/dev/null) times; the scratch index was never attempted"
	elif grep -q 'is modified' "$WORK/stderr.last"; then
		ok "a scratch index that cannot be created aborts"
	else
		ko "a scratch index that cannot be created aborts" \
			"aborted, but without saying why: $(head -1 "$WORK/stderr.last")"
	fi
fi

# core.fsmonitor is the third way to stop git looking at a file, and the only one
# the scan cannot see -- `ls-files -v` does not show the fsmonitor-valid bit, so
# nothing looks flagged and the ordinary diff takes the monitor's word for it. A
# hook that answers "nothing changed" is exactly what a stale monitor does.
#
# Driven twice. The defence is a config value injected through the environment,
# and GIT_CONFIG_PARAMETERS -- which git exports to every child of a `git -c …`
# invocation, so a hook, `rebase --exec` or `bisect run` inherits it -- outranks
# that injection. Pointed back at the monitor, it switched the defence off again
# and the patched tree reported the clean release name.
#
# A fresh fixture per run, because the first run rewrites the index with the
# monitor disabled and clears the fsmonitor-valid bits: reusing it would leave
# nothing to hide behind, and the second assertion would pass against no defence
# at all. Built from scratch rather than copied for the same reason -- `cp -a`
# keeps the mtimes, so the priming `status` finds nothing to refresh, never
# rewrites the index, and the bits are never stored.
for fsmon_env in plain inherited-params; do
	fsmon_dir="$WORK/fsmon-$fsmon_env"
	rm -rf "$fsmon_dir"; mkdir -p "$fsmon_dir"
	write_configure "$fsmon_dir"
	( cd "$fsmon_dir" && git_q init -q . && echo clean > file.txt && git_q add -A &&
	  GIT_AUTHOR_DATE="2026-08-09T00:00:00+0000" GIT_COMMITTER_DATE="2026-08-09T00:00:00+0000" \
	    git_q commit -q -m fsmon ) >/dev/null 2>&1
	mkdir -p "$fsmon_dir/.git/hooks"
	printf '#!/bin/sh\nprintf "token\\0"\n' > "$fsmon_dir/.git/hooks/fsmon-stub"
	chmod +x "$fsmon_dir/.git/hooks/fsmon-stub"
	( cd "$fsmon_dir" &&
	  git_q config core.fsmonitor .git/hooks/fsmon-stub &&
	  git_q config core.fsmonitorHookVersion 2 &&
	  git_q status --porcelain ) >/dev/null 2>&1
	echo patched > "$fsmon_dir/file.txt"
	fsmon_seen="$( cd "$fsmon_dir" && git_q ls-files -f file.txt 2>/dev/null )"
	fsmon_label="a modification hidden by core.fsmonitor is still marked ($fsmon_env)"
	if [ "$fsmon_env" = plain ]; then
		pkg_fsmon="$(vi_field "$fsmon_dir" package)"
	else
		pkg_fsmon="$(GIT_CONFIG_PARAMETERS="'core.fsmonitor=.git/hooks/fsmon-stub' 'core.fsmonitorhookversion=2'" \
			vi_field "$fsmon_dir" package)"
	fi
	case "$fsmon_seen" in
		[a-z]*)
			case "$pkg_fsmon" in
				*~dirty) ok "$fsmon_label" ;;
				*) ko "$fsmon_label" "got '$pkg_fsmon', but the tree is patched" ;;
			esac
			;;
		*)
			ko "$fsmon_label" \
				"the monitor never marked file.txt valid (ls-files -f: '$fsmon_seen'); the assertion would prove nothing"
			;;
	esac
done

# Two more steps of the second opinion can fail on their own: reading the index,
# and clearing the bits in the scratch copy. Either failure leaves the flags
# where they are, so answering "clean" would again be a version invented out of
# a failure. A stub that fails exactly one git subcommand is the only way to
# reach those branches -- anything else that could break them breaks an earlier
# step, and that aborts one step earlier.
stub_git_case() { # $1 = label, $2 = subcommand the stub makes fail
	rm -rf "$WORK/stubwork"; cp -a "$WORK/repo" "$WORK/stubwork"
	rm -rf "$WORK/stubwork/nested"
	( cd "$WORK/stubwork" && git_q update-index --assume-unchanged file.txt ) >/dev/null 2>&1
	echo patched > "$WORK/stubwork/file.txt"
	rm -rf "$WORK/stubbin"; mkdir -p "$WORK/stubbin"
	{
		printf '#!/bin/sh\n'
		printf 'for a in "$@"; do [ "$a" = %s ] && exit 1; done\n' "$2"
		printf 'exec %s "$@"\n' "$stub_real_git"
	} > "$WORK/stubbin/git"
	chmod +x "$WORK/stubbin/git"
	if PATH="$WORK/stubbin:$PATH" run_vi "$WORK/stubwork" >/dev/null 2>&1; then
		ko "$1" "the script succeeded and reported a version anyway"
	elif grep -q 'is modified' "$WORK/stderr.last"; then
		ok "$1"
	else
		ko "$1" "aborted, but without saying why: $(head -1 "$WORK/stderr.last")"
	fi
}

# The scratch index is a copy of the real one, and a copy that cannot be made
# leaves the flags in place just as surely as one that cannot be cleared.
rm -rf "$WORK/nocp"; cp -a "$WORK/repo" "$WORK/nocp"
rm -rf "$WORK/nocp/nested"
( cd "$WORK/nocp" && git_q update-index --assume-unchanged file.txt ) >/dev/null 2>&1
echo patched > "$WORK/nocp/file.txt"
rm -rf "$WORK/nocpbin"; mkdir -p "$WORK/nocpbin"
printf '#!/bin/sh\nexit 1\n' > "$WORK/nocpbin/cp"
chmod +x "$WORK/nocpbin/cp"
if PATH="$WORK/nocpbin:$PATH" run_vi "$WORK/nocp" >/dev/null 2>&1; then
	ko "a scratch index that cannot be copied aborts" \
		"the script succeeded and reported a version anyway"
elif grep -q 'is modified' "$WORK/stderr.last"; then
	ok "a scratch index that cannot be copied aborts"
else
	ko "a scratch index that cannot be copied aborts" \
		"aborted, but without saying why: $(head -1 "$WORK/stderr.last")"
fi

stub_real_git="$(command -v git 2>/dev/null || true)"
if [ -z "$stub_real_git" ]; then
	ko "an index that cannot be read aborts" \
		"git is not on PATH, so the stub has nothing to forward to"
	ko "a scratch index whose flags cannot be cleared aborts" \
		"git is not on PATH, so the stub has nothing to forward to"
else
	stub_git_case "an index that cannot be read aborts" ls-files
	stub_git_case "a scratch index whose flags cannot be cleared aborts" update-index
fi

# ~dirty only sorts below the clean build while the rest of the version stays
# put. Read from the worktree, an edited configure.ac moved the base with it:
# ver_micro 27 -> 99 produced 2026.8.99+git...~dirty, which outranks the clean
# 2026.8.27+git... it was built from. The numbers come from the commit.
rm -rf "$WORK/dirtyconf"; cp -a "$WORK/repo" "$WORK/dirtyconf"
rm -rf "$WORK/dirtyconf/nested"
write_configure "$WORK/dirtyconf" 99
base_dirtyconf="$(vi_field "$WORK/dirtyconf" base)"
pkg_dirtyconf="$(vi_field "$WORK/dirtyconf" package)"
base_clean="$(vi_field "$WORK/repo" base)"
if ! have "$base_dirtyconf" "$pkg_dirtyconf" "$base_clean" "$pkg_full"; then
	ko "an edited configure.ac cannot outrank the commit it came from" \
		"base='$base_dirtyconf' package='$pkg_dirtyconf'"
elif [ "$base_dirtyconf" != "$base_clean" ]; then
	ko "an edited configure.ac cannot outrank the commit it came from" \
		"the worktree moved the base to '$base_dirtyconf'; HEAD says '$base_clean'"
elif command -v dpkg >/dev/null 2>&1; then
	if dpkg --compare-versions "$pkg_dirtyconf" lt "$pkg_full"; then
		ok "an edited configure.ac cannot outrank the commit it came from"
	else
		ko "an edited configure.ac cannot outrank the commit it came from" \
			"'$pkg_dirtyconf' !< '$pkg_full'"
	fi
else
	# Same reason as above: the base is checked without dpkg, the ordering
	# relation across the '~' is not something a shell comparison can decide.
	sk "an edited configure.ac cannot outrank the commit it came from" \
		"the base is unmoved, but only dpkg can order the ~dirty form"
fi

# Untracked leftovers are not a source change: autogen produces them on every
# build, and marking those would make every artefact dirty.
rm -rf "$WORK/untracked"; cp -a "$WORK/repo" "$WORK/untracked"
rm -rf "$WORK/untracked/nested"
echo leftover > "$WORK/untracked/Makefile.in"
pkg_untracked="$(vi_field "$WORK/untracked" package)"
if ! have "$pkg_untracked"; then
	ko "an untracked leftover does not count as a modification" "no version reported"
else
	case "$pkg_untracked" in
		*dirty*) ko "an untracked leftover does not count as a modification" \
			"got '$pkg_untracked'" ;;
		*) ok "an untracked leftover does not count as a modification" ;;
	esac
fi

slug_full="$(vi_field "$WORK/repo" slug)"
if ! have "$slug_full"; then
	ko "the filename form carries no plus sign" "no slug reported"
else
	case "$slug_full" in
		*+*) ko "the filename form carries no plus sign" "got '$slug_full'" ;;
		*) ok "the filename form carries no plus sign" ;;
	esac
fi
if have "$slug_full" &&
	printf '%s' "$slug_full" | LC_ALL=C grep -q '^[A-Za-z0-9._-]\{1,\}$'; then
	ok "the filename form uses only characters safe in a file name"
else
	ko "the filename form uses only characters safe in a file name" "got '$slug_full'"
fi

# The exact transformation, for both shapes the version can take. "no plus" and
# "safe characters" above are satisfied by any number of wrong answers; this one
# is satisfied by exactly one. The dirty form loses its tilde to the sanitiser,
# which is why the promise is '+' -> '.' *and* '~' -> '-', not just the first.
slug_dirty="$(vi_field "$WORK/dirty" slug)"
want_clean="$(printf '%s' "$pkg_full" | tr '+' '.' | tr '~' '-')"
want_dirty="$(printf '%s' "$pkg_dirty" | tr '+' '.' | tr '~' '-')"
if have "$slug_full" "$slug_dirty" &&
	[ "$slug_full" = "$want_clean" ] && [ "$slug_dirty" = "$want_dirty" ]; then
	ok "the filename form is the version with '+' as '.' and '~' as '-'"
else
	ko "the filename form is the version with '+' as '.' and '~' as '-'" \
		"clean got='$slug_full' want='$want_clean'; dirty got='$slug_dirty' want='$want_dirty'"
fi

# ------------------------------------------------------------------ consumers
# The message a user actually sees when the tool is missing. Correcting the
# package name in both guides and leaving the script saying something else is
# how the wrong advice survived a round of review.
deb_missing_msg="$(grep -m1 'dpkg-deb missing' "$ROOT_DIR/scripts/make_deb.sh" || true)"
case "$deb_missing_msg" in
	'') ko "make_deb.sh names the right package when dpkg-deb is missing" \
		"no 'dpkg-deb missing' message found in scripts/make_deb.sh" ;;
	*dpkg-dev*) ko "make_deb.sh names the right package when dpkg-deb is missing" \
		"it says dpkg-dev, but dpkg-deb ships with dpkg: $deb_missing_msg" ;;
	*dpkg*) ok "make_deb.sh names the right package when dpkg-deb is missing" ;;
	*) ko "make_deb.sh names the right package when dpkg-deb is missing" \
		"the message names no package at all: $deb_missing_msg" ;;
esac

# Both consumers are driven for real rather than by evaluating the line that
# computes their version. Evaluating the expression proves only that the
# expression is right: a make_deb.sh that reads the correct value and then
# overrides PACKAGE_VERSION on the next line passed that check.
if command -v dpkg-deb >/dev/null 2>&1; then
	rm -rf "$WORK/deb-install" "$WORK/deb-out"
	mkdir -p "$WORK/deb-install/usr/bin" "$WORK/deb-out"
	echo placeholder > "$WORK/deb-install/usr/bin/neutrino"
	deb_log="$WORK/deb.log"
	if ( cd "$ROOT_DIR" &&
		SRC_DIR="$WORK/repo" \
		NEUTRINO_INSTALL_DIR="$WORK/deb-install" \
		DEB_OUTPUT_DIR="$WORK/deb-out" \
		PACKAGE_NAME=test-version-info \
		"$BASH_BIN" scripts/make_deb.sh ) >"$deb_log" 2>&1; then
		deb_file="$(find "$WORK/deb-out" -maxdepth 1 -name '*.deb' -print 2>/dev/null | head -n1)"
		deb_control_version="$(dpkg-deb -f "$deb_file" Version 2>/dev/null || true)"
		deb_base="$(basename "${deb_file:-}")"
		if have "$pkg_full" && [ "$deb_control_version" = "$pkg_full" ]; then
			ok "the built .deb carries the reported version in its control file"
		else
			ko "the built .deb carries the reported version in its control file" \
				"control='$deb_control_version' version_info='$pkg_full'"
		fi
		case "$deb_base" in
			"test-version-info_${slug_full}_"*.deb)
				ok "the built .deb is named with the reported slug" ;;
			*)
				ko "the built .deb is named with the reported slug" \
					"got '$deb_base', want test-version-info_${slug_full}_<arch>.deb" ;;
		esac
	else
		# Two failures, not one: the success path emits two assertions, and
		# collapsing them into a single `ko` made pass+fail+skip drop by one
		# whenever make_deb.sh failed for any reason.
		ko "the built .deb carries the reported version in its control file" \
			"scripts/make_deb.sh failed: $(tail -n 2 "$deb_log" 2>/dev/null)"
		ko "the built .deb is named with the reported slug" \
			"scripts/make_deb.sh failed: $(tail -n 2 "$deb_log" 2>/dev/null)"
	fi
else
	sk "the built .deb carries the reported version in its control file" \
		"dpkg-deb is not installed on this host"
	sk "the built .deb is named with the reported slug" \
		"dpkg-deb is not installed on this host"
fi

# The AppImage name, from the real generator. Everything expensive is skipped:
# a stub stands in for appimagetool and the staged tree holds one placeholder
# binary, which is enough to reach the naming decision.
rm -rf "$WORK/app-install" "$WORK/app-out" "$WORK/app-bin"
mkdir -p "$WORK/app-install/usr/bin" "$WORK/app-install/opt/neutrino/usr/var" \
	"$WORK/app-out" "$WORK/app-bin"
cp /bin/true "$WORK/app-install/usr/bin/neutrino" 2>/dev/null ||
	printf '#!/bin/sh\nexit 0\n' > "$WORK/app-install/usr/bin/neutrino"
chmod +x "$WORK/app-install/usr/bin/neutrino"
printf '#!/bin/sh\n: > "$2"\nexit 0\n' > "$WORK/app-bin/test-appimagetool"
chmod +x "$WORK/app-bin/test-appimagetool"
app_log="$WORK/app.log"
if ( cd "$ROOT_DIR" &&
	PATH="$WORK/app-bin:$PATH" \
	SRC_DIR="$WORK/repo" \
	NEUTRINO_INSTALL_DIR="$WORK/app-install" \
	APPIMAGE_OUTPUT_DIR="$WORK/app-out" \
	APPIMAGE_TOOL=test-appimagetool \
	APPIMAGE_BUNDLE_GSTREAMER=0 \
	"$BASH_BIN" scripts/gen_appimage.sh ) >"$app_log" 2>&1; then
	app_base="$(basename "$(find "$WORK/app-out" -maxdepth 1 -name '*.AppImage' -print 2>/dev/null | head -n1)")"
	case "$app_base" in
		"Neutrino_${slug_full}_"*.AppImage)
			ok "the generated AppImage is named with the reported slug" ;;
		*)
			ko "the generated AppImage is named with the reported slug" \
				"got '$app_base', want Neutrino_${slug_full}_<arch>.AppImage" ;;
	esac
else
	ko "scripts/gen_appimage.sh names a package from a minimal tree" \
		"$(tail -n 2 "$app_log" 2>/dev/null)"
fi

# The third artifact the change names. It had neither a real run nor an
# expression check, so switching it from slug to package -- putting a '+' back
# into a file name, the exact thing slug exists to prevent -- left the suite green.
rm -rf "$WORK/static-install" "$WORK/static-out"
mkdir -p "$WORK/static-install/usr/bin" "$WORK/static-out"
echo placeholder > "$WORK/static-install/usr/bin/neutrino"
static_log="$WORK/static.log"
if ( cd "$ROOT_DIR" &&
	SRC_DIR="$WORK/repo" \
	NEUTRINO_INSTALL_DIR_STATIC="$WORK/static-install" \
	STATIC_OUTPUT_DIR="$WORK/static-out" \
	"$BASH_BIN" scripts/static_link.sh ) >"$static_log" 2>&1; then
	static_base="$(basename "$(find "$WORK/static-out" -maxdepth 1 -name '*.tar.gz' -print 2>/dev/null | head -n1)")"
	if [ "$static_base" = "neutrino-generic-static_${slug_full}.tar.gz" ]; then
		ok "the static tarball is named with the reported slug"
	else
		ko "the static tarball is named with the reported slug" \
			"got '$static_base', want neutrino-generic-static_${slug_full}.tar.gz"
	fi
else
	ko "scripts/static_link.sh builds an archive from a minimal tree" \
		"$(tail -n 2 "$static_log" 2>/dev/null)"
fi

printf -- '----\n'
printf '[test-version-info] pass=%d fail=%d skip=%d\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ] || exit 1
exit 0
