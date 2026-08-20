#!/bin/sh
#
# publish_release.sh - put a built AppImage where somebody can download it.
#
# Three commands, driven by the publish job in .github/workflows/ci.yml:
#
#   checksum   write SHA256SUMS next to the AppImage
#   latest     replace the rolling `latest` release with this build
#   archive    create a permanent release under the tag in ARCHIVE_TAG
#
# This lives in a file rather than inside the workflow for the same reason
# release_tag.sh does: a test can reach a file. And it needs one. What matters
# here is not which gh commands are called but in which order, and what survives
# when one of them fails halfway. Both are claims a comment can make and only a
# test can keep.
#
# Two facts shape the order:
#
#   An asset cannot be replaced in place. `gh release upload --clobber` deletes
#   the same-named asset and uploads afterwards, so every replacement has a
#   window. The AppImage carries Neutrino's version and usually arrives under a
#   new name, but SHA256SUMS never does -- so the package goes up first and the
#   checksum last, leaving the shortest possible window at the very end of the
#   run, where the next run repairs it.
#
#   What that leaves open, deliberately: a rebuild of the *same* Neutrino commit
#   whose bytes did change -- a new build system commit, a moved dependency, a
#   rebuilt runner image -- keeps the AppImage's name, so replacing it means
#   deleting it first, and a failure inside that upload leaves `latest` without
#   its package until the next run. Closing it would mean uploading beside the
#   old asset and renaming through the REST API; that was weighed and declined
#   as more machinery than the window is worth. tests/shell/test_publish_release.sh
#   pins the behaviour instead, so the cost stays visible and cannot widen
#   unnoticed.
#
#   A tag is a claim about which build is published. It is therefore moved
#   *after* the assets are in place, never before: a failed upload must leave
#   `latest` pointing at the last build that actually made it.
#
# Environment:
#   ASSET_DIR           where the package is (default artifacts/appimage)
#   GITHUB_SHA          the commit being published
#   GITHUB_REPOSITORY   owner/name, for the git-ref API
#   ARCHIVE_TAG         archive only: the name from scripts/release_tag.sh
#   RUNNER_TEMP         scratch space; a mktemp -d stands in outside Actions
#   GH_TOKEN            read by gh itself
#
# Beyond coreutils and grep the only dependency is gh.

set -eu

ASSET_DIR="${ASSET_DIR:-artifacts/appimage}"

LATEST_NOTES="**Neutrino for a PC, in a single file.** Not an image for a receiver -- those come from [tuxbox-os-builder](https://github.com/tuxbox-neutrino/tuxbox-os-builder).

\`\`\`
chmod +x Neutrino_*.AppImage
sha256sum -c SHA256SUMS          # optional, checks the download
./Neutrino_*.AppImage
\`\`\`

Neutrino opens in a window, with its web interface at <http://localhost:31344>. With no DVB tuner it starts in simulation mode by itself, and everything but live TV works; with one it uses it. Set \`SIMULATE_FE\` yourself to overrule that.

**What it needs.** x86_64, and glibc 2.38 or newer -- Debian 13 (2.41) and Ubuntu 24.04 (2.39) work, Debian 12 (2.36) and Ubuntu 22.04 (2.35) do not. Also \`libgl1\`, \`libglx0\` and \`libglvnd0\`, and a private mount namespace: unprivileged user namespaces are enough, \`bwrap\` works too, and as root neither is needed.

Settings live in \`~/.local/share/neutrino-appimage\` (\`NEUTRINO_APPIMAGE_STATE\` moves them). Nothing is written outside your home directory.

**This release is rolling.** Every publishing run replaces it, so nothing here is guaranteed to stay. The filename names the Neutrino commit inside. Take an archived \`build/…\` release when you need a state that stays put."

ARCHIVE_NOTES="**Neutrino for a PC, in a single file** -- this one kept on purpose, and it stays as it is. Not an image for a receiver; those come from [tuxbox-os-builder](https://github.com/tuxbox-neutrino/tuxbox-os-builder).

\`\`\`
chmod +x Neutrino_*.AppImage
sha256sum -c SHA256SUMS          # optional, checks the download
./Neutrino_*.AppImage
\`\`\`

Neutrino opens in a window, with its web interface at <http://localhost:31344>. With no DVB tuner it starts in simulation mode by itself, and everything but live TV works; with one it uses it. Set \`SIMULATE_FE\` yourself to overrule that.

**What it needs.** x86_64, and glibc 2.38 or newer -- Debian 13 (2.41) and Ubuntu 24.04 (2.39) work, Debian 12 (2.36) and Ubuntu 22.04 (2.35) do not. Also \`libgl1\`, \`libglx0\` and \`libglvnd0\`, and a private mount namespace: unprivileged user namespaces are enough, \`bwrap\` works too, and as root neither is needed.

Settings live in \`~/.local/share/neutrino-appimage\` (\`NEUTRINO_APPIMAGE_STATE\` moves them). Nothing is written outside your home directory.

The tag names what this was built from: the Neutrino version inside, this repository's commit, and the two dependencies that are not pinned to a version -- libstb-hal and libdvbsi++. docs/PACKAGING explains why all four are needed to tell two builds apart."

die() {
	echo "publish_release: $*" >&2
	exit 1
}

if [ -n "${RUNNER_TEMP:-}" ]; then
	SCRATCH="$RUNNER_TEMP/publish_release"
	mkdir -p "$SCRATCH"
else
	SCRATCH="$(mktemp -d)"
	trap 'rm -rf "$SCRATCH"' EXIT
fi
GH_ERR="$SCRATCH/gh-stderr"

# gh_says_absent -- did the last gh call fail because the thing is not there?
# Anything else is a question that could not be asked, which is a different
# answer entirely and must not be rounded down to "there is nothing there".
gh_says_absent() {
	grep -qiE 'release not found|no assets match|HTTP 404|not found' "$GH_ERR"
}

# release_assets <tag> -- the asset names a release holds, one per line.
#   0  the release exists; the list follows, possibly empty
#   2  there is no such release
#   3  the question could not be asked; the reason is already on stderr
#
# The difference between 2 and 3 is the whole point of this function. Folding a
# failed query into "no assets" is how a permanent archive gets overwritten: the
# comparison that protects it is skipped, while the upload that follows is not.
release_assets() {
	if out=$(gh release view "$1" --json assets --jq '.assets[].name' 2>"$GH_ERR"); then
		printf '%s\n' "$out"
		return 0
	fi
	gh_says_absent && return 2
	echo "publish_release: cannot read the release $1:" >&2
	cat "$GH_ERR" >&2
	return 3
}

# read_assets <tag> -- release_assets with the three answers turned into either
# a value or an exit, so callers stay readable.
read_assets() {
	rc=0
	have=$(release_assets "$1") || rc=$?
	case "$rc" in
		0) release_exists=1 ;;
		2) release_exists=0; have="" ;;
		*) exit 1 ;;
	esac
}

# move_tag <tag> -- point a tag at GITHUB_SHA, creating it when absent. Called
# only once the assets are in place.
move_tag() {
	if gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/$1" >/dev/null 2>"$GH_ERR"; then
		gh api -X PATCH "repos/${GITHUB_REPOSITORY}/git/refs/tags/$1" \
			-f sha="$GITHUB_SHA" -F force=true >/dev/null
		return 0
	fi
	if gh_says_absent; then
		gh api -X POST "repos/${GITHUB_REPOSITORY}/git/refs" \
			-f ref="refs/tags/$1" -f sha="$GITHUB_SHA" >/dev/null
		return 0
	fi
	echo "publish_release: cannot read the tag $1:" >&2
	cat "$GH_ERR" >&2
	exit 1
}

# local_assets -- what this build is publishing, by name. Fails when the package
# or its checksum is absent, rather than publishing a release with a hole in it.
#
# Not written as `ls ... | sed ...`: a pipeline reports the status of its last
# command, so the sed would report success over a missing SHA256SUMS and the
# archive could then be called complete without one.
local_assets() {
	( cd "$ASSET_DIR" && ls -1 ./*.AppImage SHA256SUMS ) > "$SCRATCH/names" || return 1
	sed 's|^\./||' "$SCRATCH/names"
}

# release_is_draft <tag> -- a draft is invisible on the download page and
# carries no tag. Asked rather than remembered: a run that failed after creating
# the draft leaves one behind, and only the next run can finish it.
release_is_draft() {
	if out=$(gh release view "$1" --json isDraft --jq '.isDraft' 2>"$GH_ERR"); then
		[ "$out" = "true" ]
		return
	fi
	# Same reading as everywhere else: a release that is not there is not a
	# draft, but a question that could not be asked is not an answer. Rounded
	# down to "not a draft", a transient failure here would leave the release
	# unpublished and the run green -- an archive nobody can see, reported as
	# archived.
	gh_says_absent && return 1
	echo "publish_release: cannot read the draft state of $1:" >&2
	cat "$GH_ERR" >&2
	exit 1
}

# missing_names <have> <want> -- the names in want that have does not carry.
missing_names() {
	printf '%s\n' "$1" > "$SCRATCH/have"
	printf '%s\n' "$2" | grep -vxF -f "$SCRATCH/have" || true
}

# published_checksum_matches <tag> -- does the SHA256SUMS in that release equal
# the one just built? Exit 1 when it is absent or different.
#
# Dies when it cannot be fetched at all. Rounding that down to "different" is
# not a small inaccuracy here: the caller takes a differing checksum as licence
# to replace the assets, so a transient download failure on an unchanged
# re-dispatch would walk straight into the one replacement this script exists
# to avoid.
published_checksum_matches() {
	mkdir -p "$SCRATCH/archived"
	rm -f "$SCRATCH/archived/SHA256SUMS"
	if gh release download "$1" --pattern SHA256SUMS \
		--dir "$SCRATCH/archived" --clobber >/dev/null 2>"$GH_ERR"; then
		cmp -s "$SCRATCH/archived/SHA256SUMS" "$ASSET_DIR/SHA256SUMS"
		return
	fi
	gh_says_absent && return 1
	echo "publish_release: cannot read the published checksum of $1:" >&2
	cat "$GH_ERR" >&2
	exit 1
}

# upload_build <tag> -- package first, checksum last. See the head of the file.
upload_build() {
	gh release upload "$1" "$ASSET_DIR"/*.AppImage --clobber
	gh release upload "$1" "$ASSET_DIR/SHA256SUMS" --clobber
}

cmd_checksum() {
	[ -d "$ASSET_DIR" ] || die "no such directory: $ASSET_DIR"
	if ! (cd "$ASSET_DIR" && ls -1 ./*.AppImage >/dev/null 2>&1); then
		die "the build artefact holds no AppImage"
	fi
	# Names go in relative, without the ./ that the glob needs: `sha256sum -c`
	# then works from the directory the file sits in. Two steps rather than one
	# pipeline, so a failing sha256sum is not hidden behind a successful sed --
	# it would otherwise leave a truncated SHA256SUMS and exit 0.
	( cd "$ASSET_DIR" && sha256sum ./*.AppImage ) > "$SCRATCH/sums" \
		|| die "sha256sum failed over $ASSET_DIR"
	sed 's| \./| |' "$SCRATCH/sums" > "$ASSET_DIR/SHA256SUMS"
	cat "$ASSET_DIR/SHA256SUMS"
}

cmd_latest() {
	[ -n "${GITHUB_SHA:-}" ] || die "GITHUB_SHA is not set"
	[ -n "${GITHUB_REPOSITORY:-}" ] || die "GITHUB_REPOSITORY is not set"

	published="$(local_assets)"
	read_assets latest
	before="$have"

	if [ "$release_exists" = 0 ]; then
		# Created as a draft. A draft is not on the download page and carries
		# no tag, so a failure during the very first upload cannot leave an
		# empty release in public view. It is published below, once the assets
		# are actually in it.
		gh release create latest --draft \
			--target "$GITHUB_SHA" --prerelease --title "Latest build" \
			--notes "$LATEST_NOTES"
		before=""
	fi

	# Re-dispatching an unchanged commit is the common case, and the one where
	# uploading is pure risk: the AppImage carries Neutrino's version, so the
	# rebuild has the same asset name, and replacing an asset by name means
	# deleting it first. When the release already holds exactly this build,
	# not touching it is the only handling that cannot go wrong.
	if [ -z "$(missing_names "$before" "$published")" ] \
		&& published_checksum_matches latest; then
		echo "latest already holds this exact build; nothing to upload."
	else
		upload_build latest
	fi

	# --target as well as --draft=false: publishing a draft is what creates its
	# tag, and a draft left behind by an earlier failed run still carries that
	# run's target. Without this, a repair after master moved on would publish
	# the new package under the old commit's tag.
	if release_is_draft latest; then
		gh release edit latest --target "$GITHUB_SHA" --draft=false >/dev/null
	fi

	move_tag latest

	# --clobber only overwrites an asset of the *same* name, and the AppImage
	# carries Neutrino's version in its filename. Left alone the release would
	# accumulate one AppImage per Neutrino commit, while SHA256SUMS -- whose
	# name never changes -- described only the newest.
	#
	# Pruned last of all, after the tag is in place. Deleting the superseded
	# package first and then failing to move the tag would leave `latest`
	# naming a build whose package is already gone. This way the worst a
	# failure leaves behind is one superseded AppImage too many, which the next
	# run clears.
	printf '%s\n' "$before" | while IFS= read -r stale; do
		[ -n "$stale" ] || continue
		if printf '%s\n' "$published" | grep -qxF "$stale"; then
			continue
		fi
		echo "removing superseded asset: $stale"
		gh release delete-asset latest "$stale" --yes
	done
}

cmd_archive() {
	[ -n "${GITHUB_SHA:-}" ] || die "GITHUB_SHA is not set"
	tag="${ARCHIVE_TAG:-}"
	[ -n "$tag" ] || die "ARCHIVE_TAG is empty: the build named no archive tag"
	# The name is formed in the job that runs project code -- a bootstrap that
	# clones and executes two moving branch tips -- while the write token lives
	# in this one. A prefix test alone would still let that job name any tag
	# under build/, which is a confused deputy with a smaller blast radius, not
	# none. So check the two things this job knows on its own: the character
	# set, and that the build-system part really is this run's commit. What
	# stays forgeable after that -- the slug and the two dependency commits --
	# is data the build job legitimately determines anyway.
	case "$tag" in
		build/*) ;;
		*) die "refusing an archive tag outside build/: $tag" ;;
	esac
	case "$tag" in
		*[!A-Za-z0-9._/-]*) die "refusing an archive tag with unusual characters: $tag" ;;
	esac
	run_commit="$(printf '%.7s' "$GITHUB_SHA")"
	case "$tag" in
		*"-${run_commit}-hal"*) ;;
		*) die "archive tag does not name this run's commit (${run_commit}): $tag" ;;
	esac

	expected="$(local_assets)"
	read_assets "$tag"

	# An archive already holding a *different* build must be neither quietly
	# kept nor quietly overwritten. The tag names three source commits but
	# cannot name the machine, and GitHub rebuilds its runner image weekly, so
	# the same commits can produce different bytes months apart. Compare what is
	# published with what was just built and stop if they disagree.
	if [ "$release_exists" = 1 ] && printf '%s\n' "$have" | grep -qxF SHA256SUMS; then
		mkdir -p "$SCRATCH/archived"
		gh release download "$tag" --pattern SHA256SUMS \
			--dir "$SCRATCH/archived" --clobber
		if ! cmp -s "$SCRATCH/archived/SHA256SUMS" "$ASSET_DIR/SHA256SUMS"; then
			echo "published under $tag:" >&2
			cat "$SCRATCH/archived/SHA256SUMS" >&2
			echo "built now:" >&2
			cat "$ASSET_DIR/SHA256SUMS" >&2
			if printf '%s\n' "$have" | grep -q '\.AppImage$'; then
				die "$tag already archives a different build; refusing to merge two builds under one tag"
			fi
			# A checksum whose package was never uploaded describes something
			# nobody can download, and this build is not it. Repairing it here
			# would silently replace that record, so a person decides instead.
			die "$tag holds a checksum for a package that was never uploaded, and this build does not match it; delete the release and archive again"
		fi
	fi

	# Completeness is a question of names, not of count. An archive whose
	# AppImage uploaded and whose SHA256SUMS did not would otherwise be declared
	# finished by every later run and could never be repaired -- and the
	# reverse, a checksum with no package, is worse.
	missing="$(missing_names "$have" "$expected")"
	if [ -z "$missing" ]; then
		# Complete, but possibly still a draft: a run that died between the
		# upload and the publish leaves one, and nothing else will finish it.
		if release_is_draft "$tag"; then
			echo "$tag holds this build but was left as a draft; publishing it."
			gh release edit "$tag" --target "$GITHUB_SHA" --draft=false >/dev/null
		else
			echo "$tag already holds this exact build; leaving it untouched."
		fi
		return 0
	fi
	echo "missing from $tag:"
	printf '%s\n' "$missing"

	if [ "$release_exists" = 0 ]; then
		# A draft for the same reason as latest: an archive is meant to be a
		# build somebody can rely on, and a failed upload must not leave a
		# permanent-looking release with nothing in it.
		gh release create "$tag" --draft \
			--target "$GITHUB_SHA" --title "$tag" --notes "$ARCHIVE_NOTES"
	fi
	upload_build "$tag"
	if release_is_draft "$tag"; then
		gh release edit "$tag" --target "$GITHUB_SHA" --draft=false >/dev/null
	fi
}

case "${1:-}" in
	checksum) cmd_checksum ;;
	latest) cmd_latest ;;
	archive) cmd_archive ;;
	*) die "usage: publish_release.sh checksum|latest|archive" ;;
esac
