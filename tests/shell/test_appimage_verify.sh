#!/bin/sh
#
# Unit test for the AppImage verification gate in scripts/verify_appimage.sh.
#
# The gate is the only thing standing between a broken package and a release, so
# the interesting question about it is not whether it passes -- it is whether it
# can still fail. Twice now it could not: a check that grepped for a log line
# Neutrino prints from a compile-time constant *before* it opens the file, so an
# empty data tree went through green; and an architecture check that compared
# the ELF class but not the machine. Both looked correct while reviewing them.
#
# So every assertion below takes a package that is known good, breaks exactly one
# property, and requires the gate to name that property. A gate that keeps
# passing is the failure being tested for.
#
# Runs offline: a stand-in binary and stand-in libraries stand for the real ones,
# and the container half of the gate is switched off.
#
# POSIX sh. Exits 0 on success, 1 on any failure.

set -u

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GEN="$ROOT_DIR/scripts/gen_appimage.sh"
VERIFY="$ROOT_DIR/scripts/verify_appimage.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
skip=0
ok() { printf 'ok   %s\n' "$1"; pass=$((pass + 1)); }
ko() { printf 'FAIL %s\n' "$1"; printf '     %s\n' "$2"; fail=$((fail + 1)); }
sk() { printf 'skip %s\n' "$1"; printf '     %s\n' "$2"; skip=$((skip + 1)); }

for f in "$GEN" "$VERIFY"; do
	if [ ! -f "$f" ]; then
		printf 'FAIL %s not found\n' "$f"
		exit 1
	fi
done

PREFIX=/opt/neutrino

# The gate is bash: it uses [[ ]], regex matching and process substitution.
# readelf/strings come from binutils, which it also depends on.
missing_tool=""
for t in bash readelf strings od; do
	command -v "$t" >/dev/null 2>&1 || missing_tool="$missing_tool $t"
done

CC="$(printf '%s' "${CC:-cc}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
[ -n "$CC" ] || CC=cc
CC_BIN="${CC%% *}"
command -v "$CC_BIN" >/dev/null 2>&1 || missing_tool="$missing_tool $CC_BIN"

if [ -n "$missing_tool" ]; then
	ko "the tools the gate itself needs are available" \
		"missing:$missing_tool -- the gate cannot run here, and neither can this test.
     Reporting that as a skip would leave the gate unexercised while the suite passes."
	printf -- '----\n'
	printf '[test-appimage-verify] pass=%d fail=%d skip=%d\n' "$pass" "$fail" "$skip"
	exit 1
fi

# --- a package the gate should accept ---------------------------------------
# Built through gen_appimage.sh rather than assembled by hand, so the AppRun the
# gate inspects is the real one. What gen does not produce -- the data volume of
# a real install, and the libraries the gate expects by name -- is added here.
# $1 = sysroot, $2 = soname for the freeglut stand-in. The second argument
# exists because the soname differs per distribution -- libglut.so.3 on
# Debian 13, libglut.so.3.12 on Ubuntu 24.04 -- and a gate that names it is
# wrong on one of them.
build_sysroot() {
	root="$1"
	glut_soname="${2:-libglut.so.3}"
	rm -rf "$root"
	mkdir -p "$root/usr/bin" "$root/usr/lib" "$root/usr/share/lua/5.1"
	data="$root$PREFIX/usr"
	mkdir -p "$data/share/tuxbox/neutrino/icons" \
		"$data/share/tuxbox/neutrino/locale" \
		"$data/share/tuxbox/neutrino/httpd" \
		"$data/share/fonts" \
		"$data/var/tuxbox/config"

	i=0
	while [ "$i" -lt 120 ]; do
		echo png > "$data/share/tuxbox/neutrino/icons/icon$i.png"
		i=$((i + 1))
	done
	i=0
	while [ "$i" -lt 60 ]; do
		echo page > "$data/share/tuxbox/neutrino/httpd/page$i.yhtm"
		i=$((i + 1))
	done
	i=0
	while [ "$i" -lt 8 ]; do
		echo conf > "$data/var/tuxbox/config/setting$i.conf"
		i=$((i + 1))
	done
	echo index > "$data/share/tuxbox/neutrino/httpd/index.html"
	echo locale > "$data/share/tuxbox/neutrino/locale/english.locale"
	echo font > "$data/share/fonts/neutrino.ttf"
	echo lua > "$root/usr/share/lua/5.1/module.lua"

	# The baked paths the gate looks for. Referenced from main so no optimisation
	# level can drop them.
	cat > "$WORK/fake.c" <<'CSRC'
#include <stdio.h>

static const char *const baked[] = {
	"/opt/neutrino/usr/share/tuxbox/neutrino",
	"/opt/neutrino/usr/share/fonts/neutrino.ttf",
	"/opt/neutrino/usr/var/tuxbox/config",
};

int main(void)
{
	printf("%s\n", baked[0]);
	return 0;
}
CSRC
	# LuaJIT's compiled-in module path names the staging directory; the gate
	# exempts it, and that exemption is one of the things under test.
	cat > "$WORK/fakelib.c" <<'CSRC'
const char luajit_baked_path[] = "/home/builder/staging/share/lua/5.1/?.lua";

int fake_entry(void)
{
	return 0;
}
CSRC
	# shellcheck disable=SC2086
	$CC -s -shared -fPIC -o "$root/usr/lib/libluajit-5.1.so.2" "$WORK/fakelib.c" \
		>/dev/null 2>&1 || return 1
	# Stand-ins for the libraries a package has to carry. Built from a source
	# without the staging path: only the LuaJIT library is exempt from the
	# host-path check, and copying it under these names would fail the fixture
	# for a reason this file is not about.
	#
	# Each gets its real soname and the binary is linked against it, because the
	# gate derives what must be bundled from the binary's own DT_NEEDED list.
	# A fixture whose binary depends on nothing would let that check pass no
	# matter what the package is missing.
	printf 'int stub_entry(void) { return 0; }\n' > "$WORK/stub.c"
	stub_libs=""
	for l in libGLEW.so.2.2 "$glut_soname" libfreetype.so.6; do
		# shellcheck disable=SC2086
		$CC -s -shared -fPIC -Wl,-soname,"$l" -o "$root/usr/lib/$l" "$WORK/stub.c" \
			>/dev/null 2>&1 || return 1
		stub_libs="$stub_libs -l:$l"
	done
	# --no-as-needed: the stand-in calls nothing in them, and the linker would
	# otherwise drop the very DT_NEEDED entries this fixture exists to produce.
	# Unquoted on purpose: CC may be "ccache gcc", and stub_libs is a list.
	# shellcheck disable=SC2086
	$CC -s -o "$root/usr/bin/neutrino" "$WORK/fake.c" \
		-L"$root/usr/lib" -Wl,--no-as-needed $stub_libs >/dev/null 2>&1 || return 1
	return 0
}

if ! build_sysroot "$WORK/sysroot"; then
	ko "the stand-in package can be built" \
		"'$CC' is on PATH but compiling the fixtures failed; nothing below would be exercised"
	printf -- '----\n'
	printf '[test-appimage-verify] pass=%d fail=%d skip=%d\n' "$pass" "$fail" "$skip"
	exit 1
fi

# scripts/version_info.sh exits when the Neutrino source tree is absent, which
# is the normal state of a CI checkout of this repo alone. It honours SRC_DIR,
# and the version it derives only names the output file, so the three defines it
# reads are enough.
FAKE_SRC="$WORK/fake-src"
mkdir -p "$FAKE_SRC"
cat > "$FAKE_SRC/configure.ac" <<'ACSRC'
define(ver_major, 2026)
define(ver_minor, 8)
define(ver_micro, 0)
ACSRC

( cd "$ROOT_DIR" && \
	SRC_DIR="$FAKE_SRC" \
	NEUTRINO_INSTALL_DIR="$WORK/sysroot" \
	APPIMAGE_OUTPUT_DIR="$WORK/out" \
	NEUTRINO_APPIMAGE_PREFIX="$PREFIX" \
	APPIMAGE_BUNDLE_GSTREAMER=0 \
	APPIMAGE_TOOL=/nonexistent-appimagetool \
	"$GEN" ) >"$WORK/gen.log" 2>&1

GOOD="$WORK/out/Neutrino.AppDir"
if [ ! -d "$GOOD" ] || [ ! -x "$GOOD/AppRun" ]; then
	ko "gen_appimage.sh produced an AppDir to verify" "$(tail -3 "$WORK/gen.log")"
	printf -- '----\n'
	printf '[test-appimage-verify] pass=%d fail=%d skip=%d\n' "$pass" "$fail" "$skip"
	exit 1
fi

# The gate takes an AppImage and extracts it. A script that answers
# --appimage-extract the same way is indistinguishable to it and needs no
# appimagetool, no FUSE and no root.
wrap() {
	img="$WORK/img-$2.AppImage"
	{
		printf '#!/bin/sh\n'
		printf '[ "$1" = "--appimage-extract" ] || exit 1\n'
		printf 'rm -rf ./squashfs-root\n'
		printf 'cp -a %s ./squashfs-root\n' "$1"
	} > "$img"
	chmod +x "$img"
	printf '%s' "$img"
}

# $1 = AppDir, $2 = tag, $3 = glibc floor
run_verify() {
	APPIMAGE_VERIFY_CONTAINER=0 \
	APPIMAGE_BUNDLE_GSTREAMER=0 \
	APPIMAGE_GLIBC_FLOOR="$3" \
		bash "$VERIFY" "$(wrap "$1" "$2")" 2>&1
}

# The floor is a property of the machine this runs on, not of the fixture, so it
# is put out of the way for every case except the one that tests it.
FLOOR=2.99

out="$(run_verify "$GOOD" good "$FLOOR")"
if [ $? -eq 0 ] && printf '%s' "$out" | grep -q 'Static checks passed'; then
	ok "a well-formed package passes the static checks"
else
	ko "a well-formed package passes the static checks" \
		"$(printf '%s' "$out" | tail -4)"
fi

# $1 = tag, $2 = expected message fragment, $3 = description, $4.. = mutation
# commands run against a copy in $BAD.
mutate() {
	tag="$1"; want="$2"; desc="$3"; shift 3
	BAD="$WORK/bad-$tag"
	rm -rf "$BAD"
	cp -a "$GOOD" "$BAD"
	"$@"
	out="$(run_verify "$BAD" "$tag" "${MUT_FLOOR:-$FLOOR}")"
	rc=$?
	if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "$want"; then
		ok "$desc"
	else
		ko "$desc" "rc=$rc, expected a failure naming '$want'
     got: $(printf '%s' "$out" | tail -3)"
	fi
	unset MUT_FLOOR
}

# The regression that started this file: the data tree present but empty. The
# gate used to test the directories with -d and the runtime with a log line
# printed before the file was opened, so this passed twice over.
empty_fonts() { rm -f "$BAD$PREFIX/usr/share/fonts/neutrino.ttf"; }
mutate fonts "share/fonts/neutrino.ttf" \
	"an empty fonts directory is rejected, not passed as present" empty_fonts

empty_icons() { find "$BAD$PREFIX/usr/share/tuxbox/neutrino/icons" -name '*.png' -delete; }
mutate icons "icons, expected at least" \
	"an emptied icon directory is rejected" empty_icons

empty_webroot() { find "$BAD$PREFIX/usr/share/tuxbox/neutrino/httpd" -name '*.yhtm' -delete; }
mutate webroot "expected at least 50" \
	"a webroot stripped to a handful of files is rejected" empty_webroot

empty_seed() { find "$BAD$PREFIX/usr/var/tuxbox/config" -name '*.conf' -delete; }
mutate seed "expected at least 5" \
	"a missing configuration seed is rejected" empty_seed

no_locale() { rm -f "$BAD$PREFIX/usr/share/tuxbox/neutrino/locale/english.locale"; }
mutate locale "no .locale file" \
	"a package without a single locale is rejected" no_locale

# The host graphics stack. A four-name list let these two through while
# reporting "no host graphics libraries bundled".
inject_gles() { cp "$BAD/usr/lib/libGLEW.so.2.2" "$BAD/usr/lib/libGLESv2.so.2"; }
mutate gles "graphics-driver libraries are bundled" \
	"an injected libGLESv2 is caught by the pattern" inject_gles

inject_gbm() { cp "$BAD/usr/lib/libGLEW.so.2.2" "$BAD/usr/lib/libgbm.so.1"; }
mutate gbm "graphics-driver libraries are bundled" \
	"an injected libgbm is caught by the pattern" inject_gbm

# The C runtime. A nine-name list called a package that shipped libgomp clean.
inject_libc() { cp "$BAD/usr/lib/libGLEW.so.2.2" "$BAD/usr/lib/libc.so.6"; }
mutate libc "C runtime are bundled" \
	"an injected C library is caught by the pattern" inject_libc

inject_stdcxx() { cp "$BAD/usr/lib/libGLEW.so.2.2" "$BAD/usr/lib/libstdc++.so.6"; }
mutate stdcxx "C runtime are bundled" \
	"an injected libstdc++ is caught by the pattern" inject_stdcxx

# A library the binary needs, simply absent. Named by the binary rather than by
# the gate: the list this replaced spelled out soname versions, and libglut.so.3
# does not exist on Ubuntu 24.04, so the gate rejected a sound package built
# there.
drop_freetype() { rm -f "$BAD/usr/lib/libfreetype.so.6"; }
mutate freetype "does not carry: libfreetype.so.6" \
	"a library the binary needs going missing is caught" drop_freetype

drop_glut() { rm -f "$BAD/usr/lib/libglut.so.3"; }
mutate glut "does not carry: libglut.so.3" \
	"the check follows the binary's own dependency list, not a fixed one" drop_glut

# The regression this cost a CI run: freeglut is libglut.so.3 on Debian 13 and
# libglut.so.3.12 on Ubuntu 24.04. A gate that names the file rejects a sound
# package built on the other distribution, which is exactly what happened.
if build_sysroot "$WORK/sysroot-alt" libglut.so.3.12; then
	( cd "$ROOT_DIR" && \
		SRC_DIR="$FAKE_SRC" \
		NEUTRINO_INSTALL_DIR="$WORK/sysroot-alt" \
		APPIMAGE_OUTPUT_DIR="$WORK/out-alt" \
		NEUTRINO_APPIMAGE_PREFIX="$PREFIX" \
		APPIMAGE_BUNDLE_GSTREAMER=0 \
		APPIMAGE_TOOL=/nonexistent-appimagetool \
		"$GEN" ) >"$WORK/gen-alt.log" 2>&1
	if [ -d "$WORK/out-alt/Neutrino.AppDir" ]; then
		out="$(run_verify "$WORK/out-alt/Neutrino.AppDir" alt "$FLOOR")"
		if [ $? -eq 0 ] && printf '%s' "$out" | grep -q 'Static checks passed'; then
			ok "a different soname for the same library still passes"
		else
			ko "a different soname for the same library still passes" \
				"$(printf '%s' "$out" | tail -3)"
		fi
	else
		ko "a different soname for the same library still passes" \
			"gen_appimage.sh produced no AppDir: $(tail -2 "$WORK/gen-alt.log")"
	fi
else
	ko "a different soname for the same library still passes" \
		"the alternative fixture could not be built"
fi

# A shared object that cannot be read is not automatically harmless: a truncated
# one wears the ELF magic, and skipping it silently is how a wrong-architecture
# library would travel.
truncate_lib() { head -c 24 "$BAD/usr/lib/libGLEW.so.2.2" > "$BAD/usr/lib/libtrunc.so.1"; }
mutate trunc "unreadable-ELF-header" \
	"a truncated shared object is reported, not skipped" truncate_lib

# ... while a *.so that was never ELF is exactly the case the guard exists for,
# and must not abort the gate before the checks below it have run.
add_text_so() { printf 'GROUP ( libc.so.6 )\n' > "$BAD/usr/lib/libscript.so"; }
BAD="$WORK/bad-textso"
rm -rf "$BAD"; cp -a "$GOOD" "$BAD"; add_text_so
out="$(run_verify "$BAD" textso "$FLOOR")"
if [ $? -eq 0 ] && printf '%s' "$out" | grep -q 'Static checks passed'; then
	ok "a linker script named *.so does not abort the gate"
else
	ko "a linker script named *.so does not abort the gate" \
		"$(printf '%s' "$out" | tail -4)"
fi

# The LuaJIT exemption. AppRun only overrides the module path when the module
# directory is in the package, so without it the exempted host path is live.
drop_lua() { rm -rf "$BAD/usr/share/lua" "$BAD/usr/lib/lua"; }
mutate lua "LuaJIT's baked build path would be used" \
	"the LuaJIT exemption is withdrawn when AppRun's override cannot run" drop_lua

# Any other file carrying a build host path.
add_host_path() { echo 'prefix=/home/builder/staging' > "$BAD/usr/lib/leftover.pc"; }
mutate hostpath "build host paths" \
	"a stray file naming the build host is caught" add_host_path

# The wrong build variant: a binary that resolves its data somewhere else.
swap_binary() {
	# shellcheck disable=SC2086
	printf 'int main(void){return 0;}\n' > "$WORK/other.c"
	# shellcheck disable=SC2086
	$CC -s -o "$BAD/usr/bin/neutrino" "$WORK/other.c" >/dev/null 2>&1
}
mutate variant "wrong build variant" \
	"a binary built for another prefix is caught" swap_binary

# The documented glibc floor, measured rather than asserted.
noop() { :; }
MUT_FLOOR=2.0
mutate floor "documented floor" \
	"a package needing a newer glibc than documented is rejected" noop

printf -- '----\n'
printf '[test-appimage-verify] pass=%d fail=%d skip=%d\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ] || exit 1
exit 0
