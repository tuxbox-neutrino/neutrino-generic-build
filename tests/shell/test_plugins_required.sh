#!/bin/sh
#
# Unit test for the plugin aggregate contract in plugins/Makefile.
#
# The aggregate used to be a plain prerequisite list: the first failure aborted
# everything, and conversely a failed clone exited 0, so a REQUIRED plugin could
# be missing while the summary still said "ok". Both directions are checked here
# because either one silently defeats the guarantee.
#
# Runs offline: the plugin is pointed at a non-existent source with no clone URL,
# which makes it fail deterministically without touching the network.
#
# POSIX sh. Exits 0 on success, 1 on any failure.

set -u

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGINS_MK_DIR="$ROOT_DIR/plugins"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok() { printf 'ok   %s\n' "$1"; pass=$((pass + 1)); }
ko() { printf 'FAIL %s\n' "$1"; printf '     %s\n' "$2"; fail=$((fail + 1)); }

if [ ! -f "$PLUGINS_MK_DIR/Makefile" ]; then
	printf 'FAIL plugins/Makefile not found\n'
	exit 1
fi

# The mediathek install pulls in neutrino-mediathek-lua-helpers, which would
# otherwise clone plugin-scripts-lua over the network and write into the real
# sources/. Point it at a local stub and blank the clone URL, so this suite
# keeps its offline guarantee.
LUA_HELPERS_STUB="$WORK/lua-helpers"
mkdir -p "$LUA_HELPERS_STUB/5.2"
: > "$LUA_HELPERS_STUB/5.2/json.lua"

# Drive a single plugin that cannot possibly succeed: no source directory and no
# clone URL. Whether that makes the aggregate fail must depend solely on whether
# the plugin is listed in PLUGINS_REQUIRED.
run_aggregate() {
	required="$1"
	out_file="$2"
	make -C "$PLUGINS_MK_DIR" install \
		PLUGINS_ALL=neutrino-mediathek \
		PLUGINS_REQUIRED="$required" \
		NEUTRINO_MEDIATHEK_GIT_URL= \
		PLUGIN_SCRIPTS_LUA_GIT_URL= \
		NEUTRINO_LUA_HELPERS_SRC="$LUA_HELPERS_STUB" \
		NEUTRINO_RUNTIME_PREFIX_ABS="$WORK/runtime" \
		RUNTIME_ROOT_FALLBACK="$WORK/runtime" \
		NEUTRINO_MEDIATHEK_SRC="$WORK/does-not-exist" \
		PLUGIN_PRIMARY_DIR="$WORK/does-not-exist" \
		LEGACY_PLUGIN_SRC="$WORK/does-not-exist" \
		DESTDIR="$WORK/dest" \
		> "$out_file" 2>&1
	echo $?
}

# --- optional plugin fails: the aggregate must still succeed ---------------
rc_opt="$(run_aggregate "" "$WORK/opt.log")"
if [ "$rc_opt" -eq 0 ]; then
	ok "an OPTIONAL plugin failure does not fail the aggregate"
else
	ko "an OPTIONAL plugin failure does not fail the aggregate" "got rc=$rc_opt"
fi

if grep -q "FAILED" "$WORK/opt.log"; then
	ok "the failure is still reported in the summary"
else
	ko "the failure is still reported in the summary" "no FAILED line in output"
fi

if grep -q -- "---------- summary ----------" "$WORK/opt.log"; then
	ok "a deterministic summary is printed"
else
	ko "a deterministic summary is printed" "summary header missing"
fi

# --- required plugin fails: the aggregate must fail -------------------------
rc_req="$(run_aggregate "neutrino-mediathek" "$WORK/req.log")"
if [ "$rc_req" -ne 0 ]; then
	ok "a REQUIRED plugin failure fails the aggregate"
else
	ko "a REQUIRED plugin failure fails the aggregate" "got rc=0 (silent success)"
fi

if grep -q "at least one REQUIRED plugin failed" "$WORK/req.log"; then
	ok "the required-failure reason is named"
else
	ko "the required-failure reason is named" "explanatory line missing"
fi

# The plugin must be shown as FAILED and marked required, not as ok.
if grep -E "neutrino-mediathek[[:space:]]+FAILED[[:space:]]+\(required\)" "$WORK/req.log" >/dev/null; then
	ok "the summary marks it FAILED (required)"
else
	ko "the summary marks it FAILED (required)" "$(grep -i 'neutrino-mediathek' "$WORK/req.log" | head -2)"
fi

printf -- '----\n'
printf '[test-plugins-required] pass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
