#!/bin/sh
#
# Unit test for the neutrino-mediathek install guard in plugins/Makefile.
#
# A pre-fix version of the plugin's own Makefile left plugins/neutrino-mediathek
# as a real directory with a wrongly nested symlink inside it, so at launch
# dofile(".../plugins/neutrino-mediathek/mt_variables.lua") failed with a Lua
# Script Error. neutrino-mediathek-install now verifies the installed layout and
# repairs that corruption (or fails loudly), so a broken plugin can never be
# shipped silently.
#
# Hermetic: a fake plugin source with its own Makefile stands in for the real
# repo, so nothing is cloned and no network is touched. The install also does
# a stale-copy cleanup across the runtime mirrors, so those roots are pointed
# into $WORK too -- otherwise the suite would delete plugins a developer has
# actually staged under root/. Three source layouts are
# exercised: the buggy nested one (must be repaired), a correct one (no-op), and
# an unrepairable one (must fail).
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

# Build a fake plugin source. $1 = directory, $2 = layout mode the fake
# Makefile's install target should produce (buggy|good|broken). The pre-checks
# in neutrino-mediathek-install require the top-level files and the subdirectory
# to exist in the source, so every mode ships them.
make_fake_source() {
	src="$1"
	mode="$2"
	mkdir -p "$src/neutrino-mediathek"
	: > "$src/neutrino-mediathek.lua"
	: > "$src/neutrino-mediathek.cfg"
	: > "$src/neutrino-mediathek_hint.png"
	printf 'return true\n' > "$src/neutrino-mediathek/mt_variables.lua"

	# The generic build calls: make -C <src> install DESTDIR=.. \
	#   PREFIX=<..>/share/tuxbox/neutrino PLUGIN_SUBDIR=plugins \
	#   LUAPLUGIN_SUBDIR=luaplugins
	# Recreate just enough of that contract for each layout.
	{
		printf 'install:\n'
		printf '\t@P="$(DESTDIR)$(PREFIX)"; \\\n'
		printf '\tinstall -d "$$P/$(LUAPLUGIN_SUBDIR)/neutrino-mediathek"; \\\n'
		printf '\tinstall -d "$$P/$(PLUGIN_SUBDIR)"; \\\n'
		case "$mode" in
		good)
			# real files in luaplugins, correct directory symlink in plugins
			printf '\tcp neutrino-mediathek/mt_variables.lua "$$P/$(LUAPLUGIN_SUBDIR)/neutrino-mediathek/"; \\\n'
			printf '\trm -rf "$$P/$(PLUGIN_SUBDIR)/neutrino-mediathek"; \\\n'
			printf '\tln -s ../$(LUAPLUGIN_SUBDIR)/neutrino-mediathek "$$P/$(PLUGIN_SUBDIR)/neutrino-mediathek"\n'
			;;
		buggy)
			# real files in luaplugins, but the plugins entry is a directory
			# with a nested symlink inside it (the shipped-broken layout)
			printf '\tcp neutrino-mediathek/mt_variables.lua "$$P/$(LUAPLUGIN_SUBDIR)/neutrino-mediathek/"; \\\n'
			printf '\tinstall -d "$$P/$(PLUGIN_SUBDIR)/neutrino-mediathek"; \\\n'
			printf '\tln -sf ../$(LUAPLUGIN_SUBDIR)/neutrino-mediathek "$$P/$(PLUGIN_SUBDIR)/neutrino-mediathek"\n'
			;;
		broken)
			# nothing resolvable anywhere: luaplugins has no files, so the
			# guard cannot repair and must fail
			printf '\tinstall -d "$$P/$(PLUGIN_SUBDIR)/neutrino-mediathek"\n'
			;;
		esac
	} > "$src/Makefile"
}

run_install() {
	src="$1"
	dest="$2"
	out="$3"
	make -C "$PLUGINS_MK_DIR" neutrino-mediathek-install \
		NEUTRINO_MEDIATHEK_GIT_URL= \
		PLUGIN_SCRIPTS_LUA_GIT_URL= \
		NEUTRINO_LUA_HELPERS_SRC="$LUA_HELPERS_STUB" \
		NEUTRINO_RUNTIME_PREFIX_ABS="$WORK/runtime" \
		RUNTIME_ROOT_FALLBACK="$WORK/runtime" \
		NEUTRINO_MEDIATHEK_SRC="$src" \
		PLUGIN_PRIMARY_DIR="$src" \
		LEGACY_PLUGIN_SRC="$src" \
		DESTDIR="$dest" \
		> "$out" 2>&1
	echo $?
}

plugin_entry() { echo "$1/usr/share/tuxbox/neutrino/plugins/neutrino-mediathek"; }

# --- buggy layout: install must succeed and repair the plugin ---------------
src_b="$WORK/src-buggy"; dest_b="$WORK/dest-buggy"
make_fake_source "$src_b" buggy
rc_b="$(run_install "$src_b" "$dest_b" "$WORK/buggy.log")"
entry_b="$(plugin_entry "$dest_b")"

if [ "$rc_b" -eq 0 ]; then
	ok "install succeeds on the pre-fix nested layout"
else
	ko "install succeeds on the pre-fix nested layout" "rc=$rc_b: $(tail -3 "$WORK/buggy.log")"
fi

if [ -f "$entry_b/mt_variables.lua" ]; then
	ok "the plugin resolves to mt_variables.lua after repair"
else
	ko "the plugin resolves to mt_variables.lua after repair" "not readable via the plugins path"
fi

if [ -L "$entry_b" ]; then
	ok "plugins/neutrino-mediathek is a directory symlink, not a nested dir"
else
	ko "plugins/neutrino-mediathek is a directory symlink, not a nested dir" "entry is not a symlink"
fi

if grep -qi "repair" "$WORK/buggy.log"; then
	ok "the repair is reported"
else
	ko "the repair is reported" "no repair notice in output"
fi

# --- good layout: install must succeed and leave it untouched (no-op) -------
src_g="$WORK/src-good"; dest_g="$WORK/dest-good"
make_fake_source "$src_g" good
rc_g="$(run_install "$src_g" "$dest_g" "$WORK/good.log")"
entry_g="$(plugin_entry "$dest_g")"

if [ "$rc_g" -eq 0 ] && [ -f "$entry_g/mt_variables.lua" ]; then
	ok "a correct layout installs and resolves without repair"
else
	ko "a correct layout installs and resolves without repair" "rc=$rc_g, resolvable=$([ -f "$entry_g/mt_variables.lua" ] && echo yes || echo no)"
fi

if grep -qi "repair" "$WORK/good.log"; then
	ko "a correct layout triggers no repair" "unexpected repair notice"
else
	ok "a correct layout triggers no repair"
fi

# --- broken layout: nothing resolvable, install must fail loudly ------------
src_x="$WORK/src-broken"; dest_x="$WORK/dest-broken"
make_fake_source "$src_x" broken
rc_x="$(run_install "$src_x" "$dest_x" "$WORK/broken.log")"

if [ "$rc_x" -ne 0 ]; then
	ok "an unrepairable install fails instead of shipping a broken plugin"
else
	ko "an unrepairable install fails instead of shipping a broken plugin" "got rc=0 (silent success)"
fi

printf -- '----\n'
printf '[test-mediathek-install] pass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
