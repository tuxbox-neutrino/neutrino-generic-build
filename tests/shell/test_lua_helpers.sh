#!/bin/sh
#
# Unit test for the Lua helper acquisition in plugins/Makefile.
#
# The helper libraries (json, feedparser, n_gui, n_helpers) used to be a
# vendored copy inside this repository, so they were always present. They now
# come from plugin-scripts-lua, fetched on demand like every other plugin
# source. That swapped an always-succeeds path for one that can fail, and a
# swallowed failure here is invisible: the plugin installs, the aggregate says
# "ok", and Neutrino only breaks at runtime when a plugin calls require("json").
#
# So the contract under test is: the helpers are either staged, or the build
# fails loudly. Never "warned about and continued".
#
# Runs offline: the clone URL is either blank or points at an unresolvable host,
# so the network is never usefully reached and nothing is written to sources/.
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

# $1 = destination root, remaining args = extra make variables.
run_helpers() {
	dest="$1"
	out="$2"
	shift 2
	make -C "$PLUGINS_MK_DIR" neutrino-mediathek-lua-helpers \
		DESTDIR="$dest" \
		PREFIX=/usr \
		"$@" \
		> "$out" 2>&1
	echo $?
}

# --- a usable source is staged, including the 5.1 compat copy --------------
src="$WORK/helpers"
mkdir -p "$src/5.2/feedparser" "$src/5.3"
: > "$src/5.2/json.lua"
: > "$src/5.2/feedparser/url.lua"
: > "$src/5.3/json.lua"

rc="$(run_helpers "$WORK/dest-ok" "$WORK/ok.log" \
	NEUTRINO_LUA_HELPERS_SRC="$src" \
	PLUGIN_SCRIPTS_LUA_GIT_URL=)"
if [ "$rc" -eq 0 ]; then
	ok "an available helper source is staged"
else
	ko "an available helper source is staged" "got rc=$rc: $(cat "$WORK/ok.log")"
fi

if [ -f "$WORK/dest-ok/usr/share/lua/5.2/json.lua" ] &&
	[ -f "$WORK/dest-ok/usr/share/lua/5.3/json.lua" ] &&
	[ -f "$WORK/dest-ok/usr/share/lua/5.2/feedparser/url.lua" ]; then
	ok "the staged tree keeps the 5.x layout and subdirectories"
else
	ko "the staged tree keeps the 5.x layout and subdirectories" \
		"missing under $WORK/dest-ok"
fi

# Lua 5.1 consumers look in 5.1/; the recipe mirrors 5.2 there.
if [ -f "$WORK/dest-ok/usr/share/lua/5.1/json.lua" ]; then
	ok "a 5.1 compatibility copy is created"
else
	ko "a 5.1 compatibility copy is created" "no 5.1/json.lua"
fi

# --- helpers unobtainable, no clone URL: must fail, not warn ---------------
rc="$(run_helpers "$WORK/dest-nourl" "$WORK/nourl.log" \
	NEUTRINO_LUA_HELPERS_SRC="$WORK/absent/share/lua" \
	LEGACY_LUA_SRC="$WORK/absent/share/lua" \
	PLUGIN_SCRIPTS_LUA_SRC="$WORK/absent" \
	PLUGIN_SCRIPTS_LUA_GIT_URL=)"
if [ "$rc" -ne 0 ]; then
	ok "missing helpers with no clone URL fail the build"
else
	ko "missing helpers with no clone URL fail the build" "got rc=0"
fi

if grep -q 'NEUTRINO_LUA_HELPERS_SRC=' "$WORK/nourl.log"; then
	ok "the failure names a way to supply the helpers"
else
	ko "the failure names a way to supply the helpers" "$(cat "$WORK/nourl.log")"
fi

# --- clone fails: must fail, not warn --------------------------------------
rc="$(run_helpers "$WORK/dest-clone" "$WORK/clone.log" \
	NEUTRINO_LUA_HELPERS_SRC="$WORK/never-cloned/share/lua" \
	LEGACY_LUA_SRC="$WORK/never-cloned/share/lua" \
	PLUGIN_SCRIPTS_LUA_SRC="$WORK/never-cloned" \
	PLUGIN_SCRIPTS_LUA_GIT_URL=https://plugin-scripts-lua.invalid/x.git)"
if [ "$rc" -ne 0 ]; then
	ok "a failed clone fails the build"
else
	ko "a failed clone fails the build" "got rc=0"
fi

# --- an interrupted clone must not be mistaken for a usable checkout -------
mkdir -p "$WORK/partial"
rc="$(run_helpers "$WORK/dest-partial" "$WORK/partial.log" \
	NEUTRINO_LUA_HELPERS_SRC="$WORK/partial/share/lua" \
	LEGACY_LUA_SRC="$WORK/partial/share/lua" \
	PLUGIN_SCRIPTS_LUA_SRC="$WORK/partial" \
	PLUGIN_SCRIPTS_LUA_GIT_URL=https://plugin-scripts-lua.invalid/x.git)"
if [ "$rc" -ne 0 ]; then
	ok "a checkout without share/lua fails instead of being used"
else
	ko "a checkout without share/lua fails instead of being used" "got rc=0"
fi

if grep -q 'no share/lua' "$WORK/partial.log"; then
	ok "the failure explains the incomplete checkout"
else
	ko "the failure explains the incomplete checkout" "$(cat "$WORK/partial.log")"
fi

# --- an explicitly chosen source is never silently swapped for a clone ------
# A typo in NEUTRINO_LUA_HELPERS_SRC used to fall through to the network and
# stage plugin-scripts-lua instead, so the build quietly ignored what was asked
# for -- and an intendedly offline build reached out anyway.
rc="$(run_helpers "$WORK/dest-typo" "$WORK/typo.log" \
	NEUTRINO_LUA_HELPERS_SRC="$WORK/typo-path")"
if [ "$rc" -ne 0 ]; then
	ok "an explicit but missing helper source fails instead of cloning"
else
	ko "an explicit but missing helper source fails instead of cloning" "got rc=0"
fi

if grep -q 'Cloning plugin-scripts-lua' "$WORK/typo.log"; then
	ko "no clone is attempted for an explicit source" "$(cat "$WORK/typo.log")"
else
	ok "no clone is attempted for an explicit source"
fi

printf -- '----\n'
printf '[test-lua-helpers] pass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
