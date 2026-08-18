#!/bin/sh
#
# Unit test for scripts/release_tag.sh, the name an archived AppImage release
# hangs on.
#
# The point of the script is that the artefact slug alone is not unique: it is
# derived entirely from Neutrino, so two builds of the same Neutrino commit
# carry the same name even when the build system or libstb-hal changed
# underneath. Every assertion below exists to keep the other two halves --
# build system commit and libstb-hal commit -- attached, and to keep the whole
# truthful about a modified worktree.
#
# The real file is driven inside a temporary tree with a stubbed
# version_info.sh, because the script resolves everything relative to its own
# location. That also keeps the suite runnable without a Neutrino checkout.
#
# POSIX sh, no external deps beyond git and python3. Exits 0 on success.

set -u

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/release_tag.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
skip=0

sk() { skip=$((skip + 1)); printf 'skip %-46s %s\n' "$1" "$2"; }

ok() { pass=$((pass + 1)); printf 'ok   %-46s %s\n' "$1" "$2"; }

no() {
	fail=$((fail + 1))
	printf 'FAIL %-46s want(%s) got(%s)\n' "$1" "$2" "$3"
}

# make_tree <json-body> -- a temp copy of the script next to a version_info.sh
# that reports exactly what the case needs.
make_tree() {
	rm -rf "$WORK/tree"
	mkdir -p "$WORK/tree/scripts"
	cp "$SCRIPT" "$WORK/tree/scripts/release_tag.sh"
	chmod +x "$WORK/tree/scripts/release_tag.sh"
	printf '#!/bin/sh\ncat <<JSON\n%s\nJSON\n' "$1" > "$WORK/tree/scripts/version_info.sh"
	chmod +x "$WORK/tree/scripts/version_info.sh"
}

# The fixtures must not inherit the developer's git config -- the same trap
# test_version_info.sh documents. A global commit.gpgsign, or the commit-msg
# hook a core.hooksPath installs, makes every fixture commit fail, and the suite
# then blames the script under test. (Observed here: the hook printed "subject
# is not <type> (<scope>): summary" for the seed commit.)
git_q() {
	GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
		git -c user.email=t@example.invalid -c user.name=Test \
		    -c init.defaultBranch=main -c commit.gpgsign=false \
		    -c core.hooksPath=/dev/null "$@"
}

# make_repo -- turn the tree into a git repository with one commit, so the
# deriving branch has a HEAD to read.
make_repo() {
	git_q -C "$WORK/tree" init -q 2>/dev/null
	echo seed > "$WORK/tree/seed.txt"
	git_q -C "$WORK/tree" add seed.txt
	git_q -C "$WORK/tree" commit -qm seed
}

# libstb-hal is part of the tag, so every fixture needs one. A repository of its
# own, not a copy of the tree: the script must read *that* checkout, and a bug
# that reads the build repo instead has to show up here.
make_hal() {
	rm -rf "$WORK/hal"; mkdir -p "$WORK/hal"
	git_q -C "$WORK/hal" init -q 2>/dev/null
	echo hal > "$WORK/hal/hal.txt"
	git_q -C "$WORK/hal" add hal.txt
	git_q -C "$WORK/hal" commit -qm hal
}

# libdvbsi++ is the fourth part and the second unpinned dependency:
# make/deps.mk clones DVBSI_GIT_REF (`master`) at its tip. A repository of its
# own again, so that reading the commit from the wrong checkout shows up here.
make_dvbsi() {
	rm -rf "$WORK/dvbsi"; mkdir -p "$WORK/dvbsi"
	git_q -C "$WORK/dvbsi" init -q 2>/dev/null
	echo dvbsi > "$WORK/dvbsi/dvbsi.txt"
	git_q -C "$WORK/dvbsi" add dvbsi.txt
	git_q -C "$WORK/dvbsi" commit -qm dvbsi
}

# `package` ist absichtlich mit drin und absichtlich anders: version_info.sh
# meldet beide, und der Kopf von release_tag.sh nennt ausdruecklich "slug, not
# package" -- ein '+' im Namen wird von Uploadern als Leerzeichen gelesen. Ohne
# dieses Feld im Stub ueberlebt eine Mutation auf `package` den ganzen Test.
SLUG_JSON='{ "base": "2026.8.42", "package": "2026.8.42+git20260816192537.g85503bef6f", "slug": "2026.8.42.git20260816192537.g85503bef6f" }'
SLUG='2026.8.42.git20260816192537.g85503bef6f'

if ! command -v python3 >/dev/null 2>&1; then
	sk "the whole suite" "python3 not available"
	echo "----"
	echo "[test-shell] pass=$pass fail=$fail skip=$skip"
	exit 0
fi

if ! command -v git >/dev/null 2>&1; then
	sk "the whole suite" "git not available"
	echo "----"
	echo "[test-shell] pass=$pass fail=$fail skip=$skip"
	exit 0
fi

make_hal
HAL=$(git_q -C "$WORK/hal" rev-parse --short=7 HEAD)
LIBSTB_HAL_DIR="$WORK/hal"
export LIBSTB_HAL_DIR

make_dvbsi
DVBSI=$(git_q -C "$WORK/dvbsi" rev-parse --short=7 HEAD)
DVBSI_SRC_DIR="$WORK/dvbsi"
export DVBSI_SRC_DIR

# --- a caller-supplied commit is used as given, shortened to seven ---
make_tree "$SLUG_JSON"
got=$("$WORK/tree/scripts/release_tag.sh" abcdef1 2>&1) || got="rc=$?"
want="build/${SLUG}-abcdef1-hal${HAL}-dvbsi${DVBSI}"
[ "$got" = "$want" ] && ok "explicit commit names the tag" "$got" \
	|| no "explicit commit names the tag" "$want" "$got"

# github.sha is 40 characters. Left whole, the tag would be unreadable and the
# release list unscannable.
got=$("$WORK/tree/scripts/release_tag.sh" 5eefe8e1234567890abcdef1234567890abcdef1 2>&1) || got="rc=$?"
want="build/${SLUG}-5eefe8e-hal${HAL}-dvbsi${DVBSI}"
[ "$got" = "$want" ] && ok "a full sha is shortened to seven" "$got" \
	|| no "a full sha is shortened to seven" "$want" "$got"

# CDPATH makes `cd` write the directory it resolved to on *stdout*, so ROOT_DIR
# would hold two newline-separated paths and every path built from it would be
# wrong. It applies to relative paths, which is exactly how the workflow calls
# this script -- and scripts/version_info.sh unsets it for the same reason,
# naming the builder's profile as where it comes from. Reproduced here the way
# it was found: the script reports a version_info.sh that is plainly there.
make_tree "$SLUG_JSON"
got=$(cd "$WORK/tree" && CDPATH="$WORK/tree" scripts/release_tag.sh abcdef1 2>&1) || got="rc=$?"
want="build/${SLUG}-abcdef1-hal${HAL}-dvbsi${DVBSI}"
[ "$got" = "$want" ] && ok "a relative call survives CDPATH" "$got" \
	|| no "a relative call survives CDPATH" "$want" "$got"

# slug beats package, and the difference is visible: the stub reports both, and
# only one of them is a legal filename half. This is the rule release_tag.sh
# names in its own header; without an assertion on it, a mutation to `package`
# would pass every other case.
make_tree "$SLUG_JSON"
got=$("$WORK/tree/scripts/release_tag.sh" abcdef1 2>&1) || got="rc=$?"
case "$got" in
	*+*) plus=1 ;;
	*) plus=0 ;;
esac
[ "$got" = "build/${SLUG}-abcdef1-hal${HAL}-dvbsi${DVBSI}" ] && [ "$plus" = 0 ] \
	&& ok "slug is used, not package" "$got" \
	|| no "slug is used, not package" "build/<slug>-abcdef1-hal<hal>, kein '+'" "$got"

# --- the slug half must actually come from version_info.sh ---
make_tree '{ "base": "1.2.3", "slug": "1.2.3.gdeadbee" }'
got=$("$WORK/tree/scripts/release_tag.sh" abcdef1 2>&1) || got="rc=$?"
want="build/1.2.3.gdeadbee-abcdef1-hal${HAL}-dvbsi${DVBSI}"
[ "$got" = "$want" ] && ok "the slug comes from version_info.sh" "$got" \
	|| no "the slug comes from version_info.sh" "$want" "$got"

# base is the documented fallback when slug is absent, matching gen_appimage.sh.
make_tree '{ "base": "2026.8.42" }'
got=$("$WORK/tree/scripts/release_tag.sh" abcdef1 2>&1) || got="rc=$?"
want="build/2026.8.42-abcdef1-hal${HAL}-dvbsi${DVBSI}"
[ "$got" = "$want" ] && ok "base stands in when slug is absent" "$got" \
	|| no "base stands in when slug is absent" "$want" "$got"

# --- deriving from HEAD ---
{
	make_tree "$SLUG_JSON"
	make_repo
	head=$(git_q -C "$WORK/tree" rev-parse --short=7 HEAD)
	got=$("$WORK/tree/scripts/release_tag.sh" 2>&1) || got="rc=$?"
	want="build/${SLUG}-${head}-hal${HAL}-dvbsi${DVBSI}"
	[ "$got" = "$want" ] && ok "HEAD stands in when no commit is given" "$got" \
		|| no "HEAD stands in when no commit is given" "$want" "$got"

	# A modified tracked file means the tag would otherwise name a commit that
	# is not what got packaged.
	echo changed > "$WORK/tree/seed.txt"
	got=$("$WORK/tree/scripts/release_tag.sh" 2>&1) || got="rc=$?"
	want="build/${SLUG}-${head}-hal${HAL}-dvbsi${DVBSI}-dirty"
	[ "$got" = "$want" ] && ok "a modified worktree is marked dirty" "$got" \
		|| no "a modified worktree is marked dirty" "$want" "$got"

	# An untracked file is not a modification. plugins/tuxwetter-neutrino/ sits
	# untracked in the real repository and belongs to the developer; counting it
	# would stamp -dirty on every archived release built there.
	git_q -C "$WORK/tree" checkout -q -- seed.txt
	mkdir -p "$WORK/tree/plugins/somebodys-checkout"
	echo x > "$WORK/tree/plugins/somebodys-checkout/file"
	got=$("$WORK/tree/scripts/release_tag.sh" 2>&1) || got="rc=$?"
	want="build/${SLUG}-${head}-hal${HAL}-dvbsi${DVBSI}"
	[ "$got" = "$want" ] && ok "an untracked file is not dirty" "$got" \
		|| no "an untracked file is not dirty" "$want" "$got"

	# The one untracked exception that does change the build. make/main.mk
	# includes Makefile.local into every build and CLAUDE.md recommends it for
	# TOOLCHAIN_GCC_VERSION, so a package built with one is not reproducible
	# from the commits the tag names -- and git, which never reports the file,
	# cannot say so.
	echo 'TOOLCHAIN_GCC_VERSION := 15' > "$WORK/tree/Makefile.local"
	got=$("$WORK/tree/scripts/release_tag.sh" 2>&1) || got="rc=$?"
	want="build/${SLUG}-${head}-hal${HAL}-dvbsi${DVBSI}-dirty"
	[ "$got" = "$want" ] && ok "a local Makefile override is dirty" "$got" \
		|| no "a local Makefile override is dirty" "$want" "$got"

	# It counts even when the caller passed a commit in: a commit vouches for a
	# commit, and nobody vouches for a file that is in none.
	got=$("$WORK/tree/scripts/release_tag.sh" abcdef1 2>&1) || got="rc=$?"
	want="build/${SLUG}-abcdef1-hal${HAL}-dvbsi${DVBSI}-dirty"
	[ "$got" = "$want" ] && ok "an override counts with a given commit" "$got" \
		|| no "an override counts with a given commit" "$want" "$got"
	rm -f "$WORK/tree/Makefile.local"

	# main.mk reads a second one, late, for targets that need the derived
	# values. It changes the build just as much.
	echo 'NEUTRINO_EXTRA := 1' > "$WORK/tree/Makefile.local.post"
	got=$("$WORK/tree/scripts/release_tag.sh" 2>&1) || got="rc=$?"
	want="build/${SLUG}-${head}-hal${HAL}-dvbsi${DVBSI}-dirty"
	[ "$got" = "$want" ] && ok "Makefile.local.post counts as well" "$got" \
		|| no "Makefile.local.post counts as well" "$want" "$got"
	rm -f "$WORK/tree/Makefile.local.post"

	# git can also be told to stop looking at a file. The ordinary diff then
	# calls a patched tree clean and the tag names a commit that is not what got
	# packaged -- the very failure this script exists to prevent, arriving
	# through a different door. Each case is guarded: a fixture that does not
	# actually hide the change would make the assertion prove nothing.
	for hide in assume-unchanged skip-worktree; do
		rm -rf "$WORK/tree"; make_tree "$SLUG_JSON"; make_repo
		head=$(git_q -C "$WORK/tree" rev-parse --short=7 HEAD)
		echo patched > "$WORK/tree/seed.txt"
		git_q -C "$WORK/tree" update-index "--$hide" seed.txt
		label="a change hidden by $hide is still dirty"
		if git_q -C "$WORK/tree" diff --quiet HEAD --; then
			got=$("$WORK/tree/scripts/release_tag.sh" 2>&1) || got="rc=$?"
			want="build/${SLUG}-${head}-hal${HAL}-dvbsi${DVBSI}-dirty"
			[ "$got" = "$want" ] && ok "$label" "$got" || no "$label" "$want" "$got"
		else
			no "$label" "a fixture that hides the change" "git diff saw it anyway"
		fi
	done

	# The third way, and the only one the index does not show: with
	# core.fsmonitor nothing is flagged -- `ls-files -v` says H -- so the scan
	# finds a clean index and the diff takes the monitor's word for it. Only the
	# environment injection at the head of the script closes this one. A fresh
	# fixture, built rather than copied: the priming status has to find something
	# to refresh, or the valid bits are never stored and there is nothing left to
	# hide behind.
	# Driven twice. The defence is a config value injected through the
	# environment, and GIT_CONFIG_PARAMETERS -- which git exports into every
	# child of a `git -c ...` invocation, so a hook or `rebase --exec` inherits
	# it -- outranks that injection. Pointed back at the monitor it would switch
	# the defence off again, which is why the script drops it rather than
	# argues with it. A fresh fixture per run: the first one rewrites the index
	# with the monitor disabled and clears the valid bits, so a reused tree
	# would leave the second assertion nothing to hide behind.
	for fsmon_env in plain inherited-params; do
		rm -rf "$WORK/tree"; make_tree "$SLUG_JSON"; make_repo
		head=$(git_q -C "$WORK/tree" rev-parse --short=7 HEAD)
		mkdir -p "$WORK/tree/.git/hooks"
		printf '#!/bin/sh\nprintf "token\\0"\n' > "$WORK/tree/.git/hooks/fsmon-stub"
		chmod +x "$WORK/tree/.git/hooks/fsmon-stub"
		git_q -C "$WORK/tree" config core.fsmonitor .git/hooks/fsmon-stub
		git_q -C "$WORK/tree" config core.fsmonitorHookVersion 2
		git_q -C "$WORK/tree" status --porcelain >/dev/null 2>&1
		echo patched > "$WORK/tree/seed.txt"
		label="a change hidden by core.fsmonitor is dirty ($fsmon_env)"
		if git_q -C "$WORK/tree" diff --quiet HEAD --; then
			if [ "$fsmon_env" = plain ]; then
				got=$("$WORK/tree/scripts/release_tag.sh" 2>&1) || got="rc=$?"
			else
				got=$(GIT_CONFIG_PARAMETERS="'core.fsmonitor=.git/hooks/fsmon-stub' 'core.fsmonitorhookversion=2'" \
					"$WORK/tree/scripts/release_tag.sh" 2>&1) || got="rc=$?"
			fi
			want="build/${SLUG}-${head}-hal${HAL}-dvbsi${DVBSI}-dirty"
			[ "$got" = "$want" ] && ok "$label" "$got" || no "$label" "$want" "$got"
		else
			no "$label" "a fixture that hides the change" "git diff saw it anyway"
		fi
	done

	# A replacement object changes what git reports for a commit without
	# changing its id: rev-parse still hands back the original while diff
	# honours the replacement and calls a patched tree clean. The fixture is a
	# second commit carrying the patched tree, with refs/replace/<orig> pointed
	# at it -- the shape a local `git replace` leaves behind.
	rm -rf "$WORK/tree"; make_tree "$SLUG_JSON"; make_repo
	head=$(git_q -C "$WORK/tree" rev-parse --short=7 HEAD)
	orig=$(git_q -C "$WORK/tree" rev-parse HEAD)
	echo patched > "$WORK/tree/seed.txt"
	git_q -C "$WORK/tree" add seed.txt
	git_q -C "$WORK/tree" commit -qm patched
	repl=$(git_q -C "$WORK/tree" rev-parse HEAD)
	git_q -C "$WORK/tree" reset -q --hard "$orig"
	echo patched > "$WORK/tree/seed.txt"
	git_q -C "$WORK/tree" replace "$orig" "$repl" >/dev/null 2>&1
	label="a change hidden by a replacement object is dirty"
	if git_q -C "$WORK/tree" diff --quiet HEAD --; then
		got=$("$WORK/tree/scripts/release_tag.sh" 2>&1) || got="rc=$?"
		want="build/${SLUG}-${head}-hal${HAL}-dvbsi${DVBSI}-dirty"
		[ "$got" = "$want" ] && ok "$label" "$got" || no "$label" "$want" "$got"
	else
		no "$label" "a fixture that hides the change" "git diff saw it anyway"
	fi

	# A caller-supplied commit vouches for *which* commit was built, not for the
	# tree still matching it. CI passes github.sha and then runs a bootstrap
	# that could patch tracked packaging code; the archive would otherwise
	# carry a clean name for a build that is not that commit.
	rm -rf "$WORK/tree"; make_tree "$SLUG_JSON"; make_repo
	echo changed > "$WORK/tree/seed.txt"
	got=$("$WORK/tree/scripts/release_tag.sh" abcdef1 2>&1) || got="rc=$?"
	want="build/${SLUG}-abcdef1-hal${HAL}-dvbsi${DVBSI}-dirty"
	[ "$got" = "$want" ] && ok "a given commit does not excuse a dirty tree" "$got" \
		|| no "a given commit does not excuse a dirty tree" "$want" "$got"

	# An inherited git environment outranks `git -C`: with GIT_DIR pointing at
	# another repository -- a hook, `rebase --exec`, `bisect run` -- both
	# dependency commits would be read from there instead.
	rm -rf "$WORK/tree"; make_tree "$SLUG_JSON"; make_repo
	got=$(GIT_DIR="$WORK/tree/.git" GIT_WORK_TREE="$WORK/tree" \
		"$WORK/tree/scripts/release_tag.sh" abcdef1 2>&1) || got="rc=$?"
	want="build/${SLUG}-abcdef1-hal${HAL}-dvbsi${DVBSI}"
	[ "$got" = "$want" ] && ok "an inherited GIT_DIR is ignored" "$got" \
		|| no "an inherited GIT_DIR is ignored" "$want" "$got"

	# An index that cannot be read is not a clean tree either.
	if [ "$(id -u)" = 0 ]; then
		sk "an unreadable index is refused" "root reads it anyway"
	else
		rm -rf "$WORK/tree"; make_tree "$SLUG_JSON"; make_repo
		chmod 000 "$WORK/tree/.git/index"
		out=$("$WORK/tree/scripts/release_tag.sh" 2>&1); rc=$?
		chmod 644 "$WORK/tree/.git/index"
		case "$out" in
			*"index could not be read"*) msg=1 ;;
			*) msg=0 ;;
		esac
		[ "$rc" -ne 0 ] && [ "$msg" = 1 ] \
			&& ok "an unreadable index is refused" "rc=$rc" \
			|| no "an unreadable index is refused" "rc!=0 and a reason" "rc=$rc [$out]"
	fi

	# `git diff` answers with neither 0 nor 1. version_info.sh keeps three cases
	# for this branch because a real git once did exactly that (textconv naming
	# an absent program). Guessing here would stamp a clean commit on a tree
	# whose state nobody could determine. A PATH stub is used rather than a real
	# provocation: which git versions produce which code is exactly the
	# instability that made the original fixture useless.
	diff_real_git="$(command -v git 2>/dev/null || true)"
	rm -rf "$WORK/oddbin"; mkdir -p "$WORK/oddbin"
	{
		printf '#!/bin/sh\n'
		printf 'for a in "$@"; do [ "$a" = diff ] && exit 42; done\n'
		printf 'exec %s "$@"\n' "$diff_real_git"
	} > "$WORK/oddbin/git"
	chmod +x "$WORK/oddbin/git"
	rm -rf "$WORK/tree"; make_tree "$SLUG_JSON"; make_repo
	out=$(PATH="$WORK/oddbin:$PATH" "$WORK/tree/scripts/release_tag.sh" 2>&1); rc=$?
	case "$out" in
		*"refusing to guess"*) msg=1 ;;
		*) msg=0 ;;
	esac
	[ "$rc" -ne 0 ] && [ "$msg" = 1 ] \
		&& ok "an odd git diff status is refused" "rc=$rc" \
		|| no "an odd git diff status is refused" "rc!=0 and a reason" "rc=$rc [$out]"

	# No HEAD at all: refuse rather than invent one.
	rm -rf "$WORK/tree"
	make_tree "$SLUG_JSON"
	git_q -C "$WORK/tree" init -q 2>/dev/null
	out=$("$WORK/tree/scripts/release_tag.sh" 2>&1); rc=$?
	case "$out" in
		*"no usable HEAD"*) msg=1 ;;
		*) msg=0 ;;
	esac
	[ "$rc" -ne 0 ] && [ "$msg" = 1 ] \
		&& ok "a repository without HEAD is refused" "rc=$rc" \
		|| no "a repository without HEAD is refused" "rc!=0 and a reason" "rc=$rc [$out]"
}

# --- the libstb-hal half ---
# It is the only input nobody passes in, so it is the one that can move
# unnoticed: make/neutrino.mk clones LIBSTB_HAL_GIT_REF (`mpx`) at its tip.
make_tree "$SLUG_JSON"
hal_dirty_before=$(LIBSTB_HAL_DIR="$WORK/hal" "$WORK/tree/scripts/release_tag.sh" abcdef1 2>&1) || hal_dirty_before="rc=$?"
echo changed > "$WORK/hal/hal.txt"
got=$(LIBSTB_HAL_DIR="$WORK/hal" "$WORK/tree/scripts/release_tag.sh" abcdef1 2>&1) || got="rc=$?"
want="build/${SLUG}-abcdef1-hal${HAL}-dvbsi${DVBSI}-dirty"
[ "$got" = "$want" ] && ok "a modified libstb-hal is marked dirty" "$got" \
	|| no "a modified libstb-hal is marked dirty" "$want" "$got"
git_q -C "$WORK/hal" checkout -q -- hal.txt

# With no checkout the part reads sys, exactly as for libdvbsi++: make/neutrino.mk
# skips the build when the host already provides a matching libstb-hal, and that
# build is valid -- it simply cannot be named by a commit. Refusing would reject
# it; `sys` records what actually went in.
make_tree "$SLUG_JSON"
got=$(LIBSTB_HAL_DIR="$WORK/nonexistent-hal" "$WORK/tree/scripts/release_tag.sh" abcdef1 2>&1) || got="rc=$?"
want="build/${SLUG}-abcdef1-halsys-dvbsi${DVBSI}"
[ "$got" = "$want" ] && ok "a host libstb-hal is named sys, not refused" "$got" \
	|| no "a host libstb-hal is named sys, not refused" "$want" "$got"

# --- the libdvbsi++ part ---
# The second unpinned dependency, and the one Codex caught missing: with only
# three parts, two packages that differ solely in libdvbsi++ share a tag.
make_tree "$SLUG_JSON"
echo changed > "$WORK/dvbsi/dvbsi.txt"
got=$("$WORK/tree/scripts/release_tag.sh" abcdef1 2>&1) || got="rc=$?"
want="build/${SLUG}-abcdef1-hal${HAL}-dvbsi${DVBSI}-dirty"
[ "$got" = "$want" ] && ok "a modified libdvbsi++ is marked dirty" "$got" \
	|| no "a modified libdvbsi++ is marked dirty" "$want" "$got"
git_q -C "$WORK/dvbsi" checkout -q -- dvbsi.txt

# Unlike libstb-hal, having no checkout is legitimate: make/deps.mk skips the
# clone when the host already provides libdvbsi++. Refusing would break a valid
# build, so the part says what happened instead.
make_tree "$SLUG_JSON"
got=$(DVBSI_SRC_DIR="$WORK/nonexistent-dvbsi" "$WORK/tree/scripts/release_tag.sh" abcdef1 2>&1) || got="rc=$?"
want="build/${SLUG}-abcdef1-hal${HAL}-dvbsisys"
[ "$got" = "$want" ] && ok "a host libdvbsi++ is named sys, not refused" "$got" \
	|| no "a host libdvbsi++ is named sys, not refused" "$want" "$got"

# `git -C` walks upward. With a plain directory where a checkout belongs -- an
# emptied clone, a stray mkdir -- git answers about the repository enclosing it,
# and the tag would carry the build commit as the dependency's provenance.
rm -rf "$WORK/tree"; make_tree "$SLUG_JSON"; make_repo
build_head=$(git_q -C "$WORK/tree" rev-parse --short=7 HEAD)
mkdir -p "$WORK/tree/sources/libdvbsi++"
got=$( unset DVBSI_SRC_DIR; "$WORK/tree/scripts/release_tag.sh" abcdef1 2>&1 ) || got="rc=$?"
want="build/${SLUG}-abcdef1-hal${HAL}-dvbsisys"
[ "$got" = "$want" ] && ok "a plain directory is not a checkout" "$got" \
	|| no "a plain directory is not a checkout" "$want" "$got (build head was $build_head)"

# Past that test it really is a checkout, so an unreadable HEAD is a broken one.
# Calling that `sys` would report a host library where there is a half-finished
# clone.
rm -rf "$WORK/emptyrepo"; mkdir -p "$WORK/emptyrepo"
git_q -C "$WORK/emptyrepo" init -q 2>/dev/null
out=$(DVBSI_SRC_DIR="$WORK/emptyrepo" "$WORK/tree/scripts/release_tag.sh" abcdef1 2>&1); rc=$?
case "$out" in
	*"whose HEAD cannot be read"*) msg=1 ;;
	*) msg=0 ;;
esac
[ "$rc" -ne 0 ] && [ "$msg" = 1 ] \
	&& ok "a checkout without a readable HEAD is refused" "rc=$rc" \
	|| no "a checkout without a readable HEAD is refused" "rc!=0 and a reason" "rc=$rc [$out]"

# version_info.sh resolves its own source tree from the *caller's* directory
# (its line 68), so running this script by absolute path from somewhere else
# would take that place's Neutrino and this repository's commits, and produce a
# tag describing a build that never existed. The probe reports which kind of
# SRC_DIR it was handed.
rm -rf "$WORK/tree"; mkdir -p "$WORK/tree/scripts"
cp "$SCRIPT" "$WORK/tree/scripts/release_tag.sh"
chmod +x "$WORK/tree/scripts/release_tag.sh"
cat > "$WORK/tree/scripts/version_info.sh" <<'PROBE'
#!/bin/sh
case "${SRC_DIR:-unset}" in
	/*) printf '{ "slug": "anchored" }\n' ;;
	*) printf '{ "slug": "callerrelative" }\n' ;;
esac
PROBE
chmod +x "$WORK/tree/scripts/version_info.sh"
got=$( cd / && "$WORK/tree/scripts/release_tag.sh" abcdef1 2>&1 ) || got="rc=$?"
want="build/anchored-abcdef1-hal${HAL}-dvbsi${DVBSI}"
[ "$got" = "$want" ] && ok "the Neutrino source is anchored, not relative" "$got" \
	|| no "the Neutrino source is anchored, not relative" "$want" "$got"

# --- refusals ---
make_tree "$SLUG_JSON"
rm -f "$WORK/tree/scripts/version_info.sh"
out=$("$WORK/tree/scripts/release_tag.sh" abcdef1 2>&1); rc=$?
case "$out" in
	*"missing or not executable"*) msg=1 ;;
	*) msg=0 ;;
esac
[ "$rc" -ne 0 ] && [ "$msg" = 1 ] \
	&& ok "a missing version_info.sh is refused" "rc=$rc" \
	|| no "a missing version_info.sh is refused" "rc!=0 and a reason" "rc=$rc [$out]"

# The guard against a future sanitiser change. A slug with a space cannot be a
# ref, and the script has to say so instead of handing it to `git tag`.
make_tree '{ "base": "1.0", "slug": "has a space" }'
out=$("$WORK/tree/scripts/release_tag.sh" abcdef1 2>&1); rc=$?
case "$out" in
	*"invalid tag name"*) msg=1 ;;
	*) msg=0 ;;
esac
[ "$rc" -ne 0 ] && [ "$msg" = 1 ] \
	&& ok "an unusable tag name is refused" "rc=$rc" \
	|| no "an unusable tag name is refused" "rc!=0 and a reason" "rc=$rc [$out]"

# --- the real file against the real repository ---
# Everything above runs against a stub. This is the one case that proves the
# script still agrees with the version_info.sh actually shipped here.
unset LIBSTB_HAL_DIR
unset DVBSI_SRC_DIR
if ! "$ROOT_DIR/scripts/version_info.sh" >/dev/null 2>&1; then
	sk "the real tree produces a usable tag" "version_info.sh cannot run (no Neutrino source?)"
elif ! git -C "$ROOT_DIR/sources/libstb-hal" rev-parse HEAD >/dev/null 2>&1; then
	sk "the real tree produces a usable tag" "no libstb-hal checkout (not built here?)"
else
	# Named exactly, not by shape. A shape test passes just as happily when
	# both parts read the same checkout, which is precisely the mistake worth
	# catching: point the hal default at sources/libdvbsi++ and
	# `build/...-hal<x>-dvbsi<x>` still looks like a tag.
	real_hal=$(git -C "$ROOT_DIR/sources/libstb-hal" rev-parse --short=7 HEAD 2>/dev/null)
	real_dvbsi=$(git -C "$ROOT_DIR/sources/libdvbsi++" rev-parse --short=7 HEAD 2>/dev/null || echo sys)
	got=$("$SCRIPT" abcdef1 2>&1); rc=$?
	case "$got" in
		build/*-abcdef1-hal${real_hal}-dvbsi${real_dvbsi}*) shape=1 ;;
		*) shape=0 ;;
	esac
	[ "$rc" -eq 0 ] && [ "$shape" = 1 ] \
		&& ok "the real tree names the real checkouts" "$got" \
		|| no "the real tree names the real checkouts" \
		      "build/<slug>-abcdef1-hal${real_hal}-dvbsi${real_dvbsi}" "rc=$rc [$got]"
fi

echo "----"
echo "[test-shell] pass=$pass fail=$fail skip=$skip"
[ "$fail" -eq 0 ]
