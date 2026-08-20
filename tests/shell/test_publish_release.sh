#!/bin/sh
#
# Unit test for scripts/publish_release.sh, which turns a built AppImage into
# something with a download link.
#
# What is worth testing here is not which gh commands run but in what order, and
# what survives when one of them fails. Two properties carry the whole design:
#
#   the rolling release is never empty while its links are public -- new assets
#   go up first, superseded ones come down afterwards;
#
#   an archive is complete or repairable -- a half-finished upload must not be
#   mistaken for a finished one on the next run.
#
# Both are invisible in a green run and only show themselves on the second one,
# or on a failure halfway through. So gh is replaced by a stub that keeps state
# in a directory, logs every call in order, and can be told to fail on a chosen
# command.
#
# POSIX sh, no external deps beyond coreutils and grep. Exits 0 on success.

set -u

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/publish_release.sh"
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

# --- the gh stub -------------------------------------------------------------
# A release is a directory of assets; a tag is a file holding a sha. Enough to
# answer the only questions the script asks: does this exist, what does it hold,
# put this in, take that out.
BIN="$WORK/bin"
mkdir -p "$BIN"
cat > "$BIN/gh" <<'STUB'
#!/bin/sh
srv="$GH_STUB_SRV"
printf '%s\n' "$*" >> "$srv/log"
if [ -n "${GH_STUB_FAIL:-}" ]; then
	case "$*" in
		$GH_STUB_FAIL)
			echo "gh stub: forced failure on: $*" >&2
			exit 1
			;;
	esac
fi
slug() { printf '%s' "$1" | tr / _; }
sub="$1"; shift
case "$sub" in
api)
	method=GET; path=""; sha=""; newref=""
	while [ $# -gt 0 ]; do
		case "$1" in
			-X) method="$2"; shift 2 ;;
			-f|-F)
				case "$2" in
					sha=*) sha="${2#sha=}" ;;
					ref=*) newref="${2#ref=}" ;;
				esac
				shift 2 ;;
			*) if [ -z "$path" ]; then path="$1"; fi; shift ;;
		esac
	done
	case "$path" in
		*/git/ref/tags/*)
			t="${path##*/git/ref/tags/}"
			[ -f "$srv/refs/$t" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
			cat "$srv/refs/$t"
			exit 0 ;;
		*/git/refs/tags/*)
			t="${path##*/git/refs/tags/}"
			[ "$method" = PATCH ] || exit 1
			[ -f "$srv/refs/$t" ] || exit 1
			printf '%s\n' "$sha" > "$srv/refs/$t"
			exit 0 ;;
		*/git/refs)
			[ "$method" = POST ] || exit 1
			case "$newref" in
				refs/tags/*) ;;
				*) exit 1 ;;
			esac
			mkdir -p "$srv/refs"
			printf '%s\n' "$sha" > "$srv/refs/${newref#refs/tags/}"
			exit 0 ;;
	esac
	exit 1 ;;
release)
	rsub="$1"; shift
	tag="$1"; shift
	d="$srv/rel/$(slug "$tag")"
	case "$rsub" in
		view)
			[ -d "$d" ] || { echo "release not found" >&2; exit 1; }
			if [ "${1:-}" = "--json" ]; then
				case "${2:-}" in
					*isDraft*) [ -f "$d/draft" ] && echo true || echo false ;;
					*) ls -1 "$d/assets" 2>/dev/null || true ;;
				esac
			fi
			exit 0 ;;
		create)
			target=""; draft=0
			while [ $# -gt 0 ]; do
				case "$1" in
					--target) target="$2"; shift 2 ;;
					--notes) printf '%s' "$2" > "$d.body"; shift 2 ;;
					--title) printf '%s' "$2" > "$d.title"; shift 2 ;;
					--draft) draft=1; shift ;;
					*) shift ;;
				esac
			done
			mkdir -p "$d/assets" "$srv/refs"
			printf '%s\n' "$target" > "$d/target"
			# A draft carries no tag until it is published -- that is the whole
			# reason the first run creates one.
			if [ "$draft" = 1 ]; then
				: > "$d/draft"
			elif [ -n "$target" ]; then
				printf '%s\n' "$target" > "$srv/refs/$(slug "$tag")"
			fi
			exit 0 ;;
		edit)
			[ -d "$d" ] || exit 1
			publish=0
			while [ $# -gt 0 ]; do
				case "$1" in
					--target) printf '%s\n' "$2" > "$d/target"; shift 2 ;;
					--notes) printf '%s' "$2" > "$d.body"; shift 2 ;;
					--draft=false) publish=1; shift ;;
					*) shift ;;
				esac
			done
			if [ "$publish" = 1 ]; then
				rm -f "$d/draft"
				if [ -f "$d/target" ]; then
					cp "$d/target" "$srv/refs/$(slug "$tag")"
				fi
			fi
			exit 0 ;;
		upload)
			[ -d "$d" ] || exit 1
			for f in "$@"; do
				case "$f" in --*) continue ;; esac
				n="$(basename "$f")"
				rm -f "$d/assets/$n"
				if [ "${GH_STUB_FAIL_MIDWAY:-}" = "$n" ]; then
					echo "gh stub: forced failure after deleting $n" >&2
					exit 1
				fi
				cp "$f" "$d/assets/$n" || exit 1
			done
			exit 0 ;;
		download)
			pattern=""; dir="."
			while [ $# -gt 0 ]; do
				case "$1" in
					--pattern) pattern="$2"; shift 2 ;;
					--dir) dir="$2"; shift 2 ;;
					*) shift ;;
				esac
			done
			[ -f "$d/assets/$pattern" ] || exit 1
			mkdir -p "$dir"
			cp "$d/assets/$pattern" "$dir/$pattern"
			exit 0 ;;
		delete-asset)
			rm -f "$d/assets/$1"
			exit 0 ;;
	esac
	exit 1 ;;
esac
exit 1
STUB
chmod +x "$BIN/gh"

SRV="$WORK/srv"
GH_STUB_SRV="$SRV"
export GH_STUB_SRV
PATH="$BIN:$PATH"
export PATH

GITHUB_REPOSITORY="tuxbox-neutrino/neutrino-generic-build"
export GITHUB_REPOSITORY
ASSET_DIR="$WORK/assets"
export ASSET_DIR
RUNNER_TEMP="$WORK/runner-temp"
export RUNNER_TEMP

srv_reset() {
	rm -rf "$SRV" "$RUNNER_TEMP"
	mkdir -p "$SRV/rel" "$SRV/refs" "$RUNNER_TEMP"
	: > "$SRV/log"
	unset GH_STUB_FAIL || true
	unset GH_STUB_FAIL_MIDWAY || true
}

# make_assets <appimage-name> [content-marker] -- a package to publish, with the
# checksum the script itself writes, so the fixture cannot disagree with it.
make_assets() {
	rm -rf "$ASSET_DIR"
	mkdir -p "$ASSET_DIR"
	printf 'fake appimage %s %s\n' "$1" "${2:-first}" > "$ASSET_DIR/$1"
	"$SCRIPT" checksum >/dev/null
}

assets() { ls -1 "$SRV/rel/$(printf '%s' "$1" | tr / _)/assets" 2>/dev/null | LC_ALL=C sort | tr '\n' ' '; }

if ! command -v sha256sum >/dev/null 2>&1; then
	sk "the whole suite" "sha256sum not available"
	echo "----"
	echo "[test-shell] pass=$pass fail=$fail skip=$skip"
	exit 0
fi

APP_A="Neutrino_2026.8.42.gaaaaaaa_x86_64.AppImage"
APP_B="Neutrino_2026.9.01.gbbbbbbb_x86_64.AppImage"
GITHUB_SHA="1111111111111111111111111111111111111111"
export GITHUB_SHA

# --- checksum ----------------------------------------------------------------
srv_reset
make_assets "$APP_A"
got="$(cat "$ASSET_DIR/SHA256SUMS")"
case "$got" in
	*"  $APP_A") named=1 ;;
	*) named=0 ;;
esac
# ./ in the name would make `sha256sum -c` depend on the directory it is run
# from, which is exactly what a downloader cannot know.
case "$got" in
	*./*) dotted=1 ;;
	*) dotted=0 ;;
esac
[ "$named" = 1 ] && [ "$dotted" = 0 ] \
	&& ok "checksum names the file plainly" "$got" \
	|| no "checksum names the file plainly" "<sha>  $APP_A" "$got"

(cd "$ASSET_DIR" && sha256sum -c SHA256SUMS >/dev/null 2>&1) \
	&& ok "the checksum verifies where it is published" "sha256sum -c" \
	|| no "the checksum verifies where it is published" "rc=0" "rc=$?"

rm -rf "$ASSET_DIR"; mkdir -p "$ASSET_DIR"
out=$("$SCRIPT" checksum 2>&1); rc=$?
case "$out" in *"no AppImage"*) msg=1 ;; *) msg=0 ;; esac
[ "$rc" -ne 0 ] && [ "$msg" = 1 ] \
	&& ok "an artefact without an AppImage is refused" "rc=$rc" \
	|| no "an artefact without an AppImage is refused" "rc!=0 and a reason" "rc=$rc [$out]"

# The mirror case, and the one a pipeline hides: `ls ... | sed ...` reports sed's
# status, so a missing SHA256SUMS would pass for a complete build and an archive
# could be called finished without one.
srv_reset
rm -rf "$ASSET_DIR"; mkdir -p "$ASSET_DIR"
printf 'no checksum next to me\n' > "$ASSET_DIR/$APP_A"
out=$("$SCRIPT" latest 2>&1); rc=$?
grep -q '^release upload' "$SRV/log" 2>/dev/null && uploaded=1 || uploaded=0
[ "$rc" -ne 0 ] && [ "$uploaded" = 0 ] \
	&& ok "a package without its checksum is refused" "rc=$rc" \
	|| no "a package without its checksum is refused" "rc!=0 and no upload" "rc=$rc upload=$uploaded [$out]"

# And the producer side of the same trap: `sha256sum ... | sed ... > SHA256SUMS`
# reports sed's status, so a failing sha256sum would leave a truncated checksum
# file and exit 0. A PATH stub rather than a real provocation -- which inputs
# make a given coreutils fail is exactly the instability that makes a fixture
# useless.
srv_reset
make_assets "$APP_A"
rm -f "$ASSET_DIR/SHA256SUMS"
rm -rf "$WORK/badbin"; mkdir -p "$WORK/badbin"
printf '#!/bin/sh\nexit 3\n' > "$WORK/badbin/sha256sum"
chmod +x "$WORK/badbin/sha256sum"
out=$(PATH="$WORK/badbin:$PATH" "$SCRIPT" checksum 2>&1); rc=$?
[ "$rc" -ne 0 ] && [ ! -f "$ASSET_DIR/SHA256SUMS" ] \
	&& ok "a failing checksum producer is not hidden" "rc=$rc" \
	|| no "a failing checksum producer is not hidden" "rc!=0 and no SHA256SUMS" "rc=$rc [$out]"

# --- latest, first run -------------------------------------------------------
srv_reset
make_assets "$APP_A"
out=$("$SCRIPT" latest 2>&1); rc=$?
want="$APP_A SHA256SUMS "
[ "$rc" -eq 0 ] && [ "$(assets latest)" = "$want" ] \
	&& ok "the first run creates latest with both files" "$(assets latest)" \
	|| no "the first run creates latest with both files" "$want" "rc=$rc [$(assets latest)] $out"

[ "$(cat "$SRV/refs/latest" 2>/dev/null)" = "$GITHUB_SHA" ] \
	&& ok "the first run points the tag at the build" "$GITHUB_SHA" \
	|| no "the first run points the tag at the build" "$GITHUB_SHA" "$(cat "$SRV/refs/latest" 2>/dev/null)"

# --- latest, second run with a different Neutrino ----------------------------
# The AppImage carries Neutrino's version, so the new one does not overwrite the
# old one by name. Without the prune the release would hold two packages and one
# SHA256SUMS describing only the newer.
GITHUB_SHA="2222222222222222222222222222222222222222"
make_assets "$APP_B"
# The log is cleared first: the ordering assertion below has to measure inside
# this one run. Across both runs the first upload is the one that created the
# release, when there was nothing to delete yet, and the assertion would hold no
# matter what this run does.
: > "$SRV/log"
out=$("$SCRIPT" latest 2>&1); rc=$?
want="$APP_B SHA256SUMS "
[ "$rc" -eq 0 ] && [ "$(assets latest)" = "$want" ] \
	&& ok "a second build replaces, not accumulates" "$(assets latest)" \
	|| no "a second build replaces, not accumulates" "$want" "rc=$rc [$(assets latest)] $out"

[ "$(cat "$SRV/refs/latest" 2>/dev/null)" = "$GITHUB_SHA" ] \
	&& ok "an existing tag is moved to the new build" "$GITHUB_SHA" \
	|| no "an existing tag is moved to the new build" "$GITHUB_SHA" "$(cat "$SRV/refs/latest" 2>/dev/null)"

# The order is the whole point: upload first, delete afterwards. Reversed, the
# release stands empty for as long as the upload takes -- and for good if the
# upload then fails.
up=$(grep -n '^release upload latest' "$SRV/log" | head -n1 | cut -d: -f1)
del=$(grep -n '^release delete-asset latest' "$SRV/log" | head -n1 | cut -d: -f1)
if [ -n "$up" ] && [ -n "$del" ] && [ "$up" -lt "$del" ]; then
	ok "the new asset goes up before the old comes down" "upload@$up < delete@$del"
else
	no "the new asset goes up before the old comes down" "upload before delete" "upload@${up:-none} delete@${del:-none}"
fi

# --- latest, when the upload fails halfway -----------------------------------
# An asset cannot be replaced in place: --clobber deletes the same-named one and
# uploads afterwards, so SHA256SUMS -- the one name that never changes -- has a
# window on every run. The package is uploaded first so that window sits at the
# very end, and the tag is moved only once everything is in place. What must
# survive a failure inside that window: the previous package, and a tag that
# still names the last build that actually made it.
prev_tag="$(cat "$SRV/refs/latest" 2>/dev/null)"
GITHUB_SHA="3333333333333333333333333333333333333333"
make_assets "$APP_A" second
GH_STUB_FAIL_MIDWAY=SHA256SUMS
export GH_STUB_FAIL_MIDWAY
out=$("$SCRIPT" latest 2>&1); rc=$?
unset GH_STUB_FAIL_MIDWAY
want="$APP_A $APP_B "
[ "$rc" -ne 0 ] && [ "$(assets latest)" = "$want" ] \
	&& ok "a failure mid-upload keeps the old package" "$(assets latest)" \
	|| no "a failure mid-upload keeps the old package" "rc!=0 and $want" "rc=$rc [$(assets latest)]"

[ "$(cat "$SRV/refs/latest" 2>/dev/null)" = "$prev_tag" ] \
	&& ok "a failed publish does not move the tag" "still $prev_tag" \
	|| no "a failed publish does not move the tag" "$prev_tag" "$(cat "$SRV/refs/latest" 2>/dev/null)"

# ... and the next run repairs all of it, which is what makes the window
# tolerable rather than merely small.
out=$("$SCRIPT" latest 2>&1); rc=$?
want="$APP_A SHA256SUMS "
[ "$rc" -eq 0 ] && [ "$(assets latest)" = "$want" ] \
	&& [ "$(cat "$SRV/refs/latest" 2>/dev/null)" = "$GITHUB_SHA" ] \
	&& ok "the next run repairs what the failure left" "$(assets latest)" \
	|| no "the next run repairs what the failure left" "$want and tag $GITHUB_SHA" "rc=$rc [$(assets latest)] tag=$(cat "$SRV/refs/latest" 2>/dev/null)"

# --- latest, when the release cannot be read ---------------------------------
# "I could not ask" is not "there is nothing there". Rounded down, the second
# reading makes the script upload into a release it never inspected.
before_assets="$(assets latest)"
before_tag="$(cat "$SRV/refs/latest" 2>/dev/null)"
GH_STUB_FAIL='release view latest*'
export GH_STUB_FAIL
out=$("$SCRIPT" latest 2>&1); rc=$?
unset GH_STUB_FAIL
[ "$rc" -ne 0 ] && [ "$(assets latest)" = "$before_assets" ] \
	&& [ "$(cat "$SRV/refs/latest" 2>/dev/null)" = "$before_tag" ] \
	&& ok "a failed query stops the run, not just the read" "rc=$rc" \
	|| no "a failed query stops the run, not just the read" "rc!=0 and nothing touched" "rc=$rc [$(assets latest)]"

# --- the very first run ------------------------------------------------------
# There is nothing to fall back on the first time, so the release is created as
# a draft: not on the download page, and carrying no tag until it is published.
# A failure before the assets are in must therefore leave nothing public at all,
# rather than an empty release somebody can already find.
srv_reset
GITHUB_SHA="6666666666666666666666666666666666666666"
make_assets "$APP_A"
GH_STUB_FAIL_MIDWAY="$APP_A"
export GH_STUB_FAIL_MIDWAY
out=$("$SCRIPT" latest 2>&1); rc=$?
unset GH_STUB_FAIL_MIDWAY
[ "$rc" -ne 0 ] && [ -f "$SRV/rel/latest/draft" ] && [ ! -f "$SRV/refs/latest" ] \
	&& ok "a failed first run stays a draft, untagged" "rc=$rc" \
	|| no "a failed first run stays a draft, untagged" "rc!=0, still draft, no tag" \
	      "rc=$rc draft=$([ -f "$SRV/rel/latest/draft" ] && echo yes || echo no) tag=$(cat "$SRV/refs/latest" 2>/dev/null)"

out=$("$SCRIPT" latest 2>&1); rc=$?
want="$APP_A SHA256SUMS "
[ "$rc" -eq 0 ] && [ ! -f "$SRV/rel/latest/draft" ] && [ "$(assets latest)" = "$want" ] \
	&& [ "$(cat "$SRV/refs/latest" 2>/dev/null)" = "$GITHUB_SHA" ] \
	&& ok "the repair run publishes the draft and tags it" "$(assets latest)" \
	|| no "the repair run publishes the draft and tags it" "$want, published, tagged" "rc=$rc [$(assets latest)]"

# --- re-dispatching an unchanged commit --------------------------------------
# The AppImage name carries Neutrino's version, so a rebuild of the same commit
# has the same asset name -- and replacing an asset by name means deleting it
# first. Where the release already holds this exact build, the safe handling is
# to touch nothing at all.
: > "$SRV/log"
out=$("$SCRIPT" latest 2>&1); rc=$?
grep -q '^release upload' "$SRV/log" && uploaded=1 || uploaded=0
[ "$rc" -eq 0 ] && [ "$uploaded" = 0 ] && [ "$(assets latest)" = "$want" ] \
	&& ok "an unchanged rebuild is not re-uploaded" "no upload" \
	|| no "an unchanged rebuild is not re-uploaded" "rc=0 and no upload" "rc=$rc upload=$uploaded [$out]"

# The notes of a rolling release have to follow the build it holds. They are
# handed to `gh release create`, which runs exactly once, so without a refresh
# every later correction would stay invisible at the place people actually read.
real_notes="$(cat "$SRV/rel/latest.body" 2>/dev/null)"
printf 'stale text from the very first run' > "$SRV/rel/latest.body"
out=$("$SCRIPT" latest 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$SRV/rel/latest.body")" = "$real_notes" ] \
	&& ok "latest refreshes its notes on every run" "restored" \
	|| no "latest refreshes its notes on every run" "the script's own notes" "rc=$rc [$(cut -c1-30 "$SRV/rel/latest.body")]"

# A draft state that cannot be read is not "published". Rounded down, the run
# would end green with the release still invisible -- an archive nobody can see,
# reported as archived.
GH_STUB_FAIL='release view * --json isDraft*'
export GH_STUB_FAIL
out=$("$SCRIPT" latest 2>&1); rc=$?
unset GH_STUB_FAIL
case "$out" in *"cannot read the draft state"*) msg=1 ;; *) msg=0 ;; esac
[ "$rc" -ne 0 ] && [ "$msg" = 1 ] \
	&& ok "an unreadable draft state stops the run" "rc=$rc" \
	|| no "an unreadable draft state stops the run" "rc!=0 and a reason" "rc=$rc [$out]"

# The same reading again, and the most expensive place to get it wrong: a
# checksum that could not be downloaded is not a checksum that differs. Taken
# as "differs", an unchanged re-dispatch would walk into the replacement path
# it is meant to avoid -- deleting a same-named package before uploading it.
: > "$SRV/log"
GH_STUB_FAIL='release download*'
export GH_STUB_FAIL
out=$("$SCRIPT" latest 2>&1); rc=$?
unset GH_STUB_FAIL
grep -q '^release upload' "$SRV/log" && uploaded=1 || uploaded=0
case "$out" in *"cannot read the published checksum"*) msg=1 ;; *) msg=0 ;; esac
[ "$rc" -ne 0 ] && [ "$msg" = 1 ] && [ "$uploaded" = 0 ] \
	&& ok "an unreadable checksum does not trigger a replacement" "rc=$rc" \
	|| no "an unreadable checksum does not trigger a replacement" "rc!=0, a reason, no upload" "rc=$rc upload=$uploaded [$out]"

# --- a draft left behind while master moved on -------------------------------
# Publishing a draft is what creates its tag, and the draft still carries the
# target of the run that made it. Without updating that first, the repair would
# publish the new package under the old commit's tag.
srv_reset
GITHUB_SHA="8888888888888888888888888888888888888888"
make_assets "$APP_A"
GH_STUB_FAIL_MIDWAY="$APP_A"
export GH_STUB_FAIL_MIDWAY
"$SCRIPT" latest >/dev/null 2>&1 || true
unset GH_STUB_FAIL_MIDWAY
GITHUB_SHA="9999999999999999999999999999999999999999"
make_assets "$APP_B"
# The tag move afterwards would paper over a stale target on its own, so it is
# made to fail here. That is the sequence the retargeting exists for: publish
# the draft, then lose the tag move, and the public release would serve the new
# package under the old commit's tag.
GH_STUB_FAIL='api -X PATCH*'
export GH_STUB_FAIL
out=$("$SCRIPT" latest 2>&1); rc=$?
unset GH_STUB_FAIL
[ "$(cat "$SRV/refs/latest" 2>/dev/null)" = "$GITHUB_SHA" ] \
	&& ok "a stale draft is retargeted before publishing" "$GITHUB_SHA" \
	|| no "a stale draft is retargeted before publishing" "tag $GITHUB_SHA" "rc=$rc tag=$(cat "$SRV/refs/latest" 2>/dev/null) [$out]"

# --- the window that is left -------------------------------------------------
# Where Neutrino is unchanged but the bytes are not -- a new build system
# commit, a moved dependency, a rebuilt runner image -- the AppImage keeps its
# name, and replacing an asset by name means deleting it first. gh offers no
# way around that. Pinned here so the cost stays visible and cannot widen
# unnoticed: the package is missing until the next run, the run is red, and the
# tag still names the build whose checksum is still published.
prev_tag="$(cat "$SRV/refs/latest" 2>/dev/null)"
make_assets "$APP_B" different-bytes
GH_STUB_FAIL_MIDWAY="$APP_B"
export GH_STUB_FAIL_MIDWAY
out=$("$SCRIPT" latest 2>&1); rc=$?
unset GH_STUB_FAIL_MIDWAY
gone=1
printf '%s\n' "$(assets latest)" | grep -q "$APP_B" && gone=0
[ "$rc" -ne 0 ] && [ "$gone" = 1 ] \
	&& [ "$(cat "$SRV/refs/latest" 2>/dev/null)" = "$prev_tag" ] \
	&& ok "a same-name replacement costs the package, not the tag" "rc=$rc" \
	|| no "a same-name replacement costs the package, not the tag" "rc!=0, package gone, tag kept" "rc=$rc [$(assets latest)]"

out=$("$SCRIPT" latest 2>&1); rc=$?
want="$APP_B SHA256SUMS "
[ "$rc" -eq 0 ] && [ "$(assets latest)" = "$want" ] \
	&& ok "and the next run puts it back" "$(assets latest)" \
	|| no "and the next run puts it back" "$want" "rc=$rc [$(assets latest)]"

# --- when the tag will not move ----------------------------------------------
# Pruning runs last, after the tag is in place. Reversed, a failed tag move
# would leave latest naming a build whose package had already been deleted.
# Self-contained: two builds of its own, so it does not depend on whatever the
# case above happened to leave behind.
srv_reset
GITHUB_SHA="7000000000000000000000000000000000000000"
make_assets "$APP_A"
"$SCRIPT" latest >/dev/null 2>&1
GITHUB_SHA="7777777777777777777777777777777777777777"
make_assets "$APP_B"
GH_STUB_FAIL='api -X PATCH*'
export GH_STUB_FAIL
out=$("$SCRIPT" latest 2>&1); rc=$?
unset GH_STUB_FAIL
still_there=0
printf '%s\n' "$(assets latest)" | grep -q "$APP_A" && still_there=1
[ "$rc" -ne 0 ] && [ "$still_there" = 1 ] \
	&& ok "a failed tag move keeps the old package" "$(assets latest)" \
	|| no "a failed tag move keeps the old package" "rc!=0 and $APP_A still there" "rc=$rc [$(assets latest)]"

# --- archive -----------------------------------------------------------------
srv_reset
GITHUB_SHA="4444444444444444444444444444444444444444"
make_assets "$APP_A"
# The tag has to name the commit of the run that publishes it -- the publish job
# checks that, because the name is formed in the job that runs project code.
archive_tag_for() {
	printf 'build/2026.8.42.git20260816192537.g85503bef6f-%.7s-hal455fba3-dvbsi8ed28af\n' "$1"
}
ARCHIVE_TAG="$(archive_tag_for "$GITHUB_SHA")"
export ARCHIVE_TAG
out=$("$SCRIPT" archive 2>&1); rc=$?
want="$APP_A SHA256SUMS "
[ "$rc" -eq 0 ] && [ "$(assets "$ARCHIVE_TAG")" = "$want" ] \
	&& ok "an archive is created with both files" "$(assets "$ARCHIVE_TAG")" \
	|| no "an archive is created with both files" "$want" "rc=$rc [$(assets "$ARCHIVE_TAG")] $out"

# The tag is a key and reads like one: it names four inputs that move on their
# own, and the publish job verifies part of it before writing. The title is the
# only half a person sees, so it must not be a copy of the key. Pinned as an
# exact string -- "shorter than the tag" would pass on a title that dropped the
# commit, and matching a download to its archive is the one thing it is for.
arch_title="$SRV/rel/$(printf '%s' "$ARCHIVE_TAG" | tr / _).title"
want="Neutrino 2026.8.42 (2026-08-16, 85503bef6f)"
[ "$(cat "$arch_title" 2>/dev/null)" = "$want" ] \
	&& ok "an archive is titled for a reader" "$want" \
	|| no "an archive is titled for a reader" "$want" "[$(cat "$arch_title" 2>/dev/null)]"

# A title is decoration. A slug it cannot read must cost the title, never the
# release -- so the tag comes back and both files still go up.
srv_reset
GITHUB_SHA="4a00000000000000000000000000000000000000"
make_assets "$APP_A"
ARCHIVE_TAG="build/2026.8.42.git2026081.g85503bef6f-$(printf '%.7s' "$GITHUB_SHA")-halsys-dvbsisys"
export ARCHIVE_TAG
out=$("$SCRIPT" archive 2>&1); rc=$?
arch_title="$SRV/rel/$(printf '%s' "$ARCHIVE_TAG" | tr / _).title"
want="$APP_A SHA256SUMS "
[ "$rc" -eq 0 ] && [ "$(assets "$ARCHIVE_TAG")" = "$want" ] \
	&& [ "$(cat "$arch_title" 2>/dev/null)" = "$ARCHIVE_TAG" ] \
	&& ok "an unreadable slug costs the title, not the release" "rc=0, tag as title" \
	|| no "an unreadable slug costs the title, not the release" "rc=0, both files, tag as title" \
		"rc=$rc [$(assets "$ARCHIVE_TAG")] title=[$(cat "$arch_title" 2>/dev/null)]"

srv_reset
GITHUB_SHA="4444444444444444444444444444444444444444"
make_assets "$APP_A"
ARCHIVE_TAG="$(archive_tag_for "$GITHUB_SHA")"
export ARCHIVE_TAG
"$SCRIPT" archive >/dev/null 2>&1

# Running it again must not upload anything: the archive is finished.
: > "$SRV/log"
out=$("$SCRIPT" archive 2>&1); rc=$?
case "$out" in *"already holds this exact build"*) msg=1 ;; *) msg=0 ;; esac
grep -q '^release upload' "$SRV/log" && again=1 || again=0
[ "$rc" -eq 0 ] && [ "$msg" = 1 ] && [ "$again" = 0 ] \
	&& ok "a finished archive is left alone" "no upload" \
	|| no "a finished archive is left alone" "rc=0, said so, no upload" "rc=$rc upload=$again [$out]"

# And the opposite for an archive: it describes one frozen build, so its notes
# must not drift to whatever the script says today. Not hypothetical -- the
# first archives were published before the package could detect a missing tuner,
# and their notes have to keep saying so.
arch_body="$SRV/rel/$(printf '%s' "$ARCHIVE_TAG" | tr / _).body"
printf 'the text this build was published with' > "$arch_body"
out=$("$SCRIPT" archive 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$arch_body")" = "the text this build was published with" ] \
	&& ok "an archive keeps the notes it was created with" "unchanged" \
	|| no "an archive keeps the notes it was created with" "unchanged text" "rc=$rc [$(cut -c1-30 "$arch_body")]"

# A half-finished archive -- the package uploaded, the checksum did not -- must
# be repaired, not declared finished. Counting assets instead of naming them is
# exactly the bug that makes this unrepairable.
rm -f "$SRV/rel/$(printf '%s' "$ARCHIVE_TAG" | tr / _)/assets/SHA256SUMS"
: > "$SRV/log"
out=$("$SCRIPT" archive 2>&1); rc=$?
want="$APP_A SHA256SUMS "
[ "$rc" -eq 0 ] && [ "$(assets "$ARCHIVE_TAG")" = "$want" ] \
	&& ok "a missing checksum is repaired" "$(assets "$ARCHIVE_TAG")" \
	|| no "a missing checksum is repaired" "$want" "rc=$rc [$(assets "$ARCHIVE_TAG")] $out"

# The reverse: a checksum with no package. Worse, because the release looks
# populated.
rm -f "$SRV/rel/$(printf '%s' "$ARCHIVE_TAG" | tr / _)/assets/$APP_A"
out=$("$SCRIPT" archive 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(assets "$ARCHIVE_TAG")" = "$want" ] \
	&& ok "a missing package is repaired" "$(assets "$ARCHIVE_TAG")" \
	|| no "a missing package is repaired" "$want" "rc=$rc [$(assets "$ARCHIVE_TAG")] $out"

# --- archive: a different build under the same tag ---------------------------
# The tag names three source commits but not the runner image, which GitHub
# rebuilds weekly. Two different packages must not end up under one label, and
# neither must be silently thrown away.
make_assets "$APP_A" rebuilt-elsewhere
: > "$SRV/log"
out=$("$SCRIPT" archive 2>&1); rc=$?
case "$out" in *"already archives a different build"*) msg=1 ;; *) msg=0 ;; esac
grep -q '^release upload' "$SRV/log" && again=1 || again=0
[ "$rc" -ne 0 ] && [ "$msg" = 1 ] && [ "$again" = 0 ] \
	&& ok "a differing rebuild is refused, not merged" "rc=$rc" \
	|| no "a differing rebuild is refused, not merged" "rc!=0, said so, no upload" "rc=$rc upload=$again [$out]"

# A checksum whose package was never uploaded describes something nobody can
# download, and this build is not it. Replacing it quietly would erase the
# record of what was meant to be archived, so the run stops and names the
# remedy rather than deciding for a person.
srv_reset
GITHUB_SHA="5555555555555555555555555555555555555555"
ARCHIVE_TAG="$(archive_tag_for "$GITHUB_SHA")"
make_assets "$APP_A"
"$SCRIPT" archive >/dev/null 2>&1 || true
rm -f "$SRV/rel/$(printf '%s' "$ARCHIVE_TAG" | tr / _)/assets/$APP_A"
make_assets "$APP_A" rebuilt-elsewhere
: > "$SRV/log"
out=$("$SCRIPT" archive 2>&1); rc=$?
case "$out" in *"delete the release"*) msg=1 ;; *) msg=0 ;; esac
grep -q '^release upload' "$SRV/log" && again=1 || again=0
[ "$rc" -ne 0 ] && [ "$msg" = 1 ] && [ "$again" = 0 ] \
	&& ok "a checksum without its package names a remedy" "rc=$rc" \
	|| no "a checksum without its package names a remedy" "rc!=0, a remedy, no upload" "rc=$rc upload=$again [$out]"

# The same reading as on latest, and the more expensive one to get wrong: a
# query that failed is not an empty archive. Rounded down, the comparison that
# keeps a permanent release permanent is skipped while the upload that follows
# is not.
srv_reset
make_assets "$APP_A"
"$SCRIPT" archive >/dev/null 2>&1 || true
kept="$(assets "$ARCHIVE_TAG")"
make_assets "$APP_A" rebuilt-elsewhere
GH_STUB_FAIL='release view build/*'
export GH_STUB_FAIL
out=$("$SCRIPT" archive 2>&1); rc=$?
unset GH_STUB_FAIL
[ "$rc" -ne 0 ] && [ "$(assets "$ARCHIVE_TAG")" = "$kept" ] \
	&& ok "a failed query does not overwrite an archive" "rc=$rc" \
	|| no "a failed query does not overwrite an archive" "rc!=0 and untouched" "rc=$rc [$(assets "$ARCHIVE_TAG")] want [$kept]"

# --- archive: refusals -------------------------------------------------------
# The name arrives from the job that clones and executes two moving branch tips.
# A prefix test alone would let that job name any tag under build/; these two
# are what this job can check on its own.
make_assets "$APP_A"
ARCHIVE_TAG="build/forged"
out=$("$SCRIPT" archive 2>&1); rc=$?
case "$out" in *"does not name this run's commit"*) msg=1 ;; *) msg=0 ;; esac
[ "$rc" -ne 0 ] && [ "$msg" = 1 ] \
	&& ok "a tag not naming this run's commit is refused" "rc=$rc" \
	|| no "a tag not naming this run's commit is refused" "rc!=0 and a reason" "rc=$rc [$out]"

ARCHIVE_TAG="build/2026.8.42-$(printf '%.7s' "$GITHUB_SHA")-hal455fba3-dvbsi8ed28af;rm -rf /"
out=$("$SCRIPT" archive 2>&1); rc=$?
case "$out" in *"unusual characters"*) msg=1 ;; *) msg=0 ;; esac
[ "$rc" -ne 0 ] && [ "$msg" = 1 ] \
	&& ok "a tag with unusual characters is refused" "rc=$rc" \
	|| no "a tag with unusual characters is refused" "rc!=0 and a reason" "rc=$rc [$out]"

ARCHIVE_TAG=""
out=$("$SCRIPT" archive 2>&1); rc=$?
case "$out" in *"named no archive tag"*) msg=1 ;; *) msg=0 ;; esac
[ "$rc" -ne 0 ] && [ "$msg" = 1 ] \
	&& ok "an empty archive tag is refused" "rc=$rc" \
	|| no "an empty archive tag is refused" "rc!=0 and a reason" "rc=$rc [$out]"

# The name is formed in the job that runs project code; this is the guard that
# sits where the write token is.
ARCHIVE_TAG="latest"
out=$("$SCRIPT" archive 2>&1); rc=$?
case "$out" in *"outside build/"*) msg=1 ;; *) msg=0 ;; esac
[ "$rc" -ne 0 ] && [ "$msg" = 1 ] \
	&& ok "a tag outside build/ is refused" "rc=$rc" \
	|| no "a tag outside build/ is refused" "rc!=0 and a reason" "rc=$rc [$out]"

out=$("$SCRIPT" 2>&1); rc=$?
case "$out" in *usage*) msg=1 ;; *) msg=0 ;; esac
[ "$rc" -ne 0 ] && [ "$msg" = 1 ] \
	&& ok "no command is refused" "rc=$rc" \
	|| no "no command is refused" "rc!=0 and a usage line" "rc=$rc [$out]"

echo "----"
echo "[test-shell] pass=$pass fail=$fail skip=$skip"
[ "$fail" -eq 0 ]
