#!/usr/bin/env bash
# Verify a built AppImage.
#
# ldd on the build machine proves nothing: every dependency is installed there,
# which is exactly why the package looked fine for so long while shipping no
# data at all. So this checks the finished artefact instead, and then starts it
# on a system that has never built Neutrino.
#
# Usage: verify_appimage.sh [path/to/Neutrino*.AppImage]
set -euo pipefail

APPIMAGE="${1:-}"
OUTPUT_DIR="${APPIMAGE_OUTPUT_DIR:-artifacts/appimage}"
DATA_PREFIX="${NEUTRINO_APPIMAGE_PREFIX:-/opt/neutrino}"
VERIFY_IMAGE="${APPIMAGE_VERIFY_IMAGE:-debian:13}"
RUN_CONTAINER="${APPIMAGE_VERIFY_CONTAINER:-1}"

if [[ -z "${APPIMAGE}" ]]; then
  APPIMAGE="$(ls -1t "${OUTPUT_DIR}"/*.AppImage 2>/dev/null | sed -n 1p || true)"
fi
if [[ -z "${APPIMAGE}" || ! -f "${APPIMAGE}" ]]; then
  echo "[verify] No AppImage found. Run 'make package-appimage' first." >&2
  exit 1
fi
APPIMAGE="$(readlink -f "${APPIMAGE}")"
echo "[verify] Checking ${APPIMAGE}"

fail() { echo "[verify] FAIL: $*" >&2; exit 1; }
pass() { echo "[verify]   ok: $*"; }

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
( cd "${workdir}" && APPIMAGE_EXTRACT_AND_RUN=1 "${APPIMAGE}" --appimage-extract >/dev/null 2>&1 ) \
  || fail "cannot extract the AppImage"
appdir="${workdir}/squashfs-root"
binary="${appdir}/usr/bin/neutrino"

[[ -x "${binary}" ]] || fail "no Neutrino binary inside the package"

# Dumped once, to a file, deliberately. "strings | grep -q" looks harmless but
# is inverted under `set -o pipefail`: grep -q exits at the first match, strings
# dies of SIGPIPE, the pipeline reports 141, and the test is false exactly when
# a match is present -- so the check would have passed on every package it was
# supposed to reject.
strings_dump="${workdir}/binary.strings"
strings -a "${binary}" >"${strings_dump}"

# 1. The binary has to look for its data where the package actually carries it.
#    A package built from the developer tree points at the builder's home
#    directory instead, and nothing about it looks wrong until it is started.
data_hits="$(grep -c "^${DATA_PREFIX}/" "${strings_dump}" || true)"
[[ "${data_hits}" -gt 0 ]] || fail "binary carries no ${DATA_PREFIX} paths -- wrong build variant packaged"
pass "binary resolves its data below ${DATA_PREFIX} (${data_hits} paths)"

# 2. No trace of the machine it was built on -- neither in the binary, nor in
#    the RUNPATH, nor in any other file the package ships. Libtool archives and
#    pkg-config files record the staging directory too, and checking only the
#    binary is how they went unnoticed.
if grep -qE '/(home|root)/[^/]+/' "${strings_dump}"; then
  grep -oE '/(home|root)/[^/"]+' "${strings_dump}" | sort -u | sed -n '1,5p' >&2
  fail "binary carries build host paths"
fi
# One named exception, not a blanket one. LuaJIT is built with PREFIX set to
# the staging directory instead of /usr plus DESTDIR, so its compiled-in module
# search path names the build machine. That is a property of how this build
# system builds LuaJIT, not of the packaging, and changing it would move the
# module path for the developer build too. AppRun sets LUA_PATH and LUA_CPATH so
# the baked default is never consulted; the string remains inside the library.
host_path_files_all="$(grep -rlE '/(home|root)/[^/]+/' "${appdir}" 2>/dev/null || true)"
host_path_files="$(printf '%s\n' "${host_path_files_all}" | grep -v '/usr/lib/libluajit-' | grep -v '^$' || true)"
if [[ -n "${host_path_files}" ]]; then
  printf '%s\n' "${host_path_files}" | sed "s|${appdir}|.|" | sed -n '1,10p' >&2
  fail "the package ships files containing build host paths"
fi
# The exemption is only worth granting while the override it relies on actually
# happens. AppRun sets LUA_PATH/LUA_CPATH inside an `if` that tests for the
# module directories, so on a package built without them the export never runs,
# LuaJIT consults its baked staging path after all -- and the exemption would
# wave the resulting host path through unremarked. Tie the two together.
if printf '%s\n' "${host_path_files_all}" | grep -q '/usr/lib/libluajit-'; then
  lua_abi="$(sed -n 's|^[[:space:]]*LUA_PATH="\${APPDIR}/usr/share/lua/\([^/]*\)/.*|\1|p' "${appdir}/AppRun" | sed -n 1p)"
  [[ -n "${lua_abi}" ]] \
    || fail "AppRun sets no LUA_PATH, so LuaJIT would fall back to its baked build path"
  [[ -d "${appdir}/usr/share/lua/${lua_abi}" || -d "${appdir}/usr/lib/lua/${lua_abi}" ]] \
    || fail "AppRun only sets LUA_PATH when usr/{share,lib}/lua/${lua_abi} is in the package, and it is not -- LuaJIT's baked build path would be used"
  grep -qE '^[[:space:]]*export LUA_PATH LUA_CPATH$' "${appdir}/AppRun" \
    || fail "AppRun does not export LUA_PATH/LUA_CPATH, so LuaJIT would fall back to its baked build path"
  # Spelled out rather than `grep && fail`: the exit status of an AND-OR list
  # whose first half failed is 1, and reasoning about whether errexit sees that
  # through the enclosing block is not worth the risk in a script whose whole
  # job is to be trustworthy.
  if grep -q 'LUA_CPATH=.*;;' "${appdir}/AppRun"; then
    fail "LUA_CPATH ends in ';;', which appends LuaJIT's baked build path again"
  fi
fi
pass "no build host path anywhere in the package (LuaJIT's baked default is overridden)"
runpath="$(readelf -d "${binary}" | awk '/RUNPATH|RPATH/ {print $NF}' | tr -d '[]')"
case "${runpath}" in
  ''|'$ORIGIN'*) pass "RUNPATH is relocatable (${runpath:-none})" ;;
  *) fail "RUNPATH points outside the package: ${runpath}" ;;
esac

# 3. The data the earlier packages were missing.
#    Directories are not enough. `-d` is satisfied by an empty tree, so this
#    check passed on a package whose icons, locales, webroot and fonts were all
#    present and all empty -- which is the very regression it exists to catch.
#    Name files the application actually opens, and count the trees.
for want in \
  "share/fonts/neutrino.ttf" \
  "share/tuxbox/neutrino/httpd/index.html"
do
  [[ -s "${appdir}${DATA_PREFIX}/usr/${want}" ]] \
    || fail "missing or empty in the package: ${DATA_PREFIX}/usr/${want}"
done
# `fail` must not be called from inside a command substitution: its `exit` would
# only end the subshell and the check would carry on with an empty count.
count_files() { find "${appdir}${DATA_PREFIX}/usr/$1" -type f -name "$2" 2>/dev/null | wc -l; }
icon_count="$(count_files share/tuxbox/neutrino/icons '*.png')"
locale_count="$(count_files share/tuxbox/neutrino/locale '*.locale')"
webroot_count="$(count_files share/tuxbox/neutrino/httpd '*')"
seed_count="$(count_files var/tuxbox/config '*')"
[[ "${icon_count}"    -ge 100 ]] || fail "${DATA_PREFIX}/usr/share/tuxbox/neutrino/icons holds ${icon_count} icons, expected at least 100"
[[ "${locale_count}"  -ge 1   ]] || fail "${DATA_PREFIX}/usr/share/tuxbox/neutrino/locale holds no .locale file"
[[ "${webroot_count}" -ge 50  ]] || fail "${DATA_PREFIX}/usr/share/tuxbox/neutrino/httpd holds ${webroot_count} files, expected at least 50"
[[ "${seed_count}"    -ge 5   ]] || fail "${DATA_PREFIX}/usr/var/tuxbox/config holds ${seed_count} files, expected at least 5"
pass "data tree carries real files (${icon_count} icons, ${locale_count} locales, ${webroot_count} webroot, ${seed_count} config defaults)"

# 4. The graphics stack has to come from the machine the package runs on.
#    Bundling it is the classic way to make an AppImage fail on exactly the
#    systems it was supposed to support.
# A pattern, not four names: the build-time rule also forbids libGLESv*,
# libOpenGL, libglapi, libdrm* and libgbm, and a four-name list let injected
# libGLESv2 and libOpenGL through while claiming "no libGL family is bundled".
gl_family='^(libGL\.so|libGLX\.so|libGLdispatch\.so|libEGL\.so|libGLESv[0-9]*\.so|libOpenGL\.so|libglapi\.so|libdrm\.so|libdrm_|libgbm\.so)'
bundled_gl=""
while IFS= read -r lib; do
  name="$(basename "${lib}")"
  [[ "${name}" =~ ${gl_family} ]] || continue
  bundled_gl="${bundled_gl} ${name}"
done < <(find "${appdir}/usr/lib" -maxdepth 1 -name '*.so' -o -maxdepth 1 -name '*.so.*')
[[ -z "${bundled_gl}" ]] || fail "graphics-driver libraries are bundled:${bundled_gl}"
pass "no host graphics libraries bundled"
for required in libGLEW.so.2.2 libglut.so.3 libfreetype.so.6; do
  [[ -e "${appdir}/usr/lib/${required}" ]] || fail "${required} is missing from the package"
done
pass "the libraries the host does not provide are bundled"

# A library of the wrong architecture is invisible to a "not found" check: the
# loader skips it and quietly falls through to the host's copy, so the package
# looks fine and silently depends on the target having that library after all.
# One did ship this way (an x32 libmvec, from picking the first `ldconfig -p`
# line without looking at its ABI field).
# Class *and* machine. Comparing only the class lets an ELF64 AArch64 library
# through on an x86-64 package -- the historical x32 case was caught only
# because x32 happens to be ELF32.
#
# The readelf calls are guarded with `|| true`: without it a non-ELF file named
# *.so makes readelf exit non-zero, pipefail propagates it, and errexit kills
# this script with no message at all, skipping every check below -- the same
# pipefail trap the comment at the top of this file warns about.
elf_id() {
  local out
  out="$(readelf -h "$1" 2>/dev/null || true)"
  printf '%s' "${out}" | awk '/Class:/ {c=$2} /Machine:/ {sub(/^ *Machine: */,""); m=$0} END {print c"/"m}'
}
# A file readelf cannot parse is not automatically harmless. `*.so` is also worn
# by linker scripts and by ld.so.conf-style text files, which are fine to skip --
# but a truncated or corrupt shared object wears the ELF magic and would be
# skipped by the same `continue`, so the header is what decides.
is_elf() { [[ "$(head -c4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')" == "7f454c46" ]]; }
binary_id="$(elf_id "${binary}")"
wrong_arch=""
elf_count=0
while IFS= read -r lib; do
  [[ -f "${lib}" && ! -L "${lib}" ]] || continue
  lib_id="$(elf_id "${lib}")"
  if [[ "${lib_id}" == "/" ]]; then
    if is_elf "${lib}"; then
      wrong_arch="${wrong_arch} $(basename "${lib}"):unreadable-ELF-header"
    fi
    continue
  fi
  elf_count=$((elf_count + 1))
  [[ "${lib_id}" != "${binary_id}" ]] || continue
  wrong_arch="${wrong_arch} $(basename "${lib}"):${lib_id}"
done < <(find "${appdir}/usr/lib" -name '*.so' -o -name '*.so.*')
[[ -z "${wrong_arch}" ]] || fail "bundled libraries of the wrong architecture (expected ${binary_id}):${wrong_arch}"
[[ "${elf_count}" -gt 0 ]] || fail "no bundled shared object could be read at all, so the architecture check proved nothing"
pass "all ${elf_count} bundled shared objects are ${binary_id}, like the binary"

# glibc and the gcc runtime have to come from the target. Mixing pieces of them
# across the boundary fails on any machine whose glibc is older than the build
# host's, and the failure is a version-symbol error at start-up.
# A pattern, not a list of names. The previous version enumerated nine files and
# therefore said "no part of the C runtime is bundled" about a package that
# shipped libgomp -- the same hand-maintained-list failure this check exists to
# catch. libgomp and libatomic are deliberately not matched: they are leaves
# that talk to no driver and need not agree with the target's copy.
c_runtime='^(ld-linux|libc\.so|libm\.so|libmvec\.|libdl\.|librt\.|libpthread\.|libresolv\.|libnsl\.|libanl\.|libutil\.|libcrypt\.|libthread_db|libBrokenLocale|libnss_|libstdc\+\+|libgcc_s)'
bundled_runtime=""
while IFS= read -r lib; do
  name="$(basename "${lib}")"
  [[ "${name}" =~ ${c_runtime} ]] || continue
  bundled_runtime="${bundled_runtime} ${name}"
done < <(find "${appdir}/usr/lib" -maxdepth 1 -name '*.so' -o -maxdepth 1 -name '*.so.*')
[[ -z "${bundled_runtime}" ]] || fail "parts of the target's C runtime are bundled:${bundled_runtime}"
pass "no part of the target's C runtime is bundled"

# The oldest system the package can run on is decided by the build host, and a
# documented floor that nothing measures rots the moment the base image moves.
# The binary alone needs less than the package as a whole does: a bundled
# libsystemd raised the real floor a release above what the docs said.
GLIBC_FLOOR="${APPIMAGE_GLIBC_FLOOR:-2.39}"
max_glibc="$(
  { readelf -V "${binary}" 2>/dev/null || true
    while IFS= read -r lib; do readelf -V "${lib}" 2>/dev/null || true; done \
      < <(find "${appdir}/usr/lib" -name '*.so' -o -name '*.so.*')
  } | grep -oE 'GLIBC_2\.[0-9]+' | sort -t. -k2,2n -u | tail -n1
)"
if [[ -n "${max_glibc}" ]]; then
  want="GLIBC_${GLIBC_FLOOR}"
  newest="$(printf '%s\n%s\n' "${max_glibc}" "${want}" | sort -t. -k2,2n | tail -n1)"
  [[ "${newest}" == "${want}" ]] \
    || fail "the package needs ${max_glibc} but the documented floor is ${want}; update docs/PACKAGING.*.md or build on an older base"
  pass "needs at most ${max_glibc}, within the documented floor of ${want}"
fi

[[ -x "${appdir}/AppRun" ]] || fail "no AppRun"
grep -q 'NEUTRINO_DATA_PREFIX' "${appdir}/AppRun" || fail "AppRun is not the one that maps the data prefix"
pass "AppRun carries the data mapping"

# 5. GStreamer loads its elements with dlopen, so they appear in no dependency
#    walk, and the pipeline is only built when playback starts -- long after a
#    start-up smoke test has passed. Without these the application comes up
#    perfectly and then plays nothing.
if [[ "${APPIMAGE_BUNDLE_GSTREAMER:-1}" == "1" ]]; then
  gst_dir="${appdir}/usr/lib/gstreamer-1.0"
  [[ -d "${gst_dir}" ]] || fail "no GStreamer modules in the package; playback would not work"
  for element in libgstplayback.so libgstcoreelements.so libgsttypefindfunctions.so libgstlibav.so; do
    [[ -e "${gst_dir}/${element}" ]] || fail "GStreamer module missing from the package: ${element}"
  done
  for driver_plugin in libgstva.so libgstvaapi.so libgstvdpau.so libgstnvcodec.so; do
    if [[ -e "${gst_dir}/${driver_plugin}" ]]; then
      fail "${driver_plugin} drives the host GPU and must not be bundled"
    fi
  done
  pass "GStreamer modules bundled ($(find "${gst_dir}" -name '*.so' | wc -l)), GPU driver plugins excluded"
fi

if [[ "${RUN_CONTAINER}" != "1" ]]; then
  echo "[verify] Container start-up check skipped (APPIMAGE_VERIFY_CONTAINER=${RUN_CONTAINER})."
  echo "[verify] Static checks passed."
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  cat >&2 <<'MSG'
[verify] docker is not available, so the package cannot be started on a clean
[verify] system here. The static checks above passed, but they cannot tell you
[verify] whether it actually runs. Re-run where docker is available, or set
[verify] APPIMAGE_VERIFY_CONTAINER=0 to accept the static checks alone.
MSG
  exit 1
fi

# A probe that asks GStreamer, on the clean system, whether the bundled modules
# actually load and yield a playbin. Listing the files in the package cannot
# answer that: a module whose own dependency was left out is present and
# unloadable at the same time, which is how the missing libfreetype behaved.
# Built here rather than shipped -- it is a test tool, not part of the package.
probe_bin=""
if [[ "${APPIMAGE_BUNDLE_GSTREAMER:-1}" == "1" ]] \
   && command -v cc >/dev/null 2>&1 \
   && pkg-config --exists gstreamer-1.0 2>/dev/null; then
  cat >"${workdir}/gst_probe.c" <<'PROBE'
#include <gst/gst.h>
int main(void)
{
	GstElement *e;
	gst_init(NULL, NULL);
	e = gst_element_factory_make("playbin", "p");
	if (e == NULL) {
		g_print("NO_PLAYBIN\n");
		return 3;
	}
	g_print("PLAYBIN_OK\n");
	return 0;
}
PROBE
  if cc -o "${workdir}/gst_probe" "${workdir}/gst_probe.c" \
       $(pkg-config --cflags --libs gstreamer-1.0) >/dev/null 2>&1; then
    probe_bin="${workdir}/gst_probe"
  else
    fail "the GStreamer probe could not be built, so the module check cannot run"
  fi
elif [[ "${APPIMAGE_BUNDLE_GSTREAMER:-1}" == "1" ]]; then
  cat >&2 <<'MSG'
[verify] This host has no C compiler or no gstreamer-1.0 pkg-config file, so the
[verify] check that the bundled modules actually load cannot run -- and that is
[verify] the check the package most needs. Install them, or set
[verify] APPIMAGE_BUNDLE_GSTREAMER=0 if this package has no modules to check.
MSG
  exit 1
fi

# --privileged is needed for the mount namespace AppRun sets up. A container
# denies that to root as well, so this is not about trusting the image.
echo "[verify] Starting it on a stock ${VERIFY_IMAGE} with no build dependencies"
log="${workdir}/run.log"
probe_mount=()
[[ -n "${probe_bin}" ]] && probe_mount=(-v "${probe_bin}":/tmp/gst_probe:ro)
set +e
docker run --rm --privileged -v "${APPIMAGE}":/tmp/n.AppImage:ro \
  ${probe_mount[@]+"${probe_mount[@]}"} "${VERIFY_IMAGE}" bash -c '
  set -e
  cp /tmp/n.AppImage /root/n.AppImage && chmod +x /root/n.AppImage
  cd /root
  export APPIMAGE_EXTRACT_AND_RUN=1
  ./n.AppImage --appimage-extract >/dev/null 2>&1
  AD=/root/squashfs-root

  # Before anything is installed. What an untouched system cannot resolve IS the
  # package host requirement, and the documentation makes a promise about it.
  # Asking after apt-get would be asking a question whose answer has just been
  # repaired -- which is exactly how "starts on a stock system" came to be
  # asserted by a check that installed the missing library first.
  { LD_LIBRARY_PATH="$AD/usr/lib" ldd "$AD/usr/bin/neutrino" 2>/dev/null || true
    for l in "$AD"/usr/lib/*.so "$AD"/usr/lib/*.so.*; do
      [ -f "$l" ] || continue
      LD_LIBRARY_PATH="$AD/usr/lib" ldd "$l" 2>/dev/null || true
    done
  } | awk "/not found/ {print \"STOCK_MISSING: \" \$1}" | sort -u

  apt-get update -qq >/dev/null 2>&1
  apt-get install -y -qq --no-install-recommends libgl1 libglx0 libglvnd0 xvfb binutils curl >/dev/null 2>&1
  Xvfb :99 -screen 0 1280x720x24 >/dev/null 2>&1 &
  sleep 2
  export DISPLAY=:99

  # Run it in the background and ask its web server for a file that exists only
  # in the mapped data tree. Serving that file back, byte for byte, is a
  # positive proof about a second data directory -- one that the font check says
  # nothing about, and that no log line reports on its own.
  WEBFILE="$AD/opt/neutrino/usr/share/tuxbox/neutrino/httpd/index.html"
  echo "NEUTRINO_WEB_WANT=$(wc -c < "$WEBFILE" 2>/dev/null || echo 0)"
  # Neutrino signals its follow-up action through the exit status and the
  # timeout reports 124, so a non-zero status here says nothing about success.
  # Without the guard, set -e would end the script before the checks below.
  timeout -k 3 60 ./n.AppImage >/root/neutrino.log 2>&1 &
  npid=$!
  webbytes=0
  i=0
  while [ "$i" -lt 45 ]; do
    if curl -fsS -m 3 -o /root/web.out http://127.0.0.1/index.html 2>/dev/null; then
      webbytes=$(wc -c < /root/web.out)
      break
    fi
    i=$((i + 1))
    sleep 1
  done
  echo "NEUTRINO_WEB_BYTES=$webbytes"
  wait "$npid" || true
  cat /root/neutrino.log
  echo "NEUTRINO_STATE_FILES=$(find /root/.local/share/neutrino-appimage -type f 2>/dev/null | wc -l)"
  [ -d /root/.local/share/neutrino-appimage/tuxbox/config ] && echo "NEUTRINO_STATE_SEEDED=yes"

  # Neutrino initialises GStreamer lazily, on the first playback, so a start-up
  # run never touches it. Ask the bundled modules directly instead.
  if [ -x /tmp/gst_probe ]; then
    # A module that is present but cannot be loaded is the failure this whole
    # check exists for: it looks fine in a file listing and silently costs every
    # element it provides. Only the graphics and display stack may be unresolved
    # here -- those come from the machine, and a headless container has none.
    # The filter matches the missing library, not the whole line: matching the
    # line would exempt a module wholesale whenever its own name happened to
    # contain one of these tokens. Display-stack libraries are expected to be
    # absent here -- a headless container has no EGL and no Wayland -- but which
    # modules that costs is printed rather than hidden.
    all_missing=$(for m in "$AD"/usr/lib/gstreamer-1.0/*.so; do
        LD_LIBRARY_PATH="$AD/usr/lib" ldd "$m" 2>/dev/null |
          awk -v mod="$(basename "$m")" "/not found/ {print mod\" \"\$1}"
      done | sort -u)
    printf "%s\n" "$all_missing" | awk "NF" | awk "{print \"GSTPROBE: needs-host \" \$0}"
    unresolved=$(printf "%s\n" "$all_missing" | awk "NF" |
      awk "{print \$2}" | grep -vE "^lib(GL|GLX|GLdispatch|EGL|GLESv|OpenGL|wayland|X11|xcb)" || true)
    if [ -n "$unresolved" ]; then
      echo "GSTPROBE: UNRESOLVED"
      # Double quotes on purpose. This whole script reaches docker inside a
      # single-quoted argument, so a single quote in here closes it early: bash
      # concatenates the pieces, drops the quotes and reduces the now unquoted
      # backslash-n to a plain n. The list came out with its last entry mangled
      # and no trailing newline -- in the one path where somebody needs to read
      # it. No single quotes anywhere in this block, for that reason.
      printf "%s\n" "$unresolved" | sed "s/^/GSTPROBE: /" | head -20
    else
      echo "GSTPROBE: ALL_MODULES_RESOLVE"
    fi
    LD_LIBRARY_PATH="$AD/usr/lib" \
    GST_PLUGIN_SYSTEM_PATH="$AD/usr/lib/gstreamer-1.0" \
    GST_PLUGIN_PATH="$AD/usr/lib/gstreamer-1.0" \
    GST_PLUGIN_SCANNER="$AD/usr/libexec/gstreamer-1.0/gst-plugin-scanner" \
    GST_REGISTRY=/tmp/gst-registry.bin \
      /tmp/gst_probe 2>&1 | sed "s/^/GSTPROBE: /"
  fi
' >"${log}" 2>&1
set -e

fail_with_log() { tail -n 25 "${log}" >&2; fail "$@"; }

# What the untouched image could not resolve. This is the package's documented
# host requirement, and it is only allowed to contain the graphics and display
# stack -- the libraries deliberately left out of the package because they have
# to match the machine's driver. Anything else here is a library that was meant
# to be bundled and is not, which on the developer's machine is invisible.
host_provided='^lib(GL|GLX|GLdispatch|GLESv[0-9]*|EGL|OpenGL|glapi|drm|gbm|wayland-[a-z]+|X11|X11-xcb|xcb|xcb-[a-z0-9-]+|Xext|Xrender|Xfixes|Xdamage|Xxf86vm|xshmfence)[-.]'
stock_missing="$(awk '/^STOCK_MISSING: / {print $2}' "${log}" | sort -u)"
unexpected_missing=""
while IFS= read -r missing; do
  [[ -n "${missing}" ]] || continue
  [[ "${missing}" =~ ${host_provided} ]] || unexpected_missing="${unexpected_missing} ${missing}"
done <<<"${stock_missing}"
if [[ -n "${unexpected_missing}" ]]; then
  fail_with_log "on an untouched ${VERIFY_IMAGE} the package cannot resolve libraries that are not part of the documented host requirement:${unexpected_missing}"
fi
pass "on an untouched ${VERIFY_IMAGE} only the host graphics stack is missing ($(printf '%s' "${stock_missing}" | wc -w) libraries, as documented)"

if grep -qi 'error while loading shared librar' "${log}"; then
  grep -i 'error while loading shared librar' "${log}" >&2
  fail "the package is missing a shared library the documented host requirement does not cover"
fi
if grep -q 'AppRun: cannot map' "${log}"; then
  fail_with_log "AppRun could not establish the data mapping"
fi

# Proof that the mapping took effect has to be positive, and it has to come from
# a line printed *after* the file was read. "font file: <path>" is not that line:
# neutrinofonts.cpp prints it from a compile-time constant and only then calls
# access(), so it appears whenever the binary was configured for this prefix --
# which check 1 already established -- and a package with an empty fonts
# directory passed the whole gate green while dying at start-up.
# "standard font family: <name>" is printed after FT_New_Face parsed the file;
# AddFont returns NULL on failure and getFamily then yields an empty string, so a
# non-empty family name cannot be produced without opening the bundled TTF
# through the read-only half of the mapping.
if grep -q ' neutrino exit' "${log}"; then
  fail_with_log "Neutrino aborted during start-up on ${VERIFY_IMAGE}"
fi
if ! grep -qE 'standard font family: [^[:space:]]' "${log}"; then
  fail_with_log "the bundled font was not parsed from ${DATA_PREFIX}; the data mapping did not take effect"
fi
# A second data class, from a different directory, so the proof does not rest on
# the fonts alone. It has to be positive for the same reason: "cannot read
# locale" looks like the obvious marker and is worthless -- Neutrino starts with
# no language configured, tries to load "", fails, and falls back to english,
# which returns without touching the filesystem at all. That message is printed
# by every healthy first start.
# What the web server hands back cannot be produced without reading the file.
web_want="$(awk -F= '/^NEUTRINO_WEB_WANT=/ {print $2}' "${log}" | sed -n 1p)"
web_bytes="$(awk -F= '/^NEUTRINO_WEB_BYTES=/ {print $2}' "${log}" | sed -n 1p)"
[[ "${web_want:-0}" -gt 0 ]] \
  || fail_with_log "the packaged webroot has no index.html to serve, so the web interface cannot be proven"
[[ "${web_bytes:-0}" == "${web_want}" ]] \
  || fail_with_log "the web interface returned ${web_bytes:-0} bytes for index.html, expected ${web_want} from ${DATA_PREFIX}"
pass "starts on ${VERIFY_IMAGE} with only the documented host requirement, parses its bundled font and serves its webroot (${web_bytes} bytes)"

# Counting files would be satisfied by the .seeded marker AppRun always writes,
# so this looks for something the shipped defaults actually contain.
state_files="$(awk -F= '/^NEUTRINO_STATE_FILES=/ {print $2}' "${log}")"
grep -q '^NEUTRINO_STATE_SEEDED=yes' "${log}" \
  || fail_with_log "the per-user configuration was not seeded from the shipped defaults"
pass "per-user configuration seeded from the shipped defaults (${state_files:-0} files)"

# GStreamer writes its registry once it has scanned the bundled modules, so the
# file appearing is proof that the plugin path took effect on a machine with no
# GStreamer of its own -- which listing the files in the package alone is not.
if [[ -n "${probe_bin}" ]]; then
  if ! grep -q 'GSTPROBE: PLAYBIN_OK' "${log}"; then
    grep 'GSTPROBE:' "${log}" >&2 || true
    fail_with_log "playbin cannot be created from the bundled modules; playback would fail"
  fi
  if ! grep -q 'GSTPROBE: ALL_MODULES_RESOLVE' "${log}"; then
    grep 'GSTPROBE:' "${log}" >&2 || true
    fail "bundled GStreamer modules cannot be loaded on the clean system"
  fi
  pass "every bundled GStreamer module resolves, and playbin can be created"
fi

echo "[verify] All checks passed."
