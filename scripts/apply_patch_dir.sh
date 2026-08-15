#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
	echo "Usage: $0 <src-dir> <patch-dir> [label]" >&2
	exit 1
fi

SRC_DIR="$1"
PATCH_DIR="$2"
LABEL="${3:-patches}"

if [ ! -d "$PATCH_DIR" ]; then
	exit 0
fi

shopt -s nullglob
patches=("$PATCH_DIR"/*.patch)
shopt -u nullglob

if [ "${#patches[@]}" -eq 0 ]; then
	exit 0
fi

# Shared awk normaliser, used by the hunk matcher below.
#
# Comparison is case-sensitive except inside shell variable references.
# Autoconf derives PKG_CHECK_MODULES variables from the module name, so an
# upstream fix may read $LUAJIT_CFLAGS where the patch writes $luajit_CFLAGS.
# Folding only $-references keeps case-sensitive C/C++ and shell identifiers
# outside those references from matching each other by accident. Everything used
# here is POSIX awk; IGNORECASE would be a gawk extension that mawk silently
# ignores, giving two different results on two hosts.
AWK_NORM_FUNC='
	function norm(s,   out) {
		gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
		out = ""
		while (match(s, /\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/)) {
			out = out substr(s, 1, RSTART - 1) \
				toupper(substr(s, RSTART, RLENGTH))
			s = substr(s, RSTART + RLENGTH)
		}
		return out s
	}
'

# Do the given lines appear in the target as one contiguous block, in order?
# Requiring the whole block rather than each line individually stops a single
# identical line elsewhere in the file from making an inapplicable patch look
# already applied. Hunk context is deliberately not required: upstream often
# restructures the surrounding code while keeping the fix itself, which is
# exactly the case this fallback exists for.
contiguous_block_present() {
	local target_file="$1"
	local joined="$2"

	awk -v joined="$joined" "$AWK_NORM_FUNC"'
		BEGIN {
			n = split(joined, want, "\001")
			for (i = 1; i <= n; i++) want[i] = norm(want[i])
		}
		{ lines[NR] = norm($0) }
		END {
			if (n == 0) exit 1
			for (start = 1; start + n - 1 <= NR; start++) {
				ok = 1
				for (i = 1; i <= n; i++) {
					if (lines[start + i - 1] != want[i]) { ok = 0; break }
				}
				if (ok) exit 0
			}
			exit 1
		}
	' "$target_file"
}

# A patch counts as already present in evolved form only when, for every hunk:
#   * the added lines appear contiguously in the target, anchored by one of the
#     hunk's immediately adjacent context lines, and
#   * none of the deleted lines survive anywhere in the file.
#
# The anchor is what ties the match to a location. Requiring the hunk's FULL
# context instead would defeat the purpose: upstream typically restructures the
# surrounding code while keeping the fix, which is exactly the situation this
# fallback exists for. Requiring no anchor at all would let an identical block
# somewhere else in the file pass. One adjacent line is the middle ground —
# either the line that followed the addition or the one that preceded it.
#
# This is weaker than a real patch application and deliberately so: it only
# decides whether to skip a patch that neither applies nor reverses cleanly.
patch_effectively_present() {
	local patch_file="$1"
	local saw_change=0

	while IFS=$'\t' read -r rel_file kind joined; do
		local target_file="$SRC_DIR/$rel_file"

		[ -n "$rel_file" ] || return 1
		[ -f "$target_file" ] || return 1
		[ -n "$joined" ] || continue

		case "$kind" in
		ANCHORED)
			saw_change=1
			local matched=0 candidate
			# Any one anchored candidate is enough; they describe the same
			# addition seen from its trailing and from its leading context.
			while IFS= read -r candidate; do
				[ -n "$candidate" ] || continue
				if contiguous_block_present "$target_file" "$candidate"; then
					matched=1
					break
				fi
			done < <(printf '%s\n' "$joined" | tr '\002' '\n')
			[ "$matched" = 1 ] || return 1
			;;
		DEL)
			contiguous_block_present "$target_file" "$joined" && return 1
			;;
		UNANCHORED)
			# An addition with no context on either side cannot be located.
			return 1
			;;
		*)
			return 1
			;;
		esac
	done < <(
		awk '
			# Each contiguous run of + lines is one group with its own anchors.
			# A hunk may hold several such runs separated by context, and they
			# are not adjacent in the target, so they must not be merged.
			function close_group(post,   cands) {
				if (nadd == 0) { return }
				if (file == "") { adds = ""; nadd = 0; pre = ""; return }
				cands = ""
				if (post != "") { cands = adds "\001" post }
				if (pre != "") {
					cands = (cands == "" ? "" : cands "\002") pre "\001" adds
				}
				# No context on either side means no way to tie the block to a
				# location, so the patch cannot be confirmed as already present.
				if (cands != "") { print file "\tANCHORED\t" cands }
				else { print file "\tUNANCHORED\t" adds }
				adds = ""; nadd = 0; pre = ""
			}
			/^\+\+\+ b\// { close_group(""); file = substr($0, 7); in_hunk = 0; prev = ""; next }
			/^@@/ { close_group(""); in_hunk = 1; prev = ""; next }
			!in_hunk { next }
			/^\\/ { next }
			/^\+/ {
				if (nadd == 0) { pre = prev }
				adds = (nadd++ ? adds "\001" : "") substr($0, 2)
				next
			}
			# Deletions do not appear in the post-image, so they neither anchor
			# a group nor become the preceding line of the next one.
			/^-/ { close_group(""); if (file != "") print file "\tDEL\t" substr($0, 2); next }
			/^ / {
				close_group(substr($0, 2))
				prev = substr($0, 2)
				next
			}
			{ close_group(""); in_hunk = 0 }
			END { close_group("") }
		' "$patch_file"
	)

	[ "$saw_change" = 1 ]
}

for patch_file in "${patches[@]}"; do
	patch_name="$(basename "$patch_file")"
	echo "[$LABEL] Applying $patch_name"

	if patch -d "$SRC_DIR" -p1 -N --dry-run < "$patch_file" >/dev/null 2>&1; then
		# --no-backup-if-mismatch: a hunk applying at an offset otherwise leaves
		# a .orig file behind in the source checkout, which is a shared repo.
		patch -d "$SRC_DIR" -p1 -N --no-backup-if-mismatch < "$patch_file"
		continue
	fi

	if patch -d "$SRC_DIR" -R -p1 --dry-run < "$patch_file" >/dev/null 2>&1; then
		echo "[$LABEL] Patch already present: $patch_name"
		continue
	fi

	if patch_effectively_present "$patch_file"; then
		echo "[$LABEL] Patch already present in evolved form: $patch_name"
		continue
	fi

	echo "[$LABEL] ERROR: could not apply $patch_name in $SRC_DIR" >&2
	exit 1
done
